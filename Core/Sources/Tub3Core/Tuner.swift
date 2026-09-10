import Foundation
import Observation

/// What the screen should currently be showing.
public enum TunerState: Equatable, Sendable {
    case idle
    case tuning(channel: Int, station: String)
    case playing(channel: Int, station: String, title: String, contentType: String)
    case guideChannel(channel: Int, station: String)
    /// A caption rather than a picture: off air, or a file Plex cannot identify.
    case slate(channel: Int, station: String, message: String)
    /// Reached the box, and it is not finished being set up.
    ///
    /// Deliberately not `.broken`: nothing is wrong, and "no signal" is a lie that sends
    /// someone looking at their network when the answer is a form on the box's own web page.
    /// This is the likeliest state a brand new box is ever in, because Plex is configured
    /// after the box first boots and not before.
    case standby(headline: String, detail: String, address: String)
    case broken(String)
}

/// The dial.
///
/// The box decides what is on; this decides nothing about programming at all. It asks, plays
/// what it is told, and asks again when the item's slot is up. Keeping that boundary sharp is
/// what makes the app a *front end* rather than a second, disagreeing scheduler.
@MainActor
@Observable
public final class Tuner {
    public private(set) var state: TunerState = .idle
    public private(set) var channels: [Channel] = []
    public private(set) var current: Int?
    /// Shown briefly on tune-in, like a channel bug on real television.
    public private(set) var bugVisible = true
    /// Listings for the guide channel, fetched when it is tuned rather than on launch —
    /// most viewings never open it.
    public private(set) var guide: Guide?
    /// What is on, for the channel bug's bottom-right block. The box reads the same
    /// thing out of the airing it just opened; the state enum deliberately does not
    /// carry it, because "how much is left" changes every second and the state should
    /// not churn for something only the ident reads.
    public private(set) var nowEntry: NowEntry?
    /// The programme the bug should name, which mid-break is not the entry being played.
    /// Nil against an older box, or once a local step has made the last answer stale.
    public private(set) var feature: Feature?

    /// What is on, as a viewer would name it.
    ///
    /// The break case is the whole reason this exists: `nowEntry` is then the advert, and
    /// every caption in the app — the bug, the menu's now-line — is supposed to keep saying
    /// the programme the ads are interrupting. The box answers this; falling back to the
    /// entry only covers a box too old to have been asked.
    public var featureTitle: String { Feature.caption(feature, playing: nowEntry) }

    /// How much of the programme is left, breaks included — so it does not jump upward
    /// when the ads end. Falls back to the entry's own remainder.
    public var featureRemaining: Double { Feature.remaining(feature, playing: nowEntry) }

    /// When this visit to the guide began.
    ///
    /// The crawl is measured from here, the way the box measures it from `Guide._started` —
    /// a fresh object built by `_tune_guide` on every tune. Not from the payload's `begin`,
    /// which is the top of the current half hour: arriving at 7:17 would then apply seventeen
    /// minutes of scroll before drawing anything, opening the listing at a different place
    /// every time. Set on arrival only, so a refetch does not jerk the crawl.
    public private(set) var guideStartedAt = Date()
    /// How often the listings are refetched while the guide is on screen. The box rebuilds
    /// its rows on `GUIDE_ROWS_TTL = 20.0` and recomputes the window every frame, so its
    /// columns roll over at the half hour and finished programmes fall off. Fetching once per
    /// tune, as this did, left the grid frozen at the moment you arrived.
    static let guideRefresh: UInt64 = 20_000_000_000
    private var guidePoll: Task<Void, Never>?
    /// How often the dial is re-read. `Box.RESCAN` is a minute, for the same reason:
    /// a channel added while the set is on should appear without restarting anything.
    static let dialRefresh: UInt64 = 60_000_000_000
    private var dialPoll: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?

    private let box: BoxClient
    private var plex: PlexClient?
    private var plexBase: URL?
    private var resolver: StreamResolver?
    private let engine: PlayerEngine
    private let clientID: String

    /// Rises on every tune. An answer that arrives for a channel we have since left is
    /// dropped rather than played — otherwise flipping quickly through the dial lands you on
    /// channel 9 watching whatever channel 6 was about to show.
    private var tuneGeneration = 0
    /// Set when a direct fetch has failed on this channel, so the next attempt asks Plex to
    /// stream the same programme instead of re-requesting the URL the server just refused.
    /// The television cannot get stuck on one file; neither should this.
    private var avoidDirect = false
    /// Whether the item now on screen was fetched as a file rather than streamed.
    private var playingDirect = false
    /// The last answer the box gave, kept for its `next`. A file that will not open is
    /// indistinguishable from one that ended, and the answer to both is the next thing
    /// in the plan.
    private var lastNow: NowPlaying?
    /// Consecutive failures on the current channel, reset whenever a picture arrives.
    private var failures = 0

    public var player: PlayerEngine { engine }

    /// Channel 2's own soundtrack, kept out of the scheduled-playback path entirely.
    private let music = GuideMusic()
    /// Fetched once *successfully* and kept: the playlist changes with the season,
    /// not with the minute.
    private var musicTracks: [URL]?

    public init(box: BoxClient, engine: PlayerEngine, clientID: String) {
        self.box = box
        self.engine = engine
        self.clientID = clientID
        Self.forgetChannelIfAsked()
        engine.onBoundary = { [weak self] in
            Task { await self?.advance() }
        }
        // A channel that cannot show a picture says so and tries again. The television it is
        // imitating cannot get stuck — it opens the next file off a disk — so the app has to
        // work at being equally hard to kill.
        engine.onFailure = { [weak self] why in
            Task { await self?.recover(from: why) }
        }
    }

    public func start() async { await start(retrying: true) }

    private func start(retrying: Bool) async {
        // Which tune, if any, was in force before the box was asked anything.
        //
        // Every line below this is on the far side of two network round trips, and the
        // backoff ladder means one of these can be in flight all evening. Press a channel
        // button inside that window and the ladder used to come back and tune to the
        // *opening* channel over the top of it — `stillWaiting` was checked before the
        // await and not after, so nothing noticed. On the shelf that is a set that jumps
        // back to last night's channel a beat after you changed it; in the suite it is the
        // signature every flaky test shared, and it is why they all failed parked on the
        // last-watched channel rather than on the one that was pressed.
        let entryGeneration = tuneGeneration
        do {
            channels = try await box.channels()
            guard let base = try await box.plexBase() else {
                state = .standby(headline: "Almost there",
                                 detail: "This box has no Plex server yet.",
                                 address: box.base.absoluteString)
                Diag.log("plex is not configured on the box")
                // And ask again, because someone is very likely filling that form in right
                // now on a laptop, and walking back to the television to find it still
                // saying the same thing is how a person concludes it did not work.
                if retrying { await retryStart(after: 10) }
                return
            }
            plexBase = base
            let client = PlexClient(base: base, clientID: clientID)
            plex = client
            resolver = StreamResolver(plex: client, clientID: clientID)
            engine.attach(plex: client)
            // The ambiance channel, as `tub3/app.py` does and for its reason: it is the one
            // channel with no schedule, no catalogue and nothing to go wrong, so it is what a
            // set should open on. Falls through to the lowest scheduled station when there is
            // no ambiance channel, which is the box's fallback too — and never the guide,
            // because a television switched on does not open its menu.
            // A channel named on the command line, so a fault on one channel can be
            // reproduced without someone standing at the television pressing buttons.
            // `integer(forKey:)`, not `object(forKey:) as? Int`: the argument domain stores a
            // command-line value as a string, so the cast always failed and the flag silently
            // did nothing — which cost a whole diagnostic run to notice.
            let defaults = UserDefaults.standard
            let forced = defaults.object(forKey: "tub3Channel") != nil
                ? defaults.integer(forKey: "tub3Channel") : nil
            // Start-on, from the menu. Validated against the dial that was just fetched: a
            // stored channel the box no longer carries — a station dropped by a rebuild, or
            // a preference set against a different box — falls through to the default rather
            // than opening on a channel that will never answer.
            let stored: Int? = {
                let key = defaults.object(forKey: Self.startOnKey) != nil
                    ? defaults.integer(forKey: Self.startOnKey) : nil
                let wanted = key ?? (defaults.object(forKey: Self.lastWatchedKey) != nil
                                     ? defaults.integer(forKey: Self.lastWatchedKey) : nil)
                guard let wanted, channels.contains(where: { $0.channel == wanted }) else {
                    return nil
                }
                return wanted
            }()
            let first = forced ?? stored ?? (channels.first { $0.isAmbiance }
                                             ?? channels.first { !$0.isGuide }
                                             ?? channels.first)?.channel
            // Somebody chose a channel while the box was being asked. Theirs wins: the
            // opening channel is for a set that has just been switched on, not for a viewer
            // who has just pressed something.
            if let first, tuneGeneration == entryGeneration { await tune(to: first) }
            keepDialFresh()
        } catch {
            Diag.log("box unreachable: \(error.localizedDescription)")
            state = .broken("no signal")
            guard retrying else { return }
            // A box that is still booting is the ordinary case, not the exceptional one: the
            // television and the Pi come on at the same moment when both are on the same
            // power strip, and the app always won that race. Nothing retried out of here, so
            // the first thing anyone saw was a fault card that stayed up all evening.
            await retryStart(after: 5)
        }
    }

    /// Backs off 5s → 10s → 20s → 40s → 60s and then stays at a minute, forever.
    ///
    /// Forever is the point. This is an appliance on a shelf and there is no one to press a
    /// button: it has to be still trying whenever the box comes back, an hour later or in the
    /// morning. `startGeneration` makes a later `start()` — someone choosing a different box —
    /// abandon an older ladder rather than have two of them tuning over each other.
    private var startGeneration = 0
    private func retryStart(after seconds: Double) async {
        startGeneration += 1
        let generation = startGeneration
        // Inherits the main actor, so `startGeneration` and `state` below are read on the
        // same actor that writes them and no lock is involved.
        Task { [weak self] in
            var wait = seconds
            while true {
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                guard let self, self.startGeneration == generation else { return }
                guard self.stillWaiting else { return }   // recovered by some other route
                // `retrying: false`, so this attempt does not arm a second ladder beneath
                // the one already running.
                await self.start(retrying: false)
                guard self.startGeneration == generation, self.stillWaiting else { return }
                wait = min(wait * 2, 60)
            }
        }
    }

    private var stillWaiting: Bool {
        switch state {
        case .broken, .standby, .idle: true
        default: false
        }
    }

    /// How long the dial waits for the thumb to stop before it opens anything.
    ///
    /// The box's own number. Eight presses up the dial should open one file, not eight: the
    /// number on screen keeps up with the button while the tuner obviously cannot, and the
    /// whole trick of a dial that feels fast is that the display never admits it. Without
    /// this, surfing opened — and abandoned — a Plex session per channel passed through.
    static let settle: Duration = .milliseconds(220)

    /// A press. Announces the channel immediately and opens it once the pressing stops.
    public func tune(to channel: Int) async {
        // Already showing this one. Reopening it would drop the Plex session and rejoin the
        // programme a few seconds later behind a tuning card — the glitch `box._reannounce`
        // exists to avoid. Say which channel it is instead. Keyed on a picture actually being
        // up rather than on `current`, because a slate is mid-retry and re-picking it there
        // means "try again", which is what the box arranges by clearing `_on_air`.
        if case .playing(let showing, _, _, _) = state, showing == channel {
            showBug()
            return
        }
        if case .guideChannel(let showing, _) = state, showing == channel { return }
        tuneGeneration += 1
        let generation = tuneGeneration
        failures = 0
        avoidDirect = false
        current = channel
        let station = channels.first { $0.channel == channel }?.station ?? ""
        state = .tuning(channel: channel, station: station)
        Diag.log("tune ch\(channel) \(station) gen=\(generation)")
        // The outgoing channel's number must not linger over the incoming one; the
        // ident is re-shown when a picture actually arrives, not when a button moves.
        bugVisible = false
        if channels.first(where: { $0.channel == channel })?.isGuide != true {
            music.stop()
            guidePoll?.cancel()
            guidePoll = nil
        }
        engine.standDown()

        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: Tuner.settle)
            guard let self, !Task.isCancelled, generation == self.tuneGeneration else { return }
            // Only now is this a channel change rather than a thumb in motion. Hand back the
            // transcoder we are leaving before asking for another: Plex does not reap
            // abandoned sessions, so surfing without this buries the server.
            await self.engine.stopCurrentSession()
            guard generation == self.tuneGeneration else { return }
            await self.load(channel: channel, generation: generation, announce: true)
        }
    }

    /// Wait for any settle in flight. Tests need it; nothing in the app does.
    public func settled() async {
        await settleTask?.value
    }

    public func channelUp() async {
        guard let index = tunedIndex() else { return await lost() }
        await tune(to: channels[(index + 1) % channels.count].channel)
    }

    public func channelDown() async {
        guard let index = tunedIndex() else { return await lost() }
        await tune(to: channels[(index - 1 + channels.count) % channels.count].channel)
    }

    /// No place in the dial. Two causes, opposite answers.
    ///
    /// An empty dial means the box has not been heard from and the thing to do is ask again.
    /// A `current` the dial no longer carries — a station dropped by a rebuild, or a Start-on
    /// preference the box has outlived — means the dial is fine and only our place in it is
    /// wrong, so the answer is to land somewhere real.
    ///
    /// Without the distinction, up and down are dead buttons on the one screen where every
    /// button gets pressed; and asking again in both cases would re-request a channel that
    /// will never answer, once per press, for as long as somebody keeps pressing.
    private func lost() async {
        if let first = channels.first {
            await tune(to: first.channel)
        } else {
            await retryNow()
        }
    }

    /// Ask the box again, now, without yanking anybody off what they are watching.
    ///
    /// Deliberately not `start()`: that ends by tuning to the opening channel, so a viewer on
    /// channel 6 who pressed "try again" would find themselves back on ambiance.
    public func retryNow() async {
        if stillWaiting {
            startGeneration += 1
            await start(retrying: true)
        } else if let current {
            await load(channel: current, generation: tuneGeneration)
        }
    }

    /// Let go of the Plex session, without forgetting what is tuned.
    ///
    /// For leaving the app. Plex does not reap a session whose client simply vanished —
    /// `PlexClient` says so in its own comment — so an app that is killed while playing
    /// leaves a transcoder running on the server until something else clears it. On a
    /// television that is invisible; it shows up as the next thing to ask for a stream
    /// waiting behind work nobody is watching.
    public func release() async {
        await engine.stopCurrentSession()
    }

    /// What the box thinks of itself. The menu asks once per opening.
    public func boxHealth() async throws -> BoxHealth { try await box.health() }

    /// Where this app is pointed, for the menu to show. `base` is an immutable `let` on the
    /// actor, so no await.
    public var address: String { box.base.absoluteString }

    private func tunedIndex() -> Int? {
        guard let current else { return channels.isEmpty ? nil : 0 }
        return channels.firstIndex { $0.channel == current }
    }

    /// The item's slot is up. Ask what is on now rather than assuming it is `next`: the
    /// answer already accounts for however long the transition actually took.
    private func advance() async {
        // The watchdog only knows the playhead has stopped; it cannot tell "this item
        // ended" from "this stream died". Leaving it armed across a boundary let the
        // outgoing item's clock count against the incoming one, and the box has no
        // stall detection at all — it would simply have kept playing.
        engine.standDown()
        guard let channel = current else { return }
        // During a tune the in-flight `load` already owns the next item, and on a slate the
        // pending `retry` does. The box refuses this outright for the same reason.
        guard case .playing = state else { return }
        tuneGeneration += 1
        await load(channel: channel, generation: tuneGeneration)
    }

    private func load(channel: Int, generation: Int, announce: Bool = false) async {
        do {
            let state = try await box.now(channel: channel)
            guard generation == tuneGeneration else { return }
            await present(state, generation: generation, announce: announce)
        } catch {
            guard generation == tuneGeneration else { return }
            Diag.log("box unreachable: \(error.localizedDescription)")
            self.state = .broken("no signal")
            // And ask again. A box that is rebooting, or a network that dropped for a moment,
            // used to end the app's evening: nothing retried out of this state.
            await retry(channel: channel, after: 10, generation: generation)
        }
    }

    /// - Parameter announce: whether a picture arriving means "you changed channel".
    ///   False when the schedule simply stepped to the next programme, which is the
    ///   box's own distinction and what stops the ident popping up at every ad break.
    private func present(_ now: NowPlaying, generation: Int,
                         announce: Bool = false) async {
        lastNow = now
        // The guide is a channel exactly as it is on the box: tuning to it shows listings,
        // not a picture, and there is nothing to resolve.
        if now.isGuide {
            // No video plays on the guide, so the previous channel has to actually stop —
            // otherwise its audio carries on underneath the listings.
            await engine.stop()
            if case .guideChannel = state {} else { guideStartedAt = Date() }
            state = .guideChannel(channel: now.channel, station: now.station)
            await startGuideMusic(generation: generation)
            await loadGuide(generation: generation)
            keepGuideFresh(generation: generation)
            return
        }
        music.stop()
        guard let entry = now.now, !now.isOffAir else {
            nowEntry = nil
            feature = nil
            // The box never puts machine text on the picture. Whatever it said goes to the
            // trace; the viewer gets the same card a set shows for a channel with nothing on.
            if let why = now.error { Diag.log("ch\(now.channel) box says: \(why)") }
            state = .slate(channel: now.channel, station: now.station, message: "off air")
            // Come back when the block does. A plan that runs a second or two short of its
            // own end is not a sign-off — the box's blocks are contiguous, so the next one
            // starts at `block_ends_at` and a set-top box shows that gap as a flicker rather
            // than a card. A real sign-off carries no block at all and keeps the fifteen.
            var wait = 15.0
            if !now.isOffAir, let ends = now.blockEndsAt {
                wait = min(15.0, max(1.0, ends - now.serverTime + 0.5))
            }
            await retry(channel: now.channel, after: wait, generation: generation)
            return
        }
        guard entry.plex != nil else {
            // 0.7% of the dial. The box plays these perfectly from disk; only Plex cannot
            // name them, so an app has nothing to ask for.
            let building = now.map == nil || now.map?.stale == true
            state = .slate(channel: now.channel, station: now.station,
                           message: building ? "tuning in…" : "not available here")
            await retry(channel: now.channel, after: building ? 10 : 5, generation: generation)
            return
        }
        guard let resolver, let base = plexBase else {
            // Reachable whenever the box answers before Plex has been configured on it, and
            // a bare `return` left the screen saying "tuning…" for ever with nothing
            // retrying. Say what is actually wrong, and keep asking — somebody is very
            // likely filling that form in on a laptop right now.
            state = .standby(headline: "Almost there",
                             detail: "This box has no Plex server yet.",
                             address: box.base.absoluteString)
            Diag.log("no plex while tuning ch\(now.channel)")
            await retryStart(after: 10)
            return
        }
        do {
            let item = try await resolver.resolve(entry, base: base,
                                                  forceTranscode: avoidDirect)
            guard generation == tuneGeneration else {
                // Left this channel while Plex was thinking. Give the transcoder back.
                if let session = item.session { await plex?.stop(session: session) }
                return
            }
            Diag.log("play url=\(item.url.absoluteString) joinAt=\(item.joinAt) playFor=\(item.playFor) session=\(item.session ?? "direct")")
            // The bug's name, not the file's: mid-break these differ, and the caption is
            // the half a viewer sees.
            let caption = Feature.caption(now.feature, playing: entry)
            if now.feature?.inBreak == true {
                // The one divergence worth a line in the trace: what is on the screen and
                // what the bug says are deliberately different here, and a photo of the
                // television cannot show which of the two went wrong.
                Diag.log("ch\(now.channel) in break, playing \(entry.displayTitle) — bug says \(caption)")
            }
            state = .playing(channel: now.channel, station: now.station,
                             title: caption, contentType: entry.contentType)
            // On a picture arriving, not on a button moving. Surfing through eight channels
            // should not make the eighth the one it opens on tomorrow.
            UserDefaults.standard.set(now.channel, forKey: Self.lastWatchedKey)
            playingDirect = item.session == nil
            nowEntry = entry
            feature = now.feature
            if await engine.play(item) {
                failures = 0
                // `engine.play` returns true only after the item became ready, which is
                // this app's `playback-restart`. On a slow tune the old code had already
                // spent the ident's four seconds before there was anything to identify.
                if announce { showBug() }
            }
        } catch {
            state = .slate(channel: now.channel, station: now.station,
                           message: "cannot play this")
            await retry(channel: now.channel, after: 8, generation: generation)
        }
    }

    /// Something went wrong with the picture. Say what, then go back to the box and ask
    /// again — which is also how a real set-top box behaves when a stream drops.
    /// Step to the next thing in the plan, the way `_advance_if_ended` does.
    ///
    /// A file that will not open and a file that has finished look identical from here, and
    /// the answer to both is the same: play what comes next. Asking again for the entry that
    /// just failed holds a caption on screen for the rest of its slot while the television
    /// beside it has already moved on to the break.
    ///
    /// Deliberately called after `avoidDirect` has been set, so the forward step already
    /// prefers a transcode — the app's direct-to-stream fallback survives, and this adds only
    /// the box's forward motion on top of it.
    private func playNextEntry(channel: Int, station: String, generation: Int) async -> Bool {
        guard let next = lastNow?.next, next.plex != nil,
              let resolver, let base = plexBase else { return false }
        // Consumed, not merely read. If the next entry fails too, the payload it came from is
        // stale and stepping again would offer the same broken file for ever with no backoff
        // behind it. Dropping it here sends the second failure down the retry path, which
        // asks the box what is on rather than guessing.
        lastNow = nil
        guard let item = try? await resolver.resolve(next, base: base,
                                                     forceTranscode: avoidDirect),
              generation == tuneGeneration else { return false }
        Diag.log("stepping past a file that will not open, to \(next.displayTitle)")
        // Stepping out of the *programme* loses it; stepping between two adverts does not.
        // The box's answer named the programme the break is interrupting, and a broken advert
        // in the middle of it does not change what the viewer sat down to watch — so carry it,
        // minus whatever was left of the entry just abandoned. Outside a break the programme
        // itself is what would not open, and nothing here knows what follows it.
        let carried = feature?.inBreak == true
            ? feature?.skipping(nowEntry?.remainingSeconds ?? 0) : nil
        state = .playing(channel: channel, station: station,
                         title: Feature.caption(carried, playing: next),
                         contentType: next.contentType)
        nowEntry = next
        feature = carried
        playingDirect = item.session == nil
        return await engine.play(item)
    }

    private func recover(from why: String) async {
        guard let channel = current else { return }
        // Only a channel that believes it is showing a picture can fail to show one. A late
        // report about somewhere we have already left is not this channel's problem.
        guard case .playing = state else {
            Diag.log("ignored stale failure: \(why)")
            return
        }
        Diag.log("recover ch\(channel): \(why)")
        // A failure on a direct fetch is a verdict on the route, not on the programme: the
        // same thing is still there and Plex will stream it. Falling back beats asking again
        // for a URL the server has already refused, which is how channel 13 stayed dead.
        if playingDirect { avoidDirect = true }
        let station = channels.first { $0.channel == channel }?.station ?? ""
        failures += 1
        // The reason is already in the trace one line above. On screen it is a house
        // line, because the box refuses to put maintenance text on the picture at all
        // — a viewer cannot act on "the stream did not start", and a television that
        // explains its own internals to the room is not the illusion being built.
        state = .slate(channel: channel, station: station, message: "one moment…")
        await engine.stopCurrentSession()
        tuneGeneration += 1
        if await playNextEntry(channel: channel, station: station,
                               generation: tuneGeneration) {
            failures = 0
            return
        }

        // Back off a little if it keeps happening, so a channel whose content is genuinely
        // broken does not sit in a tight retry loop hammering Plex.
        let wait = min(2.0 * Double(failures), 15.0)
        tuneGeneration += 1
        let generation = tuneGeneration
        try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        guard generation == tuneGeneration else { return }
        await load(channel: channel, generation: generation)
    }

    private func startGuideMusic(generation: Int) async {
        // Only a successful answer is remembered. `?? []` cached the *failure* too, so
        // one dropped request left channel 2 silent for the life of the app. The box
        // cannot do that: its playlist is a local folder scan, not a fetch. Retrying on
        // the next tune to the guide is the right cadence — press 2 again and it is
        // back — and a periodic refetch would diverge in the other direction, since the
        // box only re-reads the folder when it restarts.
        if musicTracks == nil, let fetched = try? await box.guideMusic() {
            musicTracks = fetched
        }
        guard generation == tuneGeneration, let tracks = musicTracks, !tracks.isEmpty else {
            return
        }
        await music.start(tracks)
    }

    /// Keep asking the box what is on, for as long as the guide is the channel.
    ///
    /// `/api/guide` recomputes `begin` from the current half hour on every request, so this
    /// alone rolls the columns, the slot geometry and the now-line over — no arithmetic in
    /// the view has to know about the passage of time.
    /// Re-read the dial, the way the box does every minute.
    ///
    /// Additive, and that is not a nicety. A rebuild truncates and rewrites each station's
    /// config in place, and the box's own reader skips a file caught mid-write — so a
    /// wholesale replace would briefly delete channels out from under someone watching one.
    /// The box merges for exactly this reason; so does this.
    ///
    /// Touches neither `current` nor the engine: this changes the dial, not what is playing.
    private func keepDialFresh() {
        dialPoll?.cancel()
        dialPoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Tuner.dialRefresh)
                guard let self, let fresh = try? await self.box.channels() else { continue }
                let known = Set(self.channels.map(\.channel))
                let added = fresh.filter { !known.contains($0.channel) }
                guard !added.isEmpty else { continue }
                Diag.log("dial: \(added.count) new channel(s)")
                self.channels = (self.channels + added).sorted { $0.channel < $1.channel }
            }
        }
    }

    private func keepGuideFresh(generation: Int) {
        guidePoll?.cancel()
        guidePoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Tuner.guideRefresh)
                guard let self, generation == self.tuneGeneration else { return }
                await self.loadGuide(generation: generation)
            }
        }
    }

    private func loadGuide(generation: Int) async {
        guard let listings = try? await box.guide(), generation == tuneGeneration else { return }
        Diag.log("guide refreshed: begin=\(Int(listings.begin)) rows=\(listings.rows.count)")
        guide = listings
    }

    private func retry(channel: Int, after seconds: Double, generation: Int) async {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, generation == self.tuneGeneration else { return }
            await self.load(channel: channel, generation: generation)
        }
    }

    /// Where the two preferences live. Read here rather than passed in, because `Tuner` is
    /// in Core and `AppConfig` is not — the same reason `tub3Channel` above is read this way.
    public static let startOnKey = "tub3.startOn"
    public static let lastWatchedKey = "tub3.lastWatched"

    /// A launch that inherits nothing from the one before it.
    ///
    /// `lastWatched` is written on every picture that arrives, so each test in a suite used
    /// to open on whatever channel the test before it happened to leave behind — and a
    /// channel inherited from a live schedule is sometimes one that has since gone off air,
    /// or that the box is mid-rebuild on. The test then waits for a picture that is not
    /// coming and blames the button it pressed.
    ///
    /// A separate flag from `-tub3Forget`, which forgets the *box* and so lands on the setup
    /// screen: a test needs to forget the channel without forgetting the television. Forget
    /// implies it, because a launch that starts from nothing starts from nothing.
    static func forgetChannelIfAsked() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-tub3ForgetChannel") || args.contains("-tub3Forget") else {
            return
        }
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: startOnKey)
        defaults.removeObject(forKey: lastWatchedKey)
    }

    /// How long the ident stays up. The box's number.
    static let bugSeconds: UInt64 = 4_000_000_000
    private var bugToken = 0

    private func showBug() {
        bugToken += 1
        let token = bugToken
        bugVisible = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: Tuner.bugSeconds)
            guard let self else { return }
            // Only if no newer ident has been raised meanwhile, or a quick second
            // channel change would be un-identified by the first one's timer.
            guard token == self.bugToken else { return }
            self.bugVisible = false
        }
    }
}

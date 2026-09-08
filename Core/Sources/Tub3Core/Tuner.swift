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

    public func start() async {
        do {
            channels = try await box.channels()
            guard let base = try await box.plexBase() else {
                state = .broken("Plex is not configured on the box")
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
            let first = forced ?? (channels.first { $0.isAmbiance }
                                   ?? channels.first { !$0.isGuide }
                                   ?? channels.first)?.channel
            if let first { await tune(to: first) }
        } catch {
            state = .broken(error.localizedDescription)
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
        tuneGeneration += 1
        let generation = tuneGeneration
        failures = 0
        avoidDirect = false
        current = channel
        let station = channels.first { $0.channel == channel }?.station ?? ""
        state = .tuning(channel: channel, station: station)
        Diag.log("tune ch\(channel) \(station) gen=\(generation)")
        if channels.first(where: { $0.channel == channel })?.isGuide != true {
            music.stop()
            guidePoll?.cancel()
            guidePoll = nil
        }
        showBug()
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
            await self.load(channel: channel, generation: generation)
        }
    }

    /// Wait for any settle in flight. Tests need it; nothing in the app does.
    public func settled() async {
        await settleTask?.value
    }

    public func channelUp() async {
        guard let index = tunedIndex() else { return }
        await tune(to: channels[(index + 1) % channels.count].channel)
    }

    public func channelDown() async {
        guard let index = tunedIndex() else { return }
        await tune(to: channels[(index - 1 + channels.count) % channels.count].channel)
    }

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
        tuneGeneration += 1
        await load(channel: channel, generation: tuneGeneration)
    }

    private func load(channel: Int, generation: Int) async {
        do {
            let state = try await box.now(channel: channel)
            guard generation == tuneGeneration else { return }
            await present(state, generation: generation)
        } catch {
            guard generation == tuneGeneration else { return }
            self.state = .broken(error.localizedDescription)
            // And ask again. A box that is rebooting, or a network that dropped for a moment,
            // used to end the app's evening: nothing retried out of this state.
            await retry(channel: channel, after: 10, generation: generation)
        }
    }

    private func present(_ now: NowPlaying, generation: Int) async {
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
            state = .slate(channel: now.channel, station: now.station,
                           message: now.error ?? "off air")
            await retry(channel: now.channel, after: 15, generation: generation)
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
        guard let resolver, let base = plexBase else { return }
        do {
            let item = try await resolver.resolve(entry, base: base,
                                                  forceTranscode: avoidDirect)
            guard generation == tuneGeneration else {
                // Left this channel while Plex was thinking. Give the transcoder back.
                if let session = item.session { await plex?.stop(session: session) }
                return
            }
            Diag.log("play url=\(item.url.absoluteString) joinAt=\(item.joinAt) playFor=\(item.playFor) session=\(item.session ?? "direct")")
            state = .playing(channel: now.channel, station: now.station,
                             title: entry.displayTitle, contentType: entry.contentType)
            playingDirect = item.session == nil
            nowEntry = entry
            if await engine.play(item) { failures = 0 }
        } catch {
            state = .slate(channel: now.channel, station: now.station,
                           message: "cannot play this")
            await retry(channel: now.channel, after: 8, generation: generation)
        }
    }

    /// Something went wrong with the picture. Say what, then go back to the box and ask
    /// again — which is also how a real set-top box behaves when a stream drops.
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
        state = .slate(channel: channel, station: station, message: why)
        await engine.stopCurrentSession()

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

    private func showBug() {
        bugVisible = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self else { return }
            self.bugVisible = false
        }
    }
}

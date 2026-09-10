import AVFoundation
import Foundation

/// Puts one item on screen and takes it off again at the right moment.
///
/// Deliberately one player, not a pool of warm ones. A pool is the obvious way to make
/// channel changes instant, and it is also the design most likely to be jetsammed on an
/// Apple TV HD with 2GB of RAM. A second or two of "tuning" is what a television does
/// anyway; a channel that dies because the app was killed is not.
///
/// One player with **one item queued behind the current one**, though, which is a different
/// bargain and worth the memory it costs. A channel change is a thing a person did and a
/// television is allowed to take a moment over it; an ad break is not, and a set that blacks
/// out for a second between the programme and the first advert — and again between every
/// advert in the pod — is doing the one thing the box never does. Measured on this dial
/// before the queue existed: 575ms, 966ms and 1296ms of held frame and black across three
/// consecutive boundaries in a single pod. The box has no equivalent problem because mpv
/// opens the next file off a local disk; this has to get a decision out of Plex, start a
/// transcoder and let AVFoundation fill a buffer, and none of that has to happen on screen.
///
/// The cost is one extra HLS item buffering and one extra Plex session, for the ten seconds
/// before a boundary. That is nothing like a warm player per channel.
@MainActor
public final class PlayerEngine {
    public let player = AVQueuePlayer()

    /// The Plex session currently burning CPU on the server, if any.
    private var liveSession: String?
    /// And the one the item waiting behind it is using. Two at once, briefly and on purpose.
    private var queuedSession: String?
    /// One per item, because with a queue there are two items in flight and the old
    /// single-observer version removed the outgoing item's registration as it installed the
    /// incoming one — which on a queue is exactly the notification the boundary rides on.
    private var boundaryObservers: [Any] = []
    private var plex: PlexClient?

    /// How far from the requested join point is close enough.
    ///
    /// Plex never trims the playlist — the offset arrives only as `#EXT-X-START`, and
    /// AVPlayer honours it but snaps *down* to the segment boundary at or before it. On a
    /// ten-second segment that is up to ten seconds of unwanted replay, which nobody notices
    /// inside a feature and everybody notices inside a thirty-second advert. So the join is
    /// left alone when it lands close and corrected when it does not, rather than paying for
    /// an exact seek every time.
    static let joinTolerance = 2.0

    /// An item's slot is up.
    ///
    /// - Parameter continued: whether a queued item took over without a gap. True means the
    ///   picture never went away and the tuner's job is bookkeeping — say what is on, hand
    ///   the old transcoder back, line up the next one — rather than tuning. False is the
    ///   old behaviour and still the right answer at the end of a block, where the box has
    ///   no `next` to give and the clock is the authority again.
    public var onBoundary: (@MainActor (_ continued: Bool) -> Void)?
    /// Raised when the picture does not arrive, or stops arriving. The box cannot get stuck
    /// like this — it opens the next file off a disk — so the app needs to say so and be told
    /// what to do, rather than sit on an empty layer looking like a dead channel.
    public var onFailure: (@MainActor (String) -> Void)?

    private var stallObserver: Any?
    private var watchdog: Task<Void, Never>?
    private var lastPlayhead: Double = -1
    private var lastProgressAt = Date()

    /// How long the picture may fail to advance before the channel is re-tuned. Long enough
    /// to ride out a transcoder catching its breath, short enough that nobody fetches the
    /// remote to check whether the television is broken.
    static let stallLimit: TimeInterval = 12

    public init() {
        // A test run should not play your dial out loud through the Mac. The flag is passed
        // by the UI tests only; nothing sets it in a shipped launch.
        if ProcessInfo.processInfo.arguments.contains("-tub3Mute") {
            player.isMuted = true
        }
    }

    public func attach(plex: PlexClient) { self.plex = plex }

    /// Build the item, cut where the plan says to cut.
    ///
    /// Shared by the hard cut and the queued one so the two cannot disagree about where an
    /// entry ends — which they would, silently, the first time only one of them was changed.
    private func makeItem(_ item: PlayableItem) -> AVPlayerItem {
        let playerItem = AVPlayerItem(asset: AVURLAsset(url: item.url))
        // The cut that keeps the schedule honest. Without it AVPlayer runs to end-of-file
        // and a feature plays straight through its own ad breaks.
        if item.playFor > 0 {
            playerItem.forwardPlaybackEndTime = CMTime(seconds: item.stopAt,
                                                       preferredTimescale: 600)
        }
        return playerItem
    }

    /// Put an item behind the one on screen, so the boundary is a swap rather than a start.
    ///
    /// AVFoundation prepares a queued item while the current one plays — that is what
    /// `AVQueuePlayer` is for — so by the time the cut arrives the segments are already in
    /// hand and the picture does not go away. Everything expensive about a transition
    /// happens here instead, ten seconds early, where nobody is looking at it.
    ///
    /// - Returns: false when there is nothing on screen to queue behind, in which case the
    ///   caller should simply play it.
    @discardableResult
    public func queue(_ item: PlayableItem) -> Bool {
        guard let current = player.currentItem else { return false }
        let playerItem = makeItem(item)
        guard player.canInsert(playerItem, after: current) else { return false }
        observeBoundary(of: playerItem)
        player.insert(playerItem, after: current)
        queuedSession = item.session
        Diag.log("queued the next entry behind this one session=\(item.session ?? "direct")")
        return true
    }

    /// The queue has moved on. Roll the bookkeeping to match.
    ///
    /// Synchronous, deliberately, with only the Plex call detached. The tuner queues the
    /// *next* entry from inside the boundary that this serves, so a version that rolled the
    /// sessions after an await would overwrite `queuedSession` with the one it had just
    /// replaced — and strand a transcoder on every break.
    ///
    /// The outgoing transcoder is handed back after the swap rather than before it. Plex
    /// does not reap abandoned sessions so it has to happen, but doing it first is a round
    /// trip spent with the picture already gone, which is the whole thing this is avoiding.
    private func advancedInQueue() {
        let outgoing = liveSession
        liveSession = queuedSession
        queuedSession = nil
        startWatchdog()
        guard let outgoing, let plex else { return }
        Task { await plex.stop(session: outgoing) }
    }

    /// Play an item now, dropping whatever is on screen and whatever was queued behind it.
    ///
    /// The hard cut: a channel change, a first tune, a recovery. Not a boundary — a boundary
    /// that has an item queued never reaches here, which is the point.
    ///
    /// - Returns: whether a picture actually arrived. The caller cannot tell otherwise —
    ///   this returns either way — and treating a failed item as a success is what kept the
    ///   retry backoff pinned at two seconds while a channel failed over and over.
    @discardableResult
    public func play(_ item: PlayableItem) async -> Bool {
        let handedBack = Date()
        await stopCurrentSession()
        Diag.took("  stop old session", since: handedBack)

        let playerItem = makeItem(item)

        liveSession = item.session
        let handedOver = Date()
        // `removeAllItems` rather than `replaceCurrentItem`: the latter leaves anything
        // queued behind it in place, so a channel change would have played the old channel's
        // next advert straight after the new channel's first frame.
        forgetBoundaries()
        observeBoundary(of: playerItem)
        player.removeAllItems()
        player.insert(playerItem, after: nil)
        player.play()

        // Nothing above proves a picture arrived. Wait for the item to actually become
        // playable and report it if it does not — the previous version declared success the
        // moment it handed the URL over, so a failed item left a black screen that never
        // retried and never explained itself.
        guard await waitUntilReady(playerItem) else {
            let ns = playerItem.error as NSError?
            Diag.log("not ready: status=\(playerItem.status.rawValue) domain=\(ns?.domain ?? "-") code=\(ns?.code ?? 0) err=\(playerItem.error?.localizedDescription ?? "none")")
            if let u = ns?.userInfo[NSUnderlyingErrorKey] as? NSError {
                Diag.log("   underlying domain=\(u.domain) code=\(u.code) \(u.localizedDescription)")
            }
            await Diag.probe(item.url)
            let why = playerItem.error?.localizedDescription ?? "the stream did not start"
            onFailure?(why)
            return false
        }

        Diag.took("  avplayer to readyToPlay", since: handedOver)
        let seeking = Date()
        await correctJoinIfNeeded(playerItem, wanted: item.joinAt, isTranscoded: item.session != nil)
        Diag.took("  join seek", since: seeking)
        Diag.log("  joined at \(playerItem.currentTime().seconds) rate=\(player.rate)")
        startWatchdog()
        return true
    }

    /// Notices a picture that has stopped arriving.
    ///
    /// A stall is not an error: AVFoundation reports no failure, the item stays `readyToPlay`,
    /// and the playhead simply stops. Only watching the clock catches it.
    private func startWatchdog() {
        watchdog?.cancel()
        lastPlayhead = -1
        lastProgressAt = Date()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self else { return }
                guard let item = self.player.currentItem else { continue }
                let now = item.currentTime().seconds
                if now.isFinite, now > self.lastPlayhead + 0.25 {
                    self.lastPlayhead = now
                    self.lastProgressAt = Date()
                    continue
                }
                if item.status == .failed {
                    self.watchdog?.cancel()
                    self.onFailure?(item.error?.localizedDescription ?? "playback failed")
                    return
                }
                if Date().timeIntervalSince(self.lastProgressAt) > Self.stallLimit {
                    Diag.log("stall at \(now) rate=\(self.player.rate) waiting=\(item.isPlaybackLikelyToKeepUp)")
                    self.watchdog?.cancel()
                    self.onFailure?("the picture stopped")
                    return
                }
            }
        }
    }

    private func correctJoinIfNeeded(_ item: AVPlayerItem, wanted: Double,
                                     isTranscoded: Bool) async {
        guard wanted > 0 else { return }
        // Wait for the item either way. A seek issued before `readyToPlay` is discarded
        // silently — the file then plays from the beginning with no error, which on a
        // twelve-hour ambiance clip looks like the wrong thing playing and on a feature looks
        // like the schedule being ignored.
        guard await waitUntilReady(item) else { return }

        // A direct-played file has no EXT-X-START to honour, so it always needs the seek —
        // and there it is frame-accurate and costs about two milliseconds.
        if !isTranscoded {
            await item.seek(to: CMTime(seconds: wanted, preferredTimescale: 600),
                            toleranceBefore: .zero, toleranceAfter: .zero)
            return
        }
        let landed = item.currentTime().seconds
        guard landed.isFinite, abs(landed - wanted) > Self.joinTolerance else { return }
        await item.seek(to: CMTime(seconds: wanted, preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func waitUntilReady(_ item: AVPlayerItem, timeout: Double = 10) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if item.status == .readyToPlay { return true }
            if item.status == .failed { return false }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }

    private func observeBoundary(of item: AVPlayerItem) {
        // `forwardPlaybackEndTime` ends the item early, and AVFoundation reports that as an
        // ordinary "played to end". That is the signal that the entry's slot is up.
        //
        // One registration per item and none of them removed here. There are two items in
        // flight now, and the old version removed the previous observer as it installed the
        // next — which with a queue meant unregistering the very item whose ending is the
        // event. They are all dropped together on a hard cut and on `stop`.
        let observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.stepOverBoundary(from: item)
                }
            }
        boundaryObservers.append(observer)
    }

    /// Take the step the queue will not take by itself.
    ///
    /// `forwardPlaybackEndTime` stops an item where the *plan* says the entry ends, and
    /// AVFoundation reports that as having played to the end — but `AVQueuePlayer` only
    /// advances on a file's real end, so it does not move. Measured: the notification
    /// arrives, the queued item is sitting behind it already prepared, and the player stays
    /// parked on the frame it stopped at. Every entry in this app ends that way, because
    /// every entry is a slice of a longer file, so the step is always ours to take.
    private func stepOverBoundary(from item: AVPlayerItem) {
        var continued = false
        if player.currentItem === item, player.items().count > 1 {
            let next = player.items()[1]
            Diag.log("boundary: stepping to the queued item, prepared=\(next.isPlaybackLikelyToKeepUp)")
            player.advanceToNextItem()
            player.play()
            continued = true
        } else if player.currentItem !== item, player.currentItem != nil {
            // It moved on its own — a file that genuinely ran out rather than being cut.
            continued = true
        }
        // Asked of the player rather than assumed from `queuedSession`: a queued item that
        // failed to load is dropped by AVFoundation, and the honest answer is then the same
        // as having queued nothing at all.
        if continued { advancedInQueue() }
        onBoundary?(continued)
    }

    private func forgetBoundaries() {
        for observer in boundaryObservers { NotificationCenter.default.removeObserver(observer) }
        boundaryObservers.removeAll()
    }

    /// Hand the transcoders back. Called on every tune-out, because Plex does not reap
    /// abandoned sessions and a few minutes of channel surfing would otherwise leave a pile
    /// of them running.
    ///
    /// Both of them: a tune-out that happens in the ten seconds before a boundary is leaving
    /// two behind, and the queued one is the easier of the two to forget precisely because
    /// nothing was ever shown from it.
    public func stopCurrentSession() async {
        let sessions = [liveSession, queuedSession].compactMap { $0 }
        liveSession = nil
        queuedSession = nil
        guard let plex else { return }
        for session in sessions { await plex.stop(session: session) }
    }

    /// Whether anything is lined up behind what is on screen.
    public var hasQueued: Bool { player.items().count > 1 }

    /// Stop watching, without tearing down the player.
    ///
    /// Called whenever the app leaves a channel. The watchdog only knows that the playhead
    /// has stopped advancing; it cannot tell "the stream died" from "we tuned away", and if
    /// left running it reports the channel you just left as broken — which on the guide,
    /// where there is no stream at all, replaces the listings with a fault message.
    public func standDown() {
        watchdog?.cancel()
        watchdog = nil
    }

    public func stop() async {
        watchdog?.cancel()
        watchdog = nil
        player.pause()
        player.removeAllItems()
        forgetBoundaries()
        await stopCurrentSession()
    }
}

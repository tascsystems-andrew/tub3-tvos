import AVFoundation
import Foundation

/// Puts one item on screen and takes it off again at the right moment.
///
/// Deliberately one player, not a pool of warm ones. A pool is the obvious way to make
/// channel changes instant, and it is also the design most likely to be jetsammed on an
/// Apple TV HD with 2GB of RAM. A second or two of "tuning" is what a television does
/// anyway; a channel that dies because the app was killed is not.
@MainActor
public final class PlayerEngine {
    public let player = AVPlayer()

    /// The Plex session currently burning CPU on the server, if any.
    private var liveSession: String?
    private var boundaryObserver: Any?
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

    public var onBoundary: (@MainActor () -> Void)?
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

    /// Play an item, joining part-way in, and call `onBoundary` when its slot is up.
    ///
    /// - Returns: whether a picture actually arrived. The caller cannot tell otherwise —
    ///   this returns either way — and treating a failed item as a success is what kept the
    ///   retry backoff pinned at two seconds while a channel failed over and over.
    @discardableResult
    public func play(_ item: PlayableItem) async -> Bool {
        await stopCurrentSession()

        let asset = AVURLAsset(url: item.url)
        let playerItem = AVPlayerItem(asset: asset)

        // The cut that keeps the schedule honest. Without it AVPlayer runs to end-of-file
        // and a feature plays straight through its own ad breaks.
        if item.playFor > 0 {
            playerItem.forwardPlaybackEndTime = CMTime(seconds: item.stopAt,
                                                       preferredTimescale: 600)
        }

        liveSession = item.session
        player.replaceCurrentItem(with: playerItem)
        installBoundary(for: playerItem)
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

        Diag.log("ready, seeking to \(item.joinAt)")
        await correctJoinIfNeeded(playerItem, wanted: item.joinAt, isTranscoded: item.session != nil)
        Diag.log("joined at \(playerItem.currentTime().seconds) rate=\(player.rate)")
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

    private func installBoundary(for item: AVPlayerItem) {
        if let observer = boundaryObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        // `forwardPlaybackEndTime` ends the item early, and AVFoundation reports that as an
        // ordinary "played to end". That is the signal to ask the box what is next.
        boundaryObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onBoundary?() }
            }
    }

    /// Hand the transcoder back. Called on every tune-out, because Plex does not reap
    /// abandoned sessions and a few minutes of channel surfing would otherwise leave a pile
    /// of them running.
    public func stopCurrentSession() async {
        guard let session = liveSession, let plex else { liveSession = nil; return }
        liveSession = nil
        await plex.stop(session: session)
    }

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
        player.replaceCurrentItem(with: nil)
        if let observer = boundaryObserver {
            NotificationCenter.default.removeObserver(observer)
            boundaryObserver = nil
        }
        await stopCurrentSession()
    }
}

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

    public init() {
        // A test run should not play your dial out loud through the Mac. The flag is passed
        // by the UI tests only; nothing sets it in a shipped launch.
        if ProcessInfo.processInfo.arguments.contains("-tub3Mute") {
            player.isMuted = true
        }
    }

    public func attach(plex: PlexClient) { self.plex = plex }

    /// Play an item, joining part-way in, and call `onBoundary` when its slot is up.
    public func play(_ item: PlayableItem) async {
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

        await correctJoinIfNeeded(playerItem, wanted: item.joinAt, isTranscoded: item.session != nil)
    }

    private func correctJoinIfNeeded(_ item: AVPlayerItem, wanted: Double,
                                     isTranscoded: Bool) async {
        guard wanted > 0 else { return }
        // A direct-played file has no EXT-X-START to honour, so it always needs the seek —
        // and there it is frame-accurate and costs about two milliseconds.
        if !isTranscoded {
            await item.seek(to: CMTime(seconds: wanted, preferredTimescale: 600),
                            toleranceBefore: .zero, toleranceAfter: .zero)
            return
        }
        _ = await waitUntilReady(item)
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

    public func stop() async {
        player.pause()
        player.replaceCurrentItem(with: nil)
        if let observer = boundaryObserver {
            NotificationCenter.default.removeObserver(observer)
            boundaryObserver = nil
        }
        await stopCurrentSession()
    }
}

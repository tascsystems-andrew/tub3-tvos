import AVFoundation
import Foundation

public struct MusicTrack: Codable, Equatable, Sendable {
    public let index: Int
    public let name: String
    public let url: String
}

struct MusicList: Codable, Sendable { let tracks: [MusicTrack] }

/// The elevator music behind channel 2.
///
/// Its own player, not the tuner's. The guide has no video and the listings are drawn by the
/// app, so there is nothing for `PlayerEngine` to do here — and giving the music its own
/// player means the boundary timer, the join correction and the stall watchdog, all of which
/// exist to police a *schedule*, never run against a track that has none.
@MainActor
public final class GuideMusic {
    private let player = AVQueuePlayer()
    private var endObserver: Any?
    private var tracks: [URL] = []

    public init() {
        if ProcessInfo.processInfo.arguments.contains("-tub3Mute") {
            player.isMuted = true
        }
    }

    public var isPlaying: Bool { player.rate > 0 }
    /// Where the current track has got to, so a probe can prove it is actually moving.
    public var playhead: Double { player.currentItem?.currentTime().seconds ?? 0 }

    /// Start the playlist, joined at the wall clock rather than at the beginning.
    ///
    /// The box's music has been running since it booted, so arriving at channel 2 there drops
    /// you somewhere in the middle. Starting from zero on every visit would instead play the
    /// same opening bars every time anyone glanced at the listings, which is the one way a
    /// three-hour loop manages to sound repetitive.
    public func start(_ tracks: [URL]) async {
        guard !tracks.isEmpty else { return }
        guard tracks != self.tracks || !isPlaying else { return }   // already on, leave it be
        stop()
        self.tracks = tracks

        enqueue(from: 0)
        player.play()

        guard let item = player.currentItem else { return }
        Diag.log("guide music \(tracks.count) track(s), first=\(tracks[0].lastPathComponent)")
        // Duration is not known until the header has been read, so the join has to wait for
        // it. Failing to get one is not a fault — it just means starting at the top.
        if let seconds = try? await item.asset.load(.duration).seconds,
           seconds.isFinite, seconds > 1 {
            let into = Date().timeIntervalSince1970.truncatingRemainder(dividingBy: seconds)
            await item.seek(to: CMTime(seconds: into, preferredTimescale: 600),
                            toleranceBefore: .zero, toleranceAfter: .zero)
            Diag.log("guide music joined at \(Int(into))s of \(Int(seconds))s")
        }
    }

    public func stop() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player.pause()
        player.removeAllItems()
        tracks = []
    }

    private func enqueue(from index: Int) {
        player.removeAllItems()
        for offset in 0 ..< tracks.count {
            player.insert(AVPlayerItem(url: tracks[(index + offset) % tracks.count]),
                          after: nil)
        }
        // The queue empties at the end of the last track. Refilling it there is what makes
        // this a channel rather than a playlist: the guide is the one thing that is always on.
        //
        // Watching the last item specifically, rather than every item and reading the
        // notification, keeps the callback free of anything that has to cross into the main
        // actor with it.
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: player.items().last, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.enqueue(from: 0)
                self.player.play()
            }
        }
    }
}

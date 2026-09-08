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
    private var keepAlive: Task<Void, Never>?
    private var lastPlayhead: Double = -1
    private var lastProgressAt = Date()

    public init() {
        if ProcessInfo.processInfo.arguments.contains("-tub3Mute") {
            player.isMuted = true
        }
    }

    public var isPlaying: Bool { player.rate > 0 }
    /// Where the current track has got to, so a probe can prove it is actually moving.
    public var playhead: Double { player.currentItem?.currentTime().seconds ?? 0 }

    /// Start the playlist at the top, which is what the television does.
    ///
    /// `tuner/player.py: play_loop` hands mpv the playlist with `loop-playlist inf` and loads
    /// it with `replace`, so tuning to channel 2 on the box always begins at the first track,
    /// and its docstring says why: "the guide's music is not on a timetable and nobody can
    /// tune in late to it."
    ///
    /// An earlier version here joined at the wall clock instead, on the assumption that the
    /// box's music had been running since it booted. It has not, and the guide track is a
    /// three-hour compilation — so the app played the same file as the television and a
    /// different song, every time. The assumption was never the box's; it was mine.
    public func start(_ tracks: [URL]) async {
        guard !tracks.isEmpty else { return }
        guard tracks != self.tracks || !isPlaying else { return }   // already on, leave it be
        stop()
        self.tracks = tracks
        enqueue(from: 0)
        player.play()
        startKeepAlive()
        Diag.log("guide music from the top: \(tracks[0].lastPathComponent) of \(tracks.count)")
    }

    /// Keep the music going past a track that will not play.
    ///
    /// The box cannot lose its music: mpv is handed the whole playlist with `loop-playlist
    /// inf` and skips anything it cannot open. AVFoundation is fussier — `music_for` accepts
    /// .ogg, .wma and .flac, and the endpoint serves whatever is in the folder — so one file
    /// this player will not open used to stop channel 2, and if it was the last track the
    /// loop never restarted at all.
    ///
    /// Polled rather than driven by `AVPlayerItemFailedToPlayToEndTime`, because that
    /// notification does not fire for an item that never became ready, which is precisely
    /// what an unsupported format does. Polling catches every failure the same way.
    ///
    /// It never reports upward. Silence behind the listings is a disappointment; a fault
    /// slate over them would be a broken channel, and the listings are the point.
    private func startKeepAlive() {
        keepAlive?.cancel()
        lastPlayhead = -1
        lastProgressAt = Date()
        keepAlive = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self, !self.tracks.isEmpty else { return }

                guard let item = self.player.currentItem else {
                    // The queue drained — the last track was the unplayable one.
                    Diag.log("guide music: queue empty, starting the playlist again")
                    self.enqueue(from: 0)
                    self.player.play()
                    self.lastProgressAt = Date()
                    continue
                }
                let now = item.currentTime().seconds
                if item.status != .failed, now.isFinite, now > self.lastPlayhead + 0.25 {
                    self.lastPlayhead = now
                    self.lastProgressAt = Date()
                    continue
                }
                let stuck = Date().timeIntervalSince(self.lastProgressAt) > 6
                guard item.status == .failed || stuck else { continue }
                Diag.log("guide music: skipping a track that will not play")
                self.player.advanceToNextItem()
                if self.player.currentItem == nil { self.enqueue(from: 0) }
                self.player.play()
                self.lastPlayhead = -1
                self.lastProgressAt = Date()
            }
        }
    }

    public func stop() {
        keepAlive?.cancel()
        keepAlive = nil
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

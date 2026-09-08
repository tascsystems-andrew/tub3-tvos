import XCTest
import AVFoundation
@testable import Tub3Core

/// Resolve and actually play whatever is on given channels, right now, against the real box
/// and real Plex. Run by name:
///   TUB3_BOX=http://yourbox:8008 swift test --package-path Core --filter LiveChannelProbe
@MainActor
final class LiveChannelProbe: XCTestCase {
    func testChannelsPlay() async throws {
        try LiveTarget.required()
        let channels = [12, 13]
        let box = BoxClient(base: LiveTarget.box)
        guard let base = try await box.plexBase() else { return XCTFail("no plex base") }
        let plex = PlexClient(base: base, clientID: "probe-mac")
        let resolver = StreamResolver(plex: plex, clientID: "probe-mac")

        for ch in channels {
            print("\n===== CHANNEL \(ch) =====")
            let now: NowPlaying
            do { now = try await box.now(channel: ch) }
            catch { print("  box.now FAILED: \(error)"); XCTFail("ch\(ch) box"); continue }

            guard let entry = now.now else { print("  box has nothing on"); continue }
            print("  title:   \(entry.displayTitle)")
            print("  type:    \(entry.contentType)  offset=\(entry.offsetSeconds) remaining=\(entry.remainingSeconds)")
            guard let ref = entry.plex else { print("  NO PLEX REF — box could not identify the file"); XCTFail("ch\(ch) ref"); continue }
            print("  ratingKey=\(ref.ratingKey) media=\(ref.mediaIndex) part=\(ref.partIndex)")

            // What does Plex say the file is?
            do {
                let part = try await plex.part(ratingKey: ref.ratingKey,
                                               mediaIndex: ref.mediaIndex, partIndex: ref.partIndex)
                print("  plex part: \(part)")
                print("  route:     \(StreamRouter.route(part))")
            } catch { print("  plex.part FAILED: \(error)"); XCTFail("ch\(ch) part"); continue }

            let item: PlayableItem
            do { item = try await resolver.resolve(entry, base: base) }
            catch { print("  RESOLVE FAILED: \(error)"); XCTFail("ch\(ch) resolve"); continue }
            print("  url:     \(item.url.absoluteString)")
            print("  session: \(item.session ?? "direct")")

            let pi = AVPlayerItem(asset: AVURLAsset(url: item.url))
            let player = AVPlayer(playerItem: pi)
            player.volume = 0
            player.play()
            let deadline = Date().addingTimeInterval(25)
            while pi.status == .unknown && Date() < deadline {
                try await Task.sleep(nanoseconds: 200_000_000)
            }
            print("  status:  \(pi.status.rawValue) err=\(pi.error?.localizedDescription ?? "none")")
            guard pi.status == .readyToPlay else { XCTFail("ch\(ch) never became ready"); continue }

            await pi.seek(to: CMTime(seconds: item.joinAt, preferredTimescale: 600))
            let a = pi.currentTime().seconds
            try await Task.sleep(nanoseconds: 5_000_000_000)
            let b = pi.currentTime().seconds
            print(String(format: "  playhead %.1f -> %.1f (advanced %.1f in 5s)", a, b, b - a))
            let tracks = pi.tracks.map { "\($0.assetTrack?.mediaType.rawValue ?? "?")" }
            print("  tracks:  \(tracks)")
            if let session = item.session { try? await plex.stop(session: session) }
            XCTAssertGreaterThan(b - a, 2, "ch\(ch) did not advance")
        }
    }
}

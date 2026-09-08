import XCTest
import AVFoundation
@testable import Tub3Core

/// Talks to the real box and the real Plex. Never part of the suite — run by name:
///   TUB3_BOX=http://yourbox:8008 swift test --package-path Core --filter LiveAmbianceProbe
final class LiveAmbianceProbe: XCTestCase {
    func testAmbianceActuallyPlays() async throws {
        try LiveTarget.required()
        let box = BoxClient(base: LiveTarget.box)
        let now = try await box.now(channel: 13)
        guard let entry = now.now else { return XCTFail("box had nothing on channel 13") }
        guard let base = try await box.plexBase() else { return XCTFail("no plex base") }

        let plex = PlexClient(base: base, clientID: "probe-mac")
        let item = try await StreamResolver(plex: plex, clientID: "probe-mac")
            .resolve(entry, base: base)
        print("PROBE url:", item.url.absoluteString)
        print("PROBE joinAt:", item.joinAt, "playFor:", item.playFor,
              "stopAt:", item.stopAt, "session:", item.session ?? "direct")

        let asset = AVURLAsset(url: item.url)
        let playerItem = AVPlayerItem(asset: asset)
        if item.playFor > 0 {
            playerItem.forwardPlaybackEndTime = CMTime(seconds: item.stopAt, preferredTimescale: 600)
        }
        let player = AVPlayer(playerItem: playerItem)
        player.volume = 0
        player.play()

        let readyBy = Date().addingTimeInterval(30)
        while playerItem.status == .unknown && Date() < readyBy {
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        print("PROBE status:", playerItem.status.rawValue,
              "error:", playerItem.error?.localizedDescription ?? "none")
        XCTAssertEqual(playerItem.status, .readyToPlay)

        let began = Date()
        await playerItem.seek(to: CMTime(seconds: item.joinAt, preferredTimescale: 600),
                             toleranceBefore: .zero, toleranceAfter: .zero)
        print(String(format: "PROBE exact seek to %.1f took %.1f s", item.joinAt,
                     Date().timeIntervalSince(began)))

        var samples: [Double] = []
        for _ in 0 ..< 8 {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            samples.append(playerItem.currentTime().seconds)
        }
        print("PROBE playhead:", samples.map { String(format: "%.1f", $0) }.joined(separator: " "))
        let advanced = (samples.last ?? 0) - (samples.first ?? 0)
        print(String(format: "PROBE advanced %.2f s over 14 s of wall clock", advanced))
        XCTAssertGreaterThan(advanced, 5, "the picture never got going")
    }
}

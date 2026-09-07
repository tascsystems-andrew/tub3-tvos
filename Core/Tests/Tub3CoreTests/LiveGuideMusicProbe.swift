import XCTest
import AVFoundation
@testable import Tub3Core

/// Talks to the real box. Run by name:
///   swift test --package-path Core --filter LiveGuideMusicProbe
@MainActor
final class LiveGuideMusicProbe: XCTestCase {
    func testGuideMusicPlays() async throws {
        let box = BoxClient(base: URL(string: "http://boobtube:8008")!)
        let tracks = try await box.guideMusic()
        print("PROBE tracks:", tracks.map(\.absoluteString))
        XCTAssertFalse(tracks.isEmpty, "the box offered no guide music")

        let music = GuideMusic()
        await music.start(tracks)

        var samples: [Double] = []
        for _ in 0 ..< 6 {
            try await Task.sleep(nanoseconds: 1_500_000_000)
            samples.append(music.playhead)
        }
        print("PROBE playhead:", samples.map { String(format: "%.1f", $0) }.joined(separator: " "))
        let advanced = (samples.last ?? 0) - (samples.first ?? 0)
        print(String(format: "PROBE advanced %.2f s over 7.5 s", advanced))
        XCTAssertGreaterThan(samples.first ?? 0, 1, "did not join part-way in")
        XCTAssertGreaterThan(advanced, 3, "the music never got going")

        music.stop()
        XCTAssertFalse(music.isPlaying)
    }
}

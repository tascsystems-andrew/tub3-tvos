import XCTest

/// Flips through the dial the way a bored person does.
///
/// This is not testing the UI so much as what the UI leaves behind on the Plex server. Plex
/// does not reap abandoned transcode sessions: without an explicit stop on every tune-out,
/// each flip strands a live transcoder, and a couple of minutes of surfing will bury the
/// machine. The assertion for that lives outside this process — the session count is read
/// from Plex before and after — so this test's job is simply to do the flipping.
final class SurfTests: XCTestCase {

    func testFlipThroughTheDial() throws {
        let app = XCUIApplication()
        app.launchArguments += Harness.quiet
        app.launch()

        let label = app.staticTexts["tub3.channel.number"]
        XCTAssertTrue(label.waitForExistence(timeout: 40), "never tuned at all")

        // Long enough for each tune to actually reach Plex and start a transcoder — a flip
        // that never got as far as asking for a stream proves nothing about cleaning up.
        for _ in 0 ..< 8 {
            XCUIRemote.shared.press(.up)
            Thread.sleep(forTimeInterval: 4)
        }
        XCTAssertTrue(label.exists)
    }
}

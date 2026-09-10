import XCTest

/// Flips through the dial the way a bored person does.
///
/// A **probe**, not a test, and out of `make uitest` for the same reason `ParkTests` is: it
/// asserts nothing this process can check. What it is for lives outside — Plex does not reap
/// abandoned transcode sessions, so without an explicit stop on every tune-out each flip
/// strands a live transcoder and a couple of minutes of surfing buries the machine, and the
/// session count is read from Plex before and after by whoever is running it. Left in the
/// default suite it could only ever fail for the box's reasons, which is precisely what
/// makes a red suite stop meaning anything.
///
///     make uiprobe
final class LiveSurfProbe: XCTestCase {

    func testFlipThroughTheDial() throws {
        let app = XCUIApplication()
        app.launchArguments += Harness.quiet
        app.launch()
        Harness.settled(app)

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

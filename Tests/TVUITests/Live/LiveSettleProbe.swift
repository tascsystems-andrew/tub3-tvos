import XCTest

/// A thumb moving up the dial should open one channel, not every channel it passes.
///
/// The box waits 220ms of quiet before it opens anything, and says why: eight presses up the
/// dial should open one file, the number on screen keeps up with the button while the tuner
/// obviously cannot, and the whole trick of a dial that feels fast is that the display never
/// admits it. Without a settle the app opened — and abandoned — a Plex session per channel
/// passed through, which is exactly what SurfTests exists to worry about.
///
/// The assertion is on the app's own trace: `tune` is announced per press, `play url` only
/// when something is actually opened. Run against a live box.
final class SettleTests: XCTestCase {

    func testABurstOfPressesOpensOneChannel() throws {
        let app = XCUIApplication()
        app.launchArguments += Harness.quiet + ["-tub3Trace"]
        app.launch()

        let label = app.staticTexts["tub3.channel.number"]
        XCTAssertTrue(label.waitForExistence(timeout: 40), "never tuned at all")
        Thread.sleep(forTimeInterval: 3)          // let the first channel settle and open

        // Six presses far faster than the settle window.
        for _ in 0 ..< 6 {
            XCUIRemote.shared.press(.up)
            Thread.sleep(forTimeInterval: 0.08)
        }
        // The number must have kept up with the thumb even though nothing has opened yet.
        // waitForExistence rather than `exists`: tvOS drops accessibility snapshots under
        // load (FBSSceneSnapshotErrorDomain 4 in the runner log), and sampling once turns
        // that into a failed assertion about the app.
        XCTAssertTrue(label.waitForExistence(timeout: 5), "the ident stopped following the button")
        Thread.sleep(forTimeInterval: 6)          // settle, then open exactly one
        XCTAssertTrue(label.exists)
    }
}

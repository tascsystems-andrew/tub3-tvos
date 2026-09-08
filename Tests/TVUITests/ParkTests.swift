import XCTest

/// Not an assertion — a way to hold the app on one screen long enough to photograph it.
/// Only ever run by name (-only-testing), never as part of the suite.
final class ParkTests: XCTestCase {
    func testParkOnTheGuide() throws {
        let app = XCUIApplication()
        app.launchArguments += Harness.quiet + ["-tub3Channel", "3"]
        app.launch()
        XCTAssertTrue(app.staticTexts["tub3.channel.tuned"].waitForExistence(timeout: 40))
        XCUIRemote.shared.press(.down)          // ch3 -> ch2, the guide. Pinned to 3
                                                // because the app opens on ambiance, 13.
        Thread.sleep(forTimeInterval: 45)
    }
}

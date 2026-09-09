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

    /// Holds the menu open long enough to photograph it. Only ever run by name.
    func testParkOnTheMenu() throws {
        let app = XCUIApplication()
        app.launchArguments += Harness.quiet
        app.launch()
        XCTAssertTrue(app.staticTexts["tub3.channel.tuned"].waitForExistence(timeout: 40))
        // `tub3.channel.tuned` appears while the state is still `.tuning`; the switch to
        // `.playing` rebuilds the content and can take focus off the invisible SELECT button
        // for a frame. Let the picture settle before pressing, or the press lands in that gap.
        Thread.sleep(forTimeInterval: 4)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.otherElements["tub3.menu"].waitForExistence(timeout: 10))
        XCUIRemote.shared.press(.down)          // off the exit row, onto Signal
        Thread.sleep(forTimeInterval: 2)

        // Written from inside the test rather than photographed from outside: a UI test owns
        // the simulator while it runs, and `simctl io screenshot` fired at it from another
        // process caught the Home screen three times running.
        let shot = XCUIScreen.main.screenshot()
        let out = URL(fileURLWithPath: ProcessInfo.processInfo
            .environment["TUB3_SHOT"] ?? "/tmp/tub3-menu.png")
        try? shot.pngRepresentation.write(to: out)
    }
}

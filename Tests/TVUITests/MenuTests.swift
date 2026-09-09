import XCTest

/// Can this television be switched off?
///
/// A tvOS app that swallows Menu at its top level cannot be left except with the TV button,
/// and it is the best-documented reason Apple rejects one. The app believes it does not do
/// this — there is a comment in `TunerScreen` saying Menu is deliberately not swallowed when
/// the strip is shut — and no test has ever checked it from the top level, only with the
/// strip already open.
final class MenuTests: XCTestCase {

    func testMenuLeavesTheAppFromTheTopLevel() throws {
        let app = XCUIApplication()
        app.launchArguments += Harness.quiet
        app.launch()
        XCTAssertTrue(app.staticTexts["tub3.channel.tuned"].waitForExistence(timeout: 40),
                      "never tuned, so this proves nothing either way")

        // The app's OWN state is not the signal. XCUITest on tvOS keeps reporting
        // `.runningForeground` for the app under test after the system has backgrounded it,
        // so an assertion on `app.state` fails whether or not Menu was swallowed — it says
        // nothing. What does say something is the Home screen coming to the front.
        let home = XCUIApplication(bundleIdentifier: "com.apple.HeadBoard")

        XCUIRemote.shared.press(.menu)

        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline && home.state != .runningForeground {
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertEqual(home.state, .runningForeground,
                       "Menu did not leave the app from the top level: the viewer is "
                       + "trapped and only the TV button gets them out")

        // Put the simulator back where it was found. This test succeeds by leaving the Home
        // screen up, and the next test in the class then launches into a simulator that is
        // showing something else — which cost a false failure of `testSelectOpensTheMenu`,
        // passing alone and failing in the suite.
        app.activate()
    }

    /// SELECT opens the menu. The box's own grammar — `WATCH SELECT opens the menu` — and
    /// the route that three previous attempts failed to find.
    func testSelectOpensTheMenu() {
        let app = XCUIApplication()
        app.launchArguments += Harness.quiet
        app.launch()
        XCTAssertTrue(app.staticTexts["tub3.channel.tuned"].waitForExistence(timeout: 40))

        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.otherElements["tub3.menu"].waitForExistence(timeout: 10),
                      "select did not open the menu")
        // It opens on the way out, so the button that opened it closes it.
        XCUIRemote.shared.press(.select)
        XCTAssertFalse(app.otherElements["tub3.menu"].waitForExistence(timeout: 3),
                       "a second select should have closed it again")
    }

    /// Back inside the menu is its way out, and leaves the app alone.
    func testBackClosesTheMenuRatherThanTheApp() {
        let app = XCUIApplication()
        app.launchArguments += Harness.quiet
        app.launch()
        XCTAssertTrue(app.staticTexts["tub3.channel.tuned"].waitForExistence(timeout: 40))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.otherElements["tub3.menu"].waitForExistence(timeout: 10))

        let home = XCUIApplication(bundleIdentifier: "com.apple.HeadBoard")
        XCUIRemote.shared.press(.menu)
        XCTAssertFalse(app.otherElements["tub3.menu"].waitForExistence(timeout: 3),
                       "back did not close the menu")
        XCTAssertNotEqual(home.state, .runningForeground,
                          "back left the app instead of closing the menu")
    }

    /// The strip always carries a way into the menu, even with no channels at all.
    ///
    /// Load-bearing rather than a nicety: the empty-dial strip path had never run once,
    /// because the play/pause branch that used to forget the box short-circuited before the
    /// strip was ever built.
    func testTheStripIsNeverEmpty() {
        let app = XCUIApplication()
        // Nothing answers here, so the dial stays empty and the screen sits on no signal.
        app.launchArguments += ["-tub3Mute", "-tub3Box", "http://127.0.0.1:1"]
        app.launch()

        XCUIRemote.shared.press(.playPause)
        XCTAssertTrue(app.buttons["tub3.dial.setup"].waitForExistence(timeout: 25),
                      "an empty strip left the viewer with nothing to press")
    }

    /// Opening the menu twice.
    ///
    /// The design called this the most likely regression of the whole build and it was
    /// right: the invisible SELECT button is removed from the tree while an overlay is up,
    /// so when the menu closes the button comes back with no focus on it, and the next press
    /// goes nowhere. The menu opened exactly once per launch.
    func testTheMenuOpensAgainAfterItIsClosed() {
        let app = XCUIApplication()
        app.launchArguments += Harness.quiet
        app.launch()
        XCTAssertTrue(app.staticTexts["tub3.channel.tuned"].waitForExistence(timeout: 40))
        Thread.sleep(forTimeInterval: 4)

        for attempt in 1 ... 3 {
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.otherElements["tub3.menu"].waitForExistence(timeout: 8),
                          "the menu did not open on attempt \(attempt)")
            XCUIRemote.shared.press(.menu)
            XCTAssertFalse(app.otherElements["tub3.menu"].waitForExistence(timeout: 3),
                           "the menu did not close on attempt \(attempt)")
            Thread.sleep(forTimeInterval: 1)
        }
    }
}

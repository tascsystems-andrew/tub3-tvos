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
    }
}

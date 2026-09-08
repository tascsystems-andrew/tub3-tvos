import XCTest

/// The first thing anybody ever sees.
///
/// Worth a test of its own because it is the one screen with no fallback behind it: every
/// other failure in this app still leaves a television showing something, and this one leaves
/// a stranger holding a remote with nothing to press. It is also the only screen whose
/// correctness depends on the network answering, so it fails in ways a unit test cannot see.
final class SetupTests: XCTestCase {

    func testFirstRunFindsTheBoxAndTunes() {
        let app = XCUIApplication()
        // No box, and deliberately no `-tub3Box` either: discovery is the thing under test.
        app.launchArguments += ["-tub3Mute", "-tub3Forget"]
        app.launch()

        let box = app.buttons["tub3.setup.box"].firstMatch
        XCTAssertTrue(box.waitForExistence(timeout: 30),
                      "nothing was found on the network within thirty seconds")

        // tvOS has no tap: the focus engine puts focus on the only button on screen, and
        // select presses whatever holds it.
        XCUIRemote.shared.press(.select)

        XCTAssertTrue(app.staticTexts["tub3.channel.tuned"].waitForExistence(timeout: 40),
                      "chose a box and never tuned")
    }

    /// The setup screen has to *stop* offering itself once a box is chosen — a picker that
    /// reappears on every launch is indistinguishable from one that never saved anything.
    func testTheChoiceIsRemembered() {
        let app = XCUIApplication()
        app.launchArguments += ["-tub3Mute", "-tub3Forget"]
        app.launch()
        XCTAssertTrue(app.buttons["tub3.setup.box"].firstMatch.waitForExistence(timeout: 30))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["tub3.channel.tuned"].waitForExistence(timeout: 40))
        app.terminate()

        // Same app, no flags: it should go straight to a picture.
        let again = XCUIApplication()
        again.launchArguments += ["-tub3Mute"]
        again.launch()
        XCTAssertTrue(again.staticTexts["tub3.channel.tuned"].waitForExistence(timeout: 40),
                      "the box it was told about was not remembered")
        XCTAssertFalse(again.buttons["tub3.setup.box"].firstMatch.exists,
                       "asked again for a box it had already been given")
    }
}

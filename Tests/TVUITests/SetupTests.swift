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
        // select presses whatever holds it. Existing is not the same as holding focus, and
        // a press sent in between is lost silently — the same fault that made the whole
        // tuner suite intermittent, on the one screen that has no watchdog behind it.
        XCTAssertTrue(focused(box), "the box this screen found was never focusable")
        XCUIRemote.shared.press(.select)

        Harness.tuned(app)
    }

    /// The setup screen has to *stop* offering itself once a box is chosen — a picker that
    /// reappears on every launch is indistinguishable from one that never saved anything.
    func testTheChoiceIsRemembered() {
        let app = XCUIApplication()
        app.launchArguments += ["-tub3Mute", "-tub3Forget"]
        app.launch()
        let box = app.buttons["tub3.setup.box"].firstMatch
        XCTAssertTrue(box.waitForExistence(timeout: 30))
        XCTAssertTrue(focused(box), "the box this screen found was never focusable")
        XCUIRemote.shared.press(.select)
        Harness.tuned(app)
        app.terminate()

        // Same app, no flags: it should go straight to a picture.
        let again = XCUIApplication()
        again.launchArguments += ["-tub3Mute"]
        again.launch()
        Harness.tuned(again)
        XCTAssertFalse(again.buttons["tub3.setup.box"].firstMatch.exists,
                       "asked again for a box it had already been given")
    }

    /// Waits for the focus engine to actually land on an element.
    private func focused(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.hasFocus { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return false
    }
}

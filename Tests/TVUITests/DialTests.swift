import XCTest

/// Remote behaviour cannot be checked any other way from a terminal — there is no simctl
/// verb for a Siri Remote press, and the clickpad is this app's only control surface.
final class DialTests: XCTestCase {

    private enum ID {
        static let channelNumber = "tub3.channel.tuned"
    }

    private func launched() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += Harness.quiet
        app.launch()
        // Past the walk from .idle through .tuning, which rebuilds the tree next to the only
        // focusable view on screen — and past a slate, which used to read as settled while a
        // retry was armed behind it. `Harness.settled` also waits for something to hold
        // focus, which is the condition a press actually needs and the one every
        // intermittent failure in this class turned out to be missing.
        Harness.settled(app)
        return app
    }

    /// Poll rather than use `expectation(for:evaluatedWith:)`: the KVO-based form requires
    /// sending the test case across a concurrency boundary, which Swift 6 refuses.
    ///
    /// Fifteen seconds, and it is deliberately not forty. The number on screen is written
    /// the moment the button is handled — `tune` sets `current` before it awaits anything,
    /// because a television's ident keeps up with the thumb while its tuner cannot — so the
    /// only thing a long wait here buys is a slower report of a press that was lost. The
    /// waiting for a *picture* is `Harness.settled`'s job and has its own, longer, budget.
    @discardableResult
    private func waitForChannel(_ app: XCUIApplication,
                                timeout: TimeInterval = 15,
                                until matches: (String) -> Bool) -> String? {
        let label = app.staticTexts[ID.channelNumber]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if label.exists {
                let value = label.label
                if matches(value) { return value }
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return nil
    }

    /// The suite's own hermeticity, asserted rather than assumed — and the app's opening
    /// channel with it.
    ///
    /// Every other test here starts from a known place because `-tub3ForgetChannel` throws
    /// away what the last one left behind. That is load-bearing, and it fails silently: a
    /// flag that quietly does nothing puts the suite straight back to inheriting a channel
    /// from whichever test happened to run before it, which is how four consecutive runs
    /// came to fail parked on the same station. Not a hypothetical — the scheme's
    /// `skippedTests` had precisely that fault at precisely that time, and had been running
    /// the photography aids in the gate for as long as the comment said it was not.
    ///
    /// The second launch names no channel on purpose. That is the only way to see what the
    /// app chooses for itself: with nothing remembered it must open on ambiance, the way a
    /// set switched on does, rather than on wherever the last run was left.
    func testALaunchInheritsNothingFromTheOneBefore() throws {
        let app = launched()
        let opened = try XCTUnwrap(waitForChannel(app) { !$0.isEmpty })
        XCTAssertEqual(Int(opened), Harness.home, "did not open where it was told to")

        XCUIRemote.shared.press(.up)
        let moved = try XCTUnwrap(waitForChannel(app) { $0 != opened && !$0.isEmpty },
                                  "up did not move off \(opened)")
        app.terminate()

        let again = XCUIApplication()
        again.launchArguments += ["-tub3Mute", "-tub3ForgetChannel"] + Harness.box
        again.launch()
        let reopened = try XCTUnwrap(Harness.tuned(again))
        XCTAssertEqual(Int(reopened), Harness.home,
                       "came back on \(reopened) — \(moved) is where the last run was left, "
                       + "so the channel memory was inherited rather than cleared")
    }

    func testTunesToAChannelOnLaunch() throws {
        let app = launched()
        let channel = waitForChannel(app) { !$0.isEmpty }
        XCTAssertNotNil(channel, "no channel bug appeared — did it tune at all?")
    }

    func testClickpadUpChangesChannel() throws {
        let app = launched()
        let before = try XCTUnwrap(waitForChannel(app) { !$0.isEmpty })

        XCUIRemote.shared.press(.up)

        let after = waitForChannel(app) { $0 != before && !$0.isEmpty }
        XCTAssertNotNil(after, "clickpad up did not change the channel from \(before)")
    }

    func testClickpadDownReturnsToWhereItStarted() throws {
        let app = launched()
        let before = try XCTUnwrap(waitForChannel(app) { !$0.isEmpty })

        XCUIRemote.shared.press(.up)
        XCTAssertNotNil(waitForChannel(app) { $0 != before && !$0.isEmpty },
                        "up did not move off \(before)")

        XCUIRemote.shared.press(.down)
        XCTAssertNotNil(waitForChannel(app) { $0 == before },
                        "down did not come back to \(before)")
    }
}

extension DialTests {
    /// The channel strip: it must open, land on the channel you are watching, and let you
    /// jump somewhere far away without clicking through everything in between.
    func testDialOpensAndJumps() throws {
        let app = launched()
        let before = try XCTUnwrap(waitForChannel(app) { !$0.isEmpty })

        XCUIRemote.shared.press(.playPause)
        // Query a channel button rather than the container: a SwiftUI stack with an
        // identifier is not necessarily an accessibility element, but a Button always is.
        let anyChannelButton = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'tub3.dial.'")).firstMatch
        if !anyChannelButton.waitForExistence(timeout: 10) {
            XCTFail("the channel strip did not open. On screen: "
                    + app.debugDescription.prefix(2000))
        }

        // Walk a few along and pick, which is the point of the strip — reaching a distant
        // channel without pressing up eleven times.
        for _ in 0 ..< 3 { XCUIRemote.shared.press(.right); Thread.sleep(forTimeInterval: 0.4) }
        XCUIRemote.shared.press(.select)

        let after = waitForChannel(app) { $0 != before && !$0.isEmpty }
        XCTAssertNotNil(after, "picking from the strip did not change channel from \(before)")
    }

    /// Menu must close the strip, not quit to the tvOS home screen.
    func testMenuClosesTheStripRatherThanTheApp() throws {
        let app = launched()
        _ = waitForChannel(app) { !$0.isEmpty }

        XCUIRemote.shared.press(.playPause)
        let anyChannelButton = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'tub3.dial.'")).firstMatch
        XCTAssertTrue(anyChannelButton.waitForExistence(timeout: 10))

        XCUIRemote.shared.press(.menu)
        Thread.sleep(forTimeInterval: 1.5)

        XCTAssertEqual(app.state, .runningForeground, "Menu quit the app instead of closing the strip")
        XCTAssertFalse(anyChannelButton.exists, "the strip is still open")
    }
}

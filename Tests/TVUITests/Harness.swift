import XCTest

/// What every UI test has to say to the app before it will show a picture, and what it has
/// to wait for before pressing anything.
enum Harness {
    /// The box to point the app at, as launch arguments.
    ///
    /// Necessary since the address stopped being a compile-time constant: with no box
    /// remembered a fresh install lands on the setup screen, so a suite that just launched
    /// and waited for a channel number would wait forty seconds and fail — and would have
    /// been *right* to. It is passed as an argument rather than left to whatever a previous
    /// run happened to save, which is what makes a run hermetic.
    ///
    /// `TEST_RUNNER_TUB3_BOX` in the caller's environment arrives here as `TUB3_BOX`:
    /// xcodebuild forwards variables with that prefix to the test runner and strips it. The
    /// default is the name the box advertises, so `make uitest` needs nothing set.
    static var box: [String] {
        let url = ProcessInfo.processInfo.environment["TUB3_BOX"] ?? "http://boobtube.local:8008"
        return ["-tub3Box", url]
    }

    /// The channel every test starts on unless it says otherwise.
    ///
    /// Ambiance, and for the box's own reason: it is the one channel with no schedule, no
    /// catalogue and nothing to go wrong, so it is the one that reliably has a picture at
    /// four in the afternoon and at four in the morning. Pinning it is what stops the suite
    /// depending on what a live schedule happens to be doing — a channel that is off air, or
    /// that `tub3-build.service` is mid-rebuild on, puts the app on a slate, and a test that
    /// expects a picture then fails for reasons that have nothing to do with the app.
    static let home = 13

    /// Mute, the box, a cleared channel memory, and a known channel to open on.
    ///
    /// `-tub3ForgetChannel` is the load-bearing half. `lastWatched` is written on every
    /// picture that arrives, so without it each test opened on whatever channel the test
    /// before it left behind — inherited state, from a live schedule, decided by test
    /// ordering. Four consecutive runs of this suite all failed parked on channel 17 for
    /// exactly that reason.
    static var quiet: [String] {
        ["-tub3Mute", "-tub3ForgetChannel", "-tub3Channel", "\(home)"] + box
    }

    /// The same, opening somewhere else. For the tests whose subject is a particular channel.
    static func quiet(on channel: Int) -> [String] {
        ["-tub3Mute", "-tub3ForgetChannel", "-tub3Channel", "\(channel)"] + box
    }

    /// The app can actually receive a button. **The precondition for every press.**
    ///
    /// tvOS routes a remote press by focus, so a screen with nothing focused swallows
    /// everything silently — there is no error, no callback, and the app carries on looking
    /// perfectly healthy. That is not a hypothetical: measured on a cold launch, one run in
    /// four came up with the invisible SELECT button in the tree, enabled, and unfocused,
    /// and then ignored four play/pause presses over seventeen seconds while playing a
    /// picture. Every flaky failure in this suite was one of those, and every one of them
    /// was recorded as a fault in whatever the test pressed.
    ///
    /// The app now keeps hold of focus itself — `TunerScreen` has a watchdog — so this is a
    /// short wait for that to land, not a workaround for its absence. It is also the
    /// assertion that the watchdog works: if focus never arrives, the suite says so here
    /// rather than forty seconds later somewhere unrelated.
    @discardableResult
    static func responsive(_ app: XCUIApplication, timeout: TimeInterval = 20,
                           file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let select = app.buttons["tub3.select"]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if select.exists, select.hasFocus { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTFail("nothing on screen holds focus after \(timeout)s, so the remote is dead. "
                + "On screen: \(app.debugDescription.prefix(1500))", file: file, line: line)
        return false
    }

    /// The app has actually tuned, not merely drawn a placeholder.
    ///
    /// `tub3.channel.tuned` is unconditional in the view tree and its label is empty until
    /// the first tune, so `waitForExistence` alone returns the instant the screen appears and
    /// says nothing. Only `DialTests` checked the label, and it was right to.
    @discardableResult
    static func tuned(_ app: XCUIApplication, timeout: TimeInterval = 40,
                      file: StaticString = #filePath, line: UInt = #line) -> String {
        label(app.staticTexts["tub3.channel.tuned"], timeout: timeout,
              what: "never tuned", file: file, line: line)
    }

    /// A picture is up, nothing is pending behind it, and the remote works.
    ///
    /// The one gate a test should use before pressing anything. `tub3.settled` is only
    /// `.playing` and the guide now — the two states the app will sit in with nothing armed
    /// — where it used to include a slate and "no signal", both of which have a retry behind
    /// them that rebuilds the screen a few seconds later. A suite released into one of those
    /// is pressing buttons at a moving target: measured, a run reported settled 3.0s after
    /// launch on a slate and did not reach a picture until 10s.
    ///
    /// Forty-five seconds because a cold launch legitimately takes that long against a real
    /// box: the app must ask for the dial, ask for the Plex address, resolve the programme
    /// through Plex, and wait for AVFoundation to report the item ready before the state
    /// becomes `.playing` — four round trips, one of them a transcode start. Measured cold
    /// launches on this box run 5–10s; the margin is for a box that is still waking up.
    @discardableResult
    static func settled(_ app: XCUIApplication, timeout: TimeInterval = 45,
                        file: StaticString = #filePath, line: UInt = #line) -> String {
        let reached = label(app.staticTexts["tub3.settled"], timeout: timeout,
                            what: stuck(app), file: file, line: line)
        responsive(app, file: file, line: line)
        return reached
    }

    /// What the app says it is doing, for a message that names the actual problem.
    static func state(_ app: XCUIApplication) -> String {
        let element = app.staticTexts["tub3.state"]
        return element.exists ? element.label : "unknown"
    }

    /// Why the app never reached a picture, in one line and in the right direction.
    ///
    /// The point of a gate is that going red tells somebody where to look, and three of
    /// these states are not the app's fault at all — a channel that is off air, a box that
    /// is rebooting, a Plex server nobody has configured yet. Left as "never settled within
    /// 45s" they were indistinguishable from a bug in the thing under test, which is how a
    /// suite that depends on a live box quietly stops being read.
    private static func stuck(_ app: XCUIApplication) -> String {
        let now = state(app)
        let because = switch now {
        case "slate":
            "the box has no picture for this channel — off air, or mid-rebuild. "
            + "`tub3-build.service` rewrites a station's blocks in place, and this is what "
            + "that looks like from here"
        case "broken": "the box is not answering. Check it is up and on this network"
        case "standby": "the box is up but has no Plex server configured on it yet"
        case "tuning", "idle":
            "the app is still starting — the box, Plex, or the transcoder is slow to answer"
        default: "the app is in a state this harness does not know about"
        }
        return "never reached a picture: the app is on '\(now)' — \(because)"
    }

    /// `what` is an autoclosure so the message can name the state the app was actually
    /// stuck in, read at the moment it gave up rather than before the wait began.
    private static func label(_ element: XCUIElement, timeout: TimeInterval,
                              what: @autoclosure () -> String,
                              file: StaticString, line: UInt) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists, !element.label.isEmpty { return element.label }
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTFail("\(what()) within \(timeout)s", file: file, line: line)
        return ""
    }
}

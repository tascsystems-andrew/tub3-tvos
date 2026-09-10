import XCTest

/// What every UI test has to say to the app before it will show a picture.
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

    /// Mute, plus the box. The suite's usual opening line.
    static var quiet: [String] { ["-tub3Mute"] + box }

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

    /// The tuner has reached a state it will sit in — past the .idle to .tuning to .playing
    /// walk that rebuilds the tree next to the screen's only focusable view. Replaces the
    /// guessed four-second sleeps.
    @discardableResult
    static func settled(_ app: XCUIApplication, timeout: TimeInterval = 45,
                        file: StaticString = #filePath, line: UInt = #line) -> String {
        label(app.staticTexts["tub3.settled"], timeout: timeout,
              what: "never settled", file: file, line: line)
    }

    private static func label(_ element: XCUIElement, timeout: TimeInterval, what: String,
                              file: StaticString, line: UInt) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists, !element.label.isEmpty { return element.label }
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTFail("\(what) within \(timeout)s", file: file, line: line)
        return ""
    }
}

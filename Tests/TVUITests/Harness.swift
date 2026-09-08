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
}

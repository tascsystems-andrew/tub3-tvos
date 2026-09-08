import Foundation
import XCTest

/// Where the box is, for the probes that need a real one.
///
/// From the environment rather than a literal: these are opt-in tests that talk to somebody's
/// actual television, and which television that is has no business being in a public
/// repository. Falls back to the mDNS name a box answers to out of the box.
///
///     TUB3_BOX=http://myhost:8008 swift test --package-path Core --filter LiveChannelProbe
enum LiveTarget {
    /// Whether the probes are allowed to touch the network at all.
    ///
    /// They were not gated on anything, so `make core` — advertised in the Makefile as "the
    /// fast loop — no simulator, seconds" — spent three minutes timing out against a box
    /// that is not on every machine, and then reported failure. Opt-in tests have to be
    /// opt-in or the fast loop stops being run.
    static var enabled: Bool { ProcessInfo.processInfo.environment["TUB3_LIVE"] == "1" }

    /// Skips the calling test unless the live suite was asked for.
    static func required(_ file: StaticString = #filePath, _ line: UInt = #line) throws {
        try XCTSkipUnless(enabled,
                          "live probe: set TUB3_LIVE=1 (and TUB3_BOX) to run it",
                          file: file, line: line)
    }

    static var box: URL {
        let raw = ProcessInfo.processInfo.environment["TUB3_BOX"] ?? "http://tub3.local:8008"
        return URL(string: raw) ?? URL(string: "http://tub3.local:8008")!
    }
}

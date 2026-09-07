import Foundation

/// Where the box is, for the probes that need a real one.
///
/// From the environment rather than a literal: these are opt-in tests that talk to somebody's
/// actual television, and which television that is has no business being in a public
/// repository. Falls back to the mDNS name a box answers to out of the box.
///
///     TUB3_BOX=http://myhost:8008 swift test --package-path Core --filter LiveChannelProbe
enum LiveTarget {
    static var box: URL {
        let raw = ProcessInfo.processInfo.environment["TUB3_BOX"] ?? "http://tub3.local:8008"
        return URL(string: raw) ?? URL(string: "http://tub3.local:8008")!
    }
}

import XCTest
@testable import Tub3Core

/// The launch flag that makes a run start where it says it starts.
///
/// Worth its own test because the failure is silent in both directions: a flag that does
/// nothing leaves a suite inheriting a channel from the test before it — which is what made
/// four consecutive runs of the tvOS suite fail parked on channel 17 — and a flag that fires
/// when it should not throws away a viewer's Start-on preference on an ordinary launch.
@MainActor
final class ForgetChannelTests: XCTestCase {

    /// A domain of its own, so the machine's real preferences are never touched.
    private func scratch(_ name: String = #function) -> UserDefaults {
        let suite = "tub3.tests.\(name)"
        UserDefaults().removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }

    func testTheFlagClearsBothChannelMemories() {
        let defaults = scratch()
        defaults.set(9, forKey: Tuner.lastWatchedKey)
        defaults.set(6, forKey: Tuner.startOnKey)

        Tuner.forgetChannelIfAsked(["Tub3TV", "-tub3ForgetChannel"], defaults: defaults)

        XCTAssertNil(defaults.object(forKey: Tuner.lastWatchedKey))
        XCTAssertNil(defaults.object(forKey: Tuner.startOnKey))
    }

    /// Forgetting the box forgets the channel too: a launch that starts from nothing starts
    /// from nothing.
    func testForgettingTheBoxAlsoForgetsTheChannel() {
        let defaults = scratch()
        defaults.set(9, forKey: Tuner.lastWatchedKey)

        Tuner.forgetChannelIfAsked(["Tub3TV", "-tub3Forget"], defaults: defaults)

        XCTAssertNil(defaults.object(forKey: Tuner.lastWatchedKey))
    }

    /// An ordinary launch keeps both. The set comes back on the channel it went off on,
    /// which is the whole point of remembering it.
    func testAnOrdinaryLaunchKeepsThem() {
        let defaults = scratch()
        defaults.set(9, forKey: Tuner.lastWatchedKey)
        defaults.set(6, forKey: Tuner.startOnKey)

        Tuner.forgetChannelIfAsked(["Tub3TV", "-tub3Mute", "-tub3Box", "http://box:8008"],
                                   defaults: defaults)

        XCTAssertEqual(defaults.integer(forKey: Tuner.lastWatchedKey), 9)
        XCTAssertEqual(defaults.integer(forKey: Tuner.startOnKey), 6)
    }
}

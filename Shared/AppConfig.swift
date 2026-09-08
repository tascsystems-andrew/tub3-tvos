import Foundation
import Tub3Core

enum AppConfig {
    /// Where the chosen box is remembered.
    static let savedKey = "tub3.box"
    /// The launch override, for tests and for reproducing a fault on one box.
    ///
    /// A *different* key from the saved one, deliberately. With a single key the setup
    /// screen's save would appear to succeed and change nothing any read would ever see, for
    /// as long as an override was being passed — which under `make uitest` is every run.
    static let overrideKey = "tub3Box"

    /// The box, or nobody has chosen one yet.
    ///
    /// Was a compile-time constant naming one person's Pi. Everything else the app needs is
    /// discovered *from* the box at runtime, so this single value was the whole of the
    /// configuration problem — and nil is what puts the setup screen on screen.
    static var boxURL: URL? {
        // A launch that starts from nothing, which is otherwise impossible to arrange: the
        // setup screen only appears on a box the app has never been told about, and a
        // simulator that has run the suite once has been told. Not `-tub3Box ""` — an
        // unparseable override falls through to the saved key, so an empty one would quietly
        // test the opposite of what it looks like.
        if ProcessInfo.processInfo.arguments.contains("-tub3Forget") { return nil }
        let defaults = UserDefaults.standard
        // The argument domain outranks the persistent one, so a launch override also makes a
        // test run hermetic regardless of what a previous run saved.
        if let raw = defaults.string(forKey: overrideKey), let url = BoxAddress.parse(raw) {
            return url
        }
        if let raw = defaults.string(forKey: savedKey) { return BoxAddress.parse(raw) }
        return nil
    }

    static func remember(_ url: URL) {
        UserDefaults.standard.set(url.absoluteString, forKey: savedKey)
    }

    static func forget() {
        UserDefaults.standard.removeObject(forKey: savedKey)
    }

    /// Stable for the life of the install: Plex uses it to tell one client from another, and
    /// a fresh one on every launch would litter the server with strangers.
    static let clientID: String = {
        let key = "tub3.clientID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let minted = "tub3-appletv-" + UUID().uuidString.prefix(8).lowercased()
        UserDefaults.standard.set(minted, forKey: key)
        return minted
    }()
}

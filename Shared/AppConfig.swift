import Foundation

enum AppConfig {
    /// The box. A hostname rather than an IP literal on purpose — App Transport Security
    /// treats the two differently, and a `.local` name also survives the Pi changing address.
    static let boxURL = URL(string: "http://boobtube:8008")!

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

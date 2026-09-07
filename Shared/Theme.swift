import SwiftUI

/// The box's own palette, so the app and the television look like the same channel.
public enum Theme {
    public static let ink = Color(red: 0.047, green: 0.043, blue: 0.039)
    public static let gold = Color(red: 1.0, green: 0.784, blue: 0.235)
    public static let purple = Color(red: 0.659, green: 0.361, blue: 0.965)
    public static let dim = Color(red: 0.541, green: 0.514, blue: 0.471)

    /// The furniture green, `&H55FF33&` in the box's ASS overlays.
    ///
    /// Everything the box draws *over the picture* is this: the channel bug, the
    /// tuning card, the off-air card, the menu. Gold and purple are for the guide and
    /// the settings page. `tuner/menu.py` says why it is green rather than amber —
    /// green tubes were far more common on 90s CRTs.
    public static let phosphor = Color(red: 0.2, green: 1.0, blue: 0.333)
    /// The episode line under a programme name, `&HAAAAAA&`.
    public static let bugDetail = Color(red: 0.667, green: 0.667, blue: 0.667)
}

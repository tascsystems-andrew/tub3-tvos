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
    /// Furniture is monospace, the way the box draws every overlay it has.
    ///
    /// Not a stylistic preference on either side. `\fnmonospace` is on the bug, the
    /// tuning card, the off-air card, the menu and every string in the guide — because
    /// a channel number that changes width as it counts, or a clock whose colon shifts
    /// every second, reads as a web page rather than as a television. SF Rounded is a
    /// friendly UI face; this furniture is imitating a character generator.
    public static func furniture(_ size: CGFloat,
                                 _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// The episode line under a programme name, `&HAAAAAA&`.
    public static let bugDetail = Color(red: 0.667, green: 0.667, blue: 0.667)
}

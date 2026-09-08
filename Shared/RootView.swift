import SwiftUI
import Tub3Core

/// Owns which box the app is talking to.
///
/// The Tuner is built *after* a box is chosen, not before. Both apps used to construct it in
/// a `@State` initialiser, which meant the address had to exist before SwiftUI had rendered
/// anything — fine for a compile-time constant naming one person's Pi, impossible for a
/// choice someone makes on screen.
struct RootView: View {
    /// A remembered box is built here, in the initialiser, and not in a `.task`. The
    /// difference is a frame: a `.task` would put the setup screen up first and take it away
    /// again, so every launch after the first would flash a "looking for your television"
    /// card at someone whose television was never lost.
    @State private var tuner: Tuner? = {
        guard let url = AppConfig.boxURL else { return nil }
        return RootView.build(url)
    }()

    var body: some View {
        Group {
            if let tuner {
                TunerScreen(tuner: tuner, onChangeBox: changeBox)
                    // Identity, so choosing a different box tears the old screen down rather
                    // than leaving a dead AVPlayer layer attached to a new Tuner.
                    .id(ObjectIdentifier(tuner))
            } else {
                SetupScreen { chosen in
                    AppConfig.remember(chosen)
                    tuner = RootView.build(chosen)
                }
            }
        }
    }

    private func changeBox() {
        AppConfig.forget()
        tuner = nil
    }

    private static func build(_ url: URL) -> Tuner {
        Tuner(box: BoxClient(base: url), engine: PlayerEngine(), clientID: AppConfig.clientID)
    }
}

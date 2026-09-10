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

    @Environment(\.scenePhase) private var scenePhase

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
        .onChange(of: scenePhase) { _, phase in phaseChanged(phase) }
    }

    /// Leaving the app releases the Plex session.
    ///
    /// Menu from the top level backgrounds this app, and tvOS may kill it outright afterwards
    /// — at which point nothing gets a chance to tidy up. Plex does not reap a session whose
    /// client vanished, so without this every exit mid-programme leaves a transcoder running
    /// on the server for somebody else's stream to queue behind.
    private func phaseChanged(_ phase: ScenePhase) {
        guard phase != .active, let tuner else { return }
        Task { await tuner.release() }
    }

    private func changeBox() {
        AppConfig.forget()
        tuner = nil
    }

    private static func build(_ url: URL) -> Tuner {
        Tuner(box: BoxClient(base: url), engine: PlayerEngine(), clientID: AppConfig.clientID)
    }
}

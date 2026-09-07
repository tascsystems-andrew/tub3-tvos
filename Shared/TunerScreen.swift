import SwiftUI
import Tub3Core

/// The whole app: one full-screen channel, and the means to change it.
public struct TunerScreen: View {
    @State private var tuner: Tuner
    @State private var showingDial = false

    public init(tuner: Tuner) { _tuner = State(initialValue: tuner) }

    public var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()

            switch tuner.state {
            case .idle:
                ProgressView().tint(Theme.gold)
            case .broken(let why):
                SlateView(channel: 0, station: "8008TUB3", message: why)
            case .slate(let channel, let station, let message):
                SlateView(channel: channel, station: station, message: message)
            case .guideChannel(let channel, let station):
                GuideChannelView(guide: tuner.guide, channel: channel, station: station,
                                 startedAt: tuner.guideStartedAt)
            case .tuning(let channel, let station):
                SlateView(channel: channel, station: station, message: "tuning…")
            case .playing:
                PlayerLayerView(player: tuner.player.player).ignoresSafeArea()
            }

            // The bug stays in the view tree and only its opacity changes. Removing it would
            // also remove it from the accessibility tree, and that tree is the only way a
            // test can read which channel is tuned.
            if case .playing(let channel, let station, let title, _) = tuner.state {
                // Full frame: the bug places its own two blocks, top right and bottom right,
                // because that separation is the whole design and not this screen's business.
                ChannelBugView(channel: channel, station: station, title: title,
                               remaining: tuner.nowEntry?.remainingSeconds ?? 0)
                    .opacity(tuner.bugVisible ? 1 : 0)
            }

            if showingDial {
                DialOverlay(channels: tuner.channels, current: tuner.current) { picked in
                    showingDial = false
                    Task { await tuner.tune(to: picked) }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(2)
            }

        }
        .animation(.easeInOut(duration: 0.4), value: tuner.bugVisible)
        .animation(.easeOut(duration: 0.25), value: showingDial)
        .task { await tuner.start() }
        #if os(tvOS)
        // Three routes, and each is the one that verifiably works rather than the one that
        // reads best.
        //
        // `.focusable()` is what makes move commands arrive at all: tvOS routes them through
        // the focus engine, and this screen is a video layer with no buttons, so without it
        // the remote is simply dead.
        //
        // The channel strip is on PLAY/PAUSE, not the centre click. Centre click looks
        // obvious and has no reliable SwiftUI route here — `.onTapGesture` is an iOS idiom
        // that never fires from a clickpad, wrapping the screen in a `Button` does work and
        // collapses the whole view tree into one accessibility element, and a first-responder
        // UIView never received the presses at all. Play/pause is a real physical button, it
        // is what a set-top box uses for its banner, and it is verified by a test.
        .focusable(!showingDial)
        .onMoveCommand { direction in
            guard !showingDial else { return }
            switch direction {
            case .up: Task { await tuner.channelUp() }
            case .down: Task { await tuner.channelDown() }
            default: break
            }
        }
        .onPlayPauseCommand { withAnimation { showingDial.toggle() } }
        // Menu closes the strip. Deliberately not swallowed when the strip is already shut,
        // so Menu still leaves the app — one that cannot be exited is a broken tvOS app.
        .onExitCommand {
            if showingDial { withAnimation { showingDial = false } }
        }
        #endif
    }
}

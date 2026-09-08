import SwiftUI
import Tub3Core

/// The whole app: one full-screen channel, and the means to change it.
public struct TunerScreen: View {
    @State private var tuner: Tuner
    @State private var showingDial = false
    /// A route back to the box picker. Nil in the previews and the Core tests, where there
    /// is nothing to go back to.
    private let onChangeBox: (() -> Void)?

    public init(tuner: Tuner, onChangeBox: (() -> Void)? = nil) {
        _tuner = State(initialValue: tuner)
        self.onChangeBox = onChangeBox
    }

    public var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()

            switch tuner.state {
            case .idle:
                ProgressView().tint(Theme.gold)
            case .standby(let headline, let detail, let address):
                StandbyCard(headline: headline, detail: detail, address: address)
            case .broken(let why):
                SlateView(channel: 0, station: "8008TUB3", message: why)
            case .slate(let channel, let station, let message):
                SlateView(channel: channel, station: station, message: message)
            case .guideChannel(let channel, let station):
                GuideChannelView(guide: tuner.guide, channel: channel, station: station,
                                 startedAt: tuner.guideStartedAt)
            case .tuning, .playing:
                // The picture stays up while tuning. A television does not blank when you
                // press a channel button — it keeps showing what it has and writes the new
                // number over the top, which is what makes surfing feel instant even though
                // the tuner behind it plainly is not. The box says so in its own docstring;
                // this screen used to replace the picture with a card that said "tuning…",
                // which is the one thing a television never does.
                PlayerLayerView(player: tuner.player.player).ignoresSafeArea()
            }

            // What is tuned, always, drawn nowhere.
            //
            // The bug cannot carry this. It fades to nothing four seconds after tuning, and
            // UIKit drops a view at zero alpha out of the accessibility tree altogether — so
            // "wait for a channel number" found nothing whenever tuning took longer than
            // that window, which on a cold launch it routinely does. Three tests failed that
            // way and every one of them blamed the tuner, which had in fact tuned. A hair
            // above zero keeps it in the tree and off the screen.
            Text(tuner.current.map { String(format: "%02d", $0) } ?? "")
                .accessibilityIdentifier("tub3.channel.tuned")
                .frame(width: 1, height: 1)
                .opacity(0.02)

            // The bug's own identifier stays on the bug, because what it is for is asserting
            // that the ident was *drawn* — which is a different question from what is tuned.
            switch tuner.state {
            case .playing(let channel, let station, let title, _):
                // Full frame: the bug places its own two blocks, top right and bottom right,
                // because that separation is the whole design and not this screen's business.
                ChannelBugView(channel: channel, station: station, title: title,
                               remaining: tuner.nowEntry?.remainingSeconds ?? 0)
                    .opacity(tuner.bugVisible ? 1 : 0)
            case .tuning(let channel, let station):
                // The same ident, with nothing under it yet — the number is the whole point
                // of it while a thumb is still moving.
                ChannelBugView(channel: channel, station: station)
            default:
                EmptyView()
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
        .onPlayPauseCommand {
            // With no channels there is no strip to open, and the button would do nothing at
            // all — which on a screen already saying "no signal" reads as a dead remote. So
            // it goes back to the picker instead: the cheapest correct gesture out of a
            // wrong or stale address, and the only one, since Menu deliberately leaves the
            // app rather than being swallowed here.
            if tuner.channels.isEmpty, let onChangeBox {
                onChangeBox()
            } else {
                withAnimation { showingDial.toggle() }
            }
        }
        // Menu closes the strip. Deliberately not swallowed when the strip is already shut,
        // so Menu still leaves the app — one that cannot be exited is a broken tvOS app.
        .onExitCommand {
            if showingDial { withAnimation { showingDial = false } }
        }
        #endif
    }
}

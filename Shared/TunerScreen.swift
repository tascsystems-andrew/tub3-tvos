import SwiftUI
import Tub3Core

/// The whole app: one full-screen channel, and the means to change it.
public struct TunerScreen: View {
    @State private var tuner: Tuner

    /// One state, not a boolean per overlay.
    ///
    /// "The tuner screen must not steal up and down while something is up" becomes a
    /// structural guarantee in one switch, rather than a guard the next overlay's author has
    /// to remember. It also bounds Menu at two presses from the Home screen, because opening
    /// one overlay closes the other by construction.
    private enum Overlay { case none, dial, menu }
    @State private var overlay: Overlay = .none
    /// So the SELECT button is focused from the first frame rather than whenever the engine
    /// gets round to it. Without this the screen has exactly one focus candidate and still
    /// takes an indeterminate moment to focus it, and every press that lands in that gap is
    /// simply lost — which showed up as tests timing out at forty seconds, passing alone,
    /// and failing on a different test each run.
    @Namespace private var focusScope
    // The focus engine itself, which is the one thing an iPad genuinely does not have.
    // `resetFocus`, `focusScope` and `prefersDefaultFocus` are all tvOS-only, and the first
    // of them was left unguarded when it landed — so `make phone` has not compiled since,
    // and nothing said so because nothing in the loop builds that target.
    #if os(tvOS)
    /// Re-resolves focus inside the namespace. Needed even though the SELECT button now
    /// stays in the tree: closing an overlay leaves focus on rows that have just gone, and
    /// without this the menu reopened two times in three.
    @Environment(\.resetFocus) private var resetFocus
    /// Whether the invisible SELECT button is actually holding focus — the sensor the
    /// watchdog below reads. Not a preference: this is the app finding out, from the focus
    /// engine, whether anything on this screen can receive a button at all.
    @FocusState private var selectFocused: Bool
    #endif

    /// Built fresh on every open, because every value on it is a fact about right now.
    @State private var menu = MenuModel(root: { MenuScreen(title: "SETUP", items: []) })
    /// Nil until the box answers. The screen says "checking…" rather than going blank.
    @State private var health: BoxHealth?
    /// A route back to the box picker. Nil in the previews and the Core tests, where there
    /// is nothing to go back to.
    private let onChangeBox: (() -> Void)?

    public init(tuner: Tuner, onChangeBox: (() -> Void)? = nil) {
        _tuner = State(initialValue: tuner)
        self.onChangeBox = onChangeBox
    }

    /// What is on, for the strip under the panel. Suppressed on the guide channel, where the
    /// listings are the picture and a line saying what is on would be furniture on furniture.
    private var nowLine: String? {
        if case .guideChannel = tuner.state { return nil }
        guard let channel = tuner.current, tuner.nowEntry != nil else { return nil }
        let station = tuner.channels.first { $0.channel == channel }?.station ?? ""
        let bits = tuner.featureTitle.components(separatedBy: " — ")
        var parts = [String(format: "CH %02d", channel), station]
        parts += bits.filter { !$0.isEmpty }
        let minutes = Int(tuner.featureRemaining / 60)
        if minutes > 0 { parts.append("\(minutes) min left") }
        return parts.filter { !$0.isEmpty }.joined(separator: "   ·   ")
    }

    /// Nothing more is about to change shape, *by itself*.
    ///
    /// `tub3.channel.tuned` goes non-empty when a tune *begins* — the same turn the state
    /// becomes `.tuning`, before the settle window and before Plex has been asked anything.
    /// It says a channel number exists, not that a picture is up, and the difference is the
    /// window in which the tree is rebuilt under whatever holds focus. The 4-second sleeps in
    /// the tests were guessing at this.
    ///
    /// Only the two states nothing is pending behind. This used to be everything except
    /// `.idle` and `.tuning`, which quietly included the three states the app is *retrying*
    /// from: a slate has a `retry` armed, and `.broken` and `.standby` each have a backoff
    /// ladder that will re-ask the box and then tune. A suite told "ready" on one of those
    /// was handed a screen that would rebuild itself a few seconds later, and it read the
    /// resulting mess as a fault in whatever it pressed. Measured: a run that reported
    /// settled 3.0s after launch was on a slate, and did not reach a picture until 10s.
    private var settled: Bool {
        switch tuner.state {
        case .playing, .guideChannel: true
        case .idle, .tuning, .slate, .standby, .broken: false
        }
    }

    /// The state, by name, for a test to wait on the one it actually needs.
    private var stateName: String {
        switch tuner.state {
        case .idle: "idle"
        case .tuning: "tuning"
        case .playing: "playing"
        case .guideChannel: "guide"
        case .slate: "slate"
        case .standby: "standby"
        case .broken: "broken"
        }
    }

    private func rebuildMenu() {
        let wasOpen = menu.isOpen
        menu = MenuModel(root: {
            MenuTree.root(tuner: tuner, health: health, onChangeBox: onChangeBox,
                          onStartOn: { pick in
                              let defaults = UserDefaults.standard
                              if let pick { defaults.set(pick, forKey: Tuner.startOnKey) }
                              else { defaults.removeObject(forKey: Tuner.startOnKey) }
                          })
        })
        menu.open()
        _ = wasOpen
    }

    public var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()

            // SELECT, and it has to be a Button because a Button is what the focus engine
            // presses. The three attempts recorded below all failed the same way: they tried
            // to catch a press on a view the engine was not pressing.
            //
            // A CHILD of this ZStack and a SIBLING of the content, never a wrapper. Wrapping
            // does work for input and collapses the whole view tree into one accessibility
            // element, taking `tub3.channel.tuned`, the ident and the strip with it. A
            // sibling encloses nothing, and being a child keeps this ZStack an ancestor of
            // whatever holds focus — which is what keeps the move and play/pause handlers
            // below firing.
            //
            // Present-or-absent rather than merely unfocusable: `.focusable(false)` is for
            // bare views, while a Button takes its focusability from the control, so the
            // modifier is a hope and taking it out of the tree is a guarantee.
            //
            // `Color.clear`, never `.opacity(0)` — UIKit refuses focus to an alpha-zero view
            // and drops it out of the accessibility tree, which is the fault that cost a
            // morning on the channel bug. And no `.contentShape`: that defines a hit-test
            // region, and nothing here hit-tests. A UIPress is routed by focus, which is
            // exactly why `.onTapGesture` never fired.
            #if os(tvOS)
            // Always in the tree, disabled rather than removed.
            //
            // It used to be `if overlay == .none { … }`, on the reasoning that a Button takes
            // its focusability from the control so removing it is a guarantee where
            // `.focusable(false)` is only a hope. True, and it cost more than it bought: a
            // view that leaves the tree and comes back has no identity across the gap, the
            // engine has no reason to focus it again, and the menu opened once per launch.
            // `resetFocus` on the way back fixed that two times in three, which is not a fix.
            //
            // `.disabled` is a real control-level property and is respected — a disabled
            // Button is not a focus candidate, so an overlay's own rows take focus while one
            // is up — and the view keeps its identity throughout, so there is no gap to
            // recover from.
            // Populate it BEFORE inserting it, not after. `rebuildMenu()` used to run from
            // `.onChange(of: overlay)`, one update later — so MenuOverlay first appeared bound
            // to the empty placeholder above, its ForEach produced no rows at all, and for
            // that update the whole app had zero focus candidates: this Button had just been
            // disabled and the rows did not exist yet. Focus went nowhere, and the
            // `@FocusState` write arriving with the rows a frame later raced their
            // registration and was dropped. The dial never had this problem because its cards
            // exist on the frame it is inserted — which is what proves the transition and the
            // alpha are innocent.
            Button { rebuildMenu(); withAnimation { overlay = .menu } } label: { Color.clear }
                .buttonStyle(.plain)
                .disabled(overlay != .none)
                .focused($selectFocused)
                .prefersDefaultFocus(in: focusScope)
                .accessibilityLabel("Setup")
                .accessibilityIdentifier("tub3.select")
            #endif

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

            Text(settled ? "ready" : "")
                .accessibilityIdentifier("tub3.settled")
                .frame(width: 1, height: 1)
                .opacity(0.02)

            Text(stateName)
                .accessibilityIdentifier("tub3.state")
                .frame(width: 1, height: 1)
                .opacity(0.02)

            // The bug's own identifier stays on the bug, because what it is for is asserting
            // that the ident was *drawn* — which is a different question from what is tuned.
            switch tuner.state {
            case .playing(let channel, let station, let title, _):
                // Full frame: the bug places its own two blocks, top right and bottom right,
                // because that separation is the whole design and not this screen's business.
                ChannelBugView(channel: channel, station: station, title: title,
                               remaining: tuner.featureRemaining)
                    .opacity(tuner.bugVisible ? 1 : 0)
            case .tuning(let channel, let station):
                // The same ident, with nothing under it yet — the number is the whole point
                // of it while a thumb is still moving.
                ChannelBugView(channel: channel, station: station)
            default:
                EmptyView()
            }

            if overlay == .menu {
                MenuOverlay(menu: menu, nowLine: nowLine)
                    .transition(.opacity)
                    .zIndex(3)
            }

            if overlay == .dial {
                DialOverlay(channels: tuner.channels, current: tuner.current,
                            onClose: { withAnimation { overlay = .none } },
                            onSetup: { rebuildMenu(); withAnimation { overlay = .menu } }) { picked in
                    overlay = .none
                    Task { await tuner.tune(to: picked) }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(2)
            }

        }
        #if os(tvOS)
        .focusScope(focusScope)
        #endif
        .animation(.easeInOut(duration: 0.4), value: tuner.bugVisible)
        .animation(.easeOut(duration: 0.25), value: overlay)
        .task { await tuner.start() }
        #if os(tvOS)
        // Keep hold of focus, because losing it is how this television goes deaf.
        //
        // tvOS resolves focus for a scope once, when the scope appears, and nothing ever
        // makes it try again. Measured on a cold launch against the real box: one run in
        // four came up with the SELECT button in the tree, enabled, and simply *not
        // focused* — and then every press went nowhere for as long as the app was left
        // running. Not a slow start. Four play/pause presses over seventeen seconds, over a
        // picture that was playing perfectly, all lost; the suite recorded that as "the
        // channel strip did not open" and blamed the strip. Nothing in the app would ever
        // have recovered from it, and on the shelf it is a set that has to be force-quit,
        // which is why the answer is a watchdog rather than a longer wait in a test.
        //
        // The sensor is `@FocusState`, which is the only way to ask whether the engine
        // actually gave the button focus. The actuators are alternated on purpose: a
        // `@FocusState` write is dropped outright when the control is not yet registered
        // with the engine, and `resetFocus` does nothing when the scope is not installed
        // yet — whichever of those is true at this instant, the other is tried 250ms later.
        //
        // Runs for as long as the screen is up, like `retryStart` and for its reason: this
        // is an appliance on a shelf with nobody to press anything, so it has to still be
        // trying whenever the engine is finally ready to listen. While an overlay is up the
        // button is disabled and its own rows hold focus, so the watchdog stands down —
        // `.task(id:)` restarts it the moment the overlay closes.
        .task(id: overlay) {
            var attempt = 0
            // Re-read rather than checked once: `.task(id:)` cancels at the next suspension
            // point, so without this an iteration that began just before an overlay opened
            // could still reach for focus a quarter of a second into it.
            while !Task.isCancelled, overlay == .none {
                if selectFocused {
                    attempt = 0
                } else {
                    if attempt.isMultiple(of: 2) { selectFocused = true }
                    else { resetFocus(in: focusScope) }
                    attempt += 1
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        #endif
        // Closing the menu is the model's job, not this view's: `leave()` pops a level and
        // closes at the root, and the Menu button and the Back row both go through it. This
        // watches the result rather than duplicating the rule.
        .onChange(of: menu.isOpen) { _, open in
            if !open, overlay == .menu { withAnimation { overlay = .none } }
        }
        .onChange(of: overlay) { _, now in
            #if os(tvOS)
            if now == .none { resetFocus(in: focusScope) }
            #endif
            guard now == .menu else { return }
            // Asked once per opening, on a six-second session of its own. A stale verdict on
            // a screen somebody opened *because* they are worried is worse than "checking…".
            Task {
                health = try? await tuner.boxHealth()
                if overlay == .menu { rebuildMenu() }
            }
        }
        #if os(tvOS)
        // Three routes, and each is the one that verifiably works rather than the one that
        // reads best.
        //
        // Move commands arrive because something in this tree is focusable and this ZStack
        // is its ancestor — the invisible Button above. This used to be `.focusable()` on the
        // screen itself, which worked while there was nothing else to focus.
        //
        // The channel strip stays on PLAY/PAUSE rather than moving to the centre click.
        // Play/pause is a real physical button, it is what a set-top box uses for its
        // banner, and it is verified by a test. The centre click is now SETUP, which is the
        // box's own grammar: WATCH SELECT opens the menu.
        .onMoveCommand { direction in
            guard overlay == .none else { return }
            switch direction {
            case .up: Task { await tuner.channelUp() }
            case .down: Task { await tuner.channelDown() }
            default: break
            }
        }
        // The strip, and nothing conditional about it. It used to fall back to forgetting
        // the box when the dial was empty — the worst accidental press in the app, because
        // on a cold no-signal screen it was the only responsive control and what it did was
        // throw away the pairing. The strip now always carries a SETUP card, so there is
        // always something to open and the menu owns that route properly.
        .onPlayPauseCommand {
            withAnimation { overlay = (overlay == .dial) ? .none : .dial }
        }
        // No `.onExitCommand` here, deliberately, and it is worth saying why the obvious
        // version was wrong. It used to close the strip from this screen with the body
        // guarded by `if showingDial`, on the belief that leaving the closure empty let the
        // press through. It does not: registration is what consumes it, not the body. So
        // Menu was swallowed on the picture as well, and this app could not be left at all —
        // which is both a trap for whoever is holding the remote and the best-documented
        // reason Apple rejects a tvOS app. `MenuTests` presses it from the top level now.
        // The strip carries its own handler, which exists only while the strip does.
        #endif
    }
}

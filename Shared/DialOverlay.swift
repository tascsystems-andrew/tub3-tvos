import SwiftUI
import Tub3Core

/// The channel strip: every channel at once, so reaching 15 is not fourteen clicks.
///
/// It sits over the picture rather than replacing it, the way a set-top box banner does —
/// the programme keeps playing behind, because a channel list that blacks out the television
/// is a menu, and this is meant to feel like a dial.
public struct DialOverlay: View {
    let channels: [Channel]
    let current: Int?
    let onPick: (Int) -> Void
    let onClose: () -> Void
    let onSetup: () -> Void

    /// A slot rather than a channel number, because the strip's last card is not a channel.
    private enum Slot: Hashable { case channel(Int), setup }
    @FocusState private var focused: Slot?

    public init(channels: [Channel], current: Int?,
                onClose: @escaping () -> Void = {},
                onSetup: @escaping () -> Void = {},
                onPick: @escaping (Int) -> Void) {
        self.channels = channels
        self.current = current
        self.onClose = onClose
        self.onSetup = onSetup
        self.onPick = onPick
    }

    public var body: some View {
        VStack {
            Spacer()
            ScrollViewReader { scroll in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        ForEach(channels) { channel in
                            Button { onPick(channel.channel) } label: {
                                VStack(spacing: 4) {
                                    Text("\(channel.channel)")
                                        .font(.system(size: 38, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Theme.gold)
                                    Text(channel.station)
                                        .font(.system(size: 17, weight: .medium, design: .monospaced))
                                        .foregroundStyle(
                                            channel.channel == current ? Theme.gold : Theme.purple)
                                }
                                .frame(minWidth: 150)
                                .padding(.vertical, 14)
                            }
                            // `.card` is the tvOS focus-aware style and does not exist on
                            // iOS. This is the only place the two platforms genuinely differ
                            // so far, which is a good sign for the shared layer.
                            #if os(tvOS)
                            .buttonStyle(.card)
                            #else
                            .buttonStyle(.plain)
                            #endif
                            .id(channel.channel)
                            .focused($focused, equals: .channel(channel.channel))
                            .accessibilityIdentifier("tub3.dial.\(channel.channel)")
                        }

                        // Always here, even with no channels at all.
                        //
                        // This card is what earns removing the old play/pause fallback. On a
                        // cold no-signal screen the strip is empty, play/pause was the only
                        // responsive control on screen, and what it did was forget the box.
                        // Now there is always one thing to press and it opens the menu.
                        Button(action: onSetup) {
                            VStack(spacing: 4) {
                                Text("SETUP")
                                    .font(.system(size: 38, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Theme.phosphor)
                                Text("this app")
                                    .font(.system(size: 17, design: .monospaced))
                                    .foregroundStyle(Theme.dim)
                            }
                            .frame(minWidth: 150)
                            .padding(.vertical, 14)
                        }
                        #if os(tvOS)
                        .buttonStyle(.card)
                        #else
                        .buttonStyle(.plain)
                        #endif
                        .id("setup")
                        .focused($focused, equals: .setup)
                        .accessibilityIdentifier("tub3.dial.setup")
                    }
                    .padding(.horizontal, 60)
                    .padding(.vertical, 24)
                }
                .background(Theme.ink.opacity(0.86))
                .onAppear {
                    // Open on the channel you are already watching, not at the far left —
                    // and on SETUP when there is no dial, which is the whole point of the
                    // `?? .setup`. With an empty dial the focus engine previously had
                    // nothing at all to focus, which is the fault `SetupScreen` already
                    // records once: a screen with no focus candidate swallows every press.
                    focused = current.map(Slot.channel)
                        ?? channels.first.map { Slot.channel($0.channel) }
                        ?? .setup
                    if let current { scroll.scrollTo(current, anchor: .center) }
                }
            }
        }
        .accessibilityIdentifier("tub3.dial")
        // The strip's own way out, and it lives here rather than on the tuner screen for a
        // reason that is not tidiness.
        //
        // `.onExitCommand` has no pass-through: it returns Void, with no .ignored/.handled
        // result, so a handler registered anywhere in the focused view's ancestor chain
        // consumes the press whatever its closure does. The old placement was on the tuner's
        // ZStack with `if showingDial { … }` inside the body — a conditional body under an
        // unconditional registration, which swallowed Menu at the top level too and left the
        // viewer in an app they could only escape with the TV button. The comment there said
        // the opposite in good faith, and the one test that pressed Menu did it with the
        // strip already open, which is the single case that cannot catch it.
        //
        // Here there is no handler when there is no overlay, so the press falls through to
        // UIKit and it takes them home. Correct by construction rather than by promise. It
        // still fires while a card holds focus because this stack is that card's ancestor,
        // which is the same mechanism that made the old placement work at all.
        #if os(tvOS)
        .onExitCommand(perform: onClose)
        #endif
    }
}

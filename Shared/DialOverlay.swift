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

    @FocusState private var focused: Int?

    public init(channels: [Channel], current: Int?, onPick: @escaping (Int) -> Void) {
        self.channels = channels
        self.current = current
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
                            .focused($focused, equals: channel.channel)
                            .accessibilityIdentifier("tub3.dial.\(channel.channel)")
                        }
                    }
                    .padding(.horizontal, 60)
                    .padding(.vertical, 24)
                }
                .background(Theme.ink.opacity(0.86))
                .onAppear {
                    // Open on the channel you are already watching, not at the far left.
                    focused = current ?? channels.first?.channel
                    if let current { scroll.scrollTo(current, anchor: .center) }
                }
            }
        }
        .accessibilityIdentifier("tub3.dial")
    }
}

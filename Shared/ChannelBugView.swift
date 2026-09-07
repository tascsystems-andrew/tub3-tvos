import SwiftUI

/// The corner ident, the way a CRT drew it.
///
/// Two blocks, deliberately far apart, because that is what `render_bug` in the box does and
/// the reason it gives is a good one: the number goes top right and is enormous, since it is
/// the one thing readable from across a room while you are still pressing the button;
/// everything else goes bottom right at a normal size, for someone who has already stopped
/// and is now curious.
///
/// Phosphor green and monospace, not the mark's gold and purple. The box draws every overlay
/// that sits *over the picture* in `&H55FF33&` — bug, tuning card, off-air card, menu — and
/// keeps gold and purple for the guide and the settings page. `tub3/web.py` writes the rule
/// down: the on-screen furniture is pretending to be a CRT from three metres away, while a
/// settings page is a surface on a desk. A channel bug over full-screen video is the three
/// metres. Drawn in gold it reads as a piece of the guide that has escaped.
public struct ChannelBugView: View {
    let channel: Int
    let station: String
    let title: String
    /// Seconds left of the programme, for the "12 min left" line. Zero hides it.
    let remaining: Double

    public init(channel: Int, station: String, title: String = "", remaining: Double = 0) {
        self.channel = channel
        self.station = station
        self.title = title
        self.remaining = remaining
    }

    /// "Show" and the episode under it, from the box's "Show — Episode" form.
    private var parts: (show: String, detail: String?) {
        let bits = title.components(separatedBy: " — ")
        guard let first = bits.first, !first.isEmpty else { return ("", nil) }
        return (first, bits.count > 1 ? bits.dropFirst().joined(separator: " — ") : nil)
    }

    private var minutesLeft: String? {
        guard remaining > 0 else { return nil }
        let minutes = Int(remaining / 60)
        return minutes > 0 ? "\(minutes) min left" : "ending"
    }

    public var body: some View {
        ZStack {
            // Top right: the number, enormous. Zero-padded like every set-top box and every
            // CRT tuner — CH 03, not CH 3.
            VStack {
                HStack {
                    Spacer()
                    Text(String(format: "CH %02d", channel))
                        .font(.system(size: 150, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.phosphor)
                        .accessibilityIdentifier("tub3.channel.number")
                }
                Spacer()
            }

            // Bottom right: what it is, for whoever stopped to look.
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(station)
                            .font(.system(size: 34, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.phosphor)
                            .accessibilityIdentifier("tub3.channel.station")
                        if !parts.show.isEmpty {
                            Text(parts.show)
                                .font(.system(size: 34, design: .monospaced))
                                .foregroundStyle(Theme.phosphor)
                        }
                        if let detail = parts.detail {
                            Text(detail)
                                .font(.system(size: 26, design: .monospaced))
                                .foregroundStyle(Theme.bugDetail)
                        }
                        if let left = minutesLeft {
                            Text(left)
                                .font(.system(size: 34, design: .monospaced))
                                .foregroundStyle(Theme.phosphor)
                        }
                    }
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                }
            }
        }
        .padding(.top, 40)
        .padding(.trailing, 56)
        .padding(.bottom, 48)
        // The box's \shad6 and \shad3 over a black outline colour. Video is an unpredictable
        // background and a thin glyph on a bright frame is unreadable without it.
        .shadow(color: .black.opacity(0.9), radius: 5, y: 2)
        .allowsHitTesting(false)
    }
}

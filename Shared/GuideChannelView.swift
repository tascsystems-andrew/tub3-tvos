import SwiftUI
import Tub3Core

/// The guide, as a channel rather than a menu.
///
/// Tuning to it shows listings exactly as it does on the box — there is no picture, because
/// on real cable the guide channel *was* the picture. Laid out proportionally against the
/// clock rather than as a list, so a two-hour film looks like a two-hour film.
public struct GuideChannelView: View {
    let guide: Guide?
    let channel: Int
    let station: String

    public init(guide: Guide?, channel: Int, station: String) {
        self.guide = guide
        self.channel = channel
        self.station = station
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm"
        return f
    }()

    public var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()
            if let guide {
                VStack(alignment: .leading, spacing: 0) {
                    header(guide)
                    GeometryReader { geo in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 6) {
                                ForEach(guide.rows) { row in
                                    self.row(row, guide: guide, width: geo.size.width - 210)
                                }
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            // The now line, which is what makes a guide readable at a glance.
                            Rectangle()
                                .fill(Theme.gold)
                                .frame(width: 3)
                                .offset(x: 210 + (geo.size.width - 210)
                                        * GuideLayout.nowFraction(guide))
                                .allowsHitTesting(false)
                        }
                    }
                }
                .padding(.horizontal, 48)
                .padding(.vertical, 36)
            } else {
                ProgressView().tint(Theme.gold)
            }
        }
        .accessibilityIdentifier("tub3.guide")
    }

    private func header(_ guide: Guide) -> some View {
        HStack(spacing: 0) {
            Text("\(channel)  \(station)")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.gold)
                .frame(width: 210, alignment: .leading)
            GeometryReader { geo in
                ForEach(GuideLayout.timeMarks(guide), id: \.self) { mark in
                    Text(Self.clock.string(from: Date(timeIntervalSince1970: mark)))
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.purple)
                        .offset(x: geo.size.width
                                * ((mark - guide.begin) / guide.span))
                }
            }
            .frame(height: 30)
        }
        .padding(.bottom, 14)
    }

    private func row(_ row: GuideRow, guide: Guide, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("\(row.number)")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.gold)
                Text(row.name)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.purple)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(width: 210, alignment: .leading)

            ZStack(alignment: .leading) {
                ForEach(row.slots) { slot in
                    let box = GuideLayout.fraction(of: slot, in: guide)
                    Text((slot.clipped == true ? "‹ " : "") + slot.title)
                        .font(.system(size: 17, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .padding(.horizontal, 8)
                        .frame(width: max(10, width * box.width), height: 54, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.08)))
                        .offset(x: width * box.x)
                }
            }
            .frame(width: width, height: 54, alignment: .leading)
        }
    }
}

import SwiftUI
import Tub3Core

/// Channel 2, built to match the television rather than to be a better table.
///
/// The box's own guide is the reference and its three decisions are copied deliberately:
/// it **crawls continuously and slowly**, it shows **ninety minutes in three columns**, and a
/// programme that began before the window still appears, clipped to the left edge. The crawl
/// is most of the character — the original could not be rushed, and a guide you can scroll
/// yourself is a table, not a cable channel. So there is no manual scrolling here on purpose.
///
/// Sizes are the box's, near enough 1:1: tvOS lays out in a 1920×1080 point space, which is
/// exactly the space the overlay is drawn in. Everything here was half this size to begin
/// with, which reads fine on a monitor and is illegible from a sofa.
public struct GuideChannelView: View {
    let guide: Guide?
    let channel: Int
    let station: String

    public init(guide: Guide?, channel: Int, station: String) {
        self.guide = guide
        self.channel = channel
        self.station = station
    }

    // The box's own constants, so the two screens agree.
    private static let rowHeight: CGFloat = 96
    private static let leftWidth: CGFloat = 400
    private static let numberWidth: CGFloat = 90
    private static let columns = 3
    private static let columnSeconds: Double = 1800      // ninety minutes across three
    private static let scrollRate: CGFloat = 22          // pixels per second, slow on purpose
    private static let showSize: CGFloat = 32
    private static let episodeSize: CGFloat = 24
    private static let nameSize: CGFloat = 30
    private static let slotSize: CGFloat = 42
    private static let networkSize: CGFloat = 88

    private static let columnClock: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm"; return f
    }()
    private static let wallClock: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()
    private static let dateLine: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE d MMMM"; return f
    }()
    private static let dateSize: CGFloat = 40

    /// The visible window: ninety minutes from the top of the guide, not the whole payload.
    private func window(_ guide: Guide) -> (begin: Double, span: Double) {
        (guide.begin, Double(Self.columns) * Self.columnSeconds)
    }

    public var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()
            if let guide {
                grid(guide)
            } else {
                ProgressView().tint(Theme.gold)
            }
        }
        .accessibilityIdentifier("tub3.guide")
    }

    private func grid(_ guide: Guide) -> some View {
        let win = window(guide)
        let bodyWidth = 1920 - Self.leftWidth
        let total = CGFloat(guide.rows.count) * Self.rowHeight

        return GeometryReader { geo in
            // A clock the view can read continuously, so the crawl is a function of time
            // rather than an animation that can drift or be interrupted.
            TimelineView(.animation) { timeline in
                let elapsed = timeline.date.timeIntervalSince1970 - guide.begin
                let offset = crawl(elapsed, total)

                ZStack(alignment: .topLeading) {
                    // Two copies, so rows scrolling off the top are already coming back in
                    // at the bottom and the loop has no gap.
                    ForEach(0 ..< 2, id: \.self) { copy in
                        let base = CGFloat(copy) * total - offset
                        VStack(spacing: 0) {
                            ForEach(guide.rows) { row in
                                self.row(row, win: win, width: bodyWidth)
                                    .frame(height: Self.rowHeight)
                            }
                        }
                        .offset(y: base)
                        // The seam where the listing loops, in the channel numbers' own gold.
                        .overlay(alignment: .top) {
                            Rectangle().fill(Theme.gold).frame(height: 4).offset(y: base - 4)
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .clipped()
                .overlay(alignment: .top) { header(guide, win: win, width: bodyWidth) }
                .overlay(alignment: .topLeading) { nowLine(guide, win: win, width: bodyWidth) }
            }
        }
        .padding(.horizontal, 40)
    }

    /// How far the listing has crawled, wrapped to one full pass.
    private func crawl(_ elapsed: Double, _ total: CGFloat) -> CGFloat {
        guard total > 0, elapsed > 0 else { return 0 }
        return CGFloat(elapsed * Double(Self.scrollRate)).truncatingRemainder(dividingBy: total)
    }

    private func nowLine(_ guide: Guide, win: (begin: Double, span: Double),
                         width: CGFloat) -> some View {
        let f = min(max((Date().timeIntervalSince1970 - win.begin) / win.span, 0), 1)
        return Rectangle()
            .fill(Color(red: 1.0, green: 0.275, blue: 0.275))   // the box's NOW red
            .frame(width: 4)
            .offset(x: Self.leftWidth + width * CGFloat(f))
            .allowsHitTesting(false)
    }

    private func header(_ guide: Guide, win: (begin: Double, span: Double),
                        width: CGFloat) -> some View {
        // Same furniture as the box, down to which colour goes where: the network in gold,
        // the wall clock in purple on the right, the date dim beneath the name, and the
        // column headings in gold on their own dark bands. Only the clock was missing, but
        // the headings were purple here and gold there, which is the kind of drift that makes
        // two screens of the same channel feel like two different products.
        TimelineView(.periodic(from: .now, by: 1)) { tick in
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(station)
                            .font(.system(size: Self.networkSize, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.gold)
                        Text(Self.dateLine.string(from: tick.date))
                            .font(.system(size: Self.dateSize, design: .rounded))
                            .foregroundStyle(Theme.dim)
                    }
                    Spacer(minLength: 0)
                    Text(Self.wallClock.string(from: tick.date))
                        .font(.system(size: Self.networkSize, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.purple)
                        .accessibilityIdentifier("tub3.guide.clock")
                }
                .padding(.bottom, 22)

                HStack(spacing: 0) {
                    // Height as well as width. A Color is flexible in whichever dimension you
                    // leave unfixed, and this one sits inside a TimelineView, which is greedy:
                    // it takes the whole overlay. Left free, the strip stretched the header to
                    // full screen, so its background painted over every listing row.
                    Color.clear.frame(width: Self.leftWidth, height: 66)
                    ZStack(alignment: .leading) {
                        ForEach(0 ..< Self.columns, id: \.self) { column in
                            let at = win.begin + Double(column) * Self.columnSeconds
                            Text(Self.columnClock.string(from: Date(timeIntervalSince1970: at)))
                                .font(.system(size: Self.slotSize, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.gold)
                                .padding(.horizontal, 16)
                                .frame(width: width / CGFloat(Self.columns) - 6,
                                       height: 66, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(red: 0.165, green: 0.129, blue: 0.094)))
                                .offset(x: width * CGFloat(Double(column) / Double(Self.columns)) + 3)
                        }
                    }
                    .frame(width: width, height: 66, alignment: .leading)
                }
                // The purple rule the box closes its header with.
                Rectangle().fill(Theme.purple).frame(height: 6).padding(.top, 6)
            }
            // Belt and braces against the same trap: the header is furniture at the top of the
            // grid, and it should be exactly as tall as its contents whatever it is placed in.
            .fixedSize(horizontal: false, vertical: true)
            .background(Color(red: 0.071, green: 0.055, blue: 0.043))
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ row: GuideRow, win: (begin: Double, span: Double),
                     width: CGFloat) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("\(row.number)")
                    .font(.system(size: Self.nameSize + 6, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.gold)
                    .frame(width: Self.numberWidth)      // centred in its own sub-column
                Text(row.name)
                    .font(.system(size: Self.nameSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.gold)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(width: Self.leftWidth, alignment: .leading)

            ZStack(alignment: .leading) {
                ForEach(row.slots) { slot in
                    let from = max(slot.start, win.begin)
                    let to = min(slot.end, win.begin + win.span)
                    if to > from {
                        let x = CGFloat((from - win.begin) / win.span) * width
                        let w = CGFloat((to - from) / win.span) * width
                        slotCell(slot, width: w).offset(x: x)
                    }
                }
            }
            .frame(width: width, alignment: .leading)
        }
    }

    private func slotCell(_ slot: GuideSlot, width: CGFloat) -> some View {
        // "‹" marks a programme already in progress when the window opened — otherwise the
        // channel you are half-watching looks blank, which is exactly when you looked up.
        let parts = slot.title.components(separatedBy: " — ")
        return VStack(alignment: .leading, spacing: 2) {
            Text((slot.clipped == true ? "‹ " : "") + (parts.first ?? slot.title))
                .font(.system(size: Self.showSize, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
            if parts.count > 1 {
                Text(parts.dropFirst().joined(separator: " — "))
                    .font(.system(size: Self.episodeSize, design: .rounded))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .frame(width: max(20, width), height: Self.rowHeight - 10, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.07)))
    }
}

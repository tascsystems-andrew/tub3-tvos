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
    /// When this visit to the guide began. The crawl is measured from here.
    let startedAt: Date

    public init(guide: Guide?, channel: Int, station: String, startedAt: Date) {
        self.guide = guide
        self.channel = channel
        self.station = station
        self.startedAt = startedAt
    }

    // The box's own constants, so the two screens agree.
    private static let rowHeight = CGFloat(GuideLayout.rowHeight)
    /// The band the header owns. Rows start below it and scroll up behind it, exactly as on
    /// the box, whose header is drawn last and opaque so that departing rows disappear into
    /// it rather than off the top of the screen.
    private static let headerHeight = CGFloat(GuideLayout.headerHeight)
    private static let leftWidth: CGFloat = 400
    private static let numberWidth: CGFloat = 90
    private static let columns = 3
    private static let columnSeconds: Double = 1800      // ninety minutes across three
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
                // A picture first, always — the box's rule, and it applies here more than
                // anywhere. `tuner/box.py` puts the backdrop up *before* any rows exist and
                // says why: "a guide with no music must still look like a guide, not like a
                // failed channel change." A spinner is the one thing the box states it does
                // not have. So the furniture goes up immediately and the rows fill in.
                waitingHeader
            }
        }
        .accessibilityIdentifier("tub3.guide")
    }

    /// The guide's furniture with no listings behind it yet.
    ///
    /// The window is synthesised rather than waited for, because it is not a mystery: the
    /// box's `window()` opens on the current half hour, so the column headings this draws are
    /// the ones the payload will carry when it arrives.
    private var waitingHeader: some View {
        let begin = (Date().timeIntervalSince1970 / Self.columnSeconds).rounded(.down)
            * Self.columnSeconds
        return GeometryReader { geo in
            VStack(spacing: 0) {
                header(win: (begin, Double(Self.columns) * Self.columnSeconds),
                       width: max(1, geo.size.width - Self.leftWidth))
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 40)
    }

    private func grid(_ guide: Guide) -> some View {
        let win = window(guide)
        let total = CGFloat(guide.rows.count) * Self.rowHeight

        return GeometryReader { geo in
            // Measured, not assumed. This was `1920 - leftWidth`, but the grid sits inside
            // 40pt of title-safe padding on each side, so the columns were laid out 80pt
            // wider than the space they had and the right-hand end of the third column fell
            // off the screen. The box derives its own column width for the same reason and
            // says so: "Derived, not fixed, so the columns always reach the right edge."
            let bodyWidth = max(1, geo.size.width - Self.leftWidth)
            // A clock the view can read continuously, so the crawl is a function of time
            // rather than an animation that can drift or be interrupted.
            TimelineView(.animation) { timeline in
                // Since arriving, not since the top of the half hour. Tuning in at 7:17
                // used to apply seventeen minutes — 22,440 pixels — of scroll before drawing
                // anything, so the listing opened partway down the dial at a spot that
                // differed on every visit.
                let elapsed = timeline.date.timeIntervalSince(startedAt)
                let offset = CGFloat(GuideLayout.crawlOffset(elapsed: elapsed,
                                                             totalHeight: Double(total)))

                ZStack(alignment: .topLeading) {
                    // Two copies, so rows scrolling off the top are already coming back in
                    // at the bottom and the loop has no gap.
                    ForEach(0 ..< 2, id: \.self) { copy in
                        let base = Self.headerHeight + CGFloat(copy) * total - offset
                        VStack(spacing: 0) {
                            ForEach(guide.rows) { row in
                                self.row(row, win: win, width: bodyWidth)
                                    .frame(height: Self.rowHeight)
                            }
                        }
                        .offset(y: base)
                        // The seam where the listing loops, in the channel numbers' own gold.
                        .overlay(alignment: .top) {
                            Rectangle().fill(Theme.gold).frame(height: 6).offset(y: base - 7)
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .clipped()
                .overlay(alignment: .top) { header(win: win, width: bodyWidth) }
                .overlay(alignment: .topLeading) { nowLine(guide, win: win, width: bodyWidth) }
            }
        }
        .padding(.horizontal, 40)
    }

    private func nowLine(_ guide: Guide, win: (begin: Double, span: Double),
                         width: CGFloat) -> some View {
        let f = min(max((Date().timeIntervalSince1970 - win.begin) / win.span, 0), 1)
        let red = Color(red: 1.0, green: 0.275, blue: 0.275)   // the box's NOW red
        return Rectangle()
            .fill(red)
            .frame(width: 4)
            // The box runs the line from HEADER_H down and draws its header last, so it never
            // touches the furniture. Padding does the same job here, by shortening the height
            // proposed to the rectangle rather than leaving it free.
            .padding(.top, Self.headerHeight)
            // The cap. A wider stub at the top makes it read as a marker rather than a stray
            // rule that happens to be red.
            .overlay(alignment: .top) {
                Rectangle().fill(red).frame(width: 15, height: 10)
                    .offset(y: Self.headerHeight)
            }
            .offset(x: Self.leftWidth + width * CGFloat(f))
            .allowsHitTesting(false)
    }

    private func header(win: (begin: Double, span: Double),
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
                            .font(.system(size: Self.networkSize, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.gold)
                        Text(Self.dateLine.string(from: tick.date))
                            .font(.system(size: Self.dateSize, design: .monospaced))
                            .foregroundStyle(Theme.dim)
                    }
                    Spacer(minLength: 0)
                    Text(Self.wallClock.string(from: tick.date))
                        .font(.system(size: Self.networkSize, weight: .bold, design: .monospaced))
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
                                .font(.system(size: Self.slotSize, weight: .bold, design: .monospaced))
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
            .frame(height: Self.headerHeight, alignment: .top)
            .background(Color(red: 0.071, green: 0.055, blue: 0.043))
        }
        .frame(height: Self.headerHeight, alignment: .top)
    }

    private func row(_ row: GuideRow, win: (begin: Double, span: Double),
                     width: CGFloat) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("\(row.number)")
                    .font(.system(size: Self.nameSize + 6, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.gold)
                    .frame(width: Self.numberWidth)      // centred in its own sub-column
                Text(row.name)
                    .font(.system(size: Self.nameSize, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.gold)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(width: Self.leftWidth, alignment: .leading)

            ZStack(alignment: .leading) {
                ForEach(row.slots) { slot in
                    let from = max(slot.start, win.begin)
                    let to = min(slot.end, win.begin + win.span)
                    let w = CGFloat((to - from) / win.span) * width
                    // Too short to read is worse than absent: a two-word title in a sliver is
                    // one clipped letter, and it is drawn wider than the time it occupies to
                    // fit even that. The box drops these outright.
                    if to > from, w >= width * CGFloat(GuideLayout.minSlotFraction) {
                        slotCell(slot, width: w)
                            .offset(x: CGFloat((from - win.begin) / win.span) * width)
                    }
                }
            }
            .frame(width: width, alignment: .leading)
        }
        // The row's own band, and the channel column's darker block over it — the two
        // rectangles the box paints before any text. Without them the grid reads as cells
        // floating on ink rather than as a printed listing. The 4pt shortfall is the ink
        // gutter between rows; `.top` keeps it below the row rather than splitting it.
        .frame(height: Self.rowHeight - 4)
        .background(alignment: .leading) {
            Color(red: 0.094, green: 0.129, blue: 0.165)      // &H2A2118&
                .frame(width: Self.leftWidth - 6)
        }
        .background(row.number % 2 == 0
                    ? Color(red: 0.090, green: 0.102, blue: 0.122)    // &H1F1A17&
                    : Color(red: 0.063, green: 0.075, blue: 0.090))   // &H171310&
        .frame(height: Self.rowHeight, alignment: .top)
    }

    private func slotCell(_ slot: GuideSlot, width: CGFloat) -> some View {
        // "‹" marks a programme already in progress when the window opened — otherwise the
        // channel you are half-watching looks blank, which is exactly when you looked up.
        let parts = slot.title.components(separatedBy: " — ")
        return VStack(alignment: .leading, spacing: 2) {
            Text((slot.clipped == true ? "‹ " : "") + (parts.first ?? slot.title))
                .font(.system(size: Self.showSize, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
            if parts.count > 1 {
                Text(parts.dropFirst().joined(separator: " — "))
                    .font(.system(size: Self.episodeSize, design: .monospaced))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .frame(width: width, height: Self.rowHeight - 10, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.07)))
    }
}

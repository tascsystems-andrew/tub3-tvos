import Foundation

public struct GuideSlot: Codable, Equatable, Sendable, Identifiable {
    public let title: String
    public let start: Double
    public let end: Double
    /// True when the programme began before this window opened, so the grid can show that
    /// it is joining something already in progress rather than starting it.
    public let clipped: Bool?

    public var id: String { "\(start)-\(title)" }
    public var duration: Double { max(0, end - start) }
}

public struct GuideRow: Codable, Equatable, Sendable, Identifiable {
    public let number: Int
    public let name: String
    public let slots: [GuideSlot]
    public var id: Int { number }
}

public struct Guide: Codable, Equatable, Sendable {
    public let now: Double
    public let begin: Double
    public let end: Double
    public let rows: [GuideRow]

    public var span: Double { max(1, end - begin) }
}

/// Where things sit in the grid, as fractions of its width.
///
/// Kept as pure arithmetic in Core rather than inside the view so it can be checked without
/// rendering anything — a grid that is subtly wrong is very hard to see and very easy to test.
public enum GuideLayout {
    /// A slot's position as (x, width) in 0...1, clamped to the visible window.
    public static func fraction(of slot: GuideSlot, in guide: Guide) -> (x: Double, width: Double) {
        let from = max(slot.start, guide.begin)
        let to = min(slot.end, guide.end)
        let x = (from - guide.begin) / guide.span
        let width = max(0, (to - from) / guide.span)
        return (min(max(x, 0), 1), min(width, 1 - min(max(x, 0), 1)))
    }

    /// Where "now" falls, so the grid can draw the line a real guide draws.
    public static func nowFraction(_ guide: Guide) -> Double {
        min(max((guide.now - guide.begin) / guide.span, 0), 1)
    }

    /// The box's own layout numbers, so the two screens agree by construction.
    /// `tuner/guide.py`: ROW_H, HEADER_H, SCROLL_PX_PER_SEC.
    public static let rowHeight: Double = 96
    /// The band the header occupies. Rows begin below it and scroll up behind it — the box
    /// draws its header last and opaque for exactly that reason.
    public static let headerHeight: Double = 300
    public static let scrollRate: Double = 22
    /// The narrowest cell worth drawing, as a fraction of the visible window.
    ///
    /// `tuner/guide.py` drops anything under 40px across its 1520px grid — about two
    /// minutes. A fraction rather than a pixel count because the app draws the same
    /// grid at other widths, and the box's intent is "too short to read", not "40px".
    public static let minSlotFraction: Double = 40.0 / 1520.0

    /// How far the listing has crawled, wrapped to one full pass.
    ///
    /// `elapsed` is measured from the moment the channel was tuned, not from the top of the
    /// half hour: the box builds a fresh `Guide` per tune and measures from that, so channel
    /// 2 always opens on the first channel of the dial and crawls from there. Anchoring to
    /// the half hour instead opened the listing at a different place on every visit.
    public static func crawlOffset(elapsed: Double, totalHeight: Double,
                                   rate: Double = scrollRate) -> Double {
        guard totalHeight > 0, elapsed > 0 else { return 0 }
        return (elapsed * rate).truncatingRemainder(dividingBy: totalHeight)
    }

    /// Where a row sits, in the same terms the box uses:
    /// `y = HEADER_H + index * ROW_H - offset + repeat * total_h`
    public static func rowY(index: Int, copy: Int, offset: Double, totalHeight: Double) -> Double {
        headerHeight + Double(index) * rowHeight - offset + Double(copy) * totalHeight
    }

    /// Column headings on the half hour, which is what broadcast guides use.
    public static func timeMarks(_ guide: Guide, every seconds: Double = 1800) -> [Double] {
        var marks: [Double] = []
        var t = (guide.begin / seconds).rounded(.up) * seconds
        while t < guide.end {
            marks.append(t)
            t += seconds
        }
        return marks
    }
}

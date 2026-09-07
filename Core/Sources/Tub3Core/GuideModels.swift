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

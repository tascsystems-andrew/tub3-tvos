import Foundation
import Testing
@testable import Tub3Core

private func fixture(_ name: String) throws -> Data {
    let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)
    return try Data(contentsOf: #require(url))
}

@Test func decodesTheRealGuide() throws {
    let guide = try JSONDecoder().decode(Guide.self, from: fixture("guide.json"))
    #expect(guide.rows.isEmpty == false)
    #expect(guide.span > 0)
    #expect(guide.rows.allSatisfy { !$0.name.isEmpty })
}

@Test func everySlotLandsInsideTheGrid() throws {
    let guide = try JSONDecoder().decode(Guide.self, from: fixture("guide.json"))
    for row in guide.rows {
        for slot in row.slots {
            let box = GuideLayout.fraction(of: slot, in: guide)
            #expect(box.x >= 0 && box.x <= 1)
            #expect(box.width >= 0)
            #expect(box.x + box.width <= 1.0001, "\(row.name) overflows the grid")
        }
    }
}

@Test func aProgrammeStartingBeforeTheWindowIsClippedNotShifted() {
    let guide = Guide(now: 100, begin: 100, end: 200,
                      rows: [GuideRow(number: 1, name: "X",
                                      slots: [GuideSlot(title: "early", start: 50, end: 150,
                                                        clipped: true)])])
    let box = GuideLayout.fraction(of: guide.rows[0].slots[0], in: guide)
    // It must start at the left edge and be half the width, not start off-screen.
    #expect(box.x == 0)
    #expect(abs(box.width - 0.5) < 0.0001)
}

@Test func nowSitsWhereTheClockSays() throws {
    let guide = try JSONDecoder().decode(Guide.self, from: fixture("guide.json"))
    let f = GuideLayout.nowFraction(guide)
    #expect(f >= 0 && f <= 1)
}

@Test func timeMarksLandOnTheHalfHour() throws {
    let guide = try JSONDecoder().decode(Guide.self, from: fixture("guide.json"))
    let marks = GuideLayout.timeMarks(guide)
    #expect(marks.isEmpty == false)
    for mark in marks {
        #expect(mark.truncatingRemainder(dividingBy: 1800) == 0)
        #expect(mark >= guide.begin && mark < guide.end)
    }
}

/// The crawl, checked against the box's own arithmetic in `tuner/guide.py`:
///     offset = ((now - self._started) * SCROLL_PX_PER_SEC) % total_h
///     y      = HEADER_H + index * ROW_H - offset + repeat * total_h
@Suite("Guide crawl")
struct GuideCrawlTests {
    /// A twelve-channel dial, which is what this one is.
    let total = 12 * GuideLayout.rowHeight

    @Test("the listing opens at the top of the dial")
    func opensAtTheTop() {
        // The defining property: on arrival nothing has scrolled, so the first channel sits
        // directly below the header. This is what "channel 2 always opens the same way" means.
        #expect(GuideLayout.crawlOffset(elapsed: 0, totalHeight: total) == 0)
        #expect(GuideLayout.rowY(index: 0, copy: 0, offset: 0, totalHeight: total)
                == GuideLayout.headerHeight)
    }

    @Test("twenty-two pixels a second, as the box scrolls")
    func rate() {
        #expect(abs(GuideLayout.crawlOffset(elapsed: 1, totalHeight: total) - 22) < 0.001)
        #expect(abs(GuideLayout.crawlOffset(elapsed: 10, totalHeight: total) - 220) < 0.001)
    }

    @Test("wraps at one full pass of the dial")
    func wraps() {
        let onePass = total / 22
        #expect(abs(GuideLayout.crawlOffset(elapsed: onePass, totalHeight: total)) < 0.001)
        #expect(abs(GuideLayout.crawlOffset(elapsed: onePass + 1, totalHeight: total) - 22) < 0.001)
    }

    /// The regression this replaces. The crawl was measured from the payload's `begin` — the
    /// top of the current half hour — so tuning in at 7:17 applied 1020s x 22 = 22,440px of
    /// scroll before drawing anything, and the listing opened somewhere different every time.
    /// Nothing about when the half hour started may reach this arithmetic.
    @Test("does not depend on when the half hour started")
    func independentOfTheWindow() {
        for _ in [0.0, 17.0 * 60, 29.0 * 60] {
            #expect(abs(GuideLayout.crawlOffset(elapsed: 3, totalHeight: total) - 66) < 0.001)
        }
    }

    @Test("rows stack below the header and the loop has no gap")
    func stacking() {
        #expect(GuideLayout.rowY(index: 3, copy: 0, offset: 0, totalHeight: total) == 300 + 3 * 96)
        // Copy 1 begins exactly one full dial below copy 0.
        #expect(GuideLayout.rowY(index: 0, copy: 1, offset: 0, totalHeight: total)
                == GuideLayout.rowY(index: 0, copy: 0, offset: 0, totalHeight: total) + total)
    }

    @Test("an empty dial does not divide by zero")
    func emptyDial() {
        #expect(GuideLayout.crawlOffset(elapsed: 5, totalHeight: 0) == 0)
    }
}

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

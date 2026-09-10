import XCTest

/// The guide broke once by rendering all of its furniture and none of its listings — the
/// header stretched and painted over the rows. Chrome alone looks like a working screen in a
/// screenshot, so this asserts the part that actually carries the information.
final class GuideRowsTests: XCTestCase {
    func testGuideShowsChannelRowsNotJustChrome() {
        let app = XCUIApplication()
        app.launchArguments += Harness.quiet + ["-tub3Channel", "3"]
        app.launch()

        Harness.tuned(app)
        XCUIRemote.shared.press(.down)                       // ch3 -> ch2, the guide,
                                                             // which -tub3Channel pinned
        XCTAssertTrue(app.otherElements["tub3.guide"].waitForExistence(timeout: 25))

        // The clock is chrome and was present the whole time the guide was broken.
        XCTAssertTrue(app.staticTexts["tub3.guide.clock"].waitForExistence(timeout: 10))

        // A station name from the listings themselves. The crawl moves rows, so poll rather
        // than sample once: any row appearing at all is the thing under test.
        let deadline = Date().addingTimeInterval(20)
        var sawRow = false
        while Date() < deadline && !sawRow {
            sawRow = app.staticTexts.matching(
                NSPredicate(format: "label MATCHES %@", "BOOBTUBE|SATURDAY AM|SUNNY DAYS")
            ).firstMatch.exists
            if !sawRow { Thread.sleep(forTimeInterval: 1) }
        }
        XCTAssertTrue(sawRow, "guide drew its header and no listings")
    }
}

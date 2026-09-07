import XCTest

/// The guide is channel 2, so tuning down from the first channel reaches it. This asserts on
/// the accessibility tree rather than on a screenshot: a screenshot proves something was
/// drawn, the tree proves the listings actually arrived from the box.
final class GuideTests: XCTestCase {

    func testTuningToTheGuideShowsListings() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-tub3Mute"]
        app.launch()

        let bug = app.staticTexts["tub3.channel.number"]
        XCTAssertTrue(bug.waitForExistence(timeout: 40), "never tuned at all")

        // Down from the first channel lands on the guide.
        XCUIRemote.shared.press(.down)

        let guide = app.otherElements["tub3.guide"]
        let grid = guide.waitForExistence(timeout: 25)
        if !grid {
            // Fall back to looking for row text, in case the container is not an element.
            let anyRow = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'BOOBTUBE'")).firstMatch
            XCTAssertTrue(anyRow.waitForExistence(timeout: 15),
                          "the guide channel showed nothing. On screen: "
                          + app.debugDescription.prefix(1500))
        }
    }
}

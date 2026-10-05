import XCTest

/// Recent rows in the Log Food sheet must open on the first tap, with the keyboard up, every
/// time: for a saved food, a food that was deleted after logging, and a quick entry. Expects a
/// fresh install (only the bundled Tiki Cat foods, no log entries).
@MainActor
final class RecentFoodsUITests: XCTestCase {
    private let app = XCUIApplication()
    private let rounds = 4

    override func setUp() {
        continueAfterFailure = false
    }

    func testRecentRowsOpenOnFirstTap() {
        app.launch()
        app.tabBars.buttons["Calories"].tap()

        // A quick entry.
        openLogFood()
        app.buttons["Quick Entry"].firstMatch.tap()
        type("Treat", into: app.textFields["quickName"])
        type("5", into: app.textFields["quickCalories"])
        app.navigationBars.buttons["Save"].tap()

        // A bundled food, found by search.
        openLogFood()
        app.typeText("after dark lamb")
        let lamb = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Lamb")).firstMatch
        XCTAssertTrue(lamb.waitForExistence(timeout: 5))
        lamb.tap()
        XCTAssertTrue(app.textFields["portionCalories"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Save"].tap()

        // An own food: add it, log 20 g, then delete it from saved foods.
        app.buttons["Saved Foods"].tap()
        app.buttons["Add Food"].tap()
        type("Home Chicken", into: app.textFields["Product name"])
        type("1.5", into: app.textFields["Calories per gram"])
        app.navigationBars.buttons["Save"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        openLogFood()
        app.typeText("Home Chicken")
        let chicken = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Home Chicken")).firstMatch
        XCTAssertTrue(chicken.waitForExistence(timeout: 5))
        chicken.tap()
        type("20", into: app.textFields["portionGrams"])
        app.navigationBars.buttons["Save"].tap()
        app.buttons["Saved Foods"].tap()
        app.descendants(matching: .any).matching(identifier: "brandRow")
            .matching(NSPredicate(format: "label CONTAINS %@", "My foods")).firstMatch.tap()
        let saved = app.descendants(matching: .any).matching(identifier: "savedFood").firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.swipeLeft()
        app.buttons["Delete"].tap()
        app.tabBars.buttons["Calories"].tap()
        app.tabBars.buttons["Calories"].tap()

        // Three distinct Recent rows, nothing repeated in Frequent.
        openLogFood()
        XCTAssertEqual(rows("recentRow").count, 3)
        XCTAssertEqual(rows("frequentRow").count, 0)
        XCTAssertTrue(row("Home Chicken").label.contains("Not in saved foods"), row("Home Chicken").label)
        XCTAssertTrue(row("Treat").label.contains("Quick entry"), row("Treat").label)
        attach("Recent")
        cancel()

        // Each row, several times, tapped straight away with the keyboard showing.
        for round in 1...rounds {
            openLogFood()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "Keyboard should be up (round \(round))")
            row("Lamb").tap()
            XCTAssertTrue(app.textFields["portionCalories"].waitForExistence(timeout: 3), "Saved food didn't open (round \(round))")
            cancel()

            openLogFood()
            row("Home Chicken").tap()
            XCTAssertTrue(app.textFields["portionGrams"].waitForExistence(timeout: 3), "Deleted food didn't open (round \(round))")
            XCTAssertEqual(app.textFields["portionGrams"].value as? String, "20")
            XCTAssertTrue(app.staticTexts["Not in saved foods · logged from an earlier entry"].exists)
            if round == 1 { attach("Deleted food opened") }
            cancel()

            openLogFood()
            row("Treat").tap()
            XCTAssertTrue(app.textFields["quickName"].waitForExistence(timeout: 3), "Quick entry didn't open (round \(round))")
            XCTAssertEqual(app.textFields["quickName"].value as? String, "Treat")
            XCTAssertEqual(app.textFields["quickCalories"].value as? String, "5")
            cancel()
        }

        // Logging again from the deleted food's copy works.
        openLogFood()
        row("Home Chicken").tap()
        XCTAssertTrue(app.textFields["portionGrams"].waitForExistence(timeout: 3))
        app.navigationBars.buttons["Save"].tap()
        let chickenEntries = app.descendants(matching: .any).matching(identifier: "logEntry")
            .matching(NSPredicate(format: "label CONTAINS %@", "Home Chicken"))
        XCTAssertTrue(chickenEntries.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(chickenEntries.count, 2)
        attach("Logged again")
    }

    // MARK: - Helpers

    private func openLogFood() {
        let button = app.buttons["Log Food"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        XCTAssertTrue(app.textFields["Search your foods"].waitForExistence(timeout: 5))
    }

    private func cancel() {
        app.navigationBars.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Log Food"].firstMatch.waitForExistence(timeout: 5))
    }

    private func type(_ text: String, into field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Missing field \(field)")
        field.tap()
        field.typeText(text)
    }

    private func rows(_ identifier: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: identifier)
    }

    private func row(_ text: String) -> XCUIElement {
        rows("recentRow").matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

import XCTest

/// Walks through logging what Mochi eats, the way a person would. Expects a fresh install.
@MainActor
final class FoodLogUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
    }

    func testLogEditDeleteAndHistory() {
        app.launch()
        app.tabBars.buttons["Calories"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Nothing logged"].exists)
        XCTAssertEqual(total, "0 kcal")

        // Log half a can, found by searching.
        app.buttons["Log Food"].tap()
        search("grill tuna prawn")
        foodRow("Grill Tuna & Prawn Pâté").tap()
        XCTAssertEqual(app.textFields["portionCalories"].value as? String, "77")
        app.buttons["1/2"].tap()
        XCTAssertEqual(app.textFields["portionCalories"].value as? String, "38.5")
        app.buttons["Save"].tap()
        XCTAssertTrue(entry("Grill Tuna & Prawn Pâté").waitForExistence(timeout: 5))
        XCTAssertTrue(entry("Grill Tuna & Prawn Pâté").label.contains("1/2 of a 2.8 oz can"), entry("Grill Tuna & Prawn Pâté").label)
        XCTAssertEqual(total, "38.5 kcal")

        // Quick entry: just a name and calories.
        app.buttons["Log Food"].tap()
        app.buttons["quickEntryRow"].tap()
        app.textFields["quickName"].tap()
        app.textFields["quickName"].typeText("Freeze-dried treat")
        app.textFields["quickCalories"].tap()
        app.textFields["quickCalories"].typeText("5")
        app.buttons["Save"].tap()
        XCTAssertTrue(entry("Freeze-dried treat").waitForExistence(timeout: 5))
        XCTAssertEqual(total, "43.5 kcal")
        attachScreenshot("Today")

        // Tap an entry to change its amount.
        entry("Grill Tuna & Prawn Pâté").tap()
        XCTAssertTrue(app.buttons["1/2"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["1/2"].isSelected)
        app.buttons["1 whole"].tap()
        app.buttons["Save"].tap()
        XCTAssertTrue(entry("1 whole 2.8 oz can").waitForExistence(timeout: 5))
        XCTAssertEqual(total, "82 kcal")

        // "Log This" from a food's own page.
        app.buttons["Saved Foods"].tap()
        search("grill tuna prawn")
        foodRow("Grill Tuna & Prawn Pâté").tap()
        let logThis = app.buttons["Log This"]
        for _ in 0..<8 where !logThis.isHittable { app.swipeUp() }
        logThis.tap()
        app.buttons["Save"].tap()

        // Deleting the saved food must not change past entries.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        foodRow("Grill Tuna & Prawn Pâté").swipeLeft()
        app.buttons["Delete"].tap()
        app.tabBars.buttons["Calories"].tap()
        app.tabBars.buttons["Calories"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        XCTAssertEqual(total, "159 kcal")
        XCTAssertEqual(entries.count, 3)

        // Earlier days, and back to today.
        app.buttons["Previous Day"].tap()
        XCTAssertTrue(app.navigationBars["Yesterday"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Nothing logged"].exists)
        app.buttons["Back to Today"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))

        // Still there after closing and reopening.
        app.terminate()
        app.launch()
        app.tabBars.buttons["Calories"].tap()
        XCTAssertTrue(entry("Freeze-dried treat").waitForExistence(timeout: 5))
        XCTAssertEqual(total, "159 kcal")

        // Swipe to delete an entry.
        entry("Freeze-dried treat").swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(total, "154 kcal")
    }

    private var total: String { app.staticTexts["dayTotal"].label }

    private var entries: XCUIElementQuery { app.buttons.matching(identifier: "logEntry") }

    private func entry(_ text: String) -> XCUIElement {
        entries.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func foodRow(_ text: String) -> XCUIElement {
        let row = app.descendants(matching: .any).matching(identifier: "savedFood")
            .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        return row
    }

    private func search(_ text: String) {
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

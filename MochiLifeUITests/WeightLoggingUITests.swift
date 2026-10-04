import XCTest

/// Walks through weight logging and the weight chart the way a person would. Expects a
/// fresh install (no saved entries, unit set to kg), and leaves the app with no entries in kg.
@MainActor
final class WeightLoggingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testAddSwitchUnitsReopenAndDelete() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["Mochi Life"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No weights yet"].exists)
        XCTAssertTrue(app.buttons["kg"].isSelected)
        XCTAssertFalse(changeLine(in: app).exists)

        addWeight("4.25", in: app)
        XCTAssertTrue(entry(containing: "4.25 kg", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["No weights yet"].exists)
        // A single entry shows on the chart but has no change line yet.
        XCTAssertFalse(changeLine(in: app).exists)

        // Switching back and forth many times must never change the numbers.
        for _ in 0..<25 {
            app.buttons["lb"].tap()
            app.buttons["kg"].tap()
        }
        XCTAssertTrue(entry(containing: "4.25 kg", in: app).exists)

        app.buttons["lb"].tap()
        XCTAssertTrue(entry(containing: "9.37 lb", in: app).exists)

        // The add form uses the selected unit.
        addWeight("10", in: app)
        XCTAssertTrue(entry(containing: "10.00 lb", in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(entries(in: app).count, 2)
        XCTAssertTrue(entries(in: app).element(boundBy: 0).label.contains("10.00 lb"), "Newest entry should be first")

        // The change line follows the selected unit and matches the numbers in the list.
        XCTAssertTrue(changeLine(in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(changeLine(in: app).label.hasPrefix("Up 0.63 lb since "), changeLine(in: app).label)
        app.buttons["kg"].tap()
        XCTAssertTrue(entry(containing: "4.54 kg", in: app).exists)
        XCTAssertTrue(changeLine(in: app).label.hasPrefix("Up 0.29 kg since "), changeLine(in: app).label)
        app.buttons["lb"].tap()

        // Entries and the chosen unit survive closing and reopening the app.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["lb"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["lb"].isSelected)
        XCTAssertTrue(entry(containing: "10.00 lb", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(entry(containing: "9.37 lb", in: app).exists)

        // Weights with more than two decimals can't be saved.
        app.buttons["Add Weight"].tap()
        let field = app.textFields["Weight"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("4.255")
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        app.buttons["Cancel"].tap()

        // Swipe to delete. With one entry left, the change line goes away.
        entries(in: app).element(boundBy: 0).swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertEqual(entries(in: app).count, 1)
        XCTAssertFalse(changeLine(in: app).exists)
        entries(in: app).element(boundBy: 0).swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["No weights yet"].waitForExistence(timeout: 5))

        app.buttons["kg"].tap()
    }

    private func addWeight(_ text: String, in app: XCUIApplication) {
        app.buttons["Add Weight"].tap()
        let field = app.textFields["Weight"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)
        app.buttons["Save"].tap()
    }

    private func entries(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "weightEntry")
    }

    private func entry(containing text: String, in app: XCUIApplication) -> XCUIElement {
        entries(in: app).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func changeLine(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts["weightChange"]
    }
}

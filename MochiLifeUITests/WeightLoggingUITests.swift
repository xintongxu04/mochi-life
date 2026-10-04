import XCTest

/// Walks through weight logging the way a person would. Expects a fresh install
/// (no saved entries, unit set to kg), and leaves the app with no entries in kg.
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

        addWeight("4.25", in: app)
        XCTAssertTrue(entry(containing: "4.25 kg", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["No weights yet"].exists)

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
        XCTAssertEqual(app.cells.count, 2)
        XCTAssertTrue(contains("10.00 lb", app.cells.element(boundBy: 0)), "Newest entry should be first")

        app.buttons["kg"].tap()
        XCTAssertTrue(entry(containing: "4.54 kg", in: app).exists)
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

        // Swipe to delete.
        app.cells.element(boundBy: 0).swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertEqual(app.cells.count, 1)
        app.cells.element(boundBy: 0).swipeLeft()
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

    private func entry(containing text: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func contains(_ text: String, _ element: XCUIElement) -> Bool {
        element.label.contains(text)
            || element.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch.exists
    }
}

import XCTest

/// A quick check that the app starts on the Calories screen, Log Food opens, and Saved Foods opens
/// and its search takes text. Works with any saved data and in any iPhone Duo pose.
@MainActor
final class SmokeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testLaunchShowsCaloriesAndLogFoodOpens() {
        let app = XCUIApplication()
        app.launch()

        let logFood = app.buttons["logFoodButton"]
        XCTAssertTrue(logFood.waitForExistence(timeout: 10), "The Calories screen's Log Food button should show")
        XCTAssertTrue(app.staticTexts["Daily Calories"].waitForExistence(timeout: 5), "The Calories screen should show")

        logFood.tap()
        XCTAssertTrue(app.navigationBars["Log Food"].waitForExistence(timeout: 5), "Log Food should open")
    }

    func testSavedFoodsOpensAndSearchTakesText() {
        let app = XCUIApplication()
        app.launch()

        let savedFoods = app.buttons["Saved Foods"].firstMatch
        XCTAssertTrue(savedFoods.waitForExistence(timeout: 10), "The Saved Foods button should show")
        savedFoods.tap()
        XCTAssertTrue(app.navigationBars["Saved Foods"].waitForExistence(timeout: 5), "Saved Foods should open")

        // The system search field on a one-column screen; the pane's own field when the fold
        // splits the screen.
        let paneField = app.textFields["savedFoodsSearch"]
        let field = paneField.waitForExistence(timeout: 2) ? paneField : app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "A search field should show")
        field.tap()
        field.typeText("tuna")
        XCTAssertEqual(field.value as? String, "tuna", "The search field should take text")
    }
}

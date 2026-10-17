import XCTest

/// A quick check that the app starts on the Calories screen and Log Food opens. Works with any
/// saved data and in any iPhone Duo pose.
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
}

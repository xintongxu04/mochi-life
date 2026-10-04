import XCTest

/// Walks through saved foods in the Calories tab the way a person would. Expects a fresh
/// install (no saved foods), and leaves the app with no saved foods.
@MainActor
final class SavedFoodsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testAddEditReopenAndDeleteFoods() {
        let app = XCUIApplication()
        app.launch()

        // The Weight tab is still the first screen.
        XCTAssertTrue(app.staticTexts["Mochi Life"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Calories"].tap()
        XCTAssertTrue(app.staticTexts["No foods yet"].waitForExistence(timeout: 5))
        attachScreenshot("Empty", app)

        // Typed directly as kcal per gram.
        addFood("Dry Food", calories: "3.85", per100Grams: false, in: app)
        XCTAssertTrue(food(containing: "Dry Food", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(food(containing: "3.85 kcal/g", in: app).exists)
        XCTAssertFalse(app.staticTexts["No foods yet"].exists)

        // Typed as kcal per 100 g, which the app converts to kcal per gram.
        app.buttons["Add Food"].tap()
        app.textFields["Name"].tap()
        app.textFields["Name"].typeText("Chicken Treats")
        app.buttons["per 100 g"].tap()
        app.textFields["Calories"].tap()
        app.textFields["Calories"].typeText("352")
        XCTAssertTrue(app.staticTexts["That's 3.52 kcal per gram."].waitForExistence(timeout: 5))
        attachScreenshot("Add per 100 g", app)
        app.buttons["Save"].tap()
        XCTAssertTrue(food(containing: "3.52 kcal/g", in: app).waitForExistence(timeout: 5))

        addFood("apple slices", calories: "0.52", per100Grams: false, in: app)
        XCTAssertTrue(food(containing: "0.52 kcal/g", in: app).waitForExistence(timeout: 5))

        // Alphabetical, ignoring capital letters.
        XCTAssertEqual(foodNames(in: app), ["apple slices", "Chicken Treats", "Dry Food"])
        attachScreenshot("List", app)

        // A per-100 g number typed as per gram is caught.
        app.buttons["Add Food"].tap()
        app.textFields["Name"].tap()
        app.textFields["Name"].typeText("Wet Food")
        app.textFields["Calories"].tap()
        app.textFields["Calories"].typeText("385")
        XCTAssertTrue(app.staticTexts["That's more than 10 kcal per gram. Did you mean per 100 g?"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        app.buttons["Cancel"].tap()
        XCTAssertEqual(foodNames(in: app).count, 3)

        // Tap to edit: rename and change calories.
        food(containing: "Dry Food", in: app).tap()
        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["Calories"].value as? String, "3.85")
        // Tap at the end of the name, then delete it and type a new one.
        name.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Dry Food".count))
        name.typeText("Kibble")
        let calories = app.textFields["Calories"]
        calories.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        calories.typeText("5")
        app.buttons["Save"].tap()
        XCTAssertTrue(food(containing: "3.855 kcal/g", in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(foodNames(in: app), ["apple slices", "Chicken Treats", "Kibble"])

        // Foods are still there after closing and reopening the app.
        app.terminate()
        app.launch()
        app.tabBars.buttons["Calories"].tap()
        XCTAssertTrue(food(containing: "Kibble", in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(foodNames(in: app), ["apple slices", "Chicken Treats", "Kibble"])

        // Swipe to delete.
        while foods(in: app).count > 0 {
            let count = foods(in: app).count
            foods(in: app).element(boundBy: 0).swipeLeft()
            app.buttons["Delete"].tap()
            XCTAssertEqual(foods(in: app).count, count - 1)
        }
        XCTAssertTrue(app.staticTexts["No foods yet"].waitForExistence(timeout: 5))
    }

    private func addFood(_ name: String, calories: String, per100Grams: Bool, in app: XCUIApplication) {
        app.buttons["Add Food"].tap()
        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(name)
        if per100Grams { app.buttons["per 100 g"].tap() }
        app.textFields["Calories"].tap()
        app.textFields["Calories"].typeText(calories)
        app.buttons["Save"].tap()
    }

    private func foods(in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(identifier: "savedFood")
    }

    private func food(containing text: String, in app: XCUIApplication) -> XCUIElement {
        foods(in: app).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func foodNames(in app: XCUIApplication) -> [String] {
        foods(in: app).allElementsBoundByIndex.map { $0.label.components(separatedBy: ",").first ?? "" }
    }

    private func attachScreenshot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

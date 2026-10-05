import XCTest

/// Walks through saved foods in the Calories tab the way a person would. Expects a fresh
/// install, where the 99 bundled Tiki Cat foods are the only saved foods. Tests run in name
/// order; only the last one changes saved foods.
@MainActor
final class SavedFoodsUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launch()
        app.tabBars.buttons["Calories"].tap()
        app.buttons["Saved Foods"].tap()
        XCTAssertTrue(app.navigationBars["Saved Foods"].waitForExistence(timeout: 5))
    }

    func testA_BrowseSearchAndDetails() {
        // Brands, with "My foods" absent until the user adds a food without a brand.
        XCTAssertTrue(row("brandRow", "Tiki Cat").waitForExistence(timeout: 5))
        XCTAssertTrue(row("brandRow", "Tiki Cat").label.contains("99"), row("brandRow", "Tiki Cat").label)
        XCTAssertFalse(row("brandRow", "My foods").exists)
        attachScreenshot("Brands")

        // Lines, each with a count.
        row("brandRow", "Tiki Cat").tap()
        XCTAssertTrue(row("lineRow", "After Dark").waitForExistence(timeout: 5))
        XCTAssertEqual(rows("lineRow").count, 10)
        XCTAssertTrue(row("lineRow", "After Dark").label.contains("25"), row("lineRow", "After Dark").label)
        attachScreenshot("Lines")

        // Products in a line, then a product's details.
        row("lineRow", "After Dark").tap()
        // Long lists only build the rows on screen, so scroll to the product first.
        scrollTo(row("savedFood", "Pâté Lamb & Beef Liver"))
        row("savedFood", "Pâté Lamb & Beef Liver").tap()
        XCTAssertTrue(app.staticTexts["After Dark Pâté Lamb & Beef Liver Recipe"].waitForExistence(timeout: 5))
        XCTAssertTrue(row("sizeCalories", "110 kcal per can").exists)
        let calculatedSize = row("sizeCalories", "5.5 oz can")
        XCTAssertTrue(calculatedSize.label.contains("calculated"), calculatedSize.label)
        XCTAssertTrue(calculatedSize.label.contains("201 kcal per can"), calculatedSize.label)
        XCTAssertFalse(row("sizeCalories", "3 oz can").label.contains("calculated"))
        XCTAssertTrue(app.staticTexts["As written by the brand"].exists)
        attachScreenshot("Details top")

        scrollTo(app.staticTexts["Crude protein"])
        XCTAssertTrue(app.staticTexts["INGREDIENTS"].exists || app.staticTexts["Ingredients"].exists)
        attachScreenshot("Details ingredients and analysis")
        scrollTo(app.links.firstMatch)
        XCTAssertTrue(app.links["tikipets.com"].exists)
        attachScreenshot("Details bottom")

        // Search: brand, line and name together, any order, ignoring capitals and accents.
        app.tabBars.buttons["Calories"].tap()
        app.tabBars.buttons["Calories"].tap()
        app.buttons["Saved Foods"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("TUNA pate")
        XCTAssertTrue(row("savedFood", "Grill Tuna & Prawn Pâté").waitForExistence(timeout: 5))
        attachScreenshot("Search")
        search.typeText(" grill tiki")
        XCTAssertTrue(row("savedFood", "Grill Tuna & Prawn Pâté").waitForExistence(timeout: 5))
        row("savedFood", "Grill Tuna & Prawn Pâté").tap()
        XCTAssertTrue(app.staticTexts["Grill Tuna & Prawn Pâté"].waitForExistence(timeout: 5))
        XCTAssertTrue(row("sizeCalories", "77 kcal per can").exists)
    }

    func testB_PortionPicker() {
        row("brandRow", "Tiki Cat").tap()
        row("lineRow", "After Dark").tap()
        scrollTo(row("savedFood", "Pâté Lamb & Beef Liver"))
        row("savedFood", "Pâté Lamb & Beef Liver").tap()
        let calories = app.textFields["portionCalories"]
        scrollTo(calories)

        // Starts on the first size, one whole can.
        XCTAssertEqual(calories.value as? String, "110")
        app.buttons["1/2"].tap()
        XCTAssertEqual(calories.value as? String, "55")
        attachScreenshot("Portion half")

        // Choose the other size.
        let sizePicker = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Size'")).firstMatch
        reveal(sizePicker)
        sizePicker.tap()
        app.buttons["5.5 oz can"].tap()
        scrollTo(calories)
        XCTAssertEqual(calories.value as? String, "100.5")

        // Any other amount, including more than one can.
        let amount = app.textFields["portionAmount"]
        amount.tap()
        amount.typeText("1.5")
        XCTAssertEqual(calories.value as? String, "301.5")
        XCTAssertFalse(app.buttons["1/2"].isSelected)

        // Switch to grams: starts from the same portion in grams.
        reveal(app.buttons["By grams"])
        app.buttons["By grams"].tap()
        let grams = app.textFields["portionGrams"]
        XCTAssertTrue(grams.waitForExistence(timeout: 5))
        reveal(calories)
        let gramsValue = Double(grams.value as? String ?? "") ?? 0
        XCTAssertEqual(gramsValue, 233.85, accuracy: 0.1)
        let gramsCalories = Double(calories.value as? String ?? "") ?? 0
        XCTAssertEqual(gramsCalories, 301.5, accuracy: 3)
        attachScreenshot("Portion grams")

        // Type my own calories over the worked-out number, then go back to it.
        replaceText(in: calories, with: "250")
        XCTAssertTrue(app.staticTexts["Using your own number."].waitForExistence(timeout: 5))
        let useWorkedOut = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Use worked-out number'")).firstMatch
        reveal(useWorkedOut)
        useWorkedOut.tap()
        XCTAssertEqual(Double(calories.value as? String ?? "") ?? 0, gramsCalories, accuracy: 0.05)

        // Back to cans.
        reveal(app.buttons["By can"])
        app.buttons["By can"].tap()
        reveal(calories)
        XCTAssertEqual(calories.value as? String, "301.5")
    }

    func testC_AddEditDeleteAndNoDuplicates() {
        // My own food with no brand goes under "My foods".
        addFood(name: "Home Cooked Chicken", brand: nil, line: nil, kilocaloriesPerGram: "1.5")
        XCTAssertTrue(row("brandRow", "My foods").waitForExistence(timeout: 5))
        XCTAssertTrue(row("brandRow", "My foods").label.contains("1"))

        // With a brand and line.
        addFood(name: "Chicken Recipe", brand: "Ziwi", line: "Peak", kilocaloriesPerGram: "4.3")
        XCTAssertTrue(row("brandRow", "Ziwi").waitForExistence(timeout: 5))

        // "My foods" lists products directly, and opens their details.
        row("brandRow", "My foods").tap()
        row("savedFood", "Home Cooked Chicken").tap()
        XCTAssertTrue(element(containing: "1.50 kcal/g").waitForExistence(timeout: 5))
        let calories = app.textFields["portionCalories"]
        let grams = app.textFields["portionGrams"]
        scrollTo(grams)
        grams.tap()
        grams.typeText("20")
        XCTAssertEqual(calories.value as? String, "30")

        // Edit my food.
        app.buttons["Edit"].tap()
        replaceText(in: app.textFields["Name"], with: "Boiled Chicken")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Boiled Chicken"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Swipe to delete my food.
        XCTAssertTrue(row("savedFood", "Boiled Chicken").waitForExistence(timeout: 5))
        row("savedFood", "Boiled Chicken").swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["No foods here"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Edit a loaded food's calories per can.
        row("brandRow", "Tiki Cat").tap()
        row("lineRow", "Grill").tap()
        scrollTo(row("savedFood", "Grill Tuna & Prawn Pâté"))
        row("savedFood", "Grill Tuna & Prawn Pâté").tap()
        app.buttons["Edit"].tap()
        let sizeCalories = app.textFields["sizeCaloriesField"].firstMatch
        XCTAssertEqual(sizeCalories.value as? String, "77")
        // A number far too big for the can is caught.
        replaceText(in: sizeCalories, with: "8077")
        XCTAssertTrue(app.staticTexts["8077 kcal is too much for a 2.8 oz can. Please check it."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        replaceText(in: sizeCalories, with: "80")
        app.buttons["Save"].tap()
        XCTAssertTrue(row("sizeCalories", "80 kcal per can").waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Delete a loaded food.
        scrollTo(row("savedFood", "Grill Tuna & Prawn Pâté"))
        row("savedFood", "Grill Tuna & Prawn Pâté").swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertFalse(row("savedFood", "Grill Tuna & Prawn Pâté").waitForExistence(timeout: 2))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(row("lineRow", "Grill").label.contains("12"), row("lineRow", "Grill").label)

        // After reopening: no duplicates, and the deleted food doesn't come back.
        app.terminate()
        app.launch()
        app.tabBars.buttons["Calories"].tap()
        app.buttons["Saved Foods"].tap()
        XCTAssertTrue(row("brandRow", "Tiki Cat").waitForExistence(timeout: 5))
        XCTAssertTrue(row("brandRow", "Tiki Cat").label.contains("98"), row("brandRow", "Tiki Cat").label)
        XCTAssertTrue(row("brandRow", "Ziwi").exists)
        XCTAssertFalse(row("brandRow", "My foods").exists)
        row("brandRow", "Tiki Cat").tap()
        XCTAssertTrue(row("lineRow", "Grill").label.contains("12"), row("lineRow", "Grill").label)
    }

    // MARK: - Helpers

    private func rows(_ identifier: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: identifier)
    }

    private func row(_ identifier: String, _ text: String) -> XCUIElement {
        rows(identifier).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text))
            .firstMatch
    }

    private func addFood(name: String, brand: String?, line: String?, kilocaloriesPerGram: String) {
        app.buttons["Add Food"].tap()
        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(name)
        if let brand {
            app.textFields["Brand"].tap()
            app.textFields["Brand"].typeText(brand)
        }
        if let line {
            app.textFields["Line"].tap()
            app.textFields["Line"].typeText(line)
        }
        app.textFields["Calories"].tap()
        app.textFields["Calories"].typeText(kilocaloriesPerGram)
        app.buttons["Save"].tap()
    }

    /// Selects everything in the field, then types over it.
    private func replaceText(in field: XCUIElement, with text: String) {
        field.tap()
        field.press(forDuration: 1.2)
        let selectAll = app.menuItems["Select All"]
        if selectAll.waitForExistence(timeout: 2) {
            selectAll.tap()
        } else {
            let current = field.value as? String ?? ""
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(text)
        XCTAssertEqual(field.value as? String, text)
    }

    private func scrollTo(_ element: XCUIElement) {
        for _ in 0..<10 where !(element.exists && element.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "Couldn't scroll to \(element)")
    }

    /// Scrolls up, then down if needed, until the element is on screen.
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<5 where !(element.exists && element.isHittable) {
            app.swipeDown()
        }
        scrollTo(element)
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

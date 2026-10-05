import Foundation
import Testing
@testable import MochiLife

/// CalorieVerifier rules, on small fixed page texts. No network and no model.
struct CalorieVerifierTests {
    private let source = FactSource(host: "example.com", url: URL(string: "https://example.com/p")!, isManufacturer: true, stage: "test")

    private let wetPage = """
    Grill Tuna Pâté. Net Wt. 3 oz (85 g) can. Calorie Content (ME, calculated): 1,050 kcal/kg, 89 kcal/can.
    Feeding: adult cats need 1 can per 3 lbs of body weight daily.
    """

    private func food(form: String = "wet", densities: [ExtractedFood.EnergyDensity] = [],
                      containers: [ExtractedFood.ContainerCalories] = [], sizes: [ExtractedFood.Size] = []) -> ExtractedFood {
        ExtractedFood(found: true, form: form, energyDensity: densities, containerCalories: containers, sizes: sizes)
    }

    private let threeOunceCan = ExtractedFood.Size(label: "3 oz can", weight: 3, unit: "oz", container: "can", evidence: "Net Wt. 3 oz (85 g) can")

    @Test func evidencePresentIsVerified() {
        let reading = CalorieVerifier.verify(
            food(densities: [.init(value: 1050, unit: "kcal/kg", evidence: "Calorie Content (ME, calculated): 1,050 kcal/kg")]),
            sentText: wetPage, source: source)
        #expect(reading.kilocaloriesPerGram?.value == 1.05)
        #expect(reading.kilocaloriesPerGram?.status == .verified)
    }

    @Test func evidenceAbsentIsDiscarded() {
        let reading = CalorieVerifier.verify(
            food(densities: [.init(value: 1050, unit: "kcal/kg", evidence: "Contains 1,050 kcal/kg of energy")]),
            sentText: wetPage, source: source)
        #expect(reading.kilocaloriesPerGram == nil)
        #expect(reading.rejections == ["density:not_in_source"])
    }

    @Test func valueNotInItsEvidenceIsDiscarded() {
        let reading = CalorieVerifier.verify(
            food(densities: [.init(value: 1100, unit: "kcal/kg", evidence: "1,050 kcal/kg")]),
            sentText: wetPage, source: source)
        #expect(reading.kilocaloriesPerGram == nil)
        #expect(reading.rejections == ["density:value_not_in_evidence"])
    }

    @Test func kilojoulesAreRejectedAndKilocaloriesKept() {
        let page = "Energy: 3,800 kcal/kg (15,900 kJ/kg)."
        let asKcal = CalorieVerifier.verify(
            food(form: "dry", densities: [.init(value: 15900, unit: "kcal/kg", evidence: "3,800 kcal/kg (15,900 kJ/kg)")]),
            sentText: page, source: source)
        #expect(asKcal.kilocaloriesPerGram == nil)
        #expect(asKcal.rejections == ["density:kj"])
        let kcal = CalorieVerifier.verify(
            food(form: "dry", densities: [.init(value: 3800, unit: "kcal/kg", evidence: "3,800 kcal/kg (15,900 kJ/kg)")]),
            sentText: page, source: source)
        #expect(kcal.kilocaloriesPerGram?.value == 3.8)
    }

    @Test func perCupIsNotUsedAsPerCan() {
        let page = "Net Wt. 3 oz (85 g) can. Calorie content: 1,050 kcal/kg; 238 kcal/cup."
        let reading = CalorieVerifier.verify(
            food(containers: [.init(sizeLabel: "3 oz can", value: 238, unit: "kcal", per: "cup", evidence: "238 kcal/cup")],
                 sizes: [threeOunceCan]),
            sentText: page, source: source)
        #expect(reading.sizes.count == 1)
        #expect(reading.sizes[0].kilocalories == nil)
        #expect(reading.rejections == ["container_kcal:per_cup"])
    }

    @Test func feedingGuideAmountIsRejected() {
        let reading = CalorieVerifier.verify(
            food(containers: [.init(sizeLabel: "3 oz can", value: 3, unit: "kcal", per: "can",
                                    evidence: "adult cats need 1 can per 3 lbs of body weight daily")],
                 sizes: [threeOunceCan]),
            sentText: wetPage, source: source)
        #expect(reading.rejections.contains("container_kcal:feeding_guide"))
    }

    @Test func multipackTotalIsNotAUnitSize() {
        let page = "Case of 12, 3 oz cans (36 oz total)."
        let total = CalorieVerifier.verify(
            food(sizes: [.init(label: "36 oz", weight: 36, unit: "oz", evidence: "Case of 12, 3 oz cans (36 oz total)")]),
            sentText: page, source: source)
        #expect(total.sizes.isEmpty)
        #expect(total.rejections == ["size:multipack_total"])
        let unit = CalorieVerifier.verify(
            food(sizes: [.init(label: "3 oz can", weight: 3, unit: "oz", container: "can", packCount: 12, evidence: "Case of 12, 3 oz cans")]),
            sentText: page, source: source)
        #expect(unit.sizes.first?.grams.value == 85)
    }

    @Test func consistentTripleIsVerified() {
        let reading = CalorieVerifier.verify(
            food(densities: [.init(value: 1050, unit: "kcal/kg", evidence: "1,050 kcal/kg")],
                 containers: [.init(sizeLabel: "3 oz can", value: 89, unit: "kcal", per: "can", evidence: "89 kcal/can")],
                 sizes: [threeOunceCan]),
            sentText: wetPage, source: source)
        #expect(reading.kilocaloriesPerGram?.status == .verified)
        #expect(reading.sizes.first?.kilocalories?.status == .verified)
        #expect(reading.sizes.first?.kilocalories?.value == 89)
    }

    @Test func inconsistentTripleIsConflicting() {
        let page = "Net Wt. 3 oz (85 g) can. 1,050 kcal/kg, 120 kcal/can."
        let reading = CalorieVerifier.verify(
            food(densities: [.init(value: 1050, unit: "kcal/kg", evidence: "1,050 kcal/kg")],
                 containers: [.init(sizeLabel: "3 oz can", value: 120, unit: "kcal", per: "can", evidence: "120 kcal/can")],
                 sizes: [threeOunceCan]),
            sentText: page, source: source)
        #expect(reading.kilocaloriesPerGram?.status == .conflicting)
        #expect(reading.sizes.first?.kilocalories?.status == .conflicting)
        #expect(reading.sizes.first?.kilocalories?.value == 120)
        #expect(reading.kilocaloriesPerGram?.conflict?.contains("120 kcal") == true)
    }

    @Test func missingContainerCaloriesAreCalculated() {
        let reading = CalorieVerifier.verify(
            food(densities: [.init(value: 1050, unit: "kcal/kg", evidence: "1,050 kcal/kg")], sizes: [threeOunceCan]),
            sentText: wetPage, source: source)
        #expect(reading.sizes.first?.kilocalories?.status == .calculated)
        #expect(reading.sizes.first?.kilocalories?.value == 89.3)
    }

    @Test func ouncesAndPoundsConvertToGrams() {
        let page = "Available in 5.5 oz cans and a 3.5 lb bag."
        let ounces = CalorieVerifier.verify(
            food(sizes: [.init(label: "5.5 oz can", weight: 5.5, unit: "oz", evidence: "5.5 oz cans")]),
            sentText: page, source: source)
        #expect(ounces.sizes.first?.grams.value == 155.9)
        let pounds = CalorieVerifier.verify(
            food(form: "dry", sizes: [.init(label: "3.5 lb bag", weight: 3.5, unit: "lb", evidence: "3.5 lb bag")]),
            sentText: page, source: source)
        #expect(pounds.sizes.first?.grams.value == 1587.6)
    }

    @Test func sizesAreDeduplicated() {
        let page = "Net Wt. 3 oz (85 g) can"
        let reading = CalorieVerifier.verify(
            food(sizes: [threeOunceCan, .init(label: "85 g", weight: 85, unit: "g", evidence: "85 g")]),
            sentText: page, source: source)
        #expect(reading.sizes.count == 1)
    }

    @Test func outOfRangeDensityIsRejected() {
        let page = "Calories: 9,500 kcal/kg"
        let reading = CalorieVerifier.verify(
            food(densities: [.init(value: 9500, unit: "kcal/kg", evidence: "9,500 kcal/kg")]),
            sentText: page, source: source)
        #expect(reading.kilocaloriesPerGram == nil)
        #expect(reading.rejections == ["density:out_of_range"])
    }
}

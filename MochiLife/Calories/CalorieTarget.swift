import Foundation
import SwiftData
import SwiftUI

/// Mochi's daily calorie target: either the owner's own number, or an estimate worked out from
/// her weight, age and spay status (Merck Veterinary Manual: resting energy × a life-stage factor).
enum CalorieTarget {
    case own(kilocalories: Double)
    case estimate(CalorieEstimate)
    /// Some details are missing, so no estimate is given rather than guessing.
    case missing([MissingCalorieDetail])

    /// Settings stored on the phone.
    static let ownTargetKey = "calorieTarget.own"
    static let gainsWeightEasilyKey = "calorieTarget.gainsWeightEasily"

    var dailyKilocalories: Double? {
        switch self {
        case let .own(kilocalories): kilocalories
        case let .estimate(estimate): estimate.dailyKilocalories
        case .missing: nil
        }
    }

    /// "Estimate" or "Your target", for labels next to the number.
    var label: String {
        if case .own = self { "Your target" } else { "Estimate" }
    }

    static func make(
        ownTarget: Double,
        latestWeight: WeightEntry?,
        profile: CatProfile?,
        gainsWeightEasily: Bool,
        now: Date = .now
    ) -> CalorieTarget {
        if ownTarget > 0 {
            return .own(kilocalories: ownTarget)
        }
        var missing: [MissingCalorieDetail] = []
        if latestWeight == nil { missing.append(.weight) }

        var lifeStage: CalorieEstimate.LifeStage?
        if let birthday = profile?.birthday {
            let years = Calendar.current.dateComponents([.year], from: birthday, to: now).year ?? 0
            if years < 1 {
                lifeStage = .kitten
            } else if gainsWeightEasily {
                lifeStage = .adultGainsWeightEasily
            } else {
                switch profile?.spayedOrNeutered {
                case .yes: lifeStage = .adultSpayedOrNeutered
                case .no: lifeStage = .adultNotSpayedOrNeutered
                case .notSure, nil: missing.append(.spayStatus)
                }
            }
        } else {
            missing.append(.birthday)
        }

        guard missing.isEmpty, let latestWeight, let lifeStage, let profile, let birthday = profile.birthday
        else { return .missing(missing) }

        return .estimate(CalorieEstimate(
            weightKilograms: latestWeight.kilograms,
            weightDate: latestWeight.date,
            age: CatAge.description(birthday: birthday, precision: profile.birthdayPrecision, now: now) ?? "Under 1 month",
            lifeStage: lifeStage
        ))
    }
}

struct CalorieEstimate {
    enum LifeStage {
        case kitten
        case adultSpayedOrNeutered
        case adultNotSpayedOrNeutered
        case adultGainsWeightEasily

        var factor: Double {
            switch self {
            case .kitten: 2.5
            case .adultSpayedOrNeutered: 1.2
            case .adultNotSpayedOrNeutered: 1.4
            case .adultGainsWeightEasily: 1.0
            }
        }

        var description: String {
            switch self {
            case .kitten: "kitten (under 1 year old)"
            case .adultSpayedOrNeutered: "adult, spayed or neutered"
            case .adultNotSpayedOrNeutered: "adult, not spayed or neutered"
            case .adultGainsWeightEasily: "adult who gains weight easily"
            }
        }
    }

    var weightKilograms: Double
    var weightDate: Date
    var age: String
    var lifeStage: LifeStage

    /// Resting energy: 70 × (weight in kg) to the power 0.75, in kcal per day.
    var restingEnergy: Double { 70 * pow(weightKilograms, 0.75) }

    /// Resting energy × the life-stage factor, rounded to the nearest 5 kcal.
    var dailyKilocalories: Double { ((restingEnergy * lifeStage.factor) / 5).rounded() * 5 }
}

enum MissingCalorieDetail: Hashable {
    case weight
    case birthday
    case spayStatus

    func message(catName: String) -> String {
        switch self {
        case .weight: "Add \(catName)'s weight on the Weight screen."
        case .birthday: "Add \(catName)'s birthday in \(catName)'s profile."
        case .spayStatus: "Set whether \(catName) is spayed or neutered in \(catName)'s profile."
        }
    }

    func buttonTitle(catName: String) -> String {
        switch self {
        case .weight: "Go to Weight"
        case .birthday, .spayStatus: "Go to Profile"
        }
    }

    var screen: AppScreen {
        switch self {
        case .weight: .weight
        case .birthday, .spayStatus: .profile
        }
    }
}

/// Reads everything the calorie target depends on and hands the result to its content.
struct CalorieTargetReader<Content: View>: View {
    @ViewBuilder let content: (CalorieTarget) -> Content

    @Query private var profiles: [CatProfile]
    @Query(sort: [SortDescriptor(\WeightEntry.date, order: .reverse), SortDescriptor(\WeightEntry.createdAt, order: .reverse)])
    private var weights: [WeightEntry]
    @AppStorage(CalorieTarget.ownTargetKey) private var ownTarget = 0.0
    @AppStorage(CalorieTarget.gainsWeightEasilyKey) private var gainsWeightEasily = false

    var body: some View {
        content(CalorieTarget.make(
            ownTarget: ownTarget,
            latestWeight: weights.first,
            profile: profiles.current,
            gainsWeightEasily: gainsWeightEasily
        ))
    }
}

/// Shows what's missing for an estimate, with a button to go and fill it in.
struct MissingCalorieDetailsView: View {
    let missing: [MissingCalorieDetail]

    @Environment(\.openScreen) private var openScreen
    @Environment(\.catName) private var catName

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("To estimate \(catName)'s daily calories:")
                .font(.subheadline.weight(.medium))
            ForEach(missing, id: \.self) { detail in
                HStack {
                    Text(detail.message(catName: catName))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(detail.buttonTitle(catName: catName)) { openScreen(detail.screen) }
                        .buttonStyle(.bordered)
                        .font(.subheadline)
                }
            }
        }
    }
}

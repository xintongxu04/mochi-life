import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case weight
    case calories
    case mochi
}

/// Switches to another tab, for buttons like "Go to Weight".
struct OpenTabAction {
    fileprivate var selection: Binding<AppTab>?

    func callAsFunction(_ tab: AppTab) {
        selection?.wrappedValue = tab
    }
}

extension EnvironmentValues {
    @Entry var openTab = OpenTabAction()
}

struct ContentView: View {
    @State private var selectedTab = AppTab.weight

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Weight", systemImage: "scalemass", value: .weight) {
                WeightView()
            }
            Tab("Calories", systemImage: "fork.knife", value: .calories) {
                CaloriesView()
            }
            Tab("Mochi", systemImage: "pawprint", value: .mochi) {
                MochiView()
            }
        }
        .environment(\.openTab, OpenTabAction(selection: $selectedTab))
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [WeightEntry.self, Food.self, FoodLogEntry.self, CatProfile.self, Vaccination.self, MedicalRecord.self], inMemory: true)
}

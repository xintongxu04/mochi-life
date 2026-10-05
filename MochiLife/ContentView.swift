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
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [CatProfile]
    @State private var selectedTab = AppTab.weight

    private var catName: String { profiles.current?.displayName ?? CatProfile.defaultName }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Weight", systemImage: "scalemass", value: .weight) {
                WeightView()
            }
            Tab("Calories", systemImage: "fork.knife", value: .calories) {
                CaloriesView()
            }
            Tab(catName, systemImage: "pawprint", value: .mochi) {
                MochiView()
            }
        }
        .environment(\.openTab, OpenTabAction(selection: $selectedTab))
        .environment(\.catName, catName)
        .task { LaunchMaintenance.run(in: modelContext) }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [WeightEntry.self, Food.self, FoodLogEntry.self, CatProfile.self, Vaccination.self, MedicalRecord.self], inMemory: true)
}

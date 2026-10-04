import SwiftData
import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Weight", systemImage: "scalemass") {
                WeightView()
            }
            Tab("Calories", systemImage: "fork.knife") {
                CaloriesView()
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [WeightEntry.self, Food.self], inMemory: true)
}

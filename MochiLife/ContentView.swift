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
            Tab("Mochi", systemImage: "pawprint") {
                MochiView()
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [WeightEntry.self, Food.self, FoodLogEntry.self, CatProfile.self, Vaccination.self, MedicalRecord.self], inMemory: true)
}

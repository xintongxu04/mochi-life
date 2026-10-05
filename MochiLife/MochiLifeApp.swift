import SwiftData
import SwiftUI

@main
struct MochiLifeApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(for: WeightEntry.self, Food.self, FoodLogEntry.self)
        } catch {
            fatalError("Couldn't open Mochi Life's saved data: \(error)")
        }
        FoodLibraryLoader.loadBundledLibrariesIfNeeded(into: modelContainer.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}

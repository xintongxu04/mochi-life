import SwiftData
import SwiftUI

@main
struct MochiLifeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: WeightEntry.self)
    }
}

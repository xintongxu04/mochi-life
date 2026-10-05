import SwiftData
import SwiftUI

@main
struct MochiLifeApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(
                for: Schema(versionedSchema: SchemaV3.self),
                migrationPlan: MochiLifeMigrationPlan.self
            )
        } catch {
            fatalError("Couldn't open Mochi Life's saved data: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}

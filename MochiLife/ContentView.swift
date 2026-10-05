import SwiftData
import SwiftUI

/// Opens a screen on the main navigation stack, for buttons like "Go to Weight".
struct OpenScreenAction {
    fileprivate weak var home: MochiHome?

    @MainActor
    func callAsFunction(_ screen: AppScreen) {
        home?.push(screen)
    }
}

extension EnvironmentValues {
    @Entry var openScreen = OpenScreenAction()
}

/// The app's single screen: Calories, with Mochi floating above it. Weight, Mochi's profile and
/// Settings are pushed from the ring of actions around her, drawn over everything.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var profiles: [CatProfile]
    @State private var home = MochiHome()
    /// A backup file opened from Files, AirDrop or the share sheet.
    @State private var openedBackup: RestoreSource?

    private var catName: String { profiles.current?.displayName ?? CatProfile.defaultName }

    var body: some View {
        CaloriesView()
            // Floating Mochi: a full-screen root layer in screen points, so scrolling can't move her.
            .overlay {
                if !home.isSpriteHidden {
                    FloatingMochiView(home: home)
                }
            }
            .overlay {
                if home.isMenuOpen {
                    RadialActionMenu(home: home)
                        .transition(.opacity)
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: home.isMenuOpen) { _, isOpen in isOpen }
            .environment(home)
            .environment(\.openScreen, OpenScreenAction(home: home))
            .environment(\.foodLogged, FoodLoggedAction(home: home))
            .environment(\.catName, catName)
            .task { LaunchMaintenance.run(in: modelContext) }
            // Scheduled feedings catch up whenever the app comes back and when the day or clock changes.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { ScheduleMaterializer(context: modelContext).materialize() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
                ScheduleMaterializer(context: modelContext).materialize()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                ScheduleMaterializer(context: modelContext).materialize()
            }
            .onOpenURL { url in
                guard url.pathExtension.lowercased() == BackupFormat.fileExtension else { return }
                home.isMenuOpen = false
                openedBackup = RestoreSource(url: url)
            }
            .onChange(of: openedBackup != nil) { _, isOpen in home.isRestoring = isOpen }
            .sheet(item: $openedBackup) { source in
                RestoreFlowView(url: source.url)
            }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [WeightEntry.self, Food.self, FoodLogEntry.self, CatProfile.self, Vaccination.self, MedicalRecord.self, FeedingSchedule.self], inMemory: true)
}

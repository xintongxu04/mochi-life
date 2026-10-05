import SwiftUI

/// The Calories tab. For now it opens straight onto saved foods; later features (like logging
/// meals or daily totals) can be added here, with saved foods one tap away.
struct CaloriesView: View {
    var body: some View {
        NavigationStack {
            SavedFoodsView()
        }
    }
}

#Preview {
    CaloriesView()
        .modelContainer(for: Food.self, inMemory: true)
}

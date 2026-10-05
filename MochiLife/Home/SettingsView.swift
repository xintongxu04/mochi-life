import SwiftUI

/// App settings, opened from the ring around Mochi: the weight unit, the AI lookup keys, and
/// backup and restore.
struct SettingsView: View {
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .kilograms

    var body: some View {
        Form {
            Section {
                Picker("Weight unit", selection: $weightUnit) {
                    ForEach(WeightUnit.allCases) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Units")
            } footer: {
                Text("Weights are always saved in kilograms; this only changes how they're shown and typed.")
            }

            AILookupSettingsSections()

            Section {
                NavigationLink {
                    BackupRestoreView()
                } label: {
                    Label("Back Up and Restore", systemImage: "externaldrive")
                }
            } header: {
                Text("Backup")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

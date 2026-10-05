import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// "Back Up and Restore": export everything to a .mochibackup file, restore from one, and the
/// automatic safety backups made before each restore.
struct BackupRestoreView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.catName) private var catName
    @AppStorage(BackupFiles.lastExportKey) private var lastExport: Double = 0
    @State private var exportTask: Task<Void, Never>?
    @State private var exportedFile: URL?
    @State private var exportError: String?
    @State private var isImporting = false
    @State private var restoreSource: RestoreSource?
    @State private var safetyBackups = BackupFiles.safetyBackups()

    private var isExporting: Bool { exportTask != nil }

    var body: some View {
        Form {
            Section {
                LabeledContent("Last backup", value: lastExport > 0
                    ? Date(timeIntervalSinceReferenceDate: lastExport).formatted(date: .abbreviated, time: .shortened)
                    : "Never")
                if isExporting {
                    HStack {
                        ProgressView()
                        Text("Making a backup…")
                        Spacer()
                        Button("Cancel") { exportTask?.cancel() }
                    }
                } else {
                    Button("Back Up Now", systemImage: "square.and.arrow.up", action: export)
                }
                if let exportedFile {
                    ShareLink(item: exportedFile) {
                        Label("Share or Save \(exportedFile.lastPathComponent)", systemImage: "square.and.arrow.up.on.square")
                    }
                }
            } header: {
                Text("Back up")
            } footer: {
                if let exportError {
                    Text(exportError).foregroundStyle(.red)
                } else {
                    Text("Share the file with AirDrop, or save it to Files or iCloud Drive.")
                }
            }

            Section {
                Button("Restore from File", systemImage: "square.and.arrow.down") { isImporting = true }
            } header: {
                Text("Restore")
            } footer: {
                Text("Restoring replaces all data on this iPhone with the backup. A safety backup of the current data is made first.")
            }

            Section("Safety backups") {
                if safetyBackups.isEmpty {
                    Text("None yet. One is made automatically before each restore.")
                        .foregroundStyle(.secondary)
                }
                ForEach(safetyBackups) { backup in
                    Button {
                        restoreSource = RestoreSource(url: backup.url)
                    } label: {
                        LabeledContent("Restore", value: backup.date.formatted(date: .abbreviated, time: .shortened))
                    }
                    .accessibilityLabel("Restore the safety backup from \(backup.date.formatted(date: .long, time: .shortened))")
                }
                .onDelete { offsets in
                    for index in offsets { try? FileManager.default.removeItem(at: safetyBackups[index].url) }
                    safetyBackups = BackupFiles.safetyBackups()
                }
            }

            Section {
                Text("A backup contains \(catName)'s health records, weights and food log in readable form. Keep backup files private. API keys are never included.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Back Up and Restore")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.mochiBackup]) { result in
            if case let .success(url) = result { restoreSource = RestoreSource(url: url) }
        }
        .sheet(item: $restoreSource, onDismiss: { safetyBackups = BackupFiles.safetyBackups() }) { source in
            RestoreFlowView(url: source.url)
        }
        .onDisappear { exportTask?.cancel() }
    }

    private func export() {
        exportError = nil
        exportedFile = nil
        let container = modelContext.container
        exportTask = Task {
            do {
                exportedFile = try await BackupFiles.exportCurrentData(container: container)
            } catch is CancellationError {
            } catch {
                exportError = "The backup couldn't be made. \(error.localizedDescription)"
            }
            exportTask = nil
        }
    }
}

struct RestoreSource: Identifiable {
    var url: URL
    var id: URL { url }
}

/// Reads and checks a backup, shows what it holds next to what's on this iPhone, and replaces
/// the data only after an explicit confirmation (making a safety backup first).
struct RestoreFlowView: View {
    let url: URL

    private enum Phase {
        case reading
        case summary(PreparedRestore)
        case restoring
        case done
        case failed(String)
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var phase = Phase.reading
    @State private var isConfirming = false
    @State private var readTask: Task<Void, Never>?
    @State private var currentCounts = BackupCounts()

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .reading:
                    progress("Checking the backup…", cancellable: true)
                case let .summary(prepared):
                    summary(prepared)
                case .restoring:
                    progress("Restoring…", cancellable: false)
                case .done:
                    ContentUnavailableView {
                        Label("Restored", systemImage: "checkmark.circle")
                    } description: {
                        Text("All data on this iPhone now comes from the backup.")
                    } actions: {
                        Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
                    }
                case let .failed(message):
                    ContentUnavailableView {
                        Label("Can't Restore", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Close") { dismiss() }
                    }
                }
            }
            .navigationTitle("Restore Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if case .summary = phase {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { discardAndClose() }
                    }
                }
            }
            .interactiveDismissDisabled(isRestoring)
        }
        .task { read() }
    }

    private var isRestoring: Bool {
        if case .restoring = phase { true } else { false }
    }

    private func progress(_ text: String, cancellable: Bool) -> some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text(text).font(.headline)
            if cancellable {
                Button("Cancel") {
                    readTask?.cancel()
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func summary(_ prepared: PreparedRestore) -> some View {
        let envelope = prepared.envelope
        let backup = prepared.counts
        return Form {
            Section("Backup") {
                LabeledContent("Made", value: envelope.createdAt.formatted(date: .long, time: .shortened))
                LabeledContent("On", value: envelope.deviceName)
                LabeledContent("App version", value: envelope.appVersion)
            }
            Section {
                countRow("Weights", backup.weights, currentCounts.weights)
                countRow("Your foods", backup.foods, currentCounts.foods)
                countRow("Edited Tiki Cat foods", backup.editedSeedFoods, currentCounts.editedSeedFoods)
                countRow("Deleted Tiki Cat foods", backup.deletedSeedFoods, currentCounts.deletedSeedFoods)
                countRow("Food log entries", backup.foodLog, currentCounts.foodLog)
                countRow("Feeding schedules", backup.schedules, currentCounts.schedules)
                countRow("Profile", backup.hasProfile ? 1 : 0, currentCounts.hasProfile ? 1 : 0)
                countRow("Vaccinations", backup.vaccinations, currentCounts.vaccinations)
                countRow("Medical history", backup.medicalRecords, currentCounts.medicalRecords)
                countRow("Photos", backup.photos, currentCounts.photos)
            } header: {
                HStack {
                    Text("Records")
                    Spacer()
                    Text("Backup · This iPhone")
                }
            }
            Section {
                Button("Replace All Data on This iPhone", role: .destructive) { isConfirming = true }
                    .frame(maxWidth: .infinity)
            } footer: {
                Text("Everything on this iPhone is replaced by the backup. A safety backup of the current data is saved first, and you can restore it from Back Up and Restore.")
            }
        }
        .confirmationDialog("Replace all data on this iPhone?", isPresented: $isConfirming, titleVisibility: .visible) {
            Button("Replace All Data", role: .destructive) { restore(prepared) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone, except by restoring the safety backup.")
        }
    }

    private func countRow(_ label: String, _ backup: Int, _ current: Int) -> some View {
        LabeledContent(label) {
            Text("\(backup) · \(current)").monospacedDigit()
        }
        .accessibilityLabel("\(label): \(backup) in the backup, \(current) on this iPhone")
    }

    private func read() {
        readTask = Task {
            do {
                let prepared = try await BackupReader.prepare(from: url)
                currentCounts = await currentDeviceCounts()
                phase = .summary(prepared)
            } catch is CancellationError {
            } catch let error as BackupError {
                phase = .failed(error.message)
            } catch {
                phase = .failed(BackupError.unreadableFile.message)
            }
        }
    }

    private func currentDeviceCounts() async -> BackupCounts {
        let container = modelContext.container
        let (settings, deleted) = BackupSettings.read(from: .standard)
        guard let envelope = try? await BackupService(modelContainer: container)
            .makeEnvelope(settings: settings, deletedSeedIDs: deleted, deviceName: "")
        else { return BackupCounts() }
        return BackupCounts(envelope.payload, files: envelope.files)
    }

    private func restore(_ prepared: PreparedRestore) {
        phase = .restoring
        let container = modelContext.container
        Task {
            do {
                try await BackupFiles.writeSafetyBackup(container: container)
            } catch {
                prepared.discardStaging()
                phase = .failed("A safety backup of the current data couldn't be saved, so nothing was changed.")
                return
            }
            do {
                try BackupRestorer.restore(prepared, into: modelContext)
                phase = .done
            } catch let error as BackupError {
                phase = .failed(error.message)
            } catch {
                phase = .failed(BackupError.saveFailed.message)
            }
        }
    }

    private func discardAndClose() {
        if case let .summary(prepared) = phase { prepared.discardStaging() }
        dismiss()
    }
}

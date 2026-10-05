import SwiftData
import SwiftUI

/// Adds something to Mochi's medical history, or edits it when `record` is set.
struct MedicalRecordFormView: View {
    let record: MedicalRecord?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date.now
    @State private var title = ""
    @State private var kind = MedicalRecordKind.vetVisit
    @State private var clinic = ""
    @State private var notes = ""

    init(record: MedicalRecord?) {
        self.record = record
        guard let record else { return }
        _date = State(initialValue: record.date)
        _title = State(initialValue: record.title)
        _kind = State(initialValue: record.kind)
        _clinic = State(initialValue: record.clinic ?? "")
        _notes = State(initialValue: record.notes ?? "")
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What happened, like Dental cleaning", text: $title)
                    Picker("Type", selection: $kind) {
                        ForEach(MedicalRecordKind.allCases) { kind in
                            Label(kind.label, systemImage: kind.systemImage).tag(kind)
                        }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Vet or clinic", text: $clinic)
                        .textInputAutocapitalization(.words)
                }
                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle(record == nil ? "Add to History" : "Edit History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(trimmedTitle.isEmpty)
                }
            }
        }
    }

    private func optional(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func save() {
        let record = record ?? {
            let new = MedicalRecord(date: date, title: trimmedTitle, kind: kind)
            modelContext.insert(new)
            return new
        }()
        record.date = date
        record.title = trimmedTitle
        record.kind = kind
        record.clinic = optional(clinic)
        record.notes = optional(notes)
        try? modelContext.save()
        dismiss()
    }
}

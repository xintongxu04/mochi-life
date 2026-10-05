import SwiftData
import SwiftUI

/// Adds a vaccination, or edits one when `vaccination` is set.
struct VaccinationFormView: View {
    let vaccination: Vaccination?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var dateGiven = Date.now
    @State private var hasNextDue = false
    @State private var nextDue = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    @State private var notes = ""

    init(vaccination: Vaccination?) {
        self.vaccination = vaccination
        guard let vaccination else { return }
        _name = State(initialValue: vaccination.name)
        _dateGiven = State(initialValue: vaccination.dateGiven)
        if let nextDue = vaccination.nextDue {
            _hasNextDue = State(initialValue: true)
            _nextDue = State(initialValue: nextDue)
        }
        _notes = State(initialValue: vaccination.notes ?? "")
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Vaccine, like FVRCP or Rabies", text: $name)
                    DatePicker("Given", selection: $dateGiven, displayedComponents: .date)
                }
                Section {
                    Toggle("Next due date", isOn: $hasNextDue.animation())
                    if hasNextDue {
                        DatePicker("Next due", selection: $nextDue, displayedComponents: .date)
                    }
                } footer: {
                    Text("Use the date from your vet's records.")
                }
                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .navigationTitle(vaccination == nil ? "Add Vaccination" : "Edit Vaccination")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
    }

    private func save() {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let vaccination = vaccination ?? {
            let new = Vaccination(name: trimmedName, dateGiven: dateGiven)
            modelContext.insert(new)
            return new
        }()
        vaccination.name = trimmedName
        vaccination.dateGiven = dateGiven
        vaccination.nextDue = hasNextDue ? nextDue : nil
        vaccination.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        if Persistence.save(modelContext) { dismiss() }
    }
}

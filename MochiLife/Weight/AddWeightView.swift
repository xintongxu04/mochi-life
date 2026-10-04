import SwiftData
import SwiftUI

struct AddWeightView: View {
    let unit: WeightUnit

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date.now
    @State private var weightText = ""

    private var weight: Double? { WeightUnit.parseWeight(weightText) }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                HStack {
                    TextField("Weight", text: $weightText)
                        .keyboardType(.decimalPad)
                    Text(unit.rawValue)
                        .foregroundStyle(.secondary)
                }
                if !weightText.isEmpty && weight == nil {
                    Text("Enter a weight like 4.25, with up to two decimal places.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Add Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(weight == nil)
                }
            }
        }
    }

    private func save() {
        guard let weight else { return }
        modelContext.insert(WeightEntry(date: date, kilograms: unit.kilograms(from: weight)))
        try? modelContext.save()
        dismiss()
    }
}

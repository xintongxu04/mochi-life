import SwiftData
import SwiftUI

/// The Mochi tab: her basic facts, vaccinations and medical history.
struct MochiView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [CatProfile]
    @Query(sort: \Vaccination.dateGiven, order: .reverse) private var vaccinations: [Vaccination]
    @Query(sort: \MedicalRecord.date, order: .reverse) private var medicalRecords: [MedicalRecord]
    @Query(sort: [SortDescriptor(\WeightEntry.date, order: .reverse), SortDescriptor(\WeightEntry.createdAt, order: .reverse)])
    private var weights: [WeightEntry]
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .kilograms

    @State private var isEditingProfile = false
    @State private var isAddingVaccination = false
    @State private var vaccinationBeingEdited: Vaccination?
    @State private var isAddingMedicalRecord = false
    @State private var medicalRecordBeingEdited: MedicalRecord?

    private var profile: CatProfile? { profiles.current }

    var body: some View {
        NavigationStack {
            List {
                header
                detailsSection
                vaccinationsSection
                medicalHistorySection
            }
            .navigationTitle(profile?.displayName ?? CatProfile.defaultName)
            .toolbar {
                Button("Edit") { isEditingProfile = true }
            }
            .sheet(isPresented: $isEditingProfile) {
                ProfileFormView(profile: profile)
            }
            .sheet(isPresented: $isAddingVaccination) {
                VaccinationFormView(vaccination: nil)
            }
            .sheet(item: $vaccinationBeingEdited) { vaccination in
                VaccinationFormView(vaccination: vaccination)
            }
            .sheet(isPresented: $isAddingMedicalRecord) {
                MedicalRecordFormView(record: nil)
            }
            .sheet(item: $medicalRecordBeingEdited) { record in
                MedicalRecordFormView(record: record)
            }
        }
    }

    private var header: some View {
        Section {
            VStack(spacing: 8) {
                CatPhoto(data: profile?.photoData, size: 120)
                if let ageText {
                    Text(ageText)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .listRowBackground(Color.clear)
    }

    private var ageText: String? {
        guard let profile, let birthday = profile.birthday else { return nil }
        return CatAge.description(birthday: birthday, precision: profile.birthdayPrecision)
    }

    private var birthdayText: String? {
        guard let profile, let birthday = profile.birthday else { return nil }
        switch profile.birthdayPrecision {
        case .exact: return birthday.formatted(date: .abbreviated, time: .omitted)
        case .approximate: return "Around \(birthday.formatted(.dateTime.month(.abbreviated).year()))"
        case .yearOnly: return birthday.formatted(.dateTime.year())
        }
    }

    private var latestWeightText: String? {
        guard let latest = weights.first else { return nil }
        return "\(weightUnit.formatted(kilograms: latest.kilograms)) · \(latest.date.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private var detailsSection: some View {
        Section("Details") {
            DetailRow(label: "Birthday", value: birthdayText.map { text in
                ageText.map { "\(text) (\($0.lowercased()))" } ?? text
            })
            DetailRow(label: "Breed", value: profile?.breed)
            DetailRow(label: "Color & markings", value: profile?.colorAndMarkings)
            DetailRow(label: "Sex", value: profile?.sex?.label)
            DetailRow(label: "Spayed or neutered", value: profile?.spayedOrNeutered?.label)
            DetailRow(label: "Microchip", value: profile?.microchipNumber)
            DetailRow(label: "Latest weight", value: latestWeightText)
            if let notes = profile?.notes {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(notes)
                }
            }
        }
    }

    private var vaccinationsSection: some View {
        Section("Vaccinations") {
            ForEach(vaccinations) { vaccination in
                Button {
                    vaccinationBeingEdited = vaccination
                } label: {
                    VaccinationRow(vaccination: vaccination)
                }
                .tint(.primary)
            }
            .onDelete { offsets in
                for index in offsets { modelContext.delete(vaccinations[index]) }
                Persistence.save(modelContext)
            }
            if vaccinations.isEmpty {
                Text("No vaccinations yet")
                    .foregroundStyle(.secondary)
            }
            Button("Add Vaccination", systemImage: "plus") { isAddingVaccination = true }
        }
    }

    private var medicalHistorySection: some View {
        Section("Medical History") {
            ForEach(medicalRecords) { record in
                Button {
                    medicalRecordBeingEdited = record
                } label: {
                    MedicalRecordRow(record: record)
                }
                .tint(.primary)
            }
            .onDelete { offsets in
                for index in offsets { modelContext.delete(medicalRecords[index]) }
                Persistence.save(modelContext)
            }
            if medicalRecords.isEmpty {
                Text("Nothing here yet")
                    .foregroundStyle(.secondary)
            }
            Button("Add to History", systemImage: "plus") { isAddingMedicalRecord = true }
        }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String?

    var body: some View {
        LabeledContent(label) {
            Text(value ?? "–")
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct VaccinationRow: View {
    let vaccination: Vaccination

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(vaccination.name)
                    .font(.body.weight(.medium))
                Spacer()
                switch vaccination.dueStatus() {
                case .overdue:
                    StatusBadge(text: "Overdue", color: .red)
                case .dueSoon:
                    StatusBadge(text: "Due soon", color: .orange)
                case nil:
                    EmptyView()
                }
            }
            Text(detailText)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let notes = vaccination.notes {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var detailText: String {
        var parts = ["Given \(vaccination.dateGiven.formatted(date: .abbreviated, time: .omitted))"]
        if let nextDue = vaccination.nextDue {
            parts.append("next due \(nextDue.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: " · ")
    }
}

private struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color, in: .capsule)
    }
}

private struct MedicalRecordRow: View {
    let record: MedicalRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: record.kind.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(record.title)
                    .font(.body.weight(.medium))
                Text([record.kind.label, record.date.formatted(date: .abbreviated, time: .omitted), record.clinic]
                    .compactMap(\.self).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let notes = record.notes {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}

/// Mochi's photo in a circle, or a paw print if there's no photo yet.
struct CatPhoto: View {
    let data: Data?
    let size: CGFloat

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.fill.tertiary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .accessibilityHidden(true)
    }
}

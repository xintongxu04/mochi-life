import PhotosUI
import SwiftData
import SwiftUI

/// Edits Mochi's basic facts. Creates her profile the first time it's saved.
struct ProfileFormView: View {
    let profile: CatProfile?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var photoData: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var isTakingPhoto = false
    @State private var name = CatProfile.defaultName
    @State private var hasBirthday = false
    @State private var birthday = Date.now
    @State private var birthdayPrecision = BirthdayPrecision.exact
    @State private var birthYear = Calendar.current.component(.year, from: .now)
    @State private var breed = ""
    @State private var colorAndMarkings = ""
    @State private var sex: CatSex?
    @State private var spayedOrNeutered: YesNoUnsure?
    @State private var microchipNumber = ""
    @State private var notes = ""

    init(profile: CatProfile?) {
        self.profile = profile
        guard let profile else { return }
        _photoData = State(initialValue: profile.photoData)
        _name = State(initialValue: profile.name ?? CatProfile.defaultName)
        if let date = profile.birthday {
            _hasBirthday = State(initialValue: true)
            _birthday = State(initialValue: date)
            _birthYear = State(initialValue: Calendar.current.component(.year, from: date))
        }
        _birthdayPrecision = State(initialValue: profile.birthdayPrecision)
        _breed = State(initialValue: profile.breed ?? "")
        _colorAndMarkings = State(initialValue: profile.colorAndMarkings ?? "")
        _sex = State(initialValue: profile.sex)
        _spayedOrNeutered = State(initialValue: profile.spayedOrNeutered)
        _microchipNumber = State(initialValue: profile.microchipNumber ?? "")
        _notes = State(initialValue: profile.notes ?? "")
    }

    private var currentYear: Int { Calendar.current.component(.year, from: .now) }

    var body: some View {
        NavigationStack {
            Form {
                photoSection
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                }
                birthdaySection
                Section {
                    TextField("Breed", text: $breed)
                        .textInputAutocapitalization(.words)
                    TextField("Color & markings", text: $colorAndMarkings)
                    Picker("Sex", selection: $sex) {
                        Text("Not set").tag(CatSex?.none)
                        ForEach(CatSex.allCases) { Text($0.label).tag(CatSex?.some($0)) }
                    }
                    Picker("Spayed or neutered", selection: $spayedOrNeutered) {
                        Text("Not set").tag(YesNoUnsure?.none)
                        ForEach(YesNoUnsure.allCases) { Text($0.label).tag(YesNoUnsure?.some($0)) }
                    }
                    TextField("Microchip number", text: $microchipNumber)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Notes") {
                    TextField("Anything else worth remembering", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section {
                } footer: {
                    Text("Latest weight comes from the Weight screen.")
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .onChange(of: photoItem) {
                Task { await loadPickedPhoto() }
            }
            .fullScreenCover(isPresented: $isTakingPhoto) {
                CameraPicker { image in
                    photoData = image.resizedForProfile()
                }
                .ignoresSafeArea()
            }
        }
    }

    private var photoSection: some View {
        Section {
            VStack(spacing: 12) {
                CatPhoto(data: photoData, size: 120)
                HStack(spacing: 12) {
                    PhotosPicker("Choose Photo", selection: $photoItem, matching: .images)
                    if CameraPicker.isAvailable {
                        Button("Take Photo") { isTakingPhoto = true }
                    }
                    if photoData != nil {
                        Button("Remove", role: .destructive) {
                            photoData = nil
                            photoItem = nil
                        }
                    }
                }
                .buttonStyle(.bordered)
                .font(.subheadline)
            }
            .frame(maxWidth: .infinity)
        }
        .listRowBackground(Color.clear)
    }

    private var birthdaySection: some View {
        Section("Birthday") {
            Toggle("Add birthday", isOn: $hasBirthday.animation())
            if hasBirthday {
                Picker("How sure", selection: $birthdayPrecision) {
                    ForEach(BirthdayPrecision.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                if birthdayPrecision == .yearOnly {
                    Picker("Year", selection: $birthYear) {
                        ForEach((currentYear - 30...currentYear).reversed(), id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                } else {
                    DatePicker("Date", selection: $birthday, in: ...Date.now, displayedComponents: .date)
                }
            }
        }
    }

    private func loadPickedPhoto() async {
        guard let photoItem,
              let data = try? await photoItem.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else { return }
        photoData = image.resizedForProfile()
    }

    private func optional(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func save() {
        let profile = profile ?? CatProfile.current(in: modelContext)
        profile.photoData = photoData
        profile.name = optional(name)
        if hasBirthday {
            profile.birthdayPrecision = birthdayPrecision
            if birthdayPrecision == .yearOnly {
                // Stored as mid-year so the worked-out age is never off by a whole year.
                profile.birthday = Calendar.current.date(from: DateComponents(year: birthYear, month: 7, day: 1))
            } else {
                profile.birthday = birthday
            }
        } else {
            profile.birthday = nil
        }
        profile.breed = optional(breed)
        profile.colorAndMarkings = optional(colorAndMarkings)
        profile.sex = sex
        profile.spayedOrNeutered = spayedOrNeutered
        profile.microchipNumber = optional(microchipNumber)
        profile.notes = optional(notes)
        if Persistence.save(modelContext) { dismiss() }
    }
}

private extension UIImage {
    /// Shrinks the photo so it doesn't take much space, and saves it as a JPEG.
    func resizedForProfile(maxDimension: CGFloat = 800) -> Data? {
        let scale = min(1, maxDimension / max(size.width, size.height))
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }
}

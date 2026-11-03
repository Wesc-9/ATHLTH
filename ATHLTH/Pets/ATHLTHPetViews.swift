import PhotosUI
import SwiftUI
import UIKit
import Supabase

private enum ATHLTHPetStyle {
    static let ink = ATHLTHTheme.primaryText
    static let muted = ATHLTHTheme.mutedText
    static let gold = ATHLTHTheme.premiumGold
    static let bronze = ATHLTHTheme.accentDeep
    static let border = ATHLTHTheme.border
}

struct ATHLTHPetAvatar: View {
    let pet: ATHLTHPet
    var size: CGFloat = 52
    @EnvironmentObject private var pets: ATHLTHPetStore

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27)
                .fill(ATHLTHTheme.accentSoft)
            if let url = pets.photoURLs[pet.id] {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Image(systemName: "pawprint.fill")
                            .font(.system(size: size * 0.35))
                            .foregroundStyle(ATHLTHPetStyle.bronze)
                    }
                }
            } else {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: size * 0.35))
                    .foregroundStyle(ATHLTHPetStyle.bronze)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.27))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.27)
                .stroke(ATHLTHPetStyle.gold.opacity(0.28), lineWidth: 1)
        }
        .accessibilityLabel(pet.name)
    }
}

struct ATHLTHPetsSettingsView: View {
    @EnvironmentObject private var pets: ATHLTHPetStore
    @State private var showingCreate = false
    @State private var editingPet: ATHLTHPet?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Label(
                        ATHLTHLocalization.choose(english: "My pets", norwegian: "Mine kjæledyr"),
                        systemImage: "pawprint.fill"
                    )
                    .font(.system(size: 29, weight: .regular, design: .serif))
                    .foregroundStyle(ATHLTHPetStyle.ink)
                    Text(ATHLTHLocalization.choose(
                        english: "Your companions on walks, runs and other workouts.",
                        norwegian: "Dine turkamerater på gåturer, løpeturer og andre økter."))
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHPetStyle.muted)
                }
                ATHLTHCard {
                    if pets.pets.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(ATHLTHLocalization.choose(
                                english: "No pets added", norwegian: "Ingen kjæledyr lagt til"),
                                systemImage: "pawprint")
                                .font(.headline)
                            Text(ATHLTHLocalization.choose(
                                english: "No pet controls appear elsewhere in ATHLTH until you add one.",
                                norwegian: "Ingen kjæledyrvalg vises ellers i ATHLTH før du legger til et dyr."))
                                .font(.subheadline)
                                .foregroundStyle(ATHLTHPetStyle.muted)
                        }
                    } else {
                        ForEach(pets.pets) { pet in
                            NavigationLink {
                                ATHLTHPetDetailView(petID: pet.id)
                            } label: {
                                HStack(spacing: 13) {
                                    ATHLTHPetAvatar(pet: pet, size: 54)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(pet.name)
                                            .font(.headline)
                                            .foregroundStyle(ATHLTHPetStyle.ink)
                                        Text(([pet.breed, pet.speciesName]
                                            .compactMap { $0 }
                                            .joined(separator: " · ")))
                                            .font(.caption)
                                            .foregroundStyle(ATHLTHPetStyle.muted)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.tertiary)
                                }
                                .frame(minHeight: 60)
                            }
                            .buttonStyle(.plain)
                            if pet.id != pets.pets.last?.id { Divider() }
                        }
                    }
                }

                Button {
                    showingCreate = true
                } label: {
                    Label(
                        ATHLTHLocalization.choose(english: "Add pet", norwegian: "Legg til kjæledyr"),
                        systemImage: "plus"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHPetStyle.bronze)

                Text(ATHLTHLocalization.choose(
                    english: "Pets and workout associations stay private to you unless you explicitly make a pet public. Pet information is not written into Apple Health.",
                    norwegian: "Kjæledyr og tilknyttede økter er private med mindre du gjør kjæledyret offentlig. Dyreopplysninger skrives ikke til Apple Helse."))
                    .font(.caption)
                    .foregroundStyle(ATHLTHPetStyle.muted)

                if let errorMessage = pets.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(18)
            .frame(maxWidth: 740)
            .frame(maxWidth: .infinity)
        }
        .background(ATHLTHTheme.cardWarm.opacity(0.28))
        .navigationTitle(ATHLTHLocalization.choose(english: "My pets", norwegian: "Mine kjæledyr"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingCreate) {
            ATHLTHPetEditorView()
                .environmentObject(pets)
        }
        .task { await pets.refresh() }
    }
}

struct ATHLTHPetEditorView: View {
    @EnvironmentObject private var pets: ATHLTHPetStore
    @Environment(\.dismiss) private var dismiss

    let editing: ATHLTHPet?
    @State private var draft: ATHLTHPetDraft
    @State private var weightText: String
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var jpegData: Data?
    @State private var removePhoto = false
    @State private var saving = false
    @State private var showingDelete = false

    init(editing: ATHLTHPet? = nil) {
        self.editing = editing
        _draft = State(initialValue: ATHLTHPetDraft(pet: editing))
        _weightText = State(initialValue: editing?.weightKG.map { String(format: "%g", $0) } ?? "")
    }

    private var hasPhoto: Bool {
        jpegData != nil || (!removePhoto && editing?.photoPath != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 9) {
                            if let jpegData, let image = UIImage(data: jpegData) {
                                Image(uiImage: image)
                                    .resizable().scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: 25))
                            } else if let editing, !removePhoto {
                                ATHLTHPetAvatar(pet: editing, size: 100)
                            } else {
                                Image(systemName: "pawprint.fill")
                                    .font(.system(size: 36))
                                    .foregroundStyle(ATHLTHPetStyle.bronze)
                                    .frame(width: 100, height: 100)
                                    .background(ATHLTHTheme.accentSoft, in: RoundedRectangle(cornerRadius: 25))
                            }
                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                Label(ATHLTHLocalization.choose(
                                    english: "Choose photo", norwegian: "Velg bilde"),
                                    systemImage: "photo.on.rectangle")
                            }
                            .font(.subheadline)
                            if hasPhoto {
                                Button(ATHLTHLocalization.choose(
                                    english: "Remove photo", norwegian: "Fjern bilde")) {
                                    jpegData = nil
                                    removePhoto = true
                                    selectedPhoto = nil
                                }
                                .font(.caption)
                                .foregroundStyle(.red)
                            }
                        }
                        Spacer()
                    }
                }
                Section(ATHLTHLocalization.choose(english: "About your pet", norwegian: "Om kjæledyret")) {
                    TextField(ATHLTHLocalization.choose(english: "Name", norwegian: "Navn"), text: $draft.name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                    Picker(ATHLTHLocalization.choose(english: "Animal", norwegian: "Dyretype"), selection: $draft.species) {
                        Text(ATHLTHLocalization.choose(english: "Dog", norwegian: "Hund")).tag("dog")
                        Text(ATHLTHLocalization.choose(english: "Cat", norwegian: "Katt")).tag("cat")
                        Text(ATHLTHLocalization.choose(english: "Horse", norwegian: "Hest")).tag("horse")
                        Text(ATHLTHLocalization.choose(english: "Other", norwegian: "Annet")).tag("other")
                    }
                    TextField(ATHLTHLocalization.choose(english: "Breed (optional)", norwegian: "Rase (valgfritt)"), text: $draft.breed)
                    Toggle(ATHLTHLocalization.choose(english: "Birth date", norwegian: "Fødselsdato"), isOn: Binding(
                        get: { draft.birthDate != nil },
                        set: { draft.birthDate = $0 ? (draft.birthDate ?? Date()) : nil }
                    ))
                    if draft.birthDate != nil {
                        DatePicker(
                            ATHLTHLocalization.choose(english: "Born", norwegian: "Født"),
                            selection: Binding(
                                get: { draft.birthDate ?? Date() },
                                set: { draft.birthDate = $0 }
                            ),
                            in: ...Date(),
                            displayedComponents: .date)
                    }
                    HStack {
                        Text(ATHLTHLocalization.choose(english: "Weight", norwegian: "Vekt"))
                        Spacer()
                        TextField("kg", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("kg").foregroundStyle(.secondary)
                    }
                }
                Section(ATHLTHLocalization.choose(english: "Visibility", norwegian: "Synlighet")) {
                    Toggle(ATHLTHLocalization.choose(
                        english: "Show on my profile", norwegian: "Vis på min profil"),
                        isOn: $draft.showOnProfile)
                    Toggle(ATHLTHLocalization.choose(
                        english: "Visible to other ATHLTH users", norwegian: "Synlig for andre ATHLTH-brukere"),
                        isOn: $draft.isPublic)
                        .disabled(!draft.showOnProfile)
                    Text(ATHLTHLocalization.choose(
                        english: "Your pet stays private by default. Public sharing only applies when both switches are enabled.",
                        norwegian: "Kjæledyret er privat som standard. Andre kan bare se det når begge valgene er på."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if editing != nil {
                    Section {
                        Button(ATHLTHLocalization.choose(
                            english: "Delete pet", norwegian: "Slett kjæledyr"), role: .destructive) {
                            showingDelete = true
                        }
                    }
                }
                if let message = pets.errorMessage {
                    Section { Text(message).font(.caption).foregroundStyle(.red) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ATHLTHTheme.cardWarm.opacity(0.23))
            .navigationTitle(editing == nil
                ? ATHLTHLocalization.choose(english: "Add pet", norwegian: "Legg til kjæledyr")
                : ATHLTHLocalization.choose(english: "Edit pet", norwegian: "Rediger kjæledyr"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(ATHLTHLocalization.choose(english: "Cancel", norwegian: "Avbryt")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(ATHLTHLocalization.choose(english: "Save", norwegian: "Lagre")) {
                        Task { await save() }
                    }
                    .disabled(saving || draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                Task {
                    guard let bytes = try? await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: bytes) else { return }
                    let maxDimension: CGFloat = 1200
                    let factor = min(1, maxDimension / max(image.size.width, image.size.height))
                    let targetSize = CGSize(width: image.size.width * factor, height: image.size.height * factor)
                    let renderer = UIGraphicsImageRenderer(size: targetSize)
                    let scaled = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: targetSize)) }
                    jpegData = scaled.jpegData(compressionQuality: 0.77)
                    removePhoto = false
                }
            }
            .confirmationDialog(
                ATHLTHLocalization.choose(
                    english: "Delete this pet and its activity history?",
                    norwegian: "Slette kjæledyret og aktivitetshistorikken?"),
                isPresented: $showingDelete,
                titleVisibility: .visible) {
                    Button(ATHLTHLocalization.choose(english: "Delete", norwegian: "Slett"), role: .destructive) {
                        guard let editing else { return }
                        Task {
                            if await pets.delete(editing) { dismiss() }
                        }
                    }
                }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let raw = weightText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty {
            guard let value = Double(raw.replacingOccurrences(of: ",", with: ".")), value > 0 else {
                pets.errorMessage = ATHLTHLocalization.choose(
                    english: "Enter a valid weight.", norwegian: "Oppgi en gyldig vekt.")
                return
            }
            draft.weightKG = value
        } else {
            draft.weightKG = nil
        }
        if await pets.save(draft: draft, editing: editing, jpegData: jpegData, removePhoto: removePhoto) {
            dismiss()
        }
    }
}

struct ATHLTHPetProfileSection: View {
    @EnvironmentObject private var pets: ATHLTHPetStore

    var body: some View {
        if !pets.visiblePets.isEmpty {
            ATHLTHCard {
                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        Label(ATHLTHLocalization.choose(
                            english: "My companions", norwegian: "Mine turkamerater"),
                            systemImage: "pawprint.fill")
                            .font(.headline)
                            .foregroundStyle(ATHLTHPetStyle.ink)
                        Spacer()
                        NavigationLink {
                            ATHLTHPetsSettingsView()
                        } label: {
                            Image(systemName: "chevron.right")
                                .foregroundStyle(ATHLTHPetStyle.bronze)
                        }
                    }
                    ForEach(pets.visiblePets) { pet in
                        NavigationLink {
                            ATHLTHPetDetailView(petID: pet.id)
                        } label: {
                            HStack(spacing: 12) {
                                ATHLTHPetAvatar(pet: pet, size: 52)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(pet.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(ATHLTHPetStyle.ink)
                                    let stats = pets.stats(for: pet)
                                    Text(String(format: "%d %@ · %.1f km",
                                        stats.outings,
                                        ATHLTHLocalization.choose(english: "outings", norwegian: "turer"),
                                        stats.meters / 1000))
                                        .font(.caption)
                                        .foregroundStyle(ATHLTHPetStyle.muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        if pet.id != pets.visiblePets.last?.id { Divider() }
                    }
                }
            }
        }
    }
}

private struct ATHLTHPetMonthlyActivity: Identifiable {
    let month: Date
    let meters: Double
    let outings: Int
    var id: Date { month }
}

struct ATHLTHPetDetailView: View {
    @EnvironmentObject private var pets: ATHLTHPetStore
    let petID: UUID
    @State private var showingEdit = false

    private var pet: ATHLTHPet? { pets.pets.first { $0.id == petID } }

    var body: some View {
        ScrollView {
            if let pet {
                VStack(alignment: .leading, spacing: 16) {
                    ATHLTHCard {
                        HStack(alignment: .center, spacing: 16) {
                            ATHLTHPetAvatar(pet: pet, size: 96)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(pet.name)
                                    .font(.system(size: 27, weight: .regular, design: .serif))
                                Text([pet.breed, pet.speciesName]
                                    .compactMap { $0 }.joined(separator: " · "))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                if let date = pet.birthDate.flatMap(ATHLTHPetDate.date(from:)) {
                                    Text(date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let kg = pet.weightKG {
                                    Text(String(format: "%.1f kg", kg))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                    }
                    let stats = pets.stats(for: pet)
                    HStack(spacing: 10) {
                        metric(ATHLTHLocalization.choose(english: "Outings", norwegian: "Turer"), value: "\(stats.outings)")
                        metric(ATHLTHLocalization.choose(english: "Distance", norwegian: "Distanse"), value: String(format: "%.1f km", stats.meters / 1000))
                        metric(ATHLTHLocalization.choose(english: "Active time", norwegian: "Aktiv tid"), value: String(format: "%.1f t", stats.seconds / 3600))
                    }
                    ATHLTHCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label(ATHLTHLocalization.choose(
                                    english: "Activity over time", norwegian: "Aktivitet over tid"),
                                    systemImage: "chart.bar.xaxis")
                                    .font(.headline)
                                Spacer()
                                Text(ATHLTHLocalization.choose(
                                    english: "Last 6 months", norwegian: "Siste 6 måneder"))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            let months = monthlyActivity(for: pet)
                            let maximum = max(months.map(\.meters).max() ?? 0, 1)
                            ForEach(months) { item in
                                VStack(spacing: 5) {
                                    HStack {
                                        Text(item.month.formatted(.dateTime.month(.abbreviated)))
                                            .font(.caption.weight(.medium))
                                        Spacer()
                                        Text(String(format: "%.1f km", item.meters / 1000))
                                            .font(.caption.weight(.semibold))
                                            .monospacedDigit()
                                        Text("· \(item.outings)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    ProgressView(value: item.meters, total: maximum)
                                        .tint(ATHLTHTheme.premiumGold)
                                }
                            }
                            Divider()
                            HStack {
                                Text(ATHLTHLocalization.choose(
                                    english: "Longest outing", norwegian: "Lengste tur"))
                                    .font(.subheadline)
                                Spacer()
                                Text(String(format: "%.2f km", stats.longestMeters / 1000))
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                    ATHLTHCard {
                        VStack(alignment: .leading, spacing: 11) {
                            Text(ATHLTHLocalization.choose(english: "Activity history", norwegian: "Aktivitetshistorikk"))
                                .font(.headline)
                            if pets.usage(for: pet).isEmpty {
                                Text(ATHLTHLocalization.choose(
                                    english: "Add this companion to a walk or workout to begin tracking activity.",
                                    norwegian: "Legg til turkameraten i en tur eller økt for å starte aktivitetsoversikten."))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(pets.usage(for: pet)) { entry in
                                HStack {
                                    Image(systemName: "figure.walk")
                                        .foregroundStyle(ATHLTHPetStyle.bronze)
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.workoutTitle)
                                            .font(.subheadline.weight(.medium))
                                        Text(entry.startedAt.formatted(date: .abbreviated, time: .omitted))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 3) {
                                        Text(String(format: "%.2f km", (entry.distanceMeters ?? 0) / 1000))
                                            .font(.caption.weight(.semibold))
                                        if entry.distanceIsEstimated {
                                            Text(ATHLTHLocalization.choose(english: "Estimated", norwegian: "Estimert"))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                if entry.id != pets.usage(for: pet).last?.id { Divider() }
                            }
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: 740)
                .frame(maxWidth: .infinity)
            }
        }
        .background(ATHLTHTheme.cardWarm.opacity(0.24))
        .navigationTitle(pet?.name ?? ATHLTHLocalization.choose(english: "Pet", norwegian: "Kjæledyr"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if pet != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(ATHLTHLocalization.choose(english: "Edit", norwegian: "Rediger")) {
                        showingEdit = true
                    }
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            if let pet {
                ATHLTHPetEditorView(editing: pet)
                    .environmentObject(pets)
            }
        }
    }

    private func monthlyActivity(for pet: ATHLTHPet) -> [ATHLTHPetMonthlyActivity] {
        let calendar = Calendar.current
        let thisMonth = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
        let records = pets.usage(for: pet)
        return (0..<6).reversed().compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: -offset, to: thisMonth),
                  let next = calendar.date(byAdding: .month, value: 1, to: month) else {
                return nil
            }
            let outings = records.filter { $0.startedAt >= month && $0.startedAt < next }
            return ATHLTHPetMonthlyActivity(
                month: month,
                meters: outings.reduce(0) { $0 + ($1.distanceMeters ?? 0) },
                outings: outings.count)
        }
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 72)
        .background(ATHLTHTheme.accentSoft.opacity(0.63), in: RoundedRectangle(cornerRadius: 15))
    }
}

struct ATHLTHWorkoutPetSelectionCard: View {
    @EnvironmentObject private var pets: ATHLTHPetStore
    @Binding var selectedPetIDs: Set<UUID>

    var body: some View {
        if !pets.pets.isEmpty {
            ATHLTHCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(ATHLTHLocalization.choose(
                            english: "With pets", norwegian: "Med kjæledyr"),
                            systemImage: "pawprint.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ATHLTHPetStyle.ink)
                        Spacer()
                        Text(ATHLTHLocalization.choose(english: "Optional", norwegian: "Valgfritt"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(pets.pets) { pet in
                        Button {
                            if selectedPetIDs.contains(pet.id) {
                                selectedPetIDs.remove(pet.id)
                            } else {
                                selectedPetIDs.insert(pet.id)
                            }
                        } label: {
                            HStack(spacing: 11) {
                                ATHLTHPetAvatar(pet: pet, size: 37)
                                Text(pet.name)
                                    .font(.subheadline)
                                    .foregroundStyle(ATHLTHPetStyle.ink)
                                Spacer()
                                Image(systemName: selectedPetIDs.contains(pet.id)
                                    ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedPetIDs.contains(pet.id)
                                        ? ATHLTHPetStyle.bronze : .secondary)
                                    .font(.title3)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(pet.name)
                        .accessibilityAddTraits(selectedPetIDs.contains(pet.id) ? [.isSelected] : [])
                    }
                }
            }
        }
    }
}

struct ATHLTHLivePetSelectionCard: View {
    @EnvironmentObject private var pets: ATHLTHPetStore
    let distanceMeters: Double?

    var body: some View {
        if !pets.pets.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label(ATHLTHLocalization.choose(
                    english: "Companions on this workout", norwegian: "Turkamerater på denne økten"),
                    systemImage: "pawprint.fill")
                    .font(.subheadline.weight(.semibold))
                ForEach(pets.pets) { pet in
                    Button {
                        var ids = pets.activePetIDs
                        if ids.contains(pet.id) { ids.remove(pet.id) }
                        else { ids.insert(pet.id) }
                        pets.updateActiveWorkoutPets(ids, distanceMeters: distanceMeters)
                    } label: {
                        HStack {
                            ATHLTHPetAvatar(pet: pet, size: 32)
                            Text(pet.name)
                            Spacer()
                            Image(systemName: pets.activePetIDs.contains(pet.id)
                                ? "checkmark.circle.fill" : "circle")
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct ATHLTHWorkoutPetHistoryCard: View {
    @EnvironmentObject private var pets: ATHLTHPetStore
    let workout: SocialPublishableWorkout

    var body: some View {
        let linked = pets.pets.filter { pets.petIDs(for: workout.id).contains($0.id) }
        if !linked.isEmpty {
            ATHLTHUnifiedCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label(ATHLTHLocalization.choose(
                        english: "Companions", norwegian: "Turkamerater"),
                        systemImage: "pawprint.fill")
                        .font(.headline)
                    ForEach(linked) { pet in
                        NavigationLink {
                            ATHLTHPetDetailView(petID: pet.id)
                        } label: {
                            HStack(spacing: 10) {
                                ATHLTHPetAvatar(pet: pet, size: 40)
                                Text(pet.name)
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                if let record = pets.usage.first(where: {
                                    $0.petID == pet.id && $0.workoutID == workout.id
                                }) {
                                    Text(String(format: "%.2f km", (record.distanceMeters ?? 0) / 1000))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

 
/// Only opt-in public companions appear on other people's ATHLTH profiles.
/// Workout history and private animal details are never fetched here.
struct ATHLTHPublicPetProfileSection: View {
    let userID: UUID
    @State private var publicPets: [ATHLTHPet] = []
    @State private var photoURLs: [UUID: URL] = [:]

    var body: some View {
        Group {
            if !publicPets.isEmpty {
            ATHLTHCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label(ATHLTHLocalization.choose(
                        english: "Companions", norwegian: "Turkamerater"),
                        systemImage: "pawprint.fill")
                        .font(.headline)
                        .foregroundStyle(ATHLTHTheme.primaryText)
                    ForEach(publicPets) { pet in
                        HStack(spacing: 11) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 13)
                                    .fill(ATHLTHTheme.accentSoft)
                                if let url = photoURLs[pet.id] {
                                    AsyncImage(url: url) { phase in
                                        if let image = phase.image {
                                            image.resizable().scaledToFill()
                                        } else {
                                            Image(systemName: "pawprint.fill")
                                                .foregroundStyle(ATHLTHTheme.premiumGold)
                                        }
                                    }
                                } else {
                                    Image(systemName: "pawprint.fill")
                                        .foregroundStyle(ATHLTHTheme.premiumGold)
                                }
                            }
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 13))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(pet.name)
                                    .font(.subheadline.weight(.semibold))
                                Text([pet.breed, pet.speciesName]
                                    .compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        if pet.id != publicPets.last?.id { Divider() }
                    }
                }
            }
            }
        }
        .task(id: userID) { await load() }
    }

    private func load() async {
        do {
            let rows: [ATHLTHPet] = try await SupabaseEnvironment.client
                .from("profile_pets")
                .select().eq("user_id", value: userID)
                .eq("is_public", value: true)
                .eq("show_on_profile", value: true)
                .execute().value
            publicPets = rows
            var URLs: [UUID: URL] = [:]
            for pet in rows {
                guard let path = pet.photoPath,
                      let URL = try? await SupabaseEnvironment.client.storage
                        .from("pet-photos")
                        .createSignedURL(path: path, expiresIn: 3600)
                else { continue }
                URLs[pet.id] = URL
            }
            photoURLs = URLs
        } catch {
            // Pet sharing is optional and must never block another profile.
            publicPets = []
            photoURLs = [:]
        }
    }
}

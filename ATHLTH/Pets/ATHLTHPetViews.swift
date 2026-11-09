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

/// Optional and compact profile entry. No card appears until an athlete
/// explicitly opts a pet into their profile, and pet privacy is preserved.
/// Optional profile preview: a compact, premium link to full pet details.
/// All pet identity and statistics remain available in the detail screen.
struct ATHLTHPetProfileSection: View {
    @EnvironmentObject private var pets: ATHLTHPetStore

    var body: some View {
        Group {
            if !pets.visiblePets.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "pawprint.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(ATHLTHPetStyle.bronze)
                            .frame(width: 29, height: 29)
                            .background(
                                ATHLTHTheme.premiumGoldSoft.opacity(0.50),
                                in: RoundedRectangle(cornerRadius: 9)
                            )
                        Text(ATHLTHLocalization.choose(
                            english: "Training companions",
                            norwegian: "Mine turkamerater"
                        ))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ATHLTHPetStyle.ink)
                        Spacer(minLength: 0)
                        Text("\(pets.visiblePets.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHPetStyle.muted)
                    }

                    ForEach(pets.visiblePets) { pet in
                        NavigationLink {
                            ATHLTHPetDetailView(petID: pet.id)
                        } label: {
                            HStack(spacing: 9) {
                                ATHLTHPetAvatar(pet: pet, size: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pet.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(ATHLTHPetStyle.ink)
                                    Text(pet.breed ?? pet.speciesName)
                                        .font(.caption)
                                        .foregroundStyle(ATHLTHPetStyle.muted)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(ATHLTHPetStyle.muted)
                            }
                            .padding(.horizontal, 9)
                            .frame(minHeight: 51)
                            .background(
                                Color.white.opacity(0.82),
                                in: RoundedRectangle(cornerRadius: 13)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(11)
                .background(
                    LinearGradient(
                        colors: [.white.opacity(0.97),
                                 ATHLTHTheme.premiumGoldSoft.opacity(0.13)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 21, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .strokeBorder(ATHLTHPetStyle.border.opacity(0.53), lineWidth: 0.8)
                }
            }
        }
        .task {
            if pets.pets.isEmpty { await pets.refresh() }
        }
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
                    english: "Manage your pets and their activity here. Choose who joins a workout from its optional pet menu. Pet data is not written to Apple Health.",
                    norwegian: "Administrer kjæledyr og aktivitet her. Velg hvem som blir med fra den valgfrie turkameratmenyen under trening. Kjæledyrdata skrives ikke til Apple Helse."))
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
        // Keep legacy storage fields for old records, but new edits do not
        // publish pets on the user's public or personal profile.
        draft.showOnProfile = false
        draft.isPublic = false
        if await pets.save(draft: draft, editing: editing, jpegData: jpegData, removePhoto: removePhoto) {
            dismiss()
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

/// A single compact menu replaces the large multi-row card.
/// The selected pet IDs are the same binding used by the workout engine.
struct ATHLTHWorkoutPetSelectionCard: View {
    @EnvironmentObject private var pets: ATHLTHPetStore
    @Binding var selectedPetIDs: Set<UUID>

    private var selectedNames: String {
        let names = pets.pets.filter { selectedPetIDs.contains($0.id) }
            .map(\.name)
        if names.isEmpty {
            return ATHLTHLocalization.choose(
                english: "Choose", norwegian: "Velg"
            )
        }
        return names.joined(separator: ", ")
    }

    var body: some View {
        if !pets.pets.isEmpty {
            Menu {
                ForEach(pets.pets) { pet in
                    Button {
                        if selectedPetIDs.contains(pet.id) {
                            selectedPetIDs.remove(pet.id)
                        } else {
                            selectedPetIDs.insert(pet.id)
                        }
                    } label: {
                        Label(pet.name, systemImage: selectedPetIDs.contains(pet.id)
                            ? "checkmark.circle.fill" : "circle")
                    }
                }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "pawprint.fill")
                        .foregroundStyle(ATHLTHPetStyle.bronze)
                    Text(ATHLTHLocalization.choose(
                        english: "Companion", norwegian: "Turkamerat"
                    ))
                    .foregroundStyle(ATHLTHPetStyle.ink)
                    Spacer(minLength: 4)
                    Text(selectedNames)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(ATHLTHPetStyle.muted)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(ATHLTHPetStyle.bronze)
                }
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Color.white.opacity(0.9),
                            in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityHint(ATHLTHLocalization.choose(
                english: "Choose one or more pets for the workout",
                norwegian: "Velg ett eller flere kjæledyr som blir med"
            ))
        }
    }
}

/// Live edits preserve the existing participation/partial-distance logic.
struct ATHLTHLivePetSelectionCard: View {
    @EnvironmentObject private var pets: ATHLTHPetStore
    let distanceMeters: Double?

    var body: some View {
        if !pets.pets.isEmpty {
            Menu {
                ForEach(pets.pets) { pet in
                    Button {
                        var ids = pets.activePetIDs
                        if ids.contains(pet.id) {
                            ids.remove(pet.id)
                        } else {
                            ids.insert(pet.id)
                        }
                        pets.updateActiveWorkoutPets(
                            ids, distanceMeters: distanceMeters
                        )
                    } label: {
                        Label(pet.name, systemImage:
                            pets.activePetIDs.contains(pet.id)
                                ? "checkmark.circle.fill" : "circle")
                    }
                }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "pawprint.fill")
                        .foregroundStyle(ATHLTHPetStyle.bronze)
                    Text(ATHLTHLocalization.choose(
                        english: "Companion", norwegian: "Turkamerat"
                    ))
                    .font(.subheadline.weight(.medium))
                    Spacer(minLength: 4)
                    let selected = pets.pets.filter {
                        pets.activePetIDs.contains($0.id)
                    }.map(\.name)
                    Text(selected.isEmpty
                         ? ATHLTHLocalization.choose(
                            english: "Add", norwegian: "Legg til")
                         : selected.joined(separator: ", "))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(ATHLTHPetStyle.muted)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(ATHLTHPetStyle.bronze)
                }
                .foregroundStyle(ATHLTHPetStyle.ink)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Color.white.opacity(0.9),
                            in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityHint(ATHLTHLocalization.choose(
                english: "Update companions without interrupting the workout",
                norwegian: "Endre turkamerater uten å avbryte økten"
            ))
        }
    }
}

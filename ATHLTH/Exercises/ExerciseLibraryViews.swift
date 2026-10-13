import AVKit
import PhotosUI
import Supabase
import SwiftUI
import UniformTypeIdentifiers
import UIKit

enum ExerciseLibrarySection: String, CaseIterable, Identifiable {
    case library
    case mine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library:
            return ATHLTHLocalization.choose(
                english: "ATHLTH Library", norwegian: "ATHLTH-bibliotek"
            )
        case .mine:
            return ATHLTHLocalization.choose(
                english: "My Exercises", norwegian: "Mine øvelser"
            )
        }
    }
}

struct ExerciseLibraryView: View {
    @EnvironmentObject private var library: ExerciseLibraryStore
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var favorites: LibraryFavoritesStore
    @EnvironmentObject private var recents: LibraryRecentsStore

    let source: ExerciseLibrarySection?
    let selectionTitle: String?
    let selectedExerciseCounts: [UUID: Int]
    let onSelect: ((ExerciseLibraryEntry) -> Void)?

    @State private var query = ""
    @State private var selectedBodyPart = "All"
    @State private var selectedEquipment = "All"
    @State private var favoritesOnly = false
    @State private var showingCreateExercise = false
    @State private var selectedSection: ExerciseLibrarySection = .library

    init(
        source: ExerciseLibrarySection? = nil,
        initialBodyPart: String = "All",
        selectionTitle: String? = nil,
        selectedExerciseCounts: [UUID: Int] = [:],
        onSelect: ((ExerciseLibraryEntry) -> Void)? = nil
    ) {
        self.source = source
        _selectedSection = State(initialValue: source ?? .library)
        self.selectionTitle = selectionTitle
        self.selectedExerciseCounts = selectedExerciseCounts
        self.onSelect = onSelect
        _selectedBodyPart = State(initialValue: initialBodyPart)
    }

    private var results: [ExerciseLibraryEntry] {
        library.search(
            query: query,
            bodyPart: selectedBodyPart,
            equipment: selectedEquipment
        )
        .filter { entry in
            let sourceMatches: Bool
            switch selectedSection {
            case .library:
                sourceMatches = entry.source != .custom
            case .mine:
                sourceMatches = entry.source == .custom
            }

            let favoriteMatches =
                !favoritesOnly ||
                favorites.isFavorite(
                    .exercise,
                    itemID: entry.id.uuidString
                )

            return sourceMatches && favoriteMatches
        }
    }

    private static let exerciseAlphabet:
        [String] = [
            "A", "B", "C", "D", "E", "F",
            "G", "H", "I", "J", "K", "L",
            "M", "N", "O", "P", "Q", "R",
            "S", "T", "U", "V", "W", "X",
            "Y", "Z", "Æ", "Ø", "Å"
        ]

    private var displayedResults:
        [ExerciseLibraryEntry] {
        let trimmedQuery =
            query.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard trimmedQuery.isEmpty else {
            return results
        }

        return results.sorted {
            $0.name.localizedStandardCompare(
                $1.name
            ) == .orderedAscending
        }
    }

    private var firstExerciseIDByLetter:
        [String: UUID] {
        var firstIDs: [String: UUID] = [:]

        for entry in displayedResults {
            let letter =
                exerciseIndexLetter(
                    for: entry.name
                )

            if firstIDs[letter] == nil {
                firstIDs[letter] = entry.id
            }
        }

        return firstIDs
    }

    private func exerciseIndexLetter(
        for name: String
    ) -> String {
        guard let first =
                name
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .first
        else {
            return "#"
        }

        let letter =
            String(first)
                .uppercased(
                    with:
                        Locale(
                            identifier: "nb_NO"
                        )
                )

        return Self.exerciseAlphabet
            .contains(letter)
            ? letter
            : "#"
    }

    private var selectedSectionIndex:
        Binding<Int> {
        Binding(
            get: {
                selectedSection == .mine
                    ? 1
                    : 0
            },
            set: { index in
                selectedSection =
                    index == 1
                        ? .mine
                        : .library
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if source == nil {
                ATHLTHPremiumSegmentedControl(
                    titles:
                        ExerciseLibrarySection
                            .allCases
                            .map(\.title),
                    selection:
                        selectedSectionIndex
                )
                .padding(.horizontal)
                .padding(.top, 10)
                .padding(.bottom, 4)
            }

            filters

            if selectedSection == .library &&
                library.isLoading &&
                library.athlthCatalogExercises.isEmpty {
                ProgressView(ATHLTHLocalization.choose(
                    english: "Loading exercises…", norwegian: "Laster øvelser…"
                ))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if results.isEmpty {
                if selectedSection == .mine && query.isEmpty {
                    ContentUnavailableView {
                        Label("No custom exercises yet", systemImage: "dumbbell")
                    } description: {
                        Text("Create your own exercise and it will appear here.")
                    } actions: {
                        Button("Create Exercise") {
                            showingCreateExercise = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ATHLTHTheme.accent)
                    }
                } else {
                    ContentUnavailableView(
                        query.isEmpty ? "No exercises" : "No matches",
                        systemImage: "dumbbell",
                        description: Text(
                            selectedSection == .library
                                ? (library.errorMessage ?? "Try another search or filter.")
                                : "Try another search or filter."
                        )
                    )
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(
                                displayedResults
                            ) { entry in
                                ZStack(
                                    alignment:
                                        .topTrailing
                                ) {
                                    NavigationLink {
                                        ExerciseDetailView(
                                            entry: entry,
                                            selectionTitle:
                                                selectionTitle,
                                            onSelect:
                                                onSelect
                                        )
                                    } label: {
                                        exerciseRow(entry)
                                    }
                                    .buttonStyle(.plain)
                                    .simultaneousGesture(
                                        TapGesture().onEnded {
                                            recordExerciseSelection(entry)
                                        }
                                    )

                                    if let onSelect {
                                        Button {
                                            recordExerciseSelection(entry)
                                            onSelect(entry)
                                        } label: {
                                            VStack(spacing: 3) {
                                                Image(systemName: "plus")
                                                    .font(.system(size: 18, weight: .bold))
                                                Text(
                                                    ATHLTHLocalization.choose(
                                                        english: "Add",
                                                        norwegian: "Legg til"
                                                    )
                                                )
                                                .font(.system(size: 10, weight: .semibold))
                                            }
                                            .foregroundStyle(ATHLTHTheme.accentDeep)
                                            .frame(width: 62, height: 53)
                                            .background(
                                                Color.white.opacity(0.90),
                                                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            )
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                    .stroke(ATHLTHTheme.accent.opacity(0.20), lineWidth: 0.8)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(
                                            ATHLTHLocalization.choose(
                                                english: "Add " + library.localizedExerciseName(entry) + " to workout",
                                                norwegian: "Legg til " + library.localizedExerciseName(entry) + " i økten"
                                            )
                                        )
                                        .padding(8)
                                    } else {
                                        LibraryFavoriteButton(
                                            kind: .exercise,
                                            itemID: entry.id.uuidString,
                                            title: entry.name,
                                            subtitle: [
                                                entry.bodyPart,
                                                entry.exercise.equipment.first
                                            ]
                                            .compactMap { $0 }
                                            .joined(separator: " · "),
                                            icon: "dumbbell.fill"
                                        )
                                        .padding(8)
                                    }
                                }
                                .id(entry.id)
                            }

                            if selectedSection == .library,
                               let attributionURL =
                                    URL(
                                        string:
                                            "https://repdb.co"
                                    ) {
                                Link(
                                    destination:
                                        attributionURL
                                ) {
                                    HStack(
                                        spacing: 5
                                    ) {
                                        Text(
                                            "Exercise data by RepDB"
                                        )
                                        Image(
                                            systemName:
                                                "arrow.up.right"
                                        )
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(
                                        ATHLTHTheme
                                            .mutedText
                                    )
                                }
                                .padding(.top, 8)
                                .padding(
                                    .bottom,
                                    4
                                )
                            }
                        }
                        .padding(.leading, 16)
                        .padding(.trailing, 34)
                        .padding(.vertical, 16)
                    }
                    .overlay(
                        alignment: .trailing
                    ) {
                        if query
                            .trimmingCharacters(
                                in:
                                    .whitespacesAndNewlines
                            )
                            .isEmpty {
                            exerciseAlphabetIndex(
                                proxy: proxy
                            )
                            .padding(.trailing, 4)
                        }
                    }
                }
            }
        }
        .background(
            ATHLTHPremiumCanvas(
                accent:
                    ATHLTHTheme.accent
            )
        )
        .navigationTitle(selectionTitle ?? "Exercises")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if selectedSection == .mine {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingCreateExercise = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create exercise")
                }
            }
        }
        .sheet(isPresented: $showingCreateExercise) {
            CustomExerciseEditorView()
                .environmentObject(library)
                .environmentObject(session)
        }
        .task {
            recents.refresh()
            async let exerciseRefresh: Void = library.refresh()
            async let favoriteRefresh: Void = favorites.refresh()
            _ = await (exerciseRefresh, favoriteRefresh)
        }
        .refreshable {
            await library.refresh(force: true)
        }
    }

    private func exerciseAlphabetIndex(
        proxy: ScrollViewProxy
    ) -> some View {
        let targets =
            firstExerciseIDByLetter

        return VStack(spacing: 0) {
            ForEach(
                Self.exerciseAlphabet,
                id: \.self
            ) { letter in
                let targetID =
                    targets[letter]

                Button {
                    guard let targetID else {
                        return
                    }

                    withAnimation(
                        .easeOut(
                            duration: 0.18
                        )
                    ) {
                        proxy.scrollTo(
                            targetID,
                            anchor: .top
                        )
                    }
                } label: {
                    Text(letter)
                        .font(
                            .system(
                                size: 8.5,
                                weight:
                                    targetID == nil
                                        ? .medium
                                        : .bold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(
                            targetID == nil
                                ? ATHLTHTheme
                                    .mutedText
                                    .opacity(0.24)
                                : ATHLTHTheme
                                    .accentDeep
                        )
                        .frame(
                            width: 22,
                            height: 14
                        )
                        .contentShape(
                            Rectangle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(
                    targetID == nil
                )
                .accessibilityLabel(
                    ATHLTHLocalization.format(
                        english:
                            "Jump to exercises beginning with %@",
                        norwegian:
                            "Hopp til øvelser som begynner på %@",
                        letter
                    )
                )
            }
        }
        .padding(.vertical, 6)
        .background(
            .ultraThinMaterial,
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(
                    Color.white.opacity(
                        0.60
                    ),
                    lineWidth: 0.6
                )
        }
        .shadow(
            color:
                Color.black.opacity(
                    0.05
                ),
            radius: 8,
            y: 3
        )
    }

    private var filters: some View {
        VStack(spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField(
                    ATHLTHLocalization.choose(
                        english: "Search exercise, muscle or equipment",
                        norwegian: "Søk øvelse på norsk eller engelsk"
                    ),
                    text: $query
                )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(11)
            .background(
                LinearGradient(
                    colors: [
                        ATHLTHTheme.card,
                        ATHLTHTheme.cardWarm
                            .opacity(0.58)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
                .stroke(
                    Color.white.opacity(0.72),
                    lineWidth: 0.8
                )
            }
            .shadow(
                color:
                    ATHLTHTheme.accentDeep
                        .opacity(0.055),
                radius: 10,
                x: 0,
                y: 5
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if onSelect == nil {
                    Button {
                        favoritesOnly.toggle()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "star.fill")
                            Text(
                                ATHLTHLocalization.choose(
                                    english: "Favorites",
                                    norwegian: "Favoritter"
                                )
                            )
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(
                            favoritesOnly
                                ? Color.white
                                : Color.primary
                        )
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(
                            favoritesOnly
                                ? ATHLTHTheme.accent
                                : ATHLTHTheme.cardWarm
                                    .opacity(0.72),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                    }

                    Menu {
                        Button(
                            ATHLTHLocalization.choose(
                                english: "All",
                                norwegian: "Alle"
                            )
                        ) { selectedBodyPart = "All" }
                        ForEach(library.bodyParts, id: \.self) { part in
                            Button(
                                library.localizedBodyPartTitle(
                                    part
                                )
                            ) {
                                selectedBodyPart = part
                            }
                        }
                    } label: {
                        filterChip(
                            selectedBodyPart == "All"
                                ? ATHLTHLocalization.choose(
                                    english: "Muscle group",
                                    norwegian: "Muskelgruppe"
                                )
                                : library.localizedBodyPartTitle(
                                    selectedBodyPart
                                ),
                            active: selectedBodyPart != "All"
                        )
                    }

                    Menu {
                        Button(
                            ATHLTHLocalization.choose(
                                english: "All",
                                norwegian: "Alle"
                            )
                        ) { selectedEquipment = "All" }
                        ForEach(library.equipmentOptions, id: \.self) { equipment in
                            Button(equipment) { selectedEquipment = equipment }
                        }
                    } label: {
                        filterChip(
                            selectedEquipment == "All"
                                ? ATHLTHLocalization.choose(
                                    english: "Equipment",
                                    norwegian: "Utstyr"
                                )
                                : selectedEquipment,
                            active: selectedEquipment != "All"
                        )
                    }

                    if selectedBodyPart != "All" || selectedEquipment != "All" {
                        Button(
                            ATHLTHLocalization.choose(
                                english: "Clear",
                                norwegian: "Nullstill"
                            )
                        ) {
                            selectedBodyPart = "All"
                            selectedEquipment = "All"
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private func filterChip(_ text: String, active: Bool) -> some View {
        HStack(spacing: 5) {
            Text(text)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(active ? .white : .primary)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(
            active
                ? ATHLTHTheme.accent
                : ATHLTHTheme.cardWarm
                    .opacity(0.72),
            in: Capsule()
        )
    }

    private func recordExerciseSelection(_ entry: ExerciseLibraryEntry) {
        recents.markUsed(
            .exercise,
            itemID: entry.id.uuidString,
            title: entry.name,
            subtitle: [entry.bodyPart, entry.exercise.equipment.first]
                .compactMap { $0 }
                .joined(separator: " · "),
            icon: "dumbbell.fill"
        )
    }

    private func exerciseRow(_ entry: ExerciseLibraryEntry) -> some View {
        HStack(spacing: 13) {
            ExerciseArtwork(entry: entry, size: 68)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(library.localizedExerciseName(entry))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if entry.source == .custom {
                        Text("CUSTOM")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(ATHLTHTheme.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(ATHLTHTheme.accent.opacity(0.10), in: Capsule())
                    }
                }

                Text(
                    [
                        entry.bodyPart,
                        entry.exercise.equipment.first
                    ]
                    .compactMap { $0 }
                    .joined(separator: " · ")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                if let difficulty = entry.difficulty {
                    Text(difficulty)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if onSelect != nil, let count = selectedExerciseCounts[entry.id], count > 0 {
                    Label(
                        count == 1
                            ? ATHLTHLocalization.choose(english: "In workout", norwegian: "I økten")
                            : ATHLTHLocalization.choose(
                                english: "In workout · " + String(count),
                                norwegian: "I økten · " + String(count)
                            ),
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(ATHLTHTheme.accent.opacity(0.09), in: Capsule())
                }
            }

            Spacer(minLength: 4)

            if onSelect == nil {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Color.clear.frame(width: 70, height: 1)
            }
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [
                    ATHLTHTheme.card,
                    ATHLTHTheme.cardWarm
                        .opacity(0.62)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.72),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                ATHLTHTheme.accentDeep
                    .opacity(0.07),
            radius: 12,
            x: 0,
            y: 6
        )
    }
}

struct ExerciseDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: ExerciseLibraryStore

    let entry: ExerciseLibraryEntry
    let selectionTitle: String?
    let onSelect: ((ExerciseLibraryEntry) -> Void)?

    @State private var showingDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                artwork

                VStack(alignment: .leading, spacing: 5) {
                    Text(library.localizedExerciseName(entry))
                        .font(.largeTitle.bold())

                    Text(
                        [
                            entry.bodyPart,
                            entry.difficulty,
                            entry.exercise.equipment.first
                        ]
                        .compactMap { $0 }
                        .joined(separator: " · ")
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                if let summary = library.localizedExerciseSummary(entry),
                   !summary.isEmpty {
                    Text(summary)
                        .font(.subheadline)
                }

                if !library.localizedExerciseInstructions(entry).isEmpty {
                    detailCard(ATHLTHLocalization.choose(
                        english: "How to perform",
                        norwegian: "Slik utfører du øvelsen"
                    )) {
                        ForEach(
                            Array(library.localizedExerciseInstructions(entry).enumerated()),
                            id: \.offset
                        ) { index, instruction in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.caption.bold())
                                    .foregroundStyle(ATHLTHTheme.accent)
                                    .frame(width: 24, height: 24)
                                    .background(ATHLTHTheme.accent.opacity(0.10), in: Circle())

                                Text(instruction)
                                    .font(.subheadline)
                            }
                        }
                    }
                }

                if let videoURL = entry.exercise.videoURL {
                    detailCard("Video") {
                        VideoPlayer(
                            player: AVPlayer(url: videoURL)
                        )
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                        Link(destination: videoURL) {
                            Label("Open source video", systemImage: "arrow.up.right.square")
                                .font(.caption.weight(.semibold))
                        }
                    }
                }

                if !entry.tips.isEmpty {
                    detailCard("Tips") {
                        ForEach(entry.tips, id: \.self) { tip in
                            Label(tip, systemImage: "lightbulb.fill")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if entry.source == .repDB {
                    Link(destination: URL(string: "https://repdb.co")!) {
                        Label("Exercise data by RepDB", systemImage: "arrow.up.right.square")
                            .font(.caption.weight(.semibold))
                    }
                }

                if entry.source == .custom {
                    Button("Delete Custom Exercise", role: .destructive) {
                        showingDelete = true
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding()
        }
        .background(
            ATHLTHPremiumCanvas(
                accent:
                    ATHLTHTheme.accent
            )
        )
        .navigationTitle("Exercise")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let onSelect {
                VStack(spacing: 0) {
                    Divider()
                        .opacity(0.35)

                    Button {
                        onSelect(entry)
                        dismiss()
                    } label: {
                        Label(
                            selectionTitle ?? "Add Exercise",
                            systemImage: "plus.circle.fill"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(ATHLTHTheme.accent)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                }
                .background(
                    .ultraThinMaterial
                )
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(
                            Color.white
                                .opacity(0.42)
                        )
                        .frame(height: 0.6)
                }
            }
        }
        .confirmationDialog(
            "Delete this custom exercise?",
            isPresented: $showingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                library.deleteCustomExercise(entry.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var artwork: some View {
        HStack(spacing: 10) {
            ExerciseArtwork(entry: entry, size: 160)

            if entry.imagePeakURL != nil &&
               entry.imagePeakURL != entry.imageStartURL {
                ATHLTHStorageImage(url: entry.imagePeakURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    default:
                        Color(.secondarySystemGroupedBackground)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 20,
                        style: .continuous
                    )
                )
            }
        }
        .padding(10)
        .background(
            LinearGradient(
                colors: [
                    ATHLTHTheme.card,
                    ATHLTHTheme.cardWarm
                        .opacity(0.52)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.72),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                ATHLTHTheme.accentDeep
                    .opacity(0.06),
            radius: 12,
            x: 0,
            y: 6
        )
    }

    private func detailCard<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background(
            LinearGradient(
                colors: [
                    ATHLTHTheme.card,
                    ATHLTHTheme.cardWarm
                        .opacity(0.62)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.72),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                ATHLTHTheme.accentDeep
                    .opacity(0.065),
            radius: 12,
            x: 0,
            y: 6
        )
    }
}

// AI only drafts editable exercise metadata. It never publishes the exercise or
// pretends that a demonstration video was generated.
private struct ATHLTHAIExerciseDraft: Decodable {
    let name: String
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let equipment: [String]
    let instructions: [String]
    let videoBrief: String
}

private struct ATHLTHAIExerciseRequest: Encodable {
    let description: String
    let language: String
}

@MainActor
private final class ATHLTHAIExerciseDraftService {
    private let client = SupabaseEnvironment.client

    func generate(description: String) async throws -> ATHLTHAIExerciseDraft {
        try await client.functions.invoke(
            "generate-exercise-draft",
            options: FunctionInvokeOptions(
                body: ATHLTHAIExerciseRequest(
                    description: description,
                    language: ATHLTHLocalization.isNorwegian ? "no" : "en"
                )
            )
        )
    }
}

private enum ATHLTHAIDraftValidationError: LocalizedError {
    case incompleteDraft

    var errorDescription: String? {
        ATHLTHLocalization.choose(
            english: "The exercise suggestion was incomplete.",
            norwegian: "Øvelsesforslaget var ufullstendig."
        )
    }
}

struct CustomExerciseEditorView: View {
    let editing: ExerciseLibraryEntry?

    init(editing: ExerciseLibraryEntry? = nil) {
        self.editing = editing
        _name = State(initialValue: editing?.exercise.name ?? "")
        _primaryMuscles = State(initialValue: Set(
            ExerciseMuscleGroup.allCases.filter {
                editing?.exercise.primaryMuscles.contains($0.rawValue) ?? false
            }
        ))
        _secondaryMuscles = State(initialValue: Set(
            ExerciseMuscleGroup.allCases.filter {
                editing?.exercise.secondaryMuscles.contains($0.rawValue) ?? false
            }
        ))
        _equipment = State(initialValue: editing?.exercise.equipment.joined(separator: ", ") ?? "")
        _instructions = State(initialValue: editing?.exercise.instructions.joined(separator: "\n") ?? "")
        _shareable = State(initialValue: editing?.exercise.isVisibleOutsideOwnerLibrary ?? false)
        _videoURLText = State(initialValue: editing?.exercise.videoURL.flatMap {
            $0.isFileURL ? nil : $0.absoluteString
        } ?? "")
    }

    private var previewVideoURL: URL? {
        if removingExistingVideo {
            return importedVideoURL ?? cleanVideoURL
        }
        return importedVideoURL ?? cleanVideoURL ?? editing?.exercise.videoURL
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: ExerciseLibraryStore
    @EnvironmentObject private var session: AppSessionStore

    @State private var name = ""
    @State private var primaryMuscles:
        Set<ExerciseMuscleGroup> = []
    @State private var secondaryMuscles:
        Set<ExerciseMuscleGroup> = []
    @State private var equipment = ""
    @State private var instructions = ""
    @State private var shareable = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var videoURLText = ""
    @State private var showingVideoImporter = false
    @State private var importedVideoURL: URL?
    @State private var removingExistingVideo = false
    @State private var isImportingVideo = false
    @State private var didSaveExercise = false
    @State private var studioError: String?
    @State private var aiPrompt = ""
    @State private var aiVideoBrief = ""
    @State private var isGeneratingAIDraft = false
    @State private var hasAIDraft = false
    @State private var aiErrorMessage: String?
    private let aiDraftService = ATHLTHAIExerciseDraftService()

    var body: some View {
        let photoButtonTitle =
            selectedImageData == nil
                ? "Add Exercise Image"
                : "Change Exercise Image"

        return NavigationStack {
            Form {
                Section {
                    TextField(
                        ATHLTHLocalization.choose(
                            english: "Describe the movement, equipment and goal.",
                            norwegian: "Beskriv bevegelsen, utstyret og formålet."
                        ),
                        text: $aiPrompt,
                        axis: .vertical
                    )
                    .lineLimit(3...6)

                    Button {
                        Task { await generateAIDraft() }
                    } label: {
                        HStack(spacing: 9) {
                            if isGeneratingAIDraft {
                                ProgressView()
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(ATHLTHLocalization.choose(
                                english: "Create AI suggestion",
                                norwegian: "Lag forslag med AI"
                            ))
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 46)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accentDeep)
                    .disabled(
                        isGeneratingAIDraft ||
                        aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines).count < 12
                    )

                    if let aiErrorMessage {
                        Text(aiErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if hasAIDraft {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Draft ready. Review all fields before saving.",
                                norwegian: "Utkastet er klart. Kontroller alle feltene før du lagrer."
                            ),
                            systemImage: "checkmark.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.vitality)
                    }
                    Text(ATHLTHLocalization.choose(
                        english: "ATHLTH AI+ suggests text and muscle groups. You approve the result. The video storyboard is not a generated video.",
                        norwegian: "ATHLTH AI+ foreslår tekst og muskelgrupper. Du godkjenner resultatet. Videoplanen er ikke en ferdig generert video."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                } header: {
                    Label("ATHLTH AI", systemImage: "sparkles")
                }

                Section("Exercise") {
                    TextField("Name", text: $name)

                    Menu {
                        ForEach(
                            ExerciseMuscleGroup.allCases
                        ) { group in
                            Button {
                                togglePrimary(group)
                            } label: {
                                Label(
                                    group.title,
                                    systemImage:
                                        primaryMuscles
                                            .contains(group)
                                            ? "checkmark.circle.fill"
                                            : "circle"
                                )
                            }
                        }
                    } label: {
                        HStack {
                            VStack(
                                alignment: .leading,
                                spacing: 2
                            ) {
                                Text(
                                    ATHLTHLocalization.choose(
                                        english: "Primary muscle groups",
                                        norwegian: "Primære muskelgrupper"
                                    )
                                )
                                .foregroundStyle(.primary)

                                Text(
                                    muscleSelectionSummary(
                                        primaryMuscles,
                                        empty:
                                            ATHLTHLocalization.choose(
                                                english: "Choose at least one",
                                                norwegian: "Velg minst én"
                                            )
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    primaryMuscles.isEmpty
                                        ? Color.red
                                        : ATHLTHTheme
                                            .mutedText
                                )
                            }

                            Spacer()

                            Image(
                                systemName:
                                    "chevron.up.chevron.down"
                            )
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        }
                    }

                    Menu {
                        ForEach(
                            ExerciseMuscleGroup.allCases
                        ) { group in
                            Button {
                                toggleSecondary(group)
                            } label: {
                                Label(
                                    group.title,
                                    systemImage:
                                        secondaryMuscles
                                            .contains(group)
                                            ? "checkmark.circle.fill"
                                            : "circle"
                                )
                            }
                            .disabled(
                                primaryMuscles
                                    .contains(group)
                            )
                        }
                    } label: {
                        HStack {
                            VStack(
                                alignment: .leading,
                                spacing: 2
                            ) {
                                Text(
                                    ATHLTHLocalization.choose(
                                        english: "Secondary muscle groups",
                                        norwegian: "Sekundære muskelgrupper"
                                    )
                                )
                                .foregroundStyle(.primary)

                                Text(
                                    muscleSelectionSummary(
                                        secondaryMuscles,
                                        empty:
                                            ATHLTHLocalization.choose(
                                                english: "Optional",
                                                norwegian: "Valgfritt"
                                            )
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(
                                systemName:
                                    "chevron.up.chevron.down"
                            )
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        }
                    }

                    TextField(
                        "Equipment, comma separated",
                        text: $equipment
                    )
                }

                Section("Instructions") {
                    TextField(
                        "One instruction per line",
                        text: $instructions,
                        axis: .vertical
                    )
                    .lineLimit(5...12)
                }

                Section("Media") {
                    if let selectedImageData,
                       let image = UIImage(data: selectedImageData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 190)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    }

                    PhotosPicker(
                        selection: $selectedPhoto,
                        matching: .images
                    ) {
                        Label(
                            photoButtonTitle,
                            systemImage: "photo.badge.plus"
                        )
                    }

                    if !aiVideoBrief.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Suggested video storyboard",
                                    norwegian: "Forslag til demonstrasjonsvideo"
                                ),
                                systemImage: "video"
                            )
                            .font(.subheadline.weight(.semibold))

                            Text(aiVideoBrief)
                                .font(.caption)
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .background(
                            ATHLTHPlanDesign.selectedSurface,
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                    }

                    TextField(
                        ATHLTHLocalization.choose(
                            english: "Direct video URL (optional)",
                            norwegian: "Direkte videolenke (valgfritt)"
                        ),
                        text: $videoURLText
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                    Text(
                        "Your image is stored locally in ATHLTH. A direct video URL can be attached to the exercise and shown on its detail page."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section("Sharing") {
                    Toggle(
                        "Allow this exercise in shared plans",
                        isOn: $shareable
                    )

                    Text(
                        shareable
                            ? "The exercise snapshot can travel with a plan you share."
                            : "This custom exercise stays private to your library."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(ATHLTHLocalization.choose(
                english: editing == nil ? "Exercise Studio" : "Edit exercise",
                norwegian: editing == nil ? "Øvelsesstudio" : "Rediger øvelse"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Save", norwegian: "Lagre"
                    )) {
                        saveExercise()
                    }
                    .disabled(
                        name
                            .trimmingCharacters(
                                in:
                                    .whitespacesAndNewlines
                            )
                            .isEmpty ||
                        primaryMuscles.isEmpty
                    )
                }
            }
            .fileImporter(
                isPresented: $showingVideoImporter,
                allowedContentTypes: [.movie, .mpeg4Movie],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let selected = urls.first else { return }
                    Task {
                        isImportingVideo = true
                        defer { isImportingVideo = false }
                        do {
                            let imported = try await Task.detached(priority: .userInitiated) {
                                try ExerciseStudioVideoStorage.importVideo(from: selected)
                            }.value
                            ExerciseStudioVideoStorage.discardOwnedVideo(importedVideoURL)
                            importedVideoURL = imported
                            removingExistingVideo = false
                            videoURLText = ""
                            studioError = nil
                        } catch {
                            studioError = error.localizedDescription
                        }
                    }
                case .failure(let error):
                    studioError = error.localizedDescription
                }
            }
            .onDisappear {
                if !didSaveExercise {
                    ExerciseStudioVideoStorage.discardOwnedVideo(importedVideoURL)
                }
            }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else {
                    selectedImageData = nil
                    return
                }

                Task {
                    selectedImageData = try? await item.loadTransferable(type: Data.self)
                }
            }
        }
    }

    private func saveExercise() {
        do {
            let video = previewVideoURL
            if let editing {
                var updated = editing.exercise
                updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                updated.instructions = splitLines(instructions)
                updated.primaryMuscles = selectedMuscleValues(primaryMuscles)
                updated.secondaryMuscles = selectedMuscleValues(secondaryMuscles)
                updated.equipment = splitCSV(equipment)
                updated.isVisibleOutsideOwnerLibrary = shareable
                updated.videoURL = video
                if let selectedImageData {
                    updated.imageURL = try library.updateCustomImageData(
                        selectedImageData, for: editing.id
                    )
                }
                library.updateCustomExercise(updated)
            } else {
                _ = library.createCustomExercise(
                    ownerID: session.profile.userID,
                    name: name,
                    instructions: splitLines(instructions),
                    primaryMuscles: selectedMuscleValues(primaryMuscles),
                    secondaryMuscles: selectedMuscleValues(secondaryMuscles),
                    equipment: splitCSV(equipment),
                    isVisibleOutsideOwnerLibrary: shareable,
                    imageData: selectedImageData,
                    videoURL: video
                )
            }
            didSaveExercise = true
            importedVideoURL = nil
            dismiss()
        } catch {
            studioError = error.localizedDescription
        }
    }

    @MainActor
    private func generateAIDraft() async {
        let description = aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard description.count >= 12, !isGeneratingAIDraft else { return }
        isGeneratingAIDraft = true
        aiErrorMessage = nil
        defer { isGeneratingAIDraft = false }
        do {
            let suggestion = try await aiDraftService.generate(description: description)
            let primary = Set(ExerciseMuscleGroup.allCases.filter {
                suggestion.primaryMuscles.contains($0.rawValue)
            })
            guard !primary.isEmpty,
                  !suggestion.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  suggestion.instructions.count >= 2 else {
                throw ATHLTHAIDraftValidationError.incompleteDraft
            }
            let secondary = Set(ExerciseMuscleGroup.allCases.filter {
                suggestion.secondaryMuscles.contains($0.rawValue) && !primary.contains($0)
            })
            name = String(suggestion.name.prefix(90))
            primaryMuscles = primary
            secondaryMuscles = secondary
            equipment = suggestion.equipment.joined(separator: ", ")
            instructions = suggestion.instructions.joined(separator: "\n")
            aiVideoBrief = suggestion.videoBrief
            hasAIDraft = true
        } catch {
            aiErrorMessage = ATHLTHLocalization.choose(
                english: "ATHLTH AI could not prepare this exercise. Check your ATHLTH+ access and try again. ",
                norwegian: "ATHLTH AI klarte ikke å lage øvelsen. Kontroller ATHLTH+-tilgangen og prøv igjen. "
            ) + error.localizedDescription
        }
    }

    private func togglePrimary(
        _ group: ExerciseMuscleGroup
    ) {
        if primaryMuscles.contains(group) {
            primaryMuscles.remove(group)
        } else {
            primaryMuscles.insert(group)
            secondaryMuscles.remove(group)
        }
    }

    private func toggleSecondary(
        _ group: ExerciseMuscleGroup
    ) {
        guard !primaryMuscles.contains(group) else {
            return
        }

        if secondaryMuscles.contains(group) {
            secondaryMuscles.remove(group)
        } else {
            secondaryMuscles.insert(group)
        }
    }

    private func selectedMuscleValues(
        _ selection: Set<ExerciseMuscleGroup>
    ) -> [String] {
        ExerciseMuscleGroup
            .allCases
            .filter {
                selection.contains($0)
            }
            .map(\.rawValue)
    }

    private func muscleSelectionSummary(
        _ selection: Set<ExerciseMuscleGroup>,
        empty: String
    ) -> String {
        let values =
            ExerciseMuscleGroup
                .allCases
                .filter {
                    selection.contains($0)
                }
                .map(\.title)

        return values.isEmpty
            ? empty
            : values.joined(
                separator: " · "
            )
    }

    private var cleanVideoURL: URL? {
        let clean = videoURLText
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !clean.isEmpty else { return nil }
        return URL(string: clean)
    }

    private func splitCSV(_ value: String) -> [String] {
        value
            .split(separator: ",")
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func splitLines(_ value: String) -> [String] {
        value
            .split(whereSeparator: \Character.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct ExerciseArtwork: View {
    let entry: ExerciseLibraryEntry
    let size: CGFloat

    var body: some View {
        Group {
            if let slug = entry.sourceIdentifier,
               entry.source == .athlthCatalog,
               slug.hasPrefix("athlth-core-") {
                // Distinct royalty-free local artwork for all 20 originals.
                ATHLTHOriginalCoreArtwork(slug: slug)
            } else if let url = entry.imageStartURL {
                if url.isFileURL,
                   let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ATHLTHStorageImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            fallback
                        }
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: min(size * 0.18, 20)))
    }

    private var fallback: some View {
        ATHLTHTheme.accent.opacity(0.08)
            .overlay {
                Image(
                    systemName: entry.source == .custom
                        ? "person.crop.circle.badge.plus"
                        : "dumbbell.fill"
                )
                .font(.system(size: size * 0.28))
                .foregroundStyle(ATHLTHTheme.accent)
            }
    }
}

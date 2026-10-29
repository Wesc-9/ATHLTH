import AVKit
import PhotosUI
import Supabase
import SwiftUI
import Translation
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
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @EnvironmentObject private var favorites: LibraryFavoritesStore
    @EnvironmentObject private var recents: LibraryRecentsStore
    @ObservedObject private var norwegianTranslations = NorwegianExerciseAutoTranslation.shared
    @State private var nameTranslationConfig: TranslationSession.Configuration?
    @State private var languageStatus: LanguageAvailability.Status = .unsupported

    let source: ExerciseLibrarySection?
    let selectionTitle: String?
    let selectedExerciseCounts: [UUID: Int]
    let onSelect: ((ExerciseLibraryEntry) -> Void)?

    @State private var query = ""
    @State private var queryInput = ""
    @State private var selectedBodyPart = "All"
    @State private var selectedEquipment = "All"
    @State private var favoritesOnly = false
    @State private var showingCreateExercise = false
    @State private var showingEquipmentCamera = false
    @State private var showingCameraUnavailable = false
    @State private var showingEquipmentSubscription = false
    @State private var equipmentPhoto: UIImage?
    @State private var scannerIsAnalyzing = false
    @State private var scannerAnalysis: ATHLTHEquipmentScanResponse?
    @State private var scannerMessage: String?
    @State private var scannerResultsActive = false
    @State private var scannerCandidates: [ExerciseLibraryEntry] = []
    @State private var scannerTask: Task<Void, Never>?
    @State private var scanIdentity = UUID()
    @State private var selectedSection: ExerciseLibrarySection = .library
    @State private var exerciseHistory: [StrengthWorkoutLog] = []

    private func refreshExerciseHistory() {
        exerciseHistory = AccountLocalStorage.read(
            [StrengthWorkoutLog].self, name: "strengthHistory",
            userID: session.profile.userID
        ) ?? []
    }

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
        // Callers may still pass legacy detailed muscle names. Keep the
        // picker aligned with the nine visible familiar groups.
        let normalizedBodyPart =
            ExerciseLibraryStore.canonicalMuscleFilter(initialBodyPart)
        _selectedBodyPart = State(
            initialValue: ExerciseLibraryStore.commonMuscleFilters.contains(
                normalizedBodyPart
            ) ? normalizedBodyPart : "All"
        )
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

    // Search now returns an alphabetized cached result. Avoid repeating
    // an expensive localized name sort on every SwiftUI state publication.
    private var displayedResults: [ExerciseLibraryEntry] {
        if scannerResultsActive {
            guard let scannerAnalysis else { return [] }
            let regularIDs = Set(results.map(\.id))
            return library.alphabetized(
                scannerAnalysis.matchedExercises(in: scannerCandidates)
                    .filter { regularIDs.contains($0.id) }
            )
        }
        return results
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
        // Reuse one filtered/sorted list for empty state, rows and alphabet targets.
        let entries = displayedResults
        return VStack(spacing: 0) {
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
            translationAvailabilityBanner

            Button {
                beginEquipmentScan()
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(ATHLTHPlanDesign.accent)
                        .frame(width: 38, height: 38)
                        .background(ATHLTHPlanDesign.selectedSurface, in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ATHLTHLocalization.choose(
                            english: "Scan gym equipment",
                            norwegian: "Skann treningsapparat"
                        ))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        Text(
                            session.hasPaidAccess
                            ? ATHLTHLocalization.choose(
                                english: "Camera opens directly · photo is sent to AI for matching",
                                norwegian: "Kamera åpnes direkte · bildet sendes til AI for treff"
                            )
                            : ATHLTHLocalization.choose(
                                english: "ATHLTH+ · Unlock equipment recognition",
                                norwegian: "ATHLTH+ · Lås opp apparatgjenkjenning"
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                    Spacer()
                    Image(systemName:
                        session.hasPaidAccess ? "arrow.up.right" : "lock.fill"
                    )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.accent)
                }
                .padding(12)
                .background(
                    Color.white,
                    in: RoundedRectangle(cornerRadius: ATHLTHPlanDesign.cardRadius)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: ATHLTHPlanDesign.cardRadius)
                        .stroke(ATHLTHPlanDesign.outline, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 5)

            if scannerResultsActive {
                equipmentScanFilterSummary
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }

            if selectedSection == .mine {
                ATHLTHPlanSurface {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("ATHLTH EXERCISE STUDIO")
                                    .font(.system(size: 10, weight: .semibold))
                                    .tracking(1.6)
                                    .foregroundStyle(ATHLTHPlanDesign.accent)
                                Text(ATHLTHLocalization.choose(
                                    english: "Your exercises",
                                    norwegian: "Dine øvelser"
                                ))
                                .font(.system(size: 27, weight: .regular, design: .serif))
                                .foregroundStyle(ATHLTHPlanDesign.ink)
                            }
                            Spacer()
                            Image(systemName: "figure.strengthtraining.traditional")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(ATHLTHPlanDesign.accent)
                                .frame(width: 42, height: 42)
                                .background(
                                    ATHLTHPlanDesign.selectedSurface,
                                    in: Circle()
                                )
                        }
                        Text(ATHLTHLocalization.choose(
                            english: "Create with AI or manually. Add a picture and your own technique video. Edit the exercise any time.",
                            norwegian: "Lag med AI eller manuelt. Legg til bilde og egen teknikkvideo. Rediger øvelsen når som helst."
                        ))
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

                        Button {
                            showingCreateExercise = true
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Create exercise",
                                    norwegian: "Opprett øvelse"
                                ),
                                systemImage: "plus"
                            )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(ATHLTHPlanDesign.ink, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }

            if scannerIsAnalyzing {
                ProgressView(ATHLTHLocalization.choose(
                    english: "Analyzing equipment and finding exercises…",
                    norwegian: "Analyserer apparatet og finner aktuelle øvelser…"
                ))
                .padding(30)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if selectedSection == .library &&
                library.isLoading &&
                library.athlthCatalogExercises.isEmpty {
                ProgressView(ATHLTHLocalization.choose(
                    english: "Loading exercises…", norwegian: "Laster øvelser…"
                ))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                if scannerResultsActive {
                    scannerEmptyState
                } else if selectedSection == .mine && query.isEmpty {
                    ContentUnavailableView {
                        Label(ATHLTHLocalization.choose(
                            english: "No personal exercises yet",
                            norwegian: "Ingen egne øvelser ennå"
                        ), systemImage: "dumbbell")
                    } description: {
                        Text(ATHLTHLocalization.choose(
                            english: "Create an exercise to see it here.",
                            norwegian: "Lag en egen øvelse for å se den her."
                        ))
                    } actions: {
                        Button(ATHLTHLocalization.choose(
                            english: "Create exercise", norwegian: "Opprett øvelse"
                        )) {
                            showingCreateExercise = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ATHLTHTheme.accent)
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 34, weight: .ultraLight))
                            .foregroundStyle(ATHLTHPlanDesign.accent)
                            .frame(width: 72, height: 72)
                            .background(ATHLTHPlanDesign.selectedSurface, in: Circle())
                        Text(ATHLTHLocalization.choose(
                            english: "No matching exercises",
                            norwegian: "Ingen øvelser funnet"
                        ))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        Text(library.errorMessage ?? ATHLTHLocalization.choose(
                            english: "Try a different search or adjust the filters.",
                            norwegian: "Prøv et annet søk eller juster filtrene."
                        ))
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        .multilineTextAlignment(.center)
                        if selectedBodyPart != "All" || selectedEquipment != "All" || !query.isEmpty {
                            Button(ATHLTHLocalization.choose(
                                english: "Clear filters", norwegian: "Nullstill filtrene"
                            )) {
                                selectedBodyPart = "All"
                                selectedEquipment = "All"
                                query = ""
                                queryInput = ""
                            }
                            .font(.subheadline.weight(.semibold))
                            .tint(ATHLTHPlanDesign.accent)
                            .padding(.top, 4)
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(
                                entries
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
                                            title: library.localizedExerciseName(entry),
                                            subtitle: [
                                                entry.bodyPart.map(library.localizedBodyPartTitle),
                                                entry.exercise.equipment.first.map(library.localizedEquipmentTitle)
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
                        if !entries.isEmpty {
                            ATHLTHExerciseAlphabetIndex(
                                targets: library.alphabetIndexTargets(for: entries),
                                onJump: { id in
                                    withAnimation(.easeOut(duration: 0.18)) {
                                        proxy.scrollTo(id, anchor: .top)
                                    }
                                }
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
        .sheet(isPresented: $showingEquipmentSubscription) {
            SubscriptionOfferView {
                session.applyStoreKitEntitlement(
                    subscriptionStore.activeEntitlement
                )
                showingEquipmentSubscription = false
            }
        }
        .fullScreenCover(isPresented: $showingEquipmentCamera) {
            ATHLTHEquipmentCameraPicker(
                onCapture: { captured in
                    showingEquipmentCamera = false
                    processEquipmentPhoto(captured)
                },
                onCancel: {
                    showingEquipmentCamera = false
                }
            )
            .ignoresSafeArea()
        }
        .alert(
            ATHLTHLocalization.choose(
                english: "Camera not available",
                norwegian: "Kamera ikke tilgjengelig"
            ),
            isPresented: $showingCameraUnavailable
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(ATHLTHLocalization.choose(
                english: "A camera is required to scan gym equipment.",
                norwegian: "Du trenger et kamera for å skanne treningsapparater."
            ))
        }
        .onChange(of: selectedSection) { _, section in
            if section == .mine, scannerResultsActive {
                resetEquipmentScan()
            }
        }
        .onAppear(perform: refreshExerciseHistory)
        .onReceive(NotificationCenter.default.publisher(for: .athlthTrainingDataDidChange)) { _ in
            refreshExerciseHistory()
        }
        // Debounce typing so long catalog scans do not run for each key.
        .task(id: queryInput) {
            do {
                try await Task.sleep(for: .milliseconds(180))
            } catch { return }
            guard !Task.isCancelled else { return }
            query = queryInput
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
        .task {
            guard ATHLTHLocalization.isNorwegian else { return }
            languageStatus = await NorwegianExerciseAutoTranslation.availabilityStatus()
            if languageStatus == .installed {
                nameTranslationConfig = NorwegianExerciseAutoTranslation.configuration()
            }
        }
        .translationTask(nameTranslationConfig) { session in
            let pendingNames = library.selectableExercises
                .filter { $0.source == .repDB }
                .filter {
                    NorwegianExerciseText.name(for: $0.sourceIdentifier) == nil
                      && ATHLTHExerciseNameLocalization.norwegianName(for: $0.name)
                         == $0.name
                }
                .map(\.name)
            await norwegianTranslations.translate(texts: pendingNames, using: session)
        }
    }

    /// Keep the scan photo and feedback within the exercise picker, not
    /// another NavigationStack or a second exercise list.
    private var equipmentScanFilterSummary: some View {
        HStack(spacing: 11) {
            if let equipmentPhoto {
                Image(uiImage: equipmentPhoto)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel(ATHLTHLocalization.choose(
                        english: "Scanned equipment",
                        norwegian: "Skannet treningsapparat"
                    ))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(scannerAnalysis?.equipmentName ??
                    ATHLTHLocalization.choose(
                        english: scannerMessage == nil
                            ? "Analyzing equipment" : "Analysis failed",
                        norwegian: scannerMessage == nil
                            ? "Analyserer apparatet" : "Analyse mislyktes"
                    ))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                    .lineLimit(1)

                Text(scannerIsAnalyzing
                    ? ATHLTHLocalization.choose(
                        english: "Filtering the ATHLTH exercise library…",
                        norwegian: "Filtrerer ATHLTH-biblioteket…"
                    )
                    : (scannerMessage ??
                        ATHLTHLocalization.choose(
                            english: "\(displayedResults.count) relevant exercises · verify equipment",
                            norwegian: "\(displayedResults.count) aktuelle øvelser · kontroller apparatet"
                        )))
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Button {
                beginEquipmentScan()
            } label: {
                Image(systemName: "camera.fill")
                    .font(.subheadline)
                    .frame(width: 36, height: 36)
                    .background(ATHLTHPlanDesign.selectedSurface, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ATHLTHLocalization.choose(
                english: "Scan again",
                norwegian: "Skann på nytt"
            ))

            Button {
                resetEquipmentScan()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    .frame(width: 32, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ATHLTHLocalization.choose(
                english: "Clear equipment filter",
                norwegian: "Fjern apparatfilter"
            ))
        }
        .padding(12)
        .background(
            ATHLTHPlanDesign.selectedSurface.opacity(0.70),
            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
        )
    }

    private var scannerEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 30))
                .foregroundStyle(ATHLTHPlanDesign.accent)

            Text(scannerMessage == nil
                ? ATHLTHLocalization.choose(
                    english: "No matching exercises",
                    norwegian: "Ingen aktuelle øvelser funnet"
                )
                : ATHLTHLocalization.choose(
                    english: "Could not analyze the photo",
                    norwegian: "Kunne ikke analysere bildet"
                )
            )
            .font(.headline)

            Text(scannerMessage ?? (
                scannerAnalysis?.confidence == "low"
                    ? ATHLTHLocalization.choose(
                        english: "The photo was too uncertain. Try a clearer picture of the entire machine.",
                        norwegian: "Apparatet ble ikke gjenkjent sikkert. Prøv et tydeligere bilde av hele apparatet."
                    )
                    : ATHLTHLocalization.choose(
                        english: "No exercises matched this machine and the active filters.",
                        norwegian: "Ingen øvelser passer til apparatet og filtrene som er valgt."
                    )
            ))
            .font(.subheadline)
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            .multilineTextAlignment(.center)

            if scannerMessage != nil,
               let equipmentPhoto {
                Button {
                    processEquipmentPhoto(equipmentPhoto)
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Try again with the same photo",
                            norwegian: "Prøv igjen med samme bilde"
                        ),
                        systemImage: "arrow.clockwise"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHPlanDesign.ink)
            }

            Button(ATHLTHLocalization.choose(
                english: "Show all exercises",
                norwegian: "Vis alle øvelser"
            )) {
                resetEquipmentScan()
            }
            .buttonStyle(.bordered)
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func beginEquipmentScan() {
        guard session.hasPaidAccess else {
            showingEquipmentSubscription = true
            return
        }
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            showingCameraUnavailable = true
            return
        }
        showingEquipmentCamera = true
    }

    /// Capturing a photo is an explicit scan action. The entry point explains
    /// that AI analyzes the photo before the user opens the camera.
    private func processEquipmentPhoto(_ image: UIImage) {
        guard session.hasPaidAccess else {
            resetEquipmentScan()
            showingEquipmentSubscription = true
            return
        }
        scannerTask?.cancel()
        let identity = UUID()
        scanIdentity = identity
        equipmentPhoto = image
        scannerAnalysis = nil
        scannerMessage = nil
        scannerIsAnalyzing = true
        scannerResultsActive = true

        // Prevent older search filters from silently hiding matched exercises.
        query = ""
        queryInput = ""
        selectedBodyPart = "All"
        selectedEquipment = "All"
        favoritesOnly = false
        selectedSection = .library

        let candidates = ATHLTHEquipmentScanCandidateSelector.select(
            from: library.search(query: "")
        )
        scannerCandidates = candidates

        scannerTask = Task {
            do {
                let analysis = try await ATHLTHEquipmentVisionService()
                    .analyze(image: image, exercises: candidates)
                guard !Task.isCancelled, scanIdentity == identity else {
                    return
                }
                scannerAnalysis = analysis
                scannerIsAnalyzing = false
            } catch {
                guard !Task.isCancelled, scanIdentity == identity else {
                    return
                }
                // Keep the service's safe, localized failure reason
                // instead of disguising every provider error as a bad photo.
                scannerMessage = ATHLTHEquipmentScannerError.from(error)
                    .localizedDescription
                scannerIsAnalyzing = false
            }
        }
    }

    private func resetEquipmentScan() {
        scannerTask?.cancel()
        scannerTask = nil
        scanIdentity = UUID()
        scannerIsAnalyzing = false
        scannerResultsActive = false
        scannerAnalysis = nil
        scannerMessage = nil
        scannerCandidates = []
        equipmentPhoto = nil
    }

    @ViewBuilder
    private var translationAvailabilityBanner: some View {
        if ATHLTHLocalization.isNorwegian &&
           selectedSection == .library &&
           languageStatus == .supported {
            Button {
                // The system explicitly asks before downloading any missing
                // language model. Nothing is bundled inside ATHLTH itself.
                nameTranslationConfig = NorwegianExerciseAutoTranslation.configuration()
                languageStatus = .installed
            } label: {
                Label(
                    "Oversett resten av øvelsesnavnene til norsk",
                    systemImage: "character.book.closed"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 17)
        }
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
                    text: $queryInput
                )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if !queryInput.isEmpty {
                    Button {
                        query = ""
                        queryInput = ""
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
                        ForEach(
                            library.equipmentOptions.sorted {
                                library.localizedEquipmentTitle($0)
                                    .localizedStandardCompare(
                                        library.localizedEquipmentTitle($1)
                                    ) == .orderedAscending
                            },
                            id: \.self
                        ) { equipment in
                            Button(library.localizedEquipmentTitle(equipment)) {
                                selectedEquipment = equipment
                            }
                        }
                    } label: {
                        filterChip(
                            selectedEquipment == "All"
                                ? ATHLTHLocalization.choose(
                                    english: "Equipment",
                                    norwegian: "Utstyr"
                                )
                                : library.localizedEquipmentTitle(selectedEquipment),
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
            title: library.localizedExerciseName(entry),
            subtitle: [
                entry.bodyPart.map(library.localizedBodyPartTitle),
                entry.exercise.equipment.first.map(library.localizedEquipmentTitle)
            ]
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
                        Text(ATHLTHLocalization.choose(
                             english: "CUSTOM", norwegian: "EGEN"
                         ))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(ATHLTHTheme.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(ATHLTHTheme.accent.opacity(0.10), in: Capsule())
                    }
                }

                Text(
                    [
                        entry.bodyPart.map(library.localizedBodyPartTitle),
                        entry.exercise.equipment.first.map(library.localizedEquipmentTitle)
                    ]
                    .compactMap { $0 }
                    .joined(separator: " · ")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                if let difficulty = entry.difficulty {
                    Text(library.localizedDifficultyTitle(difficulty))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let last = ATHLTHLibraryWorkoutHistory.strengthExercise(
                    id: entry.id, canonicalName: entry.canonicalName,
                    isCustom: entry.source == .custom, workouts: exerciseHistory
                ) {
                    ATHLTHLastWorkoutHistoryLabel(summary: last)
                        .padding(.top, 2)
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
    @EnvironmentObject private var session: AppSessionStore
    @ObservedObject private var norwegianTranslations = NorwegianExerciseAutoTranslation.shared
    @State private var detailTranslationConfig: TranslationSession.Configuration?
    @State private var showOriginalEnglish = false
    @State private var galleryPage: Int? = 0
    @State private var instructionsAsList = false
    @State private var languageStatus: LanguageAvailability.Status = .unsupported

    let entry: ExerciseLibraryEntry
    let selectionTitle: String?
    let onSelect: ((ExerciseLibraryEntry) -> Void)?

    @State private var showingDelete = false
    @State private var showingEdit = false
    @State private var exerciseHistory: [StrengthWorkoutLog] = []
    @State private var preparedShare: MessageShareDraft?

    private func refreshExerciseHistory() {
        exerciseHistory = AccountLocalStorage.read(
            [StrengthWorkoutLog].self, name: "strengthHistory",
            userID: session.profile.userID
        ) ?? []
    }
    @State private var shareError: String?

    private var currentEntry: ExerciseLibraryEntry {
        library.allExercises.first(where: { $0.id == entry.id }) ?? entry
    }

    private var displayedSummary: String? {
        showOriginalEnglish
            ? currentEntry.summary
            : library.localizedExerciseSummary(currentEntry)
    }

    private var displayedInstructions: [String] {
        showOriginalEnglish
            ? currentEntry.exercise.instructions
            : library.localizedExerciseInstructions(currentEntry)
    }

    private var displayedTips: [String] {
        showOriginalEnglish
            ? currentEntry.tips
            : library.localizedExerciseTips(currentEntry)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                artwork

                VStack(alignment: .leading, spacing: 5) {
                    Text(library.localizedExerciseName(currentEntry))
                         .font(.system(size: 31, weight: .semibold, design: .serif))
                        .foregroundStyle(ATHLTHTrainDesign.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(
                        [
                            currentEntry.bodyPart.map(library.localizedBodyPartTitle),
                            currentEntry.difficulty.map(library.localizedDifficultyTitle),
                            currentEntry.exercise.equipment.first.map(library.localizedEquipmentTitle)
                        ]
                        .compactMap { $0 }
                        .joined(separator: " · ")
                    )
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
                }

                ATHLTHLastWorkoutHistoryCard(summary:
                    ATHLTHLibraryWorkoutHistory.strengthExercise(
                        id: currentEntry.id,
                        canonicalName: currentEntry.canonicalName,
                        isCustom: currentEntry.source == .custom,
                        workouts: exerciseHistory
                    )
                )

                ATHLTHExerciseProgressView(
                    progress: ATHLTHExerciseProgress.summary(
                        exerciseID: currentEntry.id,
                        name: currentEntry.canonicalName,
                        isCustom: currentEntry.source == .custom,
                        workouts: exerciseHistory
                    )
                )

                if let summary = displayedSummary, !summary.isEmpty {
                    detailCard(ATHLTHLocalization.choose(
                        english: "About the exercise", norwegian: "Om øvelsen"
                    ), symbol: "dumbbell") {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(ATHLTHTrainDesign.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if ATHLTHLocalization.isNorwegian,
                   currentEntry.source == .repDB {
                    HStack(spacing: 8) {
                        Text("Norsk tekst kan være automatisk oversatt.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button(showOriginalEnglish ? "Vis norsk" : "Vis original (EN)") {
                            showOriginalEnglish.toggle()
                        }
                        .font(.caption2.weight(.semibold))
                    }
                }

                if ATHLTHLocalization.isNorwegian,
                   currentEntry.source == .repDB,
                   languageStatus == .supported,
                   detailTranslationConfig == nil {
                    Button {
                        // iOS asks before installing the language resources.
                        detailTranslationConfig =
                            NorwegianExerciseAutoTranslation.configuration()
                    } label: {
                        Label("Oversett øvelsesbeskrivelsen til norsk",
                              systemImage: "character.book.closed")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }

                if !displayedInstructions.isEmpty {
                    detailCard(ATHLTHLocalization.choose(
                        english: "How to perform",
                        norwegian: "Slik utfører du øvelsen"
                    )) {
                        HStack {
                            Spacer()
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    instructionsAsList.toggle()
                                }
                            } label: {
                                Label(
                                    instructionsAsList
                                        ? ATHLTHLocalization.choose(
                                            english: "Show illustrations",
                                            norwegian: "Vis med bilder"
                                        )
                                        : ATHLTHLocalization.choose(
                                            english: "Show as list",
                                            norwegian: "Vis som liste"
                                        ),
                                    systemImage: instructionsAsList
                                        ? "photo.on.rectangle" : "list.bullet"
                                )
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ATHLTHTrainDesign.bronze)
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(Array(displayedInstructions.enumerated()), id: \.offset) {
                            index, instruction in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                                    .frame(width: 32, height: 32)
                                    .background(
                                        ATHLTHTrainDesign.paleGold.opacity(0.55),
                                        in: Circle()
                                    )
                                Text(instruction)
                                    .font(.subheadline)
                                    .foregroundStyle(ATHLTHTrainDesign.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.top, 5)
                                if !instructionsAsList {
                                    if index == 0 {
                                        ExerciseArtwork(entry: currentEntry, size: 102)
                                            .accessibilityHidden(true)
                                    } else if index == 1,
                                              let peakURL = currentEntry.imagePeakURL,
                                              peakURL != currentEntry.imageStartURL {
                                        peakExerciseArtwork(peakURL, size: 102)
                                            .accessibilityHidden(true)
                                    }
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                ATHLTHTrainDesign.paper,
                                in: RoundedRectangle(cornerRadius: 17)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 17)
                                    .stroke(ATHLTHTrainDesign.rule.opacity(0.45),
                                            lineWidth: 0.7)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                }

                if let videoURL = currentEntry.exercise.videoURL {
                    detailCard(ATHLTHLocalization.choose(
                        english: "Demonstration", norwegian: "Demonstrasjon"
                    )) {
                        VideoPlayer(player: AVPlayer(url: videoURL))
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .id(videoURL)

                        if !videoURL.isFileURL {
                            Link(destination: videoURL) {
                                Label(ATHLTHLocalization.choose(
                                    english: "Open video source",
                                    norwegian: "Åpne videokilden"
                                ), systemImage: "arrow.up.right.square")
                                    .font(.caption.weight(.semibold))
                            }
                        } else {
                            Label(ATHLTHLocalization.choose(
                                english: "Private on-device video",
                                norwegian: "Privat video lagret på enheten"
                            ), systemImage: "iphone")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !displayedTips.isEmpty {
                    detailCard("Tips") {
                        ForEach(displayedTips, id: \.self) { tip in
                            Label(tip, systemImage: "lightbulb.fill")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if currentEntry.source == .repDB {
                    Link(destination: URL(string: "https://repdb.co")!) {
                        Label("Exercise data by RepDB", systemImage: "arrow.up.right.square")
                            .font(.caption.weight(.semibold))
                    }
                }

                if currentEntry.source == .custom {
                    Button("Delete Custom Exercise", role: .destructive) {
                        showingDelete = true
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding()
        }
        .background(ATHLTHTrainDesign.canvas.ignoresSafeArea())
        .navigationTitle(ATHLTHLocalization.choose(
            english: "Exercise", norwegian: "Øvelse"
        ))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    do {
                        preparedShare = try ATHLTHShareDraftFactory.exercise(
                            currentEntry, ownerID: session.profile.userID
                        )
                    } catch {
                        shareError = error.localizedDescription
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Share exercise", norwegian: "Del øvelse"
                ))
            }
            if currentEntry.source == .custom {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingEdit = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel(ATHLTHLocalization.choose(
                        english: "Edit exercise", norwegian: "Rediger øvelse"
                    ))
                }
            }
        }
        .onAppear(perform: refreshExerciseHistory)
        .onReceive(NotificationCenter.default.publisher(for: .athlthTrainingDataDidChange)) { _ in
            refreshExerciseHistory()
        }
        .sheet(isPresented: $showingEdit) {
            CustomExerciseEditorView(editing: currentEntry)
        }
        .sheet(item: $preparedShare) { draft in
            ATHLTHDirectShareSheet(draft: draft)
        }
        .alert(
            ATHLTHLocalization.choose(
                english: "Could not share exercise", norwegian: "Kunne ikke dele øvelsen"
            ),
            isPresented: Binding(
                get: { shareError != nil },
                set: { if !$0 { shareError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(shareError ?? "")
        }
        .task(id: currentEntry.id) {
            guard ATHLTHLocalization.isNorwegian,
                  currentEntry.source == .repDB else { return }
            languageStatus = await NorwegianExerciseAutoTranslation.availabilityStatus()
            if languageStatus == .installed {
                detailTranslationConfig = NorwegianExerciseAutoTranslation.configuration()
            }
        }
        .translationTask(detailTranslationConfig) { session in
            let exercise = currentEntry
            guard exercise.source == .repDB else { return }
            let raw = [exercise.name]
                + [exercise.summary].compactMap { $0 }
                + exercise.exercise.instructions
                + exercise.tips
            await norwegianTranslations.translate(
                texts: raw, using: session, batchSize: 14
            )
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let onSelect {
                VStack(spacing: 0) {
                    Button {
                        onSelect(currentEntry)
                        dismiss()
                    } label: {
                        Label(
                            selectionTitle ?? ATHLTHLocalization.choose(
                                english: "Add to workout",
                                norwegian: "Legg til i økten"
                            ),
                            systemImage: "plus.circle.fill"
                        )
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 62)
                        .background(
                            LinearGradient(
                                colors: [
                                    ATHLTHTrainDesign.bronze,
                                    ATHLTHTrainDesign.gold
                                ],
                                startPoint: .leading, endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: 24)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 10)
                }
                .background(ATHLTHTrainDesign.canvas)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(ATHLTHTrainDesign.rule.opacity(0.5))
                        .frame(height: 0.7)
                }
            }
        }
        .confirmationDialog(
            "Delete this custom exercise?",
            isPresented: $showingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                library.deleteCustomExercise(currentEntry.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var artwork: some View {
        let hasPeakArtwork = currentEntry.imagePeakURL != nil &&
            currentEntry.imagePeakURL != currentEntry.imageStartURL
        let hasMuscleArtwork = !currentEntry.exercise.primaryMuscles.isEmpty ||
            !currentEntry.exercise.secondaryMuscles.isEmpty
        let numberOfPages = 1 + (hasPeakArtwork ? 1 : 0) + (hasMuscleArtwork ? 1 : 0)
        let tileSize: CGFloat = 280

        return VStack(alignment: .leading, spacing: 9) {
            ScrollView(.horizontal) {
                HStack(spacing: 11) {
                    ExerciseArtwork(entry: currentEntry, size: tileSize)
                        .id(0)
                        .accessibilityLabel(ATHLTHLocalization.choose(
                            english: "Exercise starting position",
                            norwegian: "Øvelsens startposisjon"
                        ))
                    if hasPeakArtwork, let peakURL = currentEntry.imagePeakURL {
                        peakExerciseArtwork(peakURL, size: tileSize)
                            .id(1)
                    }
                    if hasMuscleArtwork {
                        ExerciseMuscleGalleryTile(
                            primaryMuscles: currentEntry.exercise.primaryMuscles,
                            secondaryMuscles: currentEntry.exercise.secondaryMuscles,
                            size: tileSize
                        )
                        .id(hasPeakArtwork ? 2 : 1)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 13)
                .padding(.vertical, 13)
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $galleryPage)
            .frame(height: tileSize + 26)

            HStack(spacing: 10) {
                Text("\(min((galleryPage ?? 0) + 1, numberOfPages)) / \(numberOfPages)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
                Spacer()
                if hasMuscleArtwork {
                    Label(ATHLTHLocalization.choose(
                        english: "Swipe for muscles used",
                        norwegian: "Sveip for muskler i bruk"
                    ), systemImage: "hand.draw")
                    .font(.caption2)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
                    .lineLimit(1)
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        galleryPage = max((galleryPage ?? 0) - 1, 0)
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 34, height: 34)
                        .background(ATHLTHTrainDesign.paper, in: Circle())
                }
                .disabled((galleryPage ?? 0) == 0)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Previous image", norwegian: "Forrige bilde"
                ))
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        galleryPage = min((galleryPage ?? 0) + 1, numberOfPages - 1)
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 34, height: 34)
                        .background(ATHLTHTrainDesign.paper, in: Circle())
                }
                .disabled((galleryPage ?? 0) >= numberOfPages - 1)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Next image", norwegian: "Neste bilde"
                ))
            }
            .foregroundStyle(ATHLTHTrainDesign.bronze)
            .padding(.horizontal, 13)
            .padding(.bottom, 12)
        }
        .athlthTrainPaper()
        .onChange(of: currentEntry.id) { _, _ in galleryPage = 0 }
    }

    private func peakExerciseArtwork(_ url: URL, size: CGFloat = 160) -> some View {
        Group {
            if url.isFileURL, let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ATHLTHStorageImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    default:
                        Color.clear
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .background(ExerciseMuscleGalleryTile.skyBlue)
         .clipShape(RoundedRectangle(cornerRadius: 20))
        .accessibilityLabel(ATHLTHLocalization.choose(
            english: "Exercise movement position",
            norwegian: "Øvelsens bevegelsesposisjon"
        ))
    }

    private func detailCard<Content: View>(
        _ title: String,
        symbol: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 11) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(
                            LinearGradient(
                                colors: [
                                    ATHLTHTrainDesign.gold,
                                    ATHLTHTrainDesign.bronze
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Circle()
                        )
                        .accessibilityHidden(true)
                } else {
                    Capsule()
                        .fill(ATHLTHTrainDesign.gold)
                        .frame(width: 3, height: 19)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.system(size: 21, weight: .medium, design: .serif))
                    .foregroundStyle(ATHLTHTrainDesign.ink)
            }
            content()
        }
        .padding(19)
        .frame(maxWidth: .infinity, alignment: .leading)
        .athlthTrainPaper()
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
    /// Allows the active-workout queue to use a newly created exercise
    /// immediately, without requiring a second search in the library.
    var onSaved: ((ExerciseLibraryEntry) -> Void)? = nil

    init(
        editing: ExerciseLibraryEntry? = nil,
        onSaved: ((ExerciseLibraryEntry) -> Void)? = nil
    ) {
        self.editing = editing
        self.onSaved = onSaved
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
    @EnvironmentObject private var subscriptionStore: SubscriptionStore

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
    @State private var showingEquipmentScanner = false
    @State private var showingScannerSubscription = false
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

                Section {
                    Button {
                        if session.hasPaidAccess {
                            showingEquipmentScanner = true
                        } else {
                            showingScannerSubscription = true
                        }
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Scan a gym machine and suggest an exercise",
                                norwegian: "Skann et apparat og få øvelsesforslag"
                            ),
                            systemImage: session.hasPaidAccess
                                ? "camera.viewfinder" : "lock.fill"
                        )
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 48)
                    }
                    .tint(ATHLTHPlanDesign.ink)
                    Text(
                        session.hasPaidAccess
                        ? ATHLTHLocalization.choose(
                            english: "Choose an existing ATHLTH exercise as a starting point, then edit before saving your own version.",
                            norwegian: "Bruk en eksisterende ATHLTH-øvelse som utgangspunkt, og tilpass den før du lagrer din egen versjon."
                        )
                        : ATHLTHLocalization.choose(
                            english: "Requires ATHLTH+. Creating your own exercises manually remains free.",
                            norwegian: "Krever ATHLTH+. Du kan fortsatt lage egne øvelser manuelt."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } header: {
                    Text(ATHLTHLocalization.choose(
                        english: "Identify equipment with AI",
                        norwegian: "Gjenkjenn apparat med AI"
                    ))
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

                    if selectedImageData == nil,
                       let originalImageURL = editing?.exercise.imageURL,
                       originalImageURL.isFileURL,
                       let image = UIImage(contentsOfFile: originalImageURL.path) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    Button {
                        showingVideoImporter = true
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Import demonstration video",
                                norwegian: "Importer demonstrasjonsvideo"
                            ),
                            systemImage: "video.badge.plus"
                        )
                    }
                    .disabled(isImportingVideo)

                    if isImportingVideo {
                        ProgressView(ATHLTHLocalization.choose(
                            english: "Copying video to ATHLTH…",
                            norwegian: "Kopierer video til ATHLTH…"
                        ))
                    }

                    if let previewVideoURL {
                        VideoPlayer(player: AVPlayer(url: previewVideoURL))
                            .frame(height: 210)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .id(previewVideoURL)

                        Button(role: .destructive) {
                            ExerciseStudioVideoStorage.discardOwnedVideo(importedVideoURL)
                            importedVideoURL = nil
                            videoURLText = ""
                            removingExistingVideo = true
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Remove video",
                                    norwegian: "Fjern video"
                                ),
                                systemImage: "trash"
                            )
                        }
                    }

                    if let studioError {
                        Text(studioError)
                            .font(.caption)
                            .foregroundStyle(.red)
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

                    Text(ATHLTHLocalization.choose(
                        english: "Import an MP4, MOV or M4V (max 120 MB), or enter a direct HTTPS video URL. Imported media stays on this device and is not included when you share a plan. Only publish technique demonstrations you have reviewed.",
                        norwegian: "Importer MP4, MOV eller M4V (maks 120 MB), eller legg inn en direkte HTTPS-lenke. Importert media lagres kun på denne enheten og følger ikke med delte planer. Kontroller teknikken før du deler en demonstrasjon."
                    ))
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
                        primaryMuscles.isEmpty ||
                        isImportingVideo
                    )
                }
            }
            .sheet(isPresented: $showingScannerSubscription) {
                SubscriptionOfferView {
                    session.applyStoreKitEntitlement(
                        subscriptionStore.activeEntitlement
                    )
                    showingScannerSubscription = false
                }
            }
            .sheet(isPresented: $showingEquipmentScanner) {
                ATHLTHEquipmentScannerView(onSelect: { entry in
                    name = library.localizedExerciseName(entry)
                    primaryMuscles = Set(ExerciseMuscleGroup.allCases.filter {
                        entry.exercise.primaryMuscles.contains($0.rawValue)
                    })
                    secondaryMuscles = Set(ExerciseMuscleGroup.allCases.filter {
                        entry.exercise.secondaryMuscles.contains($0.rawValue) &&
                        !primaryMuscles.contains($0)
                    })
                    equipment = entry.exercise.equipment.joined(separator: ", ")
                    instructions = library.localizedExerciseInstructions(entry).joined(separator: "\n")
                })
                .environmentObject(library)
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
                if let entry = library.customExercises.first(where: {
                    $0.id == editing.id
                }) {
                    onSaved?(entry)
                }
            } else {
                let created = library.createCustomExercise(
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
                onSaved?(created)
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
        let clean = videoURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty,
              let url = URL(string: clean),
              url.scheme?.lowercased() == "https",
              url.host != nil else { return nil }
        return url
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
        .background(ExerciseMuscleGalleryTile.skyBlue)
        .clipShape(RoundedRectangle(cornerRadius: min(size * 0.18, 20)))
    }

    private var fallback: some View {
        ExerciseMuscleGalleryTile.skyBlue
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


/// Compact anatomy summary shared by the library and workout planning.
/// Renders the existing vector atlas; never downloads extra muscle imagery.
/// A third exercise-gallery image, using the same native vector muscle atlas
/// and activation data as the former full-width muscle diagram. It requires
/// no image download and remains crisp on Retina and larger displays.
struct ExerciseMuscleGalleryTile: View {
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let size: CGFloat

    // Matches the pale blue exercise-illustration photography without
    // tinting the anatomy atlas or changing primary/secondary highlights.
    // Shared reference blue for start, peak and anatomy tiles (#DFF0FA).
    // Original catalog illustrations may have a baked-in slightly different
    // blue; keeping all three host surfaces equal prevents extra color drift.
    static let skyBlue = Color(red: 223.0 / 255, green: 240.0 / 255, blue: 250.0 / 255)

    private var profile: StrengthMuscleProfile {
        ExerciseMuscleProfileFactory.profile(
            primary: primaryMuscles, secondary: secondaryMuscles
        )
    }

    var body: some View {
        VStack(spacing: 5) {
            Text(ATHLTHLocalization.choose(
                english: "Muscles used", norwegian: "Muskler i bruk"
            ))
            .font(.system(size: size > 200 ? 13 : 10, weight: .semibold))
            .foregroundStyle(ATHLTHPlanDesign.ink)
            .lineLimit(1)

            HStack(alignment: .bottom, spacing: 6) {
                ForEach([true, false], id: \.self) { front in
                    VStack(spacing: 3) {
                        ATHLTHPremiumMuscleFigure(
                            profile: profile,
                            isFront: front,
                            activationTint: ATHLTHPlanDesign.accent
                        )
                        .frame(width: size * 0.36, height: size * 0.68)
                        Text(ATHLTHLocalization.choose(
                            english: front ? "Front" : "Back",
                            norwegian: front ? "Forside" : "Bakside"
                        ))
                        .font(.system(size: size > 200 ? 11 : 9, weight: .medium))
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(9)
        .frame(width: size, height: size)
        .background(Self.skyBlue,
                    in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ATHLTHLocalization.choose(
            english: "Muscles used: front and back. Primary: " +
                primaryMuscles.joined(separator: ", ") + ". Secondary: " +
                secondaryMuscles.joined(separator: ", "),
            norwegian: "Muskler i bruk, forside og bakside. Primære: " +
                primaryMuscles.joined(separator: ", ") + ". Sekundære: " +
                secondaryMuscles.joined(separator: ", ")
        ))
    }
}

/// Shared mapping for the full atlas and the compact gallery illustration.
/// A secondary region overlapping a primary muscle must remain primary.
enum ExerciseMuscleProfileFactory {
    static func profile(
        primary: [String], secondary: [String]
    ) -> StrengthMuscleProfile {
        let main = Set(primary.flatMap { StrengthMuscleResolver.regions(for: $0) })
        let assist = Set(secondary.flatMap { StrengthMuscleResolver.regions(for: $0) })
            .subtracting(main)
        return StrengthMuscleProfile(
            activations: main.union(assist).map {
                StrengthMuscleActivation(
                    region: $0, score: main.contains($0) ? 1 : 0.45
                )
            },
            primaryRegions: main,
            secondaryRegions: assist
        )
    }
}

struct ExerciseMuscleOverview: View {
    @EnvironmentObject private var library: ExerciseLibraryStore

    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    var showsAnatomy: Bool = true

    private var primaryRegions: Set<StrengthMuscleRegion> {
        Set(primaryMuscles.flatMap { StrengthMuscleResolver.regions(for: $0) })
    }

    private var secondaryRegions: Set<StrengthMuscleRegion> {
        Set(secondaryMuscles.flatMap { StrengthMuscleResolver.regions(for: $0) })
            .subtracting(primaryRegions)
    }

    private var profile: StrengthMuscleProfile {
        ExerciseMuscleProfileFactory.profile(
            primary: primaryMuscles, secondary: secondaryMuscles
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsAnatomy &&
                (!primaryRegions.isEmpty || !secondaryRegions.isEmpty) {
                HStack(spacing: 18) {
                    ForEach([true, false], id: \.self) { isFront in
                        VStack(spacing: 5) {
                            ATHLTHPremiumMuscleFigure(
                                profile: profile,
                                isFront: isFront,
                                activationTint: ATHLTHPlanDesign.accent
                            )
                            .frame(width: 82, height: 148)
                            Text(ATHLTHLocalization.choose(
                                english: isFront ? "Front" : "Back",
                                norwegian: isFront ? "Forside" : "Bakside"
                            ))
                            .font(.caption2)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(
                    ATHLTHPlanDesign.selectedSurface.opacity(0.42),
                    in: RoundedRectangle(cornerRadius: 16)
                )
            }
            if !primaryMuscles.isEmpty {
                muscleList(
                    primaryMuscles,
                    title: ATHLTHLocalization.choose(
                        english: "Primary", norwegian: "Primære"
                    ),
                    emphasized: true
                )
            }
            if !secondaryMuscles.isEmpty {
                muscleList(
                    secondaryMuscles,
                    title: ATHLTHLocalization.choose(
                        english: "Supporting", norwegian: "Sekundære"
                    ),
                    emphasized: false
                )
            }
        }
    }

    private func muscleList(
        _ muscles: [String], title: String, emphasized: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    ForEach(Array(Set(muscles)).sorted(), id: \.self) {
                        muscleChip($0, emphasized: emphasized)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(Set(muscles)).sorted(), id: \.self) {
                        muscleChip($0, emphasized: emphasized)
                    }
                }
            }
        }
    }

    private func muscleChip(_ muscle: String, emphasized: Bool) -> some View {
        Text(library.localizedBodyPartTitle(muscle))
            .font(.caption.weight(emphasized ? .semibold : .regular))
            .foregroundStyle(
                emphasized ? ATHLTHPlanDesign.ink : ATHLTHPlanDesign.secondaryInk
            )
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                emphasized
                    ? ATHLTHPlanDesign.selectedSurface
                    : ATHLTHPlanDesign.outline.opacity(0.30),
                in: Capsule()
            )
    }
}

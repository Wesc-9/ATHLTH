import Foundation
import Supabase
import SwiftUI

enum WorkoutTemplateBlockKind: String, Codable, CaseIterable, Hashable {
    case run
    case exercise
    case rest
    case note

    var title: String {
        switch self {
        case .run: return "Run"
        case .exercise: return "Exercise"
        case .rest: return "Rest"
        case .note: return "Note"
        }
    }

    var systemImage: String {
        switch self {
        case .run: return "figure.run"
        case .exercise: return "dumbbell.fill"
        case .rest: return "pause.fill"
        case .note: return "text.alignleft"
        }
    }
}

/// Common phase taxonomy for running, strength, mobility and hybrid blocks.
enum WorkoutPhaseKind: String, Codable, CaseIterable, Identifiable {
    case warmup
    case main
    case recovery
    case cooldown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .warmup: return ATHLTHLocalization.choose(english: "Warm-up", norwegian: "Oppvarming")
        case .main: return ATHLTHLocalization.choose(english: "Main set", norwegian: "Hoveddel")
        case .recovery: return ATHLTHLocalization.choose(english: "Recovery", norwegian: "Pause")
        case .cooldown: return ATHLTHLocalization.choose(english: "Cool-down", norwegian: "Nedtrapping")
        }
    }

    var symbol: String {
        switch self {
        case .warmup: return "flame"
        case .main: return "figure.run"
        case .recovery: return "pause.circle"
        case .cooldown: return "wind"
        }
    }
}

struct WorkoutTemplateBlock: Codable, Hashable, Identifiable {
    let sequence: Int
    var kind: WorkoutTemplateBlockKind
    var title: String
    var exerciseSlug: String?
    var distanceMeters: Double?
    var repetitions: Int?
    var durationSeconds: TimeInterval?
    var targetWeightKilograms: Double?
    var loadNote: String?
    var notes: String?
    /// Missing in historic templates; assume the main section except rests.
    var phase: WorkoutPhaseKind? = nil
    var targetPaceSecondsPerKilometer: Double? = nil
    var targetHeartRateZone: Int? = nil

    var resolvedPhase: WorkoutPhaseKind {
        phase ?? (kind == .rest ? .recovery : .main)
    }

    var id: String {
        "\(sequence)|\(kind.rawValue)|\(title)"
    }

    enum CodingKeys: String, CodingKey {
        case sequence
        case kind
        case title
        case exerciseSlug = "exercise_slug"
        case distanceMeters = "distance_meters"
        case repetitions
        case durationSeconds = "duration_seconds"
        case targetWeightKilograms = "target_weight_kg"
        case loadNote = "load_note"
        case notes
        case phase
        case targetPaceSecondsPerKilometer = "target_pace_seconds_per_km"
        case targetHeartRateZone = "target_hr_zone"
    }

    var targetText: String? {
        var parts: [String] = []

        if let distanceMeters, distanceMeters > 0 {
            if distanceMeters >= 1_000 {
                let kilometers = distanceMeters / 1_000
                if kilometers.rounded() == kilometers {
                    parts.append("\(Int(kilometers)) km")
                } else {
                    parts.append(
                        String(format: "%.1f km", kilometers)
                    )
                }
            } else {
                parts.append("\(Int(distanceMeters.rounded())) m")
            }
        }

        if let repetitions, repetitions > 0 {
            parts.append("\(repetitions) reps")
        }

        if let durationSeconds, durationSeconds > 0 {
            let minutes = Int(durationSeconds) / 60
            let seconds = Int(durationSeconds) % 60
            if minutes > 0 && seconds > 0 {
                parts.append("\(minutes)m \(seconds)s")
            } else if minutes > 0 {
                parts.append("\(minutes) min")
            } else {
                parts.append("\(seconds) sec")
            }
        }

        if let targetWeightKilograms,
           targetWeightKilograms > 0 {
            parts.append(
                String(
                    format: "%.1f kg",
                    targetWeightKilograms
                )
            )
        }

        if let targetPaceSecondsPerKilometer,
           targetPaceSecondsPerKilometer > 0 {
            let seconds = Int(targetPaceSecondsPerKilometer.rounded())
            parts.append(String(format: "%d:%02d/km", seconds / 60, seconds % 60))
        }

        if let targetHeartRateZone, (1...5).contains(targetHeartRateZone) {
            parts.append("Puls sone \(targetHeartRateZone)")
        }

        if let loadNote,
           !loadNote.trimmingCharacters(
                in: .whitespacesAndNewlines
           ).isEmpty {
            parts.append(loadNote)
        }

        return parts.isEmpty
            ? nil
            : parts.joined(separator: " · ")
    }
}

struct WorkoutTemplateCatalogEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let slug: String
    let title: String
    let summary: String
    let category: String
    let difficulty: String
    let estimatedDurationMinutes: Int?
    let tags: [String]
    let sourceLabel: String?
    let sourceURL: String?
    let blocks: [WorkoutTemplateBlock]
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case slug
        case title
        case summary
        case category
        case difficulty
        case estimatedDurationMinutes =
            "estimated_duration_minutes"
        case tags
        case sourceLabel = "source_label"
        case sourceURL = "source_url"
        case blocks
        case sortOrder = "sort_order"
    }

    var categoryTitle: String {
        category
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    var workoutKind: WorkoutKind {
        switch category {
        case "running":
            return .running
        case "strength":
            return .strength
        case "mobility":
            return .mobility
        default:
            return .custom
        }
    }

    var systemImage: String {
        switch category {
        case "running":
            return "figure.run"
        case "strength":
            return "dumbbell.fill"
        case "mobility":
            return "figure.flexibility"
        case "hybrid":
            return "figure.run.square.stack.fill"
        default:
            return "square.stack.3d.up.fill"
        }
    }

    func plannedSession() -> PlannedSession {
        var result = PlannedSession(
            id: UUID(),
            title: title,
            kind: workoutKind,
            scheduledStart: nil,
            durationMinutes: estimatedDurationMinutes,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes: summary
        )

        result.workoutTemplateID = id
        result.workoutBlocks = blocks
        result.workoutCategory = category
        return result
    }
}

@MainActor
final class WorkoutTemplateCatalogStore: ObservableObject {
    @Published private(set) var entries:
        [WorkoutTemplateCatalogEntry] =
            WorkoutTemplateCatalogEntry.fallbackCatalog
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let client: SupabaseClient
    private var loadedRemote = false

    init(client: SupabaseClient = SupabaseEnvironment.client) {
        self.client = client
    }

    func refresh(force: Bool = false) async {
        if loadedRemote && !force { return }
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let remote: [WorkoutTemplateCatalogEntry] =
                try await client
                    .from("workout_template_catalog")
                    .select(
                        "id,slug,title,summary,category,difficulty,estimated_duration_minutes,tags,source_label,source_url,blocks,sort_order"
                    )
                    .eq("is_published", value: true)
                    .order("sort_order", ascending: true)
                    .execute()
                    .value

            if !remote.isEmpty {
                entries = remote
                loadedRemote = true
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct WorkoutTemplateLibraryView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var favorites: LibraryFavoritesStore
    @EnvironmentObject private var recents: LibraryRecentsStore

    @StateObject private var catalog =
        WorkoutTemplateCatalogStore()
    @State private var query = ""
    @State private var selectedCategory = "All"
    @State private var favoritesOnly = false

    private var categories: [String] {
        ["All"] +
        Array(Set(catalog.entries.map(\.categoryTitle)))
            .sorted()
    }

    private var filteredEntries:
        [WorkoutTemplateCatalogEntry] {
        let clean = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        return catalog.entries.filter { entry in
            let categoryMatches =
                selectedCategory == "All" ||
                entry.categoryTitle == selectedCategory

            let favoriteMatches =
                !favoritesOnly ||
                favorites.isFavorite(
                    .workout,
                    itemID: entry.id.uuidString
                )

            let searchMatches =
                clean.isEmpty ||
                entry.title.localizedCaseInsensitiveContains(clean) ||
                entry.summary.localizedCaseInsensitiveContains(clean) ||
                entry.tags.joined(separator: " ")
                    .localizedCaseInsensitiveContains(clean)

            return categoryMatches &&
                favoriteMatches &&
                searchMatches
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                LibraryPremiumIntro(
                    eyebrow: "WORKOUT LIBRARY",
                    title: "Complete workouts",
                    subtitle:
                        "A workout is the session you actually perform. It can combine running, exercises, rest, routes and targets in one structure.",
                    icon: "rectangle.stack.fill",
                    accent: ATHLTHTheme.accent
                ) {
                    HStack(spacing: 8) {
                        LibraryStatPill(
                            value: "\(catalog.entries.count)",
                            label: "workouts",
                            icon: "rectangle.stack.fill",
                            tint: ATHLTHTheme.accent
                        )

                        LibraryStatPill(
                            value:
                                "\(favorites.count(for: .workout))",
                            label: "saved",
                            icon: "star.fill",
                            tint: ATHLTHTheme.premiumGold
                        )
                    }
                }

                ScrollView(
                    .horizontal,
                    showsIndicators: false
                ) {
                    HStack(spacing: 8) {
                        Button {
                            favoritesOnly.toggle()
                        } label: {
                            filterChip(
                                "Favorites",
                                systemImage: "star.fill",
                                selected: favoritesOnly
                            )
                        }
                        .buttonStyle(.plain)

                        ForEach(categories, id: \.self) {
                            category in
                            Button {
                                selectedCategory = category
                            } label: {
                                filterChip(
                                    category,
                                    systemImage: nil,
                                    selected:
                                        selectedCategory ==
                                        category
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if filteredEntries.isEmpty {
                    ContentUnavailableView(
                        favoritesOnly
                            ? "No favorite workouts yet"
                            : "No workouts found",
                        systemImage: "rectangle.stack",
                        description: Text(
                            catalog.errorMessage ??
                            "Try another search or category."
                        )
                    )
                    .padding(.top, 32)
                } else {
                    ForEach(filteredEntries) { entry in
                        ZStack(alignment: .topTrailing) {
                            NavigationLink {
                                WorkoutTemplateDetailView(
                                    entry: entry
                                )
                            } label: {
                                workoutCard(entry)
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(
                                TapGesture().onEnded {
                                    recents.markUsed(
                                        .workout,
                                        itemID:
                                            entry.id.uuidString,
                                        title: entry.title,
                                        subtitle:
                                            entry.categoryTitle,
                                        icon:
                                            entry.systemImage
                                    )
                                }
                            )

                            LibraryFavoriteButton(
                                kind: .workout,
                                itemID:
                                    entry.id.uuidString,
                                title: entry.title,
                                subtitle:
                                    entry.categoryTitle,
                                icon: entry.systemImage
                            )
                            .padding(12)
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(
            ATHLTHPremiumCanvas(
                accent: ATHLTHTheme.accent.opacity(0.16)
            )
        )
        .navigationTitle("Workouts")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $query,
            prompt: "Search workouts"
        )
        .task {
            async let workoutRefresh: Void =
                catalog.refresh()
            async let favoriteRefresh: Void =
                favorites.refresh()
            _ = await (
                workoutRefresh,
                favoriteRefresh
            )
        }
        .refreshable {
            async let workoutRefresh: Void =
                catalog.refresh(force: true)
            async let favoriteRefresh: Void =
                favorites.refresh(force: true)
            _ = await (
                workoutRefresh,
                favoriteRefresh
            )
        }
    }

    private func workoutCard(
        _ entry: WorkoutTemplateCatalogEntry
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: entry.systemImage)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(workoutTint(entry))
                .frame(width: 50, height: 50)
                .background(
                    workoutTint(entry).opacity(0.10),
                    in: RoundedRectangle(
                        cornerRadius: 16,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 5) {
                Text(entry.categoryTitle.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(workoutTint(entry))

                Text(entry.title)
                    .font(.headline)
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .multilineTextAlignment(.leading)

                Text(entry.summary)
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 9) {
                    Label(
                        "\(entry.blocks.count) blocks",
                        systemImage:
                            "list.number"
                    )

                    if let minutes =
                        entry.estimatedDurationMinutes {
                        Label(
                            "~\(minutes) min",
                            systemImage: "clock"
                        )
                    }
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
                .padding(.top, 2)
            }

            Spacer(minLength: 34)
        }
        .padding(16)
        .background(
            Color.white.opacity(0.86),
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
                Color.white.opacity(0.94),
                lineWidth: 0.8
            )
        }
    }

    private func workoutTint(
        _ entry: WorkoutTemplateCatalogEntry
    ) -> Color {
        switch entry.category {
        case "hybrid": return .orange
        case "strength": return .indigo
        case "running": return ATHLTHTheme.vitality
        case "mobility": return .teal
        default: return ATHLTHTheme.accent
        }
    }

    private func filterChip(
        _ title: String,
        systemImage: String?,
        selected: Bool
    ) -> some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
            }

            Text(title)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(
            selected
                ? Color.white
                : ATHLTHTheme.primaryText.opacity(0.82)
        )
        .padding(.horizontal, 13)
        .frame(height: 38)
        .background(
            selected
                ? ATHLTHTheme.accentDeep
                : Color.white.opacity(0.86),
            in: Capsule()
        )
    }
}

struct WorkoutTemplateDetailView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var favorites: LibraryFavoritesStore

    let entry: WorkoutTemplateCatalogEntry

    @State private var saved = false
    @State private var showingWorkout = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ATHLTHCard {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: entry.systemImage)
                            .font(
                                .system(
                                    size: 25,
                                    weight: .semibold
                                )
                            )
                            .foregroundStyle(
                                ATHLTHTheme.accentDeep
                            )
                            .frame(width: 54, height: 54)
                            .background(
                                ATHLTHTheme.accentSoft,
                                in: RoundedRectangle(
                                    cornerRadius: 17,
                                    style: .continuous
                                )
                            )

                        VStack(alignment: .leading, spacing: 5) {
                            Text(
                                entry.categoryTitle.uppercased()
                            )
                            .font(
                                .system(
                                    size: 9,
                                    weight: .bold
                                )
                            )
                            .tracking(1.6)
                            .foregroundStyle(
                                ATHLTHTheme.mutedText
                            )

                            Text(entry.title)
                                .font(.title2.weight(.bold))

                            Text(entry.summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)
                    }
                }

                ATHLTHCard {
                    HStack(spacing: 16) {
                        detailMetric(
                            title: "Blocks",
                            value: "\(entry.blocks.count)"
                        )

                        Divider()
                            .frame(height: 34)

                        detailMetric(
                            title: "Level",
                            value: entry.difficulty
                        )

                        if let minutes =
                            entry.estimatedDurationMinutes {
                            Divider()
                                .frame(height: 34)

                            detailMetric(
                                title: "Time",
                                value: "~\(minutes)m"
                            )
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("WORKOUT")
                        .font(.caption2.weight(.bold))
                        .tracking(1.8)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )

                    ForEach(entry.blocks) { block in
                        blockRow(block)
                    }
                }

                if let source = entry.sourceLabel {
                    ATHLTHCard {
                        Label(
                            source,
                            systemImage: "checkmark.seal.fill"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(
                            ATHLTHTheme.accentDeep
                        )

                        if entry.tags.contains("hyrox") {
                            Text(
                                "HYROX race loads differ by division. Use the load specified for your division when a block says race load."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 5)
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        session.saveSharedWorkout(
                            entry.plannedSession(),
                            sourceSessionID: entry.id
                        )
                        saved = true
                    } label: {
                        Label(
                            saved
                                ? "Saved"
                                : "Save",
                            systemImage:
                                saved
                                    ? "checkmark.circle.fill"
                                    : "square.and.arrow.down"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                    }
                    .buttonStyle(.bordered)
                    .disabled(saved)

                    Button {
                        showingWorkout = true
                    } label: {
                        Label(
                            "Start",
                            systemImage: "play.fill"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accentDeep)
                }
            }
            .padding(18)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(
            ATHLTHPremiumCanvas(
                accent: ATHLTHTheme.accent.opacity(0.15)
            )
        )
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(
            isPresented: $showingWorkout
        ) {
            StructuredWorkoutSessionView(
                workout: entry.plannedSession()
            )
            .environmentObject(session)
        }
    }

    private func blockRow(
        _ block: WorkoutTemplateBlock
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(block.sequence)")
                .font(.caption.weight(.bold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(width: 30, height: 30)
                .background(
                    ATHLTHTheme.accentSoft,
                    in: Circle()
                )

            Image(systemName: block.kind.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(
                    block.kind == .run
                        ? ATHLTHTheme.vitality
                        : ATHLTHTheme.accentDeep
                )
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(block.title)
                    .font(.subheadline.weight(.semibold))

                if let target = block.targetText {
                    Text(target)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let notes = block.notes,
                   !notes.isEmpty {
                    Text(notes)
                        .font(.caption2)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                }
            }

            Spacer(minLength: 0)
        }
        .padding(13)
        .background(
            Color.white.opacity(0.78),
            in: RoundedRectangle(
                cornerRadius: 17,
                style: .continuous
            )
        )
    }

    private func detailMetric(
        title: String,
        value: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline)
                .foregroundStyle(ATHLTHTheme.primaryText)

            Text(title)
                .font(.caption2)
                .foregroundStyle(ATHLTHTheme.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension WorkoutTemplateCatalogEntry {
    static let fallbackCatalog:
        [WorkoutTemplateCatalogEntry] = [
            WorkoutTemplateCatalogEntry(
                id: UUID(
                    uuidString:
                        "C3000000-0000-0000-0000-000000000001"
                )!,
                slug: "hyrox-full-race-simulation",
                title: "HYROX Full Race Simulation",
                summary:
                    "Full race-order simulation with eight 1 km runs and all eight stations.",
                category: "hybrid",
                difficulty: "Advanced",
                estimatedDurationMinutes: 90,
                tags: [
                    "hyrox",
                    "hybrid",
                    "race-simulation"
                ],
                sourceLabel:
                    "HYROX official race format",
                sourceURL:
                    "https://hyrox.com/the-fitness-race/",
                blocks: hyroxFullBlocks,
                sortOrder: 10
            ),
            WorkoutTemplateCatalogEntry(
                id: UUID(
                    uuidString:
                        "C3000000-0000-0000-0000-000000000002"
                )!,
                slug: "hyrox-half-simulation",
                title: "HYROX Half Simulation",
                summary:
                    "Shorter race-order session with 500 m runs and reduced station volume.",
                category: "hybrid",
                difficulty: "Intermediate",
                estimatedDurationMinutes: 50,
                tags: [
                    "hyrox",
                    "hybrid",
                    "simulation"
                ],
                sourceLabel:
                    "ATHLTH adaptation of HYROX race format",
                sourceURL:
                    "https://hyrox.com/the-fitness-race/",
                blocks: hyroxHalfBlocks,
                sortOrder: 20
            ),
            WorkoutTemplateCatalogEntry(
                id: UUID(
                    uuidString:
                        "C3000000-0000-0000-0000-000000000003"
                )!,
                slug: "hyrox-pft",
                title: "HYROX PFT",
                summary:
                    "Official HYROX Physical Fitness Test performed for time.",
                category: "hybrid",
                difficulty: "All levels",
                estimatedDurationMinutes: 35,
                tags: ["hyrox", "pft", "fitness-test"],
                sourceLabel: "HYROX PFT",
                sourceURL:
                    "https://register.hyrox.com/event/hyrox-pft---new-york/",
                blocks: hyroxPFTBlocks,
                sortOrder: 30
            )
        ]

    private static let hyroxFullBlocks:
        [WorkoutTemplateBlock] = {
            let stations:
                [(String, String, Double?, Int?)] = [
                    ("SkiErg", "ski-erg", 1_000, nil),
                    ("Sled Push", "sled-push", 50, nil),
                    ("Sled Pull", "sled-pull", 50, nil),
                    (
                        "Burpee Broad Jumps",
                        "burpee-broad-jump",
                        80,
                        nil
                    ),
                    ("Row", "rowing-erg", 1_000, nil),
                    (
                        "Farmers Carry",
                        "farmers-carry",
                        200,
                        nil
                    ),
                    (
                        "Sandbag Lunges",
                        "sandbag-walking-lunge",
                        100,
                        nil
                    ),
                    ("Wall Balls", "wall-ball", nil, 100)
                ]

            var result: [WorkoutTemplateBlock] = []

            for (index, station) in
                stations.enumerated() {
                result.append(
                    WorkoutTemplateBlock(
                        sequence: index * 2 + 1,
                        kind: .run,
                        title: "Run \(index + 1)",
                        exerciseSlug: nil,
                        distanceMeters: 1_000,
                        repetitions: nil,
                        durationSeconds: nil,
                        targetWeightKilograms: nil,
                        loadNote: nil,
                        notes: nil
                    )
                )

                result.append(
                    WorkoutTemplateBlock(
                        sequence: index * 2 + 2,
                        kind: .exercise,
                        title: station.0,
                        exerciseSlug: station.1,
                        distanceMeters: station.2,
                        repetitions: station.3,
                        durationSeconds: nil,
                        targetWeightKilograms: nil,
                        loadNote:
                            [
                                "sled-push",
                                "sled-pull",
                                "farmers-carry",
                                "sandbag-walking-lunge",
                                "wall-ball"
                            ].contains(station.1)
                                ? "Use your division race load"
                                : nil,
                        notes: nil
                    )
                )
            }

            return result
        }()

    private static let hyroxHalfBlocks:
        [WorkoutTemplateBlock] =
            hyroxFullBlocks.map { block in
                WorkoutTemplateBlock(
                    sequence: block.sequence,
                    kind: block.kind,
                    title: block.title,
                    exerciseSlug: block.exerciseSlug,
                    distanceMeters:
                        block.distanceMeters.map {
                            $0 / 2
                        },
                    repetitions:
                        block.repetitions.map {
                            max($0 / 2, 1)
                        },
                    durationSeconds:
                        block.durationSeconds,
                    targetWeightKilograms:
                        block.targetWeightKilograms,
                    loadNote:
                        block.loadNote == nil
                            ? nil
                            : "Use a controlled training load",
                    notes: block.notes
                )
            }

    private static let hyroxPFTBlocks:
        [WorkoutTemplateBlock] = [
            WorkoutTemplateBlock(
                sequence: 1,
                kind: .run,
                title: "Run",
                exerciseSlug: nil,
                distanceMeters: 1_000,
                repetitions: nil,
                durationSeconds: nil,
                targetWeightKilograms: nil,
                loadNote: nil,
                notes: nil
            ),
            WorkoutTemplateBlock(
                sequence: 2,
                kind: .exercise,
                title: "Burpee Broad Jumps",
                exerciseSlug: "burpee-broad-jump",
                distanceMeters: nil,
                repetitions: 50,
                durationSeconds: nil,
                targetWeightKilograms: nil,
                loadNote: nil,
                notes: nil
            ),
            WorkoutTemplateBlock(
                sequence: 3,
                kind: .exercise,
                title: "Stationary Lunges",
                exerciseSlug: "stationary-lunge",
                distanceMeters: nil,
                repetitions: 100,
                durationSeconds: nil,
                targetWeightKilograms: nil,
                loadNote: nil,
                notes: nil
            ),
            WorkoutTemplateBlock(
                sequence: 4,
                kind: .exercise,
                title: "Row / Run",
                exerciseSlug: "rowing-erg",
                distanceMeters: 1_000,
                repetitions: nil,
                durationSeconds: nil,
                targetWeightKilograms: nil,
                loadNote: nil,
                notes:
                    "Use the rower, or run if the rower option is unavailable."
            ),
            WorkoutTemplateBlock(
                sequence: 5,
                kind: .exercise,
                title: "Hand-Release Push-Ups",
                exerciseSlug: "hand-release-push-up",
                distanceMeters: nil,
                repetitions: 30,
                durationSeconds: nil,
                targetWeightKilograms: nil,
                loadNote: nil,
                notes: nil
            ),
            WorkoutTemplateBlock(
                sequence: 6,
                kind: .exercise,
                title: "Wall Balls",
                exerciseSlug: "wall-ball",
                distanceMeters: nil,
                repetitions: 100,
                durationSeconds: nil,
                targetWeightKilograms: nil,
                loadNote:
                    "6 kg / 4 kg as specified by the HYROX PFT",
                notes: nil
            )
        ]
}


struct MyWorkoutTemplatesView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var runningLibrary: RunningWorkoutLibraryStore

    @State private var completionHistory:
        [StructuredWorkoutCompletion] = []
    @State private var showingRunningBuilder = false
    @State private var showingHybridBuilder = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Button {
                        showingRunningBuilder = true
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "Advanced run", norwegian: "Detaljert løpeøkt"
                        ), systemImage: "figure.run")
                            .frame(maxWidth: .infinity)
                    }
                    Button {
                        showingHybridBuilder = true
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "Strength / hybrid", norwegian: "Styrke / hybrid"
                        ), systemImage: "dumbbell")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                if !runningLibrary.customTemplates.isEmpty {
                    Text(ATHLTHLocalization.choose(
                        english: "SAVED DETAILED RUNS", norwegian: "LAGREDE DETALJØKTER"
                    ))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    ForEach(runningLibrary.customTemplates) { workout in
                        NavigationLink {
                            RunningWorkoutDetailView(
                                workout: workout,
                                selectionTitle: nil,
                                onSelect: nil,
                                onStart: nil
                            )
                        } label: {
                            HStack {
                                Label(workout.title, systemImage: "figure.run")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(workout.blocks.count) " +
                                     ATHLTHLocalization.choose(
                                         english: "phases", norwegian: "deler"
                                     ))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                            }
                            .padding(14)
                            .background(.white, in: RoundedRectangle(cornerRadius: 15))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !completionHistory.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("RECENT COMPLETED")
                            .font(.caption2.weight(.bold))
                            .tracking(1.7)
                            .foregroundStyle(
                                ATHLTHTheme.mutedText
                            )

                        ForEach(
                            completionHistory.prefix(3)
                        ) { completion in
                            HStack(spacing: 12) {
                                Image(
                                    systemName:
                                        "checkmark.circle.fill"
                                )
                                .foregroundStyle(.green)
                                .frame(width: 34, height: 34)
                                .background(
                                    Color.green.opacity(0.09),
                                    in: Circle()
                                )

                                VStack(
                                    alignment: .leading,
                                    spacing: 3
                                ) {
                                    Text(completion.title)
                                        .font(
                                            .subheadline
                                                .weight(.semibold)
                                        )

                                    Text(
                                        "\(completion.completedBlockCount)/\(completion.totalBlockCount) blocks · \(completion.endedAt.formatted(date: .abbreviated, time: .shortened))"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }
                            .padding(12)
                            .background(
                                Color.white.opacity(0.72),
                                in: RoundedRectangle(
                                    cornerRadius: 17,
                                    style: .continuous
                                )
                            )
                        }
                    }
                }

                if session.savedWorkoutTemplates.isEmpty &&
                   runningLibrary.customTemplates.isEmpty {
                    ContentUnavailableView(
                        "No saved workouts",
                        systemImage: "rectangle.stack",
                        description: Text(
                            "Save a workout from the Library or create one of your own."
                        )
                    )
                    .padding(.top, 60)
                } else {
                    ForEach(
                        session.savedWorkoutTemplates
                    ) { workout in
                        savedWorkoutCard(workout)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(
            ATHLTHPremiumCanvas(
                accent: ATHLTHTheme.accent.opacity(0.14)
            )
        )
        .navigationTitle("My Workouts")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingRunningBuilder) {
            ATHLTHTrainIntervalComposerView { workout in
                runningLibrary.save(workout)
            }
        }
        .sheet(isPresented: $showingHybridBuilder) {
            WorkoutTemplateBuilderView()
        }
        .task {
            completionHistory =
                StructuredWorkoutCompletionStore.load(
                    userID: session.profile.userID
                )
        }
    }

    private func savedWorkoutCard(
        _ workout: PlannedSession
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(
                    systemName:
                        workout.isStructuredWorkout
                            ? "rectangle.stack.fill"
                            : workout.kind.systemImage
                )
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(width: 44, height: 44)
                .background(
                    ATHLTHTheme.accentSoft,
                    in: RoundedRectangle(
                        cornerRadius: 14,
                        style: .continuous
                    )
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(workout.title)
                        .font(.headline)

                    Text(savedWorkoutSubtitle(workout))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Menu {
                    Button(
                        "Delete",
                        role: .destructive
                    ) {
                        session.deleteSavedWorkoutTemplate(
                            workout.id
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }

            if workout.isStructuredWorkout {
                HStack(spacing: 7) {
                    ForEach(
                        workout.resolvedWorkoutBlocks
                            .prefix(4)
                    ) { block in
                        Label(
                            block.title,
                            systemImage:
                                block.kind.systemImage
                        )
                        .font(.system(size: 9.5, weight: .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(
                            Color.primary.opacity(0.045),
                            in: Capsule()
                        )
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(15)
        .background(
            Color.white.opacity(0.82),
            in: RoundedRectangle(
                cornerRadius: 21,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 21,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.90),
                lineWidth: 0.8
            )
        }
    }

    private func savedWorkoutSubtitle(
        _ workout: PlannedSession
    ) -> String {
        if workout.isStructuredWorkout {
            let category =
                workout.workoutCategory?
                    .capitalized ??
                "Workout"
            return
                "\(category) · \(workout.resolvedWorkoutBlocks.count) blocks"
        }

        return workout.kind.title
    }
}

struct WorkoutTemplateBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var exerciseLibrary: ExerciseLibraryStore

    @State private var title = ""
    @State private var blocks: [WorkoutTemplateBlock] = []
    @State private var selectedRouteID: UUID?
    @State private var showingExercisePicker = false
    @State private var selectedPhase: WorkoutPhaseKind = .main
    @State private var expandedBlockIndex: Int?

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    private var hasRunning: Bool {
        blocks.contains(where: { $0.kind == .run })
    }

    private var hasStrength: Bool {
        blocks.contains(where: { $0.kind == .exercise })
    }

    // Infer the workout type from its actual content, instead of forcing a type
    // before the user has added any blocks.
    private var category: String {
        if hasRunning && hasStrength { return "hybrid" }
        if hasRunning { return "running" }
        if hasStrength { return "strength" }
        return "custom"
    }

    private var categoryTitle: String {
        switch category {
        case "hybrid": return tr("Hybrid", "Hybrid")
        case "running": return tr("Running", "Løping")
        case "strength": return tr("Strength", "Styrke")
        default: return tr("Custom", "Egendefinert")
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (hasRunning || hasStrength)
    }

    private var knownDurationMinutes: Int? {
        let total = blocks.compactMap(\.durationSeconds).reduce(0, +)
        return total > 0 ? Int(ceil(total / 60)) : nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    workoutOverview
                    timeline
                    addBlockSection
                    if hasRunning {
                        routeSection
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 24)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(ATHLTHPremiumCanvas(accent: Color.teal.opacity(0.12)))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                saveBar
            }
            .navigationTitle(tr("Create Workout", "Lag treningsøkt"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel", "Avbryt")) {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingExercisePicker) {
                NavigationStack {
                    // No fixed source: allow switching between the ATHLTH
                    // library and exercises created by the user.
                    ExerciseLibraryView(
                        source: nil,
                        selectionTitle: tr("Add Exercise", "Legg til øvelse")
                    ) { entry in
                        addExerciseBlock(entry)
                        showingExercisePicker = false
                    }
                }
            }
            .task {
                if exerciseLibrary.allExercises.isEmpty {
                    await exerciseLibrary.refresh()
                }
            }
        }
    }

    private var workoutOverview: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(tr("NEW WORKOUT", "NY TRENINGSØKT"))
                        .font(.caption2.weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    Spacer()
                    Label(categoryTitle, systemImage: "circle.grid.2x2")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                }

                TextField(tr("Name your workout", "Gi økten et navn"), text: $title)
                    .font(.title2.weight(.bold))
                    .textInputAutocapitalization(.sentences)

                HStack(spacing: 14) {
                    Label("\(blocks.count) " + tr("blocks", "blokker"),
                          systemImage: "rectangle.stack")
                    if let knownDurationMinutes {
                        Label("\(knownDurationMinutes) " + tr("min", "min"),
                              systemImage: "clock")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(tr("YOUR WORKOUT", "DIN TRENINGSØKT"))
                    .font(.caption2.weight(.bold))
                    .tracking(1.6)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                Spacer()
                if !blocks.isEmpty {
                    Text(tr("Tap a block to edit", "Trykk på en blokk for å redigere"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if blocks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "figure.run.square.stack")
                        .font(.system(size: 29, weight: .light))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                    Text(tr("Build your session, one block at a time",
                            "Bygg økten, én blokk om gangen"))
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Text(tr("Start with an exercise, run or warm-up. The timeline will appear here.",
                            "Start med en øvelse, løpetur eller oppvarming. Økten vises her etter hvert."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button {
                        showingExercisePicker = true
                    } label: {
                        Label(tr("Add exercise", "Legg til øvelse"),
                              systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accentDeep)
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.82),
                            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(blocks.indices), id: \.self) { index in
                        builderBlockRow(index)
                    }
                }
            }
        }
    }

    private func builderBlockRow(_ index: Int) -> some View {
        let block = blocks[index]
        let isExpanded = expandedBlockIndex == index

        return HStack(alignment: .top, spacing: 11) {
            VStack(spacing: 4) {
                Image(systemName: block.resolvedPhase.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .frame(width: 30, height: 30)
                    .background(ATHLTHTheme.accentSoft, in: Circle())
                RoundedRectangle(cornerRadius: 1)
                    .fill(ATHLTHTheme.accentDeep.opacity(0.16))
                    .frame(width: 2, height: isExpanded ? 170 : 64)
            }
            .frame(width: 30)

            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 8) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            expandedBlockIndex = isExpanded ? nil : index
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: block.kind.systemImage)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(
                                    block.kind == .run
                                        ? ATHLTHTheme.vitality
                                        : ATHLTHTheme.accentDeep
                                )
                                .frame(width: 26)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(block.resolvedPhase.title.uppercased())
                                    .font(.caption2.weight(.bold))
                                    .tracking(0.8)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                                Text(block.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                if let targetText = block.targetText {
                                    Text(targetText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Menu {
                        ForEach(WorkoutPhaseKind.allCases) { phase in
                            Button {
                                blocks[index].phase = phase
                            } label: {
                                Label(phase.title, systemImage: phase.symbol)
                            }
                        }
                        if index > 0 {
                            Button(tr("Move up", "Flytt opp"), systemImage: "arrow.up") {
                                blocks.swapAt(index, index - 1)
                                resequence()
                                expandedBlockIndex = index - 1
                            }
                        }
                        if index < blocks.count - 1 {
                            Button(tr("Move down", "Flytt ned"), systemImage: "arrow.down") {
                                blocks.swapAt(index, index + 1)
                                resequence()
                                expandedBlockIndex = index + 1
                            }
                        }
                        Button(role: .destructive) {
                            blocks.remove(at: index)
                            resequence()
                            expandedBlockIndex = nil
                        } label: {
                            Label(tr("Remove", "Fjern"), systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 36)
                            .contentShape(Rectangle())
                    }
                }

                if isExpanded {
                    Divider()
                    blockDetails(index)
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.87),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    @ViewBuilder
    private func blockDetails(_ index: Int) -> some View {
        let block = blocks[index]
            switch block.kind {
            case .run:
                TextField(ATHLTHLocalization.choose(english: "Activity (jogging, strides, drills)",
                                                       norwegian: "Aktivitet (jogg, stigningsløp, drill)"),
                          text: Binding(
                            get: { blocks[index].title },
                            set: { blocks[index].title = $0 }
                          ))
                    .font(.subheadline)
                Picker(ATHLTHLocalization.choose(english: "Goal", norwegian: "Mål"),
                       selection: Binding<Bool>(
                          get: { blocks[index].durationSeconds != nil },
                          set: { timed in
                              blocks[index].durationSeconds = timed ? 600 : nil
                              blocks[index].distanceMeters = timed ? nil : 1_000
                          })) {
                    Text(ATHLTHLocalization.choose(english: "Distance", norwegian: "Distanse")).tag(false)
                    Text(ATHLTHLocalization.choose(english: "Time", norwegian: "Tid")).tag(true)
                }
                .pickerStyle(.segmented)
                if blocks[index].durationSeconds != nil {
                    Stepper(value: durationBinding(index), in: 15...7200, step: 15) {
                        Text("\(Int(blocks[index].durationSeconds ?? 600)) s")
                    }
                } else {
                    Stepper(value: distanceBinding(index), in: 100...20000, step: 100) {
                        Text("\(Int(blocks[index].distanceMeters ?? 1000)) m")
                    }
                }
                Toggle(ATHLTHLocalization.choose(english: "Target pace", norwegian: "Måltempo"),
                       isOn: Binding(
                          get: { blocks[index].targetPaceSecondsPerKilometer != nil },
                          set: { blocks[index].targetPaceSecondsPerKilometer = $0 ? 330 : nil }
                       ))
                if blocks[index].targetPaceSecondsPerKilometer != nil {
                    Stepper(value: Binding(
                              get: { blocks[index].targetPaceSecondsPerKilometer ?? 330 },
                              set: { blocks[index].targetPaceSecondsPerKilometer = $0 }),
                            in: 150...1200, step: 5) {
                        let pace = Int(blocks[index].targetPaceSecondsPerKilometer ?? 330)
                        Text(String(format: "%d:%02d/km", pace / 60, pace % 60))
                    }
                }
                Picker(ATHLTHLocalization.choose(english: "Target pulse zone", norwegian: "Pulssone"),
                       selection: Binding<Int>(
                         get: { blocks[index].targetHeartRateZone ?? 0 },
                         set: { blocks[index].targetHeartRateZone = $0 == 0 ? nil : $0 }
                       )) {
                    Text(ATHLTHLocalization.choose(english: "No target", norwegian: "Ingen")).tag(0)
                    ForEach(1...5, id: \.self) { zone in
                        Text("\(zone)").tag(zone)
                    }
                }

            case .exercise:
                Stepper(
                    value: repetitionsBinding(index),
                    in: 1...300
                ) {
                    Text(tr("Target", "Mål") + " · \(blocks[index].repetitions ?? 10) " + tr("reps", "reps"))
                    .font(.caption)
                }

            case .rest:
                Stepper(
                    value: durationBinding(index),
                    in: 15...900,
                    step: 15
                ) {
                    Text(tr("Recovery", "Pause") + " · \(Int((blocks[index].durationSeconds ?? 60).rounded())) " + tr("sec", "sek"))
                    .font(.caption)
                }

            case .note:
                EmptyView()
            }
    }

    private var addBlockSection: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text(tr("ADD A BLOCK", "LEGG TIL BLOKK"))
                        .font(.caption2.weight(.bold))
                        .tracking(1.5)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    Spacer()
                    Menu {
                        ForEach(WorkoutPhaseKind.allCases) { phase in
                            Button {
                                selectedPhase = phase
                            } label: {
                                Label(phase.title, systemImage: phase.symbol)
                            }
                        }
                    } label: {
                        Label(selectedPhase.title, systemImage: selectedPhase.symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                    }
                }

                Button {
                    showingExercisePicker = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "dumbbell.fill")
                            .font(.title3)
                            .frame(width: 30)
                        Text(tr("Add exercise from library",
                                "Legg til øvelse fra biblioteket"))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 54)
                    .background(ATHLTHTheme.accentDeep,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)

                HStack(spacing: 10) {
                    blockAddButton(tr("Running", "Løping"), icon: "figure.run") {
                        addRunBlock()
                    }
                    blockAddButton(tr("Rest", "Pause"), icon: "pause.fill") {
                        addRestBlock()
                    }
                }
            }
        }
    }

    private var routeSection: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(tr("Route", "Rute"), systemImage: "map")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Picker(tr("Route", "Rute"), selection: $selectedRouteID) {
                        Text(tr("No route", "Ingen rute")).tag(nil as UUID?)
                        ForEach(session.savedRoutes) { route in
                            Text(route.title).tag(route.id as UUID?)
                        }
                    }
                    .labelsHidden()
                }
                Text(tr("Optional route for the running parts of this workout.",
                        "Valgfri rute for løpedelene av treningsøkten."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var saveBar: some View {
        Button {
            saveWorkout()
        } label: {
            Label(tr("Save Workout", "Lagre treningsøkt"),
                  systemImage: "checkmark.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
        }
        .buttonStyle(.borderedProminent)
        .tint(ATHLTHTheme.accentDeep)
        .disabled(!canSave)
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.regularMaterial)
    }

    private func blockAddButton(
        _ label: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                Text(label)
                Spacer(minLength: 0)
                Image(systemName: "plus")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ATHLTHTheme.accentDeep)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(height: 51)
            .background(ATHLTHTheme.accentSoft.opacity(0.72),
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func addRunBlock() {
        blocks.append(
            WorkoutTemplateBlock(
                sequence: blocks.count + 1,
                kind: .run,
                title: tr("Running", "Løping"),
                exerciseSlug: nil,
                distanceMeters: 1_000,
                repetitions: nil,
                durationSeconds: nil,
                targetWeightKilograms: nil,
                loadNote: nil,
                notes: nil,
                phase: selectedPhase
            )
        )
        expandedBlockIndex = blocks.count - 1
    }

    private func addRestBlock() {
        blocks.append(
            WorkoutTemplateBlock(
                sequence: blocks.count + 1,
                kind: .rest,
                title: tr("Rest", "Pause"),
                exerciseSlug: nil,
                distanceMeters: nil,
                repetitions: nil,
                durationSeconds: 60,
                targetWeightKilograms: nil,
                loadNote: nil,
                notes: nil,
                phase: .recovery
            )
        )
        expandedBlockIndex = blocks.count - 1
    }

    private func addExerciseBlock(_ entry: ExerciseLibraryEntry) {
        blocks.append(
            WorkoutTemplateBlock(
                sequence: blocks.count + 1,
                kind: .exercise,
                title: entry.name,
                exerciseSlug: entry.sourceIdentifier,
                distanceMeters: nil,
                repetitions: 10,
                durationSeconds: nil,
                targetWeightKilograms: nil,
                loadNote: nil,
                notes: nil,
                phase: selectedPhase
            )
        )
        expandedBlockIndex = blocks.count - 1
    }

    private func resequence() {
        blocks = blocks.enumerated().map { index, block in
            WorkoutTemplateBlock(
                sequence: index + 1,
                kind: block.kind,
                title: block.title,
                exerciseSlug: block.exerciseSlug,
                distanceMeters: block.distanceMeters,
                repetitions: block.repetitions,
                durationSeconds: block.durationSeconds,
                targetWeightKilograms: block.targetWeightKilograms,
                loadNote: block.loadNote,
                notes: block.notes,
                phase: block.phase,
                targetPaceSecondsPerKilometer: block.targetPaceSecondsPerKilometer,
                targetHeartRateZone: block.targetHeartRateZone
            )
        }
    }

    private func saveWorkout() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSave else { return }

        var workout = PlannedSession(
            id: UUID(),
            title: cleanTitle,
            kind: resolvedWorkoutKind,
            scheduledStart: nil,
            durationMinutes: knownDurationMinutes,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: hasRunning ? selectedRouteID : nil,
            exercises: [],
            notes: nil
        )
        workout.workoutBlocks = blocks
        workout.workoutCategory = category
        session.saveSharedWorkout(workout)
        dismiss()
    }

    private var resolvedWorkoutKind: WorkoutKind {
        switch category {
        case "running": return .running
        case "strength": return .strength
        default: return .custom
        }
    }

    private func distanceBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: { blocks[index].distanceMeters ?? 1_000 },
            set: { blocks[index].distanceMeters = $0 }
        )
    }

    private func repetitionsBinding(_ index: Int) -> Binding<Int> {
        Binding(
            get: { blocks[index].repetitions ?? 10 },
            set: { blocks[index].repetitions = $0 }
        )
    }

    private func durationBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: { blocks[index].durationSeconds ?? 60 },
            set: { blocks[index].durationSeconds = $0 }
        )
    }
}

struct SavedWorkoutPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore

    let onSelect: (PlannedSession) -> Void

    var body: some View {
        NavigationStack {
            List {
                if session.savedWorkoutTemplates.isEmpty {
                    ContentUnavailableView(
                        "No saved workouts",
                        systemImage: "rectangle.stack",
                        description: Text(
                            "Save or create a workout in Library first."
                        )
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(
                        session.savedWorkoutTemplates
                    ) { workout in
                        Button {
                            onSelect(workout)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(
                                    systemName:
                                        workout.isStructuredWorkout
                                            ? "rectangle.stack.fill"
                                            : workout.kind.systemImage
                                )
                                .foregroundStyle(
                                    ATHLTHTheme.accent
                                )
                                .frame(width: 34, height: 34)
                                .background(
                                    ATHLTHTheme.accentSoft,
                                    in: RoundedRectangle(
                                        cornerRadius: 10,
                                        style: .continuous
                                    )
                                )

                                VStack(
                                    alignment: .leading,
                                    spacing: 3
                                ) {
                                    Text(workout.title)
                                        .font(
                                            .subheadline
                                                .weight(.semibold)
                                        )
                                        .foregroundStyle(
                                            ATHLTHTheme.primaryText
                                        )

                                    Text(
                                        workout.isStructuredWorkout
                                            ? "\(workout.resolvedWorkoutBlocks.count) blocks · \(workout.workoutCategory?.capitalized ?? "Workout")"
                                            : workout.kind.title
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(
                                    systemName: "chevron.right"
                                )
                                .font(.caption.bold())
                                .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("My Workouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .cancellationAction
                ) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}



struct PlanWorkoutPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore

    @StateObject private var catalog =
        WorkoutTemplateCatalogStore()
    @State private var query = ""

    let onSelect: (PlannedSession) -> Void

    private var savedWorkouts: [PlannedSession] {
        let clean =
            query.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !clean.isEmpty else {
            return session.savedWorkoutTemplates
        }

        return session.savedWorkoutTemplates.filter {
            $0.title.localizedCaseInsensitiveContains(
                clean
            ) ||
            ($0.notes ?? "")
                .localizedCaseInsensitiveContains(
                    clean
                )
        }
    }

    private var catalogWorkouts:
        [WorkoutTemplateCatalogEntry] {
        let clean =
            query.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !clean.isEmpty else {
            return catalog.entries
        }

        return catalog.entries.filter {
            $0.title.localizedCaseInsensitiveContains(
                clean
            ) ||
            $0.summary
                .localizedCaseInsensitiveContains(
                    clean
                ) ||
            $0.tags
                .joined(separator: " ")
                .localizedCaseInsensitiveContains(
                    clean
                )
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !savedWorkouts.isEmpty {
                    Section("My Workouts") {
                        ForEach(savedWorkouts) {
                            workout in
                            Button {
                                onSelect(workout)
                                dismiss()
                            } label: {
                                workoutRow(
                                    title: workout.title,
                                    subtitle:
                                        savedWorkoutSubtitle(
                                            workout
                                        ),
                                    icon:
                                        workout.kind
                                            .systemImage
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !catalogWorkouts.isEmpty {
                    Section("Workout Library") {
                        ForEach(catalogWorkouts) {
                            entry in
                            Button {
                                onSelect(
                                    entry
                                        .plannedSession()
                                )
                                dismiss()
                            } label: {
                                workoutRow(
                                    title: entry.title,
                                    subtitle:
                                        catalogWorkoutSubtitle(
                                            entry
                                        ),
                                    icon:
                                        entry.systemImage
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if savedWorkouts.isEmpty &&
                    catalogWorkouts.isEmpty {
                    ContentUnavailableView(
                        "No workouts found",
                        systemImage:
                            "rectangle.stack",
                        description: Text(
                            "Try another search."
                        )
                    )
                    .listRowBackground(
                        Color.clear
                    )
                }
            }
            .navigationTitle("Choose Workout")
            .navigationBarTitleDisplayMode(
                .inline
            )
            .searchable(
                text: $query,
                prompt: "Search workouts"
            )
            .toolbar {
                ToolbarItem(
                    placement:
                        .cancellationAction
                ) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                await catalog.refresh()
            }
        }
    }

    private func workoutRow(
        title: String,
        subtitle: String,
        icon: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(
                    ATHLTHTheme.accent
                )
                .frame(
                    width: 36,
                    height: 36
                )
                .background(
                    ATHLTHTheme.accentSoft,
                    in: RoundedRectangle(
                        cornerRadius: 11,
                        style: .continuous
                    )
                )

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(title)
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )
            }

            Spacer()

            Image(
                systemName: "plus.circle.fill"
            )
            .foregroundStyle(
                ATHLTHTheme.accent
            )
        }
    }

    private func savedWorkoutSubtitle(
        _ workout: PlannedSession
    ) -> String {
        if !workout.exercises.isEmpty {
            let count =
                workout.exercises.count
            return count == 1
                ? "1 exercise · \(workout.kind.title)"
                : "\(count) exercises · \(workout.kind.title)"
        }

        let blocks =
            workout
                .resolvedWorkoutBlocks

        if !blocks.isEmpty {
            let exerciseCount =
                blocks.filter {
                    $0.kind == .exercise
                }.count

            if exerciseCount > 0 {
                return exerciseCount == 1
                    ? "1 exercise · Structured workout"
                    : "\(exerciseCount) exercises · Structured workout"
            }

            return "\(blocks.count) blocks · Structured workout"
        }

        return workout.kind.title
    }

    private func catalogWorkoutSubtitle(
        _ entry:
            WorkoutTemplateCatalogEntry
    ) -> String {
        let exerciseCount =
            entry.blocks.filter {
                $0.kind == .exercise
            }.count

        if exerciseCount > 0 {
            return exerciseCount == 1
                ? "1 exercise · \(entry.categoryTitle)"
                : "\(exerciseCount) exercises · \(entry.categoryTitle)"
        }

        return "\(entry.blocks.count) blocks · \(entry.categoryTitle)"
    }
}

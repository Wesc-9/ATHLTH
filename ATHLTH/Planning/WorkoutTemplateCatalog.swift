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

                Button {
                    session.saveSharedWorkout(
                        entry.plannedSession(),
                        sourceSessionID: entry.id
                    )
                    saved = true
                } label: {
                    Label(
                        saved
                            ? "Saved to My Workouts"
                            : "Save to My Workouts",
                        systemImage:
                            saved
                                ? "checkmark.circle.fill"
                                : "square.and.arrow.down"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.accentDeep)
                .disabled(saved)
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

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if session.savedWorkoutTemplates.isEmpty {
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
    @EnvironmentObject private var exerciseLibrary:
        ExerciseLibraryStore

    @State private var title = ""
    @State private var category = "hybrid"
    @State private var blocks: [WorkoutTemplateBlock] = []
    @State private var showingExercisePicker = false

    private var canSave: Bool {
        !title.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty &&
        !blocks.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ATHLTHCard {
                        Text("BUILD WORKOUT")
                            .font(.caption2.weight(.bold))
                            .tracking(1.8)
                            .foregroundStyle(
                                ATHLTHTheme.mutedText
                            )

                        TextField(
                            "Workout name",
                            text: $title
                        )
                        .font(.title3.weight(.semibold))
                        .padding(.top, 8)

                        Picker(
                            "Workout type",
                            selection: $category
                        ) {
                            Text("Hybrid")
                                .tag("hybrid")
                            Text("Running")
                                .tag("running")
                            Text("Strength")
                                .tag("strength")
                            Text("Custom")
                                .tag("custom")
                        }
                        .pickerStyle(.segmented)
                        .padding(.top, 12)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("BLOCKS")
                                .font(.caption2.weight(.bold))
                                .tracking(1.8)
                                .foregroundStyle(
                                    ATHLTHTheme.mutedText
                                )

                            Spacer()

                            Text("\(blocks.count)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        if blocks.isEmpty {
                            ATHLTHCard {
                                Text(
                                    "Build the workout in the order it should be performed. A block can be a run, an exercise or recovery."
                                )
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            }
                        } else {
                            ForEach(
                                Array(blocks.indices),
                                id: \.self
                            ) { index in
                                builderBlockRow(index)
                            }
                        }
                    }

                    ATHLTHCard {
                        Text("ADD BLOCK")
                            .font(.caption2.weight(.bold))
                            .tracking(1.5)
                            .foregroundStyle(
                                ATHLTHTheme.mutedText
                            )

                        HStack(spacing: 9) {
                            blockAddButton(
                                "Run",
                                icon: "figure.run"
                            ) {
                                addRunBlock()
                            }

                            blockAddButton(
                                "Exercise",
                                icon: "dumbbell.fill"
                            ) {
                                showingExercisePicker = true
                            }

                            blockAddButton(
                                "Rest",
                                icon: "pause.fill"
                            ) {
                                addRestBlock()
                            }
                        }
                        .padding(.top, 10)
                    }

                    Button {
                        saveWorkout()
                    } label: {
                        Label(
                            "Save Workout",
                            systemImage:
                                "checkmark.circle.fill"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accentDeep)
                    .disabled(!canSave)
                }
                .padding(18)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(
                ATHLTHPremiumCanvas(
                    accent: Color.teal.opacity(0.12)
                )
            )
            .navigationTitle("Create Workout")
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
            .sheet(
                isPresented: $showingExercisePicker
            ) {
                NavigationStack {
                    ExerciseLibraryView(
                        source: .library,
                        selectionTitle: "Add Exercise"
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

    private func builderBlockRow(
        _ index: Int
    ) -> some View {
        let block = blocks[index]

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("\(index + 1)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )
                    .frame(width: 28, height: 28)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: Circle()
                    )

                Image(systemName: block.kind.systemImage)
                    .foregroundStyle(
                        block.kind == .run
                            ? ATHLTHTheme.vitality
                            : ATHLTHTheme.accentDeep
                    )

                Text(block.title)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Button(role: .destructive) {
                    blocks.remove(at: index)
                    resequence()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }

            switch block.kind {
            case .run:
                Stepper(
                    value: distanceBinding(index),
                    in: 100...20_000,
                    step: 100
                ) {
                    Text(
                        "Distance · \(Int((blocks[index].distanceMeters ?? 1_000).rounded())) m"
                    )
                    .font(.caption)
                }

            case .exercise:
                Stepper(
                    value: repetitionsBinding(index),
                    in: 1...300
                ) {
                    Text(
                        "Target · \(blocks[index].repetitions ?? 10) reps"
                    )
                    .font(.caption)
                }

            case .rest:
                Stepper(
                    value: durationBinding(index),
                    in: 15...900,
                    step: 15
                ) {
                    Text(
                        "Recovery · \(Int((blocks[index].durationSeconds ?? 60).rounded())) sec"
                    )
                    .font(.caption)
                }

            case .note:
                EmptyView()
            }
        }
        .padding(13)
        .background(
            Color.white.opacity(0.80),
            in: RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
    }

    private func blockAddButton(
        _ title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(ATHLTHTheme.accentDeep)
            .frame(maxWidth: .infinity)
            .frame(height: 68)
            .background(
                ATHLTHTheme.accentSoft.opacity(0.72),
                in: RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
    }

    private func addRunBlock() {
        blocks.append(
            WorkoutTemplateBlock(
                sequence: blocks.count + 1,
                kind: .run,
                title: "Run",
                exerciseSlug: nil,
                distanceMeters: 1_000,
                repetitions: nil,
                durationSeconds: nil,
                targetWeightKilograms: nil,
                loadNote: nil,
                notes: nil
            )
        )
    }

    private func addRestBlock() {
        blocks.append(
            WorkoutTemplateBlock(
                sequence: blocks.count + 1,
                kind: .rest,
                title: "Recovery",
                exerciseSlug: nil,
                distanceMeters: nil,
                repetitions: nil,
                durationSeconds: 60,
                targetWeightKilograms: nil,
                loadNote: nil,
                notes: nil
            )
        )
    }

    private func addExerciseBlock(
        _ entry: ExerciseLibraryEntry
    ) {
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
                notes: nil
            )
        )
    }

    private func resequence() {
        blocks = blocks.enumerated().map {
            index, block in
            WorkoutTemplateBlock(
                sequence: index + 1,
                kind: block.kind,
                title: block.title,
                exerciseSlug: block.exerciseSlug,
                distanceMeters: block.distanceMeters,
                repetitions: block.repetitions,
                durationSeconds: block.durationSeconds,
                targetWeightKilograms:
                    block.targetWeightKilograms,
                loadNote: block.loadNote,
                notes: block.notes
            )
        }
    }

    private func saveWorkout() {
        let cleanTitle =
            title.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        var workout = PlannedSession(
            id: UUID(),
            title: cleanTitle,
            kind: resolvedWorkoutKind,
            scheduledStart: nil,
            durationMinutes: nil,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
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

    private func distanceBinding(
        _ index: Int
    ) -> Binding<Double> {
        Binding(
            get: {
                blocks[index].distanceMeters ?? 1_000
            },
            set: {
                blocks[index].distanceMeters = $0
            }
        )
    }

    private func repetitionsBinding(
        _ index: Int
    ) -> Binding<Int> {
        Binding(
            get: {
                blocks[index].repetitions ?? 10
            },
            set: {
                blocks[index].repetitions = $0
            }
        )
    }

    private func durationBinding(
        _ index: Int
    ) -> Binding<Double> {
        Binding(
            get: {
                blocks[index].durationSeconds ?? 60
            },
            set: {
                blocks[index].durationSeconds = $0
            }
        )
    }
}


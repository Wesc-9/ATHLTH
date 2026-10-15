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

enum WorkoutBlockGroupKind: String, Codable, Hashable {
    case superset
    case intervals

    var title: String {
        switch self {
        case .superset:
            return ATHLTHLocalization.choose(english: "Superset", norwegian: "Supersett")
        case .intervals:
            return ATHLTHLocalization.choose(english: "Intervals", norwegian: "Intervaller")
        }
    }

    var symbol: String {
        switch self {
        case .superset: return "dumbbell.fill"
        case .intervals: return "repeat"
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
    // Optional fields preserve compatibility with all existing saved workouts.
    var setCount: Int? = nil
    var restBetweenSetsSeconds: TimeInterval? = nil
    var groupID: UUID? = nil
    var groupKind: WorkoutBlockGroupKind? = nil
    var groupRounds: Int? = nil

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
        case setCount = "set_count"
        case restBetweenSetsSeconds = "rest_between_sets_seconds"
        case groupID = "group_id"
        case groupKind = "group_kind"
        case groupRounds = "group_rounds"
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

        if let setCount, setCount > 1, kind == .exercise {
            parts.append("\(setCount) sett")
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
           targetWeightKilograms >= 0 {
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

/// Converts a compact editor recipe to the actual ordered steps the structured
/// session player completes. Old recipes with no new metadata remain unchanged.
/// Rounds are expanded per group, whereas stand-alone exercises repeat by set.
/// Explicit rest blocks inside groups are respected; stand-alone sets insert
/// recovery only *between* sets, never after the final set.
extension Array where Element == WorkoutTemplateBlock {
    func expandedForExecution() -> [WorkoutTemplateBlock] {
        var output: [WorkoutTemplateBlock] = []
        var cursor = 0

        func append(_ source: WorkoutTemplateBlock, title: String? = nil) {
            guard output.count < 1000 else { return }
            let item = WorkoutTemplateBlock(
                sequence: output.count + 1,
                kind: source.kind,
                title: title ?? source.title,
                exerciseSlug: source.exerciseSlug,
                distanceMeters: source.distanceMeters,
                repetitions: source.repetitions,
                durationSeconds: source.durationSeconds,
                targetWeightKilograms: source.targetWeightKilograms,
                loadNote: source.loadNote,
                notes: source.notes,
                phase: source.phase,
                targetPaceSecondsPerKilometer: source.targetPaceSecondsPerKilometer,
                targetHeartRateZone: source.targetHeartRateZone
            )
            output.append(item)
        }

        while cursor < count && output.count < 1000 {
            let current = self[cursor]
            if let groupID = current.groupID, current.groupKind != nil {
                let start = cursor
                while cursor < count && self[cursor].groupID == groupID {
                    cursor += 1
                }
                let members = Array(self[start..<cursor])
                let rounds = Swift.min(Swift.max(current.groupRounds ?? 1, 1), 20)
                for round in 1...rounds {
                    for (position, member) in members.enumerated() {
                        // A recovery at the end of an interval group is a
                        // between-round break, not a mandatory final pause.
                        if round == rounds && position == members.count - 1
                            && member.kind == .rest && rounds > 1 {
                            continue
                        }
                        append(member, title: rounds > 1
                            ? "\(member.title) · \(round)/\(rounds)"
                            : member.title)
                    }
                }
            } else {
                cursor += 1
                let sets = current.kind == .exercise
                    ? Swift.min(Swift.max(current.setCount ?? 1, 1), 20) : 1
                for set in 1...sets {
                    append(current, title: sets > 1
                        ? "\(current.title) · \(set)/\(sets)"
                        : current.title)
                    if set < sets,
                       let rest = current.restBetweenSetsSeconds,
                       rest > 0 {
                        append(WorkoutTemplateBlock(
                            sequence: 0,
                            kind: .rest,
                            title: ATHLTHLocalization.choose(
                                english: "Between sets", norwegian: "Mellom sett"),
                            exerciseSlug: nil,
                            distanceMeters: nil,
                            repetitions: nil,
                            durationSeconds: rest,
                            targetWeightKilograms: nil,
                            loadNote: nil,
                            notes: nil,
                            phase: .recovery
                        ))
                    }
                }
            }
        }
        return output
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
    @State private var exerciseTargetGroupID: UUID?
    @State private var pendingNewGroupKind: WorkoutBlockGroupKind?
    @State private var collapsedGroupIDs: Set<UUID> = []
    @State private var showingDiscardConfirmation = false
    /// Present from advanced plan creation to edit a specific weekday
    /// without creating an unwanted shared workout template.
    private let onSaveToPlan: ((String, [WorkoutTemplateBlock], UUID?, Int?) -> Void)?

    init(
        initialTitle: String = "",
        initialBlocks: [WorkoutTemplateBlock] = [],
        initialRouteID: UUID? = nil,
        onSaveToPlan: ((String, [WorkoutTemplateBlock], UUID?, Int?) -> Void)? = nil
    ) {
        _title = State(initialValue: initialTitle)
        _blocks = State(initialValue: initialBlocks)
        _selectedRouteID = State(initialValue: initialRouteID)
        self.onSaveToPlan = onSaveToPlan
    }

    private let studioInk = Color(red: 0.08, green: 0.14, blue: 0.27)
    private let studioBlue = Color(red: 0.04, green: 0.43, blue: 0.98)
    private let studioBackground = Color(red: 0.958, green: 0.973, blue: 0.988)

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
        (hasRunning || hasStrength) && !hasIncompleteSuperset
    }

    private var hasIncompleteSuperset: Bool {
        let groups = Set(blocks.compactMap { block -> UUID? in
            block.groupKind == .superset ? block.groupID : nil
        })
        return groups.contains { id in
            blocks.filter { $0.groupID == id && $0.kind == .exercise }.count < 2
        }
    }

    private var timelineStarts: [Int] {
        blocks.indices.filter { index in
            guard index > 0, let id = blocks[index].groupID else { return true }
            return blocks[index - 1].groupID != id
        }
    }

    private func groupIndices(startingAt start: Int) -> [Int] {
        guard blocks.indices.contains(start), let id = blocks[start].groupID else {
            return [start]
        }
        var index = start
        while blocks.indices.contains(index), blocks[index].groupID == id {
            index += 1
        }
        return Array(start..<index)
    }

    private var knownDurationMinutes: Int? {
        guard !blocks.isEmpty else { return nil }
        var seconds = 0.0
        for block in blocks.expandedForExecution() {
            if let duration = block.durationSeconds, duration > 0 {
                seconds += duration
            } else if block.kind == .run,
                      let distance = block.distanceMeters,
                      let pace = block.targetPaceSecondsPerKilometer,
                      distance > 0, pace > 0 {
                seconds += distance / 1_000 * pace
            } else {
                // A repetition-based exercise or unpaced distance has no
                // reliable duration. Avoid displaying or saving a false total.
                return nil
            }
        }
        return Int(ceil(seconds / 60))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    workoutOverview
                    addBlockSection
                    timeline
                    if hasRunning {
                        routeSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 28)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(studioBackground.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                saveBar
            }
            .navigationTitle(onSaveToPlan == nil
                ? tr("Create Workout", "Lag treningsøkt")
                : tr("Build planned workout", "Bygg planlagt økt"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel", "Avbryt")) {
                        if !blocks.isEmpty || !title.isEmpty {
                            showingDiscardConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                }
            }
            .confirmationDialog(
                tr("Discard workout?", "Forkaste treningsøkten?"),
                isPresented: $showingDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button(tr("Discard", "Forkast"), role: .destructive) {
                    dismiss()
                }
                Button(tr("Keep editing", "Fortsett å redigere"), role: .cancel) {}
            } message: {
                Text(tr("Changes that haven't been saved will be lost.",
                        "Endringer som ikke er lagret, går tapt."))
            }
            .sheet(isPresented: $showingExercisePicker) {
                NavigationStack {
                    ExerciseLibraryView(
                        source: nil,
                        selectionTitle: tr("Add Exercise", "Legg til øvelse")
                    ) { entry in
                        addExerciseBlock(entry, toGroup: exerciseTargetGroupID)
                        showingExercisePicker = false
                    }
                }
            }
            .onChange(of: showingExercisePicker) { _, showing in
                if !showing {
                    exerciseTargetGroupID = nil
                    pendingNewGroupKind = nil
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
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Image("TreadmillRecentCardHero")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: 184)
                    .clipped()

                LinearGradient(
                    stops: [
                        .init(color: Color(red: 0.92, green: 0.96, blue: 1).opacity(0.99), location: 0),
                        .init(color: Color(red: 0.92, green: 0.96, blue: 1).opacity(0.96), location: 0.36),
                        .init(color: Color(red: 0.92, green: 0.96, blue: 1).opacity(0.36), location: 0.68),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                VStack(alignment: .leading, spacing: 11) {
                    Text("A T H L T H")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(studioInk.opacity(0.73))

                    TextField(
                        tr("Workout name (optional)", "Navn på økten (valgfritt)"),
                        text: $title
                    )
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(studioInk)
                    .tint(studioBlue)
                    .lineLimit(1)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityLabel(tr("Workout name", "Navn på treningsøkt"))

                    HStack(spacing: 6) {
                        metricPill(
                            "\(blocks.expandedForExecution().count) " + tr("steps", "steg"),
                            icon: "square.stack.3d.up"
                        )
                        if let knownDurationMinutes {
                            metricPill("\(knownDurationMinutes) min", icon: "clock")
                        }
                        metricPill(categoryTitle, icon: "chart.bar.fill")
                    }

                    Text(tr("Build your workout, step by step.",
                            "Bygg økten steg for steg."))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(studioInk.opacity(0.7))
                }
                .padding(.horizontal, 19)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(height: 184)
        .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .strokeBorder(.white.opacity(0.92), lineWidth: 1)
        }
        .shadow(color: studioInk.opacity(0.07), radius: 16, y: 8)
    }

    private func metricPill(_ value: String, icon: String) -> some View {
        Label(value, systemImage: icon)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(studioInk)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(.white.opacity(0.79), in: Capsule())
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center, spacing: 8) {
                Text(tr("WORKOUT", "TRENINGSØKT").uppercased() +
                     " (\(blocks.expandedForExecution().count) " +
                     tr("STEPS", "STEG") + ")")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.25)
                    .foregroundStyle(studioInk.opacity(0.8))

                Spacer(minLength: 0)

                if !blocks.isEmpty {
                    Label(tr("Drag to reorder", "Dra for å endre rekkefølge"),
                          systemImage: "arrow.up.arrow.down")
                        .font(.system(size: 10))
                        .foregroundStyle(studioInk.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .padding(.horizontal, 3)

            if blocks.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 27))
                        .foregroundStyle(studioBlue)
                    Text(tr("Your workout starts here",
                            "Treningsøkten din starter her"))
                        .font(.headline)
                    Text(tr("Choose an exercise, run, rest or group above.",
                            "Velg øvelse, løping, pause eller gruppe over."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        openExercisePicker()
                    } label: {
                        Label(tr("Add your first exercise", "Legg til første øvelse"),
                              systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(studioBlue)
                    .padding(.top, 7)
                }
                .frame(maxWidth: .infinity)
                .padding(22)
                .background(.white, in: RoundedRectangle(cornerRadius: 22))
            } else {
                VStack(spacing: 11) {
                    ForEach(Array(timelineStarts.enumerated()), id: \.element) { position, index in
                        HStack(alignment: .top, spacing: 10) {
                            timelineNumber(position + 1)
                                .frame(width: 34)
                            Group {
                                if blocks[index].groupID != nil {
                                    groupTimelineCard(startingAt: index)
                                } else {
                                    builderBlockRow(index, nested: false)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .dropDestination(for: String.self) { items, _ in
                                guard let source = items.first.flatMap(Int.init),
                                      source != index else { return false }
                                moveTimelineSection(from: source, to: index)
                                return true
                            }
                        }
                    }
                }
                .background(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(studioBlue.opacity(0.17))
                        .frame(width: 2)
                        .padding(.leading, 16)
                        .padding(.vertical, 22)
                }
            }
        }
    }

    private func timelineNumber(_ number: Int) -> some View {
        Text("\(number)")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(studioBlue)
            .frame(width: 33, height: 33)
            .background(Color(red: 0.87, green: 0.93, blue: 1.0), in: Circle())
            .overlay { Circle().strokeBorder(.white, lineWidth: 1.4) }
            .padding(.top, 8)
            .accessibilityLabel(tr("Section", "Del") + " \(number)")
    }

    private func groupTimelineCard(startingAt firstIndex: Int) -> some View {
        let first = blocks[firstIndex]
        let members = groupIndices(startingAt: firstIndex)
        let kind = first.groupKind ?? .intervals
        let id = first.groupID!
        let collapsed = collapsedGroupIDs.contains(id)
        let number = timelineStarts.filter {
            $0 <= firstIndex && blocks[$0].groupID != nil
        }.count
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let letter = String(letters[(max(number, 1) - 1) % letters.count])

        return VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 13))
                    .foregroundStyle(studioInk.opacity(0.36))
                    .frame(width: 20, height: 38)
                    .contentShape(Rectangle())
                    .draggable(String(firstIndex))
                    .accessibilityLabel(tr("Drag to reorder group",
                                           "Dra for å flytte gruppe"))

                Image(systemName: kind == .superset ? "dumbbell.fill" : "figure.run")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(studioBlue)
                    .frame(width: 40, height: 40)
                    .background(studioBlue.opacity(0.085),
                                in: RoundedRectangle(cornerRadius: 12))

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        if collapsed {
                            collapsedGroupIDs.remove(id)
                        } else {
                            collapsedGroupIDs.insert(id)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(tr("Group", "Gruppe") + " " + letter + " – " + kind.title)
                            .font(.system(size: 13, weight: .bold))
                            .lineLimit(2)
                            .foregroundStyle(studioInk)
                        Spacer(minLength: 0)
                        Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(studioInk.opacity(0.58))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Menu {
                    ForEach(1...20, id: \.self) { rounds in
                        Button("\(rounds) " + tr("rounds", "runder")) {
                            for index in blocks.indices where blocks[index].groupID == id {
                                blocks[index].groupRounds = rounds
                            }
                        }
                    }
                } label: {
                    Text("\(first.groupRounds ?? 3) " + tr("rounds", "runder"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(studioInk.opacity(0.82))
                        .lineLimit(1)
                        .padding(.horizontal, 9)
                        .frame(height: 25)
                        .background(studioBlue.opacity(0.075), in: Capsule())
                }

                Menu {
                    if let pos = timelineStarts.firstIndex(of: firstIndex), pos > 0 {
                        Button(tr("Move group up", "Flytt gruppe opp"),
                               systemImage: "arrow.up") {
                            moveTimelineSection(startingAt: firstIndex, direction: -1)
                        }
                    }
                    if let pos = timelineStarts.firstIndex(of: firstIndex),
                       pos < timelineStarts.count - 1 {
                        Button(tr("Move group down", "Flytt gruppe ned"),
                               systemImage: "arrow.down") {
                            moveTimelineSection(startingAt: firstIndex, direction: 1)
                        }
                    }
                    Button(tr("Ungroup", "Løs opp gruppe"),
                           systemImage: "square.stack.3d.up") {
                        for index in members {
                            blocks[index].groupID = nil
                            blocks[index].groupKind = nil
                            blocks[index].groupRounds = nil
                        }
                        collapsedGroupIDs.remove(id)
                    }
                    Button(role: .destructive) {
                        blocks.removeAll { $0.groupID == id }
                        resequence()
                        collapsedGroupIDs.remove(id)
                        expandedBlockIndex = nil
                    } label: {
                        Label(tr("Delete group", "Slett gruppe"),
                              systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(studioInk.opacity(0.64))
                        .frame(width: 24, height: 36)
                }
            }

            if !collapsed {
                VStack(spacing: 0) {
                    ForEach(members, id: \.self) { index in
                        builderBlockRow(index, nested: true)
                        if index != members.last {
                            Divider()
                                .padding(.leading, 57)
                        }
                    }
                }

                if kind == .superset && members.filter({ blocks[$0].kind == .exercise }).count < 2 {
                    Label(tr("Add at least two exercises before saving.",
                             "Legg til minst to øvelser før lagring."),
                          systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Menu {
                    Button(tr("Exercise", "Øvelse"), systemImage: "dumbbell.fill") {
                        openExercisePicker(for: id)
                    }
                    if kind == .intervals {
                        Button(tr("Running", "Løping"), systemImage: "figure.run") {
                            addRunBlock(toGroup: id)
                        }
                    }
                    Button(tr("Rest", "Pause"), systemImage: "pause.fill") {
                        addRestBlock(toGroup: id)
                    }
                } label: {
                    Label(tr("Add to group", "Legg til i gruppen"),
                          systemImage: "plus.circle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(studioBlue)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(studioBlue.opacity(0.065),
                                    in: RoundedRectangle(cornerRadius: 11))
                }
            }
        }
        .padding(11)
        .background(.white,
                    in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .strokeBorder(studioInk.opacity(0.045), lineWidth: 0.8)
        }
        .shadow(color: studioInk.opacity(0.055), radius: 13, y: 5)
    }

    private func builderBlockRow(_ index: Int, nested: Bool = false) -> some View {
        let block = blocks[index]
        let isExpanded = expandedBlockIndex == index

        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: nested ? 7 : 9) {
                if !nested {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 13))
                        .foregroundStyle(studioInk.opacity(0.34))
                        .frame(width: 18, height: 46)
                        .contentShape(Rectangle())
                        .draggable(String(index))
                        .accessibilityLabel(tr("Drag to reorder", "Dra for å flytte blokk"))
                }

                blockArtwork(block, size: nested ? 49 : 52)

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        expandedBlockIndex = isExpanded ? nil : index
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localizedBlockTitle(block))
                            .font(.system(size: nested ? 13 : 14, weight: .semibold))
                            .foregroundStyle(studioInk)
                            .lineLimit(2)

                        if let summary = block.targetText {
                            Text(summary)
                                .font(.system(size: 11))
                                .foregroundStyle(studioInk.opacity(0.62))
                                .lineLimit(2)
                        } else if block.kind == .exercise {
                            Text(tr("Adjust reps and load", "Juster reps og belastning"))
                                .font(.system(size: 11))
                                .foregroundStyle(studioInk.opacity(0.55))
                        } else {
                            Text(block.resolvedPhase.title)
                                .font(.system(size: 11))
                                .foregroundStyle(studioInk.opacity(0.55))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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

                    if index > 0 &&
                       (block.groupID == nil || blocks[index - 1].groupID == block.groupID) {
                        Button(tr("Move up", "Flytt opp"), systemImage: "arrow.up") {
                            if block.groupID == nil {
                                moveTimelineSection(startingAt: index, direction: -1)
                            } else {
                                blocks.swapAt(index, index - 1)
                                resequence()
                                expandedBlockIndex = index - 1
                            }
                        }
                    }

                    if index < blocks.count - 1 &&
                       (block.groupID == nil || blocks[index + 1].groupID == block.groupID) {
                        Button(tr("Move down", "Flytt ned"), systemImage: "arrow.down") {
                            if block.groupID == nil {
                                moveTimelineSection(startingAt: index, direction: 1)
                            } else {
                                blocks.swapAt(index, index + 1)
                                resequence()
                                expandedBlockIndex = index + 1
                            }
                        }
                    }

                    Button(role: .destructive) {
                        let removedGroup = blocks[index].groupID
                        blocks.remove(at: index)
                        if let removedGroup,
                           blocks.filter({ $0.groupID == removedGroup }).count < 2 {
                            for i in blocks.indices where blocks[i].groupID == removedGroup {
                                blocks[i].groupID = nil
                                blocks[i].groupKind = nil
                                blocks[i].groupRounds = nil
                            }
                        }
                        resequence()
                        expandedBlockIndex = nil
                    } label: {
                        Label(tr("Remove", "Fjern"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(studioInk.opacity(0.65))
                        .frame(width: 24, height: 38)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        expandedBlockIndex = isExpanded ? nil : index
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(studioInk.opacity(0.58))
                        .frame(width: 18, height: 38)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                Divider()
                blockDetails(index)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
            }
        }
        .padding(nested ? 5 : 11)
        .background {
            if !nested {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.white)
            }
        }
        .overlay {
            if !nested {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(studioInk.opacity(0.04), lineWidth: 0.8)
            }
        }
        .shadow(color: studioInk.opacity(nested ? 0 : 0.05),
                radius: 12, y: 5)
    }

    private func localizedBlockTitle(_ block: WorkoutTemplateBlock) -> String {
        guard block.kind == .exercise else { return block.title }
        if let entry = exerciseLibrary.allExercises.first(where: { entry in
            (block.exerciseSlug != nil && entry.sourceIdentifier == block.exerciseSlug)
                || entry.name.localizedCaseInsensitiveCompare(block.title) == .orderedSame
        }) {
            return exerciseLibrary.localizedExerciseName(entry)
        }
        return ATHLTHLocalization.isNorwegian
            ? ATHLTHExerciseNameLocalization.norwegianName(for: block.title)
            : block.title
    }

    @ViewBuilder
    private func blockArtwork(_ block: WorkoutTemplateBlock, size: CGFloat) -> some View {
        if block.kind == .exercise,
           let match = exerciseLibrary.allExercises.first(where: { entry in
               (block.exerciseSlug != nil && entry.sourceIdentifier == block.exerciseSlug)
                   || entry.name.localizedCaseInsensitiveCompare(block.title) == .orderedSame
           }) {
            ExerciseArtwork(entry: match, size: size)
        } else if block.kind == .run,
                  (block.title.localizedCaseInsensitiveContains("mølle") ||
                   block.title.localizedCaseInsensitiveContains("treadmill")) {
            Image("TreadmillRecentCardHero")
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 11))
        } else {
            let icon = block.kind == .run
                ? (block.resolvedPhase == .cooldown ? "figure.walk" : "figure.run")
                : block.kind.systemImage
            Image(systemName: icon)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(studioInk.opacity(0.82))
                .frame(width: size, height: size)
                .background(studioBackground,
                            in: RoundedRectangle(cornerRadius: 11))
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
                if block.groupID == nil {
                    Stepper(value: Binding(
                        get: { blocks[index].setCount ?? 1 },
                        set: { blocks[index].setCount = $0 }
                    ), in: 1...20) {
                        Text("\(blocks[index].setCount ?? 1) " + tr("sets", "sett"))
                            .font(.subheadline.weight(.semibold))
                    }

                    if (blocks[index].setCount ?? 1) > 1 {
                        Stepper(value: Binding(
                            get: { blocks[index].restBetweenSetsSeconds ?? 90 },
                            set: { blocks[index].restBetweenSetsSeconds = $0 }
                        ), in: 0...600, step: 15) {
                            Text(tr("Rest between sets", "Pause mellom sett") +
                                 " · \(Int(blocks[index].restBetweenSetsSeconds ?? 90)) " +
                                 tr("sec", "sek"))
                                .font(.caption)
                        }
                    }
                }
                Stepper(value: Binding(
                    get: { blocks[index].targetWeightKilograms ?? 0 },
                    set: { blocks[index].targetWeightKilograms = $0 }
                ), in: 0...500, step: 2.5) {
                    Text(String(format: "%.1f kg",
                        blocks[index].targetWeightKilograms ?? 0))
                        .font(.caption)
                }

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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(tr("BLOCK LIBRARY", "BLOKKBIBLIOTEK"))
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(studioInk.opacity(0.74))
                Spacer()
                Text(tr("Add blocks to your workout.",
                        "Legg til blokker i økten din."))
                    .font(.system(size: 10))
                    .foregroundStyle(studioInk.opacity(0.55))
            }

            HStack(spacing: 9) {
                Button {
                    openExercisePicker()
                } label: {
                    studioLibraryTile(tr("Exercise", "Øvelse"), icon: "dumbbell.fill",
                                      color: Color(red: 0.12, green: 0.48, blue: 0.98))
                }
                .buttonStyle(.plain)

                Button {
                    addRunBlock()
                } label: {
                    studioLibraryTile(tr("Running", "Løping"), icon: "figure.run",
                                      color: Color(red: 0.04, green: 0.48, blue: 0.47))
                }
                .buttonStyle(.plain)

                Button {
                    addRestBlock()
                } label: {
                    studioLibraryTile(tr("Rest", "Pause"), icon: "pause.fill",
                                      color: Color(red: 0.73, green: 0.38, blue: 0.29))
                }
                .buttonStyle(.plain)

                Menu {
                    Button {
                        createSuperset()
                    } label: {
                        Label(tr("Superset", "Supersett"), systemImage: "dumbbell.fill")
                    }
                    Button {
                        createIntervals()
                    } label: {
                        Label(tr("Intervals", "Intervaller"), systemImage: "repeat")
                    }
                } label: {
                    studioLibraryTile(tr("Groups", "Grupper"), icon: "square.on.square",
                                      color: Color(red: 0.45, green: 0.27, blue: 0.91))
                }
            }
        }
        .padding(14)
        .background(.white.opacity(0.96),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white, lineWidth: 1)
        }
        .shadow(color: studioInk.opacity(0.045), radius: 14, y: 6)
    }

    private func studioLibraryTile(_ title: String, icon: String, color: Color) -> some View {
        VStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 21, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity)
        .frame(height: 87)
        .background(color.opacity(0.105),
                    in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 17))
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
        HStack(spacing: 10) {
            Menu {
                Button(tr("Exercise", "Øvelse"), systemImage: "dumbbell.fill") {
                    openExercisePicker()
                }
                Button(tr("Running", "Løping"), systemImage: "figure.run") {
                    addRunBlock()
                }
                Button(tr("Rest", "Pause"), systemImage: "pause.fill") {
                    addRestBlock()
                }
                Button(tr("Superset", "Supersett"), systemImage: "dumbbell.fill") {
                    createSuperset()
                }
                Button(tr("Intervals", "Intervaller"), systemImage: "repeat") {
                    createIntervals()
                }
            } label: {
                Label(tr("Add block", "Legg til blokk"), systemImage: "plus.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(studioInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(.white, in: Capsule())
                    .overlay { Capsule().strokeBorder(studioInk.opacity(0.12)) }
            }

            Button {
                saveWorkout()
            } label: {
                Label(tr("Save workout", "Lagre treningsøkt"),
                      systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(studioBlue, in: Capsule())
                    .opacity(canSave ? 1 : 0.48)
            }
            .disabled(!canSave)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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

    private func openExercisePicker(for groupID: UUID? = nil) {
        exerciseTargetGroupID = groupID
        pendingNewGroupKind = nil
        showingExercisePicker = true
    }

    private func createSuperset() {
        exerciseTargetGroupID = UUID()
        pendingNewGroupKind = .superset
        showingExercisePicker = true
    }

    private func createIntervals() {
        let id = UUID()
        var run = WorkoutTemplateBlock(
            sequence: 0, kind: .run,
            title: tr("Run interval", "Løpeintervall"),
            exerciseSlug: nil, distanceMeters: nil,
            repetitions: nil, durationSeconds: 120,
            targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: .main
        )
        run.groupID = id
        run.groupKind = .intervals
        run.groupRounds = 4
        insertBlock(run, toGroup: nil)

        var rest = WorkoutTemplateBlock(
            sequence: 0, kind: .rest,
            title: tr("Recovery", "Pause"),
            exerciseSlug: nil, distanceMeters: nil,
            repetitions: nil, durationSeconds: 60,
            targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: .recovery
        )
        rest.groupID = id
        rest.groupKind = .intervals
        rest.groupRounds = 4
        insertBlock(rest, toGroup: id)
    }

    private func insertBlock(_ source: WorkoutTemplateBlock, toGroup groupID: UUID?) {
        var block = source
        if let id = groupID,
           let first = blocks.first(where: { $0.groupID == id }) {
            block.groupID = id
            block.groupKind = first.groupKind
            block.groupRounds = first.groupRounds
            block.setCount = nil
            block.restBetweenSetsSeconds = nil
        }
        if let id = groupID,
           let last = blocks.indices.last(where: { blocks[$0].groupID == id }) {
            blocks.insert(block, at: last + 1)
            expandedBlockIndex = last + 1
        } else {
            blocks.append(block)
            expandedBlockIndex = blocks.count - 1
        }
        resequence()
    }

    private func addRunBlock(toGroup groupID: UUID? = nil) {
        insertBlock(WorkoutTemplateBlock(
            sequence: 0, kind: .run,
            title: tr("Running", "Løping"),
            exerciseSlug: nil, distanceMeters: 1_000,
            repetitions: nil, durationSeconds: nil,
            targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: selectedPhase
        ), toGroup: groupID)
    }

    private func addRestBlock(toGroup groupID: UUID? = nil) {
        insertBlock(WorkoutTemplateBlock(
            sequence: 0, kind: .rest,
            title: tr("Rest", "Pause"),
            exerciseSlug: nil, distanceMeters: nil,
            repetitions: nil, durationSeconds: 60,
            targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: .recovery
        ), toGroup: groupID)
    }

    private func addExerciseBlock(_ entry: ExerciseLibraryEntry, toGroup groupID: UUID? = nil) {
        var block = WorkoutTemplateBlock(
            sequence: 0, kind: .exercise,
            title: entry.name,
            exerciseSlug: entry.sourceIdentifier,
            distanceMeters: nil, repetitions: 10,
            durationSeconds: nil, targetWeightKilograms: nil,
            loadNote: nil, notes: nil, phase: selectedPhase
        )
        if let groupID, let pendingNewGroupKind,
           !blocks.contains(where: { $0.groupID == groupID }) {
            block.groupID = groupID
            block.groupKind = pendingNewGroupKind
            block.groupRounds = 3
        } else if groupID == nil {
            block.setCount = 3
            block.restBetweenSetsSeconds = 90
        }
        insertBlock(block, toGroup: groupID)
    }

    private func moveTimelineSection(from source: Int, to destination: Int) {
        let starts = timelineStarts
        guard let sourcePosition = starts.firstIndex(of: source),
              let targetPosition = starts.firstIndex(of: destination),
              sourcePosition != targetPosition else { return }

        var sections = starts.map { start in
            groupIndices(startingAt: start).map { blocks[$0] }
        }
        let moving = sections.remove(at: sourcePosition)
        sections.insert(moving, at: targetPosition)
        blocks = sections.flatMap { $0 }
        resequence()
        expandedBlockIndex = nil
    }

    private func moveTimelineSection(startingAt index: Int, direction: Int) {
        let starts = timelineStarts
        guard let position = starts.firstIndex(of: index),
              starts.indices.contains(position + direction) else { return }
        var sections = starts.map { first in
            groupIndices(startingAt: first).map { blocks[$0] }
        }
        sections.swapAt(position, position + direction)
        blocks = sections.flatMap { $0 }
        resequence()
        expandedBlockIndex = nil
    }

    private func resequence() {
        blocks = blocks.enumerated().map { index, block in
            var copy = WorkoutTemplateBlock(
                sequence: index + 1,
                kind: block.kind, title: block.title,
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
            copy.setCount = block.setCount
            copy.restBetweenSetsSeconds = block.restBetweenSetsSeconds
            copy.groupID = block.groupID
            copy.groupKind = block.groupKind
            copy.groupRounds = block.groupRounds
            return copy
        }
    }

    private func saveWorkout() {
        guard canSave else { return }
        let requestedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTitle = requestedTitle.isEmpty ? resolvedWorkoutKind.title : requestedTitle

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
        if let onSaveToPlan {
            onSaveToPlan(cleanTitle, blocks, hasRunning ? selectedRouteID : nil, knownDurationMinutes)
        } else {
            session.saveSharedWorkout(workout)
        }
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

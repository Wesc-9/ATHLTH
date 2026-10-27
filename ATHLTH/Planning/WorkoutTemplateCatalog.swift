import Foundation
import Supabase
import SwiftUI
import UniformTypeIdentifiers

/// Movement identity is stored separately from the existing run timeline
/// kind so old planned workouts and their playback remain compatible.
enum WorkoutCardioActivity: String, Codable, Hashable {
    case running
    case walking

    var title: String {
        switch self {
        case .running: return ATHLTHLocalization.choose(english: "Run", norwegian: "Løp")
        case .walking: return ATHLTHLocalization.choose(english: "Walk", norwegian: "Gå")
        }
    }
}

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

/// Timed recovery and mobility activities reuse the existing non-strength
/// timeline block kind. This avoids misclassifying meditation as strength.
enum WorkoutWellnessKind: String, Codable, CaseIterable {
    case meditation, stretching, mobility, yoga

    var title: String {
        switch self {
        case .meditation: return ATHLTHLocalization.choose(english: "Meditation", norwegian: "Meditasjon")
        case .stretching: return ATHLTHLocalization.choose(english: "Stretching", norwegian: "Uttøying")
        case .mobility: return ATHLTHLocalization.choose(english: "Mobility", norwegian: "Mobilitet")
        case .yoga: return "Yoga"
        }
    }

    var symbol: String {
        switch self {
        case .meditation: return "sparkles"
        case .stretching: return "figure.flexibility"
        case .mobility: return "figure.cooldown"
        case .yoga: return "figure.yoga"
        }
    }

    var workoutKind: WorkoutKind {
        self == .meditation ? .recovery : .mobility
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
    /// Original intensity target from Zoned (which uses six heart-rate zones).
    /// This displays normalized ATHLTH Z1-Z5 ranges; original source is in JSON.
    var sourceIntensityZoneLabel: String? = nil
    var targetHeartRatePercentMin: Double? = nil
    var targetHeartRatePercentMax: Double? = nil
    /// Athlete-selected perceived intensity (RPE 1...10). Never a measured
    /// physiological reading; optional so historic templates still decode.
    var targetEffortRPE: Int? = nil
    /// Planned treadmill gradient in percent: never treated as measured data.
    var treadmillInclinePercent: Double? = nil
    // Optional fields preserve compatibility with all existing saved workouts.
    var setCount: Int? = nil
    var restBetweenSetsSeconds: TimeInterval? = nil
    var groupID: UUID? = nil
    var groupKind: WorkoutBlockGroupKind? = nil
    var groupRounds: Int? = nil
    /// Nil is an old running block. New walk blocks keep their real identity.
    var cardioActivity: WorkoutCardioActivity? = nil
    /// Nil remains outdoors for backward compatibility.
    var isIndoor: Bool? = nil
    /// Author-approved metadata can travel with a shared workout/plan.
    var exerciseSnapshot: ExerciseSnapshot? = nil
    /// Exact identifier for personal exercises; never infer two owners'
    /// exercises are equivalent merely from their displayed names.
    var exerciseID: UUID? = nil
    /// Optional, so historic note blocks continue decoding unchanged.
    var wellnessKind: WorkoutWellnessKind? = nil
    /// Non-running timed activities remain distinct from running metrics.
    var activityTag: String? = nil
    /// Ephemeral, stable identity for live drag ordering. Never persisted:
    /// old workout recipes decode unchanged and get fresh editor IDs.
    var editorDragID: UUID = UUID()

    // The drag token is an editor-only visual identity. It must not affect
    // recipe equality, hashing, undo, persisted plans or Codable round trips.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.sequence == rhs.sequence &&
        lhs.kind == rhs.kind &&
        lhs.title == rhs.title &&
        lhs.exerciseSlug == rhs.exerciseSlug &&
        lhs.distanceMeters == rhs.distanceMeters &&
        lhs.repetitions == rhs.repetitions &&
        lhs.durationSeconds == rhs.durationSeconds &&
        lhs.targetWeightKilograms == rhs.targetWeightKilograms &&
        lhs.loadNote == rhs.loadNote &&
        lhs.notes == rhs.notes &&
        lhs.phase == rhs.phase &&
        lhs.targetPaceSecondsPerKilometer == rhs.targetPaceSecondsPerKilometer &&
        lhs.targetHeartRateZone == rhs.targetHeartRateZone &&
        lhs.sourceIntensityZoneLabel == rhs.sourceIntensityZoneLabel &&
        lhs.targetHeartRatePercentMin == rhs.targetHeartRatePercentMin &&
        lhs.targetHeartRatePercentMax == rhs.targetHeartRatePercentMax &&
        lhs.targetEffortRPE == rhs.targetEffortRPE &&
        lhs.treadmillInclinePercent == rhs.treadmillInclinePercent &&
        lhs.setCount == rhs.setCount &&
        lhs.restBetweenSetsSeconds == rhs.restBetweenSetsSeconds &&
        lhs.groupID == rhs.groupID &&
        lhs.groupKind == rhs.groupKind &&
        lhs.groupRounds == rhs.groupRounds &&
        lhs.cardioActivity == rhs.cardioActivity &&
        lhs.isIndoor == rhs.isIndoor &&
        lhs.exerciseSnapshot == rhs.exerciseSnapshot &&
        lhs.exerciseID == rhs.exerciseID &&
        lhs.wellnessKind == rhs.wellnessKind &&
        lhs.activityTag == rhs.activityTag
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(sequence)
        hasher.combine(kind)
        hasher.combine(title)
        hasher.combine(exerciseSlug)
        hasher.combine(distanceMeters)
        hasher.combine(repetitions)
        hasher.combine(durationSeconds)
        hasher.combine(targetWeightKilograms)
        hasher.combine(loadNote)
        hasher.combine(notes)
        hasher.combine(phase)
        hasher.combine(targetPaceSecondsPerKilometer)
        hasher.combine(targetHeartRateZone)
        hasher.combine(sourceIntensityZoneLabel)
        hasher.combine(targetHeartRatePercentMin)
        hasher.combine(targetHeartRatePercentMax)
        hasher.combine(targetEffortRPE)
        hasher.combine(treadmillInclinePercent)
        hasher.combine(setCount)
        hasher.combine(restBetweenSetsSeconds)
        hasher.combine(groupID)
        hasher.combine(groupKind)
        hasher.combine(groupRounds)
        hasher.combine(cardioActivity)
        hasher.combine(isIndoor)
        hasher.combine(exerciseSnapshot)
        hasher.combine(exerciseID)
        hasher.combine(wellnessKind)
        hasher.combine(activityTag)
    }

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
        case sourceIntensityZoneLabel = "source_intensity_zone"
        case targetHeartRatePercentMin = "target_hr_percent_min"
        case targetHeartRatePercentMax = "target_hr_percent_max"
        case targetEffortRPE = "target_effort_rpe"
        case treadmillInclinePercent = "treadmill_incline_percent"
        case setCount = "set_count"
        case restBetweenSetsSeconds = "rest_between_sets_seconds"
        case groupID = "group_id"
        case groupKind = "group_kind"
        case groupRounds = "group_rounds"
        case cardioActivity = "cardio_activity"
        case isIndoor = "is_indoor"
        case exerciseSnapshot = "exercise_snapshot"
        case exerciseID = "exercise_id"
        case wellnessKind = "wellness_kind"
        case activityTag = "activity_tag"
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
                parts.append("\(seconds) " + ATHLTHLocalization.choose(
                    english: "sec", norwegian: "sek"
                ))
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

        if let zoneLabel = sourceIntensityZoneLabel,
           let lo = targetHeartRatePercentMin,
           let hi = targetHeartRatePercentMax {
            let label = ATHLTHLocalization.choose(
                english: "HR zone", norwegian: "Pulssone"
            )
            parts.append("\(label) \(zoneLabel) · \(Int(lo))–\(Int(hi)) % " +
                ATHLTHLocalization.choose(english: "max HR", norwegian: "makspuls"))
        } else if let targetHeartRateZone, (1...5).contains(targetHeartRateZone) {
            parts.append(ATHLTHLocalization.choose(
                english: "HR zone \(targetHeartRateZone)",
                norwegian: "Pulssone \(targetHeartRateZone)"
            ))
        }
        if let targetEffortRPE, (1...10).contains(targetEffortRPE) {
            parts.append("RPE \(targetEffortRPE)/10")
        }
        if isIndoor == true, let treadmillInclinePercent,
           treadmillInclinePercent.isFinite,
           (0...20).contains(treadmillInclinePercent) {
            parts.append(String(format: "%.1f %% stigning", treadmillInclinePercent))
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
            var item = WorkoutTemplateBlock(
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
                targetHeartRateZone: source.targetHeartRateZone,
                cardioActivity: source.cardioActivity,
                isIndoor: source.isIndoor
            )
            item.exerciseID = source.exerciseID
            item.exerciseSnapshot = source.exerciseSnapshot
            item.wellnessKind = source.wellnessKind
            item.activityTag = source.activityTag
            item.treadmillInclinePercent = source.treadmillInclinePercent
            item.targetEffortRPE = source.targetEffortRPE
            item.sourceIntensityZoneLabel = source.sourceIntensityZoneLabel
            item.targetHeartRatePercentMin = source.targetHeartRatePercentMin
            item.targetHeartRatePercentMax = source.targetHeartRatePercentMax
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
                            && member.isRestOrActiveRecovery && rounds > 1 {
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


enum ATHLTHActiveRecovery {
    /// The same timer and interval group survive switching passive/active.
    static func convert(_ source: WorkoutTemplateBlock, active: Bool) -> WorkoutTemplateBlock {
        var block = source
        if active {
            block.kind = .run
            block.title = ATHLTHLocalization.choose(english: "Active recovery · easy jog", norwegian: "Aktiv pause · rolig jogg")
            block.activityTag = "active_recovery"
            block.cardioActivity = .running
            block.durationSeconds = block.durationSeconds ?? 60
            block.distanceMeters = nil
            block.targetPaceSecondsPerKilometer = nil
            block.targetHeartRateZone = block.targetHeartRateZone ?? 1
            block.sourceIntensityZoneLabel = nil
            block.targetHeartRatePercentMin = nil
            block.targetHeartRatePercentMax = nil
            if block.groupID == nil { block.phase = .recovery }
        } else {
            block.kind = .rest
            block.title = ATHLTHLocalization.choose(english: "Rest", norwegian: "Pause")
            block.activityTag = nil
            block.cardioActivity = nil
            block.distanceMeters = nil
            block.targetPaceSecondsPerKilometer = nil
            block.targetHeartRateZone = nil
            block.targetEffortRPE = nil
            block.sourceIntensityZoneLabel = nil
            block.targetHeartRatePercentMin = nil
            block.targetHeartRatePercentMax = nil
            block.durationSeconds = block.durationSeconds ?? 60
        }
        return block
    }
}

extension WorkoutTemplateBlock {
    var isActiveRecovery: Bool { kind == .run && activityTag == "active_recovery" }
    var isRestOrActiveRecovery: Bool { kind == .rest || isActiveRecovery }
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

extension WorkoutTemplateCatalogEntry {
    /// A single offline baseline used everywhere, even without connectivity.
    static var bundledCatalog: [WorkoutTemplateCatalogEntry] {
        fallbackCatalog + ATHLTHCuratedStrengthWorkouts.entries + ATHLTHZonedPlanLibrary.workoutCatalogEntries
    }
}

@MainActor
final class WorkoutTemplateCatalogStore: ObservableObject {
    @Published private(set) var entries:
        [WorkoutTemplateCatalogEntry] =
            WorkoutTemplateCatalogEntry.bundledCatalog
    @Published private(set) var isLoading = false
    /// Whether the catalogue contains live published data rather than the
    /// bundled HYROX-only fallback. Used by general Train suggestions.
    @Published private(set) var hasPublishedCatalog = false
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

            // Remote and built-in exercises should complement one another.
            // Replace identical slugs with their published version, but do
            // not hide offline running/strength recommendations when online.
            let publishedSlugs = Set(remote.map(\.slug))
            let localOnly = WorkoutTemplateCatalogEntry.bundledCatalog
                .filter { !publishedSlugs.contains($0.slug) }
            entries = (remote + localOnly).sorted {
                $0.sortOrder == $1.sortOrder
                    ? $0.title < $1.title : $0.sortOrder < $1.sortOrder
            }
            loadedRemote = true
            hasPublishedCatalog = !remote.isEmpty
            errorMessage = nil
        } catch {
            // The full offline collection remains available on network errors.
            if !hasPublishedCatalog {
                entries = WorkoutTemplateCatalogEntry.bundledCatalog
            }
            errorMessage = error.localizedDescription
        }
    }
}

struct WorkoutTemplateLibraryView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var favorites: LibraryFavoritesStore
    @EnvironmentObject private var recents: LibraryRecentsStore
    @EnvironmentObject private var runningLibrary: RunningWorkoutLibraryStore

    /// Keeps legacy running templates available through the unified workout library.
    var onStartRunning: ((RunningWorkoutTemplate) -> Void)? = nil

    @StateObject private var catalog =
        WorkoutTemplateCatalogStore()
    @State private var query = ""
    @State private var selectedCategory = "All"
    @State private var favoritesOnly = false

    private var categories: [String] {
        ["All"] +
        Array(Set(catalog.entries.map(\.categoryTitle) + ["Running"]))
            .sorted()
    }

    private var builtInRunningTemplates: [RunningWorkoutTemplate] {
        // Workouts must also expose user-created running templates.
        runningLibrary.allTemplates
    }

    /// Built-in running workouts share the same search, category and favorite
    /// filters as catalog workouts, without creating another library section.
    private var filteredRunningTemplates: [RunningWorkoutTemplate] {
        guard selectedCategory == "All" || selectedCategory == "Running" else {
            return []
        }

        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return builtInRunningTemplates.filter { workout in
            let favoriteMatches =
                !favoritesOnly ||
                favorites.isFavorite(.workout, itemID: workout.id.uuidString)
            let searchMatches =
                clean.isEmpty ||
                workout.title.localizedCaseInsensitiveContains(clean) ||
                workout.summary.localizedCaseInsensitiveContains(clean) ||
                workout.type.title.localizedCaseInsensitiveContains(clean)
            return favoriteMatches && searchMatches
        }
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
                            value: "\(catalog.entries.count + builtInRunningTemplates.count)",
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
                                    category == "Running"
                                        ? ATHLTHLocalization.choose(
                                            english: "Running",
                                            norwegian: "Løping"
                                        )
                                        : category,
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

                if filteredEntries.isEmpty && filteredRunningTemplates.isEmpty {
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

                    ForEach(filteredRunningTemplates) { workout in
                        ZStack(alignment: .topTrailing) {
                            NavigationLink {
                                RunningWorkoutDetailView(
                                    workout: workout,
                                    selectionTitle: nil,
                                    onSelect: nil,
                                    onStart: onStartRunning
                                )
                            } label: {
                                runningWorkoutCard(workout)
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(
                                TapGesture().onEnded {
                                    recents.markUsed(
                                        .workout,
                                        itemID: workout.id.uuidString,
                                        title: workout.title,
                                        subtitle: workout.type.title,
                                        icon: workout.type.systemImage
                                    )
                                }
                            )

                            LibraryFavoriteButton(
                                kind: .workout,
                                itemID: workout.id.uuidString,
                                title: workout.title,
                                subtitle: workout.type.title,
                                icon: workout.type.systemImage
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

    private func runningWorkoutCard(_ workout: RunningWorkoutTemplate) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: workout.type.systemImage)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.vitality)
                .frame(width: 50, height: 50)
                .background(
                    ATHLTHTheme.vitality.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 5) {
                Text(workout.type.title.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(ATHLTHTheme.vitality)

                Text(workout.title)
                    .font(.headline)
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .multilineTextAlignment(.leading)

                Text(workout.summary)
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 9) {
                    Label("\(workout.blocks.count) blocks", systemImage: "list.number")
                    if let seconds = workout.estimatedDurationSeconds {
                        Label(
                            "~\(Int((seconds / 60).rounded(.up))) min",
                            systemImage: "clock"
                        )
                    }
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(ATHLTHTheme.mutedText)
                .padding(.top, 2)
            }

            Spacer(minLength: 34)
        }
        .padding(16)
        .background(
            Color.white.opacity(0.86),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.94), lineWidth: 0.8)
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
    @EnvironmentObject private var exerciseLibrary: ExerciseLibraryStore
    @EnvironmentObject private var phoneWorkout: IPhoneWorkoutStore
    @EnvironmentObject private var strengthWorkout: StrengthWorkoutStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore

    let entry: WorkoutTemplateCatalogEntry

    @State private var saved = false
    @State private var showingWorkout = false
    @State private var showingEditor = false
    @State private var preparedShare: MessageShareDraft?
    @State private var shareError: String?

    private var hasActiveWorkout: Bool {
        phoneWorkout.active != nil ||
        strengthWorkout.activeWorkout != nil ||
        watchConnection.hasActiveWatchWorkout ||
        ATHLTHWatchWorkoutRuntime.isMirroredWorkoutActive
    }

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ATHLTHWorkoutRecipePreview(
                    title: entry.title,
                    summary: entry.summary,
                    category: entry.category,
                    symbol: entry.systemImage,
                    difficulty: entry.difficulty,
                    durationMinutes: entry.estimatedDurationMinutes,
                    blocks: entry.blocks
                )

                Button {
                    showingEditor = true
                } label: {
                    Label(tr("Customize a copy", "Tilpass en kopi"),
                          systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.bordered)
                .tint(ATHLTHPlanDesign.ink)

                if let source = entry.sourceLabel {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.seal")
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source)
                                .font(.subheadline.weight(.semibold))
                            if entry.tags.contains("hyrox") {
                                Text(tr(
                                    "HYROX loads differ by division. Confirm the correct race load before starting.",
                                    "HYROX-belastning varierer med klasse. Kontroller konkurransevekten før start."
                                ))
                                .font(.caption)
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(15)
                    .athlthPlanCard(radius: 19)
                }

                if hasActiveWorkout {
                    Label(tr(
                        "Finish the active workout before starting another.",
                        "Fullfør økten som pågår før du starter en ny."
                    ), systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
            }
            .padding(18)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
        .navigationTitle(tr("Workout", "Treningsøkt"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    do {
                        preparedShare = try ATHLTHShareDraftFactory.workout(
                            entry.plannedSession(),
                            library: exerciseLibrary.allExercises,
                            ownerID: session.profile.userID
                        )
                    } catch {
                        shareError = error.localizedDescription
                    }
                } label: {
                    Label(tr("Share", "Del"), systemImage: "square.and.arrow.up")
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    session.saveSharedWorkout(
                        entry.plannedSession(), sourceSessionID: entry.id
                    )
                    saved = true
                } label: {
                    Label(
                        saved ? tr("Saved", "Lagret") : tr("Save", "Lagre"),
                        systemImage: saved ? "checkmark.circle.fill" : "square.and.arrow.down"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 51)
                }
                .buttonStyle(.bordered)
                .disabled(saved)

                Button {
                    guard !hasActiveWorkout else { return }
                    showingWorkout = true
                } label: {
                    Label(tr("Start workout", "Start økt"),
                          systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 51)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.accentDeep)
                .disabled(hasActiveWorkout)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(.regularMaterial)
        }
        .sheet(item: $preparedShare) { draft in
            ATHLTHDirectShareSheet(draft: draft)
        }
        .alert(tr("Could not share", "Kunne ikke dele"),
               isPresented: Binding(
                   get: { shareError != nil },
                   set: { if !$0 { shareError = nil } }
               )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(shareError ?? "")
        }
        .fullScreenCover(isPresented: $showingWorkout) {
            StructuredWorkoutSessionView(workout: entry.plannedSession())
                .environmentObject(session)
        }
        .sheet(isPresented: $showingEditor) {
            WorkoutTemplateBuilderView(
                initialTitle: entry.title,
                initialBlocks: entry.blocks,
                draftContext: "catalog-copy-\(entry.slug)"
            )
        }
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
                            .frame(minHeight: ATHLTHPlanDesign.minTapHeight)
                            .athlthPlanCard(radius: 18)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !completionHistory.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(ATHLTHLocalization.choose(
                            english: "RECENTLY COMPLETED",
                            norwegian: "NYLIG GJENNOMFØRT"
                        ))
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
                                        "\(completion.completedBlockCount)/\(completion.totalBlockCount) " +
                                    ATHLTHLocalization.choose(english: "blocks", norwegian: "blokker") +
                                    " · \(completion.endedAt.formatted(date: .abbreviated, time: .shortened))"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }
                            .padding(12)
                            .athlthPlanCard(radius: 17)
                        }
                    }
                }

                if session.savedWorkoutTemplates.isEmpty &&
                   runningLibrary.customTemplates.isEmpty {
                    ContentUnavailableView(
                        ATHLTHLocalization.choose(
                            english: "No saved workouts", norwegian: "Ingen lagrede treningsøkter"
                        ),
                        systemImage: "rectangle.stack",
                        description: Text(
                            ATHLTHLocalization.choose(
                            english: "Save a workout from the Library or create one of your own.",
                            norwegian: "Lagre en økt fra biblioteket, eller lag din egen."
                        )
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
        .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
        .navigationTitle(ATHLTHLocalization.choose(english: "My workouts", norwegian: "Mine treningsøkter"))
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
                        ATHLTHLocalization.choose(
                            english: "Delete", norwegian: "Slett"
                        ),
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
        .padding(16)
        .athlthPlanCard(radius: 21)
    }

    private func savedWorkoutSubtitle(
        _ workout: PlannedSession
    ) -> String {
        if workout.isStructuredWorkout {
            let category = workout.workoutCategory?.capitalized ??
                ATHLTHLocalization.choose(english: "Workout", norwegian: "Treningsøkt")
            return category + " · \(workout.resolvedWorkoutBlocks.count) " +
                ATHLTHLocalization.choose(english: "blocks", norwegian: "blokker")
        }

        return workout.kind.title
    }
}

/// SwiftUI's native drag preview follows the finger while dropEntered moves
/// nearby cards in real time. No new workout model or plan save is triggered
/// until the athlete finishes interacting with the editor.
private struct ATHLTHWorkoutTimelineDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var activeID: UUID?
    @Binding var hoveredID: UUID?
    let reorder: (UUID, UUID) -> Void

    func dropEntered(info: DropInfo) {
        guard let activeID, activeID != targetID else { return }
        hoveredID = targetID
        reorder(activeID, targetID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if hoveredID == targetID { hoveredID = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard activeID != nil else { return false }
        activeID = nil
        hoveredID = nil
        return true
    }
}

struct ATHLTHPlanCopyDay: Identifiable, Hashable {
    let weekIndex: Int
    let weekday: Int
    let date: Date
    let hasWorkout: Bool
    let isSource: Bool

    var id: Int { weekIndex * 7 + weekday }
}

struct WorkoutTemplateBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var exerciseLibrary: ExerciseLibraryStore

    @State private var title = ""
    @State private var blocks: [WorkoutTemplateBlock] = []
    @State private var selectedRouteID: UUID?
    @State private var showingExercisePicker = false
    @State private var selectedExerciseInfo: WorkoutTemplateBlock?
    @State private var selectedPhase: WorkoutPhaseKind = .main
    @State private var expandedBlockIndex: Int?
    @State private var draggingSectionID: UUID?
    @State private var hoveredSectionID: UUID?
    @State private var draggingGroupMemberID: UUID?
    @State private var hoveredGroupMemberID: UUID?
    @State private var exerciseTargetGroupID: UUID?
    @State private var pendingNewGroupKind: WorkoutBlockGroupKind?
    @State private var collapsedGroupIDs: Set<UUID> = []
    @State private var showingDiscardConfirmation = false
    @State private var manualDurationMinutes: Int?
    @State private var durationInputText = ""
    @State private var allRoundsExpandedIDs: Set<UUID> = []
    @State private var draftRestored = false
    @State private var draftActive = false
    @State private var initialQuickAddConsumed = false
    @State private var draftFinished = false
    @State private var draftNotice = false
    @State private var showingBlockPicker = false
    @State private var showingSavedWorkoutPicker = false
    @State private var showingCopyPicker = false
    @State private var pendingExerciseChoice: WorkoutBlockGroupKind?
    @State private var pendingSavedWorkoutPicker = false
    @State private var pendingStandaloneExercise = false
    @State private var pendingCopyDayIDs: Set<Int> = []
    @State private var selectedCopyDayIDs: Set<Int> = []
    @State private var copyWeekIndex = 0
    @State private var savedToMyWorkouts = false
    @State private var savedTemplateID: UUID?
    @State private var actionNotice: String?
    @AppStorage("athlth.workoutBuilder.durationInput.v1")
    private var durationInputMode = "clock"
    private let draftContext: String
    private let initialQuickAdd: String?
    private let initialFocusedBlockIndex: Int?
    private let initialFocusedExecutionStepIndex: Int?
    private let plannedDate: Date?
    private let planCopyDays: [ATHLTHPlanCopyDay]
    private let onCopyToPlan: ((String, [WorkoutTemplateBlock], UUID?, Int?, [Int]) -> Bool)?
    private let initialDraftSignature: String
    /// Present from advanced plan creation to edit a specific weekday
    /// without creating an unwanted shared workout template.
    private let onSaveToPlan: ((String, [WorkoutTemplateBlock], UUID?, Int?, Bool) -> Bool)?

    init(
        initialTitle: String = "",
        initialBlocks: [WorkoutTemplateBlock] = [],
        initialRouteID: UUID? = nil,
        initialQuickAdd: String? = nil,
        initialPhase: WorkoutPhaseKind? = nil,
        initialFocusedBlockIndex: Int? = nil,
        initialFocusedExecutionStepIndex: Int? = nil,
        initialDurationOverrideMinutes: Int? = nil,
        draftContext: String = "shared-template",
        plannedDate: Date? = nil,
        planCopyDays: [ATHLTHPlanCopyDay] = [],
        initialCopyWeekIndex: Int = 0,
        onCopyToPlan: ((String, [WorkoutTemplateBlock], UUID?, Int?, [Int]) -> Bool)? = nil,
        onSaveToPlan: ((String, [WorkoutTemplateBlock], UUID?, Int?, Bool) -> Bool)? = nil
    ) {
        _title = State(initialValue: initialTitle)
        _blocks = State(initialValue: initialBlocks)
        // A newly planned workout starts at warm-up; when editing a saved
        // sequence, open its first actual phase instead of assuming main.
        _selectedPhase = State(initialValue:
            initialPhase ?? (onSaveToPlan == nil
                ? .main
                : initialBlocks.first?.resolvedPhase ?? .warmup)
        )
        _selectedRouteID = State(initialValue: initialRouteID)
        _manualDurationMinutes = State(initialValue: initialDurationOverrideMinutes)
        _durationInputText = State(initialValue: (initialDurationOverrideMinutes ??
            ATHLTHWorkoutDurationEstimator.minutes(for: initialBlocks)).map(String.init) ?? "")
        self.draftContext = draftContext
        self.initialQuickAdd = initialQuickAdd
        self.initialFocusedBlockIndex = initialFocusedBlockIndex
        self.initialFocusedExecutionStepIndex = initialFocusedExecutionStepIndex
        self.plannedDate = plannedDate
        self.planCopyDays = planCopyDays
        self.onCopyToPlan = onCopyToPlan
        _copyWeekIndex = State(initialValue: initialCopyWeekIndex)
        let originalBlocks = (try? JSONEncoder().encode(initialBlocks))?.base64EncodedString() ?? ""
        self.initialDraftSignature = initialTitle + "|" + originalBlocks +
            "|" + (initialRouteID?.uuidString ?? "") +
            "|" + String(initialDurationOverrideMinutes ?? -1)
        self.onSaveToPlan = onSaveToPlan
    }

    private struct StoredWorkoutDraft: Codable {
        let signature: String
        let title: String
        let blocks: [WorkoutTemplateBlock]
        let routeID: UUID?
        let manualMinutes: Int?
        let pendingCopyDayIDs: [Int]?
        let updatedAt: Date
    }

    private var draftStorageKey: String {
        let encodedContext = Data(draftContext.utf8).base64EncodedString()
        return "athlth.workoutBuilder.draft.v1.\(session.profile.userID.uuidString).\(encodedContext)"
    }

    private func restoreWorkoutDraft() {
        guard let data = UserDefaults.standard.data(forKey: draftStorageKey),
              let stored = try? JSONDecoder().decode(StoredWorkoutDraft.self, from: data),
              stored.signature == initialDraftSignature else { return }
        title = stored.title
        blocks = stored.blocks
        selectedRouteID = stored.routeID
        manualDurationMinutes = stored.manualMinutes
        durationInputText = (stored.manualMinutes ??
            ATHLTHWorkoutDurationEstimator.minutes(for: stored.blocks)).map(String.init) ?? ""
        pendingCopyDayIDs = Set(stored.pendingCopyDayIDs ?? [])
        collapsedGroupIDs = Set(blocks.compactMap(\.groupID))
        draftRestored = true
        draftNotice = true
    }

    private func persistWorkoutDraft() {
        guard draftActive, !draftFinished else { return }
        // Save on edits and when locking the device, not only on explicit Save.
        let snapshot = StoredWorkoutDraft(
            signature: initialDraftSignature,
            title: title,
            blocks: blocks,
            routeID: selectedRouteID,
            manualMinutes: manualDurationMinutes,
            pendingCopyDayIDs: Array(pendingCopyDayIDs).sorted(),
            updatedAt: Date()
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: draftStorageKey)
    }

    // Standalone workout creation keeps its established palette. When opened
    // from the plan, use the same tokens as the first plan-creation screen.
    private var isPlannedWorkout: Bool { onSaveToPlan != nil }
    private var studioInk: Color {
        isPlannedWorkout ? ATHLTHTrainDesign.ink
            : Color(red: 0.17, green: 0.17, blue: 0.18)
    }
    private var studioAccent: Color {
        isPlannedWorkout ? ATHLTHTrainDesign.bronze
            : Color(red: 0.65, green: 0.53, blue: 0.37)
    }
    private var studioBackground: Color {
        isPlannedWorkout ? ATHLTHTrainDesign.canvas
            : Color(red: 0.986, green: 0.978, blue: 0.964)
    }

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    private var hasRunning: Bool {
        blocks.contains(where: { $0.kind == .run })
    }

    private var hasOutdoorCardio: Bool {
        blocks.contains { $0.kind == .run && $0.isIndoor != true }
    }

    private var hasWalking: Bool {
        blocks.contains { $0.kind == .run && $0.cardioActivity == .walking }
    }

    private var hasActualRunning: Bool {
        blocks.contains { $0.kind == .run && $0.cardioActivity != .walking }
    }

    private var hasStrength: Bool {
        blocks.contains(where: { $0.kind == .exercise })
    }

    private var hasCycling: Bool {
        blocks.contains { $0.kind == .note && $0.activityTag == "cycling"
            && ($0.durationSeconds ?? 0) > 0 }
    }

    private var hasTimedWellness: Bool {
        blocks.contains { $0.kind == .note && $0.wellnessKind != nil
            && ($0.durationSeconds ?? 0) > 0 }
    }

    // Infer the workout type from its actual content, instead of forcing a type
    // before the user has added any blocks.
    private var category: String {
        let categories = [hasActualRunning, hasWalking, hasStrength,
                          hasCycling, hasTimedWellness]
        if categories.filter({ $0 }).count > 1 { return "hybrid" }
        if hasWalking { return "walking" }
        if hasRunning { return "running" }
        if hasStrength { return "strength" }
        if hasCycling { return "cycling" }
        if hasTimedWellness {
            return blocks.contains {
                $0.wellnessKind != nil && $0.wellnessKind != .meditation
            } ? "mobility" : "recovery"
        }
        return "custom"
    }

    private var categoryTitle: String {
        switch category {
        case "hybrid": return tr("Hybrid", "Hybrid")
        case "running": return tr("Running", "Løping")
        case "walking": return tr("Walking", "Gåing")
        case "cycling": return tr("Cycling", "Sykling")
        case "strength": return tr("Strength", "Styrke")
        case "mobility": return tr("Mobility", "Mobilitet")
        case "recovery": return tr("Recovery", "Restitusjon")
        default: return tr("Custom", "Egendefinert")
        }
    }

    private var canSave: Bool {
        (hasRunning || hasStrength || hasCycling || hasTimedWellness) &&
        !hasIncompleteSuperset &&
        (!isPlannedWorkout || resolvedDurationMinutes != nil)
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

    private struct TimelineSection: Identifiable {
        let id: UUID
        let start: Int
        let position: Int
    }

    private struct TimelineGroupMember: Identifiable {
        let id: UUID
        let index: Int
    }

    private func sectionID(at index: Int) -> UUID {
        blocks[index].groupID ?? blocks[index].editorDragID
    }

    private var timelineSections: [TimelineSection] {
        timelineStarts.enumerated().map { position, index in
            TimelineSection(id: sectionID(at: index),
                            start: index, position: position)
        }
    }

    private func moveDraggedSection(_ draggedID: UUID, over targetID: UUID) {
        let sections = timelineSections
        guard let from = sections.firstIndex(where: { $0.id == draggedID }),
              let target = sections.firstIndex(where: { $0.id == targetID }),
              from != target else { return }
        var grouped = sections.map { section in
            groupIndices(startingAt: section.start).map { blocks[$0] }
        }
        let moved = grouped.remove(at: from)
        grouped.insert(moved, at: target)
        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.86)) {
            blocks = grouped.flatMap { $0 }
            resequence()
            expandedBlockIndex = nil
        }
    }

    /// Exercises inside a superset/interval can be moved only within that
    /// same group; dragging across its boundary never breaks group membership.
    private func moveDraggedGroupMember(_ draggedID: UUID, over targetID: UUID) {
        guard let source = blocks.firstIndex(where: { $0.editorDragID == draggedID }),
              let target = blocks.firstIndex(where: { $0.editorDragID == targetID }),
              source != target,
              let group = blocks[source].groupID,
              blocks[target].groupID == group else { return }
        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.86)) {
            let moved = blocks.remove(at: source)
            blocks.insert(moved, at: target)
            resequence()
            expandedBlockIndex = nil
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
        ATHLTHWorkoutDurationEstimator.minutes(for: blocks)
    }

    private var resolvedDurationMinutes: Int? {
        manualDurationMinutes ?? knownDurationMinutes
    }

    private var durationSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(tr("Workout duration", "Varighet på økten"),
                      systemImage: "clock")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(studioInk)
                Spacer()
                Text(manualDurationMinutes == nil
                     ? tr("Estimated", "Estimert")
                     : tr("Entered", "Angitt"))
                    .font(.caption)
                    .foregroundStyle(studioInk.opacity(0.58))
            }
            HStack(spacing: 8) {
                TextField(tr("Enter minutes", "Skriv inn minutter"),
                          text: Binding(
                            get: { durationInputText },
                            set: { value in
                                // Only user typing changes the manual override.
                                // Restored and recalculated estimates stay estimates.
                                durationInputText = value
                                let digits = value.filter { $0.isNumber }
                                manualDurationMinutes = Int(digits).flatMap {
                                    (1...240).contains($0) ? $0 : nil
                                }
                                savedToMyWorkouts = false
                            }
                          ))
                    .keyboardType(.numberPad)
                    .font(.system(size: 23, weight: .semibold, design: .rounded))
                    .foregroundStyle(studioInk)
                    .tint(studioAccent)
                    .accessibilityLabel(
                        tr("Workout duration in minutes", "Øktvarighet i minutter")
                    )
                Text(tr("min", "min"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(studioInk.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(ATHLTHPlanDesign.selectedSurface,
                        in: RoundedRectangle(cornerRadius: 13))
            Text(tr(
                "The estimate updates as you edit blocks, even after entering a duration.",
                "Varigheten beregnes på nytt når du endrer blokker, også etter at du har skrevet inn et tall."
            ))
            .font(.caption)
            .foregroundStyle(studioInk.opacity(0.58))
        }
        .padding(ATHLTHPlanDesign.Density.comfortable.cardPadding)
        .athlthPlanCard(radius: 20, warm: isPlannedWorkout)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let plannedDate {
                        Label(
                            plannedDate.formatted(.dateTime.weekday(.wide).day().month(.wide)),
                            systemImage: "calendar"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(studioInk)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .athlthPlanCard(radius: 12, warm: isPlannedWorkout)
                    }
                    workoutOverview
                    durationSettings
                    if isPlannedWorkout {
                        plannedPhaseComposer
                    }
                    if isPlannedWorkout {
                        workoutActions
                    }
                    timeline
                    if draftNotice {
                        Label(tr("Recovered saved draft", "Gjenopprettet lagret utkast"),
                              systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(studioAccent)
                            .padding(.horizontal, 6)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 28)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(studioBackground.ignoresSafeArea())
            .sheet(isPresented: $showingBlockPicker, onDismiss: {
                if pendingStandaloneExercise {
                    pendingStandaloneExercise = false
                    openExercisePicker()
                } else if let group = pendingExerciseChoice {
                    pendingExerciseChoice = nil
                    if group == .superset { createSuperset() }
                    else { openExercisePicker() }
                } else if pendingSavedWorkoutPicker {
                    pendingSavedWorkoutPicker = false
                    showingSavedWorkoutPicker = true
                }
            }) {
                blockPickerSheet
            }
            .sheet(isPresented: $showingSavedWorkoutPicker) {
                savedWorkoutPickerSheet
            }
            .sheet(isPresented: $showingCopyPicker) {
                copyPickerSheet
            }
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
                    draftFinished = true
                    UserDefaults.standard.removeObject(forKey: draftStorageKey)
                    dismiss()
                }
                Button(tr("Keep editing", "Fortsett å redigere"), role: .cancel) {}
            } message: {
                Text(tr("A recoverable local draft is kept until you discard or save.",
                        "Utkastet er lagret lokalt til du forkaster eller lagrer det."))
            }
            .sheet(item: $selectedExerciseInfo) { block in
                ATHLTHLinkedExerciseDetailView(block: block)
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
            .onAppear {
                guard !draftActive else { return }
                restoreWorkoutDraft()
                if !draftRestored {
                    collapsedGroupIDs = Set(blocks.compactMap(\.groupID))
                }
                if let focused = initialFocusedBlockIndex,
                   blocks.indices.contains(focused) {
                    // The Plan card uses the executable interval index, not
                    // just the compact group's first recipe item. Split only
                    // when a specific round was selected. This allows editing
                    // duration, pace, incline and recovery independently.
                    if let requestedStep = initialFocusedExecutionStepIndex,
                       let groupID = blocks[focused].groupID,
                       blocks[focused].groupKind == .intervals,
                       let individualized = ATHLTHIntervalGroupEditing.individualSteps(
                           in: blocks, groupID: groupID
                       ) {
                        blocks = individualized
                        let index = min(focused + requestedStep, blocks.count - 1)
                        expandedBlockIndex = index
                        selectedPhase = blocks[index].resolvedPhase
                    } else {
                        expandedBlockIndex = focused
                        selectedPhase = blocks[focused].resolvedPhase
                        if let groupID = blocks[focused].groupID {
                            collapsedGroupIDs.remove(groupID)
                        }
                    }
                }
                draftActive = true
                // Apply one explicitly requested block after the draft is
                // restored. Never insert it twice on sheet reappearance.
                if !draftRestored, !initialQuickAddConsumed,
                   let initialQuickAdd {
                    initialQuickAddConsumed = true
                    applyInitialQuickAdd(initialQuickAdd)
                }
            }
            .onChange(of: blocks) { _, _ in
                // A changed recipe updates the estimate even if the
                // user previously entered a time. Keep the field editable.
                manualDurationMinutes = nil
                durationInputText = knownDurationMinutes.map(String.init) ?? ""
                savedToMyWorkouts = false
                persistWorkoutDraft()
            }
            .onChange(of: title) { _, _ in
                savedToMyWorkouts = false
                persistWorkoutDraft()
            }
            .onChange(of: selectedRouteID) { _, _ in persistWorkoutDraft() }
            .onChange(of: manualDurationMinutes) { _, _ in
                persistWorkoutDraft()
            }
            .onChange(of: pendingCopyDayIDs) { _, _ in persistWorkoutDraft() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { persistWorkoutDraft() }
            }
            .onDisappear { persistWorkoutDraft() }
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
                LinearGradient(
                    colors: [
                        .white,
                        isPlannedWorkout ? ATHLTHTheme.cardWarm.opacity(0.45)
                            : Color(red: 0.965, green: 0.952, blue: 0.932)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: proxy.size.width, height: 184)

                Circle()
                    .fill(studioAccent.opacity(0.10))
                    .frame(width: 225, height: 225)
                    .offset(x: proxy.size.width - 154, y: -69)
                    .blur(radius: 18)

                VStack(alignment: .leading, spacing: 11) {
                    HStack(spacing: 7) {
                        Text("A T H L T H")
                        Spacer()
                        Label(tr("Edit workout name", "Endre øktnavn"), systemImage: "pencil")
                    }
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(studioInk.opacity(0.73))

                    TextField(
                        tr("Workout name (optional)", "Navn på økten (valgfritt)"),
                        text: $title
                    )
                    .font(.system(size: 27, weight: .semibold,
                                  design: isPlannedWorkout ? .serif : .rounded))
                    .foregroundStyle(studioInk)
                    .tint(studioAccent)
                    .lineLimit(1)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityLabel(tr("Workout name", "Navn på treningsøkt"))

                    HStack(spacing: 6) {
                        metricPill(
                            "\(blocks.expandedForExecution().count) " + tr("steps", "steg"),
                            icon: "square.stack.3d.up"
                        )
                        if let resolvedDurationMinutes {
                            metricPill(
                                "\(manualDurationMinutes == nil ? "~" : "")\(resolvedDurationMinutes) min",
                                icon: "clock"
                            )
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
                .strokeBorder(isPlannedWorkout ? ATHLTHPlanDesign.outline
                                : Color.white.opacity(0.92), lineWidth: 1)
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
            .background(isPlannedWorkout ? ATHLTHPlanDesign.selectedSurface
                         : Color.white.opacity(0.79), in: Capsule())
            .overlay {
                Capsule().strokeBorder(isPlannedWorkout ? ATHLTHPlanDesign.outline
                                       : Color.clear, lineWidth: 0.7)
            }
    }

    /// Plan the same chronological phases that the live session executes.
    /// Selecting a phase never creates a second workout or a separate engine.
    private var plannedPhaseComposer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(tr("WORKOUT PHASES", "ØKTENS DELER"))
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.3)
                    .foregroundStyle(studioInk)
                Spacer(minLength: 0)
                Text(tr("One connected session", "Én sammenhengende økt"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(studioInk.opacity(0.60))
            }

            ForEach(
                [WorkoutPhaseKind.warmup, .main, .cooldown]
            ) { phase in
                plannedPhaseRow(phase)
            }

            Text(tr(
                "Time and intensity belong to each activity. Running, strength and cycling can be mixed in the same phase. Pauses can be inserted between steps.",
                "Tid og intensitet settes for hver aktivitet. Løping, styrke og sykling kan blandes i samme del. Pauser kan legges mellom stegene."
            ))
            .font(.caption)
            .foregroundStyle(studioInk.opacity(0.67))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 3)
        }
        .padding(14)
        .athlthPlanCard(radius: 21, warm: true)
    }

    private func plannedPhaseRow(_ phase: WorkoutPhaseKind) -> some View {
        let isSelected = selectedPhase == phase
        // Legacy independent recovery blocks remain visible under the main
        // phase. Newly created rests inherit the selected actual phase.
        let steps = blocks.filter {
            $0.resolvedPhase == phase ||
                (phase == .main && $0.resolvedPhase == .recovery)
        }
        let knownSeconds = steps.expandedForExecution()
            .compactMap(\.durationSeconds)
            .filter { $0.isFinite && $0 > 0 }.reduce(0, +)

        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    selectedPhase = phase
                }
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: phase.symbol)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(isSelected ? Color.white : studioAccent)
                        .frame(width: 39, height: 39)
                        .background(
                            isSelected ? studioAccent : ATHLTHPlanDesign.selectedSurface,
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(phase.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(studioInk)
                        Text("\(steps.count) " +
                             tr("blocks", "blokker") +
                             (knownSeconds > 0
                                ? " · " + shortDuration(knownSeconds) : ""))
                            .font(.caption)
                            .foregroundStyle(studioInk.opacity(0.64))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(studioInk.opacity(0.64))
                }
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(phase.title)
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            if isSelected {
                // A readable live-style phase outline, derived from the
                // very same blocks that are saved and executed in order.
                if steps.isEmpty {
                    Text(tr("No activities added yet", "Ingen aktiviteter lagt til ennå"))
                        .font(.caption)
                        .foregroundStyle(studioInk.opacity(0.62))
                        .padding(.horizontal, 3)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(steps, id: \.editorDragID) { block in
                            HStack(alignment: .top, spacing: 9) {
                                Image(systemName: block.wellnessKind?.symbol ??
                                    (block.activityTag == "cycling" ? "bicycle"
                                        : block.kind.systemImage))
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(studioAccent)
                                    .frame(width: 22, height: 23)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(localizedBlockTitle(block))
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(studioInk)
                                        .lineLimit(2)
                                    if let targets = block.targetText {
                                        Text(targets)
                                            .font(.system(size: 11))
                                            .foregroundStyle(studioInk.opacity(0.66))
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Text(tr(
                            "Change time, intensity and order in the workout steps below.",
                            "Endre tid, intensitet og rekkefølge i øktstegene nedenfor."
                        ))
                        .font(.caption2)
                        .foregroundStyle(studioInk.opacity(0.60))
                        .padding(.top, 3)
                    }
                    .padding(11)
                    .background(
                        ATHLTHPlanDesign.surface,
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                }

                HStack(spacing: 7) {
                    phaseAddButton(tr("Running", "Løping"), icon: "figure.run") {
                        selectedPhase = phase
                        addRunBlock(activity: .running)
                    }
                    phaseAddButton(tr("Strength", "Styrke"), icon: "dumbbell.fill") {
                        selectedPhase = phase
                        openExercisePicker()
                    }
                    phaseAddButton(tr("Cycling", "Sykling"), icon: "bicycle") {
                        selectedPhase = phase
                        addCyclingBlock()
                    }
                }
                Menu {
                    Button(tr("Walking", "Gåing"), systemImage: "figure.walk") {
                        selectedPhase = phase
                        addRunBlock(activity: .walking)
                    }
                    Button(tr("Yoga", "Yoga"), systemImage: "figure.yoga") {
                        selectedPhase = phase
                        addWellnessBlock(.yoga)
                    }
                    Button(tr("Stretching", "Uttøying"),
                           systemImage: "figure.flexibility") {
                        selectedPhase = phase
                        addWellnessBlock(.stretching)
                    }
                    Button(tr("Rest", "Pause"), systemImage: "pause.fill") {
                        selectedPhase = phase
                        addRestBlock()
                    }
                    Button(tr("Active recovery · jog", "Aktiv pause · jogg"),
                           systemImage: "figure.run") {
                        selectedPhase = phase
                        addActiveRecoveryBlock()
                    }
                    Button(tr("Intervals", "Intervaller"), systemImage: "repeat") {
                        selectedPhase = phase
                        createIntervals()
                    }
                } label: {
                    Label(tr("More activities and blocks", "Flere aktiviteter og blokker"),
                          systemImage: "plus.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(studioAccent)
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
            }
        }
        .padding(11)
        .background(
            isSelected ? ATHLTHPlanDesign.selectedSurface
                : ATHLTHPlanDesign.surface,
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isSelected ? studioAccent.opacity(0.35)
                    : ATHLTHPlanDesign.outline, lineWidth: 0.8)
        }
    }

    private func phaseAddButton(
        _ title: String, icon: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(studioInk)
            .frame(maxWidth: .infinity, minHeight: 55)
            .background(ATHLTHPlanDesign.surface,
                        in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("Add", "Legg til") + " " + title)
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
                        .foregroundStyle(studioAccent)
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
                    .tint(studioAccent)
                    .padding(.top, 7)
                }
                .frame(maxWidth: .infinity)
                .padding(22)
                .athlthPlanCard(radius: 22, warm: isPlannedWorkout)
            } else {
                VStack(spacing: 11) {
                    ForEach(timelineSections) { section in
                        timelineDraggableSection(section)
                    }
                }
                .background(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(studioAccent.opacity(0.17))
                        .frame(width: 2)
                        .padding(.leading, 16)
                        .padding(.vertical, 22)
                }
            }
        }
    }

    // Keep the drag implementation separate from the timeline's ViewBuilder.
    // This avoids another deeply nested generic SwiftUI view type.
    private func timelineSectionContent(_ section: TimelineSection) -> some View {
        HStack(alignment: .top, spacing: 10) {
            timelineNumber(section.position + 1)
                .frame(width: 34)
            Group {
                if blocks[section.start].groupID != nil {
                    groupTimelineCard(startingAt: section.start)
                } else {
                    builderBlockRow(section.start, nested: false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func timelineDraggableSection(_ section: TimelineSection) -> some View {
        let hovering = hoveredSectionID == section.id &&
            draggingSectionID != section.id
        return timelineSectionContent(section)
            .padding(.top, hovering ? 12 : 0)
            .contentShape(RoundedRectangle(cornerRadius: 20))
            .overlay(alignment: .top) {
                if hovering {
                    Capsule()
                        .fill(studioAccent)
                        .frame(height: 3)
                        .padding(.horizontal, 10)
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeInOut(duration: 0.16), value: hoveredSectionID)
            .onDrag {
                draggingSectionID = section.id
                hoveredSectionID = nil
                return NSItemProvider(object: section.id.uuidString as NSString)
            } preview: {
                timelineSectionContent(section)
                    .frame(width: 340)
                    .background(studioBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            .onDrop(
                of: [UTType.plainText],
                delegate: ATHLTHWorkoutTimelineDropDelegate(
                    targetID: section.id,
                    activeID: $draggingSectionID,
                    hoveredID: $hoveredSectionID,
                    reorder: moveDraggedSection
                )
            )
            .accessibilityHint(tr(
                "Long-press and drag the whole card to rearrange.",
                "Hold inne og dra hele kortet for å endre rekkefølgen."
            ))
    }

    private func timelineNumber(_ number: Int) -> some View {
        Text("\(number)")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(studioAccent)
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
                    .accessibilityLabel(tr("Drag to reorder group",
                                           "Dra for å flytte gruppe"))

                Image(systemName: kind == .superset ? "dumbbell.fill" : "figure.run")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(studioAccent)
                    .frame(width: 40, height: 40)
                    .background(studioAccent.opacity(0.085),
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
                        .background(studioAccent.opacity(0.075), in: Capsule())
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

            if kind == .intervals {
                Text(intervalGroupSummary(members: members, rounds: first.groupRounds ?? 1))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(studioInk.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 51)
            }

            if !collapsed {
                VStack(spacing: 0) {
                    ForEach(members.map {
                        TimelineGroupMember(id: blocks[$0].editorDragID, index: $0)
                    }) { member in
                        let index = member.index
                        builderBlockRow(index, nested: true)
                            .padding(.top,
                                hoveredGroupMemberID == member.id &&
                                draggingGroupMemberID != member.id ? 9 : 0)
                            .overlay(alignment: .top) {
                                if hoveredGroupMemberID == member.id &&
                                    draggingGroupMemberID != member.id {
                                    Capsule()
                                        .fill(studioAccent)
                                        .frame(height: 2)
                                        .allowsHitTesting(false)
                                }
                            }
                            .animation(.easeInOut(duration: 0.16),
                                       value: hoveredGroupMemberID)
                            .contentShape(Rectangle())
                            .onDrag {
                                draggingGroupMemberID = blocks[index].editorDragID
                                hoveredGroupMemberID = nil
                                return NSItemProvider(
                                    object: blocks[index].editorDragID.uuidString as NSString
                                )
                            }
                            .onDrop(
                                of: [UTType.plainText],
                                delegate: ATHLTHWorkoutTimelineDropDelegate(
                                    targetID: blocks[index].editorDragID,
                                    activeID: $draggingGroupMemberID,
                                    hoveredID: $hoveredGroupMemberID,
                                    reorder: moveDraggedGroupMember
                                )
                            )
                        if index != members.last {
                            Divider()
                                .padding(.leading, 57)
                        }
                    }
                }

                if kind == .intervals {
                    Button {
                        if let individual = ATHLTHIntervalGroupEditing.individualSteps(
                            in: blocks, groupID: id
                        ) {
                            blocks = individual
                            collapsedGroupIDs.remove(id)
                            allRoundsExpandedIDs.remove(id)
                            expandedBlockIndex = firstIndex
                        }
                    } label: {
                        Label(tr("Customize each effort and recovery", "Tilpass hvert drag og hver pause"),
                              systemImage: "slider.horizontal.3")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                    .disabled(!ATHLTHIntervalGroupEditing.canIndividualize(in: blocks, groupID: id))
                    Text(tr("Keeps the complete sequence and makes each effort editable on its own. Save the workout to keep your changes.",
                            "Hele rekkefølgen beholdes, og hvert drag kan redigeres separat. Lagre økten for å beholde endringene."))
                        .font(.caption)
                        .foregroundStyle(ATHLTHTrainDesign.secondary)
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            if allRoundsExpandedIDs.contains(id) {
                                allRoundsExpandedIDs.remove(id)
                            } else {
                                allRoundsExpandedIDs.insert(id)
                            }
                        }
                    } label: {
                        Label(
                            allRoundsExpandedIDs.contains(id)
                                ? tr("Hide all rounds", "Skjul alle intervaller")
                                : tr("Show all rounds", "Vis alle intervaller"),
                            systemImage: allRoundsExpandedIDs.contains(id)
                                ? "chevron.up" : "list.number"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(studioAccent)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 5)

                    if allRoundsExpandedIDs.contains(id) {
                        intervalFullTimeline(
                            memberIndices: members,
                            rounds: first.groupRounds ?? 1
                        )
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
                            addRunBlock(toGroup: id, activity: .running)
                        }
                        Button(tr("Walking", "Gåing"), systemImage: "figure.walk") {
                            addRunBlock(toGroup: id, activity: .walking)
                        }
                    }
                    Button(tr("Rest", "Pause"), systemImage: "pause.fill") {
                        addRestBlock(toGroup: id)
                    }
                    Button(tr("Active recovery · jog", "Aktiv pause · jogg"),
                           systemImage: "figure.run") {
                        addActiveRecoveryBlock(toGroup: id)
                    }
                } label: {
                    Label(tr("Add to group", "Legg til i gruppen"),
                          systemImage: "plus.circle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(studioAccent)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: ATHLTHPlanDesign.minTapHeight)
                        .background(isPlannedWorkout ? ATHLTHPlanDesign.selectedSurface
                                     : studioAccent.opacity(0.065),
                                    in: RoundedRectangle(cornerRadius: 11))
                        .overlay {
                            RoundedRectangle(cornerRadius: 11)
                                .strokeBorder(isPlannedWorkout ? ATHLTHPlanDesign.outline
                                              : Color.clear, lineWidth: 0.8)
                        }
                }
            }
        }
        .padding(13)
        .athlthPlanCard(radius: 21, warm: isPlannedWorkout)
    }

    private func intervalGroupSummary(members: [Int], rounds: Int) -> String {
        let description = members.map { intervalStepLabel(blocks[$0]) }
            .joined(separator: "  +  ")
        return String(max(rounds, 1)) + " " + tr("rounds", "runder") + " · " + description
    }

    private func intervalStepLabel(_ block: WorkoutTemplateBlock) -> String {
        let activity = block.isActiveRecovery
            ? tr("Active recovery jog", "Aktiv joggepause")
            : block.kind == .rest
            ? tr("Rest", "Pause")
            : block.kind == .run
            ? (block.cardioActivity ?? .running).title
            : localizedBlockTitle(block)
        let duration: String
        if let seconds = block.durationSeconds {
            duration = shortDuration(seconds)
        } else {
            duration = block.targetText ?? ""
        }
        return duration.isEmpty ? activity : duration + " " + activity.lowercased()
    }

    private func shortDuration(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds.rounded()))
        let mins = whole / 60
        let secs = whole % 60
        if mins > 0 && secs > 0 {
            return "\(mins) " + tr("min", "min") + " \(secs) " + tr("sec", "sek")
        }
        return mins > 0
            ? "\(mins) " + tr("min", "min")
            : "\(secs) " + tr("sec", "sek")
    }

    private func intervalFullTimeline(
        memberIndices: [Int], rounds: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(1...min(max(rounds, 1), 20), id: \.self) { round in
                VStack(alignment: .leading, spacing: 5) {
                    Text(tr("Round", "Runde") + " \(round)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(studioInk)
                    ForEach(memberIndices, id: \.self) { index in
                        if !(round == min(max(rounds, 1), 20) &&
                             index == memberIndices.last &&
                             blocks[index].isRestOrActiveRecovery &&
                             rounds > 1) {
                            HStack(spacing: 8) {
                                Image(systemName: blocks[index].kind == .rest
                                      ? "pause.fill"
                                      : blocks[index].cardioActivity == .walking
                                      ? "figure.walk" : "figure.run")
                                    .frame(width: 20)
                                Text(intervalStepLabel(blocks[index]))
                            }
                            .font(.caption)
                            .foregroundStyle(studioInk.opacity(0.78))
                        }
                    }
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isPlannedWorkout ? ATHLTHPlanDesign.selectedSurface : studioBackground,
                            in: RoundedRectangle(cornerRadius: 13))
                .overlay {
                    RoundedRectangle(cornerRadius: 13)
                        .strokeBorder(isPlannedWorkout ? ATHLTHPlanDesign.outline
                                      : Color.clear, lineWidth: 0.8)
                }
            }
        }
        .padding(.top, 4)
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

                        Text(block.resolvedPhase.title.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.7)
                            .foregroundStyle(studioAccent)
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

                if block.kind == .exercise {
                    Button {
                        selectedExerciseInfo = block
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(studioAccent)
                            .frame(width: 34, height: 40)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tr(
                        "Exercise details", "Øvelsesinformasjon"
                    ))
                }

                Menu {
                    ForEach(WorkoutPhaseKind.allCases) { phase in
                        Button {
                            moveBlockToPhase(at: index, phase: phase)
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
                Picker(tr("Section", "Del"), selection: Binding(
                    get: { blocks[index].resolvedPhase },
                    set: { moveBlockToPhase(at: index, phase: $0) }
                )) {
                    ForEach(WorkoutPhaseKind.allCases) { phase in
                        Label(phase.title, systemImage: phase.symbol).tag(phase)
                    }
                }
                .font(.caption)
                blockDetails(index)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
            }
        }
        .padding(nested ? 5 : 13)
        .background {
            if !nested {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(
                        colors: [
                            ATHLTHPlanDesign.surface,
                            isPlannedWorkout ? ATHLTHTheme.cardWarm.opacity(0.38)
                                : ATHLTHPlanDesign.surface
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
            }
        }
        .overlay {
            if !nested {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(isPlannedWorkout ? ATHLTHPlanDesign.outline
                                  : studioInk.opacity(0.04), lineWidth: 0.8)
            }
        }
        .shadow(color: ATHLTHTheme.accentDeep.opacity(nested ? 0 : 0.05),
                radius: 12, y: 5)
    }

    private func localizedBlockTitle(_ block: WorkoutTemplateBlock) -> String {
        guard block.kind == .exercise else { return block.title }
        if let match = ATHLTHExerciseReferenceResolver.resolve(
            block, in: exerciseLibrary.allExercises
        ) {
            return exerciseLibrary.localizedExerciseName(match)
        }
        return ATHLTHLocalization.isNorwegian
            ? ATHLTHExerciseNameLocalization.norwegianName(for: block.title)
            : block.title
    }

    @ViewBuilder
    private func blockArtwork(_ block: WorkoutTemplateBlock, size: CGFloat) -> some View {
        if let match = ATHLTHExerciseReferenceResolver.resolve(
            block, in: exerciseLibrary.allExercises
        ) {
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
            let icon = block.wellnessKind?.symbol ?? (block.kind == .run
                ? ((block.cardioActivity == .walking || block.resolvedPhase == .cooldown)
                    ? "figure.walk" : "figure.run")
                : block.kind.systemImage)
            Image(systemName: icon)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(studioInk.opacity(0.82))
                .frame(width: size, height: size)
                .background(isPlannedWorkout ? ATHLTHPlanDesign.selectedSurface : studioBackground,
                            in: RoundedRectangle(cornerRadius: 11))
        }
    }

    @ViewBuilder
    private func blockDetails(_ index: Int) -> some View {
        let block = blocks[index]
        if block.isRestOrActiveRecovery {
            Picker(tr("Recovery type", "Pausetype"), selection: Binding<Bool>(
                get: { blocks[index].isActiveRecovery },
                set: { active in
                    blocks[index] = ATHLTHActiveRecovery.convert(blocks[index], active: active)
                }
            )) {
                Text(tr("Rest", "Hvile")).tag(false)
                Text(tr("Active jog", "Aktiv jogg")).tag(true)
            }
            .pickerStyle(.segmented)
            Text(tr(
                "Active recovery keeps the timer running while you jog lightly. Adjust time and HR zone below.",
                "Ved aktiv pause jogger du rolig mens tiden går. Juster tid og pulssone nedenfor."
            ))
            .font(.caption)
            .foregroundStyle(studioInk.opacity(0.65))
        }
        switch block.kind {
            case .run:
                Picker(tr("Activity", "Aktivitet"), selection: Binding(
                    get: { blocks[index].cardioActivity ?? .running },
                    set: { activity in
                        let oldActivity = blocks[index].cardioActivity ?? .running
                        blocks[index].cardioActivity = activity
                        if blocks[index].title == oldActivity.title ||
                            blocks[index].title == "Løping" ||
                            blocks[index].title == "Running" ||
                            blocks[index].title == "Gåing" ||
                            blocks[index].title == "Walking" ||
                            blocks[index].title == "Løpeintervall" ||
                            blocks[index].title == "Run interval" ||
                            blocks[index].title == "Gåintervall" ||
                            blocks[index].title == "Walking interval" {
                            let isInterval = blocks[index].groupKind == .intervals
                            blocks[index].title = isInterval
                                ? (activity == .walking
                                    ? tr("Walking interval", "Gåintervall")
                                    : tr("Run interval", "Løpeintervall"))
                                : (activity == .walking
                                    ? tr("Walking", "Gåing")
                                    : tr("Running", "Løping"))
                        }
                    }
                )) {
                    Text(tr("Run", "Løp")).tag(WorkoutCardioActivity.running)
                    Text(tr("Walk", "Gå")).tag(WorkoutCardioActivity.walking)
                }
                .pickerStyle(.segmented)
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
                    durationEntryEditor(index)
                } else {
                    Stepper(value: distanceBinding(index), in: 1...100000, step: 1) {
                        Text("\(Int(blocks[index].distanceMeters ?? 1000)) m")
                    }
                }
                Toggle(tr("Outdoor activity", "Utendørs"), isOn: Binding(
                    get: { blocks[index].isIndoor != true },
                    set: { outdoor in
                        blocks[index].isIndoor = !outdoor
                        if outdoor { blocks[index].treadmillInclinePercent = nil }
                    }
                ))
                .tint(studioAccent)
                if blocks[index].isIndoor != true {
                    routeSection
                } else {
                    Toggle(
                        tr("Treadmill incline target", "Målstigning på tredemølle"),
                        isOn: Binding(
                            get: { blocks[index].treadmillInclinePercent != nil },
                            set: { blocks[index].treadmillInclinePercent = $0 ? 0 : nil }
                        )
                    )
                    .tint(studioAccent)
                    if blocks[index].treadmillInclinePercent != nil {
                        Stepper(
                            value: Binding(
                                get: { blocks[index].treadmillInclinePercent ?? 0 },
                                set: { blocks[index].treadmillInclinePercent = $0 }
                            ),
                            in: 0...20, step: 0.5
                        ) {
                            Text(String(
                                format: "%.1f %% stigning",
                                blocks[index].treadmillInclinePercent ?? 0
                            ))
                            .font(.subheadline.weight(.medium))
                        }
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
                            in: 60...3600, step: 1) {
                        let pace = Int(blocks[index].targetPaceSecondsPerKilometer ?? 330)
                        Text(String(format: "%d:%02d/km", pace / 60, pace % 60))
                    }
                }
            case .exercise:
                Toggle(
                    tr("Timed exercise", "Tidsstyrt øvelse"),
                    isOn: Binding(
                        get: { blocks[index].durationSeconds != nil },
                        set: { active in
                            blocks[index].durationSeconds = active ? 60 : nil
                        }
                    )
                )
                .tint(studioAccent)
                if blocks[index].durationSeconds != nil {
                    durationEntryEditor(index)
                }
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
                        Button {
                            splitExerciseIntoIndividualSets(at: index)
                        } label: {
                            Label(
                                tr("Customize each set", "Tilpass hvert sett"),
                                systemImage: "slider.horizontal.3"
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(studioAccent)
                        }
                        .buttonStyle(.plain)
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
                durationEntryEditor(index)

            case .note:
                TextField(tr("Activity", "Aktivitet"), text: Binding(
                    get: { blocks[index].title },
                    set: { blocks[index].title = $0 }
                ))
                .font(.subheadline)
                durationEntryEditor(index)
                TextField(tr("Guidance (optional)", "Veiledning (valgfritt)"),
                    text: Binding(
                        get: { blocks[index].notes ?? "" },
                        set: { blocks[index].notes = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                    .font(.caption)
            }

            if block.kind != .rest {
                Divider().padding(.vertical, 3)

                Text(tr("PLANNED INTENSITY", "PLANLAGT INTENSITET"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(studioAccent)

                Picker(
                    tr("Heart rate zone", "Pulssone"),
                    selection: Binding<Int>(
                        get: { blocks[index].targetHeartRateZone ?? 0 },
                        set: { selected in
                            blocks[index].targetHeartRateZone =
                                (1...5).contains(selected) ? selected : nil
                            // A manual choice replaces the imported intensity
                            // label; never keep contradictory HR ranges.
                            blocks[index].sourceIntensityZoneLabel = nil
                            blocks[index].targetHeartRatePercentMin = nil
                            blocks[index].targetHeartRatePercentMax = nil
                        }
                    )
                ) {
                    Text(tr("No target", "Ingen")).tag(0)
                    ForEach(1...5, id: \.self) { zone in
                        Text("\(zone)").tag(zone)
                    }
                }

                Picker(
                    tr("Perceived effort", "Opplevd anstrengelse"),
                    selection: Binding<Int>(
                        get: { blocks[index].targetEffortRPE ?? 0 },
                        set: { blocks[index].targetEffortRPE =
                            (1...10).contains($0) ? $0 : nil }
                    )
                ) {
                    Text(tr("No target", "Ingen")).tag(0)
                    ForEach(1...10, id: \.self) { effort in
                        Text("RPE \(effort)/10").tag(effort)
                    }
                }

                Text(tr(
                    "These are planned targets, not measured heart rate or effort.",
                    "Dette er planlagte mål, ikke målt puls eller anstrengelse."
                ))
                .font(.caption2)
                .foregroundStyle(studioInk.opacity(0.6))
            }
    }

    private var workoutActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    saveToMyWorkouts()
                } label: {
                    Label(savedToMyWorkouts
                        ? tr("Saved in My workouts", "Lagret i mine økter")
                        : savedTemplateID == nil
                            ? tr("Save to My workouts", "Lagre til mine økter")
                            : tr("Update My workout", "Oppdater min økt"),
                          systemImage: savedToMyWorkouts ? "checkmark.circle.fill" : "bookmark")
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .disabled(!canSave || savedToMyWorkouts)
                if savedTemplateID != nil {
                    Menu {
                        Button {
                            saveToMyWorkouts(asNew: true)
                        } label: {
                            Label(tr("Save as new workout", "Lagre som ny økt"),
                                  systemImage: "plus.square.on.square")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 30, height: 46)
                    }
                    .disabled(!canSave)
                }
                if onCopyToPlan != nil && !planCopyDays.isEmpty {
                    Button {
                        selectedCopyDayIDs = pendingCopyDayIDs
                        showingCopyPicker = true
                    } label: {
                        Label(tr("Copy to days", "Kopier til andre dager"),
                              systemImage: "calendar.badge.plus")
                            .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .disabled(!canSave)
                }
            }
            .buttonStyle(.bordered)
            .tint(studioInk)
            if !pendingCopyDayIDs.isEmpty {
                Label("\(pendingCopyDayIDs.count) " +
                      tr("copy destinations selected; saved together with the workout",
                         "valgte dager; kopiene lagres sammen med originaløkten"),
                      systemImage: "calendar.badge.clock")
                    .font(.caption)
                    .foregroundStyle(studioInk.opacity(0.7))
            }
            if let actionNotice {
                Label(actionNotice, systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(studioAccent)
            }
        }
    }

    private func pickerRow(
        _ name: String, icon: String, action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .medium))
                    .frame(width: 30)
                Text(name)
                    .font(.system(size: 16, weight: .medium))
                Spacer()
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(studioInk.opacity(0.45))
            }
            .foregroundStyle(studioInk)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var blockPickerSheet: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        Color.clear.frame(height: 1).id("picker-top")
                        pickerRow(tr("Running", "Løping"), icon: "figure.run") {
                            addRunBlock(activity: .running)
                            showingBlockPicker = false
                        }
                        pickerRow(tr("Walking", "Gå"), icon: "figure.walk") {
                            addRunBlock(activity: .walking)
                            showingBlockPicker = false
                        }
                        pickerRow(tr("Cycling", "Sykling"), icon: "bicycle") {
                            addCyclingBlock()
                            showingBlockPicker = false
                        }
                        pickerRow("Yoga", icon: "figure.yoga") {
                            addWellnessBlock(.yoga)
                            showingBlockPicker = false
                        }
                        pickerRow(tr("Meditation", "Meditasjon"), icon: "sparkles") {
                            addWellnessBlock(.meditation)
                            showingBlockPicker = false
                        }
                        Divider().padding(.vertical, 10)
                        pickerRow(tr("Exercise", "Øvelse"), icon: "dumbbell.fill") {
                            pendingStandaloneExercise = true
                            showingBlockPicker = false
                        }
                        pickerRow(tr("Workout", "Treningsøkt"), icon: "rectangle.stack") {
                            pendingSavedWorkoutPicker = true
                            showingBlockPicker = false
                        }
                        Divider().padding(.vertical, 10)
                        pickerRow(tr("Intervals", "Intervall"), icon: "repeat") {
                            createIntervals()
                            showingBlockPicker = false
                        }
                        pickerRow(tr("Superset", "Supersett"), icon: "square.stack.3d.up") {
                            pendingExerciseChoice = .superset
                            showingBlockPicker = false
                        }
                        pickerRow(tr("Rest", "Pause"), icon: "pause.fill") {
                            addRestBlock()
                            showingBlockPicker = false
                        }
                        pickerRow(tr("Stretching", "Uttøying"), icon: "figure.flexibility") {
                            addWellnessBlock(.stretching)
                            showingBlockPicker = false
                        }
                    }
                    .padding(.horizontal, 15)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .onAppear {
                    proxy.scrollTo("picker-top", anchor: .top)
                }
            }
            .background(studioBackground.ignoresSafeArea())
            .navigationTitle(tr("Add block", "Legg til blokk"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Close", "Lukk")) { showingBlockPicker = false }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var savedWorkoutPickerSheet: some View {
        NavigationStack {
            List {
                ForEach(session.savedWorkoutTemplates.filter {
                    !($0.workoutBlocks ?? []).isEmpty
                }) { workout in
                    Button {
                        appendSavedWorkout(workout)
                        showingSavedWorkoutPicker = false
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(workout.title)
                                .font(.headline)
                            Text("\(workout.workoutBlocks?.count ?? 0) " +
                                 tr("blocks", "blokker"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(studioInk)
                }
                if !session.savedWorkoutTemplates.contains(where: {
                    !($0.workoutBlocks ?? []).isEmpty
                }) {
                    Text(tr("Save a structured workout under My workouts first.",
                            "Lagre først en sammensatt økt i Mine økter."))
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(tr("My workouts", "Mine økter"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Close", "Lukk")) { showingSavedWorkoutPicker = false }
                }
            }
        }
    }

    private var copyPickerSheet: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack {
                    Button {
                        copyWeekIndex = max(0, copyWeekIndex - 1)
                    } label: { Image(systemName: "chevron.left").frame(width: 42, height: 42) }
                    .disabled(copyWeekIndex == 0)
                    Spacer()
                    Text(tr("Week", "Uke") + " \(copyWeekIndex + 1)")
                        .font(.headline)
                    Spacer()
                    Button {
                        copyWeekIndex = min(maxCopyWeekIndex, copyWeekIndex + 1)
                    } label: { Image(systemName: "chevron.right").frame(width: 42, height: 42) }
                    .disabled(copyWeekIndex >= maxCopyWeekIndex)
                }
                .padding(.horizontal, 12)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            Color.clear.frame(height: 1).id("copy-top")
                            ForEach(planCopyDays.filter {
                                $0.weekIndex == copyWeekIndex
                            }) { option in
                                let selected = selectedCopyDayIDs.contains(option.id)
                                Button {
                                    if selected {
                                        selectedCopyDayIDs.remove(option.id)
                                    } else {
                                        selectedCopyDayIDs.insert(option.id)
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                            .font(.title3)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(option.date.formatted(.dateTime.weekday(.wide)))
                                                .font(.subheadline.weight(.semibold))
                                            Text(option.date.formatted(.dateTime.day().month(.wide)) +
                                                 (option.isSource ? " · " + tr("Original", "Original") :
                                                  option.hasWorkout ? " · " +
                                                  tr("Has a workout", "Har allerede økt") : ""))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .foregroundStyle(studioInk)
                                    .padding(14)
                                    .background(selected ? ATHLTHPlanDesign.selectedSurface
                                                : ATHLTHPlanDesign.surface,
                                                in: RoundedRectangle(cornerRadius: 14))
                                }
                                .disabled(option.isSource)
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                    }
                    .onChange(of: copyWeekIndex) { _, _ in
                        proxy.scrollTo("copy-top", anchor: .top)
                    }
                    .onAppear { proxy.scrollTo("copy-top", anchor: .top) }
                }
                Text(tr("Existing workouts are kept. Save the original workout when you return.",
                        "Eksisterende økter beholdes. Husk å lagre originaløkten når du kommer tilbake."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                Button {
                    guard canSave else { return }
                    pendingCopyDayIDs = selectedCopyDayIDs
                    selectedCopyDayIDs.removeAll()
                    actionNotice = tr(
                        "Copy destinations are ready; save to apply them.",
                        "Dagene er valgt. Lagre økten for å kopiere."
                    )
                    showingCopyPicker = false
                } label: {
                    Text(tr("Copy to selected days", "Kopier til valgte dager") +
                         " (\(selectedCopyDayIDs.count))")
                        .frame(maxWidth: .infinity, minHeight: 51)
                }
                .buttonStyle(.borderedProminent)
                .tint(studioAccent)
                .disabled(selectedCopyDayIDs.isEmpty || !canSave)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .navigationTitle(tr("Copy workout", "Kopier økt"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Close", "Lukk")) { showingCopyPicker = false }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var maxCopyWeekIndex: Int {
        planCopyDays.map(\.weekIndex).max() ?? 0
    }

    /// Plan chips route to the actual timeline composer, not merely a
    /// generic workout editor. No change is persisted until Save.
    private func applyInitialQuickAdd(_ choice: String) {
        switch choice {
        case "running": addRunBlock(activity: .running)
        case "walking": addRunBlock(activity: .walking)
        case "cycling": addCyclingBlock()
        case "yoga": addWellnessBlock(.yoga)
        case "meditation": addWellnessBlock(.meditation)
        case "exercise": openExercisePicker()
        case "workout": showingSavedWorkoutPicker = true
        case "interval": createIntervals()
        case "superset": createSuperset()
        case "rest": addRestBlock()
        case "active_recovery": addActiveRecoveryBlock()
        case "stretching": addWellnessBlock(.stretching)
        default: showingBlockPicker = true
        }
    }

    private func addCyclingBlock() {
        var block = WorkoutTemplateBlock(
            sequence: 0, kind: .note,
            title: tr("Cycling", "Sykling"),
            exerciseSlug: nil, distanceMeters: nil,
            repetitions: nil, durationSeconds: selectedPhase == .main ? 1800 : 600,
            targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: selectedPhase
        )
        block.activityTag = "cycling"
        insertBlock(block, toGroup: nil)
    }

    private func appendSavedWorkout(_ workout: PlannedSession) {
        let source = workout.workoutBlocks ?? []
        guard !source.isEmpty else { return }
        var newGroups: [UUID: UUID] = [:]
        for original in source {
            var copy = original
            copy.editorDragID = UUID()
            if let id = original.groupID {
                if newGroups[id] == nil { newGroups[id] = UUID() }
                copy.groupID = newGroups[id]
            }
            blocks.append(copy)
        }
        resequence()
    }

    private func saveToMyWorkouts(asNew: Bool = false) {
        guard canSave else { return }
        let snapshot = workoutSnapshot()
        if let savedTemplateID, !asNew,
           session.updateSavedWorkoutTemplate(snapshot, id: savedTemplateID) {
            savedToMyWorkouts = true
            actionNotice = tr("Updated in My workouts", "Oppdatert i Mine økter")
        } else {
            savedTemplateID = session.saveSharedWorkout(snapshot)
            savedToMyWorkouts = true
            actionNotice = tr("Saved in My workouts", "Lagret i Mine økter")
        }
    }

    private var routeSection: some View {
        ATHLTHPlanSurface {
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
                Text(tr("One optional route for outdoor running and walking blocks.",
                        "Én valgfri rute for utendørs løpe- og gåblokker."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                NavigationLink {
                    RunRouteBuilderView()
                } label: {
                    Label(tr("Create a new route", "Opprett ny rute"),
                          systemImage: "map.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(studioAccent)
                }
            }
        }
    }

    private var saveBar: some View {
        HStack(spacing: 10) {
            Button {
                showingBlockPicker = true
            } label: {
                Label(tr("Add block", "Legg til blokk"), systemImage: "plus.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(studioInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(ATHLTHPlanDesign.surface,
                                in: RoundedRectangle(cornerRadius: ATHLTHPlanDesign.fieldRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: ATHLTHPlanDesign.fieldRadius)
                            .strokeBorder(ATHLTHPlanDesign.outline, lineWidth: 0.8)
                    }
            }

            Button {
                saveWorkout()
            } label: {
                Label(isPlannedWorkout
                    ? tr("Save planned workout", "Lagre planlagt økt")
                    : tr("Save workout", "Lagre treningsøkt"),
                      systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(studioAccent,
                                in: RoundedRectangle(cornerRadius: ATHLTHPlanDesign.fieldRadius))
                    .opacity(canSave ? 1 : 0.48)
            }
            .disabled(!canSave)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            ATHLTHPlanDesign.outline.frame(height: 1)
        }
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
            notes: nil, phase: selectedPhase
        )
        run.groupID = id
        run.groupKind = .intervals
        run.groupRounds = 4
        run.cardioActivity = .running
        run.durationSeconds = 240
        insertBlock(run, toGroup: nil)

        var rest = WorkoutTemplateBlock(
            sequence: 0, kind: .rest,
            title: tr("Recovery", "Pause"),
            exerciseSlug: nil, distanceMeters: nil,
            repetitions: nil, durationSeconds: 60,
            targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: selectedPhase
        )
        rest.groupID = id
        rest.groupKind = .intervals
        rest.groupRounds = 4
        insertBlock(rest, toGroup: id)
    }

    private func splitExerciseIntoIndividualSets(at index: Int) {
        guard blocks.indices.contains(index) else { return }
        let separated = ATHLTHWorkoutSetExpansion.separateSets(in: blocks[index])
        guard separated.count > 1 else { return }
        blocks.replaceSubrange(index...index, with: separated)
        resequence()
        expandedBlockIndex = index
    }

    /// Moving one interval effort must bring every recovery in that group.
    /// Never leave a mixed-phase group that previews differently from live.
    private func moveBlockToPhase(at index: Int, phase: WorkoutPhaseKind) {
        guard blocks.indices.contains(index) else { return }
        let selectedID = blocks[index].editorDragID
        blocks = ATHLTHWorkoutPhasePlacement.relocatingSelection(
            at: index, to: phase, in: blocks
        )
        expandedBlockIndex = blocks.firstIndex {
            $0.editorDragID == selectedID
        }
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
            let position = ATHLTHWorkoutPhasePlacement.insertionIndex(
                for: block.resolvedPhase, in: blocks
            )
            blocks.insert(block, at: position)
            expandedBlockIndex = position
        }
        resequence()
    }

    private func addRunBlock(
        toGroup groupID: UUID? = nil,
        activity: WorkoutCardioActivity = .running
    ) {
        var block = WorkoutTemplateBlock(
            sequence: 0, kind: .run,
            title: activity == .walking ? tr("Walking", "Gåing") : tr("Running", "Løping"),
            exerciseSlug: nil,
            distanceMeters: selectedPhase == .main ? 1_000 : nil,
            repetitions: nil,
            durationSeconds: selectedPhase == .main ? nil : 600,
            targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: selectedPhase
        )
        block.cardioActivity = activity
        insertBlock(block, toGroup: groupID)
    }

    private func addWarmUpRun() {
        var block = WorkoutTemplateBlock(
            sequence: 0, kind: .run,
            title: tr("Easy jogging warm-up", "Oppvarming – rolig jogg"),
            exerciseSlug: nil, distanceMeters: nil,
            repetitions: nil, durationSeconds: 600,
            targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: .warmup
        )
        block.cardioActivity = .running
        blocks.insert(block, at: 0)
        resequence()
        expandedBlockIndex = 0
    }

    private func addWellnessBlock(_ wellness: WorkoutWellnessKind) {
        let minutes: Double = wellness == .meditation ? 5 : wellness == .yoga ? 15 : 10
        var block = WorkoutTemplateBlock(
            sequence: 0, kind: .note, title: wellness.title,
            exerciseSlug: nil, distanceMeters: nil,
            repetitions: nil, durationSeconds: minutes * 60,
            targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: wellness == .meditation ? .recovery : selectedPhase
        )
        block.wellnessKind = wellness
        insertBlock(block, toGroup: nil)
    }

    private func addWellnessGuide(_ guide: ATHLTHWellnessGuide) {
        var block = WorkoutTemplateBlock(
            sequence: 0, kind: .note, title: guide.title,
            exerciseSlug: nil, distanceMeters: nil, repetitions: nil,
            durationSeconds: Double(guide.seconds),
            targetWeightKilograms: nil, loadNote: nil,
            notes: guide.instructions,
            phase: guide.category == .zen ? .recovery : selectedPhase
        )
        block.wellnessKind = guide.category == .zen ? .meditation : .stretching
        insertBlock(block, toGroup: nil)
    }

    private func addRestBlock(toGroup groupID: UUID? = nil) {
        insertBlock(WorkoutTemplateBlock(
            sequence: 0, kind: .rest,
            title: tr("Rest", "Pause"),
            exerciseSlug: nil, distanceMeters: nil,
            repetitions: nil, durationSeconds: 60,
            targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: selectedPhase
        ), toGroup: groupID)
    }

    private func addActiveRecoveryBlock(toGroup groupID: UUID? = nil) {
        let rest = WorkoutTemplateBlock(
            sequence: 0, kind: .rest, title: tr("Rest", "Pause"),
            exerciseSlug: nil, distanceMeters: nil,
            repetitions: nil, durationSeconds: 60,
            targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: selectedPhase
        )
        insertBlock(ATHLTHActiveRecovery.convert(rest, active: true), toGroup: groupID)
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
        block.exerciseID = entry.id
        block.exerciseSnapshot = entry.source == .custom &&
            entry.exercise.isVisibleOutsideOwnerLibrary
            ? ATHLTHExerciseReferenceResolver.shareableSnapshot(entry.exercise)
            : nil
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
            ATHLTHWorkoutPhasePlacement.renumbered(block, sequence: index + 1)
        }
    }

    private func workoutSnapshot() -> PlannedSession {
        let requestedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTitle = requestedTitle.isEmpty ? categoryTitle : requestedTitle

        var workout = PlannedSession(
            id: UUID(),
            title: cleanTitle,
            kind: resolvedWorkoutKind,
            scheduledStart: nil,
            durationMinutes: resolvedDurationMinutes,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: hasOutdoorCardio ? selectedRouteID : nil,
            exercises: [],
            notes: nil
        )
        workout.workoutBlocks = blocks
        workout.workoutCategory = category
        return workout
    }

    private func saveWorkout() {
        guard canSave else { return }
        let workout = workoutSnapshot()
        let cleanTitle = workout.title
        if let onSaveToPlan {
            guard onSaveToPlan(
                cleanTitle, blocks, hasOutdoorCardio ? selectedRouteID : nil,
                resolvedDurationMinutes, manualDurationMinutes != nil
            ) else {
                actionNotice = tr("Cannot save this workout yet",
                                  "Kunne ikke lagre økten ennå")
                return
            }
            if !pendingCopyDayIDs.isEmpty, let onCopyToPlan {
                guard onCopyToPlan(
                    cleanTitle, blocks, hasOutdoorCardio ? selectedRouteID : nil,
                    resolvedDurationMinutes, Array(pendingCopyDayIDs).sorted()
                ) else {
                    actionNotice = tr("Workout saved; check copy destinations",
                                      "Økten er lagret. Kontroller kopieringsdagene.")
                    return
                }
            }
        } else {
            session.saveSharedWorkout(workout)
        }
        draftFinished = true
        UserDefaults.standard.removeObject(forKey: draftStorageKey)
        dismiss()
    }

    private var resolvedWorkoutKind: WorkoutKind {
        switch category {
        case "running": return .running
        case "walking": return .walking
        case "strength": return .strength
        case "mobility": return .mobility
        case "recovery": return .recovery
        default: return .custom
        }
    }

    // Presentation preference only; the workout model always stores seconds.
    @ViewBuilder
    private func durationEntryEditor(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text(tr("Duration", "Varighet"))
                    .font(.caption.weight(.semibold))
                Spacer()
                Menu {
                    Button(tr("Minutes", "Minutter")) { durationInputMode = "minutes" }
                    Button(tr("Minutes : seconds", "Minutter : sekunder")) {
                        durationInputMode = "clock"
                    }
                    Button(tr("Seconds", "Sekunder")) { durationInputMode = "seconds" }
                } label: {
                    HStack(spacing: 5) {
                        Text(durationInputMode == "minutes"
                             ? tr("Minutes", "Minutter")
                             : durationInputMode == "seconds"
                             ? tr("Seconds", "Sekunder")
                             : tr("Min : sec", "Min : sek"))
                        Image(systemName: "chevron.down")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(studioAccent)
                }
            }
            HStack(spacing: 7) {
                if durationInputMode == "seconds" {
                    TextField(tr("Seconds", "Sekunder"),
                              value: totalSecondsBinding(index),
                              format: .number)
                        .keyboardType(.numberPad)
                        .frame(width: 82)
                    Text(tr("sec", "sek"))
                        .foregroundStyle(studioInk.opacity(0.60))
                } else {
                    TextField(tr("Minutes", "Minutter"),
                              value: minutesComponentBinding(index),
                              format: .number)
                        .keyboardType(.numberPad)
                        .frame(width: 62)
                    if durationInputMode == "clock" {
                        Text(":")
                        TextField(tr("Seconds", "Sekunder"),
                                  value: secondsComponentBinding(index),
                                  format: .number)
                            .keyboardType(.numberPad)
                            .frame(width: 56)
                        Text(tr("min : sec", "min : sek"))
                            .font(.caption)
                            .foregroundStyle(studioInk.opacity(0.60))
                    } else {
                        Text(tr("min", "min"))
                            .foregroundStyle(studioInk.opacity(0.60))
                        let remainder = Int((blocks[index].durationSeconds ?? 0).rounded()) % 60
                        if remainder > 0 {
                            Text("+ \(remainder) " + tr("sec", "sek"))
                                .font(.caption)
                                .foregroundStyle(studioInk.opacity(0.60))
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 20, weight: .medium, design: .rounded))
            .textFieldStyle(.roundedBorder)
            Text(tr("Stored precisely in seconds, regardless of display choice.",
                    "Tiden lagres nøyaktig i sekunder uansett visning."))
                .font(.caption2)
                .foregroundStyle(studioInk.opacity(0.55))
        }
        .padding(.vertical, 3)
    }

    private func totalSecondsBinding(_ index: Int) -> Binding<Int> {
        Binding(
            get: { Int((blocks[index].durationSeconds ?? 60).rounded()) },
            set: { blocks[index].durationSeconds = Double(min(max($0, 1), 21600)) }
        )
    }

    private func minutesComponentBinding(_ index: Int) -> Binding<Int> {
        Binding(
            get: { Int((blocks[index].durationSeconds ?? 60).rounded()) / 60 },
            set: { minutes in
                let remaining = Int((blocks[index].durationSeconds ?? 60).rounded()) % 60
                blocks[index].durationSeconds = Double(
                    min(max(minutes, 0) * 60 + remaining, 21600)
                )
            }
        )
    }

    private func secondsComponentBinding(_ index: Int) -> Binding<Int> {
        Binding(
            get: { Int((blocks[index].durationSeconds ?? 60).rounded()) % 60 },
            set: { seconds in
                let minutes = Int((blocks[index].durationSeconds ?? 60).rounded()) / 60
                blocks[index].durationSeconds = Double(
                    min(minutes * 60 + min(max(seconds, 0), 59), 21600)
                )
            }
        )
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
    @EnvironmentObject private var runningLibrary: RunningWorkoutLibraryStore

    @StateObject private var catalog =
        WorkoutTemplateCatalogStore()
    @State private var query = ""
    @State private var selectedCategory = "all"

    let onSelect: (PlannedSession) -> Void

    private func categoryMatches(_ kind: WorkoutKind, category: String? = nil) -> Bool {
        switch selectedCategory {
        case "running": return kind == .running
        case "strength": return kind == .strength
        case "hybrid": return category == "hybrid"
        case "other": return kind == .mobility || kind == .walking ||
            (kind == .custom && category != "hybrid")
        default: return true
        }
    }

    private var runningWorkouts: [RunningWorkoutTemplate] {
        guard selectedCategory == "all" || selectedCategory == "running" else { return [] }
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return runningLibrary.allTemplates.filter {
            clean.isEmpty || $0.title.localizedCaseInsensitiveContains(clean)
                || $0.summary.localizedCaseInsensitiveContains(clean)
                || $0.type.title.localizedCaseInsensitiveContains(clean)
        }
    }

    private var savedWorkouts: [PlannedSession] {
        let clean =
            query.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        return session.savedWorkoutTemplates.filter { workout in
            categoryMatches(workout.kind, category: workout.workoutCategory) &&
                (clean.isEmpty || workout.title.localizedCaseInsensitiveContains(clean) ||
                 (workout.notes ?? "").localizedCaseInsensitiveContains(clean))
        }
    }

    private var catalogWorkouts:
        [WorkoutTemplateCatalogEntry] {
        let clean =
            query.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        return catalog.entries.filter { entry in
            categoryMatches(entry.workoutKind, category: entry.category) &&
                (clean.isEmpty ||
                 entry.title.localizedCaseInsensitiveContains(clean) ||
                 entry.summary.localizedCaseInsensitiveContains(clean) ||
                 entry.tags.joined(separator: " ").localizedCaseInsensitiveContains(clean))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(ATHLTHLocalization.choose(english: "Workout type", norwegian: "Økttype"),
                           selection: $selectedCategory) {
                        Text(ATHLTHLocalization.choose(english: "All", norwegian: "Alle")).tag("all")
                        Text(ATHLTHLocalization.choose(english: "Strength", norwegian: "Styrke")).tag("strength")
                        Text(ATHLTHLocalization.choose(english: "Running", norwegian: "Løping")).tag("running")
                        Text(ATHLTHLocalization.choose(english: "Hybrid", norwegian: "Hybrid")).tag("hybrid")
                        Text(ATHLTHLocalization.choose(english: "Other", norwegian: "Annet")).tag("other")
                    }
                    .pickerStyle(.menu)
                }
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

                if !runningWorkouts.isEmpty {
                    Section(ATHLTHLocalization.choose(
                        english: "Running workouts", norwegian: "Løpeøkter"
                    )) {
                        ForEach(runningWorkouts) { workout in
                            Button {
                                onSelect(workout.plannedSession())
                                dismiss()
                            } label: {
                                workoutRow(
                                    title: workout.title,
                                    subtitle: workout.summary,
                                    icon: workout.type.systemImage
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !catalogWorkouts.isEmpty {
                    Section(ATHLTHLocalization.choose(
                        english: "Complete workout library",
                        norwegian: "Ferdige treningsøkter"
                    )) {
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
                    catalogWorkouts.isEmpty && runningWorkouts.isEmpty {
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

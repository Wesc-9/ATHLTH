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
                english: "HR zone Z\(targetHeartRateZone)",
                norwegian: "Pulssone S\(targetHeartRateZone)"
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

    func plannedSession(useOriginalID: Bool = false) -> PlannedSession {
        var result = PlannedSession(
            id: useOriginalID ? id : UUID(),
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
        fallbackCatalog + ATHLTHCuratedStrengthWorkouts.entries + ATHLTHPremiumStrengthSessions.entries + ATHLTHZonedPlanLibrary.workoutCatalogEntries + ATHLTHGymCoachStrengthLibrary.workoutCatalogEntries
    }
}

@MainActor
final class WorkoutTemplateCatalogStore: ObservableObject {
    @Published private(set) var entries: [WorkoutTemplateCatalogEntry]
    private let offlineEntries: [WorkoutTemplateCatalogEntry]
    @Published private(set) var isLoading = false
    /// Whether the catalogue contains live published data rather than the
    /// bundled HYROX-only fallback. Used by general Train suggestions.
    @Published private(set) var hasPublishedCatalog = false
    @Published private(set) var errorMessage: String?

    private let client: SupabaseClient
    private var loadedRemote = false
    private var lastRemoteRefreshAttemptAt: Date?

    init(client: SupabaseClient = SupabaseEnvironment.client) {
        self.client = client
        let baseline = WorkoutTemplateCatalogEntry.bundledCatalog
        self.offlineEntries = baseline
        self.entries = baseline
    }

    func refresh(force: Bool = false) async {
        if loadedRemote && !force { return }
        guard !isLoading else { return }

        // The Train Today view is recreated when switching Plan/Today.
        // If the catalog endpoint is unavailable, do not retry the same
        // network request on every tab switch: offline entries remain ready.
        if !force,
           let lastRemoteRefreshAttemptAt,
           Date().timeIntervalSince(lastRemoteRefreshAttemptAt) < 90 {
            return
        }
        lastRemoteRefreshAttemptAt = Date()

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
            let localOnly = offlineEntries
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
                entries = offlineEntries
            }
            errorMessage = error.localizedDescription
        }
    }
}

/// Shared bilingual, spacing-tolerant workout search. Original titles are never modified.
enum ATHLTHWorkoutSearch {
    static func normalized(_ value: String) -> String {
        let folded = value.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "nb_NO")
        ).replacingOccurrences(
            of: #"(?<=[0-9])\s*[x×]\s*(?=[0-9])"#,
            with: "x", options: .regularExpression
        )
        return folded.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func matches(_ query: String, texts: [String]) -> Bool {
        let needle = normalized(query)
        guard !needle.isEmpty else { return true }
        var candidates = texts
        if texts.contains(where: { normalized($0).contains("4x4") }) {
            candidates += [
                "4x4 intervals", "4x4 interval run", "4x4 intervaller",
                "norwegian 4x4", "norwegian 4x4 intervals",
                "4x4 training", "4x4 running"
            ]
        }
        return candidates.contains {
            let haystack = normalized($0)
            return haystack.contains(needle) ||
                haystack.replacingOccurrences(of: " ", with: "")
                    .contains(needle.replacingOccurrences(of: " ", with: ""))
        }
    }
}

/// Reuse the existing complete workout library when choosing a planned session.
/// Both Home calendar and Community select an independent editable session.
struct PlanWorkoutPickerView: View {
    let onSelect: (PlannedSession) -> Void

    var body: some View {
        NavigationStack {
            WorkoutTemplateLibraryView(onSelectPlanned: onSelect)
        }
    }
}

struct WorkoutTemplateLibraryView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var favorites: LibraryFavoritesStore
    @EnvironmentObject private var recents: LibraryRecentsStore
    @EnvironmentObject private var runningLibrary: RunningWorkoutLibraryStore

    /// Keeps legacy running templates available through the unified workout library.
    var onStartRunning: ((RunningWorkoutTemplate) -> Void)? = nil
    var onSelectPlanned: ((PlannedSession) -> Void)? = nil

    /// Optional category from the new premium planned-workout selector.
    /// Other library entry points continue to start with "All".
    var initialCategory: ATHLTHPlannedWorkoutType? = nil

    @StateObject private var catalog =
        WorkoutTemplateCatalogStore()
    @State private var query = ""
    @State private var selectedCategory = "All"
    @State private var favoritesOnly = false
    @State private var selectedMuscleFocus = "all"
    @State private var selectedWorkoutLevel = "all"
    @State private var selectedStrengthMuscles: Set<String> = []
    @State private var selectedRunningType: RunningWorkoutType?
    @State private var selectedRunningDuration:
        ATHLTHWorkoutDiscoveryFilter.Duration = .any
    @State private var selectedDiscoverySort: DiscoverySort = .recommended
    @State private var displayMode: ATHLTHLibraryDisplayMode = .list
    @State private var libraryViewWidth: CGFloat = 390

    private enum DiscoverySort: String, CaseIterable, Identifiable {
        case recommended, shortest, longest
        var id: String { rawValue }
        var title: String {
            switch self {
            case .recommended: return ATHLTHLocalization.choose(
                english: "Default order", norwegian: "Standard"
            )
            case .shortest: return ATHLTHLocalization.choose(
                english: "Shortest first", norwegian: "Kortest først"
            )
            case .longest: return ATHLTHLocalization.choose(
                english: "Longest first", norwegian: "Lengst først"
            )
            }
        }
    }
    @AppStorage("athlth.workoutPreview.advanced.v1") private var advancedMode = false
    @State private var pendingCatalogAddition: WorkoutTemplateCatalogEntry?
    @State private var pendingRunningAddition: RunningWorkoutTemplate?
    @State private var previewedWorkoutSource: SelectedWorkoutSource?
    @State private var workoutSourceAfterPreviewDismiss: SelectedWorkoutSource?

    /// All workout categories use the same recipe preview and editor.
    private enum SelectedWorkoutSource: Identifiable {
        case scheduled(PlannedSession)
        case saved(PlannedSession)
        case catalog(WorkoutTemplateCatalogEntry)
        case running(RunningWorkoutTemplate)

        var id: String {
            switch self {
            case .scheduled(let value): return "scheduled-\(value.id.uuidString)"
            case .saved(let value): return "saved-\(value.id.uuidString)"
            case .catalog(let value): return "catalog-\(value.id.uuidString)"
            case .running(let value): return "running-\(value.id.uuidString)"
            }
        }

        var workout: PlannedSession {
            switch self {
            case .scheduled(let value), .saved(let value): return value
            case .catalog(let value): return value.plannedSession()
            case .running(let value): return value.plannedSession()
            }
        }
    }

    @State private var showingPersonalizationQuestion = false
    @State private var showingCatalogPersonalization = false
    @State private var showingRunningPersonalization = false
    @State private var catalogPersonalBlocks: [WorkoutTemplateBlock] = []
    @State private var libraryCompletions: [StructuredWorkoutCompletion] = []
    @State private var runningCompletions: [ATHLTHCompletedRunningPerformance] = []

    /// Configure the library's initial category without changing its
    /// behaviour for the Home, Community and general Library entry points.
    init(
        onStartRunning: ((RunningWorkoutTemplate) -> Void)? = nil,
        onSelectPlanned: ((PlannedSession) -> Void)? = nil,
        initialCategory: ATHLTHPlannedWorkoutType? = nil
    ) {
        self.onStartRunning = onStartRunning
        self.onSelectPlanned = onSelectPlanned
        self.initialCategory = initialCategory
        _selectedCategory = State(
            initialValue: initialCategory?.catalogCategory ?? "All"
        )
    }

    private func loadHistory() {
        libraryCompletions = StructuredWorkoutCompletionStore.load(
            userID: session.profile.userID
        )
        runningCompletions = ATHLTHRunningPerformanceHistory.load(
            userID: session.profile.userID
        )
    }

    /// Library selection is shared by Plan and My Workouts. It must not
    /// automatically make a public recipe's targets the athlete's targets.
    private func addCatalogToPlan(
        _ entry: WorkoutTemplateCatalogEntry,
        blocks: [WorkoutTemplateBlock]
    ) {
        var source = entry.plannedSession()
        source.workoutBlocks = blocks
        let personalID = session.saveSharedWorkout(
            source, sourceSessionID: entry.id
        )
        onSelectPlanned?(session.savedWorkoutTemplates.first {
            $0.id == personalID
        } ?? source)
    }

    private func addRunningToPlan(_ source: RunningWorkoutTemplate) {
        let personal = runningLibrary.savedCopy(for: source) ??
            (source.isBuiltIn ? runningLibrary.duplicate(source) : source)
        onSelectPlanned?(personal.plannedSession())
    }

    private func chooseCatalogForPlan(_ entry: WorkoutTemplateCatalogEntry) {
        if let existing = session.savedWorkoutTemplates.first(where: {
            $0.workoutTemplateID == entry.id ||
                $0.sharedSourceSessionID == entry.id
        }) {
            onSelectPlanned?(existing)
            return
        }
        if ATHLTHWorkoutFirstUsePolicy.asksForTargets(
            advanced: advancedMode, hasPersonalCopy: false
        ) {
            pendingCatalogAddition = entry
            pendingRunningAddition = nil
            showingPersonalizationQuestion = true
        } else {
            addCatalogToPlan(entry, blocks:
                ATHLTHWorkoutLibraryPersonalization.blankTargets(entry.blocks))
        }
    }

    /// Keep target personalization and the common editor exactly as before:
    /// the preview is only a reading/confirmation step.
    private func confirmPreview(_ source: SelectedWorkoutSource) {
        // Dismiss the detail sheet *before* opening target personalization
        // or returning to the editor. Presenting both at once can lose taps.
        workoutSourceAfterPreviewDismiss = source
        previewedWorkoutSource = nil
    }

    private func completeConfirmedPreview(_ source: SelectedWorkoutSource) {
        switch source {
        case .scheduled(let workout), .saved(let workout):
            onSelectPlanned?(workout)
        case .catalog(let entry):
            chooseCatalogForPlan(entry)
        case .running(let workout):
            chooseRunningForPlan(workout)
        }
    }

    private func chooseRunningForPlan(_ source: RunningWorkoutTemplate) {
        guard source.isBuiltIn,
              ATHLTHWorkoutFirstUsePolicy.asksForTargets(
                advanced: advancedMode,
                hasPersonalCopy: runningLibrary.savedCopy(for: source) != nil
              ) else {
            addRunningToPlan(source)
            return
        }
        pendingRunningAddition = source
        pendingCatalogAddition = nil
        showingPersonalizationQuestion = true
    }

    private func saveFirstAdditionWithoutTargets() {
        if let entry = pendingCatalogAddition {
            addCatalogToPlan(entry, blocks:
                ATHLTHWorkoutLibraryPersonalization.blankTargets(entry.blocks))
        } else if let source = pendingRunningAddition {
            addRunningToPlan(source)
        }
        pendingCatalogAddition = nil
        pendingRunningAddition = nil
    }

    private let strengthFocuses = [
        "all", "chest", "back", "legs", "shoulders",
        "arms", "glutes", "fullbody", "core", "home"
    ]
    private let strengthLevels = ["all", "Beginner", "Intermediate", "Advanced", "Expert"]

    /// These are anatomical filters, not an additional strength library.
    /// The matching rules use published tags and embedded exercise muscles.
    private let strengthMuscleChoices = [
        "chest", "back", "shoulders", "arms", "legs", "glutes",
        "core", "fullbody", "biceps", "triceps", "quads",
        "hamstrings", "calves"
    ]

    private func toggleStrengthMuscle(_ muscle: String) {
        if selectedStrengthMuscles.contains(muscle) {
            selectedStrengthMuscles.remove(muscle)
        } else {
            selectedStrengthMuscles.insert(muscle)
        }
    }

    private func clearStrengthFilters() {
        selectedStrengthMuscles.removeAll()
        selectedWorkoutLevel = "all"
        selectedDiscoverySort = .recommended
    }

    private var discoveryFilter: ATHLTHWorkoutDiscoveryFilter {
        ATHLTHWorkoutDiscoveryFilter(
            muscleGroups: initialCategory == .strength
                ? selectedStrengthMuscles : [],
            runningType: initialCategory == .running
                ? selectedRunningType : nil,
            duration: initialCategory == .running
                ? selectedRunningDuration : .any
        )
    }

    private var hasDiscoveryFilters: Bool {
        !selectedStrengthMuscles.isEmpty ||
        selectedRunningType != nil ||
        selectedRunningDuration != .any ||
        selectedDiscoverySort != .recommended ||
        (initialCategory == .strength && selectedWorkoutLevel != "all")
    }

    private func discoverySorted<T>(
        _ items: [T], durationMinutes: (T) -> Double?
    ) -> [T] {
        guard initialCategory != nil,
              selectedDiscoverySort != .recommended else { return items }
        return items.enumerated().sorted { lhs, rhs in
            let a = durationMinutes(lhs.element)
            let b = durationMinutes(rhs.element)
            guard let a else { return false }
            guard let b else { return true }
            if a == b { return lhs.offset < rhs.offset }
            return selectedDiscoverySort == .shortest ? a < b : a > b
        }.map { $0.element }
    }

    private func focusName(_ focus: String) -> String {
        switch focus {
        case "chest": return ATHLTHLocalization.choose(english: "Chest", norwegian: "Bryst")
        case "back": return ATHLTHLocalization.choose(english: "Back", norwegian: "Rygg")
        case "legs": return ATHLTHLocalization.choose(english: "Legs", norwegian: "Bein")
        case "shoulders": return ATHLTHLocalization.choose(english: "Shoulders", norwegian: "Skuldre")
        case "arms": return ATHLTHLocalization.choose(english: "Arms", norwegian: "Armer")
        case "glutes": return ATHLTHLocalization.choose(english: "Glutes", norwegian: "Sete")
        case "fullbody": return ATHLTHLocalization.choose(english: "Full body", norwegian: "Fullkropp")
        case "core": return ATHLTHLocalization.choose(english: "Core", norwegian: "Kjerne")
        case "home": return ATHLTHLocalization.choose(english: "At home", norwegian: "Hjemme")
        case "biceps": return "Biceps"
        case "triceps": return "Triceps"
        case "quads": return ATHLTHLocalization.choose(english: "Quads", norwegian: "Forside lår")
        case "hamstrings": return ATHLTHLocalization.choose(english: "Hamstrings", norwegian: "Bakside lår")
        case "calves": return ATHLTHLocalization.choose(english: "Calves", norwegian: "Legger")
        default: return ATHLTHLocalization.choose(english: "All muscles", norwegian: "Alle muskelgrupper")
        }
    }

    private func levelName(_ level: String) -> String {
        switch level {
        case "Beginner": return ATHLTHLocalization.choose(english: "Beginner", norwegian: "Nybegynner")
        case "Intermediate": return ATHLTHLocalization.choose(english: "Intermediate", norwegian: "Middels")
        case "Advanced": return ATHLTHLocalization.choose(english: "Advanced", norwegian: "Avansert")
        case "Expert": return ATHLTHLocalization.choose(english: "Expert", norwegian: "Ekspert")
        default: return ATHLTHLocalization.choose(english: "All levels", norwegian: "Alle nivåer")
        }
    }

    private func levelMatches(_ entry: WorkoutTemplateCatalogEntry) -> Bool {
        guard selectedWorkoutLevel != "all" else { return true }
        let text = entry.difficulty.lowercased()
        let accepted = [selectedWorkoutLevel.lowercased(), levelName(selectedWorkoutLevel).lowercased()]
        return accepted.contains(text) || entry.tags.contains(selectedWorkoutLevel.lowercased())
    }

    private var categories: [String] {
        ["All"] +
        Array(Set(
            catalog.entries.map(\.categoryTitle) +
            ATHLTHPlannedWorkoutType.defaultOrder.map(\.catalogCategory)
        )).sorted()
    }

    private var builtInRunningTemplates: [RunningWorkoutTemplate] {
        // Workouts must also expose user-created running templates.
        runningLibrary.allTemplates
    }

    /// Built-in running workouts share the same search, category and favorite
    /// filters as catalog workouts, without creating another library section.
    private var filteredRunningTemplates: [RunningWorkoutTemplate] {
        guard (selectedCategory == "All" || selectedCategory == "Running") &&
                selectedMuscleFocus == "all" && selectedWorkoutLevel == "all"
        else { return [] }

        let clean = query
        let matching = builtInRunningTemplates.filter { workout in
            guard discoveryFilter.matches(workout) else { return false }
            let favoriteMatches =
                !favoritesOnly ||
                favorites.isFavorite(.workout, itemID: workout.id.uuidString)
            let searchMatches = ATHLTHWorkoutSearch.matches(
                clean, texts: [workout.title, workout.summary, workout.type.title]
            )
            return favoriteMatches && searchMatches
        }
        return discoverySorted(matching) {
            $0.estimatedDurationSeconds.map { $0 / 60 }
        }
    }

    private var filteredEntries:
        [WorkoutTemplateCatalogEntry] {
        let clean = query

        let matching = catalog.entries.filter { entry in
            guard discoveryFilter.matches(entry) else { return false }
            let categoryMatches =
                selectedCategory == "All" ||
                entry.categoryTitle == selectedCategory ||
                (selectedCategory == "Custom" &&
                 ATHLTHPlannedWorkoutType.custom.matches(entry))

            let favoriteMatches =
                !favoritesOnly ||
                favorites.isFavorite(
                    .workout,
                    itemID: entry.id.uuidString
                )

            let searchMatches = ATHLTHWorkoutSearch.matches(
                clean, texts: [entry.title, entry.summary, entry.categoryTitle,
                               entry.tags.joined(separator: " ")]
            )

            let muscleMatches = selectedMuscleFocus == "all" ||
                entry.tags.contains(selectedMuscleFocus)
            return categoryMatches &&
                favoriteMatches &&
                searchMatches && muscleMatches && levelMatches(entry)
        }
        return discoverySorted(matching) {
            $0.estimatedDurationMinutes.map(Double.init)
        }
    }

    private var filteredSavedWorkouts: [PlannedSession] {
        guard onSelectPlanned != nil else { return [] }
        let clean = query
        // Most library visits have no specialised filter. Only build the
        // publisher metadata index when a muscle/level/type filter needs it.
        let needMetadata = !selectedStrengthMuscles.isEmpty ||
            selectedRunningType != nil ||
            (initialCategory == .strength && selectedWorkoutLevel != "all")
        let originals: [UUID: WorkoutTemplateCatalogEntry] = needMetadata
            ? Dictionary(
                catalog.entries.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            ) : [:]
        let matching = session.savedWorkoutTemplates.filter { workout in
            let source = workout.workoutTemplateID.flatMap { originals[$0] } ??
                workout.sharedSourceSessionID.flatMap { originals[$0] }
            guard discoveryFilter.matches(workout, catalogEntry: source),
                  initialCategory != .strength ||
                    selectedWorkoutLevel == "all" ||
                    (source.map(levelMatches) ?? false)
            else { return false }
            let matchesCategory = selectedCategory == "All" ||
                (ATHLTHPlannedWorkoutType(
                    rawValue: selectedCategory.lowercased()
                )?.matches(workout) ??
                    (workout.kind.title == selectedCategory))
            return ATHLTHWorkoutSearch.matches(
                clean, texts: [workout.title, workout.notes ?? ""]
            ) && matchesCategory
        }
        return discoverySorted(matching) {
            $0.durationMinutes.map(Double.init)
        }
    }

    /// The original picker only exposed saved templates. "Bruk planlagt
    /// økt" also needs actual sessions from the calendar and active plans.
    private var filteredScheduledWorkouts: [PlannedSession] {
        guard onSelectPlanned != nil else { return [] }
        let clean = query
        let stored = session.standalonePlannedSessions +
            session.trainingPlans.flatMap { $0.weeks }
                .flatMap { $0.days }
                .flatMap { $0.sessions }
        var seen = Set<UUID>()
        // Most library visits have no specialised filter. Only build the
        // publisher metadata index when a muscle/level/type filter needs it.
        let needMetadata = !selectedStrengthMuscles.isEmpty ||
            selectedRunningType != nil ||
            (initialCategory == .strength && selectedWorkoutLevel != "all")
        let originals: [UUID: WorkoutTemplateCatalogEntry] = needMetadata
            ? Dictionary(
                catalog.entries.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            ) : [:]
        let matching = stored.filter { workout in
            let source = workout.workoutTemplateID.flatMap { originals[$0] } ??
                workout.sharedSourceSessionID.flatMap { originals[$0] }
            guard seen.insert(workout.id).inserted,
                  discoveryFilter.matches(workout, catalogEntry: source),
                  initialCategory != .strength ||
                    selectedWorkoutLevel == "all" ||
                    (source.map(levelMatches) ?? false)
            else { return false }
            let matchingType = ATHLTHPlannedWorkoutType(
                rawValue: selectedCategory.lowercased()
            )
            return (selectedCategory == "All" ||
                    (matchingType?.matches(workout) ??
                     (workout.kind.title == selectedCategory))) &&
                ATHLTHWorkoutSearch.matches(
                    clean, texts: [workout.title, workout.notes ?? ""]
                )
        }
        .sorted {
            ($0.scheduledStart ?? .distantPast) >
            ($1.scheduledStart ?? .distantPast)
        }
        return discoverySorted(matching) {
            $0.durationMinutes.map(Double.init)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                LibraryPremiumIntro(
                    eyebrow: initialCategory != nil
                        ? "ATHLTH · PLAN" : "WORKOUT LIBRARY",
                    title: initialCategory == .strength
                        ? ATHLTHLocalization.choose(
                            english: "Strength workouts", norwegian: "Styrkeøkter"
                          )
                        : initialCategory == .running
                            ? ATHLTHLocalization.choose(
                                english: "Running workouts", norwegian: "Løpeøkter"
                              )
                            : initialCategory?.title ?? "Complete workouts",
                    subtitle: initialCategory == .strength
                        ? ATHLTHLocalization.choose(
                            english: "Choose muscle groups and preview the actual exercises before planning.",
                            norwegian: "Velg muskelgrupper og se øvelsene før du planlegger."
                          )
                        : initialCategory == .running
                            ? ATHLTHLocalization.choose(
                                english: "Find intervals, easy runs or long runs. Filter and inspect each part.",
                                norwegian: "Finn intervaller, rolige turer eller langtur. Filtrer og se alle øktdelene."
                              )
                            : initialCategory != nil
                                ? ATHLTHLocalization.choose(
                                    english: "Explore and adapt an existing workout.",
                                    norwegian: "Finn og tilpass en eksisterende økt."
                                  )
                                : "A workout is the session you actually perform. It can combine running, exercises, rest, routes and targets in one structure.",
                    icon: "rectangle.stack.fill",
                    accent: ATHLTHPlanDesign.accentInk
                ) {
                    HStack(spacing: 8) {
                        LibraryStatPill(
                            value: "\(catalog.entries.count + builtInRunningTemplates.count)",
                            label: "workouts",
                            icon: "rectangle.stack.fill",
                            tint: ATHLTHPlanDesign.accentInk
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

                HStack {
                    Text(ATHLTHLocalization.choose(english: "View", norwegian: "Visning"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    Spacer()
                    ATHLTHLibraryDisplayPicker(selection: $displayMode)
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

                        if initialCategory == .strength {
                            // One compact, horizontally scrolling tab row beside
                            // Favorites instead of the old multi-row muscle grid.
                            Button {
                                selectedStrengthMuscles.removeAll()
                            } label: {
                                filterChip(
                                    ATHLTHLocalization.choose(
                                        english: "All", norwegian: "Alle"
                                    ),
                                    systemImage: nil,
                                    selected: selectedStrengthMuscles.isEmpty
                                )
                                .frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)

                            ForEach(strengthMuscleChoices, id: \.self) { muscle in
                                let selected = selectedStrengthMuscles.contains(muscle)
                                Button {
                                    toggleStrengthMuscle(muscle)
                                } label: {
                                    filterChip(
                                        focusName(muscle),
                                        systemImage: selected ? "checkmark" : nil,
                                        selected: selected
                                    )
                                    .frame(minHeight: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(
                                    selected ? [.isSelected] : []
                                )
                            }
                        }

                        if initialCategory == nil {
                        ForEach(categories, id: \.self) {
                            category in
                            Button {
                                selectedCategory = category
                                if category != "Strength" {
                                    selectedMuscleFocus = "all"
                                    selectedWorkoutLevel = "all"
                                }
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
                }

                if initialCategory == .strength {
                    strengthRefinementBar
                } else if initialCategory != nil {
                    activityDiscoveryFilters
                }

                if initialCategory == nil &&
                    (selectedCategory == "Strength" ||
                    selectedMuscleFocus != "all" ||
                    selectedWorkoutLevel != "all") {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(ATHLTHLocalization.choose(
                            english: "MUSCLE GROUP", norwegian: "MUSKELGRUPPE"
                        ))
                        .font(.caption2.weight(.semibold))
                        .tracking(1.1)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 7) {
                                ForEach(strengthFocuses, id: \.self) { focus in
                                    Button {
                                        selectedCategory = "Strength"
                                        selectedMuscleFocus = focus
                                    } label: {
                                        filterChip(
                                            focusName(focus),
                                            systemImage: nil,
                                            selected: selectedMuscleFocus == focus
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        Text(ATHLTHLocalization.choose(
                            english: "EXPERIENCE LEVEL", norwegian: "ERFARINGSNIVÅ"
                        ))
                        .font(.caption2.weight(.semibold))
                        .tracking(1.1)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 7) {
                                ForEach(strengthLevels, id: \.self) { level in
                                    Button {
                                        selectedCategory = "Strength"
                                        selectedWorkoutLevel = level
                                    } label: {
                                        filterChip(
                                            levelName(level),
                                            systemImage: nil,
                                            selected: selectedWorkoutLevel == level
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                if onSelectPlanned != nil && !filteredScheduledWorkouts.isEmpty {
                    Text(ATHLTHLocalization.choose(
                        english: "From your plans",
                        norwegian: "Fra dine planer"
                    ))
                    .font(.headline)
                    LazyVGrid(columns: libraryColumns, spacing: 10) {
                    ForEach(filteredScheduledWorkouts.prefix(50)) { workout in
                        Button {
                            if initialCategory != nil {
                                previewedWorkoutSource = .scheduled(workout)
                            } else {
                                onSelectPlanned?(workout)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 12) {
                                Image(systemName: workout.kind.systemImage)
                                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                    .frame(width: 36, height: 36)
                                    .background(ATHLTHTheme.accentSoft, in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(workout.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(ATHLTHPlanDesign.ink)
                                    Text(workout.kind.title)
                                        .font(.caption)
                                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            }
                                if initialCategory != nil && displayMode == .list {
                                    ATHLTHWorkoutContentsPreview(workout: workout)
                                }
                            }
                            .padding(14)
                            .background(.white,
                                        in: RoundedRectangle(cornerRadius: 17))
                        }
                        .buttonStyle(.plain)
                    }
                    }
                }

                if onSelectPlanned != nil && !filteredSavedWorkouts.isEmpty {
                    Text(ATHLTHLocalization.choose(english: "My workouts", norwegian: "Mine økter"))
                        .font(.headline)
                    LazyVGrid(columns: libraryColumns, spacing: 10) {
                    ForEach(filteredSavedWorkouts) { workout in
                        Button {
                            if initialCategory != nil {
                                previewedWorkoutSource = .saved(workout)
                            } else {
                                onSelectPlanned?(workout)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: workout.kind.systemImage)
                                    Text(workout.title)
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                }
                                if initialCategory != nil && displayMode == .list {
                                    ATHLTHWorkoutContentsPreview(workout: workout)
                                }
                            }
                            .padding(15)
                            .background(.white, in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                    }
                }
                if filteredEntries.isEmpty && filteredRunningTemplates.isEmpty &&
                   filteredSavedWorkouts.isEmpty && filteredScheduledWorkouts.isEmpty {
                    VStack(spacing: 14) {
                        ContentUnavailableView(
                            ATHLTHLocalization.choose(
                                english: "No matching workouts",
                                norwegian: "Ingen økter passer filtrene"
                            ),
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text(
                                ATHLTHLocalization.choose(
                                    english: "Try a different muscle group, run type or duration.",
                                    norwegian: "Prøv en annen muskelgruppe, økttype eller varighet."
                                )
                            )
                        )
                        if hasDiscoveryFilters {
                            Button(ATHLTHLocalization.choose(
                                english: "Clear filters", norwegian: "Nullstill filtre"
                            )) {
                                selectedStrengthMuscles = []
                                selectedRunningType = nil
                                selectedRunningDuration = .any
                                selectedWorkoutLevel = "all"
                                selectedDiscoverySort = .recommended
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(ATHLTHTheme.accentDeep)
                        }
                    }
                    .padding(.top, 25)
                } else {
                    LazyVGrid(columns: libraryColumns, spacing: 10) {
                    ForEach(filteredEntries) { entry in
                        ZStack(alignment: .topTrailing) {
                            Group {
                                if let onSelectPlanned {
                                Button {
                                    if initialCategory != nil {
                                        previewedWorkoutSource = .catalog(entry)
                                    } else {
                                        chooseCatalogForPlan(entry)
                                    }
                                } label: {
                                    catalogTile(entry)
                                }
                                .buttonStyle(.plain)
                            } else {
                                NavigationLink {
                                    WorkoutTemplateDetailView(entry: entry)
                                } label: {
                                    catalogTile(entry)
                                }
                                .buttonStyle(.plain)
                                }
                            }
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
                            Group {
                                if let onSelectPlanned {
                                Button {
                                    if initialCategory != nil {
                                        previewedWorkoutSource = .running(workout)
                                    } else {
                                        chooseRunningForPlan(workout)
                                    }
                                } label: {
                                    runningTile(workout)
                                }
                                .buttonStyle(.plain)
                            } else {
                                NavigationLink {
                                    RunningWorkoutDetailView(
                                        workout: workout,
                                        selectionTitle: nil,
                                        onSelect: nil,
                                        onStart: onStartRunning
                                    )
                                } label: {
                                    runningTile(workout)
                                }
                                .buttonStyle(.plain)
                                }
                            }
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
            }
            .padding(18)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(
            ATHLTHPremiumCanvas(
                accent: ATHLTHPlanDesign.accent.opacity(0.16)
            )
        )
        .navigationTitle(initialCategory?.title ?? ATHLTHLocalization.choose(
            english: "Workouts", norwegian: "Treningsøkter"
        ))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $query,
            prompt: ATHLTHLocalization.choose(english: "Search workouts", norwegian: "Søk etter treningsøkter")
        )
        .sheet(item: $previewedWorkoutSource, onDismiss: {
            if let source = workoutSourceAfterPreviewDismiss {
                workoutSourceAfterPreviewDismiss = nil
                completeConfirmedPreview(source)
            }
        }) { source in
            ATHLTHWorkoutSelectionPreviewSheet(workout: source.workout) {
                confirmPreview(source)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english: "Set personal workout targets now?",
                norwegian: "Vil du legge inn personlige øktmål nå?"
            ),
            isPresented: $showingPersonalizationQuestion,
            titleVisibility: .visible
        ) {
            Button(ATHLTHLocalization.choose(
                english: "Customize in Advanced", norwegian: "Tilpass i Avansert"
            )) {
                if let entry = pendingCatalogAddition {
                    catalogPersonalBlocks =
                        ATHLTHWorkoutLibraryPersonalization.blankTargets(entry.blocks)
                    showingCatalogPersonalization = true
                } else if pendingRunningAddition != nil {
                    showingRunningPersonalization = true
                }
            }
            Button(ATHLTHLocalization.choose(
                english: "Add without personal targets",
                norwegian: "Legg til uten personlige mål"
            )) {
                saveFirstAdditionWithoutTargets()
            }
            Button(ATHLTHLocalization.choose(
                english: "Cancel", norwegian: "Avbryt"
            ), role: .cancel) {
                pendingCatalogAddition = nil
                pendingRunningAddition = nil
            }
        } message: {
            Text(ATHLTHLocalization.choose(
                english: "Pace, heart-rate targets and incline are optional. Your library original stays unchanged.",
                norwegian: "Fart, pulsmål og stigning er valgfrie. Originaløkten i biblioteket endres ikke."
            ))
        }
        .sheet(isPresented: $showingCatalogPersonalization, onDismiss: {
            pendingCatalogAddition = nil
        }) {
            if let entry = pendingCatalogAddition {
                NavigationStack {
                    ScrollView {
                        ATHLTHWorkoutRecipePreview(
                            title: entry.title,
                            summary: entry.summary,
                            category: entry.category,
                            symbol: entry.systemImage,
                            difficulty: entry.difficulty,
                            durationMinutes: entry.estimatedDurationMinutes,
                            blocks: catalogPersonalBlocks,
                            onUpdateBlock: { index, updated in
                                guard catalogPersonalBlocks.indices.contains(index) else {
                                    return
                                }
                                catalogPersonalBlocks[index] = updated
                            }
                        )
                        .padding(18)
                    }
                    .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
                    .navigationTitle(ATHLTHLocalization.choose(
                        english: "Personal targets", norwegian: "Personlige øktmål"
                    ))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(ATHLTHLocalization.choose(
                                english: "Cancel", norwegian: "Avbryt"
                            )) {
                                showingCatalogPersonalization = false
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(ATHLTHLocalization.choose(
                                english: "Save and add", norwegian: "Lagre og legg til"
                            )) {
                                addCatalogToPlan(entry, blocks: catalogPersonalBlocks)
                                showingCatalogPersonalization = false
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingRunningPersonalization, onDismiss: {
            pendingRunningAddition = nil
        }) {
            if let source = pendingRunningAddition {
                ATHLTHTrainIntervalComposerView(initial: source) { personalized in
                    var saved = personalized
                    saved.sharedSourceWorkoutID = source.id
                    runningLibrary.save(saved)
                    onSelectPlanned?(saved.plannedSession())
                    showingRunningPersonalization = false
                }
            }
        }
        .onAppear {
            loadHistory()
            displayMode = .load(userID: session.profile.userID)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
            libraryViewWidth = width
        }
        .onChange(of: session.profile.userID) { _, userID in
            displayMode = .load(userID: userID)
        }
        .onChange(of: displayMode) { _, mode in
            mode.save(userID: session.profile.userID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .athlthTrainingDataDidChange)) { _ in
            loadHistory()
        }
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

    /// Extra strength filters stay on one small toolbar; muscle selection
    /// belongs to the horizontal Favorites/tab row above the results.
    private var strengthRefinementBar: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(strengthLevels, id: \.self) { level in
                    Button {
                        selectedWorkoutLevel = level
                    } label: {
                        if selectedWorkoutLevel == level {
                            Label(levelName(level), systemImage: "checkmark")
                        } else {
                            Text(levelName(level))
                        }
                    }
                }
            } label: {
                Label(
                    selectedWorkoutLevel == "all"
                        ? ATHLTHLocalization.choose(
                            english: "Experience", norwegian: "Erfaringsnivå"
                          )
                        : levelName(selectedWorkoutLevel),
                    systemImage: "slider.horizontal.3"
                )
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(ATHLTHPlanDesign.ink)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(.white.opacity(0.86), in: Capsule())
            }

            Spacer(minLength: 0)

            Picker(
                ATHLTHLocalization.choose(
                    english: "Sort workouts", norwegian: "Sorter økter"
                ),
                selection: $selectedDiscoverySort
            ) {
                ForEach(DiscoverySort.allCases) { sort in
                    Text(sort.title).tag(sort)
                }
            }
            .tint(ATHLTHPlanDesign.accentInk)

            if hasDiscoveryFilters {
                Button {
                    clearStrengthFilters()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Clear filters", norwegian: "Nullstill filtre"
                ))
            }
        }
    }

    @ViewBuilder
    private var activityDiscoveryFilters: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ATHLTHLocalization.choose(
                        english: "FIND THE RIGHT WORKOUT",
                        norwegian: "FINN RIKTIG ØKT"
                    ))
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(ATHLTHTheme.mutedText)

                    Text(initialCategory == .strength
                        ? ATHLTHLocalization.choose(
                            english: "Which muscles?", norwegian: "Hvilke muskelgrupper?"
                        )
                        : initialCategory == .running
                            ? ATHLTHLocalization.choose(
                                english: "What kind of run?", norwegian: "Hva slags løpeøkt?"
                              )
                            : ATHLTHLocalization.choose(
                                english: "Narrow your search", norwegian: "Finn økten du ønsker"
                              ))
                    .font(.title3.bold())
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                }
                Spacer(minLength: 5)
                if hasDiscoveryFilters {
                    Button(ATHLTHLocalization.choose(
                        english: "Clear filters", norwegian: "Nullstill"
                    )) {
                        selectedStrengthMuscles = []
                        selectedRunningType = nil
                        selectedRunningDuration = .any
                        selectedWorkoutLevel = "all"
                        selectedDiscoverySort = .recommended
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                }
            }

            if initialCategory == .running {
                Text(ATHLTHLocalization.choose(
                    english: "Workout type", norwegian: "Økttype"
                ))
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.mutedText)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button { selectedRunningType = nil } label: {
                            filterChip(
                                ATHLTHLocalization.choose(
                                    english: "All", norwegian: "Alle"
                                ),
                                systemImage: "figure.run",
                                selected: selectedRunningType == nil
                            )
                        }
                        .buttonStyle(.plain)
                        ForEach(RunningWorkoutType.allCases) { type in
                            Button { selectedRunningType = type } label: {
                                filterChip(
                                    type.title, systemImage: nil,
                                    selected: selectedRunningType == type
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Text(ATHLTHLocalization.choose(
                    english: "Duration", norwegian: "Varighet"
                ))
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.mutedText)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(ATHLTHWorkoutDiscoveryFilter.Duration.allCases) {
                            duration in
                            Button {
                                selectedRunningDuration = duration
                            } label: {
                                filterChip(
                                    duration.title, systemImage: nil,
                                    selected: selectedRunningDuration == duration
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if selectedRunningDuration != .any {
                    Text(ATHLTHLocalization.choose(
                        english: "Only workouts with a recorded duration can match a time filter.",
                        norwegian: "Kun økter med registrert varighet kan vises med tidsfilter."
                    ))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }
            }

            HStack {
                Text(ATHLTHLocalization.choose(
                    english: "Sort workouts", norwegian: "Sorter økter"
                ))
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.mutedText)
                Spacer()
                Picker(ATHLTHLocalization.choose(
                    english: "Sort", norwegian: "Sorter"
                ), selection: $selectedDiscoverySort) {
                    ForEach(DiscoverySort.allCases) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
                .tint(ATHLTHPlanDesign.accentInk)
            }
        }
        .padding(15)
        .background(
            ATHLTHTheme.accentSoft.opacity(0.3),
            in: RoundedRectangle(cornerRadius: 21)
        )
    }

    private var libraryColumns: [GridItem] {
        ATHLTHLibraryGridColumns.make(
            mode: displayMode,
            width: libraryViewWidth,
            reservedHorizontalSpace: 36,
            accessibilityText: dynamicTypeSize.isAccessibilitySize
        )
    }

    @ViewBuilder
    private func catalogTile(_ entry: WorkoutTemplateCatalogEntry) -> some View {
        if displayMode == .grid {
            workoutGridCard(
                title: entry.title,
                subtitle: entry.categoryTitle,
                symbol: entry.systemImage
            )
        } else {
            workoutCard(entry)
        }
    }

    @ViewBuilder
    private func runningTile(_ workout: RunningWorkoutTemplate) -> some View {
        if displayMode == .grid {
            workoutGridCard(
                title: workout.title,
                subtitle: workout.type.title,
                symbol: workout.type.systemImage
            )
        } else {
            runningWorkoutCard(workout)
        }
    }

    private func workoutGridCard(
        title: String, subtitle: String, symbol: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                .frame(width: 44, height: 44)
                .background(ATHLTHTheme.accentSoft,
                            in: RoundedRectangle(cornerRadius: 13))
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(ATHLTHPlanDesign.ink)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 164, alignment: .topLeading)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
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

                if initialCategory != nil {
                    ATHLTHWorkoutContentsPreview(
                        workout: entry.plannedSession()
                    )
                    .padding(.top, 7)
                }

                if let last = ATHLTHLibraryWorkoutHistory.catalogOriginal(
                    id: entry.id, completions: libraryCompletions
                ) {
                    ATHLTHLastWorkoutHistoryLabel(summary: last)
                        .padding(.top, 4)
                }
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
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                .frame(width: 50, height: 50)
                .background(
                    ATHLTHPlanDesign.accent.opacity(0.10),
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

                if initialCategory != nil {
                    ATHLTHWorkoutContentsPreview(
                        workout: workout.plannedSession()
                    )
                    .padding(.top, 7)
                }

                if let last = ATHLTHLibraryWorkoutHistory.running(
                    id: workout.id, records: runningCompletions
                ) {
                    ATHLTHLastWorkoutHistoryLabel(summary: last)
                        .padding(.top, 4)
                }
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
        default: return ATHLTHPlanDesign.accentInk
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
                ? ATHLTHPlanDesign.accentInk
                : Color.white.opacity(0.86),
            in: Capsule()
        )
    }
}

/// Explicit first-add choice; simple users never see a personalization prompt.
enum ATHLTHWorkoutFirstUsePolicy {
    static func asksForTargets(advanced: Bool, hasPersonalCopy: Bool) -> Bool {
        advanced && !hasPersonalCopy
    }
}

/// A library workout describes the structure, not the athlete's personal targets.
/// Leave time, prescribed repetitions and exercise names alone. Targets are
/// intentionally empty until the athlete saves them to My Workouts.
enum ATHLTHWorkoutLibraryPersonalization {
    static func blankTargets(_ blocks: [WorkoutTemplateBlock]) -> [WorkoutTemplateBlock] {
        blocks.map { original in
            var block = original
            block.targetPaceSecondsPerKilometer = nil
            block.treadmillInclinePercent = nil
            block.targetHeartRateZone = nil
            block.targetHeartRatePercentMin = nil
            block.targetHeartRatePercentMax = nil
            block.sourceIntensityZoneLabel = nil
            block.targetEffortRPE = nil
            block.targetWeightKilograms = nil
            block.loadNote = nil
            return block
        }
    }
}

struct WorkoutTemplateDetailView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var exerciseLibrary: ExerciseLibraryStore
    @EnvironmentObject private var phoneWorkout: IPhoneWorkoutStore
    @EnvironmentObject private var strengthWorkout: StrengthWorkoutStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore

    let entry: WorkoutTemplateCatalogEntry

    @AppStorage("athlth.workoutPreview.advanced.v1") private var advancedMode = false
    @State private var saved = false
    @State private var showingWorkout = false
    @State private var showingEditor = false
    @State private var askingForPersonalTargets = false
    @State private var editingPersonalTargets = false
    @State private var personalBlocks: [WorkoutTemplateBlock]?
    @State private var originalCompletions: [StructuredWorkoutCompletion] = []
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

    private var savedPersonalWorkout: PlannedSession? {
        session.savedWorkoutTemplates.first {
            $0.workoutTemplateID == entry.id || $0.sharedSourceSessionID == entry.id
        }
    }

    private var libraryDisplayBlocks: [WorkoutTemplateBlock] {
        // The original catalogue page never inherits personalized targets.
        ATHLTHWorkoutLibraryPersonalization.blankTargets(entry.blocks)
    }

    private var workoutForStarting: PlannedSession {
        // A stable source ID lets original completions remain separate from
        // personal My Workouts copies and their distinct session IDs.
        var original = entry.plannedSession(useOriginalID: true)
        original.workoutBlocks = libraryDisplayBlocks
        return original
    }

    private func savePersonalWorkout(blocks: [WorkoutTemplateBlock]) {
        var copy = entry.plannedSession()
        copy.workoutBlocks = blocks
        if let existing = savedPersonalWorkout {
            _ = session.updateSavedWorkoutTemplate(copy, id: existing.id)
        } else {
            _ = session.saveSharedWorkout(copy, sourceSessionID: entry.id)
        }
        saved = true
    }

    private func addToMyWorkouts() {
        if savedPersonalWorkout != nil {
            saved = true
        } else if ATHLTHWorkoutFirstUsePolicy.asksForTargets(
            advanced: advancedMode, hasPersonalCopy: false
        ) {
            askingForPersonalTargets = true
        } else {
            savePersonalWorkout(blocks:
                ATHLTHWorkoutLibraryPersonalization.blankTargets(entry.blocks))
        }
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
                    blocks: libraryDisplayBlocks
                )

                ATHLTHLastWorkoutHistoryCard(summary:
                    ATHLTHLibraryWorkoutHistory.catalogOriginal(
                        id: entry.id, completions: originalCompletions
                    )
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
                    addToMyWorkouts()
                } label: {
                    Label(
                        saved || savedPersonalWorkout != nil
                            ? tr("Saved in My Workouts", "Lagret i Mine økter")
                            : tr("Save to My Workouts", "Lagre i Mine økter"),
                        systemImage: saved ? "checkmark.circle.fill" : "square.and.arrow.down"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 51)
                }
                .buttonStyle(.bordered)
                .disabled(saved || savedPersonalWorkout != nil)

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
        .confirmationDialog(
            tr("Add personal workout targets?", "Vil du legge inn personlige øktmål?"),
            isPresented: $askingForPersonalTargets,
            titleVisibility: .visible
        ) {
            Button(tr("Enter pace and targets", "Legg inn fart og mål")) {
                personalBlocks = ATHLTHWorkoutLibraryPersonalization.blankTargets(entry.blocks)
                editingPersonalTargets = true
            }
            Button(tr("Save without personal targets", "Lagre uten personlige mål")) {
                savePersonalWorkout(
                    blocks: ATHLTHWorkoutLibraryPersonalization.blankTargets(entry.blocks)
                )
            }
            Button(tr("Cancel", "Avbryt"), role: .cancel) {}
        } message: {
            Text(tr(
                "You can set pace, heart-rate zone, incline and other personal targets now, or add them later. The original workout will not change.",
                "Du kan legge inn tempo, pulssone, stigning og andre egne mål nå eller senere. Originaløkten endres ikke."
            ))
        }
        .sheet(isPresented: $editingPersonalTargets) {
            NavigationStack {
                ScrollView {
                    ATHLTHWorkoutRecipePreview(
                        title: entry.title,
                        summary: entry.summary,
                        category: entry.category,
                        symbol: entry.systemImage,
                        difficulty: entry.difficulty,
                        durationMinutes: entry.estimatedDurationMinutes,
                        blocks: personalBlocks ?? [],
                        onUpdateBlock: { index, updated in
                            guard var draft = personalBlocks, draft.indices.contains(index) else {
                                return
                            }
                            draft[index] = updated
                            personalBlocks = draft
                        }
                    )
                    .padding(18)
                }
                .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
                .navigationTitle(tr("Personal targets", "Personlige øktmål"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(tr("Cancel", "Avbryt")) {
                            editingPersonalTargets = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(tr("Save workout", "Lagre økt")) {
                            guard let personalBlocks else { return }
                            savePersonalWorkout(blocks: personalBlocks)
                            editingPersonalTargets = false
                        }
                    }
                }
            }
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
            StructuredWorkoutSessionView(workout: workoutForStarting)
                .environmentObject(session)
        }
        .onAppear {
            originalCompletions = StructuredWorkoutCompletionStore.load(
                userID: session.profile.userID
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .athlthTrainingDataDidChange)) { _ in
            originalCompletions = StructuredWorkoutCompletionStore.load(
                userID: session.profile.userID
            )
        }
        .sheet(isPresented: $showingEditor) {
            WorkoutTemplateBuilderView(
                initialTitle: entry.title,
                initialBlocks: libraryDisplayBlocks,
                draftContext: "catalog-copy-\(entry.slug)",
                sourceTemplateID: entry.id
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var runningLibrary: RunningWorkoutLibraryStore

    @State private var completionHistory:
        [StructuredWorkoutCompletion] = []
    @State private var runningCompletionHistory:
        [ATHLTHCompletedRunningPerformance] = []

    private func refreshHistory() {
        completionHistory = StructuredWorkoutCompletionStore.load(
            userID: session.profile.userID
        )
        runningCompletionHistory = ATHLTHRunningPerformanceHistory.load(
            userID: session.profile.userID
        )
    }

    @State private var showingRunningBuilder = false
    @State private var showingHybridBuilder = false
    @State private var displayMode: ATHLTHLibraryDisplayMode = .list
    @State private var libraryViewWidth: CGFloat = 390

    private var libraryColumns: [GridItem] {
        ATHLTHLibraryGridColumns.make(
            mode: displayMode,
            width: libraryViewWidth,
            reservedHorizontalSpace: 36,
            accessibilityText: dynamicTypeSize.isAccessibilitySize
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(ATHLTHLocalization.choose(
                        english: "View", norwegian: "Visning"
                    ))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    Spacer()
                    ATHLTHLibraryDisplayPicker(selection: $displayMode)
                }
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
                    LazyVGrid(columns: libraryColumns, spacing: 10) {
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
                                VStack(alignment: .trailing, spacing: 5) {
                                    Text("\(workout.blocks.count) " +
                                         ATHLTHLocalization.choose(
                                             english: "phases", norwegian: "deler"
                                         ))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let last = ATHLTHLibraryWorkoutHistory.running(
                                        id: workout.id, records: runningCompletionHistory
                                    ) {
                                        ATHLTHLastWorkoutHistoryLabel(summary: last)
                                    }
                                }
                                Image(systemName: "chevron.right")
                            }
                            .padding(14)
                            .frame(minHeight: ATHLTHPlanDesign.minTapHeight)
                            .athlthPlanCard(radius: 18)
                        }
                        .buttonStyle(.plain)
                    }
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
                    LazyVGrid(columns: libraryColumns, spacing: 10) {
                        ForEach(session.savedWorkoutTemplates) { workout in
                            savedWorkoutCard(workout)
                        }
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
        .onAppear {
            refreshHistory()
            displayMode = .load(userID: session.profile.userID)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
            libraryViewWidth = width
        }
        .onChange(of: session.profile.userID) { _, id in
            displayMode = .load(userID: id)
        }
        .onChange(of: displayMode) { _, mode in
            mode.save(userID: session.profile.userID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .athlthTrainingDataDidChange)) { _ in
            refreshHistory()
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
                        .lineLimit(displayMode == .grid ? 2 : 3)

                    Text(savedWorkoutSubtitle(workout))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let last = ATHLTHLibraryWorkoutHistory.savedWorkout(
                        id: workout.id, completions: completionHistory
                    ) {
                        ATHLTHLastWorkoutHistoryLabel(summary: last)
                            .padding(.top, 4)
                    }
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

            if workout.isStructuredWorkout && displayMode == .list {
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
    @State private var showingStudioRoutePicker = false
    @State private var showingStudioRouteBuilder = false
    @State private var showingStudioStepEditor = false
    @State private var studioEditedStepID: UUID?
    @State private var studioRoutePhase: WorkoutPhaseKind = .main
    @State private var studioVisiblePhases: Set<WorkoutPhaseKind> = []
    @State private var studioAdvanced = true
    @State private var studioBasicRunMode: RunQuickStartMode = .free
    @State private var studioBasicRunEnvironment: RunEnvironment = .outdoor
    @State private var studioBasicDate = Date()
    @State private var studioBasicOwnedBlockIDs: Set<UUID> = []
    @State private var studioBasicWorkoutTitle: String?
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
    private let draftContext: String
    private let sourceTemplateID: UUID?
    private let initialQuickAdd: String?
    private let initialFocusedBlockIndex: Int?
    private let initialFocusedExecutionStepIndex: Int?
    private let plannedDate: Date?
    private let initialActivity: ATHLTHPlannedWorkoutType?
    private let onScheduledTimeChanged: ((Date) -> Void)?
    private let planCopyDays: [ATHLTHPlanCopyDay]
    private let onCopyToPlan: ((String, [WorkoutTemplateBlock], UUID?, Int?, [Int]) -> Bool)?
    private let initialDraftSignature: String
    /// Present from advanced plan creation to edit a specific weekday
    /// without creating an unwanted shared workout template.
    private let onSaveToPlan: ((String, [WorkoutTemplateBlock], UUID?, Int?, Bool) -> Bool)?
    /// Used by Coach's Add flow: schedule an edited workout without
    /// automatically saving a template in My Workouts.
    private let onAddStandalone: ((PlannedSession) -> Bool)?
    private let onValidateSave: ((PlannedSession) -> String?)?
    private let saveButtonTitle: String?

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
        sourceTemplateID: UUID? = nil,
        plannedDate: Date? = nil,
        initialActivity: ATHLTHPlannedWorkoutType? = nil,
        initialStudioAdvanced: Bool? = nil,
        onScheduledTimeChanged: ((Date) -> Void)? = nil,
        planCopyDays: [ATHLTHPlanCopyDay] = [],
        initialCopyWeekIndex: Int = 0,
        onCopyToPlan: ((String, [WorkoutTemplateBlock], UUID?, Int?, [Int]) -> Bool)? = nil,
        onSaveToPlan: ((String, [WorkoutTemplateBlock], UUID?, Int?, Bool) -> Bool)? = nil,
        onAddStandalone: ((PlannedSession) -> Bool)? = nil,
        onValidateSave: ((PlannedSession) -> String?)? = nil,
        saveButtonTitle: String? = nil
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
        self.sourceTemplateID = sourceTemplateID
        self.initialQuickAdd = initialQuickAdd
        self.initialFocusedBlockIndex = initialFocusedBlockIndex
        self.initialFocusedExecutionStepIndex = initialFocusedExecutionStepIndex
        self.plannedDate = plannedDate
        self.initialActivity = initialActivity
        self.onScheduledTimeChanged = onScheduledTimeChanged
        _studioAdvanced = State(initialValue:
            initialStudioAdvanced ?? (initialActivity == nil))
        _studioBasicRunMode = State(initialValue:
            initialRouteID != nil ? .route :
            initialBlocks.count > 1 ? .structured : .free
        )
        let firstRun = initialBlocks.first { $0.kind == .run }
        _studioBasicRunEnvironment = State(initialValue:
            firstRun?.isIndoor == true
                ? (firstRun?.treadmillInclinePercent != nil ? .treadmill : .indoor)
                : .outdoor
        )
        _studioBasicDate = State(initialValue: plannedDate ?? Date())
        self.planCopyDays = planCopyDays
        self.onCopyToPlan = onCopyToPlan
        _copyWeekIndex = State(initialValue: initialCopyWeekIndex)
        let originalBlocks = (try? JSONEncoder().encode(initialBlocks))?.base64EncodedString() ?? ""
        self.initialDraftSignature = initialTitle + "|" + originalBlocks +
            "|" + (initialRouteID?.uuidString ?? "") +
            "|" + String(initialDurationOverrideMinutes ?? -1)
        self.onSaveToPlan = onSaveToPlan
        self.onAddStandalone = onAddStandalone
        self.onValidateSave = onValidateSave
        self.saveButtonTitle = saveButtonTitle
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
    private var isPlannedWorkout: Bool {
        onSaveToPlan != nil || onAddStandalone != nil
    }
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
        let routeDistanceGoal = selectedRouteID != nil &&
            blocks.contains { $0.kind == .run &&
                ($0.distanceMeters ?? 0) > 0 &&
                $0.isIndoor != true }
        // A distance-based outdoor route is a complete planned workout,
        // even without an estimated finishing time.
        let basicFreeRun = isPlannedWorkout && !studioAdvanced &&
            initialActivity == .running && studioBasicRunMode == .free
        return (hasRunning || hasStrength || hasCycling ||
                hasTimedWellness || basicFreeRun) &&
            !hasIncompleteSuperset &&
            (!isPlannedWorkout || resolvedDurationMinutes != nil ||
             routeDistanceGoal || basicFreeRun)
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
                VStack(alignment: .leading, spacing: 16) {
                    if isPlannedWorkout {
                        if !studioAdvanced && initialActivity == .running {
                            ATHLTHRunBasicSetupView(
                                workoutName: $title,
                                mode: $studioBasicRunMode,
                                environment: $studioBasicRunEnvironment,
                                date: $studioBasicDate,
                                scheduleEditable: true,
                                selectedRouteTitle: session.savedRoutes.first {
                                    $0.id == selectedRouteID
                                }?.title,
                                selectedWorkoutTitle: studioBasicWorkoutTitle,
                                onChooseRoute: {
                                    studioRoutePhase = .main
                                    showingStudioRoutePicker = true
                                },
                                onChooseWorkout: {
                                    selectedPhase = .main
                                    showingSavedWorkoutPicker = true
                                }
                            )
                            if blocks.count > 0 {
                                Text(ATHLTHLocalization.format(
                                    english: "%d workout steps selected",
                                    norwegian: "%d deløkter valgt",
                                    blocks.count
                                ))
                                .font(.caption)
                                .foregroundStyle(studioInk.opacity(0.65))
                            }
                        } else {
                            ATHLTHPlannedWorkoutStudioHeader(
                                workoutName: $title,
                                activity: initialActivity,
                                blocks: blocks,
                                durationMinutes: resolvedDurationMinutes,
                                route: session.savedRoutes.first { $0.id == selectedRouteID },
                                plannedDate: plannedDate,
                                onDateChanged: onScheduledTimeChanged
                            )
                            plannedStudio
                        }
                        if let actionNotice {
                            Label(actionNotice, systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(studioAccent)
                        }
                    } else {
                        if let plannedDate {
                            Label(
                                plannedDate.formatted(.dateTime.day().month().year()),
                                systemImage: "calendar"
                            )
                        }
                        workoutOverview
                        durationSettings
                        timeline
                    }
                    if draftNotice {
                        Label(tr("Recovered saved draft", "Gjenopprettet lagret utkast"),
                              systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(studioAccent)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 28)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(studioBackground.ignoresSafeArea())
            .onChange(of: studioBasicDate) { _, value in
                if !studioAdvanced && initialActivity == .running {
                    onScheduledTimeChanged?(value)
                }
            }
            .onChange(of: studioBasicRunEnvironment) { _, place in
                guard isPlannedWorkout, initialActivity == .running else { return }
                for index in blocks.indices where blocks[index].kind == .run {
                    blocks[index].isIndoor = place != .outdoor
                    blocks[index].treadmillInclinePercent =
                        place == .treadmill ? 0 : nil
                }
                if place != .outdoor && studioBasicRunMode == .route {
                    studioBasicRunMode = .free
                    selectedRouteID = nil
                }
            }
            .onChange(of: studioBasicRunMode) { _, mode in
                guard isPlannedWorkout, !studioAdvanced,
                      initialActivity == .running else { return }
                // Only content added by the previous Basic selection is
                // cleared; pre-existing edited exercise rows are preserved.
                removeBasicOwnedBlocks()
                if mode != .route { selectedRouteID = nil }
                if mode != .structured { studioBasicWorkoutTitle = nil }
            }
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
                if isPlannedWorkout {
                    WorkoutTemplateLibraryView(
                        onSelectPlanned: { workout in
                            appendSavedWorkout(workout)
                            if !studioAdvanced && initialActivity == .running {
                                studioBasicWorkoutTitle = workout.title
                            }
                            showingSavedWorkoutPicker = false
                        },
                        initialCategory: initialActivity
                    )
                } else {
                    savedWorkoutPickerSheet
                }
            }
            .sheet(isPresented: $showingStudioRoutePicker) {
                SavedRoutesView(
                    selectionTitle: tr("Choose route", "Velg rute")
                ) { route in
                    useRoute(route, in: studioRoutePhase)
                    showingStudioRoutePicker = false
                }
            }
            .sheet(isPresented: $showingStudioRouteBuilder) {
                RunRouteBuilderView(onRouteSaved: {
                    guard let route = session.savedRoutes.max(by: {
                        $0.createdAt < $1.createdAt
                    }) else { return }
                    useRoute(route, in: studioRoutePhase)
                })
            }
            .sheet(isPresented: $showingStudioStepEditor) {
                NavigationStack {
                    ScrollView {
                        if let id = studioEditedStepID,
                           let index = blocks.firstIndex(where: {
                               $0.editorDragID == id
                           }) {
                            VStack(alignment: .leading, spacing: 15) {
                                Text(ATHLTHWorkoutNameSuggestion.displayStepTitle(blocks[index]))
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(studioInk)
                                blockDetails(index)
                            }
                            .padding(18)
                        }
                    }
                    .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
                    .navigationTitle(tr("Edit step", "Rediger deløkt"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(tr("Done", "Ferdig")) {
                                showingStudioStepEditor = false
                            }
                        }
                    }
                }
                .presentationDetents([.large])
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
                if isPlannedWorkout {
                    ToolbarItem(placement: .confirmationAction) {
                        ATHLTHPlannerModeSwitch(advanced: $studioAdvanced)
                    }
                }
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
                if !isPlannedWorkout, !draftRestored,
                   !initialQuickAddConsumed, let initialQuickAdd {
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

    // Replaces the old fixed warmup/main/cooldown selector AND the second
    // legacy timeline on planned workouts. Only one phase/step UI exists.
    private var plannedStudio: some View {
        ATHLTHPlannedWorkoutStudioView(
            blocks: $blocks,
            visiblePhases: $studioVisiblePhases,
            selectedPhase: $selectedPhase,
            advanced: studioAdvanced,
            activity: initialActivity,
            hasSelectedRoute: selectedRouteID != nil,
            onAddRun: { phase in
                selectedPhase = phase
                studioVisiblePhases.insert(phase)
                switch initialActivity {
                case .strength:
                    openExercisePicker()
                case .walking:
                    addRunBlock(activity: .walking)
                case .cycling:
                    addCyclingBlock()
                case .mobility:
                    addWellnessBlock(.stretching)
                default:
                    addRunBlock()
                }
            },
            onAddIntervals: { phase in
                selectedPhase = phase
                studioVisiblePhases.insert(phase)
                let existingGroups = Set(blocks.compactMap(\.groupID))
                createIntervals()
                // Only individualize the NEW interval group. A warm-up
                // insert must never unexpectedly rewrite a later group.
                if let id = blocks.first(where: {
                    $0.groupKind == .intervals &&
                    $0.groupID.map { !existingGroups.contains($0) } == true
                })?.groupID,
                   let individual = ATHLTHIntervalGroupEditing.individualSteps(
                    in: blocks, groupID: id
                   ) {
                    blocks = individual
                }
            },
            onAddExercise: { phase in
                selectedPhase = phase
                studioVisiblePhases.insert(phase)
                openExercisePicker()
            },
            onAddRest: { phase in
                selectedPhase = phase
                studioVisiblePhases.insert(phase)
                addRestBlock()
            },
            onAddActiveRest: { phase in
                selectedPhase = phase
                studioVisiblePhases.insert(phase)
                addActiveRecoveryBlock()
            },
            onAddWorkout: { phase in
                selectedPhase = phase
                studioVisiblePhases.insert(phase)
                showingSavedWorkoutPicker = true
            },
            onSelectRoute: { phase in
                selectedPhase = phase
                studioRoutePhase = phase
                showingStudioRoutePicker = true
            },
            onBuildRoute: { phase in
                selectedPhase = phase
                studioRoutePhase = phase
                showingStudioRouteBuilder = true
            },
            onEdit: { id in
                studioEditedStepID = id
                showingStudioStepEditor = true
            },
            onMove: { id, phase, targetID in
                moveStudioBlock(id, to: phase, before: targetID)
            },
            onRemove: { id in
                guard let index = blocks.firstIndex(where: {
                    $0.editorDragID == id
                }) else { return }
                let groupID = blocks[index].groupID
                blocks.remove(at: index)
                if let groupID,
                   blocks.filter({ $0.groupID == groupID }).count < 2 {
                    for i in blocks.indices where blocks[i].groupID == groupID {
                        blocks[i].groupID = nil
                        blocks[i].groupKind = nil
                        blocks[i].groupRounds = nil
                    }
                }
                resequence()
            }
        )
    }

    private func removeBasicOwnedBlocks() {
        guard !studioBasicOwnedBlockIDs.isEmpty else { return }
        blocks.removeAll { studioBasicOwnedBlockIDs.contains($0.editorDragID) }
        studioBasicOwnedBlockIDs.removeAll()
        resequence()
    }

    private func useRoute(_ route: TrainingRoute, in phase: WorkoutPhaseKind) {
        selectedPhase = phase
        if isPlannedWorkout && !studioAdvanced && initialActivity == .running {
            removeBasicOwnedBlocks()
        }
        let previousRoute = session.savedRoutes.first { $0.id == selectedRouteID }
        let existingRouteBlockIndex = previousRoute.flatMap { previous in
            blocks.firstIndex(where: {
                $0.title == previous.title && $0.kind == .run
            })
        }
        // A route can be the entire workout with no mandatory phase header.
        // If the user has already added parts, the route joins the chosen part.
        let directRoute = blocks.isEmpty && studioVisiblePhases.isEmpty
            && phase == .main
        selectedRouteID = route.id
        if !directRoute { studioVisiblePhases.insert(phase) }
        if let existingRouteBlockIndex {
            blocks[existingRouteBlockIndex].title = route.title
            blocks[existingRouteBlockIndex].distanceMeters =
                route.distanceKilometers * 1_000
            blocks[existingRouteBlockIndex].phase = phase
            blocks[existingRouteBlockIndex].durationSeconds = nil
            resequence()
            return
        }
        var routeRun = WorkoutTemplateBlock(
            sequence: 0, kind: .run, title: route.title,
            exerciseSlug: nil,
            distanceMeters: route.distanceKilometers * 1_000,
            repetitions: nil, durationSeconds: nil,
            targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: phase
        )
        routeRun.cardioActivity = initialActivity == .walking ? .walking : .running
        routeRun.isIndoor = false
        insertBlock(routeRun, toGroup: nil)
        if isPlannedWorkout && !studioAdvanced &&
            initialActivity == .running, let added = blocks.last {
            studioBasicOwnedBlockIDs.insert(added.editorDragID)
        }
    }

    private func moveStudioBlock(
        _ id: UUID, to phase: WorkoutPhaseKind, before targetID: UUID?
    ) {
        let moved = ATHLTHStudioBlockReorder.moving(
            id, to: phase, over: targetID, in: blocks
        )
        guard moved.map(\.editorDragID) != blocks.map(\.editorDragID)
                || moved != blocks else { return }
        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.86)) {
            blocks = moved
            expandedBlockIndex = nil
        }
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
                ATHLTHPlannedRunStepEditor(block: $blocks[index])
                if !isPlannedWorkout && blocks[index].isIndoor != true {
                    routeSection
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
                ATHLTHPlannedIntensityEditor(block: $blocks[index])
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
        let source = workout.resolvedWorkoutBlocks
        guard !source.isEmpty else { return }
        if isPlannedWorkout && !studioAdvanced && initialActivity == .running {
            removeBasicOwnedBlocks()
        }
        var newGroups: [UUID: UUID] = [:]
        let insertAt = ATHLTHWorkoutPhasePlacement.insertionIndex(
            for: selectedPhase, in: blocks
        )
        let copied = source.map { original -> WorkoutTemplateBlock in
            var copy = original
            copy.editorDragID = UUID()
            copy.phase = selectedPhase
            if let id = original.groupID {
                if newGroups[id] == nil { newGroups[id] = UUID() }
                copy.groupID = newGroups[id]
            }
            return copy
        }
        blocks.insert(contentsOf: copied, at: insertAt)
        if isPlannedWorkout && !studioAdvanced && initialActivity == .running {
            studioBasicOwnedBlockIDs.formUnion(copied.map(\.editorDragID))
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
            if !isPlannedWorkout {
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
            }

            Button {
                saveWorkout()
            } label: {
                Label(saveButtonTitle ?? (isPlannedWorkout
                    ? tr("Save and continue", "Lagre og gå videre")
                    : tr("Save workout", "Lagre treningsøkt")),
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

    private var basicFreeRunningKind: WorkoutKind {
        if isPlannedWorkout && !studioAdvanced &&
           initialActivity == .running && studioBasicRunMode == .free &&
           blocks.isEmpty {
            return .running
        }
        return resolvedWorkoutKind
    }

    private func workoutSnapshot() -> PlannedSession {
        let requestedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let suggestedBasicTitle: String = {
            guard isPlannedWorkout && !studioAdvanced,
                  initialActivity == .running else { return categoryTitle }
            switch studioBasicRunMode {
            case .free: return RunQuickStartMode.free.title
            case .route:
                return session.savedRoutes.first { $0.id == selectedRouteID }?.title
                    ?? RunQuickStartMode.route.title
            case .structured:
                return blocks.first?.title ?? RunQuickStartMode.structured.title
            }
        }()
        let suggestedAdvancedTitle = ATHLTHWorkoutNameSuggestion.suggested(
            activity: initialActivity,
            blocks: blocks,
            durationMinutes: resolvedDurationMinutes,
            routeTitle: session.savedRoutes.first { $0.id == selectedRouteID }?.title
        )
        let fallbackTitle = isPlannedWorkout && studioAdvanced
            ? suggestedAdvancedTitle : suggestedBasicTitle
        let cleanTitle = requestedTitle.isEmpty ? fallbackTitle : requestedTitle

        var workout = PlannedSession(
            id: UUID(),
            title: cleanTitle,
            kind: basicFreeRunningKind,
            scheduledStart: nil,
            durationMinutes: resolvedDurationMinutes,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: hasOutdoorCardio ? selectedRouteID : nil,
            exercises: [],
            notes: nil
        )
        workout.workoutBlocks = blocks
        if isPlannedWorkout, initialActivity == .running, !studioAdvanced {
            switch studioBasicRunEnvironment {
            case .outdoor: workout.workoutCategory = "running"
            case .indoor: workout.workoutCategory = "indoor"
            case .treadmill: workout.workoutCategory = "treadmill"
            }
        } else {
            workout.workoutCategory = category
        }
        return workout
    }

    private func saveWorkout() {
        guard canSave else { return }
        let workout = workoutSnapshot()
        if let issue = onValidateSave?(workout) {
            actionNotice = issue
            return
        }
        let cleanTitle = workout.title
        if let onAddStandalone {
            guard onAddStandalone(workout) else {
                actionNotice = tr("Cannot add this workout yet",
                                  "Kunne ikke legge til økten ennå")
                return
            }
        } else if let onSaveToPlan {
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
            if let sourceTemplateID {
                var personalized = workout
                personalized.workoutTemplateID = sourceTemplateID
                session.saveSharedWorkout(
                    personalized, sourceSessionID: sourceTemplateID
                )
            } else {
                session.saveSharedWorkout(workout)
            }
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
    private func durationEntryEditor(_ index: Int) -> some View {
        ATHLTHPlannedDurationEditor(durationSeconds: $blocks[index].durationSeconds)
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




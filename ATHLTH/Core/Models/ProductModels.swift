import CoreLocation
import Foundation

enum SubscriptionTier: String, Codable, CaseIterable, Identifiable, Hashable {
    case free
    case paid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free: return ATHLTHLocalization.string( "Free")
        case .paid: return "ATHLTH+"
        }
    }
}

enum SubscriptionAccessState: String, Codable, Hashable {
    case free
    case trial
    case paid
    case expired
    case revoked

    var title: String {
        switch self {
        case .free: return ATHLTHLocalization.string( "Free")
        case .trial: return ATHLTHLocalization.string( "ATHLTH+ trial")
        case .paid: return "ATHLTH+"
        case .expired: return ATHLTHLocalization.string( "ATHLTH+ expired")
        case .revoked: return ATHLTHLocalization.string( "ATHLTH+ revoked")
        }
    }
}

enum SubscriptionLifecycleState: String, Codable, Hashable {
    case free
    case trial
    case active
    case expired
    case revoked

    var title: String {
        switch self {
        case .free: return ATHLTHLocalization.string( "Free")
        case .trial: return ATHLTHLocalization.string( "ATHLTH+ trial")
        case .active: return "ATHLTH+"
        case .expired: return ATHLTHLocalization.string( "ATHLTH+ expired")
        case .revoked: return ATHLTHLocalization.string( "ATHLTH+ revoked")
        }
    }
}

enum SubscriptionAccessSource: String, Codable, Hashable {
    case none
    case athlthTrial
    case appStore
    case serverVerified
    case ownerOverride
}

enum ATHLTHFeature: Hashable, CaseIterable {
    case backgroundHealthSync
    case advancedTrainingPlans
    case advancedRecovery
    case aiTrainingPrograms
    case audioCoach
    case appleCalendarSync

    var requiresATHLTHPlus: Bool {
        switch self {
        case .aiTrainingPrograms,
             .audioCoach,
             .appleCalendarSync:
            return true
        case .backgroundHealthSync,
             .advancedTrainingPlans,
             .advancedRecovery:
            return false
        }
    }
}

struct SubscriptionAccess: Codable, Hashable {
    var state: SubscriptionAccessState
    var trialStartedAt: Date?
    var trialEndsAt: Date?
    var source: SubscriptionAccessSource?
    var productID: String?
    var currentPeriodEndsAt: Date?

    init(
        state: SubscriptionAccessState,
        trialStartedAt: Date? = nil,
        trialEndsAt: Date? = nil,
        source: SubscriptionAccessSource? = nil,
        productID: String? = nil,
        currentPeriodEndsAt: Date? = nil
    ) {
        self.state = state
        self.trialStartedAt = trialStartedAt
        self.trialEndsAt = trialEndsAt
        self.source = source
        self.productID = productID
        self.currentPeriodEndsAt = currentPeriodEndsAt
    }

    static let free = SubscriptionAccess(
        state: .free,
        source: SubscriptionAccessSource.none
    )

    var trialIsActive: Bool {
        guard state == .trial, let trialEndsAt else { return false }
        return Date() < trialEndsAt
    }

    var paidIsActive: Bool {
        guard state == .paid else { return false }
        guard let currentPeriodEndsAt else { return true }
        return Date() < currentPeriodEndsAt
    }

    var lifecycleState: SubscriptionLifecycleState {
        switch state {
        case .trial:
            return trialIsActive ? .trial : .expired
        case .paid:
            return paidIsActive ? .active : .expired
        case .expired:
            return .expired
        case .revoked:
            return .revoked
        case .free:
            let normalizedSource = source ?? .none
            if normalizedSource != .none,
               trialEndsAt != nil || currentPeriodEndsAt != nil || productID != nil {
                return .expired
            }
            return .free
        }
    }

    var hasPaidAccess: Bool {
        lifecycleState == .trial || lifecycleState == .active
    }

    var effectiveTier: SubscriptionTier {
        hasPaidAccess ? .paid : .free
    }

    var displayTitle: String {
        lifecycleState.title
    }

    var billingPeriodTitle: String? {
        switch productID {
        case SubscriptionStore.monthlyProductID:
            return ATHLTHLocalization.string( "Monthly")
        case SubscriptionStore.yearlyProductID:
            return ATHLTHLocalization.string( "Yearly")
        default:
            return nil
        }
    }

    var trialDaysRemaining: Int? {
        guard trialIsActive, let trialEndsAt else { return nil }
        let remaining = Calendar.current.dateComponents(
            [.day],
            from: Date(),
            to: trialEndsAt
        ).day ?? 0
        return max(1, remaining + 1)
    }
}

enum AccountRole: String, Codable, Hashable, CaseIterable {
    case user
    case admin
    case owner

    var title: String {
        switch self {
        case .user: return ATHLTHLocalization.string( "User")
        case .admin: return ATHLTHLocalization.string( "Admin")
        case .owner: return ATHLTHLocalization.string( "Owner")
        }
    }

    var canAccessControlCenter: Bool {
        self == .admin || self == .owner
    }

    var canManageAdmins: Bool {
        self == .owner
    }
}

enum ProfileVisibility: String, Codable, CaseIterable, Identifiable {
    case privateOnly = "private"
    case friends
    case publicProfile = "public"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privateOnly: return ATHLTHLocalization.string( "Private")
        case .friends: return ATHLTHLocalization.string( "Followers")
        case .publicProfile: return ATHLTHLocalization.string( "Public")
        }
    }
}

struct ATHLTHUser: Identifiable, Codable, Hashable {
    let id: UUID
    var email: String?
    var appleUserIdentifier: String?
    var username: String
    var displayName: String
    var createdAt: Date
}

enum TrainingPresenceState: String, Codable, Hashable {
    case offline
    case available
    case training
}

struct TrainingPresence: Codable, Hashable {
    var state: TrainingPresenceState
    var workoutTitle: String?
    var startedAt: Date?
    var visibility: ProfileVisibility
}

struct UserProfile: Identifiable, Codable, Hashable {
    let id: UUID
    var userID: UUID
    var username: String
    var displayName: String
    var bio: String
    var avatarURL: URL?
    var headerArtworkName: String? = nil
    var headerImageURL: URL? = nil
    var headerDimStrength: Double? = nil
    var presence: TrainingPresence
}

enum WorkoutKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case running
    case walking
    case strength
    case mobility
    case recovery
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .running: return ATHLTHLocalization.string( "Run")
        case .walking: return ATHLTHLocalization.string( "Walk")
        case .strength: return ATHLTHLocalization.string( "Strength")
        case .mobility: return ATHLTHLocalization.string( "Mobility")
        case .recovery: return ATHLTHLocalization.string( "Recovery")
        case .custom: return ATHLTHLocalization.string( "Custom")
        }
    }

    var systemImage: String {
        switch self {
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .strength: return "dumbbell.fill"
        case .mobility: return "figure.flexibility"
        case .recovery: return "leaf.fill"
        case .custom: return "plus.circle.fill"
        }
    }
}

enum ExerciseOrigin: String, Codable, Hashable {
    case publicCatalog
    case custom
}

struct ExerciseSnapshot: Codable, Hashable {
    var name: String
    var instructions: [String]
    var primaryMuscles: [String]
    // Optional for backwards compatibility with workout logs created
    // before secondary-muscle metadata was preserved in snapshots.
    var secondaryMuscles: [String]? = nil
    var equipment: [String]
    var imageURL: URL?
    var videoURL: URL? = nil

    var displayName: String {
        ATHLTHLocalization.choose(
            english: name,
            norwegian:
                ATHLTHExerciseNameLocalization
                    .norwegianName(for: name)
        )
    }
}

struct Exercise: Identifiable, Codable, Hashable {
    let id: UUID
    var origin: ExerciseOrigin
    var ownerID: UUID?
    var name: String
    var instructions: [String]
    var primaryMuscles: [String]
    var secondaryMuscles: [String]
    var equipment: [String]
    var imageURL: URL?
    var isVisibleOutsideOwnerLibrary: Bool
    var videoURL: URL? = nil

    var displayName: String {
        guard origin != .custom else {
            return name
        }

        return ATHLTHLocalization.choose(
            english: name,
            norwegian:
                ATHLTHExerciseNameLocalization
                    .norwegianName(for: name)
        )
    }

    var searchNames: [String] {
        guard origin != .custom else {
            return [name]
        }

        return ATHLTHExerciseNameLocalization
            .searchTerms(for: name)
    }

    var snapshot: ExerciseSnapshot {
        ExerciseSnapshot(
            name: name,
            instructions: instructions,
            primaryMuscles: primaryMuscles,
            secondaryMuscles: secondaryMuscles,
            equipment: equipment,
            imageURL: imageURL,
            videoURL: videoURL
        )
    }
}

enum StrengthExerciseLoadKind: String, CaseIterable, Identifiable, Codable, Hashable {
    case weightKilograms
    case resistanceLevel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weightKilograms:
            return ATHLTHLocalization.choose(
                english: "Weight",
                norwegian: "Vekt"
            )
        case .resistanceLevel:
            return ATHLTHLocalization.choose(
                english: "Resistance",
                norwegian: "Motstand"
            )
        }
    }
}

enum StrengthExerciseTargetKind: String, CaseIterable, Identifiable, Codable, Hashable {
    case reps
    case time

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reps:
            return ATHLTHLocalization.choose(
                english: "Target reps",
                norwegian: "Målreps"
            )
        case .time:
            return ATHLTHLocalization.choose(
                english: "Duration",
                norwegian: "Varighet"
            )
        }
    }
}

extension ExerciseSnapshot {
    private var normalizedStrengthEquipmentText: String {
        ([name] + equipment)
            .joined(separator: " ")
            .folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: .current
            )
            .lowercased()
    }

    var defaultStrengthLoadKind: StrengthExerciseLoadKind {
        let resistanceKeywords = [
            "rowing",
            "rowerg",
            "rower",
            "rowing machine",
            "concept2 row",
            "ski erg",
            "skierg"
        ]

        return resistanceKeywords.contains {
            normalizedStrengthEquipmentText.contains($0)
        }
            ? .resistanceLevel
            : .weightKilograms
    }

    var supportsStrengthDistanceResult: Bool {
        let distanceKeywords = [
            "rowing",
            "rowerg",
            "rower",
            "rowing machine",
            "concept2 row",
            "ski erg",
            "skierg"
        ]

        return distanceKeywords.contains {
            normalizedStrengthEquipmentText.contains($0)
        }
    }

    var defaultStrengthTargetKind: StrengthExerciseTargetKind {
        let normalized =
            ([name] + equipment)
                .joined(separator: " ")
                .folding(
                    options: [.diacriticInsensitive, .caseInsensitive],
                    locale: .current
                )
                .lowercased()

        let timeBasedKeywords = [
            "rowing machine",
            "rower",
            "concept2 row",
            "ski erg",
            "skierg",
            "treadmill",
            "stationary bike",
            "exercise bike",
            "air bike",
            "assault bike",
            "elliptical",
            "stair climber",
            "stairmaster",
            "battle rope",
            "plank",
            "wall sit",
            "dead hang",
            "hollow hold",
            "isometric hold"
        ]

        return timeBasedKeywords.contains {
            normalized.contains($0)
        }
            ? .time
            : .reps
    }

    var defaultStrengthTargetDurationSeconds: Int {
        let normalized =
            ([name] + equipment)
                .joined(separator: " ")
                .folding(
                    options: [.diacriticInsensitive, .caseInsensitive],
                    locale: .current
                )
                .lowercased()

        let cardioMachineKeywords = [
            "rowing machine",
            "rower",
            "concept2 row",
            "ski erg",
            "skierg",
            "treadmill",
            "stationary bike",
            "exercise bike",
            "air bike",
            "assault bike",
            "elliptical",
            "stair climber",
            "stairmaster"
        ]

        return cardioMachineKeywords.contains {
            normalized.contains($0)
        }
            ? 300
            : 60
    }
}

enum PlannedStrengthSetType: String, Codable, Hashable, CaseIterable, Identifiable {
    case warmUp
    case work
    case backOff
    case drop
    case failure
    case cluster

    var id: String { rawValue }

    var title: String {
        switch self {
        case .warmUp:
            return ATHLTHLocalization.choose(
                english: "Warm-up",
                norwegian: "Oppvarming"
            )
        case .work:
            return ATHLTHLocalization.choose(
                english: "Work",
                norwegian: "Arbeidssett"
            )
        case .backOff:
            return ATHLTHLocalization.choose(
                english: "Back-off",
                norwegian: "Back-off"
            )
        case .drop:
            return ATHLTHLocalization.choose(
                english: "Drop set",
                norwegian: "Droppsett"
            )
        case .failure:
            return ATHLTHLocalization.choose(
                english: "To failure",
                norwegian: "Til utmattelse"
            )
        case .cluster:
            return ATHLTHLocalization.choose(
                english: "Cluster",
                norwegian: "Klyngesett"
            )
        }
    }

    var systemImage: String {
        switch self {
        case .warmUp:
            return "flame"
        case .work:
            return "dumbbell.fill"
        case .backOff:
            return "arrow.down.right"
        case .drop:
            return "arrow.down.to.line"
        case .failure:
            return "bolt.fill"
        case .cluster:
            return "square.grid.2x2.fill"
        }
    }
}

struct PlannedExerciseSetTarget: Identifiable, Codable, Hashable {
    let id: UUID
    var reps: Int?
    var durationSeconds: Int?
    var weightKilograms: Double?
    var resistanceLevel: Int?
    var restSeconds: Int?
    var targetRPE: Double?
    var targetRIR: Double?
    var isWarmUp: Bool? = nil
    var setType: PlannedStrengthSetType? = nil
    var tempo: String? = nil
    var notes: String? = nil

    init(
        id: UUID = UUID(),
        reps: Int? = nil,
        durationSeconds: Int? = nil,
        weightKilograms: Double? = nil,
        resistanceLevel: Int? = nil,
        restSeconds: Int? = nil,
        targetRPE: Double? = nil,
        targetRIR: Double? = nil,
        isWarmUp: Bool? = nil,
        setType: PlannedStrengthSetType? = nil,
        tempo: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.weightKilograms = weightKilograms
        self.resistanceLevel = resistanceLevel
        self.restSeconds = restSeconds
        self.targetRPE = targetRPE
        self.targetRIR = targetRIR
        self.isWarmUp = isWarmUp
        self.setType = setType
        self.tempo = tempo
        self.notes = notes
    }
}

struct PlannedExercise: Identifiable, Codable, Hashable {
    let id: UUID
    var exerciseID: UUID?
    var embeddedExercise: ExerciseSnapshot
    var sets: Int
    var reps: Int?
    var targetWeightKilograms: Double?
    var targetRPE: Double?
    var restSeconds: Int?
    var notes: String?
    var targetRIR: Double? = nil
    var supersetGroupID: UUID? = nil
    var progression: StrengthProgressionRule? = nil

    // Optional keeps plans created before target-type support decodable.
    // nil means use the exercise's normal default (reps for most exercises,
    // time for common timed/cardio exercises).
    var targetKind: StrengthExerciseTargetKind? = nil
    var targetDurationSeconds: Int? = nil

    // Optional load metadata keeps older plans compatible while allowing
    // machine settings such as a RowErg damper/resistance level.
    var loadKind: StrengthExerciseLoadKind? = nil
    var targetResistanceLevel: Int? = nil

    // Optional keeps older plans fully compatible. When present, each set can
    // carry its own prescription instead of inheriting one exercise-wide
    // value for reps/time, load, rest and effort.
    var setTargets: [PlannedExerciseSetTarget]? = nil

    var hasIndividualSetTargets: Bool {
        guard let setTargets else {
            return false
        }

        return !setTargets.isEmpty
    }

    var resolvedSetTargets: [PlannedExerciseSetTarget] {
        let count = max(sets, 1)
        let fallback =
            PlannedExerciseSetTarget(
                reps:
                    resolvedTargetKind == .reps
                        ? reps
                        : nil,
                durationSeconds:
                    resolvedTargetKind == .time
                        ? resolvedTargetDurationSeconds
                        : nil,
                weightKilograms:
                    resolvedLoadKind == .weightKilograms
                        ? targetWeightKilograms
                        : nil,
                resistanceLevel:
                    resolvedLoadKind == .resistanceLevel
                        ? resolvedTargetResistanceLevel
                        : nil,
                restSeconds: restSeconds,
                targetRPE: targetRPE,
                targetRIR: targetRIR
            )

        guard let setTargets,
              !setTargets.isEmpty
        else {
            return (0..<count).map { _ in
                PlannedExerciseSetTarget(
                    reps: fallback.reps,
                    durationSeconds:
                        fallback.durationSeconds,
                    weightKilograms:
                        fallback.weightKilograms,
                    resistanceLevel:
                        fallback.resistanceLevel,
                    restSeconds:
                        fallback.restSeconds,
                    targetRPE:
                        fallback.targetRPE,
                    targetRIR:
                        fallback.targetRIR
                )
            }
        }

        var resolved =
            Array(setTargets.prefix(count))

        if resolved.count < count {
            let source =
                resolved.last ??
                fallback

            for _ in resolved.count..<count {
                resolved.append(
                    PlannedExerciseSetTarget(
                        reps:
                            source.reps ??
                            fallback.reps,
                        durationSeconds:
                            source.durationSeconds ??
                            fallback.durationSeconds,
                        weightKilograms:
                            source.weightKilograms ??
                            fallback.weightKilograms,
                        resistanceLevel:
                            source.resistanceLevel ??
                            fallback.resistanceLevel,
                        restSeconds:
                            source.restSeconds ??
                            fallback.restSeconds,
                        targetRPE:
                            source.targetRPE ??
                            fallback.targetRPE,
                        targetRIR:
                            source.targetRIR ??
                            fallback.targetRIR,
                        isWarmUp:
                            source.isWarmUp,
                        setType:
                            source.setType,
                        tempo:
                            source.tempo,
                        notes:
                            source.notes
                    )
                )
            }
        }

        return resolved
    }

    var resolvedLoadKind: StrengthExerciseLoadKind {
        loadKind ??
            embeddedExercise.defaultStrengthLoadKind
    }

    var resolvedTargetResistanceLevel: Int? {
        guard resolvedLoadKind == .resistanceLevel else {
            return nil
        }

        return min(
            max(targetResistanceLevel ?? 5, 1),
            10
        )
    }

    var resolvedTargetKind: StrengthExerciseTargetKind {
        targetKind ??
            embeddedExercise.defaultStrengthTargetKind
    }

    var resolvedTargetDurationSeconds: Int? {
        guard resolvedTargetKind == .time else {
            return nil
        }

        return max(
            targetDurationSeconds ??
                embeddedExercise
                    .defaultStrengthTargetDurationSeconds,
            15
        )
    }

    var resolvedTargetReps: Int? {
        resolvedTargetKind == .reps
            ? reps
            : nil
    }

    var compactLoadSummary: String? {
        if hasIndividualSetTargets {
            switch resolvedLoadKind {
            case .weightKilograms:
                let values =
                    resolvedSetTargets
                        .compactMap(\.weightKilograms)

                guard !values.isEmpty else {
                    return nil
                }

                let rounded =
                    values.map {
                        String(
                            format: "%.1f",
                            $0
                        )
                    }

                if Set(rounded).count == 1,
                   let first = values.first {
                    return String(
                        format: "%.1f kg",
                        first
                    )
                }

                return
                    rounded
                        .map { "\($0) kg" }
                        .joined(separator: " / ")

            case .resistanceLevel:
                let values =
                    resolvedSetTargets
                        .compactMap(\.resistanceLevel)

                guard !values.isEmpty else {
                    return nil
                }

                if Set(values).count == 1,
                   let first = values.first {
                    return ATHLTHLocalization.choose(
                        english: "Resistance \(first)",
                        norwegian: "Motstand \(first)"
                    )
                }

                return ATHLTHLocalization.choose(
                    english:
                        "Resistance " +
                        values
                            .map { String($0) }
                            .joined(separator: " / "),
                    norwegian:
                        "Motstand " +
                        values
                            .map { String($0) }
                            .joined(separator: " / ")
                )
            }
        }

        switch resolvedLoadKind {
        case .weightKilograms:
            guard let targetWeightKilograms else {
                return nil
            }
            return String(
                format: "%.1f kg",
                targetWeightKilograms
            )

        case .resistanceLevel:
            guard let level =
                    resolvedTargetResistanceLevel
            else {
                return nil
            }
            return ATHLTHLocalization.choose(
                english: "Resistance \(level)",
                norwegian: "Motstand \(level)"
            )
        }
    }

    var compactTargetSummary: String {
        if hasIndividualSetTargets {
            switch resolvedTargetKind {
            case .reps:
                let values =
                    resolvedSetTargets
                        .compactMap(\.reps)

                if values.count == resolvedSetTargets.count,
                   Set(values).count == 1,
                   let first = values.first {
                    return "\(sets) × \(first)"
                }

                let joined =
                    resolvedSetTargets
                        .map {
                            $0.reps.map(String.init) ?? "—"
                        }
                        .joined(separator: " / ")

                return ATHLTHLocalization.choose(
                    english: "\(joined) reps",
                    norwegian: "\(joined) reps"
                )

            case .time:
                let values =
                    resolvedSetTargets
                        .map {
                            formattedPlannedDuration(
                                $0.durationSeconds ??
                                resolvedTargetDurationSeconds ??
                                0
                            )
                        }

                if Set(values).count == 1,
                   let first = values.first {
                    return "\(sets) × \(first)"
                }

                return values.joined(separator: " / ")
            }
        }

        switch resolvedTargetKind {
        case .reps:
            return
                "\(sets) × \(reps ?? 0)"

        case .time:
            return
                "\(sets) × \(formattedPlannedDuration(resolvedTargetDurationSeconds ?? 0))"
        }
    }

    private func formattedPlannedDuration(
        _ seconds: Int
    ) -> String {
        let totalSeconds =
            max(seconds, 0)
        let hours =
            totalSeconds / 3_600
        let minutes =
            (totalSeconds % 3_600) / 60
        let seconds =
            totalSeconds % 60

        return
            hours > 0
                ? String(
                    format:
                        "%d:%02d:%02d",
                    hours,
                    minutes,
                    seconds
                )
                : String(
                    format:
                        "%02d:%02d",
                    minutes,
                    seconds
                )
    }
}

struct PlannedSession: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var kind: WorkoutKind
    var scheduledStart: Date?
    var durationMinutes: Int?
    var targetDistanceKilometers: Double?
    var targetPaceSecondsPerKilometer: Double?
    var routeID: UUID?
    var exercises: [PlannedExercise]
    var notes: String?

    // Kept for backwards compatibility with plans created before multi-run
    // support. New sessions also store the first selected workout here so
    // older code paths still have a useful structured workout.
    var runningWorkout: RunningWorkoutTemplate? = nil

    // Optional so previously persisted plans decode without migration.
    var runningWorkouts: [RunningWorkoutTemplate]? = nil

    // Optional planned gear selection. nil means legacy/default behavior;
    // an empty array explicitly means no gear for this workout.
    var gearIDs: [UUID]? = nil

    // nil uses the current app default. A stored configuration is a
    // per-workout Audio Coach override.
    var audioCoachConfiguration: WatchAudioCoachConfiguration? = nil

    // nil inherits the global outdoor auto-pause setting. true/false is an
    // explicit per-workout override for outdoor running or walking.
    var autoPauseEnabled: Bool? = nil

    // Per-workout Spotify override. spotifyAutoplayOnStart == nil keeps
    // backwards compatibility by inheriting the program-level Spotify
    // setting. false explicitly disables Spotify for this workout, while
    // true starts spotifyPlaylist when one is selected.
    var spotifyPlaylist: SpotifyPlaylistReference? = nil
    var spotifyAutoplayOnStart: Bool? = nil

    // Optional per-workout live target alerts.
    var targetAlertConfiguration:
        WatchWorkoutTargetAlertConfiguration? = nil

    // Optional per-workout running guidance. Nil keeps backwards-compatible
    // inheritance from global Workout Guidance settings.
    var routeAlertConfiguration:
        WatchRouteAlertConfiguration? = nil
    var ghostTargetDurationSeconds:
        TimeInterval? = nil
    var ghostUpdates:
        WatchGhostRaceAudioConfiguration? = nil

    // Unified workout hierarchy. Optional so all existing plans and saved
    // workouts continue to decode unchanged.
    var workoutTemplateID: UUID? = nil
    var workoutBlocks: [WorkoutTemplateBlock]? = nil
    var workoutCategory: String? = nil

    var sharedSourceOwnerID: UUID? = nil
    var sharedSourceSessionID: UUID? = nil

    var resolvedRunningWorkouts: [RunningWorkoutTemplate] {
        if let runningWorkouts,
           !runningWorkouts.isEmpty {
            return runningWorkouts
        }

        if let runningWorkout {
            return [runningWorkout]
        }

        return []
    }

    var resolvedWorkoutBlocks: [WorkoutTemplateBlock] {
        workoutBlocks ?? []
    }

    var isStructuredWorkout: Bool {
        !resolvedWorkoutBlocks.isEmpty
    }
}

struct TrainingPlanDay: Identifiable, Codable, Hashable {
    let id: UUID
    var dayIndex: Int
    var title: String
    var sessions: [PlannedSession]
}

/// Optional training-load designation. Missing for all historical plans.
enum TrainingWeekStrengthPhase: String, Codable, Hashable {
    case build
    case deload
}

struct TrainingPlanWeek: Identifiable, Codable, Hashable {
    let id: UUID
    var weekNumber: Int
    var title: String
    var days: [TrainingPlanDay]
    // Optional to preserve decoding of all pre-periodization plans.
    var strengthPhase: TrainingWeekStrengthPhase? = nil
}

enum TrainingPlanBuilderMode: String, Codable, Hashable, CaseIterable, Identifiable {
    case basic
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .basic:
            return ATHLTHLocalization.choose(
                english: "Basic",
                norwegian: "Basic"
            )
        case .advanced:
            return ATHLTHLocalization.choose(
                english: "Advanced",
                norwegian: "Avansert"
            )
        }
    }
}

enum TrainingPlanFocus: String, Codable, Hashable, CaseIterable, Identifiable {
    case generalFitness
    case strength
    case hypertrophy
    case running
    case hybrid
    case endurance
    case mobilityRehab

    var id: String { rawValue }

    var title: String {
        switch self {
        case .generalFitness:
            return ATHLTHLocalization.choose(
                english: "General fitness",
                norwegian: "Form"
            )
        case .strength:
            return ATHLTHLocalization.choose(
                english: "Strength",
                norwegian: "Styrke"
            )
        case .hypertrophy:
            return ATHLTHLocalization.choose(
                english: "Build muscle",
                norwegian: "Bygge muskler"
            )
        case .running:
            return ATHLTHLocalization.choose(
                english: "Running",
                norwegian: "Løping"
            )
        case .hybrid:
            return ATHLTHLocalization.choose(
                english: "Hybrid",
                norwegian: "Hybrid"
            )
        case .endurance:
            return ATHLTHLocalization.choose(
                english: "Endurance",
                norwegian: "Utholdenhet"
            )
        case .mobilityRehab:
            return ATHLTHLocalization.choose(
                english: "Mobility / rehab",
                norwegian: "Mobilitet / rehab"
            )
        }
    }

    var systemImage: String {
        switch self {
        case .generalFitness:
            return "figure.mixed.cardio"
        case .strength:
            return "dumbbell.fill"
        case .hypertrophy:
            return "figure.strengthtraining.traditional"
        case .running:
            return "figure.run"
        case .hybrid:
            return "arrow.triangle.2.circlepath"
        case .endurance:
            return "heart.fill"
        case .mobilityRehab:
            return "figure.flexibility"
        }
    }

    var suggestedWorkoutPattern: [WorkoutKind] {
        switch self {
        case .generalFitness:
            return [.strength, .running, .walking]
        case .strength:
            return [.strength, .strength, .mobility]
        case .hypertrophy:
            return [.strength, .strength, .strength]
        case .running:
            return [.running, .running, .running]
        case .hybrid:
            return [.strength, .running]
        case .endurance:
            return [.running, .walking, .running]
        case .mobilityRehab:
            return [.mobility, .strength, .recovery]
        }
    }
}

enum TrainingPlanGoalType: String, Codable, Hashable, CaseIterable, Identifiable {
    case getStronger
    case buildMuscle
    case runFaster
    case raceReady
    case improveFitness
    case maintain
    case returnAfterBreak

    var id: String { rawValue }

    var title: String {
        switch self {
        case .getStronger:
            return ATHLTHLocalization.choose(
                english: "Get stronger",
                norwegian: "Bli sterkere"
            )
        case .buildMuscle:
            return ATHLTHLocalization.choose(
                english: "Build muscle",
                norwegian: "Bygge muskler"
            )
        case .runFaster:
            return ATHLTHLocalization.choose(
                english: "Run faster",
                norwegian: "Løpe raskere"
            )
        case .raceReady:
            return ATHLTHLocalization.choose(
                english: "Race ready",
                norwegian: "Konkurranseform"
            )
        case .improveFitness:
            return ATHLTHLocalization.choose(
                english: "Improve fitness",
                norwegian: "Bedre form"
            )
        case .maintain:
            return ATHLTHLocalization.choose(
                english: "Maintain",
                norwegian: "Vedlikeholde"
            )
        case .returnAfterBreak:
            return ATHLTHLocalization.choose(
                english: "Return after a break",
                norwegian: "Tilbake etter pause"
            )
        }
    }
}

struct TrainingPlanBuilderProfile: Codable, Hashable {
    var mode: TrainingPlanBuilderMode
    var primaryFocus: TrainingPlanFocus?
    var secondaryFocus: TrainingPlanFocus? = nil
    var primaryFocusWeightPercent: Int? = nil
    var goal: TrainingPlanGoalType?
    var goalDetail: String? = nil
    var competitionDate: Date? = nil
    var sessionsPerWeek: Int
    var preferredDayIndexes: [Int]
    var injuriesOrLimitations: String? = nil
    var priorityMuscles: [String] = []
    var equipmentContext: String? = nil
    var weeklyTimeBudgetMinutes: Int? = nil

    // Optional for backwards compatibility with plans created before the
    // per-day workout-type picker was introduced. Missing values keep using
    // the focus-based suggested pattern.
    var preferredWorkoutKindsByDay: [Int: WorkoutKind]? = nil
}

struct TrainingPlan: Identifiable, Codable, Hashable {
    let id: UUID
    var ownerID: UUID
    var title: String
    var summary: String
    var visibility: ProfileVisibility
    var version: Int
    var weeks: [TrainingPlanWeek]
    var tags: [String]
    var spotifyPlaylist: SpotifyPlaylistReference? = nil
    var spotifyAutoplayOnWorkoutStart: Bool = true
    var createdAt: Date
    var updatedAt: Date
    var startDate: Date? = nil
    var endDate: Date? = nil
    var sharedSourceOwnerID: UUID? = nil
    var sharedSourcePlanID: UUID? = nil
    var sharedSourceVersion: Int? = nil
    var builderProfile: TrainingPlanBuilderProfile? = nil
}

struct RouteCoordinate: Codable, Hashable {
    var latitude: Double
    var longitude: Double
    var altitude: Double?
    var sequence: Int

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct TrainingRoute: Identifiable, Codable, Hashable {
    let id: UUID
    var ownerID: UUID
    var title: String
    var visibility: ProfileVisibility
    var coordinates: [RouteCoordinate]
    var distanceKilometers: Double
    var elevationGainMeters: Double?
    var importedFilename: String?
    var createdAt: Date

    // Optional route-builder metadata. Kept optional so previously saved
    // GPX routes continue to decode without migration.
    var startName: String? = nil
    var endName: String? = nil
    var expectedTravelTimeSeconds: TimeInterval? = nil
    var routeSource: String? = nil
    var sharedSourceOwnerID: UUID? = nil
    var sharedSourceRouteID: UUID? = nil
}

struct ActivityRecord: Identifiable, Codable, Hashable {
    let id: UUID
    var userID: UUID
    var workoutKind: WorkoutKind
    var title: String
    var startedAt: Date
    var duration: TimeInterval
    var distanceKilometers: Double?
    var activeCalories: Double?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var routeID: UUID?
    var visibility: ProfileVisibility
}

struct ActivityComment: Identifiable, Codable, Hashable {
    let id: UUID
    var activityID: UUID
    var authorID: UUID
    var body: String
    var createdAt: Date
}

struct DirectMessage: Identifiable, Codable, Hashable {
    let id: UUID
    var senderID: UUID
    var recipientID: UUID
    var body: String
    var createdAt: Date
    var readAt: Date?
}

struct HealthSnapshot: Equatable, Hashable {
    var activeCalories: Double
    var activeCaloriesGoal: Double
    var steps: Int
    var sleepDuration: TimeInterval
    var restingHeartRate: Double?
    var hrvMilliseconds: Double?
    var recoveryScore: Int?
}

struct RecoverySnapshot: Equatable, Hashable {
    var score: Int
    var sleepScore: Int
    var sleepDuration: TimeInterval
    var hrvMilliseconds: Double?
    var restingHeartRate: Double?
    var readinessText: String
}

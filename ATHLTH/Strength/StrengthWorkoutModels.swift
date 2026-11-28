import Foundation

enum WorkoutCaptureDevice: String, Codable, Hashable {
    case iPhone
    case appleWatch

    var title: String {
        switch self {
        case .iPhone: return "iPhone"
        case .appleWatch: return "Apple Watch"
        }
    }
}

enum StrengthTrackingMode: String, Codable, Hashable {
    case simple
    case advanced

    var title: String {
        switch self {
        case .simple: return "Simple"
        case .advanced: return "Advanced"
        }
    }
}

enum StrengthEffortMetric: String, Codable, CaseIterable, Identifiable, Hashable {
    case off
    case rpe
    case rir

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:
            return ATHLTHLocalization.choose(
                english: "Off",
                norwegian: "Av"
            )
        case .rpe:
            return "RPE"
        case .rir:
            return "RIR"
        }
    }
}

enum StrengthExerciseGroupStyle: String, Codable, CaseIterable, Identifiable, Hashable {
    case superset
    case circuit
    case emom
    case amrap
    case dropSet = "dropset"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .superset:
            return ATHLTHLocalization.choose(
                english: "Superset",
                norwegian: "Supersett"
            )
        case .circuit:
            return ATHLTHLocalization.choose(
                english: "Circuit",
                norwegian: "Sirkel"
            )
        case .emom: return "EMOM"
        case .amrap: return "AMRAP"
        case .dropSet: return ATHLTHLocalization.choose(
            english: "Drop set", norwegian: "Dropsett"
        )
        }
    }
}

struct StrengthAudioCoachConfiguration:
    Codable,
    Hashable
{
    var enabled = false
    var language: WatchAudioCoachLanguage = .system
    var voiceIdentifier: String? = nil
    var speechRate: Double = 0.48
    var speechVolume: Double = 1.0
    var speechStyle: ATHLTHCoachSpeechStyle? = nil
    var duckOtherAudio = true

    var announceSetComplete = true
    var announceRestStarted = true
    var announceRestCountdown = true
    var announceRestComplete = true
    var announceNextExercise = true

    // Optional additions preserve decoding of saved strength settings from
    // earlier 1.6.8 builds while allowing richer, less repetitive coaching.
    var announceNextSetDetails: Bool? = nil
    var announceExerciseProgress: Bool? = nil
    // Optional: older saved workouts decode without these strength-only cues.
    var announceExerciseComplete: Bool? = nil
    var motivationEveryCompletedSets: Int? = nil
    var personalMotivationPhrase: String? = nil
    // Effective shared rule snapshot, resolved at launch (disabled groups excluded).
    var customStrengthEventRules: [ATHLTHAudioCoachRule]? = nil

    var announceWorkoutStatus = false
    var workoutStatusIntervalMinutes = 15
    var restCountdownSeconds = 10
    // Optional strength-only second-by-second speech controls.
    var spokenCountdownToRestSeconds: Int? = nil
    var spokenCountdownFromRestSeconds: Int? = nil
    var afterCountdownToRest: ATHLTHCoachCountdownAfter? = nil
    var afterCountdownFromRest: ATHLTHCoachCountdownAfter? = nil
    var boundaryCountdownRules: [ATHLTHCoachBoundaryCountdownRule]? = nil

    var shouldAnnounceNextSetDetails: Bool {
        announceNextSetDetails ?? true
    }

    var shouldAnnounceExerciseProgress: Bool {
        announceExerciseProgress ?? false
    }

    var shouldAnnounceExerciseComplete: Bool {
        announceExerciseComplete ?? false
    }

    var resolvedMotivationEveryCompletedSets: Int? {
        guard let count = motivationEveryCompletedSets, (1...10).contains(count) else {
            return nil
        }
        return count
    }

    var resolvedCountdownToRest: Int? {
        guard let value = spokenCountdownToRestSeconds, (1...30).contains(value) else { return nil }
        return value
    }

    var resolvedCountdownFromRest: Int? {
        guard let value = spokenCountdownFromRestSeconds, (1...30).contains(value) else { return nil }
        return value
    }

    var watchConfiguration:
        WatchAudioCoachConfiguration {
        var configuration =
            WatchAudioCoachConfiguration.disabled

        configuration.enabled = enabled
        configuration.language = language
        configuration.duckOtherAudio =
            duckOtherAudio
        configuration.voiceIdentifier =
            voiceIdentifier
        configuration.speechRate =
            Float(
                min(
                    max(speechRate, 0.35),
                    0.65
                )
            )
        configuration.speechVolume =
            Float(
                min(
                    max(speechVolume, 0.2),
                    1.0
                )
            )
        configuration.speechStyle = speechStyle
        configuration.customRules = customStrengthEventRules

        configuration
            .announceStrengthSetComplete =
            announceSetComplete
        configuration
            .announceStrengthRestStarted =
            announceRestStarted
        configuration
            .announceStrengthRestCountdown =
            announceRestCountdown
        configuration
            .announceStrengthRestComplete =
            announceRestComplete
        configuration
            .announceStrengthNextExercise =
            announceNextExercise
        configuration
            .announceStrengthNextSetDetails =
            shouldAnnounceNextSetDetails
        configuration
            .announceStrengthExerciseProgress =
            shouldAnnounceExerciseProgress
        configuration.announceStrengthExerciseComplete = shouldAnnounceExerciseComplete
        configuration.strengthMotivationEverySets = resolvedMotivationEveryCompletedSets
        configuration.strengthPersonalMotivationPhrase = personalMotivationPhrase
        configuration.strengthCountdownToRestSeconds = resolvedCountdownToRest
        configuration.strengthCountdownFromRestSeconds = resolvedCountdownFromRest
        configuration.strengthAfterCountdownToRest = afterCountdownToRest
        configuration.strengthAfterCountdownFromRest = afterCountdownFromRest
        configuration.boundaryCountdownRules = boundaryCountdownRules
        configuration
            .strengthStatusIntervalSeconds =
            announceWorkoutStatus
                ? TimeInterval(
                    max(
                        workoutStatusIntervalMinutes,
                        5
                    ) * 60
                )
                : nil
        configuration
            .strengthRestCountdownSeconds =
            min(
                max(
                    restCountdownSeconds,
                    3
                ),
                30
            )

        return configuration
    }
}

struct StrengthRestCueConfiguration:
    Codable,
    Hashable
{
    var automaticRestTimer = true
    var defaultRestSeconds = 90
    var hapticsEnabled = true
}

struct StrengthAdvancedConfiguration:
    Codable,
    Hashable
{
    var spotifyPlaylist:
        SpotifyPlaylistReference? = nil
    var spotifyAutoplay = false
    var audioCoach =
        StrengthAudioCoachConfiguration()
    var restCues =
        StrengthRestCueConfiguration()
    var keepScreenAwake = false
    var inputMode:
        WatchStrengthInputMode = .both
    // Optional keeps advanced configurations written by earlier 1.5.5 builds decodable.
    var effortMetric:
        StrengthEffortMetric? = nil

    static let standard =
        StrengthAdvancedConfiguration()

    private static let defaultsKey =
        "strength.advanced.configuration.v1"

    static func savedDefaults() ->
        StrengthAdvancedConfiguration {
        guard let data =
                UserDefaults.standard.data(
                    forKey: defaultsKey
                ),
              let decoded =
                try? JSONDecoder().decode(
                    StrengthAdvancedConfiguration.self,
                    from: data
                )
        else {
            return .standard
        }

        return decoded
    }

    func saveAsDefaults() {
        guard let data =
                try? JSONEncoder().encode(self)
        else {
            return
        }

        UserDefaults.standard.set(
            data,
            forKey:
                Self.defaultsKey
        )
    }
}

struct LinkedHealthWorkoutMetrics: Codable, Hashable {
    var healthKitWorkoutUUID: UUID?
    var duration: TimeInterval?
    var activeCalories: Double?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
}

struct StrengthSetEffortSegment: Identifiable, Codable, Hashable {
    let id: UUID
    var reps: Int?
    var weightKilograms: Double?
    var durationSeconds: Int?
    var distanceMeters: Double?
    var resistanceLevel: Int?

    init(
        id: UUID = UUID(),
        reps: Int? = nil,
        weightKilograms: Double? = nil,
        durationSeconds: Int? = nil,
        distanceMeters: Double? = nil,
        resistanceLevel: Int? = nil
    ) {
        self.id = id
        self.reps = reps
        self.weightKilograms = weightKilograms
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.resistanceLevel = resistanceLevel
    }
}

/// Incremental device readings belong to an individual timed cardio set in
/// a strength workout. Distances are only carried over from actual Watch
/// readings, never from manually chosen treadmill speed.
struct StrengthWatchCardioCapture: Codable, Hashable {
    var watchWorkoutStartedAt: Date
    var lastCapturedAt: Date
    var lastElapsedTime: TimeInterval
    var lastDistanceMeters: Double
    var capturedActiveDuration: TimeInterval = 0
    var measuredDistanceMeters: Double = 0
    var heartRateSum: Double = 0
    var heartRateSampleCount: Int = 0
    var peakHeartRateBPM: Double? = nil
    var lastHeartRateSampleAt: Date? = nil

    mutating func ingest(_ sample: WatchWorkoutLiveSnapshot) {
        guard sample.startedAt == watchWorkoutStartedAt,
              sample.capturedAt > lastCapturedAt,
              sample.elapsedTime.isFinite, sample.distanceMeters.isFinite
        else { return }

        let gap = sample.capturedAt.timeIntervalSince(lastCapturedAt)
        let timeDelta = sample.elapsedTime - lastElapsedTime
        let distanceDelta = sample.distanceMeters - lastDistanceMeters
        // On reconnection or after changing exercises, do not assign
        // time/distance from the intervening exercise to this set.
        if gap > 0, gap <= 30, sample.state == .running,
           timeDelta >= 0, timeDelta <= gap + 5 {
            capturedActiveDuration += timeDelta
            if distanceDelta > 0, distanceDelta <= gap * 10 {
                measuredDistanceMeters += distanceDelta
            }
        }

        lastCapturedAt = sample.capturedAt
        lastElapsedTime = sample.elapsedTime
        lastDistanceMeters = sample.distanceMeters
        recordHeartRate(from: sample)
    }

    mutating func recordHeartRate(from sample: WatchWorkoutLiveSnapshot) {
        guard let sampledAt = sample.coachHeartRateSampleAt,
              abs(sample.capturedAt.timeIntervalSince(sampledAt)) <= 20,
              sampledAt > (lastHeartRateSampleAt ?? .distantPast),
              sample.heartRate.isFinite,
              (35...240).contains(sample.heartRate)
        else { return }
        heartRateSum += sample.heartRate
        heartRateSampleCount += 1
        peakHeartRateBPM = max(peakHeartRateBPM ?? sample.heartRate, sample.heartRate)
        lastHeartRateSampleAt = sampledAt
    }

    var averageHeartRate: Double? {
        heartRateSampleCount > 0 ? heartRateSum / Double(heartRateSampleCount) : nil
    }
}

struct StrengthSetLog: Identifiable, Codable, Hashable {
    let id: UUID
    var setNumber: Int
    var plannedReps: Int?
    var plannedWeightKilograms: Double?
    var completedReps: Int?
    var completedWeightKilograms: Double?
    var rpe: Double?
    var completedAt: Date?
    var restSeconds: Int?
    /// A missed/skipped EMOM station is resolved but never completed.
    /// It does not contribute repetitions, volume or records.
    var skippedAt: Date? = nil

    // Planned effort targets are separate from the athlete's logged result.
    // Optional fields keep all existing workout history decodable.
    var plannedRPE: Double? = nil
    var plannedRIR: Double? = nil
    var plannedSetType: PlannedStrengthSetType? = nil
    var plannedTempo: String? = nil
    var plannedNote: String? = nil

    // Optional fields preserve decoding of workouts created before this strength upgrade.
    var rir: Double? = nil
    var isWarmUp: Bool? = nil

    // Optional keeps workout history created before timed strength targets
    // fully decodable. Legacy sets remain repetition-based.
    var targetKind: StrengthExerciseTargetKind? = nil
    var plannedDurationSeconds: Int? = nil
    var completedDurationSeconds: Int? = nil
    /// Independently measured real set time (including repetition sets).
    /// Never includes the rest period; nil means not measured in older logs.
    var actualSetElapsedSeconds: TimeInterval? = nil
    // An explicit bodyweight/no-load choice; nil preserves legacy sessions.
    var recordsWeight: Bool? = nil

    // Optional machine/result metadata keeps older workout history decodable.
    var loadKind: StrengthExerciseLoadKind? = nil
    var plannedResistanceLevel: Int? = nil
    var completedResistanceLevel: Int? = nil
    var completedDistanceMeters: Double? = nil
    // Manually entered treadmill settings. Nil for normal strength sets,
    // and distinct from verified Watch speed/distance measurements.
    var completedTreadmillSpeedKilometersPerHour: Double? = nil
    var completedTreadmillInclinePercent: Double? = nil
    // Kept separate from actual/verified workout distance, since entered
    // treadmill speed is not a device-measured distance.
    var manuallyEstimatedTreadmillDistanceMeters: Double? = nil
    // Measurements from the active Watch strength workout only. These
    // never replace manual speed/incline, nor claim an estimated distance
    // was measured. Nil means no qualifying Watch sample was received.
    var watchMeasuredDistanceMeters: Double? = nil
    var watchActiveDurationSeconds: TimeInterval? = nil
    var watchAverageHeartRateBPM: Double? = nil
    var watchMaximumHeartRateBPM: Double? = nil
    /// Running interval phase stored within the same strength workout.
    /// Nil for every existing strength set and older saved workouts.
    var hybridPhaseTitle: String? = nil
    var hybridPhaseKind: String? = nil
    var hybridTargetHeartRateZone: Int? = nil
    var hybridTargetPaceSecondsPerKilometer: Double? = nil
    /// Watch GPS-measured distance goal, not a treadmill estimate.
    /// Nil for time-based running and all older strength logs.
    var hybridTargetDistanceMeters: Double? = nil

    // A completed set can contain multiple effort segments. Example:
    // 8 reps @ 10 kg + 2 reps @ 8 kg in the same planned 10-rep set.
    var effortSegments: [StrengthSetEffortSegment]? = nil

    // Actual time from set completion until the athlete explicitly continues.
    // Optional keeps older workout history fully decodable.
    var actualRestAfterSeconds: TimeInterval? = nil

    var resolvedLoadKind: StrengthExerciseLoadKind {
        loadKind ??
            (plannedResistanceLevel != nil ||
             completedResistanceLevel != nil
                ? .resistanceLevel
                : .weightKilograms)
    }

    var resolvedTargetKind: StrengthExerciseTargetKind {
        targetKind ??
            (plannedDurationSeconds != nil ? .time : .reps)
    }

    var resolvedCompletedReps: Int? {
        if let effortSegments,
           !effortSegments.isEmpty {
            let total =
                effortSegments
                    .compactMap(\.reps)
                    .reduce(0, +)
            return total > 0 ? total : nil
        }

        return completedReps
    }

    var resolvedCompletedDurationSeconds: Int? {
        if let effortSegments,
           !effortSegments.isEmpty {
            let total =
                effortSegments
                    .compactMap(\.durationSeconds)
                    .reduce(0, +)
            return total > 0 ? total : completedDurationSeconds
        }

        return completedDurationSeconds
    }

    var resolvedCompletedDistanceMeters: Double? {
        if let effortSegments,
           !effortSegments.isEmpty {
            let total =
                effortSegments
                    .compactMap(\.distanceMeters)
                    .reduce(0, +)
            return total > 0 ? total : completedDistanceMeters
        }

        return completedDistanceMeters
    }

    func completedReps(
        atOrAboveWeightKilograms target: Double
    ) -> Int {
        if let effortSegments,
           !effortSegments.isEmpty {
            return effortSegments.reduce(0) {
                partial,
                segment in

                guard let reps = segment.reps,
                      let weight =
                        segment.weightKilograms,
                      weight + 0.01 >= target
                else {
                    return partial
                }

                return partial + reps
            }
        }

        guard let weight =
                completedWeightKilograms,
              weight + 0.01 >= target
        else {
            return 0
        }

        return completedReps ?? 0
    }

    var volumeKilograms: Double {
        guard countsTowardTrainingLoad else {
            return 0
        }

        if let effortSegments,
           !effortSegments.isEmpty {
            return effortSegments.reduce(0) {
                partial,
                segment in

                guard let reps = segment.reps,
                      let weight =
                        segment.weightKilograms,
                      reps > 0,
                      weight > 0
                else {
                    return partial
                }

                return partial +
                    Double(reps) * weight
            }
        }

        guard let reps = completedReps,
              let weight =
                completedWeightKilograms
        else {
            return 0
        }

        return Double(reps) * weight
    }

    var isCompleted: Bool {
        completedAt != nil
    }

    var isResolved: Bool {
        completedAt != nil || skippedAt != nil
    }

    var countsTowardTrainingLoad: Bool {
        isCompleted && hybridPhaseKind == nil && isWarmUp != true && plannedSetType != .warmUp
    }
}

struct StrengthExerciseLog: Identifiable, Codable, Hashable {
    let id: UUID
    var plannedExerciseID: UUID?
    var exercise: ExerciseSnapshot
    var sets: [StrengthSetLog]
    var completedAt: Date?
    // Exercise-level behavior is optional for backward-compatible workout history.
    var restSecondsOverride: Int? = nil
    var groupID: UUID? = nil
    var groupStyle: StrengthExerciseGroupStyle? = nil
    /// Planned timer config for EMOM/AMRAP, never a measured result.
    var groupClockSeconds: TimeInterval? = nil
    /// Recorded when this group first becomes active. Optional so
    /// existing history and Watch transfers stay decodable.
    var groupStartedAt: Date? = nil
    var groupStationRestSeconds: Int? = nil
    var groupRoundRestSeconds: Int? = nil
    var substitutedFromExerciseName: String? = nil
    // Actual transition time from finishing this exercise until the athlete
    // explicitly confirms that they are ready to start the next exercise.
    // Optional keeps older workout history fully decodable.
    var transitionToNextExerciseSeconds: TimeInterval? = nil
    // Preserves an explicit decision to omit planned sets in a live workout.
    // Saved training plan and completed set IDs remain unchanged.
    var skippedPlannedSetCount: Int? = nil
    var targetSpeedKilometersPerHour: Double? = nil
    var targetHeartRateZone: Int? = nil
    /// Display provenance only; completed sets remain in the parent workout.
    var appendedWorkoutTitle: String? = nil
    var appendedWorkoutID: UUID? = nil
    var isEmbeddedRunningInterval: Bool? = nil
    /// Selected unloaded bar/machine bar mass (kg), already included in
    /// the total planned and completed set weight. Never add it again to
    /// volume or personal-record calculations. Nil means unspecified.
    var barWeightKilograms: Double? = nil

    var isCompleted: Bool {
        completedAt != nil
    }

    /// Older manual skips remove planned sets and record a separate count;
    /// timed EMOM skips retain the original slot and store skippedAt.
    /// These must be combined for display, never counted twice in totals.
    var auditedSkippedSets: Int {
        let legacySkippedCount = skippedPlannedSetCount ?? 0
        let retainedSkippedCount = sets.filter { $0.skippedAt != nil }.count
        // EMOM retains a skipped set in its original minute/station slot
        // AND previously incremented skippedPlannedSetCount. These are the
        // same omissions, not independent missed sets. max() also preserves
        // older checkpoints without rewriting their stored IDs or counters.
        if groupStyle != nil {
            // Grouped execution preserves the station/round slot when a
            // set is intentionally skipped. Its legacy count mirrors the
            // same omissions for Watch and older readers, not extra sets.
            return max(legacySkippedCount, retainedSkippedCount)
        }
        // Other modes may physically remove planned rows while retaining
        // separate timestamped skips, so those independent counts add.
        return legacySkippedCount + retainedSkippedCount
    }

    var isWarmUpExercise: Bool {
        !sets.isEmpty && sets.allSatisfy {
            $0.isWarmUp == true || $0.plannedSetType == .warmUp
        }
    }
}

enum StrengthPersonalRecordKind: String, Codable, Hashable {
    case heaviestSet
    case estimatedOneRepMax
    case workoutVolume

    var systemImage: String {
        switch self {
        case .heaviestSet: return "dumbbell.fill"
        case .estimatedOneRepMax: return "bolt.fill"
        case .workoutVolume: return "sum"
        }
    }
}

enum StrengthProgressionRecentTrend:
    Hashable
{
    case readyRepeated(
        readySessions: Int,
        totalSessions: Int
    )
    case readyLatest(
        totalSessions: Int
    )
    case improving(
        totalSessions: Int
    )
    case stable(
        totalSessions: Int
    )
    case heavy(
        totalSessions: Int
    )
}

struct StrengthProgressionSuggestion: Hashable {
    let previousWeightKilograms: Double
    let previousReps: Int
    let suggestedWeightKilograms: Double
    let suggestedReps: Int
    var reason: String? = nil

    // Recent context is optional so legacy callers/tests stay source compatible.
    // The active workout can use this to show a small "last time + trend" hint
    // without performing any expensive analysis while scrolling.
    var recentSessionCount: Int = 1
    var recentTrend:
        StrengthProgressionRecentTrend? = nil
}

struct StrengthPersonalRecord: Identifiable, Hashable {
    let id: String
    let kind: StrengthPersonalRecordKind
    let title: String
    let value: String
    let date: Date
    let score: Double
}

enum StrengthWorkoutPRKind: Hashable {
    case repMax(reps: Int)
    case heaviestWeight
    case estimatedOneRepMax
}

struct StrengthWorkoutPersonalRecord:
    Identifiable,
    Hashable
{
    let id: String
    let exerciseID: UUID
    let exerciseName: String
    let kind: StrengthWorkoutPRKind
    let value: String
    let previousValue: String
    let score: Double
    let setID: UUID?
}

struct StrengthRepPersonalRecord: Identifiable, Hashable {
    var id: String {
        "rep-pr-\(exerciseName.lowercased())-\(reps)"
    }

    let exerciseName: String
    let weightKilograms: Double
    let reps: Int
    let date: Date
    let sourceWorkoutID: UUID

    var title: String {
        "\(exerciseName) PR"
    }

    var value: String {
        guard weightKilograms > 0 else {
            return "\(reps) reps"
        }

        let weight: String
        if weightKilograms.rounded() == weightKilograms {
            weight = String(Int(weightKilograms))
        } else {
            weight = String(format: "%.1f", weightKilograms)
        }

        return "\(weight) kg × \(reps)"
    }
}

/// Explicit execution order, scoped to one active workout and stable set IDs.
struct StrengthLiveQueueEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    let exerciseID: UUID
    // nil means all remaining sets of the exercise, or the complete group.
    let setID: UUID?
    var groupID: UUID? = nil
}

struct StrengthWorkoutLog: Identifiable, Codable, Hashable {
    let id: UUID
    var plannedSessionID: UUID?
    var watchSessionID: UUID?
    var captureDevice: WorkoutCaptureDevice
    var trackingMode: StrengthTrackingMode
    var title: String
    var startedAt: Date
    var endedAt: Date?
    // Present only when iPad remotely requested this exact existing workout.
    // Optional to keep previously recorded strength history decodable.
    var relayRequestID: UUID? = nil
    /// Accumulated *confirmed* phone-offline downtime after crash recovery.
    /// Optional preserves histories and checkpoints from earlier versions.
    /// Watch-owned HealthKit recordings never use this local correction.
    var excludedRecoverySeconds: TimeInterval? = nil
    /// Exact pause windows for HealthKit; optional for existing history.
    /// A second save/recovery cannot insert the same offline pause twice.
    var recoveryPauseIntervals: [DateInterval]? = nil
    /// One Watch-owned cross-training workout may contain timed outdoor GPS
    /// segments. Optional keeps all earlier strength checkpoints decodable.
    var isOutdoorHybrid: Bool? = nil
    var exercises: [StrengthExerciseLog]
    var healthMetrics: LinkedHealthWorkoutMetrics
    var liveExecutionQueue: [StrengthLiveQueueEntry]? = nil
    var sourceWorkoutTemplateID: UUID? = nil
    var requiresCompanionExecutionOrder: Bool? = nil
    var advancedConfiguration:
        StrengthAdvancedConfiguration? = nil
    // True only when the athlete explicitly starts a no-plan strength
    // workout. Optional preserves older workout-history decoding.
    var allowsLiveExerciseBuilding: Bool? = nil
    // Optional for backward-compatible saved strength sessions.
    var liveHeartRateTargetZone: Int? = nil
    /// The same optional planned venue can be shown in preparation, live
    /// training and the saved strength summary, without claiming GPS check-in.
    var plannedTrainingPlace: ATHLTHTrainingPlace? = nil

    /// One pure elapsed clock for live strength, hybrid, summary and
    /// recovery. Only explicit checkpoint downtime is excluded; ordinary
    /// exercise rest remains part of the workout's elapsed time.
    func elapsedSessionSeconds(
        at now: Date = Date(),
        suspendedAt: Date? = nil
    ) -> TimeInterval {
        let end = endedAt ?? suspendedAt ?? now
        let inactive = excludedRecoverySeconds ?? 0
        let excluded = inactive.isFinite ? max(inactive, 0) : 0
        return max(end.timeIntervalSince(startedAt) - excluded, 0)
    }

    /// Reconcile overlapping/retried crash checkpoints, retaining the
    /// entire offline pause only once. No ordinary between-set rest is a
    /// HealthKit pause.
    mutating func recordRecoveredDowntime(
        from checkpoint: Date,
        until resumedAt: Date
    ) {
        guard captureDevice == .iPhone else { return }
        let start = max(checkpoint, startedAt)
        guard resumedAt > start else { return }
        let previous = (recoveryPauseIntervals ?? [])
            .filter { $0.duration.isFinite && $0.duration > 0 }
        let previousSeconds = previous.reduce(0) { $0 + $1.duration }
        let legacyUnrepresentedSeconds = max(
            (excludedRecoverySeconds ?? 0) - previousSeconds, 0
        )
        let sorted = (previous + [DateInterval(start: start, end: resumedAt)])
            .sorted { $0.start < $1.start }
        var merged: [DateInterval] = []
        for interval in sorted {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(
                    start: last.start, end: max(last.end, interval.end)
                )
            } else {
                merged.append(interval)
            }
        }
        recoveryPauseIntervals = merged
        excludedRecoverySeconds = legacyUnrepresentedSeconds +
            merged.reduce(0) { $0 + $1.duration }
    }

    var totalCompletedSets: Int {
        exercises
            .flatMap(\.sets)
            .filter { $0.isCompleted && $0.hybridPhaseKind == nil }
            .count
    }

    var totalWorkingSets: Int {
        exercises
            .flatMap(\.sets)
            .filter(\.countsTowardTrainingLoad)
            .count
    }

    var totalVolumeKilograms: Double {
        exercises
            .flatMap(\.sets)
            .reduce(0) {
                $0 + $1.volumeKilograms
            }
    }

    var totalCompletedReps: Int {
        // Prescribed or skipped sets may still contain legacy draft inputs.
        // Only the athlete's completed repetitions belong in the result.
        exercises
            .flatMap(\.sets)
            .filter(\.isCompleted)
            .reduce(0) { $0 + max($1.resolvedCompletedReps ?? 0, 0) }
    }

    var recordedRestDurationsSeconds: [TimeInterval] {
        exercises
            .flatMap(\.sets)
            .filter(\.isCompleted)
            .compactMap(\.actualRestAfterSeconds)
            .filter { $0.isFinite && $0 >= 0 }
    }

    var totalActualRestSeconds: TimeInterval {
        recordedRestDurationsSeconds.reduce(0, +)
    }

    var longestActualRestSeconds: TimeInterval {
        recordedRestDurationsSeconds.max() ?? 0
    }

    var averageActualRestSeconds: TimeInterval {
        let values = recordedRestDurationsSeconds
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    var isFinished: Bool {
        endedAt != nil
    }
}


/// Derived from the authoritative StrengthWorkoutLog, never persisted and
/// never a second workout/HealthKit recording. Every exercise retains its
/// stable source ID so hybrid cardio and strength can share one result.
struct StrengthWorkoutResultSegment: Identifiable {
    let id: UUID
    let exerciseName: String
    let isCardio: Bool
    let completedSets: Int
    let skippedSets: Int
    let completedReps: Int
    let volumeKilograms: Double
    let registeredEffortSeconds: TimeInterval
    let measuredDistanceMeters: Double
    let loggedDistanceMeters: Double
    let estimatedTreadmillDistanceMeters: Double

    init(exercise: StrengthExerciseLog) {
        id = exercise.id
        exerciseName = exercise.exercise.displayName
        isCardio = exercise.isEmbeddedRunningInterval == true ||
            StrengthCardioExercisePolicy.isCardio(exercise.exercise.name) ||
            exercise.sets.contains { $0.hybridPhaseKind != nil }
        let completed = exercise.sets.filter(\.isCompleted)
        completedSets = completed.count
        skippedSets = exercise.auditedSkippedSets
        completedReps = completed.reduce(0) {
            $0 + max($1.resolvedCompletedReps ?? 0, 0)
        }
        volumeKilograms = completed.reduce(0) { $0 + $1.volumeKilograms }
        // Prefer actual set/Watch timing to a manually recorded timed target.
        // Never add both for the same set.
        registeredEffortSeconds = completed.reduce(0) { subtotal, set in
            let seconds = set.actualSetElapsedSeconds ??
                set.watchActiveDurationSeconds ??
                set.resolvedCompletedDurationSeconds.map { TimeInterval($0) }
            return subtotal + ((seconds?.isFinite == true) ? max(seconds ?? 0, 0) : 0)
        }
        measuredDistanceMeters = completed.reduce(0) { subtotal, set in
            let meters = set.watchMeasuredDistanceMeters
            return subtotal + ((meters?.isFinite == true) ? max(meters ?? 0, 0) : 0)
        }
        loggedDistanceMeters = completed.reduce(0) { subtotal, set in
            // The Watch measurement also populates completedDistanceMeters;
            // report it only once, in the measured category.
            guard set.watchMeasuredDistanceMeters == nil else { return subtotal }
            let meters = set.resolvedCompletedDistanceMeters
            return subtotal + ((meters?.isFinite == true) ? max(meters ?? 0, 0) : 0)
        }
        estimatedTreadmillDistanceMeters = completed.reduce(0) { subtotal, set in
            let meters = set.manuallyEstimatedTreadmillDistanceMeters
            return subtotal + ((meters?.isFinite == true) ? max(meters ?? 0, 0) : 0)
        }
    }
}

/// One non-destructive results projection for the live finish review and
/// saved history. Ordinary rest stays inside the HealthKit workout duration,
/// while process-recovery downtime is excluded by the authoritative clock.
struct StrengthWorkoutResultBreakdown {
    let totalSeconds: TimeInterval
    let restSeconds: TimeInterval
    let activeSeconds: TimeInterval
    let segments: [StrengthWorkoutResultSegment]

    init(
        workout: StrengthWorkoutLog,
        elapsedSeconds: TimeInterval,
        ongoingRestSeconds: TimeInterval = 0,
        recordedRestSeconds: TimeInterval? = nil,
        includeSegments: Bool = true
    ) {
        let healthSeconds = workout.healthMetrics.duration
        // A live finish preview continues to use the shared runtime clock.
        // HealthKit's final duration only becomes authoritative after Finish.
        let useFinalHealthKitDuration = workout.isFinished &&
            (healthSeconds?.isFinite == true) && (healthSeconds ?? 0) > 0
        let chosen = useFinalHealthKitDuration
            ? (healthSeconds ?? 0) : elapsedSeconds
        totalSeconds = chosen.isFinite ? max(chosen, 0) : 0
        // Explicitly tracked live rest has not been written to a completed
        // set yet. Include it in the preview without modifying history.
        let liveRest = ongoingRestSeconds.isFinite
            ? max(ongoingRestSeconds, 0) : 0
        // Invalid imported rest evidence must never make 'active time'
        // negative or exceed the actual workout duration.
        restSeconds = min((recordedRestSeconds ?? workout.totalActualRestSeconds) + liveRest, totalSeconds)
        activeSeconds = max(totalSeconds - restSeconds, 0)
        segments = includeSegments ? workout.exercises.map(StrengthWorkoutResultSegment.init) : []
    }
}

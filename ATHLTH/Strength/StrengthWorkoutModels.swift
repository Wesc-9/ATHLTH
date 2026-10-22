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

    var announceWorkoutStatus = false
    var workoutStatusIntervalMinutes = 15
    var restCountdownSeconds = 10

    var shouldAnnounceNextSetDetails: Bool {
        announceNextSetDetails ?? true
    }

    var shouldAnnounceExerciseProgress: Bool {
        announceExerciseProgress ?? false
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

    var countsTowardTrainingLoad: Bool {
        isCompleted && isWarmUp != true && plannedSetType != .warmUp
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

    var isCompleted: Bool {
        completedAt != nil
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

struct StrengthWorkoutLog: Identifiable, Codable, Hashable {
    let id: UUID
    var plannedSessionID: UUID?
    var watchSessionID: UUID?
    var captureDevice: WorkoutCaptureDevice
    var trackingMode: StrengthTrackingMode
    var title: String
    var startedAt: Date
    var endedAt: Date?
    var exercises: [StrengthExerciseLog]
    var healthMetrics: LinkedHealthWorkoutMetrics
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

    var totalCompletedSets: Int {
        exercises
            .flatMap(\.sets)
            .filter(\.isCompleted)
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
        exercises
            .flatMap(\.sets)
            .compactMap {
                $0.resolvedCompletedReps
            }
            .reduce(0, +)
    }

    var totalActualRestSeconds: TimeInterval {
        exercises
            .flatMap(\.sets)
            .compactMap {
                $0.actualRestAfterSeconds
            }
            .reduce(0, +)
    }

    var longestActualRestSeconds: TimeInterval {
        exercises
            .flatMap(\.sets)
            .compactMap {
                $0.actualRestAfterSeconds
            }
            .max() ?? 0
    }

    var averageActualRestSeconds: TimeInterval {
        let values =
            exercises
                .flatMap(\.sets)
                .compactMap {
                    $0.actualRestAfterSeconds
                }

        guard !values.isEmpty else {
            return 0
        }

        return
            values.reduce(0, +) /
            Double(values.count)
    }

    var isFinished: Bool {
        endedAt != nil
    }
}

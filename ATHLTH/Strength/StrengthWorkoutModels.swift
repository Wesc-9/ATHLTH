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
    var duckOtherAudio = true

    var announceSetComplete = true
    var announceRestStarted = true
    var announceRestCountdown = true
    var announceRestComplete = true
    var announceNextExercise = true
    var announceWorkoutStatus = false
    var workoutStatusIntervalMinutes = 15
    var restCountdownSeconds = 10

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
}

struct LinkedHealthWorkoutMetrics: Codable, Hashable {
    var healthKitWorkoutUUID: UUID?
    var duration: TimeInterval?
    var activeCalories: Double?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
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
    // Optional fields preserve decoding of workouts created before this strength upgrade.
    var rir: Double? = nil
    var isWarmUp: Bool? = nil

    var isCompleted: Bool {
        completedAt != nil
    }

    var countsTowardTrainingLoad: Bool {
        isCompleted && isWarmUp != true
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

    var isCompleted: Bool {
        completedAt != nil
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

struct StrengthPersonalRecord: Identifiable, Hashable {
    let id: String
    let kind: StrengthPersonalRecordKind
    let title: String
    let value: String
    let date: Date
    let score: Double
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
            .reduce(0) { partial, set in
                guard
                    set.countsTowardTrainingLoad,
                    let reps = set.completedReps,
                    let weight = set.completedWeightKilograms
                else {
                    return partial
                }

                return partial + (Double(reps) * weight)
            }
    }

    var isFinished: Bool {
        endedAt != nil
    }
}

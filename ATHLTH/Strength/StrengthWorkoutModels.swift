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

    var isCompleted: Bool {
        completedAt != nil
    }
}

struct StrengthExerciseLog: Identifiable, Codable, Hashable {
    let id: UUID
    var plannedExerciseID: UUID?
    var exercise: ExerciseSnapshot
    var sets: [StrengthSetLog]
    var completedAt: Date?

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

    var totalCompletedSets: Int {
        exercises
            .flatMap(\.sets)
            .filter(\.isCompleted)
            .count
    }

    var totalVolumeKilograms: Double {
        exercises
            .flatMap(\.sets)
            .reduce(0) { partial, set in
                guard
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

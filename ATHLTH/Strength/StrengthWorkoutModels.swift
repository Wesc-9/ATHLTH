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

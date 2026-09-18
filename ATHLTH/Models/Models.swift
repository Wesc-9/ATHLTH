import CoreLocation
import Foundation
import HealthKit

struct WorkoutDetail {
    var route: [CLLocation] = []
    var averageHeartRate: Double?
    var maxHeartRate: Double?
}

struct WorkoutSummary: Identifiable, Hashable {
    let id: UUID
    let activity: WorkoutActivity
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval
    let distanceMeters: Double?
    let activeEnergyKilocalories: Double?

    init(workout: HKWorkout) {
        id = workout.uuid
        activity = WorkoutActivity(healthKitType: workout.workoutActivityType)
        startDate = workout.startDate
        endDate = workout.endDate
        duration = workout.duration
        distanceMeters = workout.totalDistance?.doubleValue(for: .meter())
        activeEnergyKilocalories = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
    }

    var distanceKilometers: Double? {
        distanceMeters.map { $0 / 1_000 }
    }

    var paceMinutesPerKilometer: Double? {
        guard let km = distanceKilometers, km > 0 else { return nil }
        return duration / 60 / km
    }
}

enum WorkoutActivity: String, Codable, CaseIterable, Hashable {
    case running = "Running"
    case walking = "Walking"
    case strength = "Strength"
    case other = "Workout"

    init(healthKitType: HKWorkoutActivityType) {
        switch healthKitType {
        case .running:
            self = .running
        case .walking:
            self = .walking
        case .traditionalStrengthTraining, .functionalStrengthTraining:
            self = .strength
        default:
            self = .other
        }
    }

    var icon: String {
        switch self {
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .strength: return "dumbbell.fill"
        case .other: return "figure.mixed.cardio"
        }
    }
}

struct SleepSummary: Equatable {
    var totalAsleep: TimeInterval = 0
    var core: TimeInterval = 0
    var deep: TimeInterval = 0
    var rem: TimeInterval = 0
    var awake: TimeInterval = 0
    var sleepStart: Date?
    var sleepEnd: Date?

    static let empty = SleepSummary()
}

struct HeartSummary: Equatable {
    var latestHeartRate: Double?
    var latestHeartRateDate: Date?
    var restingHeartRate: Double?
    var restingHeartRateDate: Date?
    var hrvMilliseconds: Double?
    var hrvDate: Date?

    static let empty = HeartSummary()
}

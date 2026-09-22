import CoreLocation
import Foundation
import HealthKit

struct WorkoutDetail {
    var route: [CLLocation] = []
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var stepCount: Double?
    var averageRunningSpeedMetersPerSecond: Double?
    var averageRunningPowerWatts: Double?
    var averageRunningStrideLengthMeters: Double?
    var averageRunningVerticalOscillationCentimeters: Double?
    var averageRunningGroundContactTimeMilliseconds: Double?
    var averageCyclingSpeedMetersPerSecond: Double?
    var averageCyclingPowerWatts: Double?
    var swimmingStrokeCount: Double?
}

struct TrainingHealthSummary: Equatable {
    var stepsToday: Double?
    var activeEnergyKilocaloriesToday: Double?
    var basalEnergyKilocaloriesToday: Double?
    var exerciseMinutesToday: Double?
    var distanceWalkingRunningMetersToday: Double?
    var distanceCyclingMetersToday: Double?
    var distanceSwimmingMetersToday: Double?
    var flightsClimbedToday: Double?
    var vo2Max: Double?
    var walkingHeartRateAverage: Double?
    var oxygenSaturationPercent: Double?
    var respiratoryRate: Double?

    static let empty = TrainingHealthSummary()
}

enum HealthProgressGrouping {
    case day
    case week
    case month
}

struct HealthProgressBucket: Identifiable, Equatable {
    var id: Date { startDate }

    let startDate: Date
    let endDate: Date
    let workoutCount: Int
    let averageDailySteps: Double?
    let averageSleepDuration: TimeInterval?
    let trainingDuration: TimeInterval
}

struct HealthProgressSnapshot: Equatable {
    let startDate: Date
    let endDate: Date
    let workoutCount: Int
    let totalSteps: Double?
    let averageDailySteps: Double?
    let averageSleepDuration: TimeInterval?
    let trainingDuration: TimeInterval
    let activeWorkoutDays: [Date]
    let buckets: [HealthProgressBucket]

    let previousWorkoutCount: Int
    let previousTotalSteps: Double?
    let previousAverageDailySteps: Double?
    let previousAverageSleepDuration: TimeInterval?
    let previousTrainingDuration: TimeInterval

    var workoutChangePercent: Double? {
        Self.percentChange(current: Double(workoutCount), previous: Double(previousWorkoutCount))
    }

    var totalStepsChangePercent: Double? {
        Self.percentChange(current: totalSteps, previous: previousTotalSteps)
    }

    var stepsChangePercent: Double? {
        Self.percentChange(current: averageDailySteps, previous: previousAverageDailySteps)
    }

    var sleepChangePercent: Double? {
        Self.percentChange(current: averageSleepDuration, previous: previousAverageSleepDuration)
    }

    var trainingDurationChangePercent: Double? {
        Self.percentChange(current: trainingDuration, previous: previousTrainingDuration)
    }

    private static func percentChange(current: Double?, previous: Double?) -> Double? {
        guard let current, let previous, previous > 0 else { return nil }
        return ((current - previous) / previous) * 100
    }
}

enum HealthPersonalRecordKind: String, Hashable {
    case longestRun
    case longestRide
    case longestWalkOrHike
    case longestWorkout
    case mostActiveCalories

    var title: String {
        switch self {
        case .longestRun: return "Longest Run"
        case .longestRide: return "Longest Ride"
        case .longestWalkOrHike: return "Longest Walk / Hike"
        case .longestWorkout: return "Longest Workout"
        case .mostActiveCalories: return "Most Active Calories"
        }
    }

    var systemImage: String {
        switch self {
        case .longestRun: return "figure.run"
        case .longestRide: return "figure.outdoor.cycle"
        case .longestWalkOrHike: return "figure.hiking"
        case .longestWorkout: return "clock.fill"
        case .mostActiveCalories: return "flame.fill"
        }
    }
}

struct HealthPersonalRecord: Identifiable, Equatable {
    var id: String { kind.rawValue }

    let kind: HealthPersonalRecordKind
    let value: Double
    let date: Date

    var formattedValue: String {
        switch kind {
        case .longestRun, .longestRide, .longestWalkOrHike:
            return String(format: "%.1f km", value / 1_000)

        case .longestWorkout:
            let totalMinutes = Int((value / 60).rounded())
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes) min"

        case .mostActiveCalories:
            return "\(Int(value.rounded())) kcal"
        }
    }
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
    case cycling = "Cycling"
    case swimming = "Swimming"
    case hiking = "Hiking"
    case strength = "Strength"
    case hiit = "HIIT"
    case rowing = "Rowing"
    case elliptical = "Elliptical"
    case stairClimbing = "Stair Climbing"
    case yoga = "Yoga"
    case coreTraining = "Core Training"
    case other = "Workout"

    init(healthKitType: HKWorkoutActivityType) {
        switch healthKitType {
        case .running:
            self = .running
        case .walking:
            self = .walking
        case .cycling:
            self = .cycling
        case .swimming:
            self = .swimming
        case .hiking:
            self = .hiking
        case .traditionalStrengthTraining, .functionalStrengthTraining:
            self = .strength
        case .highIntensityIntervalTraining:
            self = .hiit
        case .rowing:
            self = .rowing
        case .elliptical:
            self = .elliptical
        case .stairClimbing:
            self = .stairClimbing
        case .yoga:
            self = .yoga
        case .coreTraining:
            self = .coreTraining
        default:
            self = .other
        }
    }

    var icon: String {
        switch self {
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .cycling: return "figure.outdoor.cycle"
        case .swimming: return "figure.pool.swim"
        case .hiking: return "figure.hiking"
        case .strength: return "dumbbell.fill"
        case .hiit: return "figure.highintensity.intervaltraining"
        case .rowing: return "figure.rower"
        case .elliptical: return "figure.elliptical"
        case .stairClimbing: return "figure.stair.stepper"
        case .yoga: return "figure.yoga"
        case .coreTraining: return "figure.core.training"
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

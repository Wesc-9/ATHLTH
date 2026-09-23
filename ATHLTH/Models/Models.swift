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
    var moveGoalKilocaloriesToday: Double?
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
    case fastest1K
    case fastestMile
    case fastest5K
    case fastest10K
    case fastestHalfMarathon
    case fastestMarathon
    case longestRide
    case longestWalkOrHike
    case longestWorkout
    case mostActiveCalories

    var title: String {
        switch self {
        case .longestRun: return "Longest Run"
        case .fastest1K: return "Fastest 1K"
        case .fastestMile: return "Fastest Mile"
        case .fastest5K: return "Fastest 5K"
        case .fastest10K: return "Fastest 10K"
        case .fastestHalfMarathon: return "Fastest Half Marathon"
        case .fastestMarathon: return "Fastest Marathon"
        case .longestRide: return "Longest Ride"
        case .longestWalkOrHike: return "Longest Walk / Hike"
        case .longestWorkout: return "Longest Workout"
        case .mostActiveCalories: return "Most Active Calories"
        }
    }

    var systemImage: String {
        switch self {
        case .longestRun:
            return "figure.run"
        case .fastest1K,
             .fastestMile,
             .fastest5K,
             .fastest10K,
             .fastestHalfMarathon,
             .fastestMarathon:
            return "stopwatch.fill"
        case .longestRide:
            return "figure.outdoor.cycle"
        case .longestWalkOrHike:
            return "figure.hiking"
        case .longestWorkout:
            return "clock.fill"
        case .mostActiveCalories:
            return "flame.fill"
        }
    }

    var isRunningRecord: Bool {
        switch self {
        case .longestRun,
             .fastest1K,
             .fastestMile,
             .fastest5K,
             .fastest10K,
             .fastestHalfMarathon,
             .fastestMarathon:
            return true
        default:
            return false
        }
    }

    var targetDistanceMeters: Double? {
        switch self {
        case .fastest1K: return 1_000
        case .fastestMile: return 1_609.344
        case .fastest5K: return 5_000
        case .fastest10K: return 10_000
        case .fastestHalfMarathon: return 21_097.5
        case .fastestMarathon: return 42_195
        default: return nil
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

        case .fastest1K,
             .fastestMile,
             .fastest5K,
             .fastest10K,
             .fastestHalfMarathon,
             .fastestMarathon:
            let totalSeconds = max(Int(value.rounded()), 0)
            let hours = totalSeconds / 3_600
            let minutes = (totalSeconds % 3_600) / 60
            let seconds = totalSeconds % 60

            if hours > 0 {
                return String(
                    format: "%d:%02d:%02d",
                    hours,
                    minutes,
                    seconds
                )
            }

            return String(format: "%d:%02d", minutes, seconds)

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

struct TimedDistancePerformanceRecord: Equatable, Hashable {
    let distanceMeters: Double
    let duration: TimeInterval
    let date: Date
    let workoutID: UUID

    var formattedTime: String {
        let seconds = max(Int(duration.rounded()), 0)
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }

        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    var formattedPace: String {
        guard distanceMeters > 0 else { return "—" }

        let paceSeconds = duration / (distanceMeters / 1_000)
        let minutes = Int(paceSeconds) / 60
        let seconds = Int(paceSeconds.rounded()) % 60
        return String(format: "%d:%02d /km", minutes, seconds)
    }
}

struct ProfilePerformanceStats: Equatable, Hashable {
    let fastestOneKilometer: TimedDistancePerformanceRecord?
    let fastestFiveKilometers: TimedDistancePerformanceRecord?
    let fastestMarathon: TimedDistancePerformanceRecord?

    let longestWorkoutDuration: TimeInterval?
    let longestWorkoutDate: Date?
    let longestWorkoutActivity: WorkoutActivity?

    let longestWorkoutDistanceMeters: Double?
    let longestWorkoutDistanceDate: Date?
    let longestWorkoutDistanceActivity: WorkoutActivity?

    let longestRunMeters: Double?
    let longestRunDate: Date?

    let totalWorkoutCount: Int
    let totalTrainingDuration: TimeInterval
    let totalRunningDistanceMeters: Double

    static let empty = ProfilePerformanceStats(
        fastestOneKilometer: nil,
        fastestFiveKilometers: nil,
        fastestMarathon: nil,
        longestWorkoutDuration: nil,
        longestWorkoutDate: nil,
        longestWorkoutActivity: nil,
        longestWorkoutDistanceMeters: nil,
        longestWorkoutDistanceDate: nil,
        longestWorkoutDistanceActivity: nil,
        longestRunMeters: nil,
        longestRunDate: nil,
        totalWorkoutCount: 0,
        totalTrainingDuration: 0,
        totalRunningDistanceMeters: 0
    )
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

enum RecoveryReadinessState: String, Equatable {
    case buildingBaseline
    case ready
    case balanced
    case takeItEasy
    case recover

    var title: String {
        switch self {
        case .buildingBaseline: return "Building baseline"
        case .ready: return "Ready"
        case .balanced: return "Balanced"
        case .takeItEasy: return "Take it easier"
        case .recover: return "Prioritize recovery"
        }
    }

    var systemImage: String {
        switch self {
        case .buildingBaseline: return "waveform.path.ecg"
        case .ready: return "bolt.heart.fill"
        case .balanced: return "heart.fill"
        case .takeItEasy: return "gauge.with.dots.needle.33percent"
        case .recover: return "bed.double.fill"
        }
    }
}

struct RecoveryReadinessSummary: Equatable {
    let score: Int?
    let state: RecoveryReadinessState
    let detail: String
    let baselineDays: Int
    let averageSleepDuration: TimeInterval?
    let baselineHRVMilliseconds: Double?
    let baselineRestingHeartRate: Double?

    static let buildingBaseline = RecoveryReadinessSummary(
        score: nil,
        state: .buildingBaseline,
        detail: "ATHLTH is learning your recent sleep, HRV and resting heart-rate baseline.",
        baselineDays: 0,
        averageSleepDuration: nil,
        baselineHRVMilliseconds: nil,
        baselineRestingHeartRate: nil
    )
}

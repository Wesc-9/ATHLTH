import CoreLocation
import Foundation
import HealthKit

struct RoutePerformanceAnalysis: Hashable {
    let workoutID: UUID
    let activity: WorkoutActivity
    let startedAt: Date
    let durationSeconds: TimeInterval
    let distanceMeters: Double
    let routeMatchPercent: Double
    let averageDeviationMeters: Double
    let maxDeviationMeters: Double
    let startDistanceMeters: Double
    let endDistanceMeters: Double

    var deviationPercent: Double {
        max(0, 100 - routeMatchPercent)
    }

    var leaderboardEligible: Bool {
        routeMatchPercent >= 85
    }
}

struct WorkoutDetail {
    var route: [CLLocation] = []
    var workoutLocation: CLLocation?
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

struct WorkoutRouteHealthSegment: Codable, Hashable {
    let label: String
    let durationSeconds: Double
    let distanceMeters: Double
    let elevationGainMeters: Double
    let elevationLossMeters: Double
    let averageHeartRateBPM: Double?
    let maxHeartRateBPM: Double?
    let paceSecondsPerKilometer: Double?
}

struct WorkoutStrengthExerciseContext: Codable, Hashable {
    let name: String
    let completedSets: Int
    let totalReps: Int?
    let volumeKilograms: Double?
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
}

struct WorkoutAIInsightContext: Codable, Hashable {
    let activity: String
    let durationSeconds: Double
    let distanceMeters: Double?
    let activeEnergyKilocalories: Double?
    let averageHeartRateBPM: Double?
    let maxHeartRateBPM: Double?
    let personalMaximumHeartRateBPM: Int?
    let elevationGainMeters: Double?
    let routePointCount: Int
    let averagePaceSecondsPerKilometer: Double?
    let averageRunningPowerWatts: Double?
    let averageRunningStrideLengthMeters: Double?
    let averageRunningVerticalOscillationCentimeters: Double?
    let averageRunningGroundContactTimeMilliseconds: Double?
    let segments: [WorkoutRouteHealthSegment]
    var strengthTotalSets: Int? = nil
    var strengthTotalReps: Int? = nil
    var strengthTotalVolumeKilograms: Double? = nil
    var strengthMuscleFocus: [String]? = nil
    var strengthExercises: [WorkoutStrengthExerciseContext]? = nil
}

struct WorkoutVisualRecipe: Codable, Hashable {
    let palette: String
    let scene: String
    let light: String
    let motif: String
    let energy: String
    let variant: Int
}

struct WorkoutAIInsight: Codable, Hashable {
    let headline: String
    let summary: String
    let visualRecipe: WorkoutVisualRecipe?

    init(
        headline: String,
        summary: String,
        visualRecipe: WorkoutVisualRecipe? = nil
    ) {
        self.headline = headline
        self.summary = summary
        self.visualRecipe = visualRecipe
    }
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
    let workoutDistanceMeters: Double
}

struct HealthProgressSnapshot: Equatable {
    let startDate: Date
    let endDate: Date
    let workoutCount: Int
    let totalSteps: Double?
    let averageDailySteps: Double?
    let averageSleepDuration: TimeInterval?
    let trainingDuration: TimeInterval
    let workoutDistanceMeters: Double
    let activeWorkoutDays: [Date]
    let buckets: [HealthProgressBucket]

    let previousWorkoutCount: Int
    let previousTotalSteps: Double?
    let previousAverageDailySteps: Double?
    let previousAverageSleepDuration: TimeInterval?
    let previousTrainingDuration: TimeInterval
    let previousWorkoutDistanceMeters: Double

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

    var workoutDistanceChangePercent: Double? {
        Self.percentChange(
            current: workoutDistanceMeters,
            previous: previousWorkoutDistanceMeters
        )
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
    case longestSwim
    case longestWorkout
    case longestStrengthWorkout
    case longestHIITWorkout
    case longestRowingWorkout
    case longestEllipticalWorkout
    case longestStairClimbingWorkout
    case longestYogaWorkout
    case longestCoreWorkout
    case mostActiveCalories
    case mostStepsInWorkout

    var title: String {
        switch self {
        case .longestRun: return ATHLTHLocalization.string( "Longest Run")
        case .fastest1K: return ATHLTHLocalization.string( "Fastest 1K")
        case .fastestMile: return ATHLTHLocalization.string( "Fastest Mile")
        case .fastest5K: return ATHLTHLocalization.string( "Fastest 5K")
        case .fastest10K: return ATHLTHLocalization.string( "Fastest 10K")
        case .fastestHalfMarathon: return ATHLTHLocalization.string( "Fastest Half Marathon")
        case .fastestMarathon: return ATHLTHLocalization.string( "Fastest Marathon")
        case .longestRide: return ATHLTHLocalization.string( "Longest Ride")
        case .longestWalkOrHike: return ATHLTHLocalization.string( "Longest Walk / Hike")
        case .longestSwim:
            return ATHLTHLocalization.choose(
                english: "Longest Swim",
                norwegian: "Lengste svømmetur"
            )
        case .longestWorkout: return ATHLTHLocalization.string( "Longest Workout")
        case .longestStrengthWorkout:
            return ATHLTHLocalization.choose(
                english: "Longest Strength Workout",
                norwegian: "Lengste styrkeøkt"
            )
        case .longestHIITWorkout:
            return ATHLTHLocalization.choose(
                english: "Longest HIIT Workout",
                norwegian: "Lengste HIIT-økt"
            )
        case .longestRowingWorkout:
            return ATHLTHLocalization.choose(
                english: "Longest Rowing Workout",
                norwegian: "Lengste roøkt"
            )
        case .longestEllipticalWorkout:
            return ATHLTHLocalization.choose(
                english: "Longest Elliptical Workout",
                norwegian: "Lengste ellipseøkt"
            )
        case .longestStairClimbingWorkout:
            return ATHLTHLocalization.choose(
                english: "Longest Stair Workout",
                norwegian: "Lengste trappeøkt"
            )
        case .longestYogaWorkout:
            return ATHLTHLocalization.choose(
                english: "Longest Yoga Workout",
                norwegian: "Lengste yogaøkt"
            )
        case .longestCoreWorkout:
            return ATHLTHLocalization.choose(
                english: "Longest Core Workout",
                norwegian: "Lengste kjernestyrkeøkt"
            )
        case .mostActiveCalories: return ATHLTHLocalization.string( "Most Active Calories")
        case .mostStepsInWorkout:
            return ATHLTHLocalization.choose(
                english: "Most Steps in a Workout",
                norwegian: "Flest steg i én økt"
            )
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
        case .longestSwim:
            return "figure.pool.swim"
        case .longestWorkout:
            return "clock.fill"
        case .longestStrengthWorkout:
            return "dumbbell.fill"
        case .longestHIITWorkout:
            return "figure.highintensity.intervaltraining"
        case .longestRowingWorkout:
            return "figure.rower"
        case .longestEllipticalWorkout:
            return "figure.elliptical"
        case .longestStairClimbingWorkout:
            return "figure.stair.stepper"
        case .longestYogaWorkout:
            return "figure.yoga"
        case .longestCoreWorkout:
            return "figure.core.training"
        case .mostActiveCalories:
            return "flame.fill"
        case .mostStepsInWorkout:
            return "shoeprints.fill"
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
        case .longestRun,
             .longestRide,
             .longestWalkOrHike,
             .longestSwim:
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

        case .longestWorkout,
             .longestStrengthWorkout,
             .longestHIITWorkout,
             .longestRowingWorkout,
             .longestEllipticalWorkout,
             .longestStairClimbingWorkout,
             .longestYogaWorkout,
             .longestCoreWorkout:
            let totalMinutes = Int((value / 60).rounded())
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes) min"

        case .mostActiveCalories:
            return "\(Int(value.rounded())) kcal"

        case .mostStepsInWorkout:
            return ATHLTHLocalization.format(
                english: "%d steps",
                norwegian: "%d steg",
                Int(value.rounded())
            )
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

extension HKWorkout {
    var athlthDistanceMeters: Double? {
        let identifiers:
            [HKQuantityTypeIdentifier]

        switch workoutActivityType {
        case .running,
             .walking,
             .hiking,
             .elliptical,
             .stairClimbing:
            identifiers = [
                .distanceWalkingRunning
            ]

        case .cycling:
            identifiers = [
                .distanceCycling
            ]

        case .swimming:
            identifiers = [
                .distanceSwimming
            ]

        default:
            // Imported workouts can come from many apps and devices.
            // Fall back across the distance types ATHLTH currently reads.
            identifiers = [
                .distanceWalkingRunning,
                .distanceCycling,
                .distanceSwimming
            ]
        }

        for identifier in identifiers {
            guard let type =
                    HKObjectType.quantityType(
                        forIdentifier: identifier
                    ),
                  let quantity =
                    statistics(
                        for: type
                    )?.sumQuantity(),
                  quantity.is(
                    compatibleWith: .meter()
                  )
            else {
                continue
            }

            let value =
                quantity.doubleValue(
                    for: .meter()
                )

            if value.isFinite {
                return value
            }
        }

        return nil
    }

    var athlthActiveEnergyKilocalories:
        Double? {
        guard let type =
                HKObjectType.quantityType(
                    forIdentifier:
                        .activeEnergyBurned
                ),
              let quantity =
                statistics(
                    for: type
                )?.sumQuantity(),
              quantity.is(
                compatibleWith:
                    .kilocalorie()
              )
        else {
            return nil
        }

        let value =
            quantity.doubleValue(
                for: .kilocalorie()
            )

        return value.isFinite
            ? value
            : nil
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
    let isIndoor: Bool?

    init(workout: HKWorkout) {
        id = workout.uuid
        activity = WorkoutActivity(healthKitType: workout.workoutActivityType)
        startDate = workout.startDate
        endDate = workout.endDate
        duration = workout.duration
        distanceMeters =
            workout.athlthDistanceMeters

        activeEnergyKilocalories =
            workout
                .athlthActiveEnergyKilocalories

        let locationType =
            workout
                .workoutActivities
                .first?
                .workoutConfiguration
                .locationType

        switch locationType {
        case .indoor:
            isIndoor = true
        case .outdoor:
            isIndoor = false
        default:
            isIndoor = nil
        }
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

    func allowsTrainingPlaceCheckIn(
        isIndoor: Bool?
    ) -> Bool {
        switch self {
        case .strength,
             .hiit,
             .rowing,
             .elliptical,
             .stairClimbing,
             .yoga,
             .coreTraining:
            return true

        case .running,
             .walking,
             .cycling,
             .swimming,
             .hiking,
             .other:
            return isIndoor == true
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
        case .buildingBaseline: return ATHLTHLocalization.string( "Building baseline")
        case .ready: return ATHLTHLocalization.string( "Ready")
        case .balanced: return ATHLTHLocalization.string( "Balanced")
        case .takeItEasy: return ATHLTHLocalization.string( "Take it easier")
        case .recover: return ATHLTHLocalization.string( "Prioritize recovery")
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

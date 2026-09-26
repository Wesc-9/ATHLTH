import Foundation

struct WatchRoutePoint: Codable, Hashable {
    var latitude: Double
    var longitude: Double
    var altitude: Double?
    var sequence: Int
}

struct WatchRouteTransfer: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var distanceKilometers: Double
    var elevationGainMeters: Double?
    var points: [WatchRoutePoint]
    var updatedAt: Date
}

enum WatchWorkoutKind: String, Codable, CaseIterable, Hashable {
    case running
    case walking
    case strength
    case hiit
    case functional
    case cycling
    case rowing
    case stairClimbing
    case yoga
    case other

    var title: String {
        switch self {
        case .running: return "Run"
        case .walking: return "Walk"
        case .strength: return "Strength"
        case .hiit: return "HIIT"
        case .functional: return "Functional"
        case .cycling: return "Cycling"
        case .rowing: return "Rowing"
        case .stairClimbing: return "Stairs"
        case .yoga: return "Yoga"
        case .other: return "Workout"
        }
    }

    var systemImage: String {
        switch self {
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .strength: return "dumbbell.fill"
        case .hiit: return "figure.highintensity.intervaltraining"
        case .functional: return "figure.cross.training"
        case .cycling: return "figure.outdoor.cycle"
        case .rowing: return "figure.rower"
        case .stairClimbing: return "figure.stair.stepper"
        case .yoga: return "figure.yoga"
        case .other: return "figure.mixed.cardio"
        }
    }

    var usesOutdoorLocation: Bool {
        switch self {
        case .running, .walking, .cycling:
            return true
        case .strength, .hiit, .functional, .rowing, .stairClimbing, .yoga, .other:
            return false
        }
    }

    var supportsDistanceMetric: Bool {
        switch self {
        case .running, .walking, .cycling:
            return true
        case .strength, .hiit, .functional, .rowing, .stairClimbing, .yoga, .other:
            return false
        }
    }
}

enum WatchAudioCoachLanguage: String, Codable, CaseIterable, Hashable {
    case system
    case english = "en-US"
    case norwegian = "nb-NO"

    var title: String {
        switch self {
        case .system: return "System"
        case .english: return "English"
        case .norwegian: return "Norsk"
        }
    }
}

struct WatchAudioCoachConfiguration: Codable, Hashable {
    var enabled: Bool
    var language: WatchAudioCoachLanguage
    var distanceIntervalMeters: Double?
    var timeIntervalSeconds: TimeInterval?

    var announceDistance: Bool
    var announceElapsedTime: Bool
    var announceAveragePace: Bool
    var announceClockTime: Bool
    var announceHeartRate: Bool

    var announceRemainingRouteDistance: Bool
    var announceEstimatedRemainingRouteTime: Bool
    var routeDistanceMeters: Double?

    var announceCurrentWorkoutStep: Bool
    var announceRemainingStepTime: Bool
    var announceRemainingStepDistance: Bool

    static let disabled = WatchAudioCoachConfiguration(
        enabled: false,
        language: .system,
        distanceIntervalMeters: nil,
        timeIntervalSeconds: nil,
        announceDistance: false,
        announceElapsedTime: false,
        announceAveragePace: false,
        announceClockTime: false,
        announceHeartRate: false,
        announceRemainingRouteDistance: false,
        announceEstimatedRemainingRouteTime: false,
        routeDistanceMeters: nil,
        announceCurrentWorkoutStep: false,
        announceRemainingStepTime: false,
        announceRemainingStepDistance: false
    )
}

enum WatchRunningStepMeasure: String, Codable, Hashable {
    case distance
    case time
    case open
}

struct WatchRunningWorkoutStep: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var measure: WatchRunningStepMeasure
    var distanceMeters: Double?
    var durationSeconds: TimeInterval?
    var intensityText: String?
}

struct WatchRunningWorkoutTransfer: Codable, Hashable {
    var title: String
    var steps: [WatchRunningWorkoutStep]
}

struct WatchStrengthSessionSnapshot: Codable, Hashable {
    var workoutID: UUID
    var title: String
    var exerciseIndex: Int
    var exerciseCount: Int
    var exerciseName: String?
    var primaryMuscles: [String]
    var setIndex: Int
    var setCount: Int
    var setNumber: Int?
    var completedSets: Int
    var totalSets: Int
    var draftReps: Int
    var draftWeightKilograms: Double
    var draftRestSeconds: Int
    var isResting: Bool
    var restEndsAt: Date?
    var currentExerciseComplete: Bool
    var hasNextExercise: Bool
    var allExercisesComplete: Bool
    var updatedAt: Date
}

enum WatchStrengthCommandKind: String, Codable, Hashable {
    case updateDraft
    case completeSet
    case completeSetWithoutDetails
    case skipRest
    case addRest
    case nextExercise
    case requestSnapshot
}

struct WatchStrengthCommand: Codable, Hashable {
    var id: UUID
    var workoutID: UUID?
    var kind: WatchStrengthCommandKind
    var reps: Int?
    var weightKilograms: Double?
    var restSeconds: Int?
    var addRestSeconds: Int?
    var sentAt: Date
}

struct WatchWorkoutResult: Identifiable, Codable, Hashable {
    let id: UUID
    var kind: WatchWorkoutKind
    var healthKitWorkoutUUID: UUID?
    var startedAt: Date
    var endedAt: Date
    var duration: TimeInterval
    var activeCalories: Double
    var distanceMeters: Double
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var routePointCount: Int
}

enum WatchWorkoutMirrorState: String, Codable, Hashable {
    case preparing
    case running
    case paused
    case ending
    case completed
    case failed
}

struct WatchWorkoutLiveSnapshot: Codable, Hashable {
    var kind: WatchWorkoutKind
    var state: WatchWorkoutMirrorState
    var startedAt: Date?
    var capturedAt: Date
    var elapsedTime: TimeInterval
    var heartRate: Double
    var activeCalories: Double
    var distanceMeters: Double
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var routePointCount: Int
}

struct WatchWorkoutMirrorCommand: Codable, Hashable {
    var command: WatchWorkoutCommand
}

enum WatchWorkoutCommand: String, Codable, Hashable {
    case end
    case pause
    case resume
}

enum WatchTransferKind: String {
    case route
    case workoutResult
    case workoutCommand
    case workoutRouteSelection
    case audioCoachConfiguration
    case runningWorkout
    case strengthSnapshot
    case strengthCommand
    case connectivityProbe
    case connectivityAck
}

enum ATHLTHWorkoutMetadataKey {
    static let locationLatitude =
        "com.wesc9.athlth.workoutLocationLatitude"
    static let locationLongitude =
        "com.wesc9.athlth.workoutLocationLongitude"
    static let locationHorizontalAccuracy =
        "com.wesc9.athlth.workoutLocationHorizontalAccuracy"
}

enum WatchTransferMetadataKey {
    static let kind = "kind"
    static let routeID = "routeID"
    static let title = "title"
    static let payload = "payload"
    static let command = "command"
    static let probeID = "probeID"
    static let sentAt = "sentAt"
}

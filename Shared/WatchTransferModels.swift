import CoreLocation
import Foundation

struct WatchRoutePoint: Codable, Hashable {
    var latitude: Double
    var longitude: Double
    var altitude: Double?
    var sequence: Int
}

struct ATHLTHRouteGuidanceState: Codable, Hashable {
    var progressPercent: Double
    var remainingMeters: Double
    var deviationMeters: Double
    var traveledAlongRouteMeters: Double
    var distanceToStartMeters: Double
    var distanceToFinishMeters: Double
    var nearestRoutePointIndex: Int
}

struct ATHLTHRouteCompletionAnalysis: Codable, Hashable {
    var routeMatchPercent: Double
    var averageDeviationMeters: Double
    var maxDeviationMeters: Double
    var startDistanceMeters: Double
    var endDistanceMeters: Double

    var leaderboardEligible: Bool {
        routeMatchPercent >= 85 &&
            startDistanceMeters <= 450 &&
            endDistanceMeters <= 450
    }
}

enum ATHLTHRouteCompletionAnalyzer {
    static func analyze(
        actualLocations: [CLLocation],
        referenceLocations: [CLLocation],
        toleranceMeters: Double = 80
    ) -> ATHLTHRouteCompletionAnalysis? {
        guard actualLocations.count >= 2,
              referenceLocations.count >= 2
        else {
            return nil
        }

        let sampleStep =
            max(
                referenceLocations.count / 120,
                1
            )
        let referenceSamples =
            stride(
                from: 0,
                to: referenceLocations.count,
                by: sampleStep
            )
            .map {
                referenceLocations[$0]
            }

        guard !referenceSamples.isEmpty else {
            return nil
        }

        let nearestDistances =
            referenceSamples.map { point in
                actualLocations.lazy
                    .map {
                        $0.distance(from: point)
                    }
                    .min() ??
                    .greatestFiniteMagnitude
            }
        let finite =
            nearestDistances.filter(\.isFinite)

        guard !finite.isEmpty else {
            return nil
        }

        let matched =
            nearestDistances.filter {
                $0 <= toleranceMeters
            }.count
        let matchPercent =
            Double(matched) /
            Double(referenceSamples.count) *
            100
        let average =
            finite.reduce(0, +) /
            Double(finite.count)
        let maximum =
            finite.max() ?? 0

        let actualStart =
            actualLocations[0]
        let actualEnd =
            actualLocations[
                actualLocations.count - 1
            ]
        let referenceStart =
            referenceLocations[0]
        let referenceEnd =
            referenceLocations[
                referenceLocations.count - 1
            ]

        let forwardStart =
            actualStart.distance(
                from: referenceStart
            )
        let forwardEnd =
            actualEnd.distance(
                from: referenceEnd
            )
        let reverseStart =
            actualStart.distance(
                from: referenceEnd
            )
        let reverseEnd =
            actualEnd.distance(
                from: referenceStart
            )
        let useReverse =
            reverseStart + reverseEnd <
            forwardStart + forwardEnd

        return ATHLTHRouteCompletionAnalysis(
            routeMatchPercent:
                min(max(matchPercent, 0), 100),
            averageDeviationMeters:
                max(average, 0),
            maxDeviationMeters:
                max(maximum, 0),
            startDistanceMeters:
                useReverse
                    ? reverseStart
                    : forwardStart,
            endDistanceMeters:
                useReverse
                    ? reverseEnd
                    : forwardEnd
        )
    }
}

enum ATHLTHRouteGuidanceEngine {
    static func state(
        location: CLLocation,
        routeLocations: [CLLocation],
        cumulativeMeters: [Double],
        geometryTotalMeters: Double,
        advertisedDistanceMeters: Double?
    ) -> ATHLTHRouteGuidanceState? {
        guard routeLocations.count >= 2,
              cumulativeMeters.count == routeLocations.count
        else {
            return nil
        }

        var nearestIndex = 0
        var nearestDistance =
            Double.greatestFiniteMagnitude

        for (index, point) in
            routeLocations.enumerated()
        {
            let distance =
                location.distance(from: point)

            if distance < nearestDistance {
                nearestDistance = distance
                nearestIndex = index
            }
        }

        let geometryTotal =
            max(geometryTotalMeters, 1)
        let traveledAlongRoute =
            cumulativeMeters[nearestIndex]
        let progress =
            min(
                max(
                    traveledAlongRoute /
                        geometryTotal,
                    0
                ),
                1
            )
        let routeTotal =
            max(
                advertisedDistanceMeters ?? 0,
                0
            )
        let effectiveTotal =
            routeTotal > 0
                ? routeTotal
                : geometryTotal

        return ATHLTHRouteGuidanceState(
            progressPercent:
                progress * 100,
            remainingMeters:
                max(
                    effectiveTotal *
                        (1 - progress),
                    0
                ),
            deviationMeters:
                max(nearestDistance, 0),
            traveledAlongRouteMeters:
                max(traveledAlongRoute, 0),
            distanceToStartMeters:
                location.distance(
                    from:
                        routeLocations[0]
                ),
            distanceToFinishMeters:
                location.distance(
                    from:
                        routeLocations[
                            routeLocations.count - 1
                        ]
                ),
            nearestRoutePointIndex:
                nearestIndex
        )
    }

    static func cumulativeGeometry(
        locations: [CLLocation]
    ) -> (
        cumulativeMeters: [Double],
        totalMeters: Double
    ) {
        guard !locations.isEmpty else {
            return ([], 0)
        }

        var cumulative: [Double] = [0]
        cumulative.reserveCapacity(
            locations.count
        )

        var total: Double = 0

        if locations.count >= 2 {
            for index in 1..<locations.count {
                total += locations[index]
                    .distance(
                        from:
                            locations[index - 1]
                    )
                cumulative.append(total)
            }
        }

        return (cumulative, total)
    }
}

struct WatchRouteTransfer: Identifiable, Codable, Hashable {
    let id: UUID
    // Stable cross-user identity for comparisons. Saved copies of the same
    // shared/public route keep the original source ID here.
    var comparisonRouteID: UUID? = nil
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

    // Optional for backwards compatibility with configurations already
    // persisted or queued before music ducking was introduced.
    var duckOtherAudio: Bool? = nil
    var guidanceQuietPeriodSeconds: TimeInterval? = nil

    var shouldDuckOtherAudio: Bool {
        duckOtherAudio ?? true
    }

    var resolvedGuidanceQuietPeriodSeconds:
        TimeInterval {
        min(
            max(
                guidanceQuietPeriodSeconds ?? 10,
                0
            ),
            30
        )
    }

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

enum ATHLTHGuidancePriority:
    Int,
    Codable,
    Comparable,
    Hashable
{
    case routineCoach = 10
    case ghostPeriodic = 20
    case ghostImportant = 30
    case structuredStep = 40
    case targetCritical = 50
    case routeCritical = 60

    static func < (
        lhs: ATHLTHGuidancePriority,
        rhs: ATHLTHGuidancePriority
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var suppressesRoutineAfterDelivery: Bool {
        self >= .structuredStep
    }
}

enum ATHLTHGuidanceDeliveryDecision:
    Hashable
{
    case drop
    case deliver
    case interruptAndDeliver
}

struct ATHLTHGuidancePriorityGate:
    Hashable
{
    private(set) var activeVoicePriority:
        ATHLTHGuidancePriority?
    private(set) var suppressRoutineUntil:
        Date?

    mutating func voiceDecision(
        for priority: ATHLTHGuidancePriority,
        isSpeaking: Bool,
        quietPeriodSeconds: TimeInterval,
        now: Date = Date()
    ) -> ATHLTHGuidanceDeliveryDecision {
        if let suppressRoutineUntil,
           now < suppressRoutineUntil,
           priority <= .ghostPeriodic {
            return .drop
        }

        if isSpeaking,
           let activeVoicePriority {
            guard priority >
                    activeVoicePriority
            else {
                return .drop
            }

            noteDelivery(
                priority: priority,
                quietPeriodSeconds:
                    quietPeriodSeconds,
                now: now
            )
            return .interruptAndDeliver
        }

        noteDelivery(
            priority: priority,
            quietPeriodSeconds:
                quietPeriodSeconds,
            now: now
        )
        return .deliver
    }

    mutating func allowsHaptic(
        for priority: ATHLTHGuidancePriority,
        now: Date = Date()
    ) -> Bool {
        guard let suppressRoutineUntil,
              now < suppressRoutineUntil
        else {
            return true
        }

        return priority >
            .ghostPeriodic
    }

    mutating func voiceDidFinish() {
        activeVoicePriority = nil
    }

    mutating func reset() {
        activeVoicePriority = nil
        suppressRoutineUntil = nil
    }

    private mutating func noteDelivery(
        priority: ATHLTHGuidancePriority,
        quietPeriodSeconds: TimeInterval,
        now: Date
    ) {
        activeVoicePriority = priority

        if priority
            .suppressesRoutineAfterDelivery {
            suppressRoutineUntil =
                now.addingTimeInterval(
                    max(
                        quietPeriodSeconds,
                        0
                    )
                )
        }
    }
}

enum WatchAlertDelivery: String, Codable, CaseIterable, Hashable, Identifiable {
    case haptic
    case voice
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .haptic: return "Haptic"
        case .voice: return "Voice"
        case .both: return "Haptic + Voice"
        }
    }

    var usesHaptics: Bool {
        self == .haptic || self == .both
    }

    var usesVoice: Bool {
        self == .voice || self == .both
    }
}

struct WatchRouteAlertConfiguration: Codable, Hashable {
    var enabled: Bool
    var deviationMeters: Double
    var graceSeconds: TimeInterval
    var repeatSeconds: TimeInterval
    var delivery: WatchAlertDelivery
    var announceBackOnRoute: Bool

    static let standard = WatchRouteAlertConfiguration(
        enabled: true,
        deviationMeters: 80,
        graceSeconds: 10,
        repeatSeconds: 120,
        delivery: .both,
        announceBackOnRoute: true
    )
}

struct WatchWorkoutTargetAlertConfiguration: Codable, Hashable {
    var heartRateEnabled: Bool
    var heartRateZone: Int?
    var heartRateMinimumBPM: Double?
    var heartRateMaximumBPM: Double?

    var paceAlertsEnabled: Bool
    var paceToleranceSecondsPerKilometer: Double

    var graceSeconds: TimeInterval
    var repeatSeconds: TimeInterval
    var delivery: WatchAlertDelivery
    var announceBackInTarget: Bool
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
    var targetPaceMinSecondsPerKilometer: Double? = nil
    var targetPaceMaxSecondsPerKilometer: Double? = nil
}

enum ATHLTHRunningStepEngine {
    static func isCompleted(
        step: WatchRunningWorkoutStep,
        elapsedTime: TimeInterval,
        distanceMeters: Double,
        stepStartElapsedTime: TimeInterval,
        stepStartDistanceMeters: Double
    ) -> Bool {
        switch step.measure {
        case .time:
            guard let duration =
                    step.durationSeconds
            else {
                return false
            }

            return max(
                elapsedTime -
                    stepStartElapsedTime,
                0
            ) >= duration

        case .distance:
            guard let target =
                    step.distanceMeters
            else {
                return false
            }

            return max(
                distanceMeters -
                    stepStartDistanceMeters,
                0
            ) >= target

        case .open:
            return false
        }
    }

    static func progress(
        step: WatchRunningWorkoutStep,
        elapsedTime: TimeInterval,
        distanceMeters: Double,
        stepStartElapsedTime: TimeInterval,
        stepStartDistanceMeters: Double
    ) -> Double {
        switch step.measure {
        case .time:
            guard let target =
                    step.durationSeconds,
                  target > 0
            else {
                return 0
            }

            return min(
                max(
                    (
                        elapsedTime -
                            stepStartElapsedTime
                    ) / target,
                    0
                ),
                1
            )

        case .distance:
            guard let target =
                    step.distanceMeters,
                  target > 0
            else {
                return 0
            }

            return min(
                max(
                    (
                        distanceMeters -
                            stepStartDistanceMeters
                    ) / target,
                    0
                ),
                1
            )

        case .open:
            return 0
        }
    }
}

struct WatchRunningWorkoutTransfer: Codable, Hashable {
    var title: String
    var steps: [WatchRunningWorkoutStep]
    var routeAlerts: WatchRouteAlertConfiguration? = nil
    var targetAlerts: WatchWorkoutTargetAlertConfiguration? = nil
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

    // Optional route-completion fields keep older Watch/iPhone transfers
    // decodable while giving both devices the same route-quality summary.
    var routeMatchPercent: Double? = nil
    var routeAverageDeviationMeters: Double? = nil
    var routeMaxDeviationMeters: Double? = nil
    var routeLeaderboardEligible: Bool? = nil
    var routeComparisonID: UUID? = nil
    var routeTitle: String? = nil
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

    // Optional live GPS position used by iPhone-only presentation features
    // such as Ghost Race. Older persisted/transferred snapshots decode
    // without these fields, so this remains backwards compatible.
    var currentLatitude: Double? = nil
    var currentLongitude: Double? = nil
    var routeProgressPercent: Double? = nil

    // Stable route identity lets Live Ghost compare progress along the same
    // course instead of treating every meter run as equivalent.
    var routeComparisonID: UUID? = nil
    var routeTitle: String? = nil
    var routeDistanceMeters: Double? = nil
    var workoutDisplayTitle: String? = nil

    // Optional presentation fields for Dynamic Island, Lock Screen and Watch.
    // Defaults keep older mirrored snapshots backwards compatible.
    var currentPaceSecondsPerKilometer: TimeInterval? = nil
    var routeRemainingMeters: Double? = nil
    var routeDeviationMeters: Double? = nil
    var routeDeviationThresholdMeters: Double? = nil

    // Shared structured-running state for iPhone, Apple Watch, Lock Screen
    // and Dynamic Island. Optional defaults preserve older transfers.
    var runningStepTitle: String? = nil
    var runningStepIndex: Int? = nil
    var runningStepCount: Int? = nil
    var runningStepProgress: Double? = nil
    var runningNextStepTitle: String? = nil

    var heartRateTargetZone: Int? = nil
    var heartRateTargetMinimumBPM: Double? = nil
    var heartRateTargetMaximumBPM: Double? = nil
    var heartRateTargetStatus: String? = nil

    var ghostRaceTitle: String? = nil
    var ghostDistanceDeltaMeters: Double? = nil
    var ghostTimeDeltaSeconds: TimeInterval? = nil

    var strengthExerciseName: String? = nil
    var strengthSetIndex: Int? = nil
    var strengthSetCount: Int? = nil
    var strengthReps: Int? = nil
    var strengthWeightKilograms: Double? = nil
    var strengthRestEndsAt: Date? = nil

    var liveSurfaceConfiguration:
        ATHLTHLiveWorkoutSurfaceConfiguration? = nil
    var liveSurfaceContext:
        ATHLTHLiveWorkoutContext? = nil
}

struct WatchGhostRaceTimingPoint: Codable, Hashable {
    var elapsedTime: TimeInterval
    var cumulativeMeters: Double
}

struct WatchGhostRaceAudioConfiguration: Codable, Hashable {
    var enabled: Bool
    var distanceIntervalMeters: Double?
    var timeIntervalSeconds: TimeInterval?
    var announceLeadChanges: Bool
    var leadChangeThresholdMeters: Double

    // Legacy delivery remains encoded for transfers produced by older builds.
    // New builds separate routine race status from meaningful lead changes.
    var delivery: WatchAlertDelivery
    var periodicDelivery: WatchAlertDelivery? = nil
    var leadChangeDelivery: WatchAlertDelivery? = nil
    var importantLeadChangeDelivery: WatchAlertDelivery? = nil
    var importantLeadChangeMeters: Double? = nil

    var resolvedPeriodicDelivery:
        WatchAlertDelivery {
        periodicDelivery ?? delivery
    }

    var resolvedLeadChangeDelivery:
        WatchAlertDelivery {
        leadChangeDelivery ?? delivery
    }

    var resolvedImportantLeadChangeDelivery:
        WatchAlertDelivery {
        importantLeadChangeDelivery ??
            .both
    }

    var resolvedImportantLeadChangeMeters:
        Double {
        max(
            importantLeadChangeMeters ?? 50,
            leadChangeThresholdMeters
        )
    }

    static let standard = WatchGhostRaceAudioConfiguration(
        enabled: true,
        distanceIntervalMeters: 1_000,
        timeIntervalSeconds: nil,
        announceLeadChanges: true,
        leadChangeThresholdMeters: 25,
        delivery: .voice,
        periodicDelivery: .voice,
        leadChangeDelivery: .haptic,
        importantLeadChangeDelivery: .both,
        importantLeadChangeMeters: 50
    )
}

struct WatchGhostRaceTransfer: Codable, Hashable {
    var title: String
    var referenceDuration: TimeInterval
    var routeDistanceMeters: Double
    var points: [WatchGhostRaceTimingPoint]
    var audio: WatchGhostRaceAudioConfiguration? = nil
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
    case ghostRace
    case liveSurfaceConfiguration
    case liveSurfaceContext
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

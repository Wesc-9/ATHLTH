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
              referenceLocations.count >= 2,
              let match =
                RoutePerformanceMatcher
                    .analyze(
                        reference:
                            referenceLocations,
                        actual:
                            actualLocations
                    )
        else {
            return nil
        }

        // Kept in the public signature for compatibility with older call
        // sites. Matching is now soft/bidirectional rather than binary at a
        // single tolerance threshold.
        _ = toleranceMeters

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
                match.routeMatchPercent,
            averageDeviationMeters:
                match.averageDeviationMeters,
            maxDeviationMeters:
                match.maxDeviationMeters,
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
        advertisedDistanceMeters: Double?,
        workoutDistanceMeters: Double? = nil,
        previousRouteMeters: Double? = nil,
        courseAnchorMeters: Double? = nil,
        secondsSinceCourseAnchor: TimeInterval? = nil
    ) -> ATHLTHRouteGuidanceState? {
        guard routeLocations.count >= 2,
              cumulativeMeters.count == routeLocations.count,
              geometryTotalMeters.isFinite, geometryTotalMeters > 0
        else {
            return nil
        }

        // A route can return to its start or cross itself. Geographical
        // proximity alone MUST NOT choose the finish when the workout has
        // just begun. Real workout distance anchors us near the beginning
        // and only makes later route segments eligible as we run.
        // With a route-based Ghost, HealthKit workout distance is NOT the
        // athlete's distance completed on the planned course. Detours may
        // add many kilometres. Search only course positions physically
        // reachable since the last trusted on-route fix instead.
        let anchor = courseAnchorMeters.flatMap {
            $0.isFinite && $0 >= 0 ? min($0, geometryTotalMeters) : nil
        }
        let measuredWorkoutDistance = workoutDistanceMeters.flatMap {
            $0.isFinite && $0 >= 0 ? $0 : nil
        }
        let forwardLimit: Double
        if let anchor {
            let seconds = max(0, min(secondsSinceCourseAnchor ?? 0, 86_400))
            forwardLimit = min(
                geometryTotalMeters, anchor + max(90, 35 + seconds * 9)
            )
        } else if let measuredWorkoutDistance {
            let tolerance = max(75, min(measuredWorkoutDistance * 0.10, 180))
            forwardLimit = min(
                geometryTotalMeters,
                measuredWorkoutDistance + tolerance
            )
        } else {
            // Preserve earlier callers with no distance and no Ghost anchor.
            forwardLimit = geometryTotalMeters
        }

        let stablePrevious = anchor ?? previousRouteMeters.flatMap {
            $0.isFinite && $0 >= 0 && $0 <= forwardLimit + 75
                ? $0 : nil
        }
        // Intersections and routes returning to their start must not allow
        // a GPS fix to credit earlier/later legs merely because they overlap.
        let backwardLimit = stablePrevious.map {
            max(0, $0 - (anchor == nil ? 85 : 35))
        } ?? 0

        // Compare to continuous route SEGMENTS, not only recorded points.
        // Sparse GPX/MapKit waypoints could previously report a runner
        // 180 m off-route while standing on a long straight between them.
        // Progress bounds are applied to the projected location on each
        // segment, preserving out-and-back and self-crossing safeguards.
        var nearestIndex: Int?
        var nearestRouteMeters = 0.0
        var nearestDistance = Double.greatestFiniteMagnitude
        var bestScore = Double.greatestFiniteMagnitude

        let origin = location.coordinate
        let radiansPerDegree = Double.pi / 180.0
        let earthRadiusMeters = 6_371_000.0
        let longitudeScale = cos(origin.latitude * radiansPerDegree)
        func localPoint(_ point: CLLocation) -> (x: Double, y: Double) {
            let deltaLongitude = (point.coordinate.longitude -
                origin.longitude) * radiansPerDegree
            let wrappedLongitude = atan2(
                sin(deltaLongitude), cos(deltaLongitude)
            )
            return (
                x: earthRadiusMeters * wrappedLongitude * longitudeScale,
                y: earthRadiusMeters *
                    (point.coordinate.latitude - origin.latitude) *
                    radiansPerDegree
            )
        }

        for index in 0..<(routeLocations.count - 1) {
            let fromMeters = cumulativeMeters[index]
            let toMeters = cumulativeMeters[index + 1]
            guard fromMeters.isFinite, toMeters.isFinite,
                  toMeters >= fromMeters,
                  toMeters >= backwardLimit,
                  fromMeters <= forwardLimit
            else { continue }

            let from = localPoint(routeLocations[index])
            let to = localPoint(routeLocations[index + 1])
            let deltaX = to.x - from.x
            let deltaY = to.y - from.y
            let squaredLength = deltaX * deltaX + deltaY * deltaY
            let span = toMeters - fromMeters

            let lowerT = span > 0
                ? max(0, (backwardLimit - fromMeters) / span) : 0.0
            let upperT = span > 0
                ? min(1, (forwardLimit - fromMeters) / span) : 1.0
            guard lowerT <= upperT else { continue }

            let unconstrainedT = squaredLength > 0.01
                ? -(from.x * deltaX + from.y * deltaY) / squaredLength
                : 0.0
            let t = min(max(unconstrainedT, lowerT), upperT)
            let distance = hypot(from.x + t * deltaX, from.y + t * deltaY)
            guard distance.isFinite else { continue }

            let routeMeters = fromMeters + t * span
            let progressPenalty: Double
            if anchor != nil {
                progressPenalty = 0
            } else {
                progressPenalty = measuredWorkoutDistance.map {
                    abs(routeMeters - min($0, geometryTotalMeters)) * 0.12
                } ?? 0
            }
            let continuityPenalty = stablePrevious.map {
                abs(routeMeters - $0) * (anchor == nil ? 0.015 : 0.035)
            } ?? 0
            let score = distance + progressPenalty + continuityPenalty

            if score < bestScore {
                bestScore = score
                nearestDistance = distance
                nearestRouteMeters = routeMeters
                nearestIndex = t <= 0.5 ? index : index + 1
            }
        }

        guard let nearestIndex else { return nil }

        let geometryTotal = max(geometryTotalMeters, 1)
        let traveledAlongRoute = nearestRouteMeters
        let progress = min(max(traveledAlongRoute / geometryTotal, 0), 1)
        let routeTotal = max(advertisedDistanceMeters ?? 0, 0)
        let effectiveTotal = routeTotal > 0 ? routeTotal : geometryTotal

        return ATHLTHRouteGuidanceState(
            progressPercent: progress * 100,
            remainingMeters: max(effectiveTotal * (1 - progress), 0),
            deviationMeters: max(nearestDistance, 0),
            traveledAlongRouteMeters: max(traveledAlongRoute, 0),
            distanceToStartMeters: location.distance(from: routeLocations[0]),
            distanceToFinishMeters: location.distance(from: routeLocations[routeLocations.count - 1]),
            nearestRoutePointIndex: nearestIndex
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

/// A single HealthKit workout runs from the user's start until the user's
/// explicit finish. Internal set timers, strength rests, exercise switches and
/// recovery intervals must never be translated to a workout-session pause.
/// Global pause remains a deliberate action; automatic pause is limited to
/// outdoor running/walking when the athlete enables it.
/// Reject a second Watch START before altering the active source session's
/// route, Audio Coach, strength queue, owner or recovery checkpoint.
/// This is a preflight only; HealthKit remains the single recorder.
enum ATHLTHWatchWorkoutStartAdmissionPolicy {
    static func canPrepare(
        active: Bool,
        preparing: Bool,
        ending: Bool,
        finishing: Bool,
        recovering: Bool = false,
        hasExistingSession: Bool = false
    ) -> Bool {
        !active && !preparing && !ending && !finishing &&
            !recovering && !hasExistingSession
    }
}

/// Only the original finish delegate may release a live HealthKit recorder.
enum ATHLTHWatchWorkoutResetPolicy {
    static func mayClear(
        active: Bool, preparing: Bool, ending: Bool,
        finishing: Bool, recovering: Bool,
        healthKitSessionInProgress: Bool
    ) -> Bool {
        !active && !preparing && !ending && !finishing &&
            !recovering && !healthKitSessionInProgress
    }
}

/// Failed start must not leave a phantom checkpoint; failed save must not
/// discard the last durable identity of an already-started HKWorkoutSession.
enum ATHLTHWatchWorkoutFailureRecoveryPolicy {
    static func shouldRetainCheckpoint(
        hasBuilder: Bool,
        hasOriginalStart: Bool,
        healthKitStartedOrEnded: Bool
    ) -> Bool {
        hasBuilder && hasOriginalStart && healthKitStartedOrEnded
    }
}

enum ATHLTHWorkoutHealthKitContinuityPolicy {
    static func supportsAutomaticPause(_ kind: WatchWorkoutKind) -> Bool {
        kind == .running || kind == .walking
    }

    static func mayAutoPause(
        kind: WatchWorkoutKind,
        hasStructuredIntervals: Bool
    ) -> Bool {
        supportsAutomaticPause(kind) && !hasStructuredIntervals
    }

    /// Modes without automatic pause should never silently remain paused
    /// by a stray HealthKit/system event. Explicit full-workout pause wins.
    static func shouldResumeUnexpectedPause(
        kind: WatchWorkoutKind,
        userPausedWholeWorkout: Bool,
        finishing: Bool
    ) -> Bool {
        !supportsAutomaticPause(kind) &&
            !userPausedWholeWorkout && !finishing
    }

    static func pausesWorkoutForInternalRecoveryOrRest(
        kind: WatchWorkoutKind
    ) -> Bool {
        false
    }
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
        case .running: return ATHLTHLocalization.string( "Run")
        case .walking: return ATHLTHLocalization.string( "Walk")
        case .strength: return ATHLTHLocalization.string( "Strength")
        case .hiit: return ATHLTHLocalization.string( "HIIT")
        case .functional: return ATHLTHLocalization.string( "Functional")
        case .cycling: return ATHLTHLocalization.string( "Cycling")
        case .rowing: return ATHLTHLocalization.string( "Rowing")
        case .stairClimbing: return ATHLTHLocalization.string( "Stairs")
        case .yoga: return ATHLTHLocalization.string( "Yoga")
        case .other: return ATHLTHLocalization.string( "Workout")
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
        case .system: return ATHLTHLocalization.string( "System")
        case .english: return ATHLTHLocalization.string( "English")
        case .norwegian: return ATHLTHLocalization.string( "Norsk")
        }
    }
}

/// Voice output is separate from the device that records the HealthKit workout.
enum ATHLTHAudioCoachOutputPreference: String, Codable, Hashable, CaseIterable {
    case automatic
    case iPhone
    case appleWatch
}

struct WatchAudioCoachConfiguration: Codable, Hashable {
    var enabled: Bool
    var language: WatchAudioCoachLanguage
    var distanceIntervalMeters: Double?
    var timeIntervalSeconds: TimeInterval?
    // An optional ruleset keeps previously persisted and Watch transfers
    // backwards compatible. Each metric has its own cadence.
    var customRules: [ATHLTHAudioCoachRule]? = nil
    var coachGroups: [ATHLTHAudioCoachGroup]? = nil
    // Motivation, varied encouragements and user-selected GPS landmarks.
    // Optional so older persisted configurations still decode.
    var smartPrompts: ATHLTHAudioCoachSmartSettings? = nil

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
    // persisted or queued before these Audio Coach controls were introduced.
    var duckOtherAudio: Bool? = nil
    // Optional for decoding old iPhone/Watch sessions. Temporarily interrupt
    // other audio while a Coach cue speaks; restore at cue completion.
    var muteOtherAudio: Bool? = nil
    var guidanceQuietPeriodSeconds: TimeInterval? = nil
    var voiceIdentifier: String? = nil
    var speechRate: Float? = nil
    var speechVolume: Float? = nil
    var speechStyle: ATHLTHCoachSpeechStyle? = nil
    var announceWorkoutStart: Bool? = nil
    var announcePauseResume: Bool? = nil
    var announceWorkoutComplete: Bool? = nil

    // Voice-only Fuel & Hydration reminders. Nil disables them and keeps
    // payloads from older iPhone/Watch builds backward compatible.
    var fuelReminderIntervalMinutes: Int? = nil
    var fuelReminderDurationMinutes: Int? = nil
    var fuelCarbohydrateGramsPerHour: Int? = nil
    var fuelFluidMLPerHour: Int? = nil

    // When a workout was launched from iPhone, iPhone owns spoken guidance
    // while WatchConnectivity remains reachable so Spotify/AirPods can stay on
    // the phone. Watch automatically becomes the voice fallback if the phone
    // leaves range. Optional keeps older payloads fully compatible.
    var preferIPhoneAudioWhenReachable: Bool? = nil

    /// Optional so previously saved workout plans remain readable. Watch-only
    /// is respected even when an older launch explicitly preferred iPhone.
    var outputPreference: ATHLTHAudioCoachOutputPreference? = nil

    // The iPhone sets this on newly prepared mirrored workouts. Old iPhone
    // versions omit it; Watch then follows the previous reachability rule
    // rather than speaking simultaneously with a legacy mirrored phone.
    var useAcknowledgedVoiceLease: Bool? = nil

    var shouldPreferIPhoneAudioWhenReachable: Bool {
        if let outputPreference {
            return outputPreference != .appleWatch
        }
        return preferIPhoneAudioWhenReachable ?? false
    }

    var shouldUseAcknowledgedVoiceLease: Bool {
        // New sessions must never infer voice ownership from WC reachability.
        outputPreference != nil || (useAcknowledgedVoiceLease ?? false)
    }

    // Strength-specific Audio Coach cues. Optional fields keep older queued
    // Watch payloads and persisted configurations backwards compatible.
    var announceStrengthSetComplete: Bool? = nil
    var announceStrengthRestStarted: Bool? = nil
    var announceStrengthRestCountdown: Bool? = nil
    var announceStrengthRestComplete: Bool? = nil
    var announceStrengthNextExercise: Bool? = nil
    var announceStrengthNextSetDetails: Bool? = nil
    var announceStrengthExerciseProgress: Bool? = nil
    var strengthStatusIntervalSeconds: TimeInterval? = nil
    var strengthRestCountdownSeconds: Int? = nil
    var strengthHapticsEnabled: Bool? = nil
    // Strength-only optional cues, never interpreted by run/walk audio.
    var announceStrengthExerciseComplete: Bool? = nil
    var strengthMotivationEverySets: Int? = nil
    var strengthPersonalMotivationPhrase: String? = nil
    var strengthCountdownToRestSeconds: Int? = nil
    var strengthCountdownFromRestSeconds: Int? = nil
    var strengthAfterCountdownToRest: ATHLTHCoachCountdownAfter? = nil
    var strengthAfterCountdownFromRest: ATHLTHCoachCountdownAfter? = nil
    // Optional cross-mode scope rules; nil keeps old Watch payload decoding.
    var boundaryCountdownRules: [ATHLTHCoachBoundaryCountdownRule]? = nil
    // Running/walking interval recovery only. Manual workout pause is distinct.
    var intervalCountdownToRecoverySeconds: Int? = nil
    var intervalCountdownFromRecoverySeconds: Int? = nil
    var intervalAfterCountdownToRecovery: ATHLTHCoachCountdownAfter? = nil
    var intervalAfterCountdownFromRecovery: ATHLTHCoachCountdownAfter? = nil

    var resolvedFuelIntervalSeconds: TimeInterval? {
        guard enabled,
              let minutes = fuelReminderIntervalMinutes,
              (10...60).contains(minutes),
              let duration = fuelReminderDurationMinutes,
              (30...480).contains(duration),
              let carbohydrate = fuelCarbohydrateGramsPerHour,
              (0...120).contains(carbohydrate),
              let fluid = fuelFluidMLPerHour,
              (0...1500).contains(fluid),
              carbohydrate > 0 || fluid > 0
        else { return nil }
        return TimeInterval(minutes * 60)
    }

    var resolvedFuelDurationSeconds: TimeInterval {
        TimeInterval(min(max(fuelReminderDurationMinutes ?? 120, 30), 480) * 60)
    }

    var shouldDuckOtherAudio: Bool {
        duckOtherAudio ?? true
    }

    var shouldMuteOtherAudio: Bool {
        muteOtherAudio ?? false
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

    var resolvedSpeechRate: Float {
        min(
            max(
                speechRate ?? 0.48,
                0.35
            ),
            0.65
        )
    }

    var resolvedSpeechVolume: Float {
        min(
            max(
                speechVolume ?? 1.0,
                0.2
            ),
            1.0
        )
    }

    var shouldAnnounceWorkoutStart: Bool {
        announceWorkoutStart ?? true
    }

    var shouldAnnouncePauseResume: Bool {
        announcePauseResume ?? true
    }

    var shouldAnnounceWorkoutComplete: Bool {
        announceWorkoutComplete ?? true
    }

    var shouldAnnounceStrengthSetComplete: Bool {
        announceStrengthSetComplete ?? false
    }

    var shouldAnnounceStrengthRestStarted: Bool {
        announceStrengthRestStarted ?? false
    }

    var shouldAnnounceStrengthRestCountdown: Bool {
        announceStrengthRestCountdown ?? false
    }

    var shouldAnnounceStrengthRestComplete: Bool {
        announceStrengthRestComplete ?? false
    }

    var shouldAnnounceStrengthNextExercise: Bool {
        announceStrengthNextExercise ?? false
    }

    var shouldAnnounceStrengthNextSetDetails: Bool {
        announceStrengthNextSetDetails ?? true
    }

    var shouldAnnounceStrengthExerciseProgress: Bool {
        announceStrengthExerciseProgress ?? false
    }

    var shouldAnnounceStrengthExerciseComplete: Bool {
        announceStrengthExerciseComplete ?? false
    }

    var resolvedStrengthMotivationEverySets: Int? {
        guard let count = strengthMotivationEverySets, (1...10).contains(count) else { return nil }
        return count
    }

    var resolvedStrengthCountdownToRest: Int? {
        guard let seconds = strengthCountdownToRestSeconds, (1...30).contains(seconds) else { return nil }
        return seconds
    }
    var resolvedStrengthCountdownFromRest: Int? {
        guard let seconds = strengthCountdownFromRestSeconds, (1...30).contains(seconds) else { return nil }
        return seconds
    }
    var resolvedIntervalCountdownToRecovery: Int? {
        guard let seconds = intervalCountdownToRecoverySeconds ??
            smartPrompts?.intervalCountdownToRecoverySeconds,
            (1...30).contains(seconds) else { return nil }
        return seconds
    }
    var resolvedIntervalCountdownFromRecovery: Int? {
        guard let seconds = intervalCountdownFromRecoverySeconds ??
            smartPrompts?.intervalCountdownFromRecoverySeconds,
            (1...30).contains(seconds) else { return nil }
        return seconds
    }

    var resolvedIntervalAfterCountdownToRecovery: ATHLTHCoachCountdownAfter {
        intervalAfterCountdownToRecovery ??
            smartPrompts?.intervalAfterCountdownToRecovery ?? .shortAlert
    }
    var resolvedIntervalAfterCountdownFromRecovery: ATHLTHCoachCountdownAfter {
        intervalAfterCountdownFromRecovery ??
            smartPrompts?.intervalAfterCountdownFromRecovery ?? .nextStep
    }

    var effectiveBoundaryCountdownRules: [ATHLTHCoachBoundaryCountdownRule] {
        Array((boundaryCountdownRules ?? smartPrompts?.boundaryCountdownRules ?? [])
            .filter { $0.resolvedSeconds != nil }.prefix(20))
    }

    var resolvedStrengthRestCountdownSeconds: Int {
        min(max(strengthRestCountdownSeconds ?? 10, 3), 30)
    }

    var shouldUseStrengthHaptics: Bool {
        strengthHapticsEnabled ?? true
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

/// Both Watch and mirrored iPhone use the same elapsed-workout schedule.
/// Never creates a notification or assumes nutrition amounts are medical advice.
enum ATHLTHFuelVoicePrompt {
    static func nextDue(after elapsed: TimeInterval,
                        config: WatchAudioCoachConfiguration) -> TimeInterval? {
        guard let interval = config.resolvedFuelIntervalSeconds,
              elapsed.isFinite, elapsed >= 0
        else { return nil }
        let next = (floor(elapsed / interval) + 1) * interval
        return next < config.resolvedFuelDurationSeconds ? next : nil
    }

    /// Do not read a long-overdue reminder after resume, reconnection, mute
    /// or voice-ownership handoff. Both devices share this exact policy.
    static func isFreshDue(
        elapsed: TimeInterval,
        scheduled: TimeInterval
    ) -> Bool {
        elapsed.isFinite &&
        scheduled.isFinite &&
        elapsed >= scheduled &&
        elapsed - scheduled <= 12
    }

    static func phrase(config: WatchAudioCoachConfiguration) -> String? {
        guard let interval = config.resolvedFuelIntervalSeconds else {
            return nil
        }
        let minutes = Int(interval / 60)
        let fluid = Int((Double(config.fuelFluidMLPerHour ?? 0)
                         * Double(minutes) / 60).rounded())
        let carbs = Int((Double(config.fuelCarbohydrateGramsPerHour ?? 0)
                         * Double(minutes) / 60).rounded())
        let norwegian: Bool
        switch config.language {
        case .norwegian: norwegian = true
        case .english: norwegian = false
        case .system: norwegian = Locale.current.language.languageCode?.identifier == "nb"
            || Locale.current.language.languageCode?.identifier == "nn"
        }
        if carbs > 0 && fluid > 0 {
            return norwegian
                ? "Påminnelse: drikk omtrent \(fluid) milliliter og få i deg omtrent \(carbs) gram karbohydrater, etter din egen plan."
                : "Reminder: about \(fluid) milliliters of fluid and \(carbs) grams of carbohydrates, according to your plan."
        }
        if fluid > 0 {
            return norwegian
                ? "Påminnelse: drikk omtrent \(fluid) milliliter, etter din egen plan."
                : "Reminder: about \(fluid) milliliters of fluid, according to your plan."
        }
        if carbs > 0 {
            return norwegian
                ? "Påminnelse: få i deg omtrent \(carbs) gram karbohydrater, etter din egen plan."
                : "Reminder: about \(carbs) grams of carbohydrates, according to your plan."
        }
        return nil
    }
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

/// Determines which device should deliver each category of Audio Coach cue.
///
/// Reachable iPhone mirroring currently reproduces routine run updates and
/// structured run-step transitions. Target/route/Ghost alerts originate on
/// Watch, and strength cues are also Watch-only. Those must not be silenced
/// just because WatchConnectivity says the phone is reachable.
///
/// This policy is deliberately pure so routing decisions can be regression
/// tested without an active HealthKit workout or an audio route.
/// Short lived, session-bound claim for ordinary mirrored Audio Coach speech.
/// Only an acknowledged claim allows iPhone to become the voice owner.
/// Older Watch/iPhone builds ignore these standalone JSON messages.
/// Sent ONLY over the already mirrored HealthKit workout. A Watch-launched
/// workout can prepare the companion's coach without a second recorder or
/// a phone-originated launch. Never persist or send through account relay.
struct ATHLTHAudioCoachMirrorInvitation: Codable, Hashable {
    var workoutStartedAt: Date
    var sentAt: Date
    var configuration: WatchAudioCoachConfiguration

    func isValid(for start: Date?, now: Date = Date()) -> Bool {
        guard let start,
              abs(start.timeIntervalSince(workoutStartedAt)) <= 1,
              now.timeIntervalSince(sentAt) >= -2,
              now.timeIntervalSince(sentAt) <= 15,
              configuration.enabled,
              configuration.shouldPreferIPhoneAudioWhenReachable,
              configuration.shouldUseAcknowledgedVoiceLease
        else { return false }
        return true
    }
}

/// A connected iPhone is not necessarily the user's audio output. Automatic
/// routing requires a real external output, not proximity alone. An explicit
/// iPhone preference may also use the built-in speaker.
enum ATHLTHCoachPhoneOutputPolicy {
    static func permitsPhone(
        preference: ATHLTHAudioCoachOutputPreference,
        externalOutputAvailable: Bool
    ) -> Bool {
        switch preference {
        case .automatic: return externalOutputAvailable
        case .iPhone: return true
        case .appleWatch: return false
        }
    }
}

struct ATHLTHAudioCoachLeaseOffer: Codable, Hashable {
    var generationID: UUID
    var requestID: UUID
    var workoutStartedAt: Date
    var issuedAt: Date
}

struct ATHLTHAudioCoachLeaseAcknowledgement: Codable, Hashable {
    var generationID: UUID
    var requestID: UUID
    var workoutStartedAt: Date
    var acknowledgedAt: Date
}

struct ATHLTHAudioCoachVoiceLease {
    static let duration: TimeInterval = 6
    static let offerMaximumAge: TimeInterval = 4

    private(set) var expiresAt: Date?
    private var latestOfferDate: Date?

    mutating func grant(
        offer: ATHLTHAudioCoachLeaseOffer,
        workoutStartedAt: Date?,
        eligible: Bool,
        now: Date = Date()
    ) -> ATHLTHAudioCoachLeaseAcknowledgement? {
        guard eligible,
              let workoutStartedAt,
              abs(workoutStartedAt.timeIntervalSince(
                  offer.workoutStartedAt
              )) <= 1,
              now.timeIntervalSince(offer.issuedAt) >= -2,
              now.timeIntervalSince(offer.issuedAt) <= Self.offerMaximumAge,
              latestOfferDate.map({ offer.issuedAt >= $0 }) ?? true
        else {
            return nil
        }

        latestOfferDate = offer.issuedAt
        expiresAt = now.addingTimeInterval(Self.duration)
        return ATHLTHAudioCoachLeaseAcknowledgement(
            generationID: offer.generationID,
            requestID: offer.requestID,
            workoutStartedAt: workoutStartedAt,
            acknowledgedAt: now
        )
    }

    func isActive(at now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return now < expiresAt
    }

    mutating func reset() {
        expiresAt = nil
        latestOfferDate = nil
    }
}

enum ATHLTHAudioCoachVoiceRouting {
    static func shouldSpeakOnWatch(
        configuration: WatchAudioCoachConfiguration,
        workoutKind: WatchWorkoutKind,
        priority: ATHLTHGuidancePriority,
        iPhoneVoiceLeaseActive: Bool
    ) -> Bool {
        guard configuration.shouldPreferIPhoneAudioWhenReachable,
              iPhoneVoiceLeaseActive
        else {
            return true
        }

        // The mirrored iPhone Audio Coach only speaks running/walking cues.
        // Preserve the full strength experience on Watch.
        if workoutKind == .strength {
            return true
        }

        // These categories have no equivalent spoken event in the mirrored
        // iPhone coach. Keeping them on Watch avoids silent critical alerts.
        switch priority {
        case .ghostPeriodic, .ghostImportant, .targetCritical, .routeCritical:
            return true
        case .routineCoach, .structuredStep:
            return false
        }
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
        case .haptic: return ATHLTHLocalization.string( "Haptic")
        case .voice: return ATHLTHLocalization.string( "Voice")
        case .both: return ATHLTHLocalization.string( "Haptic + Voice")
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
    // Optional fields preserve older persisted workouts and Watch transfers.
    var announceUpcomingTurns: Bool? = nil
    var turnCueLeadMeters: Double? = nil

    var shouldAnnounceUpcomingTurns: Bool { announceUpcomingTurns ?? true }
    var resolvedTurnCueLeadMeters: Double {
        let value = turnCueLeadMeters ?? 85
        return value.isFinite ? min(max(value, 40), 140) : 85
    }

    /// Shared turn-warning window for the Watch cue engine. No street-level
    /// routing is inferred from the route polyline.
    func shouldAnnounceTurn(distanceMeters: Double) -> Bool {
        guard enabled, shouldAnnounceUpcomingTurns,
              distanceMeters.isFinite else { return false }
        let lead = resolvedTurnCueLeadMeters
        return (max(20, lead - 60)...lead).contains(distanceMeters)
    }

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
    /// Work, recovery, warmup, or cooldown. Optional for older transfers.
    var phase: String? = nil
    var targetHeartRateZone: Int? = nil
    /// Optional authored interval spanning more than one of the five zones.
    /// For example 50–70% HRmax is Z1–Z2; a single zone integer cannot
    /// represent this prescription. Optional for older Watch transfers.
    var targetHeartRatePercentMin: Double? = nil
    var targetHeartRatePercentMax: Double? = nil
    /// Planned belt incline; not a measured workout metric.
    var targetTreadmillInclinePercent: Double? = nil
    var ghostPaceSecondsPerKilometer: Double? = nil
    /// Optional on old Watch transfers. In recovery the pacer follows actual
    /// reduced speed without imposing a work-pace target.
    var ghostFollowsRecovery: Bool? = nil
    var ghostRecoverySlowdownPercent: Int? = nil
    var coachBrief: String? = nil
    var intervalMotivation: ATHLTHIntervalMotivationSettings? = nil
    var recoveryStyle: ATHLTHRunningRecoveryStyle? = nil
    var coachGroupID: UUID? = nil
    var spokenReport: ATHLTHIntervalSpokenReport? = nil
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

    static func overallProgress(
        steps: [WatchRunningWorkoutStep],
        index: Int,
        currentStepProgress: Double
    ) -> Double {
        guard !steps.isEmpty else { return 0 }
        let weights = steps.map { step -> Double in
            let expectedSeconds = step.durationSeconds ??
                step.distanceMeters.map {
                    ($0 / 1_000) * (step.targetPaceMinSecondsPerKilometer ?? 360)
                } ?? 60
            return expectedSeconds.isFinite ? max(expectedSeconds, 15) : 60
        }
        let total = weights.reduce(0, +)
        guard total > 0 else { return 0 }
        let complete = weights.prefix(max(0, min(index, weights.count))).reduce(0, +)
        let active = weights.indices.contains(index) ? weights[index] : 0
        return min(max((complete + active * min(max(currentStepProgress, 0), 1)) / total, 0), 1)
    }
}

/// User-entered belt speed at an active elapsed second, not Watch sensor data.
struct WatchBeltSpeedPoint: Codable, Hashable {
    var activeElapsedSeconds: TimeInterval
    var kilometersPerHour: Double
}

enum ATHLTHBeltSpeedPolicy {
    static func speed(forPace secondsPerKilometer: Double?) -> Double? {
        guard let pace = secondsPerKilometer, pace.isFinite, pace > 0 else {
            return nil
        }
        let speed = 3_600 / pace
        guard (0.1...30).contains(speed) else { return nil }
        return (speed * 10).rounded() / 10
    }
}

struct WatchRunningWorkoutTransfer: Codable, Hashable {
    var title: String
    var steps: [WatchRunningWorkoutStep]
    // Stable source identity so completed interval evidence can be associated
    // with the planned workout, even when it was started on Apple Watch.
    var sourceWorkoutID: UUID? = nil
    var routeAlerts: WatchRouteAlertConfiguration? = nil
    var targetAlerts: WatchWorkoutTargetAlertConfiguration? = nil
    /// Athlete's configured or age-estimated HRmax for per-step Z1–Z5
    /// target speech. Optional to preserve previously saved Watch transfers.
    var heartRateZoneMaximumBPM: Double? = nil
    // Non-nil means this is an indoor treadmill run, including a valid 0%.
    // Optional keeps transfers from older builds decodable.
    var treadmillInclinePercent: Double? = nil
    /// Athlete-entered treadmill belt speed. Never automatic sensor speed.
    var initialBeltSpeedKilometersPerHour: Double? = nil
    var quickBeltSpeedsKilometersPerHour: [Double]? = nil
    // Optional keeps payloads from older builds decodable. The sender resolves
    // app default vs per-workout override before launch.
    var autoPauseEnabled: Bool? = nil
    /// Automatic timed-step progression is the existing default for old plans.
    var autoAdvanceTimedSteps: Bool? = nil
    var autoStartMainAfterWarmup: Bool? = nil
    /// Route progress and navigation begin only after an optional warm-up.
    /// Nil is the legacy behavior: guidance starts with the workout.
    var deferRouteUntilMain: Bool? = nil
    var intervalCoachCueEverySeconds: TimeInterval? = nil
    var intervalCoachCountdownSeconds: TimeInterval? = nil
}


enum WatchWorkoutStartMode: String, CaseIterable, Identifiable, Codable, Hashable {
    case immediate
    case afterThirtySeconds
    case onWatch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .immediate:
            return ATHLTHLocalization.choose(english: "Now", norwegian: "Nå")
        case .afterThirtySeconds:
            return ATHLTHLocalization.choose(english: "30 sec", norwegian: "30 sek")
        case .onWatch:
            return ATHLTHLocalization.choose(english: "On Watch", norwegian: "På klokken")
        }
    }

    var detail: String {
        switch self {
        case .immediate:
            return ATHLTHLocalization.choose(
                english: "Starts automatically on Apple Watch.",
                norwegian: "Starter automatisk på Apple Watch."
            )
        case .afterThirtySeconds:
            return ATHLTHLocalization.choose(
                english: "Apple Watch counts down 30 seconds before recording starts.",
                norwegian: "Apple Watch teller ned 30 sekunder før registreringen starter."
            )
        case .onWatch:
            return ATHLTHLocalization.choose(
                english: "The workout stays ready until you tap START on Apple Watch.",
                norwegian: "Økten ligger klar til du trykker START på Apple Watch."
            )
        }
    }

    var confirmationText: String {
        switch self {
        case .immediate:
            return ATHLTHLocalization.choose(
                english: "Starting workout on Apple Watch.",
                norwegian: "Starter økten på Apple Watch."
            )
        case .afterThirtySeconds:
            return ATHLTHLocalization.choose(
                english: "Apple Watch will start your workout in 30 seconds.",
                norwegian: "Apple Watch starter økten om 30 sekunder."
            )
        case .onWatch:
            return ATHLTHLocalization.choose(
                english: "Workout ready on Apple Watch. Press START when you're ready.",
                norwegian: "Økten ligger klar på Apple Watch. Trykk START når du er klar."
            )
        }
    }
}

struct WatchPreparedWorkoutTransfer: Codable, Hashable {
    var id: UUID
    var title: String
    var summary: String
    var kind: WatchWorkoutKind
    var routeID: UUID?
    var runningWorkout: WatchRunningWorkoutTransfer?
    var audioCoach: WatchAudioCoachConfiguration?
    var ghostRace: WatchGhostRaceTransfer? = nil
    var indoor: Bool? = nil
    // Optional for backwards-compatible decoding of transfers from older builds.
    var startMode: WatchWorkoutStartMode? = nil
    // Optional and backwards-compatible: full planned strength prescription.
    var strengthWorkout: WatchStrengthSessionSnapshot? = nil
    // The original plan/session identities, never the temporary prepared-card
    // UUID. Both are optional for legacy and free Quick Train workouts.
    var plannedPlanID: UUID? = nil
    var plannedSessionID: UUID? = nil
    var updatedAt: Date
}

/// A planned Watch transfer must contain the complete original link;
/// a half-linked recipe must never be accepted as an ordinary free workout.
enum ATHLTHWatchPreparedPlanIdentityPolicy {
    static func allows(planID: UUID?, sessionID: UUID?) -> Bool {
        (planID == nil) == (sessionID == nil)
    }
}

/// Remote auto-start MUST retain its iPad/iPhone relay identity; pressing
/// START on the Watch is a genuinely local start with separate semantics.
enum ATHLTHWatchPreparedLaunchOriginPolicy {
    static func startedLocallyOnWatch(initiatedByIPhone: Bool) -> Bool {
        !initiatedByIPhone
    }
}

/// An offline recovery checkpoint may only restore plan, relay, owner and
/// stage identity into the original matched HealthKit workout. A stale
/// checkpoint from another activity must never claim the new session.
enum ATHLTHWatchRecoveredIdentityPolicy {
    static func matchesOriginalSession(
        expectedKind: WatchWorkoutKind,
        savedKind: WatchWorkoutKind,
        healthKitStartedAt: Date?,
        savedStartedAt: Date?
    ) -> Bool {
        guard expectedKind == savedKind,
              let actual = healthKitStartedAt,
              let saved = savedStartedAt,
              actual.timeIntervalSince1970.isFinite,
              saved.timeIntervalSince1970.isFinite
        else { return false }
        return abs(actual.timeIntervalSince(saved)) <= 5
    }
}

/// The final HealthKit callback is the ONLY place which may publish the
/// original Watch recording. Duplicate/late route callbacks cannot generate
/// a second result receipt or close a newer workout.
enum ATHLTHWatchResultPublicationPolicy {
    static func mayPublish(
        finishing: Bool,
        ending: Bool,
        hasPublishedResult: Bool,
        originalStartedAt: Date?,
        healthKitStartedAt: Date,
        endedAt: Date
    ) -> Bool {
        guard finishing, ending, !hasPublishedResult,
              let originalStartedAt,
              originalStartedAt.timeIntervalSince1970.isFinite,
              healthKitStartedAt.timeIntervalSince1970.isFinite,
              endedAt.timeIntervalSince1970.isFinite,
              abs(originalStartedAt.timeIntervalSince(healthKitStartedAt)) <= 5,
              endedAt >= healthKitStartedAt else { return false }
        return true
    }
}

enum WatchPreparedWorkoutTransport {
    static let kind = "preparedWorkout"
}

struct WatchTodayWorkoutTransfer: Codable, Hashable {
    var planID: UUID
    var workoutID: UUID
    var title: String
    var summary: String
    var kind: WatchWorkoutKind
    var scheduledStart: Date?
    var durationMinutes: Int?
    var distanceKilometers: Double?
    var routeID: UUID?
    var runningWorkout: WatchRunningWorkoutTransfer?
    var audioCoach: WatchAudioCoachConfiguration?
    // Optional so older iPhone/Watch pairs still decode. When present, the
    // Watch has the entire strength prescription before it leaves the phone.
    var strengthWorkout: WatchStrengthSessionSnapshot? = nil
    /// Optional, preserving the exact indoor intent when the phone sends it.
    var indoor: Bool? = nil
    var updatedAt: Date
}

/// One canonical launch adapter for the Watch's Today and prepared cards.
/// Today cards are transport snapshots, never the recorder's identity.
/// The existing WatchRouteStore/HealthKit owner performs the actual start.
enum ATHLTHWatchTodayLaunchAdapter {
    static func prepared(
        from today: WatchTodayWorkoutTransfer
    ) -> WatchPreparedWorkoutTransfer? {
        // Starting a planned strength session without its original exercises
        // would silently turn it into an unrelated free-strength recording.
        guard today.kind != .strength ||
              today.strengthWorkout != nil else { return nil }
        return WatchPreparedWorkoutTransfer(
            id: UUID(), title: today.title, summary: today.summary,
            kind: today.kind, routeID: today.routeID,
            runningWorkout: today.runningWorkout,
            audioCoach: today.audioCoach,
            indoor: today.indoor,
            startMode: .onWatch,
            strengthWorkout: today.strengthWorkout,
            plannedPlanID: today.planID,
            plannedSessionID: today.workoutID,
            updatedAt: today.updatedAt
        )
    }
}

/// A short-lived confirmation of a Today card that actually started an
/// original HealthKit recording. This is NOT a second training journal.
struct ATHLTHWatchTodayLaunchReceipt: Codable, Hashable {
    let sessionID: UUID
    let ownerID: UUID?
    let confirmedAt: Date
}

enum ATHLTHWatchTodayReplayPolicy {
    static let retention: TimeInterval = 8 * 24 * 60 * 60

    static func wasConfirmed(
        sessionID: UUID, ownerID: UUID?,
        receipts: [ATHLTHWatchTodayLaunchReceipt],
        now: Date = Date()
    ) -> Bool {
        receipts.contains { receipt in
            receipt.sessionID == sessionID &&
            receipt.ownerID == ownerID &&
            receipt.confirmedAt.timeIntervalSince1970.isFinite &&
            now.timeIntervalSince(receipt.confirmedAt) >= 0 &&
            now.timeIntervalSince(receipt.confirmedAt) < retention
        }
    }
}

/// Prepared transfers are only admitted with their original sport-specific
/// prescription. A truncated card cannot be disguised as Free Strength.
enum ATHLTHWatchPreparedRecipeAdmissionPolicy {
    static func permits(
        kind: WatchWorkoutKind,
        hasRunningRecipe: Bool,
        hasStrengthRecipe: Bool,
        hasRoute: Bool
    ) -> Bool {
        if hasStrengthRecipe && kind != .strength { return false }
        if hasRunningRecipe && kind != .running && kind != .walking {
            return false
        }
        if kind == .strength && !hasStrengthRecipe { return false }
        if hasRoute && !kind.usesOutdoorLocation { return false }
        return true
    }
}

struct WatchTodaySnapshot: Codable, Hashable {
    var workout: WatchTodayWorkoutTransfer?
    var updatedAt: Date
    // Optional for backwards compatibility with existing Watch snapshots.
    // The iPhone can send all sessions for a day, not only the first one.
    var workouts: [WatchTodayWorkoutTransfer]? = nil

    var scheduledWorkouts: [WatchTodayWorkoutTransfer] {
        let candidates = workouts ?? workout.map { [$0] } ?? []
        return candidates.sorted {
            ($0.scheduledStart ?? .distantFuture) <
                ($1.scheduledStart ?? .distantFuture)
        }
    }
}

struct WatchWorkoutLapSummary: Codable, Hashable {
    var number: Int
    var endedAt: Date
    var elapsedTime: TimeInterval
    var distanceMeters: Double
    var averagePaceSecondsPerKilometer: TimeInterval?
}

enum WatchStrengthInputMode:
    String,
    Codable,
    CaseIterable,
    Hashable,
    Identifiable
{
    case both
    case iPhone
    case appleWatch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .both:
            return ATHLTHLocalization.choose(
                english: "Both",
                norwegian: "Begge"
            )
        case .iPhone:
            return "iPhone"
        case .appleWatch:
            return "Apple Watch"
        }
    }
}

struct WatchStrengthSetPlan: Codable, Hashable {
    var setNumber: Int
    var reps: Int? = nil
    var durationSeconds: Int? = nil
    var openEndedTime: Bool? = nil
    var weightKilograms: Double? = nil
    var resistanceLevel: Int? = nil
    var restSeconds: Int? = nil
    var targetRPE: Double? = nil
    var targetRIR: Double? = nil
    var isWarmUp: Bool? = nil
    // Per-set phase metadata lets a disconnected Watch advance a timed
    // treadmill sequence without losing the next interval's instructions.
    var hybridPhaseTitle: String? = nil
    var hybridPhaseKind: String? = nil
    var hybridTargetHeartRateZone: Int? = nil
    var hybridTargetPaceSecondsPerKilometer: Double? = nil
    var hybridTargetDistanceMeters: Double? = nil
}

struct WatchStrengthExerciseSummary: Codable, Hashable {
    var index: Int
    var name: String
    var primaryMuscles: [String]
    var setCount: Int

    // Optional details let Apple Watch carry the whole strength prescription
    // without iPhone reachability. Defaults keep older snapshots decodable.
    var instructions: [String]? = nil
    var secondaryMuscles: [String]? = nil
    var equipment: [String]? = nil
    /// Optional Coach provenance travels with the prescription. The Watch
    /// only preserves the values; it must not infer identity or weight units
    /// for older offline sessions with missing metadata.
    var libraryExerciseID: UUID? = nil
    var coachLoadBasisRaw: String? = nil
    var setPlans: [WatchStrengthSetPlan]? = nil
    var isCompleted: Bool? = nil
    var firstPendingSetIndex: Int? = nil
    /// Count omitted on this exercise, distinct from completed efforts.
    var skippedSets: Int? = nil
    var isEmbeddedRunningInterval: Bool? = nil
    /// Planned group identity and timing; optional for older Watch snapshots.
    var strengthGroupID: UUID? = nil
    var strengthGroupStyleRaw: String? = nil
    var strengthGroupClockSeconds: TimeInterval? = nil
    var strengthGroupStartedAt: Date? = nil
}

/// Label for known strength weight semantics on the Watch. Unknown and
/// old payloads are left unspecified rather than guessed from a name.
enum ATHLTHWatchStrengthLoadBasisLabel {
    static func localized(raw: String?) -> String? {
        switch raw {
        case "totalKilograms":
            return ATHLTHLocalization.choose(
                english: "Total weight · kg",
                norwegian: "Totalvekt · kg"
            )
        case "kilogramsPerHand":
            return ATHLTHLocalization.choose(
                english: "Weight per hand · kg",
                norwegian: "Vekt per hånd · kg"
            )
        case "machineStackKilograms":
            return ATHLTHLocalization.choose(
                english: "Machine stack · kg",
                norwegian: "Maskinvekt · kg"
            )
        default:
            return nil
        }
    }
}

/// Absolute-date countdown snapshot. No display ticks are transmitted over WatchConnectivity.
struct WatchTimedStrengthCountdown: Codable, Hashable {
    var targetSeconds: Int
    var secondsAtPause: TimeInterval
    var resumedAt: Date?

    func remaining(at date: Date = Date()) -> TimeInterval {
        max(ATHLTHWorkoutSessionClock.remaining(
            secondsAtPause: secondsAtPause,
            resumedAt: resumedAt,
            at: date
        ), 0)
    }

    /// Actual elapsed active time, including overtime, across Watch pauses.
    /// The same clock policy is used by iPhone; no duplicate tick logic.
    func elapsed(at date: Date = Date()) -> TimeInterval {
        max(TimeInterval(targetSeconds) -
            ATHLTHWorkoutSessionClock.remaining(
                secondsAtPause: secondsAtPause,
                resumedAt: resumedAt,
                at: date
            ), 0)
    }

    var isRunning: Bool { resumedAt != nil }
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
    /// Number deliberately omitted from this session; not completed work.
    var skippedSets: Int? = nil
    var draftReps: Int
    var draftWeightKilograms: Double
    var draftRestSeconds: Int

    // Optional machine/time fields preserve compatibility with Watch builds
    // that only knew reps + kilograms.
    var draftDurationSeconds: Int? = nil
    var draftResistanceLevel: Int? = nil
    // Explicit user-entered treadmill settings, never measured Watch speed.
    var manualTreadmillSpeedKilometersPerHour: Double? = nil
    var manualTreadmillInclinePercent: Double? = nil
    var targetKindRaw: String? = nil
    var loadKindRaw: String? = nil
    // A treadmill interval inside a strength session retains its single
    // workout engine, but Watch can present running-specific phase labels.
    var isEmbeddedRunningInterval: Bool? = nil
    var embeddedRunningPhaseTitle: String? = nil
    var embeddedRunningPhaseKind: String? = nil
    var embeddedRunningTargetHeartRateZone: Int? = nil
    // Prescribed target, not measured or estimated running pace.
    var embeddedRunningTargetPaceSecondsPerKilometer: Double? = nil
    var embeddedRunningTargetDistanceMeters: Double? = nil
    var isResting: Bool
    var restEndsAt: Date?
    var currentExerciseComplete: Bool
    var hasNextExercise: Bool
    var allExercisesComplete: Bool
    var updatedAt: Date
    var inputMode: WatchStrengthInputMode? = nil
    var draftRPE: Double? = nil
    var draftRIR: Double? = nil
    var isWarmUp: Bool? = nil
    var effortMetricRaw: String? = nil
    var exerciseQueue:
        [WatchStrengthExerciseSummary]? = nil

    var currentCoachLoadBasisRaw: String? {
        exerciseQueue?.first(where: { $0.index == exerciseIndex })?
            .coachLoadBasisRaw
    }

    // Offline ownership metadata. A Watch-started workout can be rebuilt on
    // iPhone from this snapshot after hours without connectivity.
    var startedAt: Date? = nil
    var plannedSessionID: UUID? = nil
    var allowsLiveExerciseBuilding: Bool? = nil

    /// Optional: older Watch versions receive the planned duration only.
    var timedSetCountdown: WatchTimedStrengthCountdown? = nil
    /// Optional so older Watch builds can still decode the workout.
    /// Repetition sets can start a count-up effort clock from the Watch.
    var setEffortStartedAt: Date? = nil
    var isOpenEndedTimedSet: Bool? = nil
    /// Active group context for glanceable Watch guidance, not measured work.
    var strengthModeRaw: String? = nil
    var strengthModeClockSeconds: TimeInterval? = nil
    var strengthModeStartedAt: Date? = nil
    var strengthModeRound: Int? = nil
    var strengthModeTotalRounds: Int? = nil
    var strengthModeStationIndex: Int? = nil
    var strengthModeStationCount: Int? = nil
    /// Optional for compatibility with Watch snapshots made before plate-only
    /// input support. Nil means keep the legacy total-weight input.
    /// Draft/load commands always carry TOTAL kilograms, bar included.
    var barWeightKilograms: Double? = nil
    /// Empty/free sessions carry draft defaults, not an exercise to perform.
    var hasExercisePrescription: Bool { exerciseCount > 0 }

}

/// Shared by phone and Watch to reject early/expired strength efforts.
/// A clock does not prove repetitions; the athlete still confirms each set.
enum ATHLTHStrengthModeClockPolicy {
    static func permitsCompletion(
        modeRaw: String?,
        startedAt: Date?,
        clockSeconds: TimeInterval?,
        roundIndex: Int,
        stationIndex: Int,
        stationCount: Int,
        at now: Date = Date()
    ) -> Bool {
        guard let modeRaw else { return true }
        // A timed mode with no clock anchor must not silently accept work
        // outside its intended window (e.g. an incomplete Watch transfer).
        guard let startedAt else {
            return modeRaw != "emom" && modeRaw != "amrap"
        }
        let elapsed = max(0, now.timeIntervalSince(startedAt))
        switch modeRaw {
        case "amrap":
            let timeLimit = clockSeconds ?? 720
            return timeLimit.isFinite && timeLimit > 0 && elapsed < timeLimit
        case "emom":
            let perStation = clockSeconds ?? 60
            guard perStation.isFinite && perStation > 0,
                  stationIndex >= 0, stationCount > 0, roundIndex >= 0
            else { return false }
            let slot = roundIndex * stationCount + stationIndex
            return elapsed >= Double(slot) * perStation &&
                elapsed < Double(slot + 1) * perStation
        default:
            return true
        }
    }

    static func remainingSeconds(
        modeRaw: String?,
        startedAt: Date?,
        clockSeconds: TimeInterval?,
        roundIndex: Int,
        stationIndex: Int,
        stationCount: Int,
        at now: Date = Date()
    ) -> TimeInterval? {
        guard let modeRaw, let startedAt else { return nil }
        let elapsed = max(0, now.timeIntervalSince(startedAt))
        switch modeRaw {
        case "amrap":
            return max(0, (clockSeconds ?? 720) - elapsed)
        case "emom":
            let end = Double(roundIndex * max(1, stationCount) + stationIndex + 1) *
                (clockSeconds ?? 60)
            return max(0, end - elapsed)
        default:
            return nil
        }
    }
}

/// The Watch may independently advance only time-based treadmill phases
/// embedded in its existing strength recording. It never starts HealthKit,
/// guesses distance or completes ordinary strength sets automatically.
enum ATHLTHHybridWatchIntervalPolicy {
    static func shouldAutoAdvance(
        _ snapshot: WatchStrengthSessionSnapshot?,
        workoutState: WatchWorkoutMirrorState,
        at date: Date = Date()
    ) -> Bool {
        guard workoutState == .running,
              let snapshot,
              snapshot.inputMode != .iPhone,
              snapshot.isEmbeddedRunningInterval == true,
              snapshot.targetKindRaw == "time",
              !snapshot.isResting,
              !snapshot.currentExerciseComplete,
              snapshot.setIndex >= 0,
              snapshot.setIndex < snapshot.setCount,
              let countdown = snapshot.timedSetCountdown,
              countdown.isRunning
        else { return false }
        return countdown.remaining(at: date) <= 0
    }
}

/// The iPhone owns exercise scheduling while a paired Watch records the
/// workout. Adding work after the last set must reopen the Watch session;
/// delayed stale snapshots must not return it to an older queue.
enum ATHLTHStrengthWatchSnapshotAcceptance {
    static func shouldApply(
        incoming: WatchStrengthSessionSnapshot,
        after previous: WatchStrengthSessionSnapshot?
    ) -> Bool {
        guard let previous, previous.workoutID == incoming.workoutID else {
            return true
        }
        if incoming.completedSets < previous.completedSets ||
           incoming.exerciseCount < previous.exerciseCount {
            return false
        }
        let expanded = incoming.exerciseCount > previous.exerciseCount ||
            incoming.totalSets > previous.totalSets
        if !expanded {
            if previous.allExercisesComplete && !incoming.allExercisesComplete,
               incoming.completedSets == previous.completedSets,
               incoming.exerciseQueue == previous.exerciseQueue {
                return false
            }
            if incoming.completedSets == previous.completedSets &&
               incoming.updatedAt.addingTimeInterval(0.75) < previous.updatedAt {
                return false
            }
        }
        return true
    }
}

enum WatchStrengthCommandKind: String, Codable, Hashable {
    case updateDraft
    case completeSet
    case startSetEffort
    /// Explicit omission: never record zero reps as a completed effort.
    case skipSet
    case completeSetWithoutDetails
    case skipRest
    /// One atomic command: end rest and start the upcoming timed set.
    /// Avoids a race where a second start command can be dropped in transit.
    case skipRestAndStartTimedSet
    case addRest
    case nextExercise
    case requestSnapshot
    case startTimedSet
    case pauseTimedSet
    case resetTimedSet
}

struct WatchStrengthCommand: Codable, Hashable {
    var id: UUID
    var workoutID: UUID?
    var kind: WatchStrengthCommandKind
    var reps: Int?
    var weightKilograms: Double?
    var restSeconds: Int?
    var durationSeconds: Int? = nil
    var resistanceLevel: Int? = nil
    var distanceMeters: Double? = nil
    var addRestSeconds: Int?
    var sentAt: Date
    var rpe: Double? = nil
    var rir: Double? = nil
    var isWarmUp: Bool? = nil
    var exerciseIndex: Int? = nil
    var setIndex: Int? = nil
    // True only when the strength workout was initiated from the Watch UI.
    // Older queued commands remain decodable because this is optional.
    var initiatedOnWatch: Bool? = nil

    // The first durable request from a standalone Watch carries enough state
    // for iPhone to recreate the strength log before replaying queued actions.
    var bootstrapSnapshot: WatchStrengthSessionSnapshot? = nil
    /// Account which owned the workout when Watch started recording.
    /// Optional for older queued WatchConnectivity payloads; missing does
    /// not grant authority to bootstrap a workout under another account.
    var accountOwnerID: UUID? = nil
}

/// Recorded, not prescribed, performance for a complete structured run.
struct ATHLTHRecordedRunningStep: Codable, Hashable {
    var index: Int
    var title: String
    var phase: String?
    var activeSeconds: TimeInterval
    var distanceMeters: Double
    // A treadmill with manually entered belt speed is user-reported evidence.
    var isUserReported: Bool = false
    var targetPaceSecondsPerKilometer: Double? = nil
    /// Optional planned values, not measured results. Nil for older histories.
    var targetDurationSeconds: TimeInterval? = nil
    var targetHeartRateZone: Int? = nil
    var targetTreadmillInclinePercent: Double? = nil

    var actualSpeedKilometersPerHour: Double? {

        guard activeSeconds >= 10, distanceMeters > 0,
              activeSeconds.isFinite, distanceMeters.isFinite else {
            return nil
        }
        let speed = distanceMeters * 3.6 / activeSeconds
        return speed.isFinite && (0.5...35).contains(speed) ? speed : nil
    }
}

/// Watch-sampled interval timeline. A sample represents up to one minute,
/// including a shorter final slice. Targets are never reported as measurements.
struct ATHLTHRecordedRunningMinute: Codable, Hashable {
    var stepIndex: Int
    var stepElapsedAtEndSeconds: TimeInterval
    var activeSeconds: TimeInterval
    var recordedDistanceMeters: Double
    var watchHeartRateBPM: Double?
    var targetPaceSecondsPerKilometer: Double?
    var targetTreadmillInclinePercent: Double?
    /// The treadmill incline shown during the session was entered manually.
    var manuallyEnteredTreadmillInclinePercent: Double?
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

    // Optional so queued results created by older Watch builds still decode.
    var lapSummaries: [WatchWorkoutLapSummary]? = nil
    var automaticPauseCount: Int? = nil

    // Optional route-completion fields keep older Watch/iPhone transfers
    // decodable while giving both devices the same route-quality summary.
    var routeMatchPercent: Double? = nil
    var routeAverageDeviationMeters: Double? = nil
    var routeMaxDeviationMeters: Double? = nil
    var routeLeaderboardEligible: Bool? = nil
    var routeComparisonID: UUID? = nil
    var routeTitle: String? = nil

    // Exact calendar identity when the recording was started from the
    // planned Watch Today / prepared card. Optional for older Watch builds.
    var plannedCalendarSessionID: UUID? = nil

    // These fields are optional for legacy results. They are populated only
    // for structured sessions that actually reached their final step.
    var structuredWorkoutFullyCompleted: Bool? = nil
    var structuredWorkoutSourceID: UUID? = nil
    var structuredWorkoutTitle: String? = nil
    var recordedRunningSteps: [ATHLTHRecordedRunningStep]? = nil
    var recordedRunningMinutes: [ATHLTHRecordedRunningMinute]? = nil

    // Strength work performed while iPhone is unavailable is shipped together
    // with the final HealthKit result. This makes offline completion atomic
    // instead of depending on WatchConnectivity delivery order.
    var strengthSnapshot: WatchStrengthSessionSnapshot? = nil
    var strengthCommands: [WatchStrengthCommand]? = nil
    // Authoritative Watch-side pet participation, including offline sessions.
    var petSegments: [WatchPetParticipationSegment]? = nil
    // Captured when the Watch workout starts, never at delayed delivery.
    // Nil for legacy Watch versions; the phone must not silently attribute
    // an unowned result to whichever user happens to be signed in.
    var accountOwnerID: UUID? = nil
    // Stable iPad request identity only when Watch actually finished its
    // HealthKit recording. Optional for older Watch/phone builds.
    var relayRequestID: UUID? = nil
    /// Stable ATHLTH ID for the original Watch recording; separate from
    /// HealthKit UUID and queued result receipt. Nil in legacy results.
    var universalWorkoutID: UUID? = nil
}

/// The same saved HKWorkout may be delivered with different transfer
/// receipts after Watch reconnects. The original HealthKit UUID (or newer
/// exact ATHLTH original ID) is the immutable deduplication key.
enum ATHLTHWatchWorkoutResultIdentity {
    static func originalID(_ result: WatchWorkoutResult) -> UUID? {
        result.healthKitWorkoutUUID ?? result.universalWorkoutID
    }

    static func shouldEnqueue(
        _ incoming: WatchWorkoutResult,
        handledReceiptIDs: [UUID],
        handledOriginalIDs: [UUID],
        pending: [WatchWorkoutResult]
    ) -> Bool {
        guard !handledReceiptIDs.contains(incoming.id),
              !pending.contains(where: { $0.id == incoming.id })
        else { return false }
        if let original = originalID(incoming) {
            guard !handledOriginalIDs.contains(original),
                  !pending.contains(where: { originalID($0) == original })
            else { return false }
        }
        return true
    }

    /// Recovery accepts at most one queued receipt per original HKWorkout.
    /// Receipts lacking any original identity use legacy receipt-ID fallback.
    static func restorePending(
        _ candidates: [WatchWorkoutResult],
        handledReceiptIDs: [UUID],
        handledOriginalIDs: [UUID]
    ) -> [WatchWorkoutResult] {
        var accepted: [WatchWorkoutResult] = []
        for candidate in candidates.sorted(by: { $0.endedAt < $1.endedAt }) {
            guard shouldEnqueue(
                candidate, handledReceiptIDs: handledReceiptIDs,
                handledOriginalIDs: handledOriginalIDs, pending: accepted
            ) else { continue }
            accepted.append(candidate)
        }
        return accepted
    }
}

/// Minimal terminal proof, independent of the workout-history import queue.
/// This stores no health measurements, route or exercise data.
struct WatchRemoteLaunchCompletionReceipt: Codable, Hashable {
    let relayRequestID: UUID
    let ownerID: UUID
    let healthKitWorkoutUUID: UUID
    let resultID: UUID
    let kind: WatchWorkoutKind
    let startedAt: Date
    let endedAt: Date

    init?(result: WatchWorkoutResult) {
        guard let relayRequestID = result.relayRequestID,
              let ownerID = result.accountOwnerID,
              let healthKitWorkoutUUID = result.healthKitWorkoutUUID,
              result.endedAt >= result.startedAt else { return nil }
        self.relayRequestID = relayRequestID
        self.ownerID = ownerID
        self.healthKitWorkoutUUID = healthKitWorkoutUUID
        self.resultID = result.id
        self.kind = result.kind
        self.startedAt = result.startedAt
        self.endedAt = result.endedAt
    }
}


/// Two different HealthKit recordings with the same remote request ID are
/// contradictory evidence, never an invitation to pick the first result.
enum WatchRemoteLaunchCompletionPolicy {
    static func uniqueReceipt(
        _ receipts: [WatchRemoteLaunchCompletionReceipt],
        requestID: UUID,
        ownerID: UUID
    ) -> WatchRemoteLaunchCompletionReceipt? {
        let matches = receipts.filter {
            $0.relayRequestID == requestID && $0.ownerID == ownerID
        }
        guard matches.count == 1 else { return nil }
        return matches[0]
    }
}

/// Fail closed when WatchConnectivity delivers a completed workout to
/// a different signed-in ATHLTH account. Legacy (unowned) results stay in
/// the pending queue for explicit review rather than being silently assigned.
enum ATHLTHWatchWorkoutOwnershipPolicy {
    static func canApply(
        resultOwnerID: UUID?,
        signedInUserID: UUID?
    ) -> Bool {
        guard let resultOwnerID, let signedInUserID else { return false }
        return resultOwnerID == signedInUserID
    }
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
    /// Originates on Watch once per actual HKWorkoutSession and survives
    /// recovery. Nil on old Watch builds; iPhone must never invent it.
    var universalWorkoutID: UUID? = nil
    /// Exact owner captured when the Watch HealthKit workout began. Missing
    /// on older paired builds; cannot authorize private iPad telemetry.
    var accountOwnerID: UUID? = nil
    /// Exact planned session captured by the original Watch HealthKit
    /// recording. Nil for free workouts and older paired Watch builds.
    var plannedCalendarSessionID: UUID? = nil
    /// Stable ATHLTH session identity for Watch-strength mirror updates.
    /// Optional for older paired Watch apps; no new HealthKit session.
    var strengthWorkoutID: UUID? = nil

    /// HealthKit active time is authoritative; delivery time must not add pauses.
    var confirmedActiveDuration: TimeInterval {
        elapsedTime.isFinite ? max(elapsedTime, 0) : 0
    }

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
    // Accuracy is required before any GPS landmark announcement.
    var currentHorizontalAccuracy: Double? = nil
    var currentLocationSampledAt: Date? = nil
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
    // Non-nil identifies a treadmill run and carries the user-selected incline.
    var treadmillInclinePercent: Double? = nil
    var treadmillTargetPaceSecondsPerKilometer: Double? = nil // user goal, not sensor data
    var manualBeltSpeedKilometersPerHour: Double? = nil
    var manualBeltSpeedTimeline: [WatchBeltSpeedPoint]? = nil
    var routeRemainingMeters: Double? = nil
    var routeDeviationMeters: Double? = nil
    var routeDeviationThresholdMeters: Double? = nil
    // Watch-provided navigational cues are presentation-only, optional for
    // older Watch snapshots and do not assert a street intersection exists.
    var routeCueEnglish: String? = nil
    var routeCueNorwegian: String? = nil
    var routeCueSymbol: String? = nil
    var routeCueDistanceMeters: Double? = nil
    var routeCueOffRoute: Bool? = nil
    var routeCanReturnToStart: Bool? = nil

    // Shared structured-running state for iPhone, Apple Watch, Lock Screen
    // and Dynamic Island. Optional defaults preserve older transfers.
    var runningStepTitle: String? = nil
    var runningStepIndex: Int? = nil
    var runningStepCount: Int? = nil
    /// Small full phase list for read-only iPad workouts.
    var runningStageSummaries: [ATHLTHWatchRunningStageSummary]? = nil
    /// Efforts only (not warm-up/recovery). Optional for older snapshots.
    var runningIntervalOrdinal: Int? = nil
    var runningIntervalTotal: Int? = nil
    var runningInRecovery: Bool? = nil
    var runningStepProgress: Double? = nil
    var runningOverallProgress: Double? = nil
    var runningStepTargetTreadmillInclinePercent: Double? = nil
    var runningStepTargetPaceSecondsPerKilometer: Double? = nil
    /// Exact lower-effort edge of planned pace (larger seconds/km).
    /// Older Watch builds omit this optional field.
    var runningStepTargetSlowestPaceSecondsPerKilometer: Double? = nil
    var runningManualAdvanceRequired: Bool? = nil
    var runningAwaitingMainStart: Bool? = nil
    /// This warm-up needs just one manual tap to start the saved route.
    var runningRouteWarmup: Bool? = nil
    var runningStepElapsedSeconds: TimeInterval? = nil
    var runningIntervalCoachCueEverySeconds: TimeInterval? = nil
    var runningIntervalCoachCountdownSeconds: TimeInterval? = nil
    var runningNextStepTitle: String? = nil
    var runningNextStepPhase: String? = nil
    var runningStepCoachGroupID: UUID? = nil
    var runningNextStepCoachGroupID: UUID? = nil
    var runningStepRemainingSeconds: TimeInterval? = nil
    var runningStepRemainingMeters: Double? = nil
    var runningStepCoachBrief: String? = nil
    var runningStepMotivation: ATHLTHIntervalMotivationSettings? = nil
    var runningCoachReport: ATHLTHRunningCoachReport? = nil
    var coachReadoutContext: ATHLTHCoachReadoutContext? = nil
    var runningStepPhase: String? = nil
    var runningStepTargetHeartRateZone: Int? = nil

    var heartRateTargetZone: Int? = nil
    var heartRateTargetMinimumBPM: Double? = nil
    var heartRateTargetMaximumBPM: Double? = nil
    var heartRateTargetStatus: String? = nil

    var ghostRaceTitle: String? = nil
    var ghostDistanceDeltaMeters: Double? = nil
    var ghostTimeDeltaSeconds: TimeInterval? = nil
    // Newer Watch builds explicitly report workout auto-pause. This optional
    // value remains decodable from older Watch/iPhone combinations.
    var workoutAutoPaused: Bool? = nil

    /// Original strength/hybrid Watch journal identifies the active
    /// recorded subactivity. These are presentation flags, not a new
    /// HealthKit activity and never a separate workout recording.
    /// Nil is expected from older Watch builds.
    var strengthHybridRunningActive: Bool? = nil
    var strengthRecoveryActive: Bool? = nil
    var strengthExerciseName: String? = nil
    /// The zero-based ORIGINAL exercise cursor shared with iPhone.
    /// This is separate from the one-based set display below.
    /// Optional for old Watch builds; a missing cursor stays unknown.
    var strengthExerciseIndex: Int? = nil
    var strengthExerciseCount: Int? = nil
    var strengthSetIndex: Int? = nil
    var strengthSetCount: Int? = nil
    var strengthReps: Int? = nil
    var strengthWeightKilograms: Double? = nil
    var strengthRestEndsAt: Date? = nil
    var strengthNextExerciseName: String? = nil
    var strengthTimedSetTargetSeconds: Int? = nil
    var strengthTimedSetSecondsAtSnapshot: TimeInterval? = nil
    var strengthTimedSetResumedAt: Date? = nil

    var liveSurfaceConfiguration:
        ATHLTHLiveWorkoutSurfaceConfiguration? = nil
    var liveSurfaceContext:
        ATHLTHLiveWorkoutContext? = nil

    // Old Watch builds omit this marker. New iPhone builds can retain the
    // legacy phone-voice path for mixed-version Watch/iPhone installations.
    var supportsAudioCoachVoiceLease: Bool? = nil
    /// New Watch builds explicitly mark their own speech authority.
    /// A phone mirror must never request a voice lease while this is true.
    /// Optional for mixed-version watch/phone compatibility.
    var watchOwnedAudioCoach: Bool? = nil
    /// Actual enabled status, independent of who owns the speech lease.
    var watchAudioCoachEnabled: Bool? = nil

    // Sample ages travel separately from the current displayed values.
    // Older Watch builds omit these markers; coaching then avoids claiming
    // fresh live heart-rate or pace data it cannot verify.
    var coachHeartRateSampleAt: Date? = nil
    var coachPaceSampleAt: Date? = nil
    /// The Watch may use HRmax from a structured plan rather than a
    /// session-wide Coach preference. Mirror the effective value to iPhone.
    var coachResolvedMaximumHeartRateBPM: Double? = nil
    /// Watch-verified fresh terrain grade; absent on older Watch builds.
    var coachReliableNonClimbingTerrain: Bool? = nil
}

/// One source of truth for the *active* Watch segment, not just the
/// HealthKit category used to record the whole workout. A strength-owned
/// run/strength hybrid remains one HealthKit session and one workout UUID.
enum ATHLTHWatchLiveSportPolicy {
    static func activityCategory(_ snapshot: WatchWorkoutLiveSnapshot) -> String {
        switch snapshot.kind {
        case .running: return "running"
        case .walking: return "walking"
        case .strength:
            if snapshot.strengthRecoveryActive == true { return "recovery" }
            if snapshot.strengthHybridRunningActive == true { return "running" }
            return "strength"
        case .cycling: return "cycling"
        case .rowing: return "rowing"
        case .stairClimbing: return "stairclimber"
        case .hiit: return "hiit"
        case .functional: return "functional"
        case .yoga: return "yoga"
        case .other: return "other"
        }
    }
}

/// One source-provenance contract for Watch live readouts, iPad's
/// consent-protected spectator and the iPhone-mirrored Audio Coach.
/// Nothing here allocates HealthKit, estimates speed or records a workout.
/// A strength-owned running PHASE is not a native running sensor source.
enum ATHLTHWatchVerifiedLiveMetrics {
    static func measuredDistanceMeters(
        from snapshot: WatchWorkoutLiveSnapshot
    ) -> Double? {
        guard snapshot.kind.supportsDistanceMetric,
              snapshot.distanceMeters.isFinite,
              snapshot.distanceMeters > 0 else { return nil }
        return snapshot.distanceMeters
    }

    static func measuredHeartRateBPM(
        from snapshot: WatchWorkoutLiveSnapshot,
        at now: Date = Date()
    ) -> Double? {
        guard ATHLTHCoachSensorFreshness.validHeartRate(
            snapshot.heartRate,
            sampledAt: snapshot.coachHeartRateSampleAt,
            now: now
        ) else { return nil }
        return snapshot.heartRate
    }

    static func measuredPaceSecondsPerKilometer(
        from snapshot: WatchWorkoutLiveSnapshot,
        at now: Date = Date()
    ) -> TimeInterval? {
        guard snapshot.kind == .running || snapshot.kind == .walking,
              ATHLTHCoachSensorFreshness.validPace(
                snapshot.currentPaceSecondsPerKilometer,
                sampledAt: snapshot.coachPaceSampleAt,
                now: now
              ) else { return nil }
        return snapshot.currentPaceSecondsPerKilometer
    }

    static func measuredActiveCalories(
        from snapshot: WatchWorkoutLiveSnapshot
    ) -> Double? {
        let value = snapshot.activeCalories
        return value.isFinite && value > 0 ? value : nil
    }
}

struct WatchGhostRaceTimingPoint: Codable, Hashable {
    var elapsedTime: TimeInterval
    var cumulativeMeters: Double
}

enum GhostRaceStatusDetailMode:
    String,
    Codable,
    CaseIterable,
    Hashable,
    Identifiable
{
    case distance
    case time
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .distance:
            return ATHLTHLocalization.choose(
                english: "Distance",
                norwegian: "Avstand"
            )
        case .time:
            return ATHLTHLocalization.choose(
                english: "Time",
                norwegian: "Tid"
            )
        case .both:
            return ATHLTHLocalization.choose(
                english: "Distance + time",
                norwegian: "Avstand + tid"
            )
        }
    }
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

    // Optional additions keep queued/persisted payloads from older builds
    // decodable across iPhone and Apple Watch.
    var statusDetailMode: GhostRaceStatusDetailMode? = nil
    var announceOvertakes: Bool? = nil
    var finalPhaseEnabled: Bool? = nil
    var finalPhaseStartMeters: Double? = nil
    var liveConnectionAlerts: Bool? = nil

    var resolvedStatusDetailMode:
        GhostRaceStatusDetailMode {
        statusDetailMode ?? .both
    }

    var shouldAnnounceOvertakes: Bool {
        announceOvertakes ?? false
    }

    var shouldAnnounceFinalPhase: Bool {
        finalPhaseEnabled ?? false
    }

    var resolvedFinalPhaseStartMeters: Double {
        min(
            max(
                finalPhaseStartMeters ?? 500,
                200
            ),
            1_000
        )
    }

    var shouldAnnounceLiveConnectionChanges: Bool {
        liveConnectionAlerts ?? false
    }

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

    // Lead-change alerts are event-driven extras on top of the selected
    // distance/time cadence. Keep them deliberately slower than routine
    // periodic Ghost status so a 1 km setting still feels like 1 km.
    var resolvedLeadChangeCooldownSeconds:
        TimeInterval {
        90
    }

    var resolvedImportantLeadChangeCooldownSeconds:
        TimeInterval {
        60
    }

    // Require a meaningful move through the ahead/behind boundary before
    // treating it as an important overtake. This prevents GPS jitter around
    // zero from repeatedly producing "ahead/behind" alerts.
    var resolvedLeadFlipThresholdMeters:
        Double {
        min(
            max(
                leadChangeThresholdMeters,
                20
            ),
            50
        )
    }

    static let disabled = WatchGhostRaceAudioConfiguration(
        enabled: false,
        distanceIntervalMeters: nil,
        timeIntervalSeconds: nil,
        announceLeadChanges: false,
        leadChangeThresholdMeters: 25,
        delivery: .haptic,
        periodicDelivery: .haptic,
        leadChangeDelivery: .haptic,
        importantLeadChangeDelivery: .haptic,
        importantLeadChangeMeters: 50,
        statusDetailMode: .both,
        announceOvertakes: false,
        finalPhaseEnabled: false,
        finalPhaseStartMeters: 500,
        liveConnectionAlerts: false
    )

    static let standard = WatchGhostRaceAudioConfiguration(
        enabled: true,
        distanceIntervalMeters: 1_000,
        timeIntervalSeconds: nil,
        announceLeadChanges: false,
        leadChangeThresholdMeters: 25,
        delivery: .voice,
        periodicDelivery: .voice,
        leadChangeDelivery: .haptic,
        importantLeadChangeDelivery: .both,
        importantLeadChangeMeters: 50,
        statusDetailMode: .both,
        announceOvertakes: true,
        finalPhaseEnabled: true,
        finalPhaseStartMeters: 500,
        liveConnectionAlerts: true
    )
}

struct WatchGhostRaceTransfer: Codable, Hashable {
    var title: String
    var referenceDuration: TimeInterval
    var routeDistanceMeters: Double
    var points: [WatchGhostRaceTimingPoint]
    var audio: WatchGhostRaceAudioConfiguration? = nil
    // Present only when the reference belongs to another ATHLTH user.
    // Replay/target ghosts leave this nil and retain generic Ghost wording.
    var opponentName: String? = nil
}

struct WatchWorkoutMirrorCommand: Codable, Hashable {
    var command: WatchWorkoutCommand
    // Optional keeps pause/resume/end payloads and older paired builds
    // decodable while allowing treadmill incline changes during a workout.
    var treadmillInclinePercent: Double? = nil
    var treadmillTargetPaceSecondsPerKilometer: Double? = nil
    /// Actual belt display entered by the athlete (not a target pace).
    var manualBeltSpeedKilometersPerHour: Double? = nil
    // Only return-route commands need a workout identity; default nil
    // preserves pause/resume/end compatibility with existing Watch versions.
    var workoutStartedAt: Date? = nil
    // Only used to append interval parts to the existing Watch recording.
    // Older Watch builds ignore the unknown command, never start a duplicate.
    var runningWorkoutToAppend: WatchRunningWorkoutTransfer? = nil
    var runningWorkoutStartImmediately: Bool? = nil
    /// Expected phase when advancing manually: repeated/stale taps cannot skip a second step.
    var expectedRunningStepIndex: Int? = nil
    var startMainAfterWarmup: Bool? = nil
    var commandID: UUID? = nil
    /// Original recording identity, not a relay receipt or planned-card ID.
    /// Optional for decoding older queued commands; new Watch mutations
    /// require a match when the original HealthKit workout has an ID.
    var universalWorkoutID: UUID? = nil
}

enum WatchWorkoutCommand: String, Codable, Hashable {
    case end
    case pause
    case resume
    case setTreadmillIncline
    case setTreadmillTargetPace
    case setTreadmillBeltSpeed
    case returnToStart
    case appendRunningWorkout
    case advanceRunningStep
}

enum WatchSpotifyCommandKind: String, Codable, Hashable {
    case requestState
    case pause
    case resume
    case next
}

struct WatchSpotifyCommand: Codable, Hashable {
    var kind: WatchSpotifyCommandKind
    var sentAt: Date = Date()
}

struct WatchSpotifyPlaybackState: Codable, Hashable {
    var isConfigured: Bool
    var isConnected: Bool
    var isPlaying: Bool
    var playlistName: String?
    var trackTitle: String?
    var artistName: String?
    var updatedAt: Date = Date()

    static let unavailable = WatchSpotifyPlaybackState(
        isConfigured: false,
        isConnected: false,
        isPlaying: false,
        playlistName: nil,
        trackTitle: nil,
        artistName: nil
    )
}

struct WatchHomeAssistantConfiguration: Codable, Hashable {
    var enabled: Bool
    var clientID: String?
    var webhookURL: URL?
    var fallbackWebhookURL: URL?
    var sharedSecret: String?
    var updatedAt: Date

    static var disabled: WatchHomeAssistantConfiguration {
        WatchHomeAssistantConfiguration(
            enabled: false,
            clientID: nil,
            webhookURL: nil,
            fallbackWebhookURL: nil,
            sharedSecret: nil,
            updatedAt: Date()
        )
    }
}

/// The identity belongs to one remotely requested recording, never to a
/// nearby Watch session inferred from time, title, or activity category.
struct WatchRemoteLaunchIdentity: Codable, Hashable {
    let requestID: UUID
    let kind: WatchWorkoutKind
    let issuedAt: Date

    func isFresh(at date: Date = Date()) -> Bool {
        abs(date.timeIntervalSince(issuedAt)) <= 45
    }
}

struct WatchWorkoutActivityState: Codable, Hashable {
    let isActive: Bool
    let title: String?
    let updatedAt: Date
    // Optional for older Watch installations and locally started workouts.
    var relayRequestID: UUID? = nil

    /// A saved result is authoritative completion evidence. Never clear a
    /// newer recording when an older result arrives late.
    static func afterCompletion(current: Self?, endedAt: Date) -> Self {
        if let current, current.updatedAt > endedAt { return current }
        return Self(isActive: false, title: nil, updatedAt: endedAt)
    }
}

// Pet identities contain only the minimum fields Watch needs. Photos,
 // birth dates and weights never travel over WatchConnectivity.
struct WatchPetIdentity: Codable, Hashable, Identifiable {
    let id: UUID
    let name: String
}

struct WatchPetParticipationSegment: Codable, Hashable {
    let petID: UUID
    var enteredAt: Date?
    var exitedAt: Date?
    var enteredMeters: Double?
    var exitedMeters: Double?
}

struct WatchPetCatalogTransfer: Codable, Hashable {
    let ownerID: UUID
    let pets: [WatchPetIdentity]
    let selectedPetIDs: [UUID]
    let updatedAt: Date
}

/// Latest signed-in account identity for the companion Watch.
struct WatchAccountIdentityTransfer: Codable, Hashable {
    let ownerID: UUID?
    let updatedAt: Date
}

struct WatchPetSelectionTransfer: Codable, Hashable {
    let ownerID: UUID
    let selectedPetIDs: [UUID]
    let segments: [WatchPetParticipationSegment]
    let updatedAt: Date
    let workoutStartedAt: Date?
}

enum WatchTransferKind: String {
    case route
    case workoutResult
    case workoutActivityState
    case workoutActivityQuery
    case workoutRemoteLaunchCompletion
    case workoutRemoteLaunchIdentity
    case workoutStartGuard
    case workoutCommand
    case workoutRouteSelection
    case audioCoachConfiguration
    case aiCoachConversationRequest
    case aiCoachConversationState
    case runningWorkout
    case ghostRace
    case liveSurfaceConfiguration
    case liveSurfaceContext
    case todayWorkout
    case todayWorkoutRequest
    case petCatalog
    case petSelection
    case accountIdentity
    case strengthSnapshot
    case strengthCommand
    case spotifyCommand
    case spotifyPlaybackState
    case spotifyCredentials
    case homeAssistantConfiguration
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
    static let workoutID = "workoutID"
    static let relayRequestID = "relayRequestID"
    static let workoutStartedAt = "workoutStartedAt"
    static let probeID = "probeID"
    static let sentAt = "sentAt"
    static let workoutAllowed = "workoutAllowed"
    static let workoutActive = "workoutActive"
}


/// Only a fresh interactive Watch request may reveal the iPhone AI consent UI.
/// No Watch command is allowed to start the microphone directly.
enum ATHLTHAIWatchCoachRequestPolicy {
    static func accepts(sentAt: TimeInterval?, now: Date = Date()) -> Bool {
        guard let sentAt, sentAt.isFinite else { return false }
        let age = now.timeIntervalSince1970 - sentAt
        return age >= 0 && age <= 20
    }
}

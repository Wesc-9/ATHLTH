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

        var nearestIndex: Int?
        var nearestDistance = Double.greatestFiniteMagnitude
        var bestScore = Double.greatestFiniteMagnitude

        for (index, point) in routeLocations.enumerated() {
            let routeMeters = cumulativeMeters[index]
            guard routeMeters.isFinite,
                  routeMeters >= backwardLimit,
                  routeMeters <= forwardLimit else {
                continue
            }

            let distance = location.distance(from: point)
            guard distance.isFinite else { continue }

            // At self-intersections, prefer the part of the route consistent
            // with measured workout progress; preserve visual GPS proximity
            // as the dominant signal elsewhere.
            let progressPenalty: Double
            if anchor != nil {
                // Only use the last confirmed *course* position as a hint.
                // Position remains dominant, permitting a genuine downstream
                // reentry without rewarding kilometres spent off-course.
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
                nearestIndex = index
            }
        }

        guard let nearestIndex else { return nil }

        let geometryTotal = max(geometryTotalMeters, 1)
        let traveledAlongRoute = cumulativeMeters[nearestIndex]
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

struct WatchAudioCoachConfiguration: Codable, Hashable {
    var enabled: Bool
    var language: WatchAudioCoachLanguage
    var distanceIntervalMeters: Double?
    var timeIntervalSeconds: TimeInterval?
    // An optional ruleset keeps previously persisted and Watch transfers
    // backwards compatible. Each metric has its own cadence.
    var customRules: [ATHLTHAudioCoachRule]? = nil
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

    // The iPhone sets this on newly prepared mirrored workouts. Old iPhone
    // versions omit it; Watch then follows the previous reachability rule
    // rather than speaking simultaneously with a legacy mirrored phone.
    var useAcknowledgedVoiceLease: Bool? = nil

    var shouldPreferIPhoneAudioWhenReachable: Bool {
        preferIPhoneAudioWhenReachable ?? false
    }

    var shouldUseAcknowledgedVoiceLease: Bool {
        useAcknowledgedVoiceLease ?? false
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
    /// Planned belt incline; not a measured workout metric.
    var targetTreadmillInclinePercent: Double? = nil
    var ghostPaceSecondsPerKilometer: Double? = nil
    /// Optional on old Watch transfers. In recovery the pacer follows actual
    /// reduced speed without imposing a work-pace target.
    var ghostFollowsRecovery: Bool? = nil
    var ghostRecoverySlowdownPercent: Int? = nil
    var coachBrief: String? = nil
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
    var updatedAt: Date
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
    var updatedAt: Date
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
    var setPlans: [WatchStrengthSetPlan]? = nil
    var isCompleted: Bool? = nil
    var firstPendingSetIndex: Int? = nil
    var isEmbeddedRunningInterval: Bool? = nil
}

/// Absolute-date countdown snapshot. No display ticks are transmitted over WatchConnectivity.
struct WatchTimedStrengthCountdown: Codable, Hashable {
    var targetSeconds: Int
    var secondsAtPause: TimeInterval
    var resumedAt: Date?

    func remaining(at date: Date = Date()) -> TimeInterval {
        max(secondsAtPause - (resumedAt.map {
            max(date.timeIntervalSince($0), 0)
        } ?? 0), 0)
    }

    /// Actual elapsed active time, including overtime, across Watch pauses.
    /// A planned duration is never substituted for a set finished early.
    func elapsed(at date: Date = Date()) -> TimeInterval {
        let active = resumedAt.map { max(date.timeIntervalSince($0), 0) } ?? 0
        return max(TimeInterval(targetSeconds) - secondsAtPause + active, 0)
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

    // Offline ownership metadata. A Watch-started workout can be rebuilt on
    // iPhone from this snapshot after hours without connectivity.
    var startedAt: Date? = nil
    var plannedSessionID: UUID? = nil
    var allowsLiveExerciseBuilding: Bool? = nil

    /// Optional: older Watch versions receive the planned duration only.
    var timedSetCountdown: WatchTimedStrengthCountdown? = nil
    /// Empty/free sessions carry draft defaults, not an exercise to perform.
    var hasExercisePrescription: Bool { exerciseCount > 0 }

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
    case completeSetWithoutDetails
    case skipRest
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
    var runningStepProgress: Double? = nil
    var runningOverallProgress: Double? = nil
    var runningStepTargetTreadmillInclinePercent: Double? = nil
    var runningStepTargetPaceSecondsPerKilometer: Double? = nil
    var runningManualAdvanceRequired: Bool? = nil
    var runningAwaitingMainStart: Bool? = nil
    /// This warm-up needs just one manual tap to start the saved route.
    var runningRouteWarmup: Bool? = nil
    var runningStepElapsedSeconds: TimeInterval? = nil
    var runningIntervalCoachCueEverySeconds: TimeInterval? = nil
    var runningIntervalCoachCountdownSeconds: TimeInterval? = nil
    var runningNextStepTitle: String? = nil
    var runningStepRemainingSeconds: TimeInterval? = nil
    var runningStepRemainingMeters: Double? = nil
    var runningStepCoachBrief: String? = nil
    var runningStepPhase: String? = nil
    var runningStepTargetHeartRateZone: Int? = nil

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

    // Sample ages travel separately from the current displayed values.
    // Older Watch builds omit these markers; coaching then avoids claiming
    // fresh live heart-rate or pace data it cannot verify.
    var coachHeartRateSampleAt: Date? = nil
    var coachPaceSampleAt: Date? = nil
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
}

enum WatchWorkoutCommand: String, Codable, Hashable {
    case end
    case pause
    case resume
    case setTreadmillIncline
    case setTreadmillTargetPace
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

struct WatchWorkoutActivityState: Codable, Hashable {
    let isActive: Bool
    let title: String?
    let updatedAt: Date

    /// A saved result is authoritative completion evidence. Never clear a
    /// newer recording when an older result arrives late.
    static func afterCompletion(current: Self?, endedAt: Date) -> Self {
        if let current, current.updatedAt > endedAt { return current }
        return Self(isActive: false, title: nil, updatedAt: endedAt)
    }
}

enum WatchTransferKind: String {
    case route
    case workoutResult
    case workoutActivityState
    case workoutActivityQuery
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

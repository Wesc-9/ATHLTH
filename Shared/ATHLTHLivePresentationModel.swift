import Foundation

/// Presentation-only policy shared by iPhone and Apple Watch.
/// Recording and workout ownership remain in the existing workout stores.
enum ATHLTHLiveDisplayPhase: String, Codable, Hashable {
    case preparing, active, paused, resting, ending, completed
}

enum ATHLTHLiveDisplayMetric: String, Codable, Hashable {
    case pace, distance, elapsed, heartRate, reps, weight
    case strengthTimeTarget, strengthTimeRemaining, restRemaining
}

enum ATHLTHLiveDisplayPage: String, Codable, Hashable {
    case overview, set, rest, exercises, summary, intervals
    case pulse, route, ghost, audioCoach, treadmill, music, controls
}

struct ATHLTHLivePresentationContext: Hashable {
    var kind: WatchWorkoutKind
    var state: WatchWorkoutMirrorState
    var isStrengthResting = false
    var isTimedStrengthSet = false
    /// True only when an actual countdown exists, not when a duration is planned.
    var hasActiveTimedSetCountdown = false
    var hasStructuredRunningStep = false
    var hasHeartRateTarget = false
    var hasRoute = false
    var hasGhost = false
    var hasAudioCoach = false
    var hasTreadmillIncline = false
}

struct ATHLTHLivePresentationPlan: Hashable {
    var phase: ATHLTHLiveDisplayPhase
    var primary: ATHLTHLiveDisplayMetric
    var secondary: [ATHLTHLiveDisplayMetric]
    var pages: [ATHLTHLiveDisplayPage]
}

/// Keep the information hierarchy deterministic. A screen may render less
/// when the sensors are unavailable, but must never synthesize measurements.
enum ATHLTHLivePresentationResolver {
    static func resolve(_ context: ATHLTHLivePresentationContext)
        -> ATHLTHLivePresentationPlan {
        let phase: ATHLTHLiveDisplayPhase
        switch context.state {
        case .preparing:
            phase = .preparing
        case .paused:
            phase = .paused
        case .ending, .failed:
            phase = .ending
        case .completed:
            phase = .completed
        case .running:
            phase = context.isStrengthResting ? .resting : .active
        }

        let isStrength = context.kind == .strength ||
            (context.kind == .functional && context.isTimedStrengthSet)
        if isStrength {
            let primary: ATHLTHLiveDisplayMetric
            if phase == .resting {
                primary = .restRemaining
            } else if context.isTimedStrengthSet {
                primary = context.hasActiveTimedSetCountdown
                    ? .strengthTimeRemaining : .strengthTimeTarget
            } else {
                primary = .reps
            }

            var pages: [ATHLTHLiveDisplayPage] = [
                .set, .rest, .exercises, .summary
            ]
            if context.hasAudioCoach { pages.append(.audioCoach) }
            pages.append(contentsOf: [.music, .controls])
            return ATHLTHLivePresentationPlan(
                phase: phase,
                primary: primary,
                secondary: [.weight, .heartRate, .elapsed],
                pages: pages
            )
        }

        let primary: ATHLTHLiveDisplayMetric
        let secondary: [ATHLTHLiveDisplayMetric]
        switch context.kind {
        case .running:
            primary = .pace
            secondary = [.distance, .heartRate, .elapsed]
        case .walking, .cycling:
            primary = .distance
            secondary = [.pace, .heartRate, .elapsed]
        case .strength, .hiit, .functional, .rowing, .stairClimbing, .yoga, .other:
            primary = .elapsed
            secondary = [.heartRate]
        }

        var pages: [ATHLTHLiveDisplayPage] = [.overview]
        if context.hasStructuredRunningStep { pages.append(.intervals) }
        if context.kind == .running || context.hasHeartRateTarget {
            pages.append(.pulse)
        }
        if context.hasTreadmillIncline { pages.append(.treadmill) }
        if context.hasRoute { pages.append(.route) }
        if context.hasGhost { pages.append(.ghost) }
        if context.hasAudioCoach { pages.append(.audioCoach) }
        pages.append(contentsOf: [.music, .controls])
        return ATHLTHLivePresentationPlan(
            phase: phase,
            primary: primary,
            secondary: secondary,
            pages: pages
        )
    }
}

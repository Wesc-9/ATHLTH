import Foundation

/// Presentation-only hierarchy shared across phone-owned and Watch-mirrored
/// sessions. Recording, HealthKit and workout control are unchanged.
enum ATHLTHPhoneLiveMetric: String, Equatable {
    case pace, distance, elapsed, reps, timeRemaining, restRemaining
}

struct ATHLTHPhoneLiveHierarchy: Equatable {
    var primary: ATHLTHPhoneLiveMetric
    var secondary: [ATHLTHPhoneLiveMetric]
}

enum ATHLTHPhoneLiveHierarchyResolver {
    static func resolve(
        kind: WatchWorkoutKind,
        strengthHasSet: Bool = false,
        strengthIsResting: Bool = false,
        strengthIsTimed: Bool = false
    ) -> ATHLTHPhoneLiveHierarchy {
        if kind == .strength, strengthHasSet {
            if strengthIsResting {
                return .init(primary: .restRemaining,
                             secondary: [.reps, .elapsed])
            }
            if strengthIsTimed {
                return .init(primary: .timeRemaining,
                             secondary: [.elapsed])
            }
            return .init(primary: .reps, secondary: [.elapsed])
        }

        switch kind {
        case .running:
            return .init(primary: .pace,
                         secondary: [.distance, .elapsed])
        case .walking, .cycling:
            return .init(primary: .distance,
                         secondary: [.pace, .elapsed])
        case .strength, .hiit, .functional, .rowing,
             .stairClimbing, .yoga, .other:
            return .init(primary: .elapsed, secondary: [])
        }
    }

    /// This label never declares an unmeasured pace to be live.
    static func paceIsAvailable(_ value: TimeInterval?) -> Bool {
        guard let value else { return false }
        return value.isFinite && (0 < value) && value < 3_600
    }
}

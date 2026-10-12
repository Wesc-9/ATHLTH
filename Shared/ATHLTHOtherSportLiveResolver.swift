import Foundation

/// Avoid invented distance, repetitions or stroke rate on unsupported sports.
/// Only cycling is distance-first when the workout source has a valid measure.
enum ATHLTHOtherSportLiveFocus: Equatable {
    case measuredDistance
    case elapsed
}

enum ATHLTHOtherSportLiveResolver {
    static func resolve(
        kind: WatchWorkoutKind,
        distanceMeters: Double
    ) -> ATHLTHOtherSportLiveFocus {
        switch kind {
        case .cycling:
            if distanceMeters.isFinite && distanceMeters > 0 {
                return .measuredDistance
            }
            return .elapsed
        case .running, .walking, .strength, .hiit, .functional,
             .rowing, .stairClimbing, .yoga, .other:
            return .elapsed
        }
    }
}

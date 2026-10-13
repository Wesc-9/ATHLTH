import Foundation

/// Presentation-only evidence checks for synchronized Live Ghost results.
/// Server finish records remain authoritative and Arena awards points only
/// after its separate review. These checks never change a recorded time.
enum ATHLTHLiveGhostResultEvidence {
    enum Assessment: Equatable {
        case pending
        case plausible
        case needsReview
    }

    static func assess(
        synchronizedStart: Date?,
        recordedFinish: Date?,
        elapsedSeconds: TimeInterval?
    ) -> Assessment {
        guard let synchronizedStart,
              let recordedFinish,
              let elapsedSeconds else { return .pending }
        guard elapsedSeconds.isFinite,
              (5...86_400).contains(elapsedSeconds) else { return .needsReview }

        let wallSeconds = recordedFinish.timeIntervalSince(synchronizedStart)
        guard wallSeconds.isFinite,
              wallSeconds >= 5,
              wallSeconds <= 86_430 else { return .needsReview }

        // A delayed HealthKit launch, pause or offline finish upload can make
        // local elapsed time disagree with the server's shared race clock.
        // Do not silently present such a result as a verified winner.
        let tolerance = max(20, min(elapsedSeconds * 0.05, 120))
        return abs(wallSeconds - elapsedSeconds) <= tolerance
            ? .plausible : .needsReview
    }

    static func bothFinishesPlausible(
        synchronizedStart: Date?,
        firstFinish: Date?,
        firstElapsed: TimeInterval?,
        secondFinish: Date?,
        secondElapsed: TimeInterval?
    ) -> Bool {
        assess(
            synchronizedStart: synchronizedStart,
            recordedFinish: firstFinish,
            elapsedSeconds: firstElapsed
        ) == .plausible &&
        assess(
            synchronizedStart: synchronizedStart,
            recordedFinish: secondFinish,
            elapsedSeconds: secondElapsed
        ) == .plausible
    }
}

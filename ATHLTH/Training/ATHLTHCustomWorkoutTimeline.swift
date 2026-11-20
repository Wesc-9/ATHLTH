import Foundation

/// Canonical, sensor-free interval clock for every Custom Quick activity.
/// All call sites share the original method and timing configuration:
/// this neither starts a new workout nor records artificial work or distance.
enum ATHLTHCustomWorkoutTimeline {
    struct Snapshot: Equatable {
        let phase: ATHLTHWorkoutSessionPhase
        let roundNumber: Int?
        let stageIndex: Int?
        let stageCount: Int?
        /// Next phase boundary for intervals/EMOM; workout cap for AMRAP/For Time.
        let remainingSeconds: TimeInterval?
        /// Prescribed intervals ended; the athlete must still explicitly finish.
        let intervalsComplete: Bool
    }

    static func state(
        method: CustomQuickWorkoutMethod,
        durationMinutes: Int,
        workSeconds: Int,
        restSeconds: Int,
        rounds: Int,
        elapsedSeconds: TimeInterval,
        isPaused: Bool
    ) -> Snapshot? {
        guard elapsedSeconds.isFinite, elapsedSeconds >= 0,
              elapsedSeconds <= 24 * 60 * 60,
              (1...720).contains(durationMinutes),
              (1...900).contains(workSeconds),
              (0...900).contains(restSeconds),
              (1...100).contains(rounds) else { return nil }

        func snapshot(
            inRest: Bool = false,
            round: Int? = nil,
            index: Int? = nil,
            count: Int? = nil,
            remaining: TimeInterval? = nil,
            complete: Bool = false
        ) -> Snapshot {
            Snapshot(
                phase: isPaused ? .paused : (inRest ? .recovery : .work),
                roundNumber: round, stageIndex: index, stageCount: count,
                remainingSeconds: remaining, intervalsComplete: complete
            )
        }

        switch method {
        case .open:
            return snapshot()

        case .intervals, .tabata:
            // Tabata is prescribed 20/10 even when a legacy configuration
            // stores the default 40/20 for unrelated interval methods.
            let work = method == .tabata ? 20 : workSeconds
            let rest = method == .tabata ? 10 : restSeconds
            let hasRest = rest > 0 && rounds > 1
            let completeAt = Double(rounds * work + (rounds - 1) * rest)
            let count = rounds * (hasRest ? 2 : 1) -
                (hasRest ? 1 : 0)
            if elapsedSeconds >= completeAt {
                return snapshot(
                    round: rounds, index: count - 1, count: count,
                    remaining: 0, complete: true
                )
            }
            let cycle = work + rest
            let round = min(rounds - 1, Int(elapsedSeconds / Double(cycle)))
            let local = elapsedSeconds - Double(round * cycle)
            let inRest = hasRest && local >= Double(work) &&
                round < rounds - 1
            let index = round * (hasRest ? 2 : 1) + (inRest ? 1 : 0)
            let remaining = inRest
                ? Double(cycle) - local
                : Double(work) - local
            return snapshot(
                inRest: inRest, round: round + 1, index: index,
                count: count, remaining: max(0, remaining)
            )

        case .emom:
            let limit = Double(durationMinutes * 60)
            let minute = min(durationMinutes, Int(elapsedSeconds / 60) + 1)
            return snapshot(
                round: minute, index: minute - 1, count: durationMinutes,
                remaining: max(0, min(60 - elapsedSeconds.truncatingRemainder(
                    dividingBy: 60
                ), limit - elapsedSeconds)),
                complete: elapsedSeconds >= limit
            )

        case .amrap, .forTime:
            let remaining = max(0, Double(durationMinutes * 60) -
                elapsedSeconds)
            return snapshot(
                remaining: remaining,
                complete: remaining == 0
            )
        }
    }
}

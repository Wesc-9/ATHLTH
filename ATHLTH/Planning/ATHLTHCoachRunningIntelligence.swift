import Foundation

/// A bounded, read-only summary of completed running performances.
/// Only transmitted to ATHLTH Coach when the athlete confirms the
/// current question's health/training-history sharing.
enum ATHLTHCoachRunningIntelligence {
    struct RecentRun: Encodable, Equatable {
        let title: String
        let daysAgo: Int
        let durationMinutes: Int
        let averageWorkPaceSecondsPerKilometer: Int?
        let wasUserReported: Bool
    }

    struct Snapshot: Encodable, Equatable {
        let windowDays: Int
        let completedRuns: Int
        let runsLastSevenDays: Int
        let recentRuns: [RecentRun]
    }

    static func snapshot(
        from performances: [ATHLTHCompletedRunningPerformance],
        now: Date = Date()
    ) -> Snapshot {
        let start = now.addingTimeInterval(-56 * 86_400)
        var seen = Set<UUID>()
        let recent = performances.filter {
            $0.completedAt <= now && $0.completedAt >= start &&
                seen.insert($0.id).inserted
        }.sorted { $0.completedAt > $1.completedAt }

        let entries: [RecentRun] = recent.prefix(8).map { record in
            let seconds = record.steps.reduce(0) {
                $0 + max(0, $1.activeSeconds.isFinite ? $1.activeSeconds : 0)
            }
            let speed = record.averageWorkSpeed
            let pace = speed.flatMap {
                $0.isFinite && $0 > 0 ? Int((3_600 / $0).rounded()) : nil
            }
            return RecentRun(
                title: String(record.title.prefix(90)),
                daysAgo: max(0, Int(now.timeIntervalSince(record.completedAt) / 86_400)),
                durationMinutes: Int((seconds / 60).rounded()),
                averageWorkPaceSecondsPerKilometer: pace,
                wasUserReported: record.userReported
            )
        }
        return Snapshot(
            windowDays: 56,
            completedRuns: recent.count,
            runsLastSevenDays: recent.filter {
                $0.completedAt >= now.addingTimeInterval(-7 * 86_400)
            }.count,
            recentRuns: entries
        )
    }
}

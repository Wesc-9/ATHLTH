import Foundation

/// An explicit, reversible-by-edit suggestion based only on durations already
/// entered in this training plan. Never proposes a duration from health data,
/// general population norms or an AI guess.
enum ATHLTHPlanReviewDurationProposal {
    struct Proposal: Identifiable, Equatable {
        let planID: UUID
        let weekID: UUID
        let dayID: UUID
        let workoutID: UUID
        let workoutKind: WorkoutKind
        let workoutTitle: String
        let expectedPlanVersion: Int
        let previousMinutes: Int?
        let suggestedMinutes: Int
        let comparableSessionCount: Int

        var id: UUID { workoutID }
    }

    static func suggest(
        for suggestion: ATHLTHPlanReviewAdvisor.Suggestion,
        in plan: TrainingPlan,
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        eligibleWorkoutIDs: Set<UUID>? = nil
    ) -> Proposal? {
        guard suggestion.kind == .missingDuration,
              let start = plan.startDate,
              let weekIndex = plan.weeks.firstIndex(where: {
                  $0.id == suggestion.weekID
              }),
              let dayID = suggestion.dayID,
              let day = plan.weeks[weekIndex].days.first(where: {
                  $0.id == dayID
              }),
              (1...7).contains(day.dayIndex) else { return nil }

        let weekStart = calendar.date(
            byAdding: .day, value: weekIndex * 7,
            to: calendar.startOfDay(for: start)
        ) ?? start
        let fallbackDate = calendar.date(
            byAdding: .day, value: day.dayIndex - 1, to: weekStart
        ) ?? weekStart
        let today = calendar.startOfDay(for: referenceDate)

        guard let workout = day.sessions.first(where: { workout in
            (eligibleWorkoutIDs?.contains(workout.id) ?? true) &&
                (workout.durationMinutes ?? 0) <= 0 &&
                calendar.startOfDay(
                    for: workout.scheduledStart ?? fallbackDate
                ) >= today
        }) else { return nil }

        var seenIDs = Set<UUID>()
        let peerMinutes = plan.weeks
            .flatMap(\.days)
            .flatMap(\.sessions)
            .filter { peer in
                peer.id != workout.id &&
                    seenIDs.insert(peer.id).inserted &&
                    peer.kind == workout.kind
            }
            .compactMap { $0.durationMinutes }
            .filter { (10...180).contains($0) }
            .sorted()

        // One unrelated session is too little evidence for a one-tap edit.
        guard peerMinutes.count >= 2 else { return nil }
        let count = peerMinutes.count
        let median: Double
        if count.isMultiple(of: 2) {
            median = Double(peerMinutes[count / 2 - 1] +
                peerMinutes[count / 2]) / 2
        } else {
            median = Double(peerMinutes[count / 2])
        }
        // Use familiar five-minute steps, but always show the precise basis.
        let minutes = max(10, min(180, Int((median / 5).rounded()) * 5))

        return Proposal(
            planID: plan.id,
            weekID: suggestion.weekID,
            dayID: day.id,
            workoutID: workout.id,
            workoutKind: workout.kind,
            workoutTitle: workout.title,
            expectedPlanVersion: plan.version,
            previousMinutes: workout.durationMinutes,
            suggestedMinutes: minutes,
            comparableSessionCount: count
        )
    }
}

@MainActor
extension AppSessionStore {
    /// Explicit athlete approval only. All existing Plan Studio edit guards
    /// (version, dates, skip/completion, history) remain authoritative.
    @discardableResult
    func applyPlanReviewDurationProposal(
        _ proposal: ATHLTHPlanReviewDurationProposal.Proposal,
        healthWorkouts: [WorkoutSummary],
        strengthHistory: [StrengthWorkoutLog]
    ) -> Bool {
        guard (10...180).contains(proposal.suggestedMinutes),
              proposal.comparableSessionCount >= 2,
              let plan = trainingPlan(withID: proposal.planID),
              plan.version == proposal.expectedPlanVersion,
              let week = plan.weeks.first(where: {
                  $0.id == proposal.weekID
              }),
              let day = week.days.first(where: {
                  $0.id == proposal.dayID
              }),
              let source = day.sessions.first(where: {
                  $0.id == proposal.workoutID
              }),
              source.kind == proposal.workoutKind,
              source.durationMinutes == proposal.previousMinutes,
              (source.durationMinutes ?? 0) <= 0 else {
            return false
        }

        var edited = source
        edited.durationMinutes = proposal.suggestedMinutes
        return savePlanStudioWorkout(
            edited,
            inPlan: proposal.planID,
            dayID: proposal.dayID,
            editingWorkoutID: proposal.workoutID,
            expectedPlanVersion: proposal.expectedPlanVersion,
            healthWorkouts: healthWorkouts,
            strengthHistory: strengthHistory
        )
    }
}

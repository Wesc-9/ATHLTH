import SwiftUI

/// Reuse Plan Studio's evidence/version guards for every write. The review
/// itself is deterministic and can be reopened from the chat history.
struct ATHLTHCoachLocalPlanReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore
    let review: ATHLTHCoachLocalPlanReview
    let ownerID: UUID
    let onApplied: (String) -> Void
    @State private var pendingMove: ATHLTHPlanReviewMoveProposal.Proposal?
    @State private var pendingDuration: ATHLTHPlanReviewDurationProposal.Proposal?
    @State private var confirming = false
    @State private var saving = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(review.title).font(.system(.largeTitle, design: .serif))
                    Text(tr("Private review of the planned schedule. This is not a medical or training-load assessment.",
                            "Privat gjennomgang av planoppsettet. Dette er ikke en medisinsk vurdering eller måling av treningsbelastning."))
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let plan = session.trainingPlan(withID: review.planID), review.matches(plan),
                       session.signedIn, session.profile.userID == ownerID {
                        let findings = ATHLTHPlanReviewAdvisor.inspect(plan)
                        if findings.isEmpty {
                            Text(tr("No structural issues detected by the current checks.", "Ingen strukturelle avvik funnet av dagens kontroller."))
                                .font(.headline)
                        }
                        ForEach(Array(findings.prefix(12))) { finding in
                            findingCard(finding, plan: plan)
                        }
                        if findings.count > 12 {
                            Text(tr("Showing the first 12 findings. Open Plan Studio for a full review.",
                                    "Viser de første 12 funnene. Åpne Plan Studio for full gjennomgang."))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Label(tr("The plan has changed. Request a new review.", "Planen er endret. Be om ny gjennomgang."),
                              systemImage: "clock.arrow.circlepath")
                            .foregroundStyle(.secondary)
                    }
                    if let error { Text(error).foregroundStyle(.red).font(.subheadline) }
                }
                .padding(20).frame(maxWidth: 700).frame(maxWidth: .infinity, alignment: .top)
            }
            .background(ATHLTHTrainDesign.canvas)
            .navigationTitle(tr("Plan review", "Plangjennomgang"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Close", "Lukk")) { dismiss() }
                }
            }
            .confirmationDialog(tr("Approve this change?", "Godkjenne denne endringen?"),
                                isPresented: $confirming, titleVisibility: .visible) {
                Button(tr("Approve", "Godkjenn")) { apply() }
                Button(tr("Cancel", "Avbryt"), role: .cancel) {}
            } message: {
                if let move = pendingMove {
                    Text(move.workoutTitle + " · " + move.sourceDate.formatted(date: .abbreviated, time: .omitted)
                        + " → " + move.targetDate.formatted(date: .abbreviated, time: .omitted))
                } else if let duration = pendingDuration {
                    Text(duration.workoutTitle + " · \(duration.suggestedMinutes) min")
                }
            }
            .onDisappear { task?.cancel() }
        }
    }

    private func findingCard(_ finding: ATHLTHPlanReviewAdvisor.Suggestion, plan: TrainingPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(finding.title).font(.headline)
            Text(finding.detail).font(.subheadline).foregroundStyle(.secondary)
            if let move = ATHLTHPlanReviewMoveProposal.suggest(for: finding, in: plan) {
                Text(move.workoutTitle + " · " + move.sourceDate.formatted(date: .abbreviated, time: .omitted)
                    + " → " + move.targetDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline.weight(.medium))
                Button(tr("Review move", "Gjennomgå flytting")) {
                    pendingDuration = nil
                    pendingMove = move
                    confirming = true
                }.buttonStyle(.borderedProminent).tint(ATHLTHTrainDesign.bronze).disabled(saving)
            } else if let duration = ATHLTHPlanReviewDurationProposal.suggest(for: finding, in: plan) {
                Text(duration.workoutTitle + " · \(duration.suggestedMinutes) min")
                    .font(.subheadline.weight(.medium))
                Text(tr("Based on \(duration.comparableSessionCount) comparable planned sessions.",
                        "Basert på \(duration.comparableSessionCount) sammenlignbare planøkter."))
                    .font(.caption).foregroundStyle(.secondary)
                Button(tr("Review duration", "Gjennomgå varighet")) {
                    pendingMove = nil
                    pendingDuration = duration
                    confirming = true
                }.buttonStyle(.borderedProminent).tint(ATHLTHTrainDesign.bronze).disabled(saving)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
    }

    @MainActor
    private func apply() {
        guard !saving, session.signedIn, session.profile.userID == ownerID else { return }
        let move = pendingMove
        let duration = pendingDuration
        guard move != nil || duration != nil else { return }
        saving = true
        error = nil
        task = Task { @MainActor in
            defer { saving = false; task = nil }
            do {
                // Local history is only used by the existing edit guards to
                // avoid changing completed workouts, not by a model.
                let history = health.hasRequestedAuthorization ? try await health.workoutHistory() : []
                try Task.checkCancellation()
                guard session.signedIn, session.profile.userID == ownerID,
                      let plan = session.trainingPlan(withID: review.planID), review.matches(plan) else { return }
                let applied: Bool
                if let move {
                    applied = session.applyPlanReviewMoveProposal(move, healthWorkouts: history,
                        strengthHistory: strength.workoutHistory)
                } else if let duration {
                    applied = session.applyPlanReviewDurationProposal(duration, healthWorkouts: history,
                        strengthHistory: strength.workoutHistory)
                } else { return }
                guard applied else {
                    error = tr("The workout is no longer eligible or the plan changed. Nothing was saved.",
                               "Økten kan ikke endres eller planen er oppdatert. Ingenting ble lagret.")
                    return
                }
                onApplied(tr("Approved change saved to your plan.", "Godkjent endring lagret i treningsplanen."))
                dismiss()
            } catch is CancellationError {} catch {
                error = tr("Could not verify workout history. Nothing was saved.",
                           "Kunne ikke kontrollere treningshistorikken. Ingenting ble lagret.")
            }
        }
    }
}

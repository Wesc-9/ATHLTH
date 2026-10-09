import SwiftUI

/// Explicit opt-in coaching recommendations, backed by recorded evidence.
struct ATHLTHTrainProgressionCoachView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var strength: StrengthWorkoutStore
    @EnvironmentObject private var health: HealthKitManager

    let planID: UUID

    @State private var incrementKg = 1.0
    @State private var pendingSuggestion: ATHLTHTrainProgressionCoach.Suggestion?
    @State private var pendingPlanVersion = 0
    @State private var confirmationVisible = false
    @State private var resultMessage: String?

    private let ink = Color(red: 0.17, green: 0.17, blue: 0.18)
    private let muted = Color(red: 0.47, green: 0.45, blue: 0.43)
    private let champagne = Color(red: 0.65, green: 0.53, blue: 0.35)
    private let paper = Color(red: 0.986, green: 0.977, blue: 0.963)
    private let border = Color(red: 0.89, green: 0.87, blue: 0.84)

    private var plan: TrainingPlan? { session.trainingPlan(withID: planID) }

    private var suggestions: [ATHLTHTrainProgressionCoach.Suggestion] {
        guard let plan else { return [] }
        let sessions = plan.weeks.flatMap(\.days).flatMap(\.sessions)
        let completed = Set(sessions.compactMap { workout -> UUID? in
            session.isPlanSessionCompleted(
                planID: planID, sessionID: workout.id,
                healthWorkouts: health.workouts,
                strengthHistory: strength.workoutHistory
            ) ? workout.id : nil
        })
        let skipped = Set(sessions.compactMap { workout -> UUID? in
            session.isPlanSessionSkipped(planID: planID, sessionID: workout.id)
                ? workout.id : nil
        })
        return ATHLTHTrainProgressionCoach.suggestions(
            plan: plan,
            strengthHistory: strength.workoutHistory,
            completedSessionIDs: completed,
            skippedSessionIDs: skipped,
            increaseKg: incrementKg
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    controlCard
                    if let plan {
                        if suggestions.isEmpty {
                            noRecommendations
                        } else {
                            ForEach(suggestions) { suggestion in
                                suggestionCard(suggestion, planVersion: plan.version)
                            }
                        }
                    }
                    infoFooter
                }
                .frame(maxWidth: 730, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(18)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .background(paper.ignoresSafeArea())
            .navigationTitle(tr("Progression suggestions", "Progresjonsforslag"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Close", "Lukk")) { dismiss() }
                        .foregroundStyle(ink)
                }
            }
            .confirmationDialog(
                tr("Apply this suggestion?", "Vil du bruke forslaget?"),
                isPresented: $confirmationVisible,
                titleVisibility: .visible
            ) {
                Button(tr("Update this planned exercise", "Oppdater denne øvelsen")) {
                    approve()
                }
                Button(tr("Keep existing targets", "Behold eksisterende mål"),
                       role: .cancel) {
                    pendingSuggestion = nil
                }
            } message: {
                if let pendingSuggestion {
                    Text(tr(
                        "Change \(pendingSuggestion.exerciseName) from \(pendingSuggestion.beforeLoad.formatted()) to \(pendingSuggestion.proposedLoad.formatted()) kg in \(pendingSuggestion.workoutName). No other workouts or completed results change.",
                        "Endre \(pendingSuggestion.exerciseName) fra \(pendingSuggestion.beforeLoad.formatted()) til \(pendingSuggestion.proposedLoad.formatted()) kg i \(pendingSuggestion.workoutName). Ingen andre økter eller registrerte resultater endres."
                    ))
                }
            }
            .alert(tr("Training plan", "Treningsplan"),
                   isPresented: Binding(
                    get: { resultMessage != nil },
                    set: { if !$0 { resultMessage = nil } }
                   )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(resultMessage ?? "")
            }
        }
        .preferredColorScheme(.light)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(tr("YOUR PROGRESS. YOUR DECISION.", "DIN FREMGANG. DITT VALG."))
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(champagne)
            Text(tr("Ready for the next step?", "Klar for neste steg?"))
                .font(.system(size: 31, weight: .regular, design: .serif))
                .foregroundStyle(ink)
            Text(plan?.title ?? "")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ink)
            Text(tr(
                "ATHLTH compares your prescribed sets with workouts you actually completed. Nothing changes unless you approve it.",
                "ATHLTH sammenligner planlagte sett med det du faktisk har gjennomført. Ingenting endres uten at du godkjenner."
            ))
            .font(.subheadline)
            .foregroundStyle(muted)
        }
    }

    private var controlCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("SUGGESTED LOAD ADJUSTMENT", "VALGFRI BELASTNINGSØKNING"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(champagne)
            Picker(tr("Increase", "Økning"), selection: $incrementKg) {
                Text("+0,5 kg").tag(0.5)
                Text("+1 kg").tag(1.0)
                Text("+2,5 kg").tag(2.5)
            }
            .pickerStyle(.segmented)

            Text(tr(
                "This is a user-adjustable option, not a medical or performance guarantee. A suggestion requires two separate completed, linked strength sessions meeting their targets.",
                "Dette er et valgfritt forslag, ikke en garanti for treningseffekt. Forslaget krever to separate, fullførte styrkeøkter hvor målene ble nådd."
            ))
            .font(.caption)
            .foregroundStyle(muted)
        }
        .padding(16)
        .coachSurface(border)
    }

    private var noRecommendations: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 25, weight: .ultraLight))
                .foregroundStyle(champagne)
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("No verified suggestions yet",
                        "Ingen dokumenterte forslag foreløpig"))
                    .font(.system(size: 20, weight: .regular, design: .serif))
                    .foregroundStyle(ink)
                Text(tr(
                    "Keep logging completed sets and training normally. You can still adjust any upcoming workout manually in Plan Studio.",
                    "Fortsett å registrere settene du faktisk gjennomfører. Du kan alltid justere kommende økter manuelt i Planstudio."
                ))
                .font(.caption)
                .foregroundStyle(muted)
            }
        }
        .padding(17)
        .coachSurface(border)
    }

    private func suggestionCard(
        _ item: ATHLTHTrainProgressionCoach.Suggestion,
        planVersion: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 11) {
                Image(systemName: "dumbbell")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(champagne)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.exerciseName)
                        .font(.system(size: 22, weight: .regular, design: .serif))
                        .foregroundStyle(ink)
                    Text(item.workoutName + " · " +
                         item.scheduledDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "sparkle")
                    .foregroundStyle(champagne)
            }

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.beforeLoad.formatted() + " kg")
                        .font(.system(size: 28, weight: .light, design: .rounded))
                        .foregroundStyle(ink)
                    Text(tr("CURRENT", "PLANLAGT"))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(muted)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .foregroundStyle(champagne)
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(item.proposedLoad.formatted() + " kg")
                        .font(.system(size: 28, weight: .light, design: .rounded))
                        .foregroundStyle(ink)
                    Text(tr("PROPOSED", "FORSLAG"))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(muted)
                }
            }
            .padding(13)
            .background(paper, in: RoundedRectangle(cornerRadius: 12))

            Label(tr(
                "\(item.matchingFinishedWorkouts) completed sessions met the planned targets, across \(item.workingSetsVerified) verified working sets.",
                "\(item.matchingFinishedWorkouts) fullførte økter nådde planlagte mål, fordelt på \(item.workingSetsVerified) kontrollerte arbeidssett."
            ), systemImage: "checkmark.shield")
            .font(.caption)
            .foregroundStyle(muted)

            Button {
                pendingSuggestion = item
                pendingPlanVersion = planVersion
                confirmationVisible = true
            } label: {
                HStack {
                    Spacer()
                    Text(tr("Review this adjustment", "Vurder denne justeringen"))
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(height: 44)
                .padding(.horizontal, 13)
                .background(ink, in: RoundedRectangle(cornerRadius: 11))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .coachSurface(border)
    }

    private var infoFooter: some View {
        Label(tr(
            "Rule-based guidance works without AI or sharing health data. Increases apply only to prescribed positive working-set weights. Warm-ups, past results, and other sessions are preserved.",
            "Regelbaserte forslag fungerer uten AI eller deling av helsedata. Bare angitte arbeidsvekter over 0 kg justeres. Oppvarming, tidligere resultater og andre økter beholdes."
        ), systemImage: "info.circle")
        .font(.caption)
        .foregroundStyle(muted)
    }

    private func approve() {
        guard let item = pendingSuggestion else { return }
        let saved = session.applySuggestedTrainingLoad(
            planID: planID,
            workoutID: item.workoutID,
            exerciseID: item.exerciseID,
            expectedVersion: pendingPlanVersion,
            expectedBeforeLoad: item.beforeLoad,
            approvedIncreaseKg: incrementKg,
            healthWorkouts: health.workouts,
            strengthHistory: strength.workoutHistory
        )
        pendingSuggestion = nil
        resultMessage = saved
            ? tr("The upcoming workout has been updated. You can still edit it manually.",
                 "Kommende økt er oppdatert. Du kan fortsatt redigere den manuelt.")
            : tr("Nothing was saved. The evidence or plan may have changed. Review the suggestion again.",
                 "Ingen endringer ble lagret. Planen eller prestasjonene kan ha endret seg. Kontroller forslaget på nytt.")
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }
}

private extension View {
    func coachSurface(_ border: Color) -> some View {
        self.background(.white, in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .stroke(border, lineWidth: 0.7)
            }
    }
}

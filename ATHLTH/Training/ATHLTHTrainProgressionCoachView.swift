import SwiftUI

/// Explicit opt-in coaching recommendations, backed by recorded evidence.
struct ATHLTHTrainProgressionCoachView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var strength: StrengthWorkoutStore
    @EnvironmentObject private var health: HealthKitManager

    let planID: UUID

    @State private var incrementKg = 1.0
    @State private var repetitionOptionsEnabled = false
    @State private var repetitionRangeLower = 6
    @State private var repetitionRangeUpper = 12
    @State private var pendingRepetitionSuggestion: ATHLTHTrainProgressionCoach.RepetitionSuggestion?
    @State private var pendingRepetitionRange: ATHLTHCoachStrengthRepetitionVolume.RepRange?
    @State private var repetitionConfirmationVisible = false
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

    private var hasStrengthProgressionGoal: Bool {
        plan?.builderProfile?.goal == .getStronger ||
        plan?.builderProfile?.goal == .buildMuscle
    }

    private var selectedRepRange: ATHLTHCoachStrengthRepetitionVolume.RepRange? {
        guard repetitionOptionsEnabled, hasStrengthProgressionGoal else { return nil }
        return ATHLTHCoachStrengthRepetitionVolume.RepRange(
            lower: repetitionRangeLower,
            upper: repetitionRangeUpper
        )
    }

    private var repetitionSuggestions: [ATHLTHTrainProgressionCoach.RepetitionSuggestion] {
        guard let plan, let range = selectedRepRange else { return [] }
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
        // The same exercise should never display competing increase-load
        // and increase-repetitions suggestions in one Coach review.
        let weightProposals = Set(suggestions.map(\.exerciseID))
        return ATHLTHTrainProgressionCoach.repetitionSuggestions(
            plan: plan,
            strengthHistory: strength.workoutHistory,
            completedSessionIDs: completed,
            skippedSessionIDs: skipped,
            range: range
        ).filter { !weightProposals.contains($0.exerciseID) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    localStrengthEvidence
                    controlCard
                    if hasStrengthProgressionGoal {
                        repetitionControlCard
                    }
                    if let plan {
                        if suggestions.isEmpty && repetitionSuggestions.isEmpty {
                            noRecommendations
                        } else {
                            ForEach(suggestions) { suggestion in
                                suggestionCard(suggestion, planVersion: plan.version)
                            }
                            ForEach(repetitionSuggestions) { suggestion in
                                repetitionSuggestionCard(suggestion, planVersion: plan.version)
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
            .confirmationDialog(
                tr("Increase the planned repetition target?", "Øke repetisjonsmålet?"),
                isPresented: $repetitionConfirmationVisible,
                titleVisibility: .visible
            ) {
                Button(tr("Update this planned exercise", "Oppdater denne øvelsen")) {
                    approveRepetitions()
                }
                Button(tr("Keep current repetitions", "Behold repetisjonene"),
                       role: .cancel) {
                    pendingRepetitionSuggestion = nil
                    pendingRepetitionRange = nil
                }
            } message: {
                if let item = pendingRepetitionSuggestion {
                    Text(tr(
                        "Change only \(item.exerciseName) from \(item.beforeReps) to \(item.proposedReps) reps in \(item.workoutName). Your past workouts and other sets stay unchanged.",
                        "Endre bare \(item.exerciseName) fra \(item.beforeReps) til \(item.proposedReps) repetisjoner i \(item.workoutName). Tidligere økter og andre sett forblir uendret."
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

    /// Read-only local analysis: it adds context but does not bypass the
    /// existing verified, user-approved progression proposal workflow.
    private var localStrengthEvidence: some View {
        let evidence = ATHLTHCoachStrengthIntelligence.snapshot(
            from: strength.workoutHistory
        )
        return VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Image(systemName: "chart.xyaxis.line")
                    .foregroundStyle(champagne)
                Text(tr("ATHLTH COACH · TRAINING EVIDENCE",
                        "ATHLTH COACH · TRENINGSGRUNNLAG"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(champagne)
            }
            Text(evidence.summary)
                .font(.subheadline)
                .foregroundStyle(ink)
            ForEach(Array(evidence.exerciseSignals.prefix(3)), id: \.exercise) { exercise in
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: exercise.trend == "improving"
                          ? "arrow.up.right" : exercise.trend == "plateau"
                          ? "equal" : "circle.dotted")
                        .font(.caption.weight(.semibold))
                        .frame(width: 20)
                        .foregroundStyle(champagne)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ATHLTHLocalization.isNorwegian
                             ? ATHLTHExerciseNameLocalization.norwegianName(for: exercise.exercise)
                             : exercise.exercise)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ink)
                        let message = exercise.recommendation == "review_small_increase"
                            ? tr("Targets reached twice · review a modest increase",
                                 "Mål nådd i to økter · vurder en liten økning")
                            : exercise.recommendation == "review_plateau"
                            ? tr("Progress is flat · review recovery and volume",
                                 "Utviklingen har flatet ut · vurder hvile og volum")
                            : tr("Keep logging before adjusting",
                                 "Fortsett å registrere før du justerer")
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(muted)
                    }
                    Spacer(minLength: 0)
                }
            }
            Text(tr(
                "Local estimates based on confirmed working sets. Missing data is not evidence of inactivity. The proposals below still require your approval.",
                "Lokale estimater fra registrerte arbeidssett. Manglende data betyr ikke manglende aktivitet. Forslagene nedenfor krever fortsatt godkjenning."
            ))
            .font(.caption2)
            .foregroundStyle(muted)
        }
        .padding(16)
        .coachSurface(border)
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

    /// No range is inferred from a broad training goal. The athlete enables
    /// this review and explicitly sets a range for the current Coach visit.
    private var repetitionControlCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(tr("REPETITION PROGRESSION", "PROGRESJON I REPETISJONER"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(champagne)
            Toggle(isOn: $repetitionOptionsEnabled) {
                Text(tr("Review repetition targets", "Vurder repetisjonsmål"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
            }
            .tint(champagne)

            if repetitionOptionsEnabled {
                Text(tr(
                    "Choose the intended range for this review. Coach won't infer it from the goal or change any exercise until you approve.",
                    "Velg ønsket repetisjonsområde for denne vurderingen. Coach gjetter ikke området fra målet og endrer ingen øvelse uten godkjenning."
                ))
                .font(.caption)
                .foregroundStyle(muted)

                Stepper(
                    value: $repetitionRangeLower,
                    in: 1...max(1, repetitionRangeUpper - 1)
                ) {
                    HStack {
                        Text(tr("Minimum reps", "Minste antall"))
                        Spacer()
                        Text("\(repetitionRangeLower)")
                            .monospacedDigit()
                            .foregroundStyle(ink)
                    }
                }
                Stepper(
                    value: $repetitionRangeUpper,
                    in: min(30, repetitionRangeLower + 1)...30
                ) {
                    HStack {
                        Text(tr("Maximum reps", "Høyeste antall"))
                        Spacer()
                        Text("\(repetitionRangeUpper)")
                            .monospacedDigit()
                            .foregroundStyle(ink)
                    }
                }
                Text(tr(
                    "Suggestions require two linked workouts with verified reserve (RIR/RPE). Volume recommendations are review-only.",
                    "Forslag krever to tilknyttede økter med registrert kapasitet igjen (RIR/RPE). Volumforslag er kun til vurdering."
                ))
                .font(.caption2)
                .foregroundStyle(muted)
            }
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

    private func repetitionSuggestionCard(
        _ item: ATHLTHTrainProgressionCoach.RepetitionSuggestion,
        planVersion: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "repeat")
                    .foregroundStyle(champagne)
                Text("ATHLTH COACH · " + tr("REPETITIONS", "REPETISJONER"))
                    .font(.caption.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(champagne)
                Spacer()
            }
            Text(item.exerciseName)
                .font(.system(size: 21, weight: .regular, design: .serif))
                .foregroundStyle(ink)
            Text(item.workoutName + " · " +
                 item.scheduledDate.formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundStyle(muted)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(item.beforeReps)")
                    .font(.system(size: 28, weight: .light, design: .rounded))
                Image(systemName: "arrow.right")
                    .foregroundStyle(champagne)
                Text("\(item.proposedReps)")
                    .font(.system(size: 28, weight: .light, design: .rounded))
                Text(tr("reps", "reps"))
                    .font(.subheadline)
                    .foregroundStyle(muted)
                Spacer()
                Text(item.prescribedWeightKg.formatted() + " kg")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ink)
            }
            .foregroundStyle(ink)
            .padding(12)
            .background(paper, in: RoundedRectangle(cornerRadius: 12))

            Label(tr(
                "Two completed sessions support one additional repetition at the same weight.",
                "To fullførte økter gir grunnlag for én ekstra repetisjon med samme vekt."
            ), systemImage: "checkmark.shield")
            .font(.caption)
            .foregroundStyle(muted)

            Button {
                guard let range = selectedRepRange else { return }
                pendingRepetitionSuggestion = item
                pendingRepetitionRange = range
                pendingPlanVersion = planVersion
                repetitionConfirmationVisible = true
            } label: {
                HStack {
                    Spacer()
                    Text(tr("Review repetition adjustment", "Vurder repetisjonsøkningen"))
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

    private func approveRepetitions() {
        guard let item = pendingRepetitionSuggestion,
              let range = pendingRepetitionRange else { return }
        let saved = session.applySuggestedTrainingRepetitions(
            planID: planID,
            workoutID: item.workoutID,
            exerciseID: item.exerciseID,
            expectedVersion: pendingPlanVersion,
            expectedBeforeReps: item.beforeReps,
            approvedReps: item.proposedReps,
            approvedRange: range,
            healthWorkouts: health.workouts,
            strengthHistory: strength.workoutHistory
        )
        pendingRepetitionSuggestion = nil
        pendingRepetitionRange = nil
        resultMessage = saved
            ? tr("The upcoming exercise's repetition target was updated.",
                 "Repetisjonsmålet i den kommende øvelsen er oppdatert.")
            : tr("Nothing changed. The plan or evidence may have changed. Review again.",
                 "Ingen endringer ble lagret. Planen eller datagrunnlaget kan ha endret seg. Kontroller forslaget på nytt.")
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

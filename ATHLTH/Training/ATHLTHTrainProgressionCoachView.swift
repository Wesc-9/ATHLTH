import SwiftUI

/// Explicit opt-in coaching recommendations, backed by recorded evidence.
struct ATHLTHTrainProgressionCoachView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var strength: StrengthWorkoutStore
    @EnvironmentObject private var health: HealthKitManager

    let planID: UUID
    /// iPad embeds Coach directly in the Studio detail column, which owns
    /// the back action. Modal iPhone presentations retain their Close button.
    var showsCloseButton = true

    @State private var incrementKg = 1.0
    // Confirmation is per exercise, never a blanket equipment assertion.
    @State private var confirmedLoadEquipment: Set<UUID> = []
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
    @State private var expandedEvidenceExerciseIDs: Set<UUID> = []

    private let ink = Color(red: 0.17, green: 0.17, blue: 0.18)
    private let muted = Color(red: 0.47, green: 0.45, blue: 0.43)
    private let champagne = Color(red: 0.65, green: 0.53, blue: 0.35)
    private let paper = Color(red: 0.986, green: 0.977, blue: 0.963)
    private let border = Color(red: 0.89, green: 0.87, blue: 0.84)

    private var plan: TrainingPlan? { session.trainingPlan(withID: planID) }

    private var rawLoadSuggestions: [ATHLTHTrainProgressionCoach.Suggestion] {
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

    private var combinedRepetitionReviews: (
        repetitions: [ATHLTHTrainProgressionCoach.RepetitionSuggestion],
        volumes: [ATHLTHTrainProgressionCoach.VolumeReviewSuggestion]
    ) {
        guard let plan, let range = selectedRepRange else { return ([], []) }
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
        return ATHLTHTrainProgressionCoach.progressionReviews(
            plan: plan,
            strengthHistory: strength.workoutHistory,
            completedSessionIDs: completed,
            skippedSessionIDs: skipped,
            range: range,
            now: Date(),
            calendar: .current
        )
    }

    var body: some View {
        // Compute each Coach review only once per render, not repeatedly for
        // the empty state and each list. This avoids expensive history scans
        // while interacting with the controls.
        let reviews = combinedRepetitionReviews
        let repFirst = Set(reviews.repetitions.map(\.exerciseID))
        let weightSuggestions = rawLoadSuggestions.filter {
            !repFirst.contains($0.exerciseID)
        }
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    localStrengthEvidence
                    controlCard
                    if hasStrengthProgressionGoal {
                        repetitionControlCard
                    }
                    if let plan {
                        if weightSuggestions.isEmpty && reviews.repetitions.isEmpty &&
                            reviews.volumes.isEmpty {
                            noRecommendations
                        } else {
                            ForEach(weightSuggestions) { suggestion in
                                suggestionCard(suggestion, planVersion: plan.version)
                            }
                            ForEach(reviews.repetitions) { suggestion in
                                repetitionSuggestionCard(suggestion, planVersion: plan.version)
                            }
                            ForEach(reviews.volumes) { suggestion in
                                volumeReviewCard(suggestion)
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
                if showsCloseButton {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(tr("Close", "Lukk")) { dismiss() }
                            .foregroundStyle(ink)
                    }
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
            if ATHLTHDeviceRole.isIPad && strength.workoutHistory.isEmpty {
                Label(tr(
                    "This iPad has no local structured strength history. iPhone/Watch sets are not automatically available here. Coach won't invent progression from an empty history.",
                    "Denne iPaden har ingen lokal, strukturert styrkehistorikk. Sett fra iPhone/Watch er ikke automatisk tilgjengelige her. Coach gir ikke oppdiktede progresjonsforslag."
                ), systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(muted)
                .padding(10)
                .background(
                    paper,
                    in: RoundedRectangle(cornerRadius: 11)
                )
                .accessibilityIdentifier("athlth-ipad-coach-missing-local-history")
            }
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
            .onChange(of: incrementKg) { _, _ in
                confirmedLoadEquipment.removeAll()
            }

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

            evidenceDisclosure(
                exerciseID: item.exerciseID,
                workoutIDs: item.sourceWorkoutIDs,
                setIDs: item.sourceSetIDs
            )

            Toggle(
                isOn: Binding(
                    get: { confirmedLoadEquipment.contains(item.exerciseID) },
                    set: { enabled in
                        if enabled {
                            confirmedLoadEquipment.insert(item.exerciseID)
                        } else {
                            confirmedLoadEquipment.remove(item.exerciseID)
                        }
                    }
                )
            ) {
                Text(tr(
                    "I confirm that the weight units match my logged workouts and this increase is available with my equipment.",
                    "Jeg bekrefter at vekten er oppgitt på samme måte som i historikken, og at denne økningen er mulig med utstyret mitt."
                ))
                .font(.caption)
                .foregroundStyle(muted)
            }
            .tint(champagne)

            Button {
                guard confirmedLoadEquipment.contains(item.exerciseID) else { return }
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
            .disabled(!confirmedLoadEquipment.contains(item.exerciseID))
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

            evidenceDisclosure(
                exerciseID: item.exerciseID,
                workoutIDs: item.sourceWorkoutIDs,
                setIDs: item.sourceSetIDs
            )

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

    /// Read-only review prompt: it never silently adds a set or changes a
    /// training plan. Concrete set-count changes must be made by the athlete.
    private func volumeReviewCard(
        _ item: ATHLTHTrainProgressionCoach.VolumeReviewSuggestion
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.xaxis")
                    .foregroundStyle(champagne)
                Text(tr("ATHLTH COACH · VOLUME REVIEW",
                        "ATHLTH COACH · VURDER TRENINGSMENGDE"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(champagne)
                Spacer()
            }
            Text(item.exerciseName)
                .font(.system(size: 22, weight: .regular, design: .serif))
                .foregroundStyle(ink)
            Text(item.workoutName + " · " +
                 item.scheduledDate.formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundStyle(muted)

            HStack(spacing: 10) {
                Label(
                    tr("\(item.comparableWorkouts) recorded sessions",
                       "\(item.comparableWorkouts) registrerte økter"),
                    systemImage: "calendar"
                )
                Label(
                    tr("\(item.verifiedWorkingSets) working sets",
                       "\(item.verifiedWorkingSets) arbeidssett"),
                    systemImage: "dumbbell"
                )
            }
            .font(.caption2)
            .foregroundStyle(muted)

            Text(tr(
                "You reached the top of your chosen rep range across several comparable workouts. Review recovery, exercise variation and weekly volume before changing the number of sets.",
                "Du ligger på toppen av det valgte repetisjonsområdet i flere sammenlignbare økter. Se på restitusjon, øvelsesvariasjon og ukentlig treningsmengde før du eventuelt endrer antall sett."
            ))
            .font(.subheadline)
            .foregroundStyle(ink)

            Label(
                tr("No automatic set increase. Adjust in Plan Studio if you choose.",
                   "Ingen automatisk økning i sett. Du kan justere selv i Planstudio."),
                systemImage: "hand.tap"
            )
            .font(.caption)
            .foregroundStyle(muted)

            evidenceDisclosure(
                exerciseID: item.exerciseID,
                workoutIDs: item.sourceWorkoutIDs,
                setIDs: []
            )
        }
        .padding(16)
        .coachSurface(border)
    }

    /// Explanations use exact logged workout and set IDs from the
    /// deterministic Coach decision, never arbitrary similarly named lifts.
    /// The detail stays collapsed for smooth scrolling on iPhone and iPad.
    private func evidenceDisclosure(
        exerciseID: UUID,
        workoutIDs: [UUID],
        setIDs: [UUID]
    ) -> some View {
        let expanded = expandedEvidenceExerciseIDs.contains(exerciseID)
        let sourceIDs = Set(workoutIDs)
        let exactSets = Set(setIDs)
        return VStack(alignment: .leading, spacing: 9) {
            Button {
                if expanded {
                    expandedEvidenceExerciseIDs.remove(exerciseID)
                } else {
                    expandedEvidenceExerciseIDs.insert(exerciseID)
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "doc.text.magnifyingglass")
                    Text(tr("Why this suggestion?", "Hvorfor dette forslaget?"))
                    Spacer()
                    Text("\(sourceIDs.count)")
                        .monospacedDigit()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(champagne)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                let sourceWorkouts = strength.workoutHistory
                    .filter { sourceIDs.contains($0.id) && $0.isFinished }
                    .sorted {
                        ($0.endedAt ?? $0.startedAt) >
                        ($1.endedAt ?? $1.startedAt)
                    }
                if sourceWorkouts.isEmpty {
                    Text(tr(
                        "The source workouts are not stored locally on this device. No results have been inferred.",
                        "Kildeøktene er ikke lagret lokalt på denne enheten. Ingen resultater er gjettet."
                    ))
                    .font(.caption)
                    .foregroundStyle(muted)
                } else {
                    ForEach(sourceWorkouts, id: \.id) { workout in
                        let included = workout.exercises.flatMap(\.sets).filter {
                            exactSets.contains($0.id)
                        }
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle")
                                .foregroundStyle(champagne)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(workout.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(ink)
                                Text((workout.endedAt ?? workout.startedAt)
                                    .formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption2)
                                    .foregroundStyle(muted)
                                if !included.isEmpty {
                                    Text(tr(
                                        "\(included.count) verified working sets",
                                        "\(included.count) kontrollerte arbeidssett"
                                    ))
                                    .font(.caption2)
                                    .foregroundStyle(muted)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    if sourceWorkouts.count < sourceIDs.count {
                        Text(tr(
                            "Other source workouts are not available locally.",
                            "Andre kildeøkter er ikke tilgjengelige lokalt."
                        ))
                        .font(.caption2)
                        .foregroundStyle(muted)
                    }
                }
            }
        }
        .accessibilityIdentifier("athlth-coach-source-evidence")
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
        guard let item = pendingSuggestion,
              confirmedLoadEquipment.contains(item.exerciseID) else { return }
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

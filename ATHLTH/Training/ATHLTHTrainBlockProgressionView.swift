import SwiftUI

/// Athlete-controlled, preview-first adjustment of already planned workouts.
struct ATHLTHTrainBlockProgressionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore

    let planID: UUID
    let blockID: UUID

    @State private var selectedKind: TrainingBlockProgressionKind = .weight
    @State private var weightIncrement = 2.5
    @State private var repsIncrement = 1
    @State private var volumePercent = 60
    @State private var loadPercent = 90
    @State private var confirming = false
    @State private var pendingRule: TrainingBlockProgressionRule?
    @State private var pendingVersion = 0
    @State private var pendingWorkoutIDs: Set<UUID> = []
    @State private var resultMessage: String?

    private let ink = Color(red: 0.17, green: 0.17, blue: 0.18)
    private let muted = Color(red: 0.47, green: 0.45, blue: 0.43)
    private let bronze = Color(red: 0.65, green: 0.53, blue: 0.37)
    private let paper = Color(red: 0.986, green: 0.978, blue: 0.964)
    private let line = Color(red: 0.88, green: 0.86, blue: 0.83)

    private var plan: TrainingPlan? {
        session.trainingPlan(withID: planID)
    }
    private var block: TrainingPlanBlock? {
        plan?.trainingBlocks?.first { $0.id == blockID }
    }
    private var rule: TrainingBlockProgressionRule {
        TrainingBlockProgressionRule(
            kind: selectedKind,
            weightIncrementKilograms: weightIncrement,
            repetitionIncrement: repsIncrement,
            recoveryVolumeFactor: Double(volumePercent) / 100,
            recoveryWeightFactor: Double(loadPercent) / 100
        )
    }
    private var protectedIDs: Set<UUID> {
        guard let plan else { return [] }
        return Set(plan.weeks.flatMap(\.days).flatMap(\.sessions).compactMap {
            workout -> UUID? in
            if session.isPlanSessionSkipped(planID: planID, sessionID: workout.id)
                || session.isPlanSessionCompleted(
                    planID: planID,
                    sessionID: workout.id,
                    healthWorkouts: health.workouts,
                    strengthHistory: strength.workoutHistory
                ) {
                return workout.id
            }
            return nil
        })
    }
    private var proposal: TrainingBlockProgressionEngine.Summary? {
        guard let plan else { return nil }
        return TrainingBlockProgressionEngine.prepare(
            plan: plan,
            blockID: blockID,
            rule: rule,
            protectedSessionIDs: protectedIDs
        )?.summary
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    introduction
                    settingsCard
                    if let proposal {
                        previewCard(proposal)
                    } else {
                        Text(tr(
                            "This block is not available for progression.",
                            "Denne treningsblokken kan ikke justeres."
                        ))
                        .font(.subheadline)
                        .foregroundStyle(muted)
                    }
                }
                .frame(maxWidth: 690, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(18)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            .background(paper.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                Button {
                    guard let plan, proposal?.hasChanges == true else { return }
                    pendingRule = rule
                    pendingVersion = plan.version
                    pendingWorkoutIDs = Set(proposal?.changes.map(\.workoutID) ?? [])
                    confirming = true
                } label: {
                    HStack {
                        Spacer()
                        Text(tr("Review and apply changes", "Godkjenn og lagre endringer"))
                        Spacer()
                        Image(systemName: "checkmark")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(height: 48)
                    .padding(.horizontal, 15)
                    .background(ink, in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(proposal?.hasChanges != true)
                .opacity(proposal?.hasChanges == true ? 1 : 0.45)
                .buttonStyle(.plain)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(.white)
            }
            .navigationTitle(tr("Block progression", "Blokkprogresjon"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Close", "Lukk")) { dismiss() }
                        .foregroundStyle(ink)
                }
            }
            .onAppear {
                if let previous = block?.progressionRule {
                    selectedKind = previous.kind
                    weightIncrement = previous.weightIncrementKilograms
                    repsIncrement = previous.repetitionIncrement
                    volumePercent = Int((previous.recoveryVolumeFactor * 100).rounded())
                    loadPercent = Int((previous.recoveryWeightFactor * 100).rounded())
                }
            }
            .confirmationDialog(
                tr("Apply progression?", "Bruke progresjonsforslaget?"),
                isPresented: $confirming,
                titleVisibility: .visible
            ) {
                Button(tr("Apply to future workouts", "Lagre i fremtidige økter")) {
                    applyProposal()
                }
                Button(tr("Cancel", "Avbryt"), role: .cancel) {
                    pendingRule = nil
                    pendingWorkoutIDs = []
                }
            } message: {
                Text(tr(
                    "Only the displayed workout prescriptions are changed. Completed training, past workouts and unprescribed exercise data are kept.",
                    "Bare de viste treningsmålene oppdateres. Gjennomførte økter, tidligere trening og uregistrerte belastninger beholdes."
                ))
            }
            .alert(tr("Training plan", "Treningsplan"),
                   isPresented: Binding(
                    get: { resultMessage != nil },
                    set: { shown in if !shown { resultMessage = nil } }
                   )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(resultMessage ?? "")
            }
        }
        .preferredColorScheme(.light)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("ATHLETE CONTROL", "DU BESTEMMER"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.7)
                .foregroundStyle(bronze)
            Text(block?.title ?? tr("Your training block", "Treningsblokken"))
                .font(.system(size: 30, weight: .regular, design: .serif))
                .foregroundStyle(ink)
            if let block {
                Text(tr("Weeks \(block.startWeek)–\(block.endWeek)",
                        "Uke \(block.startWeek)–\(block.endWeek)"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(bronze)
            }
            Text(tr(
                "Choose how your strength workouts progress. Review every change before committing it.",
                "Velg hvordan styrkeøktene skal utvikle seg, og se endringene før du godkjenner."
            ))
            .font(.subheadline)
            .foregroundStyle(muted)
        }
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tr("PROGRESSION RULE", "PROGRESJONSREGEL"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(bronze)
            Picker(tr("Progression", "Progresjon"), selection: $selectedKind) {
                ForEach(TrainingBlockProgressionKind.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)
            .tint(ink)

            switch selectedKind {
            case .weight:
                Stepper(
                    "+\(weightIncrement.formatted()) kg "
                        + tr("per week", "per uke"),
                    value: $weightIncrement, in: 0.5...10, step: 0.5
                )
                .font(.subheadline)
                Text(tr(
                    "Only exercises with a prescribed weight above 0 kg are adjusted.",
                    "Bare øvelser som har angitt belastning over 0 kg blir endret."
                ))
                .font(.caption).foregroundStyle(muted)
            case .repetitions:
                Stepper(
                    "+\(repsIncrement) " + tr("reps per week", "reps per uke"),
                    value: $repsIncrement, in: 1...5
                )
                .font(.subheadline)
            case .recovery:
                Stepper(
                    "\(volumePercent) % " + tr("of working sets", "av arbeidssettene"),
                    value: $volumePercent, in: 25...100, step: 5
                )
                .font(.subheadline)
                Stepper(
                    "\(loadPercent) % " + tr("of prescribed load", "av angitt vekt"),
                    value: $loadPercent, in: 50...100, step: 5
                )
                .font(.subheadline)
                Text(tr(
                    "Warm-up sets remain. At least one work set is kept per exercise.",
                    "Oppvarmingssett beholdes, og minst ett arbeidssett gjenstår."
                ))
                .font(.caption).foregroundStyle(muted)
            }

            Label(
                tr(
                    "Rules apply once per planned session. You can still edit every set manually afterward.",
                    "Regelen brukes én gang per planlagte økt. Du kan redigere alle sett manuelt etterpå."
                ),
                systemImage: "shield.checkered"
            )
            .font(.caption)
            .foregroundStyle(muted)
        }
        .padding(16)
        .progressionSurface(border: line)
    }

    private func previewCard(
        _ summary: TrainingBlockProgressionEngine.Summary
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(tr("BEFORE / AFTER", "FØR / ETTER"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(bronze)
                Spacer()
                Text("\(summary.changedWorkouts) " + tr("workouts", "økter"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ink)
            }

            HStack(spacing: 8) {
                statistic(
                    "\(summary.changedWorkouts)",
                    tr("WORKOUTS", "ØKTER")
                )
                statistic(
                    "\(summary.changedExercises)",
                    tr("EXERCISES", "ØVELSER")
                )
                statistic(
                    "\(summary.protectedCompleted + summary.protectedPast)",
                    tr("PROTECTED", "SKJERMET")
                )
            }

            if summary.changes.isEmpty {
                Text(tr(
                    "No eligible planned strength workouts will change. Check the selected rule or add workouts to future weeks.",
                    "Ingen fremtidige styrkeøkter kan justeres med denne regelen. Velg en annen regel eller legg til økter."
                ))
                .font(.subheadline)
                .foregroundStyle(muted)
            } else {
                ForEach(summary.changes.prefix(15)) { change in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(change.workoutName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ink)
                            Spacer()
                            Text(tr("Week \(change.weekNumber)", "Uke \(change.weekNumber)"))
                                .font(.caption)
                                .foregroundStyle(bronze)
                        }
                        Text(tr("BEFORE", "FØR"))
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(1)
                            .foregroundStyle(muted)
                        Text(change.before)
                            .font(.caption)
                            .foregroundStyle(ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(tr("AFTER", "ETTER"))
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(1)
                            .foregroundStyle(bronze)
                        Text(change.after)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(13)
                    .background(paper, in: RoundedRectangle(cornerRadius: 12))
                }
                if summary.changes.count > 15 {
                    Text(tr(
                        "\(summary.changes.count - 15) additional workouts are included.",
                        "\(summary.changes.count - 15) øvrige økter blir også påvirket."
                    ))
                    .font(.caption)
                    .foregroundStyle(muted)
                }
            }
            if summary.alreadyApplied > 0 {
                Label(
                    tr(
                        "\(summary.alreadyApplied) workouts already received this block's rule.",
                        "\(summary.alreadyApplied) økter har allerede fått blokkprogresjon."
                    ),
                    systemImage: "checkmark.shield"
                )
                .font(.caption)
                .foregroundStyle(muted)
            }
        }
        .padding(16)
        .progressionSurface(border: line)
    }

    private func statistic(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 23, weight: .regular, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(muted)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(paper, in: RoundedRectangle(cornerRadius: 10))
    }

    private func applyProposal() {
        guard let pendingRule else { return }
        let saved = session.applyTrainingBlockProgression(
            planID: planID,
            blockID: blockID,
            expectedVersion: pendingVersion,
            expectedWorkoutIDs: pendingWorkoutIDs,
            rule: pendingRule,
            healthWorkouts: health.workouts,
            strengthHistory: strength.workoutHistory
        )
        self.pendingRule = nil
        pendingWorkoutIDs = []
        if let saved {
            resultMessage = tr(
                "Updated \(saved.changedWorkouts) workouts and \(saved.changedExercises) exercises. Your completed history is unchanged.",
                "Oppdaterte \(saved.changedWorkouts) økter og \(saved.changedExercises) øvelser. Treningshistorikken er uendret."
            )
        } else {
            resultMessage = tr(
                "Nothing was saved. The plan may have changed or there are no eligible workouts. Review the preview again.",
                "Ingen endringer ble lagret. Planen kan være endret, eller ingen aktuelle økter gjenstår. Kontroller forslaget på nytt."
            )
        }
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }
}

private extension View {
    func progressionSurface(border: Color) -> some View {
        self
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(border, lineWidth: 0.7)
            }
    }
}

import SwiftUI

/// New Train-specific goal workspace over the existing shared ATHLTH GoalStore.
struct ATHLTHTrainGoalHubView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var goalStore: GoalStore
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore

    let planID: UUID
    @State private var showingNewGoal = false
    @State private var showingLinkPicker = false
    @State private var showingTrends = false

    private let ink = Color(red: 0.18, green: 0.18, blue: 0.17)
    private let muted = Color(red: 0.46, green: 0.45, blue: 0.43)
    private let accent = Color(red: 0.65, green: 0.53, blue: 0.35)
    private let canvas = Color(red: 0.985, green: 0.975, blue: 0.96)
    private let line = Color(red: 0.89, green: 0.87, blue: 0.84)

    private var plan: TrainingPlan? {
        session.trainingPlan(withID: planID)
    }
    private var linkedGoals: [ATHLTHGoal] {
        goalStore.goals.filter { $0.linkedTrainingPlanID == planID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    introduction
                    if let plan {
                        Button {
                            showingTrends = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "chart.xyaxis.line")
                                    .foregroundStyle(accent)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(tr("See exercise progress charts",
                                            "Se grafer for treningsutvikling"))
                                        .font(.subheadline.weight(.semibold))
                                    Text(tr("Recorded load, volume and working sets",
                                            "Registrert belastning, volum og arbeidssett"))
                                        .font(.caption)
                                        .foregroundStyle(muted)
                                }
                                Spacer()
                                Image(systemName: "arrow.right")
                            }
                            .foregroundStyle(ink)
                            .padding(15)
                            .goalSurface(line: line)
                        }
                        .buttonStyle(.plain)
                        if linkedGoals.isEmpty {
                            noLinkedGoals
                        } else {
                            ForEach(linkedGoals) { goal in
                                goalCard(goal, plan: plan)
                            }
                        }
                        blockReview(plan)
                    }
                }
                .frame(maxWidth: 740, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(18)
                .padding(.bottom, 25)
            }
            .scrollIndicators(.hidden)
            .background(canvas.ignoresSafeArea())
            .navigationTitle(tr("Goals and progress", "Mål og fremgang"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Close", "Lukk")) { dismiss() }
                }
            }
            .sheet(isPresented: $showingNewGoal) {
                if let plan {
                    ATHLTHTrainNewGoalView(plan: plan)
                }
            }
            .sheet(isPresented: $showingLinkPicker) {
                ATHLTHTrainGoalLinkView(planID: planID)
            }
            .sheet(isPresented: $showingTrends) {
                ATHLTHTrainTrendsView(planID: planID)
            }
        }
        .preferredColorScheme(.light)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("YOUR REASON TO TRAIN", "DET DU TRENER MOT"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(accent)
            Text(tr("Progress with purpose.", "Fremgang med et mål."))
                .font(.system(size: 31, weight: .regular, design: .serif))
                .foregroundStyle(ink)
            Text(plan?.title ?? "")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(muted)
            Text(tr(
                "Connect goals to your plan. See planned sessions beside verified results, without turning an estimate into a fact.",
                "Koble mål til treningsplanen. Se planlagt trening mot registrerte resultater – uten at estimater vises som fakta."
            ))
            .font(.subheadline)
            .foregroundStyle(muted)
            HStack(spacing: 9) {
                action(tr("New goal", "Nytt mål"), icon: "plus") {
                    showingNewGoal = true
                }
                action(tr("Link existing", "Knytt til eksisterende"), icon: "link") {
                    showingLinkPicker = true
                }
            }
        }
    }

    private func action(
        _ title: String,
        icon: String,
        onClick: @escaping () -> Void
    ) -> some View {
        Button(action: onClick) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ink)
                .padding(.horizontal, 12)
                .frame(minHeight: 42)
                .background(.white, in: RoundedRectangle(cornerRadius: 11))
                .overlay {
                    RoundedRectangle(cornerRadius: 11).stroke(line, lineWidth: 0.7)
                }
        }
        .buttonStyle(.plain)
    }

    private var noLinkedGoals: some View {
        HStack(spacing: 13) {
            Image(systemName: "target")
                .font(.system(size: 25, weight: .ultraLight))
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 5) {
                Text(tr("No goals linked yet", "Ingen mål knyttet til planen"))
                    .font(.system(size: 21, weight: .regular, design: .serif))
                Text(tr("Add one or link a goal you already follow.",
                        "Opprett et nytt mål eller bruk et du allerede følger."))
                    .font(.caption)
                    .foregroundStyle(muted)
            }
        }
        .padding(17)
        .goalSurface(line: line)
    }

    private func goalCard(_ goal: ATHLTHGoal, plan: TrainingPlan) -> some View {
        let completed = Set(plan.weeks.flatMap(\.days)
            .flatMap(\.sessions)
            .compactMap { workout -> UUID? in
                session.isPlanSessionCompleted(
                    planID: planID,
                    sessionID: workout.id,
                    healthWorkouts: health.workouts,
                    strengthHistory: strength.workoutHistory
                ) ? workout.id : nil
            })
        let evidence = ATHLTHTrainGoalEvidence.evaluate(
            goal: goal,
            plan: plan,
            strengthHistory: strength.workoutHistory,
            completedSessionIDs: completed
        )

        return VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: goal.category.systemImage)
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(accent)
                    .frame(width: 32, height: 35)
                VStack(alignment: .leading, spacing: 4) {
                    Text(goal.title)
                        .font(.system(size: 21, weight: .regular, design: .serif))
                        .foregroundStyle(ink)
                    Text(goal.status == .completed
                         ? tr("Completed goal", "Fullført mål")
                         : goal.status == .paused
                           ? tr("Paused goal", "Mål på pause")
                           : tr("Personal goal", "Personlig mål"))
                        .font(.caption)
                        .foregroundStyle(muted)
                }
                Spacer(minLength: 4)
                Menu {
                    Button {
                        goalStore.setLinkedPlan(
                            planID,
                            goalIDs: Set(linkedGoals.map(\.id)).subtracting([goal.id])
                        )
                    } label: {
                        Label(tr("Remove from this plan", "Fjern fra treningsplan"),
                              systemImage: "link.badge.minus")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(muted)
                        .frame(width: 30, height: 34)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(evidence.observed.map { number($0) } ?? "—")
                        .font(.system(size: 30, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(ink)
                    Text(tr("RECORDED", "REGISTRERT"))
                        .font(.system(size: 10, weight: .medium))
                        .tracking(1)
                        .foregroundStyle(muted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(evidence.target.map { number($0) } ?? "—")
                        .font(.system(size: 24, weight: .regular, design: .rounded))
                        .monospacedDigit()
                    Text(tr("TARGET", "MÅL") + " · " + (evidence.unit ?? ""))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(muted)
                }
            }

            if let fraction = evidence.completionFraction {
                GeometryReader { proxy in
                    Capsule()
                        .fill(line)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(accent)
                                .frame(width: proxy.size.width * fraction)
                        }
                }
                .frame(height: 6)
            }

            if evidence.hasEvidence {
                Text(evidence.evidenceLabel == "Recorded working-set load"
                     ? tr("Registered working-set weight · not estimated 1RM",
                          "Registrert arbeidsvekt · ikke estimert 1RM")
                     : tr("Only completed planned workouts count",
                          "Kun gjennomførte planlagte økter telles"))
                    .font(.caption)
                    .foregroundStyle(muted)
            } else {
                Text(tr("No verified plan-specific result yet.",
                        "Ingen verifiserte resultater fra denne planen ennå."))
                    .font(.caption)
                    .foregroundStyle(muted)
            }
            if goal.target?.metric == .strengthWeightKilograms,
               let exercise = goal.target?.exerciseName {
                Text(tr("Exercise", "Øvelse") + ": " + exercise)
                    .font(.caption)
                    .foregroundStyle(muted)
            }
            if goal.deadline != nil {
                Text(tr("Deadline", "Frist") + ": " +
                     (goal.deadline?.formatted(date: .abbreviated, time: .omitted) ?? ""))
                    .font(.caption)
                    .foregroundStyle(muted)
            }
        }
        .padding(17)
        .goalSurface(line: line)
    }

    private func blockReview(_ plan: TrainingPlan) -> some View {
        let strengthReport = TrainingPlanStrengthReport.make(
            plan: plan,
            strengthHistory: strength.workoutHistory
        )
        return VStack(alignment: .leading, spacing: 12) {
            Text(tr("TRAINING BLOCKS", "TRENINGSPERIODER"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(accent)
            Text(tr("Planned vs. performed", "Planlagt mot gjennomført"))
                .font(.system(size: 24, weight: .regular, design: .serif))
                .foregroundStyle(ink)

            if plan.trainingBlocks?.isEmpty != false {
                Text(tr("Add blocks in Plan Studio to compare each training period.",
                        "Opprett treningsblokker i Planstudio for å sammenligne periodene."))
                    .font(.subheadline)
                    .foregroundStyle(muted)
            }

            ForEach(plan.trainingBlocks ?? []) { block in
                let sessions = plan.weeks.enumerated()
                    .filter { block.contains(week: $0.offset + 1) }
                    .flatMap { $0.element.days.flatMap(\.sessions) }
                let completed = sessions.filter {
                    session.isPlanSessionCompleted(
                        planID: planID, sessionID: $0.id,
                        healthWorkouts: health.workouts,
                        strengthHistory: strength.workoutHistory
                    )
                }.count
                let fraction = sessions.isEmpty
                    ? 0.0 : Double(completed) / Double(sessions.count)
                let includedWeeks = strengthReport.weeks.filter {
                    block.contains(week: $0.number)
                }
                let plannedSets = includedWeeks.reduce(0) { $0 + $1.plannedWorkingSets }
                let performedSets = includedWeeks.reduce(0) { $0 + $1.performedWorkingSets }

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(block.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ink)
                            Text(tr("Weeks", "Uke") + " \(block.startWeek)–\(block.endWeek)"
                                + " · " + block.purpose.title)
                                .font(.caption)
                                .foregroundStyle(muted)
                        }
                        Spacer()
                        Text("\(completed) / \(sessions.count)")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                    }
                    GeometryReader { proxy in
                        Capsule().fill(line).overlay(alignment: .leading) {
                            Capsule().fill(accent)
                                .frame(width: proxy.size.width * fraction)
                        }
                    }
                    .frame(height: 5)
                    HStack {
                        Text(tr("Planned work sets", "Planlagte arbeidssett"))
                        Spacer()
                        Text("\(plannedSets)")
                    }
                    .font(.caption)
                    .foregroundStyle(muted)
                    HStack {
                        Text(tr("Recorded work sets", "Gjennomførte arbeidssett"))
                        Spacer()
                        Text("\(performedSets)")
                    }
                    .font(.caption)
                    .foregroundStyle(muted)
                    if !block.goal.isEmpty {
                        Text(block.goal)
                            .font(.caption)
                            .foregroundStyle(muted)
                            .lineLimit(3)
                    }
                }
                .padding(15)
                .goalSurface(line: line)
            }

            Text(tr(
                "A completed session is not the same as reaching a performance goal. Load and exercise results require recorded evidence.",
                "En gjennomført økt er ikke det samme som et oppnådd prestasjonsmål. Belastning og øvelsesresultater krever registrerte data."
            ))
            .font(.caption)
            .foregroundStyle(muted)
        }
    }

    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }
}

/// Link unassigned or already-linked goals without stealing goals from other plans.
private struct ATHLTHTrainGoalLinkView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var goalStore: GoalStore

    let planID: UUID
    @State private var selected: Set<UUID> = []

    private var available: [ATHLTHGoal] {
        goalStore.goals.filter {
            $0.linkedTrainingPlanID == nil || $0.linkedTrainingPlanID == planID
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if available.isEmpty {
                    ContentUnavailableView(
                        tr("No available goals", "Ingen tilgjengelige mål"),
                        systemImage: "target"
                    )
                }
                ForEach(available) { goal in
                    Button {
                        if selected.contains(goal.id) {
                            selected.remove(goal.id)
                        } else {
                            selected.insert(goal.id)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selected.contains(goal.id)
                                  ? "checkmark.circle.fill" : "circle")
                            VStack(alignment: .leading, spacing: 4) {
                                Text(goal.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(goal.category.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle(tr("Link goals", "Knytt mål til planen"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel", "Avbryt")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Save", "Lagre")) {
                        goalStore.setLinkedPlan(planID, goalIDs: selected)
                        dismiss()
                    }
                }
            }
            .onAppear {
                selected = Set(
                    goalStore.goals.filter { $0.linkedTrainingPlanID == planID }.map(\.id)
                )
            }
        }
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }
}

/// A light, plan-scoped creation path; all goals still use the shared GoalStore.
private struct ATHLTHTrainNewGoalView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var goalStore: GoalStore

    let plan: TrainingPlan
    @State private var mode = 0
    @State private var title = ""
    @State private var targetValue = 80.0
    @State private var withBaseline = false
    @State private var baseline = 60.0
    @State private var exercise = ""
    @State private var hasDeadline = false
    @State private var deadline = Date()

    private let ink = Color(red: 0.18, green: 0.18, blue: 0.17)
    private let muted = Color(red: 0.46, green: 0.45, blue: 0.43)
    private let canvas = Color(red: 0.985, green: 0.975, blue: 0.96)

    private var plannedExercises: [String] {
        let all = plan.weeks.flatMap(\.days).flatMap(\.sessions)
            .flatMap(\.exercises).map { $0.embeddedExercise.displayName }
        return Array(Set(all)).sorted()
    }

    private var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        title.count <= 100 && targetValue > 0 &&
        (!withBaseline || baseline < targetValue) &&
        (mode == 1 || !exercise.isEmpty)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    Text(tr("YOUR NEXT MILESTONE", "DITT NESTE MÅL"))
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(.secondary)
                    Text(tr("Aim for something.", "Noe å trene mot."))
                        .font(.system(size: 30, weight: .regular, design: .serif))
                        .foregroundStyle(ink)
                    Picker(tr("Goal type", "Måltype"), selection: $mode) {
                        Text(tr("Strength", "Styrke")).tag(0)
                        Text(tr("Sessions", "Treningsøkter")).tag(1)
                    }
                    .pickerStyle(.segmented)

                    TextField(
                        tr("e.g. 100 kg bench press", "F.eks. 100 kg benkpress"),
                        text: $title
                    )
                    .padding(14)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))

                    if mode == 0 {
                        if plannedExercises.isEmpty {
                            Text(tr("Add strength exercises to the plan before setting a measurable lift goal.",
                                    "Legg til styrkeøvelser i planen før du oppretter et målbart løftemål."))
                                .font(.caption)
                                .foregroundStyle(muted)
                        } else {
                            Picker(tr("Exercise", "Øvelse"), selection: $exercise) {
                                Text(tr("Choose exercise", "Velg øvelse")).tag("")
                                ForEach(plannedExercises, id: \.self) { name in
                                    Text(name).tag(name)
                                }
                            }
                            .tint(ink)
                        }
                    }

                    Stepper(
                        "\(targetValue.formatted()) " + (mode == 0 ? "kg" : tr("sessions", "økter")),
                        value: $targetValue,
                        in: mode == 0 ? 0.5...500.0 : 1...500,
                        step: mode == 0 ? 0.5 : 1
                    )
                    .font(.subheadline.weight(.medium))
                    .padding(13)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))

                    if mode == 0 {
                        Toggle(tr("Use a starting weight", "Oppgi utgangsvekt"),
                               isOn: $withBaseline)
                        if withBaseline {
                            Stepper(
                                "\(baseline.formatted()) kg",
                                value: $baseline, in: 0...499, step: 0.5
                            )
                        }
                    }

                    Toggle(tr("Set a deadline", "Velg frist"), isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker(tr("Deadline", "Frist"),
                                   selection: $deadline,
                                   in: Date()...,
                                   displayedComponents: .date)
                    }

                    Text(tr(
                        "Private by default. No AI required. A strength result is recorded working-set weight, not an estimated 1RM.",
                        "Privat som standard, helt uten AI. Styrkeresultatet viser registrert arbeidsvekt, ikke estimert 1RM."
                    ))
                    .font(.caption)
                    .foregroundStyle(muted)

                    Button(action: create) {
                        HStack {
                            Spacer()
                            Text(tr("Create linked goal", "Opprett mål i treningsplanen"))
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(15)
                        .background(ink, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canCreate)
                    .opacity(canCreate ? 1 : 0.45)
                }
                .frame(maxWidth: 600, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(18)
            }
            .background(canvas.ignoresSafeArea())
            .navigationTitle(tr("New goal", "Nytt treningsmål"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Close", "Lukk")) { dismiss() }
                }
            }
            .onAppear {
                if !plannedExercises.isEmpty && exercise.isEmpty {
                    exercise = plannedExercises[0]
                }
                targetValue = mode == 0 ? 80 : Double(
                    plan.weeks.flatMap(\.days).flatMap(\.sessions).count
                )
                targetValue = max(targetValue, 1)
            }
            .onChange(of: mode) { _, updated in
                targetValue = updated == 0 ? 80 : max(1, Double(
                    plan.weeks.flatMap(\.days).flatMap(\.sessions).count
                ))
            }
        }
        .preferredColorScheme(.light)
    }

    private func create() {
        guard canCreate else { return }
        let target = GoalTarget(
            metric: mode == 0 ? .strengthWeightKilograms : .workoutCount,
            targetValue: targetValue,
            unit: mode == 0 ? "kg" : "økter",
            baselineValue: mode == 0 && withBaseline ? baseline : (mode == 1 ? 0 : nil),
            activity: nil,
            exerciseName: mode == 0 ? exercise : nil
        )
        goalStore.add(ATHLTHGoal(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            category: mode == 0 ? .strength : .consistency,
            deadline: hasDeadline ? deadline : nil,
            privacy: .privateOnly,
            dataSource: mode == 0 ? .athlth : .manual,
            target: target,
            linkedTrainingPlanID: plan.id
        ))
        dismiss()
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }
}

private extension View {
    func goalSurface(line: Color) -> some View {
        self
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16).stroke(line, lineWidth: 0.7)
            }
    }
}

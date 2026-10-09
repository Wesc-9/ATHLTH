import SwiftUI

/// Program-period workspace used by the rebuilt Train -> Plan -> Plan Studio.
/// Only future empty days receive copied sessions. Historical results are
/// never rewritten and no AI generation is involved.
struct ATHLTHTrainPeriodizationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @AppStorage("athlth.planWorkspace.advancedMode") private var advanced = false

    let planID: UUID
    var onOpenWeek: ((Int) -> Void)? = nil

    @State private var chosenWeekIndex: Int
    @State private var weekTitle = ""
    @State private var phaseChoice = "none"
    @State private var allFuture = false
    @State private var progressionChoice: ProgressionChoice = .unchanged
    @State private var weightIncrement = 2.5
    @State private var repsIncrement = 1
    @State private var awaitingConfirmation = false
    @State private var showResult = false
    @State private var resultMessage = ""

    private let ink = Color(red: 0.17, green: 0.17, blue: 0.18)
    private let muted = Color(red: 0.47, green: 0.45, blue: 0.43)
    private let bronze = Color(red: 0.66, green: 0.52, blue: 0.35)
    private let border = Color(red: 0.88, green: 0.86, blue: 0.83)
    private let paper = Color(red: 0.986, green: 0.978, blue: 0.964)
    private let paleGold = Color(red: 0.96, green: 0.93, blue: 0.87)

    private enum ProgressionChoice: String, CaseIterable, Identifiable {
        case unchanged, weight, repetitions, fourWeekBlock
        var id: String { rawValue }
    }

    init(planID: UUID, initialWeekIndex: Int = 0,
         onOpenWeek: ((Int) -> Void)? = nil) {
        self.planID = planID
        self.onOpenWeek = onOpenWeek
        _chosenWeekIndex = State(initialValue: max(initialWeekIndex, 0))
    }

    private var plan: TrainingPlan? {
        session.trainingPlan(withID: planID)
    }

    private var week: TrainingPlanWeek? {
        guard let plan, plan.weeks.indices.contains(chosenWeekIndex) else {
            return nil
        }
        return plan.weeks[chosenWeekIndex]
    }

    private var scope: TrainingWeekCopyScope {
        allFuture ? .allFutureWeeks : .nextWeek
    }

    private var progression: TrainingWeekProgressionMode {
        guard advanced else { return .unchanged }
        switch progressionChoice {
        case .unchanged: return .unchanged
        case .weight: return .addWeightPerWeek(weightIncrement)
        case .repetitions: return .addRepsPerWeek(repsIncrement)
        case .fourWeekBlock: return .fourWeekStrengthBlock
        }
    }

    private var preview: TrainingWeekCopySummary {
        guard let plan, let week else { return TrainingWeekCopySummary() }
        return TrainingWeekTemplateEngine.preview(
            plan: plan, sourceWeekID: week.id, scope: scope
        )
    }

    private var canEditWeekLabel: Bool {
        week != nil &&
        !weekTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        weekTitle.count <= 80
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 19) {
                    heading

                    if let plan, let week {
                        timeline(plan)
                        selectedWeekDetail(week)
                        if advanced {
                            phaseEditor(week)
                        }
                        copyControl(plan: plan, week: week)
                    } else {
                        ContentUnavailableView(
                            tr("No training weeks", "Fant ingen treningsuker"),
                            systemImage: "calendar.badge.exclamationmark"
                        )
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(19)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(paper.ignoresSafeArea())
            .navigationTitle(tr("Training periods", "Treningsperioder"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Close", "Lukk")) { dismiss() }
                        .foregroundStyle(ink)
                }
            }
            .onAppear(perform: refreshEditor)
            .onChange(of: chosenWeekIndex) { _, _ in refreshEditor() }
            .confirmationDialog(
                tr("Apply week structure?", "Kopiere ukeoppsettet?"),
                isPresented: $awaitingConfirmation,
                titleVisibility: .visible
            ) {
                Button(tr("Copy into empty future days", "Kopier til ledige fremtidige dager")) {
                    applyWeekCopy()
                }
                Button(tr("Cancel", "Avbryt"), role: .cancel) {}
            } message: {
                Text(tr(
                    "Only empty upcoming days are filled. Existing workouts, previous weeks and completed results remain unchanged.",
                    "Bare tomme fremtidige dager får nye økter. Eksisterende økter og gjennomførte resultater beholdes."
                ))
            }
            .alert(tr("Training plan", "Treningsplan"),
                   isPresented: $showResult) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(resultMessage)
            }
        }
        .preferredColorScheme(.light)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("TRAINING IN PHASES", "PLANLEGG I PERIODER"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.8)
                .foregroundStyle(bronze)
            Text(tr("Make every week count.", "Gi hver uke et formål."))
                .font(.system(size: 30, weight: .regular, design: .serif))
                .foregroundStyle(ink)
            Text(tr(
                "Build the weeks ahead. Decide when to progress, when to hold steady and when to recover.",
                "Bygg kommende uker, velg progresjon og legg inn roligere perioder når det passer programmet."
            ))
            .font(.subheadline)
            .foregroundStyle(muted)
            HStack {
                Text(tr("EDITING LEVEL", "DETALJNIVÅ"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(muted)
                Spacer()
                Picker("", selection: $advanced) {
                    Text("Basic").tag(false)
                    Text(tr("Advanced", "Avansert")).tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
            }
            .padding(.top, 6)
        }
    }

    private func timeline(_ plan: TrainingPlan) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text(tr("YOUR PROGRAM", "HELE PROGRAMMET"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(bronze)
                Spacer()
                Text("\(plan.weeks.count) " + tr("weeks", "uker"))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(muted)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 71), spacing: 7)],
                spacing: 7
            ) {
                ForEach(Array(plan.weeks.enumerated()), id: \.element.id) { index, item in
                    let selected = index == chosenWeekIndex
                    Button {
                        chosenWeekIndex = index
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(tr("WEEK", "UKE"))
                                .font(.system(size: 9, weight: .semibold))
                                .tracking(0.8)
                                .opacity(0.7)
                            Text("\(index + 1)")
                                .font(.system(size: 22, weight: .regular, design: .serif))
                                .monospacedDigit()
                            HStack(spacing: 3) {
                                Image(systemName: item.strengthPhase == .deload
                                      ? "leaf" : "circle.fill")
                                    .font(.system(size: 8))
                                Text(phaseShortLabel(item))
                                    .font(.system(size: 9, weight: .medium))
                                    .lineLimit(1)
                            }
                        }
                        .foregroundStyle(selected ? .white : ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(
                            selected ? ink : (item.strengthPhase == .deload ? paleGold : .white),
                            in: RoundedRectangle(cornerRadius: 11)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 11)
                                .stroke(selected ? ink : border, lineWidth: 0.7)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        tr("Week \(index + 1), \(phaseShortLabel(item))",
                           "Uke \(index + 1), \(phaseShortLabel(item))")
                    )
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private func selectedWeekDetail(_ week: TrainingPlanWeek) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(tr("SELECTED WEEK", "VALGT UKE"))
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.3)
                        .foregroundStyle(bronze)
                    Text(week.title)
                        .font(.system(size: 25, weight: .regular, design: .serif))
                        .foregroundStyle(ink)
                }
                Spacer()
                Image(systemName: week.strengthPhase == .deload
                      ? "leaf" : "calendar")
                    .foregroundStyle(bronze)
            }

            let workouts = week.days.reduce(0) { $0 + $1.sessions.count }
            HStack(spacing: 8) {
                metric("\(workouts)", tr("SESSIONS", "ØKTER"))
                Rectangle().fill(border).frame(width: 0.7, height: 32)
                metric("\(week.days.filter { $0.sessions.isEmpty }.count)",
                       tr("FREE DAYS", "FRIDAGER"))
            }

            if let onOpenWeek {
                Button {
                    onOpenWeek(chosenWeekIndex)
                    dismiss()
                } label: {
                    HStack {
                        Text(tr("Open this week", "Åpne denne uken"))
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
                    .padding(13)
                    .background(paper, in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(17)
        .periodSurface(border: border)
    }

    private func phaseEditor(_ week: TrainingPlanWeek) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(tr("WEEK PURPOSE", "UKENS TRENINGSMÅL"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.3)
                .foregroundStyle(bronze)
            TextField(tr("Week or block name", "Navn på uke eller blokk"),
                      text: $weekTitle)
                .font(.subheadline)
                .padding(12)
                .background(paper, in: RoundedRectangle(cornerRadius: 10))
            Picker(tr("Training phase", "Treningsfase"), selection: $phaseChoice) {
                Text(tr("Unspecified", "Ikke angitt")).tag("none")
                Text(tr("Building", "Oppbygging")).tag("build")
                Text(tr("Recovery week", "Lettere uke")).tag("deload")
            }
            .tint(ink)
            Text(tr(
                "A week label does not change your sets or weights. Use the progression tool below to create adjusted training targets.",
                "Å markere en lettere uke endrer ikke vekter eller sett. Velg progresjon under for å opprette justerte treningsmål."
            ))
            .font(.caption)
            .foregroundStyle(muted)

            Button(action: savePhase) {
                HStack {
                    Spacer()
                    Text(tr("Save week details", "Lagre ukeinformasjon"))
                    Spacer()
                    Image(systemName: "checkmark")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(13)
                .background(ink, in: RoundedRectangle(cornerRadius: 11))
            }
            .buttonStyle(.plain)
            .disabled(!canEditWeekLabel)
            .opacity(canEditWeekLabel ? 1 : 0.45)
        }
        .padding(16)
        .periodSurface(border: border)
    }

    private func copyControl(plan: TrainingPlan, week: TrainingPlanWeek) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(tr("BUILD THE NEXT WEEKS", "BYGG KOMMENDE UKER"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.3)
                .foregroundStyle(bronze)
            Text(tr(
                "Repeat your current week in the available days ahead.",
                "Bruk denne uken som utgangspunkt for tomme dager videre i programmet."
            ))
            .font(.subheadline)
            .foregroundStyle(muted)

            Toggle(
                tr("Fill all future weeks", "Fyll alle kommende uker"),
                isOn: $allFuture
            )
            .tint(bronze)
            .font(.subheadline)

            if advanced {
                Divider().overlay(border)
                Text(tr("PROGRESSION MODEL", "PROGRESJONSMODELL"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.3)
                    .foregroundStyle(bronze)
                Picker(tr("Progression", "Progresjon"), selection: $progressionChoice) {
                    Text(tr("Same targets", "Samme belastning"))
                        .tag(ProgressionChoice.unchanged)
                    Text(tr("Add weight", "Øk vekten"))
                        .tag(ProgressionChoice.weight)
                    Text(tr("Add repetitions", "Øk repetisjoner"))
                        .tag(ProgressionChoice.repetitions)
                    Text(tr("4-week strength cycle", "Fireukers styrkeblokk"))
                        .tag(ProgressionChoice.fourWeekBlock)
                }
                .pickerStyle(.menu)
                .tint(ink)

                switch progressionChoice {
                case .weight:
                    Stepper(
                        tr("+\(weightIncrement.formatted()) kg per week",
                           "+\(weightIncrement.formatted()) kg per uke"),
                        value: $weightIncrement, in: 0.5...10, step: 0.5
                    )
                    .font(.subheadline)
                case .repetitions:
                    Stepper(
                        tr("+\(repsIncrement) reps per week",
                           "+\(repsIncrement) reps per uke"),
                        value: $repsIncrement, in: 1...5
                    )
                    .font(.subheadline)
                case .fourWeekBlock:
                    Text(tr(
                        "Three building weeks followed by one lower-volume week. This is a suggested model, not a mandatory training rule.",
                        "Tre oppbyggingsuker etterfulgt av en lettere uke. Dette er en valgfri progresjonsmodell."
                    ))
                    .font(.caption)
                    .foregroundStyle(muted)
                case .unchanged:
                    EmptyView()
                }
            }

            let summary = preview
            HStack(spacing: 14) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 21, weight: .light))
                    .foregroundStyle(bronze)
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("\(summary.copiedSessions) sessions to insert",
                            "\(summary.copiedSessions) økter kan legges inn"))
                        .font(.subheadline.weight(.semibold))
                    Text(tr(
                        "\(summary.targetWeeks) future weeks · \(summary.filledDays) empty days",
                        "\(summary.targetWeeks) kommende uker · \(summary.filledDays) ledige dager"
                    ))
                    .font(.caption)
                    .foregroundStyle(muted)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(paper, in: RoundedRectangle(cornerRadius: 10))

            Button {
                awaitingConfirmation = true
            } label: {
                HStack {
                    Spacer()
                    Text(tr("Preview confirmed – copy", "Kopier ukeoppsettet"))
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(14)
                .background(ink, in: RoundedRectangle(cornerRadius: 11))
            }
            .buttonStyle(.plain)
            .disabled(!summary.hasWork)
            .opacity(summary.hasWork ? 1 : 0.45)

            Text(tr(
                "No existing workouts are overwritten. Each copied session gets a fresh ID.",
                "Eksisterende økter overskrives ikke. Nye økter får egne ID-er."
            ))
            .font(.caption)
            .foregroundStyle(muted)
        }
        .padding(16)
        .periodSurface(border: border)
    }

    private func metric(_ value: String, _ name: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 23, weight: .regular, design: .rounded))
                .foregroundStyle(ink)
            Text(name)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func refreshEditor() {
        guard let week else { return }
        weekTitle = week.title
        switch week.strengthPhase {
        case .build: phaseChoice = "build"
        case .deload: phaseChoice = "deload"
        case nil: phaseChoice = "none"
        }
    }

    private func savePhase() {
        guard let week, canEditWeekLabel else { return }
        let phase: TrainingWeekStrengthPhase?
        switch phaseChoice {
        case "build": phase = .build
        case "deload": phase = .deload
        default: phase = nil
        }
        let success = session.configureTrainingWeek(
            planID: planID,
            weekID: week.id,
            title: weekTitle,
            phase: phase
        )
        resultMessage = success
            ? tr("The week is updated.", "Uken er oppdatert.")
            : tr("Could not save the week.", "Kunne ikke lagre ukeinformasjonen.")
        showResult = true
    }

    private func applyWeekCopy() {
        guard let week else { return }
        let result = session.copyTrainingWeekToEmptyDays(
            planID: planID,
            sourceWeekID: week.id,
            scope: scope,
            progression: progression
        )
        resultMessage = result.map {
            tr(
                "Copied \($0.copiedSessions) sessions across \($0.targetWeeks) weeks. Existing sessions were preserved.",
                "Kopierte \($0.copiedSessions) økter fordelt på \($0.targetWeeks) uker. Eksisterende økter er beholdt."
            )
        } ?? tr(
            "No eligible future days remain. No workouts were changed.",
            "Det finnes ingen ledige fremtidige dager. Ingen økter ble endret."
        )
        showResult = true
    }

    private func phaseShortLabel(_ week: TrainingPlanWeek) -> String {
        switch week.strengthPhase {
        case .build: return tr("Build", "Bygg")
        case .deload: return tr("Ease", "Lett")
        case nil: return tr("Plan", "Plan")
        }
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }
}

private extension View {
    func periodSurface(border: Color) -> some View {
        self
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(border, lineWidth: 0.7)
            }
    }
}

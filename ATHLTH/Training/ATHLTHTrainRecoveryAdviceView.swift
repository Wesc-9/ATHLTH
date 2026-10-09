import SwiftUI

/// A local-only, consent-aware planning aid. HealthKit summary values are
/// only considered after explicit opt-in in this screen; no AI calls.
struct ATHLTHTrainRecoveryAdviceView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore

    let planID: UUID

    @State private var energy = 0
    @State private var useHealthSignals = false
    @State private var pendingID: UUID?
    @State private var pendingVersion = 0
    @State private var pendingEnergy: Int?
    @State private var pendingReadiness: RecoveryReadinessSummary?
    @State private var showingConfirmation = false
    @State private var resultMessage: String?
    @State private var showUndoConfirmation = false
    @State private var undoWorkoutID: UUID?

    private let ink = Color(red: 0.18, green: 0.18, blue: 0.18)
    private let muted = Color(red: 0.46, green: 0.44, blue: 0.43)
    private let accent = Color(red: 0.57, green: 0.48, blue: 0.37)
    private let paper = Color(red: 0.985, green: 0.977, blue: 0.965)
    private let line = Color(red: 0.89, green: 0.87, blue: 0.84)

    private var plan: TrainingPlan? {
        session.trainingPlan(withID: planID)
    }

    /// Missing or stale HealthKit input must not imply an accurate score.
    private var freshReadiness: RecoveryReadinessSummary? {
        guard useHealthSignals,
              health.recovery.baselineDays >= 5,
              health.recovery.score != nil,
              health.recovery.state != .buildingBaseline,
              let sleepEnd = health.sleep.sleepEnd,
              let hrvDate = health.heart.hrvDate,
              let restingDate = health.heart.restingHeartRateDate else {
            return nil
        }
        let now = Date()
        let recent = [sleepEnd, hrvDate, restingDate].allSatisfy {
            let age = now.timeIntervalSince($0)
            return age >= 0 && age <= 48 * 3600
        }
        return recent ? health.recovery : nil
    }

    private var selectedEnergy: Int? {
        (1...5).contains(energy) ? energy : nil
    }

    private var completedIDs: Set<UUID> {
        guard let plan else { return [] }
        return Set(plan.weeks.flatMap(\.days).flatMap(\.sessions).compactMap {
            session.isPlanSessionCompleted(
                planID: planID, sessionID: $0.id,
                healthWorkouts: health.workouts,
                strengthHistory: strength.workoutHistory
            ) ? $0.id : nil
        })
    }

    private var skippedIDs: Set<UUID> {
        guard let plan else { return [] }
        return Set(plan.weeks.flatMap(\.days).flatMap(\.sessions).compactMap {
            session.isPlanSessionSkipped(planID: planID, sessionID: $0.id)
                ? $0.id : nil
        })
    }

    private var proposals: [ATHLTHTrainRecoveryAdvisor.Proposal] {
        guard let plan else { return [] }
        return ATHLTHTrainRecoveryAdvisor.proposals(
            plan: plan,
            completedIDs: completedIDs,
            skippedIDs: skippedIDs,
            strengthHistory: strength.workoutHistory,
            selfReportedEnergy: selectedEnergy,
            readiness: freshReadiness
        )
    }

    private var recoverableWorkouts: [PlannedSession] {
        guard let plan, let start = plan.startDate else { return [] }
        let today = Calendar.current.startOfDay(for: Date())
        return plan.weeks.enumerated().flatMap { weekIndex, week in
            week.days.flatMap { day -> [PlannedSession] in
                guard let date = Calendar.current.date(
                    byAdding: .day,
                    value: weekIndex * 7 + day.dayIndex - 1,
                    to: Calendar.current.startOfDay(for: start)
                ), date >= today else { return [] }
                return day.sessions.filter {
                    $0.recoveryOriginalExercises != nil &&
                    !completedIDs.contains($0.id) &&
                    !skippedIDs.contains($0.id)
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    heading
                    inputCard
                    if let plan {
                        if proposals.isEmpty {
                            noProposals
                        } else {
                            ForEach(proposals) { proposal in
                                proposedCard(proposal, planVersion: plan.version)
                            }
                        }
                        if !recoverableWorkouts.isEmpty {
                            undoSection
                        }
                    }
                    Label(tr(
                        "This is training guidance, not a medical assessment. Only you can decide whether to change a session.",
                        "Dette er treningsveiledning, ikke en medisinsk vurdering. Du bestemmer selv om en økt skal endres."
                    ), systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(muted)
                }
                .frame(maxWidth: 710, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(18)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(paper.ignoresSafeArea())
            .navigationTitle(tr("Recovery suggestions", "Restitusjonsforslag"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Close", "Lukk")) { dismiss() }
                }
            }
            .confirmationDialog(
                tr("Adjust this workout?", "Vil du justere treningsøkten?"),
                isPresented: $showingConfirmation,
                titleVisibility: .visible
            ) {
                Button(tr("Use lighter workout", "Bruk lettere økt")) {
                    approve()
                }
                Button(tr("Keep original workout", "Behold opprinnelig økt"),
                       role: .cancel) {
                    pendingID = nil
                }
            } message: {
                Text(tr(
                    "Only this upcoming workout's planned strength targets change. Recorded results remain untouched and you can undo the adjustment.",
                    "Bare planlagte styrkemål i denne kommende økten endres. Registrerte resultater beholdes, og du kan angre."
                ))
            }
            .confirmationDialog(
                tr("Restore original targets?", "Gjenopprette opprinnelige mål?"),
                isPresented: $showUndoConfirmation,
                titleVisibility: .visible
            ) {
                Button(tr("Restore workout", "Gjenopprett økt")) {
                    undo()
                }
                Button(tr("Cancel", "Avbryt"), role: .cancel) {
                    undoWorkoutID = nil
                }
            } message: {
                Text(tr(
                    "The original plan is restored only if no later manual changes were made.",
                    "Opprinnelige treningsmål gjenopprettes bare hvis økten ikke er redigert manuelt etterpå."
                ))
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

    private var heading: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(tr("TRAIN SMARTER, ON YOUR TERMS", "TREN SMARTERE, PÅ DINE PREMISSER"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(accent)
            Text(tr("Make room for recovery.", "Gi kroppen rom til å hente seg inn."))
                .font(.system(size: 30, weight: .regular, design: .serif))
                .foregroundStyle(ink)
            Text(plan?.title ?? "")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ink)
            Text(tr(
                "Check how you feel. ATHLTH can offer a lighter version of a strength workout for today or tomorrow; the choice is yours.",
                "Sjekk dagsformen. ATHLTH kan foreslå en lettere styrkeøkt for i dag eller i morgen, men du bestemmer."
            ))
            .font(.subheadline)
            .foregroundStyle(muted)
        }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tr("HOW DO YOU FEEL?", "HVORDAN ER DAGSFORMEN?"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(accent)
            Picker(tr("Energy level", "Energinivå"), selection: $energy) {
                Text(tr("Not selected", "Ikke valgt")).tag(0)
                Text("1").tag(1)
                Text("2").tag(2)
                Text("3").tag(3)
                Text("4").tag(4)
                Text("5").tag(5)
            }
            .pickerStyle(.segmented)
            Text(tr(
                "1 = very low energy · 5 = full of energy. Optional and not uploaded.",
                "1 = svært lite energi · 5 = masse energi. Frivillig og sendes ikke ut av appen."
            ))
            .font(.caption)
            .foregroundStyle(muted)

            Divider().overlay(line)
            Toggle(
                tr("Consider Apple Health recovery signals",
                   "Ta hensyn til restitusjonssignaler fra Apple Health"),
                isOn: $useHealthSignals
            )
            .tint(accent)
            .font(.subheadline)
            Text(tr(
                "Off by default. When enabled, the already-authorized sleep, HRV and resting-heart-rate summary is evaluated locally. Nothing is sent to an AI service.",
                "Av som standard. Når du slår på, vurderes allerede godkjente data om søvn, HRV og hvilepuls lokalt. Ingen opplysninger sendes til en AI-tjeneste."
            ))
            .font(.caption)
            .foregroundStyle(muted)

            if useHealthSignals {
                Label(
                    freshReadiness == nil
                        ? tr("Not enough recent and reliable health data. No recovery score is assumed.",
                             "Mangler oppdaterte og tilstrekkelige helsedata. Ingen restitusjonsscore antas.")
                        : tr("Recent readiness available: \(freshReadiness?.state.title ?? "").",
                             "Oppdatert dagsform tilgjengelig: \(freshReadiness?.state.title ?? "")."),
                    systemImage: freshReadiness == nil
                        ? "clock.badge.questionmark" : "checkmark.shield"
                )
                .font(.caption)
                .foregroundStyle(muted)
            }
        }
        .padding(17)
        .recoverySurface(border: line)
    }

    private var noProposals: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "leaf")
                .font(.system(size: 26, weight: .ultraLight))
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("No concrete adjustment suggested",
                        "Ingen konkret tilpasning foreslått"))
                    .font(.system(size: 20, weight: .regular, design: .serif))
                    .foregroundStyle(ink)
                Text(tr(
                    "A suggestion appears only when current inputs point to a possible need for an easier session and an upcoming strength workout has editable targets. You can always adjust your plan manually.",
                    "Et forslag vises når det finnes tegn på behov for en lettere økt, og en kommende styrkeøkt har redigerbare treningsmål. Du kan alltid endre planen manuelt."
                ))
                .font(.caption)
                .foregroundStyle(muted)
            }
        }
        .padding(17)
        .recoverySurface(border: line)
    }

    private func proposedCard(
        _ item: ATHLTHTrainRecoveryAdvisor.Proposal,
        planVersion: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 11) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.workoutTitle)
                        .font(.system(size: 22, weight: .regular, design: .serif))
                        .foregroundStyle(ink)
                    Text(item.scheduledDay.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(muted)
                }
                Spacer()
            }

            ForEach(item.signals, id: \.self) { signal in
                Label(signalText(signal), systemImage: "circle.dotted")
                    .font(.caption)
                    .foregroundStyle(muted)
            }

            HStack(spacing: 9) {
                comparison(tr("WORK SETS", "ARBEIDSSETT"),
                           "\(item.beforeWorkingSets)", "\(item.afterWorkingSets)")
                if let current = item.beforeWeight, let lighter = item.afterWeight {
                    comparison(tr("PEAK WEIGHT", "HØYESTE VEKT"),
                               "\(current.formatted()) kg", "\(lighter.formatted()) kg")
                }
            }

            Text(tr(
                "Example adaptation: fewer working sets and 10% less prescribed working weight. Warm-up sets and completed results are preserved.",
                "Forslag: færre arbeidssett og omtrent 10 % lavere planlagt arbeidsvekt. Oppvarmingssett og registrerte resultater beholdes."
            ))
            .font(.caption)
            .foregroundStyle(muted)

            Button {
                pendingID = item.workoutID
                pendingVersion = planVersion
                pendingEnergy = selectedEnergy
                pendingReadiness = freshReadiness
                showingConfirmation = true
            } label: {
                HStack {
                    Spacer()
                    Text(tr("Review lighter workout", "Vurder lettere treningsøkt"))
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
        .recoverySurface(border: line)
    }

    private func comparison(_ label: String, _ before: String, _ after: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(muted)
            HStack(spacing: 7) {
                Text(before)
                Image(systemName: "arrow.right").font(.caption2)
                Text(after)
                    .foregroundStyle(accent)
            }
            .font(.subheadline.weight(.medium))
            .minimumScaleFactor(0.8)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(paper, in: RoundedRectangle(cornerRadius: 10))
    }

    private var undoSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(tr("PREVIOUS ADJUSTMENTS", "TIDLIGERE TILPASNINGER"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.3)
                .foregroundStyle(accent)
            ForEach(recoverableWorkouts) { workout in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(workout.title)
                            .font(.subheadline.weight(.medium))
                        Text(tr("Recovery-adjusted workout", "Restitusjonstilpasset økt"))
                            .font(.caption)
                            .foregroundStyle(muted)
                    }
                    Spacer()
                    Button(tr("Undo", "Angre")) {
                        undoWorkoutID = workout.id
                        showUndoConfirmation = true
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ink)
                }
                .padding(13)
                .background(paper, in: RoundedRectangle(cornerRadius: 11))
            }
        }
        .padding(16)
        .recoverySurface(border: line)
    }

    private func signalText(_ signal: ATHLTHTrainRecoveryAdvisor.Signal) -> String {
        switch signal {
        case .lowSelfReportedEnergy:
            return tr("You reported low energy", "Du oppga lavt energinivå")
        case .lowRecentReadiness:
            return tr("Recent authorized recovery signals suggest taking it easier",
                      "Oppdaterte restitusjonssignaler kan tale for en roligere økt")
        case .denseRecentStrengthTraining:
            return tr("Three or more completed strength sessions in the last 72 hours",
                      "Tre eller flere fullførte styrkeøkter de siste 72 timene")
        }
    }

    private func approve() {
        guard let workoutID = pendingID else { return }
        let success = session.applyRecoveryAdjustment(
            planID: planID,
            workoutID: workoutID,
            expectedVersion: pendingVersion,
            energy: pendingEnergy,
            readiness: pendingReadiness,
            healthWorkouts: health.workouts,
            strengthHistory: strength.workoutHistory
        )
        pendingID = nil
        pendingReadiness = nil
        resultMessage = success
            ? tr("Workout targets updated. You can undo the adjustment here.",
                 "Økten er justert. Du kan angre tilpasningen her.")
            : tr("No changes saved. Your plan or available signals may have changed.",
                 "Ingen endringer er lagret. Planen eller tilgjengelige signaler kan ha endret seg.")
    }

    private func undo() {
        guard let workoutID = undoWorkoutID else { return }
        let success = session.undoRecoveryAdjustment(
            planID: planID, workoutID: workoutID,
            healthWorkouts: health.workouts,
            strengthHistory: strength.workoutHistory
        )
        undoWorkoutID = nil
        resultMessage = success
            ? tr("Original workout targets restored.", "Opprinnelige treningsmål er gjenopprettet.")
            : tr("Nothing changed. The workout may have been manually edited, completed or moved to a past day.",
                 "Ingen endringer. Økten kan ha blitt redigert manuelt, gjennomført eller flyttet til en tidligere dag.")
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }
}

private extension View {
    func recoverySurface(border: Color) -> some View {
        self.background(.white, in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .stroke(border, lineWidth: 0.7)
            }
    }
}

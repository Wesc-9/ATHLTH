import SwiftUI

/// The light "I dag" surface is deliberately separate from workout recording.
/// Plans feed this view, while launching still goes through ATHLTHTrainView.
struct ATHLTHTrainTodayPremiumView: View {
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var session: AppSessionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var goalStore: GoalStore
    @ObservedObject var workoutCatalog: WorkoutTemplateCatalogStore

    let plan: TrainingPlan?
    let sessions: [PlannedSession]
    let completedIDs: Set<UUID>
    let healthCompletedIDs: Set<UUID>
    let completionFraction: Double
    let planPosition: String
    let hasActiveWorkout: Bool
    let activeWorkoutKind: WorkoutKind?
    let lastCompletedWorkoutKind: WorkoutKind?
    /// Live recorder-owned content replaces the scheduled action while active.
    let activeWorkoutCard: AnyView?
    let hasRecordedWorkoutToday: Bool
    /// Already filtered for a reliable, recent HealthKit baseline by the parent.
    let todaysReadiness: RecoveryReadinessSummary?
    /// Most recently registered body mass from Apple Health, when accessible.
    let latestHealthWeightKilograms: Double?
    let onChooseSuggestedWorkout: (WorkoutTemplateCatalogEntry) -> Void
    let onOpenPlan: () -> Void
    let onCreatePlan: () -> Void
    let onOpenLibrary: () -> Void
    let onStartWorkout: (PlannedSession, Bool) -> Void
    let onWorkoutDetails: (PlannedSession, Bool) -> Void
    /// Changes only the selected unfinished workout after explicit approval.
    let onAcceptAlternative: (
        PlannedSession, ATHLTHDailyWorkoutAlternativeAdvisor.Suggestion
    ) -> Void
    let onUndoAlternative: (PlannedSession) -> Void

    @State private var reportedEnergy: Int?
    @State private var reportedStress: Int?
    @State private var reportedSoreness: Int?
    @State private var reportedMuscles: [String: RecoverySorenessLevel] = [:]
    @State private var pendingSwap: PendingSwap?

    private struct PendingSwap {
        let workout: PlannedSession
        let suggestion: ATHLTHDailyWorkoutAlternativeAdvisor.Suggestion
    }

    private var selfReportedSignals: ATHLTHDailyWorkoutAlternativeAdvisor.Signals {
        .init(energy: reportedEnergy, stress: reportedStress,
              overallSoreness: reportedSoreness,
              muscleRatings: reportedMuscles, readiness: todaysReadiness)
    }

    private func reloadCheckIn() {
        let current = RecoverySorenessStore()
        reportedEnergy = current.todayEnergy
        reportedStress = current.todayStress
        reportedSoreness = current.todayOverallSoreness
        reportedMuscles = current.todayRatings
    }
    let onQuickTrain: (WorkoutKind) -> Void
    let onQuickCycling: () -> Void
    let onQuickCustom: (CustomQuickWorkoutActivity) -> Void
    let onGhostRace: () -> Void

    @State private var quickActivityTapCounts: [String: Int] = [:]
    @State private var temporarilyFeaturedGoalID: UUID?
    @ScaledMetric(relativeTo: .body) private var activityTileWidth: CGFloat = 90


    private let ink = ATHLTHTrainDesign.ink
    private let muted = ATHLTHTrainDesign.secondary
    private let champagne = ATHLTHTrainDesign.bronze
    private let hairline = ATHLTHTrainDesign.rule

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let plan {
                activePlanSection(plan)
            }

            // The live recording replaces the planned hero, never creates
            // a competing Start button or a second workout recorder.
            if hasActiveWorkout, let activeWorkoutCard {
                activeWorkoutCard
            } else if let plan {
                let scheduled = sessions.filter { !$0.isExplicitRestDay }
                if scheduled.isEmpty && sessions.contains(where: \.isExplicitRestDay) {
                    restDayCard
                    if let swapped = sessions.first(where: {
                        $0.isExplicitRestDay && $0.dailyAlternativeOriginal != nil
                    }) {
                        undoAlternativeRow(swapped)
                    }
                } else if !scheduled.isEmpty &&
                            scheduled.allSatisfy({ completedIDs.contains($0.id) }) {
                    completedTodayCard(plan)
                } else if let workout = primaryWorkout {
                    workoutCard(workout, plan: plan)
                } else {
                    adaptiveOpenDayCard
                }
            } else {
                adaptiveOpenDayCard
            }

            remainingTodaySection
            quickTrainSection
            todayGoalAndFocus

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 16) {
                    if primaryWorkout != nil {
                        suggestedWorkoutSection
                    }
                    ghostRaceSection
                }
                .padding(.top, 12)
            } label: {
                Label(tr("More training options", "Flere treningsmuligheter"),
                      systemImage: "sparkles")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ink)
                    .frame(minHeight: 48)
            }
            .tint(champagne)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            reloadCheckIn()
            await workoutCatalog.refresh()
        }
        .task(id: session.profile.userID) {
            quickActivityTapCounts =
                UserDefaults.standard.dictionary(forKey: quickActivityStorageKey)
                    as? [String: Int] ?? [:]
            temporarilyFeaturedGoalID = nil
        }
        .onReceive(NotificationCenter.default.publisher(
            for: Notification.Name("athlth.dailyCheckInDidUpdate")
        )) { _ in
            reloadCheckIn()
        }
        .confirmationDialog(
            tr("Swap today's workout?", "Bytte dagens økt?"),
            isPresented: Binding(
                get: { pendingSwap != nil },
                set: { if !$0 { pendingSwap = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingSwap {
                Button(tr("Use", "Bruk") + " " + pendingSwap.suggestion.title) {
                    onAcceptAlternative(pendingSwap.workout, pendingSwap.suggestion)
                    self.pendingSwap = nil
                }
            }
            Button(tr("Cancel", "Avbryt"), role: .cancel) {
                pendingSwap = nil
            }
        } message: {
            Text(tr(
                "Only this unfinished workout changes. The original stays available to restore.",
                "Kun denne ufullførte økten endres. Du kan når som helst gjenopprette den opprinnelige økten."
            ))
        }
    }

    /// At ordinary text sizes the goal and daily coaching note share a
    /// pair of quiet tiles, like the Today reference. At accessibility
    /// sizes they stack instead of clipping text or reducing tap targets.
    private var todayGoalAndFocus: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) {
                    activeGoalSection
                    dailyFocusSection
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 10) {
                        activeGoalSection.frame(maxWidth: .infinity, alignment: .topLeading)
                        dailyFocusSection.frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(minWidth: 335)

                    VStack(spacing: 10) {
                        activeGoalSection
                        dailyFocusSection
                    }
                }
            }
        }
    }

    // The factual first-screen agenda: scheduled sessions are distinct from
    // HealthKit recordings, and a day without a plan is not labelled a rest day.
    private var todayAgendaStrip: some View {
        let planned = sessions.filter { !$0.isExplicitRestDay }
        let done = planned.filter { completedIDs.contains($0.id) }.count
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(tr("TODAY'S OVERVIEW", "DAGENS OVERSIKT"))
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.6)
                        .foregroundStyle(champagne)
                    Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.system(size: 24, weight: .regular, design: .serif))
                        .foregroundStyle(ink)
                }
                Spacer(minLength: 0)
                if hasActiveWorkout {
                    Label(
                        tr("Workout active", "Aktiv økt"),
                        systemImage: "waveform.path"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ink)
                } else if planned.isEmpty && hasRecordedWorkoutToday {
                    Label(
                        tr("Workout recorded", "Økt registrert"),
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.vitality)
                }
            }

            if !planned.isEmpty {
                HStack(spacing: 7) {
                    ForEach(planned) { workout in
                        Capsule()
                            .fill(
                                completedIDs.contains(workout.id)
                                    ? ATHLTHTheme.vitality
                                    : champagne.opacity(0.65)
                            )
                            .frame(height: 5)
                    }
                }
                Text(
                    "\(done) / \(planned.count) " +
                    tr("planned workouts complete", "planlagte økter fullført")
                )
                .font(.caption)
                .foregroundStyle(muted)
            } else {
                Text(sessions.contains(where: \.isExplicitRestDay)
                    ? tr("Recovery is scheduled today.", "I dag er det planlagt restitusjon.")
                    : tr("No scheduled workout. Choose a quick session or plan ahead.",
                         "Ingen planlagt økt. Start en rask økt eller planlegg fremover."))
                    .font(.caption)
                    .foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(17)
        .premiumTrainSurface(line: hairline)
    }

    private var futurePlanningAction: some View {
        Button {
            if plan != nil {
                onOpenPlan()
            } else {
                onCreatePlan()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(champagne)
                    .frame(width: 33)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("Plan your next workouts", "Planlegg kommende økter"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                    Text(tr(
                        "Build a week, choose a day, or reuse your workouts",
                        "Bygg en uke, velg en dag eller gjenbruk lagrede økter"
                    ))
                    .font(.caption)
                    .foregroundStyle(muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ink)
            }
            .padding(16)
            .premiumTrainSurface(line: hairline)
        }
        .buttonStyle(.plain)
        .accessibilityHint(tr(
            "Open training plan studio",
            "Åpne treningsplanstudio"
        ))
    }

    private var primaryWorkout: PlannedSession? {
        let workouts = sessions.filter { !$0.isExplicitRestDay }
        return workouts.first { !completedIDs.contains($0.id) } ?? workouts.first
    }

    /// Show an actual alternative and its reason immediately after the
    /// workout. The athlete never has to open a generic 'Adjust' tile to
    /// discover the recommendation.
    /// All actionable alternatives are visible without an intermediary tile,
    /// dropdown or navigation. The two safest choices for each signal are
    /// shown directly beneath the primary workout action.
    private func alternativeRecommendationCard(
        for workout: PlannedSession,
        suggestion: ATHLTHDailyWorkoutAlternativeAdvisor.Suggestion
    ) -> some View {
        let alternatives = Array(ATHLTHDailyWorkoutAlternativeAdvisor.suggestions(
            for: workout, signals: selfReportedSignals).prefix(2))

        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                Text(tr("ATHLTH SUGGESTS", "ATHLTH FORESLÅR"))
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                Spacer()
            }

            Text(suggestion.reason)
                .font(.caption)
                .foregroundStyle(ink)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                ForEach(alternatives) { option in
                    Button {
                        pendingSwap = PendingSwap(
                            workout: workout, suggestion: option)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: option.choice.symbol)
                                .font(.caption.weight(.semibold))
                            Text(option.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                        }
                        .frame(maxWidth: .infinity, minHeight: 45)
                        .foregroundStyle(
                            option.id == suggestion.id
                                ? Color.white : ATHLTHPlanDesign.accentInk)
                        .background(
                            option.id == suggestion.id
                                ? ATHLTHPlanDesign.accentInk
                                : Color.white.opacity(0.90),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(
                                    option.id == suggestion.id
                                        ? Color.clear : ATHLTHPlanDesign.outline,
                                    lineWidth: 0.8)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(tr(
                        "Review a replacement for today's workout",
                        "Bekreft et alternativ til dagens økt"))
                }
            }

            Text(tr("Your plan changes only after confirmation.",
                    "Planen endres først når du bekrefter."))
                .font(.system(size: 10))
                .foregroundStyle(muted)
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [ATHLTHPlanDesign.selectedSurface,
                         ATHLTHPlanDesign.warmSurface],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 15)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 15)
                .strokeBorder(ATHLTHPlanDesign.outline, lineWidth: 0.7)
        }
    }

    private func undoAlternativeRow(_ workout: PlannedSession) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
            Text(tr("Today's alternative selected",
                    "Dagens alternative økt er valgt"))
                .font(.caption.weight(.medium))
                .foregroundStyle(ink)
            Spacer()
            Button(tr("Undo", "Angre")) {
                onUndoAlternative(workout)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(ATHLTHPlanDesign.accentInk)
        }
        .padding(12)
        .background(ATHLTHPlanDesign.selectedSurface,
                    in: RoundedRectangle(cornerRadius: 13))
    }

    private var restDayCard: some View {
        Button(action: onOpenPlan) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "moon.stars")
                    .font(.title2.weight(.light))
                    .foregroundStyle(champagne)
                    .frame(width: 48, height: 48)
                    .background(ATHLTHTrainDesign.paleGold.opacity(0.3), in: Circle())
                    .accessibilityHidden(true)
                ATHLTHTrainSectionHeading(
                    eyebrow: tr("REST DAY", "HVILEDAG"),
                    title: tr("Recovery is on the schedule", "Restitusjon er planlagt"),
                    detail: tr("View the day in your training plan.", "Se dagen i treningsplanen."))
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.caption)
                    .foregroundStyle(champagne)
            }
            .padding(20)
            .athlthTrainPaper(emphasized: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    // A full date on regular widths, a shorter date where labels need room.
    private func todayDateLabel(color: Color) -> some View {
        ViewThatFits(in: .horizontal) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .fixedSize(horizontal: true, vertical: false)
            Text(Date.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                .fixedSize(horizontal: true, vertical: false)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(color)
        .lineLimit(1)
        .accessibilityLabel(
            Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))
        )
    }

    private func workoutCard(
        _ workout: PlannedSession, plan: TrainingPlan
    ) -> some View {
        let finished = completedIDs.contains(workout.id)
        let blocks = ATHLTHUnifiedWorkout.editorBlocks(from: workout)
        let exerciseCount = Set(blocks.filter { $0.kind == .exercise }
            .map { $0.exerciseSlug ?? $0.title }).count
        let pauseCount = blocks.expandedForExecution()
            .filter { $0.kind == .rest }.count

        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 11) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        workoutTextAndStart(
                            workout, finished: finished,
                            exerciseCount: exerciseCount, pauseCount: pauseCount
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)

                        workoutPortrait(workout)
                            .frame(width: 110, height: 188)
                    }
                    .frame(minWidth: 313)

                    VStack(alignment: .leading, spacing: 12) {
                        workoutPortrait(workout)
                            .frame(maxWidth: .infinity)
                            .frame(height: 158)
                        workoutTextAndStart(
                            workout, finished: finished,
                            exerciseCount: exerciseCount, pauseCount: pauseCount
                        )
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        onWorkoutDetails(workout, healthCompletedIDs.contains(workout.id))
                    } label: {
                        Label(tr("View workout details", "Se øktdetaljer"),
                              systemImage: "list.bullet")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(champagne)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)

                    Menu {
                        Button {
                            onWorkoutDetails(workout, healthCompletedIDs.contains(workout.id))
                        } label: {
                            Label(tr("Workout details", "Øktdetaljer"),
                                  systemImage: "list.bullet")
                        }
                        Button(action: onOpenPlan) {
                            Label(tr("Open training plan", "Åpne treningsplan"),
                                  systemImage: "calendar")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.headline)
                            .foregroundStyle(ink)
                            .frame(width: 44, height: 44)
                            .background(ATHLTHTrainDesign.paleGold.opacity(0.35),
                                        in: Circle())
                    }
                    .accessibilityLabel(tr("Workout options", "Flere valg for økten"))
                }
            }
            .padding(15)
            .background(
                Color.white.opacity(0.96),
                in: RoundedRectangle(cornerRadius: 23, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 23, style: .continuous)
                    .strokeBorder(hairline.opacity(0.5), lineWidth: 0.7)
                    .allowsHitTesting(false)
            }

            if workout.dailyAlternativeOriginal != nil {
                undoAlternativeRow(workout)
            } else if !finished && !hasActiveWorkout,
                      let suggestion = ATHLTHDailyWorkoutAlternativeAdvisor
                        .suggestions(for: workout, signals: selfReportedSignals).first {
                alternativeRecommendationCard(for: workout, suggestion: suggestion)
            }
        }
    }

    private func workoutPortrait(_ workout: PlannedSession) -> some View {
        GeometryReader { geometry in
            Image(workoutImage(for: workout.kind))
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    private func workoutTextAndStart(
        _ workout: PlannedSession,
        finished: Bool,
        exerciseCount: Int,
        pauseCount: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("TODAY'S WORKOUT", "DAGENS ØKT"))
                .font(.caption2.weight(.semibold))
                .tracking(1.7)
                .foregroundStyle(champagne)

            Text(workout.title)
                .font(.system(.title2, design: .serif).weight(.semibold))
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)

            let facts = [
                workout.durationMinutes.map { "\($0) min" },
                exerciseCount > 0
                    ? "\(exerciseCount) " + tr("exercises", "øvelser") : nil,
                pauseCount > 0
                    ? "\(pauseCount) " + tr("rests", "pauser") : nil
            ].compactMap { $0 }
            Text(facts.isEmpty ? workout.kind.title : facts.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)

            Spacer(minLength: 4)

            Button {
                if finished || hasActiveWorkout {
                    onWorkoutDetails(workout, healthCompletedIDs.contains(workout.id))
                } else {
                    onStartWorkout(workout, healthCompletedIDs.contains(workout.id))
                }
            } label: {
                Label(
                    finished ? tr("View workout", "Se økten")
                        : hasActiveWorkout ? tr("Workout details", "Øktdetaljer")
                        : tr("Start workout", "Start økt"),
                    systemImage: finished || hasActiveWorkout
                        ? "arrow.up.right" : "play.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 51)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.73, green: 0.57, blue: 0.31),
                            Color(red: 0.57, green: 0.40, blue: 0.22)
                        ],
                        startPoint: .leading, endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint(tr(
                "Use the existing iPhone or Apple Watch workout setup",
                "Bruker eksisterende oppsett for iPhone eller Apple Watch"
            ))
        }
        .frame(minHeight: 188, alignment: .topLeading)
    }

    /// Keep every scheduled session reachable even while the recorder owns
    /// the main card. Opening details never launches a second recording.
    private var remainingTodaySection: some View {
        let hasUnfinishedWorkout = sessions.contains {
            !$0.isExplicitRestDay && !completedIDs.contains($0.id)
        }
        let visiblePrimaryID = !hasActiveWorkout && plan != nil && hasUnfinishedWorkout
            ? primaryWorkout?.id : nil
        let remaining = sessions.filter {
            !$0.isExplicitRestDay && $0.id != visiblePrimaryID
        }
        return VStack(alignment: .leading, spacing: 12) {
            if !remaining.isEmpty {
                Text(tr("ALSO TODAY", "OGSÅ I DAG"))
                    .font(.caption.weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(champagne)
                ForEach(remaining) { workout in
                    Button {
                        onWorkoutDetails(workout, healthCompletedIDs.contains(workout.id))
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: completedIDs.contains(workout.id)
                                  ? "checkmark.circle.fill" : workout.kind.systemImage)
                                .foregroundStyle(champagne)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(workout.title)
                                    .font(.headline)
                                    .foregroundStyle(ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                ATHLTHPlannedWorkoutSummaryView(workout: workout)
                                if completedIDs.contains(workout.id) {
                                    Text(tr("Completed", "Fullført"))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(champagne)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(muted)
                        }
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .padding(16)
                        .premiumTrainSurface(line: hairline)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    private func heroTimeline(for workout: PlannedSession) -> some View {
        let blocks = ATHLTHUnifiedWorkout.editorBlocks(from: workout)
        let phases = ATHLTHWorkoutTimelineOverview.sections(for: blocks)
        return VStack(alignment: .leading, spacing: 12) {
            if phases.isEmpty {
                Label(tr("View workout details", "Se øktens innhold"),
                      systemImage: "list.bullet")
                    .font(.subheadline.weight(.medium))
            } else {
                ForEach(Array(phases.enumerated()), id: \.element.id) { index, section in
                    ATHLTHTrainPhaseRow(
                        number: index + 1, title: section.phase.title,
                        detail: section.blocks
                            .map { $0.title }.joined(separator: " · "),
                        isLast: index == phases.count - 1)
                }
            }
            Label(tr("All steps and targets", "Alle øktdeler og mål"),
                  systemImage: "arrow.up.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(champagne)
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .contentShape(Rectangle())
    }
    // The primary CTA launches the existing workout setup, never a new
    // recording engine or an unsafely reconstructed historical session.
    private var openDayChoice: ATHLTHTrainOpenDayPolicy.Choice {
        ATHLTHTrainOpenDayPolicy.choose(
            hasRecordedToday: hasRecordedWorkoutToday,
            lastCompletedKind: lastCompletedWorkoutKind,
            activePrimaryGoal: primaryTrainGoal,
            quickTaps: quickActivityTapCounts,
            hasLibrarySuggestion: !suggestedWorkouts.isEmpty
        )
    }

    private func familiarQuickActivity(_ kind: WorkoutKind) -> QuickActivity {
        switch kind {
        case .running: return .running
        case .walking: return .walking
        case .strength: return .strength
        case .mobility: return .yoga
        case .recovery, .custom: return .custom
        }
    }

    private var adaptiveOpenDayCard: some View {
        let choice = openDayChoice
        let kind: QuickActivity?
        let eyebrow: String
        let title: String
        let detail: String


        switch choice {
        case .trainedToday:
            kind = nil
            eyebrow = tr("TRAINING RECORDED", "ØKT REGISTRERT")
            title = tr("You've trained today", "Du har trent i dag")
            detail = tr(
                "Your completed workout is in your history. Explore options if you want to plan ahead.",
                "Den fullførte økten ligger i historikken. Utforsk alternativer om du vil planlegge videre."
            )
        case .familiar(let workout):
            let activity = familiarQuickActivity(workout)
            kind = activity
            eyebrow = tr("BASED ON YOUR HISTORY", "BASERT PÅ HISTORIKKEN DIN")
            title = activity.title
            detail = tr(
                "You completed this activity previously. Start a new session with the familiar setup.",
                "Du har trent denne aktiviteten tidligere. Start en ny økt med det vanlige oppsettet."
            )
        case .goal(let workout):
            let activity = familiarQuickActivity(workout)
            kind = activity
            eyebrow = tr("CONNECTED TO YOUR GOAL", "KNYTTET TIL MÅLET DITT")
            title = activity.title
            detail = tr(
                "Your selected goal explicitly relates to this activity. Choose the workout that suits you today.",
                "Hovedmålet ditt er knyttet til denne aktiviteten. Velg økten som passer deg i dag."
            )
        case .favorite(let key):
            let activity = QuickActivity(rawValue: key) ?? .running
            kind = activity
            eyebrow = tr("YOUR FREQUENT CHOICE", "DITT VANLIGE VALG")
            title = activity.title
            detail = tr(
                "You often open this activity. Choose your workout details before starting.",
                "Du velger ofte denne aktiviteten. Velg øktdetaljer før du starter."
            )
        case .library:
            kind = nil
            eyebrow = tr("EXPLORE A WORKOUT", "UTFORSK EN ØKT")
            title = suggestedWorkouts.first?.title ?? tr("Find an activity", "Finn en aktivitet")
            detail = tr(
                "A workout from the existing library. Review the steps before deciding.",
                "En økt fra treningsbiblioteket. Se gjennom innholdet før du bestemmer deg."
            )
        case .explore:
            kind = nil
            eyebrow = tr("YOUR DAY, YOUR CHOICE", "DIN DAG, DITT VALG")
            title = tr("Find your next session", "Finn din neste økt")
            detail = tr(
                "Nothing is scheduled. Explore the library, start a familiar activity or take a rest day.",
                "Ingen økt er planlagt. Utforsk biblioteket, start en aktivitet eller velg en hviledag."
            )
        }

        return VStack(alignment: .leading, spacing: 0) {
            ATHLTHTrainSectionHeading(eyebrow: eyebrow, title: title)
                .padding(20)

            VStack(alignment: .leading, spacing: 13) {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 9) {
                    Button {
                        if let kind {
                            openQuickActivity(kind)
                        } else if case .library = choice,
                                  let suggestion = suggestedWorkouts.first {
                            onChooseSuggestedWorkout(suggestion)
                        } else {
                            onOpenLibrary()
                        }
                    } label: {
                        HStack(spacing: 9) {
                            Spacer(minLength: 0)
                            Image(systemName:
                                kind == nil ? "square.grid.2x2" : "play.fill")
                            Text(kind == nil
                                ? tr("Explore workouts", "Utforsk økter")
                                : tr("Set up workout", "Velg økt"))
                            Spacer(minLength: 0)
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(minHeight: 52)
                        .background(ink, in: RoundedRectangle(cornerRadius: 13))
                    }
                    .buttonStyle(.plain)

                    Button(action: onOpenLibrary) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(ink)
                            .frame(width: 52, height: 52)
                            .background(ATHLTHPlanDesign.warmSurface,
                                        in: RoundedRectangle(cornerRadius: 13))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tr("Training library", "Treningsbibliotek"))
                }
            }
            .padding(16)
        }
        .athlthTrainPaper(emphasized: true)
    }

    /// A plan-free day is not automatically a prescribed rest day. Keep
    /// this overview informational and allow the original Quick Train actions.
    private func openDayOverview(hasPlan: Bool) -> some View {
        let status = TrainTodayOverviewPolicy.status(
            hasPlan: hasPlan,
            hasRecordedWorkoutToday: hasRecordedWorkoutToday
        )

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sun.horizon")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(champagne)
                Text(tr("YOUR DAY", "DIN DAG"))
                    .font(.caption2.weight(.semibold))
                    .tracking(1.5)
                    .foregroundStyle(muted)
                Spacer(minLength: 4)
                if status == .trainedToday {
                    Label(
                        tr("Recorded", "Registrert"),
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(red: 0.19, green: 0.44, blue: 0.36))
                    .lineLimit(1)
                }
                todayDateLabel(color: muted)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(dayHeadline(for: status))
                    .font(.system(size: 24, weight: .regular, design: .serif))
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(dayDescription(for: status))
                    .font(.subheadline)
                    .foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Rectangle()
                .fill(hairline.opacity(0.75))
                .frame(height: 0.7)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "calendar")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(champagne)
                    .frame(width: 22)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("TODAY'S PLAN", "DAGENS PLAN"))
                        .font(.caption2.weight(.semibold))
                        .tracking(1.1)
                        .foregroundStyle(muted)
                    Text(hasPlan
                         ? tr("No scheduled workout", "Ingen planlagt økt")
                         : tr("No active training plan", "Ingen aktiv treningsplan"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ink)
                }
                Spacer(minLength: 0)
                if !hasPlan {
                    Button(action: onCreatePlan) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(ink)
                            .frame(width: 34, height: 34)
                            .background(
                                Color(red: 0.96, green: 0.94, blue: 0.91),
                                in: Circle()
                            )
                            .overlay {
                                Circle()
                                    .stroke(hairline.opacity(0.8), lineWidth: 0.8)
                            }
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        tr("Create training plan", "Opprett treningsplan")
                    )
                    .accessibilityHint(
                        tr("Open training plan builder", "Åpne treningsplanbyggeren")
                    )
                }
            }

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: todaysReadiness?.state.systemImage ?? "heart.text.square")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(champagne)
                    .frame(width: 22)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("RECOVERY", "RESTITUSJON"))
                        .font(.caption2.weight(.semibold))
                        .tracking(1.1)
                        .foregroundStyle(muted)

                    if let todaysReadiness, let score = todaysReadiness.score {
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Text(readinessTitle(todaysReadiness.state))
                                .font(.subheadline.weight(.medium))
                            Spacer(minLength: 4)
                            Text("\(score)/100")
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                        }
                        .foregroundStyle(ink)
                        Text(tr(
                            "Based on recent authorized health data, not a prescribed rest day.",
                            "Basert på oppdaterte helsedata – ikke en pålagt hviledag."
                        ))
                        .font(.caption)
                        .foregroundStyle(muted)
                        .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(tr(
                            "Not enough up-to-date health data for today's assessment.",
                            "Ikke nok oppdaterte helsedata til å vurdere dagsformen."
                        ))
                        .font(.caption)
                        .foregroundStyle(muted)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        }
        .padding(17)
        .premiumTrainSurface(line: hairline)
    }

    private func dayHeadline(
        for status: TrainTodayOverviewPolicy.Status
    ) -> String {
        switch status {
        case .trainedToday:
            return tr("You've trained today", "Du har trent i dag")
        case .noWorkoutInPlan:
            return tr("A flexible training day", "En åpen treningsdag")
        case .noActivePlan:
            return tr("Your day, your choice", "Dagen er din")
        }
    }

    private func dayDescription(
        for status: TrainTodayOverviewPolicy.Status
    ) -> String {
        switch status {
        case .trainedToday:
            return tr(
                "An activity has been recorded today, even though none was scheduled.",
                "En aktivitet er registrert i dag, selv om ingen økt var planlagt."
            )
        case .noWorkoutInPlan:
            return tr(
                "There is no workout in your plan today. You can rest or choose an activity.",
                "Det ligger ingen økt i planen i dag. Du kan hvile eller velge en aktivitet."
            )
        case .noActivePlan:
            return tr(
                "Nothing is scheduled. Rest, move freely, or build a training plan.",
                "Ingenting er planlagt. Hvil, beveg deg fritt eller lag en treningsplan."
            )
        }
    }

    private func readinessTitle(_ state: RecoveryReadinessState) -> String {
        switch state {
        case .ready: return tr("Ready for activity", "Klar for aktivitet")
        case .balanced: return tr("Balanced", "Balansert")
        case .takeItEasy: return tr("Take it a little easier", "Ta det litt roligere")
        case .recover: return tr("Consider recovery", "Vurder restitusjon")
        case .buildingBaseline: return tr("Building baseline", "Bygger grunnlag")
        }
    }

    // Curated and published recipes share a single source, so useful strength
    // suggestions remain available offline as well as online.
    private var suggestedWorkouts: [WorkoutTemplateCatalogEntry] {
        return TrainWorkoutSuggestionPolicy.pick(
            workoutCatalog.entries, preferredKind: primaryWorkout?.kind
        )
    }

    @ViewBuilder
    private var suggestedWorkoutSection: some View {
        let suggestions = suggestedWorkouts
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(tr("Popular from the library", "Populært fra biblioteket"))
                        .font(.system(size: 22, weight: .regular, design: .serif))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.80)
                    Spacer(minLength: 6)
                    Button(action: onOpenLibrary) {
                        HStack(spacing: 5) {
                            Text(tr("See all", "Se alle"))
                            Image(systemName: "chevron.right")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(muted)
                    }
                    .buttonStyle(.plain)
                }
                HStack(alignment: .top, spacing: 10) {
                    ForEach(suggestions.prefix(2)) { entry in
                        Button {
                            onChooseSuggestedWorkout(entry)
                        } label: {
                            HStack(spacing: 8) {
                                Image(suggestionImage(for: entry))
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 65, height: 76)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(ink)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Text(suggestionSubtitle(entry))
                                        .font(.system(size: 11))
                                        .foregroundStyle(muted)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(muted)
                            }
                            .padding(7)
                            .frame(maxWidth: .infinity, minHeight: 90,
                                   alignment: .leading)
                            .background(.white,
                                in: RoundedRectangle(cornerRadius: 16))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(hairline.opacity(0.8),
                                                  lineWidth: 0.65)
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func suggestionImage(
        for entry: WorkoutTemplateCatalogEntry
    ) -> String {
        switch entry.category.lowercased() {
        case "strength", "gym": return "StrengthQuickHero"
        case "walking", "hiking": return "GoalWalking"
        case "recovery", "mobility", "yoga": return "GoalRecovery"
        case "running", "cardio", "interval": return "GoalRunning"
        default: return "TrainHero"
        }
    }

    private func suggestionSubtitle(_ entry: WorkoutTemplateCatalogEntry) -> String {
        var parts = [entry.categoryTitle]
        if let minutes = entry.estimatedDurationMinutes, minutes > 0 {
            parts.append("\(minutes) min")
        }
        parts.append(tr(
            "\(entry.blocks.count) steps",
            "\(entry.blocks.count) steg"
        ))
        return parts.joined(separator: " · ")
    }

    // Shortcuts reuse the existing training library. No new recommendation
    // engine or Quick Train changes are needed for this navigation improvement.
    private func completedTodayCard(_ plan: TrainingPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 29, weight: .light))
                    .foregroundStyle(champagne)
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("Today's training is done", "Dagens trening er fullført"))
                        .font(ATHLTHTrainDesign.sectionTitle)
                        .foregroundStyle(ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(tr(
                        "Your planned sessions are complete.",
                        "De planlagte øktene dine er gjennomført."
                    ))
                    .font(.caption)
                    .foregroundStyle(muted)
                    todayDateLabel(color: muted)
                }
                Spacer(minLength: 0)
            }
            Button(action: onOpenPlan) {
                Label(tr("View your plan", "Se treningsplanen"),
                      systemImage: "calendar")
            }
            .buttonStyle(ATHLTHTrainPrimaryButtonStyle())
        }
        .padding(17)
        .premiumTrainSurface(line: hairline)
    }

    // Click history reflects intentional entry choices, not completed
    // workout statistics. Ordering is per ATHLTH account on this device.
    private enum QuickActivity: String, CaseIterable, Identifiable {
        case running, walking, strength, cycling, yoga, custom
        var id: String { rawValue }

        var image: String {
            switch self {
            case .running: return "GoalRunning"
            case .walking: return "GoalWalking"
            case .strength: return "StrengthQuickHero"
            case .cycling: return "TrainHero"
            case .yoga: return "GoalRelax"
            case .custom: return "GoalAdventure"
            }
        }

        var icon: String {
            switch self {
            case .running: return "figure.run"
            case .walking: return "figure.walk"
            case .strength: return "dumbbell.fill"
            case .cycling: return "bicycle"
            case .yoga: return "figure.yoga"
            case .custom: return "slider.horizontal.3"
            }
        }

        var title: String {
            switch self {
            case .running:
                return ATHLTHLocalization.choose(english: "Run", norwegian: "Løping")
            case .walking:
                return ATHLTHLocalization.choose(english: "Walk", norwegian: "Gå")
            case .strength:
                return ATHLTHLocalization.choose(english: "Strength", norwegian: "Styrke")
            case .cycling:
                return ATHLTHLocalization.choose(english: "Cycling", norwegian: "Sykling")
            case .yoga: return "Yoga"
            case .custom:
                return ATHLTHLocalization.choose(
                    english: "Custom", norwegian: "Egendefinert"
                )
            }
        }
    }

    private var quickActivityStorageKey: String {
        "athlth.train.today.quickTaps." + String(describing: session.profile.userID)
    }

    private var sortedQuickActivities: [QuickActivity] {
        let defaults = QuickActivity.allCases
        return defaults.sorted { first, second in
            let firstCount = quickActivityTapCounts[first.rawValue, default: 0]
            let secondCount = quickActivityTapCounts[second.rawValue, default: 0]
            if firstCount != secondCount { return firstCount > secondCount }
            return (defaults.firstIndex(of: first) ?? 0) <
                (defaults.firstIndex(of: second) ?? 0)
        }
    }

    private func recordQuickActivityTap(_ activity: QuickActivity) {
        var counts = quickActivityTapCounts
        counts[activity.rawValue] = min(
            counts[activity.rawValue, default: 0] + 1, 100_000
        )
        quickActivityTapCounts = counts
        UserDefaults.standard.set(counts, forKey: quickActivityStorageKey)
    }

    private func openQuickActivity(_ activity: QuickActivity) {
        guard !hasActiveWorkout else { return }
        recordQuickActivityTap(activity)
        social.quickTrainFriendIDs.removeAll()
        social.discardPreparedQuickTrainFriends()
        switch activity {
        case .running: onQuickTrain(.running)
        case .walking: onQuickTrain(.walking)
        case .strength: onQuickTrain(.strength)
        case .cycling: onQuickCycling()
        case .yoga: onQuickCustom(.yoga)
        case .custom: onQuickCustom(.other)
        }
    }

    /// The account's saved primary goal remains unchanged. Spotlighting
    /// another goal is a reversible display-only choice for this visit.
    private var primaryTrainGoal: ATHLTHGoal? {
        if let primary = goalStore.primaryGoal, primary.status == .active {
            return primary
        }
        return goalStore.activeGoals.first { $0.status == .active }
    }

    private var goalContextKind: WorkoutKind? {
        if hasActiveWorkout { return activeWorkoutKind }
        guard let workout = primaryWorkout,
              !completedIDs.contains(workout.id),
              !workout.isExplicitRestDay
        else { return nil }
        return workout.kind
    }

    private var goalRecommendationReason: String {
        switch goalContextKind {
        case .running:
            return tr("Matches today's run", "Passer til dagens løpeøkt")
        case .walking:
            return tr("Matches today's walk", "Passer til dagens gåøkt")
        case .strength:
            return tr("Matches today's strength training", "Passer til dagens styrkeøkt")
        case .mobility:
            return tr("Matches today's mobility work", "Passer til dagens bevegelighetstrening")
        case .recovery:
            return tr("Matches today's recovery", "Passer til dagens restitusjon")
        case .custom, .none:
            return tr("Relevant to today's workout", "Relevant for dagens trening")
        }
    }

    private var relevantGoalSuggestion: ATHLTHGoal? {
        ATHLTHTrainGoalPriority.recommend(
            goals: goalStore.activeGoals,
            primary: primaryTrainGoal,
            activity: goalContextKind,
            activePlanID: plan?.id
        )
    }

    private var visibleTrainGoal: ATHLTHGoal? {
        if let suggested = relevantGoalSuggestion,
           temporarilyFeaturedGoalID == suggested.id {
            return suggested
        }
        return primaryTrainGoal
    }

    @ViewBuilder
    private var activeGoalSection: some View {
        if let goal = visibleTrainGoal {
            let total = goal.milestones.count
            let done = goal.completedMilestones
            let weightProgress = ATHLTHTrainWeightGoalProgress.evaluate(
                target: goal.target,
                latestWeightKilograms: latestHealthWeightKilograms
            )
            // Incomplete Apple Health data must never become a fake percentage.
            let fraction = ATHLTHTrainWeightGoalProgress.visibleFraction(
                goal: goal, latestWeightKilograms: latestHealthWeightKilograms
            )

            VStack(alignment: .leading, spacing: 5) {
                NavigationLink {
                    GoalDetailView(goalID: goal.id)
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center, spacing: 8) {
                            Image(systemName: "target")
                                .font(.system(size: 22, weight: .regular))
                                .foregroundStyle(champagne)
                                .accessibilityHidden(true)
                            Text(tr("Active goal", "Aktivt mål"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(champagne)
                            Spacer(minLength: 2)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(champagne)
                                .accessibilityHidden(true)
                        }

                        HStack(alignment: .top, spacing: 8) {
                            Text(goal.title)
                                .font(.system(.title3, design: .serif).weight(.semibold))
                                .foregroundStyle(ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            ZStack {
                                Circle()
                                    .stroke(ATHLTHTrainDesign.paleGold, lineWidth: 6)
                                if let fraction {
                                    Circle()
                                        .trim(from: 0, to: fraction)
                                        .stroke(champagne, style: StrokeStyle(
                                            lineWidth: 6, lineCap: .round))
                                        .rotationEffect(.degrees(-90))
                                } else {
                                    Image(systemName: goal.category.systemImage)
                                        .font(.caption)
                                        .foregroundStyle(champagne)
                                }
                            }
                            .frame(width: 43, height: 43)
                            .accessibilityHidden(true)
                        }

                        if let weightProgress {
                            Text(tr(
                                "\(weightProgress.achievedKilograms.formatted(.number.precision(.fractionLength(1)))) of \(weightProgress.targetKilograms.formatted(.number.precision(.fractionLength(1)))) kg",
                                "\(weightProgress.achievedKilograms.formatted(.number.precision(.fractionLength(1)))) av \(weightProgress.targetKilograms.formatted(.number.precision(.fractionLength(1)))) kg"
                            ))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(muted)
                        } else if goal.target?.metric == .bodyWeightKilograms {
                            Text(tr("No comparable Apple Health weight yet",
                                    "Mangler sammenlignbare vektdata i Apple Health"))
                                .font(.caption)
                                .foregroundStyle(muted)
                        } else if total > 0 {
                            Text(tr("\(done) of \(total) milestones",
                                    "\(done) av \(total) delmål"))
                                .font(.caption)
                                .foregroundStyle(muted)
                        } else if let deadline = goal.deadline {
                            Text(deadline.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(muted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("Active goal", "Aktivt mål") + ": " + goal.title +
                    (fraction.map { ", \(Int(($0 * 100).rounded()))%" } ?? ""))

                if let suggested = relevantGoalSuggestion,
                   suggested.id != primaryTrainGoal?.id {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                            temporarilyFeaturedGoalID =
                                temporarilyFeaturedGoalID == suggested.id ? nil : suggested.id
                        }
                    } label: {
                        Label(
                            temporarilyFeaturedGoalID == suggested.id
                                ? tr("Main goal", "Hovedmål")
                                : tr("Relevant goal", "Relevant mål"),
                            systemImage: "sparkles"
                        )
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(champagne)
                        .frame(minHeight: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(goalRecommendationReason)
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity, minHeight: 174, alignment: .topLeading)
            .background(
                Color.white.opacity(0.95),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(hairline.opacity(0.43), lineWidth: 0.7)
                    .allowsHitTesting(false)
            }
        } else {
            NavigationLink {
                GoalsHubView()
            } label: {
                VStack(alignment: .leading, spacing: 11) {
                    Label(tr("Active goal", "Aktivt mål"), systemImage: "target")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(champagne)
                    Text(tr("Choose a goal", "Velg et mål"))
                        .font(.system(.title3, design: .serif))
                        .foregroundStyle(ink)
                    Image(systemName: "arrow.up.right")
                        .foregroundStyle(champagne)
                }
                .frame(maxWidth: .infinity, minHeight: 174, alignment: .topLeading)
                .padding(15)
                .background(
                    Color.white.opacity(0.95),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var dailyFocusSection: some View {
        let workout = primaryWorkout
        let focusTitle: String
        let focusBody: String
        let focusIcon: String

        if hasActiveWorkout {
            focusTitle = tr("Stay with your session", "Fortsett økten")
            focusBody = tr(
                "Your workout is being recorded. Resume it from the live card above.",
                "Økten registreres. Åpne den igjen fra livekortet over."
            )
            focusIcon = "waveform.path"
        } else if let workout, !completedIDs.contains(workout.id) {
            focusTitle = workout.title
            focusBody = workout.durationMinutes.map {
                tr("Planned duration: \($0) min. See workout details before you start.",
                   "Planlagt varighet: \($0) min. Se øktdetaljene før start.")
            } ?? tr("Review the planned steps before starting.",
                    "Se gjennom øktens deler før du starter.")
            focusIcon = workout.kind.systemImage
        } else if hasRecordedWorkoutToday {
            focusTitle = tr("Training recorded", "Trening registrert")
            focusBody = tr(
                "Today's workout is in your history. Plan or start another only if you want.",
                "Dagens økt ligger i historikken. Planlegg eller start en ny hvis du ønsker."
            )
            focusIcon = "checkmark.circle"
        } else if sessions.contains(where: \.isExplicitRestDay) {
            focusTitle = tr("Scheduled recovery", "Planlagt restitusjon")
            focusBody = tr("Your plan lists recovery today.",
                           "Treningsplanen har restitusjon i dag.")
            focusIcon = "leaf"
        } else {
            focusTitle = tr("Choose your training", "Velg dagens trening")
            focusBody = tr(
                "Start a familiar activity above or explore an exercise from the library.",
                "Start en kjent aktivitet over, eller utforsk en økt fra biblioteket."
            )
            focusIcon = "sparkles"
        }

        return VStack(alignment: .leading, spacing: 13) {
            Text(tr("Today's focus", "Dagens fokus"))
                .font(.headline.weight(.semibold))
                .foregroundStyle(ink)
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: focusIcon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(champagne)
                    .frame(width: 40, height: 40)
                    .background(ATHLTHTrainDesign.paleGold.opacity(0.35),
                                in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(focusTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(focusBody)
                        .font(.caption2)
                        .foregroundStyle(muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .athlthTrainPaper()
    }

    private var quickTrainSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(tr("Start a workout", "Start en økt"))
                    .font(.system(.title2, design: .serif).weight(.semibold))
                    .foregroundStyle(ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 3)
                Button(action: onOpenLibrary) {
                    HStack(spacing: 5) {
                        Text(tr("See all workouts", "Se alle økter"))
                        Image(systemName: "arrow.right")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(champagne)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }

            if hasActiveWorkout {
                Text(tr("Continue your current workout above before starting another.",
                        "Fortsett den aktive økten over før du starter en ny."))
                    .font(.caption)
                    .foregroundStyle(muted)
            }

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 9),
                    count: dynamicTypeSize.isAccessibilitySize ? 2 : 3
                ),
                spacing: 9
            ) {
                // The approved six choices remain in predictable positions
                // rather than rearranging themselves after each workout.
                ForEach(QuickActivity.allCases) { activity in
                    quickPhotoChoice(activity)
                        .disabled(hasActiveWorkout)
                }
            }
        }
    }

    private func quickPhotoChoice(_ activity: QuickActivity) -> some View {
        Button { openQuickActivity(activity) } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    quickChoiceIcon(activity)
                    Text(activity.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .minimumScaleFactor(0.84)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)

                VStack(spacing: 5) {
                    quickChoiceIcon(activity)
                    Text(activity.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 70)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 8)
            .background(
                Color.white.opacity(0.94),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(hairline.opacity(0.38), lineWidth: 0.7)
                    .allowsHitTesting(false)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(activity.title)
        .accessibilityHint(tr("Open workout setup", "Åpner treningsoppsett"))
    }

    private func quickChoiceIcon(_ activity: QuickActivity) -> some View {
        Image(systemName: activity.icon)
            .font(.system(size: 19, weight: .regular))
            .foregroundStyle(champagne)
            .frame(width: 38, height: 38)
            .background(ATHLTHTrainDesign.paleGold.opacity(0.44), in: Circle())
            .accessibilityHidden(true)
    }

    private var ghostRaceSection: some View {
        Button(action: onGhostRace) {
            ZStack(alignment: .leading) {
                GeometryReader { imageGeometry in
                    Image("GoalRunning")
                        .resizable()
                        .scaledToFill()
                        .saturation(0.25)
                        .frame(
                            width: imageGeometry.size.width,
                            height: 79
                        )
                        .clipped()
                        .allowsHitTesting(false)
                }
                .frame(height: 79)
                .allowsHitTesting(false)
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.69),
                        Color.black.opacity(0.43)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .allowsHitTesting(false)
                HStack(spacing: 13) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 19, weight: .medium))
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ghost Race")
                            .font(.system(size: 17, weight: .medium, design: .serif))
                        Text(tr("Race your previous results", "Tren mot dine tidligere tider"))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(15)
            }
            .frame(height: 79)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func activePlanSection(_ plan: TrainingPlan) -> some View {
        let progress = min(max(completionFraction, 0), 1)
        return Button(action: onOpenPlan) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 13) {
                    Image("GoalMountain")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 86, height: 94)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(tr("ACTIVE PLAN", "AKTIV PLAN"))
                            .font(.caption2.weight(.semibold))
                            .tracking(1.2)
                            .foregroundStyle(champagne)

                        Text(plan.title)
                            .font(.system(.title3, design: .serif).weight(.semibold))
                            .foregroundStyle(ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(2)

                        Text(planPosition)
                            .font(.caption)
                            .foregroundStyle(muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(champagne)
                        .accessibilityHidden(true)
                }

                HStack(spacing: 10) {
                    GeometryReader { geometry in
                        Capsule()
                            .fill(ATHLTHTrainDesign.paleGold.opacity(0.6))
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(champagne)
                                    .frame(width: geometry.size.width * progress)
                            }
                    }
                    .frame(height: 6)
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(ink)
                }
                .padding(.leading, 99)
            }
            .padding(15)
            .background(
                Color.white.opacity(0.96),
                in: RoundedRectangle(cornerRadius: 23, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 23, style: .continuous)
                    .strokeBorder(hairline.opacity(0.45), lineWidth: 0.7)
                    .allowsHitTesting(false)
            }
            .shadow(color: ATHLTHTrainDesign.ink.opacity(0.05), radius: 10, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: 23))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("Active plan", "Aktiv plan") +
                            ": " + plan.title + ", " + planPosition +
                            ", \(Int((progress * 100).rounded()))%")
        .accessibilityHint(tr("Open the training plan",
                              "Åpner treningsplanen"))
    }

    private func detailLabel(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .regular))
                .frame(width: 15)
            Text(text)
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(muted)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func workoutImage(for kind: WorkoutKind) -> String {
        switch kind {
        case .strength: return "GoalStrength"
        case .running: return "GoalRunning"
        case .walking: return "GoalWalking"
        case .recovery, .mobility: return "GoalRecovery"
        case .custom: return "TrainHero"
        }
    }

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }
}

/// Numerical progress against a body-weight target using Apple Health data.
/// Never substitutes completed milestones or a sample goal for actual kilograms.
enum ATHLTHTrainWeightGoalProgress {
    struct Result {
        let initial: Double
        let latest: Double
        let target: Double

        private var direction: Double { target < initial ? -1 : 1 }
        var achievedKilograms: Double { (latest - initial) * direction }
        var targetKilograms: Double { abs(target - initial) }
        var completionFraction: Double {
            min(max(achievedKilograms / targetKilograms, 0), 1)
        }
    }

    /// A nil result tells Today to present a missing-measurement state, not
    /// an unrelated milestone percentage. Other goals keep milestone progress.
    static func visibleFraction(
        goal: ATHLTHGoal,
        latestWeightKilograms: Double?
    ) -> Double? {
        if goal.target?.metric == .bodyWeightKilograms {
            return evaluate(
                target: goal.target, latestWeightKilograms: latestWeightKilograms
            )?.completionFraction
        }
        return goal.milestones.isEmpty ? nil : goal.progress
    }

    static func evaluate(
        target: GoalTarget?,
        latestWeightKilograms: Double?
    ) -> Result? {
        guard let target, target.metric == .bodyWeightKilograms,
              let start = target.baselineValue,
              let latest = latestWeightKilograms,
              start.isFinite, start > 0,
              latest.isFinite, latest > 0,
              target.targetValue.isFinite, target.targetValue > 0,
              abs(target.targetValue - start) >= 0.2
        else { return nil }

        return Result(initial: start, latest: latest, target: target.targetValue)
    }
}

private extension View {
    func premiumTrainSurface(line: Color) -> some View {
        athlthTrainPaper()
    }
}


/// Pure, deterministic selection for Train discovery. No user profiling,
/// hidden AI prescriptions or dependence on network availability.
enum TrainWorkoutSuggestionPolicy {
    static func pick(
        _ entries: [WorkoutTemplateCatalogEntry],
        preferredKind: WorkoutKind?
    ) -> [WorkoutTemplateCatalogEntry] {
        let safe = entries.filter { entry in
            !entry.blocks.isEmpty &&
            !["Advanced", "Avansert"].contains(where: {
                entry.difficulty.localizedCaseInsensitiveCompare($0) == .orderedSame
            }) &&
            !entry.tags.contains(where: { $0.localizedCaseInsensitiveContains("hyrox") })
        }.sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            return lhs.sortOrder < rhs.sortOrder
        }
        guard !safe.isEmpty else { return [] }

        let category: String?
        switch preferredKind {
        case .running: category = "running"
        case .walking: category = "walking"
        case .strength: category = "strength"
        default: category = nil
        }

        var ordered = safe
        if let category {
            let matched = safe.filter { $0.category == category }
            let remaining = safe.filter { $0.category != category }
            ordered = matched + remaining
        } else {
            let entryLevel = safe.filter { entry in
                ["Beginner", "Nybegynner", "All levels", "Alle nivåer"].contains { level in
                    entry.difficulty.localizedCaseInsensitiveCompare(level) == .orderedSame
                }
            }
            if !entryLevel.isEmpty {
                let other = safe.filter { entry in !entryLevel.contains(where: { $0.id == entry.id }) }
                ordered = entryLevel + other
            }
        }

        guard let first = ordered.first else { return [] }
        var picked = [first]
        if let different = ordered.dropFirst().first(where: {
            $0.category != first.category
        }) {
            picked.append(different)
        } else if let second = ordered.dropFirst().first {
            picked.append(second)
        }
        return picked
    }
}

/// Never infer a rest prescription from an empty calendar. HealthKit recovery
/// is informational only when a complete recent baseline is available.
enum TrainTodayOverviewPolicy {
    enum Status: Equatable {
        case noActivePlan
        case noWorkoutInPlan
        case trainedToday
    }

    static func status(
        hasPlan: Bool,
        hasRecordedWorkoutToday: Bool
    ) -> Status {
        if hasRecordedWorkoutToday { return .trainedToday }
        return hasPlan ? .noWorkoutInPlan : .noActivePlan
    }

    /// A completed iPhone workout still counts when HealthKit access is denied
    /// or its import has not finished. Never count an active, unfinished session.
    static func hasRecordedWorkout(
        on day: Date,
        healthStartDates: [Date],
        strengthEndDates: [Date],
        phoneCompletedDates: [Date],
        calendar: Calendar = .current
    ) -> Bool {
        healthStartDates.contains { calendar.isDate($0, inSameDayAs: day) } ||
            strengthEndDates.contains { calendar.isDate($0, inSameDayAs: day) } ||
            phoneCompletedDates.contains { calendar.isDate($0, inSameDayAs: day) }
    }

    static func reliableReadiness(
        _ readiness: RecoveryReadinessSummary,
        sleepEnd: Date?,
        hrvDate: Date?,
        restingHeartRateDate: Date?,
        now: Date = Date()
    ) -> RecoveryReadinessSummary? {
        guard readiness.baselineDays >= 5,
              readiness.score != nil,
              readiness.state != .buildingBaseline,
              let sleepEnd,
              let hrvDate,
              let restingHeartRateDate else {
            return nil
        }

        let fresh = [sleepEnd, hrvDate, restingHeartRateDate].allSatisfy {
            let age = now.timeIntervalSince($0)
            return age >= 0 && age <= 48 * 3600
        }
        return fresh ? readiness : nil
    }
}

import SwiftUI

struct CoachPlanAdaptationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var goalStore: GoalStore
    @EnvironmentObject private var health: HealthKitManager

    @State private var userNotes = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?
    @State private var appliedRecordID: UUID?

    private let service = CoachPlanAdaptationService()

    private var plan: TrainingPlan? {
        session.activePlan
    }

    private var proposal: CoachPlanChangeProposal? {
        guard let plan,
              let proposal = session.pendingCoachPlanProposal,
              proposal.isStillValid(for: plan)
        else {
            return nil
        }

        return proposal
    }

    private var recentTraining: [String] {
        guard session.signedIn, CoachHistoryPermission.isEnabled(userID: session.profile.userID) else { return [] }
        let cutoff = Date().addingTimeInterval(-14 * 86_400)

        return health.workouts
            .filter { $0.startDate >= cutoff }
            .sorted { $0.startDate > $1.startDate }
            .prefix(16)
            .map { workout in
                var pieces = [
                    workout.startDate.formatted(
                        date: .abbreviated,
                        time: .omitted
                    ),
                    workout.activity.rawValue,
                    "\(max(Int((workout.duration / 60).rounded()), 1)) min"
                ]

                if let distance = workout.distanceMeters,
                   distance > 0 {
                    pieces.append(
                        String(
                            format: "%.1f km",
                            distance / 1_000
                        )
                    )
                }

                return pieces.joined(separator: " · ")
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    intro

                    if let plan {
                        planContext(plan)

                        if let proposal {
                            proposalContent(proposal)
                        } else {
                            requestCard(plan)
                        }

                        historySection(planID: plan.id)
                    } else {
                        noPlanCard
                    }
                }
                .padding(20)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .background(
                ATHLTHPremiumCanvas(
                    accent: ATHLTHTheme.vitality.opacity(0.34)
                )
            )
            .navigationTitle("ATHLTH Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ADAPT YOUR PLAN")
                .font(.caption2.weight(.bold))
                .tracking(2.4)
                .foregroundStyle(ATHLTHTheme.mutedText)

            Text("Life changed. Your plan can too.")
                .font(
                    .system(
                        size: 31,
                        weight: .bold,
                        design: .serif
                    )
                )
                .foregroundStyle(ATHLTHTheme.primaryText)

            Text(
                "Coach reviews your current plan, goals and recent training, then proposes changes. Nothing is changed until you accept."
            )
            .font(.subheadline)
            .foregroundStyle(ATHLTHTheme.mutedText)
        }
    }

    private func planContext(_ plan: TrainingPlan) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(width: 44, height: 44)
                .background(
                    ATHLTHTheme.accentSoft,
                    in: RoundedRectangle(
                        cornerRadius: 14,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(plan.title)
                    .font(.headline)
                    .foregroundStyle(ATHLTHTheme.primaryText)

                Text(
                    ATHLTHLocalization.format(
                            english: "%d weeks · version %d",
                            norwegian: "%d uker · versjon %d",
                            plan.weeks.count,
                            plan.version
                        )
                )
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
            }

            Spacer()

            Text("ACTIVE")
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(ATHLTHTheme.vitality)
        }
        .padding(15)
        .background(
            Color.white.opacity(0.78),
            in: RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
        )
    }

    private func requestCard(_ plan: TrainingPlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What changed?")
                .font(.title3.weight(.bold))

            Text(
                "Optional. Tell Coach about travel, a busy week, missed sessions or a change in availability."
            )
            .font(.caption)
            .foregroundStyle(ATHLTHTheme.mutedText)

            TextEditor(text: $userNotes)
                .frame(minHeight: 96)
                .padding(10)
                .scrollContentBackground(.hidden)
                .background(
                    Color.white.opacity(0.74),
                    in: RoundedRectangle(
                        cornerRadius: 16,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 16,
                        style: .continuous
                    )
                    .stroke(
                        ATHLTHTheme.accentDeep.opacity(0.10),
                        lineWidth: 1
                    )
                }

            if let errorMessage {
                Label(
                    errorMessage,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.red)
            }

            if let infoMessage {
                Label(
                    infoMessage,
                    systemImage: "checkmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.vitality)
            }

            Button {
                Task {
                    await generate(for: plan)
                }
            } label: {
                HStack(spacing: 9) {
                    if isGenerating {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "sparkles")
                    }

                    Text(
                        isGenerating
                            ? "Coach is reviewing…"
                            : "Review my plan"
                    )
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .foregroundStyle(.white)
                .background(
                    ATHLTHTheme.accentDeep,
                    in: RoundedRectangle(
                        cornerRadius: 17,
                        style: .continuous
                    )
                )
            }
            .buttonStyle(.plain)
            .disabled(isGenerating)
        }
        .padding(17)
        .background(
            Color.white.opacity(0.66),
            in: RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
    }

    private func proposalContent(
        _ proposal: CoachPlanChangeProposal
    ) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 5) {
                Text("YOUR PLAN, ADAPTED")
                    .font(.caption2.weight(.bold))
                    .tracking(2.2)
                    .foregroundStyle(ATHLTHTheme.vitality)

                Text(proposal.headline)
                    .font(
                        .system(
                            size: 27,
                            weight: .bold,
                            design: .serif
                        )
                    )

                if !proposal.rationale.isEmpty {
                    Text(proposal.rationale)
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }
            }

            ForEach(proposal.changes) { change in
                changeCard(change)
            }

            VStack(alignment: .leading, spacing: 5) {
                Label(
                    "Why these changes?",
                    systemImage: "lightbulb.max.fill"
                )
                .font(.subheadline.weight(.semibold))

                Text(
                    "Coach uses the context available in ATHLTH and your note above. It does not assume missing health data means you skipped training."
                )
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
            }
            .padding(.top, 2)

            HStack(spacing: 10) {
                Button {
                    session.dismissCoachPlanProposal()
                    infoMessage = "Proposal dismissed. Your plan was not changed."
                } label: {
                    Text("Keep current plan")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.bordered)

                Button {
                    apply(proposal)
                } label: {
                    Label(
                        "Accept changes",
                        systemImage: "checkmark"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.accentDeep)
            }
        }
        .padding(17)
        .background(
            Color.white.opacity(0.76),
            in: RoundedRectangle(
                cornerRadius: 25,
                style: .continuous
            )
        )
    }

    private func changeCard(
        _ change: CoachPlanChange
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon(for: change.kind))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(width: 40, height: 40)
                .background(
                    ATHLTHTheme.accentSoft,
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(change.title)
                        .font(.subheadline.weight(.bold))

                    Spacer()

                    Text(label(for: change.kind).uppercased())
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }

                if !change.summary.isEmpty {
                    Text(change.summary)
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.primaryText)
                }

                if let sourceDate = change.sourceDate,
                   let targetDate = change.targetDate,
                   change.kind == .moveWorkout {
                    Text(
                        sourceDate.formatted(
                            date: .abbreviated,
                            time: .omitted
                        ) +
                        " → " +
                        targetDate.formatted(
                            date: .abbreviated,
                            time: .omitted
                        )
                    )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.vitality)
                } else if let targetDate = change.targetDate {
                    Text(
                        targetDate.formatted(
                            date: .abbreviated,
                            time: .omitted
                        )
                    )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.vitality)
                }

                if !change.reason.isEmpty {
                    Text(change.reason)
                        .font(.caption2)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }
            }
        }
        .padding(13)
        .background(
            ATHLTHTheme.accentDeep.opacity(0.035),
            in: RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
    }

    @ViewBuilder
    private func historySection(planID: UUID) -> some View {
        let records = session.coachPlanAdaptationHistory
            .filter { $0.planAfter.id == planID }
            .prefix(3)

        if !records.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("RECENT COACH CHANGES")
                    .font(.caption2.weight(.bold))
                    .tracking(2)
                    .foregroundStyle(ATHLTHTheme.mutedText)

                ForEach(Array(records)) { record in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.proposal.headline)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)

                            Text(
                                record.appliedAt.formatted(
                                    date: .abbreviated,
                                    time: .shortened
                                )
                            )
                            .font(.caption2)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                        }

                        Spacer()

                        if record.revertedAt != nil {
                            Text("Undone")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ATHLTHTheme.mutedText)
                        } else {
                            Button("Undo") {
                                if session.revertCoachPlanAdaptation(record.id) {
                                    appliedRecordID = nil
                                    infoMessage = "The previous plan version was restored."
                                } else {
                                    errorMessage =
                                        "This change can no longer be undone because the plan has been edited since."
                                }
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }
                    .padding(13)
                    .background(
                        Color.white.opacity(0.64),
                        in: RoundedRectangle(
                            cornerRadius: 17,
                            style: .continuous
                        )
                    )
                }
            }
        }
    }

    private var noPlanCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "calendar.badge.plus")
                .font(.title2)
                .foregroundStyle(ATHLTHTheme.accentDeep)

            Text("Start a training plan first")
                .font(.headline)

            Text(
                "Coach needs an active plan before it can propose safe changes."
            )
            .font(.subheadline)
            .foregroundStyle(ATHLTHTheme.mutedText)
        }
        .padding(18)
        .background(
            Color.white.opacity(0.72),
            in: RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
        )
    }

    @MainActor
    private func generate(
        for plan: TrainingPlan
    ) async {
        isGenerating = true
        errorMessage = nil
        infoMessage = nil
        defer { isGenerating = false }

        let goals = goalStore.goals.filter {
            $0.linkedTrainingPlanID == plan.id
        }

        let resolvedGoals: [ATHLTHGoal]
        if !goals.isEmpty {
            resolvedGoals = goals
        } else if let primary = goalStore.primaryGoal {
            resolvedGoals = [primary]
        } else {
            resolvedGoals = Array(goalStore.activeGoals.prefix(3))
        }

        let requestOwner = session.profile.userID
        let request = CoachPlanAdaptationService.makeRequest(
            plan: plan,
            goals: resolvedGoals,
            recentTraining: recentTraining,
            userNotes: userNotes
        )

        do {
            let generated = try await service.generate(request: request)
            guard session.signedIn, session.profile.userID == requestOwner else { return }

            guard !generated.changes.isEmpty else {
                infoMessage =
                    "Coach reviewed your plan and did not find a useful change to suggest right now."
                return
            }

            guard session.stageCoachPlanProposal(generated) else {
                errorMessage =
                    "Your plan changed while Coach was reviewing it. Run the review again."
                return
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func apply(
        _ proposal: CoachPlanChangeProposal
    ) {
        errorMessage = nil
        infoMessage = nil

        guard session.applyCoachPlanProposal(proposal) else {
            errorMessage =
                "The plan changed after this proposal was created. Generate a fresh Coach review."
            return
        }

        appliedRecordID =
            session.coachPlanAdaptationHistory.first?.id
        infoMessage =
            "Changes applied. You can undo them below until the plan is edited again."
    }

    private func icon(
        for kind: CoachPlanChangeKind
    ) -> String {
        switch kind {
        case .moveWorkout: return "arrow.right"
        case .replaceWorkout: return "arrow.triangle.2.circlepath"
        case .adjustDuration: return "timer"
        case .adjustIntensity: return "gauge.with.dots.needle.50percent"
        case .addRecovery: return "leaf.fill"
        case .removeWorkout: return "minus.circle"
        }
    }

    private func label(
        for kind: CoachPlanChangeKind
    ) -> String {
        switch kind {
        case .moveWorkout: return "Move"
        case .replaceWorkout: return "Replace"
        case .adjustDuration: return "Duration"
        case .adjustIntensity: return "Intensity"
        case .addRecovery: return "Recovery"
        case .removeWorkout: return "Remove"
        }
    }
}

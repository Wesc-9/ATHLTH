import Foundation
import SwiftUI

/// Actual values confirmed on the live screen, never fabricated from a plan.
struct StructuredWorkoutStepResult: Codable, Hashable {
    var stepID: String
    var title: String
    var groupKind: WorkoutBlockGroupKind?
    var round: Int?
    var repetitions: Int?
    var weightKilograms: Double?
    var elapsedSeconds: TimeInterval
    var completed: Bool
}

/// Shared deterministic recipe for the structured iPhone player.
/// AMRAP is time-limited, not a fixed 20-round interval. Expanding just
/// one round at a time avoids a bogus "completed" result from unused steps.
enum ATHLTHStructuredAMRAPProgression {
    static func initialSteps(from source: [WorkoutTemplateBlock]) -> [WorkoutTemplateBlock] {
        var oneRound = source
        for index in oneRound.indices where oneRound[index].groupKind == .amrap {
            oneRound[index].groupRounds = 1
        }
        return oneRound.expandedForExecution()
    }

    static func appendingNextRound(
        to steps: [WorkoutTemplateBlock],
        after index: Int,
        startedAt: Date?,
        now: Date
    ) -> [WorkoutTemplateBlock]? {
        guard steps.indices.contains(index),
              let id = steps[index].executionGroupID,
              steps[index].executionGroupKind == .amrap,
              let startedAt,
              let limit = steps[index].executionGroupClockSeconds,
              limit.isFinite, limit > 0,
              now.timeIntervalSince(startedAt) < limit,
              index + 1 == steps.count ||
                 steps[index + 1].executionGroupID != id
        else { return nil }
        let recipe = steps.filter {
            $0.executionGroupID == id && $0.executionRound == 1
        }
        guard !recipe.isEmpty, recipe.count <= 20 else { return nil }
        let nextRound = (steps[index].executionRound ?? 1) + 1
        let copies = recipe.map { origin -> WorkoutTemplateBlock in
            var next = origin
            next.editorDragID = UUID()
            next.executionRound = nextRound
            next.executionTotalRounds = nil
            next.title = origin.title + " · \(nextRound)"
            return next
        }
        var updated = steps
        updated.insert(contentsOf: copies, at: index + 1)
        return updated.enumerated().map {
            ATHLTHWorkoutPhasePlacement.renumbered(
                $0.element, sequence: $0.offset + 1
            )
        }
    }
}

/// The recording cursor is account-scoped and survives app termination.
/// This is not a saved workout completion and is removed on finish/discard.
struct ATHLTHStructuredWorkoutCheckpoint: Codable {
    var workoutID: UUID
    /// Stable completion receipt even if history commits before a crash
    /// prevents checkpoint cleanup. Optional for old checkpoints.
    var completionID: UUID? = nil
    var savedAt: Date
    var startedAt: Date
    var stepEnteredAt: Date
    var currentIndex: Int
    var completedIDs: Set<String>
    var results: [String: StructuredWorkoutStepResult]
    var modeStarts: [UUID: Date]
    var executionBlocks: [WorkoutTemplateBlock]
    var emomWaiting: Bool
    var timedOutGroups: Set<UUID>
    var enteredReps: Int
    var enteredWeight: String
    var pausedAt: Date? = nil
    var completedPauseSeconds: TimeInterval? = nil
}

struct StructuredWorkoutCompletion: Identifiable, Codable, Hashable {
    let id: UUID
    let workoutTemplateID: UUID?
    let sourceWorkoutID: UUID
    let title: String
    let category: String?
    let startedAt: Date
    let endedAt: Date
    let completedBlockCount: Int
    let totalBlockCount: Int
    // Optional for compatibility with previously saved workout history.
    var sourcePlanID: UUID? = nil
    /// Optional so older histories continue decoding.
    var actualStepResults: [StructuredWorkoutStepResult]? = nil
    var timedOutModes: [String]? = nil
    var activeDurationSeconds: TimeInterval? = nil

    var duration: TimeInterval {
        if let activeDurationSeconds, activeDurationSeconds.isFinite,
           activeDurationSeconds >= 0 { return activeDurationSeconds }
        return max(endedAt.timeIntervalSince(startedAt), 0)
    }
}

enum StructuredWorkoutCompletionStore {
    private static let storageName =
        "structuredWorkoutHistory"

    static func load(
        userID: UUID
    ) -> [StructuredWorkoutCompletion] {
        AccountLocalStorage.read(
            [StructuredWorkoutCompletion].self,
            name: storageName,
            userID: userID
        ) ?? []
    }

    @discardableResult
    static func save(
        _ completion: StructuredWorkoutCompletion,
        userID: UUID,
        defaults: UserDefaults = .standard
    ) -> Bool {
        var history = AccountLocalStorage.read(
            [StructuredWorkoutCompletion].self, name: storageName,
            userID: userID, defaults: defaults
        ) ?? []
        // A planned session is a single completion target. Reopening its
        // recording screen must not generate a second history entry.
        // Unlinked library workouts remain repeatable.
        if let planID = completion.sourcePlanID,
           history.contains(where: {
               $0.sourcePlanID == planID &&
               $0.sourceWorkoutID == completion.sourceWorkoutID &&
               $0.totalBlockCount > 0 &&
               $0.completedBlockCount == $0.totalBlockCount
           }) {
            return true
        }
        // Crash recovery can generate a different completion receipt for
        // the SAME persisted recording. Use its immutable source ID AND
        // original start as the idempotency key, not just the receipt UUID.
        // A later, newly started unlinked library session has a new start
        // and remains repeatable even with the same template workout ID.
        if history.contains(where: {
            $0.sourceWorkoutID == completion.sourceWorkoutID &&
                $0.startedAt == completion.startedAt
        }) {
            return true
        }
        history.removeAll {
            $0.id == completion.id
        }
        history.insert(completion, at: 0)

        if history.count > 200 {
            history = Array(history.prefix(200))
        }

        do {
            try AccountLocalStorage.writeChecked(
                history, name: storageName, userID: userID,
                defaults: defaults
            )
            guard AccountLocalStorage.read(
                [StructuredWorkoutCompletion].self,
                name: storageName, userID: userID, defaults: defaults
            )?.contains(where: { $0.id == completion.id }) == true
            else { return false }
            ATHLTHTrainingDataChangeSignal.post(userID: userID)
            return true
        } catch {
            return false
        }
    }
}

struct StructuredWorkoutSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var social: SocialStore

    let workout: PlannedSession
    var linkedPlanID: UUID? = nil

    @State private var startedAt = Date()
    @State private var completionID = UUID()
    @State private var currentIndex = 0
    @State private var completedBlockIDs = Set<String>()
    @State private var showingFinishConfirmation = false
    @State private var showingDiscardConfirmation = false
    @State private var hasStarted = false
    @State private var savedCompletion = false
    @State private var results: [String: StructuredWorkoutStepResult] = [:]
    @State private var modeStarts: [UUID: Date] = [:]
    @State private var stepEnteredAt = Date()
    @State private var pausedAt: Date?
    @State private var completedPauseSeconds: TimeInterval = 0
    @State private var emomWaitingForMinute = false
    @State private var amrapTimedOutGroups: Set<UUID> = []
    @State private var enteredReps = 0
    @State private var enteredWeight = ""
    @State private var showAllSteps = false
    @State private var activeExecutionBlocks: [WorkoutTemplateBlock] = []
    @State private var restoringCheckpoint = false
    @State private var persistenceErrorMessage: String?

    private var checkpointName: String {
        "structuredWorkoutInProgress.v1.\(workout.id.uuidString)"
    }

    private var blocks: [WorkoutTemplateBlock] {
        activeExecutionBlocks.isEmpty
            ? ATHLTHStructuredAMRAPProgression.initialSteps(
                from: workout.resolvedWorkoutBlocks
            )
            : activeExecutionBlocks
    }

    private var currentBlock: WorkoutTemplateBlock? {
        guard blocks.indices.contains(currentIndex) else {
            return nil
        }
        return blocks[currentIndex]
    }

    /// The active screen follows the current block. Changing it does not
    /// end, restart or create another workout recording.
    private var currentLiveRoute: ATHLTHLiveWorkoutRoute? {
        ATHLTHLiveWorkoutEngineRouter.route(
            workoutID: workout.id,
            blocks: blocks,
            index: currentIndex
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !savedCompletion {
                        HStack(spacing: 9) {
                            ATHLTHLiveWorkoutControlButton(kind: .minimize) {
                                persistCheckpoint()
                                dismiss()
                            }
                            Spacer(minLength: 5)
                            Button {
                                toggleStructuredPause()
                            } label: {
                                Label(
                                    pausedAt == nil ? "Pause" : "Fortsett",
                                    systemImage: pausedAt == nil ? "pause.fill" : "play.fill"
                                ).font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .tint(ATHLTHTheme.accentDeep)
                            .accessibilityIdentifier("structuredWorkoutPauseToggle")
                            ATHLTHLiveWorkoutControlButton(kind: .add) {
                                showAllSteps.toggle()
                            }
                        }
                    }
                    sessionHeader
                    if ATHLTHThreeMinuteAllOut.isRunningTest(
                        title: workout.title, blocks: workout.resolvedWorkoutBlocks
                    ) {
                        ATHLTHThreeMinuteAllOutProtocol()
                    }

                    if let currentBlock {
                        if currentBlock.executionGroupKind != nil {
                            liveModeCard(currentBlock)
                        }
                        currentBlockCard(currentBlock)
                        if currentBlock.kind == .exercise && !savedCompletion {
                            actualSetInputs(currentBlock)
                        }
                    }

                    blockTimeline

                    if savedCompletion {
                        completionConfirmation
                    }
                }
                .padding(18)
                .padding(.bottom, 110)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(
                ATHLTHPremiumCanvas(
                    accent: Color.orange.opacity(0.14)
                )
            )
            .navigationTitle(workout.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .cancellationAction
                ) {
                    Button(ATHLTHLocalization.choose(
                        english: "Close", norwegian: "Lukk"
                    )) {
                        if savedCompletion {
                            dismiss()
                        } else {
                            showingDiscardConfirmation = true
                        }
                    }
                }
            }
            .confirmationDialog(
                ATHLTHLocalization.choose(
                    english: "Leave without saving?",
                    norwegian: "Forlate økten uten å lagre?"
                ),
                isPresented: $showingDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button(ATHLTHLocalization.choose(
                    english: "Discard workout", norwegian: "Forkast økten"
                ), role: .destructive) {
                    guard removeCheckpoint() else {
                        persistenceErrorMessage = ATHLTHLocalization.choose(
                            english: "Could not discard the protected workout. Try again.",
                            norwegian: "Kunne ikke forkaste den beskyttede økten. Prøv igjen."
                        )
                        return
                    }
                    ATHLTHCrossDeviceWorkoutStore.shared.endStructuredSession(
                        workoutID: workout.id
                    )
                    dismiss()
                }
                Button(ATHLTHLocalization.choose(
                    english: "Continue workout", norwegian: "Fortsett økten"
                ), role: .cancel) {}
            } message: {
                Text(ATHLTHLocalization.choose(
                    english: "Workout progress will not be saved.",
                    norwegian: "Fremdriften i økten blir ikke lagret."
                ))
            }
            .safeAreaInset(edge: .bottom) {
                bottomControls
            }
            .alert(
                ATHLTHLocalization.choose(
                    english: "Workout was not saved",
                    norwegian: "Økten ble ikke lagret"
                ),
                isPresented: Binding(
                    get: { persistenceErrorMessage != nil },
                    set: { if !$0 { persistenceErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(persistenceErrorMessage ?? "")
            }
            .sheet(isPresented: $showingFinishConfirmation) {
                ATHLTHWorkoutFinishSheet(
                    metrics: [
                        ATHLTHWorkoutFinishMetric(
                            title: ATHLTHLocalization.choose(
                                english: "Elapsed", norwegian: "Varighet"
                            ),
                            value: "\(max(0, Int(activeElapsed(at: Date()) / 60))) min",
                            symbol: "clock"
                        ),
                        ATHLTHWorkoutFinishMetric(
                            title: ATHLTHLocalization.choose(
                                english: "Completed blocks", norwegian: "Fullførte blokker"
                            ),
                            value: "\(completedBlockIDs.count) / \(blocks.count)",
                            symbol: "checkmark.circle"
                        )
                    ],
                    progress: blocks.isEmpty ? 0 :
                        Double(completedBlockIDs.count) / Double(blocks.count),
                    remainingWarning: completedBlockIDs.isEmpty
                        ? ATHLTHLocalization.choose(
                            english: amrapTimedOutGroups.isEmpty
                                ? "Complete at least one block before saving."
                                : "Time expired. You can save a zero-round effort.",
                            norwegian: amrapTimedOutGroups.isEmpty
                                ? "Fullfør minst én blokk før du lagrer."
                                : "Tiden er ute. Du kan lagre en økt med null runder."
                        )
                        : nil,
                    saveExplanation: ATHLTHLocalization.choose(
                        english: "Your recorded steps and actual results will be retained.",
                        norwegian: "Registrerte steg og faktiske resultater blir tatt vare på."
                    ),
                    saving: false,
                    onFinish: {
                        finishWorkout()
                        if savedCompletion {
                            showingFinishConfirmation = false
                        }
                    },
                    onContinue: { showingFinishConfirmation = false },
                    canFinish: !savedCompletion &&
                        (!completedBlockIDs.isEmpty || !amrapTimedOutGroups.isEmpty)
                )
            }
            .onAppear {
                guard !hasStarted else { return }
                let hadOriginalAdmission =
                    ATHLTHStructuredCaptureAdmission.activeWorkoutID ==
                        workout.id
                if hadOriginalAdmission &&
                   ATHLTHStructuredCaptureAdmission.activeCheckpoint(
                       for: session.profile.userID
                   ) == nil {
                    persistenceErrorMessage = ATHLTHLocalization.choose(
                        english: "The previous workout checkpoint is unavailable or damaged. It has not been replaced.",
                        norwegian: "Forrige øktsjekkpunkt kan ikke leses eller er skadet. Det er ikke overskrevet."
                    )
                    return
                }
                do {
                    try ATHLTHStructuredCaptureAdmission.admit(
                        workoutID: workout.id,
                        userID: session.profile.userID
                    )
                } catch {
                    persistenceErrorMessage = error.localizedDescription
                    return
                }
                if !restoreCheckpoint() {
                    guard ATHLTHStructuredRecoveryWritePolicy
                        .canCreateFreshCheckpoint(
                            alreadyAdmitted: hadOriginalAdmission,
                            restored: false
                        ) else {
                        persistenceErrorMessage = ATHLTHLocalization.choose(
                            english: "Workout recovery failed. The original checkpoint is preserved.",
                            norwegian: "Kunne ikke gjenopprette økten. Det opprinnelige sjekkpunktet er bevart."
                        )
                        return
                    }
                    activeExecutionBlocks = ATHLTHStructuredAMRAPProgression.initialSteps(
                        from: workout.resolvedWorkoutBlocks
                    )
                    startedAt = Date()
                    hasStarted = true
                    setupCurrentStep()
                    guard persistCheckpoint() else {
                        hasStarted = false
                        ATHLTHStructuredCaptureAdmission.release(
                            workoutID: workout.id, userID: session.profile.userID
                        )
                        return
                    }
                    // Preserve the real start and the original planned ID.
                    _ = session.recordPlannedWorkoutStarted(
                        workoutID: workout.id,
                        startedAt: startedAt,
                        startedOnWatch: false
                    )
                    // Invitations only confirm once the protected checkpoint exists.
                    Task { _ = await social.confirmCurrentJoinedWorkoutStarted() }
                }
                publishStructuredSpectatorStatus()
                updateScreenAwakeState()
            }
            .onDisappear {
                ATHLTHWorkoutScreenAwake.set(
                    false,
                    reason:
                        "iphone-structured-workout"
                )
            }
            .onChange(
                of: scenePhase
            ) { _, phase in
                updateScreenAwakeState()
                if phase == .active {
                    checkTimedMode(at: Date())
                }
                persistCheckpoint()
            }
            .onChange(
                of: savedCompletion
            ) { _, _ in
                updateScreenAwakeState()
            }
            .onChange(of: currentIndex) { _, _ in
                guard !restoringCheckpoint else { return }
                setupCurrentStep()
                persistCheckpoint()
            }
            .onChange(of: completedBlockIDs) { _, _ in
                persistCheckpoint()
            }
            .onChange(of: activeExecutionBlocks) { _, _ in
                persistCheckpoint()
            }
            .onChange(of: results) { _, _ in
                persistCheckpoint()
            }
            .onChange(of: modeStarts) { _, _ in
                persistCheckpoint()
            }
            .onChange(of: emomWaitingForMinute) { _, _ in
                persistCheckpoint()
            }
            .onChange(of: amrapTimedOutGroups) { _, _ in
                persistCheckpoint()
            }
            .onChange(of: enteredReps) { _, _ in
                persistCheckpoint()
            }
            .onChange(of: enteredWeight) { _, _ in
                persistCheckpoint()
            }
        }
    }

    private var sessionHeader: some View {
        ATHLTHCard {
            HStack(alignment: .top, spacing: 14) {
                Image(
                    systemName:
                        "figure.run.square.stack.fill"
                )
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 52, height: 52)
                .background(
                    Color.orange.opacity(0.10),
                    in: RoundedRectangle(
                        cornerRadius: 16,
                        style: .continuous
                    )
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        (
                            workout.workoutCategory ??
                            "Structured workout"
                        )
                        .uppercased()
                    )
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(.orange)

                    Text(workout.title)
                        .font(.title2.weight(.bold))

                    HStack(spacing: 8) {
                        Label(
                            "\(blocks.count) blocks",
                            systemImage: "list.number"
                        )

                        TimelineView(
                            .periodic(
                                from: startedAt,
                                by: 1
                            )
                        ) { context in
                            Label(
                                elapsedText(
                                    at: context.date
                                ),
                                systemImage: "timer"
                            )
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
        }
    }

    /// Focused premium mode strip: planned clock, current round/station,
    /// next action. The timer is computed from absolute dates, not tick counts,
    /// so the displayed clock remains accurate after background/resume.
    private func liveModeCard(_ block: WorkoutTemplateBlock) -> some View {
        let kind = block.executionGroupKind ?? .superset
        let index = blocks.prefix(currentIndex).filter {
            $0.executionGroupID == block.executionGroupID
        }.count
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(kind.title.uppercased(), systemImage: kind.symbol)
                    .font(.caption.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                Spacer()
                if let round = block.executionRound,
                   let total = block.executionTotalRounds, kind != .amrap {
                    Text(ATHLTHLocalization.choose(
                        english: "Round \(round)/\(total)",
                        norwegian: "Runde \(round)/\(total)"
                    ))
                    .font(.caption.weight(.semibold))
                }
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let date = context.date
                let remaining = timeRemaining(for: block, at: date, ordinal: index)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    if kind.usesGroupClock, let remaining {
                        Text(Self.clockText(remaining))
                            .font(.system(size: 43, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(ATHLTHTheme.primaryText)
                            .contentTransition(.numericText())
                    } else {
                        Text("\(index + 1)")
                            .font(.system(size: 37, weight: .bold, design: .rounded))
                            .foregroundStyle(ATHLTHTheme.primaryText)
                        Text("/")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("\(block.executionStationCount ?? 1)")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(kind == .emom
                             ? ATHLTHLocalization.choose(english: "Next minute", norwegian: "Neste minutt")
                             : kind == .amrap
                             ? ATHLTHLocalization.choose(english: "Time remaining", norwegian: "Tid igjen")
                             : ATHLTHLocalization.choose(english: "Current stage", norwegian: "Aktivt trinn"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(kind == .emom && emomWaitingForMinute
                            ? ATHLTHLocalization.choose(english: "Rest until next tick", norwegian: "Pause frem til neste minutt")
                            : block.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.primaryText)
                            .multilineTextAlignment(.trailing)
                    }
                }
                .onChange(of: date) { _, next in
                    checkTimedMode(at: next)
                }
            }
            if kind == .dropSet {
                Text(ATHLTHLocalization.choose(
                    english: "Record each weight reduction separately. No rest between drops.",
                    norwegian: "Registrer hver vektreduksjon separat. Ingen pause mellom trinnene."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if kind == .amrap {
                Text(ATHLTHLocalization.choose(
                    english: "Complete as many rounds as possible before time runs out.",
                    norwegian: "Fullfør så mange runder du rekker før tiden går ut."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if kind == .emom {
                Text(ATHLTHLocalization.choose(
                    english: "Finish the task and rest until the next minute. Unfinished slots are skipped, never counted as completed.",
                    norwegian: "Fullfør oppgaven og hvil til neste minutt. Ikke fullførte minutter telles aldri som utført."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if let next = blocks.dropFirst(currentIndex + 1).first,
               next.executionGroupID == block.executionGroupID {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.right")
                    Text(ATHLTHLocalization.choose(english: "Up next:", norwegian: "Neste:") +
                         " " + next.title)
                        .lineLimit(2)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(ATHLTHTheme.accentDeep)
            }
        }
        .padding(17)
        .background(
            Color.white.opacity(0.94),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(ATHLTHTheme.accent.opacity(0.20), lineWidth: 1)
        }
    }

    private func actualSetInputs(_ block: WorkoutTemplateBlock) -> some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(ATHLTHLocalization.choose(
                    english: "Record actual result", norwegian: "Registrer faktisk resultat"
                ), systemImage: "checkmark.square")
                .font(.headline)
                if block.durationSeconds == nil {
                    HStack {
                        Text(ATHLTHLocalization.choose(
                            english: "Repetitions", norwegian: "Repetisjoner"
                        ))
                        Spacer()
                        Stepper(value: $enteredReps, in: 0...500) {
                            Text("\(enteredReps)")
                                .monospacedDigit()
                                .font(.title3.weight(.semibold))
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                } else if let target = block.durationSeconds {
                    Label(ATHLTHLocalization.choose(
                        english: "Planned: \(Int(target)) seconds",
                        norwegian: "Planlagt: \(Int(target)) sekunder"
                    ), systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                HStack {
                    Text(ATHLTHLocalization.choose(
                        english: "Actual load (kg)", norwegian: "Faktisk belastning (kg)"
                    ))
                    Spacer()
                    TextField("kg", text: $enteredWeight)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 92)
                }
                if block.executionGroupKind == .dropSet {
                    Text(ATHLTHLocalization.choose(
                        english: "Use the weight actually lifted, not the previous stage's weight.",
                        norwegian: "Bruk vekten du faktisk løftet, ikke vekten fra forrige trinn."
                    ))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private static func clockText(_ interval: TimeInterval) -> String {
        let seconds = max(Int(ceil(interval)), 0)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func timeRemaining(
        for block: WorkoutTemplateBlock, at date: Date, ordinal: Int
    ) -> TimeInterval? {
        guard let id = block.executionGroupID,
              let started = modeStarts[id],
              let kind = block.executionGroupKind else { return nil }
        let clockDate = ATHLTHStructuredWorkoutClock.at(date, pause: pausedAt) ?? date
        let elapsed = max(clockDate.timeIntervalSince(started), 0)
        switch kind {
        case .emom:
            return max(0, (Double(ordinal + 1) *
                (block.executionGroupClockSeconds ?? 60)) - elapsed)
        case .amrap:
            return max(0, (block.executionGroupClockSeconds ?? 720) - elapsed)
        case .superset, .circuit, .dropSet, .intervals:
            return nil
        }
    }

    private func checkTimedMode(at date: Date) {
        guard !savedCompletion, pausedAt == nil, let block = currentBlock,
              let id = block.executionGroupID,
              let started = modeStarts[id],
              let kind = block.executionGroupKind else { return }
        let elapsed = max(date.timeIntervalSince(started), 0)
        if kind == .amrap {
            if elapsed >= (block.executionGroupClockSeconds ?? 720),
               amrapTimedOutGroups.insert(id).inserted {
                // A timed group may be followed by other workout sections.
                // Move past its unfinished stage without inventing completed
                // reps. An all-AMRAP workout is offered for review.
                if let next = blocks.indices.dropFirst(currentIndex + 1)
                    .first(where: { blocks[$0].executionGroupID != id }) {
                    currentIndex = next
                } else {
                    showingFinishConfirmation = true
                }
            }
        } else if kind == .emom {
            let ordinal = blocks.prefix(currentIndex).filter {
                $0.executionGroupID == id
            }.count
            let boundary = Double(ordinal + 1) *
                (block.executionGroupClockSeconds ?? 60)
            if elapsed >= boundary {
                if !emomWaitingForMinute { record(block, completed: false) }
                goToNextStep()
            }
        }
    }

    private func currentBlockCard(
        _ block: WorkoutTemplateBlock
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                if currentLiveRoute != nil {
                    Label(
                        ATHLTHWorkoutSportMode.forBlock(block).title,
                        systemImage: ATHLTHWorkoutSportMode.forBlock(block).systemImage
                    )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Label(
                        ATHLTHLocalization.choose(
                            english: "ONE WORKOUT", norwegian: "ÉN ØKT"
                        ),
                        systemImage: "link"
                    )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.65))
                }
            }
            liveTargets(for: block)
            HStack {
                Label(block.isActiveRecovery
                          ? ATHLTHLocalization.choose(
                              english: "ACTIVE RECOVERY", norwegian: "AKTIV PAUSE")
                          : block.resolvedPhase.title.uppercased(),
                      systemImage: block.isActiveRecovery ? "figure.run"
                          : block.resolvedPhase.symbol)
                    .font(.caption2.weight(.bold))
                    .tracking(1.8)
                    .foregroundStyle(
                        Color.white.opacity(0.60)
                    )

                Spacer()

                Text(
                    "\(currentIndex + 1) / \(blocks.count)"
                )
                .font(.caption.weight(.bold))
                .foregroundStyle(
                    Color.white.opacity(0.72)
                )
            }

            HStack(alignment: .center, spacing: 15) {
                Image(systemName: block.kind.systemImage)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(
                        Color.white.opacity(0.12),
                        in: RoundedRectangle(
                            cornerRadius: 18,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: 5) {
                    Text(block.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)

                    if let target = block.targetText {
                        Text(target)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(
                                Color.white.opacity(0.76)
                            )
                    }

                    if let notes = block.notes,
                       !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(
                                Color.white.opacity(0.66)
                            )
                    }
                }

                Spacer(minLength: 0)
            }

            ProgressView(
                value:
                    Double(
                        completedBlockIDs.count
                    ),
                total:
                    Double(max(blocks.count, 1))
            )
            .tint(.white)
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [
                    Color(
                        red: 0.07,
                        green: 0.08,
                        blue: 0.11
                    ),
                    Color(
                        red: 0.16,
                        green: 0.18,
                        blue: 0.24
                    )
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
        )
    }

    /// Use the same plan-only target policy for every sport. Never expose
    /// manual targets as observed GPS, power, pulse or completed repetitions.
    @ViewBuilder
    private func liveTargets(for block: WorkoutTemplateBlock) -> some View {
        let targets = ATHLTHUniversalPlannedTargetPolicy.targets(for: block)
        if !targets.isEmpty {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 120), spacing: 8)],
                alignment: .leading, spacing: 8
            ) {
                ForEach(targets, id: \.kind) { target in
                    Label(target.label, systemImage: target.systemImage)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var blockTimeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WORKOUT")
                .font(.caption2.weight(.bold))
                .tracking(1.8)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )

            ForEach(
                Array(blocks.enumerated()).filter { index, _ in
                    showAllSteps || (index >= max(0, currentIndex - 1) &&
                        index <= currentIndex + 5)
                },
                id: \.element.id
            ) { index, block in
                Button {
                    currentIndex = index
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    blockStateTint(
                                        block,
                                        index: index
                                    )
                                    .opacity(0.11)
                                )
                                .frame(width: 38, height: 38)

                            Image(
                                systemName:
                                    completedBlockIDs.contains(
                                        block.id
                                    )
                                        ? "checkmark"
                                        : block.kind.systemImage
                            )
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(
                                blockStateTint(
                                    block,
                                    index: index
                                )
                            )
                        }

                        VStack(
                            alignment: .leading,
                            spacing: 3
                        ) {
                            Label(block.resolvedPhase.title,
                                  systemImage: block.resolvedPhase.symbol)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                            Text(block.title)
                                .font(
                                    .subheadline.weight(.semibold)
                                )
                                .foregroundStyle(
                                    ATHLTHTheme.primaryText
                                )

                            if let target =
                                block.targetText {
                                Text(target)
                                    .font(.caption)
                                    .foregroundStyle(
                                        .secondary
                                    )
                            }
                        }

                        Spacer()

                        if index == currentIndex &&
                            !savedCompletion {
                            Text("NOW")
                                .font(
                                    .system(
                                        size: 8,
                                        weight: .bold
                                    )
                                )
                                .tracking(1.1)
                                .foregroundStyle(
                                    ATHLTHTheme.accentDeep
                                )
                                .padding(.horizontal, 7)
                                .frame(height: 23)
                                .background(
                                    ATHLTHTheme.accentSoft,
                                    in: Capsule()
                                )
                        }
                    }
                    .padding(13)
                    .background(
                        Color.white.opacity(
                            index == currentIndex
                                ? 0.92
                                : 0.72
                        ),
                        in: RoundedRectangle(
                            cornerRadius: 18,
                            style: .continuous
                        )
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: 18,
                            style: .continuous
                        )
                        .stroke(
                            index == currentIndex
                                ? ATHLTHTheme.accent
                                    .opacity(0.20)
                                : Color.white
                                    .opacity(0.75),
                            lineWidth: 0.8
                        )
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var recordedRepetitions: Int {
        results.values.filter(\.completed).compactMap(\.repetitions).reduce(0, +)
    }

    private var recordedVolume: Double {
        results.values.filter(\.completed).reduce(0) { total, result in
            total + Double(result.repetitions ?? 0) * (result.weightKilograms ?? 0)
        }
    }

    private var completionConfirmation: some View {
        ATHLTHCard {
            Label(
                ATHLTHLocalization.choose(
                    english: "Workout completed", norwegian: "Økt gjennomført"
                ),
                systemImage: "checkmark.circle.fill"
            )
            .font(.headline)
            .foregroundStyle(ATHLTHTheme.accentDeep)

            Text(
                ATHLTHLocalization.choose(
                    english: "This structured workout has been saved to your ATHLTH training history.",
                    norwegian: "Denne økten er lagret i treningshistorikken din i ATHLTH."
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
            Divider().padding(.vertical, 6)
            Text("\(results.values.filter(\.completed).count) " +
                 ATHLTHLocalization.choose(english: "recorded stages", norwegian: "registrerte trinn"))
                .font(.subheadline.weight(.medium))
            Text("\(recordedRepetitions) " +
                 ATHLTHLocalization.choose(english: "repetitions", norwegian: "repetisjoner") +
                 " · " + String(format: "%.0f kg", recordedVolume))
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(Array(Set(results.values.compactMap {
                $0.groupKind?.title
            })).sorted(), id: \.self) { mode in
                Label(mode, systemImage: "checkmark.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
            }
        }
    }

    /// The original structured checkpoint is still the sole state machine.
    /// The common bottom dock is a control surface, not a second recorder.
    @ViewBuilder
    private var bottomControls: some View {
        if savedCompletion {
            Button {
                dismiss()
            } label: {
                Text(ATHLTHLocalization.choose(
                    english: "Done", norwegian: "Ferdig"
                ))
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(ATHLTHTheme.accentDeep)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        } else {
            let mode = ATHLTHLiveWorkoutBottomMode.structuredActivity(
                currentBlock.map { ATHLTHWorkoutSportMode.forBlock($0) }
                    ?? .instructions,
                isFinalStep: currentIndex >= blocks.count - 1
            )
            let disabled = !hasStarted || pausedAt != nil ||
                blocks.isEmpty || emomWaitingForMinute ||
                currentBlock.flatMap { block in
                    block.executionGroupID.map {
                        amrapTimedOutGroups.contains($0)
                    }
                } == true

            ATHLTHLiveWorkoutBottomDock(
                mode: mode,
                subtitle: emomWaitingForMinute
                    ? ATHLTHLocalization.choose(
                        english: "Waiting for next minute",
                        norwegian: "Venter på neste minutt"
                    )
                    : currentBlock?.title,
                primaryDisabled: disabled,
                onPrimary: { completeCurrentAndAdvance() },
                onSecondary: { showingFinishConfirmation = true }
            ) {
                HStack {
                    Label(
                        "\(min(currentIndex + 1, blocks.count)) / \(blocks.count)",
                        systemImage: "list.number"
                    )
                    if pausedAt != nil {
                        Spacer()
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Paused", norwegian: "Pauset"
                            ),
                            systemImage: "pause.fill"
                        )
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(ATHLTHTrainDesign.secondary)
            }
        }
    }

    private func completeCurrentAndAdvance() {
        guard hasStarted, pausedAt == nil, let block = currentBlock else { return }
        if let id = block.executionGroupID,
           amrapTimedOutGroups.contains(id) { return }
        guard !emomWaitingForMinute else { return }
        record(block, completed: true)
        if block.executionGroupKind == .emom {
            // Completing a station early is an intentional rest. The next
            // station starts at the absolute minute boundary, not immediately.
            emomWaitingForMinute = true
            return
        }
        goToNextStep()
    }

    private func goToNextStep() {
        guard pausedAt == nil else { return }
        // Validate prospective AMRAP expansion BEFORE mutating the
        // persisted step array or advancing the original journal cursor.
        // Invalid or duplicated IDs cannot leave a half-applied round.
        let candidateRound: [WorkoutTemplateBlock]?
        if let block = currentBlock,
           let id = block.executionGroupID {
            candidateRound = ATHLTHStructuredAMRAPProgression.appendingNextRound(
                to: blocks,
                after: currentIndex,
                startedAt: modeStarts[id],
                now: Date()
            )
        } else {
            candidateRound = nil
        }
        let prospectiveBlocks = candidateRound ?? blocks
        if currentIndex < prospectiveBlocks.count - 1 {
            guard ATHLTHLiveWorkoutEngineRouter.advance(
                workoutID: workout.id,
                blocks: prospectiveBlocks,
                from: currentIndex
            ) != nil else {
                persistenceErrorMessage = ATHLTHLocalization.choose(
                    english: "The workout step order could not be verified. Your progress has been preserved.",
                    norwegian: "Kunne ikke kontrollere rekkefølgen på økten. Fremdriften er bevart."
                )
                return
            }
            if let candidateRound {
                activeExecutionBlocks = candidateRound
            }
            emomWaitingForMinute = false
            currentIndex += 1
        } else {
            emomWaitingForMinute = false
            showingFinishConfirmation = true
        }
    }

    private func record(_ block: WorkoutTemplateBlock, completed: Bool) {
        guard results[block.id] == nil else { return }
        let typedWeight = Double(enteredWeight.replacingOccurrences(of: ",", with: "."))
        let value = typedWeight.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let recorded = StructuredWorkoutStepResult(
            stepID: block.id,
            title: block.title,
            groupKind: block.executionGroupKind,
            round: block.executionRound,
            repetitions: completed && block.kind == .exercise && block.durationSeconds == nil
                ? max(0, enteredReps) : nil,
            weightKilograms: completed && block.kind == .exercise ? value : nil,
            elapsedSeconds: max((ATHLTHStructuredWorkoutClock.at(Date(), pause: pausedAt) ?? Date()).timeIntervalSince(stepEnteredAt), 0),
            completed: completed
        )
        results[block.id] = recorded
        if completed { completedBlockIDs.insert(block.id) }
    }

    private func setupCurrentStep() {
        guard let block = currentBlock else { return }
        stepEnteredAt = Date()
        enteredReps = max(block.repetitions ?? 0, 0)
        enteredWeight = block.targetWeightKilograms.map { String($0) } ?? ""
        emomWaitingForMinute = false
        if let id = block.executionGroupID, modeStarts[id] == nil {
            modeStarts[id] = Date()
        }
    }

    private func activeElapsed(at now: Date) -> TimeInterval {
        ATHLTHStructuredWorkoutClock.elapsed(
            start: startedAt, now: now, pause: pausedAt,
            pausedSeconds: completedPauseSeconds
        ) ?? 0
    }

    /// Stop all timed groups and the stage clock without changing the
    /// original workout ID, actual start, HealthKit owner, or history.
    private func toggleStructuredPause() {
        guard hasStarted, !savedCompletion else { return }
        let now = Date(), oldPause = pausedAt
        let oldTotal = completedPauseSeconds
        let oldStep = stepEnteredAt, oldGroups = modeStarts
        if let pausedAt {
            guard let delta = ATHLTHStructuredWorkoutClock.resumeOffset(
                from: pausedAt, at: now
            ) else { return }
            completedPauseSeconds += delta
            stepEnteredAt = stepEnteredAt.addingTimeInterval(delta)
            modeStarts = modeStarts.mapValues { $0.addingTimeInterval(delta) }
            self.pausedAt = nil
        } else {
            pausedAt = now
        }
        guard persistCheckpoint() else {
            pausedAt = oldPause
            completedPauseSeconds = oldTotal
            stepEnteredAt = oldStep
            modeStarts = oldGroups
            return
        }
        updateScreenAwakeState()
    }

    @discardableResult
    private func persistCheckpoint() -> Bool {
        guard hasStarted, !savedCompletion, !restoringCheckpoint else {
            return false
        }
        let state = ATHLTHStructuredWorkoutCheckpoint(
            workoutID: workout.id,
            completionID: completionID,
            savedAt: Date(),
            startedAt: startedAt,
            stepEnteredAt: stepEnteredAt,
            currentIndex: currentIndex,
            completedIDs: completedBlockIDs,
            results: results,
            modeStarts: modeStarts,
            executionBlocks: activeExecutionBlocks,
            emomWaiting: emomWaitingForMinute,
            timedOutGroups: amrapTimedOutGroups,
            enteredReps: enteredReps,
            enteredWeight: enteredWeight,
            pausedAt: pausedAt,
            completedPauseSeconds: completedPauseSeconds
        )
        do {
            try AccountLocalStorage.writeChecked(
                state, name: checkpointName, userID: session.profile.userID
            )
            guard AccountLocalStorage.read(
                ATHLTHStructuredWorkoutCheckpoint.self,
                name: checkpointName, userID: session.profile.userID
            )?.savedAt == state.savedAt else {
                persistenceErrorMessage = ATHLTHLocalization.choose(
                    english: "Cannot verify the workout checkpoint. Keep the workout open.",
                    norwegian: "Kunne ikke kontrollere øktlagringen. Hold økten åpen."
                )
                return false
            }
        } catch {
            persistenceErrorMessage = ATHLTHLocalization.choose(
                english: "Cannot save the current workout progress. Try again.",
                norwegian: "Kunne ikke lagre fremdriften i økten. Prøv igjen."
            )
            return false
        }
        publishStructuredSpectatorStatus()
        return true
    }

    private func publishStructuredSpectatorStatus() {
        guard ATHLTHDeviceRole.isIPhone, hasStarted, !savedCompletion
        else { return }
        // No invented health metrics: the structured recorder only knows
        // elapsed time, the actual current block and completed block count.
        let stages = blocks.enumerated().map { index, block in
            ATHLTHLiveWorkoutStage(
                index: index,
                title: block.title,
                phase: block.resolvedPhase.rawValue,
                durationSeconds: block.durationSeconds,
                distanceMeters: block.distanceMeters
            )
        }
        ATHLTHCrossDeviceWorkoutStore.shared.updateStructuredSession(
            ATHLTHLocalStructuredWorkoutStatus(
                ownerID: session.profile.userID,
                workoutID: workout.id,
                title: workout.title,
                // A mixed plan's spectator must show the actual ACTIVE
                // sport at each checkpoint, never its generic plan kind.
                kind: currentBlock.map {
                    ($0.kind == .rest || $0.isActiveRecovery)
                        ? ATHLTHWorkoutSportMode.recovery.category
                        : ATHLTHWorkoutSportMode.forBlock($0).category
                } ?? String(describing: workout.kind),
                startedAt: startedAt,
                steps: stages,
                stepIndex: currentIndex,
                stepEnteredAt: stepEnteredAt,
                completedCount: completedBlockIDs.count,
                pausedAt: pausedAt,
                completedPauseSeconds: completedPauseSeconds
            )
        )
    }

    @discardableResult
    private func restoreCheckpoint() -> Bool {
        guard let saved = AccountLocalStorage.read(
            ATHLTHStructuredWorkoutCheckpoint.self,
            name: checkpointName, userID: session.profile.userID
        ), saved.workoutID == workout.id,
           saved.savedAt > Date().addingTimeInterval(-7 * 24 * 3600),
           !saved.executionBlocks.isEmpty,
           saved.executionBlocks.indices.contains(saved.currentIndex),
           ATHLTHStructuredWorkoutClock.elapsed(
               start: saved.startedAt, now: Date(), pause: saved.pausedAt,
               pausedSeconds: saved.completedPauseSeconds ?? 0
           ) != nil
        else { return false }
        restoringCheckpoint = true
        activeExecutionBlocks = saved.executionBlocks
        completionID = saved.completionID ?? UUID()
        startedAt = saved.startedAt
        stepEnteredAt = saved.stepEnteredAt
        pausedAt = saved.pausedAt
        completedPauseSeconds = saved.completedPauseSeconds ?? 0
        currentIndex = saved.currentIndex
        completedBlockIDs = saved.completedIDs
        results = saved.results
        modeStarts = saved.modeStarts
        emomWaitingForMinute = saved.emomWaiting
        amrapTimedOutGroups = saved.timedOutGroups
        enteredReps = saved.enteredReps
        enteredWeight = saved.enteredWeight
        hasStarted = true
        Task { @MainActor in
            await Task.yield()
            restoringCheckpoint = false
            checkTimedMode(at: Date())
        }
        return true
    }

    @discardableResult
    private func removeCheckpoint() -> Bool {
        let key = AccountLocalStorage.key(
            checkpointName, userID: session.profile.userID
        )
        UserDefaults.standard.removeObject(forKey: key)
        guard UserDefaults.standard.data(forKey: key) == nil else {
            return false
        }
        ATHLTHStructuredCaptureAdmission.release(
            workoutID: workout.id, userID: session.profile.userID
        )
        return true
    }

    @MainActor
    private func updateScreenAwakeState() {
        ATHLTHWorkoutScreenAwake.set(
            !savedCompletion && pausedAt == nil &&
                scenePhase == .active,
            reason:
                "iphone-structured-workout"
        )
    }

    private func finishWorkout() {
        // Ignore repeated confirmation taps and empty sessions. A saved
        // structured completion is evidence for the linked training plan.
        guard !savedCompletion,
              !completedBlockIDs.isEmpty || !amrapTimedOutGroups.isEmpty
        else { return }
        var completion =
            StructuredWorkoutCompletion(
                id: completionID,
                workoutTemplateID:
                    workout.workoutTemplateID,
                sourceWorkoutID: workout.id,
                title: workout.title,
                category:
                    workout.workoutCategory,
                startedAt: startedAt,
                endedAt: Date(),
                completedBlockCount:
                    completedBlockIDs.count,
                totalBlockCount: blocks.count,
                sourcePlanID: linkedPlanID
            )

        completion.activeDurationSeconds = activeElapsed(at: completion.endedAt)
        completion.actualStepResults = results.values.sorted {
            $0.stepID < $1.stepID
        }
        completion.timedOutModes = Array(amrapTimedOutGroups).map { $0.uuidString }
        guard StructuredWorkoutCompletionStore.save(
            completion,
            userID: session.profile.userID
        ) else {
            persistenceErrorMessage = ATHLTHLocalization.choose(
                english: "The workout could not be saved. Its unfinished checkpoint remains available.",
                norwegian: "Økten kunne ikke lagres. Den uferdige økten er bevart for nytt forsøk."
            )
            return
        }
        _ = session.recordPlannedWorkoutFinished(
            workoutID: workout.id,
            recordedStart: completion.startedAt,
            endedAt: completion.endedAt
        )
        guard removeCheckpoint() else {
            persistenceErrorMessage = ATHLTHLocalization.choose(
                english: "The completion is saved, but the active checkpoint could not be closed. Retry to release it.",
                norwegian: "Fullføringen er lagret, men det aktive checkpointet kunne ikke avsluttes. Prøv igjen."
            )
            return
        }
        ATHLTHCrossDeviceWorkoutStore.shared.endStructuredSession(
            workoutID: workout.id
        )
        savedCompletion = true
    }

    private func elapsedText(
        at date: Date
    ) -> String {
        let seconds = max(Int(activeElapsed(at: date)), 0)

        return String(
            format: "%d:%02d:%02d",
            seconds / 3_600,
            (seconds % 3_600) / 60,
            seconds % 60
        )
    }

    private func blockStateTint(
        _ block: WorkoutTemplateBlock,
        index: Int
    ) -> Color {
        if completedBlockIDs.contains(block.id) {
            return .green
        }

        if index == currentIndex {
            return ATHLTHTheme.accentDeep
        }

        return ATHLTHTheme.mutedText
    }
}

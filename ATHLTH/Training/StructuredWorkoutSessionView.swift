import Foundation
import SwiftUI

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

    var duration: TimeInterval {
        max(endedAt.timeIntervalSince(startedAt), 0)
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

    static func save(
        _ completion: StructuredWorkoutCompletion,
        userID: UUID
    ) {
        var history = load(userID: userID)
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
            return
        }
        history.removeAll {
            $0.id == completion.id
        }
        history.insert(completion, at: 0)

        if history.count > 200 {
            history = Array(history.prefix(200))
        }

        AccountLocalStorage.write(
            history,
            name: storageName,
            userID: userID
        )
        ATHLTHTrainingDataChangeSignal.post(
            userID: userID
        )
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
    @State private var currentIndex = 0
    @State private var completedBlockIDs = Set<String>()
    @State private var showingFinishConfirmation = false
    @State private var showingDiscardConfirmation = false
    @State private var hasStarted = false
    @State private var savedCompletion = false

    private var blocks: [WorkoutTemplateBlock] {
        workout.resolvedWorkoutBlocks.expandedForExecution()
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
                    sessionHeader

                    if let currentBlock {
                        currentBlockCard(currentBlock)
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
                ), role: .destructive) { dismiss() }
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
            .confirmationDialog(
                ATHLTHLocalization.choose(
                    english: "Finish workout?", norwegian: "Avslutte økten?"
                ),
                isPresented: $showingFinishConfirmation,
                titleVisibility: .visible
            ) {
                Button(ATHLTHLocalization.choose(
                    english: "Finish workout", norwegian: "Fullfør økt"
                )) {
                    finishWorkout()
                }
                .disabled(savedCompletion || completedBlockIDs.isEmpty)

                Button(ATHLTHLocalization.choose(
                    english: "Cancel", norwegian: "Avbryt"
                ), role: .cancel) {}
            } message: {
                Text(
                    completedBlockIDs.isEmpty
                        ? ATHLTHLocalization.choose(
                            english: "Complete at least one block before saving the workout.",
                            norwegian: "Fullfør minst én blokk før økten kan lagres."
                        )
                        : completedBlockIDs.count == blocks.count
                            ? ATHLTHLocalization.choose(
                                english: "All blocks are completed.",
                                norwegian: "Alle blokkene er gjennomført."
                            )
                            : ATHLTHLocalization.choose(
                                english: "\(completedBlockIDs.count) of \(blocks.count) blocks are completed.",
                                norwegian: "\(completedBlockIDs.count) av \(blocks.count) blokker er gjennomført."
                            )
                )
            }
            .onAppear {
                if !hasStarted {
                    startedAt = Date()
                    hasStarted = true
                    // This view itself is the iPhone interval/strength
                    // recorder. A ready lobby is only marked started when
                    // its first real recording screen becomes active.
                    Task { _ = await social.confirmCurrentJoinedWorkoutStarted() }
                }
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
            ) { _, _ in
                updateScreenAwakeState()
            }
            .onChange(
                of: savedCompletion
            ) { _, _ in
                updateScreenAwakeState()
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

    private func currentBlockCard(
        _ block: WorkoutTemplateBlock
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                if let route = currentLiveRoute {
                    Label(route.engine.title, systemImage: route.engine.systemImage)
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

    /// Show only the targets relevant to the active motor. These are
    /// planned targets, never presented as measured live sensor data.
    @ViewBuilder
    private func liveTargets(for block: WorkoutTemplateBlock) -> some View {
        switch ATHLTHLiveWorkoutEngineRouter.engine(for: block) {
        case .endurance:
            HStack(spacing: 12) {
                if let seconds = block.durationSeconds, seconds > 0 {
                    Label(
                        "\(Int(seconds / 60)) min",
                        systemImage: "clock"
                    )
                }
                if let pace = block.targetPaceSecondsPerKilometer,
                   pace > 0 {
                    Label(
                        String(
                            format: "%d:%02d/km",
                            Int(pace) / 60,
                            Int(pace) % 60
                        ),
                        systemImage: "speedometer"
                    )
                }
                if let normalized = block.sourceIntensityZoneLabel {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Zone \(normalized)", norwegian: "Sone \(normalized)"
                        ),
                        systemImage: "heart"
                    )
                } else if let zone = block.targetHeartRateZone {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Zone \(zone)", norwegian: "Sone \(zone)"
                        ),
                        systemImage: "heart"
                    )
                }
                if let incline = block.treadmillInclinePercent {
                    Label(
                        String(format: "%.1f %%", incline),
                        systemImage: "mountain.2"
                    )
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.72))

        case .cycling:
            HStack(spacing: 12) {
                if let seconds = block.durationSeconds, seconds > 0 {
                    Label("\(Int(seconds / 60)) min",
                          systemImage: "clock")
                }
                if let normalized = block.sourceIntensityZoneLabel {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Zone \(normalized)", norwegian: "Sone \(normalized)"
                        ),
                        systemImage: "heart"
                    )
                } else if let zone = block.targetHeartRateZone, (1...5).contains(zone) {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Zone \(zone)",
                            norwegian: "Sone \(zone)"
                        ),
                        systemImage: "heart"
                    )
                }
                if let effort = block.targetEffortRPE, (1...10).contains(effort) {
                    Label("RPE \(effort)/10", systemImage: "gauge")
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.72))

        case .strength:
            HStack(spacing: 12) {
                if let repetitions = block.repetitions {
                    Label(
                        "\(repetitions) reps",
                        systemImage: "number"
                    )
                }
                if let weight = block.targetWeightKilograms {
                    Label(
                        String(format: "%.1f kg", weight),
                        systemImage: "scalemass"
                    )
                }
                if let seconds = block.durationSeconds {
                    Label(
                        "\(Int(seconds)) s",
                        systemImage: "timer"
                    )
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.72))

        case .recovery:
            if let seconds = block.durationSeconds {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Planned pause: \(Int(seconds)) s",
                        norwegian: "Planlagt pause: \(Int(seconds)) sek"
                    ),
                    systemImage: "pause.circle"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.72))
            }

        case .mobility, .instructions:
            EmptyView()
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
                Array(blocks.enumerated()),
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
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 10) {
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
                } else {
                    Button {
                        showingFinishConfirmation = true
                    } label: {
                        Text(ATHLTHLocalization.choose(
                            english: "Finish", norwegian: "Avslutt"
                        ))
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 88, height: 50)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        completeCurrentAndAdvance()
                    } label: {
                        Label(
                            currentIndex >= blocks.count - 1
                                ? ATHLTHLocalization.choose(
                                    english: "Complete block",
                                    norwegian: "Fullfør blokk"
                                )
                                : (currentLiveRoute?.engine.nextActionTitle ??
                                    ATHLTHLocalization.choose(
                                        english: "Complete & next",
                                        norwegian: "Fullfør og neste"
                                    )),
                            systemImage:
                                "checkmark.circle.fill"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accentDeep)
                    .disabled(blocks.isEmpty)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .background(.ultraThinMaterial)
    }

    private func completeCurrentAndAdvance() {
        guard let currentBlock else {
            return
        }

        completedBlockIDs.insert(
            currentBlock.id
        )

        if currentIndex < blocks.count - 1 {
            currentIndex += 1
        } else {
            showingFinishConfirmation = true
        }
    }

    @MainActor
    private func updateScreenAwakeState() {
        ATHLTHWorkoutScreenAwake.set(
            !savedCompletion &&
                scenePhase == .active,
            reason:
                "iphone-structured-workout"
        )
    }

    private func finishWorkout() {
        // Ignore repeated confirmation taps and empty sessions. A saved
        // structured completion is evidence for the linked training plan.
        guard !savedCompletion, !completedBlockIDs.isEmpty else { return }
        let completion =
            StructuredWorkoutCompletion(
                id: UUID(),
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

        StructuredWorkoutCompletionStore.save(
            completion,
            userID: session.profile.userID
        )
        savedCompletion = true
    }

    private func elapsedText(
        at date: Date
    ) -> String {
        let seconds = max(
            Int(
                date.timeIntervalSince(
                    startedAt
                )
            ),
            0
        )

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

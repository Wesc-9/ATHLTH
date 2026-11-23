import SwiftUI

/// One shared preview for every ATHLTH workout source. The selection screen
/// reads the real, executable timeline without mutating sets, targets or rest.
struct ATHLTHWorkoutContentsPreview: View {
    let workout: PlannedSession?
    let catalogBlocks: [WorkoutTemplateBlock]?
    var maximumVisibleBlocks: Int? = 3

    init(workout: PlannedSession, maximumVisibleBlocks: Int? = 3) {
        self.workout = workout
        self.catalogBlocks = nil
        self.maximumVisibleBlocks = maximumVisibleBlocks
    }

    init(blocks: [WorkoutTemplateBlock], maximumVisibleBlocks: Int? = 3) {
        self.workout = nil
        self.catalogBlocks = blocks
        self.maximumVisibleBlocks = maximumVisibleBlocks
    }

    private var blocks: [WorkoutTemplateBlock] {
        if let catalogBlocks { return catalogBlocks }
        if let workout { return ATHLTHUnifiedWorkout.editorBlocks(from: workout) }
        return []
    }

    var body: some View {
        let resolved = blocks
        Group {
            if maximumVisibleBlocks == nil {
                completeOutline(resolved)
            } else {
                compactOutline(
                    resolved,
                    maximumVisible: maximumVisibleBlocks ?? 3
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Keep the compact list used across Library and Plan lightweight. Only
    /// the full inspection sheet expands/group-compacts the executable sets.
    private func compactOutline(
        _ blocks: [WorkoutTemplateBlock],
        maximumVisible: Int
    ) -> some View {
        let visible = Array(blocks.prefix(max(0, maximumVisible)))
        return VStack(alignment: .leading, spacing: 9) {
            sectionHeading(remaining: blocks.count)
            if visible.isEmpty {
                emptyState
            } else {
                ForEach(visible.indices, id: \.self) { index in
                    let block = visible[index]
                    HStack(alignment: .top, spacing: block.isRestOrActiveRecovery ? 7 : 9) {
                        Image(systemName: block.isRestOrActiveRecovery
                              ? "pause.fill" : block.kind.systemImage)
                            .font(.system(
                                size: block.isRestOrActiveRecovery ? 11 : 13,
                                weight: .semibold
                            ))
                            .frame(
                                width: block.isRestOrActiveRecovery ? 19 : 22,
                                height: block.isRestOrActiveRecovery ? 19 : 22
                            )
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                            .background(ATHLTHTheme.accentSoft, in: Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            Text(block.kind == .rest
                                ? ATHLTHLocalization.choose(
                                    english: "Pause", norwegian: "Pause"
                                  )
                                : block.title)
                                .font(.system(
                                    size: block.isRestOrActiveRecovery ? 12 : 14,
                                    weight: .medium
                                ))
                                .foregroundStyle(ATHLTHPlanDesign.ink)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(compactSubtitle(block))
                                .font(.system(
                                    size: block.isRestOrActiveRecovery ? 10 : 11
                                ))
                                .foregroundStyle(ATHLTHTheme.mutedText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if blocks.count > visible.count {
                    Text(ATHLTHLocalization.choose(
                        english: "+ \(blocks.count - visible.count) more steps",
                        norwegian: "+ \(blocks.count - visible.count) øktdeler"
                    ))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                }
            }
        }
    }

    private func compactSubtitle(_ block: WorkoutTemplateBlock) -> String {
        if block.kind == .rest {
            // Keep pause as the main heading, followed by its purpose/time.
            return ATHLTHWorkoutSelectionOverview.Row(
                id: 0, steps: [block]
            ).subtitle
        }
        return [block.resolvedPhase.title, block.targetText]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func completeOutline(_ blocks: [WorkoutTemplateBlock]) -> some View {
        let rows = ATHLTHWorkoutSelectionOverview.rows(for: blocks)
        let stats = ATHLTHWorkoutSelectionOverview.metrics(for: blocks)
        return VStack(alignment: .leading, spacing: 12) {
            sectionHeading(remaining: nil)
            if rows.isEmpty {
                emptyState
            } else {
                HStack {
                    if stats.exerciseCount > 0 {
                        Text(ATHLTHLocalization.choose(
                            english: "\(stats.exerciseCount) exercises · \(stats.setCount) sets · \(stats.pauseCount) pauses",
                            norwegian: "\(stats.exerciseCount) øvelser · \(stats.setCount) sett · \(stats.pauseCount) pauser"
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                    } else {
                        Text(ATHLTHLocalization.choose(
                            english: "\(max(0, stats.executedStepCount - stats.pauseCount)) work steps · \(stats.pauseCount) pauses",
                            norwegian: "\(max(0, stats.executedStepCount - stats.pauseCount)) øktdeler · \(stats.pauseCount) pauser"
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                    }
                    Spacer(minLength: 0)
                }

                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        expandedRow(row)
                        if row.id != rows.last?.id {
                            Divider()
                                .overlay(ATHLTHPlanDesign.outline.opacity(0.35))
                                .padding(.vertical, row.isPause ? 5 : 8)
                        }
                    }
                }

                Label(
                    ATHLTHLocalization.choose(
                        english: "Only saved rests are shown. A between-set rest is not added after the final set.",
                        norwegian: "Bare lagrede pauser vises. Det legges ikke til settpause etter siste sett."
                    ),
                    systemImage: "info.circle"
                )
                .font(.caption2)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private func expandedRow(_ row: ATHLTHWorkoutSelectionOverview.Row) -> some View {
        if row.isPause {
            pauseRow(row)
        } else if row.isExercise && row.sets > 1 {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(row.steps.indices, id: \.self) { index in
                        let step = row.steps[index]
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Image(systemName: step.kind == .rest
                                  ? "pause.fill" : "circle.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(ATHLTHTrainDesign.bronze)
                                .frame(width: 14)
                            Text(step.kind == .rest
                                ? ATHLTHLocalization.choose(
                                    english: "Pause", norwegian: "Pause"
                                  )
                                : ATHLTHLocalization.choose(
                                    english: "Set", norwegian: "Sett"
                                  ) + " \(row.steps[0...index].filter { $0.kind == .exercise }.count)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ATHLTHPlanDesign.ink)
                            Spacer(minLength: 5)
                            Text(rowStepDetail(step))
                                .font(.caption)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                .padding(.leading, 30)
                .padding(.top, 11)
            } label: {
                rowHeader(row)
            }
            .tint(ATHLTHTrainDesign.bronze)
            .accessibilityIdentifier("athlth-workout-preview-exercise-group")
        } else {
            rowHeader(row)
        }
    }

    /// Rest and active recovery carry less visual weight than exercises.
    /// This only affects presentation, not time targets or execution.
    private func pauseRow(
        _ row: ATHLTHWorkoutSelectionOverview.Row
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: row.first.isActiveRecovery
                  ? "figure.walk" : "pause.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(ATHLTHTrainDesign.bronze)
                .frame(width: 23, height: 23)
                .background(
                    ATHLTHPlanDesign.selectedSurface.opacity(0.65),
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                Text(row.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .padding(.leading, 7)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("athlth-workout-preview-compact-pause")
    }

    private func rowStepDetail(_ step: WorkoutTemplateBlock) -> String {
        if step.kind == .rest {
            return ATHLTHWorkoutSelectionOverview.Row(
                id: 0, steps: [step]
            ).subtitle
        }
        return step.targetText ?? "–"
    }

    private func rowHeader(_ row: ATHLTHWorkoutSelectionOverview.Row) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: row.isPause
                  ? "pause.fill" : row.first.kind.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ATHLTHTrainDesign.bronze)
                .frame(width: 30, height: 30)
                .background(ATHLTHPlanDesign.selectedSurface, in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(row.title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Text(row.subtitle)
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                if row.betweenSetPauses > 0 {
                    Text(ATHLTHLocalization.choose(
                        english: "\(row.betweenSetPauses) between-set pauses",
                        norwegian: "\(row.betweenSetPauses) pauser mellom sett"
                    ) + (row.betweenSetRestSeconds.map {
                        " · " + ATHLTHWorkoutDurationEstimator.conciseDuration($0)
                    } ?? ""))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if row.isExercise {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(ATHLTHLocalization.choose(
                        english: "\(row.sets) sets",
                        norwegian: "\(row.sets) sett"
                    ))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                    if let duration = row.estimatedSeconds {
                        Text("~" + ATHLTHWorkoutDurationEstimator
                            .conciseDuration(duration))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(ATHLTHTrainDesign.bronze)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            } else if !row.isPause, let duration = row.estimatedSeconds {
                Text("~" + ATHLTHWorkoutDurationEstimator.conciseDuration(duration))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
            }
        }
    }

    private func sectionHeading(remaining: Int?) -> some View {
        HStack(spacing: 6) {
            Text(ATHLTHLocalization.choose(
                english: "EXERCISES & STEPS", norwegian: "ØVELSER OG ØKTDELER"
            ))
            .font(.system(size: 10, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(ATHLTHTheme.mutedText)
            Spacer(minLength: 0)
            if let remaining, remaining > 0 {
                Text(ATHLTHLocalization.choose(
                    english: "\(remaining) steps",
                    norwegian: "\(remaining) øktdeler"
                ))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(ATHLTHTheme.mutedText)
            }
        }
    }

    private var emptyState: some View {
        Text(ATHLTHLocalization.choose(
            english: "No detailed steps are saved for this workout. You can add them in the workout builder.",
            norwegian: "Denne økten har ingen lagrede deløkter. Du kan legge dem til i øktbyggeren."
        ))
        .font(.caption)
        .foregroundStyle(ATHLTHTheme.mutedText)
    }
}

/// Inspect an existing workout BEFORE copying it into the user's calendar.
/// The original workout is never altered when the athlete taps Use.
struct ATHLTHWorkoutSelectionPreviewSheet: View {
    let workout: PlannedSession
    let onUse: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var blocks: [WorkoutTemplateBlock] {
        ATHLTHUnifiedWorkout.editorBlocks(from: workout)
    }

    private func summary(for blocks: [WorkoutTemplateBlock])
        -> ATHLTHWorkoutSelectionOverview.Metrics {
        ATHLTHWorkoutSelectionOverview.metrics(
            for: blocks,
            defaultActivity: workout.kind == .walking ? .walking : .running
        )
    }

    private func durationLabel(_ seconds: TimeInterval?) -> String {
        seconds.map {
            "~" + ATHLTHWorkoutDurationEstimator.conciseDuration($0)
        } ?? "–"
    }

    private func headlineDuration(
        for summary: ATHLTHWorkoutSelectionOverview.Metrics
    ) -> String {
        if let estimated = summary.totalSeconds {
            return durationLabel(estimated)
        }
        if let planned = workout.durationMinutes, planned > 0 {
            return "\(planned) min"
        }
        return "–"
    }

    var body: some View {
        let source = blocks
        let stats = summary(for: source)
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    workoutOverview(stats)
                    ATHLTHWorkoutContentsPreview(
                        blocks: source,
                        maximumVisibleBlocks: nil
                    )
                    .padding(17)
                    .background(
                        ATHLTHPlanDesign.surface,
                        in: RoundedRectangle(cornerRadius: 22)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 22)
                            .strokeBorder(ATHLTHPlanDesign.outline, lineWidth: 0.7)
                    }
                    Text(ATHLTHLocalization.choose(
                        english: "You can edit exercises, intervals, pace targets and rests in the workout builder. Using this workout does not overwrite the original.",
                        norwegian: "Øvelser, intervaller, målfart og pauser kan tilpasses i øktbyggeren. Originaløkten endres ikke."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .padding(.horizontal, 3)
                }
                .padding(16)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(ATHLTHLocalization.choose(
                english: "Workout contents", norwegian: "Øktinnhold"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button(action: onUse) {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Use this workout", norwegian: "Bruk denne økten"
                        ),
                        systemImage: "checkmark"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.accentDeep)
                .padding(16)
                .background(.regularMaterial)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Back", norwegian: "Tilbake"
                    )) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func workoutOverview(
        _ summary: ATHLTHWorkoutSelectionOverview.Metrics
    ) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: workout.kind.systemImage)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                    .frame(width: 54, height: 54)
                    .background(ATHLTHPlanDesign.selectedSurface,
                                in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 5) {
                    Text(ATHLTHLocalization.choose(
                        english: "WORKOUT DETAILS", norwegian: "ØKTDETALJER"
                    ))
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                    Text(workout.title)
                        .font(.system(size: 25, weight: .semibold, design: .serif))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(workout.kind.title)
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }
                Spacer(minLength: 0)
            }

            if let notes = workout.notes?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ), !notes.isEmpty {
                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().overlay(ATHLTHPlanDesign.outline.opacity(0.35))

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                spacing: 8
            ) {
                metricTile(
                    ATHLTHLocalization.choose(
                        english: "Duration", norwegian: "Varighet"
                    ),
                    headlineDuration(for: summary), icon: "clock"
                )
                metricTile(
                    summary.exerciseCount > 0
                        ? ATHLTHLocalization.choose(
                            english: "Exercises", norwegian: "Øvelser"
                        )
                        : ATHLTHLocalization.choose(
                            english: "Active steps", norwegian: "Øktdeler"
                        ),
                    String(summary.exerciseCount > 0
                        ? summary.exerciseCount
                        : max(0, summary.executedStepCount - summary.pauseCount)),
                    icon: "figure.strengthtraining.traditional"
                )
                metricTile(
                    summary.setCount > 0
                        ? ATHLTHLocalization.choose(
                            english: "Sets", norwegian: "Sett"
                        )
                        : ATHLTHLocalization.choose(
                            english: "Work steps", norwegian: "Arbeidsdeler"
                        ),
                    String(summary.setCount > 0
                        ? summary.setCount
                        : max(0, summary.executedStepCount - summary.pauseCount)),
                    icon: "square.stack"
                )
                metricTile(
                    ATHLTHLocalization.choose(
                        english: "Pauses", norwegian: "Pauser"
                    ),
                    "\(summary.pauseCount)", icon: "pause.circle"
                )
                metricTile(
                    ATHLTHLocalization.choose(
                        english: "Rest time", norwegian: "Hviletid"
                    ),
                    durationLabel(summary.restSeconds),
                    icon: "hourglass"
                )
                metricTile(
                    ATHLTHLocalization.choose(
                        english: "Active time", norwegian: "Aktiv tid"
                    ),
                    durationLabel(summary.activeSeconds),
                    icon: "bolt"
                )
            }

            if !summary.primaryMuscles.isEmpty {
                overviewDetail(
                    ATHLTHLocalization.choose(
                        english: "Muscle focus", norwegian: "Muskelfokus"
                    ),
                    items: summary.primaryMuscles.map {
                        ExerciseMuscleGroup(rawValue: $0)?.title ?? $0
                    },
                    icon: "figure.strengthtraining.traditional"
                )
            }
            if !summary.equipment.isEmpty {
                overviewDetail(
                    ATHLTHLocalization.choose(
                        english: "Equipment", norwegian: "Utstyr"
                    ),
                    items: summary.equipment,
                    icon: "dumbbell"
                )
            }

            Text(summary.totalSeconds != nil
                ? ATHLTHLocalization.choose(
                    english: "Duration is a planning estimate based on the saved sets, targets and pauses.",
                    norwegian: "Tiden er et planestimat basert på lagrede sett, mål og pauser."
                )
                : ATHLTHLocalization.choose(
                    english: "Some steps have no time target. Shown duration, if any, comes from the workout plan.",
                    norwegian: "Noen øktdeler mangler tidsmål. Eventuell varighet er hentet fra øktplanen."
                ))
            .font(.caption2)
            .foregroundStyle(ATHLTHTheme.mutedText)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(17)
        .background(
            ATHLTHPlanDesign.surface,
            in: RoundedRectangle(cornerRadius: 22)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(ATHLTHPlanDesign.outline, lineWidth: 0.7)
        }
        .accessibilityIdentifier("athlth-workout-selection-overview")
    }

    private func metricTile(_ label: String, _ value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(label, systemImage: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ATHLTHTheme.mutedText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(ATHLTHPlanDesign.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, minHeight: 67, alignment: .leading)
        .padding(10)
        .background(
            ATHLTHPlanDesign.selectedSurface.opacity(0.52),
            in: RoundedRectangle(cornerRadius: 13)
        )
    }

    private func overviewDetail(
        _ label: String,
        items: [String],
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(label, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHTrainDesign.bronze)
            Text(items.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(ATHLTHPlanDesign.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

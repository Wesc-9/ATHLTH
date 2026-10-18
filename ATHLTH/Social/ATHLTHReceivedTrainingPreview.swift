import SwiftUI

/// Review a received item without importing it into the athlete's library.
/// Shared exercise details use the existing library card and its private-copy
/// action, while plan/workout previews never activate a session.
struct ATHLTHReceivedTrainingPreview: View {
    @Environment(\.dismiss) private var dismiss
    let message: DirectMessageRecord
    let onSave: () -> Void

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        Group {
            if message.attachmentKind == .exercise,
               let exercise = message.decodeSnapshot(ATHLTHSharedExerciseAttachment.self) {
                ATHLTHLinkedExerciseDetailView(block: exercise.previewBlock)
            } else {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 15) {
                            switch message.attachmentKind {
                            case .workout:
                                if let workout = message.decodeSnapshot(PlannedSession.self) {
                                    sessionPreview(workout)
                                } else {
                                    unavailable
                                }
                            case .trainingPlan:
                                if let plan = message.decodeSnapshot(TrainingPlan.self) {
                                    planPreview(plan)
                                } else {
                                    unavailable
                                }
                            case .runningWorkout:
                                if let workout = message.decodeSnapshot(RunningWorkoutTemplate.self) {
                                    Text(workout.title)
                                        .font(.title2.weight(.semibold))
                                    Text(workout.summary)
                                        .font(.subheadline)
                                    Text("\(workout.blocks.count) " +
                                         tr("training blocks", "treningsblokker"))
                                        .foregroundStyle(.secondary)
                                } else {
                                    unavailable
                                }
                            default:
                                unavailable
                            }
                        }
                        .padding(18)
                        .frame(maxWidth: 680)
                        .frame(maxWidth: .infinity)
                    }
                    .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
                    .navigationTitle(tr("Shared training", "Delt trening"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(tr("Close", "Lukk")) { dismiss() }
                        }
                    }
                    .safeAreaInset(edge: .bottom) {
                        if [.workout, .trainingPlan, .runningWorkout].contains(
                            message.attachmentKind
                        ) {
                            Button {
                                onSave()
                                dismiss()
                            } label: {
                                Label(tr("Save a private copy", "Lagre privat kopi"),
                                      systemImage: "square.and.arrow.down")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, minHeight: 51)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(ATHLTHTheme.accentDeep)
                            .padding(14)
                            .background(.regularMaterial)
                        }
                    }
                }
            }
        }
    }

    private var unavailable: some View {
        ContentUnavailableView(
            tr("Preview unavailable", "Forhåndsvisning utilgjengelig"),
            systemImage: "exclamationmark.circle",
            description: Text(tr(
                "The shared item could not be read. Nothing has been saved.",
                "Det delte innholdet kunne ikke leses. Ingenting er lagret."
            ))
        )
    }

    private func sessionPreview(_ workout: PlannedSession) -> some View {
        ATHLTHWorkoutRecipePreview(
            title: workout.title,
            summary: workout.notes ?? "",
            category: workout.workoutCategory ??
                (workout.kind == .strength ? "strength" :
                 workout.kind == .running ? "running" : "hybrid"),
            symbol: workout.kind.systemImage,
            difficulty: nil,
            durationMinutes: workout.durationMinutes,
            blocks: ATHLTHUnifiedWorkout.editorBlocks(from: workout)
        )
    }

    private func planPreview(_ plan: TrainingPlan) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(plan.title)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
            Label("\(plan.weeks.count) " + tr("weeks", "uker"),
                  systemImage: "calendar")
                .font(.subheadline)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            Text(tr(
                "Review the sessions before saving. This will not activate or replace your current training plan.",
                "Se gjennom øktene før du lagrer. Planen aktiveres ikke og erstatter ikke din nåværende treningsplan."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

            ForEach(Array(plan.weeks.enumerated()), id: \.offset) { index, week in
                VStack(alignment: .leading, spacing: 10) {
                    Text(tr("Week ", "Uke ") + "\(index + 1)")
                        .font(.headline)
                    ForEach(Array(week.days.enumerated()), id: \.offset) { dayIndex, day in
                        ForEach(day.sessions) { workout in
                            NavigationLink {
                                ScrollView {
                                    sessionPreview(workout)
                                        .padding(18)
                                }
                                .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
                                .navigationTitle(workout.title)
                                .navigationBarTitleDisplayMode(.inline)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: workout.kind.systemImage)
                                        .foregroundStyle(ATHLTHTheme.accentDeep)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(workout.title)
                                            .font(.subheadline.weight(.semibold))
                                        Text(tr("Day ", "Dag ") + "\(dayIndex + 1)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .background(ATHLTHPlanDesign.selectedSurface,
                                            in: RoundedRectangle(cornerRadius: 13))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(15)
                .background(.white, in: RoundedRectangle(cornerRadius: 20))
            }
        }
    }
}

import SwiftUI

struct PlannedWorkoutDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore

    let planID: UUID
    let workout: PlannedSession
    let isHealthCompleted: Bool

    private var isManuallyCompleted: Bool {
        session.isPlanSessionManuallyCompleted(
            planID: planID,
            sessionID: workout.id
        )
    }

    private var isCompleted: Bool {
        isHealthCompleted || isManuallyCompleted
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    overviewCard

                    if !workout.exercises.isEmpty {
                        strengthCard
                    }

                    if let runningWorkout = workout.runningWorkout {
                        runningCard(runningWorkout)
                    }

                    if let notes = cleanNotes {
                        notesCard(notes)
                    }

                    completionCard
                }
                .padding(20)
                .padding(.bottom, 28)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .background(
                LinearGradient(
                    colors: [
                        ATHLTHTheme.canvasTop,
                        ATHLTHTheme.canvasBottom
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        ATHLTHCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: workout.kind.systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accent)
                    .frame(width: 52, height: 52)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: RoundedRectangle(cornerRadius: 16)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(workout.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(ATHLTHTheme.primaryText)

                    HStack(spacing: 7) {
                        Text(workout.kind.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.mutedText)

                        Circle()
                            .fill(ATHLTHTheme.mutedText.opacity(0.55))
                            .frame(width: 3, height: 3)

                        Label(
                            isCompleted ? "Completed" : "Planned",
                            systemImage: isCompleted
                                ? "checkmark.circle.fill"
                                : "calendar"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(
                            isCompleted
                                ? ATHLTHTheme.accent
                                : ATHLTHTheme.mutedText
                        )
                    }
                }

                Spacer()
            }
        }
    }

    private var overviewCard: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Plan details")

                if let scheduledStart = workout.scheduledStart {
                    detailRow(
                        icon: "clock",
                        title: "Scheduled",
                        value: scheduledStart.formatted(
                            date: .omitted,
                            time: .shortened
                        )
                    )
                }

                if let duration = workout.durationMinutes {
                    detailRow(
                        icon: "timer",
                        title: "Duration",
                        value: "\(duration) min"
                    )
                }

                if let distance = workout.targetDistanceKilometers {
                    detailRow(
                        icon: "point.topleft.down.to.point.bottomright.curvepath",
                        title: "Distance",
                        value: String(format: "%.1f km", distance)
                    )
                }

                if let pace = workout.targetPaceSecondsPerKilometer {
                    detailRow(
                        icon: "speedometer",
                        title: "Target pace",
                        value: paceText(pace)
                    )
                }

                if let routeID = workout.routeID,
                   let route = session.savedRoutes.first(where: { $0.id == routeID }) {
                    detailRow(
                        icon: "map",
                        title: "Route",
                        value: route.title
                    )
                }

                if workout.scheduledStart == nil &&
                    workout.durationMinutes == nil &&
                    workout.targetDistanceKilometers == nil &&
                    workout.targetPaceSecondsPerKilometer == nil &&
                    workout.routeID == nil {
                    Text("No additional targets are set for this workout.")
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }
            }
        }
    }

    private var strengthCard: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 13) {
                sectionTitle("Exercises")

                ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { index, exercise in
                    HStack(alignment: .top, spacing: 11) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(ATHLTHTheme.accent)
                            .frame(width: 28, height: 28)
                            .background(
                                ATHLTHTheme.accentSoft,
                                in: Circle()
                            )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(exercise.embeddedExercise.name)
                                .font(.subheadline.weight(.semibold))

                            Text(exerciseSummary(exercise))
                                .font(.caption)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                        }

                        Spacer()
                    }

                    if index < workout.exercises.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private func runningCard(
        _ runningWorkout: RunningWorkoutTemplate
    ) -> some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Running workout")

                HStack(spacing: 11) {
                    Image(systemName: runningWorkout.type.systemImage)
                        .font(.title3)
                        .foregroundStyle(ATHLTHTheme.accent)
                        .frame(width: 38, height: 38)
                        .background(
                            ATHLTHTheme.accentSoft,
                            in: RoundedRectangle(cornerRadius: 12)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(runningWorkout.title)
                            .font(.subheadline.weight(.semibold))

                        Text(
                            "\(runningWorkout.type.title) · \(runningWorkout.blocks.count) blocks"
                        )
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    }

                    Spacer()
                }

                if !runningWorkout.summary.isEmpty {
                    Text(runningWorkout.summary)
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func notesCard(_ notes: String) -> some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 9) {
                sectionTitle("Notes")

                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var completionCard: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Completion")

                if isHealthCompleted {
                    HStack(spacing: 12) {
                        Image(systemName: "heart.circle.fill")
                            .font(.title2)
                            .foregroundStyle(ATHLTHTheme.accent)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Completed")
                                .font(.headline)

                            Text("Matched automatically from Apple Health.")
                                .font(.caption)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                        }

                        Spacer()

                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(ATHLTHTheme.accent)
                    }
                } else {
                    Button {
                        session.setPlanSessionManuallyCompleted(
                            planID: planID,
                            sessionID: workout.id,
                            completed: !isManuallyCompleted
                        )
                    } label: {
                        HStack(spacing: 10) {
                            Image(
                                systemName: isManuallyCompleted
                                    ? "arrow.uturn.backward.circle.fill"
                                    : "checkmark.circle.fill"
                            )
                            .font(.title3)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(
                                    isManuallyCompleted
                                        ? "Mark as Not Completed"
                                        : "Mark as Completed"
                                )
                                .font(.headline)

                                Text(
                                    isManuallyCompleted
                                        ? "Remove the manual completion."
                                        : "Set this planned workout as performed."
                                )
                                .font(.caption)
                                .opacity(0.78)
                            }

                            Spacer()
                        }
                        .foregroundStyle(
                            isManuallyCompleted
                                ? ATHLTHTheme.accentDeep
                                : Color.white
                        )
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .background(
                            isManuallyCompleted
                                ? ATHLTHTheme.accentSoft
                                : ATHLTHTheme.accent,
                            in: RoundedRectangle(cornerRadius: 18)
                        )
                    }
                    .buttonStyle(.plain)

                    Text(
                        "Manual completion updates your ATHLTH plan only. It does not create an Apple Health workout."
                    )
                    .font(.caption2)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var cleanNotes: String? {
        guard let notes = workout.notes?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !notes.isEmpty
        else {
            return nil
        }

        return notes
    }

    @ViewBuilder
    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(1.1)
            .foregroundStyle(ATHLTHTheme.mutedText)
    }

    @ViewBuilder
    private func detailRow(
        icon: String,
        title: String,
        value: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.accent)
                .frame(width: 34, height: 34)
                .background(
                    ATHLTHTheme.accentSoft,
                    in: RoundedRectangle(cornerRadius: 11)
                )

            Text(title)
                .font(.subheadline)
                .foregroundStyle(ATHLTHTheme.mutedText)

            Spacer()

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.primaryText)
                .multilineTextAlignment(.trailing)
        }
    }

    private func exerciseSummary(
        _ exercise: PlannedExercise
    ) -> String {
        var parts: [String] = []

        if let reps = exercise.reps {
            parts.append("\(exercise.sets) × \(reps)")
        } else {
            parts.append("\(exercise.sets) sets")
        }

        if let weight = exercise.targetWeightKilograms {
            parts.append(String(format: "%.1f kg", weight))
        }

        if let rest = exercise.restSeconds {
            parts.append("\(rest)s rest")
        }

        return parts.joined(separator: " · ")
    }

    private func paceText(_ secondsPerKilometer: Double) -> String {
        let totalSeconds = max(Int(secondsPerKilometer.rounded()), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d /km", minutes, seconds)
    }
}

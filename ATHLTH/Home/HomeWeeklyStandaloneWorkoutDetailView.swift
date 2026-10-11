import SwiftUI

/// Calendar-only sessions are not members of a training plan, so they must
/// not be opened with a fabricated plan ID. Keep their details editable
/// without changing the workout's UUID or creating a duplicate entry.
struct HomeWeeklyStandaloneWorkoutDetailView: View {
    @EnvironmentObject private var session: AppSessionStore

    let workout: PlannedSession
    @State private var showingEditor = false
    @State private var showingInvitationLobby = false

    private var currentWorkout: PlannedSession {
        session.standalonePlannedSessions.first {
            $0.id == workout.id
        } ?? workout
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                ATHLTHCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Planned workout",
                                norwegian: "Planlagt økt"
                            ),
                            systemImage: "calendar"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.mutedText)

                        Text(currentWorkout.title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(ATHLTHTheme.primaryText)

                        Label(
                            currentWorkout.kind.title,
                            systemImage: currentWorkout.kind.systemImage
                        )
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHTheme.accentDeep)

                        if let start = currentWorkout.scheduledStart {
                            Label(
                                start.formatted(
                                    .dateTime.weekday(.wide).day().month(.wide)
                                        .hour().minute()
                                ),
                                systemImage: "clock"
                            )
                            .font(.subheadline)
                        }

                        if let duration = currentWorkout.durationMinutes {
                            Label(
                                "\(duration) min",
                                systemImage: "timer"
                            )
                            .font(.subheadline)
                        }

                        if let distance = currentWorkout.targetDistanceKilometers {
                            Label(
                                String(format: "%.1f km", distance),
                                systemImage: "figure.run"
                            )
                            .font(.subheadline)
                        }

                        if let notes = currentWorkout.notes,
                           !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(notes)
                                .font(.subheadline)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !currentWorkout.exercises.isEmpty {
                    ATHLTHCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(
                                ATHLTHLocalization.choose(
                                    english: "Exercises",
                                    norwegian: "Øvelser"
                                )
                            )
                            .font(.headline)

                            ForEach(
                                Array(currentWorkout.exercises.enumerated()),
                                id: \.element.id
                            ) { index, exercise in
                                HStack(spacing: 10) {
                                    Text("\(index + 1).")
                                        .foregroundStyle(ATHLTHTheme.mutedText)
                                    Text(exercise.embeddedExercise.displayName)
                                        .font(.subheadline.weight(.medium))
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if currentWorkout.trainTogetherMode != nil {
                    Button {
                        showingInvitationLobby = true
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Open Train Together lobby",
                                norwegian: "Åpne Tren sammen-lobby"
                            ),
                            systemImage: "person.2"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    showingEditor = true
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Edit workout",
                            norwegian: "Rediger økt"
                        ),
                        systemImage: "square.and.pencil"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.accentDeep)
            }
            .padding(16)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(
            ATHLTHLocalization.choose(
                english: "Workout details",
                norwegian: "Øktdetaljer"
            )
        )
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEditor) {
            SessionEditorView(
                standaloneDate: currentWorkout.scheduledStart ?? Date(),
                initialSourceWorkout: currentWorkout,
                preserveSourceID: true
            )
        }
        .sheet(isPresented: $showingInvitationLobby) {
            PlannedWorkoutLobbyView(workout: currentWorkout)
                .presentationDetents([.medium, .large])
        }
    }
}

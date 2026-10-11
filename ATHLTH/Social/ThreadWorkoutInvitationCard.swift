import SwiftUI

/// A private invitation surfaced directly in the message timeline.
/// The workout is saved into the recipient's calendar only after acceptance.
struct ThreadWorkoutInvitationCard: View {
    let workout: PlannedSession
    let response: PlannedWorkoutInviteResponse?
    let isMine: Bool
    let isResponding: Bool
    let onAccept: () -> Void
    let onDecline: () -> Void
    let onProposeChanges: () -> Void

    @State private var showingDetails = false

    private var isPhysical: Bool {
        workout.trainTogetherMode != .sameWorkout
    }

    private var subtitle: String {
        isPhysical
            ? ATHLTHLocalization.choose(
                english: "Train together in person",
                norwegian: "Trene fysisk sammen"
            )
            : ATHLTHLocalization.choose(
                english: "Do the same workout",
                norwegian: "Trene samme økt"
            )
    }

    private var responseStatus: (text: String, icon: String) {
        switch response?.decision {
        case .accepted:
            return (
                ATHLTHLocalization.choose(
                    english: "Accepted", norwegian: "Godtatt"
                ), "checkmark.circle.fill"
            )
        case .declined:
            return (
                ATHLTHLocalization.choose(
                    english: "Declined", norwegian: "Avslått"
                ), "xmark.circle.fill"
            )
        case .none:
            return (
                isMine
                    ? ATHLTHLocalization.choose(
                        english: "Waiting for a reply",
                        norwegian: "Venter på svar"
                    )
                    : ATHLTHLocalization.choose(
                        english: "Invited · awaiting your reply",
                        norwegian: "Invitert · venter på svar"
                    ), "clock"
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Button {
                showingDetails = true
            } label: {
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: workout.kind.systemImage)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                        .frame(width: 44, height: 44)
                        .background(
                            Color.white.opacity(0.7),
                            in: RoundedRectangle(cornerRadius: 14)
                        )

                    VStack(alignment: .leading, spacing: 5) {
                        Text(ATHLTHLocalization.choose(
                            english: "ATHLTH · WORKOUT INVITE",
                            norwegian: "ATHLTH · TRENINGSINVITASJON"
                        ))
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(ATHLTHTheme.accentDeep)

                        Text(workout.title)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(ATHLTHTheme.primaryText)
                            .multilineTextAlignment(.leading)

                        Text(workout.kind.title + " · " + subtitle)
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 8) {
                if let start = workout.scheduledStart {
                    Label(
                        start.formatted(date: .abbreviated, time: .shortened),
                        systemImage: "calendar"
                    )
                }
                if let duration = workout.durationMinutes {
                    Label(
                        "\(duration) min",
                        systemImage: "clock"
                    )
                }
                if isPhysical, let point = workout.meetingPoint {
                    Label(point.name, systemImage: "mappin.circle.fill")
                    if let url = URL(string:
                        "https://maps.apple.com/?ll=\(point.latitude),\(point.longitude)") {
                        Link(
                            ATHLTHLocalization.choose(
                                english: "Open meeting point in Maps",
                                norwegian: "Åpne møtested i Kart"
                            ),
                            destination: url
                        )
                        .font(.caption.weight(.semibold))
                    }
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(ATHLTHTheme.primaryText)

            Label(responseStatus.text, systemImage: responseStatus.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.60), in: Capsule())

            if !isMine && response == nil {
                HStack(spacing: 9) {
                    Button(action: onDecline) {
                        Text(ATHLTHLocalization.choose(
                            english: "Decline", norwegian: "Avslå"
                        ))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(ATHLTHTheme.accentDeep)

                    Button(action: onAccept) {
                        HStack(spacing: 6) {
                            if isResponding {
                                ProgressView().controlSize(.mini)
                            }
                            Text(ATHLTHLocalization.choose(
                                english: "Accept", norwegian: "Godta"
                            ))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accentDeep)
                }
                .disabled(isResponding)

                Button(action: onProposeChanges) {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Propose changes",
                            norwegian: "Foreslå endringer"
                        ),
                        systemImage: "square.and.pencil"
                    )
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(ATHLTHTheme.accentDeep)
                .disabled(isResponding)
            }

            Button {
                showingDetails = true
            } label: {
                HStack(spacing: 6) {
                    Text(ATHLTHLocalization.choose(
                        english: "View workout details",
                        norwegian: "Se øktdetaljer"
                    ))
                    Image(systemName: "arrow.up.right")
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(ATHLTHTheme.vitality)
            }
            .buttonStyle(.plain)
        }
        .padding(15)
        .frame(maxWidth: 320, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .fill(LinearGradient(
                    colors: [
                        Color.white.opacity(0.98),
                        ATHLTHTheme.surfaceStone.opacity(0.87),
                        ATHLTHTheme.cardWarm.opacity(0.7)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .stroke(Color.white.opacity(0.97), lineWidth: 1)
        }
        .shadow(color: ATHLTHTheme.accentDeep.opacity(0.08),
                radius: 14, x: 0, y: 6)
        .sheet(isPresented: $showingDetails) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 17) {
                        HStack(spacing: 12) {
                            Image(systemName: workout.kind.systemImage)
                                .font(.title2)
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                                .frame(width: 52, height: 52)
                                .background(
                                    ATHLTHTheme.accentSoft,
                                    in: RoundedRectangle(cornerRadius: 15)
                                )
                            VStack(alignment: .leading, spacing: 5) {
                                Text(workout.title)
                                    .font(.title2.weight(.bold))
                                Text(workout.kind.title + " · " + subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                            }
                        }

                        if let start = workout.scheduledStart {
                            Label(start.formatted(date: .complete, time: .shortened),
                                  systemImage: "calendar")
                        }
                        if let duration = workout.durationMinutes {
                            Label("\(duration) min", systemImage: "clock")
                        }
                        if let km = workout.targetDistanceKilometers {
                            Label(
                                String(format: "%.1f km", km),
                                systemImage: "figure.run"
                            )
                        }
                        if isPhysical, let point = workout.meetingPoint {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(point.name, systemImage: "mappin.and.ellipse")
                                    .font(.headline)
                                Text(point.address)
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                                if let url = URL(string:
                                    "https://maps.apple.com/?ll=\(point.latitude),\(point.longitude)") {
                                    Link(
                                        ATHLTHLocalization.choose(
                                            english: "Open in Maps", norwegian: "Åpne i Kart"
                                        ),
                                        destination: url
                                    )
                                }
                            }
                        }
                        if !workout.exercises.isEmpty {
                            VStack(alignment: .leading, spacing: 9) {
                                Text(ATHLTHLocalization.choose(
                                    english: "Exercises", norwegian: "Øvelser"
                                ))
                                .font(.headline)
                                ForEach(workout.exercises) { exercise in
                                    HStack {
                                        Text(exercise.embeddedExercise.displayName)
                                        Spacer()
                                        Text("\(exercise.sets) sett")
                                            .foregroundStyle(ATHLTHTheme.mutedText)
                                    }
                                    .font(.subheadline)
                                }
                            }
                        }
                        if !workout.resolvedWorkoutBlocks.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(ATHLTHLocalization.choose(
                                    english: "Workout structure",
                                    norwegian: "Øktstruktur"
                                ))
                                .font(.headline)
                                ForEach(workout.resolvedWorkoutBlocks) { block in
                                    Text(block.title)
                                        .font(.subheadline)
                                }
                            }
                        }
                        if let notes = workout.notes, !notes.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(ATHLTHLocalization.choose(
                                    english: "Notes", norwegian: "Notater"
                                ))
                                .font(.headline)
                                Text(notes)
                                    .font(.subheadline)
                            }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(ATHLTHPremiumCanvas())
                .navigationTitle(ATHLTHLocalization.choose(
                    english: "Workout invitation",
                    norwegian: "Treningsinvitasjon"
                ))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(ATHLTHLocalization.choose(
                            english: "Done", norwegian: "Ferdig"
                        )) { showingDetails = false }
                    }
                }
            }
        }
    }
}

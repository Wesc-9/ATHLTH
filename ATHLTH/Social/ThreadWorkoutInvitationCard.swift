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

    private var statusTint: Color {
        switch response?.decision {
        case .accepted: return ATHLTHTheme.vitality
        case .declined: return ATHLTHTheme.mutedText
        case .none: return ATHLTHTheme.accentDeep
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                showingDetails = true
            } label: {
                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "TRAINING INVITATION",
                                norwegian: "INVITASJON TIL ØKT"
                            ),
                            systemImage: "person.2.fill"
                        )
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(ATHLTHTheme.accentDeep)

                        Spacer()

                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                    }

                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: workout.kind.systemImage)
                            .font(.system(size: 23, weight: .semibold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .frame(width: 54, height: 54)
                            .background(
                                Color.white.opacity(0.70),
                                in: RoundedRectangle(cornerRadius: 17)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 17)
                                    .stroke(Color.white.opacity(0.86), lineWidth: 1)
                            }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(workout.title)
                                .font(.system(size: 21, weight: .bold, design: .rounded))
                                .foregroundStyle(ATHLTHTheme.primaryText)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(subtitle)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(ATHLTHTheme.mutedText)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(17)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    LinearGradient(
                        colors: [
                            ATHLTHTheme.champagneSoft.opacity(0.75),
                            Color.white.opacity(0.50),
                            ATHLTHTheme.accentSoft.opacity(0.24)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 7) {
                    if let start = workout.scheduledStart {
                        inviteDetail(
                            icon: "calendar",
                            title: start.formatted(.dateTime.day().month(.abbreviated)),
                            detail: start.formatted(.dateTime.hour().minute())
                        )
                    }
                    if let duration = workout.durationMinutes {
                        inviteDetail(
                            icon: "clock",
                            title: "\(duration) min",
                            detail: ATHLTHLocalization.choose(
                                english: "Duration", norwegian: "Varighet"
                            )
                        )
                    }
                }

                if isPhysical, let point = workout.meetingPoint {
                    HStack(spacing: 8) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(point.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ATHLTHTheme.primaryText)
                            Text(point.address)
                                .font(.caption2)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        if let url = URL(string:
                            "https://maps.apple.com/?ll=\(point.latitude),\(point.longitude)") {
                            Link(destination: url) {
                                Image(systemName: "arrow.up.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(ATHLTHTheme.accentDeep)
                            }
                        }
                    }
                    .padding(11)
                    .background(
                        ATHLTHTheme.surfaceStone.opacity(0.7),
                        in: RoundedRectangle(cornerRadius: 13)
                    )
                }

                HStack(spacing: 7) {
                    Image(systemName: responseStatus.icon)
                        .foregroundStyle(statusTint)
                    Text(responseStatus.text)
                        .foregroundStyle(ATHLTHTheme.primaryText)
                    Spacer(minLength: 0)
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(
                    statusTint.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 11)
                )

                if !isMine && response == nil {
                    HStack(spacing: 9) {
                        Button(action: onDecline) {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Decline", norwegian: "Avslå"
                                ),
                                systemImage: "xmark"
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(ATHLTHTheme.accentDeep)

                        Button(action: onAccept) {
                            HStack(spacing: 7) {
                                if isResponding {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Image(systemName: "checkmark")
                                }
                                Text(ATHLTHLocalization.choose(
                                    english: "Accept", norwegian: "Godta"
                                ))
                            }
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ATHLTHTheme.accentDeep)
                    }
                    .disabled(isResponding)

                    Button(action: onProposeChanges) {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Suggest changes",
                                norwegian: "Foreslå endringer i økten"
                            ),
                            systemImage: "square.and.pencil"
                        )
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .disabled(isResponding)
                } else if response?.decision == .accepted {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Added to your workout calendar",
                            norwegian: "Økten ligger nå i kalenderen din"
                        ),
                        systemImage: "calendar.badge.checkmark"
                    )
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                } else if isMine && response == nil {
                    Text(ATHLTHLocalization.choose(
                        english: "Your own workout stays scheduled whether or not your friend joins.",
                        norwegian: "Din økt blir stående i kalenderen selv om vennen ikke blir med."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    showingDetails = true
                } label: {
                    HStack {
                        Text(ATHLTHLocalization.choose(
                            english: "View workout details",
                            norwegian: "Vis hele økten"
                        ))
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                }
                .buttonStyle(.plain)
            }
            .padding(15)
        }
        .frame(maxWidth: 340, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.86), lineWidth: 1)
        }
        .shadow(color: ATHLTHTheme.accentDeep.opacity(0.10), radius: 20, x: 0, y: 9)
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
    private func inviteDetail(
        icon: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.accentDeep)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(ATHLTHTheme.mutedText)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.66),
                    in: RoundedRectangle(cornerRadius: 12))
    }

}

import SwiftUI

struct TrainTogetherStatusStrip: View {
    @EnvironmentObject private var social: SocialStore

    private var sessionID: UUID? {
        social.currentJoinedWorkoutSessionID ??
        social.activeWorkoutSession?.id
    }

    private var participants:
        [SocialWorkoutParticipantRecord] {
        guard let sessionID else {
            return []
        }

        return social.workoutParticipants
            .filter {
                $0.sessionID == sessionID &&
                $0.state != .declined
            }
            .sorted { lhs, rhs in
                if lhs.state == .creator {
                    return true
                }
                if rhs.state == .creator {
                    return false
                }
                return lhs.displayNameSnapshot
                    .localizedCaseInsensitiveCompare(
                        rhs.displayNameSnapshot
                    ) == .orderedAscending
            }
    }

    var body: some View {
        if let sessionID,
           participants.count > 1 {
            VStack(
                alignment: .leading,
                spacing: 8
            ) {
                HStack {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Training together",
                            norwegian: "Trener sammen"
                        ),
                        systemImage: "person.3.fill"
                    )
                    .font(
                        .caption.weight(.bold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )

                    Spacer()

                    Text(
                        "\(participants.count)"
                    )
                    .font(
                        .caption2.weight(.bold)
                    )
                    .foregroundStyle(
                        .secondary
                    )
                }

                ScrollView(
                    .horizontal,
                    showsIndicators: false
                ) {
                    HStack(spacing: 10) {
                        ForEach(participants) {
                            participant in
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(
                                        statusColor(
                                            participant
                                        )
                                    )
                                    .frame(
                                        width: 7,
                                        height: 7
                                    )

                                Text(
                                    participant
                                        .displayNameSnapshot
                                )
                                .font(
                                    .caption2
                                        .weight(
                                            .semibold
                                        )
                                )
                                .lineLimit(1)

                                Text(
                                    statusText(
                                        participant
                                    )
                                )
                                .font(.caption2)
                                .foregroundStyle(
                                    .secondary
                                )
                            }
                            .padding(
                                .horizontal,
                                9
                            )
                            .padding(
                                .vertical,
                                6
                            )
                            .background(
                                Color(
                                    .secondarySystemGroupedBackground
                                ),
                                in: Capsule()
                            )
                        }
                    }
                }
            }
            .padding(12)
            .background(
                ATHLTHTheme.accent
                    .opacity(0.06),
                in: RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
            )
            .task(id: sessionID) {
                while !Task.isCancelled {
                    try? await social
                        .refreshWorkoutLobby(
                            sessionID: sessionID
                        )
                    try? await Task.sleep(
                        for: .seconds(3)
                    )
                }
            }
        }
    }

    private func statusText(
        _ participant:
            SocialWorkoutParticipantRecord
    ) -> String {
        if participant.launchFailedAt != nil {
            return ATHLTHLocalization.choose(
                english: "Couldn’t start",
                norwegian: "Kunne ikke starte"
            )
        }

        if participant.workoutFinishedAt != nil {
            return ATHLTHLocalization.choose(
                english: "Finished",
                norwegian: "Ferdig"
            )
        }

        if participant.workoutStartedAt != nil {
            return ATHLTHLocalization.choose(
                english: "Training",
                norwegian: "Trener"
            )
        }

        if participant.readyAt != nil {
            return ATHLTHLocalization.choose(
                english: "Ready",
                norwegian: "Klar"
            )
        }

        if participant.state == .accepted {
            return ATHLTHLocalization.choose(
                english: "Accepted",
                norwegian: "Godtatt"
            )
        }

        return ATHLTHLocalization.choose(
            english: "Invited",
            norwegian: "Invitert"
        )
    }

    private func statusColor(
        _ participant:
            SocialWorkoutParticipantRecord
    ) -> Color {
        if participant.launchFailedAt != nil {
            return .red
        }
        if participant.workoutFinishedAt != nil {
            return .secondary
        }
        if participant.workoutStartedAt != nil {
            return ATHLTHTheme.accent
        }
        if participant.readyAt != nil {
            return .green
        }
        return .orange
    }
}

import SwiftUI

struct TrainTogetherCreatorLobbyView: View {
    @EnvironmentObject private var social: SocialStore

    let sessionID: UUID

    private var session: SocialWorkoutSessionRecord? {
        social.workoutSessions.first {
            $0.id == sessionID
        } ?? (
            social.activeWorkoutSession?.id == sessionID
                ? social.activeWorkoutSession
                : nil
        )
    }

    private var participants:
        [SocialWorkoutParticipantRecord] {
        let active = social.activeWorkoutParticipants.filter {
            $0.sessionID == sessionID
        }
        if !active.isEmpty {
            return active
        }

        return social.workoutParticipants.filter {
            $0.sessionID == sessionID
        }
    }

    private var acceptedGuests:
        [SocialWorkoutParticipantRecord] {
        participants.filter {
            $0.userID != social.currentUserID &&
            $0.state == .accepted
        }
    }

    private var allAcceptedGuestsReady: Bool {
        !acceptedGuests.isEmpty &&
        acceptedGuests.allSatisfy(\.isReady)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ATHLTHPremiumCanvas(
                    accent:
                        ATHLTHTheme.accent
                            .opacity(0.18)
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        headerCard
                        participantCard

                        if let startAt =
                                session?
                                    .coordinatedStartAt {
                            countdownCard(
                                startAt: startAt
                            )
                        } else {
                            actionCard
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english: "Train Together",
                    norwegian: "Tren sammen"
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
        }
        .task(id: sessionID) {
            while !Task.isCancelled,
                  social.coordinatedLobbySessionID ==
                    sessionID {
                try? await social
                    .refreshWorkoutLobby(
                        sessionID: sessionID
                    )
                try? await Task.sleep(
                    for: .seconds(1)
                )
            }
        }
    }

    private var headerCard: some View {
        ATHLTHCard {
            VStack(
                alignment: .leading,
                spacing: 8
            ) {
                HStack(spacing: 10) {
                    Image(
                        systemName:
                            "person.3.fill"
                    )
                    .font(.title2)
                    .foregroundStyle(
                        ATHLTHTheme.accent
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 2
                    ) {
                        Text(
                            session?.title ??
                            ATHLTHLocalization.choose(
                                english:
                                    "Shared workout",
                                norwegian:
                                    "Fellesøkt"
                            )
                        )
                        .font(
                            .title3.weight(.bold)
                        )

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Everyone keeps their own workout session. Start together when you are ready.",
                                norwegian:
                                    "Alle får sin egen økt. Start sammen når dere er klare."
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                    }

                    Spacer()
                }
            }
        }
    }

    private var participantCard: some View {
        ATHLTHCard {
            VStack(
                alignment: .leading,
                spacing: 12
            ) {
                Text(
                    ATHLTHLocalization.choose(
                        english: "Participants",
                        norwegian: "Deltakere"
                    )
                )
                .font(
                    .headline.weight(.semibold)
                )

                ForEach(participants) {
                    participant in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(
                                statusColor(
                                    participant
                                )
                            )
                            .frame(
                                width: 10,
                                height: 10
                            )

                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Text(
                                participant
                                    .displayNameSnapshot
                            )
                            .font(
                                .subheadline
                                    .weight(
                                        .semibold
                                    )
                            )

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

                        Spacer()

                        if let icon =
                                deviceIcon(
                                    participant
                                ) {
                            Image(
                                systemName: icon
                            )
                            .foregroundStyle(
                                ATHLTHTheme.accent
                            )
                        }

                        if participant.userID !=
                                social.currentUserID,
                           participant.workoutStartedAt == nil,
                           participant.state == .invited ||
                                participant.state == .accepted {
                            Menu {
                                Button(
                                    role: .destructive
                                ) {
                                    Task {
                                        await social
                                            .withdrawWorkoutParticipant(
                                                participant
                                            )
                                    }
                                } label: {
                                    Label(
                                        ATHLTHLocalization.choose(
                                            english:
                                                "Remove from workout",
                                            norwegian:
                                                "Fjern fra økten"
                                        ),
                                        systemImage:
                                            "person.badge.minus"
                                    )
                                }
                            } label: {
                                Image(
                                    systemName:
                                        "ellipsis"
                                )
                                .font(
                                    .system(
                                        size: 16,
                                        weight: .semibold
                                    )
                                )
                                .frame(
                                    width: 30,
                                    height: 30
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var actionCard: some View {
        ATHLTHCard {
            VStack(spacing: 10) {
                Button {
                    Task {
                        _ = await social
                            .scheduleCoordinatedWorkoutStart(
                                sessionID:
                                    sessionID,
                                countdownSeconds: 3
                            )
                    }
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english:
                                "Start together",
                            norwegian:
                                "Start sammen"
                        ),
                        systemImage:
                            "person.3.sequence.fill"
                    )
                    .font(
                        .headline.weight(
                            .semibold
                        )
                    )
                    .frame(
                        maxWidth: .infinity
                    )
                }
                .buttonStyle(
                    .borderedProminent
                )
                .controlSize(.large)
                .tint(ATHLTHTheme.accent)
                .disabled(
                    !allAcceptedGuestsReady
                )

                Button {
                    Task {
                        _ = await social
                            .scheduleCoordinatedWorkoutStart(
                                sessionID:
                                    sessionID,
                                countdownSeconds: 3
                            )
                    }
                } label: {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Start now",
                            norwegian:
                                "Start nå"
                        )
                    )
                    .frame(
                        maxWidth: .infinity
                    )
                }
                .buttonStyle(.bordered)

                Text(
                    allAcceptedGuestsReady
                        ? ATHLTHLocalization.choose(
                            english:
                                "Everyone who joined is ready.",
                            norwegian:
                                "Alle som har godtatt er klare."
                        )
                        : ATHLTHLocalization.choose(
                            english:
                                "Wait for the others, or start now. Late participants can still join.",
                            norwegian:
                                "Vent på de andre, eller start nå. De som er sene kan fortsatt bli med."
                        )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(
                    .center
                )

                Divider()

                Button(
                    role: .destructive
                ) {
                    Task {
                        await social
                            .cancelActiveWorkout()
                    }
                } label: {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Cancel shared workout",
                            norwegian:
                                "Avbryt fellesøkten"
                        )
                    )
                }
            }
        }
    }

    private func countdownCard(
        startAt: Date
    ) -> some View {
        ATHLTHCard {
            TimelineView(
                .periodic(
                    from: .now,
                    by: 0.2
                )
            ) { context in
                let remaining =
                    max(
                        startAt
                            .timeIntervalSince(
                                context.date
                            ),
                        0
                    )
                let count =
                    max(
                        Int(
                            ceil(remaining)
                        ),
                        0
                    )

                VStack(spacing: 8) {
                    Text(
                        count > 0
                            ? "\(count)"
                            : ATHLTHLocalization.choose(
                                english: "GO",
                                norwegian: "KJØR"
                            )
                    )
                    .font(
                        .system(
                            size: 58,
                            weight: .black,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.accent
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Starting together",
                            norwegian:
                                "Starter sammen"
                        )
                    )
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )
                }
                .frame(
                    maxWidth: .infinity
                )
                .padding(
                    .vertical,
                    10
                )
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
            let device =
                participant.captureDevice ==
                    "apple_watch"
                    ? "Apple Watch"
                    : "iPhone"
            return ATHLTHLocalization.choose(
                english: "Ready · \(device)",
                norwegian: "Klar · \(device)"
            )
        }

        switch participant.state {
        case .creator:
            return ATHLTHLocalization.choose(
                english: "Preparing",
                norwegian: "Gjør seg klar"
            )
        case .invited:
            return ATHLTHLocalization.choose(
                english: "Invited",
                norwegian: "Invitert"
            )
        case .accepted:
            return ATHLTHLocalization.choose(
                english: "Accepted",
                norwegian: "Godtatt"
            )
        case .declined:
            return ATHLTHLocalization.choose(
                english: "Declined",
                norwegian: "Avslått"
            )
        }
    }

    private func statusColor(
        _ participant:
            SocialWorkoutParticipantRecord
    ) -> Color {
        if participant.launchFailedAt != nil {
            return .red
        }
        if participant.workoutStartedAt != nil {
            return ATHLTHTheme.accent
        }
        if participant.readyAt != nil {
            return .green
        }
        if participant.state == .declined {
            return .secondary
        }
        return .orange
    }

    private func deviceIcon(
        _ participant:
            SocialWorkoutParticipantRecord
    ) -> String? {
        switch participant.captureDevice {
        case "apple_watch":
            return "applewatch"
        case "iphone":
            return "iphone"
        default:
            return nil
        }
    }
}

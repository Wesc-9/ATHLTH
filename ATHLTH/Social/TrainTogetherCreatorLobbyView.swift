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
            ScrollView {
                VStack(spacing: 16) {
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
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 34)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(
                ATHLTHPremiumCanvas(
                    accent:
                        ATHLTHTheme
                            .vitality
                            .opacity(0.10)
                )
                .ignoresSafeArea()
            )
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
        ZStack(
            alignment: .bottomLeading
        ) {
            Image("TrainHero")
                .resizable()
                .scaledToFill()
                .frame(height: 190)
                .clipped()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.04),
                    Color.black.opacity(0.18),
                    Color.black.opacity(0.70)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(
                alignment: .leading,
                spacing: 7
            ) {
                HStack {
                    Label(
                        "TRAIN TOGETHER",
                        systemImage:
                            "person.2.fill"
                    )
                    .font(
                        .caption.weight(
                            .bold
                        )
                    )
                    .tracking(0.8)
                    .foregroundStyle(
                        Color.white
                            .opacity(0.92)
                    )

                    Spacer()

                    Button {
                        social
                            .minimizeCoordinatedLobby()
                    } label: {
                        Image(
                            systemName:
                                "rectangle.compress.vertical"
                        )
                        .font(
                            .system(
                                size: 14,
                                weight:
                                    .bold
                            )
                        )
                        .foregroundStyle(
                            .white
                        )
                        .frame(
                            width: 38,
                            height: 38
                        )
                        .background(
                            .ultraThinMaterial,
                            in: Circle()
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        ATHLTHLocalization.choose(
                            english:
                                "Minimize Train Together",
                            norwegian:
                                "Minimer Tren sammen"
                        )
                    )
                }

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
                    .title2.weight(.bold)
                )
                .foregroundStyle(.white)
                .lineLimit(1)

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Everyone keeps their own workout. Start together when everyone is ready.",
                        norwegian:
                            "Alle får sin egen økt. Start sammen når alle er klare."
                    )
                )
                .font(.subheadline)
                .foregroundStyle(
                    Color.white
                        .opacity(0.86)
                )
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
            }
            .padding(16)
        }
        .frame(height: 190)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
            .stroke(
                Color.white
                    .opacity(0.30),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                Color.black
                    .opacity(0.10),
            radius: 18,
            y: 8
        )
    }

    private var participantCard: some View {
        ATHLTHCard {
            VStack(
                alignment: .leading,
                spacing: 12
            ) {
                HStack {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "LOBBY",
                            norwegian: "LOBBY"
                        )
                    )
                    .font(
                        .caption.weight(.bold)
                    )
                    .tracking(1.1)
                    .foregroundStyle(
                        ATHLTHTheme
                            .vitality
                    )

                    Spacer()

                    Text(
                        "\(participants.count)"
                    )
                    .font(
                        .caption.weight(
                            .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                }

                ForEach(
                    Array(
                        participants
                            .enumerated()
                    ),
                    id: \.element.id
                ) {
                    index,
                    participant in

                    if index > 0 {
                        Divider()
                    }

                    participantRow(
                        participant
                    )
                }
            }
        }
    }

    private func participantRow(
        _ participant:
            SocialWorkoutParticipantRecord
    ) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(
                    participant.isReady
                        ? ATHLTHTheme
                            .vitality
                            .opacity(0.14)
                        : Color.primary
                            .opacity(0.055)
                )
                .frame(
                    width: 44,
                    height: 44
                )
                .overlay {
                    Image(
                        systemName:
                            participant.isReady
                                ? "checkmark"
                                : "person.fill"
                    )
                    .font(
                        .system(
                            size: 15,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        participant.isReady
                            ? ATHLTHTheme
                                .vitality
                            : ATHLTHTheme
                                .mutedText
                    )
                }

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(
                    participant
                        .displayNameSnapshot
                )
                .font(
                    .subheadline
                        .weight(.semibold)
                )

                HStack(spacing: 5) {
                    Text(
                        statusText(
                            participant
                        )
                    )

                    if let icon =
                            deviceIcon(
                                participant
                            ) {
                        Image(
                            systemName: icon
                        )
                    }
                }
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
            }

            Spacer()

            Text(
                participant.isReady
                    ? ATHLTHLocalization.choose(
                        english: "READY",
                        norwegian: "KLAR"
                    )
                    : ATHLTHLocalization.choose(
                        english: "WAITING",
                        norwegian: "VENTER"
                    )
            )
            .font(
                .caption2.weight(.bold)
            )
            .foregroundStyle(
                participant.isReady
                    ? ATHLTHTheme
                        .vitality
                    : ATHLTHTheme
                        .mutedText
            )

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
                            size: 15,
                            weight:
                                .semibold
                        )
                    )
                    .frame(
                        width: 28,
                        height: 28
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var actionCard: some View {
        ATHLTHCard {
            VStack(spacing: 11) {
                HStack(spacing: 8) {
                    Image(
                        systemName:
                            allAcceptedGuestsReady
                                ? "checkmark.circle.fill"
                                : "clock.fill"
                    )
                    .foregroundStyle(
                        allAcceptedGuestsReady
                            ? ATHLTHTheme
                                .vitality
                            : ATHLTHTheme
                                .premiumGold
                    )

                    Text(
                        allAcceptedGuestsReady
                            ? ATHLTHLocalization.choose(
                                english:
                                    "Everyone is ready",
                                norwegian:
                                    "Alle er klare"
                            )
                            : ATHLTHLocalization.choose(
                                english:
                                    "Waiting for the others",
                                norwegian:
                                    "Venter på de andre"
                            )
                    )
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )

                    Spacer()
                }

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
                    .frame(height: 52)
                }
                .buttonStyle(
                    .borderedProminent
                )
                .tint(
                    ATHLTHTheme.vitality
                )
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
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )
                    .frame(
                        maxWidth: .infinity
                    )
                    .frame(height: 46)
                }
                .buttonStyle(.bordered)

                Text(
                    allAcceptedGuestsReady
                        ? ATHLTHLocalization.choose(
                            english:
                                "ATHLTH starts one synchronized countdown for everyone.",
                            norwegian:
                                "ATHLTH starter én synkronisert nedtelling for alle."
                        )
                        : ATHLTHLocalization.choose(
                            english:
                                "You can minimize this lobby while you wait. Late participants can still join.",
                            norwegian:
                                "Du kan minimere lobbyen mens du venter. De som er sene kan fortsatt bli med."
                        )
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
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
                    .font(
                        .subheadline
                            .weight(.semibold)
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

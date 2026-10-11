import SwiftUI

struct TrainTogetherCreatorLobbyView: View {
    @EnvironmentObject private var social: SocialStore
    @StateObject private var companion = SocialWorkoutCompanionStore()

    let sessionID: UUID
    @State private var isStarting = false
    @State private var startError: String?

    private var hasStarted: Bool {
        participants.contains { $0.workoutStartedAt != nil }
    }

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

                    if !companion.liveStates.isEmpty {
                        liveParticipantsCard
                    }

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
            var cycle = 0
            while !Task.isCancelled,
                  social.coordinatedLobbySessionID == sessionID {
                try? await social.refreshWorkoutLobby(
                    sessionID: sessionID
                )
                if cycle.isMultiple(of: 5) {
                    await companion.refresh(sessionID: sessionID)
                }
                cycle += 1
                try? await Task.sleep(for: .seconds(1))
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
                        ATHLTHLocalization.choose(
                            english: hasStarted ? "TRAIN TOGETHER" : "PLANNED · NOT STARTED",
                            norwegian: hasStarted ? "TREN SAMMEN" : "PLANLAGT · IKKE STARTET"
                        ),
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
                                "xmark"
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
                                "Close lobby (keep invitation)",
                            norwegian:
                                "Lukk lobby (behold invitasjonen)"
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
                            "The invitation is planned, not started. Wait for your friend or choose how to begin.",
                        norwegian:
                            "Invitasjonen er planlagt, ikke startet. Vent på vennen din eller velg å starte."
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
                        ATHLTHLocalization.format(
                            english: "%d of %d ready",
                            norwegian: "%d av %d klare",
                            participants.filter(\.isReady).count,
                            participants.count
                        )
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
            Group {
                if let profile = social.profile(for: participant.userID) {
                    SocialAvatar(profile: profile, size: 44)
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .frame(width: 44, height: 44)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if participant.isReady {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 17, height: 17)
                        .background(ATHLTHTheme.vitality, in: Circle())
                        .overlay { Circle().stroke(.white, lineWidth: 2) }
                }
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

    private var liveParticipantsCard: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Shared live progress",
                        norwegian: "Felles fremdrift"
                    ),
                    systemImage: "waveform.path.ecg"
                )
                .font(.headline)

                ForEach(companion.liveStates) { state in
                    HStack(spacing: 12) {
                        Image(systemName: state.workoutKind == "strength"
                            ? "dumbbell.fill" : "figure.run")
                            .foregroundStyle(ATHLTHTheme.vitality)
                            .frame(width: 32, height: 32)
                            .background(ATHLTHTheme.vitalitySoft,
                                        in: RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(state.displayNameSnapshot)
                                .font(.subheadline.weight(.semibold))
                            HStack(spacing: 8) {
                                if let km = state.payload.distanceMeters {
                                    Text(String(format: "%.2f km", km / 1000))
                                }
                                if let seconds = state.payload.elapsedSeconds {
                                    Text("\(Int(seconds / 60)) min")
                                }
                                if let set = state.payload.currentSetNumber {
                                    Text(
                                        ATHLTHLocalization.format(
                                            english: "Set %d",
                                            norwegian: "Sett %d",
                                            set
                                        )
                                    )
                                }
                                if let title = state.payload.currentTitle {
                                    Text(title).lineLimit(1)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private var actionCard: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: allAcceptedGuestsReady
                          ? "checkmark.circle.fill" : "clock")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(allAcceptedGuestsReady
                            ? ATHLTHTheme.vitality
                            : ATHLTHTheme.premiumGold)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(ATHLTHLocalization.choose(
                            english: allAcceptedGuestsReady
                                ? "Your group is ready"
                                : "Waiting for your friend",
                            norwegian: allAcceptedGuestsReady
                                ? "Dere er klare"
                                : "Venter på vennen din"
                        ))
                        .font(.subheadline.weight(.semibold))

                        Text(ATHLTHLocalization.choose(
                            english: "Planned · not started",
                            norwegian: "Planlagt · ikke startet"
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                    Spacer(minLength: 0)
                }

                Button {
                    guard !isStarting else { return }
                    isStarting = true
                    startError = nil
                    Task {
                        let started = await social.scheduleCoordinatedWorkoutStart(
                            sessionID: sessionID,
                            countdownSeconds: 3
                        )
                        if !started {
                            startError = social.errorMessage ??
                                ATHLTHLocalization.choose(
                                    english: "Could not start the group workout.",
                                    norwegian: "Kunne ikke starte fellesøkten."
                                )
                        }
                        isStarting = false
                    }
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Start together",
                            norwegian: "Start sammen"
                        ),
                        systemImage: "person.3.sequence.fill"
                    )
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.vitality)
                .disabled(
                    isStarting ||
                    !allAcceptedGuestsReady ||
                    session?.invitePayload?.resolvedStartIndependently == true
                )

                Button {
                    guard !isStarting else { return }
                    isStarting = true
                    startError = nil
                    Task {
                        let started = await social.enableIndependentWorkoutStart(
                            sessionID: sessionID
                        )
                        if !started {
                            startError = social.errorMessage ??
                                ATHLTHLocalization.choose(
                                    english: "Could not start the workout.",
                                    norwegian: "Kunne ikke starte økten."
                                )
                        }
                        isStarting = false
                    }
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Start alone",
                            norwegian: "Start alene"
                        ),
                        systemImage: "figure.run"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                }
                .buttonStyle(.bordered)
                .disabled(isStarting || session?.invitePayload == nil)

                if let startError {
                    Text(startError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Text(ATHLTHLocalization.choose(
                    english: "Nothing starts while you wait. Close the lobby whenever you want and train something else normally. This invitation stays planned.",
                    norwegian: "Ingenting starter mens du venter. Du kan lukke lobbyen og trene noe annet som vanlig. Invitasjonen forblir planlagt."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)

                Divider()

                Button(role: .destructive) {
                    Task {
                        await social.cancelActiveWorkout(sessionID: sessionID)
                    }
                } label: {
                    Text(ATHLTHLocalization.choose(
                        english: "Cancel invitation",
                        norwegian: "Avlys invitasjonen"
                    ))
                    .font(.subheadline.weight(.semibold))
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

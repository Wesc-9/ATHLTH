import SwiftUI

struct TrainTogetherCreatorLobbyView: View {
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var messaging: MessagingStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @StateObject private var companion = SocialWorkoutCompanionStore()

    let sessionID: UUID
    @State private var isStarting = false
    @State private var isMarkingReady = false
    @State private var selectedCaptureDevice: WorkoutCaptureDevice = .iPhone
    @State private var didLoadCaptureDevice = false
    @State private var startError: String?
    @State private var isChangingArrival = false
    @State private var confirmingIndependentStart = false
    @State private var confirmingCancellation = false
    @State private var reminderInFlight: Set<UUID> = []
    @State private var chatPartner: SocialProfileCard?

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

    private var creatorParticipant: SocialWorkoutParticipantRecord? {
        participants.first { $0.userID == social.currentUserID }
    }

    private var creatorReady: Bool {
        creatorParticipant?.isReady == true
    }

    private var invitedGuests: [SocialWorkoutParticipantRecord] {
        participants.filter {
            $0.userID != social.currentUserID &&
            $0.state != .declined
        }
    }

    private var everyoneReady: Bool {
        creatorReady &&
        !invitedGuests.isEmpty &&
        invitedGuests.allSatisfy {
            $0.state == .accepted && $0.isReady
        }
    }

    private var watchSelectable: Bool {
        ATHLTHDeviceRole.isIPad || watchConnection.isReady
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
            .background(ATHLTHTrainTogetherDesign.canvas.ignoresSafeArea())
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english: "Train Together",
                    norwegian: "Tren sammen"
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
        }
        .sheet(item: $chatPartner) { profile in
            NavigationStack {
                DirectMessageThreadView(friend: profile)
            }
        }
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english: "Start without the others?",
                norwegian: "Starte uten de andre?"
            ),
            isPresented: $confirmingIndependentStart,
            titleVisibility: .visible
        ) {
            Button(ATHLTHLocalization.choose(
                english: "Start alone", norwegian: "Start alene"
            ), role: .destructive) {
                startAloneAfterConfirmation()
            }
            Button(ATHLTHLocalization.choose(
                english: "Keep waiting", norwegian: "Fortsett å vente"
            ), role: .cancel) {}
        } message: {
            Text(ATHLTHLocalization.choose(
                english: "Other participants will remain invited. You won't have a shared 3–2–1 start.",
                norwegian: "De andre beholder invitasjonen, men dere får ikke felles 3–2–1-start."
            ))
        }
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english: "Cancel the shared start invitation?",
                norwegian: "Avlyse invitasjonen til fellesstart?"
            ),
            isPresented: $confirmingCancellation,
            titleVisibility: .visible
        ) {
            Button(ATHLTHLocalization.choose(
                english: "Cancel invitation", norwegian: "Avlys invitasjonen"
            ), role: .destructive) {
                Task { await social.cancelActiveWorkout(sessionID: sessionID) }
            }
            Button(ATHLTHLocalization.choose(
                english: "Keep invitation", norwegian: "Behold invitasjonen"
            ), role: .cancel) {}
        }
        .task(id: sessionID) {
            if !didLoadCaptureDevice {
                selectedCaptureDevice = social.proposedCreatorCaptureDevice(
                    for: sessionID
                )
                didLoadCaptureDevice = true
            }
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "person.2.wave.2.fill")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(ATHLTHTrainTogetherDesign.accent)
                    .frame(width: 54, height: 54)
                    .background(
                        ATHLTHTrainTogetherDesign.accentSoft,
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 5) {
                    Text(ATHLTHLocalization.choose(
                        english: hasStarted ? "TRAINING TOGETHER" : "READY LOBBY",
                        norwegian: hasStarted ? "TRENER SAMMEN" : "KLAR TIL ØKT"
                    ))
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(ATHLTHTrainTogetherDesign.accent)

                    Text(session?.title ?? ATHLTHLocalization.choose(
                        english: "Shared workout", norwegian: "Fellesøkt"
                    ))
                    .font(.system(size: 27, weight: .semibold, design: .serif))
                    .foregroundStyle(ATHLTHTrainTogetherDesign.ink)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)

                Button {
                    social.minimizeCoordinatedLobby()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHTrainTogetherDesign.ink)
                        .frame(width: 44, height: 44)
                        .background(
                            ATHLTHTrainTogetherDesign.accentSoft.opacity(0.7),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Close lobby (keep invitation)",
                    norwegian: "Lukk lobby (behold invitasjonen)"
                ))
            }

            Label(
                ATHLTHLocalization.choose(
                    english: hasStarted
                        ? "Your shared session is underway."
                        : "The workout has not started. Participants can mark themselves ready.",
                    norwegian: hasStarted
                        ? "Fellesøkten er i gang."
                        : "Økten er ikke startet. Deltakerne kan markere seg klare."
                ),
                systemImage: hasStarted ? "figure.run" : "clock"
            )
            .font(.subheadline)
            .foregroundStyle(ATHLTHTrainTogetherDesign.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if let plannedStart = session?.invitePayload?.workout.scheduledStart {
                Label(
                    plannedStart > Date()
                        ? plannedStart.formatted(date: .abbreviated, time: .shortened)
                        : ATHLTHLocalization.choose(
                            english: "Scheduled time passed · awaiting shared start",
                            norwegian: "Planlagt tid passert · venter på felles start"
                        ),
                    systemImage: "calendar"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(ATHLTHTrainTogetherDesign.accent)
            }
        }
        .padding(19)
        .frame(maxWidth: .infinity, alignment: .leading)
        .athlthTrainTogetherCard(radius: 25)
    }

    private var participantCard: some View {
        ATHLTHTrainTogetherSurface {
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
                        ATHLTHTheme.premiumGold
                    )

                    Spacer()

                    Text(
                        ATHLTHLocalization.format(
                            english: "%d of %d ready",
                            norwegian: "%d av %d klare",
                            participants.filter {
                                $0.state != .declined && $0.isReady
                            }.count,
                            participants.filter { $0.state != .declined }.count
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
                        .background(ATHLTHTheme.premiumGold, in: Circle())
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
                .foregroundStyle(ATHLTHTheme.mutedText)

                if let arrival = participant.arrivalStatus,
                   participant.workoutFinishedAt == nil {
                    Label(arrival.label, systemImage: arrival.symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(ATHLTHTrainTogetherDesign.accent)
                }
            }

            Spacer()

            Text(participantHeadline(participant))
            .font(
                .caption2.weight(.bold)
            )
            .foregroundStyle(
                participant.isReady || participant.isTraining
                    ? ATHLTHTrainTogetherDesign.accent
                    : ATHLTHTheme.mutedText
            )

            if participant.userID !=
                    social.currentUserID,
               participant.workoutStartedAt == nil,
               participant.state == .invited ||
                    participant.state == .accepted {
                Menu {
                    if let profile = social.profile(for: participant.userID) {
                        Button {
                            chatPartner = profile
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Message", norwegian: "Send melding"
                                ),
                                systemImage: "bubble.left"
                            )
                        }
                    }
                    if !participant.isReady {
                        Button {
                            Task { await sendReminder(to: participant) }
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Send reminder", norwegian: "Send påminnelse"
                                ),
                                systemImage: "bell"
                            )
                        }
                        .disabled(!canRemind(participant))
                    }
                    Divider()
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
        ATHLTHTrainTogetherSurface {
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
                            .foregroundStyle(ATHLTHTheme.premiumGold)
                            .frame(width: 32, height: 32)
                            .background(ATHLTHTheme.premiumGoldSoft,
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
        ATHLTHTrainTogetherSurface {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: everyoneReady
                          ? "checkmark.circle.fill" : "clock")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(everyoneReady
                            ? ATHLTHTheme.premiumGold
                            : ATHLTHTheme.premiumGold)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(ATHLTHLocalization.choose(
                            english: everyoneReady
                                ? "Everyone ready · host can start"
                                : "Waiting for everyone to be ready",
                            norwegian: everyoneReady
                                ? "Alle klare · eier kan starte"
                                : "Venter på at alle skal bli klare"
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

                if session?.invitePayload?.resolvedParticipationMode == .physical {
                    arrivalControls
                }

                if !creatorReady {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(ATHLTHLocalization.choose(
                            english: "Your recording device",
                            norwegian: "Din opptaksenhet"
                        ))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.mutedText)

                        Picker(
                            ATHLTHLocalization.choose(
                                english: "Recording device",
                                norwegian: "Opptaksenhet"
                            ),
                            selection: $selectedCaptureDevice
                        ) {
                            Text("iPhone").tag(WorkoutCaptureDevice.iPhone)
                            if watchSelectable {
                                Text("Apple Watch").tag(WorkoutCaptureDevice.appleWatch)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    Button {
                        guard !isMarkingReady else { return }
                        isMarkingReady = true
                        startError = nil
                        Task {
                            let ready = await social.markCurrentUserReady(
                                sessionID: sessionID,
                                captureDevice: selectedCaptureDevice
                            )
                            if !ready {
                                startError = social.errorMessage ??
                                    ATHLTHLocalization.choose(
                                        english: "Could not mark you ready.",
                                        norwegian: "Kunne ikke markere deg som klar."
                                    )
                            }
                            isMarkingReady = false
                        }
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "I'm ready",
                                norwegian: "Klar"
                            ),
                            systemImage: "checkmark.circle"
                        )
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTrainTogetherDesign.accent)
                    .disabled(isMarkingReady || isStarting)
                } else {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "You are ready",
                            norwegian: "Du er klar"
                        ),
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.premiumGold)
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
                .tint(ATHLTHTrainTogetherDesign.accent)
                .disabled(
                    isStarting ||
                    !everyoneReady ||
                    session?.invitePayload?.startIndependently == true
                )

                Button {
                    confirmingIndependentStart = true
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
                .tint(ATHLTHTheme.premiumGold)
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
                    confirmingCancellation = true
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

    private func participantHeadline(_ person: SocialWorkoutParticipantRecord) -> String {
        if person.launchFailedAt != nil {
            return ATHLTHLocalization.choose(english: "FAILED", norwegian: "FEIL")
        }
        if person.workoutFinishedAt != nil {
            return ATHLTHLocalization.choose(english: "DONE", norwegian: "FERDIG")
        }
        if person.workoutStartedAt != nil {
            return ATHLTHLocalization.choose(english: "TRAINING", norwegian: "TRENER")
        }
        if person.isReady {
            return ATHLTHLocalization.choose(english: "READY", norwegian: "KLAR")
        }
        switch person.state {
        case .creator:
            return ATHLTHLocalization.choose(english: "PREPARING", norwegian: "GJØR SEG KLAR")
        case .accepted:
            return ATHLTHLocalization.choose(english: "ACCEPTED", norwegian: "GODTATT")
        case .invited:
            return ATHLTHLocalization.choose(english: "INVITED", norwegian: "INVITERT")
        case .declined:
            return ATHLTHLocalization.choose(english: "DECLINED", norwegian: "AVSLÅTT")
        }
    }

    private var ownArrival: SocialWorkoutArrivalStatus? {
        participants.first { $0.userID == social.currentUserID }?.arrivalStatus
    }

    private var arrivalControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ATHLTHLocalization.choose(
                english: "Before meeting up", norwegian: "Før dere møtes"
            ))
            .font(.caption.weight(.semibold))
            .foregroundStyle(ATHLTHTrainTogetherDesign.secondary)

            HStack(spacing: 8) {
                ForEach(SocialWorkoutArrivalStatus.allCases, id: \.self) { status in
                    let selected = ownArrival == status
                    Button {
                        guard !isChangingArrival else { return }
                        isChangingArrival = true
                        Task {
                            let newStatus: SocialWorkoutArrivalStatus? =
                                selected ? nil : status
                            let didUpdate = await social.setCurrentWorkoutArrival(
                                sessionID: sessionID, status: newStatus
                            )
                            if !didUpdate {
                                startError = social.errorMessage ??
                                    ATHLTHLocalization.choose(
                                        english: "Could not update arrival status.",
                                        norwegian: "Kunne ikke oppdatere ankomststatus."
                                    )
                            }
                            isChangingArrival = false
                        }
                    } label: {
                        Label(status.label, systemImage: status.symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(
                                selected
                                    ? ATHLTHTrainTogetherDesign.accent
                                    : ATHLTHTrainTogetherDesign.secondary
                            )
                            .frame(maxWidth: .infinity, minHeight: 37)
                            .background(
                                selected
                                    ? ATHLTHTrainTogetherDesign.accentSoft
                                    : ATHLTHTrainTogetherDesign.surface,
                                in: Capsule()
                            )
                            .overlay {
                                Capsule().stroke(
                                    ATHLTHTrainTogetherDesign.outline, lineWidth: 0.8
                                )
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(isChangingArrival || isStarting)
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                }
            }

            Text(ATHLTHLocalization.choose(
                english: "Only a status label is shared; never your location.",
                norwegian: "Kun statusen deles – aldri posisjonen din."
            ))
            .font(.caption2)
            .foregroundStyle(ATHLTHTheme.mutedText)
        }
    }

    private func canRemind(_ person: SocialWorkoutParticipantRecord) -> Bool {
        guard !reminderInFlight.contains(person.id),
              person.userID != social.currentUserID,
              person.workoutStartedAt == nil, !person.isReady
        else { return false }
        let key = "athlth.trainTogether.reminder.\(sessionID).\(person.userID)"
        guard let last = UserDefaults.standard.object(forKey: key) as? Date else {
            return true
        }
        return Date().timeIntervalSince(last) >= 900
    }

    @MainActor
    private func sendReminder(to person: SocialWorkoutParticipantRecord) async {
        guard canRemind(person) else { return }
        reminderInFlight.insert(person.id)
        defer { reminderInFlight.remove(person.id) }
        do {
            let chat = try await messaging.openConversation(with: person.userID)
            let workoutTitle = session?.title ?? "ATHLTH"
            let note = ATHLTHLocalization.choose(
                english: "Reminder: \(workoutTitle) is waiting for your response or ready status in ATHLTH.",
                norwegian: "Påminnelse: \(workoutTitle) venter på svar eller klarmelding i ATHLTH."
            )
            if await messaging.send(
                to: person.userID,
                conversationID: chat,
                body: note
            ) {
                let key = "athlth.trainTogether.reminder.\(sessionID).\(person.userID)"
                UserDefaults.standard.set(Date(), forKey: key)
            } else {
                startError = messaging.errorMessage ??
                    ATHLTHLocalization.choose(
                        english: "Could not send reminder.",
                        norwegian: "Kunne ikke sende påminnelse."
                    )
            }
        } catch {
            startError = error.localizedDescription
        }
    }

    private func startAloneAfterConfirmation() {
        guard !isStarting else { return }
        isStarting = true
        startError = nil
        Task {
            var isReady = creatorReady
            if !isReady {
                isReady = await social.markCurrentUserReady(
                    sessionID: sessionID, captureDevice: selectedCaptureDevice
                )
            }
            guard isReady else {
                startError = social.errorMessage ??
                    ATHLTHLocalization.choose(
                        english: "Could not mark you ready.",
                        norwegian: "Kunne ikke markere deg som klar."
                    )
                isStarting = false
                return
            }
            let started = await social.enableIndependentWorkoutStart(sessionID: sessionID)
            if !started {
                startError = social.errorMessage ??
                    ATHLTHLocalization.choose(
                        english: "Could not start the workout.",
                        norwegian: "Kunne ikke starte økten."
                    )
            }
            isStarting = false
        }
    }

    private func countdownCard(
        startAt: Date
    ) -> some View {
        ATHLTHTrainTogetherSurface {
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
                        ATHLTHTheme.premiumGold
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
            return ATHLTHTrainTogetherDesign.accent
        }
        if participant.readyAt != nil {
            return ATHLTHTheme.premiumGold
        }
        if participant.state == .declined {
            return .secondary
        }
        return ATHLTHTheme.premiumGold.opacity(0.68)
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

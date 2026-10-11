import SwiftUI

/// A countdown can arrive before a participant's READY update; re-arm
/// the launch task whenever either readiness state changes.
private struct LiveGhostStartTrigger: Equatable {
    let startsAt: Date?
    let ownReady: Bool
    let opponentReady: Bool
}

struct LiveGhostRaceLobbyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var phoneWorkout: IPhoneWorkoutStore
    @EnvironmentObject private var ghostRace: GhostRaceStore
    @EnvironmentObject private var realtime: ATHLTHRealtimeSocialStore

    let challenge: GhostFriendRaceChallengeRecord

    @StateObject private var liveRace =
        LiveGhostRaceStore()
    @StateObject private var friendRaces =
        GhostFriendRaceStore()

    @State private var captureDevice:
        WorkoutCaptureDevice = .iPhone
    @State private var launchError: String?
    @State private var didLaunch = false
    @State private var isLaunching = false
    @State private var rematchSent = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                participantCard

                if ATHLTHDeviceRole.isIPad {
                    spectatorCard
                } else {
                    deviceCard
                    readyCard
                }

                phaseCard

                if let liveSession {
                    NavigationLink {
                        ATHLTHLiveWorkoutMapView(
                            session: liveSession
                        )
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Open live race map",
                                norwegian: "Åpne livekart"
                            ),
                            systemImage: "map.fill"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accentDeep)
                }

                if case .finished =
                    liveRace.phase() {
                    resultCard
                } else if ownParticipant?.finishedAt != nil {
                    pendingFinishCard
                }

                if let message =
                        launchError ??
                        liveRace.errorMessage ??
                        friendRaces.errorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                }
            }
            .padding(18)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(
            ATHLTHPremiumCanvas(
                accent:
                    ATHLTHTheme.vitality
                        .opacity(0.10)
            )
        )
        .navigationTitle("Live Ghost")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: challenge.id) {
            await social.refresh()
            await realtime
                .refreshVisibleLiveSessions(
                    force: true
                )
            await liveRace.open(
                challenge: challenge
            )
        }
        .task(id: LiveGhostStartTrigger(
            startsAt: liveRace.room?.startsAt,
            ownReady: ownParticipant?.ready == true,
            opponentReady: opponentParticipant?.ready == true
        )) {
            await waitForSynchronizedStart()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await liveRace.refresh(challengeID: challenge.id)
                await waitForSynchronizedStart()
            }
        }
        .onChange(of: liveRace.room?.status) { _, status in
            guard status == .finished || status == .cancelled,
                  realtime.currentSession?.ghostChallengeID == challenge.id
            else { return }
            // Stop sharing this user's live position when the duel settles.
            // Local HealthKit workouts are left untouched.
            Task { await realtime.setCurrentLiveLocationSharing(false) }
        }
        .onDisappear {
            liveRace.close()
        }
        .alert(
            "Live Ghost",
            isPresented:
                Binding(
                    get: {
                        launchError != nil
                    },
                    set: { shown in
                        if !shown {
                            launchError = nil
                        }
                    }
                )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            if let launchError {
                Text(launchError)
            }
        }
    }

    private var liveSession:
        ATHLTHLiveWorkoutSession? {
        realtime.visibleLiveSessions
            .first {
                $0.ghostChallengeID ==
                    challenge.id
            } ??
        (
            realtime.currentSession?
                .ghostChallengeID ==
                challenge.id
                ? realtime.currentSession
                : nil
        )
    }

    private var currentUserID: UUID {
        session.profile.userID
    }

    private var opponentID: UUID {
        currentUserID ==
            challenge.senderID
            ? challenge.recipientID
            : challenge.senderID
    }

    private var ownParticipant:
        LiveGhostRaceParticipantRecord? {
        liveRace.participant(
            userID: currentUserID
        )
    }

    private var opponentParticipant:
        LiveGhostRaceParticipantRecord? {
        liveRace.participant(
            userID: opponentID
        )
    }

    private var headerCard: some View {
        ATHLTHCard {
            VStack(
                alignment: .leading,
                spacing: 12
            ) {
                HStack {
                    Label(
                        "LIVE GHOST",
                        systemImage:
                            "dot.radiowaves.left.and.right"
                    )
                    .font(.caption.bold())
                    .foregroundStyle(
                        ATHLTHTheme.vitality
                    )

                    Spacer()

                    Text(
                        String(
                            format:
                                "%.1f km",
                            challenge
                                .distanceMeters /
                                1_000
                        )
                    )
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )
                    .monospacedDigit()
                }

                Text(challenge.title)
                    .font(
                        .title2.weight(.bold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                Label(
                    challenge.sourceKind == "planned_route"
                        ? ATHLTHLocalization.choose(
                            english: "Planned route · shared start",
                            norwegian: "Planlagt rute · felles start"
                        )
                        : ATHLTHLocalization.choose(
                            english: "Previous GPS run · shared start",
                            norwegian: "Tidligere GPS-økt · felles start"
                        ),
                    systemImage: challenge.sourceKind == "planned_route"
                        ? "map.fill" : "figure.run"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(ATHLTHTheme.mutedText)

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Both athletes enter the same race room. When both are ready, ATHLTH starts one synchronized countdown.",
                        norwegian:
                            "Begge går inn i samme race-rom. Når begge er klare, starter ATHLTH én synkronisert nedtelling."
                    )
                )
                .font(.subheadline)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
            }
        }
    }

    private var participantCard: some View {
        ATHLTHCard {
            VStack(
                alignment: .leading,
                spacing: 12
            ) {
                sectionTitle(
                    ATHLTHLocalization.choose(
                        english: "Race lobby",
                        norwegian: "Race-lobby"
                    )
                )

                participantRow(
                    userID: currentUserID,
                    participant:
                        ownParticipant,
                    isCurrentUser: true
                )

                Divider()

                participantRow(
                    userID: opponentID,
                    participant:
                        opponentParticipant,
                    isCurrentUser: false
                )
            }
        }
    }

    @ViewBuilder
    private func participantRow(
        userID: UUID,
        participant:
            LiveGhostRaceParticipantRecord?,
        isCurrentUser: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(
                    participant?.ready == true
                        ? ATHLTHTheme.vitality
                            .opacity(0.14)
                        : Color.primary
                            .opacity(0.06)
                )
                .frame(
                    width: 42,
                    height: 42
                )
                .overlay {
                    Image(
                        systemName:
                            participant?.ready ==
                            true
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
                        participant?.ready == true
                            ? ATHLTHTheme.vitality
                            : ATHLTHTheme
                                .mutedText
                    )
                }

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(
                    isCurrentUser
                        ? ATHLTHLocalization.choose(
                            english: "You",
                            norwegian: "Du"
                        )
                        : displayName(
                            userID
                        )
                )
                .font(
                    .subheadline
                        .weight(.semibold)
                )

                Text(
                    participantSubtitle(
                        participant
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            }

            Spacer()

            Text(
                participant?.ready == true
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
                participant?.ready == true
                    ? ATHLTHTheme.vitality
                    : ATHLTHTheme.mutedText
            )
        }
    }

    private var deviceCard: some View {
        ATHLTHCard {
            VStack(
                alignment: .leading,
                spacing: 12
            ) {
                sectionTitle(
                    ATHLTHLocalization.choose(
                        english: "Race device",
                        norwegian: "Race-enhet"
                    )
                )

                QuickStartWorkoutDeviceCard(
                    selection: $captureDevice,
                    watchConnected:
                        watchConnection.isReady &&
                        !watchConnection
                            .workoutLaunchInProgress,
                    iPhoneEnabled:
                        phoneWorkout.active ==
                        nil,
                    iPhoneSubtitle:
                        ATHLTHLocalization.choose(
                            english:
                                "Use iPhone GPS for this Live Ghost race.",
                            norwegian:
                                "Bruk iPhone-GPS for denne Live Ghost-racen."
                        )
                )
                .disabled(
                    ownParticipant?.ready ==
                        true ||
                    isLaunching
                )
            }
        }
    }

    private var readyCard: some View {
        ATHLTHCard {
            VStack(
                alignment: .leading,
                spacing: 12
            ) {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Ready means you consent to share your live race position with this opponent for this race.",
                        norwegian:
                            "Når du markerer deg klar, samtykker du til å dele live-posisjonen din med motstanderen i akkurat denne racen."
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )

                Button {
                    Task {
                        await toggleReady()
                    }
                } label: {
                    HStack {
                        if liveRace
                            .isChangingReady {
                            ProgressView()
                        } else {
                            Image(
                                systemName:
                                    ownParticipant?
                                        .ready ==
                                    true
                                        ? "xmark.circle"
                                        : "checkmark.circle.fill"
                            )
                        }

                        Text(
                            ownParticipant?
                                .ready ==
                            true
                                ? ATHLTHLocalization.choose(
                                    english:
                                        "I'm not ready",
                                    norwegian:
                                        "Jeg er ikke klar"
                                )
                                : ATHLTHLocalization.choose(
                                    english:
                                        "I'm ready",
                                    norwegian:
                                        "Jeg er klar"
                                )
                        )
                        .font(.headline)

                        Spacer()
                    }
                    .frame(height: 48)
                }
                .buttonStyle(
                    .borderedProminent
                )
                .tint(
                    ownParticipant?.ready ==
                        true
                        ? Color.secondary
                        : ATHLTHTheme.vitality
                )
                .disabled(
                    liveRace.isChangingReady ||
                    isLaunching ||
                    (ownParticipant?.ready != true && !deviceCanStart)
                )
            }
        }
    }

    private var spectatorCard: some View {
        ATHLTHCard {
            HStack(
                alignment: .top,
                spacing: 12
            ) {
                Image(
                    systemName:
                        "ipad.and.iphone"
                )
                .font(.title2)
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )

                VStack(
                    alignment: .leading,
                    spacing: 4
                ) {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Spectator mode",
                            norwegian:
                                "Tilskuermodus"
                        )
                    )
                    .font(.headline)

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "iPad follows the lobby, countdown, live map and result. The workout itself stays on iPhone or Apple Watch.",
                            norwegian:
                                "iPad følger lobby, nedtelling, livekart og resultat. Selve økten kjøres fortsatt på iPhone eller Apple Watch."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var phaseCard: some View {
        TimelineView(
            .periodic(
                from: Date(),
                by: 0.25
            )
        ) { context in
            let phase =
                liveRace.phase(
                    at: context.date
                )

            ATHLTHCard {
                VStack(
                    spacing: 10
                ) {
                    phaseIcon(phase)

                    Text(
                        phaseTitle(phase)
                    )
                    .font(
                        .title2.weight(.bold)
                    )
                    .multilineTextAlignment(
                        .center
                    )

                    if let subtitle =
                            phaseSubtitle(
                                phase
                            ) {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(
                                ATHLTHTheme
                                    .mutedText
                            )
                            .multilineTextAlignment(
                                .center
                            )
                    }
                }
                .frame(
                    maxWidth: .infinity
                )
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func phaseIcon(
        _ phase: LiveGhostRacePhase
    ) -> some View {
        switch phase {
        case .countdown(let seconds):
            Text("\(seconds)")
                .font(
                    .system(
                        size: 50,
                        weight: .black,
                        design: .rounded
                    )
                )
                .monospacedDigit()
                .foregroundStyle(
                    ATHLTHTheme.vitality
                )

        case .racing:
            Image(
                systemName:
                    "flag.checkered"
            )
            .font(.system(size: 38))
            .foregroundStyle(
                ATHLTHTheme.vitality
            )

        case .finished:
            Image(
                systemName:
                    "trophy.fill"
            )
            .font(.system(size: 38))
            .foregroundStyle(
                ATHLTHTheme.premiumGold
            )

        case .cancelled:
            Image(
                systemName:
                    "xmark.circle"
            )
            .font(.system(size: 38))
            .foregroundStyle(.secondary)

        case .lobby:
            Image(
                systemName:
                    "person.2.fill"
            )
            .font(.system(size: 34))
            .foregroundStyle(
                ATHLTHTheme.accentDeep
            )
        }
    }

    @ViewBuilder
    private var resultCard: some View {
        ATHLTHCard {
            VStack(
                alignment: .leading,
                spacing: 14
            ) {
                sectionTitle(
                    ATHLTHLocalization.choose(
                        english: "Result",
                        norwegian: "Resultat"
                    )
                )

                Text(resultTitle)
                    .font(
                        .title2.weight(.bold)
                    )

                Label(
                    challenge.arenaRoundID != nil
                        ? ATHLTHLocalization.choose(
                            english: "Provisional live times. Review and approve the Arena round separately; points are never awarded automatically.",
                            norwegian: "Foreløpige live-tider. Resultatet må godkjennes separat i Arena; poeng tildeles aldri automatisk."
                        )
                        : ATHLTHLocalization.choose(
                            english: "Reported live times, not independently verified race results.",
                            norwegian: "Oppgitte live-tider, ikke uavhengig verifiserte løpsresultater."
                        ),
                    systemImage: resultCandidate == nil
                        ? "exclamationmark.triangle" : "info.circle"
                )
                .font(.caption)
                .foregroundStyle(resultCandidate == nil
                    ? .orange : ATHLTHTheme.mutedText)

                HStack(spacing: 10) {
                    resultMetric(
                        title:
                            ATHLTHLocalization.choose(
                                english: "Your time",
                                norwegian: "Din tid"
                            ),
                        value:
                            resultTime(
                                ownParticipant?
                                    .elapsedSeconds
                            )
                    )

                    resultMetric(
                        title:
                            displayName(
                                opponentID
                            ),
                        value:
                            resultTime(
                                opponentParticipant?
                                    .elapsedSeconds
                            )
                    )

                    resultMetric(
                        title:
                            ATHLTHLocalization.choose(
                                english: "Margin",
                                norwegian: "Margin"
                            ),
                        value:
                            resultMargin
                    )
                }

                HStack(spacing: 10) {
                    resultMetric(
                        title:
                            ATHLTHLocalization.choose(
                                english: "Best lead",
                                norwegian:
                                    "Største ledelse"
                            ),
                        value:
                            String(
                                format:
                                    "%.0f m",
                                ownMaximumLead
                            )
                    )

                    resultMetric(
                        title:
                            ATHLTHLocalization.choose(
                                english:
                                    "Largest deficit",
                                norwegian:
                                    "Største etterslep"
                            ),
                        value:
                            String(
                                format:
                                    "%.0f m",
                                opponentMaximumLead
                            )
                    )

                    resultMetric(
                        title:
                            ATHLTHLocalization.choose(
                                english:
                                    "Lead changes",
                                norwegian:
                                    "Lederskifter"
                            ),
                        value:
                            "\(liveRace.room?.leadChangeCount ?? 0)"
                    )
                }

                Button {
                    Task {
                        rematchSent =
                            await friendRaces
                                .rematch(
                                    challenge
                                )
                    }
                } label: {
                    Label(
                        rematchSent
                            ? ATHLTHLocalization.choose(
                                english:
                                    "Rematch sent",
                                norwegian:
                                    "Ny utfordring sendt"
                            )
                            : ATHLTHLocalization.choose(
                                english: "Rematch",
                                norwegian:
                                    "Kjør igjen"
                            ),
                        systemImage:
                            rematchSent
                                ? "checkmark"
                                : "arrow.counterclockwise"
                    )
                    .font(.headline)
                    .frame(
                        maxWidth: .infinity
                    )
                    .frame(height: 48)
                }
                .buttonStyle(
                    .borderedProminent
                )
                .tint(
                    ATHLTHTheme.accentDeep
                )
                .disabled(rematchSent)
            }
        }
    }

    private var pendingFinishCard: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Your finish has been recorded",
                        norwegian: "Din sluttid er registrert"
                    ),
                    systemImage: "checkmark.circle.fill"
                )
                .font(.headline)
                .foregroundStyle(ATHLTHTheme.accentDeep)

                HStack {
                    Text(ATHLTHLocalization.choose(
                        english: "Your reported time",
                        norwegian: "Din oppgitte tid"
                    ))
                    .font(.subheadline)
                    Spacer()
                    Text(resultTime(ownParticipant?.elapsedSeconds))
                        .font(.headline.monospacedDigit())
                }
                Text(opponentParticipant?.finishedAt == nil
                    ? ATHLTHLocalization.choose(
                        english: "Waiting for the other athlete. No winner is declared until both finishes are recorded.",
                        norwegian: "Venter på motstanderen. Ingen vinner blir kåret før begge sluttider er registrert."
                    )
                    : ATHLTHLocalization.choose(
                        english: "Both athletes have reported a finish. Waiting for the shared result to be finalized.",
                        norwegian: "Begge har rapportert målgang. Venter på at fellesresultatet blir ferdigstilt."
                    ))
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
            }
        }
    }

    private var deviceCanStart: Bool {
        switch captureDevice {
        case .iPhone:
            return phoneWorkout.active == nil &&
                !watchConnection.hasActiveWatchWorkout &&
                !watchConnection.workoutLaunchInProgress

        case .appleWatch:
            return watchConnection.isReady &&
                !watchConnection.workoutLaunchInProgress &&
                !watchConnection.hasActiveWatchWorkout &&
                phoneWorkout.active == nil &&
                !watchConnection.hasActiveIPhoneWorkout
        }
    }

    @MainActor
    private func toggleReady() async {
        guard !ATHLTHDeviceRole.isIPad
        else {
            return
        }

        let next =
            !(ownParticipant?.ready ??
                false)

        if next && !deviceCanStart {
            launchError = ATHLTHLocalization.choose(
                english: "Finish the active workout or connect the selected device before marking ready.",
                norwegian: "Avslutt den aktive økten eller koble til valgt enhet før du markerer deg klar."
            )
            return
        }

        await liveRace.setReady(
            next,
            captureDevice:
                captureDevice
        )
    }

    @MainActor
    private func waitForSynchronizedStart()
        async {
        guard
            !ATHLTHDeviceRole.isIPad,
            scenePhase == .active,
            !didLaunch,
            ownParticipant?.ready ==
                true,
            let startsAt =
                liveRace.room?
                    .startsAt
        else {
            return
        }

        let delay =
            startsAt.timeIntervalSince(
                Date()
            )

        // Do not silently launch a stale race after the app resumes late.
        if delay < -15 {
            launchError = ATHLTHLocalization.choose(
                english: "This countdown has already passed. Rejoin the live duel instead of starting late.",
                norwegian: "Nedtellingen er allerede passert. Gå tilbake til live-duellen i stedet for å starte for sent."
            )
            return
        }

        if delay > 0 {
            try? await Task.sleep(
                for: .seconds(delay)
            )
        }

        guard
            !Task.isCancelled,
            scenePhase == .active,
            !didLaunch,
            ownParticipant?.ready == true,
            liveRace.participant(userID: opponentID)?.ready == true,
            liveRace.room?.phase() == .racing
        else {
            return
        }

        await launchLiveRace()
    }

    @MainActor
    private func launchLiveRace() async {
        guard !didLaunch, !isLaunching else { return }
        guard deviceCanStart else {
            launchError = ATHLTHLocalization.choose(
                english: "The selected device became unavailable. Your readiness was reset to prevent a duplicate workout.",
                norwegian: "Valgt enhet er ikke lenger klar. Klarstatusen ble nullstilt for å hindre doble treningsøkter."
            )
            await liveRace.setReady(false, captureDevice: captureDevice)
            return
        }

        isLaunching = true
        launchError = nil
        defer {
            isLaunching = false
        }

        do {
            // A temporary builder converts the shared challenge route into the
            // same route representation used by normal running workouts.
            let builder =
                GhostRaceStore()
            try builder.prepare(
                reference:
                    challenge.reference()
            )

            let route =
                builder.temporaryRoute(
                    ownerID:
                        currentUserID,
                    title:
                        challenge.title,
                    comparisonRouteID:
                        challenge.id
                )

            try await GhostRaceStartService
                .startLive(
                    title:
                        challenge.title,
                    route: route,
                    ghostRace:
                        ghostRace,
                    watchConnection:
                        watchConnection,
                    phoneWorkout:
                        phoneWorkout,
                    captureDevice:
                        captureDevice,
                    settings:
                        settings
                )

            guard let liveSession =
                    await realtime
                        .beginGhostSession(
                            challenge:
                                challenge
                        )
            else {
                throw NSError(
                    domain:
                        "ATHLTH.LiveGhost",
                    code: 2,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            ATHLTHLocalization.choose(
                                english:
                                    "The race started, but ATHLTH could not connect the shared Live Ghost session.",
                                norwegian:
                                    "Racen startet, men ATHLTH klarte ikke å koble til den delte Live Ghost-sesjonen."
                            )
                    ]
                )
            }

            await realtime
                .refreshVisibleLiveSessions(
                    force: true
                )
            realtime.selectLiveGhost(
                liveSession
            )

            // Touching the ready row after the synchronized start lets the
            // server promote countdown -> racing atomically.
            await liveRace.setReady(
                true,
                captureDevice:
                    captureDevice
            )

            didLaunch = true
        } catch {
            launchError =
                error.localizedDescription
        }
    }

    private func displayName(
        _ userID: UUID
    ) -> String {
        if userID ==
            currentUserID {
            return ATHLTHLocalization.choose(
                english: "You",
                norwegian: "Du"
            )
        }

        return social.visibleProfiles
            .first {
                $0.userID == userID
            }?
            .resolvedName ??
        social.following
            .first {
                $0.userID == userID
            }?
            .resolvedName ??
        "ATHLTH Athlete"
    }

    private func participantSubtitle(
        _ participant:
            LiveGhostRaceParticipantRecord?
    ) -> String {
        guard let participant else {
            return ATHLTHLocalization.choose(
                english:
                    "Not in lobby yet",
                norwegian:
                    "Ikke i lobbyen ennå"
            )
        }

        guard participant.ready
        else {
            return ATHLTHLocalization.choose(
                english:
                    "Choosing race device",
                norwegian:
                    "Velger race-enhet"
            )
        }

        switch participant.deviceType {
        case "apple_watch":
            return "Apple Watch"
        case "iphone":
            return "iPhone"
        default:
            return ATHLTHLocalization.choose(
                english: "Ready",
                norwegian: "Klar"
            )
        }
    }

    private func phaseTitle(
        _ phase: LiveGhostRacePhase
    ) -> String {
        switch phase {
        case .lobby:
            return ATHLTHLocalization.choose(
                english:
                    "Waiting for both athletes",
                norwegian:
                    "Venter på begge"
            )

        case .countdown:
            return ATHLTHLocalization.choose(
                english: "Get ready",
                norwegian: "Gjør deg klar"
            )

        case .racing:
            return ATHLTHLocalization.choose(
                english: "GO!",
                norwegian: "KJØR!"
            )

        case .finished:
            return ATHLTHLocalization.choose(
                english: "Race finished",
                norwegian: "Race fullført"
            )

        case .cancelled:
            return ATHLTHLocalization.choose(
                english: "Race cancelled",
                norwegian: "Race avbrutt"
            )
        }
    }

    private func phaseSubtitle(
        _ phase: LiveGhostRacePhase
    ) -> String? {
        switch phase {
        case .lobby:
            return ATHLTHLocalization.choose(
                english:
                    "The countdown begins automatically when both are ready.",
                norwegian:
                    "Nedtellingen starter automatisk når begge er klare."
            )

        case .countdown:
            return ATHLTHLocalization.choose(
                english:
                    "Both devices use the same server start time.",
                norwegian:
                    "Begge enheter bruker samme starttid fra serveren."
            )

        case .racing:
            return ATHLTHDeviceRole.isIPad
                ? ATHLTHLocalization.choose(
                    english:
                        "Follow both runners live from iPad.",
                    norwegian:
                        "Følg begge løperne live fra iPad."
                )
                : ATHLTHLocalization.choose(
                    english:
                        "Your Live Ghost workout is starting.",
                    norwegian:
                        "Live Ghost-økten starter."
                )

        case .finished,
             .cancelled:
            return nil
        }
    }

    private var ownMaximumLead: Double {
        guard let room =
                liveRace.room
        else {
            return 0
        }

        return currentUserID ==
            challenge.senderID
            ? room.senderMaxLeadMeters
            : room.recipientMaxLeadMeters
    }

    private var opponentMaximumLead: Double {
        guard let room =
                liveRace.room
        else {
            return 0
        }

        return currentUserID ==
            challenge.senderID
            ? room.recipientMaxLeadMeters
            : room.senderMaxLeadMeters
    }

    /// A missing, contradictory or malformed finish is never displayed as
    /// a win or tie. The Arena result review uses the same common validator.
    private var resultCandidate: ATHLTHArenaLiveDuelCandidate? {
        ATHLTHArenaLiveDuelReview.candidate(
            senderID: challenge.senderID,
            recipientID: challenge.recipientID,
            senderSeconds: liveRace.participant(userID: challenge.senderID)?.elapsedSeconds,
            recipientSeconds: liveRace.participant(userID: challenge.recipientID)?.elapsedSeconds,
            reportedWinnerID: liveRace.room?.winnerID,
            isFinished: liveRace.room?.status == .finished
        )
    }

    private var resultTitle: String {
        guard let candidate = resultCandidate else {
            return ATHLTHLocalization.choose(
                english: "Result requires review",
                norwegian: "Resultatet må kontrolleres"
            )
        }

        guard let winnerID = candidate.winnerID else {
            return ATHLTHLocalization.choose(
                english: "It's a tie",
                norwegian: "Uavgjort"
            )
        }

        if winnerID == currentUserID {
            return ATHLTHLocalization.choose(
                english: "You won",
                norwegian: "Du vant"
            )
        }

        return ATHLTHLocalization.format(
            english: "%@ won",
            norwegian: "%@ vant",
            displayName(winnerID)
        )
    }

    private var resultMargin: String {
        guard let candidate = resultCandidate else {
            return "—"
        }
        if candidate.marginSeconds < 0.5 {
            return "0.0 s"
        }
        return String(format: "%.1f s", candidate.marginSeconds)
    }

    private func resultTime(
        _ seconds: TimeInterval?
    ) -> String {
        guard let seconds,
              seconds.isFinite,
              (60...86_400).contains(seconds) else {
            return "—"
        }

        let total =
            max(
                Int(seconds.rounded()),
                0
            )
        let hours = total / 3_600
        let minutes =
            (total % 3_600) / 60
        let remainder = total % 60

        if hours > 0 {
            return String(
                format:
                    "%d:%02d:%02d",
                hours,
                minutes,
                remainder
            )
        }

        return String(
            format:
                "%d:%02d",
            minutes,
            remainder
        )
    }

    private func resultMetric(
        title: String,
        value: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 3
        ) {
            Text(value)
                .font(
                    .subheadline
                        .weight(.bold)
                )
                .monospacedDigit()

            Text(title)
                .font(.caption2)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
    }

    private func sectionTitle(
        _ title: String
    ) -> some View {
        Text(title.uppercased())
            .font(
                .caption2.weight(.bold)
            )
            .tracking(1.2)
            .foregroundStyle(
                ATHLTHTheme.mutedText
            )
    }
}

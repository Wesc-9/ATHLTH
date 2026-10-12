import SwiftUI
import Supabase

/// A linked Arena round is resolved separately and respects both tables' RLS.
private struct LiveGhostArenaRoundLink: Decodable {
    let seriesID: UUID
    enum CodingKeys: String, CodingKey {
        case seriesID = "series_id"
    }
}

/// A countdown can arrive before a participant's READY update; re-arm
/// the launch task whenever either readiness state changes.
private struct LiveGhostStartTrigger: Equatable {
    let startsAt: Date?
    let status: LiveGhostRaceRoomStatus?
    let ownReady: Bool
    let opponentReady: Bool
}

struct LiveGhostRaceLobbyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var phoneWorkout: IPhoneWorkoutStore
    @EnvironmentObject private var mirroring: WorkoutMirroringStore
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
    @State private var isConnectingLiveSession = false
    @State private var lastAutoWatchReconnectAt: Date?
    @State private var rematchSent = false
    @State private var confirmCancelDuel = false
    @State private var accessibleArenaSeries: ATHLTHArenaRemoteSeries?

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

                if !ATHLTHDeviceRole.isIPad,
                   ownParticipant != nil,
                   let room = liveRace.room,
                   room.status == .lobby ||
                   room.status == .countdown ||
                   room.status == .racing {
                    Button(role: .destructive) {
                        confirmCancelDuel = true
                    } label: {
                        if liveRace.isCancelling {
                            ProgressView()
                        } else {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Leave synchronized duel",
                                    norwegian: "Avbryt synkronisert duell"
                                ),
                                systemImage: "xmark.circle"
                            )
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(liveRace.isCancelling)
                    .accessibilityHint(ATHLTHLocalization.choose(
                        english: "Cancels the shared duel, not your local workout.",
                        norwegian: "Avlyser fellesduellen, men avslutter ikke din lokale treningsøkt."
                    ))
                }

                if (didLaunch || canReconnectRecoveredPhoneRace ||
                    canReconnectRecoveredWatchRace) &&
                   LiveGhostRaceReentry.canReconnectSharedSession(
                       roomStatus: liveRace.room?.status
                   ) &&
                   realtime.currentSession?.ghostChallengeID != challenge.id {
                    ATHLTHCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Workout started – live connection pending",
                                    norwegian: "Økten er startet – live-tilkobling mangler"
                                ),
                                systemImage: "wifi.exclamationmark"
                            )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)

                            Text(ATHLTHLocalization.choose(
                                english: "Keep your ongoing workout. Reconnect Live Ghost without starting a second recording.",
                                norwegian: "Behold treningsøkten som allerede går. Koble Live Ghost til på nytt uten å starte en ny registrering."
                            ))
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)

                            Button {
                                Task { await connectLiveSession() }
                            } label: {
                                if isConnectingLiveSession {
                                    ProgressView()
                                } else {
                                    Label(
                                        ATHLTHLocalization.choose(
                                            english: "Reconnect Live Ghost",
                                            norwegian: "Koble til Live Ghost igjen"
                                        ),
                                        systemImage: "arrow.clockwise"
                                    )
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(ATHLTHTheme.accentDeep)
                            .disabled(isConnectingLiveSession)
                        }
                    }
                }

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
                    if let accessibleArenaSeries {
                        NavigationLink {
                            ATHLTHArenaOnlineDetailView(series: accessibleArenaSeries)
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Review result in Arena",
                                    norwegian: "Se og godkjenn resultatet i Arena"
                                ),
                                systemImage: "checkmark.shield.fill"
                            )
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ATHLTHTheme.accentDeep)
                        .accessibilityHint(ATHLTHLocalization.choose(
                            english: "Opens the linked competition. Points still require participant approval.",
                            norwegian: "Åpner den tilknyttede konkurransen. Poeng krever fortsatt godkjenning fra deltakerne."
                        ))
                    }
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
            guard !Task.isCancelled else { return }
            // A recovered iPhone workout for this exact duel may reconnect
            // to its shared location session without starting HealthKit again.
            if canReconnectRecoveredPhoneRace || canReconnectRecoveredWatchRace {
                await connectLiveSession()
            }
        }
        .task(id: challenge.arenaRoundID) {
            await resolveAccessibleArenaSeries()
        }
        .task(id: LiveGhostStartTrigger(
            startsAt: liveRace.room?.startsAt,
            status: liveRace.room?.status,
            ownReady: ownParticipant?.ready == true,
            opponentReady: opponentParticipant?.ready == true
        )) {
            await waitForSynchronizedStart()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await liveRace.refresh(challengeID: challenge.id)
                if canReconnectRecoveredPhoneRace || canReconnectRecoveredWatchRace {
                    await connectLiveSession()
                }
                await waitForSynchronizedStart()
            }
        }
        .onChange(of: mirroring.snapshot?.capturedAt) { _, _ in
            // A recovering Watch can deliver dozens of snapshots quickly.
            // Retry the shared connection at most once per 20 seconds, and
            // only while this scene is active; never start another workout.
            guard scenePhase == .active,
                  canReconnectRecoveredWatchRace,
                  !isConnectingLiveSession,
                  realtime.currentSession?.ghostChallengeID != challenge.id
            else { return }
            let now = Date()
            if let lastAutoWatchReconnectAt,
               now.timeIntervalSince(lastAutoWatchReconnectAt) < 20 {
                return
            }
            lastAutoWatchReconnectAt = now
            Task { await connectLiveSession() }
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
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english: "Cancel the synchronized duel?",
                norwegian: "Avbryte den synkroniserte duellen?"
            ),
            isPresented: $confirmCancelDuel,
            titleVisibility: .visible
        ) {
            Button(
                ATHLTHLocalization.choose(
                    english: "Cancel duel", norwegian: "Avbryt duell"
                ),
                role: .destructive
            ) {
                Task {
                    let cancelled = await liveRace.cancelDuel()
                    if cancelled,
                       realtime.currentSession?.ghostChallengeID == challenge.id {
                        await realtime.setCurrentLiveLocationSharing(false)
                    }
                }
            }
            Button(
                ATHLTHLocalization.choose(
                    english: "Continue race", norwegian: "Fortsett duellen"
                ),
                role: .cancel
            ) {}
        } message: {
            Text(ATHLTHLocalization.choose(
                english: "This ends the shared race without declaring a winner or awarding Arena points. Your current iPhone or Apple Watch workout is not ended.",
                norwegian: "Fellesduellen avlyses uten vinner eller Arena-poeng. En pågående treningsøkt på iPhone eller Apple Watch avsluttes ikke."
            ))
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Label(
                    "LIVE GHOST",
                    systemImage: "dot.radiowaves.left.and.right"
                )
                .font(.caption.weight(.bold))
                .tracking(0.9)
                .foregroundStyle(.white.opacity(0.94))

                Spacer(minLength: 5)

                Text(String(format: "%.1f km", challenge.distanceMeters / 1_000))
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(.white.opacity(0.15), in: Capsule())
            }

            Text(challenge.title)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Label(
                challenge.sourceKind == "planned_route"
                    ? ATHLTHLocalization.choose(
                        english: "Planned route · synchronized start",
                        norwegian: "Planlagt rute · synkronisert start"
                    )
                    : ATHLTHLocalization.choose(
                        english: "Previous GPS run · synchronized start",
                        norwegian: "Tidligere GPS-økt · synkronisert start"
                    ),
                systemImage: challenge.sourceKind == "planned_route"
                    ? "map.fill" : "figure.run"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.95))
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(.white.opacity(0.12), in: Capsule())

            Rectangle()
                .fill(.white.opacity(0.17))
                .frame(height: 1)
                .accessibilityHidden(true)

            Text(
                ATHLTHLocalization.choose(
                    english: "Both athletes enter the same race lobby. Once both are ready, ATHLTH starts a single synchronized countdown.",
                    norwegian: "Begge utøverne møtes i samme lobby. Når begge er klare, starter ATHLTH én felles nedtelling."
                )
            )
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.86))
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ATHLTHArenaLightStyle.heroSurface(24))
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
                by: 1
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
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)
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

                HStack(spacing: 12) {
                    Image(systemName: resultCandidate == nil
                        ? "exclamationmark.shield.fill"
                        : resultCandidate?.winnerID == nil
                            ? "equal.circle.fill"
                            : "trophy.fill"
                    )
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(resultCandidate == nil
                        ? .orange : ATHLTHTheme.accentDeep)
                    .frame(width: 46, height: 46)
                    .background(
                        ATHLTHTheme.vitalitySoft.opacity(0.56),
                        in: Circle()
                    )
                    Text(resultTitle)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                }

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

                LazyVGrid(columns: resultMetricColumns, spacing: 9) {
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

                LazyVGrid(columns: resultMetricColumns, spacing: 9) {
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

    /// Recover only this duel's already-running iPhone workout. Merely
    /// reopening the lobby must never initiate another recording.
    private var canReconnectRecoveredPhoneRace: Bool {
        LiveGhostRaceReentry.canReconnectPhoneWorkout(
            comparisonRouteID: phoneWorkout.active?.plannedComparisonRouteID,
            challengeID: challenge.id,
            roomStatus: liveRace.room?.status
        )
    }

    private var canReconnectRecoveredWatchRace: Bool {
        guard let snapshot = mirroring.snapshot,
              phoneWorkout.active == nil else { return false }
        return LiveGhostRaceReentry.canReconnectWatchWorkout(
            comparisonRouteID: snapshot.routeComparisonID,
            challengeID: challenge.id,
            roomStatus: liveRace.room?.status,
            mirroredWorkoutActive: mirroring.hasActiveMirroredWorkout,
            isRunningOrPaused: snapshot.state == .running || snapshot.state == .paused,
            snapshotAgeSeconds: Date().timeIntervalSince(snapshot.capturedAt)
        )
    }

    private var deviceCanStart: Bool {
        switch captureDevice {
        case .iPhone:
            return phoneWorkout.active == nil &&
                phoneWorkout.canStartSynchronizedOutdoorWorkout &&
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

    /// No fallback by title or club membership is allowed: only the exact
    /// database-linked round can open the result review destination.
    @MainActor
    private func resolveAccessibleArenaSeries() async {
        accessibleArenaSeries = nil
        guard let roundID = challenge.arenaRoundID else { return }
        do {
            let round: LiveGhostArenaRoundLink = try await SupabaseEnvironment.client
                .from("arena_round_proposals")
                .select("series_id")
                .eq("id", value: roundID)
                .single()
                .execute().value
            let series: ATHLTHArenaRemoteSeries = try await SupabaseEnvironment.client
                .from("arena_series")
                .select()
                .eq("id", value: round.seriesID)
                .single()
                .execute().value
            guard !Task.isCancelled else { return }
            accessibleArenaSeries = series
        } catch {
            // Both tables are RLS protected; a deleted or inaccessible link
            // must never become a navigation destination.
            accessibleArenaSeries = nil
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
            if captureDevice == .iPhone &&
               !phoneWorkout.canStartSynchronizedOutdoorWorkout {
                phoneWorkout.requestLiveGhostLocationPermissionIfNeeded()
                launchError = ATHLTHLocalization.choose(
                    english: "Allow iPhone location access and make sure you are signed in before marking ready. Then tap Ready again.",
                    norwegian: "Tillat stedstilgang på iPhone og kontroller at du er logget inn før du markerer deg klar. Trykk deretter Klar på nytt."
                )
            } else {
                launchError = ATHLTHLocalization.choose(
                    english: "Finish the active workout or connect the selected device before marking ready.",
                    norwegian: "Avslutt den aktive økten eller koble til valgt enhet før du markerer deg klar."
                )
            }
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
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                // A READY or room-state change has superseded this timer.
                return
            }
        }

        guard !Task.isCancelled,
              scenePhase == .active,
              !didLaunch,
              !isLaunching else { return }

        // Validate the race immediately before starting HealthKit/Watch.
        // Two participant snapshots from a realtime socket can be stale
        // when the other athlete withdraws during the final second.
        let confirmed = await liveRace.confirmSynchronizedStart(
            challengeID: challenge.id,
            senderID: challenge.senderID,
            recipientID: challenge.recipientID
        )
        guard !Task.isCancelled,
              scenePhase == .active,
              !didLaunch else { return }
        guard confirmed else {
            launchError = ATHLTHLocalization.choose(
                english: "The race start changed or could not be verified. Check both athletes are ready before trying again. No workout was started.",
                norwegian: "Starten ble endret eller kunne ikke bekreftes. Kontroller at begge er klare før du prøver igjen. Ingen treningsøkt ble startet."
            )
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

            // The local workout is authoritative. Mark it as started
            // immediately: a transient network failure must never cause a
            // second iPhone/Watch workout to be launched.
            didLaunch = true
            await connectLiveSession()
        } catch {
            launchError = error.localizedDescription
        }
    }

    @MainActor
    private func connectLiveSession() async {
        guard didLaunch || canReconnectRecoveredPhoneRace ||
                  canReconnectRecoveredWatchRace,
              LiveGhostRaceReentry.canReconnectSharedSession(
                  roomStatus: liveRace.room?.status
              ),
              !isConnectingLiveSession,
              realtime.currentSession?.ghostChallengeID != challenge.id else {
            return
        }

        isConnectingLiveSession = true
        defer { isConnectingLiveSession = false }

        guard let liveSession = await realtime.beginGhostSession(
            challenge: challenge
        ) else {
            launchError = ATHLTHLocalization.choose(
                english: "Your workout is still running, but the shared Live Ghost session could not connect. Use 'Reconnect Live Ghost' to retry without starting another workout.",
                norwegian: "Treningsøkten fortsetter, men den delte Live Ghost-sesjonen kunne ikke kobles til. Bruk «Koble til Live Ghost igjen» for å prøve uten å starte en ny økt."
            )
            return
        }

        await realtime.refreshVisibleLiveSessions(force: true)
        realtime.selectLiveGhost(liveSession)
        launchError = nil

        // Touching the ready row after start allows the server to promote
        // the shared countdown to racing without changing the local workout.
        await liveRace.setReady(
            true,
            captureDevice: captureDevice
        )
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

    private var resultMetricColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        let count = horizontalSizeClass == .regular ? 3 : 2
        return (0..<count).map { _ in GridItem(.flexible(), spacing: 9) }
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
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(11)
        .background(
            ATHLTHTheme.accentDeep.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
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

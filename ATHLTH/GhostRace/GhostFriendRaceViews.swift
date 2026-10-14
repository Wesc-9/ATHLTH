import SwiftUI

private enum GhostFriendCourseMode: String, CaseIterable, Identifiable {
    case previousWorkout
    case plannedRoute

    var id: String { rawValue }

    var title: String {
        switch self {
        case .previousWorkout:
            return ATHLTHLocalization.choose(
                english: "Previous run", norwegian: "Tidligere økt"
            )
        case .plannedRoute:
            return ATHLTHLocalization.choose(
                english: "Planned route", norwegian: "Velg rute"
            )
        }
    }
}

private enum GhostInvitationStep: Int {
    case friend
    case reference
    case confirm

    var number: Int { rawValue + 1 }
}

struct GhostFriendRaceHubView: View {
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var phoneWorkout: IPhoneWorkoutStore
    @EnvironmentObject private var ghostRace: GhostRaceStore
    @EnvironmentObject private var realtime: ATHLTHRealtimeSocialStore

    @StateObject private var friendRaces =
        GhostFriendRaceStore()

    @State private var runs: [WorkoutSummary] = []
    @State private var unverifiedRuns: [WorkoutSummary] = []
    @State private var checkedRunCount = 0
    @State private var selectedFriendID: UUID?
    @State private var selectedWorkoutID: UUID?
    @State private var selectedPlannedRoute: TrainingRoute?
    @State private var courseMode: GhostFriendCourseMode = .previousWorkout
    @State private var targetTimeText = "40:00"
    @State private var showingInviteComposer = false
    @State private var inviteStep: GhostInvitationStep = .friend
    @State private var friendSearch = ""
    @State private var showSentConfirmation = false
    @State private var didAutoOpenInvitation = false
    @AppStorage("athlth.ghostRace.live.advancedMode")
    private var advancedMode = false
    @State private var showingRoutePicker = false
    @State private var loadingRuns = false
    @State private var sending = false
    @State private var startingChallengeID: UUID?
    @State private var localError: String?
    @State private var captureDevice:
        WorkoutCaptureDevice = .iPhone
    private let arenaRoundID: UUID?
    private let agreedArenaRouteID: UUID?
    private let openInvitationOnAppear: Bool

    /// Opening a duel from an active Arena 1v1 series can suggest its
    /// opponent; the existing mutual-follow and permission checks remain.
    init(
        preferredFriendID: UUID? = nil,
        preferredRoute: TrainingRoute? = nil,
        arenaRoundID: UUID? = nil,
        openInvitationOnAppear: Bool = false
    ) {
        self.openInvitationOnAppear = openInvitationOnAppear
        self.arenaRoundID = arenaRoundID
        self.agreedArenaRouteID = arenaRoundID == nil ? nil : preferredRoute?.id
        _selectedFriendID = State(initialValue: preferredFriendID)
        _selectedPlannedRoute = State(initialValue: preferredRoute)
        _courseMode = State(initialValue: preferredRoute == nil
            ? .previousWorkout : .plannedRoute)
        if let preferredRoute {
            let suggestion = preferredRoute.expectedTravelTimeSeconds ??
                max(preferredRoute.distanceKilometers * 330, 300)
            _targetTimeText = State(initialValue:
                GhostTargetTimeFormatter.string(suggestion))
        }
    }

    private var targetTime: TimeInterval? {
        guard let seconds = GhostTargetTimeFormatter.parse(targetTimeText),
              seconds.isFinite, (60...86_400).contains(seconds) else {
            return nil
        }
        return seconds
    }

    private var canSendSelectedCourse: Bool {
        switch courseMode {
        case .previousWorkout:
            return runs.contains { $0.id == selectedWorkoutID }
        case .plannedRoute: return selectedPlannedRoute != nil && targetTime != nil
        }
    }

    /// Only a matching planned course is linked to the existing Arena round.
    /// A prior GPS run is a valid standalone duel, not automatically the
    /// same course as the one agreed in the competition.
    private var eligibleArenaRoundID: UUID? {
        GhostFriendRaceArenaLinkPolicy.eligibleRoundID(
            roundID: arenaRoundID,
            agreedRouteID: agreedArenaRouteID,
            selectedRouteID: selectedPlannedRoute?.id,
            isPlannedRoute: courseMode == .plannedRoute
        )
    }

    // A premium landing page keeps received and sent races visible,
    // while creation happens in a short, focused invitation flow.
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                friendIntroCard

                if showSentConfirmation {
                    Label(ATHLTHLocalization.choose(
                        english: "Invitation sent. Waiting for your friend to accept.",
                        norwegian: "Invitasjonen er sendt. Venter på svar fra vennen din."
                    ), systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(ATHLTHTheme.accentSoft,
                                in: RoundedRectangle(cornerRadius: 15))
                }

                Button {
                    inviteStep = selectedFriendID == nil ? .friend : .reference
                    friendSearch = ""
                    showSentConfirmation = false
                    showingInviteComposer = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.badge.plus")
                            .font(.title3.weight(.semibold))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ATHLTHLocalization.choose(
                                english: "Invite a friend",
                                norwegian: "Inviter en venn"
                            ))
                            .font(.headline)
                            Text(ATHLTHLocalization.choose(
                                english: "Choose a friend and a Ghost reference",
                                norwegian: "Velg en venn og et løpegrunnlag"
                            ))
                            .font(.caption)
                            .opacity(0.84)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "arrow.right")
                            .font(.headline)
                    }
                    .foregroundStyle(.white)
                    .padding(18)
                    .frame(maxWidth: .infinity, minHeight: 76)
                    .background(ATHLTHTheme.accentDeep,
                                in: RoundedRectangle(cornerRadius: 20))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                invitationsOverview

                if advancedMode {
                    ATHLTHCard { privacyCard }
                }
            }
            .padding(16)
            .padding(.bottom, 32)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(ATHLTHPremiumCanvas(
            accent: ATHLTHTheme.vitality.opacity(0.13)
        ))
        .navigationTitle(ATHLTHLocalization.choose(
            english: "Live Ghost duel", norwegian: "Live Ghost-duell"
        ))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingInviteComposer) {
            invitationComposer
        }
        .task {
            if openInvitationOnAppear && !didAutoOpenInvitation {
                didAutoOpenInvitation = true
                inviteStep = selectedFriendID == nil ? .friend : .reference
                showingInviteComposer = true
            }
            await social.refresh()
            await friendRaces.refresh()
            await realtime.refreshOnlineUsers()
            await realtime.refreshVisibleLiveSessions()
            await loadRuns()
        }
        .refreshable {
            await social.refresh()
            await friendRaces.refresh()
            await realtime.refreshOnlineUsers()
            await realtime.refreshVisibleLiveSessions()
            await loadRuns()
        }
        .alert(
            "Race a Friend",
            isPresented: Binding(
                get: {
                    localError != nil ||
                    friendRaces.errorMessage != nil
                },
                set: { visible in
                    if !visible {
                        localError = nil
                        friendRaces.errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                localError ??
                friendRaces.errorMessage ??
                ""
            )
        }
    }

    private var friendIntroCard: some View {
        ATHLTHCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .frame(width: 50, height: 50)
                    .background(ATHLTHTheme.accentSoft, in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(ATHLTHLocalization.choose(
                        english: "Race a friend",
                        norwegian: "Løp mot en venn"
                    ))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(ATHLTHTheme.primaryText)

                    Text(ATHLTHLocalization.choose(
                        english: "Send a private Ghost invite. The duel only starts after your friend accepts and both are ready.",
                        norwegian: "Inviter til en privat Ghost-duell. Dere starter først når invitasjonen er godtatt og begge er klare."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var invitationsOverview: some View {
        VStack(spacing: 14) {
            ATHLTHCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(ATHLTHLocalization.choose(
                            english: "Incoming", norwegian: "Mottatte invitasjoner"
                        ))
                        .font(.headline)
                        Spacer()
                        if friendRaces.isLoading {
                            ProgressView().controlSize(.small)
                        }
                    }

                    if friendRaces.incoming.isEmpty {
                        Label(ATHLTHLocalization.choose(
                            english: "No invitations to respond to",
                            norwegian: "Ingen invitasjoner å svare på"
                        ), systemImage: "tray")
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .padding(.vertical, 9)
                    } else {
                        ForEach(friendRaces.incoming) { challenge in
                            incomingRow(challenge)
                            if challenge.id != friendRaces.incoming.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }

            ATHLTHCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(ATHLTHLocalization.choose(
                        english: "Sent", norwegian: "Sendte invitasjoner"
                    ))
                    .font(.headline)

                    if friendRaces.outgoing.isEmpty {
                        Text(ATHLTHLocalization.choose(
                            english: "No active invitations sent",
                            norwegian: "Ingen aktive sendte invitasjoner"
                        ))
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .padding(.vertical, 9)
                    } else {
                        ForEach(friendRaces.outgoing) { challenge in
                            outgoingRow(challenge)
                            if challenge.id != friendRaces.outgoing.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private var filteredFriends: [SocialProfileCard] {
        let query = friendSearch.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !query.isEmpty else { return social.mutualFollows }
        return social.mutualFollows.filter {
            $0.resolvedName.localizedStandardContains(query)
        }
    }

    private var selectedFriend: SocialProfileCard? {
        guard let selectedFriendID else { return nil }
        return social.mutualFollows.first {
            $0.userID == selectedFriendID
        }
    }

    private var invitationComposer: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    inviteProgress

                    switch inviteStep {
                    case .friend: invitationFriendStep
                    case .reference: invitationReferenceStep
                    case .confirm: invitationConfirmationStep
                    }
                }
                .padding(16)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .background(ATHLTHPremiumCanvas(
                accent: ATHLTHTheme.vitality.opacity(0.13)
            ))
            .navigationTitle(ATHLTHLocalization.choose(
                english: "Invite a friend", norwegian: "Inviter venn"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Close", norwegian: "Lukk"
                    )) {
                        showingInviteComposer = false
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                inviteActions
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.regularMaterial)
            }
            .sheet(isPresented: $showingRoutePicker) {
                NavigationStack {
                    SavedRoutesView(
                        selectionTitle: ATHLTHLocalization.choose(
                            english: "Duel route",
                            norwegian: "Rute for duellen"
                        ),
                        onSelect: { route in
                            selectedPlannedRoute = route
                            let suggested = route.expectedTravelTimeSeconds ??
                                max(route.distanceKilometers * 330, 300)
                            targetTimeText = GhostTargetTimeFormatter.string(suggested)
                            showingRoutePicker = false
                            if !advancedMode {
                                inviteStep = .confirm
                            }
                        }
                    )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(ATHLTHLocalization.choose(
                                english: "Close", norwegian: "Lukk"
                            )) {
                                showingRoutePicker = false
                            }
                        }
                    }
                }
            }
            .alert(
                ATHLTHLocalization.choose(
                    english: "Could not send invitation",
                    norwegian: "Kunne ikke sende invitasjonen"
                ),
                isPresented: Binding(
                    get: {
                        localError != nil ||
                        friendRaces.errorMessage != nil
                    },
                    set: { visible in
                        if !visible {
                            localError = nil
                            friendRaces.errorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(localError ?? friendRaces.errorMessage ?? "")
            }
        }
        .interactiveDismissDisabled(sending || friendRaces.isSending)
    }

    private var inviteProgress: some View {
        HStack(spacing: 8) {
            ForEach(1...3, id: \.self) { number in
                HStack(spacing: 7) {
                    Image(systemName: number < inviteStep.number
                        ? "checkmark.circle.fill"
                        : (number == inviteStep.number
                            ? "circle.inset.filled" : "circle"))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(
                        number <= inviteStep.number
                            ? ATHLTHTheme.accentDeep
                            : ATHLTHTheme.mutedText
                    )

                    Text(number == 1
                         ? ATHLTHLocalization.choose(
                             english: "Friend", norwegian: "Venn"
                         )
                         : number == 2
                             ? ATHLTHLocalization.choose(
                                 english: "Run", norwegian: "Løp"
                             )
                             : ATHLTHLocalization.choose(
                                 english: "Confirm", norwegian: "Bekreft"
                             ))
                    .font(.caption.weight(number == inviteStep.number
                        ? .bold : .medium))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(13)
        .background(ATHLTHTheme.surfaceStone,
                    in: RoundedRectangle(cornerRadius: 15))
        .accessibilityElement(children: .combine)
    }

    private var invitationFriendStep: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 13) {
                Text(ATHLTHLocalization.choose(
                    english: "Who would you like to race?",
                    norwegian: "Hvem vil du løpe mot?"
                ))
                .font(.title3.weight(.bold))

                if social.mutualFollows.isEmpty {
                    ContentUnavailableView(
                        ATHLTHLocalization.choose(
                            english: "No mutual friends yet",
                            norwegian: "Ingen gjensidige venner ennå"
                        ),
                        systemImage: "person.2",
                        description: Text(ATHLTHLocalization.choose(
                            english: "Find a friend in Community. You can invite each other once you both follow.",
                            norwegian: "Finn en venn i Fellesskap. Dere kan invitere hverandre når begge følger hverandre."
                        ))
                    )
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(ATHLTHTheme.mutedText)
                        TextField(ATHLTHLocalization.choose(
                            english: "Search friends",
                            norwegian: "Søk etter venner"
                        ), text: $friendSearch)
                        .textInputAutocapitalization(.never)
                    }
                    .padding(12)
                    .background(ATHLTHTheme.surfaceStone,
                                in: RoundedRectangle(cornerRadius: 13))

                    if filteredFriends.isEmpty {
                        Text(ATHLTHLocalization.choose(
                            english: "No friends match the search.",
                            norwegian: "Ingen venner samsvarer med søket."
                        ))
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    }

                    ForEach(filteredFriends) { friend in
                        Button {
                            selectedFriendID = friend.userID
                            withAnimation(.easeInOut(duration: 0.18)) {
                                inviteStep = .reference
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Text(String(friend.resolvedName.prefix(1)).uppercased())
                                    .font(.headline)
                                    .foregroundStyle(ATHLTHTheme.accentDeep)
                                    .frame(width: 44, height: 44)
                                    .background(ATHLTHTheme.accentSoft, in: Circle())

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(friend.resolvedName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(ATHLTHTheme.primaryText)

                                    if realtime.isOnline(friend.userID) {
                                        Label(ATHLTHLocalization.choose(
                                            english: "Online", norwegian: "Pålogget"
                                        ), systemImage: "circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(ATHLTHTheme.accentDeep)
                                    }
                                }

                                Spacer(minLength: 6)

                                Image(systemName: selectedFriendID == friend.userID
                                    ? "checkmark.circle.fill" : "chevron.right")
                                    .foregroundStyle(ATHLTHTheme.accentDeep)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .background(ATHLTHTheme.surfaceStone,
                                        in: RoundedRectangle(cornerRadius: 16))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var invitationReferenceStep: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(ATHLTHLocalization.choose(
                    english: "Choose a race reference",
                    norwegian: "Velg løpegrunnlag"
                ))
                .font(.title3.weight(.bold))

                if let selectedFriend {
                    Label(selectedFriend.resolvedName,
                          systemImage: "person.crop.circle")
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }

                if advancedMode && agreedArenaRouteID == nil {
                    Picker(ATHLTHLocalization.choose(
                        english: "Reference", norwegian: "Grunnlag"
                    ), selection: $courseMode) {
                        ForEach(GhostFriendCourseMode.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if courseMode == .previousWorkout {
                    if loadingRuns {
                        ProgressView(ATHLTHLocalization.choose(
                            english: "Loading previous runs...",
                            norwegian: "Henter tidligere løp..."
                        ))
                    } else if runs.isEmpty {
                        ContentUnavailableView(
                            ATHLTHLocalization.choose(
                                english: "No previous runs",
                                norwegian: "Ingen tidligere løp"
                            ),
                            systemImage: "figure.run",
                            description: Text(ATHLTHLocalization.choose(
                                english: "Record a GPS run or choose a saved course.",
                                norwegian: "Registrer et GPS-løp eller velg en lagret rute."
                            ))
                        )

                        Button {
                            courseMode = .plannedRoute
                        } label: {
                            Label(ATHLTHLocalization.choose(
                                english: "Use a saved course",
                                norwegian: "Bruk en lagret rute"
                            ), systemImage: "map")
                        }
                        .buttonStyle(.bordered)

                        if hasMoreFriendRuns {
                            Button {
                                Task { await loadMoreFriendRuns() }
                            } label: {
                                Label(ATHLTHLocalization.choose(
                                    english: "Check more previous runs",
                                    norwegian: "Kontroller flere løp"
                                ), systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .disabled(loadingRuns)
                        }
                    } else {
                        Text(ATHLTHLocalization.choose(
                            english: "Use a GPS-verified previous run as your Ghost.",
                            norwegian: "Bruk et tidligere løp med gyldig GPS som Ghost."
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)

                        ForEach(Array(runs.prefix(advancedMode ? 30 : 5))) { workout in
                            Button {
                                selectedWorkoutID = workout.id
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    inviteStep = .confirm
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "figure.run")
                                        .font(.headline)
                                        .foregroundStyle(ATHLTHTheme.accentDeep)
                                        .frame(width: 42, height: 42)
                                        .background(ATHLTHTheme.accentSoft,
                                                    in: RoundedRectangle(cornerRadius: 13))

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(workout.startDate.formatted(
                                            date: .abbreviated, time: .omitted
                                        ))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(ATHLTHTheme.primaryText)

                                        Text(runTitle(workout))
                                            .font(.caption)
                                            .foregroundStyle(ATHLTHTheme.mutedText)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 4)
                                    Image(systemName: selectedWorkoutID == workout.id
                                        ? "checkmark.circle.fill" : "chevron.right")
                                        .foregroundStyle(ATHLTHTheme.accentDeep)
                                }
                                .frame(maxWidth: .infinity, minHeight: 58)
                                .padding(11)
                                .background(ATHLTHTheme.surfaceStone,
                                            in: RoundedRectangle(cornerRadius: 15))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(ATHLTHLocalization.choose(
                                english: "Choose this verified run as your invitation reference",
                                norwegian: "Velg dette GPS-godkjente løpet til invitasjonen"
                            ))
                        }

                        if hasMoreFriendRuns {
                            Button {
                                Task { await loadMoreFriendRuns() }
                            } label: {
                                Label(ATHLTHLocalization.choose(
                                    english: "Find more GPS runs",
                                    norwegian: "Finn flere GPS-løp"
                                ), systemImage: "arrow.clockwise")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .disabled(loadingRuns)
                        }
                    }
                } else {
                    Button {
                        showingRoutePicker = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "map.fill")
                            Text(selectedPlannedRoute?.title ??
                                 ATHLTHLocalization.choose(
                                     english: "Choose a saved course",
                                     norwegian: "Velg en lagret rute"
                                 ))
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(14)
                        .background(ATHLTHTheme.surfaceStone,
                                    in: RoundedRectangle(cornerRadius: 15))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(agreedArenaRouteID != nil)

                    if let route = selectedPlannedRoute {
                        Label(String(format: "%.2f km", route.distanceKilometers),
                              systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    }

                    if advancedMode {
                        TextField(ATHLTHLocalization.choose(
                            english: "Target time (MM:SS)",
                            norwegian: "Måltid (MM:SS)"
                        ), text: $targetTimeText)
                        .keyboardType(.numbersAndPunctuation)
                        .font(.title3.weight(.semibold))
                        .padding(13)
                        .background(ATHLTHTheme.surfaceStone,
                                    in: RoundedRectangle(cornerRadius: 15))
                    } else if let targetTime {
                        Label(ATHLTHLocalization.format(
                            english: "Suggested time: %@",
                            norwegian: "Foreslått tid: %@",
                            GhostTargetTimeFormatter.string(targetTime)
                        ), systemImage: "clock")
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                    }

                    if agreedArenaRouteID != nil {
                        Label(ATHLTHLocalization.choose(
                            english: "The Arena course is locked for this round.",
                            norwegian: "Arena-ruten er låst for denne runden."
                        ), systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    }

                    if targetTime == nil {
                        Text(ATHLTHLocalization.choose(
                            english: "Choose a valid finish time (1 min–24 h).",
                            norwegian: "Velg en gyldig sluttid (1 min–24 t)."
                        ))
                        .font(.caption)
                        .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    private var invitationConfirmationStep: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(ATHLTHLocalization.choose(
                    english: "Ready to invite?",
                    norwegian: "Klar til å invitere?"
                ))
                .font(.title3.weight(.bold))

                if let selectedFriend {
                    confirmationLine(
                        icon: "person.crop.circle.fill",
                        title: ATHLTHLocalization.choose(
                            english: "Opponent", norwegian: "Motstander"
                        ),
                        value: selectedFriend.resolvedName
                    )
                }

                if courseMode == .previousWorkout,
                   let workout = runs.first(where: { $0.id == selectedWorkoutID }) {
                    confirmationLine(
                        icon: "figure.run",
                        title: ATHLTHLocalization.choose(
                            english: "Reference", norwegian: "Løp"
                        ),
                        value: runTitle(workout)
                    )
                } else if let route = selectedPlannedRoute {
                    confirmationLine(
                        icon: "map",
                        title: ATHLTHLocalization.choose(
                            english: "Course", norwegian: "Løype"
                        ),
                        value: route.title
                    )
                    if let targetTime {
                        confirmationLine(
                            icon: "stopwatch",
                            title: ATHLTHLocalization.choose(
                                english: "Finish time", norwegian: "Sluttid"
                            ),
                            value: GhostTargetTimeFormatter.string(targetTime)
                        )
                    }
                }

                Label(ATHLTHLocalization.choose(
                    english: "The race starts together only after your friend accepts.",
                    norwegian: "Dere starter sammen først når vennen har godkjent."
                ), systemImage: "person.2.wave.2.fill")
                .font(.subheadline)
                .foregroundStyle(ATHLTHTheme.accentDeep)

                Divider()

                Label(
                    settings.hideRouteStartAndEnd
                        ? ATHLTHLocalization.choose(
                            english: "Start/end trimmed before sharing.",
                            norwegian: "Start og slutt skjules før deling."
                        )
                        : ATHLTHLocalization.choose(
                            english: "Full GPS reference will be shared with this friend. You can enable route trimming in Privacy Settings.",
                            norwegian: "Hele GPS-referansen deles med vennen. Du kan skjule start og slutt i personverninnstillingene."
                        ),
                    systemImage: settings.hideRouteStartAndEnd
                        ? "lock.shield.fill" : "exclamationmark.shield"
                )
                .font(.caption)
                .foregroundStyle(settings.hideRouteStartAndEnd
                    ? ATHLTHTheme.mutedText : .orange)

                if advancedMode {
                    Text(ATHLTHLocalization.choose(
                        english: "Heart rate, calories and HealthKit identifiers are not shared.",
                        norwegian: "Puls, kalorier og HealthKit-ID-er deles ikke."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }
            }
        }
    }

    private func confirmationLine(
        icon: String, title: String, value: String
    ) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
        }
        .padding(12)
        .background(ATHLTHTheme.surfaceStone,
                    in: RoundedRectangle(cornerRadius: 14))
    }

    private var inviteActions: some View {
        HStack(spacing: 10) {
            if inviteStep != .friend {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        inviteStep = inviteStep == .confirm
                            ? .reference : .friend
                    }
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.headline)
                        .frame(width: 48, height: 48)
                        .background(ATHLTHTheme.surfaceStone,
                                    in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Previous step", norwegian: "Forrige steg"
                ))
            }

            Button {
                if inviteStep == .confirm {
                    Task { await sendChallenge() }
                } else {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        inviteStep = inviteStep == .friend
                            ? .reference : .confirm
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    if sending || friendRaces.isSending {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: inviteStep == .confirm
                            ? "paperplane.fill" : "arrow.right")
                    }
                    Text(
                        inviteStep == .confirm
                            ? ATHLTHLocalization.choose(
                                english: "Send invitation",
                                norwegian: "Send invitasjon"
                            )
                            : ATHLTHLocalization.choose(
                                english: "Continue", norwegian: "Fortsett"
                            )
                    )
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(ATHLTHTheme.accentDeep,
                            in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(
                sending || friendRaces.isSending ||
                (inviteStep == .friend && selectedFriend == nil) ||
                (inviteStep != .friend && !canSendSelectedCourse)
            )
        }
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                "Private by design",
                systemImage: "lock.shield.fill"
            )
            .font(.headline)
            .foregroundStyle(ATHLTHTheme.vitality)

            Text(
                ATHLTHLocalization.choose(
                    english: "Only a reduced route and timing reference are shared. For previous runs this comes from the chosen GPS workout; for planned routes it is generated from your selected course. Heart rate, calories and HealthKit identifiers are not shared.",
                    norwegian: "Bare en forenklet rute og tidsreferanse deles. For tidligere økter brukes den valgte GPS-økten; for planlagte ruter lages en beregnet mål-Ghost. Puls, kalorier og HealthKit-ID-er deles ikke."
                )
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if settings.hideRouteStartAndEnd {
                Label(
                    "Your first and last 250 m are removed before the ghost is uploaded.",
                    systemImage: "location.slash.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            } else {
                Label(
                    "Hide route start/end is off. The full selected route will be shared with the chosen friend.",
                    systemImage: "location.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }

    private func incomingRow(
        _ challenge:
            GhostFriendRaceChallengeRecord
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(
                            profileName(
                                challenge.senderID
                            )
                        )
                        .font(.headline)

                        if realtime.isOnline(
                            challenge.senderID
                        ) {
                            Circle()
                                .fill(Color.green)
                                .frame(
                                    width: 8,
                                    height: 8
                                )
                                .accessibilityLabel(
                                    "Online"
                                )
                        }
                    }

                    Text(challenge.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Label(
                        challenge.sourceKind == "planned_route"
                            ? ATHLTHLocalization.choose(
                                english: "Planned route · synchronized duel",
                                norwegian: "Planlagt rute · synkronisert duell"
                            )
                            : ATHLTHLocalization.choose(
                                english: "Previous GPS run · synchronized duel",
                                norwegian: "Tidligere GPS-økt · synkronisert duell"
                            ),
                        systemImage: challenge.sourceKind == "planned_route"
                            ? "map.fill" : "figure.run"
                    )
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                }

                Spacer()

                statusBadge(challenge.status)
            }

            HStack(spacing: 14) {
                Label(
                    distanceText(
                        challenge.distanceMeters
                    ),
                    systemImage: "location.fill"
                )

                Label(
                    durationText(
                        challenge
                            .referenceDurationSeconds
                    ),
                    systemImage: "stopwatch.fill"
                )

                if challenge.privacyTrimmed {
                    Label(
                        "Trimmed",
                        systemImage:
                            "lock.shield.fill"
                    )
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if challenge.status == .pending {
                HStack(spacing: 10) {
                    Button("Accept") {
                        Task {
                            await friendRaces.respond(
                                challenge,
                                status: .accepted
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.vitality)

                    Button("Decline") {
                        Task {
                            await friendRaces.respond(
                                challenge,
                                status: .declined
                            )
                        }
                    }
                    .buttonStyle(.bordered)
                }
            } else if challenge.status == .accepted {
                if let liveSession =
                    realtime.visibleLiveSessions
                        .first(
                            where: {
                                $0.ghostChallengeID ==
                                    challenge.id
                            }
                        ) {
                    NavigationLink {
                        ATHLTHLiveWorkoutMapView(
                            session: liveSession
                        )
                    } label: {
                        Label(
                            "Open live Ghost Run",
                            systemImage:
                                "location.circle.fill"
                        )
                    }
                    .buttonStyle(.bordered)
                }

                NavigationLink {
                    LiveGhostRaceLobbyView(
                        challenge: challenge
                    )
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english:
                                "Open Live Ghost lobby",
                            norwegian:
                                "Åpne Live Ghost-lobby"
                        ),
                        systemImage:
                            "person.2.wave.2.fill"
                    )
                    .frame(
                        maxWidth: .infinity
                    )
                }
                .buttonStyle(
                    .borderedProminent
                )
                .tint(
                    ATHLTHTheme.vitality
                )
            }
        }
        .padding(.vertical, 5)
    }

    private func outgoingRow(
        _ challenge:
            GhostFriendRaceChallengeRecord
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        profileName(
                            challenge.recipientID
                        )
                    )
                    .font(.headline)

                    Text(challenge.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(challenge.sourceKind == "planned_route"
                        ? ATHLTHLocalization.choose(
                            english: "Planned course · live start",
                            norwegian: "Planlagt rute · felles start"
                        )
                        : ATHLTHLocalization.choose(
                            english: "Previous GPS run · live start",
                            norwegian: "Tidligere GPS-økt · felles start"
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                statusBadge(challenge.status)
            }

            HStack {
                Text(
                    challenge.createdAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                if challenge.status == .pending {
                    Button(
                        "Cancel",
                        role: .destructive
                    ) {
                        Task {
                            await friendRaces.respond(
                                challenge,
                                status: .cancelled
                            )
                        }
                    }
                    .font(.caption.weight(.semibold))
                }
            }

            if challenge.status == .accepted {
                NavigationLink {
                    LiveGhostRaceLobbyView(
                        challenge: challenge
                    )
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english:
                                "Open Live Ghost lobby",
                            norwegian:
                                "Åpne Live Ghost-lobby"
                        ),
                        systemImage:
                            "person.2.wave.2.fill"
                    )
                    .frame(
                        maxWidth: .infinity
                    )
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusBadge(
        _ status: GhostFriendRaceStatus
    ) -> some View {
        Text(statusTitle(status))
            .font(.caption2.weight(.bold))
            .foregroundStyle(
                status == .accepted
                    ? ATHLTHTheme.vitality
                    : .secondary
            )
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                (
                    status == .accepted
                        ? ATHLTHTheme.vitality
                        : Color.secondary
                ).opacity(0.10),
                in: Capsule()
            )
    }

    @MainActor
    private func sendChallenge() async {
        guard let friendID = selectedFriendID,
              let friend = social.mutualFollows.first(where: {
                  $0.userID == friendID
              }), !sending else { return }

        sending = true
        defer { sending = false }

        let sent: Bool
        switch courseMode {
        case .plannedRoute:
            guard let route = selectedPlannedRoute,
                  let seconds = targetTime else { return }
            sent = await friendRaces.sendPlannedRoute(
                to: friend,
                route: route,
                targetDurationSeconds: seconds,
                settings: settings,
                arenaRoundID: eligibleArenaRoundID
            )
        case .previousWorkout:
            guard let workoutID = selectedWorkoutID,
                  let workout = runs.first(where: {
                      $0.id == workoutID
                  }) else { return }
            let detail = await health.workoutDetail(for: workout)
            sent = await friendRaces.send(
                to: friend,
                workout: workout,
                detail: detail,
                settings: settings,
                arenaRoundID: eligibleArenaRoundID
            )
        }

        if sent {
            showSentConfirmation = true
            showingInviteComposer = false
            inviteStep = .friend
            selectedFriendID = nil
            selectedWorkoutID = nil
        }
    }

    @MainActor
    private func start(
        _ challenge:
            GhostFriendRaceChallengeRecord
    ) async {
        guard challenge.status ==
                .accepted
        else {
            localError =
                GhostFriendRaceError
                    .notAccepted
                    .localizedDescription
            return
        }

        switch captureDevice {
        case .iPhone:
            guard phoneWorkout.active == nil
            else {
                localError =
                    "Finish the active iPhone workout before starting a friend Ghost Race."
                return
            }

        case .appleWatch:
            guard watchConnection.isReady
            else {
                localError =
                    "Connect Apple Watch or choose iPhone before starting a friend Ghost Race."
                return
            }
        }

        startingChallengeID =
            challenge.id
        defer {
            startingChallengeID = nil
        }

        do {
            realtime.selectLiveGhost(nil)

            let currentUserID =
                session.profile.userID
            let opponentUserID =
                challenge.senderID ==
                    currentUserID
                    ? challenge.recipientID
                    : challenge.senderID
            let opponent =
                profileName(
                    opponentUserID
                )

            try await GhostRaceStartService.start(
                reference:
                    challenge.reference(),
                ownerID:
                    currentUserID,
                comparisonRouteID:
                    challenge.id,
                opponentName:
                    opponent,
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

            if social.privacy?
                .shareLiveWorkoutLocation ==
                true {
                _ = await realtime
                    .beginGhostSession(
                        challenge: challenge
                    )
            }
        } catch {
            localError =
                error.localizedDescription
        }
    }

    private var hasMoreFriendRuns: Bool {
        checkedRunCount < unverifiedRuns.count
    }

    @MainActor
    private func loadRuns() async {
        guard !loadingRuns else { return }
        loadingRuns = true
        defer { loadingRuns = false }

        let history = (try? await health.workoutHistory()) ?? health.workouts
        unverifiedRuns = history.filter {
            $0.activity == .running &&
            ($0.distanceMeters ?? 0) >= 250 &&
            $0.duration > 0
        }
        .sorted { $0.startDate > $1.startDate }

        runs = []
        checkedRunCount = 0
        selectedWorkoutID = nil
        await scanMoreFriendRuns()
    }

    @MainActor
    private func loadMoreFriendRuns() async {
        guard !loadingRuns else { return }
        loadingRuns = true
        defer { loadingRuns = false }
        await scanMoreFriendRuns()
    }

    @MainActor
    private func scanMoreFriendRuns() async {
        // In Basic, search for five ready choices without extra taps.
        // Limit the number of HealthKit GPS queries in one interaction.
        let needed = advancedMode ? 30 : 5
        let limit = min(checkedRunCount + 30, unverifiedRuns.count)

        while checkedRunCount < limit && runs.count < needed {
            if Task.isCancelled { return }
            let workout = unverifiedRuns[checkedRunCount]
            let route = await health.workoutRoute(for: workout.id)
            checkedRunCount += 1

            if GhostRaceTrackEligibility.hasUsableGPS(route) {
                runs.append(workout)
            }
        }
    }

    private func profileName(
        _ userID: UUID
    ) -> String {
        social.mutualFollows.first(
            where: {
                $0.userID == userID
            }
        )?.resolvedName ??
        social.visibleProfiles.first(
            where: {
                $0.userID == userID
            }
        )?.resolvedName ??
        "ATHLTH Athlete"
    }

    private func statusTitle(
        _ status: GhostFriendRaceStatus
    ) -> String {
        switch status {
        case .pending:
            return "PENDING"
        case .accepted:
            return "ACCEPTED"
        case .declined:
            return "DECLINED"
        case .cancelled:
            return "CANCELLED"
        }
    }

    private func runTitle(
        _ workout: WorkoutSummary
    ) -> String {
        let distance =
            workout.distanceKilometers.map {
                String(
                    format: "%.1f km",
                    $0
                )
            } ?? "Run"

        return
            "\(workout.startDate.formatted(date: .abbreviated, time: .omitted)) · \(distance) · \(durationText(workout.duration))"
    }

    private func distanceText(
        _ meters: Double
    ) -> String {
        String(
            format: "%.2f km",
            meters / 1_000
        )
    }

    private func durationText(
        _ seconds: TimeInterval
    ) -> String {
        let total =
            max(
                Int(seconds.rounded()),
                0
            )
        let hours = total / 3_600
        let minutes =
            (total % 3_600) / 60
        let remainder =
            total % 60

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
}

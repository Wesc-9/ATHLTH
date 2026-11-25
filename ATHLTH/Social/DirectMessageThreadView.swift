import CoreLocation
import SwiftUI

struct DirectMessageThreadView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var messaging: MessagingStore
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var runningLibrary: RunningWorkoutLibraryStore
    @EnvironmentObject private var challengeStore: ChallengeStore
    @EnvironmentObject private var notifications: ATHLTHNotificationStore
    @EnvironmentObject private var social: SocialStore

    let friend: SocialProfileCard

    @State private var conversationID: UUID?
    @State private var draftOwner: UUID?
    @State private var foregroundRefreshRequest: UUID?
    @State private var realtimeGeneration = UUID()
    @State private var realtimeConnected = false
    @State private var loadingOlderMessages = false
    @FocusState private var composerFocused: Bool
    @State private var text = ""
    @State private var selectedShare: MessageShareDraft?
    @State private var showingSharePicker = false
    @State private var selectedPreviewAttachment: DirectMessageRecord?
    @State private var isSending = false
    @State private var loadError: String?
    @State private var savedFeedback: String?
    @State private var requestResponseInFlight = false
    @State private var requestResponseAccepting: Bool?
    @State private var requestResponseError: String?
    @State private var respondingToPlannedInviteID: UUID?
    @State private var respondingToWorkoutProposalID: UUID?
    @State private var workoutInvitationForProposal: DirectMessageRecord?
    @State private var plannedInviteError: String?
    @State private var respondingToChallengeID: UUID?
    @State private var respondingToProposalID: UUID?
    @State private var challengeDetailsDestination: ThreadChallengeDetailsDestination?
    @State private var showingFriendProfile = false
    @State private var cancellingChallengeID: UUID?
    @State private var cancellationError: String?
    @State private var undoSendError: String?
    @State private var sendError: String?

    var body: some View {
        ZStack {
            ATHLTHPremiumCanvas(
                accent:
                    ATHLTHTheme
                        .premiumGold
                        .opacity(0.12)
            )

            VStack(spacing: 0) {
                threadHero
                    .frame(
                        maxWidth: .infinity
                    )
                    .zIndex(0)

                Group {
                    if let conversationID {
                        messagesView(
                            conversationID
                        )
                    } else if let loadError {
                        ContentUnavailableView(
                            ATHLTHLocalization.choose(
                                english:
                                    "Messages unavailable",
                                norwegian:
                                    "Meldinger utilgjengelig"
                            ),
                            systemImage:
                                "exclamationmark.bubble",
                            description:
                                Text(loadError)
                        )
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity
                        )
                    } else {
                        ProgressView(
                            ATHLTHLocalization.choose(
                                english:
                                    "Opening conversation…",
                                norwegian:
                                    "Åpner samtalen…"
                            )
                        )
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity
                        )
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
                .athlthConversationPanelChrome()
                .padding(
                    .horizontal,
                    6
                )
                // The white conversation sheet intentionally overlaps
                // the lower part of the hero image, matching the rest
                // of ATHLTH's pinned-card visual language.
                .padding(
                    .top,
                    -52
                )
                .zIndex(2)
            }
        }
        .ignoresSafeArea(
            .container,
            edges: .top
        )
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(
            .hidden,
            for: .navigationBar
        )
        .toolbar(
            .hidden,
            for: .tabBar
        )
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .sheet(isPresented: $showingSharePicker) {
            MessageSharePicker { draft in
                selectedShare = draft
                showingSharePicker = false
            }
        }
        .sheet(item: $selectedPreviewAttachment) { message in
            ATHLTHReceivedTrainingPreview(
                message: message,
                sharedByUsername: message.senderID == friend.userID
                    ? friend.username : nil
            ) {
                saveAttachment(message)
            }
        }
        .sheet(item: $workoutInvitationForProposal) { invitation in
            if let original = invitation.decodeSnapshot(PlannedSession.self) {
                let revision = latestSharedWorkout(
                    for: invitation,
                    in: conversationID.map {
                        messaging.messages(in: $0)
                    } ?? []
                ) ?? original

                // Guest uses the exact same premium timeline editor as the
                // organizer. Saving sends a PROPOSAL only; it cannot silently
                // overwrite the owner's or guest's recorded workout.
                WorkoutTemplateBuilderView(
                    initialTitle: revision.title,
                    initialBlocks: revision.resolvedWorkoutBlocks,
                    initialRouteID: revision.routeID,
                    initialDurationOverrideMinutes: revision.durationMinutes,
                    draftContext: "workout-proposal-\(invitation.id.uuidString)",
                    plannedDate: revision.scheduledStart,
                    initialActivity: ATHLTHPlannedWorkoutType.from(revision),
                    initialStudioAdvanced: true,
                    collaborationWorkoutID: revision.id,
                    onAddStandalone: { changed in
                        var proposed = revision
                        proposed.title = changed.title
                        proposed.kind = changed.kind
                        proposed.durationMinutes = changed.durationMinutes
                        proposed.routeID = changed.routeID
                        proposed.workoutBlocks = changed.workoutBlocks
                        sendWorkoutChangeProposal(
                            invitation: invitation, proposed: proposed,
                            basedOn: revision
                        )
                        return true
                    },
                    saveButtonTitle: ATHLTHLocalization.choose(
                        english: "Send workout suggestion",
                        norwegian: "Send forslag til fellesøkten"
                    )
                )
            }
        }
        .alert(
            ATHLTHLocalization.choose(english: "Could not send message", norwegian: "Kunne ikke sende meldingen"),
            isPresented: Binding(get: { sendError != nil }, set: { if !$0 { sendError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(sendError ?? "")
        }
        .alert(
            ATHLTHLocalization.choose(english: "Undo send", norwegian: "Angre sending"),
            isPresented: Binding(get: { undoSendError != nil }, set: { if !$0 { undoSendError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(undoSendError ?? "")
        }
        .alert(
            "Saved to ATHLTH",
            isPresented: Binding(
                get: {
                    savedFeedback != nil
                },
                set: {
                    if !$0 {
                        savedFeedback = nil
                    }
                }
            )
        ) {
            Button(
                "OK",
                role: .cancel
            ) {}
        } message: {
            Text(
                savedFeedback ?? ""
            )
        }
        .alert(
            ATHLTHLocalization.choose(
                english: "Could not cancel challenge", norwegian: "Kunne ikke avlyse"
            ),
            isPresented: Binding(
                get: { cancellationError != nil },
                set: { if !$0 { cancellationError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cancellationError ?? "")
        }
        .alert(
            ATHLTHLocalization.choose(
                english: "Could not respond to invitation",
                norwegian: "Kunne ikke svare på invitasjonen"
            ),
            isPresented: Binding(
                get: { plannedInviteError != nil },
                set: { if !$0 { plannedInviteError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(plannedInviteError ?? "")
        }
        .sheet(isPresented: $showingFriendProfile) {
            NavigationStack {
                FriendProfileView(userID: friend.userID)
            }
        }
        .sheet(item: $challengeDetailsDestination) { destination in
            NavigationStack {
                ChallengeDetailView(challengeID: destination.id)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(ATHLTHLocalization.choose(
                                english: "Done", norwegian: "Ferdig"
                            )) { challengeDetailsDestination = nil }
                        }
                    }
            }
        }
        .task(id: friend.userID) {
            guard session.signedIn, !session.previewModeEnabled else { return }
            let owner = session.profile.userID
            draftOwner = owner
            text = messaging.textDraft(for: friend.userID, owner: owner)
            await openAndPoll(owner: owner)
        }
        .onReceive(NotificationCenter.default.publisher(for: .athlthRemoteNotificationReceived)) { event in
            guard let owner = draftOwner, let conversationID,
                  let payload = event.userInfo,
                  ATHLTHDirectMessageRefreshPolicy.matches(payload, owner: owner, conversation: conversationID) else { return }
            foregroundRefreshRequest = UUID()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, conversationID != nil { foregroundRefreshRequest = UUID() }
        }
        .task(id: "\(conversationID?.uuidString ?? "")|\(session.profile.userID)|\(scenePhase)|\(session.signedIn)") {
            let generation = UUID()
            realtimeGeneration = generation
            realtimeConnected = false
            guard scenePhase == .active, let id = conversationID, let owner = draftOwner,
                  session.signedIn, !session.previewModeEnabled, session.profile.userID == owner else { return }
            await messaging.observeThreadChanges(owner: owner, conversation: id,
                onChange: {
                    guard realtimeGeneration == generation, conversationID == id,
                          draftOwner == owner, session.profile.userID == owner else { return }
                    foregroundRefreshRequest = UUID()
                }, onStatus: { connected in
                    guard realtimeGeneration == generation, conversationID == id,
                          draftOwner == owner, session.profile.userID == owner else { return }
                    realtimeConnected = connected
                })
        }
        .task(id: foregroundRefreshRequest) {
            guard foregroundRefreshRequest != nil else { return }
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            guard let owner = draftOwner, let conversationID, scenePhase == .active,
                  session.signedIn, !session.previewModeEnabled, session.profile.userID == owner else { return }
            await refreshVisibleThread(conversationID, owner: owner)
        }
        .onChange(of: text) { _, value in
            guard let owner = draftOwner, session.signedIn, !session.previewModeEnabled,
                  owner == session.profile.userID else { return }
            messaging.setTextDraft(value, for: friend.userID, owner: owner)
        }
        .onChange(of: session.profile.userID) { _, _ in
            draftOwner = nil
            text = ""
            selectedShare = nil
            conversationID = nil
            dismiss()
        }
        .onChange(of: session.signedIn) { _, signedIn in
            if !signedIn {
                draftOwner = nil
                text = ""
                selectedShare = nil
                conversationID = nil
                dismiss()
            }
        }
    }

    private var threadHero: some View {
        ATHLTHConversationHero(
            title:
                friend.resolvedName,
            subtitle:
                threadStatusText,
            backgroundAsset: ATHLTHConversationArtwork.directMessageHeader,
            onBack: {
                dismiss()
            },
            onProfileTap: {
                showingFriendProfile = true
            }
        ) {
            SocialAvatar(
                profile: friend,
                size: 44
            )
            .overlay {
                Circle()
                    .stroke(
                        Color.white
                            .opacity(0.86),
                        lineWidth: 1.4
                    )
            }
        } trailing: {
            Menu {
                if let conversationID {
                    Button {
                        messaging
                            .togglePinned(
                                conversationID
                            )
                    } label: {
                        Label(
                            messaging
                                .isPinned(
                                    conversationID
                                )
                                ? ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Unpin conversation",
                                        norwegian:
                                            "Løsne samtalen"
                                    )
                                : ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Pin conversation",
                                        norwegian:
                                            "Fest samtalen"
                                    ),
                            systemImage:
                                messaging
                                    .isPinned(
                                        conversationID
                                    )
                                    ? "pin.slash"
                                    : "pin.fill"
                        )
                    }

                    Button {
                        messaging
                            .toggleArchived(
                                conversationID
                            )
                    } label: {
                        Label(
                            messaging
                                .isArchived(
                                    conversationID
                                )
                                ? ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Restore conversation",
                                        norwegian:
                                            "Gjenopprett samtalen"
                                    )
                                : ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Archive conversation",
                                        norwegian:
                                            "Arkiver samtalen"
                                    ),
                            systemImage:
                                messaging
                                    .isArchived(
                                        conversationID
                                    )
                                    ? "tray.and.arrow.up"
                                    : "archivebox"
                        )
                    }
                }

                Divider()

                Button(
                    ATHLTHLocalization.choose(
                        english: "Block",
                        norwegian: "Blokker"
                    ),
                    role: .destructive
                ) {
                    Task {
                        await social.block(
                            friend.userID
                        )
                        dismiss()
                    }
                }
            } label: {
                Image(
                    systemName:
                        "ellipsis"
                )
                .font(
                    .system(
                        size: 17,
                        weight: .bold
                    )
                )
                .foregroundStyle(
                    .white
                )
                .frame(
                    width: 42,
                    height: 42
                )
                .background(
                    .ultraThinMaterial,
                    in: Circle()
                )
                .overlay {
                    Circle()
                        .stroke(
                            Color.white
                                .opacity(0.30),
                            lineWidth: 0.8
                        )
                }
            }
        }
    }

    private var threadStatusText: String {
        if isIncomingRequest {
            return ATHLTHLocalization.choose(
                english:
                    "Message request · needs your reply",
                norwegian:
                    "Meldingsforespørsel · venter på svar"
            )
        }

        if isOutgoingRequest {
            return ATHLTHLocalization.choose(
                english:
                    "Message request sent",
                norwegian:
                    "Meldingsforespørsel sendt"
            )
        }

        return ATHLTHLocalization.choose(
            english:
                "ATHLTH conversation",
            norwegian:
                "ATHLTH-samtale"
        )
    }

    private var threadStatusIcon: String {
        if isIncomingRequest {
            return "envelope.badge.fill"
        }

        if isOutgoingRequest {
            return "paperplane.fill"
        }

        if !pendingChallengesFromFriend.isEmpty ||
            !outgoingChallengesToFriend.isEmpty {
            return "trophy.fill"
        }

        return "message.fill"
    }

    @ViewBuilder
    private func messagesView(_ conversationID: UUID) -> some View {
        let messages =
            messaging.messages(
                in: conversationID
            )
        let lifecycleEvents = challengeLifecycleEventsWithFriend
        let standaloneInvites = challengeInvitationsWithoutMessages(messages)
        let timeline = threadTimelineItems(
            messages: messages,
            lifecycleEvents: lifecycleEvents,
            challengeInvitations: standaloneInvites
        )

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if messaging.canLoadOlderMessages(in: conversationID) {
                        Button {
                            guard !loadingOlderMessages else { return }
                            loadingOlderMessages = true
                            let anchor = timeline.first?.id
                            Task {
                                await messaging.loadOlderMessages(in: conversationID)
                                loadingOlderMessages = false
                                if let anchor { proxy.scrollTo(anchor, anchor: .top) }
                            }
                        } label: {
                            if loadingOlderMessages {
                                ProgressView()
                            } else {
                                Label(ATHLTHLocalization.choose(english: "Load older messages", norwegian: "Hent eldre meldinger"),
                                      systemImage: "clock.arrow.circlepath")
                                    .font(.subheadline.weight(.medium))
                            }
                        }
                        .frame(minHeight: 44)
                        .disabled(loadingOlderMessages)
                    }
                    if messages.isEmpty &&
                        standaloneInvites.isEmpty &&
                        lifecycleEvents.isEmpty {
                        ContentUnavailableView(
                            ATHLTHLocalization
                                .choose(
                                    english:
                                        "Start the conversation",
                                    norwegian:
                                        "Start samtalen"
                                ),
                            systemImage:
                                "message",
                            description: Text(
                                ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Send a message or share a workout, plan, route or challenge.",
                                        norwegian:
                                            "Send en melding eller del en økt, plan, rute eller utfordring."
                                    )
                            )
                        )
                        .padding(
                            .top,
                            80
                        )
                    }

                    ForEach(timeline) { item in
                        switch item {
                        case .message(let message):
                            MessageBubble(
                                message: message,
                                friend: friend,
                                currentUserID:
                                    messaging
                                        .currentUserID,
                                currentUserProfile:
                                    currentUserProfileCard,
                                onSaveAttachment: {
                                    saveAttachment(message)
                                },
                                onPreviewAttachment: {
                                    selectedPreviewAttachment = message
                                },
                                inviteResponse: plannedInviteResponse(
                                    for: message, in: messages
                                ),
                                respondingToInvite: respondingToPlannedInviteID == message.id,
                                onRespondToInvite: { accept in
                                    respondToPlannedInvite(message, accept: accept)
                                },
                                onWithdrawInvite: { withdrawPlannedInvite(message) },
                                agreedWorkout: latestSharedWorkout(
                                    for: message, in: messages
                                ),
                                lifecycleUpdate: latestWorkoutLifecycle(
                                    for: message, in: messages
                                ),
                                workoutChangeDecision: workoutChangeDecision(
                                    for: message, in: messages
                                ),
                                reviewingWorkoutChange: respondingToWorkoutProposalID ==
                                    message.id,
                                onProposeWorkoutChange: {
                                    workoutInvitationForProposal = message
                                },
                                onReviewWorkoutChange: { approve in
                                    reviewWorkoutProposal(message, approve: approve)
                                },
                                respondingToChallenge: respondingToChallengeID ==
                                    message.sourceObjectID,
                                onRespondToChallenge: { challenge, accept in
                                    respondToThreadChallenge(challenge, accept: accept)
                                },
                                onOpenChallenge: { id in
                                    openChallengeDetails(id)
                                },
                                cancellingChallenge: cancellingChallengeID ==
                                    message.sourceObjectID,
                                onCancelChallenge: { challenge in
                                    cancelSharedChallenge(challenge)
                                },
                                challengeChangeResponse: proposalResponse(
                                    for: message, in: messages
                                ),
                                respondingToProposal: respondingToProposalID ==
                                    message.id,
                                onReviewProposal: { accept in
                                    reviewChallengeChange(message, accept: accept)
                                }
                            )
                            .contextMenu {
                                if message.deletedAt == nil,
                                   let body = message.body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Button {
                                        UIPasteboard.general.string = body
                                    } label: {
                                        Label(ATHLTHLocalization.choose(english: "Copy text", norwegian: "Kopier tekst"), systemImage: "doc.on.doc")
                                    }
                                    if currentConversation?.requestStatus == .accepted {
                                        Button {
                                            let excerpt = String(body.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").prefix(140))
                                            let quote = "«" + excerpt + "»\n\n"
                                            text = quote + text
                                            composerFocused = true
                                        } label: {
                                            Label(ATHLTHLocalization.choose(english: "Reply with quote", norwegian: "Svar med sitat"), systemImage: "arrowshape.turn.up.left")
                                        }
                                    }
                                }
                                if message.senderID == messaging.currentUserID,
                                   message.attachmentKindRaw == nil,
                                   message.deletedAt == nil,
                                   message.readAt == nil {
                                    Button(role: .destructive) {
                                        Task {
                                            if !(await messaging.retractTextMessage(message)) {
                                                undoSendError = messaging.errorMessage ?? ATHLTHLocalization.choose(english: "The message can no longer be withdrawn.", norwegian: "Meldingen kan ikke lenger trekkes tilbake.")
                                            }
                                        }
                                    } label: {
                                        Label(ATHLTHLocalization.choose(english: "Undo send", norwegian: "Angre sending"), systemImage: "arrow.uturn.backward")
                                    }
                                }
                            }
                            .id(item.id)

                        case .challengeInvite(let challenge, let invitedAt):
                            ThreadChallengeTimelineRow(
                                challenge: challenge,
                                friend: friend,
                                currentUserID: session.profile.userID,
                                invitedAt: invitedAt,
                                responding: respondingToChallengeID == challenge.id,
                                onAccept: {
                                    respondToThreadChallenge(challenge, accept: true)
                                },
                                onDecline: {
                                    respondToThreadChallenge(challenge, accept: false)
                                },
                                onDetails: {
                                    openChallengeDetails(challenge.id)
                                },
                                cancelling: cancellingChallengeID == challenge.id,
                                onCancel: {
                                    cancelSharedChallenge(challenge)
                                }
                            )
                            .id(item.id)
                        case .challengeEvent(let event):
                            NavigationLink {
                                ChallengeDetailView(
                                    challengeID:
                                        event.challengeID
                                )
                            } label: {
                                ThreadChallengeLifecycleEventRow(
                                    event: event
                                )
                            }
                            .buttonStyle(.plain)
                            .id(item.id)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 20)
                .padding(.bottom, 8)
                // A stable end marker works even when the last item is a
                // challenge invitation or lifecycle event rather than a DM.
                Color.clear.frame(height: 1).id("thread-bottom")
            }
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .onChange(of: timeline.last?.id) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("thread-bottom", anchor: .bottom)
                }
            }
            .task(id: conversationID) {
                // Wait for the lazy timeline to be laid out on first open.
                await Task.yield()
                proxy.scrollTo("thread-bottom", anchor: .bottom)
            }
        }
    }

    private var pendingChallengesFromFriend:
        [ATHLTHChallenge] {
        challengeStore
            .incomingInvitations(
                for:
                    session.profile
                        .userID
            )
            .filter {
                $0.creatorID ==
                    friend.userID
            }
            .sorted {
                $0.createdAt >
                    $1.createdAt
            }
    }

    private var outgoingChallengesToFriend:
        [ATHLTHChallenge] {
        challengeStore.visibleChallenges
            .filter { challenge in
                challenge.creatorID ==
                    session.profile.userID &&
                challenge.status !=
                    .completed &&
                challenge.status !=
                    .cancelled &&
                challenge.participants
                    .contains {
                        $0.userID ==
                            friend.userID &&
                        $0.state ==
                            .invited
                    }
            }
            .sorted {
                $0.createdAt >
                    $1.createdAt
            }
    }

    private var challengeLifecycleEventsWithFriend:
        [ThreadChallengeLifecycleEvent] {
        var events:
            [ThreadChallengeLifecycleEvent] = []
        let now = Date()

        for challenge in
            challengeStore.visibleChallenges {
            let isCreator =
                challenge.creatorID ==
                    session.profile.userID
            let isFriendCreator =
                challenge.creatorID ==
                    friend.userID

            guard
                isCreator ||
                isFriendCreator
            else {
                continue
            }

            let participantUserID =
                isCreator
                    ? friend.userID
                    : session.profile.userID

            guard
                let participant =
                    challenge.participants
                        .first(
                            where: {
                                $0.userID ==
                                    participantUserID
                            }
                        )
            else {
                continue
            }

            let kind:
                ThreadChallengeLifecycleKind
            let eventDate: Date

            switch participant.state {
            case .accepted:
                kind = .accepted
                eventDate =
                    participant.respondedAt ??
                    participant.invitedAt

            case .declined:
                kind = .declined
                eventDate =
                    participant.respondedAt ??
                    participant.invitedAt

            case .withdrawn:
                kind = .withdrawn
                eventDate =
                    participant.respondedAt ??
                    participant.invitedAt

            case .invited:
                guard
                    let endsAt =
                        challenge.rules.endsAt,
                    endsAt <= now
                else {
                    continue
                }

                kind = .expired
                eventDate = endsAt

            case .creator:
                continue
            }

            events.append(
                ThreadChallengeLifecycleEvent(
                    challengeID:
                        challenge.id,
                    participantID:
                        participant.id,
                    challengeTitle:
                        challenge.title,
                    kind: kind,
                    message:
                        lifecycleMessage(
                            kind: kind,
                            creatorIsCurrentUser:
                                isCreator
                        ),
                    createdAt:
                        eventDate
                )
            )
        }

        return events.sorted {
            $0.createdAt >
                $1.createdAt
        }
    }

    private func lifecycleMessage(
        kind: ThreadChallengeLifecycleKind,
        creatorIsCurrentUser: Bool
    ) -> String {
        switch kind {
        case .accepted:
            return creatorIsCurrentUser
                ? ATHLTHLocalization.choose(
                    english:
                        "\(friend.resolvedName) accepted the challenge.",
                    norwegian:
                        "\(friend.resolvedName) godtok utfordringen."
                )
                : ATHLTHLocalization.choose(
                    english:
                        "You accepted the challenge.",
                    norwegian:
                        "Du godtok utfordringen."
                )

        case .declined:
            return creatorIsCurrentUser
                ? ATHLTHLocalization.choose(
                    english:
                        "\(friend.resolvedName) declined the challenge.",
                    norwegian:
                        "\(friend.resolvedName) avslo utfordringen."
                )
                : ATHLTHLocalization.choose(
                    english:
                        "You declined the challenge.",
                    norwegian:
                        "Du avslo utfordringen."
                )

        case .withdrawn:
            return creatorIsCurrentUser
                ? ATHLTHLocalization.choose(
                    english:
                        "You withdrew the invite to \(friend.resolvedName).",
                    norwegian:
                        "Du trakk tilbake invitasjonen til \(friend.resolvedName)."
                )
                : ATHLTHLocalization.choose(
                    english:
                        "\(friend.resolvedName) withdrew the challenge invite.",
                    norwegian:
                        "\(friend.resolvedName) trakk tilbake challenge-invitasjonen."
                )

        case .expired:
            return creatorIsCurrentUser
                ? ATHLTHLocalization.choose(
                    english:
                        "The invite expired without a response from \(friend.resolvedName).",
                    norwegian:
                        "Invitasjonen utløp uten svar fra \(friend.resolvedName)."
                )
                : ATHLTHLocalization.choose(
                    english:
                        "The challenge expired before you responded.",
                    norwegian:
                        "Utfordringen utløp før du svarte."
                )
        }
    }

    private func challengeInvitationsWithoutMessages(
        _ messages: [DirectMessageRecord]
    ) -> [(challenge: ATHLTHChallenge, invitedAt: Date)] {
        let referenced = Set(messages.compactMap { message -> UUID? in
            guard message.attachmentKind == .challenge else { return nil }
            return message.sourceObjectID ??
                message.decodeSnapshot(ATHLTHChallenge.self)?.id
        })
        return challengeStore.visibleChallenges.compactMap { challenge in
            guard !referenced.contains(challenge.id),
                  challenge.creatorID == friend.userID ||
                  challenge.creatorID == session.profile.userID
            else { return nil }

            let userID = challenge.creatorID == friend.userID
                ? session.profile.userID : friend.userID
            guard let participant = challenge.participants.first(where: {
                $0.userID == userID && $0.state != .creator
            }) else { return nil }
            return (challenge: challenge, invitedAt: participant.invitedAt)
        }
    }

    private func openChallengeDetails(_ id: UUID) {
        guard challengeStore.challenge(id: id) != nil else {
            plannedInviteError = ATHLTHLocalization.choose(
                english: "This challenge is no longer available.",
                norwegian: "Denne utfordringen er ikke lenger tilgjengelig."
            )
            return
        }
        challengeDetailsDestination = ThreadChallengeDetailsDestination(id: id)
    }

    private func threadTimelineItems(
        messages: [DirectMessageRecord],
        lifecycleEvents: [ThreadChallengeLifecycleEvent],
        challengeInvitations: [(challenge: ATHLTHChallenge, invitedAt: Date)]
    ) -> [ThreadTimelineItem] {
        (
            messages.map { ThreadTimelineItem.message($0) } +
            lifecycleEvents.map { ThreadTimelineItem.challengeEvent($0) } +
            challengeInvitations.map {
                ThreadTimelineItem.challengeInvite($0.challenge, $0.invitedAt)
            }
        )
        .sorted { $0.createdAt < $1.createdAt }
    }

    private var currentConversation: DirectConversationRecord? {
        if let conversationID,
           let exact =
                messaging.conversations.first(
                    where: {
                        $0.id ==
                            conversationID
                    }
                ) {
            return exact
        }

        return messaging.conversation(
            with: friend.userID
        )
    }

    private var isIncomingRequest: Bool {
        guard let currentConversation,
              let currentUserID =
                messaging.currentUserID,
              hasSentRequestMessage
        else {
            return false
        }

        return currentConversation.requestStatus ==
                .pending &&
            currentConversation.requestedBy !=
                nil &&
            currentConversation.requestedBy !=
                currentUserID
    }

    private var isOutgoingRequest: Bool {
        guard let currentConversation,
              let currentUserID =
                messaging.currentUserID
        else {
            return false
        }

        guard currentConversation.requestStatus ==
                .pending
        else {
            return false
        }

        // Opening a non-mutual thread reserves a pending conversation
        // before anyone sends. Until the first real request exists, either
        // participant may become the requester by sending first.
        return !hasSentRequestMessage ||
            currentConversation.requestedBy ==
                currentUserID
    }

    private var hasSentRequestMessage: Bool {
        guard let conversationID else { return false }
        return !messaging.messages(in: conversationID).isEmpty
    }

    @ViewBuilder
    private var bottomBar: some View {
        if isIncomingRequest {
            incomingRequestBar
        } else if isOutgoingRequest && hasSentRequestMessage {
            outgoingRequestBar
        } else {
            composer
        }
    }

    private var incomingRequestBar: some View {
        VStack(spacing: 13) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(
                        cornerRadius: 13,
                        style: .continuous
                    )
                    .fill(
                        ATHLTHTheme
                            .premiumGoldSoft
                    )

                    Image(
                        systemName:
                            "envelope.badge.fill"
                    )
                    .font(
                        .system(
                            size: 16,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .premiumGold
                    )
                }
                .frame(
                    width: 42,
                    height: 42
                )

                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Message request",
                            norwegian:
                                "Meldingsforespørsel"
                        )
                    )
                    .font(
                        .subheadline
                            .weight(.bold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Accept before replying or sharing training.",
                            norwegian:
                                "Godta før du svarer eller deler trening."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
                }

                Spacer()
            }

            if let requestResponseError {
                HStack(spacing: 7) {
                    Image(
                        systemName:
                            "exclamationmark.circle.fill"
                    )

                    Text(
                        requestResponseError
                    )
                    .lineLimit(2)

                    Spacer()
                }
                .font(
                    .caption
                        .weight(.medium)
                )
                .foregroundStyle(
                    .red
                        .opacity(0.82)
                )
            }

            HStack(spacing: 10) {
                Button {
                    respondToIncomingRequest(
                        accept: false
                    )
                } label: {
                    HStack(spacing: 7) {
                        if requestResponseInFlight &&
                            requestResponseAccepting == false {
                            ProgressView()
                                .tint(
                                    ATHLTHTheme
                                        .primaryText
                                )
                        } else {
                            Image(
                                systemName:
                                    "xmark"
                            )
                            .font(
                                .system(
                                    size: 14,
                                    weight: .bold
                                )
                            )
                        }

                        Text(
                            ATHLTHLocalization.choose(
                                english: "Decline",
                                norwegian: "Avslå"
                            )
                        )
                        .font(
                            .subheadline
                                .weight(.semibold)
                        )
                    }
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                    .frame(
                        maxWidth: .infinity
                    )
                    .frame(height: 48)
                    .background(
                        Color.white
                            .opacity(0.76),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .stroke(
                                ATHLTHTheme
                                    .border,
                                lineWidth: 0.9
                            )
                    }
                }
                .buttonStyle(.plain)
                .disabled(
                    requestResponseInFlight
                )
                .opacity(
                    requestResponseInFlight &&
                    requestResponseAccepting == true
                        ? 0.58
                        : 1
                )

                Button {
                    respondToIncomingRequest(
                        accept: true
                    )
                } label: {
                    HStack(spacing: 7) {
                        if requestResponseInFlight &&
                            requestResponseAccepting == true {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(
                                systemName:
                                    "checkmark"
                            )
                            .font(
                                .system(
                                    size: 14,
                                    weight: .bold
                                )
                            )
                        }

                        Text(
                            ATHLTHLocalization.choose(
                                english: "Accept",
                                norwegian: "Godta"
                            )
                        )
                        .font(
                            .subheadline
                                .weight(.bold)
                        )
                    }
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .frame(
                        maxWidth: .infinity
                    )
                    .frame(height: 48)
                    .background(
                        LinearGradient(
                            colors: [
                                ATHLTHTheme
                                    .champagne,
                                ATHLTHTheme
                                    .premiumGold
                            ],
                            startPoint:
                                .topLeading,
                            endPoint:
                                .bottomTrailing
                        ),
                        in: Capsule()
                    )
                    .shadow(
                        color:
                            ATHLTHTheme
                                .premiumGold
                                .opacity(0.20),
                        radius: 10,
                        y: 5
                    )
                }
                .buttonStyle(.plain)
                .disabled(
                    requestResponseInFlight
                )
                .opacity(
                    requestResponseInFlight &&
                    requestResponseAccepting == false
                        ? 0.58
                        : 1
                )

                Menu {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Block",
                            norwegian: "Blokker"
                        ),
                        role: .destructive
                    ) {
                        Task { @MainActor in
                            guard
                                let conversationID,
                                !requestResponseInFlight
                            else {
                                return
                            }

                            requestResponseInFlight =
                                true
                            requestResponseError =
                                nil

                            let declined =
                                await messaging
                                    .respondToMessageRequest(
                                        conversationID,
                                        accept: false
                                    )

                            if declined {
                                await social.block(
                                    friend.userID
                                )
                                await messaging
                                    .refresh(
                                        force: true
                                    )
                                dismiss()
                            } else {
                                requestResponseError =
                                    messaging
                                        .errorMessage ??
                                    ATHLTHLocalization
                                        .choose(
                                            english:
                                                "Could not update the request. Try again.",
                                            norwegian:
                                                "Kunne ikke oppdatere forespørselen. Prøv igjen."
                                        )
                            }

                            requestResponseInFlight =
                                false
                        }
                    }
                } label: {
                    Image(
                        systemName:
                            "ellipsis"
                    )
                    .font(
                        .system(
                            size: 17,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                    .frame(
                        width: 48,
                        height: 48
                    )
                    .background(
                        Color.white
                            .opacity(0.76),
                        in: Circle()
                    )
                    .overlay {
                        Circle()
                            .stroke(
                                ATHLTHTheme
                                    .border,
                                lineWidth: 0.9
                            )
                    }
                }
                .disabled(
                    requestResponseInFlight
                )
            }
        }
        .padding(14)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
        .background(
            LinearGradient(
                colors: [
                    ATHLTHTheme
                        .card,
                    ATHLTHTheme
                        .cardWarm
                        .opacity(0.90)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .stroke(
                Color.white
                    .opacity(0.78),
                lineWidth: 0.9
            )
        }
        .shadow(
            color:
                ATHLTHTheme
                    .accentDeep
                    .opacity(0.08),
            radius: 14,
            y: 6
        )
        .padding(
            .horizontal,
            12
        )
        .padding(
            .vertical,
            8
        )
        .background(
            ATHLTHTheme
                .canvasBottom
                .opacity(0.92)
        )
    }

    private func respondToIncomingRequest(
        accept: Bool
    ) {
        guard
            let conversationID,
            !requestResponseInFlight
        else {
            return
        }

        requestResponseInFlight = true
        requestResponseAccepting = accept
        requestResponseError = nil

        Task { @MainActor in
            let success =
                await messaging
                    .respondToMessageRequest(
                        conversationID,
                        accept: accept
                    )

            requestResponseInFlight = false
            requestResponseAccepting = nil

            guard success else {
                requestResponseError =
                    messaging.errorMessage ??
                    ATHLTHLocalization.choose(
                        english:
                            "Could not update the request. Try again.",
                        norwegian:
                            "Kunne ikke oppdatere forespørselen. Prøv igjen."
                    )
                return
            }

            if !accept {
                dismiss()
            }
        }
    }

    private var outgoingRequestBar: some View {
        HStack(spacing: 11) {
            Image(
                systemName:
                    "paperplane.fill"
            )
            .foregroundStyle(
                ATHLTHTheme
                    .premiumGold
            )
            .frame(
                width: 38,
                height: 38
            )
            .background(
                ATHLTHTheme
                    .premiumGoldSoft,
                in: RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
            )

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Message request sent",
                        norwegian:
                            "Meldingsforespørsel sendt"
                    )
                )
                .font(
                    .subheadline
                        .weight(.semibold)
                )

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "More messages and training items unlock after acceptance.",
                        norwegian:
                            "Flere meldinger og treningsdeling åpnes etter godkjenning."
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
            }

            Spacer()
        }
        .padding(14)
        .background(
            ATHLTHTheme.card,
            in: RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
            .stroke(
                ATHLTHTheme.border,
                lineWidth: 0.8
            )
        }
        .padding(
            .horizontal,
            12
        )
        .padding(
            .vertical,
            8
        )
        .background(
            ATHLTHTheme
                .canvasBottom
                .opacity(0.92)
        )
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if let selectedShare {
                HStack(spacing: 10) {
                    Image(systemName: selectedShare.kind.systemImage)
                        .foregroundStyle(ATHLTHTheme.premiumGold)
                        .frame(width: 34, height: 34)
                        .background(ATHLTHTheme.premiumGoldSoft, in: RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedShare.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text(selectedShare.kind.localizedTitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        self.selectedShare = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14)
            }

            if !mentionSuggestions.isEmpty {
                ATHLTHMentionSuggestionList(
                    suggestions: mentionSuggestions
                ) { suggestion in
                    text = ATHLTHMentionSupport.inserting(
                        suggestion,
                        into: text
                    )
                }
                .padding(.horizontal)
            }

            HStack(alignment: .bottom, spacing: 10) {
                if currentConversation?.requestStatus == .accepted ||
                    (
                        isOutgoingRequest &&
                        !hasSentRequestMessage
                    ) {
                    Button {
                        showingSharePicker = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .foregroundStyle(
                                ATHLTHTheme
                                    .primaryText
                            )
                            .background(
                                Color.white
                                    .opacity(0.86),
                                in: Circle()
                            )
                            .overlay {
                                Circle()
                                    .stroke(
                                        ATHLTHTheme
                                            .border,
                                        lineWidth: 0.8
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(conversationID == nil)
                }

                TextField(
                    isOutgoingRequest
                        ? ATHLTHLocalization.choose(
                            english:
                                "Send one request…",
                            norwegian:
                                "Send én forespørsel …"
                        )
                        : ATHLTHLocalization.choose(
                            english:
                                "Write a message…",
                            norwegian:
                                "Skriv en melding …"
                        ),
                    text: $text,
                    axis: .vertical
                )
                    .focused($composerFocused)
                    .lineLimit(1...5)
                    .submitLabel(.send)
                    .onSubmit {
                        Task {
                            await send()
                        }
                    }
                    .padding(
                        .horizontal,
                        15
                    )
                    .padding(
                        .vertical,
                        11
                    )
                    .background(
                        Color.white
                            .opacity(0.93),
                        in:
                            RoundedRectangle(
                                cornerRadius: 20,
                                style: .continuous
                            )
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: 20,
                            style: .continuous
                        )
                        .stroke(
                            Color.white
                                .opacity(0.92),
                            lineWidth: 0.8
                        )
                    }
                    .shadow(
                        color:
                            ATHLTHTheme
                                .accentDeep
                                .opacity(0.035),
                        radius: 8,
                        y: 3
                    )

                Button {
                    Task { await send() }
                } label: {
                    if isSending {
                        ProgressView()
                            .tint(.white)
                            .frame(width: 44, height: 44)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                }
                .background(
                    // Match the conversation's outgoing message bubble.
                    ATHLTHPlanDesign.outgoingMessage,
                    in: Circle()
                )
                .buttonStyle(.plain)
                .disabled(!canSend || isSending)
                .opacity(canSend ? 1 : 0.45)
            }
            .padding(
                .horizontal,
                14
            )
            .padding(
                .bottom,
                9
            )
        }
        .padding(
            .top,
            9
        )
        .padding(
            .bottom,
            4
        )
        .athlthConversationComposerChrome()
    }

    private var mentionSuggestions: [ATHLTHMentionSuggestion] {
        ATHLTHMentionSupport.suggestions(
            in: text,
            candidates: [friend]
        )
    }

    private var currentUserProfileCard:
        SocialProfileCard {
        SocialProfileCard(
            userID: session.profile.userID,
            username:
                session.profile.username.isEmpty
                    ? nil
                    : session.profile.username,
            displayName:
                session.profile.displayName.isEmpty
                    ? nil
                    : session.profile.displayName,
            bio:
                session.profile.bio.isEmpty
                    ? nil
                    : session.profile.bio,
            avatarURL:
                session.profile.avatarURL?
                    .absoluteString,
            profileVisibility: "public",
            createdAt: nil,
            updatedAt: nil
        )
    }

    private var canSend: Bool {
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        guard let currentConversation else {
            return false
        }

        switch currentConversation.requestStatus {
        case .accepted:
            return hasText || selectedShare != nil
        case .pending:
            return isOutgoingRequest &&
                !hasSentRequestMessage &&
                (
                    hasText ||
                    selectedShare != nil
                )
        case .declined:
            return false
        }
    }

    private func openAndPoll(owner: UUID) async {
        func ownsThread() -> Bool {
            !Task.isCancelled && session.signedIn && !session.previewModeEnabled &&
                session.profile.userID == owner && draftOwner == owner
        }
        do {
            let id = try await messaging.openConversation(with: friend.userID)

            // Keep the thread in its loading state until the backend status
            // and messages have been refreshed. This avoids briefly showing
            // a stale "message request" composer after a pending conversation
            // has already been promoted to accepted.
            guard ownsThread() else { return }
            await messaging.refreshConversation(id)
            guard ownsThread() else { return }
            session.syncApprovedSharedWorkouts(from: messaging.messages(in: id))
            session.syncSharedWorkoutLifecycles(from: messaging.messages(in: id))
            await social.refreshChallenges(
                challengeStore:
                    challengeStore
            )
            guard ownsThread() else { return }
            await social.markChallengeEventsRead(
                from: friend.userID
            )
            guard ownsThread() else { return }
            conversationID = id
            markLocalMessageNotificationsRead(conversationID: id)

            var pollTick = 0
            var lastSafetyPoll = Date()
            while ownsThread() {
                try? await Task.sleep(
                    nanoseconds:
                        4_000_000_000
                )
                guard ownsThread() else { break }

                guard scenePhase == .active else { continue }
                if ATHLTHDirectMessageRefreshPolicy.shouldPoll(
                    realtimeConnected: realtimeConnected,
                    elapsed: Date().timeIntervalSince(lastSafetyPoll)) {
                    lastSafetyPoll = Date()
                    await refreshVisibleThread(id, owner: owner)
                    guard ownsThread() else { return }
                }

                pollTick += 1
                if pollTick.isMultiple(
                    of: 2
                ) {
                    await social
                        .refreshChallenges(
                            challengeStore:
                                challengeStore
                        )
                }
            }
        } catch {
            guard ownsThread() else { return }
            loadError = error.localizedDescription
        }
    }

    private func refreshVisibleThread(_ id: UUID, owner: UUID) async {
        func ownsThread() -> Bool {
            !Task.isCancelled && session.signedIn && !session.previewModeEnabled &&
                session.profile.userID == owner && draftOwner == owner && conversationID == id
        }
        guard ownsThread(), scenePhase == .active else { return }
        let previous = messaging.messages(in: id)
        await messaging.refreshConversation(id, polling: true)
        guard ownsThread() else { return }
        let updated = messaging.messages(in: id)
        if previous != updated {
            session.syncApprovedSharedWorkouts(from: updated)
            session.syncSharedWorkoutLifecycles(from: updated)
        }
    }

    private func markLocalMessageNotificationsRead(conversationID: UUID) {
        for item in notifications.items
        where (item.socialEventKind == "message" ||
               item.socialEventKind == "mention" ||
               item.socialEventKind == "message_request" ||
               item.socialEventKind == "message_request_accepted") &&
              item.socialEntityID == conversationID &&
              item.isUnread {
            notifications.markRead(item.id)
        }
    }

    private func respondToThreadChallenge(
        _ challenge: ATHLTHChallenge,
        accept: Bool
    ) {
        guard respondingToChallengeID == nil,
              let current = challengeStore.challenge(id: challenge.id),
              current.creatorID == friend.userID,
              current.status != .cancelled,
              current.status != .completed,
              current.rules.endsAt.map({ $0 > Date() }) ?? true,
              let participant = challengeStore.invitationParticipant(
                  in: current, userID: session.profile.userID
              ),
              participant.state == .invited
        else { return }

        respondingToChallengeID = current.id
        challengeStore.setParticipantState(
            challengeID: current.id,
            participantID: participant.id,
            state: accept ? .accepted : .declined
        )

        guard let updated = challengeStore.challenge(id: current.id) else {
            respondingToChallengeID = nil
            return
        }

        Task {
            let synced = await social.syncChallenge(updated)
            if synced {
                await social.markChallengeInviteRead(challengeID: current.id)
            } else {
                challengeStore.setParticipantState(
                    challengeID: current.id,
                    participantID: participant.id,
                    state: .invited
                )
                plannedInviteError = social.errorMessage ??
                    ATHLTHLocalization.choose(
                        english: "Please try again.",
                        norwegian: "Prøv igjen."
                    )
            }
            respondingToChallengeID = nil
        }
    }

    private func cancelSharedChallenge(_ challenge: ATHLTHChallenge) {
        guard cancellingChallengeID == nil,
              challenge.creatorID == session.profile.userID,
              challenge.status != .cancelled,
              challenge.status != .completed
        else { return }

        cancellingChallengeID = challenge.id
        Task {
            defer { cancellingChallengeID = nil }
            guard await social.cancelChallenge(challengeID: challenge.id) else {
                cancellationError = social.errorMessage ??
                    ATHLTHLocalization.choose(
                        english: "Could not cancel the challenge.",
                        norwegian: "Kunne ikke avlyse utfordringen."
                    )
                return
            }

            var cancelled = challenge
            cancelled.status = .cancelled
            challengeStore.update(cancelled)

            if let conversationID {
                let body = ATHLTHLocalization.choose(
                    english: "The challenge \(challenge.title) has been cancelled.",
                    norwegian: "Utfordringen \(challenge.title) er avlyst."
                )
                _ = await messaging.send(
                    to: friend.userID,
                    conversationID: conversationID,
                    body: body,
                    attachment: nil
                )
                await messaging.refreshConversation(conversationID)
            }
            await social.refreshChallenges(challengeStore: challengeStore)
        }
    }

    private func withdrawThreadChallenge(
        _ challenge: ATHLTHChallenge
    ) {
        guard
            let participant =
                challenge.participants
                    .first(
                        where: {
                            $0.userID ==
                                friend.userID &&
                            $0.state ==
                                .invited
                        }
                    )
        else {
            return
        }

        Task {
            let withdrawn =
                await social
                    .withdrawChallengeInvite(
                        participantID:
                            participant.id
                    )

            guard withdrawn else {
                return
            }

            challengeStore
                .setParticipantState(
                    challengeID:
                        challenge.id,
                    participantID:
                        participant.id,
                    state: .withdrawn
                )

            await social.refresh(
                challengeStore:
                    challengeStore
            )
        }
    }

    private func send() async {
        guard let conversationID, canSend, !isSending,
              let owner = draftOwner, session.signedIn, !session.previewModeEnabled,
              session.profile.userID == owner else { return }

        isSending = true
        defer { isSending = false }
        let body = text
        let attachment =
            (
                currentConversation?
                    .requestStatus ==
                    .accepted ||
                (
                    isOutgoingRequest &&
                    !hasSentRequestMessage
                )
            )
                ? selectedShare
                : nil

        if await messaging.send(
            to: friend.userID,
            conversationID: conversationID,
            body: body,
            attachment: attachment,
            clearMatchingTextDraft: true
        ) {
            guard session.signedIn, session.profile.userID == owner, draftOwner == owner else { return }
            // Preserve text typed during the network request.
            if text == body {
                text = ""
                messaging.setTextDraft("", for: friend.userID, owner: owner)
            }
            selectedShare = nil
        } else if !Task.isCancelled, session.signedIn, session.profile.userID == owner, draftOwner == owner {
            sendError = messaging.errorMessage ?? ATHLTHLocalization.choose(
                english: "The message could not be confirmed. Your text has been kept.",
                norwegian: "Meldingen kunne ikke bekreftes. Teksten din er beholdt.")
        }
    }

    private func proposalResponse(
        for message: DirectMessageRecord,
        in messages: [DirectMessageRecord]
    ) -> ChallengeChangeProposalResponse? {
        guard message.attachmentKind == .challenge,
              message.shareVersion == 2,
              let proposal = message.decodeSnapshot(ChallengeChangeProposal.self)
        else { return nil }

        return messages
            .filter {
                $0.attachmentKind == .challenge &&
                $0.shareVersion == 3 &&
                $0.senderID == proposal.original.creatorID &&
                $0.createdAt >= message.createdAt
            }
            .sorted { $0.createdAt > $1.createdAt }
            .compactMap {
                $0.decodeSnapshot(ChallengeChangeProposalResponse.self)
            }
            .first { $0.proposalID == proposal.id &&
                $0.challengeID == proposal.challengeID }
    }

    private func reviewChallengeChange(
        _ message: DirectMessageRecord, accept: Bool
    ) {
        guard let proposal = message.decodeSnapshot(ChallengeChangeProposal.self),
              message.shareVersion == 2,
              message.attachmentKind == .challenge,
              proposal.challengerID == friend.userID,
              proposal.original.creatorID == session.profile.userID,
              respondingToProposalID == nil,
              let conversationID
        else { return }

        respondingToProposalID = message.id
        Task {
            defer { respondingToProposalID = nil }
            if accept {
                guard let current = challengeStore.challenge(id: proposal.challengeID),
                      current.creatorID == session.profile.userID,
                      !current.rulesAreLocked,
                      current.status != .completed,
                      current.status != .cancelled,
                      current.title == proposal.original.title,
                      current.sport == proposal.original.sport,
                      current.rules == proposal.original.rules,
                      Set(current.participants.compactMap(\.userID)) ==
                          Set(proposal.original.participants.compactMap(\.userID))
                else {
                    plannedInviteError = ATHLTHLocalization.choose(
                        english: "The challenge has changed or started. Ask for a new proposal.",
                        norwegian: "Utfordringen er endret eller startet. Be om et nytt forslag."
                    )
                    return
                }

                var approved = current
                approved.title = proposal.proposed.title
                approved.sport = proposal.proposed.sport
                approved.rules = proposal.proposed.rules
                approved.visibility = .privateOnly

                // Preserve the current creator identity and participant response
                // state; proposals may change invitees, not impersonate athletes.
                let creator = current.participants.first(where: {
                    $0.userID == current.creatorID
                })
                let proposedInvitees = proposal.proposed.participants.filter {
                    $0.userID != current.creatorID
                }
                guard let creator,
                      !proposedInvitees.isEmpty,
                      proposedInvitees.allSatisfy({ $0.userID != nil }),
                      Set(proposedInvitees.compactMap(\.userID)).count ==
                          proposedInvitees.count,
                      approved.rules.endsAt.map({
                          $0 > approved.rules.startsAt
                      }) ?? true else {
                    plannedInviteError = ATHLTHLocalization.choose(
                        english: "Invalid proposal. Please revise it.",
                        norwegian: "Forslaget er ugyldig. Be om et nytt forslag."
                    )
                    return
                }

                approved.participants = [creator] + proposedInvitees.map {
                    participant in
                    current.participants.first(where: {
                        $0.userID == participant.userID
                    }) ?? participant
                }

                let incomingIDs = Set(proposedInvitees.compactMap(\.userID))
                let withdrawn = current.participants.filter {
                    $0.userID != current.creatorID &&
                    $0.userID.map { !incomingIDs.contains($0) } == true
                }
                guard withdrawn.allSatisfy({ $0.state == .invited }) else {
                    plannedInviteError = ATHLTHLocalization.choose(
                        english: "Accepted participants cannot be removed from an active agreement.",
                        norwegian: "Deltakere som har godtatt, kan ikke fjernes fra avtalen."
                    )
                    return
                }

                guard await social.syncChallenge(approved) else {
                    plannedInviteError = social.errorMessage ??
                        ATHLTHLocalization.choose(
                            english: "Could not approve changes.",
                            norwegian: "Kunne ikke godkjenne endringene."
                        )
                    return
                }
                for participant in withdrawn {
                    guard await social.withdrawChallengeInvite(
                        participantID: participant.id
                    ) else {
                        plannedInviteError = social.errorMessage ??
                            ATHLTHLocalization.choose(
                                english: "Some invitations could not be withdrawn.",
                                norwegian: "Noen invitasjoner kunne ikke trekkes tilbake."
                            )
                        await social.refreshChallenges(challengeStore: challengeStore)
                        return
                    }
                }
                challengeStore.update(approved)
            }

            do {
                let response = ChallengeChangeProposalResponse(
                    proposalID: proposal.id,
                    challengeID: proposal.challengeID,
                    accepted: accept
                )
                let payload = try MessageShareDraft(
                    kind: .challenge,
                    title: proposal.proposed.title,
                    subtitle: accept
                        ? ATHLTHLocalization.choose(
                            english: "Approved", norwegian: "Godkjent"
                        )
                        : ATHLTHLocalization.choose(
                            english: "Rejected", norwegian: "Avslått"
                        ),
                    snapshot: response,
                    sourceObjectID: proposal.challengeID,
                    sourceOwnerID: proposal.original.creatorID,
                    shareVersion: 3
                )
                let sent = await messaging.send(
                    to: friend.userID,
                    conversationID: conversationID,
                    body: accept
                        ? ATHLTHLocalization.choose(
                            english: "I approved the proposed changes.",
                            norwegian: "Jeg har godkjent endringene."
                        )
                        : ATHLTHLocalization.choose(
                            english: "I rejected the proposed changes.",
                            norwegian: "Jeg har avslått endringsforslaget."
                        ),
                    attachment: payload
                )
                if !sent {
                    plannedInviteError = messaging.errorMessage ??
                        ATHLTHLocalization.choose(
                            english: "Could not deliver the decision.",
                            norwegian: "Kunne ikke sende svaret."
                        )
                } else {
                    await messaging.refreshConversation(conversationID)
                }
            } catch {
                plannedInviteError = error.localizedDescription
            }
        }
    }

    private func workoutChangeDecision(
        for message: DirectMessageRecord,
        in messages: [DirectMessageRecord]
    ) -> WorkoutChangeDecision? {
        guard message.attachmentKind == .workout,
              message.shareVersion == 4,
              let proposal = message.decodeSnapshot(WorkoutChangeProposal.self)
        else { return nil }
        return messages
            .filter {
                $0.attachmentKind == .workout &&
                $0.shareVersion == 5 &&
                $0.sourceObjectID == proposal.workoutID &&
                $0.senderID == proposal.ownerID
            }
            .sorted { $0.createdAt > $1.createdAt }
            .compactMap { $0.decodeSnapshot(WorkoutChangeDecision.self) }
            .first { $0.proposalID == proposal.id }
    }

    /// Only the original organizer may update or cancel an invitation.
    private func latestWorkoutLifecycle(
        for invitation: DirectMessageRecord,
        in messages: [DirectMessageRecord]
    ) -> WorkoutInviteLifecycleUpdate? {
        guard invitation.attachmentKind == .workout,
              invitation.shareVersion == 2,
              let sourceID = invitation.sourceObjectID else { return nil }
        if let cancelled = PlannedWorkoutWithdrawalPolicy.cancellation(
            in: messages, sourceID: sourceID, organizerID: invitation.senderID,
            recipientID: invitation.recipientID
        ) { return cancelled }
        return messages
            .filter {
                $0.deletedAt == nil &&
                $0.attachmentKind == .workout &&
                $0.shareVersion == 6 &&
                $0.sourceObjectID == sourceID &&
                $0.sourceOwnerID == invitation.senderID &&
                $0.senderID == invitation.senderID &&
                $0.recipientID == invitation.recipientID
            }
            .sorted { $0.createdAt > $1.createdAt }
            .compactMap {
                $0.decodeSnapshot(WorkoutInviteLifecycleUpdate.self)
            }
            .first {
                $0.sourceWorkoutID == sourceID &&
                $0.organizerID == invitation.senderID
            }
    }

    private func latestAgreedWorkout(
        for invitation: DirectMessageRecord,
        in messages: [DirectMessageRecord]
    ) -> PlannedSession? {
        guard invitation.shareVersion == 2,
              let id = invitation.sourceObjectID else { return nil }
        return messages
            .filter {
                $0.attachmentKind == .workout &&
                $0.shareVersion == 5 &&
                $0.sourceObjectID == id &&
                $0.senderID == invitation.senderID
            }
            .sorted { $0.createdAt > $1.createdAt }
            .compactMap { $0.decodeSnapshot(WorkoutChangeDecision.self) }
            .first { $0.approved && $0.workoutID == id }?
            .approvedWorkout
    }

    /// Organizer lifecycle revisions supersede the original invitation
    /// snapshot. This allows both people to keep proposing on the same
    /// source ID without proposals accidentally reverting newer exercises.
    private func latestSharedWorkout(
        for invitation: DirectMessageRecord,
        in messages: [DirectMessageRecord]
    ) -> PlannedSession? {
        let lifecycle = latestWorkoutLifecycle(
            for: invitation, in: messages
        )
        if lifecycle?.kind == .cancelled { return nil }
        // Approved proposals can arrive after an organizer's update. Choose
        // the chronologically latest authorized revision, not always the
        // version-6 message even when it is already superseded.
        let ownerMessages = messages.filter {
            $0.attachmentKind == .workout &&
            $0.sourceObjectID == invitation.sourceObjectID &&
            $0.senderID == invitation.senderID
        }
        let latestOwnerUpdate = ownerMessages
            .filter { $0.shareVersion == 6 }
            .max { $0.createdAt < $1.createdAt }
        let latestApproval = ownerMessages
            .filter {
                $0.shareVersion == 5 &&
                $0.decodeSnapshot(WorkoutChangeDecision.self)?.approved == true
            }
            .max { $0.createdAt < $1.createdAt }
        if let latestApproval,
           latestApproval.createdAt > (latestOwnerUpdate?.createdAt ?? .distantPast),
           let approved = latestApproval
                .decodeSnapshot(WorkoutChangeDecision.self)?.approvedWorkout {
            return approved
        }
        return lifecycle?.updatedWorkout ??
            latestAgreedWorkout(for: invitation, in: messages)
    }

    private func sendWorkoutChangeProposal(
        invitation: DirectMessageRecord,
        proposed: PlannedSession,
        basedOn: PlannedSession? = nil
    ) {
        guard invitation.attachmentKind == .workout,
              invitation.shareVersion == 2,
              invitation.senderID == friend.userID,
              let original = invitation.decodeSnapshot(PlannedSession.self),
              let conversationID,
              proposed.id == original.id,
              original.scheduledStart.map({ $0 > Date() }) ?? true
        else { return }

        let messages = messaging.messages(in: conversationID)
        guard latestWorkoutLifecycle(
            for: invitation, in: messages
        )?.kind != .cancelled else {
            plannedInviteError = ATHLTHLocalization.choose(
                english: "This shared workout was cancelled.",
                norwegian: "Denne fellesøkten er avlyst."
            )
            return
        }
        let agreed = latestSharedWorkout(
            for: invitation, in: messages
        ) ?? original
        if let basedOn {
            let changedSinceOpening = WorkoutChangeComparison.rows(
                WorkoutChangeProposal(
                    id: UUID(),
                    proposedBy: session.profile.userID,
                    ownerID: invitation.senderID,
                    original: basedOn,
                    proposed: agreed,
                    submittedAt: Date()
                )
            )
            guard changedSinceOpening.isEmpty else {
                plannedInviteError = ATHLTHLocalization.choose(
                    english: "The shared workout changed while you were editing. Reopen it before sending your exercises.",
                    norwegian: "Fellesøkten ble oppdatert mens du redigerte. Åpne den på nytt før du sender øvelsene."
                )
                return
            }
        }
        let proposal = WorkoutChangeProposal(
            id: UUID(),
            proposedBy: session.profile.userID,
            ownerID: invitation.senderID,
            original: agreed,
            proposed: proposed,
            submittedAt: Date()
        )
        guard WorkoutInviteExercisePolicy.canPropose(
            original: agreed, proposed: proposed
        ) else {
            plannedInviteError = ATHLTHLocalization.choose(
                english: "The organizer has not allowed adding new exercises to this workout.",
                norwegian: "Arrangøren har ikke tillatt at du legger til nye øvelser i denne økten."
            )
            return
        }
        guard proposal.hasChanges else {
            plannedInviteError = ATHLTHLocalization.choose(
                english: "Change at least one detail before sending.",
                norwegian: "Endre minst én detalj før du sender."
            )
            return
        }

        Task {
            do {
                let payload = try MessageShareDraft(
                    kind: .workout,
                    title: proposed.title,
                    subtitle: ATHLTHLocalization.choose(
                        english: "Workout changes pending approval",
                        norwegian: "Øktendringer venter på godkjenning"
                    ),
                    snapshot: proposal,
                    sourceObjectID: original.id,
                    sourceOwnerID: invitation.senderID,
                    shareVersion: 4
                )
                let sent = await messaging.send(
                    to: invitation.senderID,
                    conversationID: conversationID,
                    body: ATHLTHLocalization.choose(
                        english: "I suggest changes to our workout. See the red details.",
                        norwegian: "Jeg foreslår endringer i økten vår. Se detaljene merket rødt."
                    ),
                    attachment: payload
                )
                if !sent {
                    plannedInviteError = messaging.errorMessage ??
                        ATHLTHLocalization.choose(
                            english: "Could not send the changes.",
                            norwegian: "Kunne ikke sende endringene."
                        )
                } else {
                    await messaging.refreshConversation(conversationID)
                }
            } catch {
                plannedInviteError = error.localizedDescription
            }
        }
    }

    private func reviewWorkoutProposal(
        _ message: DirectMessageRecord, approve: Bool
    ) {
        guard message.shareVersion == 4,
              message.attachmentKind == .workout,
              let proposal = message.decodeSnapshot(WorkoutChangeProposal.self),
              proposal.ownerID == session.profile.userID,
              proposal.proposedBy == friend.userID,
              message.senderID == friend.userID,
              respondingToWorkoutProposalID == nil,
              let conversationID
        else { return }

        respondingToWorkoutProposalID = message.id
        Task {
            defer { respondingToWorkoutProposalID = nil }
            var revision: PlannedSession?
            if approve {
                let inStandalone = session.standalonePlannedSessions.contains {
                    $0.id == proposal.workoutID
                }
                let inPlan = session.activePlan.flatMap { plan in
                    plan.weeks.flatMap(\.days).flatMap(\.sessions)
                        .first(where: { $0.id == proposal.workoutID })
                }
                guard let current = session.standalonePlannedSessions.first(
                    where: { $0.id == proposal.workoutID }
                ) ?? inPlan,
                current.id == proposal.original.id,
                current.scheduledStart.map({ $0 > Date() }) ?? true,
                WorkoutChangeComparison.rows(WorkoutChangeProposal(
                    id: proposal.id,
                    proposedBy: proposal.proposedBy,
                    ownerID: proposal.ownerID,
                    original: proposal.original,
                    proposed: current,
                    submittedAt: proposal.submittedAt
                )).isEmpty,
                proposal.proposed.id == current.id,
                WorkoutInviteExercisePolicy.canPropose(
                    original: current, proposed: proposal.proposed
                ),
                !proposal.proposed.title
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                proposal.proposed.scheduledStart.map({ $0 > Date() }) ?? true
                else {
                    plannedInviteError = ATHLTHLocalization.choose(
                        english: "The workout has changed or started. Ask for a new proposal.",
                        norwegian: "Økten er endret eller startet. Be om et nytt forslag."
                    )
                    return
                }
                var approved = proposal.proposed
                // The original creator's gear and music preferences are
                // private and must never be replaced by the recipient.
                approved.gearIDs = current.gearIDs
                approved.spotifyPlaylist = current.spotifyPlaylist
                approved.spotifyAutoplayOnStart = current.spotifyAutoplayOnStart
                // Invitee-supplied changes cannot alter organizer permissions,
                // ownership or the identity of the invited athlete.
                approved.allowInviteeExercises = current.allowInviteeExercises
                approved.invitedPartnerID = current.invitedPartnerID
                approved.trainTogetherMode = current.trainTogetherMode
                approved.sharedSourceOwnerID = current.sharedSourceOwnerID
                approved.sharedSourceSessionID = current.sharedSourceSessionID
                revision = approved

                if inStandalone {
                    session.updateStandalonePlannedSession(approved)
                } else if let planID = session.activePlan?.id {
                    session.updateSession(approved, inPlan: planID)
                }
            }

            do {
                let decision = WorkoutChangeDecision(
                    proposalID: proposal.id,
                    workoutID: proposal.workoutID,
                    approved: approve,
                    approvedWorkout: revision
                )
                let payload = try MessageShareDraft(
                    kind: .workout,
                    title: proposal.proposed.title,
                    subtitle: approve
                        ? ATHLTHLocalization.choose(
                            english: "Changes approved", norwegian: "Endringene er godkjent"
                        )
                        : ATHLTHLocalization.choose(
                            english: "Changes declined", norwegian: "Endringene er avslått"
                        ),
                    snapshot: decision,
                    sourceObjectID: proposal.workoutID,
                    sourceOwnerID: proposal.ownerID,
                    shareVersion: 5
                )
                let sent = await messaging.send(
                    to: friend.userID,
                    conversationID: conversationID,
                    body: approve
                        ? ATHLTHLocalization.choose(
                            english: "I approved your changes to our workout.",
                            norwegian: "Jeg har godkjent endringene i økten vår."
                        )
                        : ATHLTHLocalization.choose(
                            english: "I declined the proposed changes.",
                            norwegian: "Jeg har avslått endringsforslaget."
                        ),
                    attachment: payload
                )
                if !sent {
                    plannedInviteError = messaging.errorMessage ??
                        ATHLTHLocalization.choose(
                            english: "Could not deliver the decision.",
                            norwegian: "Kunne ikke sende svaret."
                        )
                } else {
                    await messaging.refreshConversation(conversationID)
                }
            } catch {
                plannedInviteError = error.localizedDescription
            }
        }
    }

    private func plannedInviteResponse(
        for invitation: DirectMessageRecord,
        in messages: [DirectMessageRecord]
    ) -> PlannedWorkoutInviteResponse? {
        guard invitation.attachmentKind == .workout,
              invitation.shareVersion == 2,
              let sourceID = invitation.sourceObjectID else { return nil }
        let responderID = invitation.senderID == session.profile.userID
            ? friend.userID : session.profile.userID
        return messages
            .filter {
                $0.attachmentKind == .workout &&
                $0.shareVersion == 3 &&
                $0.sourceObjectID == sourceID &&
                $0.senderID == responderID
            }
            .sorted { $0.createdAt > $1.createdAt }
            .compactMap {
                $0.decodeSnapshot(PlannedWorkoutInviteResponse.self)
            }
            .first { $0.sourceWorkoutID == sourceID }
    }

    private func withdrawPlannedInvite(_ invitation: DirectMessageRecord) {
        guard invitation.senderID == session.profile.userID,
              invitation.shareVersion == 2, invitation.attachmentKind == .workout,
              respondingToPlannedInviteID == nil,
              let sourceID = invitation.sourceObjectID else { return }
        respondingToPlannedInviteID = invitation.id
        Task {
            defer { respondingToPlannedInviteID = nil }
            do {
                try await messaging.withdrawPlannedWorkout(
                    sourceID: sourceID, session: session, social: social)
            } catch {
                plannedInviteError = error.localizedDescription
            }
        }
    }

    private func respondToPlannedInvite(
        _ invitation: DirectMessageRecord,
        accept: Bool
    ) {
        guard invitation.senderID == friend.userID,
              invitation.attachmentKind == .workout,
              invitation.shareVersion == 2,
              respondingToPlannedInviteID == nil,
              let conversationID,
              let originalWorkout = invitation.decodeSnapshot(PlannedSession.self),
              let sourceID = invitation.sourceObjectID
        else { return }

        let lifecycle = latestWorkoutLifecycle(
            for: invitation, in: messaging.messages(in: conversationID)
        )
        guard lifecycle?.kind != .cancelled else {
            plannedInviteError = ATHLTHLocalization.choose(
                english: "The organizer cancelled this workout.",
                norwegian: "Arrangøren har avlyst denne økten."
            )
            return
        }
        let workout = latestSharedWorkout(
            for: invitation, in: messaging.messages(in: conversationID)
        ) ?? originalWorkout
        let currentMessages = messaging.messages(in: conversationID)
        guard plannedInviteResponse(for: invitation, in: currentMessages) == nil,
              PlannedWorkoutInvitationPresentationState.resolve(
                start: workout.scheduledStart,
                decision: nil,
                organizerCancelled: lifecycle?.kind == .cancelled
              ).canRespond else {
            plannedInviteError = ATHLTHLocalization.choose(
                english: "This invitation has ended. Ask for a new invitation.",
                norwegian: "Invitasjonen er avlyst eller allerede besvart. Be om en ny invitasjon."
            )
            return
        }
        respondingToPlannedInviteID = invitation.id
        Task {
            defer { respondingToPlannedInviteID = nil }
            do {
                let fresh = try await SupabaseMessagingService()
                    .loadPlannedWorkoutInvitationMessages(sourceWorkoutID: sourceID)
                guard PlannedWorkoutWithdrawalPolicy.cancellation(
                    in: fresh, sourceID: sourceID, organizerID: invitation.senderID,
                    recipientID: invitation.recipientID
                ) == nil, plannedInviteResponse(for: invitation, in: fresh) == nil else {
                    await messaging.refreshConversation(conversationID)
                    plannedInviteError = ATHLTHLocalization.choose(
                        english: "This invitation is no longer open.",
                        norwegian: "Invitasjonen er ikke lenger åpen.")
                    return
                }
                let decision: PlannedWorkoutInviteDecision = accept
                    ? .accepted : .declined
                let response = PlannedWorkoutInviteResponse(
                    sourceWorkoutID: sourceID,
                    decision: decision
                )
                let shared = try MessageShareDraft(
                    kind: .workout,
                    title: workout.title,
                    subtitle: accept
                        ? ATHLTHLocalization.choose(
                            english: "Invitation accepted", norwegian: "Invitasjonen er godtatt"
                        )
                        : ATHLTHLocalization.choose(
                            english: "Invitation declined", norwegian: "Invitasjonen er avslått"
                        ),
                    snapshot: response,
                    sourceObjectID: sourceID,
                    sourceOwnerID: invitation.senderID,
                    shareVersion: 3
                )
                let body = accept
                    ? ATHLTHLocalization.choose(
                        english: "I will join the planned workout.",
                        norwegian: "Jeg blir med på den planlagte økten."
                    )
                    : ATHLTHLocalization.choose(
                        english: "I cannot join this workout.",
                        norwegian: "Jeg kan ikke bli med på denne økten."
                    )
                guard await messaging.send(
                    to: friend.userID,
                    conversationID: conversationID,
                    body: body,
                    attachment: shared
                ) else {
                    plannedInviteError = messaging.errorMessage ??
                        ATHLTHLocalization.choose(
                            english: "Could not send a response.",
                            norwegian: "Kunne ikke sende svar."
                        )
                    return
                }

                let confirmed = try await SupabaseMessagingService()
                    .loadPlannedWorkoutInvitationMessages(sourceWorkoutID: sourceID)
                if PlannedWorkoutWithdrawalPolicy.cancellation(
                    in: confirmed, sourceID: sourceID, organizerID: invitation.senderID,
                    recipientID: invitation.recipientID
                ) != nil {
                    session.syncSharedWorkoutLifecycles(from: confirmed)
                    await messaging.refreshConversation(conversationID)
                    plannedInviteError = ATHLTHLocalization.choose(
                        english: "The invitation was withdrawn.",
                        norwegian: "Invitasjonen ble trukket tilbake.")
                    return
                }
                if accept {
                    var copy = workout
                    copy.gearIDs = []
                    copy.spotifyPlaylist = nil
                    copy.spotifyAutoplayOnStart = false
                    copy.sharedSourceOwnerID = invitation.senderID
                    copy.sharedSourceSessionID = sourceID
                    if copy.scheduledStart != nil {
                        session.addStandalonePlannedSession(copy)
                    } else {
                        session.saveSharedWorkout(
                            copy,
                            sourceOwnerID: invitation.senderID,
                            sourceSessionID: sourceID
                        )
                    }
                }
                await messaging.refreshConversation(conversationID)
            } catch {
                plannedInviteError = error.localizedDescription
            }
        }
    }

    private func saveAttachment(_ message: DirectMessageRecord) {
        // Special response versions apply only to their attachment kind.
        // A legitimate version-2/3/4 training plan must still be saveable.
        if message.attachmentKind == .workout &&
           [2, 3, 4, 5].contains(message.shareVersion) {
            return
        }
        if message.attachmentKind == .challenge &&
           message.shareVersion == 2 {
            return
        }

        guard message.senderID != messaging.currentUserID else { return }

        switch message.attachmentKind {
        case .workout:
            if let workout = message.decodeSnapshot(PlannedSession.self) {
                session.saveSharedWorkout(
                    workout,
                    sourceOwnerID: message.sourceOwnerID,
                    sourceSessionID: message.sourceObjectID
                )
                savedFeedback = "\(workout.title) was saved to your workout library."
            }

        case .exercise:
            // Recipients review/import an exercise in the library detail
            // screen. Never auto-import as a consequence of opening the inbox.
            break

        case .trainingPlan:
            if let plan = message.decodeSnapshot(TrainingPlan.self) {
                session.saveSharedPlan(
                    plan,
                    sourceOwnerID: message.sourceOwnerID,
                    sourcePlanID: message.sourceObjectID,
                    sourceVersion: message.shareVersion
                )
                savedFeedback = "\(plan.title) was saved as your own private copy."
            }

        case .runningWorkout:
            if let workout = message.decodeSnapshot(RunningWorkoutTemplate.self) {
                _ = runningLibrary.saveShared(
                    workout,
                    sourceOwnerID: message.sourceOwnerID,
                    sourceWorkoutID: message.sourceObjectID
                )
                savedFeedback = "\(workout.title) was saved to Running Workouts."
            }

        case .route:
            if let route = message.decodeSnapshot(TrainingRoute.self) {
                session.saveSharedRoute(
                    route,
                    sourceOwnerID: message.sourceOwnerID,
                    sourceRouteID: message.sourceObjectID
                )
                savedFeedback = "\(route.title) was saved as a private route."
            }

        case .challenge:
            if let challengeID = message.sourceObjectID ??
                message.decodeSnapshot(ATHLTHChallenge.self)?.id {
                openChallengeDetails(challengeID)
            }

        case .none:
            break
        }
    }
}

private struct ThreadChallengeDetailsDestination: Identifiable {
    let id: UUID
}

private enum ThreadTimelineItem: Identifiable {
    case message(DirectMessageRecord)
    case challengeInvite(ATHLTHChallenge, Date)
    case challengeEvent(
        ThreadChallengeLifecycleEvent
    )

    var id: String {
        switch self {
        case .message(let message):
            return "message:" + message.id.uuidString
        case .challengeInvite(let challenge, _):
            return "challenge-invite:" + challenge.id.uuidString
        case .challengeEvent(let event):
            return "challenge-event:" +
                event.id
        }
    }

    var createdAt: Date {
        switch self {
        case .message(let message):
            return message.createdAt
        case .challengeInvite(_, let date):
            return date
        case .challengeEvent(let event):
            return event.createdAt
        }
    }
}

private enum ThreadChallengeLifecycleKind: String {
    case accepted
    case declined
    case withdrawn
    case expired

    var systemImage: String {
        switch self {
        case .accepted:
            return "checkmark.circle.fill"
        case .declined:
            return "xmark.circle.fill"
        case .withdrawn:
            return "arrow.uturn.backward.circle.fill"
        case .expired:
            return "clock.badge.xmark"
        }
    }
}

private struct ThreadChallengeLifecycleEvent: Identifiable {
    var id: String {
        challengeID.uuidString +
        ":" +
        participantID.uuidString +
        ":" +
        kind.rawValue
    }

    let challengeID: UUID
    let participantID: UUID
    let challengeTitle: String
    let kind: ThreadChallengeLifecycleKind
    let message: String
    let createdAt: Date
}

private struct ThreadChallengeLifecycleEventRow: View {
    let event: ThreadChallengeLifecycleEvent

    var body: some View {
        HStack(spacing: 10) {
            Image(
                systemName:
                    event.kind
                        .systemImage
            )
            .font(
                .system(
                    size: 13,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                ATHLTHTheme
                    .premiumGold
            )
            .frame(
                width: 30,
                height: 30
            )
            .background(
                ATHLTHTheme
                    .accentSoft,
                in: Circle()
            )

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(event.message)
                    .font(
                        .caption
                            .weight(.semibold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )

                Text(
                    event.challengeTitle +
                    " · " +
                    event.createdAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                .font(.caption2)
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
                .lineLimit(1)
            }

            Spacer()

            Image(
                systemName:
                    "chevron.right"
            )
            .font(
                .caption
                    .weight(.semibold)
            )
            .foregroundStyle(
                ATHLTHTheme
                    .mutedText
            )
        }
        .padding(
            .horizontal,
            12
        )
        .padding(
            .vertical,
            10
        )
        .background(
            Color.white
                .opacity(0.64),
            in: RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
        )
    }
}

private struct ThreadOutgoingChallengeCard: View {
    let challenge: ATHLTHChallenge
    let onCancel: () -> Void

    @State private var showingCancelConfirmation = false

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            HStack(spacing: 12) {
                Image(
                    systemName:
                        "paperplane.fill"
                )
                .font(
                    .system(
                        size: 16,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .accentDeep
                )
                .frame(
                    width: 42,
                    height: 42
                )
                .background(
                    ATHLTHTheme
                        .accentSoft,
                    in: RoundedRectangle(
                        cornerRadius: 13,
                        style: .continuous
                    )
                )

                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text(
                        ATHLTHLocalization
                            .choose(
                                english:
                                    "Sent · waiting for response",
                                norwegian:
                                    "Sendt · venter på svar"
                            )
                    )
                    .font(
                        .caption2
                            .weight(.bold)
                    )
                    .tracking(0.6)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )

                    Text(
                        challenge.title
                    )
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                    .lineLimit(1)

                    Text(
                        challenge.sport.title +
                        " · " +
                        challenge.rules
                            .scoring.title
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                    .lineLimit(1)
                }

                Spacer()
            }

            HStack(spacing: 9) {
                NavigationLink {
                    ChallengeDetailView(
                        challengeID:
                            challenge.id
                    )
                } label: {
                    Text(
                        ATHLTHLocalization
                            .choose(
                                english:
                                    "View",
                                norwegian:
                                    "Vis"
                            )
                    )
                    .frame(
                        maxWidth:
                            .infinity
                    )
                }
                .buttonStyle(.bordered)

                Button(
                    role: .destructive
                ) {
                    showingCancelConfirmation = true
                } label: {
                    Text(
                        ATHLTHLocalization
                            .choose(
                                english:
                                    "Cancel invite",
                                norwegian:
                                    "Avlys invitasjon"
                            )
                    )
                    .frame(
                        maxWidth:
                            .infinity
                    )
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [
                    Color.white
                        .opacity(0.98),
                    ATHLTHTheme
                        .cardWarm
                        .opacity(0.88)
                ],
                startPoint:
                    .topLeading,
                endPoint:
                    .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
            .stroke(
                ATHLTHTheme
                    .accentDeep
                    .opacity(0.12),
                lineWidth: 0.9
            )
        }
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english:
                    "Cancel this challenge invite?",
                norwegian:
                    "Avlyse denne challenge-invitasjonen?"
            ),
            isPresented:
                $showingCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                ATHLTHLocalization.choose(
                    english:
                        "Cancel invite",
                    norwegian:
                        "Avlys invitasjon"
                ),
                role: .destructive,
                action: onCancel
            )

            Button(
                ATHLTHLocalization.choose(
                    english:
                        "Keep invite",
                    norwegian:
                        "Behold invitasjonen"
                ),
                role: .cancel
            ) {}
        }
    }
}

private struct ThreadChallengeRequestCard: View {
    let challenge: ATHLTHChallenge
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            NavigationLink {
                ChallengeDetailView(
                    challengeID:
                        challenge.id
                )
            } label: {
                HStack(spacing: 12) {
                    Image(
                        systemName:
                            challenge.sport
                                .systemImage
                    )
                    .font(
                        .system(
                            size: 17,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .accentDeep
                    )
                    .frame(
                        width: 42,
                        height: 42
                    )
                    .background(
                        ATHLTHTheme
                            .accentSoft,
                        in: RoundedRectangle(
                            cornerRadius: 13,
                            style:
                                .continuous
                        )
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text(
                            ATHLTHLocalization
                                .choose(
                                    english:
                                        "Challenge",
                                    norwegian:
                                        "Utfordring"
                                )
                        )
                        .font(
                            .caption2
                                .weight(.bold)
                        )
                        .tracking(1)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )

                        Text(
                            challenge.title
                        )
                        .font(
                            .subheadline
                                .weight(.semibold)
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .primaryText
                        )
                        .lineLimit(1)

                        Text(
                            challenge.sport
                                .title +
                            " · " +
                            challenge.rules
                                .scoring.title
                        )
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                        .lineLimit(1)
                    }

                    Spacer()

                    Image(
                        systemName:
                            "chevron.right"
                    )
                    .font(
                        .caption.bold()
                    )
                    .foregroundStyle(
                        .tertiary
                    )
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 9) {
                Button(
                    ATHLTHLocalization
                        .choose(
                            english:
                                "Decline",
                            norwegian:
                                "Avslå"
                        ),
                    action:
                        onDecline
                )
                .buttonStyle(.bordered)
                .frame(
                    maxWidth:
                        .infinity
                )

                Button(
                    ATHLTHLocalization
                        .choose(
                            english:
                                "Accept",
                            norwegian:
                                "Godta"
                        ),
                    action:
                        onAccept
                )
                .buttonStyle(
                    .borderedProminent
                )
                .tint(
                    ATHLTHTheme
                        .accentDeep
                )
                .frame(
                    maxWidth:
                        .infinity
                )
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [
                    Color.white
                        .opacity(0.98),
                    ATHLTHTheme
                        .cardWarm
                        .opacity(0.92)
                ],
                startPoint:
                    .topLeading,
                endPoint:
                    .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
            .stroke(
                ATHLTHTheme
                    .premiumGold
                    .opacity(0.18),
                lineWidth: 0.9
            )
        }
    }
}

/// Inline invitation used by both backend challenges and chat attachments.
private struct ThreadChallengeInvitationBubble: View {
    let challenge: ATHLTHChallenge?
    let fallbackTitle: String
    let fallbackSubtitle: String?
    let currentUserID: UUID?
    let friendUserID: UUID
    let isMine: Bool
    let responding: Bool
    let onDetails: () -> Void
    let onAccept: () -> Void
    let onDecline: () -> Void
    let cancelling: Bool
    let onCancel: () -> Void
    @State private var confirmCancellation = false

    private var invitee: ChallengeParticipant? {
        guard let challenge, let currentUserID else { return nil }
        let inviteeID = challenge.creatorID == currentUserID
            ? friendUserID : currentUserID
        return challenge.participants.first(where: { $0.userID == inviteeID })
    }

    private var expired: Bool {
        if let date = challenge?.rules.endsAt { return date <= Date() }
        return false
    }

    private var mayRespond: Bool {
        guard let challenge, let currentUserID else { return false }
        return challenge.creatorID != currentUserID &&
            !isMine && invitee?.state == .invited &&
            !expired && challenge.status != .cancelled &&
            challenge.status != .completed
    }

    private var status: (text: String, icon: String) {
        guard let challenge else {
            return (ATHLTHLocalization.choose(
                english: "No longer available",
                norwegian: "Ikke lenger tilgjengelig"
            ), "exclamationmark.circle")
        }
        if challenge.status == .cancelled {
            return (ATHLTHLocalization.choose(
                english: "CANCELLED", norwegian: "AVLYST"
            ), "xmark.octagon.fill")
        }
        switch invitee?.state {
        case .accepted:
            return (ATHLTHLocalization.choose(
                english: "Accepted", norwegian: "Godtatt"
            ), "checkmark.circle.fill")
        case .declined:
            return (ATHLTHLocalization.choose(
                english: "Declined", norwegian: "Avslått"
            ), "xmark.circle.fill")
        case .withdrawn:
            return (ATHLTHLocalization.choose(
                english: "Withdrawn", norwegian: "Trukket tilbake"
            ), "arrow.uturn.backward")
        case .invited:
            if expired || challenge.status == .completed {
                return (ATHLTHLocalization.choose(
                    english: "Expired", norwegian: "Utløpt"
                ), "clock.badge.xmark")
            }
            return isMine
                ? (ATHLTHLocalization.choose(
                    english: "Waiting for a reply",
                    norwegian: "Venter på svar"
                ), "clock")
                : (ATHLTHLocalization.choose(
                    english: "Awaiting your response",
                    norwegian: "Venter på ditt svar"
                ), "clock")
        case .creator, .none:
            return (ATHLTHLocalization.choose(
                english: "Shared challenge",
                norwegian: "Delt utfordring"
            ), "bolt.fill")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onDetails) {
                HStack(alignment: .top, spacing: 10) {
                    if let challenge {
                        ChallengeCoverArtworkView(
                            sport: challenge.sport,
                            artworkName: challenge.rules.coverArtworkName,
                            remoteURL: challenge.rules.coverImageURL
                        )
                        .frame(width: 58, height: 62)
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                        .overlay {
                            RoundedRectangle(cornerRadius: 11)
                                .stroke(Color.white.opacity(0.84), lineWidth: 0.8)
                        }
                        .accessibilityHidden(true)
                    } else {
                    Image(systemName: challenge?.sport.systemImage ?? "bolt.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                        .frame(width: 42, height: 42)
                        .background(Color.white.opacity(0.70),
                            in: RoundedRectangle(cornerRadius: 13))
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(ATHLTHLocalization.choose(
                            english: "ATHLTH · CHALLENGE",
                            norwegian: "ATHLTH · UTFORDRING"
                        ))
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                        Text(challenge?.title ?? fallbackTitle)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(ATHLTHTheme.primaryText)
                            .multilineTextAlignment(.leading)
                        Text(challenge.map {
                            $0.sport.title + " · " + $0.rules.scoring.title
                        } ?? fallbackSubtitle ?? "")
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(challenge == nil)

            Label(status.text, systemImage: status.icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(challenge?.status == .cancelled ? Color.red :
                    invitee?.state == .declined ? Color.red :
                    ATHLTHTheme.accentDeep)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.59), in: Capsule())

            if let endsAt = challenge?.rules.endsAt {
                Label(
                    endsAt.formatted(date: .abbreviated, time: .shortened),
                    systemImage: "calendar"
                )
                .font(.caption2)
                .foregroundStyle(ATHLTHTheme.mutedText)
            }

            if isMine,
               challenge?.status != .cancelled,
               challenge?.status != .completed {
                Button(role: .destructive) {
                    confirmCancellation = true
                } label: {
                    HStack {
                        if cancelling { ProgressView().controlSize(.mini) }
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Cancel challenge", norwegian: "Avlys utfordring"
                            ),
                            systemImage: "xmark.circle"
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(cancelling)
            }

            if mayRespond {
                HStack(spacing: 8) {
                    Button(action: onDecline) {
                        Text(ATHLTHLocalization.choose(
                            english: "Decline", norwegian: "Avslå"
                        ))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button(action: onAccept) {
                        HStack(spacing: 5) {
                            if responding {
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
                .disabled(responding)
            }

            Button(action: onDetails) {
                HStack(spacing: 6) {
                    Text(ATHLTHLocalization.choose(
                        english: "View details", norwegian: "Se detaljer"
                    ))
                    Image(systemName: "arrow.up.right")
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(ATHLTHTheme.premiumGold)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(challenge == nil)
        }
        .padding(15)
        .frame(maxWidth: 310, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .fill(LinearGradient(
                    colors: [
                        Color.white.opacity(0.97),
                        ATHLTHTheme.surfaceStone.opacity(0.88),
                        ATHLTHTheme.cardWarm.opacity(0.68)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .stroke(LinearGradient(
                    colors: [
                        Color.white.opacity(0.99),
                        ATHLTHTheme.accent.opacity(0.22),
                        Color.white.opacity(0.70)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ), lineWidth: 1)
        }
        .shadow(color: ATHLTHTheme.accentDeep.opacity(0.08),
                radius: 14, x: 0, y: 6)
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english: "Cancel this challenge for everyone?",
                norwegian: "Avlyse utfordringen for alle?"
            ),
            isPresented: $confirmCancellation,
            titleVisibility: .visible
        ) {
            Button(
                ATHLTHLocalization.choose(
                    english: "Cancel challenge", norwegian: "Avlys utfordring"
                ),
                role: .destructive,
                action: onCancel
            )
            Button(ATHLTHLocalization.choose(
                english: "Keep challenge", norwegian: "Behold utfordringen"
            ), role: .cancel) {}
        }
    }
}

private struct ThreadChallengeTimelineRow: View {
    let challenge: ATHLTHChallenge
    let friend: SocialProfileCard
    let currentUserID: UUID?
    let invitedAt: Date
    let responding: Bool
    let onAccept: () -> Void
    let onDecline: () -> Void
    let onDetails: () -> Void
    let cancelling: Bool
    let onCancel: () -> Void

    private var isMine: Bool { challenge.creatorID == currentUserID }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if !isMine {
                SocialAvatar(profile: friend, size: 32)
            } else {
                Spacer(minLength: 48)
            }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 6) {
                ThreadChallengeInvitationBubble(
                    challenge: challenge,
                    fallbackTitle: challenge.title,
                    fallbackSubtitle: nil,
                    currentUserID: currentUserID,
                    friendUserID: friend.userID,
                    isMine: isMine,
                    responding: responding,
                    onDetails: onDetails,
                    onAccept: onAccept,
                    onDecline: onDecline,
                    cancelling: cancelling,
                    onCancel: onCancel
                )
                Text(invitedAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if !isMine { Spacer(minLength: 48) }
        }
    }
}

private struct MessageBubble: View {
    @EnvironmentObject private var challengeStore: ChallengeStore

    let message: DirectMessageRecord
    let friend: SocialProfileCard
    let currentUserID: UUID?
    let currentUserProfile: SocialProfileCard
    let onSaveAttachment: () -> Void
    let onPreviewAttachment: () -> Void
    let inviteResponse: PlannedWorkoutInviteResponse?
    let respondingToInvite: Bool
    let onRespondToInvite: (Bool) -> Void
    let onWithdrawInvite: () -> Void
    let agreedWorkout: PlannedSession?
    let lifecycleUpdate: WorkoutInviteLifecycleUpdate?
    let workoutChangeDecision: WorkoutChangeDecision?
    let reviewingWorkoutChange: Bool
    let onProposeWorkoutChange: () -> Void
    let onReviewWorkoutChange: (Bool) -> Void
    let respondingToChallenge: Bool
    let onRespondToChallenge: (ATHLTHChallenge, Bool) -> Void
    let onOpenChallenge: (UUID) -> Void
    let cancellingChallenge: Bool
    let onCancelChallenge: (ATHLTHChallenge) -> Void
    let challengeChangeResponse: ChallengeChangeProposalResponse?
    let respondingToProposal: Bool
    let onReviewProposal: (Bool) -> Void

    private var isPlannedInvitation: Bool {
        message.attachmentKind == .workout && message.shareVersion == 2
    }

    private var isPlannedInviteResponse: Bool {
        message.attachmentKind == .workout && message.shareVersion == 3
    }

    private var isMine: Bool {
        message.senderID == currentUserID
    }

    private var provenanceText: String {
        if let sourceOwnerID = message.sourceOwnerID {
            if sourceOwnerID == currentUserID {
                return ATHLTHLocalization.choose(
                    english: "Created by you", norwegian: "Opprettet av deg"
                )
            }
            if sourceOwnerID == friend.userID {
                return ATHLTHLocalization.choose(
                    english: "Created by \(friend.resolvedName)",
                    norwegian: "Opprettet av \(friend.resolvedName)"
                )
            }
            return ATHLTHLocalization.choose(
                english: "Original creator preserved",
                norwegian: "Opprinnelig oppretter er bevart"
            )
        }

        return isMine
            ? ATHLTHLocalization.choose(
                english: "Shared by you", norwegian: "Delt av deg"
            )
            : ATHLTHLocalization.choose(
                english: "Shared by \(friend.resolvedName)",
                norwegian: "Delt av \(friend.resolvedName)"
            )
    }

    private enum ChallengeStatusKind {
        case waitingOutgoing
        case waitingIncoming
        case accepted
        case declined
        case withdrawn
        case expired
        case cancelled
    }

    private var challengeStatusKind:
        ChallengeStatusKind? {
        guard
            message.attachmentKind ==
                .challenge,
            let challengeID =
                message.sourceObjectID,
            let challenge =
                challengeStore.challenge(
                    id: challengeID
                )
        else {
            return nil
        }

        if challenge.status == .cancelled {
            return .cancelled
        }

        let participantUserID =
            challenge.creatorID ==
                currentUserID
                ? friend.userID
                : currentUserID

        guard
            let participant =
                challenge.participants
                    .first(
                        where: {
                            $0.userID ==
                                participantUserID
                        }
                    )
        else {
            return nil
        }

        switch participant.state {
        case .creator:
            return nil

        case .invited:
            if let endsAt =
                    challenge.rules.endsAt,
               endsAt <= Date() {
                return .expired
            }

            return challenge.creatorID ==
                currentUserID
                ? .waitingOutgoing
                : .waitingIncoming

        case .accepted:
            return challenge.creatorID ==
                currentUserID
                ? .waitingOutgoing
                : .accepted

        case .declined:
            return challenge.creatorID ==
                currentUserID
                ? .waitingOutgoing
                : .declined

        case .withdrawn:
            return .withdrawn
        }
    }

    private var challengeStatusText: String? {
        guard let challengeStatusKind else {
            return nil
        }

        switch challengeStatusKind {
        case .waitingOutgoing:
            return ATHLTHLocalization.choose(
                english: "Sent",
                norwegian: "Sendt"
            )

        case .waitingIncoming:
            return ATHLTHLocalization.choose(
                english: "Waiting for response",
                norwegian: "Venter på svar"
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

        case .withdrawn:
            return ATHLTHLocalization.choose(
                english: "Withdrawn",
                norwegian: "Trukket tilbake"
            )

        case .expired:
            return ATHLTHLocalization.choose(
                english: "Expired",
                norwegian: "Utløpt"
            )

        case .cancelled:
            return ATHLTHLocalization.choose(
                english: "Cancelled",
                norwegian: "Avlyst"
            )
        }
    }

    private var challengeStatusSystemImage: String {
        switch challengeStatusKind {
        case .accepted:
            return "checkmark.circle.fill"
        case .declined:
            return "xmark.circle.fill"
        case .withdrawn:
            return "arrow.uturn.backward.circle.fill"
        case .expired:
            return "clock.badge.xmark"
        case .cancelled:
            return "nosign"
        case .waitingOutgoing,
             .waitingIncoming:
            return "clock.fill"
        case .none:
            return "bolt.fill"
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if !isMine {
                senderAvatar(friend)
            } else {
                Spacer(minLength: 48)
            }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 6) {
                if message.attachmentKind == .challenge &&
                   message.shareVersion == 2,
                   let proposal = message.decodeSnapshot(ChallengeChangeProposal.self) {
                    ChallengeProposalCard(
                        proposal: proposal,
                        response: challengeChangeResponse,
                        currentUserID: currentUserID,
                        sending: respondingToProposal,
                        onApprove: { onReviewProposal(true) },
                        onReject: { onReviewProposal(false) }
                    )
                } else if message.attachmentKind == .challenge &&
                          message.shareVersion == 3,
                          let response = message.decodeSnapshot(ChallengeChangeProposalResponse.self) {
                    ChallengeProposalResponseCard(response: response)
                } else if message.attachmentKind == .challenge {
                    let challengeID = message.sourceObjectID ??
                        message.decodeSnapshot(ATHLTHChallenge.self)?.id
                    let linkedChallenge = challengeID.flatMap {
                        challengeStore.challenge(id: $0)
                    }
                    ThreadChallengeInvitationBubble(
                        challenge: linkedChallenge,
                        fallbackTitle: message.attachmentTitle ??
                            ATHLTHLocalization.choose(
                                english: "Challenge", norwegian: "Utfordring"
                            ),
                        fallbackSubtitle: message.attachmentSubtitle,
                        currentUserID: currentUserID,
                        friendUserID: friend.userID,
                        isMine: isMine,
                        responding: respondingToChallenge,
                        onDetails: {
                            if let challengeID { onOpenChallenge(challengeID) }
                        },
                        onAccept: {
                            if let linkedChallenge {
                                onRespondToChallenge(linkedChallenge, true)
                            }
                        },
                        onDecline: {
                            if let linkedChallenge {
                                onRespondToChallenge(linkedChallenge, false)
                            }
                        },
                        cancelling: cancellingChallenge,
                        onCancel: {
                            if let linkedChallenge {
                                onCancelChallenge(linkedChallenge)
                            }
                        }
                    )
                } else if message.attachmentKind == .workout &&
                          message.shareVersion == 4,
                          let proposal = message.decodeSnapshot(WorkoutChangeProposal.self) {
                    ThreadWorkoutChangeProposalCard(
                        proposal: proposal,
                        decision: workoutChangeDecision,
                        currentUserID: currentUserID,
                        isWorking: reviewingWorkoutChange,
                        onApprove: { onReviewWorkoutChange(true) },
                        onDecline: { onReviewWorkoutChange(false) }
                    )
                } else if message.attachmentKind == .workout &&
                          message.shareVersion == 5,
                          let decision = message.decodeSnapshot(WorkoutChangeDecision.self) {
                    Label(
                        decision.approved
                            ? ATHLTHLocalization.choose(
                                english: "Workout changes approved",
                                norwegian: "Endringene i økten er godkjent"
                            )
                            : ATHLTHLocalization.choose(
                                english: "Workout changes declined",
                                norwegian: "Endringene i økten er avslått"
                            ),
                        systemImage: decision.approved
                            ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .padding(14)
                    .background(.ultraThinMaterial,
                                in: RoundedRectangle(cornerRadius: 16))
                } else if message.attachmentKind == .workout &&
                           message.shareVersion == 6,
                           let lifecycle = message.decodeSnapshot(
                                WorkoutInviteLifecycleUpdate.self
                           ) {
                    Label(
                        lifecycle.kind == .cancelled
                            ? ATHLTHLocalization.choose(
                                english: "Group workout cancelled",
                                norwegian: "Fellesøkten er avlyst"
                            )
                            : ATHLTHLocalization.choose(
                                english: "Group workout updated",
                                norwegian: "Fellesøkten er oppdatert"
                            ),
                        systemImage: lifecycle.kind == .cancelled
                            ? "xmark.circle.fill" : "calendar.badge.clock"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTrainTogetherDesign.accent)
                    .padding(14)
                    .athlthTrainTogetherCard(radius: 15)
                } else if isPlannedInvitation,
                          let workout = message.decodeSnapshot(PlannedSession.self) {
                    ThreadWorkoutInvitationCard(
                        workout: agreedWorkout ?? lifecycleUpdate?.updatedWorkout ?? workout,
                        response: inviteResponse,
                        lifecycleUpdate: lifecycleUpdate,
                        isMine: isMine,
                        isResponding: respondingToInvite,
                        organizerName: isMine
                            ? currentUserProfile.resolvedName : friend.resolvedName,
                        inviteeName: isMine
                            ? friend.resolvedName : currentUserProfile.resolvedName,
                        onAccept: { onRespondToInvite(true) },
                        onDecline: { onRespondToInvite(false) },
                        onWithdraw: onWithdrawInvite,
                        onProposeChanges: onProposeWorkoutChange
                    )
                } else if let attachmentKind = message.attachmentKind {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 8) {
                            Image(systemName: attachmentKind.systemImage)
                                .foregroundStyle(ATHLTHTheme.premiumGold)
                            Text(isPlannedInvitation
                                 ? ATHLTHLocalization.choose(
                                     english: "WORKOUT INVITATION",
                                     norwegian: "TRENINGSINVITASJON"
                                   )
                                 : isPlannedInviteResponse
                                     ? ATHLTHLocalization.choose(
                                         english: "INVITATION RESPONSE",
                                         norwegian: "SVAR PÅ INVITASJON"
                                       )
                                     : attachmentKind.title.uppercased())
                                .font(.caption2.weight(.semibold))
                                .tracking(1)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                        }

                        Text(message.attachmentTitle ?? attachmentKind.title)
                            .font(.headline)

                        if let subtitle = message.attachmentSubtitle,
                           !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let challengeStatusText {
                            Label(
                                challengeStatusText,
                                systemImage:
                                    challengeStatusSystemImage
                            )
                            .font(
                                .caption2
                                    .weight(.semibold)
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .accentDeep
                            )
                            .padding(
                                .horizontal,
                                8
                            )
                            .padding(
                                .vertical,
                                5
                            )
                            .background(
                                ATHLTHTheme
                                    .accentSoft,
                                in: Capsule()
                            )
                        }

                        if isPlannedInvitation {
                            if let meeting = message.decodeSnapshot(PlannedSession.self)?.meetingPoint {
                                VStack(alignment: .leading, spacing: 4) {
                                    Label(meeting.name, systemImage: "mappin.circle.fill")
                                        .font(.caption.weight(.semibold))
                                    Text(meeting.address)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    if let url = URL(string: "https://maps.apple.com/?ll=\(meeting.latitude),\(meeting.longitude)") {
                                        Link(
                                            ATHLTHLocalization.choose(
                                                english: "Open in Maps",
                                                norwegian: "Åpne i Kart"
                                            ),
                                            destination: url
                                        )
                                        .font(.caption.weight(.semibold))
                                    }
                                }
                            }

                            if let inviteResponse {
                                Label(
                                    inviteResponse.decision == .accepted
                                        ? ATHLTHLocalization.choose(
                                            english: "Accepted", norwegian: "Godtatt"
                                        )
                                        : ATHLTHLocalization.choose(
                                            english: "Declined", norwegian: "Avslått"
                                        ),
                                    systemImage: inviteResponse.decision == .accepted
                                        ? "checkmark.circle.fill" : "xmark.circle.fill"
                                )
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                            } else if isMine {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english: "Waiting for a reply",
                                        norwegian: "Venter på svar"
                                    ),
                                    systemImage: "clock"
                                )
                                .font(.caption)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                            } else {
                                HStack(spacing: 9) {
                                    Button(ATHLTHLocalization.choose(
                                        english: "Decline", norwegian: "Avslå"
                                    )) {
                                        onRespondToInvite(false)
                                    }
                                    .buttonStyle(.bordered)
                                    Button(ATHLTHLocalization.choose(
                                        english: "Accept", norwegian: "Godta"
                                    )) {
                                        onRespondToInvite(true)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(ATHLTHTheme.premiumGold)
                                }
                                .disabled(respondingToInvite)
                            }
                        }

                        Text(provenanceText)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        if !isMine && !isPlannedInvitation && !isPlannedInviteResponse {
                            HStack(spacing: 8) {
                                if attachmentKind == .challenge {
                                    Button {
                                        onSaveAttachment()
                                    } label: {
                                        Label("View details", systemImage: "bolt.fill")
                                            .font(.caption.weight(.semibold))
                                    }
                                    .buttonStyle(.bordered)
                                } else {
                                    Button {
                                        onPreviewAttachment()
                                    } label: {
                                        Label(
                                            ATHLTHLocalization.choose(
                                                english: "View content",
                                                norwegian: "Se innhold"
                                            ),
                                            systemImage: "eye"
                                        )
                                        .font(.caption.weight(.semibold))
                                    }
                                    .buttonStyle(.bordered)
                                    if attachmentKind != .exercise {
                                        Button {
                                            onSaveAttachment()
                                        } label: {
                                            Label(
                                                ATHLTHLocalization.choose(
                                                    english: "Save copy",
                                                    norwegian: "Lagre kopi"
                                                ),
                                                systemImage: "square.and.arrow.down"
                                            )
                                            .font(.caption.weight(.semibold))
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                            }
                            .tint(ATHLTHTheme.premiumGold)
                        }
                    }
                    .padding(13)
                    .frame(maxWidth: 300, alignment: .leading)
                    .background(
                        Color.white,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(ATHLTHTheme.border, lineWidth: 1)
                    }
                }

                // Invitation metadata already lives in the compact card.
                // Keep the message body for push previews, but never duplicate
                // a long invitation as a second chat bubble (also for history).
                if let body = message.body,
                   !body.isEmpty && !isPlannedInvitation {
                    Text(body)
                        .font(.body)
                        .foregroundStyle(
                            isMine
                                ? Color.white
                                : ATHLTHTheme
                                    .primaryText
                        )
                        .lineSpacing(2)
                        .padding(
                            .horizontal,
                            15
                        )
                        .padding(
                            .vertical,
                            11
                        )
                        .background(
                            isMine
                                ? AnyShapeStyle(
                                    LinearGradient(
                                        colors: [
                                            ATHLTHPlanDesign.outgoingMessage,
                                            ATHLTHPlanDesign.outgoingMessage.opacity(0.94)
                                        ],
                                        startPoint:
                                            .topLeading,
                                        endPoint:
                                            .bottomTrailing
                                    )
                                )
                                : AnyShapeStyle(
                                    Color.white
                                        .opacity(0.96)
                                ),
                            in:
                                RoundedRectangle(
                                    cornerRadius: 20,
                                    style: .continuous
                                )
                        )
                        .overlay {
                            if !isMine {
                                RoundedRectangle(
                                    cornerRadius: 20,
                                    style: .continuous
                                )
                                .stroke(
                                    Color.white
                                        .opacity(0.92),
                                    lineWidth: 0.8
                                )
                            }
                        }
                        .shadow(
                            color:
                                isMine
                                    ? ATHLTHPlanDesign
                                        .outgoingMessage
                                        .opacity(0.10)
                                    : ATHLTHTheme
                                        .accentDeep
                                        .opacity(0.04),
                            radius: 8,
                            y: 3
                        )
                }

                HStack(spacing: 4) {
                    Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                    if isMine {
                        if message.readAt != nil {
                            Label(ATHLTHLocalization.choose(english: "Read", norwegian: "Lest"), systemImage: "checkmark.circle.fill")
                        } else {
                            Label(ATHLTHLocalization.choose(english: "Sent", norwegian: "Sendt"), systemImage: "checkmark")
                        }
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            if !isMine {
                Spacer(minLength: 48)
            }
        }
    }

    private func senderAvatar(
        _ profile: SocialProfileCard
    ) -> some View {
        NavigationLink {
            FriendProfileView(
                userID: profile.userID
            )
        } label: {
            SocialAvatar(
                profile: profile,
                size: 32
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Open sender profile"
        )
    }
}

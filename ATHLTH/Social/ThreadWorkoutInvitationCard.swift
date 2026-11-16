import SwiftUI

/// A small, inexpensive timeline preview. Workout details are only built when
/// the user opens the sheet; no maps, workout blocks or exercise rows in chat.
struct ThreadWorkoutInvitationCard: View {
    let workout: PlannedSession
    let response: PlannedWorkoutInviteResponse?
    let lifecycleUpdate: WorkoutInviteLifecycleUpdate?
    let isMine: Bool
    let isResponding: Bool
    let organizerName: String
    let inviteeName: String
    let onAccept: () -> Void
    let onDecline: () -> Void
    let onProposeChanges: () -> Void

    @State private var showingDetails = false

    private var state: PlannedWorkoutInvitationPresentationState {
        PlannedWorkoutInvitationPresentationState.resolve(
            start: workout.scheduledStart,
            decision: response?.decision,
            organizerCancelled: lifecycleUpdate?.kind == .cancelled
        )
    }

    private var statusLabel: String {
        switch state {
        case .pending:
            return isMine
                ? ATHLTHLocalization.choose(english: "Awaiting reply", norwegian: "Venter på svar")
                : ATHLTHLocalization.choose(english: "Invitation received", norwegian: "Venter på ditt svar")
        case .accepted:
            return ATHLTHLocalization.choose(english: "Accepted", norwegian: "Godtatt")
        case .declined:
            return ATHLTHLocalization.choose(english: "Declined", norwegian: "Avslått")
        case .cancelled:
            return ATHLTHLocalization.choose(english: "Cancelled", norwegian: "Avlyst")
        }
    }

    private var statusColor: Color {
        switch state {
        case .cancelled, .declined: return .red
        case .accepted: return ATHLTHTheme.accentDeep
        case .pending: return ATHLTHTheme.mutedText
        }
    }

    private var subtitle: String {
        workout.kind.title + " · " + (
            workout.trainTogetherMode == .sameWorkout
            ? ATHLTHLocalization.choose(english: "Same workout", norwegian: "Samme økt")
            : ATHLTHLocalization.choose(english: "Train in person", norwegian: "Trene fysisk sammen")
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                showingDetails = true
            } label: {
                HStack(alignment: .center, spacing: 11) {
                    Image(systemName: workout.kind.systemImage)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                        .frame(width: 43, height: 43)
                        .background(ATHLTHTheme.accentSoft.opacity(0.55),
                                    in: RoundedRectangle(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(workout.title)
                            .font(.system(size: 17, weight: .semibold, design: .serif))
                            .foregroundStyle(ATHLTHTheme.primaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(statusLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(statusColor)
                    }
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if state == .cancelled {
                // Deliberately just a title, red state and a quiet date for history.
                if let start = workout.scheduledStart {
                    Text(start.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }
            } else {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    if let start = workout.scheduledStart {
                        Label(
                            start.formatted(date: .abbreviated, time: .shortened),
                            systemImage: "calendar"
                        )
                        .lineLimit(1)
                    }
                    if workout.trainTogetherMode != .sameWorkout,
                       let point = workout.meetingPoint {
                        Label(point.name, systemImage: "mappin")
                            .lineLimit(1)
                    }
                }
                .font(.caption2)
                .foregroundStyle(ATHLTHTheme.primaryText)

                if state.canRespond && !isMine {
                    HStack(spacing: 8) {
                        Button(
                            ATHLTHLocalization.choose(english: "Decline", norwegian: "Avslå"),
                            action: onDecline
                        )
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)

                        Button(
                            ATHLTHLocalization.choose(english: "Accept", norwegian: "Godta"),
                            action: onAccept
                        )
                        .buttonStyle(.borderedProminent)
                        .tint(ATHLTHTheme.accentDeep)
                        .frame(maxWidth: .infinity)
                    }
                    .controlSize(.small)
                    .disabled(isResponding)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: 310, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.white, ATHLTHTheme.cardWarm.opacity(0.78)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(ATHLTHTheme.accentDeep.opacity(0.10), lineWidth: 0.8)
        }
        .sheet(isPresented: $showingDetails) {
            ThreadWorkoutInvitationDetailsView(
                workout: workout,
                state: state,
                organizerName: organizerName,
                inviteeName: inviteeName,
                isMine: isMine,
                isResponding: isResponding,
                onAccept: onAccept,
                onDecline: onDecline,
                onProposeChanges: onProposeChanges
            )
        }
    }
}

/// Full premium invitation, kept out of the conversation cell's view tree.
private struct ThreadWorkoutInvitationDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    let workout: PlannedSession
    let state: PlannedWorkoutInvitationPresentationState
    let organizerName: String
    let inviteeName: String
    let isMine: Bool
    let isResponding: Bool
    let onAccept: () -> Void
    let onDecline: () -> Void
    let onProposeChanges: () -> Void

    @State private var showsExercises = false
    @State private var showsStructure = false

    private var statusLabel: String {
        switch state {
        case .pending: return ATHLTHLocalization.choose(english: "Awaiting reply", norwegian: "Venter på svar")
        case .accepted: return ATHLTHLocalization.choose(english: "Accepted", norwegian: "Godtatt")
        case .declined: return ATHLTHLocalization.choose(english: "Declined", norwegian: "Avslått")
        case .cancelled: return ATHLTHLocalization.choose(english: "Cancelled", norwegian: "Avlyst")
        }
    }

    private var statusColor: Color {
        state == .cancelled || state == .declined ? .red : ATHLTHTheme.accentDeep
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(ATHLTHLocalization.choose(
                                english: "TRAINING INVITATION", norwegian: "TRENINGSINVITASJON"
                            ))
                            .font(.caption2.weight(.bold))
                            .tracking(1.6)
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            Spacer()
                            Image(systemName: workout.kind.systemImage)
                                .font(.title3)
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                                .frame(width: 48, height: 48)
                                .background(ATHLTHTheme.accentSoft,
                                            in: RoundedRectangle(cornerRadius: 16))
                        }
                        Text(workout.title)
                            .font(.system(size: 30, weight: .semibold, design: .serif))
                            .foregroundStyle(ATHLTHTheme.primaryText)
                        Text(workout.kind.title + " · " + (
                            workout.trainTogetherMode == .sameWorkout
                            ? ATHLTHLocalization.choose(english: "Same workout", norwegian: "Samme økt")
                            : ATHLTHLocalization.choose(english: "Train in person", norwegian: "Trene fysisk sammen")
                        ))
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHTheme.mutedText)

                        Text(statusLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(statusColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(statusColor.opacity(0.09), in: Capsule())
                    }
                    .padding(21)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(
                            colors: [Color.white, ATHLTHTheme.champagneSoft.opacity(0.65)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 24)
                    )

                    detailSection(ATHLTHLocalization.choose(
                        english: "When and where", norwegian: "Tid og sted"
                    )) {
                        if let start = workout.scheduledStart {
                            detailRow(
                                icon: "calendar",
                                label: ATHLTHLocalization.choose(english: "Start", norwegian: "Start"),
                                value: start.formatted(date: .complete, time: .shortened)
                            )
                        }
                        if let minutes = workout.durationMinutes {
                            detailRow(
                                icon: "clock",
                                label: ATHLTHLocalization.choose(english: "Duration", norwegian: "Varighet"),
                                value: "\(minutes) min"
                            )
                        }
                        if workout.trainTogetherMode != .sameWorkout {
                            if let point = workout.meetingPoint {
                                detailRow(icon: "mappin.and.ellipse", label: point.name, value: point.address)
                                if let url = URL(string:
                                    "https://maps.apple.com/?ll=\(point.latitude),\(point.longitude)") {
                                    Link(destination: url) {
                                        Label(
                                            ATHLTHLocalization.choose(
                                                english: "Directions in Maps", norwegian: "Åpne i Kart"
                                            ),
                                            systemImage: "arrow.up.right"
                                        )
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(ATHLTHTheme.accentDeep)
                                    }
                                }
                            } else {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english: "Meeting point not specified",
                                        norwegian: "Møtested er ikke oppgitt"
                                    ), systemImage: "mappin.slash"
                                )
                                .font(.subheadline)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                            }
                        }
                    }

                    detailSection(ATHLTHLocalization.choose(
                        english: "Participants", norwegian: "Deltakere"
                    )) {
                        detailRow(
                            icon: "person.crop.circle",
                            label: ATHLTHLocalization.choose(english: "Organizer", norwegian: "Arrangør"),
                            value: organizerName
                        )
                        detailRow(
                            icon: "person.crop.circle",
                            label: ATHLTHLocalization.choose(english: "Invited", norwegian: "Invitert"),
                            value: inviteeName
                        )
                    }

                    detailSection(ATHLTHLocalization.choose(
                        english: "Workout", norwegian: "Økten"
                    )) {
                        HStack(spacing: 12) {
                            Label("\(workout.exercises.count) " +
                                ATHLTHLocalization.choose(english: "exercises", norwegian: "øvelser"),
                                  systemImage: "dumbbell")
                            if let km = workout.targetDistanceKilometers {
                                Label(String(format: "%.1f km", km), systemImage: "figure.run")
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHTheme.primaryText)

                        if !workout.exercises.isEmpty {
                            DisclosureGroup(
                                ATHLTHLocalization.choose(
                                    english: "See all exercises", norwegian: "Vis øvelser"
                                ),
                                isExpanded: $showsExercises
                            ) {
                                LazyVStack(alignment: .leading, spacing: 10) {
                                    ForEach(workout.exercises) { exercise in
                                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                                            Text(exercise.embeddedExercise.displayName)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            Text("\(exercise.sets) " +
                                                ATHLTHLocalization.choose(
                                                    english: "sets", norwegian: "sett"
                                                ))
                                                .foregroundStyle(ATHLTHTheme.mutedText)
                                        }
                                        .font(.subheadline)
                                    }
                                }
                                .padding(.top, 10)
                            }
                            .tint(ATHLTHTheme.accentDeep)
                        }

                        if !workout.resolvedWorkoutBlocks.isEmpty {
                            DisclosureGroup(
                                ATHLTHLocalization.choose(
                                    english: "Workout structure", norwegian: "Øktstruktur"
                                ),
                                isExpanded: $showsStructure
                            ) {
                                LazyVStack(alignment: .leading, spacing: 8) {
                                    ForEach(workout.resolvedWorkoutBlocks) { block in
                                        Text(block.title)
                                            .font(.subheadline)
                                    }
                                }
                                .padding(.top, 10)
                            }
                            .tint(ATHLTHTheme.accentDeep)
                        }
                    }

                    if let notes = workout.notes, !notes.isEmpty {
                        detailSection(ATHLTHLocalization.choose(
                            english: "Notes", norwegian: "Notater"
                        )) {
                            Text(notes)
                                .font(.subheadline)
                                .foregroundStyle(ATHLTHTheme.primaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if state.canRespond && !isMine {
                        HStack(spacing: 10) {
                            Button(action: onDecline) {
                                Text(ATHLTHLocalization.choose(
                                    english: "Decline", norwegian: "Avslå"
                                ))
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button(action: onAccept) {
                                Text(ATHLTHLocalization.choose(
                                    english: "Accept", norwegian: "Godta"
                                ))
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(ATHLTHTheme.accentDeep)
                        }
                        .disabled(isResponding)
                    }

                    if !isMine && (state == .pending || state == .accepted) {
                        Button(action: onProposeChanges) {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Suggest workout changes",
                                    norwegian: "Foreslå endringer i økten"
                                ),
                                systemImage: "square.and.pencil"
                            )
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(ATHLTHTheme.accentDeep)
                        .disabled(isResponding)
                    }
                }
                .padding(17)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(ATHLTHTrainTogetherDesign.canvas.ignoresSafeArea())
            .navigationTitle(ATHLTHLocalization.choose(
                english: "Invitation", norwegian: "Invitasjon"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Done", norwegian: "Ferdig"
                    )) { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func detailSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(title)
                .font(.headline)
                .foregroundStyle(ATHLTHTheme.primaryText)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 21))
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.mutedText)
            }
            Spacer(minLength: 0)
        }
    }
}


// The calendar lobby deliberately reads status from invitation messages.
// The planned workout belongs to its creator, regardless of the response.
struct PlannedWorkoutLobbyView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var messaging: MessagingStore
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore

    let workout: PlannedSession
    // Home retains ownership of the real iPhone/Watch workout engines.
    var onStartWorkout: ((PlannedSession, WorkoutCaptureDevice) -> Void)? = nil

    @State private var messages: [DirectMessageRecord] = []
    @State private var isRefreshing = false
    @State private var hasLoaded = false
    @State private var loadError: String?
    @State private var openingReadyLobby = false
    @State private var launchError: String?
    @State private var lifecycleError: String?
    @State private var isPublishingLifecycle = false
    @State private var showingWorkoutEditor = false
    @State private var confirmingCancelWorkout = false
    @State private var chatPartner: SocialProfileCard?
    @State private var reminderInFlight: Set<UUID> = []

    private let service = SupabaseMessagingService()

    private struct InvitedAthlete: Identifiable {
        let id: UUID
        let decision: PlannedWorkoutInviteDecision?
    }

    private var sourceWorkoutID: UUID {
        workout.sharedSourceSessionID ?? workout.id
    }

    private var organizerID: UUID {
        workout.sharedSourceOwnerID ?? session.profile.userID
    }

    private var invitedAthletes: [InvitedAthlete] {
        let invitations = messages
            .filter {
                $0.sourceObjectID == sourceWorkoutID &&
                $0.shareVersion == 2 &&
                $0.senderID == organizerID &&
                $0.deletedAt == nil
            }
            .sorted { $0.createdAt > $1.createdAt }

        var seen = Set<UUID>()
        return invitations.compactMap { invitation in
            guard seen.insert(invitation.recipientID).inserted else {
                return nil
            }
            let latestResponse = messages
                .filter {
                    $0.sourceObjectID == sourceWorkoutID &&
                    $0.shareVersion == 3 &&
                    $0.senderID == invitation.recipientID &&
                    $0.recipientID == organizerID &&
                    $0.deletedAt == nil
                }
                .sorted { $0.createdAt > $1.createdAt }
                .compactMap {
                    $0.decodeSnapshot(PlannedWorkoutInviteResponse.self)
                }
                .first { $0.sourceWorkoutID == sourceWorkoutID }

            return InvitedAthlete(
                id: invitation.recipientID,
                decision: latestResponse?.decision
            )
        }
    }

    private var acceptedCount: Int {
        invitedAthletes.filter { $0.decision == .accepted }.count
    }

    private var canLaunchWorkout: Bool {
        onStartWorkout != nil &&
        (workout.kind == .running || workout.kind == .walking ||
         workout.kind == .strength)
    }

    private var isOrganizer: Bool {
        organizerID == session.profile.userID
    }

    private var inviteeForReadyLobby: SocialProfileCard? {
        guard isOrganizer,
              workout.trainTogetherMode == .physical,
              let invitedPartnerID = workout.invitedPartnerID else {
            return nil
        }
        return social.trainingPartners.first {
            $0.userID == invitedPartnerID
        }
    }

    private var persistedWorkout: PlannedSession? {
        session.standalonePlannedSessions.first {
            $0.id == workout.id && !$0.isExplicitRestDay
        }
    }

    // Never reopen another workout's minimized lobby from this card.
    private var matchingReadyLobbyID: UUID? {
        guard let activeID = social.coordinatedLobbySessionID,
              social.workoutSessions.contains(where: {
                  $0.id == activeID &&
                  $0.invitePayload?.workout.id == sourceWorkoutID
              }) else {
            return nil
        }
        return activeID
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                headerCard
                workoutCard
                participantsCard
                startOptionsCard
                if isOrganizer {
                    organizerActions
                }
                Text(ATHLTHLocalization.choose(
                    english: "Your workout is in your calendar whether friends accept, decline or do not respond. You can train on your own.",
                    norwegian: "Økten ligger i kalenderen din uansett om venner godtar, avslår eller ikke svarer. Du kan gjennomføre økten alene."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .padding(.horizontal, 5)
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .background(ATHLTHTrainTogetherDesign.canvas.ignoresSafeArea())
        .tint(ATHLTHTrainTogetherDesign.accent)
        .navigationTitle(ATHLTHLocalization.choose(
            english: "Workout lobby", norwegian: "Øktlobby"
        ))
        .navigationBarTitleDisplayMode(.inline)
        .tint(ATHLTHTrainTogetherDesign.accent)
        .sheet(item: $chatPartner) { profile in
            NavigationStack {
                DirectMessageThreadView(friend: profile)
            }
        }
        .sheet(isPresented: $showingWorkoutEditor) {
            SessionEditorView(
                standaloneDate: workout.scheduledStart ?? Date(),
                initialSourceWorkout: persistedWorkout ?? workout,
                preserveSourceID: true,
                onPreparedWorkout: { revised in
                    Task { await publishLifecycle(.updated, revision: revised) }
                }
            )
        }
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english: "Cancel this planned group workout?",
                norwegian: "Avlyse den planlagte fellesøkten?"
            ),
            isPresented: $confirmingCancelWorkout,
            titleVisibility: .visible
        ) {
            Button(ATHLTHLocalization.choose(
                english: "Cancel workout for everyone",
                norwegian: "Avlys for alle"
            ), role: .destructive) {
                Task { await publishLifecycle(.cancelled, revision: nil) }
            }
            Button(ATHLTHLocalization.choose(
                english: "Keep workout", norwegian: "Behold økten"
            ), role: .cancel) {}
        } message: {
            Text(ATHLTHLocalization.choose(
                english: "Participants will be notified and their ATHLTH calendar copies removed.",
                norwegian: "Deltakerne varsles, og ATHLTH-økten fjernes fra kalenderen deres."
            ))
        }
        .task(id: sourceWorkoutID) {
            await refresh()
            if workout.invitedPartnerID != nil &&
               inviteeForReadyLobby == nil {
                await social.refresh()
            }
            // A calendar sheet can open before Community loads its profiles.
            // Resolve names once when a relevant participant is missing.
            if (organizerID != session.profile.userID &&
                social.profile(for: organizerID) == nil) ||
                invitedAthletes.contains(where: {
                    $0.id != session.profile.userID &&
                    social.profile(for: $0.id) == nil
                }) {
                await social.refresh()
            }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(25))
                } catch {
                    break
                }
                await refresh()
            }
        }
    }

    /// A planned invitation is not an active recording. The shared
    /// ready lobby is created only when the organizer explicitly opens it.
    /// This reuses the app's server-authorized ready and 3-2-1 workflow.
    private var organizerActions: some View {
        ATHLTHTrainTogetherSurface {
            HStack(spacing: 9) {
                Button {
                    showingWorkoutEditor = true
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Edit group workout", norwegian: "Endre fellesøkt"
                        ),
                        systemImage: "square.and.pencil"
                    )
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(ATHLTHTrainTogetherDesign.accent)
                .disabled(isPublishingLifecycle)

                Button {
                    confirmingCancelWorkout = true
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Cancel", norwegian: "Avlys"
                        ),
                        systemImage: "xmark.circle"
                    )
                    .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(isPublishingLifecycle)
            }

            if isPublishingLifecycle {
                ProgressView(ATHLTHLocalization.choose(
                    english: "Notifying participants…",
                    norwegian: "Varsler deltakerne…"
                ))
                .font(.caption)
            }
            if let lifecycleError {
                Label(lifecycleError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @MainActor
    private func publishLifecycle(
        _ kind: WorkoutInviteLifecycleUpdate.Kind,
        revision: PlannedSession?
    ) async {
        guard isOrganizer, !isPublishingLifecycle,
              let current = persistedWorkout else { return }
        if let lobbyID = matchingReadyLobbyID,
           social.workoutParticipants.contains(where: {
               $0.sessionID == lobbyID && $0.workoutStartedAt != nil
           }) {
            lifecycleError = ATHLTHLocalization.choose(
                english: "The shared workout has already started.",
                norwegian: "Fellesøkten er allerede startet."
            )
            return
        }
        if kind == .updated {
            guard let revision,
                  revision.id == sourceWorkoutID,
                  revision.scheduledStart != nil else {
                lifecycleError = ATHLTHLocalization.choose(
                    english: "A valid scheduled workout is required.",
                    norwegian: "Økten må ha en gyldig planlagt starttid."
                )
                return
            }
        }
        isPublishingLifecycle = true
        defer { isPublishingLifecycle = false }
        lifecycleError = nil
        let change = WorkoutInviteLifecycleUpdate(
            sourceWorkoutID: sourceWorkoutID,
            organizerID: organizerID,
            kind: kind,
            updatedWorkout: kind == .updated ? revision : nil,
            occurredAt: Date()
        )
        do {
            let attachment = try MessageShareDraft(
                kind: .workout,
                title: current.title,
                subtitle: kind == .cancelled
                    ? ATHLTHLocalization.choose(
                        english: "Workout cancelled", norwegian: "Økt avlyst"
                    )
                    : ATHLTHLocalization.choose(
                        english: "Workout updated", norwegian: "Økt oppdatert"
                    ),
                snapshot: change,
                sourceObjectID: sourceWorkoutID,
                sourceOwnerID: organizerID,
                shareVersion: 6
            )
            for invited in invitedAthletes {
                let conversationID = try await messaging.openConversation(
                    with: invited.id
                )
                let text = kind == .cancelled
                    ? ATHLTHLocalization.choose(
                        english: "Our planned workout has been cancelled.",
                        norwegian: "Den planlagte fellesøkten er avlyst."
                    )
                    : ATHLTHLocalization.choose(
                        english: "Our planned workout was updated. Check the new details in ATHLTH.",
                        norwegian: "Fellesøkten er oppdatert. Se de nye detaljene i ATHLTH."
                    )
                guard await messaging.send(
                    to: invited.id,
                    conversationID: conversationID,
                    body: text,
                    attachment: attachment
                ) else {
                    lifecycleError = messaging.errorMessage ??
                        ATHLTHLocalization.choose(
                            english: "Could not notify everyone. Try again.",
                            norwegian: "Kunne ikke varsle alle. Prøv igjen."
                        )
                    return
                }
            }
            // An old ready lobby must never outlive changed meeting details.
            if let lobbyID = matchingReadyLobbyID {
                await social.cancelActiveWorkout(sessionID: lobbyID)
            }

            if kind == .cancelled {
                session.removeStandalonePlannedSession(current.id)
            } else if let revision {
                session.updateStandalonePlannedSession(revision)
            }
            showingWorkoutEditor = false
            dismiss()
        } catch {
            lifecycleError = error.localizedDescription
        }
    }

    private var startOptionsCard: some View {
        ATHLTHTrainTogetherSurface {
            VStack(alignment: .leading, spacing: 13) {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Ready to train?",
                        norwegian: "Klar for økten?"
                    ),
                    systemImage: "person.2.circle"
                )
                .font(.headline)
                .foregroundStyle(ATHLTHTheme.primaryText)

                if isOrganizer && workout.trainTogetherMode == .physical {
                    if let friend = inviteeForReadyLobby {
                        Button {
                            if matchingReadyLobbyID != nil {
                                social.presentCoordinatedLobby()
                            } else {
                                Task { await openReadyLobby(with: friend) }
                            }
                        } label: {
                            Label(
                                matchingReadyLobbyID != nil
                                    ? ATHLTHLocalization.choose(
                                        english: "Return to ready lobby",
                                        norwegian: "Tilbake til klar-lobby"
                                    )
                                    : ATHLTHLocalization.choose(
                                        english: "Open ready lobby",
                                        norwegian: "Åpne klar-lobby"
                                    ),
                                systemImage: "person.2.fill"
                            )
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ATHLTHTrainTogetherDesign.accent)
                        .disabled(
                            openingReadyLobby || !canLaunchWorkout ||
                            (social.coordinatedLobbySessionID != nil &&
                             matchingReadyLobbyID == nil)
                        )
                    } else {
                        Text(ATHLTHLocalization.choose(
                            english: "Your selected friend must be a mutual follow to join a live lobby.",
                            norwegian: "Vennen må følge deg gjensidig for å delta i en felles startlobby."
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    }

                    Text(ATHLTHLocalization.choose(
                        english: "A start invitation opens a shared lobby. Each person chooses a device, taps Ready and can wait for the synchronized 3-2-1 start. The organizer can also start independently.",
                        norwegian: "Vennen får en startinvitasjon til en felles lobby. Begge velger enhet og trykker Klar, og kan vente på felles 3–2–1-start. Arrangøren kan også starte alene."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }

                if canLaunchWorkout &&
                    !(isOrganizer && workout.trainTogetherMode == .physical &&
                      inviteeForReadyLobby != nil) {
                    HStack(spacing: 9) {
                        Button {
                            startIndependently(using: .iPhone)
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Start on iPhone",
                                    norwegian: "Start på iPhone"
                                ),
                                systemImage: "iphone"
                            )
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.bordered)
                        .tint(ATHLTHTrainTogetherDesign.accent)
                        .disabled(
                            openingReadyLobby || persistedWorkout == nil ||
                            social.coordinatedLobbySessionID != nil
                        )

                        Button {
                            startIndependently(using: .appleWatch)
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Start on Watch",
                                    norwegian: "Start på Watch"
                                ),
                                systemImage: "applewatch"
                            )
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.bordered)
                        .tint(ATHLTHTrainTogetherDesign.accent)
                        .disabled(
                            openingReadyLobby ||
                            persistedWorkout == nil ||
                            !watchConnection.isVerifiedForLiveLaunch ||
                            social.coordinatedLobbySessionID != nil
                        )
                    }
                }

                if openingReadyLobby {
                    ProgressView(ATHLTHLocalization.choose(
                        english: "Opening lobby…",
                        norwegian: "Åpner lobby…"
                    ))
                }
                if let launchError {
                    Label(launchError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func startIndependently(using device: WorkoutCaptureDevice) {
        guard let persistedWorkout, canLaunchWorkout,
              !openingReadyLobby,
              social.coordinatedLobbySessionID == nil else {
            return
        }
        onStartWorkout?(persistedWorkout, device)
    }

    @MainActor
    private func openReadyLobby(with friend: SocialProfileCard) async {
        guard !openingReadyLobby, canLaunchWorkout,
              social.coordinatedLobbySessionID == nil,
              let persistedWorkout,
              persistedWorkout.invitedPartnerID == friend.userID else {
            return
        }
        openingReadyLobby = true
        launchError = nil

        // Invitation scheduling must not start a recorder. Starting the
        // ready lobby creates a distinct real-time participation session.
        let approved = await social.beginWorkoutWithFriends(
            title: persistedWorkout.title,
            kind: persistedWorkout.kind,
            friends: [friend],
            creatorName: session.profile.displayName,
            creatorUsername: session.profile.username,
            invitePayload: SocialWorkoutInvitePayload(
                workout: persistedWorkout,
                participationMode: .physical,
                maxParticipants: 2,
                startIndependently: false
            ),
            creatorCaptureDevice: .iPhone
        )

        openingReadyLobby = false
        guard approved else {
            if let reason = social.errorMessage {
                launchError = reason
            }
            return
        }
        guard let current = session.standalonePlannedSessions.first(where: {
            $0.id == persistedWorkout.id
        }) else {
            await social.markCurrentJoinedWorkoutLaunchFailed()
            launchError = ATHLTHLocalization.choose(
                english: "This planned workout is no longer available.",
                norwegian: "Denne planlagte økten finnes ikke lenger."
            )
            return
        }

        let recordingDevice: WorkoutCaptureDevice
        if let joinedID = social.currentJoinedWorkoutSessionID {
            recordingDevice = social.proposedCreatorCaptureDevice(for: joinedID)
        } else {
            recordingDevice = .iPhone
        }
        onStartWorkout?(current, recordingDevice)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label(ATHLTHLocalization.choose(
                    english: "TRAIN TOGETHER",
                    norwegian: "TREN SAMMEN"
                ), systemImage: "person.2.fill")
                .font(.caption.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(ATHLTHTrainTogetherDesign.accent)
                Spacer()
                Image(systemName: "person.2.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(ATHLTHTrainTogetherDesign.accent.opacity(0.8))
            }
            Text(workout.title)
                .font(.system(size: 27, weight: .semibold, design: .serif))
                .foregroundStyle(ATHLTHTheme.primaryText)
                .lineLimit(3)
            Text(workout.trainTogetherMode == .sameWorkout
                ? ATHLTHLocalization.choose(
                    english: "Same workout · your own pace",
                    norwegian: "Samme økt · eget tempo")
                : ATHLTHLocalization.choose(
                    english: "Meet and train in person",
                    norwegian: "Møt opp og tren fysisk sammen"))
                .font(.subheadline)
                .foregroundStyle(ATHLTHTheme.mutedText)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .athlthTrainTogetherCard(radius: 25)
    }

    private var workoutCard: some View {
        ATHLTHTrainTogetherSurface {
            VStack(alignment: .leading, spacing: 12) {
                if let start = workout.scheduledStart {
                    Label(start.formatted(date: .complete, time: .shortened),
                          systemImage: "calendar")
                }
                if let minutes = workout.durationMinutes {
                    Label("\(minutes) min", systemImage: "clock")
                }
                if workout.trainTogetherMode == .physical {
                    if let meeting = workout.meetingPoint {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(meeting.name, systemImage: "mappin.and.ellipse")
                                .font(.subheadline.weight(.semibold))
                            if !meeting.address.isEmpty {
                                Text(meeting.address)
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHTrainTogetherDesign.secondary)
                            }
                            if let url = URL(string:
                                "https://maps.apple.com/?ll=\(meeting.latitude),\(meeting.longitude)") {
                                Link(destination: url) {
                                    Label(
                                        ATHLTHLocalization.choose(
                                            english: "Directions in Maps",
                                            norwegian: "Veibeskrivelse i Kart"
                                        ),
                                        systemImage: "arrow.triangle.turn.up.right.diamond"
                                    )
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(ATHLTHTrainTogetherDesign.accent)
                                }
                            }
                        }
                        .padding(12)
                        .background(
                            ATHLTHTrainTogetherDesign.accentSoft.opacity(0.45),
                            in: RoundedRectangle(cornerRadius: 15)
                        )
                    } else {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Meeting point not yet specified",
                                norwegian: "Møtested er ikke oppgitt ennå"
                            ),
                            systemImage: "mappin.slash"
                        )
                        .font(.caption)
                        .foregroundStyle(ATHLTHTrainTogetherDesign.secondary)
                    }
                }
            }
            .font(.subheadline)
            .foregroundStyle(ATHLTHTheme.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var participantsCard: some View {
        ATHLTHTrainTogetherSurface {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ATHLTHLocalization.choose(
                            english: "Participants",
                            norwegian: "Deltakere"
                        ))
                        .font(.headline)
                        Text(ATHLTHLocalization.choose(
                            english: "\(acceptedCount) of \(invitedAthletes.count) accepted",
                            norwegian: "\(acceptedCount) av \(invitedAthletes.count) godtatt"
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                    Spacer()
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 38, height: 38)
                            .background(Color.white.opacity(0.7), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isRefreshing)
                    .accessibilityLabel(ATHLTHLocalization.choose(
                        english: "Refresh invitation status",
                        norwegian: "Oppdater invitasjonsstatus"
                    ))
                }

                Divider()
                athleteRow(
                    userID: organizerID,
                    status: ATHLTHLocalization.choose(
                        english: "Organizer", norwegian: "Arrangør"
                    ),
                    icon: "star.circle.fill",
                    tint: ATHLTHTrainTogetherDesign.accent
                )

                ForEach(invitedAthletes) { athlete in
                    Divider()
                    let status = invitationStatus(athlete.decision)
                    athleteRow(
                        userID: athlete.id,
                        status: status.text,
                        icon: status.icon,
                        tint: status.color
                    )
                }

                if isRefreshing && !hasLoaded {
                    HStack(spacing: 9) {
                        ProgressView().controlSize(.small)
                        Text(ATHLTHLocalization.choose(
                            english: "Loading invitation status…",
                            norwegian: "Henter invitasjonsstatus…"
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                } else if hasLoaded && invitedAthletes.isEmpty {
                    Text(ATHLTHLocalization.choose(
                        english: "No sent invitations were found for this workout yet.",
                        norwegian: "Ingen sendte invitasjoner er funnet for denne økten ennå."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }

                if let loadError {
                    Label(loadError, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func athleteRow(
        userID: UUID,
        status: String,
        icon: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(ATHLTHTrainTogetherDesign.accent.opacity(0.75))
                .frame(width: 42, height: 42)
                .background(Color.white.opacity(0.6), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(userID == session.profile.userID
                    ? ATHLTHLocalization.choose(english: "You", norwegian: "Du")
                    : social.profile(for: userID)?.resolvedName ??
                        ATHLTHLocalization.choose(
                            english: "Athlete", norwegian: "Deltaker"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                Label(status, systemImage: icon)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(tint)
            }
            Spacer(minLength: 0)

            if userID != session.profile.userID,
               let profile = social.profile(for: userID) {
                Button {
                    chatPartner = profile
                } label: {
                    Image(systemName: "bubble.left")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .background(
                            ATHLTHTrainTogetherDesign.accentSoft,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(ATHLTHTrainTogetherDesign.accent)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Message participant",
                    norwegian: "Send melding til deltaker"
                ))

                if isOrganizer,
                   invitedAthletes.first(where: { $0.id == userID })?.decision == nil {
                    Button {
                        Task { await remindParticipant(userID) }
                    } label: {
                        Image(systemName: "bell")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ATHLTHTrainTogetherDesign.accent)
                    .disabled(!canRemind(userID))
                    .accessibilityLabel(ATHLTHLocalization.choose(
                        english: "Send invitation reminder",
                        norwegian: "Send invitasjonspåminnelse"
                    ))
                }
            }
        }
    }

    private func canRemind(_ recipientID: UUID) -> Bool {
        guard isOrganizer, !reminderInFlight.contains(recipientID) else {
            return false
        }
        let key = "athlth.plannedInvite.reminder.\(sourceWorkoutID).\(recipientID)"
        guard let last = UserDefaults.standard.object(forKey: key) as? Date else {
            return true
        }
        return Date().timeIntervalSince(last) >= 900
    }

    @MainActor
    private func remindParticipant(_ recipientID: UUID) async {
        guard canRemind(recipientID) else { return }
        reminderInFlight.insert(recipientID)
        defer { reminderInFlight.remove(recipientID) }
        do {
            let id = try await messaging.openConversation(with: recipientID)
            let text = ATHLTHLocalization.choose(
                english: "Reminder: please reply to the invitation for \(workout.title) in ATHLTH.",
                norwegian: "Påminnelse: Svar gjerne på invitasjonen til \(workout.title) i ATHLTH."
            )
            if await messaging.send(
                to: recipientID, conversationID: id, body: text
            ) {
                let key = "athlth.plannedInvite.reminder.\(sourceWorkoutID).\(recipientID)"
                UserDefaults.standard.set(Date(), forKey: key)
            } else {
                lifecycleError = messaging.errorMessage ??
                    ATHLTHLocalization.choose(
                        english: "Could not send reminder.",
                        norwegian: "Kunne ikke sende påminnelse."
                    )
            }
        } catch {
            lifecycleError = error.localizedDescription
        }
    }

    private func invitationStatus(
        _ decision: PlannedWorkoutInviteDecision?
    ) -> (text: String, icon: String, color: Color) {
        switch decision {
        case .accepted:
            return (ATHLTHLocalization.choose(
                english: "Accepted", norwegian: "Godtatt"),
                "checkmark.circle.fill", ATHLTHTheme.premiumGold)
        case .declined:
            return (ATHLTHLocalization.choose(
                english: "Declined", norwegian: "Avslått"),
                "xmark.circle.fill", .red)
        case .none:
            return (ATHLTHLocalization.choose(
                english: "Invited · awaiting reply",
                norwegian: "Invitert · venter på svar"),
                "clock", ATHLTHTrainTogetherDesign.accent)
        }
    }

    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer {
            isRefreshing = false
            hasLoaded = true
        }
        do {
            messages = try await service.loadPlannedWorkoutInvitationMessages(
                sourceWorkoutID: sourceWorkoutID
            )
            loadError = nil
        } catch {
            loadError = ATHLTHLocalization.choose(
                english: "Unable to refresh status. Try again.",
                norwegian: "Kunne ikke oppdatere status. Prøv igjen."
            )
        }
    }
}

import SwiftUI

/// A private invitation surfaced directly in the message timeline.
/// The workout is saved into the recipient's calendar only after acceptance.
struct ThreadWorkoutInvitationCard: View {
    let workout: PlannedSession
    let response: PlannedWorkoutInviteResponse?
    let isMine: Bool
    let isResponding: Bool
    let onAccept: () -> Void
    let onDecline: () -> Void
    let onProposeChanges: () -> Void

    @State private var showingDetails = false

    private var isPhysical: Bool {
        workout.trainTogetherMode != .sameWorkout
    }

    private var subtitle: String {
        isPhysical
            ? ATHLTHLocalization.choose(
                english: "Train together in person",
                norwegian: "Trene fysisk sammen"
            )
            : ATHLTHLocalization.choose(
                english: "Do the same workout",
                norwegian: "Trene samme økt"
            )
    }

    private var responseStatus: (text: String, icon: String) {
        switch response?.decision {
        case .accepted:
            return (
                ATHLTHLocalization.choose(
                    english: "Accepted", norwegian: "Godtatt"
                ), "checkmark.circle.fill"
            )
        case .declined:
            return (
                ATHLTHLocalization.choose(
                    english: "Declined", norwegian: "Avslått"
                ), "xmark.circle.fill"
            )
        case .none:
            return (
                isMine
                    ? ATHLTHLocalization.choose(
                        english: "Waiting for a reply",
                        norwegian: "Venter på svar"
                    )
                    : ATHLTHLocalization.choose(
                        english: "Invited · awaiting your reply",
                        norwegian: "Invitert · venter på svar"
                    ), "clock"
            )
        }
    }

    private var statusTint: Color {
        switch response?.decision {
        case .accepted: return ATHLTHTheme.vitality
        case .declined: return ATHLTHTheme.mutedText
        case .none: return ATHLTHTheme.accentDeep
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                showingDetails = true
            } label: {
                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "TRAINING INVITATION",
                                norwegian: "INVITASJON TIL ØKT"
                            ),
                            systemImage: "person.2.fill"
                        )
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(ATHLTHTheme.accentDeep)

                        Spacer()

                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                    }

                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: workout.kind.systemImage)
                            .font(.system(size: 23, weight: .semibold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .frame(width: 54, height: 54)
                            .background(
                                Color.white.opacity(0.70),
                                in: RoundedRectangle(cornerRadius: 17)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 17)
                                    .stroke(Color.white.opacity(0.86), lineWidth: 1)
                            }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(workout.title)
                                .font(.system(size: 22, weight: .semibold, design: .serif))
                                .foregroundStyle(ATHLTHTheme.primaryText)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(subtitle)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(ATHLTHTheme.mutedText)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(17)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    LinearGradient(
                        colors: [
                            ATHLTHTheme.champagneSoft.opacity(0.75),
                            Color.white.opacity(0.50),
                            ATHLTHTheme.accentSoft.opacity(0.24)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 7) {
                    if let start = workout.scheduledStart {
                        inviteDetail(
                            icon: "calendar",
                            title: start.formatted(.dateTime.day().month(.abbreviated)),
                            detail: start.formatted(.dateTime.hour().minute())
                        )
                    }
                    if let duration = workout.durationMinutes {
                        inviteDetail(
                            icon: "clock",
                            title: "\(duration) min",
                            detail: ATHLTHLocalization.choose(
                                english: "Duration", norwegian: "Varighet"
                            )
                        )
                    }
                }

                if isPhysical, let point = workout.meetingPoint {
                    HStack(spacing: 8) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(point.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ATHLTHTheme.primaryText)
                            Text(point.address)
                                .font(.caption2)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        if let url = URL(string:
                            "https://maps.apple.com/?ll=\(point.latitude),\(point.longitude)") {
                            Link(destination: url) {
                                Image(systemName: "arrow.up.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(ATHLTHTheme.accentDeep)
                            }
                        }
                    }
                    .padding(11)
                    .athlthTrainTogetherCard(radius: 13, subtle: true)
                }

                HStack(spacing: 7) {
                    Image(systemName: responseStatus.icon)
                        .foregroundStyle(statusTint)
                    Text(responseStatus.text)
                        .foregroundStyle(ATHLTHTheme.primaryText)
                    Spacer(minLength: 0)
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(
                    statusTint.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 11)
                )

                if !isMine && response == nil {
                    HStack(spacing: 9) {
                        Button(action: onDecline) {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Decline", norwegian: "Avslå"
                                ),
                                systemImage: "xmark"
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(ATHLTHTheme.accentDeep)

                        Button(action: onAccept) {
                            HStack(spacing: 7) {
                                if isResponding {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Image(systemName: "checkmark")
                                }
                                Text(ATHLTHLocalization.choose(
                                    english: "Accept", norwegian: "Godta"
                                ))
                            }
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ATHLTHTheme.accentDeep)
                    }
                    .disabled(isResponding)

                } else if response?.decision == .accepted {
                    Label(
                        workout.scheduledStart != nil
                            ? ATHLTHLocalization.choose(
                                english: "Added to your workout calendar",
                                norwegian: "Økten ligger nå i kalenderen din"
                            )
                            : ATHLTHLocalization.choose(
                                english: "Workout saved to your shared workouts",
                                norwegian: "Økten er lagret blant dine delte økter"
                            ),
                        systemImage: workout.scheduledStart != nil
                            ? "calendar.badge.checkmark" : "checkmark.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                } else if isMine && response == nil {
                    Text(workout.scheduledStart != nil
                        ? ATHLTHLocalization.choose(
                            english: "Your own workout stays scheduled whether or not your friend joins.",
                            norwegian: "Din økt blir stående i kalenderen selv om vennen ikke blir med."
                        )
                        : ATHLTHLocalization.choose(
                            english: "Your invitation is waiting for a reply.",
                            norwegian: "Øktinvitasjonen venter på svar."
                        ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                }

                // Acceptance schedules the workout; it does not close the
                // negotiation window. Guests may suggest changes afterward.
                if !isMine && response?.decision != .declined {
                    Button(action: onProposeChanges) {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Suggest workout changes",
                                norwegian: "Foreslå endringer i økten"
                            ),
                            systemImage: "square.and.pencil"
                        )
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(ATHLTHTheme.accentDeep)
                    .disabled(isResponding)
                }

                Button {
                    showingDetails = true
                } label: {
                    HStack {
                        Text(ATHLTHLocalization.choose(
                            english: "View workout details",
                            norwegian: "Vis hele økten"
                        ))
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                }
                .buttonStyle(.plain)
            }
            .padding(15)
        }
        .frame(maxWidth: 340, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .athlthTrainTogetherCard(radius: 24)
        .sheet(isPresented: $showingDetails) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 17) {
                        HStack(spacing: 12) {
                            Image(systemName: workout.kind.systemImage)
                                .font(.title2)
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                                .frame(width: 52, height: 52)
                                .background(
                                    ATHLTHTheme.accentSoft,
                                    in: RoundedRectangle(cornerRadius: 15)
                                )
                            VStack(alignment: .leading, spacing: 5) {
                                Text(workout.title)
                                    .font(.title2.weight(.bold))
                                Text(workout.kind.title + " · " + subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                            }
                        }

                        if let start = workout.scheduledStart {
                            Label(start.formatted(date: .complete, time: .shortened),
                                  systemImage: "calendar")
                        }
                        if let duration = workout.durationMinutes {
                            Label("\(duration) min", systemImage: "clock")
                        }
                        if let km = workout.targetDistanceKilometers {
                            Label(
                                String(format: "%.1f km", km),
                                systemImage: "figure.run"
                            )
                        }
                        if isPhysical, let point = workout.meetingPoint {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(point.name, systemImage: "mappin.and.ellipse")
                                    .font(.headline)
                                Text(point.address)
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                                if let url = URL(string:
                                    "https://maps.apple.com/?ll=\(point.latitude),\(point.longitude)") {
                                    Link(
                                        ATHLTHLocalization.choose(
                                            english: "Open in Maps", norwegian: "Åpne i Kart"
                                        ),
                                        destination: url
                                    )
                                }
                            }
                        }
                        if !workout.exercises.isEmpty {
                            VStack(alignment: .leading, spacing: 9) {
                                Text(ATHLTHLocalization.choose(
                                    english: "Exercises", norwegian: "Øvelser"
                                ))
                                .font(.headline)
                                ForEach(workout.exercises) { exercise in
                                    HStack {
                                        Text(exercise.embeddedExercise.displayName)
                                        Spacer()
                                        Text("\(exercise.sets) sett")
                                            .foregroundStyle(ATHLTHTheme.mutedText)
                                    }
                                    .font(.subheadline)
                                }
                            }
                        }
                        if !workout.resolvedWorkoutBlocks.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(ATHLTHLocalization.choose(
                                    english: "Workout structure",
                                    norwegian: "Øktstruktur"
                                ))
                                .font(.headline)
                                ForEach(workout.resolvedWorkoutBlocks) { block in
                                    Text(block.title)
                                        .font(.subheadline)
                                }
                            }
                        }
                        if let notes = workout.notes, !notes.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(ATHLTHLocalization.choose(
                                    english: "Notes", norwegian: "Notater"
                                ))
                                .font(.headline)
                                Text(notes)
                                    .font(.subheadline)
                            }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(ATHLTHTrainTogetherDesign.canvas.ignoresSafeArea())
                .navigationTitle(ATHLTHLocalization.choose(
                    english: "Workout invitation",
                    norwegian: "Treningsinvitasjon"
                ))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(ATHLTHLocalization.choose(
                            english: "Done", norwegian: "Ferdig"
                        )) { showingDetails = false }
                    }
                }
            }
        }
    }
    private func inviteDetail(
        icon: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.accentDeep)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(ATHLTHTheme.mutedText)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .athlthTrainTogetherCard(radius: 12, subtle: true)
    }

}


// The calendar lobby deliberately reads status from invitation messages.
// The planned workout belongs to its creator, regardless of the response.
struct PlannedWorkoutLobbyView: View {
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
        .navigationTitle(ATHLTHLocalization.choose(
            english: "Workout lobby", norwegian: "Øktlobby"
        ))
        .navigationBarTitleDisplayMode(.inline)
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
                        .tint(ATHLTHTheme.accentDeep)
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

                if canLaunchWorkout {
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
                .foregroundStyle(ATHLTHTheme.accentDeep)
                Spacer()
                Image(systemName: "person.2.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(ATHLTHTheme.accentDeep.opacity(0.8))
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
                if let meeting = workout.meetingPoint,
                   workout.trainTogetherMode == .physical {
                    Label(meeting.name, systemImage: "mappin.and.ellipse")
                    if let url = URL(string:
                        "https://maps.apple.com/?ll=\(meeting.latitude),\(meeting.longitude)") {
                        Link(ATHLTHLocalization.choose(
                            english: "Open meeting point in Maps",
                            norwegian: "Åpne møtested i Kart"
                        ), destination: url)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
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
                    tint: ATHLTHTheme.accentDeep
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
                .foregroundStyle(ATHLTHTheme.accentDeep.opacity(0.75))
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
        }
    }

    private func invitationStatus(
        _ decision: PlannedWorkoutInviteDecision?
    ) -> (text: String, icon: String, color: Color) {
        switch decision {
        case .accepted:
            return (ATHLTHLocalization.choose(
                english: "Accepted", norwegian: "Godtatt"),
                "checkmark.circle.fill", ATHLTHTheme.vitality)
        case .declined:
            return (ATHLTHLocalization.choose(
                english: "Declined", norwegian: "Avslått"),
                "xmark.circle.fill", .red)
        case .none:
            return (ATHLTHLocalization.choose(
                english: "Invited · awaiting reply",
                norwegian: "Invitert · venter på svar"),
                "clock", ATHLTHTheme.accentDeep)
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

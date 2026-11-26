import Foundation
import MapKit
import SwiftUI
import Supabase

/// One server-owned workout document shared by both participants. This is
/// planning data only: it never creates a recording or HealthKit workout.
struct TrainTogetherLiveDraft: Decodable, Identifiable, Equatable {
    let sourceWorkoutID: UUID
    let ownerID: UUID
    let partnerID: UUID
    let editMode: String
    let participationMode: String
    let workoutSnapshot: String
    let revision: Int
    let ownerApprovedRevision: Int?
    let partnerApprovedRevision: Int?
    var cancelledAt: Date? = nil
    var proposedStart: Double? = nil
    var proposedStartBy: UUID? = nil
    var proposedDate: Date? { proposedStart.map { Date(timeIntervalSinceReferenceDate: $0) } }

    var id: UUID { sourceWorkoutID }
    var isCollaborative: Bool { editMode == "collaborative" }
    var isPhysical: Bool { participationMode == "physical" }
    var ownerApproved: Bool { ownerApprovedRevision == revision }
    var partnerApproved: Bool { partnerApprovedRevision == revision }
    var bothApproved: Bool { cancelledAt == nil && proposedStart == nil && ownerApproved && partnerApproved }

    var workout: PlannedSession? {
        guard let data = workoutSnapshot.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PlannedSession.self, from: data)
    }

    enum CodingKeys: String, CodingKey {
        case sourceWorkoutID = "source_workout_id"
        case ownerID = "owner_id"
        case partnerID = "partner_id"
        case editMode = "edit_mode"
        case participationMode = "participation_mode"
        case workoutSnapshot = "workout_snapshot"
        case revision
        case ownerApprovedRevision = "owner_approved_revision"
        case partnerApprovedRevision = "partner_approved_revision"
        case cancelledAt = "cancelled_at"
        case proposedStart = "proposed_start"
        case proposedStartBy = "proposed_start_by"
    }
}

private struct TrainTogetherCreateDraftParameters: Encodable {
    let sourceID: UUID
    let partnerID: UUID
    let editMode: String
    let participationMode: String
    let snapshot: String

    enum CodingKeys: String, CodingKey {
        case sourceID = "p_source_id"
        case partnerID = "p_partner_id"
        case editMode = "p_edit_mode"
        case participationMode = "p_participation_mode"
        case snapshot = "p_snapshot"
    }
}

private struct TrainTogetherUpdateDraftParameters: Encodable {
    let sourceID: UUID
    let expectedRevision: Int
    let snapshot: String

    enum CodingKeys: String, CodingKey {
        case sourceID = "p_source_id"
        case expectedRevision = "p_expected_revision"
        case snapshot = "p_snapshot"
    }
}

private struct TrainTogetherNegotiateStartParameters: Encodable {
    let sourceID: UUID
    let expectedRevision: Int
    let accept: Bool
    let start: Double?

    enum CodingKeys: String, CodingKey {
        case sourceID = "p_source_id"
        case expectedRevision = "p_expected_revision"
        case accept = "p_accept"
        case start = "p_start"
    }
}

private struct TrainTogetherApproveDraftParameters: Encodable {
    let sourceID: UUID
    let expectedRevision: Int

    enum CodingKeys: String, CodingKey {
        case sourceID = "p_source_id"
        case expectedRevision = "p_expected_revision"
    }
}

/// Database compare-and-swap protects concurrent edits. Realtime is a wakeup
/// signal only; every notification reloads the authorized current revision.
@MainActor
final class TrainTogetherLiveDraftStore: ObservableObject {
    @Published private(set) var draft: TrainTogetherLiveDraft?
    @Published private(set) var isLoading = false
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?
    @Published private(set) var withdrawnSourceIDs: Set<UUID> = []

    func isWithdrawn(_ sourceID: UUID) -> Bool { withdrawnSourceIDs.contains(sourceID) }

    private let client = SupabaseEnvironment.client

    // Postgres Changes, polling and the editor can request the same row at
    // once. Coalesce those requests rather than decoding full workout JSON
    // repeatedly and publishing identical state into the entire lobby.
    private var refreshInFlight = false
    private var pendingRefreshSourceID: UUID?
    private var latestRequestedSourceID: UUID?
    private var cachedWorkoutID: UUID?
    private var cachedWorkoutRevision: Int?
    private var cachedWorkout: PlannedSession?

    /// Decode one snapshot per source/revision, not on every SwiftUI body
    /// evaluation or every access by a row in the shared workout view.
    var workout: PlannedSession? {
        guard let current = draft else { return nil }
        if cachedWorkoutID == current.sourceWorkoutID &&
           cachedWorkoutRevision == current.revision {
            return cachedWorkout
        }
        let decoded = current.workout
        cachedWorkoutID = current.sourceWorkoutID
        cachedWorkoutRevision = current.revision
        cachedWorkout = decoded
        return decoded
    }

    /// Never regress to an earlier revision (or earlier approvals of that
    /// same revision) if two network requests finish out of order.
    private func apply(_ incoming: TrainTogetherLiveDraft?) {
        if let incoming {
            if incoming.cancelledAt != nil {
                withdrawnSourceIDs.insert(incoming.sourceWorkoutID)
                if draft?.sourceWorkoutID == incoming.sourceWorkoutID { draft = nil }
                errorMessage = ATHLTHLocalization.choose(english: "The invitation was withdrawn.", norwegian: "Invitasjonen er trukket tilbake.")
                return
            }
            guard !isWithdrawn(incoming.sourceWorkoutID) else { return }
        }
        if let current = draft, let incoming {
            if incoming.revision < current.revision { return }
            if incoming.revision == current.revision,
               (current.ownerApproved && !incoming.ownerApproved ||
                current.partnerApproved && !incoming.partnerApproved) {
                return
            }
        }
        if draft != incoming { draft = incoming }
    }

    static func mergingEditorRecipe(_ edited: PlannedSession, into source: PlannedSession) -> PlannedSession {
        var result = source
        result.title = edited.title
        result.kind = edited.kind
        result.durationMinutes = edited.durationMinutes
        result.targetDistanceKilometers = edited.targetDistanceKilometers
        result.targetPaceSecondsPerKilometer = edited.targetPaceSecondsPerKilometer
        result.routeID = edited.routeID
        result.workoutCategory = edited.workoutCategory
        result.workoutBlocks = edited.workoutBlocks
        // The unified blocks supersede legacy recipes, never duplicate them.
        result.exercises = edited.exercises
        result.runningWorkout = edited.runningWorkout
        result.runningWorkouts = edited.runningWorkouts
        result.audioCoachConfiguration = edited.audioCoachConfiguration
        result.routeAlertConfiguration = edited.routeAlertConfiguration
        result.ghostTargetDurationSeconds = edited.ghostTargetDurationSeconds
        result.ghostUpdates = edited.ghostUpdates
        return result
    }

    static func privateSnapshot(_ workout: PlannedSession) -> PlannedSession {
        var copy = workout
        copy.gearIDs = []
        copy.spotifyPlaylist = nil
        copy.spotifyAutoplayOnStart = false
        copy.spotifyIntervalTrack = nil
        return copy
    }

    private static func encode(_ workout: PlannedSession) throws -> String {
        let data = try JSONEncoder().encode(privateSnapshot(workout))
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return text
    }

    func create(
        workout: PlannedSession,
        partnerID: UUID,
        isCollaborative: Bool,
        isPhysical: Bool
    ) async throws {
        let parameters = TrainTogetherCreateDraftParameters(
            sourceID: workout.id,
            partnerID: partnerID,
            editMode: isCollaborative ? "collaborative" : "view_only",
            participationMode: isPhysical ? "physical" : "remote",
            snapshot: try Self.encode(workout)
        )
        try await client.rpc(
            "create_social_workout_draft", params: parameters
        ).execute()
    }

    func refresh(_ sourceID: UUID, quiet: Bool = false) async {
        latestRequestedSourceID = sourceID
        if refreshInFlight {
            pendingRefreshSourceID = sourceID
            return
        }

        refreshInFlight = true
        if !quiet && draft == nil { isLoading = true }
        defer {
            if isLoading { isLoading = false }
            refreshInFlight = false
            if let pending = pendingRefreshSourceID {
                pendingRefreshSourceID = nil
                Task { @MainActor [weak self] in
                    await self?.refresh(pending, quiet: true)
                }
            }
        }

        do {
            let rows: [TrainTogetherLiveDraft] = try await client
                .from("social_workout_draft_lobbies")
                .select()
                .eq("source_workout_id", value: sourceID)
                .limit(1)
                .execute()
                .value
            guard !Task.isCancelled,
                  latestRequestedSourceID == sourceID else { return }
            apply(rows.first)
            guard !isWithdrawn(sourceID) else { return }
            if errorMessage != nil { errorMessage = nil }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled,
                  latestRequestedSourceID == sourceID else { return }
            if !quiet { errorMessage = error.localizedDescription }
        }
    }

    @discardableResult
    func save(
        _ proposed: PlannedSession,
        basedOn originalRevision: Int
    ) async -> Bool {
        guard let current = draft, !isWorking,
              proposed.id == current.sourceWorkoutID,
              current.revision == originalRevision else {
            errorMessage = ATHLTHLocalization.choose(
                english: "The workout changed. Reopen the editor to review the latest version.",
                norwegian: "Økten ble endret. Åpne redigering på nytt for å se nyeste versjon."
            )
            return false
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let updated: TrainTogetherLiveDraft = try await client.rpc(
                "update_social_workout_draft",
                params: TrainTogetherUpdateDraftParameters(
                    sourceID: current.sourceWorkoutID,
                    expectedRevision: originalRevision,
                    snapshot: try Self.encode(proposed)
                )
            ).execute().value
            // The RPC returns the authoritative new revision. No follow-up
            // SELECT is needed just to reflect the athlete's own edit.
            apply(updated)
            guard !isWithdrawn(updated.sourceWorkoutID) else { return false }
            if errorMessage != nil { errorMessage = nil }
            return true
        } catch {
            let failure = error.localizedDescription
            await refresh(current.sourceWorkoutID, quiet: true)
            errorMessage = failure
            return false
        }
    }

    @discardableResult
    func negotiateStart(_ date: Date?, accept: Bool, basedOn revision: Int) async -> Bool {
        guard let current = draft, !isWorking, current.revision == revision,
              current.cancelledAt == nil else {
            errorMessage = "Økten er endret. Oppdater før du svarer."
            return false
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let updated: TrainTogetherLiveDraft = try await client.rpc(
                "negotiate_social_workout_start",
                params: TrainTogetherNegotiateStartParameters(
                    sourceID: current.sourceWorkoutID, expectedRevision: revision,
                    accept: accept, start: date?.timeIntervalSinceReferenceDate
                )
            ).execute().value
            apply(updated)
            guard !isWithdrawn(updated.sourceWorkoutID) else { return false }
            errorMessage = nil
            return true
        } catch {
            let failure = error.localizedDescription
            await refresh(current.sourceWorkoutID, quiet: true)
            errorMessage = failure
            return false
        }
    }

    func approve() async {
        guard let current = draft, !isWorking, current.proposedStart == nil else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let updated: TrainTogetherLiveDraft = try await client.rpc(
                "approve_social_workout_draft",
                params: TrainTogetherApproveDraftParameters(
                    sourceID: current.sourceWorkoutID,
                    expectedRevision: current.revision
                )
            ).execute().value
            apply(updated)
            guard !isWithdrawn(updated.sourceWorkoutID) else { return }
            if errorMessage != nil { errorMessage = nil }
        } catch {
            errorMessage = error.localizedDescription
            await refresh(current.sourceWorkoutID, quiet: true)
        }
    }

    /// Postgres Changes is authorized by row-level security. No invitation,
    /// exercise or permission data is sent through a public channel.
    func watch(_ sourceID: UUID) async {
        if draft?.sourceWorkoutID != sourceID {
            await refresh(sourceID)
        }
        let channel = await client.channel(
            "train-together-draft-\(sourceID.uuidString.lowercased())"
        )
        let changes = await channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "social_workout_draft_lobbies"
        )
        await channel.subscribe()
        for await _ in changes {
            if Task.isCancelled { break }
            await refresh(sourceID, quiet: true)
        }
        await channel.unsubscribe()
    }
}

/// Shared room: the normal workout header, editor and read-only outline;
/// server revisions remain authoritative for both participants.
struct TrainTogetherLiveDraftRoomView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var social: SocialStore
    @StateObject private var live = TrainTogetherLiveDraftStore()
    @State private var editor: EditorSelection?
    @State private var selectedTab: RoomTab = .workout
    @State private var presence: [RoomPresence] = []
    @State private var history: [RoomRevision] = []
    @State private var roomDataError: String?
    @State private var showingGuestLobby = false
    @State private var openingReady = false
    @State private var meetingEdit: MeetingEdit?
    @State private var dateProposalRevision: Int?
    @State private var dateProposal = Date().addingTimeInterval(3600)

    let sourceWorkoutID: UUID
    var fallbackWorkout: PlannedSession? = nil
    var initiallyShowsChat = false
    var onOpenReady: (() -> Void)? = nil

    private struct MeetingEdit: Identifiable {
        let workout: PlannedSession
        let revision: Int
        var id: Int { revision }
    }
    private enum RoomTab: String, CaseIterable { case workout, chat, history, recap }
    private struct EditorSelection: Identifiable {
        let workout: PlannedSession
        let revision: Int
        let partnerName: String
        var id: Int { revision }
    }

    private let ink = ATHLTHTrainTogetherDesign.ink
    private let accent = ATHLTHTrainTogetherDesign.accent
    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }
    private var isOwner: Bool { live.draft?.ownerID == session.profile.userID }
    private func otherID(_ draft: TrainTogetherLiveDraft) -> UUID {
        isOwner ? draft.partnerID : draft.ownerID
    }
    private func name(_ id: UUID) -> String {
        if id == session.profile.userID {
            let value = session.profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? tr("You", "Deg") : value
        }
        return social.profile(for: id)?.resolvedName
            ?? social.resolvedQuickTrainPartners([id]).first?.resolvedName
            ?? tr("Name unavailable", "Navn ikke tilgjengelig")
    }
    private var canEdit: Bool {
        guard let draft = live.draft, draft.cancelledAt == nil,
              !live.isWithdrawn(sourceWorkoutID),
              draft.ownerID == session.profile.userID || draft.partnerID == session.profile.userID else { return false }
        guard matchingSession?.coordinatedStartAt == nil,
              matchingSession?.resolvedWorkoutPhase != .completed else { return false }
        return isOwner || draft.isCollaborative
    }

    private var matchingSession: SocialWorkoutSessionRecord? {
        social.workoutSessions.filter {
            $0.invitePayload?.workout.id == sourceWorkoutID &&
                $0.creatorID == live.draft?.ownerID && $0.resolvedWorkoutPhase != .cancelled
        }.max { $0.createdAt < $1.createdAt }
    }
    private var matchingInvite: SocialWorkoutInviteDisplay? {
        social.workoutInvites.first {
            $0.session.id == matchingSession?.id && $0.participant.userID == session.profile.userID
        }
    }
    private func tabTitle(_ tab: RoomTab) -> String {
        switch tab {
        case .workout: return tr("Workout", "Økten")
        case .chat: return tr("Chat", "Chat")
        case .history: return tr("History", "Historikk")
        case .recap: return tr("Results", "Resultater")
        }
    }
    private func tabIcon(_ tab: RoomTab) -> String {
        switch tab {
        case .workout: return "list.bullet.rectangle"
        case .chat: return "bubble.left.and.bubble.right"
        case .history: return "clock.arrow.circlepath"
        case .recap: return "chart.bar"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                if let draft = live.draft, let workout = live.workout {
                    details(workout, draft: draft)
                    presenceStrip(draft)
                    tabBar
                    if selectedTab == .workout {
                        workoutContent(workout, draft: draft)
                        scheduleCard(workout, draft: draft)
                        approvalCard(draft)
                        if draft.isPhysical { meetingCard(workout) }
                    } else if selectedTab == .history {
                        historyCard
                    } else if selectedTab == .recap {
                        recapCard(draft)
                    } else {
                        TrainTogetherRoomChat(
                            sourceID: sourceWorkoutID, userID: session.profile.userID,
                            partnerName: name(otherID(draft)), canSend: !live.isWithdrawn(sourceWorkoutID))
                    }
                } else if live.isLoading {
                    ProgressView(tr("Loading shared workout…", "Henter fellesøkten…"))
                        .frame(maxWidth: .infinity, minHeight: 100)
                } else {
                    ATHLTHTrainTogetherSurface {
                        Label(live.isWithdrawn(sourceWorkoutID)
                              ? tr("Invitation withdrawn", "Invitasjonen er trukket tilbake")
                              : tr("Shared workout is unavailable", "Fellesøkten er ikke tilgjengelig"),
                              systemImage: "info.circle")
                            .font(.subheadline.weight(.medium))
                    }
                }
                if let roomDataError {
                    Text(roomDataError).font(.caption).foregroundStyle(.secondary)
                }
                if let error = live.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.red)
                }
            }
            .frame(maxWidth: 680)
            .padding(16)
            .frame(maxWidth: .infinity)
        }
        .background(ATHLTHTrainTogetherDesign.canvas.ignoresSafeArea())
        .navigationTitle(tr("Shared workout", "Fellesøkt"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await live.refresh(sourceWorkoutID) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await live.refresh(sourceWorkoutID) } } label: {
                    Image(systemName: "arrow.clockwise").foregroundStyle(accent)
                }
                .accessibilityLabel(tr("Refresh workout", "Oppdater økten"))
            }
        }
        .sheet(item: $editor) { selection in
            sharedEditor(selection)
        }
        .task(id: sourceWorkoutID) {
            if initiallyShowsChat { selectedTab = .chat }
            await live.watch(sourceWorkoutID)
        }
        .task(id: live.draft?.id) {
            guard live.draft != nil else { return }
            while !Task.isCancelled {
                if scenePhase == .active {
                    await updateRoomPresence(editor == nil ? "viewing" : "editing")
                    await refreshRoomData()
                }
                do { try await Task.sleep(for: .seconds(12)) } catch { break }
            }
        }
        .onChange(of: editor?.id) { _, value in
            Task { await updateRoomPresence(value == nil ? "viewing" : "editing") }
        }
        .onDisappear {
            Task { await updateRoomPresence("away") }
        }
        .sheet(item: $meetingEdit) { selection in
            SharedWorkoutMeetingPicker(initial: selection.workout.meetingPoint) { point in
                guard isOwner && canEdit else { return tr("Editing is unavailable.", "Redigering er ikke tilgjengelig.") }
                var revised = selection.workout
                revised.meetingPoint = point
                return await live.save(revised, basedOn: selection.revision)
                    ? nil : (live.errorMessage ?? tr("Could not save meeting point.", "Kunne ikke lagre møtested."))
            }
        }
        .sheet(isPresented: $showingGuestLobby) {
            if let invite = matchingInvite {
                WorkoutInviteLaunchSheet(invite: invite)
            }
        }
        .task(id: sourceWorkoutID) {
            await social.refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
                if scenePhase == .active { await live.refresh(sourceWorkoutID, quiet: true) }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await live.refresh(sourceWorkoutID, quiet: true)
                    await updateRoomPresence(editor == nil ? "viewing" : "editing")
                    await refreshRoomData()
                }
            } else {
                Task { await updateRoomPresence("away") }
            }
        }
        .onChange(of: live.draft?.revision) { _, _ in
            guard let updated = live.workout,
                  let local = session.standalonePlannedSessions.first(where: {
                      isOwner ? $0.id == updated.id : $0.sharedSourceSessionID == sourceWorkoutID &&
                          $0.sharedSourceOwnerID == live.draft?.ownerID
                  })
            else { return }
            if isOwner {
                var copy = updated
                copy.gearIDs = local.gearIDs
                copy.spotifyPlaylist = local.spotifyPlaylist
                copy.spotifyAutoplayOnStart = local.spotifyAutoplayOnStart
                copy.spotifyIntervalTrack = local.spotifyIntervalTrack
                session.updateStandalonePlannedSession(copy)
            } else if local.scheduledStart != updated.scheduledStart {
                var copy = local
                copy.scheduledStart = updated.scheduledStart
                session.updateStandalonePlannedSession(copy)
            }
        }
    }

    private func details(_ workout: PlannedSession, draft: TrainTogetherLiveDraft) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ATHLTHPlannedWorkoutStudioHeader(
                workoutName: .constant(workout.title),
                activity: ATHLTHPlannedWorkoutType.from(workout),
                blocks: ATHLTHUnifiedWorkout.editorBlocks(from: workout),
                durationMinutes: workout.durationMinutes,
                route: session.savedRoutes.first { $0.id == workout.routeID },
                scheduledAt: workout.scheduledStart.map { Binding<Date>.constant($0) },
                readOnly: true,
                trainingPartnerName: name(otherID(draft))
            )
            HStack(spacing: 8) {
                infoPill(draft.isPhysical ? tr("In person", "Fysisk sammen") : tr("Remote", "Hver for dere"),
                         icon: draft.isPhysical ? "person.2.fill" : "network")
                infoPill(draft.isCollaborative ? tr("Both edit", "Begge redigerer") : tr("Owner edits", "Arrangør redigerer"),
                         icon: draft.isCollaborative ? "square.and.pencil" : "lock")
            }
        }
    }

    private func presenceStrip(_ draft: TrainTogetherLiveDraft) -> some View {
        let record = presence.first { $0.userID == otherID(draft) }
        let status = record.flatMap { $0.updatedAt.timeIntervalSinceNow >= -40 ? $0.status : nil }
        return HStack(spacing: 8) {
            Image(systemName: status == "editing" ? "pencil.circle.fill" : status == "viewing" ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                .foregroundStyle(accent)
            Text(name(otherID(draft))).font(.caption.weight(.semibold))
            Spacer()
            Text(status == "editing" ? tr("Editing workout", "Redigerer økten")
                 : status == "viewing" ? tr("In the room", "I rommet")
                 : tr("Not active in room", "Ikke aktiv i rommet"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(11)
        .athlthTrainTogetherCard(radius: 12, subtle: true)
    }

    private var historyCard: some View {
        ATHLTHTrainTogetherSurface {
            Label(tr("Change history", "Endringshistorikk"), systemImage: "clock.arrow.circlepath").font(.headline)
            if history.isEmpty {
                Text(tr("No recorded edits yet.", "Ingen registrerte endringer ennå."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(history) { change in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(name(change.actorID)).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("v\(change.revision)").font(.caption.monospacedDigit()).foregroundStyle(accent)
                    }
                    Text(change.changedFields.map(fieldTitle).joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(change.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Divider()
            }
        }
    }

    private func fieldTitle(_ field: String) -> String {
        switch field {
        case "title": return tr("Name", "Øktnavn")
        case "workoutBlocks", "exercises", "runningWorkout", "runningWorkouts": return tr("Workout contents", "Øktinnhold")
        case "durationMinutes": return tr("Duration", "Varighet")
        case "scheduledStart": return tr("Start time", "Starttid")
        case "meetingPoint": return tr("Meeting point", "Møtested")
        case "audioCoachConfiguration": return "Audio Coach"
        case "routeID", "routeAlertConfiguration": return tr("Route", "Rute")
        default: return tr("Workout settings", "Øktinnstillinger")
        }
    }

    private func meetingCard(_ workout: PlannedSession) -> some View {
        ATHLTHTrainTogetherSurface {
            Label(tr("Meeting point", "Møtested"), systemImage: "mappin.and.ellipse").font(.headline)
            if let meeting = workout.meetingPoint {
                let coordinate = CLLocationCoordinate2D(latitude: meeting.latitude, longitude: meeting.longitude)
                Text(meeting.name).font(.subheadline.weight(.semibold))
                if !meeting.address.isEmpty { Text(meeting.address).font(.caption).foregroundStyle(.secondary) }
                if CLLocationCoordinate2DIsValid(coordinate) {
                    Map(initialPosition: .region(MKCoordinateRegion(center: coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)))) {
                        Marker(meeting.name, coordinate: coordinate)
                    }
                    .frame(height: 150).clipShape(RoundedRectangle(cornerRadius: 13))
                    if let url = URL(string: "https://maps.apple.com/?ll=\(meeting.latitude),\(meeting.longitude)") {
                        Link(destination: url) {
                            Label(tr("Directions in Maps", "Veibeskrivelse i Kart"), systemImage: "arrow.triangle.turn.up.right.diamond")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(accent)
                        }
                    }
                }
            } else {
                Text(tr("No meeting point specified.", "Ingen møtested er valgt.")).font(.caption).foregroundStyle(.secondary)
            }
            if isOwner && canEdit, let draft = live.draft {
                Button {
                    meetingEdit = MeetingEdit(workout: workout, revision: draft.revision)
                } label: {
                    Label(tr("Choose meeting point", "Velg møtested"), systemImage: "mappin.circle")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered).tint(accent)
            }
        }
    }

    private func recapCard(_ draft: TrainTogetherLiveDraft) -> some View {
        let people = social.workoutParticipants.filter {
            $0.sessionID == matchingSession?.id && [$0.userID].contains(where: { $0 == draft.ownerID || $0 == draft.partnerID })
        }
        return ATHLTHTrainTogetherSurface {
            Label(tr("Shared workout recap", "Felles treningssammendrag"), systemImage: "chart.bar").font(.headline)
            Text(tr("Only recorded start and finish times are shown.", "Viser kun faktisk registrert start og slutt."))
                .font(.caption).foregroundStyle(.secondary)
            ForEach([draft.ownerID, draft.partnerID], id: \.self) { id in
                let participant = people.first { $0.userID == id }
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(name(id)).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(participant?.workoutFinishedAt != nil ? tr("Completed", "Fullført")
                             : participant?.workoutStartedAt != nil ? tr("Training", "Trener")
                             : tr("Not recorded", "Ikke registrert"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let start = participant?.workoutStartedAt, let end = participant?.workoutFinishedAt, end >= start {
                        Text("\(Int(end.timeIntervalSince(start) / 60)) min · " + start.formatted(date: .omitted, time: .shortened) + "–" + end.formatted(date: .omitted, time: .shortened))
                            .font(.subheadline.monospacedDigit()).foregroundStyle(accent)
                    }
                }
                Divider()
            }
        }
    }

    private struct RoomPresence: Decodable {
        let userID: UUID
        let status: String
        let updatedAt: Date
        enum CodingKeys: String, CodingKey { case status; case userID = "user_id"; case updatedAt = "updated_at" }
    }
    private struct RoomRevision: Decodable, Identifiable {
        let revision: Int
        let actorID: UUID
        let changedFields: [String]
        let createdAt: Date
        var id: Int { revision }
        enum CodingKeys: String, CodingKey {
            case revision; case actorID = "actor_id"; case changedFields = "changed_fields"; case createdAt = "created_at"
        }
    }
    private struct PresenceParameters: Encodable {
        let p_source: UUID
        let p_status: String
    }

    @MainActor private func updateRoomPresence(_ status: String) async {
        guard live.draft != nil, !live.isWithdrawn(sourceWorkoutID) else { return }
        do {
            try await SupabaseEnvironment.client.rpc("set_workout_room_presence",
                params: PresenceParameters(p_source: sourceWorkoutID, p_status: status)).execute()
        } catch { if !Task.isCancelled { roomDataError = tr("Room status unavailable.", "Romstatus er ikke tilgjengelig.") } }
    }

    @MainActor private func refreshRoomData() async {
        do {
            let client = SupabaseEnvironment.client
            let updatedPresence: [RoomPresence] = try await client.from("social_workout_room_presence").select()
                .eq("source_workout_id", value: sourceWorkoutID).execute().value
            let updatedHistory: [RoomRevision] = try await client.from("social_workout_room_history").select()
                .eq("source_workout_id", value: sourceWorkoutID).order("revision", ascending: false).limit(100).execute().value
            guard !Task.isCancelled else { return }
            presence = updatedPresence
            history = updatedHistory
            roomDataError = nil
            if let sessionID = matchingSession?.id {
                try await social.refreshWorkoutLobby(sessionID: sessionID)
            } else {
                await social.refresh()
            }
        } catch { if !Task.isCancelled { roomDataError = tr("Could not update room information.", "Kunne ikke oppdatere rominformasjonen.") } }
    }

    private func infoPill(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.medium))
            .foregroundStyle(accent)
            .frame(maxWidth: .infinity, minHeight: 35)
            .background(ATHLTHTrainTogetherDesign.accentSoft, in: Capsule())
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(RoomTab.allCases, id: \.self) { tab in
                Button { selectedTab = tab } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tabIcon(tab)).font(.subheadline)
                        Text(tabTitle(tab)).font(.caption2.weight(.semibold)).lineLimit(1)
                    }
                        .foregroundStyle(selectedTab == tab ? ink : ATHLTHTrainTogetherDesign.secondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(selectedTab == tab ? ATHLTHTrainTogetherDesign.surface : .clear,
                                    in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(4)
        .background(ATHLTHTrainTogetherDesign.accentSoft, in: RoundedRectangle(cornerRadius: 15))
    }

    private func workoutContent(_ workout: PlannedSession, draft: TrainTogetherLiveDraft) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(tr("Workout contents", "Øktinnhold")).font(.headline)
                Spacer()
                Text(tr("Version", "Versjon") + " \(draft.revision)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            ATHLTHWorkoutCompactOutlineView(
                blocks: ATHLTHUnifiedWorkout.editorBlocks(from: workout),
                isRunning: workout.kind == .running || workout.kind == .walking
            )
            if canEdit {
                Button {
                    editor = EditorSelection(workout: workout, revision: draft.revision,
                                             partnerName: name(otherID(draft)))
                } label: {
                    Label(draft.bothApproved ? tr("Revise approved workout", "Endre godkjent økt")
                          : tr("Add or edit exercises", "Legg til eller endre øvelser"),
                          systemImage: "square.and.pencil")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(accent)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(ATHLTHTrainTogetherDesign.accentSoft, in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
                .disabled(live.isWorking)
                .accessibilityIdentifier("athlth-shared-room-edit")
            }
        }
        .padding(13)
        .athlthTrainTogetherCard(subtle: true)
    }

    private func scheduleCard(_ workout: PlannedSession, draft: TrainTogetherLiveDraft) -> some View {
        let mayNegotiate = matchingSession == nil && draft.cancelledAt == nil &&
            (draft.ownerID == session.profile.userID || draft.partnerID == session.profile.userID)
        return ATHLTHTrainTogetherSurface {
            Label("Dato og klokkeslett", systemImage: "calendar").font(.headline)
            if let start = workout.scheduledStart {
                Text(start.formatted(date: .complete, time: .shortened))
                    .font(.subheadline.weight(.semibold))
            } else {
                Text("Tidspunkt ikke avtalt").font(.subheadline)
            }
            if let proposed = draft.proposedDate, let proposer = draft.proposedStartBy {
                Divider()
                Label("Nytt datoforslag", systemImage: "calendar.badge.clock")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(accent)
                Text(proposed.formatted(date: .complete, time: .shortened))
                    .font(.headline)
                Text(proposer == session.profile.userID
                    ? "Venter på svar fra " + name(otherID(draft))
                    : name(proposer) + " foreslår et nytt tidspunkt.")
                    .font(.caption).foregroundStyle(.secondary)
                if mayNegotiate && proposer != session.profile.userID {
                    Button {
                        Task { _ = await live.negotiateStart(nil, accept: true, basedOn: draft.revision) }
                    } label: {
                        Label("Godta ny dato", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent).tint(accent)
                    .disabled(live.isWorking || proposed <= Date())
                }
            }
            if mayNegotiate {
                if let revision = dateProposalRevision {
                    DatePicker("Ny dato", selection: $dateProposal, in: Date()...,
                               displayedComponents: [.date, .hourAndMinute])
                    HStack {
                        Button("Avbryt") { dateProposalRevision = nil }
                            .buttonStyle(.bordered)
                        Spacer()
                        Button("Send forslag") {
                            Task {
                                if await live.negotiateStart(dateProposal, accept: false, basedOn: revision) {
                                    dateProposalRevision = nil
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent).tint(accent)
                        .disabled(live.isWorking || dateProposal <= Date() || revision != draft.revision)
                    }
                    if revision != draft.revision {
                        Text("Økten er endret. Lukk og åpne datovalget på nytt.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        dateProposal = max(draft.proposedDate ?? workout.scheduledStart ?? Date(),
                                           Date().addingTimeInterval(3600))
                        dateProposalRevision = draft.revision
                    } label: {
                        Label(draft.proposedDate == nil ? "Foreslå ny dato" : "Foreslå en annen dato",
                              systemImage: "calendar.badge.plus")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered).tint(accent)
                    .disabled(live.isWorking)
                }
            }
        }
    }

    private func approvalCard(_ draft: TrainTogetherLiveDraft) -> some View {
        let mineApproved = isOwner ? draft.ownerApproved : draft.partnerApproved
        return ATHLTHTrainTogetherSurface {
            HStack {
                Text(tr("Approve workout", "Godkjenn økten")).font(.headline)
                Spacer()
                Text("\((draft.ownerApproved ? 1 : 0) + (draft.partnerApproved ? 1 : 0))/2")
                    .font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(accent)
            }
            approvalRow(name(draft.ownerID), approved: draft.ownerApproved)
            Divider()
            approvalRow(name(draft.partnerID), approved: draft.partnerApproved)
            if draft.proposedStart != nil {
                Label("Avklar datoforslaget før dere godkjenner økten.", systemImage: "calendar.badge.clock")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else if draft.bothApproved {
                Label(tr("Both have approved. Ready lobby can be opened.",
                         "Begge har godkjent. Klar-lobbyen kan åpnes."),
                      systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.medium)).foregroundStyle(accent)
                if isOwner {
                    Button {
                        if let onOpenReady { onOpenReady() }
                        else { Task { await openOwnerReady() } }
                    } label: {
                        Label(tr("Open Ready lobby", "Åpne Klar-lobby"), systemImage: "person.2.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent).tint(accent)
                    .disabled(live.isWorking || openingReady || matchingSession?.coordinatedStartAt != nil || matchingSession?.resolvedWorkoutPhase == .completed)
                } else if !isOwner, matchingInvite != nil {
                    Button { showingGuestLobby = true } label: {
                        Label(tr("Join Ready lobby", "Gå til Klar-lobby"), systemImage: "person.2.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent).tint(accent)
                } else {
                    Text(tr("Waiting for the host to open Ready.", "Venter på at arrangøren åpner Klar."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Button { Task { await live.approve() } } label: {
                    Label(mineApproved ? tr("Waiting for ", "Venter på ") + name(otherID(draft))
                          : tr("Approve this workout", "Godkjenn denne økten"),
                          systemImage: mineApproved ? "clock" : "checkmark.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(mineApproved ? accent : .white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(mineApproved ? ATHLTHTrainTogetherDesign.accentSoft : accent,
                                    in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
                .disabled(mineApproved || live.isWorking)
            }
            Text(tr("Editing resets both approvals.", "Endringer nullstiller begge godkjenningene."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @MainActor private func openOwnerReady() async {
        guard !openingReady, isOwner else { return }
        if let current = social.coordinatedLobbySessionID {
            if current == matchingSession?.id { social.presentCoordinatedLobby() }
            else { roomDataError = tr("Another workout lobby is active.", "En annen øktlobby er aktiv.") }
            return
        }
        openingReady = true
        defer { openingReady = false }
        await live.refresh(sourceWorkoutID)
        guard let draft = live.draft, draft.bothApproved, isOwner,
              var approved = live.workout,
              let local = session.standalonePlannedSessions.first(where: {
                  $0.id == sourceWorkoutID && $0.cancelledAt == nil && !$0.isExplicitRestDay
              }), session.recordedTimes(for: sourceWorkoutID)?.endedAt == nil,
              let friend = social.trainingPartners.first(where: { $0.userID == draft.partnerID }),
              social.coordinatedLobbySessionID == nil else {
            roomDataError = tr("The approved workout or training partner is unavailable.", "Godkjent økt eller treningspartner er ikke tilgjengelig.")
            return
        }
        approved.gearIDs = local.gearIDs
        approved.spotifyPlaylist = local.spotifyPlaylist
        approved.spotifyAutoplayOnStart = local.spotifyAutoplayOnStart
        approved.spotifyIntervalTrack = nil
        let started = await social.beginWorkoutWithFriends(
            title: approved.title, kind: approved.kind, friends: [friend],
            creatorName: session.profile.displayName, creatorUsername: session.profile.username,
            invitePayload: SocialWorkoutInvitePayload(workout: approved,
                participationMode: draft.isPhysical ? .physical : .remote,
                maxParticipants: 2, startIndependently: false),
            creatorCaptureDevice: .iPhone
        )
        guard started, let joinedID = social.currentJoinedWorkoutSessionID else {
            if let error = social.errorMessage { roomDataError = error }
            return
        }
        social.requestSharedRoomLaunch(workoutID: sourceWorkoutID, sessionID: joinedID,
                                       device: social.proposedCreatorCaptureDevice(for: joinedID))
    }

    private func approvalRow(_ label: String, approved: Bool) -> some View {
        HStack(spacing: 10) {
            Text(String(label.prefix(1)).uppercased())
                .font(.subheadline.weight(.semibold)).foregroundStyle(accent)
                .frame(width: 36, height: 36)
                .background(ATHLTHTrainTogetherDesign.accentSoft, in: Circle())
            Text(label).font(.subheadline.weight(.medium)).foregroundStyle(ink)
            Spacer()
            Label(approved ? tr("Approved", "Godkjent") : tr("Pending", "Ikke godkjent"),
                  systemImage: approved ? "checkmark.circle.fill" : "circle.dotted")
                .font(.caption.weight(.medium))
                .foregroundStyle(approved ? accent : .secondary)
        }
    }

    private func sharedEditor(_ selection: EditorSelection) -> some View {
        let source = selection.workout
        return WorkoutTemplateBuilderView(
            initialTitle: source.title,
            initialBlocks: ATHLTHUnifiedWorkout.editorBlocks(from: source),
            initialRouteID: source.routeID,
            initialDurationOverrideMinutes: source.durationMinutes,
            initialExtras: ATHLTHWorkoutPlannerExtras(
                audioCoachConfiguration: source.audioCoachConfiguration,
                routeAlertConfiguration: source.routeAlertConfiguration,
                ghostTargetDurationSeconds: source.ghostTargetDurationSeconds,
                ghostUpdates: source.ghostUpdates,
                intervalGhostConfiguration: source.resolvedWorkoutBlocks.first?.intervalGhostConfiguration
            ),
            draftContext: "train-together-\(source.id.uuidString)-revision-\(selection.revision)",
            plannedDate: source.scheduledStart,
            initialActivity: ATHLTHPlannedWorkoutType.from(source),
            initialStudioAdvanced: true,
            collaborationPartnerName: selection.partnerName,
            collaborationWorkoutID: source.id,
            collaborationInviteSent: true,
            saveButtonTitle: tr("Save shared workout", "Lagre fellesøkt"),
            onSaveSharedRevision: { edited in
                guard canEdit else { return tr("Editing is no longer available.", "Redigering er ikke lenger tilgjengelig.") }
                let revision = TrainTogetherLiveDraftStore.mergingEditorRecipe(edited, into: source)
                let saved = await live.save(revision, basedOn: selection.revision)
                return saved ? nil : (live.errorMessage ?? tr("Could not save the workout.", "Kunne ikke lagre økten."))
            }
        )
    }
}

/// Only a deliberately chosen meeting pin is shared, never live GPS.
private struct SharedWorkoutMeetingPicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var point: PlannedWorkoutMeetingPoint?
    @State private var query = ""
    @State private var position: MapCameraPosition = .automatic
    @State private var busy = false
    @State private var error: String?
    let onSave: (PlannedWorkoutMeetingPoint?) async -> String?

    init(initial: PlannedWorkoutMeetingPoint?, onSave: @escaping (PlannedWorkoutMeetingPoint?) async -> String?) {
        _point = State(initialValue: initial)
        _query = State(initialValue: initial?.address ?? initial?.name ?? "")
        self.onSave = onSave
        if let initial {
            _position = State(initialValue: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: initial.latitude, longitude: initial.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))))
        }
    }
    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack {
                    TextField(tr("Search for an address", "Søk etter sted eller adresse"), text: $query)
                        .textFieldStyle(.roundedBorder).submitLabel(.search)
                        .onSubmit { Task { await lookup() } }
                    Button { Task { await lookup() } } label: {
                        Image(systemName: "magnifyingglass")
                    }.disabled(busy || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                MapReader { proxy in
                    Map(position: $position) {
                        if let point {
                            Marker(point.name, coordinate: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
                        }
                    }
                    .onTapGesture { location in
                        if let coordinate = proxy.convert(location, from: .local), !busy {
                            point = PlannedWorkoutMeetingPoint(name: query.isEmpty ? tr("Meeting point", "Møtested") : query,
                                address: "", latitude: coordinate.latitude, longitude: coordinate.longitude)
                        }
                    }
                }
                .frame(minHeight: 220).clipShape(RoundedRectangle(cornerRadius: 16))
                if let point { Label(point.name, systemImage: "mappin").font(.subheadline) }
                Button(tr("Remove meeting point", "Fjern møtested"), role: .destructive) { point = nil }
                    .disabled(busy || point == nil)
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
            .padding(16)
            .background(ATHLTHTrainTogetherDesign.canvas)
            .navigationTitle(tr("Meeting point", "Møtested"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel", "Avbryt")) { dismiss() }.disabled(busy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Save", "Lagre")) {
                        Task {
                            busy = true
                            let failure = await onSave(point)
                            busy = false
                            if let failure { error = failure } else { dismiss() }
                        }
                    }.disabled(busy)
                }
            }
        }
        .interactiveDismissDisabled(busy)
    }
    @MainActor private func lookup() async {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = clean
            let response = try await MKLocalSearch(request: request).start()
            guard let item = response.mapItems.first else {
                error = tr("No place found.", "Fant ikke stedet."); return
            }
            let coordinate = item.placemark.coordinate
            point = PlannedWorkoutMeetingPoint(name: item.name ?? clean,
                address: item.placemark.title ?? clean, latitude: coordinate.latitude, longitude: coordinate.longitude)
            position = .region(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)))
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

/// Separate chat per source workout. No ordinary direct messages or other
/// rooms are queried. RLS enforces membership, blocking and cancellation.
private struct TrainTogetherRoomMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let sourceWorkoutID: UUID
    let senderID: UUID
    let body: String
    let createdAt: Date
    enum CodingKeys: String, CodingKey {
        case id, body
        case sourceWorkoutID = "source_workout_id"
        case senderID = "sender_id"
        case createdAt = "created_at"
    }
}

private struct TrainTogetherRoomMessageInsert: Encodable {
    let id: UUID
    let sourceWorkoutID: UUID
    let senderID: UUID
    let body: String
    enum CodingKeys: String, CodingKey {
        case id, body
        case sourceWorkoutID = "source_workout_id"
        case senderID = "sender_id"
    }
}

struct TrainTogetherRoomChat: View {
    @Environment(\.scenePhase) private var scenePhase
    let sourceID: UUID
    let userID: UUID
    let partnerName: String
    let canSend: Bool
    @State private var messages: [TrainTogetherRoomMessage] = []
    @State private var input = ""
    @State private var sending = false
    @State private var loading = false
    @State private var error: String?
    @State private var limit = 50
    private let client = SupabaseEnvironment.client
    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        ATHLTHTrainTogetherSurface {
            HStack {
                Label(tr("Workout chat", "Øktchat"), systemImage: "bubble.left.and.bubble.right")
                    .font(.headline)
                Spacer()
                Label(tr("Private", "Privat"), systemImage: "lock.fill")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(tr("Only you and your training partner can see this chat.",
                    "Bare du og treningspartneren din kan se denne chatten."))
                .font(.caption).foregroundStyle(.secondary)
            if messages.count >= limit {
                Button(tr("Load earlier messages", "Last inn tidligere meldinger")) {
                    limit += 50
                    Task { await refresh() }
                }
                .font(.caption.weight(.semibold))
            }
            if messages.isEmpty {
                Text(tr("No messages yet. Discuss the workout here.", "Ingen meldinger ennå. Avtal økten her."))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .padding(.vertical, 10)
            }
            if !messages.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(messages) { message in
                                let mine = message.senderID == userID
                                HStack {
                                    if mine { Spacer(minLength: 36) }
                                    VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                                        Text(mine ? tr("You", "Du") : partnerName)
                                            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                                        Text(message.body)
                                            .font(.subheadline)
                                            .foregroundStyle(ATHLTHTrainTogetherDesign.ink)
                                            .padding(11)
                                            .background(mine ? ATHLTHTrainTogetherDesign.accentSoft : ATHLTHTrainTogetherDesign.surface,
                                                        in: RoundedRectangle(cornerRadius: 13))
                                        Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                    if !mine { Spacer(minLength: 36) }
                                }
                            }
                        }
                        Color.clear.frame(height: 1).id("room-chat-bottom")
                    }
                    .frame(maxHeight: 320)
                    .defaultScrollAnchor(.bottom)
                    .onChange(of: messages.last?.id) { _, _ in
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("room-chat-bottom", anchor: .bottom)
                        }
                    }
                }
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            HStack(alignment: .bottom, spacing: 9) {
                TextField(tr("Write a message…", "Skriv en melding…"), text: $input, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(10)
                    .background(ATHLTHTrainTogetherDesign.accentSoft, in: RoundedRectangle(cornerRadius: 12))
                    .disabled(!canSend || sending)
                Button { Task { await send() } } label: {
                    Image(systemName: "arrow.up")
                        .font(.headline.weight(.semibold)).foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(ATHLTHTrainTogetherDesign.accent, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend || sending || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || input.count > 2000)
                .accessibilityLabel(tr("Send message", "Send melding"))
            }
        }
        .accessibilityIdentifier("athlth-shared-room-chat")
        .task(id: sourceID) {
            await refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { break }
                if scenePhase == .active { await refresh() }
            }
        }
    }

    @MainActor private func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let rows: [TrainTogetherRoomMessage] = try await client
                .from("social_workout_room_messages").select()
                .eq("source_workout_id", value: sourceID)
                .order("created_at", ascending: false)
                .limit(limit).execute().value
            guard !Task.isCancelled else { return }
            messages = Array(rows.reversed())
        } catch is CancellationError {
        } catch { self.error = error.localizedDescription }
    }

    @MainActor private func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend, !sending, !text.isEmpty, text.count <= 2000 else { return }
        sending = true
        error = nil
        defer { sending = false }
        do {
            try await client.from("social_workout_room_messages")
                .insert(TrainTogetherRoomMessageInsert(id: UUID(), sourceWorkoutID: sourceID,
                                                       senderID: userID, body: text))
                .execute()
            input = ""
            await refresh()
        } catch { self.error = error.localizedDescription }
    }
}

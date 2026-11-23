import Foundation
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

    var id: UUID { sourceWorkoutID }
    var isCollaborative: Bool { editMode == "collaborative" }
    var isPhysical: Bool { participationMode == "physical" }
    var ownerApproved: Bool { ownerApprovedRevision == revision }
    var partnerApproved: Bool { partnerApprovedRevision == revision }
    var bothApproved: Bool { cancelledAt == nil && ownerApproved && partnerApproved }

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

    func approve() async {
        guard let current = draft, !isWorking else { return }
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

    let sourceWorkoutID: UUID
    let fallbackWorkout: PlannedSession

    private enum RoomTab: String, CaseIterable { case workout, chat }
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
        return isOwner || draft.isCollaborative
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                if let draft = live.draft, let workout = live.workout {
                    details(workout, draft: draft)
                    tabBar
                    if selectedTab == .workout {
                        workoutContent(workout, draft: draft)
                        approvalCard(draft)
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
        .task(id: sourceWorkoutID) { await live.watch(sourceWorkoutID) }
        .task(id: sourceWorkoutID) {
            await social.refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
                if scenePhase == .active { await live.refresh(sourceWorkoutID, quiet: true) }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await live.refresh(sourceWorkoutID, quiet: true) } }
        }
        .onChange(of: live.draft?.revision) { _, _ in
            guard isOwner, var updated = live.workout,
                  let local = session.standalonePlannedSessions.first(where: { $0.id == updated.id })
            else { return }
            updated.gearIDs = local.gearIDs
            updated.spotifyPlaylist = local.spotifyPlaylist
            updated.spotifyAutoplayOnStart = local.spotifyAutoplayOnStart
            updated.spotifyIntervalTrack = local.spotifyIntervalTrack
            session.updateStandalonePlannedSession(updated)
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
                    Label(tab == .workout ? tr("Workout", "Økten") : tr("Chat", "Chat"),
                          systemImage: tab == .workout ? "list.bullet.rectangle" : "bubble.left.and.bubble.right")
                        .font(.subheadline.weight(.semibold))
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
            if draft.bothApproved {
                Label(tr("Both have approved. Ready lobby can be opened.",
                         "Begge har godkjent. Klar-lobbyen kan åpnes."),
                      systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.medium)).foregroundStyle(accent)
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

private struct TrainTogetherRoomChat: View {
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

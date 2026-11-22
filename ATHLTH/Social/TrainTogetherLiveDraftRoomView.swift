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

    var id: UUID { sourceWorkoutID }
    var isCollaborative: Bool { editMode == "collaborative" }
    var isPhysical: Bool { participationMode == "physical" }
    var ownerApproved: Bool { ownerApprovedRevision == revision }
    var partnerApproved: Bool { partnerApprovedRevision == revision }
    var bothApproved: Bool { ownerApproved && partnerApproved }

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

    private let client = SupabaseEnvironment.client

    static func privateSnapshot(_ workout: PlannedSession) -> PlannedSession {
        var copy = workout
        copy.gearIDs = []
        copy.spotifyPlaylist = nil
        copy.spotifyAutoplayOnStart = false
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
        if !quiet { isLoading = true }
        defer { isLoading = false }
        do {
            let rows: [TrainTogetherLiveDraft] = try await client
                .from("social_workout_draft_lobbies")
                .select()
                .eq("source_workout_id", value: sourceID)
                .limit(1)
                .execute()
                .value
            draft = rows.first
            errorMessage = nil
        } catch {
            if !quiet { errorMessage = error.localizedDescription }
        }
    }

    func save(
        _ proposed: PlannedSession,
        basedOn originalRevision: Int
    ) async {
        guard let current = draft, !isWorking,
              proposed.id == current.sourceWorkoutID,
              current.revision == originalRevision else {
            errorMessage = ATHLTHLocalization.choose(
                english: "The workout changed. Reopen the editor to review the latest version.",
                norwegian: "Økten ble endret. Åpne redigering på nytt for å se nyeste versjon."
            )
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            try await client.rpc(
                "update_social_workout_draft",
                params: TrainTogetherUpdateDraftParameters(
                    sourceID: current.sourceWorkoutID,
                    expectedRevision: originalRevision,
                    snapshot: try Self.encode(proposed)
                )
            ).execute()
            await refresh(current.sourceWorkoutID)
        } catch {
            errorMessage = error.localizedDescription
            await refresh(current.sourceWorkoutID, quiet: true)
        }
    }

    func approve() async {
        guard let current = draft, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await client.rpc(
                "approve_social_workout_draft",
                params: TrainTogetherApproveDraftParameters(
                    sourceID: current.sourceWorkoutID,
                    expectedRevision: current.revision
                )
            ).execute()
            await refresh(current.sourceWorkoutID)
        } catch {
            errorMessage = error.localizedDescription
            await refresh(current.sourceWorkoutID, quiet: true)
        }
    }

    /// Postgres Changes is authorized by row-level security. No invitation,
    /// exercise or permission data is sent through a public channel.
    func watch(_ sourceID: UUID) async {
        await refresh(sourceID)
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

/// The same workout editor is used for running, walking, strength and every
/// other supported workout kind. No separate strength-only collaboration path.
struct TrainTogetherLiveDraftRoomView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var social: SocialStore
    @StateObject private var live = TrainTogetherLiveDraftStore()
    @State private var showEditor = false
    @State private var editingRevision = 0

    let sourceWorkoutID: UUID
    let fallbackWorkout: PlannedSession

    private var isOwner: Bool {
        live.draft?.ownerID == social.currentUserID
    }

    private var canEdit: Bool {
        guard let draft = live.draft else { return false }
        return isOwner || draft.isCollaborative
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let draft = live.draft, let workout = draft.workout {
                    ATHLTHTrainTogetherSurface {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "LIVE WORKOUT PLANNING",
                                    norwegian: "FELLES ØKTPLANLEGGING"
                                ),
                                systemImage: "person.2.fill"
                            )
                            .font(.caption.weight(.bold))
                            .foregroundStyle(ATHLTHTrainTogetherDesign.accent)

                            Text(workout.title)
                                .font(.system(size: 26, weight: .semibold, design: .serif))

                            Label(workout.kind.title, systemImage: workout.kind.systemImage)
                            Label(
                                draft.isCollaborative
                                    ? ATHLTHLocalization.choose(
                                        english: "Both can edit", norwegian: "Begge kan redigere"
                                    )
                                    : ATHLTHLocalization.choose(
                                        english: "Organizer edits · guest views",
                                        norwegian: "Arrangør redigerer · gjest leser"
                                    ),
                                systemImage: draft.isCollaborative
                                    ? "square.and.pencil" : "lock.fill"
                            )
                            Label(
                                draft.isPhysical
                                    ? ATHLTHLocalization.choose(
                                        english: "Training together in person",
                                        norwegian: "Trener fysisk sammen"
                                    )
                                    : ATHLTHLocalization.choose(
                                        english: "Training from separate locations",
                                        norwegian: "Trener hver for dere"
                                    ),
                                systemImage: draft.isPhysical
                                    ? "person.2" : "network"
                            )
                            .font(.subheadline)
                        }
                    }

                    ATHLTHTrainTogetherSurface {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(ATHLTHLocalization.choose(
                                    english: "Workout exercises",
                                    norwegian: "Øvelser i økten"
                                ))
                                .font(.headline)
                                Spacer()
                                Text("v\(draft.revision)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }

                            if workout.exercises.isEmpty &&
                               workout.resolvedWorkoutBlocks.isEmpty {
                                Text(ATHLTHLocalization.choose(
                                    english: "No exercises added yet.",
                                    norwegian: "Ingen øvelser lagt til ennå."
                                ))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            } else {
                                ForEach(workout.resolvedWorkoutBlocks) { block in
                                    Label(block.title, systemImage: "rectangle.stack")
                                        .font(.subheadline)
                                }
                                ForEach(workout.exercises) { exercise in
                                    Label(
                                        exercise.embeddedExercise.displayName,
                                        systemImage: "dumbbell"
                                    )
                                    .font(.subheadline)
                                }
                            }

                            if canEdit && !draft.bothApproved {
                                Button {
                                    editingRevision = draft.revision
                                    showEditor = true
                                } label: {
                                    Label(
                                        ATHLTHLocalization.choose(
                                            english: "Add or edit exercises",
                                            norwegian: "Legg til eller endre øvelser"
                                        ),
                                        systemImage: "plus.circle.fill"
                                    )
                                    .frame(maxWidth: .infinity, minHeight: 45)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(ATHLTHTrainTogetherDesign.accent)
                            }
                            if canEdit && draft.bothApproved {
                                Button {
                                    editingRevision = draft.revision
                                    showEditor = true
                                } label: {
                                    Label(
                                        ATHLTHLocalization.choose(
                                            english: "Revise approved workout",
                                            norwegian: "Endre godkjent økt"
                                        ),
                                        systemImage: "pencil"
                                    )
                                }
                                .font(.caption)
                            }
                        }
                    }

                    ATHLTHTrainTogetherSurface {
                        VStack(alignment: .leading, spacing: 11) {
                            Text(ATHLTHLocalization.choose(
                                english: "Approve workout before Ready",
                                norwegian: "Godkjenn økten før Klar"
                            ))
                            .font(.headline)

                            approvalRow(
                                label: ATHLTHLocalization.choose(
                                    english: "Organizer", norwegian: "Arrangør"
                                ),
                                approved: draft.ownerApproved
                            )
                            approvalRow(
                                label: ATHLTHLocalization.choose(
                                    english: "Training partner", norwegian: "Treningspartner"
                                ),
                                approved: draft.partnerApproved
                            )

                            if draft.bothApproved {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english: "Approved by both. The organizer can open the Ready lobby.",
                                        norwegian: "Begge har godkjent. Arrangøren kan åpne Klar-lobbyen."
                                    ),
                                    systemImage: "checkmark.seal.fill"
                                )
                                .foregroundStyle(ATHLTHTrainTogetherDesign.accent)
                                .font(.subheadline)
                            } else {
                                let mineApproved = isOwner
                                    ? draft.ownerApproved : draft.partnerApproved
                                Button {
                                    Task { await live.approve() }
                                } label: {
                                    Label(
                                        mineApproved
                                            ? ATHLTHLocalization.choose(
                                                english: "Waiting for partner",
                                                norwegian: "Venter på den andre"
                                            )
                                            : ATHLTHLocalization.choose(
                                                english: "Approve this workout",
                                                norwegian: "Godkjenn denne økten"
                                            ),
                                        systemImage: mineApproved
                                            ? "clock" : "checkmark.circle"
                                    )
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(ATHLTHTrainTogetherDesign.accent)
                                .disabled(mineApproved || live.isWorking)
                            }
                            Text(ATHLTHLocalization.choose(
                                english: "Any new edit clears both approvals so neither person starts with an outdated plan.",
                                norwegian: "Nye endringer nullstiller begge godkjenningene, slik at ingen starter med en utdatert plan."
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                } else if live.isLoading {
                    ProgressView()
                } else {
                    ATHLTHTrainTogetherSurface {
                        Text(ATHLTHLocalization.choose(
                            english: "No shared draft found for this invitation. The original invitation is still available.",
                            norwegian: "Fant ikke fellesutkast for denne invitasjonen. Den opprinnelige invitasjonen er fortsatt tilgjengelig."
                        ))
                        .font(.subheadline)
                    }
                }
                if let error = live.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Button {
                    Task { await live.refresh(sourceWorkoutID) }
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Refresh workout", norwegian: "Oppdater økten"
                        ),
                        systemImage: "arrow.clockwise"
                    )
                }
                .font(.caption)
                .tint(ATHLTHTrainTogetherDesign.accent)
            }
            .frame(maxWidth: 660)
            .padding(16)
            .frame(maxWidth: .infinity)
        }
        .background(ATHLTHTrainTogetherDesign.canvas.ignoresSafeArea())
        .navigationTitle(ATHLTHLocalization.choose(
            english: "Shared workout", norwegian: "Fellesøkt"
        ))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEditor) {
            SessionEditorView(
                standaloneDate: live.draft?.workout?.scheduledStart
                    ?? fallbackWorkout.scheduledStart ?? Date(),
                initialSourceWorkout: live.draft?.workout ?? fallbackWorkout,
                preserveSourceID: true,
                onPreparedWorkout: { proposed in
                    Task {
                        await live.save(proposed, basedOn: editingRevision)
                    }
                }
            )
        }
        .task(id: sourceWorkoutID) {
            await live.watch(sourceWorkoutID)
        }
        .task(id: sourceWorkoutID) {
            // Reconnect/poll fallback for suspended Realtime transports.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6))
                if Task.isCancelled { break }
                await live.refresh(sourceWorkoutID, quiet: true)
            }
        }
        .onChange(of: live.draft?.revision) { _, _ in
            guard isOwner,
                  let updated = live.draft?.workout,
                  session.standalonePlannedSessions.contains(where: {
                      $0.id == updated.id
                  }) else { return }
            session.updateStandalonePlannedSession(updated)
        }
    }

    private func approvalRow(label: String, approved: Bool) -> some View {
        HStack {
            Image(systemName: approved
                ? "checkmark.circle.fill" : "circle.dotted")
            .foregroundStyle(approved
                ? ATHLTHTrainTogetherDesign.accent : Color.secondary)
            Text(label)
            Spacer()
            Text(approved
                ? ATHLTHLocalization.choose(
                    english: "Approved", norwegian: "Godkjent"
                )
                : ATHLTHLocalization.choose(
                    english: "Not approved", norwegian: "Ikke godkjent"
                ))
            .font(.caption.weight(.semibold))
        }
        .font(.subheadline)
    }
}

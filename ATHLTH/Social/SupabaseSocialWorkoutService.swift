import Foundation
import Supabase

extension SupabaseSocialService {
    func createWorkoutSession(
        title: String,
        workoutKind: WorkoutKind,
        creatorName: String,
        creatorUsername: String?,
        friends: [SocialProfileCard]
    ) async throws -> SocialWorkoutSessionRecord {
        guard let currentUserID else {
            throw SocialServiceError.notAuthenticated
        }

        let now = Date()
        let session = SocialWorkoutSessionRecord(
            id: UUID(),
            creatorID: currentUserID,
            title: title,
            workoutKind: workoutKind.rawValue,
            status: .active,
            startedAt: now,
            endedAt: nil,
            sourceWorkoutID: nil,
            createdAt: now,
            updatedAt: now
        )

        try await client
            .from("social_workout_sessions")
            .insert(WorkoutSessionWrite(record: session))
            .execute()

        var participants: [WorkoutParticipantWrite] = [
            WorkoutParticipantWrite(
                id: UUID(),
                sessionID: session.id,
                userID: currentUserID,
                invitedBy: currentUserID,
                state: SocialWorkoutParticipantState.creator.rawValue,
                displayNameSnapshot: creatorName,
                usernameSnapshot: creatorUsername,
                invitedAt: now,
                respondedAt: now
            )
        ]

        participants.append(
            contentsOf: friends.map { friend in
                WorkoutParticipantWrite(
                    id: UUID(),
                    sessionID: session.id,
                    userID: friend.userID,
                    invitedBy: currentUserID,
                    state: SocialWorkoutParticipantState.invited.rawValue,
                    displayNameSnapshot: friend.resolvedName,
                    usernameSnapshot: friend.username,
                    invitedAt: now,
                    respondedAt: nil
                )
            }
        )

        try await client
            .from("social_workout_participants")
            .insert(participants)
            .execute()

        return session
    }

    func loadWorkoutSessions() async throws -> [SocialWorkoutSessionRecord] {
        try await client
            .from("social_workout_sessions")
            .select()
            .order("created_at", ascending: false)
            .limit(100)
            .execute()
            .value
    }

    func loadWorkoutParticipants() async throws -> [SocialWorkoutParticipantRecord] {
        try await client
            .from("social_workout_participants")
            .select()
            .order("invited_at", ascending: false)
            .limit(300)
            .execute()
            .value
    }

    func respondToWorkoutInvite(
        participantID: UUID,
        state: SocialWorkoutParticipantState
    ) async throws {
        guard state == .accepted || state == .declined else {
            throw SocialWorkoutServiceError.invalidInviteTransition
        }

        try await client
            .from("social_workout_participants")
            .update(["state": state.rawValue])
            .eq("id", value: participantID)
            .execute()
    }

    func completeWorkoutSession(
        sessionID: UUID,
        sourceWorkoutID: UUID,
        endedAt: Date
    ) async throws {
        try await client
            .from("social_workout_sessions")
            .update(
                WorkoutSessionCompletionWrite(
                    status: SocialWorkoutSessionStatus.completed.rawValue,
                    endedAt: endedAt,
                    sourceWorkoutID: sourceWorkoutID
                )
            )
            .eq("id", value: sessionID)
            .execute()
    }

    func cancelWorkoutSession(_ sessionID: UUID) async throws {
        try await client
            .from("social_workout_sessions")
            .update(["status": SocialWorkoutSessionStatus.cancelled.rawValue])
            .eq("id", value: sessionID)
            .execute()
    }

    func isActivityPublished(eventKey: String) async throws -> Bool {
        guard let currentUserID else {
            throw SocialServiceError.notAuthenticated
        }

        let rows: [SocialActivityRecord] = try await client
            .from("social_activities")
            .select()
            .eq("actor_id", value: currentUserID)
            .eq("event_key", value: eventKey)
            .limit(1)
            .execute()
            .value

        return !rows.isEmpty
    }

    func publishWorkoutActivity(
        eventKey: String,
        title: String,
        subtitle: String?,
        metadata: [String: String],
        visibility: ProfileVisibility,
        workoutSessionID: UUID?
    ) async throws {
        guard let currentUserID else {
            throw SocialServiceError.notAuthenticated
        }

        guard try await !isActivityPublished(eventKey: eventKey) else {
            return
        }

        try await client
            .from("social_activities")
            .insert(
                WorkoutActivityInsert(
                    actorID: currentUserID,
                    kind: "workout",
                    title: title,
                    subtitle: subtitle,
                    metadata: metadata,
                    visibility: visibility.rawValue,
                    eventKey: eventKey,
                    workoutSessionID: workoutSessionID
                )
            )
            .execute()
    }
}

enum SocialWorkoutServiceError: LocalizedError {
    case invalidInviteTransition

    var errorDescription: String? {
        switch self {
        case .invalidInviteTransition:
            return "That workout invite action is not available."
        }
    }
}

private struct WorkoutSessionWrite: Encodable {
    let id: UUID
    let creatorID: UUID
    let title: String
    let workoutKind: String
    let status: String
    let startedAt: Date
    let endedAt: Date?
    let sourceWorkoutID: UUID?
    let createdAt: Date
    let updatedAt: Date?

    init(record: SocialWorkoutSessionRecord) {
        id = record.id
        creatorID = record.creatorID
        title = record.title
        workoutKind = record.workoutKind
        status = record.status.rawValue
        startedAt = record.startedAt
        endedAt = record.endedAt
        sourceWorkoutID = record.sourceWorkoutID
        createdAt = record.createdAt
        updatedAt = record.updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case creatorID = "creator_id"
        case title
        case workoutKind = "workout_kind"
        case status
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case sourceWorkoutID = "source_workout_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct WorkoutParticipantWrite: Encodable {
    let id: UUID
    let sessionID: UUID
    let userID: UUID
    let invitedBy: UUID
    let state: String
    let displayNameSnapshot: String
    let usernameSnapshot: String?
    let invitedAt: Date
    let respondedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case sessionID = "session_id"
        case userID = "user_id"
        case invitedBy = "invited_by"
        case state
        case displayNameSnapshot = "display_name_snapshot"
        case usernameSnapshot = "username_snapshot"
        case invitedAt = "invited_at"
        case respondedAt = "responded_at"
    }
}

private struct WorkoutSessionCompletionWrite: Encodable {
    let status: String
    let endedAt: Date
    let sourceWorkoutID: UUID

    enum CodingKeys: String, CodingKey {
        case status
        case endedAt = "ended_at"
        case sourceWorkoutID = "source_workout_id"
    }
}

private struct WorkoutActivityInsert: Encodable {
    let actorID: UUID
    let kind: String
    let title: String
    let subtitle: String?
    let metadata: [String: String]
    let visibility: String
    let eventKey: String
    let workoutSessionID: UUID?

    enum CodingKeys: String, CodingKey {
        case actorID = "actor_id"
        case kind
        case title
        case subtitle
        case metadata
        case visibility
        case eventKey = "event_key"
        case workoutSessionID = "workout_session_id"
    }
}

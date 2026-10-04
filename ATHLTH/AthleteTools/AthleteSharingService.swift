import Foundation
import Supabase

struct AthleteCoachConnection: Identifiable, Codable, Hashable {
    let id: UUID
    let athleteID: UUID
    let coachID: UUID
    let state: String
    let shareWorkouts: Bool
    let sharePlan: Bool
    let shareReadiness: Bool
    enum CodingKeys: String, CodingKey {
        case id, state
        case athleteID = "athlete_id", coachID = "coach_id", shareWorkouts = "share_workouts", sharePlan = "share_plan", shareReadiness = "share_readiness"
    }
}
struct AthleteSharedWorkout: Codable, Hashable {
    var title: String
    var activity: String
    var date: String
    var minutes: String
}
struct AthleteCoachSnapshot: Codable {
    var planText: String?
    var workouts: [AthleteSharedWorkout]?
    var readinessScore: Int?
    var updatedAt: Date
    enum CodingKeys: String, CodingKey {
        case workouts
        case planText = "plan_text", readinessScore = "readiness_score", updatedAt = "updated_at"
    }
}
struct AthleteCoachFeedback: Identifiable, Codable {
    var id = UUID()
    var connectionID: UUID
    var authorID: UUID
    var kind: String
    var body: String
    var createdAt = Date()
    enum CodingKeys: String, CodingKey {
        case id, kind, body
        case connectionID = "connection_id", authorID = "author_id", createdAt = "created_at"
    }
}
struct AthletePartnerSlot: Identifiable, Codable {
    var id = UUID()
    var userID: UUID
    var startsAt: Date
    var endsAt: Date
    var area: String
    var sport: String
    var level: String
    var enabled: Bool
    enum CodingKeys: String, CodingKey {
        case id, area, sport, level, enabled
        case userID = "user_id", startsAt = "starts_at", endsAt = "ends_at"
    }
}

@MainActor
final class AthleteSharingService: ObservableObject {
    @Published private(set) var connections: [AthleteCoachConnection] = []
    @Published private(set) var ownSlots: [AthletePartnerSlot] = []
    @Published private(set) var matches: [AthletePartnerSlot] = []
    @Published var error: String?
    @Published private(set) var busy = false
    private let client = SupabaseEnvironment.client

    func run(_ action: () async throws -> Void) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        error = nil
        do { try await action() } catch { self.error = error.localizedDescription }
    }
    func loadConnections() async throws {
        connections = []
        connections = try await client.from("athlete_coach_connections").select().order("created_at", ascending: false).limit(100).execute().value
    }
    func manage(_ action: String, connection: UUID? = nil, coach: UUID? = nil, workouts: Bool = false, plan: Bool = false, readiness: Bool = false) async throws {
        let parameters: [String: AnyJSON] = ["p_action": .string(action), "p_connection": connection.map { .string($0.uuidString) } ?? .null,
            "p_coach": coach.map { .string($0.uuidString) } ?? .null, "p_workouts": .bool(workouts), "p_plan": .bool(plan), "p_readiness": .bool(readiness)]
        try await client.rpc("manage_athlete_coach", params: parameters).execute()
        try await loadConnections()
    }
    func loadSnapshot(_ connection: UUID) async throws -> AthleteCoachSnapshot? {
        let rows: [AthleteCoachSnapshot] = try await client.from("athlete_coach_snapshots").select().eq("connection_id", value: connection).limit(1).execute().value
        return rows.first
    }
    func loadFeedback(_ connection: UUID) async throws -> [AthleteCoachFeedback] {
        try await client.from("athlete_coach_feedback").select().eq("connection_id", value: connection).order("created_at", ascending: false).limit(100).execute().value
    }
    func publish(_ connection: UUID, plan: String?, workouts: [AthleteSharedWorkout], readiness: Int?) async throws {
        struct Parameters: Encodable {
            let p_connection: UUID
            let p_plan: String?
            let p_workouts: [AthleteSharedWorkout]
            let p_readiness: Int?
        }
        try await client.rpc("publish_athlete_coach_snapshot", params: Parameters(p_connection: connection, p_plan: plan, p_workouts: workouts, p_readiness: readiness)).execute()
    }
    func sendFeedback(connection: UUID, kind: String, body: String, author: UUID) async throws {
        try await client.from("athlete_coach_feedback").insert(AthleteCoachFeedback(connectionID: connection, authorID: author, kind: kind, body: body.trimmingCharacters(in: .whitespacesAndNewlines))).execute()
    }
    func loadSlots(userID: UUID) async throws {
        ownSlots = []
        ownSlots = try await client.from("training_partner_availability").select().eq("user_id", value: userID).order("starts_at", ascending: false).limit(30).execute().value
    }
    func publishSlot(_ slot: AthletePartnerSlot) async throws {
        try await client.from("training_partner_availability").insert(slot).execute()
        try await loadSlots(userID: slot.userID)
    }
    func removeSlot(_ slot: AthletePartnerSlot) async throws {
        try await client.from("training_partner_availability").delete().eq("id", value: slot.id).execute()
        ownSlots.removeAll { $0.id == slot.id }; matches.removeAll { $0.id == slot.id }
    }
    func findMatches(userID: UUID, sport: String, area: String, level: String, start: Date, end: Date) async throws {
        matches = []
        matches = try await client.from("training_partner_availability").select()
            .eq("enabled", value: true).eq("sport", value: sport).eq("area", value: area).eq("level", value: level)
            .neq("user_id", value: userID).lt("starts_at", value: end.ISO8601Format()).gt("ends_at", value: start.ISO8601Format())
            .order("starts_at").limit(50).execute().value
    }
}

import Combine
import Foundation
import Supabase

enum GhostFriendRaceStatus: String, Codable, Hashable {
    case pending
    case accepted
    case declined
    case cancelled
}

struct GhostFriendRacePoint: Codable, Hashable {
    let latitude: Double
    let longitude: Double
    let elapsedTime: TimeInterval
    let cumulativeMeters: Double
    let sequence: Int

    enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
        case elapsedTime = "elapsed_time"
        case cumulativeMeters = "cumulative_meters"
        case sequence
    }
}

struct GhostFriendRaceChallengeRecord:
    Identifiable,
    Codable,
    Hashable
{
    let id: UUID
    let senderID: UUID
    let recipientID: UUID
    let title: String
    let referenceDurationSeconds: TimeInterval
    let distanceMeters: Double
    let routePoints: [GhostFriendRacePoint]
    let privacyTrimmed: Bool
    var status: GhostFriendRaceStatus
    let createdAt: Date
    var respondedAt: Date?
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case senderID = "sender_id"
        case recipientID = "recipient_id"
        case title
        case referenceDurationSeconds =
            "reference_duration_seconds"
        case distanceMeters = "distance_meters"
        case routePoints = "route_points"
        case privacyTrimmed = "privacy_trimmed"
        case status
        case createdAt = "created_at"
        case respondedAt = "responded_at"
        case expiresAt = "expires_at"
    }

    func reference() -> GhostRaceReference {
        GhostRaceReference(
            id: id,
            sourceWorkoutID: id,
            title: title,
            startedAt: createdAt,
            durationSeconds:
                referenceDurationSeconds,
            distanceMeters:
                distanceMeters,
            points:
                routePoints
                    .sorted {
                        $0.sequence <
                        $1.sequence
                    }
                    .map {
                        GhostRacePoint(
                            id: $0.sequence,
                            latitude: $0.latitude,
                            longitude:
                                $0.longitude,
                            altitude: nil,
                            elapsedTime:
                                $0.elapsedTime,
                            cumulativeMeters:
                                $0.cumulativeMeters
                        )
                    }
        )
    }
}

private struct GhostFriendRaceInsert: Encodable {
    let senderID: UUID
    let recipientID: UUID
    let title: String
    let referenceDurationSeconds: TimeInterval
    let distanceMeters: Double
    let routePoints: [GhostFriendRacePoint]
    let privacyTrimmed: Bool
    let status: String

    enum CodingKeys: String, CodingKey {
        case senderID = "sender_id"
        case recipientID = "recipient_id"
        case title
        case referenceDurationSeconds =
            "reference_duration_seconds"
        case distanceMeters = "distance_meters"
        case routePoints = "route_points"
        case privacyTrimmed = "privacy_trimmed"
        case status
    }
}

enum GhostFriendRaceError: LocalizedError {
    case notAuthenticated
    case routeTooShortForPrivacy
    case missingRoute
    case notAccepted

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Sign in before sending a Ghost Race."
        case .routeTooShortForPrivacy:
            return "This route is too short to hide 250 m at both the start and finish. Turn off Hide route start/end for this race or choose a longer run."
        case .missingRoute:
            return "This run does not contain enough GPS data to share as a Ghost Race."
        case .notAccepted:
            return "Accept this Ghost Race before starting it."
        }
    }
}

enum GhostFriendRaceSanitizer {
    struct Result {
        let durationSeconds: TimeInterval
        let distanceMeters: Double
        let points: [GhostFriendRacePoint]
        let privacyTrimmed: Bool
    }

    static func makePayload(
        from reference: GhostRaceReference,
        hideStartAndEnd: Bool
    ) throws -> Result {
        let sorted =
            reference.points.sorted {
                $0.cumulativeMeters <
                $1.cumulativeMeters
            }

        guard sorted.count >= 2,
              let finalDistance =
                sorted.last?.cumulativeMeters,
              finalDistance >= 250
        else {
            throw GhostFriendRaceError
                .missingRoute
        }

        let selected: [GhostRacePoint]
        let trimmed: Bool

        if hideStartAndEnd {
            let trimMeters = 250.0

            guard finalDistance >
                    trimMeters * 2 + 200
            else {
                throw GhostFriendRaceError
                    .routeTooShortForPrivacy
            }

            selected =
                sorted.filter {
                    $0.cumulativeMeters >=
                        trimMeters &&
                    $0.cumulativeMeters <=
                        finalDistance -
                        trimMeters
                }
            trimmed = true
        } else {
            selected = sorted
            trimmed = false
        }

        guard selected.count >= 2,
              let first = selected.first,
              let last = selected.last
        else {
            throw GhostFriendRaceError
                .missingRoute
        }

        let baseDistance =
            first.cumulativeMeters
        let baseTime =
            first.elapsedTime
        let distance =
            max(
                last.cumulativeMeters -
                baseDistance,
                0
            )
        let duration =
            max(
                last.elapsedTime -
                baseTime,
                0
            )

        guard distance >= 200,
              duration > 0
        else {
            throw GhostFriendRaceError
                .missingRoute
        }

        let sampleIndices =
            downsampleIndices(
                count: selected.count,
                maximumPoints: 350
            )

        let points =
            sampleIndices.enumerated().map {
                sequence,
                sourceIndex in

                let point =
                    selected[sourceIndex]

                return GhostFriendRacePoint(
                    latitude:
                        point.latitude,
                    longitude:
                        point.longitude,
                    elapsedTime:
                        max(
                            point.elapsedTime -
                            baseTime,
                            0
                        ),
                    cumulativeMeters:
                        max(
                            point.cumulativeMeters -
                            baseDistance,
                            0
                        ),
                    sequence:
                        sequence
                )
            }

        guard points.count >= 2 else {
            throw GhostFriendRaceError
                .missingRoute
        }

        return Result(
            durationSeconds: duration,
            distanceMeters: distance,
            points: points,
            privacyTrimmed: trimmed
        )
    }

    private static func downsampleIndices(
        count: Int,
        maximumPoints: Int
    ) -> [Int] {
        guard count > maximumPoints,
              maximumPoints > 2
        else {
            return Array(0..<count)
        }

        let step =
            Double(count - 1) /
            Double(maximumPoints - 1)

        var result: [Int] = []
        result.reserveCapacity(maximumPoints)

        for sample in 0..<maximumPoints {
            let index =
                min(
                    Int(
                        (
                            Double(sample) *
                            step
                        ).rounded()
                    ),
                    count - 1
                )

            if result.last != index {
                result.append(index)
            }
        }

        if result.last != count - 1 {
            result.append(count - 1)
        }

        return result
    }
}

final class SupabaseGhostFriendRaceService {
    private let client: SupabaseClient

    init(
        client: SupabaseClient =
            SupabaseEnvironment.client
    ) {
        self.client = client
    }

    var currentUserID: UUID? {
        client.auth.currentUser?.id
    }

    func load() async throws ->
        [GhostFriendRaceChallengeRecord]
    {
        try await client
            .from("ghost_race_challenges")
            .select()
            .order(
                "created_at",
                ascending: false
            )
            .limit(100)
            .execute()
            .value
    }

    func send(
        to recipientID: UUID,
        title: String,
        reference: GhostRaceReference,
        hideStartAndEnd: Bool
    ) async throws {
        guard let senderID =
                currentUserID
        else {
            throw GhostFriendRaceError
                .notAuthenticated
        }

        let sanitized =
            try GhostFriendRaceSanitizer
                .makePayload(
                    from: reference,
                    hideStartAndEnd:
                        hideStartAndEnd
                )

        let cleanTitle =
            String(
                title
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )
                    .prefix(160)
            )

        let defaultTitle =
            String(
                format:
                    "%.1f km Ghost Race",
                sanitized.distanceMeters /
                    1_000
            )

        let payload =
            GhostFriendRaceInsert(
                senderID: senderID,
                recipientID: recipientID,
                title:
                    cleanTitle.isEmpty ||
                    cleanTitle == "Ghost Race"
                        ? defaultTitle
                        : cleanTitle,
                referenceDurationSeconds:
                    sanitized
                        .durationSeconds,
                distanceMeters:
                    sanitized.distanceMeters,
                routePoints:
                    sanitized.points,
                privacyTrimmed:
                    sanitized
                        .privacyTrimmed,
                status:
                    GhostFriendRaceStatus
                        .pending.rawValue
            )

        try await client
            .from("ghost_race_challenges")
            .insert(payload)
            .execute()
    }

    func respond(
        id: UUID,
        status: GhostFriendRaceStatus
    ) async throws {
        guard status == .accepted ||
                status == .declined ||
                status == .cancelled
        else {
            return
        }

        let date =
            ISO8601DateFormatter()
                .string(from: Date())

        try await client
            .from("ghost_race_challenges")
            .update([
                "status":
                    status.rawValue,
                "responded_at":
                    date
            ])
            .eq("id", value: id)
            .execute()
    }
}

@MainActor
final class GhostFriendRaceStore:
    ObservableObject
{
    @Published private(set) var challenges:
        [GhostFriendRaceChallengeRecord] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSending = false
    @Published var errorMessage: String?

    private let service:
        SupabaseGhostFriendRaceService

    init(
        service:
            SupabaseGhostFriendRaceService =
                SupabaseGhostFriendRaceService()
    ) {
        self.service = service
    }

    var currentUserID: UUID? {
        service.currentUserID
    }

    var incoming:
        [GhostFriendRaceChallengeRecord]
    {
        guard let currentUserID else {
            return []
        }

        return challenges.filter {
            $0.recipientID ==
                currentUserID &&
            $0.status != .cancelled &&
            $0.status != .declined &&
            $0.expiresAt > Date()
        }
    }

    var outgoing:
        [GhostFriendRaceChallengeRecord]
    {
        guard let currentUserID else {
            return []
        }

        return challenges.filter {
            $0.senderID ==
                currentUserID &&
            $0.status != .cancelled &&
            $0.expiresAt > Date()
        }
    }

    func refresh() async {
        guard !isLoading else {
            return
        }

        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
        }

        do {
            challenges =
                try await service.load()
        } catch {
            errorMessage =
                error.localizedDescription
        }
    }

    func send(
        to friend: SocialProfileCard,
        workout: WorkoutSummary,
        detail: WorkoutDetail,
        settings: AppSettingsStore
    ) async -> Bool {
        guard !isSending else {
            return false
        }

        isSending = true
        errorMessage = nil
        defer {
            isSending = false
        }

        let builder = GhostRaceStore()

        do {
            try builder.prepare(
                workoutID: workout.id,
                title:
                    workout.activity.rawValue,
                activity:
                    workout.activity,
                startedAt:
                    workout.startDate,
                duration:
                    workout.duration,
                distanceMeters:
                    workout.distanceMeters,
                route:
                    detail.route
            )

            guard let reference =
                    builder.reference
            else {
                throw GhostFriendRaceError
                    .missingRoute
            }

            try await service.send(
                to: friend.userID,
                title: "Ghost Race",
                reference: reference,
                hideStartAndEnd:
                    settings
                        .hideRouteStartAndEnd
            )

            await refresh()
            return true
        } catch {
            errorMessage =
                error.localizedDescription
            return false
        }
    }

    func respond(
        _ challenge:
            GhostFriendRaceChallengeRecord,
        status: GhostFriendRaceStatus
    ) async {
        errorMessage = nil

        do {
            try await service.respond(
                id: challenge.id,
                status: status
            )
            await refresh()
        } catch {
            errorMessage =
                error.localizedDescription
        }
    }
}

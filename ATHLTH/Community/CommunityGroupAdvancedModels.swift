import Foundation

enum CommunityGroupOrganizerKind:
    String,
    Codable,
    CaseIterable,
    Identifiable,
    Hashable
{
    case person
    case group

    var id: String { rawValue }

    var title: String {
        switch self {
        case .person: return "Person"
        case .group: return "Group"
        }
    }

    var systemImage: String {
        switch self {
        case .person: return "person.fill"
        case .group: return "person.3.fill"
        }
    }
}

enum CommunityGroupContentStatus:
    String,
    Codable,
    CaseIterable,
    Identifiable,
    Hashable
{
    case draft
    case upcoming
    case live
    case completed
    case cancelled

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }
}

enum CommunityGroupScoringMode:
    String,
    Codable,
    CaseIterable,
    Identifiable,
    Hashable
{
    case cumulative
    case bestAttempt = "best_attempt"
    case completeTarget = "complete_target"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cumulative:
            return "Cumulative"
        case .bestAttempt:
            return "Best Attempt"
        case .completeTarget:
            return "Complete Target"
        }
    }

    var subtitle: String {
        switch self {
        case .cumulative:
            return "All qualifying workouts add to the result."
        case .bestAttempt:
            return "Only the participant's best qualifying attempt counts."
        case .completeTarget:
            return "Progress counts until the target is completed."
        }
    }
}

enum CommunityGroupChallengeGoalPreset:
    String,
    CaseIterable,
    Identifiable,
    Hashable
{
    case mostDistance
    case fastestTime
    case mostCompletions
    case mostActiveMinutes
    case strengthVolume
    case heaviestWeight
    case strengthReps
    case completeTarget

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mostDistance:
            return "Most Distance"
        case .fastestTime:
            return "Fastest Time"
        case .mostCompletions:
            return "Most Completions"
        case .mostActiveMinutes:
            return "Most Active Minutes"
        case .strengthVolume:
            return "Total Volume"
        case .heaviestWeight:
            return "Heaviest Weight"
        case .strengthReps:
            return "Total Reps"
        case .completeTarget:
            return "Complete Target"
        }
    }

    var metric: CommunityGroupChallengeMetric {
        switch self {
        case .mostDistance:
            return .distanceKM
        case .fastestTime:
            return .fastestTime
        case .mostCompletions:
            return .workouts
        case .mostActiveMinutes:
            return .activeMinutes
        case .strengthVolume:
            return .strengthVolume
        case .heaviestWeight:
            return .heaviestWeight
        case .strengthReps:
            return .strengthReps
        case .completeTarget:
            return .workouts
        }
    }

    var scoringMode: CommunityGroupScoringMode {
        switch self {
        case .fastestTime,
             .heaviestWeight:
            return .bestAttempt
        case .completeTarget:
            return .completeTarget
        default:
            return .cumulative
        }
    }
}

struct CommunityGroupEventAdvancedOptions:
    Encodable,
    Hashable
{
    var organizerKind: CommunityGroupOrganizerKind = .person
    var status: CommunityGroupContentStatus = .upcoming
    var capacity: Int?
    var rsvpDeadline: Date?
    var endsAt: Date?
    var meetingLatitude: Double?
    var meetingLongitude: Double?
    var repeatWeekly = false
    var repeatUntil: Date?

    enum CodingKeys: String, CodingKey {
        case organizerKind = "organizer_kind"
        case status
        case capacity
        case rsvpDeadline = "rsvp_deadline"
        case endsAt = "ends_at"
        case meetingLatitude = "meeting_lat"
        case meetingLongitude = "meeting_long"
        case repeatRule = "repeat_rule"
        case repeatUntil = "repeat_until"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(
            keyedBy: CodingKeys.self
        )

        try container.encode(
            organizerKind.rawValue,
            forKey: .organizerKind
        )
        try container.encode(
            status.rawValue,
            forKey: .status
        )
        try container.encodeIfPresent(
            capacity,
            forKey: .capacity
        )
        try container.encodeIfPresent(
            Self.isoString(rsvpDeadline),
            forKey: .rsvpDeadline
        )
        try container.encodeIfPresent(
            Self.isoString(endsAt),
            forKey: .endsAt
        )
        try container.encodeIfPresent(
            meetingLatitude,
            forKey: .meetingLatitude
        )
        try container.encodeIfPresent(
            meetingLongitude,
            forKey: .meetingLongitude
        )

        if repeatWeekly {
            try container.encode(
                "weekly",
                forKey: .repeatRule
            )
            try container.encodeIfPresent(
                Self.isoString(repeatUntil),
                forKey: .repeatUntil
            )
        }
    }

    private static func isoString(
        _ date: Date?
    ) -> String? {
        date.map {
            ISO8601DateFormatter().string(from: $0)
        }
    }
}

struct CommunityGroupChallengeAdvancedOptions:
    Encodable,
    Hashable
{
    var organizerKind: CommunityGroupOrganizerKind = .person
    var status: CommunityGroupContentStatus = .upcoming
    var scoringMode: CommunityGroupScoringMode = .cumulative
    var attemptLimit: Int?
    var routeVerificationEnabled = false
    var routeToleranceMeters = 100
    var joinRequired = true

    enum CodingKeys: String, CodingKey {
        case organizerKind = "organizer_kind"
        case status
        case scoringMode = "scoring_mode"
        case attemptLimit = "attempt_limit"
        case routeVerificationEnabled =
            "route_verification_enabled"
        case routeToleranceMeters =
            "route_tolerance_meters"
        case joinRequired = "join_required"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(
            keyedBy: CodingKeys.self
        )

        try container.encode(
            organizerKind.rawValue,
            forKey: .organizerKind
        )
        try container.encode(
            status.rawValue,
            forKey: .status
        )
        try container.encode(
            scoringMode.rawValue,
            forKey: .scoringMode
        )
        try container.encodeIfPresent(
            attemptLimit,
            forKey: .attemptLimit
        )
        try container.encode(
            routeVerificationEnabled,
            forKey: .routeVerificationEnabled
        )
        try container.encode(
            routeToleranceMeters,
            forKey: .routeToleranceMeters
        )
        try container.encode(
            joinRequired,
            forKey: .joinRequired
        )
    }
}

struct CommunityGroupContentHostRecord:
    Codable,
    Hashable,
    Identifiable
{
    var id: String {
        "\(contentType)-\(contentID)-\(userID)"
    }

    let groupID: UUID
    let contentType: String
    let contentID: UUID
    let userID: UUID
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case groupID = "group_id"
        case contentType = "content_type"
        case contentID = "content_id"
        case userID = "user_id"
        case createdAt = "created_at"
    }
}

struct CommunityGroupContentHostInsert:
    Encodable,
    Hashable
{
    let groupID: UUID
    let contentType: String
    let contentID: UUID
    let userID: UUID

    enum CodingKeys: String, CodingKey {
        case groupID = "group_id"
        case contentType = "content_type"
        case contentID = "content_id"
        case userID = "user_id"
    }
}

struct CommunityGroupChallengeParticipantRecord:
    Codable,
    Hashable,
    Identifiable
{
    var id: String {
        "\(challengeID)-\(userID)"
    }

    let groupID: UUID
    let challengeID: UUID
    let userID: UUID
    let joinedAt: Date
    let status: String

    enum CodingKeys: String, CodingKey {
        case groupID = "group_id"
        case challengeID = "challenge_id"
        case userID = "user_id"
        case joinedAt = "joined_at"
        case status
    }
}

struct CommunityGroupContentCommentRecord:
    Codable,
    Hashable,
    Identifiable
{
    let id: UUID
    let groupID: UUID
    let contentType: String
    let contentID: UUID
    let authorID: UUID
    let body: String
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case groupID = "group_id"
        case contentType = "content_type"
        case contentID = "content_id"
        case authorID = "author_id"
        case body
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct CommunityGroupContentCommentInsert:
    Encodable
{
    let groupID: UUID
    let contentType: String
    let contentID: UUID
    let authorID: UUID
    let body: String

    enum CodingKeys: String, CodingKey {
        case groupID = "group_id"
        case contentType = "content_type"
        case contentID = "content_id"
        case authorID = "author_id"
        case body
    }
}

struct CommunityGroupEventRSVPParams: Encodable {
    let eventID: UUID
    let status: String

    enum CodingKeys: String, CodingKey {
        case eventID = "p_event_id"
        case status = "p_status"
    }
}

struct CommunityGroupChallengeParticipationParams:
    Encodable
{
    let challengeID: UUID
    let join: Bool

    enum CodingKeys: String, CodingKey {
        case challengeID = "p_challenge_id"
        case join = "p_join"
    }
}

struct CommunityGroupLeaderboardEntry:
    Identifiable,
    Hashable
{
    let userID: UUID
    let displayName: String
    let username: String?
    let avatarURL: String?
    let score: Double
    let attemptCount: Int
    let rank: Int

    var id: UUID { userID }
}

extension CommunityGroupEventRecord {
    private var occurrenceDuration:
        TimeInterval {
        max(
            endsAt?.timeIntervalSince(
                startsAt
            ) ?? 3_600,
            60
        )
    }

    func nextOccurrenceStart(
        relativeTo reference: Date = Date()
    ) -> Date? {
        guard repeatRule == "weekly" else {
            return reference <=
                startsAt.addingTimeInterval(
                    occurrenceDuration
                )
                ? startsAt
                : nil
        }

        let interval:
            TimeInterval = 7 * 24 * 3_600

        if reference <= startsAt {
            return occurrenceIsAllowed(
                startsAt
            )
                ? startsAt
                : nil
        }

        let elapsed =
            reference.timeIntervalSince(
                startsAt
            )
        let completedWeeks =
            floor(elapsed / interval)
        let currentStart =
            startsAt.addingTimeInterval(
                completedWeeks * interval
            )
        let currentEnd =
            currentStart.addingTimeInterval(
                occurrenceDuration
            )

        if reference <= currentEnd,
           occurrenceIsAllowed(
               currentStart
           ) {
            return currentStart
        }

        let next =
            currentStart.addingTimeInterval(
                interval
            )

        return occurrenceIsAllowed(next)
            ? next
            : nil
    }

    func occurrenceEnd(
        for occurrenceStart: Date
    ) -> Date {
        occurrenceStart.addingTimeInterval(
            occurrenceDuration
        )
    }

    var resolvedStatus:
        CommunityGroupContentStatus {
        if status == "cancelled" {
            return .cancelled
        }

        if status == "draft" {
            return .draft
        }

        let now = Date()

        guard let occurrence =
            nextOccurrenceStart(
                relativeTo: now
            )
        else {
            return .completed
        }

        if now < occurrence {
            return .upcoming
        }

        if now <= occurrenceEnd(
            for: occurrence
        ) {
            return .live
        }

        return .upcoming
    }

    private func occurrenceIsAllowed(
        _ occurrenceStart: Date
    ) -> Bool {
        guard let repeatUntil else {
            return true
        }

        return occurrenceStart <=
            Calendar.current
                .date(
                    bySettingHour: 23,
                    minute: 59,
                    second: 59,
                    of: repeatUntil
                )
                ?? repeatUntil
    }
}

extension CommunityGroupChallengeRecord {
    var resolvedStatus: CommunityGroupContentStatus {
        if status == "cancelled" {
            return .cancelled
        }
        if status == "draft" {
            return .draft
        }

        let now = Date()

        if now > endsAt {
            return .completed
        }

        if now >= startsAt {
            return .live
        }

        return .upcoming
    }

    var prefersLowerLeaderboardScore: Bool {
        metric == .fastestTime
    }
}

import Foundation
@preconcurrency import MapKit
import Supabase
import SwiftUI
import PhotosUI
import UIKit

enum CommunityEventActivity: String, CaseIterable, Codable, Hashable, Identifiable {
    case running
    case walking
    case strength
    case cycling
    case hike
    case groupWorkout = "group_workout"
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .running:
            return ATHLTHLocalization.choose(
                english: "Running",
                norwegian: "Løping"
            )
        case .walking:
            return ATHLTHLocalization.choose(
                english: "Walking",
                norwegian: "Gåtur"
            )
        case .strength:
            return ATHLTHLocalization.choose(
                english: "Strength",
                norwegian: "Styrke"
            )
        case .cycling:
            return ATHLTHLocalization.choose(
                english: "Cycling",
                norwegian: "Sykling"
            )
        case .hike:
            return ATHLTHLocalization.choose(
                english: "Hike",
                norwegian: "Tur"
            )
        case .groupWorkout:
            return ATHLTHLocalization.choose(
                english: "Group workout",
                norwegian: "Gruppeøkt"
            )
        case .other:
            return ATHLTHLocalization.choose(
                english: "Other",
                norwegian: "Annet"
            )
        }
    }

    var systemImage: String {
        switch self {
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .strength: return "dumbbell.fill"
        case .cycling: return "bicycle"
        case .hike: return "mountain.2.fill"
        case .groupWorkout: return "person.3.fill"
        case .other: return "sparkles"
        }
    }
}

enum CommunityEventCoverPolicy {
    static let standardArtworkOptions: [String] = [
        "GoalRunning",
        "GoalWalking",
        "GoalStrength",
        "GoalEndurance",
        "GoalMountain",
        "GoalEvent",
        "GoalAdventure",
        "GoalConsistency",
        "GoalProgress",
        "GoalRecovery",
        "GoalRelax"
    ]

    /// Some semantic goal artwork names intentionally share an existing
    /// full-resolution runtime image. Keep the semantic name in persisted
    /// event data, but always resolve it to an image set that actually has
    /// pixels before rendering. This prevents white/empty cover cells.
    static func displayArtworkName(
        _ artwork: String
    ) -> String {
        switch artwork {
        case "GoalStrength":
            return "TrainHero"
        case "GoalEndurance":
            return "StrengthPostWorkoutHero"
        case "GoalConsistency":
            return "ProgressHero"
        case "GoalEvent":
            return "CommunityHero"
        default:
            return artwork
        }
    }

    /// Every standard goal has a dedicated cropped picker thumbnail,
    /// including the semantic covers that share a full-resolution image.
    static func thumbnailArtworkName(
        _ artwork: String
    ) -> String {
        "\(artwork)Thumbnail"
    }

    static func defaultArtwork(
        for activity: CommunityEventActivity
    ) -> String {
        switch activity {
        case .running:
            return "GoalRunning"
        case .walking:
            return "GoalWalking"
        case .strength:
            return "GoalStrength"
        case .cycling:
            return "GoalAdventure"
        case .hike:
            return "GoalMountain"
        case .groupWorkout:
            return "GoalConsistency"
        case .other:
            return "GoalEvent"
        }
    }
}

struct CommunityEventRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let creatorID: UUID
    let title: String
    let summary: String
    let activityType: CommunityEventActivity
    let visibility: String
    let status: String
    let startsAt: Date
    let endsAt: Date?
    let meetingName: String
    let meetingDetails: String?
    let latitude: Double?
    let longitude: Double?
    let maxParticipants: Int?
    let paceLabel: String?
    let routeID: UUID?
    let routeTitle: String?
    let coverArtworkName: String?
    let coverImageURL: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case creatorID = "creator_id"
        case title
        case summary
        case activityType = "activity_type"
        case visibility
        case status
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case meetingName = "meeting_name"
        case meetingDetails = "meeting_details"
        case latitude
        case longitude
        case maxParticipants = "max_participants"
        case paceLabel = "pace_label"
        case routeID = "route_id"
        case routeTitle = "route_title"
        case coverArtworkName = "cover_artwork_name"
        case coverImageURL = "cover_image_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum CommunityEventAttendance: String, Codable, Hashable {
    case going
    case maybe
}

struct CommunityEventParticipantRecord: Codable, Hashable {
    let eventID: UUID
    let userID: UUID
    let joinedAt: Date
    let attendanceStatus: CommunityEventAttendance

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case userID = "user_id"
        case joinedAt = "joined_at"
        case attendanceStatus = "attendance_status"
    }
}

struct CommunityEventItem: Identifiable, Hashable {
    var id: UUID { event.id }

    let event: CommunityEventRecord
    let creator: SocialProfileCard?
    let participantRows: [CommunityEventParticipantRecord]
    let participantProfiles: [SocialProfileCard]

    var participantCount: Int {
        1 + participantRows.filter {
            $0.attendanceStatus == .going
        }.count
    }
}

struct CommunityEventDraft {
    var title = ""
    var summary = ""
    var activityType: CommunityEventActivity = .running
    var visibility: ProfileVisibility = .publicProfile
    var startsAt = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    var meetingName = ""
    var meetingDetails = ""
    var latitude: Double? = nil
    var longitude: Double? = nil
    var maxParticipants: Int? = nil
    var paceLabel = ""
    var routeID: UUID? = nil
    var routeTitle: String? = nil
    var coverArtworkName: String? = nil
    var coverImageURL: String? = nil

    func isValidForCreation(
        now: Date = Date()
    ) -> Bool {
        !title
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .isEmpty &&
        startsAt > now
    }
}

private struct CommunityEventWrite: Encodable {
    let id: UUID
    let creatorID: UUID
    let title: String
    let summary: String
    let activityType: String
    let visibility: String
    let status: String
    let startsAt: Date
    let meetingName: String
    let meetingDetails: String?
    let latitude: Double?
    let longitude: Double?
    let maxParticipants: Int?
    let paceLabel: String?
    let routeID: UUID?
    let routeTitle: String?
    let coverArtworkName: String?
    let coverImageURL: String?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case creatorID = "creator_id"
        case title
        case summary
        case activityType = "activity_type"
        case visibility
        case status
        case startsAt = "starts_at"
        case meetingName = "meeting_name"
        case meetingDetails = "meeting_details"
        case latitude
        case longitude
        case maxParticipants = "max_participants"
        case paceLabel = "pace_label"
        case routeID = "route_id"
        case routeTitle = "route_title"
        case coverArtworkName = "cover_artwork_name"
        case coverImageURL = "cover_image_url"
        case updatedAt = "updated_at"
    }
}

private struct CommunityParticipantWrite: Encodable {
    let eventID: UUID
    let userID: UUID
    let attendanceStatus: String

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case userID = "user_id"
        case attendanceStatus = "attendance_status"
    }
}

private struct CommunityResolvedCoordinate: Sendable {
    let latitude: Double
    let longitude: Double
}

@MainActor
final class SupabaseCommunityService {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseEnvironment.client) {
        self.client = client
    }

    var currentUserID: UUID? {
        client.auth.currentUser?.id
    }

    func loadEvents() async throws -> [CommunityEventItem] {
        let events: [CommunityEventRecord] = try await client
            .from("community_events")
            .select()
            .order("starts_at", ascending: true)
            .execute()
            .value

        let participants: [CommunityEventParticipantRecord] = try await client
            .from("community_event_participants")
            .select()
            .execute()
            .value

        let profiles: [SocialProfileCard] = try await client
            .from("social_profile_cards")
            .select()
            .execute()
            .value

        let profilesByID = Dictionary(
            uniqueKeysWithValues: profiles.map { ($0.userID, $0) }
        )

        return events.map { event in
            let eventParticipants = participants.filter {
                $0.eventID == event.id
            }
            return CommunityEventItem(
                event: event,
                creator: profilesByID[event.creatorID],
                participantRows: eventParticipants,
                participantProfiles: eventParticipants.compactMap {
                    profilesByID[$0.userID]
                }
            )
        }
    }

    func searchEvents(
        _ query: String,
        limit: Int = 20
    ) async throws -> [CommunityEventItem] {
        let clean = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard clean.count >= 2 else { return [] }

        let boundedLimit = min(max(limit, 8), 32)
        let pattern = "%\(clean)%"

        async let titleRows: [CommunityEventRecord] = client
            .from("community_events")
            .select()
            .ilike("title", pattern: pattern)
            .limit(boundedLimit)
            .execute()
            .value

        async let meetingRows: [CommunityEventRecord] = client
            .from("community_events")
            .select()
            .ilike("meeting_name", pattern: pattern)
            .limit(boundedLimit)
            .execute()
            .value

        async let summaryRows: [CommunityEventRecord] = client
            .from("community_events")
            .select()
            .ilike("summary", pattern: pattern)
            .limit(boundedLimit)
            .execute()
            .value

        async let routeRows: [CommunityEventRecord] = client
            .from("community_events")
            .select()
            .ilike("route_title", pattern: pattern)
            .limit(boundedLimit)
            .execute()
            .value

        async let detailRows: [CommunityEventRecord] = client
            .from("community_events")
            .select()
            .ilike("meeting_details", pattern: pattern)
            .limit(boundedLimit)
            .execute()
            .value

        let (
            titles,
            meetings,
            summaries,
            routes,
            details
        ) = try await (
            titleRows,
            meetingRows,
            summaryRows,
            routeRows,
            detailRows
        )

        var seen = Set<UUID>()
        let matchedEvents = (
            titles +
            meetings +
            summaries +
            routes +
            details
        )
            .filter { seen.insert($0.id).inserted }
            .sorted { lhs, rhs in
                let lhsUpcoming =
                    lhs.status == "upcoming" &&
                    lhs.startsAt >= Date()
                let rhsUpcoming =
                    rhs.status == "upcoming" &&
                    rhs.startsAt >= Date()

                if lhsUpcoming != rhsUpcoming {
                    return lhsUpcoming
                }

                return lhs.startsAt < rhs.startsAt
            }
            .prefix(boundedLimit)
            .map { $0 }

        guard !matchedEvents.isEmpty else { return [] }

        let eventIDs = matchedEvents.map { $0.id.uuidString }

        let participants: [CommunityEventParticipantRecord] = try await client
            .from("community_event_participants")
            .select()
            .in("event_id", values: eventIDs)
            .execute()
            .value

        var profileIDs = Set(matchedEvents.map(\.creatorID))
        profileIDs.formUnion(participants.map(\.userID))

        let profiles: [SocialProfileCard]
        if profileIDs.isEmpty {
            profiles = []
        } else {
            profiles = try await client
                .from("social_profile_cards")
                .select()
                .in(
                    "user_id",
                    values: profileIDs.map(\.uuidString)
                )
                .execute()
                .value
        }

        let profilesByID = Dictionary(
            uniqueKeysWithValues: profiles.map {
                ($0.userID, $0)
            }
        )

        return matchedEvents.map { event in
            let eventParticipants = participants.filter {
                $0.eventID == event.id
            }

            return CommunityEventItem(
                event: event,
                creator: profilesByID[event.creatorID],
                participantRows: eventParticipants,
                participantProfiles: eventParticipants.compactMap {
                    profilesByID[$0.userID]
                }
            )
        }
    }

    func createEvent(
        _ draft: CommunityEventDraft,
        eventID: UUID = UUID()
    ) async throws -> UUID {
        guard let currentUserID else {
            throw CommunityEventError.notAuthenticated
        }

        let cleanTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanMeeting = draft.meetingName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanTitle.isEmpty else {
            throw CommunityEventError.invalidEvent
        }

        let resolvedCoordinate: CLLocationCoordinate2D?
        if let latitude = draft.latitude,
           let longitude = draft.longitude {
            resolvedCoordinate = CLLocationCoordinate2D(
                latitude: latitude,
                longitude: longitude
            )
        } else if !cleanMeeting.isEmpty {
            resolvedCoordinate =
                await resolveMeetingCoordinate(
                    cleanMeeting
                )
        } else {
            resolvedCoordinate = nil
        }

        try await client
            .from("community_events")
            .insert(
                CommunityEventWrite(
                    id: eventID,
                    creatorID: currentUserID,
                    title: cleanTitle,
                    summary: draft.summary.trimmingCharacters(in: .whitespacesAndNewlines),
                    activityType: draft.activityType.rawValue,
                    visibility: draft.visibility.rawValue,
                    status: "upcoming",
                    startsAt: draft.startsAt,
                    meetingName: cleanMeeting,
                    meetingDetails: draft.meetingDetails.nilIfBlank,
                    latitude: resolvedCoordinate?.latitude,
                    longitude: resolvedCoordinate?.longitude,
                    maxParticipants: draft.maxParticipants,
                    paceLabel: draft.paceLabel.nilIfBlank,
                    routeID: draft.routeID,
                    routeTitle: draft.routeTitle,
                    coverArtworkName:
                        draft.coverArtworkName,
                    coverImageURL:
                        draft.coverImageURL,
                    updatedAt: Date()
                )
            )
            .execute()

        return eventID
    }

    func uploadEventCover(
        eventID: UUID,
        jpegData: Data
    ) async throws -> String {
        guard let userID = currentUserID else {
            throw CommunityEventError
                .notAuthenticated
        }

        guard !jpegData.isEmpty,
              jpegData.count <=
                10_485_760
        else {
            throw CommunityEventError
                .invalidEvent
        }

        let storagePath =
            "\(userID.uuidString.lowercased())/" +
            "event-covers/" +
            "\(eventID.uuidString.lowercased()).jpg"

        try await client.storage
            .from("workout-media")
            .upload(
                storagePath,
                data: jpegData,
                options: FileOptions(
                    cacheControl: "60",
                    contentType: "image/jpeg",
                    upsert: true
                )
            )

        let publicURL =
            try client.storage
                .from("workout-media")
                .getPublicURL(
                    path: storagePath
                )

        var components =
            URLComponents(
                url: publicURL,
                resolvingAgainstBaseURL:
                    false
            )
        components?.queryItems = [
            URLQueryItem(
                name: "v",
                value:
                    String(
                        Int(
                            Date()
                                .timeIntervalSince1970
                        )
                    )
            )
        ]

        return (
            components?.url ??
            publicURL
        ).absoluteString
    }

    func removeEventCover(
        eventID: UUID
    ) async throws {
        guard let userID = currentUserID else {
            throw CommunityEventError
                .notAuthenticated
        }

        let storagePath =
            "\(userID.uuidString.lowercased())/" +
            "event-covers/" +
            "\(eventID.uuidString.lowercased()).jpg"

        try await client.storage
            .from("workout-media")
            .remove(
                paths: [storagePath]
            )
    }

    private func resolveMeetingCoordinate(
        _ query: String
    ) async -> CLLocationCoordinate2D? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [
            .address,
            .pointOfInterest
        ]

        let resolved:
            CommunityResolvedCoordinate? =
                await withCheckedContinuation {
                    (
                        continuation:
                            CheckedContinuation<
                                CommunityResolvedCoordinate?,
                                Never
                            >
                    ) in

                    MKLocalSearch(request: request)
                        .start { response, _ in
                            guard let coordinate =
                                    response?
                                        .mapItems
                                        .first?
                                        .placemark
                                        .coordinate
                            else {
                                continuation.resume(
                                    returning: nil
                                )
                                return
                            }

                            continuation.resume(
                                returning:
                                    CommunityResolvedCoordinate(
                                        latitude:
                                            coordinate.latitude,
                                        longitude:
                                            coordinate.longitude
                                    )
                            )
                        }
                }

        guard let resolved else {
            return nil
        }

        return CLLocationCoordinate2D(
            latitude: resolved.latitude,
            longitude: resolved.longitude
        )
    }

    func setAttendance(
        eventID: UUID,
        status: CommunityEventAttendance
    ) async throws {
        guard let currentUserID else {
            throw CommunityEventError.notAuthenticated
        }

        try await client
            .from("community_event_participants")
            .upsert(
                CommunityParticipantWrite(
                    eventID: eventID,
                    userID: currentUserID,
                    attendanceStatus: status.rawValue
                )
            )
            .execute()
    }

    func join(eventID: UUID) async throws {
        try await setAttendance(
            eventID: eventID,
            status: .going
        )
    }

    func maybe(eventID: UUID) async throws {
        try await setAttendance(
            eventID: eventID,
            status: .maybe
        )
    }

    func leave(eventID: UUID) async throws {
        guard let currentUserID else {
            throw CommunityEventError.notAuthenticated
        }

        try await client
            .from("community_event_participants")
            .delete()
            .eq("event_id", value: eventID)
            .eq("user_id", value: currentUserID)
            .execute()
    }

    func cancel(eventID: UUID) async throws {
        try await client
            .from("community_events")
            .update([
                "status": "cancelled",
                "updated_at": ISO8601DateFormatter().string(from: Date())
            ])
            .eq("id", value: eventID)
            .execute()
    }
}

enum CommunityEventError: LocalizedError {
    case notAuthenticated
    case invalidEvent
    case eventFull

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Sign in to use Community events."
        case .invalidEvent:
            return "Add an event name and choose a future start time."
        case .eventFull:
            return "This event is full."
        }
    }
}

@MainActor
final class CommunityEventStore: ObservableObject {
    @Published private(set) var events: [CommunityEventItem] = []
    @Published private(set) var searchResults: [CommunityEventItem] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let service: SupabaseCommunityService
    private var lastRefreshAt: Date?

    init(service: SupabaseCommunityService = SupabaseCommunityService()) {
        self.service = service
    }

    var currentUserID: UUID? {
        service.currentUserID
    }

    var upcomingEvents: [CommunityEventItem] {
        events
            .filter {
                $0.event.status == "upcoming" &&
                $0.event.startsAt >= Date()
            }
            .sorted { $0.event.startsAt < $1.event.startsAt }
    }

    func refresh(force: Bool = false) async {
        guard currentUserID != nil else {
            events = []
            return
        }

        if !force,
           let lastRefreshAt,
           Date().timeIntervalSince(lastRefreshAt) < 120 {
            return
        }

        guard !isLoading else {
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let loadedEvents = try await service.loadEvents()

            guard !Task.isCancelled else {
                return
            }

            if events != loadedEvents {
                events = loadedEvents
            }
            lastRefreshAt = Date()
            errorMessage = nil
        } catch is CancellationError {
            // SwiftUI can legitimately cancel .task work when the view
            // refreshes, disappears or another refresh supersedes it.
            // This is not a user-facing Community error.
            return
        } catch {
            guard !Task.isCancelled else {
                return
            }

            errorMessage = error.localizedDescription
        }
    }

    func search(_ query: String) async {
        let requestedQuery = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard requestedQuery.count >= 2,
              currentUserID != nil
        else {
            searchResults = []
            return
        }

        do {
            let results = try await service.searchEvents(requestedQuery)
            guard !Task.isCancelled else { return }

            searchResults = results
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            searchResults = []
        }
    }

    func clearSearch() {
        searchResults = []
    }

    func create(_ draft: CommunityEventDraft) async -> Bool {
        do {
            _ = try await service
                .createEvent(draft)
            await refresh(force: true)
            return true
        } catch {
            errorMessage =
                error.localizedDescription
            return false
        }
    }

    func createAndReturnID(
        _ draft: CommunityEventDraft,
        eventID: UUID = UUID()
    ) async -> UUID? {
        do {
            let createdEventID =
                try await service
                    .createEvent(
                        draft,
                        eventID:
                            eventID
                    )
            await refresh(force: true)
            return createdEventID
        } catch {
            errorMessage =
                error.localizedDescription
            return nil
        }
    }

    func uploadEventCover(
        eventID: UUID,
        jpegData: Data
    ) async -> String? {
        do {
            return try await service
                .uploadEventCover(
                    eventID: eventID,
                    jpegData: jpegData
                )
        } catch {
            errorMessage =
                error.localizedDescription
            return nil
        }
    }

    func removeEventCover(
        eventID: UUID
    ) async {
        do {
            try await service
                .removeEventCover(
                    eventID: eventID
                )
        } catch {
            // Best-effort cleanup only.
        }
    }

    func join(_ item: CommunityEventItem) async {
        if let maximum = item.event.maxParticipants,
           item.participantCount >= maximum {
            errorMessage = CommunityEventError.eventFull.localizedDescription
            return
        }

        do {
            try await service.join(eventID: item.id)
            await refresh(force: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func maybe(_ item: CommunityEventItem) async {
        do {
            try await service.maybe(eventID: item.id)
            await refresh(force: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func leave(_ item: CommunityEventItem) async {
        do {
            try await service.leave(eventID: item.id)
            await refresh(force: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancel(_ item: CommunityEventItem) async {
        do {
            try await service.cancel(eventID: item.id)
            await refresh(force: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func item(id: UUID) -> CommunityEventItem? {
        events.first { $0.id == id } ??
            searchResults.first { $0.id == id }
    }

    func attendance(
        for item: CommunityEventItem
    ) -> CommunityEventAttendance? {
        guard let currentUserID else { return nil }

        return item.participantRows.first {
            $0.userID == currentUserID
        }?.attendanceStatus
    }

    func isJoined(_ item: CommunityEventItem) -> Bool {
        attendance(for: item) == .going
    }

    func isMaybe(_ item: CommunityEventItem) -> Bool {
        attendance(for: item) == .maybe
    }
}

private struct CommunityAvatar: View {
    let profile: SocialProfileCard
    let size: CGFloat

    var body: some View {
        Group {
            if let rawURL = profile.avatarURL,
               let url = URL(string: rawURL) {
                ATHLTHStorageImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        }
    }

    private var placeholder: some View {
        Circle()
            .fill(ATHLTHTheme.accentSoft)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.38))
                    .foregroundStyle(ATHLTHTheme.accent)
            }
    }
}

struct CommunityEventsView: View {
    @EnvironmentObject private var community: CommunityEventStore
    @State private var showingCreateEvent = false

    private var upcoming: [CommunityEventItem] {
        community.upcomingEvents
    }

    private var history: [CommunityEventItem] {
        community.events
            .filter {
                $0.event.status != "upcoming" ||
                $0.event.startsAt < Date()
            }
            .sorted {
                $0.event.startsAt > $1.event.startsAt
            }
    }

    var body: some View {
        List {
            if community.isLoading &&
                community.events.isEmpty {
                HStack {
                    Spacer()
                    ProgressView("Loading events…")
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if community.events.isEmpty {
                ContentUnavailableView {
                    Label(
                        "No events yet",
                        systemImage: "calendar.badge.plus"
                    )
                } description: {
                    Text(
                        "Create a public or friends-only run, walk or group workout."
                    )
                } actions: {
                    Button("Create Event") {
                        showingCreateEvent = true
                    }
                }
                .listRowBackground(Color.clear)
            } else {
                if !upcoming.isEmpty {
                    Section("Upcoming") {
                        ForEach(upcoming) { item in
                            NavigationLink {
                                CommunityEventDetailView(
                                    eventID: item.id
                                )
                            } label: {
                                CommunityEventListRow(
                                    item: item
                                )
                            }
                        }
                    }
                }

                if !history.isEmpty {
                    Section("History") {
                        ForEach(history) { item in
                            NavigationLink {
                                CommunityEventDetailView(
                                    eventID: item.id
                                )
                            } label: {
                                CommunityEventListRow(
                                    item: item
                                )
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Events")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCreateEvent = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create Event")
            }
        }
        .refreshable {
            await community.refresh()
        }
        .task {
            if community.events.isEmpty {
                await community.refresh()
            }
        }
        .sheet(isPresented: $showingCreateEvent) {
            CommunityEventCreateView()
                .environmentObject(community)
        }
    }
}

private struct CommunityEventListRow: View {
    let item: CommunityEventItem

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(
                    item.event.startsAt
                        .formatted(
                            .dateTime.month(.abbreviated)
                        )
                        .uppercased()
                )
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(ATHLTHTheme.accent)

                Text(
                    item.event.startsAt
                        .formatted(.dateTime.day())
                )
                .font(.title3.weight(.bold))
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )
            }
            .frame(width: 44, height: 52)
            .background(
                ATHLTHTheme.accentSoft,
                in: RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(
                        systemName:
                            item.event.activityType.systemImage
                    )
                    .foregroundStyle(ATHLTHTheme.accent)

                    Text(item.event.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )
                        .lineLimit(1)
                }

                Text(
                    [
                        item.event.startsAt
                            .formatted(
                                date: .omitted,
                                time: .shortened
                            ),
                        item.event.meetingName
                            .nilIfBlank
                    ]
                    .compactMap { $0 }
                    .joined(separator: " · ")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                Label(
                    ATHLTHLocalization.format(
                            english: "%d joined",
                            norwegian: "%d deltar",
                            item.participantCount
                        ),
                    systemImage: "person.2.fill"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct CommunityEventDetailView: View {
    @EnvironmentObject private var community: CommunityEventStore
    @EnvironmentObject private var session: AppSessionStore

    let eventID: UUID

    var body: some View {
        ScrollView {
            if let item = community.item(id: eventID) {
                VStack(alignment: .leading, spacing: 16) {
                    eventHero(item)
                    eventDetails(item)
                    participants(item)
                }
                .padding()
            } else {
                ContentUnavailableView(
                    "Event unavailable",
                    systemImage: "calendar.badge.exclamationmark"
                )
                .padding(.top, 70)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Event")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func eventHero(_ item: CommunityEventItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            eventCover(item)
                .frame(height: 178)
                .frame(maxWidth: .infinity)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 18,
                        style: .continuous
                    )
                )

            Label(
                item.event.activityType.title.uppercased(),
                systemImage: item.event.activityType.systemImage
            )
            .font(.caption2.weight(.bold))
            .tracking(1.1)
            .foregroundStyle(ATHLTHTheme.accent)

            Text(item.event.title)
                .font(.largeTitle.weight(.bold))

            if !item.event.summary.isEmpty {
                Text(item.event.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label(
                    item.event.startsAt.formatted(date: .abbreviated, time: .shortened),
                    systemImage: "calendar"
                )

                Spacer()

                Label(
                    ATHLTHLocalization.format(
                            english: "%d joined",
                            norwegian: "%d deltar",
                            item.participantCount
                        ),
                    systemImage: "person.2.fill"
                )
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            actionButton(item)
        }
        .padding(18)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }

    @ViewBuilder
    private func eventCover(
        _ item: CommunityEventItem
    ) -> some View {
        if let rawURL =
                item.event.coverImageURL,
           let url =
                URL(string: rawURL) {
            ATHLTHStorageImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()

                default:
                    Image(
                        CommunityEventCoverPolicy
                            .displayArtworkName(
                                item.event
                                    .coverArtworkName ??
                                CommunityEventCoverPolicy
                                    .defaultArtwork(
                                        for:
                                            item.event
                                                .activityType
                                    )
                            )
                    )
                    .resizable()
                    .scaledToFill()
                    .clipped()
                }
            }
        } else {
            Image(
                CommunityEventCoverPolicy
                    .displayArtworkName(
                        item.event
                            .coverArtworkName ??
                        CommunityEventCoverPolicy
                            .defaultArtwork(
                                for:
                                    item.event
                                        .activityType
                            )
                    )
            )
            .resizable()
            .scaledToFill()
            .clipped()
        }
    }

    @ViewBuilder
    private func actionButton(_ item: CommunityEventItem) -> some View {
        if item.event.creatorID == session.profile.userID {
            Button(role: .destructive) {
                Task { await community.cancel(item) }
            } label: {
                Label("Cancel Event", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        } else {
            HStack(spacing: 10) {
                if community.isJoined(item) {
                    Button {
                        Task {
                            await community.leave(item)
                        }
                    } label: {
                        Label(
                            "Deltar",
                            systemImage:
                                "checkmark.circle.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(ATHLTHTheme.accent)
                } else {
                    Button {
                        Task {
                            await community.join(item)
                        }
                    } label: {
                        Label(
                            "Delta",
                            systemImage:
                                "person.badge.plus"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accent)
                    .disabled(
                        item.event.maxParticipants.map {
                            item.participantCount >= $0
                        } ?? false
                    )
                }

                Button {
                    Task {
                        if community.isMaybe(item) {
                            await community.leave(item)
                        } else {
                            await community.maybe(item)
                        }
                    }
                } label: {
                    Label(
                        community.isMaybe(item)
                            ? "Kanskje"
                            : "Kanskje",
                        systemImage:
                            community.isMaybe(item)
                                ? "questionmark.circle.fill"
                                : "questionmark.circle"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 4)
        }
    }

    private func eventDetails(_ item: CommunityEventItem) -> some View {
        ATHLTHCard {
            Text("Details")
                .font(.headline)

            if let meeting =
                    item.event.meetingName
                        .nilIfBlank {
                eventDetailRow(
                    "Meeting point",
                    value: meeting,
                    icon:
                        "mappin.and.ellipse"
                )
            } else {
                eventDetailRow(
                    ATHLTHLocalization.choose(
                        english: "Meeting point",
                        norwegian: "Møtested"
                    ),
                    value:
                        ATHLTHLocalization.choose(
                            english:
                                "No meeting point",
                            norwegian:
                                "Ingen oppmøteplass"
                        ),
                    icon:
                        "video.fill"
                )
            }

            if let details = item.event.meetingDetails, !details.isEmpty {
                eventDetailRow(
                    "Where to meet",
                    value: details,
                    icon: "text.bubble"
                )
            }

            if let pace = item.event.paceLabel, !pace.isEmpty {
                eventDetailRow(
                    "Pace / level",
                    value: pace,
                    icon: "speedometer"
                )
            }

            if let route = item.event.routeTitle, !route.isEmpty {
                eventDetailRow(
                    "Route",
                    value: route,
                    icon: "point.topleft.down.to.point.bottomright.curvepath"
                )
            }

            eventDetailRow(
                "Visibility",
                value: item.event.visibility.capitalized,
                icon: item.event.visibility == "public"
                    ? "globe"
                    : "person.2.fill"
            )

            if let max = item.event.maxParticipants {
                eventDetailRow(
                    "Capacity",
                    value: "\(item.participantCount) / \(max)",
                    icon: "person.3.fill"
                )
            }
        }
    }

    private func participants(_ item: CommunityEventItem) -> some View {
        ATHLTHCard {
            Text("People")
                .font(.headline)

            HStack(spacing: 10) {
                if let creator = item.creator {
                    CommunityAvatar(profile: creator, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(creator.resolvedName)
                            .font(.subheadline.weight(.semibold))
                        Text("Host")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Label("Event host", systemImage: "person.crop.circle")
                        .font(.subheadline)
                }

                Spacer()
            }
            .padding(.top, 8)

            ForEach(item.participantProfiles) { profile in
                Divider()
                HStack(spacing: 10) {
                    CommunityAvatar(profile: profile, size: 36)
                    Text(profile.resolvedName)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                }
            }
        }
    }

    private func eventDetailRow(
        _ title: String,
        value: String,
        icon: String
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(ATHLTHTheme.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.medium))
            }

            Spacer()
        }
        .padding(.top, 10)
    }
}

struct CommunityEventCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var community: CommunityEventStore
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var social: SocialStore

    @State private var draft = CommunityEventDraft()
    @State private var limitParticipants = false
    @State private var maxParticipants = 20
    @State private var selectedRouteID: UUID?
    @State private var shareToCommunity = true
    @State private var isCreating = false
    @State private var selectedCoverArtworkName =
        CommunityEventCoverPolicy
            .defaultArtwork(
                for: .running
            )
    @State private var selectedCoverPhoto:
        PhotosPickerItem?
    @State private var selectedCoverImageData:
        Data?
    @State private var coverWasManuallySelected =
        false
    @State private var createError: String?

    private var canCreate: Bool {
        draft.isValidForCreation() &&
        !isCreating
    }

    private var selectedRoute: TrainingRoute? {
        guard let selectedRouteID else {
            return nil
        }

        return session.savedRoutes.first {
            $0.id == selectedRouteID
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ATHLTHPremiumCanvas(
                    accent:
                        ATHLTHTheme.vitality
                            .opacity(0.20)
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        eventHero
                        eventCoverPicker

                        if let createError {
                            Text(createError)
                                .font(.caption)
                                .foregroundStyle(
                                    .red
                                )
                                .frame(
                                    maxWidth:
                                        .infinity,
                                    alignment:
                                        .leading
                                )
                                .padding(
                                    .horizontal,
                                    4
                                )
                        }

                        eventSection(
                            title:
                                ATHLTHLocalization.choose(
                                    english: "Event",
                                    norwegian: "Arrangement"
                                ),
                            icon:
                                "calendar.badge.plus"
                        ) {
                            eventTextField(
                                title:
                                    ATHLTHLocalization.choose(
                                        english: "Event name",
                                        norwegian: "Navn på arrangement"
                                    ),
                                placeholder:
                                    ATHLTHLocalization.choose(
                                        english: "Add a name",
                                        norwegian: "Gi arrangementet et navn"
                                    ),
                                text: $draft.title,
                                icon: "doc.text"
                            )

                            eventDivider

                            Menu {
                                ForEach(
                                    CommunityEventActivity.allCases
                                ) { activity in
                                    Button {
                                        draft.activityType =
                                            activity

                                        if activity !=
                                            .running &&
                                            activity !=
                                            .walking {
                                            draft.paceLabel =
                                                ""
                                            selectedRouteID =
                                                nil
                                        }
                                    } label: {
                                        Label(
                                            activity.title,
                                            systemImage:
                                                activity
                                                    .systemImage
                                        )
                                    }
                                }
                            } label: {
                                eventSelectionRow(
                                    title:
                                        ATHLTHLocalization.choose(
                                            english: "Activity",
                                            norwegian: "Aktivitet"
                                        ),
                                    value:
                                        draft.activityType
                                            .title,
                                    icon:
                                        draft.activityType
                                            .systemImage
                                )
                            }
                            .buttonStyle(.plain)

                            eventDivider

                            eventTextField(
                                title:
                                    ATHLTHLocalization.choose(
                                        english: "Description",
                                        norwegian: "Beskrivelse"
                                    ),
                                placeholder:
                                    ATHLTHLocalization.choose(
                                        english: "Optional",
                                        norwegian: "Valgfritt"
                                    ),
                                text: $draft.summary,
                                icon: "text.alignleft",
                                axis: .vertical
                            )

                            eventDivider

                            HStack(spacing: 10) {
                                compactDateControl(
                                    title:
                                        ATHLTHLocalization.choose(
                                            english: "Date",
                                            norwegian: "Dato"
                                        ),
                                    icon: "calendar",
                                    components: [.date]
                                )

                                compactDateControl(
                                    title:
                                        ATHLTHLocalization.choose(
                                            english: "Time",
                                            norwegian: "Tid"
                                        ),
                                    icon: "clock",
                                    components: [
                                        .hourAndMinute
                                    ]
                                )
                            }

                            eventDivider

                            Menu {
                                Button {
                                    draft.visibility =
                                        .publicProfile
                                } label: {
                                    Label(
                                        ATHLTHLocalization.choose(
                                            english: "Public",
                                            norwegian: "Offentlig"
                                        ),
                                        systemImage: "globe"
                                    )
                                }

                                Button {
                                    draft.visibility =
                                        .friends
                                } label: {
                                    Label(
                                        ATHLTHLocalization.choose(
                                            english: "Friends",
                                            norwegian: "Følgere"
                                        ),
                                        systemImage:
                                            "person.2.fill"
                                    )
                                }
                            } label: {
                                eventSelectionRow(
                                    title:
                                        ATHLTHLocalization.choose(
                                            english: "Who can see it",
                                            norwegian: "Hvem kan se det"
                                        ),
                                    value:
                                        visibilityTitle,
                                    icon:
                                        draft.visibility ==
                                            .publicProfile
                                            ? "globe"
                                            : "person.2.fill"
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        eventSection(
                            title:
                                ATHLTHLocalization.choose(
                                    english: "Meet",
                                    norwegian: "Oppmøte"
                                ),
                            icon:
                                "mappin.and.ellipse"
                        ) {
                            eventTextField(
                                title:
                                    ATHLTHLocalization.choose(
                                        english: "Meeting point",
                                        norwegian: "Møtested"
                                    ),
                                placeholder:
                                    ATHLTHLocalization.choose(
                                        english: "Optional",
                                        norwegian: "Valgfritt"
                                    ),
                                text: $draft.meetingName,
                                icon:
                                    "mappin.circle"
                            )

                            eventDivider

                            eventTextField(
                                title:
                                    ATHLTHLocalization.choose(
                                        english: "Meeting details",
                                        norwegian: "Detaljer"
                                    ),
                                placeholder:
                                    ATHLTHLocalization.choose(
                                        english: "Optional",
                                        norwegian: "Valgfritt"
                                    ),
                                text:
                                    $draft.meetingDetails,
                                icon:
                                    "text.bubble",
                                axis: .vertical
                            )

                            if draft.activityType ==
                                .running ||
                                draft.activityType ==
                                .walking {
                                eventDivider

                                eventTextField(
                                    title:
                                        ATHLTHLocalization.choose(
                                            english: "Pace / level",
                                            norwegian: "Fart / nivå"
                                        ),
                                    placeholder:
                                        ATHLTHLocalization.choose(
                                            english: "Optional",
                                            norwegian: "Valgfritt"
                                        ),
                                    text:
                                        $draft.paceLabel,
                                    icon:
                                        "speedometer"
                                )

                                eventDivider

                                HStack(spacing: 12) {
                                    Image(
                                        systemName:
                                            "point.topleft.down.to.point.bottomright.curvepath"
                                    )
                                    .font(
                                        .system(
                                            size: 17,
                                            weight:
                                                .semibold
                                        )
                                    )
                                    .foregroundStyle(
                                        ATHLTHTheme
                                            .vitality
                                    )
                                    .frame(
                                        width: 38,
                                        height: 38
                                    )
                                    .background(
                                        ATHLTHTheme
                                            .vitalitySoft,
                                        in:
                                            RoundedRectangle(
                                                cornerRadius: 12,
                                                style:
                                                    .continuous
                                            )
                                    )

                                    Text(
                                        ATHLTHLocalization.choose(
                                            english: "Route",
                                            norwegian: "Rute"
                                        )
                                    )
                                    .font(.subheadline)
                                    .foregroundStyle(
                                        ATHLTHTheme
                                            .primaryText
                                    )

                                    Spacer(
                                        minLength: 8
                                    )

                                    Menu {
                                        Button {
                                            selectedRouteID =
                                                nil
                                        } label: {
                                            Label(
                                                ATHLTHLocalization.choose(
                                                    english: "No route",
                                                    norwegian: "Ingen rute"
                                                ),
                                                systemImage:
                                                    "xmark.circle"
                                            )
                                        }

                                        ForEach(
                                            session.savedRoutes
                                        ) { route in
                                            Button {
                                                selectedRouteID =
                                                    route.id
                                            } label: {
                                                Label(
                                                    route.title,
                                                    systemImage:
                                                        "map"
                                                )
                                            }
                                        }
                                    } label: {
                                        HStack(
                                            spacing: 7
                                        ) {
                                            Text(
                                                selectedRoute?
                                                    .title ??
                                                ATHLTHLocalization.choose(
                                                    english:
                                                        "No route",
                                                    norwegian:
                                                        "Ingen rute"
                                                )
                                            )
                                            .lineLimit(1)
                                            .minimumScaleFactor(
                                                0.78
                                            )

                                            Image(
                                                systemName:
                                                    "chevron.up.chevron.down"
                                            )
                                            .font(
                                                .caption2
                                                    .bold()
                                            )
                                        }
                                        .font(
                                            .subheadline
                                                .weight(
                                                    .semibold
                                                )
                                        )
                                        .foregroundStyle(
                                            ATHLTHTheme
                                                .accentDeep
                                        )
                                        .padding(
                                            .horizontal,
                                            12
                                        )
                                        .frame(
                                            height: 40
                                        )
                                        .background(
                                            ATHLTHTheme
                                                .surfaceSage,
                                            in: Capsule()
                                        )
                                    }
                                    .buttonStyle(.plain)

                                    NavigationLink {
                                        RunRouteBuilderView()
                                    } label: {
                                        Image(
                                            systemName:
                                                "plus"
                                        )
                                        .font(
                                            .system(
                                                size: 16,
                                                weight:
                                                    .bold
                                            )
                                        )
                                        .foregroundStyle(
                                            .white
                                        )
                                        .frame(
                                            width: 40,
                                            height: 40
                                        )
                                        .background(
                                            ATHLTHTheme
                                                .vitality,
                                            in: Circle()
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(
                                        ATHLTHLocalization.choose(
                                            english:
                                                "Create new route",
                                            norwegian:
                                                "Lag ny rute"
                                        )
                                    )
                                }

                                if let selectedRoute {
                                    eventRoutePreview(
                                        selectedRoute
                                    )
                                    .padding(.top, 12)
                                }
                            }
                        }

                        eventSection(
                            title:
                                ATHLTHLocalization.choose(
                                    english: "Participants",
                                    norwegian: "Deltakere"
                                ),
                            icon: "person.2.fill"
                        ) {
                            HStack(spacing: 12) {
                                Image(
                                    systemName:
                                        "person.badge.plus"
                                )
                                .font(
                                    .system(
                                        size: 17,
                                        weight: .semibold
                                    )
                                )
                                .foregroundStyle(
                                    ATHLTHTheme.accent
                                )
                                .frame(
                                    width: 38,
                                    height: 38
                                )
                                .background(
                                    ATHLTHTheme
                                        .accentSoft,
                                    in: RoundedRectangle(
                                        cornerRadius: 12,
                                        style:
                                            .continuous
                                    )
                                )

                                Text(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Limit participants",
                                        norwegian:
                                            "Begrens deltakere"
                                    )
                                )
                                .font(
                                    .subheadline
                                        .weight(.semibold)
                                )

                                Spacer()

                                Toggle(
                                    "",
                                    isOn:
                                        $limitParticipants
                                )
                                .labelsHidden()
                                .tint(
                                    ATHLTHTheme.accent
                                )
                            }

                            if limitParticipants {
                                eventDivider

                                HStack(spacing: 14) {
                                    Text(
                                        ATHLTHLocalization.choose(
                                            english:
                                                "Maximum participants",
                                            norwegian:
                                                "Maks antall deltakere"
                                        )
                                    )
                                    .font(.subheadline)
                                    .foregroundStyle(
                                        .secondary
                                    )

                                    Spacer()

                                    Button {
                                        maxParticipants =
                                            max(
                                                2,
                                                maxParticipants -
                                                1
                                            )
                                    } label: {
                                        Image(
                                            systemName:
                                                "minus"
                                        )
                                        .frame(
                                            width: 34,
                                            height: 34
                                        )
                                        .background(
                                            Color.primary
                                                .opacity(
                                                    0.045
                                                ),
                                            in: Circle()
                                        )
                                    }
                                    .buttonStyle(.plain)

                                    Text(
                                        "\(maxParticipants)"
                                    )
                                    .font(
                                        .headline
                                            .monospacedDigit()
                                    )
                                    .frame(
                                        minWidth: 32
                                    )

                                    Button {
                                        maxParticipants =
                                            min(
                                                500,
                                                maxParticipants +
                                                1
                                            )
                                    } label: {
                                        Image(
                                            systemName:
                                                "plus"
                                        )
                                        .frame(
                                            width: 34,
                                            height: 34
                                        )
                                        .background(
                                            Color.primary
                                                .opacity(
                                                    0.045
                                                ),
                                            in: Circle()
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        eventSection(
                            title:
                                ATHLTHLocalization.choose(
                                    english: "Community",
                                    norwegian: "Fellesskap"
                                ),
                            icon: "person.3.fill"
                        ) {
                            HStack(spacing: 12) {
                                Image(
                                    systemName:
                                        "megaphone.fill"
                                )
                                .font(
                                    .system(
                                        size: 17,
                                        weight: .semibold
                                    )
                                )
                                .foregroundStyle(
                                    ATHLTHTheme.accent
                                )
                                .frame(
                                    width: 38,
                                    height: 38
                                )
                                .background(
                                    ATHLTHTheme
                                        .accentSoft,
                                    in: RoundedRectangle(
                                        cornerRadius: 12,
                                        style:
                                            .continuous
                                    )
                                )

                                VStack(
                                    alignment: .leading,
                                    spacing: 3
                                ) {
                                    Text(
                                        ATHLTHLocalization.choose(
                                            english:
                                                "Share to Community activity",
                                            norwegian:
                                                "Del til Community-aktivitet"
                                        )
                                    )
                                    .font(
                                        .subheadline
                                            .weight(
                                                .semibold
                                            )
                                    )

                                    Text(
                                        ATHLTHLocalization.choose(
                                            english:
                                                "People who can see the event can also discover it in Community.",
                                            norwegian:
                                                "Arrangementet kan vises i Community for dem som har tilgang."
                                        )
                                    )
                                    .font(.caption)
                                    .foregroundStyle(
                                        .secondary
                                    )
                                    .fixedSize(
                                        horizontal:
                                            false,
                                        vertical: true
                                    )
                                }

                                Spacer(
                                    minLength: 8
                                )

                                Toggle(
                                    "",
                                    isOn:
                                        $shareToCommunity
                                )
                                .labelsHidden()
                                .tint(
                                    ATHLTHTheme.accent
                                )
                            }

                            eventDivider

                            Label(
                                privacyMessage,
                                systemImage:
                                    draft.visibility ==
                                        .publicProfile
                                        ? "globe"
                                        : "lock.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(
                                horizontal: false,
                                vertical: true
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 28)
                }
                .scrollDismissesKeyboard(
                    .interactively
                )
            }
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english: "Create Event",
                    norwegian: "Opprett arrangement"
                )
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
            .toolbarBackground(
                .hidden,
                for: .navigationBar
            )
            .toolbar {
                ToolbarItem(
                    placement:
                        .cancellationAction
                ) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Cancel",
                            norwegian: "Avbryt"
                        )
                    ) {
                        dismiss()
                    }
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                }

                ToolbarItem(
                    placement:
                        .confirmationAction
                ) {
                    Button {
                        createEvent()
                    } label: {
                        Text(
                            isCreating
                                ? ATHLTHLocalization.choose(
                                    english:
                                        "Creating…",
                                    norwegian:
                                        "Oppretter…"
                                )
                                : ATHLTHLocalization.choose(
                                    english:
                                        "Create",
                                    norwegian:
                                        "Opprett"
                                )
                        )
                        .font(
                            .subheadline
                                .weight(.semibold)
                        )
                    }
                    .disabled(!canCreate)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider()
                        .opacity(0.35)

                    Button {
                        createEvent()
                    } label: {
                        HStack(spacing: 8) {
                            if isCreating {
                                ProgressView()
                                    .tint(.white)
                            }

                            Text(
                                isCreating
                                    ? ATHLTHLocalization.choose(
                                        english:
                                            "Creating…",
                                        norwegian:
                                            "Oppretter…"
                                    )
                                    : ATHLTHLocalization.choose(
                                        english:
                                            "Create event",
                                        norwegian:
                                            "Opprett arrangement"
                                    )
                            )
                            .font(.headline)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            ATHLTHTheme
                                .vitality,
                            in: Capsule(
                                style:
                                    .continuous
                            )
                        )
                        .opacity(
                            canCreate
                                ? 1
                                : 0.34
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canCreate)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .background(
                    .ultraThinMaterial
                )
            }
            .onChange(
                of: draft.activityType
            ) { _, activity in
                if !coverWasManuallySelected &&
                    selectedCoverImageData ==
                        nil {
                    selectedCoverArtworkName =
                        CommunityEventCoverPolicy
                            .defaultArtwork(
                                for: activity
                            )
                }
            }
            .onChange(
                of: selectedCoverPhoto
            ) { _, item in
                guard let item else {
                    return
                }

                Task {
                    guard let data =
                            try? await item
                                .loadTransferable(
                                    type: Data.self
                                ),
                          let image =
                            UIImage(data: data),
                          let jpeg =
                            image.jpegData(
                                compressionQuality:
                                    0.86
                            )
                    else {
                        await MainActor.run {
                            createError =
                                ATHLTHLocalization
                                    .choose(
                                        english:
                                            "The selected image could not be read.",
                                        norwegian:
                                            "Det valgte bildet kunne ikke leses."
                                    )
                        }
                        return
                    }

                    await MainActor.run {
                        selectedCoverImageData =
                            jpeg
                        coverWasManuallySelected =
                            true
                        createError = nil
                    }
                }
            }
            .sensoryFeedback(
                .selection,
                trigger:
                    draft.activityType
            )
            .sensoryFeedback(
                .selection,
                trigger:
                    draft.visibility
            )
        }
    }

    private var eventHero: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let data =
                        selectedCoverImageData,
                   let image =
                        UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipped()
                } else {
                    Image(
                        CommunityEventCoverPolicy
                            .displayArtworkName(
                                selectedCoverArtworkName
                            )
                    )
                    .resizable()
                    .scaledToFill()
                    .clipped()
                }
            }
            .frame(height: 150)
            .frame(maxWidth: .infinity)
            .clipped()

            LinearGradient(
                colors: [
                    .clear,
                    .clear,
                    Color.black.opacity(0.38)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Label(
                eventActivityLabel,
                systemImage:
                    draft.activityType
                        .systemImage
            )
            .font(
                .caption.weight(.semibold)
            )
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                .ultraThinMaterial,
                in: Capsule()
            )
            .padding(14)
        }
        .frame(height: 150)
        .clipShape(
            RoundedRectangle(
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
                Color.white.opacity(0.35),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                Color.black.opacity(0.06),
            radius: 12,
            y: 5
        )
    }

    private var eventCoverPicker:
        some View {
        VStack(
            alignment: .leading,
            spacing: 9
        ) {
            HStack {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Cover",
                        norwegian: "Bilde"
                    ),
                    systemImage: "photo"
                )
                .font(.subheadline.weight(.semibold))

                Spacer()

                PhotosPicker(
                    selection:
                        $selectedCoverPhoto,
                    matching: .images
                ) {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Own photo",
                            norwegian: "Eget bilde"
                        ),
                        systemImage:
                            "photo.badge.plus"
                    )
                    .font(.caption.weight(.semibold))
                }
            }

            ScrollView(
                .horizontal,
                showsIndicators: false
            ) {
                HStack(spacing: 9) {
                    ForEach(
                        CommunityEventCoverPolicy
                            .standardArtworkOptions,
                        id: \.self
                    ) { artwork in
                        Button {
                            selectedCoverArtworkName =
                                artwork
                            selectedCoverImageData =
                                nil
                            selectedCoverPhoto =
                                nil
                            coverWasManuallySelected =
                                true
                            createError = nil
                        } label: {
                            Image(
                                CommunityEventCoverPolicy
                                    .thumbnailArtworkName(
                                        artwork
                                    )
                            )
                                .resizable()
                                .scaledToFill()
                                .frame(
                                    width: 82,
                                    height: 52
                                )
                                .clipped()
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius:
                                            12,
                                        style:
                                            .continuous
                                    )
                                )
                                .overlay {
                                    RoundedRectangle(
                                        cornerRadius:
                                            12,
                                        style:
                                            .continuous
                                    )
                                    .stroke(
                                        selectedCoverImageData ==
                                                nil &&
                                            selectedCoverArtworkName ==
                                                artwork
                                            ? ATHLTHTheme
                                                .accent
                                            : Color
                                                .black
                                                .opacity(
                                                    0.05
                                                ),
                                        lineWidth:
                                            selectedCoverImageData ==
                                                    nil &&
                                                selectedCoverArtworkName ==
                                                    artwork
                                                ? 2
                                                : 1
                                    )
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .background(
            ATHLTHTheme.surfaceSage,
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
                Color.white.opacity(0.72),
                lineWidth: 0.8
            )
        }
    }

    private var eventArtworkName: String {
        selectedCoverArtworkName
    }

    private var eventActivityLabel: String {
        ATHLTHLocalization.format(
            english: "%@ event",
            norwegian: "%@event",
            draft.activityType.title
        )
    }

    private var visibilityTitle: String {
        draft.visibility ==
            .publicProfile
            ? ATHLTHLocalization.choose(
                english: "Public",
                norwegian: "Offentlig"
            )
            : ATHLTHLocalization.choose(
                english: "Friends",
                norwegian: "Følgere"
            )
    }

    private var privacyMessage: String {
        draft.visibility ==
            .publicProfile
            ? ATHLTHLocalization.choose(
                english:
                    "Public events can be discovered by signed-in ATHLTH users.",
                norwegian:
                    "Offentlige arrangementer kan oppdages av innloggede ATHLTH-brukere."
            )
            : ATHLTHLocalization.choose(
                english:
                    "Followers-only events are limited to your ATHLTH network.",
                norwegian:
                    "Arrangementet er begrenset til følgernettverket ditt."
            )
    }

    private var eventDivider: some View {
        Divider()
            .opacity(0.42)
            .padding(.leading, 50)
    }

    private func eventSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content:
            () -> Content
    ) -> some View {
        ATHLTHCard {
            VStack(
                alignment: .leading,
                spacing: 14
            ) {
                HStack(spacing: 10) {
                    Image(
                        systemName: icon
                    )
                    .font(
                        .system(
                            size: 16,
                            weight:
                                .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .vitality
                    )
                    .frame(
                        width: 36,
                        height: 36
                    )
                    .background(
                        ATHLTHTheme
                            .vitalitySoft,
                        in:
                            RoundedRectangle(
                                cornerRadius: 11,
                                style:
                                    .continuous
                            )
                    )

                    Text(title)
                        .font(
                            .headline
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .primaryText
                        )

                    Spacer()
                }

                content()
            }
        }
    }

    private func eventTextField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        icon: String,
        axis: Axis = .horizontal
    ) -> some View {
        HStack(
            alignment:
                axis == .vertical
                    ? .top
                    : .center,
            spacing: 12
        ) {
            Image(systemName: icon)
                .font(
                    .system(
                        size: 17,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.vitality
                )
                .frame(width: 38, height: 38)
                .background(
                    ATHLTHTheme.vitalitySoft,
                    in: RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                )

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField(
                    placeholder,
                    text: text,
                    axis: axis
                )
                .font(.body)
                .lineLimit(
                    axis == .vertical
                        ? 2...4
                        : 1...1
                )
            }
        }
        .padding(.vertical, 2)
    }

    private func eventSelectionRow(
        title: String,
        value: String,
        icon: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(
                    .system(
                        size: 17,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.accent
                )
                .frame(width: 38, height: 38)
                .background(
                    ATHLTHTheme.accentSoft,
                    in: RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                )

            Text(title)
                .font(.subheadline)
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )

            Spacer()

            HStack(spacing: 7) {
                Text(value)
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )
                    .lineLimit(1)

                Image(
                    systemName:
                        "chevron.up.chevron.down"
                )
                .font(.caption2.bold())
            }
            .foregroundStyle(
                Color(
                    red: 0.20,
                    green: 0.26,
                    blue: 0.36
                )
            )
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(
                Color(
                    red: 0.91,
                    green: 0.94,
                    blue: 0.98
                ),
                in: Capsule()
            )
        }
    }

    private func compactDateControl(
        title: String,
        icon: String,
        components:
            DatePickerComponents
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 5
        ) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)

            DatePicker(
                "",
                selection: $draft.startsAt,
                in: Date()...,
                displayedComponents:
                    components
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            Color.primary.opacity(0.035),
            in: RoundedRectangle(
                cornerRadius: 15,
                style: .continuous
            )
        )
    }

    private func eventRoutePreview(
        _ route: TrainingRoute
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if route.coordinates.count >= 2 {
                Map(
                    initialPosition:
                        .region(
                            routeRegion(
                                route
                            )
                        )
                ) {
                    MapPolyline(
                        coordinates:
                            route.coordinates
                                .map(
                                    \.coordinate
                                )
                    )
                    .stroke(
                        Color(
                            red: 0.20,
                            green: 0.29,
                            blue: 0.52
                        ),
                        lineWidth: 5
                    )

                    if let first =
                        route.coordinates.first {
                        Marker(
                            route.startName ??
                                ATHLTHLocalization.choose(
                                    english: "Start",
                                    norwegian: "Start"
                                ),
                            coordinate:
                                first.coordinate
                        )
                        .tint(
                            ATHLTHTheme.accent
                        )
                    }

                    if let last =
                        route.coordinates.last {
                        Marker(
                            route.endName ??
                                ATHLTHLocalization.choose(
                                    english: "Finish",
                                    norwegian: "Mål"
                                ),
                            coordinate:
                                last.coordinate
                        )
                        .tint(.red)
                    }
                }
                .allowsHitTesting(false)
                .frame(height: 138)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 17,
                        style: .continuous
                    )
                )
            }

            HStack(spacing: 10) {
                Image(
                    systemName:
                        "point.topleft.down.to.point.bottomright.curvepath"
                )
                .foregroundStyle(
                    ATHLTHTheme.accent
                )

                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text(route.title)
                        .font(
                            .subheadline
                                .weight(.semibold)
                        )

                    HStack(spacing: 8) {
                        Text(
                            String(
                                format:
                                    "%.1f km",
                                route
                                    .distanceKilometers
                            )
                        )

                        if let elevation =
                            route
                                .elevationGainMeters {
                            Text(
                                "· \(Int(elevation.rounded())) m ↑"
                            )
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )
                }

                Spacer()
            }
        }
        .padding(10)
        .background(
            Color.primary.opacity(0.028),
            in: RoundedRectangle(
                cornerRadius: 19,
                style: .continuous
            )
        )
    }

    private func routeRegion(
        _ route: TrainingRoute
    ) -> MKCoordinateRegion {
        let coordinates =
            route.coordinates.map(
                \.coordinate
            )

        guard let first =
                coordinates.first
        else {
            return MKCoordinateRegion(
                center:
                    CLLocationCoordinate2D(
                        latitude: 63.43,
                        longitude: 10.39
                    ),
                span:
                    MKCoordinateSpan(
                        latitudeDelta: 0.04,
                        longitudeDelta: 0.04
                    )
            )
        }

        var minLat = first.latitude
        var maxLat = first.latitude
        var minLon = first.longitude
        var maxLon = first.longitude

        for coordinate in coordinates {
            minLat = min(
                minLat,
                coordinate.latitude
            )
            maxLat = max(
                maxLat,
                coordinate.latitude
            )
            minLon = min(
                minLon,
                coordinate.longitude
            )
            maxLon = max(
                maxLon,
                coordinate.longitude
            )
        }

        return MKCoordinateRegion(
            center:
                CLLocationCoordinate2D(
                    latitude:
                        (minLat + maxLat) /
                        2,
                    longitude:
                        (minLon + maxLon) /
                        2
                ),
            span:
                MKCoordinateSpan(
                    latitudeDelta:
                        max(
                            (maxLat - minLat) *
                            1.35,
                            0.008
                        ),
                    longitudeDelta:
                        max(
                            (maxLon - minLon) *
                            1.35,
                            0.008
                        )
                )
        )
    }

    private func createEvent() {
        guard canCreate else {
            return
        }

        Task {
            isCreating = true
            createError = nil

            draft.maxParticipants =
                limitParticipants
                    ? maxParticipants
                    : nil

            if let selectedRoute {
                draft.routeID =
                    selectedRoute.id
                draft.routeTitle =
                    selectedRoute.title
            } else {
                draft.routeID = nil
                draft.routeTitle = nil
            }

            let requestedEventID = UUID()
            var uploadedCoverURL: String?

            if let selectedCoverImageData {
                guard let imageURL =
                        await community
                            .uploadEventCover(
                                eventID:
                                    requestedEventID,
                                jpegData:
                                    selectedCoverImageData
                            )
                else {
                    createError =
                        community.errorMessage ??
                        ATHLTHLocalization.choose(
                            english:
                                "The event image could not be uploaded.",
                            norwegian:
                                "Bildet til arrangementet kunne ikke lastes opp."
                        )
                    isCreating = false
                    return
                }

                uploadedCoverURL =
                    imageURL
            }

            draft.coverArtworkName =
                selectedCoverImageData == nil
                    ? selectedCoverArtworkName
                    : nil
            draft.coverImageURL =
                uploadedCoverURL

            let eventID =
                await community
                    .createAndReturnID(
                        draft,
                        eventID:
                            requestedEventID
                    )

            guard let eventID else {
                if uploadedCoverURL != nil {
                    await community
                        .removeEventCover(
                            eventID:
                                requestedEventID
                        )
                }

                createError =
                    community.errorMessage ??
                    ATHLTHLocalization.choose(
                        english:
                            "The event could not be created.",
                        norwegian:
                            "Arrangementet kunne ikke opprettes."
                    )
                isCreating = false
                return
            }

            if shareToCommunity {
                _ = await social
                    .shareCommunityEvent(
                        id: eventID,
                        title: draft.title,
                        activityType:
                            draft.activityType,
                        startsAt:
                            draft.startsAt,
                        meetingName:
                            draft.meetingName,
                        visibility:
                            draft.visibility,
                        coverArtworkName:
                            draft.coverArtworkName,
                        coverImageURL:
                            draft.coverImageURL
                    )
            }

            isCreating = false
            dismiss()
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

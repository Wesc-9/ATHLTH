import Foundation
import MapKit
import Supabase
import SwiftUI

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
        case .running: return "Running"
        case .walking: return "Walking"
        case .strength: return "Strength"
        case .cycling: return "Cycling"
        case .hike: return "Hike"
        case .groupWorkout: return "Group workout"
        case .other: return "Other"
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
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct CommunityEventParticipantRecord: Codable, Hashable {
    let eventID: UUID
    let userID: UUID
    let joinedAt: Date

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case userID = "user_id"
        case joinedAt = "joined_at"
    }
}

struct CommunityEventItem: Identifiable, Hashable {
    var id: UUID { event.id }

    let event: CommunityEventRecord
    let creator: SocialProfileCard?
    let participantRows: [CommunityEventParticipantRecord]
    let participantProfiles: [SocialProfileCard]

    var participantCount: Int {
        1 + participantRows.count
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
}

private struct CommunityEventWrite: Encodable {
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
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
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
        case updatedAt = "updated_at"
    }
}

private struct CommunityParticipantWrite: Encodable {
    let eventID: UUID
    let userID: UUID

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case userID = "user_id"
    }
}

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

    func createEvent(_ draft: CommunityEventDraft) async throws {
        guard let currentUserID else {
            throw CommunityEventError.notAuthenticated
        }

        let cleanTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanMeeting = draft.meetingName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanTitle.isEmpty, !cleanMeeting.isEmpty else {
            throw CommunityEventError.invalidEvent
        }

        let resolvedCoordinate: CLLocationCoordinate2D?
        if let latitude = draft.latitude,
           let longitude = draft.longitude {
            resolvedCoordinate = CLLocationCoordinate2D(
                latitude: latitude,
                longitude: longitude
            )
        } else {
            resolvedCoordinate = await resolveMeetingCoordinate(cleanMeeting)
        }

        try await client
            .from("community_events")
            .insert(
                CommunityEventWrite(
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
                    updatedAt: Date()
                )
            )
            .execute()
    }

    private func resolveMeetingCoordinate(
        _ query: String
    ) async -> CLLocationCoordinate2D? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]

        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems.first?.placemark.coordinate
        } catch {
            return nil
        }
    }

    func join(eventID: UUID) async throws {
        guard let currentUserID else {
            throw CommunityEventError.notAuthenticated
        }

        try await client
            .from("community_event_participants")
            .insert(
                CommunityParticipantWrite(
                    eventID: eventID,
                    userID: currentUserID
                )
            )
            .execute()
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
            return "Add an event name and meeting point."
        case .eventFull:
            return "This event is full."
        }
    }
}

@MainActor
final class CommunityEventStore: ObservableObject {
    @Published private(set) var events: [CommunityEventItem] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let service: SupabaseCommunityService

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

    func refresh() async {
        guard currentUserID != nil else {
            events = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            events = try await service.loadEvents()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func create(_ draft: CommunityEventDraft) async -> Bool {
        do {
            try await service.createEvent(draft)
            await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
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
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func leave(_ item: CommunityEventItem) async {
        do {
            try await service.leave(eventID: item.id)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancel(_ item: CommunityEventItem) async {
        do {
            try await service.cancel(eventID: item.id)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func item(id: UUID) -> CommunityEventItem? {
        events.first { $0.id == id }
    }

    func isJoined(_ item: CommunityEventItem) -> Bool {
        guard let currentUserID else { return false }
        return item.participantRows.contains { $0.userID == currentUserID }
    }
}

struct ATHLTHCommunityView: View {
    @EnvironmentObject private var community: CommunityEventStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var challenges: ChallengeStore
    @EnvironmentObject private var session: AppSessionStore

    @State private var showingCreateEvent = false

    private var activeChallenges: [ATHLTHChallenge] {
        challenges.visibleChallenges.filter {
            $0.status == .active ||
            $0.status == .upcoming ||
            $0.status == .invited
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ATHLTHTabHero(
                        imageName: "CommunityHero",
                        title: "Community",
                        subtitle: "Train together. Go further.",
                        height: 190,
                        alignment: .leading,
                        focalOffsetX: -18,
                        focalOffsetY: 18
                    )

                    VStack(spacing: 18) {
                        quickActions
                        upcomingEvents
                        friendsSection
                        challengesSection
                        activitySection
                    }
                    .padding()
                    .frame(maxWidth: 900)
                    .frame(maxWidth: .infinity)
                }
            }
            .ignoresSafeArea(edges: .top)
            .background(
                ATHLTHPremiumCanvas(
                    accent: Color.purple.opacity(0.42)
                )
            )
            .refreshable {
                await refreshCommunity()
            }
            .task {
                await refreshCommunity()
            }
            .sheet(isPresented: $showingCreateEvent) {
                CommunityEventCreateView()
                    .environmentObject(community)
                    .environmentObject(session)
            }
            .alert(
                "Community",
                isPresented: Binding(
                    get: { community.errorMessage != nil },
                    set: { shown in
                        if !shown {
                            community.errorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(community.errorMessage ?? "")
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            CommunityQuickLink(
                title: "Friends",
                detail: "\(social.friends.count)",
                icon: "person.2.fill"
            ) {
                SocialHubView(initialTab: .friends)
            }

            CommunityQuickLink(
                title: "Challenges",
                detail: "\(activeChallenges.count)",
                icon: "bolt.fill"
            ) {
                ChallengeHubView()
            }

            CommunityQuickLink(
                title: "Discover",
                detail: "People",
                icon: "person.badge.plus"
            ) {
                SocialHubView(initialTab: .discover)
            }
        }
    }

    private var upcomingEvents: some View {
        ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Upcoming")
                        .font(.title3.weight(.bold))
                    Text("Public runs, workouts and meetups you can join.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showingCreateEvent = true
                } label: {
                    Label("Create", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(ATHLTHTheme.accent)
            }

            if community.isLoading && community.events.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if community.upcomingEvents.isEmpty {
                ContentUnavailableView {
                    Label("No upcoming events", systemImage: "calendar.badge.plus")
                } description: {
                    Text("Create the first public run, walk or group workout.")
                } actions: {
                    Button("Create Event") {
                        showingCreateEvent = true
                    }
                }
                .padding(.vertical, 12)
            } else {
                VStack(spacing: 10) {
                    ForEach(community.upcomingEvents.prefix(4)) { item in
                        NavigationLink {
                            CommunityEventDetailView(eventID: item.id)
                        } label: {
                            CommunityEventRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 12)
            }
        }
    }

    private var friendsSection: some View {
        ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your People")
                        .font(.title3.weight(.bold))
                    Text("Friends you train, compare and challenge with.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                NavigationLink {
                    SocialHubView(initialTab: .friends)
                } label: {
                    Text("See All")
                        .font(.caption.weight(.semibold))
                }
            }

            if social.friends.isEmpty {
                NavigationLink {
                    SocialHubView(initialTab: .discover)
                } label: {
                    Label("Find people on ATHLTH", systemImage: "person.badge.plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(social.friends.prefix(8)) { friend in
                            NavigationLink {
                                FriendProfileView(userID: friend.userID)
                            } label: {
                                VStack(spacing: 7) {
                                    CommunityAvatar(profile: friend, size: 52)
                                    Text(friend.resolvedName)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                        .frame(width: 72)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 12)
                }
            }
        }
    }

    private var challengesSection: some View {
        ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Challenges")
                        .font(.title3.weight(.bold))
                    Text("Compete with friends or take on a shared route.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                NavigationLink {
                    ChallengeHubView()
                } label: {
                    Text("See All")
                        .font(.caption.weight(.semibold))
                }
            }

            if activeChallenges.isEmpty {
                NavigationLink {
                    ChallengeHubView()
                } label: {
                    Label("Create a challenge", systemImage: "bolt.badge.plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(activeChallenges.prefix(3))) { challenge in
                        NavigationLink {
                            ChallengeDetailView(challengeID: challenge.id)
                        } label: {
                            ChallengeCompactRow(challenge: challenge)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private var activitySection: some View {
        ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("From Your Community")
                        .font(.title3.weight(.bold))
                    Text("Workouts, trophies, goals and shared moments.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                NavigationLink {
                    SocialHubView(initialTab: .feed)
                } label: {
                    Text("Feed")
                        .font(.caption.weight(.semibold))
                }
            }

            if social.feed.isEmpty {
                Text("Friend activity will appear here when people choose to share it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(social.feed.prefix(3))) { item in
                        CommunityFeedPreviewRow(item: item)
                    }
                }
                .padding(.top, 12)
            }
        }
    }

    @MainActor
    private func refreshCommunity() async {
        async let eventRefresh: Void = community.refresh()
        async let socialRefresh: Void = social.refresh(challengeStore: challenges)
        _ = await (eventRefresh, socialRefresh)
        challenges.refreshStatuses()
    }
}

private struct CommunityQuickLink<Destination: View>: View {
    let title: String
    let detail: String
    let icon: String
    let destination: Destination

    init(
        title: String,
        detail: String,
        icon: String,
        @ViewBuilder destination: () -> Destination
    ) {
        self.title = title
        self.detail = detail
        self.icon = icon
        self.destination = destination()
    }

    var body: some View {
        NavigationLink {
            destination
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(ATHLTHTheme.accent)

                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)

                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct CommunityEventRow: View {
    let item: CommunityEventItem

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(item.event.startsAt.formatted(.dateTime.month(.abbreviated)).uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(ATHLTHTheme.accent)

                Text(item.event.startsAt.formatted(.dateTime.day()))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 44, height: 54)
            .background(
                ATHLTHTheme.accentSoft,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: item.event.activityType.systemImage)
                        .foregroundStyle(ATHLTHTheme.accent)
                    Text(item.event.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Text(
                    "\(item.event.startsAt.formatted(date: .omitted, time: .shortened)) · \(item.event.meetingName)"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                HStack(spacing: 8) {
                    Label(
                        "\(item.participantCount)",
                        systemImage: "person.2.fill"
                    )

                    if let pace = item.event.paceLabel, !pace.isEmpty {
                        Text(pace)
                    }
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

private struct CommunityFeedPreviewRow: View {
    let item: SocialFeedItem

    var body: some View {
        NavigationLink {
            FriendProfileView(userID: item.actor.userID)
        } label: {
            HStack(spacing: 10) {
                CommunityAvatar(profile: item.actor, size: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.actor.resolvedName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(item.activity.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(item.activity.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct CommunityAvatar: View {
    let profile: SocialProfileCard
    let size: CGFloat

    var body: some View {
        Group {
            if let rawURL = profile.avatarURL,
               let url = URL(string: rawURL) {
                AsyncImage(url: url) { phase in
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
                    "\(item.participantCount) joined",
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
        } else if community.isJoined(item) {
            Button {
                Task { await community.leave(item) }
            } label: {
                Label("Joined · Leave", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        } else {
            Button {
                Task { await community.join(item) }
            } label: {
                Label("Join Event", systemImage: "person.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(ATHLTHTheme.accent)
            .padding(.top, 4)
            .disabled(
                item.event.maxParticipants.map {
                    item.participantCount >= $0
                } ?? false
            )
        }
    }

    private func eventDetails(_ item: CommunityEventItem) -> some View {
        ATHLTHCard {
            Text("Details")
                .font(.headline)

            eventDetailRow(
                "Meeting point",
                value: item.event.meetingName,
                icon: "mappin.and.ellipse"
            )

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

    @State private var draft = CommunityEventDraft()
    @State private var limitParticipants = false
    @State private var maxParticipants = 20
    @State private var selectedRouteID: UUID?
    @State private var isCreating = false

    private var canCreate: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draft.meetingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        draft.startsAt > Date()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    TextField("Event name", text: $draft.title)

                    Picker("Activity", selection: $draft.activityType) {
                        ForEach(CommunityEventActivity.allCases) { activity in
                            Label(activity.title, systemImage: activity.systemImage)
                                .tag(activity)
                        }
                    }

                    TextField(
                        "Description (optional)",
                        text: $draft.summary,
                        axis: .vertical
                    )
                    .lineLimit(2...5)

                    DatePicker(
                        "Starts",
                        selection: $draft.startsAt,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )

                    Picker("Who can see it", selection: $draft.visibility) {
                        Text("Public").tag(ProfileVisibility.publicProfile)
                        Text("Friends").tag(ProfileVisibility.friends)
                    }
                }

                Section("Meet") {
                    TextField("Meeting point", text: $draft.meetingName)

                    TextField(
                        "Meeting details (optional)",
                        text: $draft.meetingDetails,
                        axis: .vertical
                    )
                    .lineLimit(2...4)

                    if draft.activityType == .running ||
                        draft.activityType == .walking {
                        TextField(
                            "Pace / level (optional)",
                            text: $draft.paceLabel
                        )

                        Picker("Route", selection: $selectedRouteID) {
                            Text("No route").tag(UUID?.none)
                            ForEach(session.savedRoutes) { route in
                                Text(route.title).tag(Optional(route.id))
                            }
                        }
                    }
                }

                Section("Participants") {
                    Toggle("Limit participants", isOn: $limitParticipants)

                    if limitParticipants {
                        Stepper(
                            "Maximum: \(maxParticipants)",
                            value: $maxParticipants,
                            in: 2...500
                        )
                    }
                }

                Section {
                    Label(
                        "Public events can be discovered by signed-in ATHLTH users. Friends-only events are limited to your ATHLTH friends.",
                        systemImage: "hand.raised.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Create Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isCreating ? "Creating…" : "Create") {
                        Task {
                            isCreating = true
                            draft.maxParticipants = limitParticipants
                                ? maxParticipants
                                : nil

                            if let selectedRouteID,
                               let route = session.savedRoutes.first(where: {
                                   $0.id == selectedRouteID
                               }) {
                                draft.routeID = route.id
                                draft.routeTitle = route.title
                            } else {
                                draft.routeID = nil
                                draft.routeTitle = nil
                            }

                            let created = await community.create(draft)
                            isCreating = false

                            if created {
                                dismiss()
                            }
                        }
                    }
                    .disabled(!canCreate || isCreating)
                }
            }
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

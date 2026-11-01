import SwiftUI

// MARK: - Fellesskap · native premium 2.0.6 rebuild
// Old Community list and shortcut screens are removed. Club, challenge,
// Arena and RSVP stores remain authoritative and are not deleted.
enum ATHLTHCommunityMainTab: String, CaseIterable, Identifiable {
    case overview, clubs, arena, events
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview:
            return ATHLTHLocalization.choose(english: "Overview", norwegian: "Oversikt")
        case .clubs:
            return ATHLTHLocalization.choose(english: "Clubs", norwegian: "Klubber")
        case .arena:
            return "Arena"
        case .events:
            return ATHLTHLocalization.choose(english: "Events", norwegian: "Arrangementer")
        }
    }
}


// Interest chips organize real content only; no fictitious clubs or events.
enum CommunityInterest: String, CaseIterable, Identifiable {
    case all, running, strength, yoga, outdoors, social
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return ATHLTHLocalization.choose(english: "All", norwegian: "Alle")
        case .running: return ATHLTHLocalization.choose(english: "Running", norwegian: "Løping")
        case .strength: return ATHLTHLocalization.choose(english: "Strength", norwegian: "Styrke")
        case .yoga: return "Yoga"
        case .outdoors: return ATHLTHLocalization.choose(english: "Outdoors", norwegian: "Tur")
        case .social: return ATHLTHLocalization.choose(english: "Social", norwegian: "Sosialt")
        }
    }

    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .running: "figure.run"
        case .strength: "dumbbell"
        case .yoga: "figure.mind.and.body"
        case .outdoors: "mountain.2"
        case .social: "person.3"
        }
    }

    // Search public descriptions rather than claiming unsupported categories.
    func matchesClub(_ club: CommunityGroupRecord) -> Bool {
        guard self != .all else { return true }
        let text = [club.name, club.summary].joined(separator: " ").lowercased()
        let terms: [String]
        switch self {
        case .all: return true
        case .running: terms = ["løp", "run", "jogg", "maraton"]
        case .strength: terms = ["styrke", "strength", "gym", "crossfit"]
        case .yoga: terms = ["yoga", "pilates"]
        case .outdoors: terms = ["tur", "fjell", "friluft", "hike", "walk", "outdoor"]
        case .social: terms = ["sosial", "social", "fellesskap", "community"]
        }
        return terms.contains { text.contains($0) }
    }

    func matchesPublicEvent(_ event: CommunityEventRecord) -> Bool {
        guard self != .all else { return true }
        let text = [event.activityType.rawValue, event.title, event.summary]
            .joined(separator: " ").lowercased()
        let terms: [String]
        switch self {
        case .all: return true
        case .running: terms = ["running", "løp", "jogg", "run"]
        case .strength: terms = ["strength", "styrke", "gym"]
        case .yoga: terms = ["yoga", "pilates"]
        case .outdoors: terms = ["hiking", "walking", "tur", "fjell", "outdoor", "friluft"]
        case .social: terms = ["social", "sosial", "meetup", "samling"]
        }
        return terms.contains { text.contains($0) }
    }

    func matchesEvent(_ event: CommunityGroupEventRecord) -> Bool {
        guard self != .all else { return true }
        let text = [event.activityType, event.title, event.summary]
            .joined(separator: " ").lowercased()
        let terms: [String]
        switch self {
        case .all: return true
        case .running: terms = ["running", "løp", "jogg", "run"]
        case .strength: terms = ["strength", "styrke", "gym"]
        case .yoga: terms = ["yoga", "pilates"]
        case .outdoors: terms = ["hiking", "walking", "tur", "fjell", "outdoor", "friluft"]
        case .social: terms = ["social", "sosial", "meetup", "samling"]
        }
        return terms.contains { text.contains($0) }
    }
}


private enum CommunityReferenceStyle {
    static let gold = Color(red: 0.65, green: 0.49, blue: 0.31)
    static let darkGold = Color(red: 0.45, green: 0.34, blue: 0.22)
    static let ink = Color(red: 0.11, green: 0.12, blue: 0.16)
    static let muted = Color(red: 0.43, green: 0.44, blue: 0.48)
    static let canvas = Color(red: 0.975, green: 0.974, blue: 0.966)
    static let paper = Color.white
    static let edge = Color(red: 0.91, green: 0.90, blue: 0.88)
    static let cream = Color(red: 0.97, green: 0.95, blue: 0.90)
}

private struct CommunityReferenceCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                CommunityReferenceStyle.paper,
                in: RoundedRectangle(cornerRadius: 21, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 21, style: .continuous)
                    .strokeBorder(CommunityReferenceStyle.edge.opacity(0.65), lineWidth: 0.7)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.025), radius: 8, y: 2)
    }
}

private extension View {
    func communityReferenceCard() -> some View {
        modifier(CommunityReferenceCard())
    }
}

struct ATHLTHCommunityV5View: View {
    @EnvironmentObject private var groups: CommunityGroupStore
    @EnvironmentObject private var community: CommunityEventStore
    @EnvironmentObject private var weekly: OfficialWeeklyChallengeStore
    @EnvironmentObject private var challenges: ChallengeStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var realtime: ATHLTHRealtimeSocialStore
    @EnvironmentObject private var messaging: MessagingStore
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager

    @State private var tab: ATHLTHCommunityMainTab = .overview
    @State private var showSearch = false
    @FocusState private var searchFocused: Bool
    @State private var showCreateClub = false
    @State private var query = ""
    @State private var clubInterest: CommunityInterest = .all
    @State private var eventInterest: CommunityInterest = .all
    @State private var respondingToInvite: UUID?
    @State private var inviteError: String?

    // Only mutual followers may expose online/training presence, and only
    // when they have opted in. Do not infer status from their membership.
    private var activeMembers: [SocialProfileCard] {
        social.mutualFollows.filter {
            realtime.isOnline($0.userID) ||
            realtime.isTrainingNow($0.userID)
        }
    }

    private var myClub: CommunityGroupRecord? {
        groups.joinedGroups.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }.first
    }

    private var activeDuel: ATHLTHChallenge? {
        challenges.trainingChallenges(for: session.profile.userID)
            .first {
                $0.hasAcceptedOpponent &&
                !$0.expiredWithoutOpponent() &&
                $0.participants.filter {
                    $0.state == .creator || $0.state == .accepted
                }.count == 2
            }
    }

    private var upcomingGathering: CommunityGroupEventRecord? {
        groups.calendarEvents
            .filter {
                $0.status != "cancelled" &&
                $0.status != "draft" &&
                $0.startsAt >= Date() &&
                groups.joinedGroupIDs.contains($0.groupID)
            }
            .sorted { $0.startsAt < $1.startsAt }
            .first
    }

    private var pendingClubInvitation: CommunityGroupInviteRecord? {
        groups.ownInvites
            .filter { $0.status == "pending" }
            .sorted { $0.createdAt > $1.createdAt }
            .first
    }

    private var matchingPublicClubs: [CommunityGroupRecord] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = groups.groups + groups.searchResults
        var seen = Set<UUID>()
        return all.filter {
            seen.insert($0.id).inserted &&
            $0.visibility == "public" &&
            !groups.joinedGroupIDs.contains($0.id) &&
            groups.pendingInvite(for: $0.id) == nil &&
            (clean.isEmpty || ATHLTHCommunityDiscoveryPolicy.matches(
                clean, in: [$0.name, $0.locationName, $0.summary]
            ))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    cover
                        .padding(.horizontal, -14)

                    VStack(alignment: .leading, spacing: 12) {
                        tabs
                        // Search is a Clubs-specific action, not a global header.
                        if tab == .clubs && showSearch {
                            searchBar
                        }
                        switch tab {
                        case .overview:
                            overview
                        case .clubs:
                            clubsPage
                        case .arena:
                            arenaPage
                        case .events:
                            eventsPage
                        }
                    }
                    .padding(.top, -30)
                    .padding(.bottom, 34)
                    .zIndex(1)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .ignoresSafeArea(.container, edges: .top)
            .background(CommunityReferenceStyle.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: showSearch) { _, visible in
                searchFocused = visible
            }
            .sheet(isPresented: $showCreateClub) {
                CommunityGroupCreateView()
            }
            .task {
                await refreshContent(force: false)
            }
            .refreshable {
                await refreshContent(force: true)
            }
            .task(id: showSearch ? query : "") {
                let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard tab == .clubs && showSearch && term.count >= 2 else {
                    groups.clearSearch()
                    social.clearSearch()
                    return
                }
                do { try await Task.sleep(for: .milliseconds(250)) }
                catch { return }
                guard !Task.isCancelled else { return }
                async let clubSearch: Void = groups.search(term)
                async let peopleSearch: Void = social.search(term)
                _ = await (clubSearch, peopleSearch)
            }
        }
    }

    // MARK: - Hero images: one per Community destination.

    private var communityHeroImageName: String {
        switch tab {
        case .overview: "CommunityHero"
        case .clubs: "CommunityClubsHero"
        case .arena: "CommunityArenaHero"
        case .events: "CommunityEventsHero"
        }
    }

    private var cover: some View {
        ZStack(alignment: .topLeading) {
            GeometryReader { geo in
                Image(communityHeroImageName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0.21), location: 0),
                    .init(color: .white.opacity(0.10), location: 0.30),
                    .init(color: .white.opacity(0.04), location: 0.56),
                    .init(color: .white.opacity(0.30), location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
            LinearGradient(
                colors: [.white.opacity(0.60), .white.opacity(0.03)],
                startPoint: .leading, endPoint: .trailing
            )
            .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 0) {
                // The hero is image-and-title only. Global icons belong in
                // their respective destinations, not atop Fellesskap.
                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 8) {
                    Text(ATHLTHLocalization.choose(
                        english: "COMMUNITY", norwegian: "FELLESSKAP"
                    ))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(2.6)
                    .foregroundStyle(CommunityReferenceStyle.ink.opacity(0.78))

                    Text(ATHLTHLocalization.choose(
                        english: "Community", norwegian: "Fellesskap"
                    ))
                    .font(.system(size: 39, weight: .regular, design: .serif))
                    .foregroundStyle(CommunityReferenceStyle.ink)
                    .minimumScaleFactor(0.8)
                }
                .padding(.leading, 20)
                .padding(.bottom, 55)
            }
        }
        .frame(height: 229)
        .clipShape(
            UnevenRoundedRectangle(
                bottomLeadingRadius: 21, bottomTrailingRadius: 21
            )
        )
        .accessibilityElement(children: .contain)
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(ATHLTHCommunityMainTab.allCases) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.23)) {
                        tab = option
                    }
                } label: {
                    Text(option.title)
                        .font(.system(size: 12.5, weight: tab == option ? .semibold : .medium))
                        .foregroundStyle(tab == option ?
                            CommunityReferenceStyle.ink : CommunityReferenceStyle.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                        .frame(maxWidth: .infinity, minHeight: 43)
                        .background {
                            if tab == option {
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(.white.opacity(0.91))
                                    .shadow(color: .black.opacity(0.085), radius: 7, y: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == option ? .isSelected : [])
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.white.opacity(0.65), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Only the four screenshot sections

    private var overview: some View {
        VStack(spacing: 12) {
            twoColumns {
                joinedClubCard
                arenaDuelCard
            }
            twoColumns {
                weeklyChallengeCard
                nextGatheringCard
            }
            membersStrip
            if let invitation = pendingClubInvitation {
                invitationBanner(invitation)
            }
        }
    }

    private var clubsPage: some View {
        VStack(alignment: .leading, spacing: 13) {
            if let club = myClub {
                featuredClub(club)
            } else {
                discoverClubWelcome
            }
            HStack(spacing: 9) {
                Button {
                    tab = .clubs
                    showSearch = true
                } label: {
                    smallAction(
                        title: tr("Find clubs", "Finn klubber"),
                        subtitle: tr("Search members and clubs", "Søk etter klubber"),
                        icon: "magnifyingglass"
                    )
                }
                .buttonStyle(.plain)

                Button { showCreateClub = true } label: {
                    smallAction(
                        title: tr("Create club", "Opprett klubb"),
                        subtitle: tr("Build your community", "Samle treningsvenner"),
                        icon: "plus"
                    )
                }
                .buttonStyle(.plain)
            }

            communitySectionHeading(
                tr("Explore your interests", "Utforsk etter interesse"),
                icon: "tag"
            )
            interestPicker(selection: $clubInterest, showSocial: false)
            membersStrip

            HStack(alignment: .firstTextBaseline) {
                communitySectionHeading(
                    tr("Recommended clubs", "Anbefalte klubber"),
                    icon: "sparkles"
                )
                Spacer()
                Button(tr("See all", "Se alle")) {
                    clubInterest = .all
                    showSearch = true
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(CommunityReferenceStyle.darkGold)
            }

            let recommendations = matchingPublicClubs.filter {
                clubInterest.matchesClub($0)
            }
            if recommendations.isEmpty {
                emptyEditorial(
                    tr("No clubs in this category yet", "Ingen klubber i denne kategorien ennå"),
                    detail: tr(
                        "Try another interest or search for a club.",
                        "Prøv en annen interesse eller søk etter en klubb."
                    ),
                    symbol: "person.3"
                )
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 9),
                    GridItem(.flexible(), spacing: 9)
                ], spacing: 10) {
                    ForEach(Array(recommendations.prefix(6))) { club in
                        NavigationLink {
                            CommunityGroupDetailView(group: club)
                        } label: {
                            recommendedClub(club)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let invite = pendingClubInvitation {
                invitationBanner(invite)
            }
        }
    }

    private var arenaPage: some View {
        VStack(alignment: .leading, spacing: 13) {
            arenaFeaturedDuel

            HStack(spacing: 8) {
                NavigationLink {
                    ATHLTHArenaHomeView()
                } label: {
                    smallAction(
                        title: tr("Duels", "Dueller"),
                        subtitle: tr("Compete with friends", "Utfordre venner"),
                        icon: "figure.run"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    ChallengeHubView()
                } label: {
                    smallAction(
                        title: tr("Challenges", "Utfordringer"),
                        subtitle: tr("Join a new challenge", "Finn en utfordring"),
                        icon: "star"
                    )
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .firstTextBaseline) {
                communitySectionHeading(
                    tr("This week's challenge", "Ukens utfordring"),
                    icon: "star.fill"
                )
                Spacer()
                NavigationLink {
                    ChallengeHubView()
                } label: {
                    Text(tr("See all", "Se alle"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(CommunityReferenceStyle.darkGold)
                }
            }
            arenaChallengeHighlight

            communitySectionHeading(
                tr("Your Arena", "Din uke i Arena"),
                icon: "chart.bar.fill"
            )
            arenaStatusCard

            communitySectionHeading(
                tr("Compete your way", "Finn din konkurranse"),
                icon: "trophy"
            )
            HStack(spacing: 9) {
                arenaActionTile(
                    tr("Duels", "Dueller"),
                    subtitle: tr("One against one", "Én mot én"),
                    icon: "person.2.fill",
                    action: .duels
                )
                arenaActionTile(
                    tr("Friends", "Venner"),
                    subtitle: tr("Compare results", "Sammenlign økter"),
                    icon: "person.3.fill",
                    action: .friends
                )
                arenaActionTile(
                    tr("Ranking", "Rangering"),
                    subtitle: tr("See results", "Se resultater"),
                    icon: "chart.bar.xaxis",
                    action: .duels
                )
            }
            NavigationLink {
                CommunityFriendsVsFriendsDetailView()
            } label: {
                inviteToDuelStrip
            }
            .buttonStyle(.plain)
        }
    }

    private var eventsPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            interestPicker(selection: $eventInterest, showSocial: true)
            if let featured = filteredUpcomingEvents.first,
               let club = groups.group(for: featured.groupID) {
                featuredEvent(featured, club: club)
            } else if let publicEvent = filteredPublicEvents.first {
                featuredPublicEvent(publicEvent)
            } else {
                emptyEditorial(
                    tr("Find your next shared workout", "Finn din neste fellesøkt"),
                    detail: tr(
                        "New events from your clubs will appear here.",
                        "Nye arrangementer fra klubbene dine vises her."
                    ),
                    symbol: "calendar.badge.plus"
                )
            }

            HStack(alignment: .firstTextBaseline) {
                communitySectionHeading(
                    tr("Upcoming events", "Kommende arrangementer"),
                    icon: "calendar"
                )
                Spacer()
                NavigationLink {
                    CommunityEventsView()
                } label: {
                    Text(tr("See calendar", "Se kalender"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(CommunityReferenceStyle.darkGold)
                }
            }

            let upcoming = Array(filteredUpcomingEvents.dropFirst().prefix(8))
            if upcoming.isEmpty {
                emptyEditorial(
                    tr("Nothing else scheduled", "Ingen flere planlagte arrangementer"),
                    detail: tr(
                        "Explore public events or create a gathering for your club.",
                        "Utforsk åpne arrangementer eller opprett en samling i klubben."
                    ),
                    symbol: "calendar"
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 10) {
                        ForEach(upcoming) { event in
                            if let club = groups.group(for: event.groupID) {
                                NavigationLink {
                                    CommunityGroupEventDetailView(group: club, event: event)
                                } label: {
                                    upcomingEventTile(event, club: club)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            if !filteredPublicEvents.isEmpty {
                communitySectionHeading(
                    tr("Open community events", "Åpne arrangementer"),
                    icon: "person.3"
                )
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(filteredPublicEvents.prefix(8)) { event in
                            NavigationLink {
                                CommunityEventDetailView(eventID: event.id)
                            } label: {
                                publicEventTile(event)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            if let invite = pendingClubInvitation {
                invitationBanner(invite)
            }
            NavigationLink {
                CommunityEventsView()
            } label: {
                eventsOverviewStrip
            }
            .buttonStyle(.plain)
        }
    }

    private func twoColumns<Left: View, Right: View>(
        @ViewBuilder _ content: () -> TupleView<(Left, Right)>
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            content()
        }
    }


    // MARK: - Fellesskap 2.0.6: native editorial components
    // Screenshot images inform the layout. These cards read real store state
    // and route into the existing, authoritative detail editors.

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var availableUpcomingEvents: [CommunityGroupEventRecord] {
        groups.calendarEvents
            .filter { $0.startsAt >= Date() &&
                $0.status != "cancelled" && $0.status != "draft" &&
                groups.group(for: $0.groupID) != nil }
            .sorted { $0.startsAt < $1.startsAt }
    }

    private var filteredUpcomingEvents: [CommunityGroupEventRecord] {
        availableUpcomingEvents.filter { eventInterest.matchesEvent($0) }
    }

    private var filteredPublicEvents: [CommunityEventItem] {
        community.upcomingEvents
            .filter { eventInterest.matchesPublicEvent($0.event) }
            .sorted { $0.event.startsAt < $1.event.startsAt }
    }

    private func communitySectionHeading(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(CommunityReferenceStyle.ink)
            .labelStyle(.titleAndIcon)
    }

    private func smallAction(
        title: String, subtitle: String, icon: String
    ) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(CommunityReferenceStyle.darkGold)
                .frame(width: 38, height: 38)
                .background(CommunityReferenceStyle.cream, in: Circle())
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CommunityReferenceStyle.ink)
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(CommunityReferenceStyle.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 97)
        .padding(8)
        .communityReferenceCard()
        .accessibilityElement(children: .combine)
    }

    private func interestPicker(
        selection: Binding<CommunityInterest>,
        showSocial: Bool
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(CommunityInterest.allCases.filter {
                    showSocial || $0 != .social
                }) { interest in
                    let selected = selection.wrappedValue == interest
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selection.wrappedValue = interest
                        }
                    } label: {
                        Label(interest.title, systemImage: interest.symbol)
                            .font(.system(size: 11, weight: selected ? .semibold : .medium))
                            .foregroundStyle(selected ? .white :
                                CommunityReferenceStyle.darkGold)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 39)
                            .background(selected ?
                                CommunityReferenceStyle.gold :
                                CommunityReferenceStyle.paper,
                                in: Capsule())
                            .overlay {
                                Capsule().strokeBorder(
                                    selected ? Color.clear :
                                        CommunityReferenceStyle.edge,
                                    lineWidth: 0.8
                                )
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private var discoverClubWelcome: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image("GoalAdventure")
                .resizable()
                .scaledToFill()
                .frame(height: 125)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 14))
            Text(tr("Find your people", "Finn ditt treningsfellesskap"))
                .font(.system(size: 23, weight: .regular, design: .serif))
                .foregroundStyle(CommunityReferenceStyle.ink)
            Text(tr(
                "Join a club to discover sessions, friends and shared adventures.",
                "Bli med i en klubb med økter, treningsvenner og felles opplevelser."
            ))
            .font(.subheadline)
            .foregroundStyle(CommunityReferenceStyle.muted)
            Button {
                showSearch = true
            } label: {
                creamButton(tr("Explore clubs", "Utforsk klubber"), symbol: "arrow.right")
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .communityReferenceCard()
    }

    private func featuredClub(_ club: CommunityGroupRecord) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            ZStack(alignment: .topLeading) {
                ATHLTHArtworkImage(
                    reference: club.headerImageURL ?? club.imageURL,
                    fallbackAssetName: "GoalMountain",
                    maxPixelSize: 1200
                )
                .athlthBoundedFill()
                .frame(height: 133)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 14))
                Label(tr("Your club", "Din klubb"), systemImage: "star.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CommunityReferenceStyle.darkGold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.regularMaterial, in: Capsule())
                    .padding(11)
            }
            NavigationLink {
                CommunityGroupDetailView(group: club)
            } label: {
                HStack(spacing: 11) {
                    ATHLTHArtworkImage(
                        reference: club.imageURL ?? club.headerImageURL,
                        fallbackAssetName: "CommunityHero",
                        maxPixelSize: 450
                    )
                    .athlthBoundedFill()
                    .frame(width: 51, height: 51)
                    .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(club.name)
                            .font(.headline)
                            .foregroundStyle(CommunityReferenceStyle.ink)
                            .lineLimit(1)
                        Text(club.summary.isEmpty ?
                            tr("Train together. Go further.", "Tren sammen. Kom lenger.") :
                            club.summary)
                            .font(.caption)
                            .foregroundStyle(CommunityReferenceStyle.muted)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(CommunityReferenceStyle.darkGold)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 0) {
                clubMetric(groups.members(in: club.id).count,
                           label: tr("Members", "Medlemmer"), icon: "person.3.fill")
                clubMetric(groups.challenges(in: club.id).count,
                           label: tr("Challenges", "Utfordringer"), icon: "chart.bar.fill")
                clubMetric(groups.events(in: club.id).count,
                           label: tr("Events", "Arrangementer"), icon: "calendar")
            }
            .padding(.vertical, 4)
            if !groups.members(in: club.id).isEmpty {
                memberAvatars(groups.members(in: club.id))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            NavigationLink {
                CommunityGroupDetailView(group: club)
            } label: {
                creamButton(tr("Open club", "Åpne klubb"), symbol: "arrow.right")
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .communityReferenceCard()
    }

    private func clubMetric(_ value: Int, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(CommunityReferenceStyle.darkGold)
            Text(value.formatted())
                .font(.subheadline.weight(.bold))
                .foregroundStyle(CommunityReferenceStyle.ink)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(CommunityReferenceStyle.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func recommendedClub(_ club: CommunityGroupRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ATHLTHArtworkImage(
                reference: club.headerImageURL ?? club.imageURL,
                fallbackAssetName: "GoalAdventure",
                maxPixelSize: 650
            )
            .athlthBoundedFill()
            .frame(height: 93)
            .frame(maxWidth: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(club.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CommunityReferenceStyle.ink)
                .lineLimit(2)
            Label(club.locationName.isEmpty ?
                tr("Online club", "Digital klubb") : club.locationName,
                systemImage: "mappin")
                .font(.caption2)
                .foregroundStyle(CommunityReferenceStyle.muted)
                .lineLimit(1)
            Text(club.summary)
                .font(.system(size: 10))
                .foregroundStyle(CommunityReferenceStyle.muted)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            creamButton(tr("Open", "Åpne"), symbol: "arrow.right")
        }
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
        .padding(10)
        .communityReferenceCard()
    }

    private func emptyEditorial(
        _ title: String, detail: String, symbol: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(CommunityReferenceStyle.gold)
            Text(title)
                .font(.system(size: 18, weight: .regular, design: .serif))
                .foregroundStyle(CommunityReferenceStyle.ink)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(CommunityReferenceStyle.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .communityReferenceCard()
    }

    private var arenaFeaturedDuel: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                communitySectionHeading(
                    tr("Featured duel", "Fremhevet duell"),
                    icon: "trophy.fill"
                )
                Spacer()
                if activeDuel != nil {
                    Text(tr("Active", "Pågår"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CommunityReferenceStyle.darkGold)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(CommunityReferenceStyle.cream, in: Capsule())
                }
            }
            if let duel = activeDuel {
                let leaders = Array(challenges.leaderboard(for: duel.id).prefix(2))
                Text(duel.title)
                    .font(.system(size: 24, weight: .regular, design: .serif))
                    .foregroundStyle(CommunityReferenceStyle.ink)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    ForEach(leaders) { entry in
                        VStack(spacing: 7) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(CommunityReferenceStyle.gold.opacity(0.8))
                            Text(entry.participant.displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(CommunityReferenceStyle.ink)
                                .lineLimit(1)
                            Text(scoreText(entry, for: duel))
                                .font(.headline)
                                .foregroundStyle(CommunityReferenceStyle.ink)
                        }
                        .frame(maxWidth: .infinity)
                        if entry.id == leaders.first?.id && leaders.count == 2 {
                            Text("VS")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(CommunityReferenceStyle.darkGold)
                                .frame(width: 39, height: 39)
                                .background(CommunityReferenceStyle.cream, in: Circle())
                        }
                    }
                }
                .padding(.vertical, 7)
            } else {
                ZStack(alignment: .bottomLeading) {
                    Image("GoalSprint")
                        .resizable()
                        .scaledToFill()
                        .frame(height: 149)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 15))
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.65)],
                        startPoint: .center, endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                    Text(tr(
                        "Your next duel starts here",
                        "Din neste duell starter her"
                    ))
                    .font(.system(size: 21, weight: .medium, design: .serif))
                    .foregroundStyle(.white)
                    .padding(16)
                }
                .frame(height: 149)
                Text(tr(
                    "Challenge a friend and compare real training results.",
                    "Utfordre en venn og sammenlign faktiske treningsresultater."
                ))
                .font(.subheadline)
                .foregroundStyle(CommunityReferenceStyle.muted)
            }
            NavigationLink {
                ATHLTHArenaHomeView()
            } label: {
                creamButton(activeDuel == nil ?
                    tr("Find a duel", "Finn en duell") :
                    tr("View the duel", "Se duellen"),
                    symbol: "arrow.right")
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .communityReferenceCard()
    }

    private var arenaChallengeHighlight: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let challenge = weekly.activeChallenge {
                NavigationLink {
                    OfficialWeeklyChallengeDetailView(challengeID: challenge.id)
                } label: {
                    HStack(spacing: 11) {
                        Image("GoalMountain")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 89, height: 96)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(challenge.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(CommunityReferenceStyle.ink)
                                .lineLimit(2)
                            Text(challenge.subtitle)
                                .font(.caption)
                                .foregroundStyle(CommunityReferenceStyle.muted)
                                .lineLimit(3)
                            Text(weekly.isJoined(challenge.id)
                                ? OfficialWeeklyChallengeProgress.valueText(
                                    challenge: challenge, workouts: health.workouts)
                                : tr("Join to track your progress", "Bli med for å følge fremgangen"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(CommunityReferenceStyle.darkGold)
                        }
                    }
                }
                .buttonStyle(.plain)
                progressDots(challenge)
            } else {
                Text(tr(
                    "The next official challenge appears here when published.",
                    "Neste offisielle utfordring vises her når den er publisert."
                ))
                .font(.subheadline)
                .foregroundStyle(CommunityReferenceStyle.muted)
                NavigationLink {
                    ChallengeHubView()
                } label: {
                    creamButton(tr("Explore", "Utforsk"), symbol: "arrow.right")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(13)
        .communityReferenceCard()
    }

    private var arenaStatusCard: some View {
        let active = challenges.trainingChallenges(for: session.profile.userID)
            .filter { $0.hasAcceptedOpponent && !$0.expiredWithoutOpponent() }.count
        let joined = weekly.activeChallenge.map { weekly.isJoined($0.id) } ?? false
        return HStack(spacing: 13) {
            Image(systemName: "trophy.fill")
                .font(.title2)
                .foregroundStyle(CommunityReferenceStyle.gold)
                .frame(width: 54, height: 54)
                .background(CommunityReferenceStyle.cream, in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("Your active competitions", "Dine aktive konkurranser"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CommunityReferenceStyle.ink)
                Text(tr(
                    "\(active) duels · \(joined ? 1 : 0) weekly challenges",
                    "\(active) dueller · \(joined ? 1 : 0) ukesutfordringer"
                ))
                .font(.caption)
                .foregroundStyle(CommunityReferenceStyle.muted)
            }
            Spacer(minLength: 0)
            NavigationLink {
                ATHLTHArenaHomeView()
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundStyle(CommunityReferenceStyle.darkGold)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(tr("Open Arena", "Åpne Arena"))
        }
        .padding(13)
        .communityReferenceCard()
    }

    private enum ArenaTarget { case duels, friends }

    private func arenaActionTile(
        _ title: String, subtitle: String, icon: String,
        action: ArenaTarget
    ) -> some View {
        Group {
            switch action {
            case .duels:
                NavigationLink {
                    ATHLTHArenaHomeView()
                } label: {
                    arenaActionContent(title, subtitle: subtitle, icon: icon)
                }
            case .friends:
                NavigationLink {
                    CommunityFriendsVsFriendsDetailView()
                } label: {
                    arenaActionContent(title, subtitle: subtitle, icon: icon)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func arenaActionContent(
        _ title: String, subtitle: String, icon: String
    ) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(CommunityReferenceStyle.darkGold)
                .frame(height: 32)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CommunityReferenceStyle.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(subtitle)
                .font(.system(size: 9))
                .foregroundStyle(CommunityReferenceStyle.muted)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 108)
        .padding(7)
        .communityReferenceCard()
    }

    private var inviteToDuelStrip: some View {
        HStack(spacing: 11) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.title2)
                .foregroundStyle(CommunityReferenceStyle.darkGold)
                .frame(width: 44, height: 44)
                .background(CommunityReferenceStyle.cream, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("Challenge a friend", "Inviter en venn til duell"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CommunityReferenceStyle.ink)
                Text(tr(
                    "Create a challenge with someone you follow.",
                    "Start en duell med en treningsvenn."
                ))
                .font(.caption)
                .foregroundStyle(CommunityReferenceStyle.muted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .foregroundStyle(CommunityReferenceStyle.darkGold)
        }
        .padding(13)
        .background(CommunityReferenceStyle.cream.opacity(0.7),
                    in: RoundedRectangle(cornerRadius: 18))
    }

    private func featuredEvent(
        _ event: CommunityGroupEventRecord, club: CommunityGroupRecord
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink {
                CommunityGroupEventDetailView(group: club, event: event)
            } label: {
                VStack(alignment: .leading, spacing: 9) {
                    ZStack(alignment: .topLeading) {
                        ATHLTHArtworkImage(
                            reference: event.imageURL,
                            fallbackAssetName: "GoalAdventure",
                            maxPixelSize: 1200
                        )
                        .athlthBoundedFill()
                        .frame(height: 156)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 13))
                        Label(tr("Featured event", "Fremhevet arrangement"),
                              systemImage: "star.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CommunityReferenceStyle.darkGold)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(.regularMaterial, in: Capsule())
                            .padding(9)
                    }
                    Text(event.title)
                        .font(.system(size: 23, weight: .regular, design: .serif))
                        .foregroundStyle(CommunityReferenceStyle.ink)
                        .lineLimit(2)
                    Text(event.summary.isEmpty ? club.name : event.summary)
                        .font(.caption)
                        .foregroundStyle(CommunityReferenceStyle.muted)
                        .lineLimit(2)
                    HStack(spacing: 11) {
                        Label(event.startsAt.formatted(.dateTime.weekday(.abbreviated)
                            .day().month(.abbreviated)), systemImage: "calendar")
                        Label(event.meetingName.isEmpty ?
                            club.locationName : event.meetingName,
                            systemImage: "mappin")
                    }
                    .font(.caption)
                    .foregroundStyle(CommunityReferenceStyle.muted)
                    .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            NavigationLink {
                CommunityGroupEventDetailView(group: club, event: event)
            } label: {
                creamButton(tr("View event", "Se arrangement"), symbol: "arrow.right")
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .communityReferenceCard()
    }

    private func upcomingEventTile(
        _ event: CommunityGroupEventRecord,
        club: CommunityGroupRecord
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ATHLTHArtworkImage(
                reference: event.imageURL,
                fallbackAssetName: "GoalAdventure",
                maxPixelSize: 650
            )
            .athlthBoundedFill()
            .frame(height: 113)
            .frame(maxWidth: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(event.title)
                .font(.system(size: 14, weight: .semibold, design: .serif))
                .foregroundStyle(CommunityReferenceStyle.ink)
                .lineLimit(2)
            Text(club.name)
                .font(.caption2)
                .foregroundStyle(CommunityReferenceStyle.muted)
                .lineLimit(1)
            Label(event.startsAt.formatted(.dateTime.day().month(.abbreviated)
                .hour().minute()), systemImage: "calendar")
                .font(.caption2)
                .foregroundStyle(CommunityReferenceStyle.muted)
            creamButton(tr("Details", "Detaljer"), symbol: "chevron.right")
        }
        .frame(width: 190, height: 237, alignment: .topLeading)
        .padding(10)
        .communityReferenceCard()
    }

    private func featuredPublicEvent(_ item: CommunityEventItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink {
                CommunityEventDetailView(eventID: item.id)
            } label: {
                VStack(alignment: .leading, spacing: 9) {
                    ZStack(alignment: .topLeading) {
                        ATHLTHArtworkImage(
                            reference: item.event.coverImageURL,
                            fallbackAssetName: item.event.coverArtworkName ?? "GoalRunning",
                            maxPixelSize: 1200
                        )
                        .athlthBoundedFill()
                        .frame(height: 156)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 13))
                        Label(tr("Featured event", "Fremhevet arrangement"),
                              systemImage: "star.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CommunityReferenceStyle.darkGold)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(.regularMaterial, in: Capsule())
                            .padding(9)
                    }
                    Text(item.event.title)
                        .font(.system(size: 23, weight: .regular, design: .serif))
                        .foregroundStyle(CommunityReferenceStyle.ink)
                        .lineLimit(2)
                    Text(item.event.summary)
                        .font(.caption)
                        .foregroundStyle(CommunityReferenceStyle.muted)
                        .lineLimit(2)
                    HStack(spacing: 10) {
                        Label(item.event.startsAt.formatted(.dateTime.weekday(.abbreviated)
                            .day().month(.abbreviated)), systemImage: "calendar")
                        Label(item.event.meetingName, systemImage: "mappin")
                    }
                    .font(.caption)
                    .foregroundStyle(CommunityReferenceStyle.muted)
                    .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            NavigationLink {
                CommunityEventDetailView(eventID: item.id)
            } label: {
                creamButton(tr("View event", "Se arrangement"), symbol: "arrow.right")
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .communityReferenceCard()
    }

    private func publicEventTile(_ item: CommunityEventItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ATHLTHArtworkImage(
                reference: item.event.coverImageURL,
                fallbackAssetName: item.event.coverArtworkName ?? "GoalRunning",
                maxPixelSize: 650
            )
            .athlthBoundedFill()
            .frame(height: 113)
            .frame(maxWidth: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(item.event.title)
                .font(.system(size: 14, weight: .semibold, design: .serif))
                .foregroundStyle(CommunityReferenceStyle.ink)
                .lineLimit(2)
            Label(item.event.meetingName, systemImage: "mappin")
                .font(.caption2)
                .foregroundStyle(CommunityReferenceStyle.muted)
                .lineLimit(1)
            Label(item.event.startsAt.formatted(.dateTime.day().month(.abbreviated)
                .hour().minute()), systemImage: "calendar")
                .font(.caption2)
                .foregroundStyle(CommunityReferenceStyle.muted)
            creamButton(tr("Details", "Detaljer"), symbol: "chevron.right")
        }
        .frame(width: 190, height: 237, alignment: .topLeading)
        .padding(10)
        .communityReferenceCard()
    }

    private var eventsOverviewStrip: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.title2)
                .foregroundStyle(CommunityReferenceStyle.gold)
                .frame(width: 47, height: 47)
                .background(CommunityReferenceStyle.cream, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("Events in your community", "Arrangementer i fellesskapet"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CommunityReferenceStyle.ink)
                Text(tr(
                    "\(availableUpcomingEvents.count + community.upcomingEvents.count) upcoming events",
                    "\(availableUpcomingEvents.count + community.upcomingEvents.count) kommende arrangementer"
                ))
                .font(.caption)
                .foregroundStyle(CommunityReferenceStyle.muted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .foregroundStyle(CommunityReferenceStyle.darkGold)
        }
        .padding(13)
        .communityReferenceCard()
    }

    // MARK: - 2 x 2 editorial cards

    private var joinedClubCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeading(ATHLTHLocalization.choose(
                english: "Your club", norwegian: "Din klubb"
            ), icon: "person.3.fill")
            if let club = myClub {
                NavigationLink {
                    CommunityGroupDetailView(group: club)
                } label: {
                    clubSummary(club)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                if groups.members(in: club.id).count > 1 {
                    memberAvatars(groups.members(in: club.id))
                }
                NavigationLink {
                    CommunityGroupDetailView(group: club)
                } label: {
                    creamButton(ATHLTHLocalization.choose(
                        english: "Open club", norwegian: "Åpne klubb"
                    ), symbol: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(.plain)
            } else {
                Image("CommunityHero")
                    .resizable()
                    .scaledToFill()
                    .frame(height: 68)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Text(ATHLTHLocalization.choose(
                    english: "Your first club is waiting",
                    norwegian: "Din første klubb venter"
                ))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CommunityReferenceStyle.ink)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button {
                    tab = .clubs
                    showSearch = true
                } label: {
                    creamButton(ATHLTHLocalization.choose(
                        english: "Find a club", norwegian: "Finn klubb"
                    ), symbol: "person.3")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(11)
        .frame(height: 184, alignment: .topLeading)
        .communityReferenceCard()
    }

    private func clubSummary(_ club: CommunityGroupRecord) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                ATHLTHArtworkImage(
                    reference: club.headerImageURL ?? club.imageURL,
                    fallbackAssetName: "CommunityHero",
                    maxPixelSize: 700
                )
                .athlthBoundedFill()
                .frame(width: 51, height: 51)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(club.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CommunityReferenceStyle.ink)
                        .lineLimit(2)
                    Text(club.summary.isEmpty ?
                        ATHLTHLocalization.choose(
                            english: "Train together. Go further.",
                            norwegian: "Tren sammen. Kom lenger.") :
                        club.summary
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(CommunityReferenceStyle.muted)
                    .lineLimit(2)
                }
            }
            let count = groups.members(in: club.id).count
            if count > 0 {
                Label(
                    ATHLTHLocalization.choose(
                        english: "\(count) members",
                        norwegian: "\(count) medlemmer"),
                    systemImage: "person.3.fill"
                )
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(CommunityReferenceStyle.muted)
            }
        }
    }

    private func memberAvatars(
        _ members: [CommunityGroupMemberRecord]
    ) -> some View {
        HStack(spacing: -5) {
            ForEach(Array(members.prefix(5)), id: \.userID) { member in
                let profile = groups.profileCard(for: member.userID)
                CommunityShowcaseAvatar(
                    url: profile?.avatarURL.flatMap(URL.init(string:)),
                    fallback: profile?.resolvedName ?? "ATHLTH",
                    size: 23
                )
                .overlay { Circle().strokeBorder(.white, lineWidth: 1.3) }
            }
            if members.count > 5 {
                Text("+\(members.count - 5)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(CommunityReferenceStyle.muted)
                    .padding(.leading, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var arenaDuelCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeading(ATHLTHLocalization.choose(
                english: "Arena duel", norwegian: "Arena-duell"
            ), icon: "trophy.fill")

            if let duel = activeDuel {
                let leaders = challenges.leaderboard(for: duel.id)
                HStack(spacing: 6) {
                    ForEach(Array(leaders.prefix(2))) { entry in
                        VStack(spacing: 4) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 33))
                                .foregroundStyle(CommunityReferenceStyle.gold)
                            Text(entry.participant.displayName)
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                                .foregroundStyle(CommunityReferenceStyle.ink)
                            Text(scoreText(entry, for: duel))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(CommunityReferenceStyle.ink)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        if entry.id == leaders.first?.id, leaders.count >= 2 {
                            Text("VS")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(CommunityReferenceStyle.darkGold)
                                .frame(width: 29, height: 29)
                                .background(CommunityReferenceStyle.cream, in: Circle())
                        }
                    }
                }
                Text(duel.title)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .foregroundStyle(CommunityReferenceStyle.muted)
                Spacer(minLength: 0)
            } else {
                HStack {
                    Image(systemName: "person.crop.circle")
                    Text("VS")
                        .font(.caption.weight(.semibold))
                        .padding(7)
                        .background(CommunityReferenceStyle.cream, in: Circle())
                    Image(systemName: "person.crop.circle")
                }
                .font(.system(size: 34))
                .foregroundStyle(CommunityReferenceStyle.gold.opacity(0.75))
                .frame(maxWidth: .infinity)
                Text(ATHLTHLocalization.choose(
                    english: "No active duel yet",
                    norwegian: "Ingen aktiv duell ennå"
                ))
                .font(.system(size: 11))
                .foregroundStyle(CommunityReferenceStyle.muted)
                .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
            NavigationLink {
                ATHLTHArenaHomeView()
            } label: {
                creamButton(activeDuel == nil
                    ? ATHLTHLocalization.choose(
                        english: "Find a duel", norwegian: "Finn en duell")
                    : ATHLTHLocalization.choose(
                        english: "View duel", norwegian: "Se duell"),
                    symbol: "person.2.fill"
                )
            }
            .buttonStyle(.plain)
        }
        .padding(11)
        .frame(height: 184, alignment: .topLeading)
        .communityReferenceCard()
    }

    private func scoreText(
        _ entry: ChallengeLeaderboardEntry,
        for challenge: ATHLTHChallenge
    ) -> String {
        guard let score = entry.score, score.isFinite else { return "—" }
        if challenge.rules.scoring == .mostDistance {
            return String(format: "%.1f km", score / 1_000)
        }
        return score.formatted(.number.precision(.fractionLength(0...1)))
    }

    private var weeklyChallengeCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            cardHeading(ATHLTHLocalization.choose(
                english: "Weekly challenge", norwegian: "Ukens utfordring"
            ), icon: "star.fill")
            if let challenge = weekly.activeChallenge {
                NavigationLink {
                    OfficialWeeklyChallengeDetailView(challengeID: challenge.id)
                } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 8) {
                            Image(systemName: challenge.kind.icon)
                                .font(.system(size: 20))
                                .foregroundStyle(CommunityReferenceStyle.darkGold)
                                .frame(width: 39, height: 39)
                                .background(CommunityReferenceStyle.cream, in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text(challenge.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(CommunityReferenceStyle.ink)
                                    .lineLimit(2)
                                Text(challenge.subtitle)
                                    .font(.system(size: 10))
                                    .foregroundStyle(CommunityReferenceStyle.muted)
                                    .lineLimit(2)
                            }
                        }
                        progressDots(challenge)
                    }
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                NavigationLink {
                    OfficialWeeklyChallengeDetailView(challengeID: challenge.id)
                } label: {
                    creamButton(ATHLTHLocalization.choose(
                        english: "View challenge", norwegian: "Se utfordring"
                    ), symbol: "arrow.right")
                }
                .buttonStyle(.plain)
            } else {
                Spacer(minLength: 0)
                Text(ATHLTHLocalization.choose(
                    english: "Next challenge will appear here.",
                    norwegian: "Neste utfordring vises her."
                ))
                .font(.system(size: 11))
                .foregroundStyle(CommunityReferenceStyle.muted)
                Spacer(minLength: 0)
                NavigationLink {
                    ChallengeHubView()
                } label: {
                    creamButton(ATHLTHLocalization.choose(
                        english: "Explore", norwegian: "Utforsk"
                    ), symbol: "arrow.right")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(11)
        .frame(height: 173, alignment: .topLeading)
        .communityReferenceCard()
    }

    private func progressDots(_ challenge: OfficialWeeklyChallenge) -> some View {
        let target = max(1, Int(challenge.targetValue.rounded(.up)))
        let total = min(5, target)
        let current = weekly.isJoined(challenge.id)
            ? OfficialWeeklyChallengeProgress.currentValue(
                challenge: challenge, workouts: health.workouts
              ) : 0
        let fraction = max(0, min(current / max(challenge.targetValue, 1), 1))
        let completed = min(total, Int((fraction * Double(total)).rounded(.down)))

        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(0..<total, id: \.self) { index in
                    ZStack {
                        Circle()
                            .fill(index < completed
                                  ? CommunityReferenceStyle.gold
                                  : CommunityReferenceStyle.canvas)
                        Circle()
                            .strokeBorder(
                                CommunityReferenceStyle.edge,
                                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                            )
                        if index < completed {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                }
            }
            Text(weekly.isJoined(challenge.id)
                ? OfficialWeeklyChallengeProgress.valueText(
                    challenge: challenge, workouts: health.workouts
                  )
                : ATHLTHLocalization.choose(
                    english: "Not joined yet", norwegian: "Ikke påmeldt ennå"
                  ))
                .font(.system(size: 9))
                .foregroundStyle(CommunityReferenceStyle.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private var nextGatheringCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            cardHeading(ATHLTHLocalization.choose(
                english: "Next gathering", norwegian: "Neste samling"
            ), icon: "calendar")
            if let event = upcomingGathering,
               let club = groups.group(for: event.groupID) {
                NavigationLink {
                    CommunityGroupEventDetailView(group: club, event: event)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        ZStack(alignment: .topTrailing) {
                            ATHLTHArtworkImage(
                                reference: event.imageURL,
                                fallbackAssetName: "GoalAdventure",
                                maxPixelSize: 1200
                            )
                            .athlthBoundedFill()
                            .frame(height: 61)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 11))

                            Text(event.startsAt.formatted(
                                .dateTime.day().month(.abbreviated)
                            ))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(CommunityReferenceStyle.ink)
                            .padding(5)
                            .background(.white.opacity(0.92),
                                        in: RoundedRectangle(cornerRadius: 6))
                            .padding(5)
                        }
                        Text(event.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CommunityReferenceStyle.ink)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Image(systemName: "mappin")
                            Text(event.meetingName.isEmpty
                                ? club.locationName : event.meetingName)
                            Spacer(minLength: 0)
                            Image(systemName: "clock")
                            Text(event.startsAt.formatted(.dateTime.hour().minute()))
                        }
                        .font(.system(size: 9))
                        .foregroundStyle(CommunityReferenceStyle.muted)
                        .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                NavigationLink {
                    CommunityGroupEventDetailView(group: club, event: event)
                } label: {
                    creamButton(ATHLTHLocalization.choose(
                        english: "Details", norwegian: "Se detaljer"
                    ), symbol: "chevron.right")
                }
                .buttonStyle(.plain)
            } else {
                Image("GoalAdventure")
                    .resizable()
                    .scaledToFill()
                    .frame(height: 65)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                Text(ATHLTHLocalization.choose(
                    english: "No gathering scheduled",
                    norwegian: "Ingen samling planlagt"
                ))
                .font(.system(size: 11))
                .foregroundStyle(CommunityReferenceStyle.muted)
                Spacer(minLength: 0)
                NavigationLink {
                    CommunityEventsView()
                } label: {
                    creamButton(ATHLTHLocalization.choose(
                        english: "Find gatherings", norwegian: "Finn samlinger"
                    ), symbol: "chevron.right")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(11)
        .frame(height: 173, alignment: .topLeading)
        .communityReferenceCard()
    }

    private var membersStrip: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label(ATHLTHLocalization.choose(
                    english: "Active members", norwegian: "Aktive medlemmer"
                ), systemImage: "person.3.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CommunityReferenceStyle.ink)
                Spacer()
                NavigationLink {
                    ATHLTHCommunityActiveMembersDirectoryView()
                } label: {
                    Text(ATHLTHLocalization.choose(
                        english: "See all", norwegian: "Se alle"
                    ))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CommunityReferenceStyle.muted)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9))
                        .foregroundStyle(CommunityReferenceStyle.muted)
                }
                .buttonStyle(.plain)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    NavigationLink {
                        if let club = myClub, groups.canManage(club) {
                            CommunityGroupInviteMemberView(group: club)
                        } else {
                            // Non-admins can find people; only club managers
                            // may send membership invitations.
                            SocialHubView(initialTab: .discover)
                        }
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .light))
                                .foregroundStyle(CommunityReferenceStyle.gold)
                                .frame(width: 43, height: 43)
                                .background(CommunityReferenceStyle.canvas, in: Circle())
                            Text(ATHLTHLocalization.choose(
                                english: "Invite", norwegian: "Inviter"
                            ))
                            .font(.system(size: 9))
                            .foregroundStyle(CommunityReferenceStyle.muted)
                        }
                    }
                    .buttonStyle(.plain)

                    ForEach(Array(activeMembers.prefix(12))) { friend in
                        NavigationLink {
                            FriendProfileView(userID: friend.userID)
                        } label: {
                            VStack(spacing: 5) {
                                ATHLTHSocialStatusAvatar(
                                    profile: friend, size: 39
                                )
                                Text(friend.resolvedName.components(separatedBy: " ").first ?? friend.resolvedName)
                                    .font(.system(size: 9))
                                    .foregroundStyle(CommunityReferenceStyle.ink)
                                    .lineLimit(1)
                                    .frame(width: 47)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    if activeMembers.isEmpty {
                        Text(ATHLTHLocalization.choose(
                            english: "No friends sharing active status right now.",
                            norwegian: "Ingen venner deler aktiv status akkurat nå."
                        ))
                        .font(.caption)
                        .foregroundStyle(CommunityReferenceStyle.muted)
                        .frame(minHeight: 43)
                    }
                }
            }
        }
        .padding(12)
        .communityReferenceCard()
    }

    private func invitationBanner(
        _ invite: CommunityGroupInviteRecord
    ) -> some View {
        HStack(alignment: .center, spacing: 9) {
            Image(systemName: "sparkles")
                .foregroundStyle(CommunityReferenceStyle.gold)
                .frame(width: 29, height: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(ATHLTHLocalization.choose(
                    english: "CLUB INVITATION", norwegian: "KLUBBINVITASJON"
                ))
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.3)
                .foregroundStyle(CommunityReferenceStyle.muted)
                Text(ATHLTHLocalization.choose(
                    english: "\(groups.group(for: invite.groupID)?.name ?? "A club") invited you",
                    norwegian: "\(groups.group(for: invite.groupID)?.name ?? "En klubb") har invitert deg"
                ))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CommunityReferenceStyle.ink)
                .lineLimit(2)
                if let inviteError {
                    Text(inviteError)
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
            Button {
                respond(to: invite, accept: false)
            } label: {
                Text(ATHLTHLocalization.choose(
                    english: "Decline", norwegian: "Avslå"
                ))
                .font(.system(size: 10, weight: .medium))
                .frame(minWidth: 49, minHeight: 35)
                .foregroundStyle(CommunityReferenceStyle.muted)
                .background(.white.opacity(0.9), in: Capsule())
            }
            .buttonStyle(.plain)
            Button {
                respond(to: invite, accept: true)
            } label: {
                if respondingToInvite == invite.groupID {
                    ProgressView()
                        .tint(.white)
                        .frame(minWidth: 57, minHeight: 35)
                } else {
                    Text(ATHLTHLocalization.choose(
                        english: "Join", norwegian: "Bli med"
                    ))
                    .font(.system(size: 10, weight: .semibold))
                    .frame(minWidth: 57, minHeight: 35)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(CommunityReferenceStyle.gold, in: Capsule())
        }
        .disabled(respondingToInvite != nil)
        .padding(12)
        .background(
            CommunityReferenceStyle.cream.opacity(0.78),
            in: RoundedRectangle(cornerRadius: 19)
        )
    }

    // MARK: - Shared screenshot controls

    private func cardHeading(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(CommunityReferenceStyle.darkGold)
                .font(.system(size: 13))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CommunityReferenceStyle.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 1)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(CommunityReferenceStyle.muted)
        }
    }

    private func creamButton(_ title: String, symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(CommunityReferenceStyle.darkGold)
        .frame(maxWidth: .infinity, minHeight: 34)
        .background(
            CommunityReferenceStyle.cream,
            in: Capsule()
        )
    }

    private var searchBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(ATHLTHLocalization.choose(
                english: "Search clubs and people",
                norwegian: "Søk etter klubber og personer"
            ), text: $query)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($searchFocused)
            .padding(12)
            .background(CommunityReferenceStyle.canvas, in: RoundedRectangle(cornerRadius: 12))

            Button {
                showCreateClub = true
            } label: {
                Label(ATHLTHLocalization.choose(
                    english: "Create a club", norwegian: "Opprett klubb"
                ), systemImage: "plus.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CommunityReferenceStyle.gold)
                .frame(minHeight: 40)
            }
            .buttonStyle(.plain)

            if query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
                ForEach(Array(social.discoverResults.prefix(3))) { person in
                    NavigationLink {
                        FriendProfileView(userID: person.userID)
                    } label: {
                        Text(person.resolvedName)
                            .font(.subheadline)
                            .foregroundStyle(CommunityReferenceStyle.ink)
                    }
                }
                ForEach(Array(matchingPublicClubs.prefix(4))) { club in
                    NavigationLink {
                        CommunityGroupDetailView(group: club)
                    } label: {
                        Text(club.name)
                            .font(.subheadline)
                            .foregroundStyle(CommunityReferenceStyle.ink)
                    }
                }
            }
        }
        .padding(12)
        .communityReferenceCard()
    }

    private func respond(
        to invitation: CommunityGroupInviteRecord,
        accept: Bool
    ) {
        guard respondingToInvite == nil else { return }
        respondingToInvite = invitation.groupID
        inviteError = nil
        Task {
            let result = await groups.respondToInvite(
                groupID: invitation.groupID,
                accept: accept
            )
            respondingToInvite = nil
            if !result {
                inviteError = ATHLTHLocalization.choose(
                    english: "Could not respond. Try again.",
                    norwegian: "Kunne ikke svare. Prøv igjen."
                )
            }
        }
    }

    @MainActor
    private func refreshContent(force: Bool) async {
        async let a: Void = groups.refresh(force: force)
        async let b: Void = groups.refreshCalendarContent()
        async let c: Void = community.refresh(force: force)
        async let d: Void = messaging.refresh(force: force)
        async let e: Void = weekly.refresh(force: force)
        async let f: Void = force
            ? social.refresh(challengeStore: challenges)
            : social.refreshIfStale(challengeStore: challenges)
        _ = await (a, b, c, d, e, f)
    }
}


/// A privacy-respecting directory for the screenshot's "Active members" row.
/// Online status is *never* inferred from group membership or last activity.
private struct ATHLTHCommunityActiveMembersDirectoryView: View {
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var realtime: ATHLTHRealtimeSocialStore

    private var activeFriends: [SocialProfileCard] {
        social.mutualFollows.filter {
            realtime.isTrainingNow($0.userID) ||
            realtime.isOnline($0.userID)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(ATHLTHLocalization.choose(
                    english: "Active members", norwegian: "Aktive medlemmer"
                ))
                .font(.system(size: 31, weight: .regular, design: .serif))
                .foregroundStyle(CommunityReferenceStyle.ink)

                Text(ATHLTHLocalization.choose(
                    english: "Only mutual followers who have chosen to share their status appear here.",
                    norwegian: "Her vises bare gjensidige følgere som har valgt å dele statusen sin."
                ))
                .font(.subheadline)
                .foregroundStyle(CommunityReferenceStyle.muted)

                if activeFriends.isEmpty {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "No active members are sharing their status now.",
                            norwegian: "Ingen aktive medlemmer deler status akkurat nå."
                        ),
                        systemImage: "person.3"
                    )
                    .font(.subheadline)
                    .foregroundStyle(CommunityReferenceStyle.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .communityReferenceCard()
                } else {
                    ForEach(activeFriends) { member in
                        NavigationLink {
                            FriendProfileView(userID: member.userID)
                        } label: {
                            HStack(spacing: 13) {
                                ATHLTHSocialStatusAvatar(
                                    profile: member, size: 43
                                )
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(member.resolvedName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(CommunityReferenceStyle.ink)
                                    if !member.usernameLabel.isEmpty {
                                        Text(member.usernameLabel)
                                            .font(.caption)
                                            .foregroundStyle(CommunityReferenceStyle.muted)
                                    }
                                }
                                Spacer(minLength: 2)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(CommunityReferenceStyle.gold)
                            }
                            .padding(14)
                            .communityReferenceCard()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(17)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(CommunityReferenceStyle.canvas.ignoresSafeArea())
        .navigationTitle(ATHLTHLocalization.choose(
            english: "Members", norwegian: "Medlemmer"
        ))
        .navigationBarTitleDisplayMode(.inline)
    }
}

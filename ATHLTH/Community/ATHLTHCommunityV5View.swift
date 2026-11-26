import SwiftUI
@preconcurrency import CoreLocation

// MARK: - Fellesskap · native premium 2.0.6 rebuild
// Old Community list and shortcut screens are removed. Club, challenge,
// Arena and RSVP stores remain authoritative and are not deleted.
enum ATHLTHCommunityMainTab: String, CaseIterable, Identifiable {
    case overview, arena, events
    var id: String { rawValue }

    var heroAssetName: String {
        switch self {
        case .overview: "CommunityHero"
        case .arena: "CommunityArenaHero"
        case .events: "CommunityEventsHero"
        }
    }

    var title: String {
        switch self {
        case .overview:
            return ATHLTHLocalization.choose(english: "Overview", norwegian: "Oversikt")
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
    /// TabView may initialize non-selected views. Defer the Community refresh
    /// until its tab is actually foregrounded, keeping its cached UI alive.
    var isActive = true
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

    /// Community has no club-directory destination; Clubs owns its own hub.
    init(initialTab: ATHLTHCommunityMainTab = .overview, isActive: Bool = true) {
        _tab = State(initialValue: initialTab)
        self.isActive = isActive
    }
    @State private var lastBackgroundRefreshAt: Date?
    @State private var lastBackgroundRefreshAccountID: UUID?
    @State private var eventInterest: CommunityInterest = .all

    // Only mutual followers may expose online/training presence, and only
    // when they have opted in. Do not infer status from their membership.
    private var activeMembers: [SocialProfileCard] {
        social.mutualFollows.filter {
            realtime.isOnline($0.userID) ||
            realtime.isTrainingNow($0.userID)
        }
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

    var body: some View {
        NavigationStack {
            GeometryReader { viewport in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        cover
                            .padding(.horizontal, -14)

                        VStack(alignment: .leading, spacing: 12) {
                            tabs
                            switch tab {
                            case .overview:
                                overview
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
                    // A vertical ScrollView does not impose a finite content
                    // width. Propose the visible width explicitly so an
                    // aspect-fill image cannot make every tab scroll sideways.
                    .frame(width: min(viewport.size.width, 760))
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .ignoresSafeArea(.container, edges: .top)
                .background(CommunityReferenceStyle.canvas.ignoresSafeArea())
            }
            .toolbar(.hidden, for: .navigationBar)
            .task(id: "\(isActive)-\(session.profile.userID.uuidString)") {
                guard isActive else { return }
                // Rapid tab changes should never restart six backend refreshes.
                // Explicit pull-to-refresh still bypasses this foreground gate.
                let accountID = session.profile.userID
                if lastBackgroundRefreshAccountID == accountID,
                   let lastBackgroundRefreshAt,
                   Date().timeIntervalSince(lastBackgroundRefreshAt) < 90 {
                    return
                }
                let signpost = ATHLTHPerformance.begin("CommunityTabRefresh")
                await refreshContent(force: false)
                ATHLTHPerformance.end("CommunityTabRefresh", id: signpost)
                guard !Task.isCancelled else { return }
                lastBackgroundRefreshAccountID = accountID
                lastBackgroundRefreshAt = Date()
            }
            .refreshable {
                await refreshContent(force: true)
                lastBackgroundRefreshAccountID = session.profile.userID
                lastBackgroundRefreshAt = Date()
            }
        }
    }

    // MARK: - Hero images: one per Community destination.

    private var cover: some View {
        ZStack(alignment: .topLeading) {
            GeometryReader { geo in
                Image(tab.heroAssetName)
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

    // MARK: - Community sections

    private var overview: some View {
        VStack(spacing: 12) {
            weeklyChallengeSection
            // Keep Train Together discoverable without adding a fifth tab
            // or duplicating the existing marketplace and creation flows.
            trainTogetherOverviewCard
            arenaDuelCard
            nextGatheringCard
            membersStrip
        }
    }

    /// Compact shortcut between the weekly challenge and the club / Arena
    /// cards. The existing marketplace owns discovery and creation state.
    private var trainTogetherOverviewCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 11) {
                Image(systemName: "figure.run")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(CommunityReferenceStyle.darkGold)
                    .frame(width: 38, height: 38)
                    .background(
                        CommunityReferenceStyle.cream,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(tr("Train Together", "Tren sammen"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(CommunityReferenceStyle.ink)
                        let pendingInvites = social.workoutInvites.filter {
                            $0.participant.state == .invited
                        }.count
                        if pendingInvites > 0 {
                            Text("\(pendingInvites)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(CommunityReferenceStyle.darkGold)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(CommunityReferenceStyle.cream, in: Capsule())
                                .accessibilityLabel(tr(
                                    "\(pendingInvites) workout invitations",
                                    "\(pendingInvites) treningsinvitasjoner"
                                ))
                        }
                    }
                    Text(tr(
                        "Find a shared workout or invite other athletes.",
                        "Finn en fellesøkt eller inviter andre til å trene."
                    ))
                    .font(.caption)
                    .foregroundStyle(CommunityReferenceStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 9) {
                NavigationLink {
                    TrainTogetherMarketplaceView()
                } label: {
                    Label(tr("Find workouts", "Finn økter"), systemImage: "magnifyingglass")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CommunityReferenceStyle.darkGold)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(CommunityReferenceStyle.cream, in: Capsule())
                }
                .buttonStyle(.plain)

                NavigationLink {
                    TrainTogetherMarketplaceView(initialCreationMode: .physical)
                } label: {
                    Label(tr("Create workout", "Opprett økt"), systemImage: "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(
                            CommunityReferenceStyle.darkGold,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(13)
        .communityReferenceCard()
    }

    // The weekly challenge lives once, at the top of Overview.
    // Keep its existing progress and detail navigation unchanged.
    private var weeklyChallengeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            weeklyChallengeHighlight
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                CommunityFriendsVsFriendsDetailView(
                    currentUserID: session.profile.userID,
                    currentDisplayName: session.profile.displayName,
                    currentAvatarURL: session.profile.avatarURL,
                    friends: social.mutualFollows
                )
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
        title: String, subtitle: String, icon: String, compact: Bool = false
    ) -> some View {
        VStack(spacing: compact ? 4 : 6) {
            Image(systemName: icon)
                .font(.system(size: compact ? 17 : 19, weight: .medium))
                .foregroundStyle(CommunityReferenceStyle.darkGold)
                .frame(width: compact ? 31 : 38, height: compact ? 31 : 38)
                .background(CommunityReferenceStyle.cream, in: Circle())
            Text(title)
                .font(.system(size: compact ? 11.5 : 12, weight: .semibold))
                .foregroundStyle(CommunityReferenceStyle.ink)
            Text(subtitle)
                .font(.system(size: compact ? 9 : 10))
                .foregroundStyle(CommunityReferenceStyle.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 77 : 97)
        .padding(compact ? 6 : 8)
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
                GeometryReader { imageArea in
                    ZStack(alignment: .bottomLeading) {
                        Image("GoalSprint")
                            .resizable()
                            .scaledToFill()
                            .frame(
                                width: imageArea.size.width,
                                height: imageArea.size.height
                            )
                            .clipped()
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.65)],
                            startPoint: .center, endPoint: .bottom
                        )
                        Text(tr(
                            "Your next duel starts here",
                            "Din neste duell starter her"
                        ))
                        .font(.system(size: 21, weight: .medium, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .padding(16)
                    }
                    .frame(
                        width: imageArea.size.width,
                        height: imageArea.size.height
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 15))
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

    private var weeklyChallengeHighlight: some View {
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
                        // Long titles must wrap within the remaining width
                        // beside the fixed-size image.
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                    CommunityFriendsVsFriendsDetailView(
                    currentUserID: session.profile.userID,
                    currentDisplayName: session.profile.displayName,
                    currentAvatarURL: session.profile.avatarURL,
                    friends: social.mutualFollows
                )
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
                        SocialHubView(initialTab: .discover)
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


// MARK: - Standalone Clubs hub

/// One directory for both sidebar destinations. Existing club detail,
/// membership, invitations and creation flows remain authoritative.
struct ATHLTHClubsHubView: View {
    @EnvironmentObject private var groups: CommunityGroupStore
    @EnvironmentObject private var session: AppSessionStore
    @State private var showCreate = false
    @State private var discovery = false
    @State private var query = ""
    @State private var place = ""
    @State private var interest: CommunityInterest = .all
    @State private var busyGroup: UUID?
    @State private var notice: String?
    @State private var searchLoading = false
    @EnvironmentObject private var social: SocialStore
    @StateObject private var locationStore = ChallengeLocationStore()
    @State private var pinnedClubID: UUID?
    @State private var preferredInterest: CommunityInterest = .all
    @State private var showingAdministration = false
    @State private var invitationClub: CommunityGroupRecord?
    @State private var adminRequests: [CommunityGroupJoinRequestRecord] = []
    @State private var loadingRequests = false
    @State private var requestError: String?
    @State private var distances: [UUID: Double] = [:]
    @State private var locating = false
    @State private var locationNotice: String?

    private var preferenceKey: String { "athlth.clubs.hub." + session.profile.userID.uuidString }

    private func reloadPreferences() {
        pinnedClubID = UserDefaults.standard.string(forKey: preferenceKey + ".pinned").flatMap(UUID.init(uuidString:))
        preferredInterest = CommunityInterest(rawValue: UserDefaults.standard.string(forKey: preferenceKey + ".interest") ?? "") ?? .all
    }

    private func togglePinned(_ club: CommunityGroupRecord) {
        guard memberships.contains(where: { $0.id == club.id }) else { return }
        pinnedClubID = pinnedClubID == club.id ? nil : club.id
        UserDefaults.standard.set(pinnedClubID?.uuidString, forKey: preferenceKey + ".pinned")
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var memberships: [CommunityGroupRecord] {
        guard session.signedIn else { return [] }
        let account = session.profile.userID
        return groups.groups.filter {
            groups.joinedGroupIDs.contains($0.id) || $0.creatorID == account
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func manages(_ club: CommunityGroupRecord) -> Bool {
        ATHLTHClubHubPolicy.manages(club, memberships: groups.ownMemberships,
                                    account: session.profile.userID)
    }

    private var managed: [CommunityGroupRecord] { memberships.filter(manages) }
    private var joined: [CommunityGroupRecord] { memberships.filter { !manages($0) } }
    private var favorite: CommunityGroupRecord? { memberships.first { $0.id == pinnedClubID } }
    private var activity: [CommunityGroupActivityRecord] {
        let ids = Set(memberships.map(\.id))
        return Array(groups.communityActivity.filter { ids.contains($0.groupID) }
            .sorted { $0.createdAt > $1.createdAt }.prefix(5))
    }

    // The public club creator is visible in the directory. Private membership
    // records are never fetched or inferred for recommendations.
    private var friendCreators: Set<UUID> {
        guard social.currentUserID == session.profile.userID else { return [] }
        return Set(social.mutualFollows.map(\.userID))
    }

    private var invites: [CommunityGroupInviteRecord] {
        groups.ownInvites.filter {
            $0.userID == session.profile.userID && $0.status == "pending"
        }
    }

    private var requests: [CommunityGroupJoinRequestRecord] {
        groups.ownJoinRequests.filter {
            $0.userID == session.profile.userID && $0.status == "pending"
        }
    }

    private var upcomingEvents: [CommunityGroupEventRecord] {
        guard groups.homeUpcomingEventsAccountID == session.profile.userID else { return [] }
        let ids = Set(memberships.map(\.id))
        return Array(groups.homeUpcomingEvents.filter {
            ids.contains($0.groupID) && $0.startsAt >= Date() &&
            $0.status != "draft" && $0.status != "cancelled"
        }.sorted { $0.startsAt < $1.startsAt }.prefix(3))
    }

    private var searchTerm: String {
        let local = place.trimmingCharacters(in: .whitespacesAndNewlines)
        return local.isEmpty ? query.trimmingCharacters(in: .whitespacesAndNewlines) : local
    }

    private var results: [CommunityGroupRecord] {
        guard session.signedIn else { return [] }
        let matches = ATHLTHClubHubPolicy.discovery(
            groups.groups + groups.searchResults,
            excluded: Set(memberships.map(\.id) + invites.map(\.groupID)),
            query: query, place: place, interest: interest
        )
        return ATHLTHClubHubPolicy.ranked(matches, preferred: preferredInterest,
                                         friendCreators: friendCreators, distances: distances)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                Picker(tr("Club section", "Klubbseksjon"), selection: $discovery) {
                    Text(tr("My clubs", "Mine klubber")).tag(false)
                    Text(tr("Discover", "Utforsk")).tag(true)
                }
                .pickerStyle(.segmented)

                if discovery {
                    discoveryPage
                } else {
                    personalPage
                }
                if let error = groups.errorMessage, !error.isEmpty {
                    Text(error).font(.caption).foregroundStyle(CommunityReferenceStyle.muted)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(CommunityReferenceStyle.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showCreate, onDismiss: {
            Task { await groups.refresh(force: true) }
        }) {
            CommunityGroupCreateView()
        }
        .alert(tr("Clubs", "Klubber"), isPresented: Binding(
            get: { notice != nil }, set: { if !$0 { notice = nil } }
        )) {
            Button("OK", role: .cancel) { notice = nil }
        } message: { Text(notice ?? "") }
        .sheet(item: $invitationClub) { club in
            CommunityGroupInviteMemberView(group: club)
        }
        .sheet(isPresented: $showingAdministration) {
            NavigationStack {
                administrationPage
                    .navigationTitle(tr("Administration", "Administrasjon"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(tr("Done", "Ferdig")) { showingAdministration = false }
                        }
                    }
            }
        }
        .task(id: session.profile.userID) {
            reloadPreferences()
            await groups.refresh(force: false)
            guard !Task.isCancelled else { return }
            await groups.refreshRecentChatActivity()
            await groups.refreshHomeUpcomingEvents()
        }
        .task(id: managed.map(\.id)) { await reloadAdminRequests() }
        .refreshable {
            await groups.refresh(force: true)
            if discovery && searchTerm.count >= 2 { await groups.search(searchTerm) }
            await groups.refreshRecentChatActivity(force: true)
            await groups.refreshHomeUpcomingEvents(force: true)
            await reloadAdminRequests()
        }
        .task(id: "\(session.profile.userID)-\(discovery)-\(searchTerm)") {
            guard discovery, searchTerm.count >= 2 else {
                searchLoading = false
                groups.clearSearch()
                return
            }
            searchLoading = true
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            guard !Task.isCancelled else { return }
            await groups.search(searchTerm)
            if !Task.isCancelled { searchLoading = false }
        }
        .onChange(of: session.profile.userID) { _, _ in
            query = ""; place = ""; interest = .all; discovery = false
            pinnedClubID = nil; preferredInterest = .all
            distances = [:]; locationNotice = nil; adminRequests = []
            showingAdministration = false; invitationClub = nil
            reloadPreferences()
        }
        .accessibilityIdentifier("athlth-standalone-clubs-hub")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(tr("TRAIN TOGETHER", "TREN SAMMEN"))
                        .font(.caption2.weight(.semibold)).tracking(2)
                        .foregroundStyle(CommunityReferenceStyle.darkGold)
                    Text(tr("Clubs", "Klubber"))
                        .font(.system(size: 37, design: .serif))
                        .foregroundStyle(CommunityReferenceStyle.ink)
                    Text(tr("Find your people. Build something together.",
                            "Finn ditt treningsfellesskap. Bygg noe sammen."))
                        .font(.subheadline)
                        .foregroundStyle(CommunityReferenceStyle.muted)
                }
                Spacer(minLength: 8)
                Button { showCreate = true } label: {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(CommunityReferenceStyle.darkGold, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("Create club", "Opprett klubb"))
                .accessibilityIdentifier("athlth-create-club")
            }
            HStack(spacing: 8) {
                summaryMetric(memberships.count, tr("Memberships", "Medlemskap"), "person.3")
                summaryMetric(managed.count, tr("Managed", "Administrerer"), "person.badge.key")
                summaryMetric(invites.count, tr("Invitations", "Invitasjoner"), "envelope")
            }
        }
        .padding(16)
        .communityReferenceCard()
    }

    private func summaryMetric(_ count: Int, _ label: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(CommunityReferenceStyle.gold)
            Text("\(count)").font(.title2.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(CommunityReferenceStyle.muted)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .foregroundStyle(CommunityReferenceStyle.ink)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .padding(8)
        .background(CommunityReferenceStyle.canvas, in: RoundedRectangle(cornerRadius: 13))
    }

    private var personalPage: some View {
        VStack(alignment: .leading, spacing: 15) {
            if !invites.isEmpty {
                heading(tr("Invitations", "Invitasjoner"), "envelope")
                ForEach(invites, id: \.groupID) { invitation in
                    invitationRow(invitation)
                }
            }
            if !requests.isEmpty {
                heading(tr("Pending membership requests", "Ventende medlemsforespørsler"), "clock")
                ForEach(requests, id: \.groupID) { request in
                    if let club = groups.group(for: request.groupID) {
                        clubRow(club, status: tr("Awaiting approval", "Venter på godkjenning"))
                    }
                }
            }
            if let favorite {
                heading(tr("Favorite club", "Favorittklubb"), "star.fill")
                clubGrid([favorite], isManagement: manages(favorite))
            }
            if !managed.isEmpty {
                Button { showingAdministration = true } label: {
                    HStack {
                        Label(tr("Administration", "Administrasjon"), systemImage: "person.badge.key")
                            .font(.headline)
                        Spacer()
                        if !adminRequests.isEmpty {
                            Text("\(adminRequests.count)").monospacedDigit()
                        }
                        Image(systemName: "chevron.right")
                    }
                    .foregroundStyle(CommunityReferenceStyle.darkGold)
                    .padding(15).communityReferenceCard()
                }.buttonStyle(.plain)
            }
            heading(tr("Clubs I manage", "Klubber jeg administrerer"), "person.badge.key")
            if managed.isEmpty {
                empty(tr("No clubs to manage", "Ingen klubber å administrere"),
                      tr("Create a club for your training friends.", "Opprett en klubb for treningsvennene dine."))
                Button { showCreate = true } label: {
                    actionLabel(tr("Create club", "Opprett klubb"), "plus")
                }.buttonStyle(.plain)
            } else {
                clubGrid(managed.filter { $0.id != favorite?.id }, isManagement: true)
            }

            heading(tr("My memberships", "Mine medlemskap"), "person.3")
            if joined.isEmpty {
                empty(tr("No other memberships yet", "Ingen andre medlemskap ennå"),
                      tr("Discover a club that suits you.", "Utforsk klubber som passer deg."))
            } else {
                clubGrid(joined.filter { $0.id != favorite?.id }, isManagement: false)
            }
            if !activity.isEmpty {
                heading(tr("Latest club activity", "Siste klubbaktivitet"), "bolt")
                ForEach(activity) { item in
                    if let club = groups.group(for: item.groupID) {
                        NavigationLink {
                            CommunityGroupDetailView(group: club)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(club.name).font(.caption.weight(.semibold))
                                    .foregroundStyle(CommunityReferenceStyle.darkGold)
                                Text(item.headline).font(.subheadline.weight(.medium))
                                    .foregroundStyle(CommunityReferenceStyle.ink)
                                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2).foregroundStyle(CommunityReferenceStyle.muted)
                            }.padding(12).communityReferenceCard()
                        }.buttonStyle(.plain)
                    }
                }
            }
            if !upcomingEvents.isEmpty {
                heading(tr("Upcoming club events", "Kommende klubbarrangementer"), "calendar")
                ForEach(upcomingEvents) { event in
                    if let club = groups.group(for: event.groupID) {
                        NavigationLink {
                            CommunityGroupEventDetailView(group: club, event: event)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(event.title).font(.headline).foregroundStyle(CommunityReferenceStyle.ink)
                                Text(club.name).font(.caption).foregroundStyle(CommunityReferenceStyle.muted)
                                Text(event.startsAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(CommunityReferenceStyle.darkGold)
                            }.padding(12).communityReferenceCard()
                        }.buttonStyle(.plain)
                    }
                }
            }
            Button { discovery = true } label: {
                actionLabel(tr("Find clubs", "Finn klubber"), "magnifyingglass")
            }.buttonStyle(.plain)
        }
    }

    private func clubGrid(_ clubs: [CommunityGroupRecord], isManagement: Bool) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 12)], spacing: 12) {
            ForEach(clubs) { club in
                VStack(alignment: .leading, spacing: 9) {
                    clubRow(club, status: isManagement
                        ? (club.creatorID == session.profile.userID
                            ? tr("Owner", "Eier") : tr("Admin", "Administrator"))
                        : tr("Member", "Medlem"))
                    HStack(spacing: 8) {
                        Button { togglePinned(club) } label: {
                            actionLabel(pinnedClubID == club.id ? tr("Pinned", "Festet") : tr("Pin", "Fest"),
                                        pinnedClubID == club.id ? "star.fill" : "star")
                        }.buttonStyle(.plain)
                        if isManagement {
                            Button { invitationClub = club } label: {
                                actionLabel(tr("Invite", "Inviter"), "person.badge.plus")
                            }.buttonStyle(.plain)
                        }
                    }
                    if isManagement || groups.unreadClubGroupIDs.contains(club.id) {
                        HStack(spacing: 8) {
                            if isManagement {
                                NavigationLink {
                                    CommunityGroupMembersView(group: club, managementMode: true)
                                } label: {
                                    actionLabel(tr("Members", "Medlemmer"), "person.2")
                                }.buttonStyle(.plain)
                            }
                            if groups.unreadClubGroupIDs.contains(club.id) {
                                NavigationLink {
                                    CommunityGroupDetailView(group: club, initialTab: .chat)
                                } label: {
                                    actionLabel(tr("Unread chat", "Ulest chat"), "message.badge")
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private var discoveryPage: some View {
        VStack(alignment: .leading, spacing: 13) {
            heading(tr("Discover clubs", "Oppdag klubber"), "magnifyingglass")
            VStack(spacing: 9) {
                searchField(tr("Search name or interest", "Søk på navn eller interesse"),
                            symbol: "magnifyingglass", text: $query)
                searchField(tr("City or area", "By eller nærområde"),
                            symbol: "mappin.and.ellipse", text: $place)
                Text(tr("Search by a club’s registered location. No GPS access needed.",
                        "Søk etter klubbens registrerte sted. Krever ikke posisjonstilgang."))
                    .font(.caption).foregroundStyle(CommunityReferenceStyle.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12).communityReferenceCard()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(CommunityInterest.allCases) { item in
                        Button { interest = item } label: {
                            Label(item.title, systemImage: item.symbol)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12).frame(minHeight: 40)
                                .foregroundStyle(interest == item ? Color.white : CommunityReferenceStyle.darkGold)
                                .background(interest == item ? CommunityReferenceStyle.darkGold : CommunityReferenceStyle.cream,
                                            in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(interest == item ? .isSelected : [])
                    }
                }
            }
            VStack(alignment: .leading, spacing: 9) {
                Picker(tr("Preferred training interest", "Foretrukket treningsinteresse"), selection: $preferredInterest) {
                    ForEach(CommunityInterest.allCases) { item in Text(item.title).tag(item) }
                }
                .tint(CommunityReferenceStyle.darkGold)
                .onChange(of: preferredInterest) { _, value in
                    UserDefaults.standard.set(value.rawValue, forKey: preferenceKey + ".interest")
                }
                Button {
                    Task { await locateNearbyClubs() }
                } label: {
                    actionLabel(locating ? tr("Finding clubs…", "Finner klubber…") :
                                    tr("Sort by nearby", "Sorter etter nærhet"), "location")
                }.buttonStyle(.plain).disabled(locating)
                if let locationNotice {
                    Text(locationNotice).font(.caption).foregroundStyle(CommunityReferenceStyle.muted)
                }
            }.padding(12).communityReferenceCard()
            heading(place.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? tr("Discover public clubs", "Utforsk offentlige klubber")
                    : tr("Clubs in your area", "Klubber i området"), "location")
            if searchLoading || groups.isLoading {
                ProgressView().frame(maxWidth: .infinity)
            }
            if results.isEmpty && !searchLoading && !groups.isLoading {
                empty(tr("No matching clubs", "Ingen klubber funnet"),
                      tr("Try a different location, interest or name.", "Prøv et annet sted, en annen interesse eller et annet navn."))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 12)], spacing: 12) {
                ForEach(results) { club in
                    VStack(spacing: 8) {
                        clubRow(club, status: club.joinMode == "approval"
                                ? tr("Approval required", "Krever godkjenning")
                                : tr("Public club", "Offentlig klubb"))
                        if let km = distances[club.id] {
                            Text(tr("Approx. \(Int(km.rounded())) km to registered place",
                                    "Ca. \(Int(km.rounded())) km til registrert sted"))
                                .font(.caption).foregroundStyle(CommunityReferenceStyle.muted)
                        }
                        if friendCreators.contains(club.creatorID) {
                            Label(tr("Created by a mutual friend", "Opprettet av en gjensidig venn"),
                                  systemImage: "person.2")
                                .font(.caption).foregroundStyle(CommunityReferenceStyle.darkGold)
                        }
                        let pending = requests.contains { $0.groupID == club.id }
                        Button {
                            join(club)
                        } label: {
                            if busyGroup == club.id {
                                ProgressView().frame(maxWidth: .infinity, minHeight: 44)
                            } else {
                                actionLabel(pending ? tr("Request sent", "Forespørsel sendt")
                                    : club.joinMode == "approval"
                                        ? tr("Request membership", "Søk om medlemskap")
                                        : tr("Join club", "Bli med"), "person.badge.plus")
                            }
                        }.buttonStyle(.plain).disabled(pending || busyGroup != nil)
                    }
                }
            }
            if groups.canLoadMoreGroups {
                Button {
                    Task { await groups.loadMoreGroups() }
                } label: {
                    actionLabel(tr("Load more clubs", "Vis flere klubber"), "arrow.down")
                }
                .buttonStyle(.plain)
                .disabled(groups.isLoadingMoreGroups || groups.isLoading)
            }
        }
    }

    private var administrationPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                heading(tr("Incoming requests", "Innkommende medlemsforespørsler"), "person.badge.plus")
                if loadingRequests { ProgressView() }
                if let requestError {
                    Text(requestError).font(.caption).foregroundStyle(CommunityReferenceStyle.muted)
                    Button(tr("Retry", "Prøv igjen")) { Task { await reloadAdminRequests() } }
                } else if adminRequests.isEmpty && !loadingRequests {
                    empty(tr("No pending requests", "Ingen ventende forespørsler"),
                          tr("New membership requests appear here.", "Nye medlemsforespørsler vises her."))
                }
                ForEach(adminRequests, id: \.self) { request in
                    if let club = managed.first(where: { $0.id == request.groupID }) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(club.name).font(.caption.weight(.semibold))
                                .foregroundStyle(CommunityReferenceStyle.darkGold)
                            if let profile = groups.profileCard(for: request.userID) {
                                Text(profile.resolvedName).font(.headline)
                                HStack {
                                    Button { answer(request, accept: false) } label: {
                                        actionLabel(tr("Decline", "Avslå"), "xmark")
                                    }.buttonStyle(.plain)
                                    Button { answer(request, accept: true) } label: {
                                        actionLabel(tr("Approve", "Godkjenn"), "checkmark")
                                    }.buttonStyle(.plain)
                                }.disabled(busyGroup != nil)
                            } else {
                                NavigationLink {
                                    CommunityGroupMembersView(group: club, managementMode: true)
                                } label: { actionLabel(tr("Review request", "Se forespørsel"), "person.2") }
                            }
                        }.padding(12).communityReferenceCard()
                    }
                }
                heading(tr("Manage clubs", "Administrer klubber"), "gearshape")
                ForEach(managed) { club in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(club.name).font(.headline)
                        NavigationLink {
                            CommunityGroupSettingsView(group: club)
                        } label: { actionLabel(tr("Club settings", "Klubbinnstillinger"), "gearshape") }
                        NavigationLink {
                            CommunityGroupMembersView(group: club, managementMode: true)
                        } label: { actionLabel(tr("Manage members", "Administrer medlemmer"), "person.2") }
                        NavigationLink {
                            CommunityGroupInviteMemberView(group: club)
                        } label: { actionLabel(tr("Invite people", "Inviter personer"), "person.badge.plus") }
                    }.padding(12).communityReferenceCard()
                }
            }.padding(18)
        }
        .background(CommunityReferenceStyle.canvas)
        .refreshable { await reloadAdminRequests() }
    }

    private func reloadAdminRequests() async {
        let account = session.profile.userID
        loadingRequests = true
        defer { if session.profile.userID == account { loadingRequests = false } }
        do {
            let rows = try await groups.loadHubJoinRequests(groupIDs: managed.map(\.id))
            guard !Task.isCancelled, session.profile.userID == account else { return }
            adminRequests = rows; requestError = nil
        } catch {
            guard !Task.isCancelled, session.profile.userID == account else { return }
            requestError = tr("Could not load membership requests.", "Kunne ikke hente medlemsforespørsler.")
        }
    }

    private func answer(_ request: CommunityGroupJoinRequestRecord, accept: Bool) {
        guard busyGroup == nil, managed.contains(where: { $0.id == request.groupID }) else { return }
        busyGroup = request.groupID
        let account = session.profile.userID
        Task {
            let success = await groups.respondToJoinRequest(groupID: request.groupID,
                                                              userID: request.userID, accept: accept)
            guard session.profile.userID == account else { return }
            busyGroup = nil
            if success { await reloadAdminRequests() }
            else { requestError = tr("Could not respond. Try again.", "Kunne ikke svare. Prøv igjen.") }
        }
    }

    // Only requested on explicit tap. Coordinates remain local; the geocoder
    // receives public registered place names, not a member's GPS location.
    private func locateNearbyClubs() async {
        guard !locating else { return }
        locating = true
        let account = session.profile.userID
        defer { locating = false }
        guard let origin = await locationStore.requestCurrentLocation(),
              session.profile.userID == account else {
            locationNotice = tr("Location unavailable. Search by city instead.",
                                "Posisjon utilgjengelig. Søk etter by i stedet.")
            return
        }
        let candidates = Array(results.prefix(20))
        let geocoder = CLGeocoder()
        var byPlace: [String: CLLocation] = [:]
        var attempted = Set<String>()
        var measured: [UUID: Double] = [:]
        for club in candidates {
            guard !Task.isCancelled, session.profile.userID == account else { return }
            let name = club.locationName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            if !attempted.contains(name), attempted.count < 10 {
                attempted.insert(name)
                if let matches = try? await geocoder.geocodeAddressString(name),
                   matches.count == 1, let point = matches.first?.location {
                    byPlace[name] = point
                }
            }
            if let point = byPlace[name] {
                measured[club.id] = origin.distance(from: point) / 1_000
            }
        }
        guard session.profile.userID == account else { return }
        distances = measured
        locationNotice = measured.isEmpty
            ? tr("No unambiguous registered locations found.", "Fant ingen entydige registrerte steder.")
            : tr("Approximate distances for the first clubs with known places. Not exact club addresses.",
                 "Omtrentlige avstander for de første klubbene med kjente steder. Ikke eksakte klubbadresser.")
    }

    private func searchField(_ placeholder: String, symbol: String, text: Binding<String>) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).foregroundStyle(CommunityReferenceStyle.gold)
            TextField(placeholder, text: text).autocorrectionDisabled()
            if !text.wrappedValue.isEmpty {
                Button { text.wrappedValue = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(CommunityReferenceStyle.muted)
                }.buttonStyle(.plain)
            }
        }
        .padding(11)
        .background(CommunityReferenceStyle.canvas, in: RoundedRectangle(cornerRadius: 12))
    }

    private func clubRow(_ club: CommunityGroupRecord, status: String) -> some View {
        NavigationLink {
            CommunityGroupDetailView(group: club)
        } label: {
            VStack(alignment: .leading, spacing: 11) {
                ATHLTHArtworkImage(reference: club.headerImageURL ?? club.imageURL,
                                   fallbackAssetName: "CommunityClubsHero", maxPixelSize: 500)
                    .athlthBoundedFill()
                    .frame(height: 96)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(status).font(.caption.weight(.semibold))
                            .foregroundStyle(CommunityReferenceStyle.darkGold)
                        Text(club.name).font(.headline)
                            .foregroundStyle(CommunityReferenceStyle.ink)
                        if !club.locationName.isEmpty {
                            Label(club.locationName, systemImage: "mappin")
                                .font(.caption).foregroundStyle(CommunityReferenceStyle.muted)
                        }
                        if !club.summary.isEmpty {
                            Text(club.summary).font(.caption)
                                .foregroundStyle(CommunityReferenceStyle.muted).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(CommunityReferenceStyle.gold)
                }
            }
            .padding(12).communityReferenceCard()
        }.buttonStyle(.plain)
    }

    private func invitationRow(_ invitation: CommunityGroupInviteRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(groups.group(for: invitation.groupID)?.name ?? tr("Club invitation", "Klubbinvitasjon"))
                .font(.headline).foregroundStyle(CommunityReferenceStyle.ink)
            HStack {
                Button { respond(invitation, accept: false) } label: {
                    actionLabel(tr("Decline", "Avslå"), "xmark")
                }.buttonStyle(.plain)
                Button { respond(invitation, accept: true) } label: {
                    actionLabel(tr("Accept", "Godta"), "checkmark")
                }.buttonStyle(.plain)
            }.disabled(busyGroup != nil)
        }
        .padding(12).communityReferenceCard()
    }

    private func heading(_ title: String, _ icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline).foregroundStyle(CommunityReferenceStyle.ink)
    }

    private func actionLabel(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(CommunityReferenceStyle.darkGold)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(CommunityReferenceStyle.cream, in: RoundedRectangle(cornerRadius: 13))
    }

    private func empty(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(CommunityReferenceStyle.ink)
            Text(detail).font(.caption).foregroundStyle(CommunityReferenceStyle.muted)
        }.padding(15).communityReferenceCard()
    }

    private func join(_ club: CommunityGroupRecord) {
        guard busyGroup == nil else { return }
        busyGroup = club.id
        Task {
            let result = await groups.requestJoin(club)
            busyGroup = nil
            switch result {
            case "joined": notice = tr("You joined the club.", "Du er nå medlem av klubben.")
            case "error", "unavailable":
                notice = groups.errorMessage ?? tr("Could not join. Try again.", "Kunne ikke bli med. Prøv igjen.")
            default: notice = tr("Membership request sent.", "Medlemsforespørsel sendt.")
            }
        }
    }

    private func respond(_ invitation: CommunityGroupInviteRecord, accept: Bool) {
        guard busyGroup == nil else { return }
        busyGroup = invitation.groupID
        Task {
            let ok = await groups.respondToInvite(groupID: invitation.groupID, accept: accept)
            busyGroup = nil
            if !ok { notice = groups.errorMessage ?? tr("Could not respond.", "Kunne ikke svare på invitasjonen.") }
        }
    }
}

enum ATHLTHClubHubPolicy {
    static func ranked(_ clubs: [CommunityGroupRecord], preferred: CommunityInterest,
                       friendCreators: Set<UUID>, distances: [UUID: Double]) -> [CommunityGroupRecord] {
        clubs.sorted { lhs, rhs in
            if !distances.isEmpty {
                let a = distances[lhs.id] ?? .infinity, b = distances[rhs.id] ?? .infinity
                if a != b { return a < b }
            }
            func score(_ club: CommunityGroupRecord) -> Int {
                (preferred != .all && preferred.matchesClub(club) ? 2 : 0) +
                    (friendCreators.contains(club.creatorID) ? 1 : 0)
            }
            let a = score(lhs), b = score(rhs)
            if a != b { return a > b }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    static func manages(_ club: CommunityGroupRecord, memberships: [CommunityGroupMemberRecord],
                        account: UUID) -> Bool {
        club.creatorID == account || memberships.contains {
            $0.userID == account && $0.groupID == club.id && ["owner", "admin"].contains($0.role)
        }
    }

    static func discovery(_ clubs: [CommunityGroupRecord], excluded: Set<UUID>,
                          query: String, place: String, interest: CommunityInterest) -> [CommunityGroupRecord] {
        var seen = Set<UUID>()
        return clubs.filter { club in
            club.visibility == "public" && !excluded.contains(club.id) &&
            seen.insert(club.id).inserted &&
            ATHLTHCommunityDiscoveryPolicy.matches(query, in: [club.name, club.summary, club.locationName]) &&
            ATHLTHCommunityDiscoveryPolicy.matches(place, in: [club.locationName]) &&
            interest.matchesClub(club)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

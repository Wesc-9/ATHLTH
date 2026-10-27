import SwiftUI

// MARK: - ATHLTH Community 2026
// Entirely new editorial presentation. The legacy V4 feed, discovery cards
// and four-shortcut dashboard are not rendered by this entry point.
// Existing stores, permissions, server-backed membership and competitions
// remain unchanged.
enum ATHLTHCommunityMainTab: String, CaseIterable, Identifiable {
    case overview, arena, clubs
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return ATHLTHLocalization.choose(english: "Overview", norwegian: "Oversikt")
        case .arena: return "Arena"
        case .clubs: return ATHLTHLocalization.choose(english: "Clubs", norwegian: "Klubber")
        }
    }
}

private enum ATHLTHCommunityEditorial {
    static let canvas = ATHLTHTrainDesign.canvas
    static let paper = ATHLTHTrainDesign.paper
    static let ink = ATHLTHTrainDesign.ink
    static let secondary = ATHLTHTrainDesign.secondary
    static let gold = ATHLTHTrainDesign.bronze
    static let rule = ATHLTHTrainDesign.rule

    static func heading(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 20, weight: .semibold, design: .serif))
            .foregroundStyle(ink)
    }
}

struct ATHLTHCommunityV5View: View {
    @EnvironmentObject private var groups: CommunityGroupStore
    @EnvironmentObject private var community: CommunityEventStore
    @EnvironmentObject private var officialChallenges: OfficialWeeklyChallengeStore
    @EnvironmentObject private var challenges: ChallengeStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var messaging: MessagingStore
    @EnvironmentObject private var session: AppSessionStore

    @State private var tab: ATHLTHCommunityMainTab = .clubs
    @State private var showCreate = false
    @State private var showSearch = false
    @State private var query = ""
    @State private var showAllRecommendations = false
    @State private var joiningGroupIDs: Set<UUID> = []
    @State private var joinMessage: String?

    private var pendingInbox: Int {
        messaging.unreadCount + messaging.messageRequestCount
    }

    private var publicClubs: [CommunityGroupRecord] {
        let source = query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
            ? groups.groups + groups.searchResults
            : groups.groups
        var seen = Set<UUID>()
        return source.filter { group in
            seen.insert(group.id).inserted &&
            group.visibility == "public" &&
            !groups.joinedGroupIDs.contains(group.id) &&
            groups.pendingInvite(for: group.id) == nil &&
            ATHLTHCommunityDiscoveryPolicy.matches(
                query,
                in: [group.name, group.locationName, group.summary]
            )
        }
    }

    private var recommendedClubs: [CommunityGroupRecord] {
        showAllRecommendations ? publicClubs : Array(publicClubs.prefix(3))
    }

    private var upcomingSessions: [CommunityGroupEventRecord] {
        groups.calendarEvents
            .filter { item in
                item.status != "cancelled" &&
                item.startsAt >= Date() &&
                groups.joinedGroupIDs.contains(item.groupID)
            }
            .sorted { $0.startsAt < $1.startsAt }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    header
                    tabSelector

                    if showSearch {
                        searchField
                    }

                    if let joinMessage {
                        Text(joinMessage)
                            .font(.caption)
                            .foregroundStyle(ATHLTHCommunityEditorial.secondary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .communityEditorialCard()
                    }

                    switch tab {
                    case .overview:
                        overviewContent
                    case .arena:
                        arenaContent
                    case .clubs:
                        clubsContent
                    }
                }
                .padding(.horizontal, 15)
                .padding(.top, 12)
                .padding(.bottom, 38)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(ATHLTHCommunityEditorial.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showCreate) {
                ATHLTHCommunityCreateHubView()
            }
            .task {
                await refreshContent(force: false)
            }
            .refreshable {
                await refreshContent(force: true)
            }
            .task(id: query) {
                let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard clean.count >= 2 else {
                    groups.clearSearch()
                    social.clearSearch()
                    return
                }
                do { try await Task.sleep(for: .milliseconds(280)) }
                catch { return }
                guard !Task.isCancelled else { return }
                async let clubMatches: Void = groups.search(clean)
                async let peopleMatches: Void = social.search(clean)
                _ = await (clubMatches, peopleMatches)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ATHLTH")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2.6)
                    .foregroundStyle(ATHLTHCommunityEditorial.gold)
                Text("Community")
                    .font(.system(size: 36, weight: .regular, design: .serif))
                    .foregroundStyle(ATHLTHCommunityEditorial.ink)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showSearch.toggle() }
            } label: {
                headerIcon("magnifyingglass")
            }
            .accessibilityLabel(ATHLTHLocalization.choose(
                english: "Search Community", norwegian: "Søk i fellesskapet"))
            NavigationLink {
                MessageInboxDestinationView()
            } label: {
                headerIcon("bubble.left", count: pendingInbox)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ATHLTHLocalization.choose(
                english: "Messages", norwegian: "Meldinger"))
            NavigationLink {
                ATHLTHCommunityActionCenterView()
            } label: {
                headerIcon("bell")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ATHLTHLocalization.choose(
                english: "Invitations and notifications",
                norwegian: "Invitasjoner og varsler"))
        }
    }

    private func headerIcon(_ name: String, count: Int = 0) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: name)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(ATHLTHCommunityEditorial.ink)
                .frame(width: 37, height: 37)
                .background(ATHLTHCommunityEditorial.paper, in: Circle())
            if count > 0 {
                Circle()
                    .fill(ATHLTHCommunityEditorial.gold)
                    .frame(width: 8, height: 8)
                    .offset(x: -2, y: 2)
            }
        }
        .contentShape(Circle())
    }

    private var tabSelector: some View {
        HStack(spacing: 4) {
            ForEach(ATHLTHCommunityMainTab.allCases) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        tab = option
                        joinMessage = nil
                        showSearch = false
                    }
                } label: {
                    Text(option.title)
                        .font(.system(size: 13, weight: tab == option ? .semibold : .medium))
                        .foregroundStyle(tab == option ?
                                         .white : ATHLTHCommunityEditorial.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 43)
                        .background {
                            if tab == option {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(LinearGradient(
                                        colors: [ATHLTHTrainDesign.gold,
                                                 ATHLTHCommunityEditorial.gold],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == option ? .isSelected : [])
            }
        }
        .padding(4)
        .background(ATHLTHCommunityEditorial.paper,
                    in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(ATHLTHCommunityEditorial.rule.opacity(0.45),
                              lineWidth: 0.8)
        }
        .accessibilityLabel(ATHLTHLocalization.choose(
            english: "Community sections", norwegian: "Community-faner"))
    }

    private var searchField: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(ATHLTHCommunityEditorial.gold)
                TextField(ATHLTHLocalization.choose(
                    english: "Search people or Clubs",
                    norwegian: "Søk etter personer eller klubber"), text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(ATHLTHCommunityEditorial.secondary)
                    }
                    .accessibilityLabel(ATHLTHLocalization.choose(
                        english: "Clear", norwegian: "Tøm"))
                }
            }
            .font(.subheadline)

            if query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
                if !social.discoverResults.isEmpty {
                    Text(ATHLTHLocalization.choose(
                        english: "People", norwegian: "Personer"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHCommunityEditorial.secondary)
                    ForEach(Array(social.discoverResults.prefix(5))) { person in
                        NavigationLink {
                            FriendProfileView(userID: person.userID)
                        } label: {
                            HStack(spacing: 10) {
                                SocialAvatar(profile: person, size: 35)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(person.resolvedName)
                                        .font(.subheadline.weight(.medium))
                                    if let handle = person.username, !handle.isEmpty {
                                        Text("@\(handle)")
                                            .font(.caption)
                                            .foregroundStyle(ATHLTHCommunityEditorial.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHCommunityEditorial.gold)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(ATHLTHCommunityEditorial.ink)
                    }
                }
                if tab != .clubs, !publicClubs.isEmpty {
                    Button {
                        tab = .clubs
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "View matching Clubs",
                            norwegian: "Vis klubber som passer søket"),
                            systemImage: "person.3")
                            .font(.subheadline)
                            .foregroundStyle(ATHLTHCommunityEditorial.gold)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(13)
        .communityEditorialCard()
    }

    private var clubsContent: some View {
        VStack(alignment: .leading, spacing: 17) {
            clubHero

            sectionHeader(
                ATHLTHLocalization.choose(english: "My Clubs", norwegian: "Mine klubber"),
                count: groups.joinedGroups.count
            )

            if groups.joinedGroups.isEmpty {
                emptyInfo(
                    title: ATHLTHLocalization.choose(
                        english: "Your first Club is waiting",
                        norwegian: "Din første klubb venter"),
                    subtitle: ATHLTHLocalization.choose(
                        english: "Find a community to train with below.",
                        norwegian: "Finn et fellesskap å trene med nedenfor.")
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 11) {
                        ForEach(groups.joinedGroups) { club in
                            NavigationLink {
                                CommunityGroupDetailView(group: club)
                            } label: {
                                joinedClubCard(club)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .contentMargins(.trailing, 2)
            }

            sectionHeader(
                ATHLTHLocalization.choose(
                    english: "Recommended Clubs",
                    norwegian: "Anbefalte klubber"),
                moreLabel: showAllRecommendations
                    ? ATHLTHLocalization.choose(english: "Less", norwegian: "Færre")
                    : ATHLTHLocalization.choose(english: "See all", norwegian: "Se alle"),
                onMore: { showAllRecommendations.toggle() }
            )

            if recommendedClubs.isEmpty {
                emptyInfo(
                    title: ATHLTHLocalization.choose(
                        english: "No public Clubs found",
                        norwegian: "Ingen offentlige klubber funnet"),
                    subtitle: ATHLTHLocalization.choose(
                        english: "Try a different search or create a Club.",
                        norwegian: "Prøv et annet søk eller opprett en klubb.")
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(recommendedClubs) { club in
                        recommendedClubRow(club)
                        if club.id != recommendedClubs.last?.id {
                            Rectangle()
                                .fill(ATHLTHCommunityEditorial.rule.opacity(0.45))
                                .frame(height: 1)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .communityEditorialCard()
            }

            sectionHeader(
                ATHLTHLocalization.choose(
                    english: "Upcoming group workouts", norwegian: "Kommende fellesøkter"),
                moreLabel: ATHLTHLocalization.choose(english: "See all", norwegian: "Se alle"),
                moreDestination: AnyView(CommunityEventsView())
            )

            if upcomingSessions.isEmpty {
                emptyInfo(
                    title: ATHLTHLocalization.choose(
                        english: "No upcoming group sessions",
                        norwegian: "Ingen kommende fellesøkter"),
                    subtitle: ATHLTHLocalization.choose(
                        english: "Sessions from Clubs you belong to will appear here.",
                        norwegian: "Økter fra klubbene dine vises her.")
                )
            } else {
                ForEach(Array(upcomingSessions.prefix(3))) { event in
                    if let club = groups.group(for: event.groupID) {
                        NavigationLink {
                            CommunityGroupEventDetailView(group: club, event: event)
                        } label: {
                            upcomingEventRow(event, club: club)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button {
                showCreate = true
            } label: {
                Label(ATHLTHLocalization.choose(
                    english: "Create a Club or group event",
                    norwegian: "Opprett klubb eller fellesaktivitet"),
                    systemImage: "plus.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHCommunityEditorial.gold)
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.plain)
        }
    }

    private var clubHero: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { size in
                Image("CommunityHero")
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.size.width, height: size.size.height)
                    .clipped()
            }
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.02), location: 0),
                    .init(color: .black.opacity(0.18), location: 0.36),
                    .init(color: .black.opacity(0.86), location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 8) {
                Text(ATHLTHLocalization.choose(
                    english: "CLUBS", norwegian: "KLUBBER"))
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2.3)
                    .foregroundStyle(Color(red: 0.94, green: 0.77, blue: 0.47))
                Text(ATHLTHLocalization.choose(
                    english: "Find your community.",
                    norwegian: "Finn ditt fellesskap."))
                    .font(.system(size: 30, weight: .regular, design: .serif))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.72)
                    .lineLimit(2)
                Text(ATHLTHLocalization.choose(
                    english: "Join Clubs, train together and meet people who share your passion.",
                    norwegian: "Bli med i klubber, delta på fellesøkter og møt mennesker med samme lidenskap."))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAllRecommendations = true
                        showSearch = true
                    }
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Explore Clubs", norwegian: "Utforsk klubber"),
                        systemImage: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ATHLTHCommunityEditorial.ink)
                        .padding(.horizontal, 17)
                        .frame(height: 36)
                        .background(.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(19)
        }
        .frame(height: 251)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func joinedClubCard(_ club: CommunityGroupRecord) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ATHLTHArtworkImage(
                reference: club.headerImageURL ?? club.imageURL,
                fallbackAssetName: "CommunityHero",
                maxPixelSize: 440
            )
            .athlthBoundedFill()
            .frame(width: 164, height: 96)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(club.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ATHLTHCommunityEditorial.ink)
                .lineLimit(1)
            Text(club.locationName.isEmpty
                 ? ATHLTHLocalization.choose(english: "Member", norwegian: "Medlem")
                 : club.locationName)
                .font(.system(size: 10))
                .foregroundStyle(ATHLTHCommunityEditorial.secondary)
                .lineLimit(1)
        }
        .frame(width: 164, alignment: .leading)
    }

    private func recommendedClubRow(_ club: CommunityGroupRecord) -> some View {
        HStack(spacing: 9) {
            NavigationLink {
                CommunityGroupDetailView(group: club)
            } label: {
                HStack(spacing: 9) {
                    ATHLTHArtworkImage(
                        reference: club.headerImageURL ?? club.imageURL,
                        fallbackAssetName: "CommunityHero",
                        maxPixelSize: 220
                    )
                    .athlthBoundedFill()
                    .frame(width: 64, height: 56)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(club.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ATHLTHCommunityEditorial.ink)
                            .lineLimit(1)
                        Text(club.locationName.isEmpty
                            ? ATHLTHLocalization.choose(
                                english: "Public Club", norwegian: "Offentlig klubb")
                            : club.locationName)
                            .font(.system(size: 10))
                            .foregroundStyle(ATHLTHCommunityEditorial.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if club.joinMode == "invite_only" {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(ATHLTHCommunityEditorial.secondary)
                    .accessibilityLabel(ATHLTHLocalization.choose(
                        english: "Invite only", norwegian: "Kun invitasjon"))
            } else {
                Button {
                    Task {
                        joiningGroupIDs.insert(club.id)
                        let outcome = await groups.requestJoin(club)
                        joiningGroupIDs.remove(club.id)
                        joinMessage = switch outcome {
                        case "joined": ATHLTHLocalization.choose(
                            english: "You joined the Club.", norwegian: "Du er nå medlem av klubben.")
                        case "requested", "pending": ATHLTHLocalization.choose(
                            english: "Request sent to the Club.",
                            norwegian: "Forespørselen er sendt til klubben.")
                        default: ATHLTHLocalization.choose(
                            english: "Could not join right now. Please retry.",
                            norwegian: "Kunne ikke bli med nå. Prøv igjen.")
                        }
                    }
                } label: {
                    Group {
                        if joiningGroupIDs.contains(club.id) {
                            ProgressView().tint(.white)
                        } else {
                            Text(club.joinMode == "approval"
                                 ? ATHLTHLocalization.choose(
                                    english: "Request", norwegian: "Søk")
                                 : ATHLTHLocalization.choose(
                                    english: "Join", norwegian: "Bli med"))
                        }
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 65, minHeight: 32)
                    .background(ATHLTHCommunityEditorial.gold, in: Capsule())
                }
                .disabled(joiningGroupIDs.contains(club.id))
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
    }

    private func upcomingEventRow(
        _ event: CommunityGroupEventRecord,
        club: CommunityGroupRecord
    ) -> some View {
        HStack(spacing: 11) {
            VStack(spacing: 1) {
                Text(event.startsAt.formatted(.dateTime.month(.abbreviated)).uppercased())
                    .font(.system(size: 9, weight: .semibold))
                Text(event.startsAt.formatted(.dateTime.day()))
                    .font(.system(size: 25, weight: .regular, design: .serif))
            }
            .foregroundStyle(ATHLTHCommunityEditorial.ink)
            .frame(width: 58, height: 68)
            .background(ATHLTHCommunityEditorial.canvas,
                        in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ATHLTHCommunityEditorial.ink)
                    .lineLimit(1)
                Text(club.name)
                    .font(.system(size: 10))
                    .foregroundStyle(ATHLTHCommunityEditorial.secondary)
                    .lineLimit(1)
                Text(event.startsAt.formatted(.dateTime.hour().minute()) +
                     (event.meetingName.isEmpty ? "" : " · " + event.meetingName))
                    .font(.system(size: 10))
                    .foregroundStyle(ATHLTHCommunityEditorial.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(ATHLTHCommunityEditorial.gold)
        }
        .padding(11)
        .communityEditorialCard()
    }

    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            editorialHero(
                image: "CommunityHero",
                eyebrow: ATHLTHLocalization.choose(english: "YOUR CIRCLE", norwegian: "DITT FELLESSKAP"),
                title: ATHLTHLocalization.choose(
                    english: "Stronger together.", norwegian: "Sterkere sammen."),
                subtitle: ATHLTHLocalization.choose(
                    english: "Friends, activity and shared moments in one place.",
                    norwegian: "Venner, aktivitet og felles opplevelser på ett sted.")
            )
            sectionHeader(ATHLTHLocalization.choose(
                english: "Your social circle", norwegian: "Ditt nettverk"))
            HStack(spacing: 8) {
                overviewQuickLink(
                    title: ATHLTHLocalization.choose(english: "Friends", norwegian: "Venner"),
                    symbol: "person.2",
                    destination: AnyView(SocialHubView(initialTab: .feed))
                )
                overviewQuickLink(
                    title: ATHLTHLocalization.choose(english: "Events", norwegian: "Arrangementer"),
                    symbol: "calendar",
                    destination: AnyView(CommunityEventsView())
                )
                overviewQuickLink(
                    title: ATHLTHLocalization.choose(english: "Clubs", norwegian: "Klubber"),
                    symbol: "person.3",
                    selectedTab: .clubs
                )
            }
            sectionHeader(ATHLTHLocalization.choose(
                english: "Upcoming together", norwegian: "Sammen fremover"))
            if upcomingSessions.isEmpty {
                emptyInfo(
                    title: ATHLTHLocalization.choose(
                        english: "Nothing scheduled yet", norwegian: "Ingenting planlagt ennå"),
                    subtitle: ATHLTHLocalization.choose(
                        english: "Joined Clubs and upcoming sessions will appear here.",
                        norwegian: "Kommende økter fra klubbene dine dukker opp her.")
                )
            } else {
                ForEach(Array(upcomingSessions.prefix(2))) { event in
                    if let club = groups.group(for: event.groupID) {
                        NavigationLink {
                            CommunityGroupEventDetailView(group: club, event: event)
                        } label: {
                            upcomingEventRow(event, club: club)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            NavigationLink {
                SocialHubView(initialTab: .feed)
            } label: {
                editorialActionRow(
                    "Aktivitet fra venner", subtitle: "Se oppdateringer fra ditt nettverk",
                    icon: "person.crop.circle.badge.checkmark")
            }
            .buttonStyle(.plain)
        }
    }

    private var arenaContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            editorialHero(
                image: "TrainHero",
                eyebrow: "ARENA",
                title: ATHLTHLocalization.choose(
                    english: "Challenge your limits.", norwegian: "Utfordre grensene dine."),
                subtitle: ATHLTHLocalization.choose(
                    english: "Duels, distances and team challenges.",
                    norwegian: "Dueller, distanser og lagutfordringer.")
            )
            sectionHeader(ATHLTHLocalization.choose(
                english: "Your Arena", norwegian: "Din Arena"))
            NavigationLink {
                ATHLTHArenaHomeView()
            } label: {
                editorialActionRow(
                    ATHLTHLocalization.choose(
                        english: "My competitions", norwegian: "Mine konkurranser"),
                    subtitle: ATHLTHLocalization.choose(
                        english: "Invitations, rounds, scores and live status",
                        norwegian: "Invitasjoner, runder, poeng og live-status"),
                    icon: "trophy.fill")
            }
            .buttonStyle(.plain)
            NavigationLink {
                ChallengeHubView()
            } label: {
                editorialActionRow(
                    ATHLTHLocalization.choose(
                        english: "Weekly challenges", norwegian: "Ukentlige utfordringer"),
                    subtitle: ATHLTHLocalization.choose(
                        english: "See active and upcoming challenges",
                        norwegian: "Se aktive og kommende utfordringer"),
                    icon: "flag.checkered")
            }
            .buttonStyle(.plain)
            NavigationLink {
                GhostFriendRaceHubView()
            } label: {
                editorialActionRow(
                    "Live Ghost",
                    subtitle: ATHLTHLocalization.choose(
                        english: "Race a friend on a verified route",
                        norwegian: "Løp mot en venn på en avtalt rute"),
                    icon: "figure.run")
            }
            .buttonStyle(.plain)
        }
    }

    private func overviewQuickLink(
        title: String, symbol: String,
        destination: AnyView? = nil,
        selectedTab: ATHLTHCommunityMainTab? = nil
    ) -> some View {
        Group {
            if let destination {
                NavigationLink { destination } label: {
                    quickLinkTile(title: title, symbol: symbol)
                }
                .buttonStyle(.plain)
            } else if let selectedTab {
                Button {
                    tab = selectedTab
                } label: {
                    quickLinkTile(title: title, symbol: symbol)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func quickLinkTile(title: String, symbol: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(ATHLTHCommunityEditorial.gold)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ATHLTHCommunityEditorial.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, minHeight: 91)
        .communityEditorialCard()
    }

    private func editorialHero(
        image: String, eyebrow: String, title: String, subtitle: String
    ) -> some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { area in
                Image(image)
                    .resizable().scaledToFill()
                    .frame(width: area.size.width, height: area.size.height)
                    .clipped()
            }
            LinearGradient(colors: [.clear, .black.opacity(0.82)],
                           startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 8) {
                Text(eyebrow.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(Color(red: 0.94, green: 0.78, blue: 0.53))
                Text(title)
                    .font(.system(size: 29, weight: .regular, design: .serif))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.91))
                    .lineLimit(3)
            }
            .padding(19)
        }
        .frame(height: 205)
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    private func editorialActionRow(
        _ title: String, subtitle: String, icon: String
    ) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(ATHLTHCommunityEditorial.gold)
                .frame(width: 45, height: 45)
                .background(ATHLTHCommunityEditorial.canvas,
                            in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ATHLTHCommunityEditorial.ink)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(ATHLTHCommunityEditorial.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 2)
            Image(systemName: "chevron.right")
                .foregroundStyle(ATHLTHCommunityEditorial.gold)
        }
        .padding(13)
        .communityEditorialCard()
    }

    private func sectionHeader(
        _ title: String,
        count: Int? = nil,
        moreLabel: String? = nil,
        onMore: (() -> Void)? = nil,
        moreDestination: AnyView? = nil
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            ATHLTHCommunityEditorial.heading(title)
            if let count, count > 0 {
                Text("\(count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ATHLTHCommunityEditorial.secondary)
            }
            Spacer(minLength: 1)
            if let moreDestination, let moreLabel {
                NavigationLink { moreDestination } label: {
                    moreLabelView(moreLabel)
                }
                .buttonStyle(.plain)
            } else if let onMore, let moreLabel {
                Button(action: onMore) {
                    moreLabelView(moreLabel)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func moreLabelView(_ title: String) -> some View {
        HStack(spacing: 3) {
            Text(title)
            Image(systemName: "chevron.right")
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(ATHLTHCommunityEditorial.secondary)
    }

    private func emptyInfo(title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.3.sequence")
                .font(.title3)
                .foregroundStyle(ATHLTHCommunityEditorial.gold)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ATHLTHCommunityEditorial.ink)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(ATHLTHCommunityEditorial.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .communityEditorialCard()
    }

    @MainActor
    private func refreshContent(force: Bool) async {
        async let a: Void = groups.refresh(force: force)
        async let b: Void = groups.refreshCalendarContent()
        async let c: Void = community.refresh(force: force)
        async let d: Void = messaging.refresh(force: force)
        async let e: Void = officialChallenges.refresh(force: force)
        async let f: Void = force
            ? social.refresh(challengeStore: challenges)
            : social.refreshIfStale(challengeStore: challenges)
        _ = await (a, b, c, d, e, f)
    }
}

private struct ATHLTHCommunityEditorialCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(ATHLTHCommunityEditorial.paper,
                        in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(ATHLTHCommunityEditorial.rule.opacity(0.36),
                                  lineWidth: 0.8)
            }
            .shadow(color: ATHLTHCommunityEditorial.ink.opacity(0.028),
                    radius: 8, y: 3)
    }
}

private extension View {
    func communityEditorialCard() -> some View {
        modifier(ATHLTHCommunityEditorialCardModifier())
    }
}

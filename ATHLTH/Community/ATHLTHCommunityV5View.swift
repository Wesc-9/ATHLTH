import SwiftUI

// MARK: - Fellesskap · screenshot-led 2.0.4 redesign
// The former Community V5 dashboard is intentionally replaced. Club,
// challenge, Arena and RSVP stores remain intact as the source of truth.
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
    @EnvironmentObject private var messaging: MessagingStore
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager

    @StateObject private var weather = HomeWeatherStore()
    @State private var tab: ATHLTHCommunityMainTab = .overview
    @State private var showSearch = false
    @State private var showCreate = false
    @State private var query = ""
    @State private var joinMessage: String?
    @State private var joiningGroupIDs: Set<UUID> = []
    @State private var respondingToInvite: UUID?
    @State private var inviteError: String?

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
                        if showSearch {
                            searchBar
                        }
                        if let joinMessage {
                            Text(joinMessage)
                                .font(.caption)
                                .foregroundStyle(CommunityReferenceStyle.darkGold)
                                .padding(11)
                                .communityReferenceCard()
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
            .sheet(isPresented: $showCreate) {
                ATHLTHCommunityCreateHubView()
            }
            .task {
                weather.refreshIfNeeded()
                await refreshContent(force: false)
            }
            .refreshable {
                weather.refreshIfNeeded(force: true)
                await refreshContent(force: true)
            }
            .task(id: query) {
                let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard showSearch && term.count >= 2 else {
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

    // MARK: - Screenshot hero

    private var cover: some View {
        ZStack(alignment: .topLeading) {
            GeometryReader { geo in
                Image("CommunityHero")
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
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer(minLength: 0)
                    headerTools
                }
                .padding(.top, 75)
                .padding(.trailing, 14)

                Spacer(minLength: 8)

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
        .frame(height: 263)
        .clipShape(
            UnevenRoundedRectangle(
                bottomLeadingRadius: 21, bottomTrailingRadius: 21
            )
        )
        .accessibilityElement(children: .contain)
    }

    private var headerTools: some View {
        HStack(spacing: 5) {
            HStack(spacing: 5) {
                if let snapshot = weather.snapshot,
                   snapshot.temperatureCelsius.isFinite {
                    Image(systemName: snapshot.symbolName)
                    Text("\(Int(snapshot.temperatureCelsius.rounded()))°")
                } else {
                    Image(systemName: "cloud.sun")
                    Text("—")
                }
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 62, height: 36)
            .background(.black.opacity(0.20), in: Capsule())

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showSearch.toggle()
                }
            } label: {
                toolIcon("magnifyingglass")
            }
            .accessibilityLabel(ATHLTHLocalization.choose(
                english: "Search Community", norwegian: "Søk i fellesskapet"
            ))

            NavigationLink {
                MessageInboxDestinationView()
            } label: {
                toolIcon("tray", count:
                    messaging.unreadCount + messaging.messageRequestCount)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ATHLTHLocalization.choose(
                english: "Inbox", norwegian: "Innboks"
            ))

            NavigationLink {
                ATHLTHCommunityActionCenterView()
            } label: {
                toolIcon("bell")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ATHLTHLocalization.choose(
                english: "Invitations", norwegian: "Invitasjoner"
            ))

            NavigationLink {
                ATHLTHProfileView()
            } label: {
                CommunityShowcaseAvatar(
                    url: URL(string: session.profile.avatarURL ?? ""),
                    fallback: session.profile.displayName ?? "ATHLTH",
                    size: 37
                )
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ATHLTHLocalization.choose(
                english: "Profile", norwegian: "Profil"
            ))
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule().strokeBorder(.white.opacity(0.42), lineWidth: 0.9)
                .allowsHitTesting(false)
        }
    }

    private func toolIcon(_ name: String, count: Int = 0) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: name)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 35, height: 35)
                .background(.black.opacity(0.19), in: Circle())
            if count > 0 {
                Circle()
                    .fill(CommunityReferenceStyle.gold)
                    .frame(width: 7, height: 7)
                    .offset(x: 0, y: 1)
            }
        }
        .frame(minWidth: 35, minHeight: 44)
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(ATHLTHCommunityMainTab.allCases) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.23)) {
                        tab = option
                        joinMessage = nil
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
        VStack(spacing: 12) {
            twoColumns {
                joinedClubCard
                NavigationLink {
                    CommunityGroupDiscoveryView()
                } label: {
                    basicLinkCard(
                        title: ATHLTHLocalization.choose(
                            english: "Find a club", norwegian: "Finn en klubb"),
                        description: ATHLTHLocalization.choose(
                            english: "Find people to train with.",
                            norwegian: "Finn noen å trene sammen med."),
                        icon: "person.3"
                    )
                }
                .buttonStyle(.plain)
            }
            membersStrip
            if let invite = pendingClubInvitation {
                invitationBanner(invite)
            }
        }
    }

    private var arenaPage: some View {
        VStack(spacing: 12) {
            twoColumns {
                arenaDuelCard
                weeklyChallengeCard
            }
            NavigationLink {
                ATHLTHArenaHomeView()
            } label: {
                singleLinkRow(
                    title: "Arena",
                    subtitle: ATHLTHLocalization.choose(
                        english: "Competitions, duels and standings",
                        norwegian: "Konkurranser, dueller og resultater"),
                    icon: "trophy.fill"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var eventsPage: some View {
        VStack(spacing: 12) {
            twoColumns {
                nextGatheringCard
                NavigationLink {
                    CommunityEventsView()
                } label: {
                    basicLinkCard(
                        title: ATHLTHLocalization.choose(
                            english: "Explore events", norwegian: "Finn arrangementer"),
                        description: ATHLTHLocalization.choose(
                            english: "Meet others and join a workout.",
                            norwegian: "Møt andre og bli med på en økt."),
                        icon: "calendar"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func twoColumns<Left: View, Right: View>(
        @ViewBuilder _ content: () -> TupleView<(Left, Right)>
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            content()
        }
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
                NavigationLink {
                    CommunityGroupDiscoveryView()
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
                    OfficialWeeklyChallengeDetailView(challenge: challenge)
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
                    OfficialWeeklyChallengeDetailView(challenge: challenge)
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
                    SocialHubView(initialTab: .feed)
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
                    Button { showCreate = true } label: {
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

                    ForEach(Array(social.mutualFollows.prefix(12))) { friend in
                        NavigationLink {
                            FriendProfileView(userID: friend.userID)
                        } label: {
                            VStack(spacing: 5) {
                                CommunityShowcaseAvatar(
                                    url: friend.avatarURL.flatMap(URL.init(string:)),
                                    fallback: friend.resolvedName,
                                    size: 43
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

                    if social.mutualFollows.isEmpty {
                        Text(ATHLTHLocalization.choose(
                            english: "Your training friends will appear here.",
                            norwegian: "Treningsvennene dine vises her."
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

    private func basicLinkCard(
        title: String, description: String, icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            cardHeading(title, icon: icon)
            Spacer(minLength: 0)
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(CommunityReferenceStyle.gold)
                .frame(maxWidth: .infinity)
            Text(description)
                .font(.system(size: 11))
                .foregroundStyle(CommunityReferenceStyle.muted)
            Spacer(minLength: 0)
            creamButton(ATHLTHLocalization.choose(
                english: "Explore", norwegian: "Utforsk"
            ), symbol: "arrow.right")
        }
        .padding(11)
        .frame(height: 184)
        .communityReferenceCard()
    }

    private func singleLinkRow(
        title: String, subtitle: String, icon: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(CommunityReferenceStyle.gold)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                    .foregroundStyle(CommunityReferenceStyle.ink)
                Text(subtitle).font(.caption)
                    .foregroundStyle(CommunityReferenceStyle.muted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(CommunityReferenceStyle.gold)
        }
        .padding(14)
        .communityReferenceCard()
    }

    private var searchBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(ATHLTHLocalization.choose(
                english: "Search clubs and people",
                norwegian: "Søk etter klubber og personer"
            ), text: $query)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(12)
            .background(CommunityReferenceStyle.canvas, in: RoundedRectangle(cornerRadius: 12))

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

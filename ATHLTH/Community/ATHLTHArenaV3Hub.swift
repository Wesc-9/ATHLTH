import SwiftUI

// The Arena hub deliberately keeps tournaments in a separate draft namespace.
// Existing server-owned Arena series, approved scores, club seasons and
// Challenge invitations remain untouched and are linked to their real details.
enum ATHLTHTournamentFormat: String, Codable, CaseIterable, Identifiable {
    case league
    case groups
    case cup
    var id: String { rawValue }
    var title: String {
        switch self {
        case .league: return "Liga"
        case .groups: return "Gruppeliga"
        case .cup: return "Cup"
        }
    }
    var subtitle: String {
        switch self {
        case .league: return "Én tabell, alle møter alle"
        case .groups: return "Små grupper med egen tabell"
        case .cup: return "Én mot én, utslag til én vinner står igjen"
        }
    }
    var symbol: String {
        switch self {
        case .league: return "list.number"
        case .groups: return "square.grid.2x2"
        case .cup: return "trophy"
        }
    }
}

enum ATHLTHTournamentExerciseMode: String, Codable, CaseIterable, Identifiable {
    case owner, open, vote
    var id: String { rawValue }
    var title: String {
        switch self {
        case .owner: return "Arrangøren velger"
        case .open: return "Alle kan legge til"
        case .vote: return "Forslag og avstemning"
        }
    }
    var detail: String {
        switch self {
        case .owner: return "Arrangøren setter opp alle øvelsene."
        case .open: return "Deltakerne fyller opp et felles øvelsesprogram."
        case .vote: return "Alle foreslår. Hver får like mange stemmer som øvelser som velges."
        }
    }
    var symbol: String {
        switch self {
        case .owner: return "person.crop.circle"
        case .open: return "person.3"
        case .vote: return "checkmark.seal"
        }
    }
}

/// A practice round is entirely separate from official fixtures. It must
/// never feed the table, elimination engine, ranking or season points.
struct ATHLTHTournamentWarmupRound: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var title: String

    var countsForPoints: Bool { false }
    var countsForAdvancement: Bool { false }
    var mayEliminate: Bool { false }
}

/// Local tournament specification. Optional season/warm-up fields are decoded
/// with defaults to keep tournament drafts created in v2.0.9 readable.
struct ATHLTHTournamentDraft: Codable, Identifiable {
    var id: UUID
    var ownerID: UUID
    var clubID: UUID?
    var seasonID: UUID?
    var title: String
    var format: ATHLTHTournamentFormat
    var groupSize: Int
    var qualifiersPerGroup: Int
    var participants: [ATHLTHTournamentParticipant]
    var warmupRounds: [ATHLTHTournamentWarmupRound]
    var exerciseMode: ATHLTHTournamentExerciseMode
    var exerciseCount: Int
    var proposalsCloseAt: Date?
    var votesCloseAt: Date?
    var approvePlayerChanges: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        ownerID: UUID,
        clubID: UUID?,
        seasonID: UUID? = nil,
        title: String,
        format: ATHLTHTournamentFormat,
        groupSize: Int,
        qualifiersPerGroup: Int,
        participants: [ATHLTHTournamentParticipant],
        warmupRounds: [ATHLTHTournamentWarmupRound] = [],
        exerciseMode: ATHLTHTournamentExerciseMode = .owner,
        exerciseCount: Int = 4,
        proposalsCloseAt: Date? = nil,
        votesCloseAt: Date? = nil,
        approvePlayerChanges: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.ownerID = ownerID
        self.clubID = clubID
        self.seasonID = clubID == nil ? nil : seasonID
        self.title = title
        self.format = format
        self.groupSize = groupSize
        self.qualifiersPerGroup = qualifiersPerGroup
        self.participants = participants
        self.warmupRounds = Array(warmupRounds.prefix(12))
        self.exerciseMode = exerciseMode
        self.exerciseCount = min(12,max(1,exerciseCount))
        self.proposalsCloseAt = proposalsCloseAt
        self.votesCloseAt = votesCloseAt
        self.approvePlayerChanges = approvePlayerChanges
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, ownerID, clubID, seasonID, title, format, groupSize
        case qualifiersPerGroup, participants, warmupRounds, createdAt
        case exerciseMode, exerciseCount, proposalsCloseAt, votesCloseAt,
             approvePlayerChanges
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        ownerID = try values.decode(UUID.self, forKey: .ownerID)
        clubID = try values.decodeIfPresent(UUID.self, forKey: .clubID)
        seasonID = clubID == nil ? nil :
            try values.decodeIfPresent(UUID.self, forKey: .seasonID)
        title = try values.decode(String.self, forKey: .title)
        format = try values.decode(ATHLTHTournamentFormat.self, forKey: .format)
        groupSize = try values.decode(Int.self, forKey: .groupSize)
        qualifiersPerGroup = try values.decode(Int.self, forKey: .qualifiersPerGroup)
        participants = try values.decode([ATHLTHTournamentParticipant].self,
                                          forKey: .participants)
        warmupRounds = Array(try values.decodeIfPresent(
            [ATHLTHTournamentWarmupRound].self, forKey: .warmupRounds
        )?.prefix(12) ?? [])
        exerciseMode = try values.decodeIfPresent(
            ATHLTHTournamentExerciseMode.self, forKey: .exerciseMode
        ) ?? .owner
        exerciseCount = min(12, max(1, try values.decodeIfPresent(
            Int.self, forKey: .exerciseCount
        ) ?? 4))
        proposalsCloseAt = try values.decodeIfPresent(Date.self,
            forKey: .proposalsCloseAt)
        votesCloseAt = try values.decodeIfPresent(Date.self,
            forKey: .votesCloseAt)
        approvePlayerChanges = try values.decodeIfPresent(Bool.self,
            forKey: .approvePlayerChanges) ?? false
        createdAt = try values.decode(Date.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(ownerID, forKey: .ownerID)
        try values.encodeIfPresent(clubID, forKey: .clubID)
        try values.encodeIfPresent(seasonID, forKey: .seasonID)
        try values.encode(title, forKey: .title)
        try values.encode(format, forKey: .format)
        try values.encode(groupSize, forKey: .groupSize)
        try values.encode(qualifiersPerGroup, forKey: .qualifiersPerGroup)
        try values.encode(participants, forKey: .participants)
        try values.encode(warmupRounds, forKey: .warmupRounds)
        try values.encode(exerciseMode, forKey: .exerciseMode)
        try values.encode(exerciseCount, forKey: .exerciseCount)
        try values.encodeIfPresent(proposalsCloseAt, forKey: .proposalsCloseAt)
        try values.encodeIfPresent(votesCloseAt, forKey: .votesCloseAt)
        try values.encode(approvePlayerChanges, forKey: .approvePlayerChanges)
        try values.encode(createdAt, forKey: .createdAt)
    }
}

struct ATHLTHTournamentParticipant: Identifiable, Codable, Hashable {
    var id: UUID
    var username: String
}

enum ATHLTHTournamentDraftStore {
    private static func key(_ userID: UUID) -> String {
        "athlth.arena.tournament.drafts.v1." + userID.uuidString
    }

    static func load(_ owner: UUID) -> [ATHLTHTournamentDraft] {
        guard let data = UserDefaults.standard.data(forKey: key(owner)) else {
            return []
        }
        return (try? JSONDecoder().decode([ATHLTHTournamentDraft].self, from: data)) ?? []
    }

    static func save(_ drafts: [ATHLTHTournamentDraft], owner: UUID) {
        guard let data = try? JSONEncoder().encode(drafts) else { return }
        UserDefaults.standard.set(data, forKey: key(owner))
    }
}

enum ATHLTHTournamentStructure {
    // Distribute athletes deterministically; no random winners or invented
    // results are displayed until a server-approved result exists.
    static func groups(_ members: [ATHLTHTournamentParticipant], size: Int)
        -> [[ATHLTHTournamentParticipant]] {
        guard !members.isEmpty else { return [] }
        let count = max(1, Int(ceil(Double(members.count) / Double(max(2, size)))))
        var groups = Array(repeating: [ATHLTHTournamentParticipant](), count: count)
        for (index, athlete) in members.enumerated() {
            groups[index % count].append(athlete)
        }
        return groups
    }

    static func leagueMatchCount(_ count: Int) -> Int {
        max(0, count * (count - 1) / 2)
    }

    static func bracketSize(_ count: Int) -> Int {
        var capacity = 2
        while capacity < max(count, 2) { capacity *= 2 }
        return capacity
    }

    static func firstCupRound(_ athletes: [ATHLTHTournamentParticipant])
        -> [(String, String)] {
        guard !athletes.isEmpty else { return [] }
        let size = bracketSize(athletes.count)
        let byes = size - athletes.count
        var matchups: [(String, String)] = []
        var next = 0
        for match in 0..<(size / 2) {
            let first = athletes[next].username
            next += 1
            if match < byes {
                // Spread byes across separate matches. Two byes must never
                // face each other while real contestants are paired elsewhere.
                matchups.append((first, "Frirunde"))
            } else {
                let second = athletes[next].username
                next += 1
                matchups.append((first, second))
            }
        }
        return matchups
    }
}

private enum ATHLTHArenaV3CreateAction: String, Identifiable {
    case duel
    case league
    case cup
    var id: String { rawValue }
}

private enum ATHLTHArenaV3Filter: String, CaseIterable, Identifiable {
    case active, invitations, finished
    var id: String { rawValue }
    var title: String {
        switch self {
        case .active: return "Pågående"
        case .invitations: return "Invitasjoner"
        case .finished: return "Fullført"
        }
    }
}

enum ATHLTHArenaV3Style {
    static let ink = Color(red: 0.075, green: 0.080, blue: 0.10)
    static let secondary = Color(red: 0.46, green: 0.46, blue: 0.49)
    static let gold = Color(red: 0.49, green: 0.35, blue: 0.20)
    static let cream = Color(red: 0.975, green: 0.965, blue: 0.946)
    static let line = Color(red: 0.88, green: 0.86, blue: 0.83)
    static func panel() -> some View {
        RoundedRectangle(cornerRadius: 21, style: .continuous)
            .fill(Color.white.opacity(0.92))
            .overlay(RoundedRectangle(cornerRadius: 21)
                .stroke(line.opacity(0.65), lineWidth: 0.7))
    }
}

struct ATHLTHArenaV3HomeView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var challenges: ChallengeStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var tournaments: [ATHLTHTournamentDraft] = []
    @State private var legacyDrafts: [ATHLTHArenaCompetitionDraft] = []
    @State private var remoteSeries: [ATHLTHArenaRemoteSeries] = []
    @State private var officialTournaments: [ATHLTHTournamentRemote] = []
    @State private var pendingTournamentIDs: Set<UUID> = []
    @State private var myTournamentIDs: Set<UUID> = []
    @State private var tournamentError: String?
    @State private var selectedFilter: ATHLTHArenaV3Filter = .active
    @State private var showCreatePicker = false
    @State private var creation: ATHLTHArenaV3CreateAction?
    @State private var loadError: String?
    @State private var loadedID: UUID?
    private let cloud = ATHLTHArenaCloudService()
    private let tournamentCloud = ATHLTHTournamentCloudService()

    private var challengesForUser: [ATHLTHChallenge] {
        challenges.visibleChallenges.filter { c in
            c.creatorID == session.profile.userID ||
            c.participants.contains { $0.userID == session.profile.userID }
        }
    }

    private var visibleChallenges: [ATHLTHChallenge] {
        switch selectedFilter {
        case .active:
            return challengesForUser.filter {
                $0.status != .completed && $0.status != .cancelled &&
                !$0.participants.contains { p in
                    p.userID == session.profile.userID && p.state == .invited
                }
            }
        case .invitations:
            return challenges.incomingInvitations(for: session.profile.userID)
        case .finished:
            return challengesForUser.filter { $0.status == .completed || $0.status == .cancelled }
        }
    }

    private var visibleSeries: [ATHLTHArenaRemoteSeries] {
        guard loadedID == session.profile.userID else { return [] }
        return remoteSeries.filter { item in
            switch selectedFilter {
            case .active: return item.status != "completed" && item.status != "cancelled"
            case .invitations: return item.status == "draft"
            case .finished: return item.status == "completed" || item.status == "cancelled"
            }
        }
    }

    private var visibleOfficialTournaments: [ATHLTHTournamentRemote] {
        officialTournaments.filter { item in
            guard myTournamentIDs.contains(item.id) else { return false }
            switch selectedFilter {
            case .active:
                return item.status != "completed" &&
                    item.status != "cancelled" &&
                    !pendingTournamentIDs.contains(item.id)
            case .invitations:
                return item.status == "inviting" &&
                    pendingTournamentIDs.contains(item.id)
            case .finished:
                return item.status == "completed" || item.status == "cancelled"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                header
                createEntry
                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        Text("Mine konkurranser")
                            .font(.system(size: 25, weight: .semibold, design: .serif))
                            .foregroundStyle(ATHLTHArenaV3Style.ink)
                        Spacer()
                        Text("\(remoteSeries.count + myTournamentIDs.count + challengesForUser.count + tournaments.count + legacyDrafts.count)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(ATHLTHArenaV3Style.secondary)
                            .monospacedDigit()
                    }
                    Picker("Konkurranser", selection: $selectedFilter) {
                        ForEach(ATHLTHArenaV3Filter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)

                    if visibleChallenges.isEmpty && visibleSeries.isEmpty &&
                       visibleOfficialTournaments.isEmpty &&
                       (selectedFilter != .active ||
                        (tournaments.isEmpty && legacyDrafts.isEmpty)) {
                        emptyContent
                    }
                    ForEach(visibleOfficialTournaments.sorted {
                        $0.createdAt > $1.createdAt
                    }) { tournament in
                        NavigationLink {
                            ATHLTHTournamentLiveDetailView(tournament: tournament)
                        } label: {
                            competitionRow(
                                title: tournament.title,
                                caption: tournament.format.title +
                                    (tournament.clubID == nil ? "" : " · Klubb"),
                                status: pendingTournamentIDs.contains(tournament.id)
                                    ? "Svar på invitasjon" :
                                    tournament.status == "completed" ? "Fullført" :
                                    tournament.status == "inviting" ? "Invitert" : "Pågår",
                                symbol: tournament.format.symbol
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(visibleChallenges) { challenge in
                        NavigationLink {
                            ChallengeDetailView(challengeID: challenge.id)
                        } label: {
                            competitionRow(
                                title: challenge.title,
                                caption: "Duell · \(challenge.sport.title)",
                                status: challenge.status == .completed ? "Fullført" : "Utfordring",
                                symbol: "flag.checkered"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(visibleSeries) { item in
                        NavigationLink {
                            ATHLTHArenaOnlineDetailView(series: item)
                        } label: {
                            competitionRow(
                                title: item.title,
                                caption: item.clubID == nil ? "Arena-serie" : "Klubbkonkurranse",
                                status: item.status == "completed" ? "Fullført" : "Pågår",
                                symbol: "person.3.sequence"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    if selectedFilter == .active {
                        ForEach(legacyDrafts) { draft in
                            NavigationLink {
                                ATHLTHArenaDraftDetailView(
                                    draft: draft,
                                    onSave: saveLegacy,
                                    onPublished: { id in
                                        legacyDrafts.removeAll { $0.id == id }
                                        ATHLTHArenaDraftStorage.save(
                                            legacyDrafts, for: session.profile.userID
                                        )
                                        Task { await reload() }
                                    }
                                )
                            } label: {
                                competitionRow(
                                    title: draft.title,
                                    caption: "Tidligere Arena-oppsett",
                                    status: "Utkast",
                                    symbol: "square.stack"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(tournaments) { draft in
                            NavigationLink {
                                ATHLTHTournamentDraftDetailView(
                                    draft: draft,
                                    onPublished: { _ in
                                        tournaments.removeAll { $0.id == draft.id }
                                        ATHLTHTournamentDraftStore.save(
                                            tournaments, owner: session.profile.userID
                                        )
                                        Task { await reload() }
                                    }
                                )
                            } label: {
                                competitionRow(
                                    title: draft.title,
                                    caption: draft.format.title + (draft.clubID == nil ? "" : " · Klubb"),
                                    status: "Utkast",
                                    symbol: draft.format.symbol
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                HStack(spacing: 11) {
                    NavigationLink {
                        CommunityGroupsView()
                    } label: {
                        secondaryEntry("Klubber", symbol: "person.3")
                    }
                    NavigationLink {
                        ATHLTHArenaSeasonsDestination()
                    } label: {
                        secondaryEntry("Sesonger", symbol: "chart.bar.xaxis")
                    }
                }
                NavigationLink {
                    GhostFriendRaceHubView()
                } label: {
                    HStack {
                        Image(systemName: "bolt")
                        Text("Live Ghost")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ATHLTHArenaV3Style.ink)
                    .padding(16)
                    .background(ATHLTHArenaV3Style.panel())
                }
                .buttonStyle(.plain)
                if let loadError {
                    Text(loadError)
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                }
                if let tournamentError {
                    Text(tournamentError)
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 36)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(ATHLTHArenaV3Style.cream.ignoresSafeArea())
        .navigationTitle("Arena")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.profile.userID) { await reload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await reload() } }
        }
        .confirmationDialog("Ny konkurranse", isPresented: $showCreatePicker) {
            Button("Duell") { creation = .duel }
            Button("Liga eller grupper") { creation = .league }
            Button("Cup") { creation = .cup }
            Button("Avbryt", role: .cancel) {}
        }
        .sheet(item: $creation) { action in
            switch action {
            case .duel:
                ChallengeCreationView()
            case .league, .cup:
                ATHLTHTournamentCreator(
                    preset: action == .cup ? .cup : .league,
                    fixedClubID: nil,
                    onPublished: { _ in Task { await reload() } }
                ) { draft in
                    save(draft)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text("ATHLTH / KONKURRANSER")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2.2)
                    .foregroundStyle(ATHLTHArenaV3Style.gold)
                Text("Arena")
                    .font(.system(size: 43, weight: .regular, design: .serif))
                    .foregroundStyle(ATHLTHArenaV3Style.ink)
                Text("Alt du deltar i. På ett sted.")
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
            }
            Spacer()
            Image(systemName: "trophy")
                .font(.system(size: 28, weight: .ultraLight))
                .foregroundStyle(ATHLTHArenaV3Style.gold)
                .frame(width: 60, height: 60)
                .background(ATHLTHArenaV3Style.panel())
        }
    }

    private var createEntry: some View {
        Button { showCreatePicker = true } label: {
            HStack(spacing: 15) {
                Image(systemName: "plus")
                    .font(.title3.weight(.medium))
                    .frame(width: 47, height: 47)
                    .background(Color.white.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("Opprett konkurranse")
                        .font(.headline)
                    Text("Duell, liga eller cup")
                        .font(.caption)
                        .opacity(0.76)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
            }
            .foregroundStyle(.white)
            .padding(17)
            .frame(maxWidth: .infinity)
            .background(ATHLTHArenaV3Style.ink,
                        in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }

    private var emptyContent: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.stack")
                .font(.title2.weight(.ultraLight))
            Text(selectedFilter == .active
                 ? "Ingen konkurranser her ennå" :
                    selectedFilter == .invitations
                 ? "Ingen invitasjoner som venter" : "Ingen avsluttede konkurranser")
                .font(.subheadline)
        }
        .foregroundStyle(ATHLTHArenaV3Style.secondary)
        .frame(maxWidth: .infinity, minHeight: 134)
        .background(ATHLTHArenaV3Style.panel())
    }

    private func competitionRow(title: String, caption: String,
                                status: String, symbol: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .light))
                .foregroundStyle(ATHLTHArenaV3Style.gold)
                .frame(width: 42, height: 42)
                .background(ATHLTHArenaV3Style.cream,
                            in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .foregroundStyle(ATHLTHArenaV3Style.ink)
                Text(caption + " · " + status)
                    .font(.caption)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
            }
            Spacer(minLength: 2)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(ATHLTHArenaV3Style.secondary)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ATHLTHArenaV3Style.panel())
    }

    private func secondaryEntry(_ title: String, symbol: String) -> some View {
        HStack {
            Image(systemName: symbol)
                .foregroundStyle(ATHLTHArenaV3Style.gold)
            Text(title)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(ATHLTHArenaV3Style.ink)
        .padding(16)
        .background(ATHLTHArenaV3Style.panel())
    }

    @MainActor
    private func reload() async {
        tournaments = ATHLTHTournamentDraftStore.load(session.profile.userID)
        legacyDrafts = ATHLTHArenaDraftStorage.load(for: session.profile.userID)
        do {
            async let official = tournamentCloud.visibleTournaments()
            async let pending = tournamentCloud.pendingInvitationIDs(
                userID: session.profile.userID
            )
            async let membership = tournamentCloud.myTournamentIDs(
                userID: session.profile.userID
            )
            officialTournaments = try await official
            pendingTournamentIDs = try await pending
            myTournamentIDs = try await membership
            tournamentError = nil
        } catch {
            tournamentError = "Turneringer kunne ikke oppdateres: " +
                error.localizedDescription
        }
        do {
            let loaded = try await cloud.loadSeries()
            remoteSeries = loaded
            loadedID = session.profile.userID
            loadError = nil
        } catch {
            loadError = ATHLTHLocalization.choose(
                english: "Could not refresh the Arena competitions.",
                norwegian: "Kunne ikke oppdatere Arena-konkurransene."
            )
        }
    }

    private func saveLegacy(_ draft: ATHLTHArenaCompetitionDraft) {
        legacyDrafts.removeAll { $0.id == draft.id }
        legacyDrafts.insert(draft, at: 0)
        ATHLTHArenaDraftStorage.save(legacyDrafts, for: session.profile.userID)
    }

    private func save(_ draft: ATHLTHTournamentDraft) {
        tournaments.removeAll { $0.id == draft.id }
        tournaments.insert(draft, at: 0)
        ATHLTHTournamentDraftStore.save(tournaments, owner: session.profile.userID)
    }
}

/// The same local club drafts are listed at both destinations, without
/// duplicating tournament records or publishing a competition prematurely.
/// Club-owned seasons are live records, fetched using the existing
/// club-season RLS rules. Drafts reference their season without creating
/// duplicate competition records or awarding any points.
struct ATHLTHArenaClubTournamentSection: View {
    @EnvironmentObject private var session: AppSessionStore
    @Environment(\.scenePhase) private var scenePhase
    let clubID: UUID
    let isOrganizer: Bool

    @State private var drafts: [ATHLTHTournamentDraft] = []
    @State private var remote: [ATHLTHArenaRemoteSeries] = []
    @State private var officialTournaments: [ATHLTHTournamentRemote] = []
    @State private var seasons: [ATHLTHArenaClubSeason] = []
    @State private var manageableClubs: [ATHLTHArenaClubChoice] = []
    @State private var showingCreate = false
    @State private var showingCreateSeason = false
    @State private var loadError: String?

    private let cloud = ATHLTHArenaCloudService()
    private let tournamentCloud = ATHLTHTournamentCloudService()
    private let directory = ATHLTHArenaClubDirectory()

    private var canManage: Bool {
        isOrganizer && manageableClubs.contains { $0.id == clubID }
    }

    private var orderedSeasons: [ATHLTHArenaClubSeason] {
        seasons.sorted { $0.startsOn > $1.startsOn }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Cuper og ligaer")
                    .font(.system(size: 22, weight: .regular, design: .serif))
                Spacer()
                if canManage {
                    Menu {
                        Button("Opprett cup eller liga", systemImage: "trophy") {
                            showingCreate = true
                        }
                        Button("Opprett sesong", systemImage: "calendar.badge.plus") {
                            showingCreateSeason = true
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ATHLTHArenaV3Style.gold)
                            .frame(width: 40, height: 40)
                            .background(ATHLTHArenaV3Style.cream, in: Circle())
                    }
                    .accessibilityLabel("Opprett klubbturnering eller sesong")
                }
            }
            .foregroundStyle(ATHLTHArenaV3Style.ink)

            if let loadError {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
            }

            HStack {
                Text("Sesonger")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHArenaV3Style.ink)
                Spacer()
                Text("\(seasons.count)")
                    .font(.caption)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
            }
            if seasons.isEmpty {
                Text("Samle ligaer og cuper i én sesong, med egen oversikt og resultathistorikk.")
                    .font(.caption)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(orderedSeasons) { season in
                NavigationLink {
                    ATHLTHArenaSeasonDetailView(
                        season: season,
                        canManage: canManage
                    )
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar")
                            .foregroundStyle(ATHLTHArenaV3Style.gold)
                            .frame(width: 34, height: 34)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(season.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ATHLTHArenaV3Style.ink)
                            Text(ATHLTHArenaSeasonDate.label(season.startsOn) + " – " +
                                ATHLTHArenaSeasonDate.label(season.endsOn))
                                .font(.caption)
                                .foregroundStyle(ATHLTHArenaV3Style.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(ATHLTHArenaV3Style.secondary)
                    }
                    .padding(12)
                    .background(ATHLTHArenaV3Style.panel())
                }
                .buttonStyle(.plain)
            }

            Divider().opacity(0.45)

            HStack {
                Text("Konkurranser")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHArenaV3Style.ink)
                Spacer()
                Text("\(drafts.count + remote.count + officialTournaments.count)")
                    .font(.caption)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
            }
            if drafts.isEmpty && remote.isEmpty && officialTournaments.isEmpty {
                Text("Når klubben oppretter en liga eller cup, vises den her og i deltakernes Arena.")
                    .font(.caption)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(officialTournaments.sorted {
                $0.createdAt > $1.createdAt
            }) { tournament in
                NavigationLink {
                    ATHLTHTournamentLiveDetailView(tournament: tournament)
                } label: {
                    competitionRow(
                        title: tournament.title,
                        info: tournament.format.title + " · " +
                            (tournament.status == "completed" ? "Fullført" :
                             tournament.status == "active" ? "Pågår" : "Invitasjoner"),
                        symbol: tournament.format.symbol
                    )
                }
                .buttonStyle(.plain)
            }
            ForEach(remote) { series in
                NavigationLink {
                    ATHLTHArenaOnlineDetailView(series: series)
                } label: {
                    competitionRow(
                        title: series.title,
                        info: series.status == "completed" ? "Fullført" : "Pågår",
                        symbol: "trophy"
                    )
                }
                .buttonStyle(.plain)
            }
            ForEach(drafts) { draft in
                NavigationLink {
                    ATHLTHTournamentDraftDetailView(
                        draft: draft,
                        onPublished: { _ in
                            var all = ATHLTHTournamentDraftStore.load(
                                session.profile.userID
                            )
                            all.removeAll { $0.id == draft.id }
                            ATHLTHTournamentDraftStore.save(
                                all, owner: session.profile.userID
                            )
                            Task { await reload() }
                        }
                    )
                } label: {
                    let season = seasons.first { $0.id == draft.seasonID }
                    competitionRow(
                        title: draft.title,
                        info: (season?.title ?? "Uten sesong") + " · Utkast",
                        symbol: draft.format.symbol
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(15)
        .background(ATHLTHArenaV3Style.panel())
        .task(id: clubID) { await reload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await reload() } }
        }
        .sheet(isPresented: $showingCreate) {
            ATHLTHTournamentCreator(
                preset: .league, fixedClubID: clubID,
                onPublished: { _ in Task { await reload() } }
            ) { draft in
                var all = ATHLTHTournamentDraftStore.load(session.profile.userID)
                all.removeAll { $0.id == draft.id }
                all.insert(draft, at: 0)
                ATHLTHTournamentDraftStore.save(all, owner: session.profile.userID)
                drafts = all.filter { $0.clubID == clubID }
            }
        }
        .sheet(isPresented: $showingCreateSeason) {
            ATHLTHArenaSeasonCreateView(
                clubs: manageableClubs.filter { $0.id == clubID },
                preselectedClubID: clubID
            ) {
                Task { await reload() }
            }
        }
    }

    private func competitionRow(
        title: String, info: String, symbol: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(ATHLTHArenaV3Style.gold)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHArenaV3Style.ink)
                    .lineLimit(2)
                Text(info)
                    .font(.caption)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(ATHLTHArenaV3Style.secondary)
        }
        .padding(12)
        .background(ATHLTHArenaV3Style.panel())
    }

    @MainActor
    private func reload() async {
        drafts = ATHLTHTournamentDraftStore.load(session.profile.userID)
            .filter { $0.clubID == clubID }
        do {
            async let eligibleClubs = directory.manageableClubs()
            async let seasonRecords = cloud.loadClubSeasons()
            async let competitions = cloud.loadSeries()
            async let tournaments = tournamentCloud.visibleTournaments()
            let allowed = try await eligibleClubs
            let allSeasons = try await seasonRecords
            let allSeries = try await competitions
            let allTournaments = try await tournaments
            manageableClubs = allowed
            seasons = allSeasons.filter { $0.clubID == clubID }
            remote = allSeries.filter { $0.clubID == clubID }
            officialTournaments = allTournaments.filter { $0.clubID == clubID }
            loadError = nil
        } catch {
            loadError = "Kunne ikke laste alle klubbens sesonger og konkurranser."
        }
    }
}

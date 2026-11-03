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
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, ownerID, clubID, seasonID, title, format, groupSize
        case qualifiersPerGroup, participants, warmupRounds, createdAt
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
    @State private var selectedFilter: ATHLTHArenaV3Filter = .active
    @State private var showCreatePicker = false
    @State private var creation: ATHLTHArenaV3CreateAction?
    @State private var loadError: String?
    @State private var loadedID: UUID?
    private let cloud = ATHLTHArenaCloudService()

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
                        Text("\(remoteSeries.count + challengesForUser.count + tournaments.count + legacyDrafts.count)")
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
                       (selectedFilter != .active ||
                        (tournaments.isEmpty && legacyDrafts.isEmpty)) {
                        emptyContent
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
                                ATHLTHTournamentDraftDetailView(draft: draft)
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
                    fixedClubID: nil
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
struct ATHLTHArenaClubTournamentSection: View {
    @EnvironmentObject private var session: AppSessionStore
    let clubID: UUID
    let isOrganizer: Bool
    @State private var drafts: [ATHLTHTournamentDraft] = []
    @State private var remote: [ATHLTHArenaRemoteSeries] = []
    @State private var showingCreate = false
    private let cloud = ATHLTHArenaCloudService()

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("Cuper og ligaer")
                    .font(.system(size: 22, weight: .regular, design: .serif))
                Spacer()
                if isOrganizer {
                    Button {
                        showingCreate = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ATHLTHArenaV3Style.gold)
                            .frame(width: 36, height: 36)
                            .background(ATHLTHArenaV3Style.cream, in: Circle())
                    }
                    .accessibilityLabel("Opprett klubbkonkurranse")
                }
            }
            .foregroundStyle(ATHLTHArenaV3Style.ink)
            if drafts.isEmpty && remote.isEmpty {
                Text("Klubbens ligaer og cuper vises her.")
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
            }
            ForEach(remote) { series in
                NavigationLink {
                    ATHLTHArenaOnlineDetailView(series: series)
                } label: {
                    HStack {
                        Text(series.title)
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding(12)
                    .foregroundStyle(ATHLTHArenaV3Style.ink)
                    .background(ATHLTHArenaV3Style.panel())
                }
                .buttonStyle(.plain)
            }
            ForEach(drafts) { draft in
                NavigationLink {
                    ATHLTHTournamentDraftDetailView(draft: draft)
                } label: {
                    HStack {
                        Image(systemName: draft.format.symbol)
                            .foregroundStyle(ATHLTHArenaV3Style.gold)
                        Text(draft.title)
                            .lineLimit(1)
                        Spacer()
                        Text("Utkast").font(.caption)
                    }
                    .foregroundStyle(ATHLTHArenaV3Style.ink)
                    .padding(13)
                    .background(ATHLTHArenaV3Style.panel())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(15)
        .background(ATHLTHArenaV3Style.panel())
        .task(id: clubID) { await reload() }
        .sheet(isPresented: $showingCreate) {
            ATHLTHTournamentCreator(preset: .league, fixedClubID: clubID) { draft in
                var all = ATHLTHTournamentDraftStore.load(session.profile.userID)
                all.insert(draft, at: 0)
                ATHLTHTournamentDraftStore.save(all, owner: session.profile.userID)
                drafts = all.filter { $0.clubID == clubID }
            }
        }
    }

    @MainActor private func reload() async {
        drafts = ATHLTHTournamentDraftStore.load(session.profile.userID)
            .filter { $0.clubID == clubID }
        if let series = try? await cloud.loadSeries() {
            remote = series.filter { $0.clubID == clubID && $0.status != "completed" }
        }
    }
}

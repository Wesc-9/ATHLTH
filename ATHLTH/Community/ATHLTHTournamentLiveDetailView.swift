import SwiftUI

private enum ATHLTHTournamentDetailTab: String, CaseIterable, Identifiable {
    case lobby, overview, matches, standings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .lobby: return "Lobby"
        case .overview: return "Oversikt"
        case .matches: return "Oppgjør"
        case .standings: return "Tabell"
        }
    }
}

/// The same tournament ID opens from Arena, invitations and its club overview.
/// Never render a provisional match report as an official winner.
struct ATHLTHTournamentLiveDetailView: View {
    @EnvironmentObject private var session: AppSessionStore
    @Environment(\.scenePhase) private var scenePhase

    let tournament: ATHLTHTournamentRemote
    @State private var latest: ATHLTHTournamentRemote?
    @State private var entries: [ATHLTHTournamentRemoteEntry] = []
    @State private var matches: [ATHLTHTournamentRemoteMatch] = []
    @State private var confirmedStandings: [ATHLTHTournamentStandingRemote] = []
    @State private var names: [UUID: String] = [:]
    @State private var selection: ATHLTHTournamentDetailTab = .lobby
    @State private var showingMatchReport: ATHLTHTournamentRemoteMatch?
    @State private var editingExerciseDeadlines: ATHLTHTournamentRemoteMatch?
    @State private var busy = false
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var visibleMatchLimit = 80
    @State private var selectedGroup = 0
    @State private var pendingWithdrawal: UUID?
    @State private var showingCancelConfirmation = false

    private let cloud = ATHLTHTournamentCloudService()

    private var current: ATHLTHTournamentRemote { latest ?? tournament }
    private var userID: UUID { session.profile.userID }
    private var myEntry: ATHLTHTournamentRemoteEntry? {
        entries.first { $0.userID == userID }
    }
    private var confirmedEntries: [ATHLTHTournamentRemoteEntry] {
        entries.filter { $0.response == "accepted" }.sorted { $0.seed < $1.seed }
    }
    private var isOwner: Bool { current.ownerID == userID }
    private var pendingCount: Int { entries.filter { $0.response == "invited" }.count }
    private var visibleGroups: [Int] {
        Array(Set(confirmedEntries.compactMap(\.groupIndex))).sorted()
    }
    private var verifiedMatches: [ATHLTHTournamentRemoteMatch] {
        matches.filter { $0.isVerified }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heading
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(12)
                        .background(ATHLTHArenaV3Style.panel())
                }
                if current.status == "inviting" { invitationSection }
                Picker("Turnering", selection: $selection) {
                    ForEach(ATHLTHTournamentDetailTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                if loading {
                    ProgressView("Laster turnering…")
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    switch selection {
                    case .lobby:
                        ATHLTHTournamentLobbyView(
                            tournament: current,
                            entries: entries,
                            names: names,
                            matches: matches
                        ) {
                            await reload()
                        }
                    case .overview: overview
                    case .matches:
                        VStack(alignment: .leading,spacing: 18) {
                            if current.status == "active",
                               confirmedEntries.contains(where: { $0.userID == userID }) {
                                ATHLTHTournamentMyExercisesView(
                                    tournament: current,
                                    matches: matches,
                                    userID: userID
                                )
                            }
                            allMatchesSection
                        }
                    case .standings: standingsSection
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 17)
            .padding(.bottom, 38)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(ATHLTHArenaV3Style.cream.ignoresSafeArea())
        .navigationTitle(current.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isOwner && current.status == "inviting" {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingCancelConfirmation = true
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Avlys turnering")
                }
            }
        }
        .confirmationDialog(
            "Avlyse turneringen?",
            isPresented: $showingCancelConfirmation
        ) {
            Button("Avlys turneringen", role: .destructive) {
                Task { await cancel() }
            }
            Button("Behold turneringen", role: .cancel) {}
        } message: {
            Text("Invitasjonene avsluttes. Oppsettet blir stående i historikken.")
        }
        .confirmationDialog(
            "Trekk invitasjonen?",
            isPresented: Binding(
                get: { pendingWithdrawal != nil },
                set: { if !$0 { pendingWithdrawal = nil } }
            )
        ) {
            Button("Trekk invitasjonen", role: .destructive) {
                guard let selected = pendingWithdrawal else { return }
                pendingWithdrawal = nil
                Task { await withdraw(selected) }
            }
            Button("Avbryt", role: .cancel) { pendingWithdrawal = nil }
        } message: {
            Text("Deltakeren tas ut av invitasjonslisten. Andre svar beholdes.")
        }
        .refreshable { await reload() }
        .task(id: current.id) { await reload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await reload() } }
        }
        .sheet(item: $editingExerciseDeadlines) { match in
            ATHLTHTournamentExerciseDeadlineEditor(match: match) {
                await reload()
            }
        }
        .sheet(item: $showingMatchReport) { match in
            ATHLTHTournamentMatchReportView(match: match, names: names) {
                home, away, note in
                try await cloud.propose(
                    matchID: match.id,
                    homeScore: home,
                    awayScore: away,
                    evidence: note
                )
                await reload()
            }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text((current.format.title + " · " + statusLabel).uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.8)
                .foregroundStyle(ATHLTHArenaV3Style.gold)
            Text(current.title)
                .font(.system(size: 33, weight: .regular, design: .serif))
                .foregroundStyle(ATHLTHArenaV3Style.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 13) {
                Label("\(confirmedEntries.count) deltakere", systemImage: "person.2")
                Label("\(verifiedMatches.filter { !$0.isWarmup }.count) godkjent",
                      systemImage: "checkmark.shield")
            }
            .font(.caption)
            .foregroundStyle(ATHLTHArenaV3Style.secondary)
            if current.clubID != nil {
                Label("Klubbturnering" +
                      (current.seasonID == nil ? "" : " · Sesong"),
                      systemImage: "shield")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ATHLTHArenaV3Style.gold)
            }
            if current.status == "completed", let winner = champion {
                HStack(spacing: 9) {
                    Image(systemName: "trophy.fill")
                        .foregroundStyle(ATHLTHArenaV3Style.gold)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Turneringsvinner").font(.caption)
                        Text(name(winner)).font(.headline)
                    }
                    Spacer()
                }
                .padding(15)
                .background(ATHLTHArenaV3Style.panel())
            }
        }
    }

    private var statusLabel: String {
        switch current.status {
        case "active": return "Pågår"
        case "completed": return "Fullført"
        case "cancelled": return "Avlyst"
        default: return "Invitasjoner"
        }
    }

    private var champion: UUID? {
        guard current.format == .cup || current.format == .groups else {
            return nil
        }
        let phase: ATHLTHTournamentPhase =
            current.format == .cup ? .cup : .playoff
        let final = matches.filter { $0.phase == phase }
            .sorted { $0.roundNumber > $1.roundNumber }
            .first
        return final?.winnerID
    }

    private var invitationSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Image(systemName: "envelope")
                    .foregroundStyle(ATHLTHArenaV3Style.gold)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Invitasjoner")
                        .font(.subheadline.weight(.semibold))
                    Text(pendingCount == 0
                         ? "Alle inviterte har svart"
                         : "\(pendingCount) venter på svar")
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                }
                Spacer()
            }
            if myEntry?.response == "invited" {
                HStack(spacing: 9) {
                    Button("Godta") { Task { await respond(true) } }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(ATHLTHArenaV3Style.ink, in: Capsule())
                    Button("Avslå") { Task { await respond(false) } }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(ATHLTHArenaV3Style.cream, in: Capsule())
                }
                .font(.subheadline.weight(.semibold))
                .disabled(busy)
            } else if isOwner {
                if pendingCount == 0 && confirmedEntries.count >= 2 {
                    Button {
                        Task { await start() }
                    } label: {
                        Label("Start turneringen", systemImage: "play.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 47)
                            .background(ATHLTHArenaV3Style.ink, in: Capsule())
                    }
                    .disabled(busy)
                } else {
                    Label("Start blir tilgjengelig når alle har svart og minst to har godtatt.",
                          systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                }
            }
            ForEach(entries) { entry in
                HStack(spacing: 9) {
                    Text(name(entry.userID)).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(entry.response == "accepted" ? "Godtatt" :
                         entry.response == "declined" ? "Avslått" : "Invitert")
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                    if isOwner && entry.userID != userID &&
                       entry.response != "accepted" {
                        Button {
                            pendingWithdrawal = entry.userID
                        } label: {
                            Image(systemName: "xmark.circle")
                                .foregroundStyle(.red.opacity(0.75))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Trekk invitasjon")
                    }
                }
                .font(.caption)
            }
        }
        .padding(16)
        .background(ATHLTHArenaV3Style.panel())
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 17) {
            if let practice = matches.first(where: { $0.phase == .warmup }) {
                sectionTitle("Oppvarming")
                Text("Disse rundene gir ingen poeng, plassering eller utslag.")
                    .font(.caption)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
                ForEach(matches.filter { $0.phase == .warmup }.prefix(12)) { game in
                    matchRow(game)
                }
            }
            HStack {
                sectionTitle("Neste oppgjør")
                Spacer()
                Button("Se alle") { selection = .matches }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHArenaV3Style.gold)
            }
            let upcoming = matches.filter {
                !$0.isWarmup && $0.status != "confirmed"
            }.prefix(4)
            if upcoming.isEmpty {
                Text(current.status == "inviting"
                     ? "Oppsettet vises når alle har godtatt invitasjonen."
                     : "Ingen uavklarte oppgjør.")
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
                    .font(.subheadline)
                    .padding(15)
                    .background(ATHLTHArenaV3Style.panel())
            } else {
                ForEach(Array(upcoming)) { match in matchRow(match) }
            }
            if !confirmedEntries.isEmpty {
                HStack {
                    sectionTitle(current.format == .cup ? "Cup" : "Tabell")
                    Spacer()
                    Button("Se oversikt") { selection = .standings }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHArenaV3Style.gold)
                }
                standingsSection
            }
        }
    }

    private var allMatchesSection: some View {
        LazyVStack(alignment: .leading, spacing: 11) {
            let games = matches.sorted { a, b in
                if a.phase == .warmup && b.phase != .warmup { return true }
                if a.phase != .warmup && b.phase == .warmup { return false }
                if a.roundNumber != b.roundNumber {
                    return a.roundNumber < b.roundNumber
                }
                return a.slotIndex < b.slotIndex
            }
            if games.isEmpty {
                Text("Kampoppsettet er ikke klart ennå.")
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
            }
            ForEach(Array(games.prefix(visibleMatchLimit))) { match in
                matchRow(match)
            }
            if games.count > visibleMatchLimit {
                Button("Vis flere oppgjør") {
                    visibleMatchLimit += 80
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHArenaV3Style.gold)
                .frame(maxWidth: .infinity)
                .padding(12)
            }
        }
    }

    private var standingsSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            if current.format == .cup {
                cupTree
            } else if current.format == .groups {
                groupsTable
            } else {
                rankingTable(for: confirmedEntries, groupIndex: nil)
            }
            Text("Bare bekreftede resultater påvirker tabellen. Ved poenglikhet brukes målforskjell, score, seire og deretter en fast rekkefølge.")
                .font(.caption)
                .foregroundStyle(ATHLTHArenaV3Style.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var groupsTable: some View {
        VStack(alignment: .leading, spacing: 13) {
            if !visibleGroups.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(visibleGroups, id: \.self) { group in
                            Button("Gruppe \(group + 1)") { selectedGroup = group }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 15)
                                .padding(.vertical, 10)
                                .foregroundStyle(selectedGroup == group
                                    ? Color.white : ATHLTHArenaV3Style.ink)
                                .background(selectedGroup == group
                                    ? ATHLTHArenaV3Style.ink : Color.white,
                                    in: Capsule())
                        }
                    }
                }
                let group = visibleGroups.contains(selectedGroup)
                    ? selectedGroup : visibleGroups[0]
                rankingTable(for: confirmedEntries.filter {
                    $0.groupIndex == group
                }, groupIndex: group)
                if matches.contains(where: { $0.phase == .playoff }) {
                    cupTree
                } else {
                    Text("Topp \(current.qualifiersPerGroup) fra hver gruppe går videre når alle grupperesultater er godkjent.")
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                }
            } else {
                Text("Gruppene dannes når turneringen starter.")
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
            }
        }
    }

    private func rankingTable(
        for athletes: [ATHLTHTournamentRemoteEntry], groupIndex: Int?
    ) -> some View {
        // The authoritative qualification order comes from PostgreSQL, not
        // from an independent client tie-break calculation.
        let eligible = Set(athletes.map(\.userID))
        let rank = confirmedStandings
            .filter { $0.groupIndex == groupIndex && eligible.contains($0.userID) }
            .sorted { $0.rank < $1.rank }

        return VStack(spacing: 10) {
            HStack {
                Text("#").frame(width: 22, alignment: .leading)
                Text("Utøver")
                Spacer(minLength: 4)
                Text("K").frame(width: 20)
                Text("MF").frame(width: 36)
                Text("P").frame(width: 24)
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(ATHLTHArenaV3Style.secondary)

            if rank.isEmpty {
                Text("Tabellen vises når deltakerne har godtatt invitasjonene.")
                    .font(.caption)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(rank) { item in
                HStack(spacing: 7) {
                    Text("\(item.rank)")
                        .frame(width: 22, alignment: .leading)
                        .foregroundStyle(ATHLTHArenaV3Style.gold)
                    Text(item.username)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(item.played)").frame(width: 20)
                    Text(String(format: "%+.1f", item.difference))
                        .frame(width: 36)
                        .minimumScaleFactor(0.75)
                    Text("\(item.points)")
                        .fontWeight(.semibold)
                        .frame(width: 24)
                }
                .font(.subheadline)
                .foregroundStyle(ATHLTHArenaV3Style.ink)
                if item.id != rank.last?.id {
                    Divider().opacity(0.5)
                }
            }
        }
        .padding(15)
        .background(ATHLTHArenaV3Style.panel())
    }

    private var cupTree: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Utslagstre")
            let bracket = matches.filter {
                $0.phase == .cup || $0.phase == .playoff
            }
            let rounds = Array(Set(bracket.map(\.roundNumber))).sorted()
            if rounds.isEmpty {
                Text("Cupoppsettet vises når turneringen starter.")
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(rounds, id: \.self) { round in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(round == rounds.last && bracket.filter {
                                    $0.roundNumber == round
                                }.count == 1 ? "Finale" : "Runde \(round)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(ATHLTHArenaV3Style.gold)
                                ForEach(bracket.filter {
                                    $0.roundNumber == round
                                }.sorted { $0.slotIndex < $1.slotIndex }) { game in
                                    VStack(alignment: .leading, spacing: 9) {
                                        Text(name(game.homeID))
                                        Divider().opacity(0.6)
                                        Text(game.awayID.map(name) ?? "Frirunde")
                                        if let winner = game.winnerID {
                                            Label(name(winner), systemImage: "checkmark")
                                                .font(.caption2)
                                                .foregroundStyle(ATHLTHArenaV3Style.gold)
                                        }
                                    }
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(ATHLTHArenaV3Style.ink)
                                    .frame(width: 154, alignment: .leading)
                                    .padding(11)
                                    .background(ATHLTHArenaV3Style.panel())
                                }
                            }
                        }
                    }
                    .padding(.bottom, 5)
                }
            }
        }
    }

    private func matchRow(_ match: ATHLTHTournamentRemoteMatch)
        -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(match.isWarmup ? "OPPVARMING · 0 POENG" :
                     match.phase == .group ? "GRUPPE \((match.groupIndex ?? 0) + 1)" :
                     "RUNDE \(match.roundNumber)")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(ATHLTHArenaV3Style.gold)
                Spacer()
                Text(match.isBye ? "Frirunde" :
                     match.status == "confirmed" ? "Godkjent" :
                     match.status == "proposed" ? "Avventer godkjenning" :
                     match.status == "disputed" ? "Bestridt" : "Ikke avgjort")
                    .font(.caption2)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(name(match.homeID))
                        .font(.subheadline.weight(.semibold))
                    Text(match.awayID.map(name) ?? "Frirunde")
                        .font(.subheadline)
                }
                Spacer()
                if match.isVerified, let home = match.homeScore,
                   let away = match.awayScore {
                    VStack(alignment: .trailing, spacing: 5) {
                        Text(String(format: "%.1f", home))
                        Text(String(format: "%.1f", away))
                    }
                    .font(.subheadline.monospacedDigit())
                } else {
                    Image(systemName: "arrow.left.arrow.right")
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                }
            }
            .foregroundStyle(ATHLTHArenaV3Style.ink)

            if let deadline = match.deadlineAt, !match.isBye {
                let overdue = deadline < Date() && match.status != "confirmed"
                HStack(spacing: 6) {
                    Image(systemName: overdue ? "clock.badge.exclamationmark" : "calendar")
                    Text((overdue ? "Frist passert · " : "Frist · ") +
                         deadline.formatted(date: .abbreviated, time: .omitted))
                }
                .font(.caption)
                .foregroundStyle(overdue ? .orange : ATHLTHArenaV3Style.secondary)
                if overdue {
                    Text("Resultatet må fortsatt avklares – ingen blir automatisk slått ut.")
                        .font(.caption2)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                }
                if isOwner && current.status == "active" &&
                   match.awayID != nil && match.status != "confirmed" &&
                   deadline < Date().addingTimeInterval(22 * 86_400) {
                    Button {
                        Task { await extendDeadline(for: match) }
                    } label: {
                        Label("Forleng frist", systemImage: "calendar.badge.plus")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHArenaV3Style.gold)
                    }
                    .disabled(busy)
                }
            }

            if current.status == "active", match.awayID != nil,
               match.homeID == userID || match.awayID == userID {
                if let opens = match.scheduledAt, opens > Date() {
                    Label(
                        "Runden åpner " +
                        opens.formatted(date: .abbreviated, time: .omitted),
                        systemImage: "lock.clock"
                    )
                    .font(.caption)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
                } else if match.status == "scheduled" || match.status == "disputed" {
                    Button("Foreslå resultat") { showingMatchReport = match }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHArenaV3Style.gold)
                } else if match.status == "proposed",
                          match.proposedBy != userID {
                    HStack(spacing: 11) {
                        Button("Godkjenn") {
                            Task { await confirm(match.id, true) }
                        }
                        .foregroundStyle(ATHLTHArenaV3Style.gold)
                        Button("Bestrid") {
                            Task { await confirm(match.id, false) }
                        }
                        .foregroundStyle(.red)
                    }
                    .font(.caption.weight(.semibold))
                    .disabled(busy)
                }
            }
            if isOwner && current.status == "active" &&
               !match.isWarmup && match.awayID != nil &&
               match.status != "confirmed" {
                Button {
                    editingExerciseDeadlines = match
                } label: {
                    Label("Juster øvelsesfrister",systemImage: "calendar")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHArenaV3Style.gold)
                }
            }
            if match.isWarmup {
                Text("Denne runden påvirker aldri poeng, tabell eller avansement.")
                    .font(.caption2)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
            }
        }
        .padding(15)
        .background(ATHLTHArenaV3Style.panel())
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 23, weight: .regular, design: .serif))
            .foregroundStyle(ATHLTHArenaV3Style.ink)
    }

    private func name(_ id: UUID) -> String {
        if id == userID {
            let handle = session.profile.username.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            return handle.isEmpty ? "Du" : handle
        }
        return names[id] ?? "Utøver"
    }

    @MainActor private func reload() async {
        loading = true
        defer { loading = false }
        do {
            async let allTournaments = cloud.visibleTournaments()
            async let participants = cloud.entries(for: current.id)
            async let competitionMatches = cloud.matches(for: current.id)
            async let officialRankings = cloud.standings(for: current.id)
            let all = try await allTournaments
            let newEntries = try await participants
            let newMatches = try await competitionMatches
            let updatedRankings = try await officialRankings
            latest = all.first { $0.id == current.id } ?? latest
            entries = newEntries
            matches = newMatches
            confirmedStandings = updatedRankings
            names = try await cloud.athleteNames(
                for: Set(newEntries.map(\.userID))
            )
            errorMessage = nil
        } catch {
            errorMessage = "Kunne ikke hente konkurransen: " +
                error.localizedDescription
        }
    }

    @MainActor private func respond(_ accepted: Bool) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await cloud.respond(tournamentID: current.id, accept: accepted)
            await reload()
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func start() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await cloud.start(tournamentID: current.id)
            await reload()
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func withdraw(_ athlete: UUID) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await cloud.withdrawInvitation(
                tournamentID: current.id, athleteID: athlete
            )
            await reload()
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func cancel() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await cloud.cancelUnstarted(tournamentID: current.id)
            await reload()
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func extendDeadline(
        for match: ATHLTHTournamentRemoteMatch
    ) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let baseline = max(match.deadlineAt ?? Date(), Date())
            let newDeadline = baseline.addingTimeInterval(7 * 86_400)
            try await cloud.extendDeadline(
                matchID: match.id, until: newDeadline
            )
            await reload()
        } catch {
            errorMessage = "Kunne ikke forlenge fristen: " +
                error.localizedDescription
        }
    }

    @MainActor private func confirm(_ id: UUID, _ accepted: Bool) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await cloud.confirm(matchID: id, approved: accepted)
            await reload()
        } catch { errorMessage = error.localizedDescription }
    }
}

struct ATHLTHTournamentMatchReportView: View {
    @Environment(\.dismiss) private var dismiss

    let match: ATHLTHTournamentRemoteMatch
    let names: [UUID: String]
    let onSubmit: @MainActor (Double, Double, String) async throws -> Void

    @State private var homeValue = ""
    @State private var awayValue = ""
    @State private var evidence = ""
    @State private var confirmed = false
    @State private var sending = false
    @State private var errorMessage: String?

    private var home: Double? {
        Double(homeValue.replacingOccurrences(of: ",", with: "."))
    }
    private var away: Double? {
        Double(awayValue.replacingOccurrences(of: ",", with: "."))
    }
    private var valid: Bool {
        guard let home, let away else { return false }
        return home.isFinite && away.isFinite &&
            home >= 0 && away >= 0 &&
            (!match.phase.eliminates || home != away) &&
            evidence.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 &&
            confirmed && !sending
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    Text(match.isWarmup ? "Oppvarmingsrunde" : "Rapporter oppgjør")
                        .font(.system(size: 29, design: .serif))
                    Text(match.isWarmup
                         ? "Resultatet er kun til trening. Ingen poeng eller utslag."
                         : "Motstanderen må godkjenne før resultatet påvirker konkurransen.")
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                    scoreField(names[match.homeID] ?? "Utøver 1", value: $homeValue)
                    if let other = match.awayID {
                        scoreField(names[other] ?? "Utøver 2", value: $awayValue)
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Resultatgrunnlag")
                            .font(.subheadline.weight(.medium))
                        TextField("Beskriv økten eller resultatet", text: $evidence, axis: .vertical)
                            .lineLimit(2...4)
                            .padding(13)
                            .background(ATHLTHArenaV3Style.panel())
                    }
                    Toggle("Jeg bekrefter at resultatene er riktige", isOn: $confirmed)
                        .font(.subheadline)
                        .tint(ATHLTHArenaV3Style.gold)
                    if let errorMessage {
                        Text(errorMessage).font(.caption).foregroundStyle(.red)
                    }
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            if sending { ProgressView().tint(.white) }
                            Text(sending ? "Sender…" : "Send til godkjenning")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(ATHLTHArenaV3Style.ink, in: Capsule())
                    }
                    .disabled(!valid)
                    .opacity(valid ? 1 : 0.5)
                }
                .padding(19)
            }
            .background(ATHLTHArenaV3Style.cream.ignoresSafeArea())
            .navigationTitle("Resultat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Lukk") { dismiss() }
                        .disabled(sending)
                }
            }
        }
        .environment(\.colorScheme, .light)
    }

    private func scoreField(_ title: String, value: Binding<String>) -> some View {
        HStack {
            Text(title).lineLimit(1)
            Spacer()
            TextField("0", text: value)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
        }
        .font(.subheadline)
        .padding(15)
        .background(ATHLTHArenaV3Style.panel())
    }

    @MainActor private func submit() async {
        guard valid, let home, let away else { return }
        sending = true
        defer { sending = false }
        do {
            try await onSubmit(home, away, evidence)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

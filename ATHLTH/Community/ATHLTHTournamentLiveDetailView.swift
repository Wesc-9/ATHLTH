import SwiftUI
import MapKit

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
    var openChatInitially = false
    @State private var latest: ATHLTHTournamentRemote?
    @State private var entries: [ATHLTHTournamentRemoteEntry] = []
    @State private var matches: [ATHLTHTournamentRemoteMatch] = []
    @State private var confirmedStandings: [ATHLTHTournamentStandingRemote] = []
    @State private var athleteProgress: [ATHLTHTournamentAthleteProgress] = []
    @State private var names: [UUID: String] = [:]
    @State private var exerciseCandidates: [ATHLTHTournamentExerciseCandidateRemote] = []
    @State private var exerciseNames: [UUID: String] = [:]
    @State private var exerciseLoadFailed = false
    @State private var selection: ATHLTHTournamentDetailTab = .overview
    @State private var showingMatchReport: ATHLTHTournamentRemoteMatch?
    @State private var editingExerciseDeadlines: ATHLTHTournamentRemoteMatch?
    @State private var busy = false
    @State private var publishingFeed = false
    @State private var loading = true
    @State private var reloading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @State private var visibleMatchLimit = 80
    @State private var selectedGroup = 0
    @State private var pendingWithdrawal: UUID?
    @State private var showingCancelConfirmation = false
    @State private var nextSeasonDraft: ATHLTHTournamentDraft?
    @State private var continuationExists = false
    @State private var checkingSeasonRenewal = false
    @State private var seasonNotice: String?
    @State private var seasonHistory: [ATHLTHTournamentRemote] = []
    @State private var showAllSeasons = false

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
    private var minimumAthletes: Int {
        current.minimumAthletes
    }
    private var readyToStart: Bool {
        (current.isDuel ? confirmedEntries.count == 2 : confirmedEntries.count >= minimumAthletes) &&
        (current.unansweredPolicy != "replace" ||
         current.replacementUntil == nil) &&
        pendingCount == 0 &&
        confirmedEntries.allSatisfy {
            $0.isReady && $0.agreedRuleVersion == current.ruleVersion
        } &&
        current.rulesConfirmedAt != nil &&
        current.exerciseSelectionFinalizedAt != nil
    }
    private var visibleRoundComplete: Bool {
        matches.contains { match in
            !match.isWarmup && match.status == "confirmed" &&
            !matches.contains { other in
                other.phase == match.phase &&
                other.roundNumber == match.roundNumber &&
                other.groupIndex == match.groupIndex &&
                !other.isBye && other.status != "confirmed"
            }
        }
    }
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
                    ForEach(current.singleEventMode ?
                            [.overview, .lobby] :
                            ATHLTHTournamentDetailTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                if loading {
                    ProgressView("Laster konkurranse…")
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    switch selection {
                    case .lobby:
                        ATHLTHTournamentLobbyView(
                            tournament: current,
                            entries: entries,
                            names: names,
                            matches: matches,
                            openChatInitially: openChatInitially
                        ) {
                            await reload()
                        }
                    case .overview: overview
                    case .matches:
                        if current.singleEventMode {
                            singleEventSection
                        } else {
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
                        }
                    case .standings:
                        if current.singleEventMode {
                            singleEventSection
                        } else { standingsSection }
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
        .sheet(isPresented: $showingCancelConfirmation) {
            ATHLTHCompetitionConfirmationCard(
                title: "Avlyse konkurransen?",
                message: "Invitasjonene avsluttes. Oppsettet blir stående i historikken.",
                actionTitle: "Avlys konkurransen",
                onConfirm: { Task { await cancel() } }
            )
        }
        .sheet(isPresented: Binding(
            get: { pendingWithdrawal != nil },
            set: { if !$0 { pendingWithdrawal = nil } }
        )) {
            ATHLTHCompetitionConfirmationCard(
                title: "Trekke invitasjonen?",
                message: "Deltakeren tas ut av invitasjonslisten. Andre svar beholdes.",
                actionTitle: "Trekk invitasjonen",
                onConfirm: {
                    guard let selected = pendingWithdrawal else { return }
                    pendingWithdrawal = nil
                    Task { await withdraw(selected) }
                }
            )
        }
        .refreshable { await reload() }
        .task(id: current.id) { await reload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await reload() } }
        }
        .fullScreenCover(item: $nextSeasonDraft) { draft in
            ATHLTHTournamentCreator(
                preset: draft.format,
                fixedClubID: draft.clubID,
                continuation: draft,
                fixedInvitees: draft.competitionSettings.race.duelMode == true ? draft.participants.filter { $0.id != userID } : nil,
                onPublished: { _ in
                    nextSeasonDraft = nil
                    continuationExists = true
                    seasonNotice = draft.competitionSettings.race.duelMode == true ? "Rematch sendt som ny invitasjon." : "Ny sesong opprettet. Forrige sesongs resultater er bevart."
                    Task { await reload() }
                },
                onSave: { newDraft in
                    var stored = ATHLTHTournamentDraftStore.load(userID)
                    stored.append(newDraft)
                    ATHLTHTournamentDraftStore.save(stored, owner: userID)
                    nextSeasonDraft = nil
                    seasonNotice = draft.competitionSettings.race.duelMode == true ? "Rematch lagret som utkast." : "Neste sesong er lagret som utkast i Arena."
                }
            )
        }
        .alert("Konkurranse", isPresented: Binding(
            get: { seasonNotice != nil },
            set: { if !$0 { seasonNotice = nil } }
        )) {
            Button("OK") { seasonNotice = nil }
        } message: {
            Text(seasonNotice ?? "")
        }
        .fullScreenCover(item: $editingExerciseDeadlines) { match in
            ATHLTHTournamentExerciseDeadlineEditor(match: match) {
                await reload()
            }
        }
        .fullScreenCover(item: $showingMatchReport) { match in
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
            Text((current.displayFormatTitle + " · " + statusLabel).uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.8)
                .foregroundStyle(ATHLTHArenaV3Style.gold)
            Text(current.title)
                .font(.system(size: 33, weight: .regular, design: .serif))
                .foregroundStyle(ATHLTHArenaV3Style.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 13) {
                Label("\(confirmedEntries.count)/\(confirmedEntries.count + pendingCount) bekreftet", systemImage: "person.2")
                if !current.singleEventMode {
                    Label("\(verifiedMatches.filter { !$0.isWarmup }.count) godkjent",
                          systemImage: "checkmark.shield")
                }
            }
            .font(.caption)
            .foregroundStyle(ATHLTHArenaV3Style.secondary)
            if current.status == "inviting" {
                Text(current.startMode == "scheduled"
                     ? "Starter ved valgt tidspunkt når alle er klare"
                     : current.startMode == "when_ready"
                     ? "Starter automatisk når alle er klare"
                     : "Arrangøren starter når alle er klare")
                    .font(.caption)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
            }
            if let date = current.plannedStartsAt,
               current.startMode == "scheduled" {
                Label("Planlagt start: " + date.formatted(
                    date: .abbreviated, time: .shortened),
                      systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(ATHLTHArenaV3Style.gold)
            }
            if current.clubID != nil {
                Label("Klubbturnering" +
                      (current.seasonID == nil ? "" : " · Sesong"),
                      systemImage: "shield")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ATHLTHArenaV3Style.gold)
            }
            if let season = current.seasonLabel {
                Label(season, systemImage: "calendar").font(.caption.weight(.medium))
                    .foregroundStyle(ATHLTHArenaV3Style.gold)
            }
            if current.isDuel && current.status == "completed" {
                if ATHLTHDuelRematch.canRematch(current, entries: entries, userID: userID) {
                    Button {
                        Task { await prepareRematch() }
                    } label: {
                        Label(continuationExists ? "Rematch allerede opprettet" : "Ta rematch", systemImage: "arrow.clockwise.circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white).frame(maxWidth: .infinity)
                            .padding(15).background(ATHLTHArenaV3Style.ink, in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain).disabled(checkingSeasonRenewal || continuationExists)
                    Text("Din tur til å velge øvelsene. Bruk de samme eller velg nye, og send en ny invitasjon.")
                        .font(.caption).foregroundStyle(ATHLTHArenaV3Style.secondary)
                } else if current.ownerID == userID {
                    Text("Motstanderen får velge øvelsene ved rematch.")
                        .font(.caption).foregroundStyle(ATHLTHArenaV3Style.secondary)
                }
            }
            if !current.singleEventMode &&
               ATHLTHTournamentSeasonContinuation.canContinue(
                format: current.format,
                status: current.status,
                ownerID: current.ownerID,
                currentUserID: userID
            ) {
                Button {
                    Task { await prepareNextSeason() }
                } label: {
                    HStack(spacing: 10) {
                        if checkingSeasonRenewal {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "arrow.clockwise.circle")
                        }
                        Text("Fortsett til neste sesong")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(15)
                    .background(ATHLTHArenaV3Style.ink,
                                in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .disabled(checkingSeasonRenewal || continuationExists)
                .accessibilityIdentifier("athlth-tournament-next-season")
                Text(
                    "Ny sesong får egen tabell, nye invitasjoner og nullstilte poeng. " +
                    "Tidligere sesong forblir i historikken."
                )
                .font(.caption)
                .foregroundStyle(ATHLTHArenaV3Style.secondary)
            }
            if current.status == "completed" && isOwner &&
               current.allowFeedPost {
                if current.feedPublishedAt == nil {
                    Button {
                        Task { await publishToFeed() }
                    } label: {
                        HStack(spacing: 10) {
                            if publishingFeed { ProgressView() }
                            else { Image(systemName: "square.and.arrow.up") }
                            Text("Publiser konkurransen i Feed")
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHArenaV3Style.gold)
                        .padding(14)
                        .background(ATHLTHArenaV3Style.panel())
                    }
                    .disabled(publishingFeed)
                } else {
                    Label("Konkurransen er delt i vennefeeden",
                          systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaV3Style.gold)
                }
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
            if let me = myEntry, me.response == "invited",
               let expires = me.expiresAt {
                Label(expires > Date()
                      ? "Svar innen " + expires.formatted(
                            date: .abbreviated, time: .shortened)
                      : "Svarfristen er utløpt",
                      systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(expires > Date()
                        ? ATHLTHArenaV3Style.secondary : .orange)
            }
            if myEntry?.response == "invited",
               myEntry?.expiresAt.map({ $0 > Date() }) ?? false {
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
                if current.startMode == "manual" && readyToStart {
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
                    Label(current.startMode == "manual"
                          ? "Venter på Klar fra alle (minst \(minimumAthletes) deltakere)"
                          : "Starter automatisk når alle er klare og startvilkårene er oppfylt.",
                          systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                }
            }
            if myEntry?.response == "accepted" &&
               myEntry?.isReady == false && !current.simpleMode {
                if current.rulesConfirmedAt != nil &&
                   myEntry?.agreedRuleVersion == current.ruleVersion &&
                   current.exerciseSelectionFinalizedAt != nil {
                    Button {
                        Task {
                            await markReady()
                        }
                    } label: {
                        Label("Jeg er klar", systemImage: "checkmark.circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(ATHLTHArenaV3Style.ink, in: Capsule())
                    }
                    .disabled(busy)
                } else {
                    Button("Se og godta reglene før du trykker Klar") {
                        selection = .lobby
                    }
                    .font(.caption.weight(.semibold))
                    .tint(ATHLTHArenaV3Style.gold)
                }
            }
            if let window = current.replacementUntil, isOwner {
                VStack(alignment: .leading, spacing: 7) {
                    Label("Erstatningsperiode frem til " + window.formatted(
                        date: .abbreviated, time: .shortened),
                        systemImage: "person.crop.circle.badge.plus")
                        .font(.subheadline.weight(.semibold))
                    Text("Inviter en erstatter fra Lobby, eller fortsett med eksisterende deltakere når minst \(minimumAthletes) har godtatt.")
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                    Button("Finn erstatter i Lobby") { selection = .lobby }
                        .font(.subheadline.weight(.semibold))
                        .tint(ATHLTHArenaV3Style.gold)
                    if pendingCount == 0 &&
                       confirmedEntries.count >= minimumAthletes {
                        Button("Avslutt erstatningsperioden") {
                            Task { await finishReplacement() }
                        }
                        .font(.subheadline.weight(.semibold))
                        .tint(ATHLTHArenaV3Style.gold)
                        .disabled(busy)
                    }
                }
            }
            ForEach(entries) { entry in
                HStack(spacing: 9) {
                    Text(name(entry.userID)).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(entry.response == "accepted"
                         ? (entry.isReady ? "Klar" : "Ikke klar") :
                         entry.response == "declined" ? "Avslått" :
                         entry.response == "expired" ? "Utløpt" : "Invitert")
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
            competitionExercises
            eventInformation
            if !current.singleEventMode && !current.isDuel { seasonHistorySection }
            athleteProgressSection
            ATHLTHCompetitionLiveMapView(
                tournament: current,
                userID: userID,
                names: names
            )
            if current.singleEventMode {
                singleEventSection
            }
            NavigationLink {
                ATHLTHTournamentGroupConversationView(tournament: current)
            } label: {
                Label("Åpne konkurransesamtalen", systemImage: "bubble.left.and.bubble.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHArenaV3Style.gold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(ATHLTHArenaV3Style.panel())
            }
            if !current.singleEventMode {
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
            } // Separate events never display a fictitious league fixture.
        }
    }

    private var seasonHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("Sesonghistorikk")
                Spacer()
                if seasonHistory.count > 5 {
                    Button(showAllSeasons ? "Vis færre" : "Se alle") {
                        showAllSeasons.toggle()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHArenaV3Style.gold)
                }
            }
            Text("Hver sesong har egne oppgjør, resultater og tabeller.")
                .font(.caption)
                .foregroundStyle(ATHLTHArenaV3Style.secondary)
            ForEach(Array(seasonHistory.prefix(showAllSeasons ? seasonHistory.count : 5))) { season in
                if season.id == current.id {
                    seasonHistoryRow(season, isCurrent: true)
                } else {
                    NavigationLink {
                        ATHLTHTournamentLiveDetailView(tournament: season)
                    } label: {
                        seasonHistoryRow(season, isCurrent: false)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(15)
        .background(ATHLTHArenaV3Style.panel())
        .accessibilityIdentifier("athlth-tournament-season-history")
    }

    private func seasonHistoryRow(_ season: ATHLTHTournamentRemote, isCurrent: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: season.status == "completed" ? "trophy" : "calendar")
                .foregroundStyle(ATHLTHArenaV3Style.gold)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(season.seasonLabel ?? season.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHArenaV3Style.ink)
                Text(season.title)
                    .font(.caption)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
                if let date = season.completedAt ?? season.startedAt ?? season.plannedStartsAt {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(season.status == "completed" ? "Fullført" :
                     season.status == "active" ? "Pågår" :
                     season.status == "cancelled" ? "Avlyst" : "Invitasjoner")
                    .font(.caption.weight(.medium))
                if isCurrent {
                    Text("Denne sesongen").font(.caption2)
                } else {
                    Image(systemName: "chevron.right").font(.caption)
                }
            }
            .foregroundStyle(ATHLTHArenaV3Style.secondary)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private var singleEventSection: some View {
        ATHLTHTournamentSingleEventView(
            tournament: current,
            userID: userID,
            names: names
        ) {
            await reload()
        }
    }

    private var competitionExercises: some View {
        let selected = exerciseCandidates.filter { $0.selectedPosition != nil }
            .sorted { ($0.selectedPosition ?? 0) < ($1.selectedPosition ?? 0) }
        let visible = selected.isEmpty && current.exerciseSelectionFinalizedAt == nil
            ? exerciseCandidates : selected
        return VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Konkurranseøvelser")
            Text("\(current.exerciseCount) øvelser · " + (current.exerciseSelectionFinalizedAt == nil ? "Utvalg ikke endelig" : "Bekreftet oppsett"))
                .font(.caption).foregroundStyle(ATHLTHArenaV3Style.secondary)
            if exerciseLoadFailed {
                Text("Kunne ikke hente alle øvelsesdetaljene. Dra ned for å oppdatere.")
                    .font(.caption).foregroundStyle(ATHLTHArenaV3Style.secondary)
            }
            if visible.isEmpty {
                Text("Ingen øvelser tilgjengelig ennå.")
                    .font(.subheadline).foregroundStyle(ATHLTHArenaV3Style.secondary)
            }
            ForEach(visible) { candidate in
                NavigationLink {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(exerciseNames[candidate.lookupID] ?? "Øvelse")
                            .font(.system(size: 30, design: .serif))
                        Label("Frist per øvelse: \(current.completionHours) timer", systemImage: "clock")
                        Text("Detaljert øvelsesinstruksjon er ikke tilgjengelig her ennå.")
                            .foregroundStyle(ATHLTHArenaV3Style.secondary)
                        Spacer()
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ATHLTHArenaV3Style.cream.ignoresSafeArea())
                    .navigationTitle("Øvelsesdetaljer")
                    .navigationBarTitleDisplayMode(.inline)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: candidate.activityTemplateID == nil ? "dumbbell" : "figure.run")
                            .foregroundStyle(ATHLTHArenaV3Style.gold)
                            .frame(width: 44, height: 44)
                            .background(ATHLTHArenaV3Style.cream, in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exerciseNames[candidate.lookupID] ?? "Øvelse")
                                .font(.subheadline.weight(.semibold))
                            Text(candidate.selectedPosition == nil ? "Foreslått" : "Valgt øvelse")
                                .font(.caption).foregroundStyle(ATHLTHArenaV3Style.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                            .foregroundStyle(ATHLTHArenaV3Style.secondary)
                    }
                    .foregroundStyle(ATHLTHArenaV3Style.ink)
                }.buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ATHLTHArenaV3Style.panel())
    }

    private var eventInformation: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionTitle("Konkurranseregler")
            if current.requiredEnvironment != "any" {
                Label(ATHLTHCompetitionEnvironment(rawValue: current.requiredEnvironment)?.title ?? "Ukjent treningsmiljø", systemImage: "checkmark.shield")
                    .font(.subheadline.weight(.medium))
            }
            if let place = current.meetingPlace, !place.isEmpty {
                Label(place, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
            }
            if let lat = current.meetingLat, let lon = current.meetingLon {
                Button {
                    let pin = MKMapItem(placemark: MKPlacemark(
                        coordinate: CLLocationCoordinate2D(
                            latitude: lat, longitude: lon
                        )
                    ))
                    pin.name = current.meetingPlace ?? "Møtepunkt"
                    pin.openInMaps()
                } label: {
                    Label("Åpne møtepunkt i Kart",
                          systemImage: "map")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHArenaV3Style.gold)
                }
            }
            Text(current.releaseMode == "everyone_finished"
                ? "Neste øvelse åpnes når alle er ferdige."
                : "Neste øvelse åpnes etter avtalt tidsintervall.")
                .font(.caption)
                .foregroundStyle(ATHLTHArenaV3Style.secondary)
            Text("Frist per øvelse: \(current.completionHours) timer")
                .font(.caption)
                .foregroundStyle(ATHLTHArenaV3Style.secondary)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ATHLTHArenaV3Style.panel())
    }

    private var athleteProgressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Deltakerstatus")
            Text("Status er synlig uten at skjulte resultater eller privat trening deles.")
                .font(.caption)
                .foregroundStyle(ATHLTHArenaV3Style.secondary)
            ForEach(confirmedEntries) { entry in
                let progress = athleteProgress.first { $0.userID == entry.userID }
                HStack(spacing: 10) {
                    Image(systemName: progress?.symbol ?? "clock")
                        .foregroundStyle(ATHLTHArenaV3Style.gold)
                        .frame(width: 27)
                    Text(name(entry.userID))
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(progress?.label ?? (entry.isReady ? "Venter start" : "Ikke klar"))
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                }
                .padding(.vertical, 5)
            }
        }
        .padding(15)
        .background(ATHLTHArenaV3Style.panel())
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
            if current.format != .cup && current.status == "active" &&
               !visibleRoundComplete {
                Label("Resultater og tabell er skjult frem til alle oppgjørene i runden er godkjent.",
                      systemImage: "lock.shield")
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
                    .padding(14)
                    .background(ATHLTHArenaV3Style.panel())
            } else if current.format == .cup {
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
                     match.status == "confirmed" &&
                       match.homeScore == nil ? "Ferdig · skjult resultat" :
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
                if isOwner && current.allowExtensions &&
                   current.status == "active" &&
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
                } else if current.raceRules.scoringMode != nil && match.status == "disputed" && match.phase.eliminates && match.homeScore != nil && match.homeScore == match.awayScore {
                    Button("Registrer avtalt omkamp") { showingMatchReport = match }
                        .font(.caption.weight(.semibold)).foregroundStyle(ATHLTHArenaV3Style.gold)
                    Text("Oppgjøret er uavgjort. Gjennomfør en avtalt omkamp, og få resultatet godkjent av motstanderen.").font(.caption2)
                } else if (match.status == "scheduled" || match.status == "disputed") && (current.raceRules.scoringMode == nil || match.isWarmup) {
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
            if isOwner && current.allowExtensions &&
               current.status == "active" &&
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
        guard !reloading else { return }
        reloading = true
        loading = !hasLoaded
        defer { loading = false; reloading = false }
        for attempt in 0...1 {
        do {
            async let allTournaments = cloud.visibleTournaments()
            async let participants = cloud.entries(for: current.id)
            async let competitionMatches = cloud.matches(for: current.id)
            async let officialRankings = cloud.standings(for: current.id)
            async let progress = cloud.athleteProgress(for: current.id)
            let all = try await allTournaments
            let newEntries = try await participants
            let newMatches = try await competitionMatches
            let updatedRankings = try await officialRankings
            // Nonparticipants may view public results but not private athlete
            // presence. That must never prevent the public detail from loading.
            let statuses = (try? await progress) ?? []
            try Task.checkCancellation()
            latest = all.first { $0.id == current.id } ?? latest
            seasonHistory = ATHLTHTournamentSeasonContinuation.history(current: current, visible: all)
            continuationExists = all.contains {
                $0.raceRules.previousCompetitionID == current.id && $0.status != "cancelled"
            }
            entries = newEntries
            matches = newMatches
            confirmedStandings = updatedRankings
            athleteProgress = statuses
            hasLoaded = true
            if let updatedNames = try? await cloud.athleteNames(for: Set(newEntries.map(\.userID))) {
                names.merge(updatedNames) { _, new in new }
            }
            let lobby = ATHLTHTournamentLobbyCloudService()
            do {
                let candidates = try await lobby.candidates(tournamentID: current.id)
                exerciseCandidates = candidates
                exerciseNames = try await lobby.candidateNames(candidates)
                exerciseLoadFailed = false
            } catch {
                if !Task.isCancelled { exerciseLoadFailed = true }
            }
            errorMessage = nil
            return
        } catch {
            if Task.isCancelled { return }
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                if attempt == 0 { continue }
                return
            }
            if attempt == 0, let networkError = error as? URLError,
               [.timedOut, .networkConnectionLost, .notConnectedToInternet].contains(networkError.code) {
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
                continue
            }
            errorMessage = "Kunne ikke hente konkurransen: " + error.localizedDescription
        }
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

    @MainActor
    private func prepareRematch() async {
        guard !checkingSeasonRenewal else { return }
        checkingSeasonRenewal = true
        defer { checkingSeasonRenewal = false }
        do {
            let existing = try await cloud.visibleTournaments()
            guard !existing.contains(where: { $0.raceRules.previousCompetitionID == current.id && $0.status != "cancelled" }) else {
                continuationExists = true
                errorMessage = "En rematch finnes allerede."
                return
            }
            let candidates = try await ATHLTHTournamentLobbyCloudService().candidates(tournamentID: current.id)
            let ids = candidates.filter { $0.selectedPosition != nil }
                .sorted { ($0.selectedPosition ?? 0) < ($1.selectedPosition ?? 0) }.map(\.lookupID)
            guard let draft = ATHLTHDuelRematch.draft(from: current, entries: entries, names: names,
                                                     userID: userID, exerciseIDs: ids) else {
                errorMessage = "Kunne ikke hente øvelsene fra forrige duell."
                return
            }
            nextSeasonDraft = draft
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor
    private func prepareNextSeason() async {
        guard !checkingSeasonRenewal else { return }
        guard let candidate = ATHLTHTournamentSeasonContinuation.nextDraft(
            from: current, entries: entries,
            athleteNames: names, currentUserID: userID
        ) else {
            errorMessage = "Klarte ikke å lage neste sesong fra godkjente deltakere."
            return
        }
        checkingSeasonRenewal = true
        defer { checkingSeasonRenewal = false }
        do {
            let existing = try await cloud.visibleTournaments()
            if existing.contains(where: {
                $0.raceRules.previousCompetitionID == current.id && $0.status != "cancelled"
            }) || ATHLTHTournamentDraftStore.load(userID).contains(where: {
                $0.competitionSettings.race.previousCompetitionID == current.id
            }) {
                errorMessage = "En ny sesong med samme navn finnes allerede."
                return
            }
            nextSeasonDraft = candidate
        } catch {
            errorMessage = "Kunne ikke kontrollere om neste sesong finnes: " +
                error.localizedDescription
        }
    }

    @MainActor private func markReady() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await ATHLTHTournamentLobbyCloudService()
                .ready(tournamentID: current.id, value: true)
            await reload()
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func finishReplacement() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await cloud.finishReplacement(tournamentID: current.id)
            await reload()
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func publishToFeed() async {
        guard !publishingFeed else { return }
        publishingFeed = true
        defer { publishingFeed = false }
        do {
            try await cloud.publishCompletedToFeed(tournamentID: current.id)
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


/// Shared destructive-action presentation for competition surfaces.
struct ATHLTHCompetitionConfirmationCard: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let message: String
    let actionTitle: String
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.red)
                .frame(width: 60, height: 60)
                .background(Color.red.opacity(0.08), in: Circle())
            Text(title).font(.system(size: 27, design: .serif))
                .multilineTextAlignment(.center)
            Text(message).font(.subheadline)
                .foregroundStyle(ATHLTHArenaV3Style.secondary)
                .multilineTextAlignment(.center)
            Button {
                onConfirm()
                dismiss()
            } label: {
                Text(actionTitle).font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color.red, in: Capsule())
            }.buttonStyle(.plain)
            Button("Behold / gå tilbake") { dismiss() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHArenaV3Style.ink)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(24)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ATHLTHArenaV3Style.cream.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

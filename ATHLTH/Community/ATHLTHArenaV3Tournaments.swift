import SwiftUI

private enum ATHLTHTournamentInviteSource: String, CaseIterable, Identifiable {
    case friends, club, others
    var id: String { rawValue }
    var title: String {
        switch self {
        case .friends: return "Venner"
        case .club: return "Klubb"
        case .others: return "Andre"
        }
    }
    var icon: String {
        switch self {
        case .friends: return "person.2"
        case .club: return "shield"
        case .others: return "magnifyingglass"
        }
    }
}

struct ATHLTHTournamentCreator: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var social: SocialStore

    let preset: ATHLTHTournamentFormat
    let fixedClubID: UUID?
    let onSave: (ATHLTHTournamentDraft) -> Void

    @State private var format: ATHLTHTournamentFormat
    @State private var title = ""
    @State private var groupSize = 4
    @State private var qualifiersPerGroup = 2
    @State private var warmupRounds: [ATHLTHTournamentWarmupRound] = []
    @State private var selectedSeasonID: UUID?
    @State private var clubSeasons: [ATHLTHArenaClubSeason] = []
    @State private var showingSeasonCreation = false
    @State private var inviteSource: ATHLTHTournamentInviteSource = .friends
    @State private var chosenIDs: Set<UUID> = []
    @State private var chosenNames: [UUID: String] = [:]
    @State private var clubs: [ATHLTHArenaClubChoice] = []
    @State private var selectedClubID: UUID?
    @State private var clubAthletes: [ATHLTHArenaClubAthlete] = []
    @State private var search = ""
    @State private var discovered: [SocialProfileCard] = []
    @State private var errorMessage: String?
    @State private var busy = false

    private let directory = ATHLTHArenaClubDirectory()
    private let seasonCloud = ATHLTHArenaCloudService()

    private var activeClubID: UUID? {
        fixedClubID ?? (inviteSource == .club ? selectedClubID : nil)
    }

    init(
        preset: ATHLTHTournamentFormat,
        fixedClubID: UUID?,
        onSave: @escaping (ATHLTHTournamentDraft) -> Void
    ) {
        self.preset = preset
        self.fixedClubID = fixedClubID
        self.onSave = onSave
        _format = State(initialValue: preset)
        _selectedClubID = State(initialValue: fixedClubID)
        _inviteSource = State(initialValue: fixedClubID == nil ? .friends : .club)
    }

    private var athletes: [ATHLTHTournamentParticipant] {
        let ownHandle = session.profile.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = ATHLTHTournamentParticipant(
            id: session.profile.userID,
            username: ownHandle.isEmpty ? "Du" : ownHandle
        )
        return [current] + chosenIDs.sorted { $0.uuidString < $1.uuidString }
            .map { id in
                ATHLTHTournamentParticipant(
                    id: id, username: chosenNames[id] ?? "Utøver"
                )
            }
    }

    private var canSave: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 &&
        athletes.count >= 2 && !busy &&
        (inviteSource != .club || selectedClubID != nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    titleSection
                    formatSection
                    warmupSection
                    if format == .groups { groupsSection }
                    inviteSection
                    if activeClubID != nil { seasonSection }
                    preview
                    Text("Utkastet lagres privat. Ingen invitasjoner sendes før konkurransen kan publiseres med godkjenning fra deltakerne.")
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let errorMessage {
                        Text(errorMessage).font(.caption).foregroundStyle(.red)
                    }
                }
                .padding(18)
                .frame(maxWidth: 650)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(ATHLTHArenaV3Style.cream.ignoresSafeArea())
            .navigationTitle("Ny konkurranse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    let draft = ATHLTHTournamentDraft(
                        ownerID: session.profile.userID,
                        clubID: activeClubID,
                        seasonID: activeClubID == nil ? nil : selectedSeasonID,
                        title: String(title.trimmingCharacters(
                            in: .whitespacesAndNewlines).prefix(80)),
                        format: format,
                        groupSize: groupSize,
                        qualifiersPerGroup: qualifiersPerGroup,
                        participants: athletes,
                        warmupRounds: warmupRounds.enumerated().map { index, round in
                            var named = round
                            let trimmed = round.title.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                            named.title = String(
                                (trimmed.isEmpty ? "Oppvarmingsrunde \(index + 1)" : trimmed).prefix(60)
                            )
                            return named
                        }
                    )
                    onSave(draft)
                    dismiss()
                } label: {
                    Text("Lagre konkurranseoppsett")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 53)
                }
                .foregroundStyle(.white)
                .background(canSave ? ATHLTHArenaV3Style.ink : ATHLTHArenaV3Style.secondary,
                            in: Capsule())
                .disabled(!canSave)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.regularMaterial)
            }
        }
        .environment(\.colorScheme, .light)
        .task {
            if let fixedClubID { await loadClub(fixedClubID) }
            do {
                clubs = try await directory.manageableClubs()
            } catch {
                errorMessage = "Kunne ikke laste klubbene."
            }
        }
        .task(id: activeClubID) {
            if let clubID = activeClubID {
                await loadSeasons(for: clubID)
            } else {
                selectedSeasonID = nil
                clubSeasons = []
            }
        }
        .sheet(isPresented: $showingSeasonCreation) {
            if let clubID = activeClubID {
                ATHLTHArenaSeasonCreateView(
                    clubs: clubs.filter { $0.id == clubID },
                    preselectedClubID: clubID
                ) {
                    Task { await loadSeasons(for: clubID) }
                }
            }
        }
        .task(id: search) {
            guard inviteSource == .others && search.count >= 2 else {
                discovered = []
                return
            }
            let result = await social.searchQuickTrainPartners(search)
            guard !Task.isCancelled else { return }
            discovered = result
        }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("KONKURRANSE")
                .font(.caption2.weight(.semibold))
                .tracking(2)
                .foregroundStyle(ATHLTHArenaV3Style.gold)
            TextField("Navn på liga eller cup", text: $title)
                .font(.title3.weight(.medium))
                .padding(15)
                .background(ATHLTHArenaV3Style.panel())
                .onChange(of: title) { _, value in
                    if value.count > 80 { title = String(value.prefix(80)) }
                }
        }
    }

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Konkurranseform")
            ForEach(ATHLTHTournamentFormat.allCases) { option in
                Button {
                    format = option
                } label: {
                    HStack(spacing: 13) {
                        Image(systemName: option.symbol)
                            .font(.title3.weight(.light))
                            .frame(width: 44)
                            .foregroundStyle(ATHLTHArenaV3Style.gold)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(option.title).font(.subheadline.weight(.semibold))
                            Text(option.subtitle)
                                .font(.caption)
                                .foregroundStyle(ATHLTHArenaV3Style.secondary)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: format == option ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(format == option ?
                                ATHLTHArenaV3Style.gold : ATHLTHArenaV3Style.secondary)
                    }
                    .foregroundStyle(ATHLTHArenaV3Style.ink)
                    .padding(14)
                    .background(ATHLTHArenaV3Style.panel())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var groupsSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionTitle("Gruppespill")
            HStack {
                Text("Deltakere per gruppe")
                Spacer()
                Picker("Gruppestørrelse", selection: $groupSize) {
                    ForEach([3, 4, 5, 6, 8], id: \.self) { number in
                        Text("\(number)").tag(number)
                    }
                }
                .labelsHidden()
            }
            HStack {
                Text("Videre til sluttspill per gruppe")
                Spacer()
                Picker("Går videre", selection: $qualifiersPerGroup) {
                    ForEach(1...min(groupSize, 4), id: \.self) { number in
                        Text("\(number)").tag(number)
                    }
                }
                .labelsHidden()
            }
            Text("Gruppene fordeles automatisk. Sluttspill og tabell følger konkurransen.")
                .font(.caption)
                .foregroundStyle(ATHLTHArenaV3Style.secondary)
        }
        .padding(15)
        .background(ATHLTHArenaV3Style.panel())
    }

    private var warmupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                sectionTitle("Oppvarmingsrunder")
                Spacer()
                Text("Valgfritt")
                    .font(.caption)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
            }

            Text("Legg til prøverunder før konkurransen starter. Disse gir ingen poeng, endrer ikke tabellen og kan aldri slå ut en deltaker.")
                .font(.caption)
                .foregroundStyle(ATHLTHArenaV3Style.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach($warmupRounds) { $round in
                HStack(spacing: 10) {
                    Image(systemName: "figure.run")
                        .foregroundStyle(ATHLTHArenaV3Style.gold)
                    TextField("Navn på oppvarmingsrunde", text: $round.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ATHLTHArenaV3Style.ink)
                    Button(role: .destructive) {
                        warmupRounds.removeAll { $0.id == round.id }
                    } label: {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(ATHLTHArenaV3Style.secondary)
                            .frame(width: 30, height: 36)
                    }
                    .accessibilityLabel("Fjern oppvarmingsrunde")
                }
                .padding(11)
                .background(ATHLTHArenaV3Style.cream,
                            in: RoundedRectangle(cornerRadius: 13))
            }

            if warmupRounds.count < 12 {
                Button {
                    warmupRounds.append(
                        ATHLTHTournamentWarmupRound(
                            title: "Oppvarmingsrunde \(warmupRounds.count + 1)"
                        )
                    )
                } label: {
                    Label("Legg til oppvarmingsrunde", systemImage: "plus.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHArenaV3Style.gold)
                        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(15)
        .background(ATHLTHArenaV3Style.panel())
    }

    private var seasonSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("Klubbsesong")
                Spacer()
                if clubs.contains(where: { $0.id == activeClubID }) {
                    Button {
                        showingSeasonCreation = true
                    } label: {
                        Label("Ny", systemImage: "plus")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHArenaV3Style.gold)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("En sesong kan samle flere ligaer og cuper. Du kan også legge konkurransen utenfor en sesong.")
                .font(.caption)
                .foregroundStyle(ATHLTHArenaV3Style.secondary)
            Picker("Sesong", selection: $selectedSeasonID) {
                Text("Uten sesong").tag(nil as UUID?)
                ForEach(clubSeasons) { season in
                    Text(season.title).tag(season.id as UUID?)
                }
            }
            .pickerStyle(.menu)
            .tint(ATHLTHArenaV3Style.ink)

            if let chosen = clubSeasons.first(where: { $0.id == selectedSeasonID }) {
                Text("\(ATHLTHArenaSeasonDate.label(chosen.startsOn)) – \(ATHLTHArenaSeasonDate.label(chosen.endsOn))")
                    .font(.caption)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
            }
        }
        .padding(15)
        .background(ATHLTHArenaV3Style.panel())
    }

    private var inviteSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                sectionTitle("Deltakere")
                Spacer()
                Text("\(athletes.count) valgt")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHArenaV3Style.gold)
            }
            HStack(spacing: 7) {
                ForEach(ATHLTHTournamentInviteSource.allCases) { option in
                    Button {
                        inviteSource = option
                    } label: {
                        VStack(spacing: 7) {
                            Image(systemName: option.icon)
                                .font(.subheadline)
                            Text(option.title)
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(inviteSource == option ?
                            Color.white : ATHLTHArenaV3Style.ink)
                        .frame(maxWidth: .infinity, minHeight: 63)
                        .background(inviteSource == option ?
                            ATHLTHArenaV3Style.ink : Color.white,
                            in: RoundedRectangle(cornerRadius: 15))
                    }
                    .buttonStyle(.plain)
                }
            }
            switch inviteSource {
            case .friends:
                if social.mutualFollows.isEmpty {
                    Text("Gjensidige følgere vises her.")
                        .font(.caption)
                }
                ForEach(social.mutualFollows, id: \.userID) { person in
                    personRow(person.userID,
                              name: person.username ?? person.resolvedName)
                }
            case .club:
                if fixedClubID == nil {
                    ForEach(clubs) { club in
                        Button {
                            selectedClubID = club.id
                            Task { await loadClub(club.id) }
                        } label: {
                            HStack {
                                Text(club.name)
                                Spacer()
                                Image(systemName: selectedClubID == club.id ?
                                    "checkmark.circle.fill" : "circle")
                            }
                            .foregroundStyle(ATHLTHArenaV3Style.ink)
                            .padding(14)
                            .background(ATHLTHArenaV3Style.panel())
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !clubAthletes.isEmpty {
                    Button("Velg hele klubben") {
                        for person in clubAthletes where
                            person.id != session.profile.userID {
                            chosenIDs.insert(person.id)
                            chosenNames[person.id] = person.displayName
                        }
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ATHLTHArenaV3Style.gold)
                    ForEach(clubAthletes) { person in
                        if person.id != session.profile.userID {
                            personRow(person.id, name: person.displayName)
                        }
                    }
                }
            case .others:
                TextField("Søk etter brukernavn", text: $search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(ATHLTHArenaV3Style.panel())
                ForEach(discovered, id: \.userID) { person in
                    personRow(person.userID,
                              name: person.username ?? person.resolvedName)
                }
            }
            if !chosenIDs.isEmpty {
                Text("Valgte: " + athletes.dropFirst().map(\.username).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
                    .lineLimit(3)
            }
        }
    }

    private func personRow(_ id: UUID, name: String) -> some View {
        Button {
            if chosenIDs.contains(id) {
                chosenIDs.remove(id)
            } else if chosenIDs.count < 127 {
                chosenIDs.insert(id)
                chosenNames[id] = name
            }
        } label: {
            HStack {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(ATHLTHArenaV3Style.gold)
                Text(name)
                    .lineLimit(1)
                    .foregroundStyle(ATHLTHArenaV3Style.ink)
                Spacer()
                Image(systemName: chosenIDs.contains(id) ?
                    "checkmark.circle.fill" : "circle")
                    .foregroundStyle(ATHLTHArenaV3Style.gold)
            }
            .padding(13)
            .background(ATHLTHArenaV3Style.panel())
        }
        .buttonStyle(.plain)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Forhåndsvisning")
            Text(format == .cup
                ? "\(ATHLTHTournamentStructure.bracketSize(athletes.count))-plassers cupoppsett"
                : format == .league
                ? "\(ATHLTHTournamentStructure.leagueMatchCount(athletes.count)) oppgjør i én liga"
                : "\(ATHLTHTournamentStructure.groups(athletes, size: groupSize).count) grupper")
                .font(.headline)
                .foregroundStyle(ATHLTHArenaV3Style.ink)
            if !warmupRounds.isEmpty {
                Label("\(warmupRounds.count) oppvarmingsrunder · 0 poeng · ingen utslag",
                      systemImage: "figure.run")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ATHLTHArenaV3Style.gold)
            }
            if let season = clubSeasons.first(where: { $0.id == selectedSeasonID }) {
                Label(season.title, systemImage: "calendar")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ATHLTHArenaV3Style.gold)
            }
            Text("Oppsettet er et utkast. Tabellen og kampene får ikke resultater før de er registrert og godkjent.")
                .font(.caption)
                .foregroundStyle(ATHLTHArenaV3Style.secondary)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ATHLTHArenaV3Style.panel())
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 21, weight: .regular, design: .serif))
            .foregroundStyle(ATHLTHArenaV3Style.ink)
    }

    @MainActor
    private func loadSeasons(for clubID: UUID) async {
        do {
            let allSeasons = try await seasonCloud.loadClubSeasons()
            guard activeClubID == clubID else { return }
            clubSeasons = allSeasons.filter { $0.clubID == clubID }
                .sorted { $0.startsOn > $1.startsOn }
            if let selectedSeasonID,
               !clubSeasons.contains(where: { $0.id == selectedSeasonID }) {
                self.selectedSeasonID = nil
            }
        } catch {
            guard activeClubID == clubID else { return }
            errorMessage = "Kunne ikke hente klubbens sesonger."
        }
    }

    @MainActor
    private func loadClub(_ id: UUID) async {
        busy = true
        defer { busy = false }
        do {
            let people = try await directory.athletes(in: id)
            guard selectedClubID == id else { return }
            clubAthletes = people
            errorMessage = nil
        } catch {
            errorMessage = "Kunne ikke hente klubbens medlemmer."
        }
    }
}

struct ATHLTHTournamentDraftDetailView: View {
    let draft: ATHLTHTournamentDraft
    @State private var selectedGroup = 0
    @State private var linkedSeason: ATHLTHArenaClubSeason?
    private let seasonCloud = ATHLTHArenaCloudService()

    private var groups: [[ATHLTHTournamentParticipant]] {
        ATHLTHTournamentStructure.groups(draft.participants, size: draft.groupSize)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(draft.format.title.uppercased() + " · UTKAST")
                        .font(.caption2.weight(.semibold))
                        .tracking(2.2)
                        .foregroundStyle(ATHLTHArenaV3Style.gold)
                    Text(draft.title)
                        .font(.system(size: 31, weight: .regular, design: .serif))
                        .foregroundStyle(ATHLTHArenaV3Style.ink)
                    Text("\(draft.participants.count) deltakere")
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                    if let linkedSeason {
                        NavigationLink {
                            ATHLTHArenaSeasonDetailView(
                                season: linkedSeason,
                                canManage: false
                            )
                        } label: {
                            Label(linkedSeason.title, systemImage: "calendar")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(ATHLTHArenaV3Style.gold)
                        }
                    }
                }
                if !draft.warmupRounds.isEmpty {
                    warmupSection
                }
                if draft.format == .cup {
                    cupView
                } else if draft.format == .groups {
                    groupsView
                } else {
                    tableView(draft.participants, title: "Ligatabell")
                }
                Text("Dette er et lokalt konkurranseutkast. Kampoppsett er foreløpig, og ingen resultater, premier eller invitasjoner er publisert.")
                    .font(.caption)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
            }
            .padding(18)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(ATHLTHArenaV3Style.cream.ignoresSafeArea())
        .navigationTitle("Konkurranse")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: draft.seasonID) {
            guard let seasonID = draft.seasonID else {
                linkedSeason = nil
                return
            }
            if let seasons = try? await seasonCloud.loadClubSeasons() {
                linkedSeason = seasons.first { $0.id == seasonID }
            }
        }
    }

    private var warmupSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Oppvarmingsrunder")
                    .font(.system(size: 24, weight: .regular, design: .serif))
                    .foregroundStyle(ATHLTHArenaV3Style.ink)
                Spacer()
                Text("\(draft.warmupRounds.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
            }
            ForEach(draft.warmupRounds) { round in
                HStack(spacing: 12) {
                    Image(systemName: "figure.run")
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHArenaV3Style.gold)
                    Text(round.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ATHLTHArenaV3Style.ink)
                    Spacer()
                    Text("Trening")
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                }
                .padding(.vertical, 6)
            }
            Label("0 poeng · ingen utslag · teller ikke i tabell eller sesong",
                  systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(ATHLTHArenaV3Style.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .background(ATHLTHArenaV3Style.panel())
    }

    private var groupsView: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !groups.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(groups.indices, id: \.self) { index in
                            Button("Gruppe \(Character(UnicodeScalar(65 + index)!))") {
                                selectedGroup = index
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selectedGroup == index ? .white : ATHLTHArenaV3Style.ink)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 10)
                            .background(selectedGroup == index ?
                                ATHLTHArenaV3Style.ink : .white,
                                in: Capsule())
                        }
                    }
                }
                tableView(groups[min(selectedGroup, groups.count - 1)],
                          title: "Gruppe \(Character(UnicodeScalar(65 + min(selectedGroup, groups.count - 1))!))")
                Text("Topp \(draft.qualifiersPerGroup) fra hver gruppe går videre til sluttspill.")
                    .font(.caption)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
            }
        }
    }

    private func tableView(_ athletes: [ATHLTHTournamentParticipant],
                           title: String) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(title)
                .font(.system(size: 24, weight: .regular, design: .serif))
                .foregroundStyle(ATHLTHArenaV3Style.ink)
            HStack {
                Text("#").frame(width: 22, alignment: .leading)
                Text("Deltaker")
                Spacer()
                Text("K").frame(width: 26)
                Text("P").frame(width: 26)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(ATHLTHArenaV3Style.secondary)
            ForEach(Array(athletes.enumerated()), id: \.element.id) { index, athlete in
                HStack(spacing: 9) {
                    Text("\(index + 1)")
                        .frame(width: 22, alignment: .leading)
                        .foregroundStyle(ATHLTHArenaV3Style.gold)
                    Text(athlete.username)
                        .lineLimit(1)
                    Spacer()
                    Text("–").frame(width: 26)
                    Text("–").frame(width: 26)
                }
                .font(.subheadline)
                .foregroundStyle(ATHLTHArenaV3Style.ink)
                .padding(.vertical, 7)
                if index != athletes.count - 1 { Divider() }
            }
            Text("\(ATHLTHTournamentStructure.leagueMatchCount(athletes.count)) kamper planlegges · K = kamper, P = poeng")
                .font(.caption2)
                .foregroundStyle(ATHLTHArenaV3Style.secondary)
        }
        .padding(15)
        .background(ATHLTHArenaV3Style.panel())
    }

    private var cupView: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("Utslagstre")
                .font(.system(size: 24, weight: .regular, design: .serif))
                .foregroundStyle(ATHLTHArenaV3Style.ink)
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 13) {
                    let size = ATHLTHTournamentStructure.bracketSize(draft.participants.count)
                    let totalRounds = Int(log2(Double(size)))
                    ForEach(0..<totalRounds, id: \.self) { round in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(round == totalRounds - 1 ? "Finale" : "Runde \(round + 1)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ATHLTHArenaV3Style.gold)
                            let matches = size / (1 << (round + 1))
                            ForEach(0..<matches, id: \.self) { game in
                                let pair = ATHLTHTournamentStructure.firstCupRound(draft.participants)
                                VStack(alignment: .leading, spacing: 9) {
                                    if round == 0 {
                                        Text(pair[game].0)
                                        Divider()
                                        Text(pair[game].1)
                                    } else {
                                        Text("Vinner kamp \(2 * game + 1)")
                                        Divider()
                                        Text("Vinner kamp \(2 * game + 2)")
                                    }
                                }
                                .font(.caption.weight(.medium))
                                .foregroundStyle(ATHLTHArenaV3Style.ink)
                                .frame(width: 155, alignment: .leading)
                                .padding(12)
                                .background(ATHLTHArenaV3Style.panel())
                            }
                        }
                    }
                }
                .padding(.bottom, 6)
            }
            Text("Frirunder vises som slike. Ingen vinner er satt før resultatene er godkjent.")
                .font(.caption)
                .foregroundStyle(ATHLTHArenaV3Style.secondary)
        }
    }
}

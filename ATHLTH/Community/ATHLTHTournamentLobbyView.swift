import SwiftUI

private enum ATHLTHTournamentLobbyTab: String, CaseIterable, Identifiable {
    case members, exercises, chat
    var id: String { rawValue }
    var title: String {
        switch self {
        case .members: return "Deltakere"
        case .exercises: return "Øvelser"
        case .chat: return "Chat"
        }
    }
}

private struct ATHLTHTournamentReplacementSelection: Identifiable {
    let id: UUID
    let name: String
}

/// A compact, high-quality competition lobby. All visible actions call
/// server-authorized RPCs; no local ready/vote/message state is treated as
/// authoritative until the server confirms and the view reloads.
struct ATHLTHTournamentLobbyView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var social: SocialStore
    let tournament: ATHLTHTournamentRemote
    let entries: [ATHLTHTournamentRemoteEntry]
    let names: [UUID: String]
    let matches: [ATHLTHTournamentRemoteMatch]
    let onChange: @MainActor () async -> Void

    @State private var tab: ATHLTHTournamentLobbyTab = .members
    @State private var candidates: [ATHLTHTournamentExerciseCandidateRemote] = []
    @State private var votes: [ATHLTHTournamentExerciseVoteRemote] = []
    @State private var exerciseNames: [UUID: String] = [:]
    @State private var messages: [ATHLTHTournamentLobbyMessageRemote] = []
    @State private var replacements: [ATHLTHTournamentPlayerChangeRemote] = []
    @State private var replacementVotes: [ATHLTHTournamentPlayerChangeVoteRemote] = []
    @State private var exerciseQuery = ""
    @State private var exerciseResults: [ATHLTHTournamentLibraryExerciseRemote] = []
    @State private var chatText = ""
    @State private var announcing = false
    @State private var busy = false
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var showAllAthletes = false
    @State private var pendingForfeit: ATHLTHTournamentReplacementSelection?
    @State private var replacementSelection: ATHLTHTournamentReplacementSelection?

    private let cloud = ATHLTHTournamentLobbyCloudService()
    private var userID: UUID { session.profile.userID }
    private var isOwner: Bool { userID == tournament.ownerID }
    private var myEntry: ATHLTHTournamentRemoteEntry? {
        entries.first { $0.userID == userID }
    }
    private var accepted: [ATHLTHTournamentRemoteEntry] {
        entries.filter { $0.response == "accepted" && $0.removedAt == nil }
    }
    private var isAccepted: Bool {
        accepted.contains { $0.userID == userID }
    }
    private var readyCount: Int { accepted.filter(\.isReady).count }
    private var finalized: Bool { tournament.exerciseSelectionFinalizedAt != nil }
    private var selectedCandidates: [ATHLTHTournamentExerciseCandidateRemote] {
        candidates.filter { $0.selectedPosition != nil }
            .sorted { ($0.selectedPosition ?? 0) < ($1.selectedPosition ?? 0) }
    }
    private var candidatePeriodOpen: Bool {
        tournament.status == "inviting" && !finalized &&
        (tournament.exerciseMode != .vote ||
         Date() < (tournament.proposalsCloseAt ?? .distantPast))
    }
    private var ballotOpen: Bool {
        tournament.status == "inviting" && !finalized &&
        tournament.exerciseMode == .vote &&
        Date() >= (tournament.proposalsCloseAt ?? .distantFuture) &&
        Date() < (tournament.votesCloseAt ?? .distantPast)
    }
    private var canSuggest: Bool {
        candidatePeriodOpen &&
        (tournament.exerciseMode == .owner ? isOwner : isAccepted)
    }
    private var myVotes: Set<UUID> {
        Set(votes.filter { $0.voterID == userID }.map(\.candidateID))
    }
    private var neededReady: Int { max(0, accepted.count - readyCount) }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            hero

            Picker("Lobby", selection: $tab) {
                ForEach(ATHLTHTournamentLobbyTab.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)

            if let errorMessage {
                Label(errorMessage,systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(12)
                    .background(ATHLTHArenaV3Style.panel())
            }
            if loading {
                ProgressView("Henter lobby…")
                    .frame(maxWidth: .infinity,minHeight: 130)
            } else {
                switch tab {
                case .members: participantsContent
                case .exercises: exercisesContent
                case .chat: chatContent
                }
            }
        }
        .task(id: tournament.id) { await reload() }
        .task(id: exerciseQuery) {
            guard canSuggest && exerciseQuery.trimmingCharacters(
                in: .whitespacesAndNewlines).count >= 2 else {
                exerciseResults = []
                return
            }
            do {
                let result = try await cloud.searchExercises(exerciseQuery)
                if !Task.isCancelled { exerciseResults = result }
            } catch {
                if !Task.isCancelled {
                    errorMessage = "Kunne ikke søke i øvelsesbiblioteket."
                }
            }
        }
        .task(id: tab) {
            while !Task.isCancelled {
                if tab == .chat {
                    if let updated = try? await cloud.messages(
                        tournamentID: tournament.id
                    ) {
                        messages = updated
                    }
                } else {
                    // Ready state and automatic ballot completion may change
                    // on another device; refresh the official participant and
                    // tournament records without requiring a manual reload.
                    await onChange()
                    await reload()
                }
                try? await Task.sleep(for: .seconds(15))
            }
        }
        .sheet(item: $replacementSelection) { selected in
            ATHLTHTournamentReplacementPicker(
                personToReplace: selected.name
            ) { replacement in
                await perform {
                    try await cloud.requestReplacement(
                        tournamentID: tournament.id,
                        oldID: selected.id,
                        newID: replacement
                    )
                }
            }
            .environmentObject(social)
        }
        .alert("Gi walkover i gjenstående kamper?",
               isPresented: Binding(
                get: { pendingForfeit != nil },
                set: { if !$0 { pendingForfeit = nil } }
               )) {
            Button("Gi walkover",role: .destructive) {
                guard let selected = pendingForfeit else { return }
                pendingForfeit = nil
                Task {
                    await perform {
                        try await cloud.forfeit(
                            tournamentID: tournament.id, playerID: selected.id
                        )
                    }
                }
            }
            Button("Avbryt",role: .cancel) { pendingForfeit = nil }
        } message: {
            Text("Tidligere godkjente resultater bevares. Uavgjorte kamper registreres som tap for deltakeren som fjernes.")
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("TURNERINGSLOBBY",systemImage: "person.3.sequence")
                    .font(.system(size: 10,weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(ATHLTHArenaV3Style.gold)
                Spacer()
                if tournament.status == "active" {
                    Label("I gang",systemImage: "bolt")
                        .font(.caption.weight(.medium))
                } else if tournament.status == "inviting" {
                    Text("Før oppstart")
                        .font(.caption.weight(.medium))
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text("\(readyCount)/\(accepted.count)")
                    .font(.system(size: 37,weight: .medium,design: .rounded))
                    .monospacedDigit()
                Text("klare")
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
                Spacer()
                Image(systemName: "flag.checkered")
                    .font(.system(size: 27,weight: .ultraLight))
                    .foregroundStyle(ATHLTHArenaV3Style.gold)
            }
            .foregroundStyle(ATHLTHArenaV3Style.ink)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(ATHLTHArenaV3Style.line)
                    Capsule().fill(ATHLTHArenaV3Style.gold)
                        .frame(width: geometry.size.width *
                            CGFloat(readyCount) / CGFloat(max(1,accepted.count)))
                }
            }
            .frame(height: 5)

            HStack(alignment: .firstTextBaseline) {
                Text(finalized
                     ? "Øvelsene er bestemt"
                     : tournament.exerciseMode == .vote
                     ? "Forslag og avstemning"
                     : "Øvelser under oppsett")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(tournament.exerciseMode == .open && !finalized
                     ? "\(candidates.count) foreslått"
                     : "\(selectedCandidates.count)/\(tournament.exerciseCount) valgt")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
            }
            .foregroundStyle(ATHLTHArenaV3Style.ink)
        }
        .padding(17)
        .background(ATHLTHArenaV3Style.panel())
    }

    private var participantsContent: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Deltakere")
                    .font(.system(size: 23,weight: .regular,design: .serif))
                    .foregroundStyle(ATHLTHArenaV3Style.ink)
                Spacer()
                Button { Task { await reload() } } label: {
                    Label("Oppdater",systemImage: "arrow.clockwise")
                        .font(.caption.weight(.medium))
                }
                .tint(ATHLTHArenaV3Style.gold)
            }

            if tournament.status == "inviting" && isAccepted {
                Button {
                    Task {
                        await perform {
                            try await cloud.ready(
                                tournamentID: tournament.id,
                                value: !(myEntry?.isReady ?? false)
                            )
                            await onChange()
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: myEntry?.isReady == true
                              ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                        VStack(alignment: .leading,spacing: 4) {
                            Text(myEntry?.isReady == true ? "Du er klar" : "Jeg er klar")
                                .font(.headline)
                            Text(finalized
                                 ? "Alle må bekrefte før konkurransen starter"
                                 : "Øvelsene må bestemmes først")
                                .font(.caption)
                                .opacity(0.8)
                        }
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .padding(16)
                    .background(ATHLTHArenaV3Style.ink,
                                in: RoundedRectangle(cornerRadius: 19))
                }
                .buttonStyle(.plain)
                .disabled(!finalized || busy)
                .opacity(finalized ? 1 : 0.55)
            }

            VStack(spacing: 0) {
                ForEach(Array((showAllAthletes
                     ? entries : Array(entries.prefix(12))).enumerated()),
                    id: \.element.userID) { index, person in
                    HStack(spacing: 11) {
                        Text(String(name(person.userID).prefix(1)).uppercased())
                            .font(.caption.weight(.medium))
                            .foregroundStyle(ATHLTHArenaV3Style.gold)
                            .frame(width: 36,height: 36)
                            .background(ATHLTHArenaV3Style.cream,in: Circle())
                        VStack(alignment: .leading,spacing: 3) {
                            HStack(spacing: 6) {
                                Text(name(person.userID))
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                if person.userID == tournament.ownerID {
                                    Text("Arrangør")
                                        .font(.system(size: 9,weight: .semibold))
                                        .foregroundStyle(ATHLTHArenaV3Style.gold)
                                }
                            }
                            Text(participantStatus(person))
                                .font(.caption2)
                                .foregroundStyle(ATHLTHArenaV3Style.secondary)
                        }
                        Spacer(minLength: 4)
                        if person.isReady {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(ATHLTHArenaV3Style.gold)
                        } else {
                            Image(systemName: "circle.dotted")
                                .foregroundStyle(ATHLTHArenaV3Style.secondary)
                        }
                        if isOwner && person.userID != userID &&
                           person.removedAt == nil &&
                           (tournament.status == "inviting" ||
                            tournament.status == "active") {
                            Menu {
                                Button("Erstatt deltaker",systemImage: "person.crop.circle.badge.plus") {
                                    replacementSelection = .init(
                                        id: person.userID,name: name(person.userID))
                                }
                                Button("Gi walkover",systemImage: "flag.fill",role: .destructive) {
                                    pendingForfeit = .init(
                                        id: person.userID,name: name(person.userID))
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .frame(width: 28,height: 28)
                                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
                            }
                        }
                    }
                    .padding(.vertical,10)
                    if index < min(entries.count, showAllAthletes ? entries.count : 12)-1 {
                        Divider().opacity(0.55)
                    }
                }
                if entries.count > 12 {
                    Button(showAllAthletes ? "Vis færre" : "Vis alle \(entries.count)") {
                        showAllAthletes.toggle()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHArenaV3Style.gold)
                    .frame(maxWidth: .infinity)
                    .padding(10)
                }
            }
            .padding(.horizontal,15)
            .background(ATHLTHArenaV3Style.panel())

            if tournament.status == "inviting" {
                Text(neededReady == 0
                     ? "Alle godtatte deltakere har trykket klar."
                     : "\(neededReady) deltakere mangler å trykke klar.")
                    .font(.caption)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
            }

            replacementRequestsContent

            if isOwner {
                Label(tournament.approvePlayerChanges
                      ? "Spillerbytter krever samtykke fra alle gjenværende spillere."
                      : "Spillerbytter krever at ny deltaker takker ja.",
                      systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
            }
        }
    }

    private var exercisesContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Øvelser")
                    .font(.system(size: 23,weight: .regular,design: .serif))
                Spacer()
                Text(tournament.exerciseMode.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ATHLTHArenaV3Style.gold)
            }
            .foregroundStyle(ATHLTHArenaV3Style.ink)

            if tournament.exerciseMode == .vote {
                VStack(alignment: .leading,spacing: 5) {
                    if let close = tournament.proposalsCloseAt,
                       Date() < close {
                        Label("Forslag til " +
                              close.formatted(date: .abbreviated,time: .shortened),
                              systemImage: "pencil.line")
                    } else if let close = tournament.votesCloseAt, !finalized {
                        Label("Stem innen " +
                              close.formatted(date: .abbreviated,time: .shortened),
                              systemImage: "checkmark.seal")
                    } else {
                        Label("Avstemningen er avsluttet",systemImage: "checkmark.seal")
                    }
                    Text("Du får inntil \(tournament.exerciseCount) stemmer, én på hver øvelse. Det er frivillig å stemme. Ved likt antall avgjør lagret loddtrekning.")
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                }
                .font(.subheadline.weight(.medium))
                .padding(15)
                .background(ATHLTHArenaV3Style.panel())
            }

            if canSuggest {
                VStack(alignment: .leading,spacing: 9) {
                    Text("Foreslå fra øvelsesbiblioteket")
                        .font(.subheadline.weight(.medium))
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(ATHLTHArenaV3Style.secondary)
                        TextField("Søk etter en øvelse",text: $exerciseQuery)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .padding(12)
                    .background(ATHLTHArenaV3Style.cream,
                                in: RoundedRectangle(cornerRadius: 12))
                    ForEach(exerciseResults) { exercise in
                        Button {
                            Task {
                                await perform {
                                    try await cloud.suggest(
                                        tournamentID: tournament.id,
                                        exerciseID: exercise.id
                                    )
                                    exerciseQuery = ""
                                }
                            }
                        } label: {
                            HStack {
                                Text(exercise.name)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "plus.circle")
                            }
                            .font(.subheadline)
                            .foregroundStyle(ATHLTHArenaV3Style.ink)
                            .padding(.vertical,7)
                        }
                        .disabled(busy || candidates.contains {
                            $0.exerciseID == exercise.id
                        })
                    }
                }
                .padding(15)
                .background(ATHLTHArenaV3Style.panel())
            }

            if candidates.isEmpty {
                Text("Ingen øvelser foreslått ennå.")
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
                    .frame(maxWidth: .infinity,minHeight: 100)
                    .background(ATHLTHArenaV3Style.panel())
            } else {
                VStack(spacing: 0) {
                    ForEach(candidates.sorted(by: candidateOrder)) { candidate in
                        let totalVotes = votes.filter {
                            $0.candidateID == candidate.id
                        }.count
                        HStack(spacing: 11) {
                            Image(systemName: candidate.selectedPosition != nil
                                  ? "checkmark.seal.fill" : "figure.strengthtraining.traditional")
                                .foregroundStyle(ATHLTHArenaV3Style.gold)
                                .frame(width: 29)
                            VStack(alignment: .leading,spacing: 4) {
                                Text(exerciseNames[candidate.exerciseID] ??
                                     "Øvelse")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(ATHLTHArenaV3Style.ink)
                                Text(candidate.selectedPosition.map {
                                    "Øvelse \($0) · valgt"
                                } ?? (tournament.exerciseMode == .vote
                                       ? "\(totalVotes) stemmer"
                                       : "Foreslått av " + name(candidate.suggestedBy)))
                                    .font(.caption2)
                                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
                            }
                            Spacer()
                            if ballotOpen && isAccepted {
                                Button {
                                    Task {
                                        await perform {
                                            try await cloud.vote(
                                                candidateID: candidate.id,
                                                selected: !myVotes.contains(candidate.id)
                                            )
                                        }
                                    }
                                } label: {
                                    Image(systemName: myVotes.contains(candidate.id)
                                          ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(ATHLTHArenaV3Style.gold)
                                }
                                .disabled(busy || (!myVotes.contains(candidate.id)
                                                 && myVotes.count>=tournament.exerciseCount))
                                .accessibilityLabel(myVotes.contains(candidate.id)
                                                    ? "Fjern stemme" : "Stem på øvelsen")
                            }
                        }
                        .padding(.vertical,12)
                        Divider().opacity(0.45)
                    }
                }
                .padding(.horizontal,15)
                .background(ATHLTHArenaV3Style.panel())
            }
            if ballotOpen {
                Text("\(myVotes.count) av \(tournament.exerciseCount) stemmer brukt")
                    .font(.caption)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
            }

            if isOwner && tournament.exerciseMode == .vote &&
               tournament.status == "inviting" && !finalized &&
               Date() >= (tournament.votesCloseAt ?? .distantFuture) &&
               candidates.count < tournament.exerciseCount {
                VStack(alignment: .leading, spacing: 9) {
                    Label("For få øvelsesforslag til å fullføre avstemningen.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button("Åpne forslag og avstemning på nytt") {
                        Task {
                            await perform {
                                try await cloud.extendBallot(
                                    tournamentID: tournament.id
                                )
                                await onChange()
                            }
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHArenaV3Style.gold)
                    Text("Forslagsfristen forlenges med 24 timer og stemmefristen med 48 timer. Gamle stemmer nullstilles for å gi alle kandidatene lik sjanse.")
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                }
                .padding(15)
                .background(ATHLTHArenaV3Style.panel())
            }

            if isOwner && tournament.status == "inviting" && !finalized {
                Button {
                    Task {
                        await perform {
                            try await cloud.finalize(tournamentID: tournament.id)
                            await onChange()
                        }
                    }
                } label: {
                    Label("Fastsett øvelsene",systemImage: "checkmark.seal")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity,minHeight: 48)
                        .background(ATHLTHArenaV3Style.ink,in: Capsule())
                }
                .disabled(busy ||
                          (tournament.exerciseMode == .open
                           ? candidates.isEmpty
                           : candidates.count<tournament.exerciseCount) ||
                          (tournament.exerciseMode == .vote &&
                            Date() < (tournament.votesCloseAt ?? .distantFuture)))
                .opacity(tournament.exerciseMode == .open
                         ? (candidates.isEmpty ? 0.5 : 1)
                         : (candidates.count>=tournament.exerciseCount ? 1 : 0.5))
            }
            if finalized {
                Label("Øvelsene er låst for denne turneringen.",
                      systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
            }
        }
    }

    private var chatContent: some View {
        VStack(alignment: .leading,spacing: 13) {
            HStack {
                Text("Lobbychat")
                    .font(.system(size: 23,weight: .regular,design: .serif))
                Spacer()
                Button { Task { await reload() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .tint(ATHLTHArenaV3Style.gold)
            }
            Text("Meldinger er synlige for inviterte deltakere. Kun godtatte deltakere kan skrive.")
                .font(.caption)
                .foregroundStyle(ATHLTHArenaV3Style.secondary)

            LazyVStack(alignment: .leading,spacing: 12) {
                if messages.isEmpty {
                    Text("Ingen meldinger ennå. Si hei til deltakerne!")
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                        .frame(maxWidth: .infinity,minHeight: 90)
                }
                ForEach(messages) { message in
                    HStack {
                        if message.authorID == userID { Spacer(minLength: 44) }
                        VStack(alignment: .leading,spacing: 5) {
                            HStack {
                                Text(name(message.authorID))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(ATHLTHArenaV3Style.gold)
                                Spacer(minLength: 6)
                                Text(message.createdAt.formatted(
                                    date: .omitted,time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
                            }
                            if message.kind == "announcement" {
                                Label("Beskjed fra arrangøren",
                                      systemImage: "megaphone")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(ATHLTHArenaV3Style.gold)
                            }
                            Text(message.content)
                                .font(.subheadline)
                                .foregroundStyle(ATHLTHArenaV3Style.ink)
                                .fixedSize(horizontal: false,vertical: true)
                        }
                        .padding(12)
                        .background(message.authorID == userID
                            ? ATHLTHArenaV3Style.cream
                            : Color.white,
                            in: RoundedRectangle(cornerRadius: 14))
                        if message.authorID != userID { Spacer(minLength: 44) }
                    }
                }
            }
            .padding(.vertical,5)

            if isAccepted && (tournament.status == "inviting" ||
                              tournament.status == "active") {
                if isOwner {
                    Toggle("Beskjed fra arrangøren",isOn: $announcing)
                        .font(.caption)
                        .tint(ATHLTHArenaV3Style.gold)
                }
                HStack(alignment: .bottom,spacing: 9) {
                    TextField("Skriv en melding…",text: $chatText,axis: .vertical)
                        .lineLimit(1...4)
                        .font(.subheadline)
                        .padding(12)
                        .background(ATHLTHArenaV3Style.panel())
                    Button {
                        let message = chatText
                        Task {
                            await perform {
                                try await cloud.sendMessage(
                                    tournamentID: tournament.id,
                                    text: message,
                                    announcement: isOwner && announcing
                                )
                                chatText = ""
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 41,height: 41)
                            .background(ATHLTHArenaV3Style.ink,in: Circle())
                    }
                    .disabled(busy || chatText.trimmingCharacters(
                        in: .whitespacesAndNewlines).isEmpty ||
                        chatText.count>1000)
                }
            }
        }
    }

    private var replacementRequestsContent: some View {
        VStack(alignment: .leading,spacing: 10) {
            ForEach(replacements.filter {
                $0.status == "pending" &&
                ($0.newPlayerID == userID || isAccepted || isOwner)
            }) { request in
                VStack(alignment: .leading,spacing: 10) {
                    Label("Foreslått spillerbytte",systemImage: "person.crop.circle.badge.checkmark")
                        .font(.subheadline.weight(.semibold))
                    Text(name(request.oldPlayerID) + " → " +
                         name(request.newPlayerID))
                        .font(.subheadline)
                    if request.newPlayerID == userID &&
                       !request.newPlayerAccepted {
                        HStack {
                            Button("Godta plassen") {
                                Task {
                                    await perform {
                                        try await cloud.respondReplacement(
                                            requestID: request.id,accept: true)
                                        await onChange()
                                    }
                                }
                            }
                            Button("Avslå") {
                                Task {
                                    await perform {
                                        try await cloud.respondReplacement(
                                            requestID: request.id,accept: false)
                                        await onChange()
                                    }
                                }
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .tint(ATHLTHArenaV3Style.gold)
                    } else if request.requiresApproval && isAccepted &&
                              request.oldPlayerID != userID &&
                              !replacementVotes.contains(where: {
                                  $0.requestID == request.id && $0.voterID == userID
                              }) {
                        Text("Alle gjenværende deltakere må godkjenne.")
                            .font(.caption)
                        HStack(spacing: 18) {
                            Button("Godkjenn") {
                                Task {
                                    await perform {
                                        try await cloud.voteReplacement(
                                            requestID: request.id,approve: true)
                                        await onChange()
                                    }
                                }
                            }
                            Button("Avvis") {
                                Task {
                                    await perform {
                                        try await cloud.voteReplacement(
                                            requestID: request.id,approve: false)
                                        await onChange()
                                    }
                                }
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .tint(ATHLTHArenaV3Style.gold)
                    } else {
                        Text(request.newPlayerAccepted
                             ? "Venter på godkjenning fra øvrige spillere"
                             : "Venter på svar fra den nye spilleren")
                            .font(.caption)
                            .foregroundStyle(ATHLTHArenaV3Style.secondary)
                    }
                }
                .foregroundStyle(ATHLTHArenaV3Style.ink)
                .padding(15)
                .background(ATHLTHArenaV3Style.panel())
            }
        }
    }

    private func name(_ id: UUID) -> String {
        if id == userID { return session.profile.username }
        return names[id] ?? "Utøver"
    }

    private func participantStatus(_ entry: ATHLTHTournamentRemoteEntry) -> String {
        if entry.removedAt != nil { return "Tatt ut" }
        if entry.response == "invited" { return "Invitert" }
        if entry.response == "declined" { return "Avslått" }
        return entry.isReady ? "Klar" : "Ikke klar"
    }

    private func candidateOrder(_ a: ATHLTHTournamentExerciseCandidateRemote,
                                _ b: ATHLTHTournamentExerciseCandidateRemote) -> Bool {
        if let ai=a.selectedPosition,let bi=b.selectedPosition { return ai<bi }
        if a.selectedPosition != nil { return true }
        if b.selectedPosition != nil { return false }
        return a.createdAt<b.createdAt
    }

    @MainActor
    private func perform(_ operation: @escaping @MainActor () async throws -> Void) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await operation()
            await reload()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func reload() async {
        loading = candidates.isEmpty && messages.isEmpty
        defer { loading = false }
        do {
            async let allCandidates = cloud.candidates(tournamentID: tournament.id)
            async let allVotes = cloud.exerciseVotes(tournamentID: tournament.id)
            async let allMessages = cloud.messages(tournamentID: tournament.id)
            async let allChanges = cloud.playerChanges(tournamentID: tournament.id)
            let candidateRows = try await allCandidates
            let voteRows = try await allVotes
            let messageRows = try await allMessages
            let changes = try await allChanges
            candidates = candidateRows
            votes = voteRows
            messages = messageRows
            replacements = changes
            async let names = cloud.exerciseNames(
                ids: Set(candidateRows.map(\.exerciseID))
            )
            async let approvals = cloud.changeVotes(
                requestIDs: changes.map(\.id)
            )
            exerciseNames = try await names
            replacementVotes = try await approvals
            errorMessage = nil
        } catch {
            errorMessage = "Kunne ikke oppdatere lobbyen: " + error.localizedDescription
        }
    }
}

/// Intentionally a small sheet rather than a second full-screen wizard.
private struct ATHLTHTournamentReplacementPicker: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var social: SocialStore
    let personToReplace: String
    let onSelect: @MainActor (UUID) async -> Void
    @State private var query = ""
    @State private var found: [SocialProfileCard] = []
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading,spacing: 15) {
                Text("Erstatt \(personToReplace)")
                    .font(.system(size: 24,design: .serif))
                Text("Ny deltaker må takke ja. Dersom det kreves enstemmighet, må også alle gjenværende deltakere godkjenne.")
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
                TextField("Søk etter brukernavn",text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(15)
                    .background(ATHLTHArenaV3Style.panel())
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(found,id: \.userID) { person in
                            Button {
                                Task {
                                    await onSelect(person.userID)
                                    dismiss()
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "person.crop.circle")
                                    Text(person.username ?? person.resolvedName)
                                        .lineLimit(1)
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                }
                                .padding(14)
                                .foregroundStyle(ATHLTHArenaV3Style.ink)
                            }
                        }
                    }
                }
                Spacer()
            }
            .padding(18)
            .background(ATHLTHArenaV3Style.cream.ignoresSafeArea())
            .navigationTitle("Spillerbytte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Lukk") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium,.large])
        .task(id: query) {
            guard query.count >= 2 else { found=[]; return }
            let values=await social.searchQuickTrainPartners(query)
            if !Task.isCancelled { found=values }
        }
    }
}

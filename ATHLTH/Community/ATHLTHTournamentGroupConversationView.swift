import SwiftUI

/// A real conversation for one league/cup, shown independently in every
/// invited athlete's Inbox. Messages remain in the existing lobby table;
/// no parallel chat identity or duplicate conversation is created.
struct ATHLTHTournamentGroupConversationView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var social: SocialStore

    let tournament: ATHLTHTournamentRemote

    @State private var current: ATHLTHTournamentRemote?
    @State private var entries: [ATHLTHTournamentRemoteEntry] = []
    @State private var messages: [ATHLTHTournamentLobbyMessageRemote] = []
    @State private var draft = ""
    @State private var announcing = false
    @State private var isLoading = true
    @State private var working = false
    @State private var errorMessage: String?

    private let cloud = ATHLTHTournamentCloudService()
    private let lobby = ATHLTHTournamentLobbyCloudService()

    private var displayed: ATHLTHTournamentRemote { current ?? tournament }
    private var myEntry: ATHLTHTournamentRemoteEntry? {
        entries.first { $0.userID == session.profile.userID }
    }
    private var invited: Bool { myEntry?.response == "invited" }
    private var accepted: Bool {
        myEntry?.response == "accepted" && myEntry?.removedAt == nil
    }
    private var acceptedCount: Int {
        entries.filter { $0.response == "accepted" && $0.removedAt == nil }.count
    }
    private var canWrite: Bool {
        accepted && (displayed.status == "inviting" ||
                     displayed.status == "active") && !working &&
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        draft.count <= 1000
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 13) {
                        pinnedCompetitionCard
                        if invited { invitationCard }
                        if isLoading {
                            ProgressView("Henter samtalen…")
                                .frame(maxWidth: .infinity, minHeight: 70)
                        } else if messages.isEmpty {
                            Text("Her samles viktige beskjeder, rundeoppsummeringer og meldinger fra deltakerne.")
                                .font(.subheadline)
                                .foregroundStyle(ATHLTHArenaV3Style.secondary)
                                .padding(17)
                        }
                        ForEach(messages) { message in
                            messageRow(message)
                                .id(message.id)
                        }
                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: 700)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .refreshable { await reload() }
            }
        }
        .background(ATHLTHArenaV3Style.cream.ignoresSafeArea())
        .navigationTitle(displayed.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if accepted &&
                (displayed.status == "inviting" || displayed.status == "active") {
                composer
            }
        }
        .task(id: displayed.id) {
            await reload()
            await social.markTournamentInboxRead(displayed.id)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                if Task.isCancelled { break }
                if scenePhase == .active { await reload(showLoading: false) }
            }
        }
        .environment(\.colorScheme, .light)
    }

    private var pinnedCompetitionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                Image(systemName: displayed.displayFormatSymbol)
                    .font(.system(size: 21, weight: .light))
                    .foregroundStyle(ATHLTHArenaV3Style.gold)
                    .frame(width: 43, height: 43)
                    .background(ATHLTHArenaV3Style.cream, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayed.title)
                        .font(.headline)
                        .foregroundStyle(ATHLTHArenaV3Style.ink)
                    Text("\(acceptedCount) deltakere · \(statusText)")
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                }
                Spacer(minLength: 0)
            }
            if let date = displayed.plannedStartsAt,
               displayed.status == "inviting" {
                Label("Planlagt start: " + date.formatted(
                    date: .abbreviated, time: .shortened
                ), systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
            }
            NavigationLink {
                ATHLTHTournamentLiveDetailView(tournament: displayed)
            } label: {
                HStack {
                    Text("Se regler, øvelser og resultater")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHArenaV3Style.gold)
                .padding(.vertical, 5)
            }
        }
        .padding(16)
        .background(ATHLTHArenaV3Style.panel())
    }

    private var statusText: String {
        switch displayed.status {
        case "active": return "Pågår"
        case "completed": return "Ferdig"
        case "cancelled": return "Avlyst"
        default: return "Invitasjoner"
        }
    }

    private var invitationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Du er invitert", systemImage: "envelope.badge")
                .font(.headline)
                .foregroundStyle(ATHLTHArenaV3Style.ink)
            Text("Se reglene før du svarer. Du bestemmer selv om du vil delta.")
                .font(.caption)
                .foregroundStyle(ATHLTHArenaV3Style.secondary)
            if !displayed.allowedActions.isEmpty {
                Text("Tillatt: " + displayed.allowedActions).font(.caption)
            }
            if !displayed.prohibitedActions.isEmpty {
                Text("Ikke tillatt: " + displayed.prohibitedActions).font(.caption)
            }
            if !displayed.prizeFirst.isEmpty {
                Text("Premie til vinner: " + displayed.prizeFirst).font(.caption)
            }
            if !displayed.loserConsequence.isEmpty {
                Text("Frivillig konsekvens: " + displayed.loserConsequence)
                    .font(.caption)
            }
            HStack(spacing: 10) {
                Button {
                    Task { await respond(accept: true) }
                } label: {
                    Text("Godta")
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(ATHLTHArenaV3Style.ink, in: Capsule())
                }
                Button {
                    Task { await respond(accept: false) }
                } label: {
                    Text("Avslå")
                        .foregroundStyle(ATHLTHArenaV3Style.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(ATHLTHArenaV3Style.cream, in: Capsule())
                }
            }
            .buttonStyle(.plain)
            .font(.subheadline.weight(.semibold))
            .disabled(working)
        }
        .padding(16)
        .background(ATHLTHArenaV3Style.panel())
    }

    @ViewBuilder
    private func messageRow(_ message: ATHLTHTournamentLobbyMessageRemote) -> some View {
        if message.kind == "system" {
            VStack(alignment: .leading, spacing: 7) {
                Label("ATHLTH · Konkurranse", systemImage: "trophy")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHArenaV3Style.gold)
                Text(message.content)
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHArenaV3Style.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(message.createdAt.formatted(date: .abbreviated,
                                                  time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(ATHLTHArenaV3Style.panel())
        } else {
            let isMine = message.authorID == session.profile.userID
            HStack {
                if isMine { Spacer(minLength: 48) }
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(isMine ? "Du" :
                            (message.kind == "announcement"
                             ? "Arrangør" : "Deltaker"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHArenaV3Style.gold)
                        Spacer(minLength: 6)
                        Text(message.createdAt.formatted(
                            date: .omitted, time: .shortened
                        ))
                        .font(.caption2)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                    }
                    if message.kind == "announcement" {
                        Label("Viktig beskjed fra arrangør",
                              systemImage: "megaphone")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHArenaV3Style.gold)
                    }
                    Text(message.content)
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHArenaV3Style.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(13)
                .background(isMine ? ATHLTHArenaV3Style.cream : Color.white,
                            in: RoundedRectangle(cornerRadius: 16))
                if !isMine { Spacer(minLength: 48) }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 7) {
            if displayed.ownerID == session.profile.userID {
                Toggle("Send som viktig beskjed til alle", isOn: $announcing)
                    .font(.caption.weight(.medium))
                    .tint(ATHLTHArenaV3Style.gold)
            }
            HStack(spacing: 9) {
            TextField("Skriv til konkurransen…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .padding(12)
                .font(.subheadline)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))
            Button {
                Task { await send() }
            } label: {
                if working { ProgressView().tint(.white) }
                else { Image(systemName: "arrow.up").font(.headline) }
            }
            .frame(width: 43, height: 43)
            .foregroundStyle(.white)
            .background(ATHLTHArenaV3Style.ink, in: Circle())
            .disabled(!canWrite)
            .accessibilityLabel("Send melding")
        }
            }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    @MainActor
    private func respond(accept: Bool) async {
        guard !working else { return }
        working = true
        defer { working = false }
        do {
            try await cloud.respond(tournamentID: displayed.id, accept: accept)
            await reload(showLoading: false)
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor
    private func send() async {
        guard canWrite else { return }
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        working = true
        defer { working = false }
        do {
            try await lobby.sendMessage(
                tournamentID: displayed.id, text: message,
                announcement: announcing &&
                    displayed.ownerID == session.profile.userID
            )
            draft = ""
            announcing = false
            await reload(showLoading: false)
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor
    private func reload(showLoading: Bool = true) async {
        if showLoading { isLoading = messages.isEmpty }
        defer { isLoading = false }
        do {
            async let tournaments = cloud.visibleTournaments()
            async let nextEntries = cloud.entries(for: displayed.id)
            async let nextMessages = lobby.messages(tournamentID: displayed.id)
            let all = try await tournaments
            guard let latest = all.first(where: { $0.id == tournament.id }) else {
                errorMessage = "Konkurransen er ikke tilgjengelig lenger."
                return
            }
            let athletes = try await nextEntries
            let timeline = try await nextMessages
            guard athletes.contains(where: {
                $0.userID == session.profile.userID &&
                $0.removedAt == nil &&
                $0.response != "declined"
            }) else {
                errorMessage = "Du har ikke lenger tilgang til denne samtalen."
                return
            }
            current = latest
            entries = athletes
            messages = timeline
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

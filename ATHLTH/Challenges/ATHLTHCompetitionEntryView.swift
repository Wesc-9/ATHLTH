import SwiftUI

/// Competition form is the first choice; sports are configured in the rules.
struct ATHLTHCompetitionEntryView: View {
    var preselectedFriend: SocialProfileCard? = nil
    var initialFormat: ATHLTHCompetitionFormat? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: AppSessionStore
    @State private var hubTab: HubTab = .mine
    @State private var tournaments: [ATHLTHTournamentRemote] = []
    @State private var invitedIDs: Set<UUID> = []
    @State private var selectedTournament: ATHLTHTournamentRemote?
    @State private var showingFormats = false
    @State private var loading = false
    @State private var errorMessage: String?
    private let cloud = ATHLTHTournamentCloudService()
    private enum HubTab: String, CaseIterable, Identifiable {
        case mine = "Mine", invitations = "Invitasjoner", history = "Historikk"
        var id: String { rawValue }
    }
    private var isDirectEntry: Bool { preselectedFriend != nil || initialFormat != nil }
    @State private var selectedFormat: ATHLTHCompetitionFormat?
    @State private var initialized = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    ATHLTHTrainPageTitle(title: "Konkurranse")
                    if !isDirectEntry && !showingFormats { hubContent } else {
                    Text("Velg hvordan dere vil konkurrere.")
                        .font(ATHLTHTrainDesign.pageSubtitle)
                        .foregroundStyle(ATHLTHTrainDesign.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
                        ForEach(ATHLTHCompetitionFormat.allCases) { format in
                            Button { selectedFormat = format } label: {
                                competitionHero(format)
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text(format.title + ", " + format.subtitle))
                            .accessibilityValue(Text(participantLabel(format)))
                            .accessibilityIdentifier("athlth-competition-entry-\(format.rawValue)")
                        }
                    }
                    }
                }
                .padding(18).frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .background(ATHLTHTrainDesign.canvas.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await reloadHub() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(showingFormats && !isDirectEntry ? "Tilbake" : "Lukk") {
                        if showingFormats && !isDirectEntry { showingFormats = false; Task { await reloadHub() } }
                        else { dismiss() }
                    }
                }
            }
        }
        .fullScreenCover(item: $selectedFormat.keepingPresentedItemWhenInactive(scenePhase)) { format in
            AnyView(ATHLTHCompetitionCreationView(
                initialActivity: .running, advanced: true,
                initialFormat: format, preselectedFriend: preselectedFriend,
                choosesActivityInRules: true
            ))
        }
        .fullScreenCover(item: $selectedTournament, onDismiss: { Task { await reloadHub() } }) { item in
            NavigationStack {
                ATHLTHTournamentLiveDetailView(tournament: item)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Lukk") { selectedTournament = nil } } }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task(id: session.profile.userID) { if !isDirectEntry { await reloadHub() } }
        .onChange(of: selectedFormat) { _, value in
            if value == nil && !isDirectEntry { showingFormats = false; Task { await reloadHub() } }
        }
        .onAppear {
            guard !initialized else { return }
            initialized = true
            if let initialFormat { selectedFormat = initialFormat }
            else if session.signedIn {
                let friend = preselectedFriend?.userID.uuidString ?? "none"
                let pending = ATHLTHCompetitionFormat.allCases.compactMap { format -> (ATHLTHCompetitionFormat, ATHLTHCompetitionCreationCheckpoint)? in
                    guard let saved = ATHLTHCompetitionCreationCheckpoint.load(owner: session.profile.userID,
                        entry: format.rawValue + "." + friend + ".running.true"), saved.hasProgress else { return nil }
                    return (format, saved)
                }
                selectedFormat = pending.max {
                    ($0.1.updatedAt ?? .distantPast) < ($1.1.updatedAt ?? .distantPast)
                }?.0
            }
        }
    }

    private func participantLabel(_ format: ATHLTHCompetitionFormat) -> String {
        format == .duel ? "2 deltakere" :
            "Minst \(ATHLTHCompetitionCreationPolicy.minOpponents(format) + 1) deltakere"
    }

    private func competitionHero(_ format: ATHLTHCompetitionFormat) -> some View {
        let artwork: String = {
            switch format.title {
            case "Duell": return "StrengthQuickHero"
            case "Enkeltkonkurranse": return "TrainHero"
            case "Liga": return "GoalRunning"
            case "Cup": return "GoalAdventure"
            default: return "TrainHero"
            }
        }()
        return ZStack(alignment: .bottomLeading) {
            GeometryReader { geometry in
                Image(artwork)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            }
            LinearGradient(
                stops: [.init(color: .black.opacity(0.84), location: 0),
                        .init(color: .black.opacity(0.65), location: 0.55),
                        .init(color: .black.opacity(0.18), location: 1)],
                startPoint: .leading, endPoint: .trailing
            )
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(participantLabel(format), systemImage: format.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(red: 0.97, green: 0.88, blue: 0.68))
                    Text(format.title)
                        .font(.system(.title2, design: .serif).weight(.semibold))
                        .foregroundStyle(.white)
                    Text(format.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.black.opacity(0.28), in: Circle())
                    .accessibilityHidden(true)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var filtered: [ATHLTHTournamentRemote] {
        tournaments.filter { item in
            switch hubTab {
            case .mine: return !invitedIDs.contains(item.id) && ["active", "inviting"].contains(item.status)
            case .invitations: return invitedIDs.contains(item.id) && item.status == "inviting"
            case .history: return ["completed", "cancelled"].contains(item.status)
            }
        }.sorted { $0.createdAt > $1.createdAt }
    }

    private var hubContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button { showingFormats = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "trophy.fill").font(.title2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ny konkurranse").font(ATHLTHTrainDesign.cardTitle)
                        Text("Duell, enkeltkonkurranse, liga eller cup").font(.caption)
                    }
                    Spacer()
                    Image(systemName: "plus.circle").font(.title2)
                }
                .foregroundStyle(.white)
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(ATHLTHTrainDesign.bronze, in: RoundedRectangle(cornerRadius: 23))
            }.buttonStyle(.plain)
            Picker("Konkurranser", selection: $hubTab) {
                ForEach(HubTab.allCases) { tab in
                    Text(tab == .invitations && !invitedIDs.isEmpty ? "Invitasjoner (\(invitedIDs.count))" : tab.rawValue).tag(tab)
                }
            }.pickerStyle(.segmented)
            if loading && tournaments.isEmpty { ProgressView("Henter konkurranser…") }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
                Button("Prøv igjen") { Task { await reloadHub() } }.font(.subheadline)
            }
            if filtered.isEmpty && !loading && errorMessage == nil {
                Text(hubTab == .invitations ? "Ingen nye invitasjoner." : hubTab == .history ? "Ingen avsluttede konkurranser." : "Ingen pågående konkurranser.")
                    .font(.subheadline).foregroundStyle(ATHLTHTrainDesign.secondary)
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading).athlthTrainEditorialCard()
            }
            ForEach(filtered) { item in
                Button { selectedTournament = item } label: {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text(item.displayFormatTitle + (item.seasonLabel.map { " · " + $0 } ?? ""))
                                .font(ATHLTHTrainDesign.cardEyebrow).foregroundStyle(ATHLTHTrainDesign.bronze)
                            Spacer()
                            Text(status(item)).font(.caption)
                        }
                        HStack {
                            Image(systemName: item.displayFormatSymbol).foregroundStyle(ATHLTHTrainDesign.bronze)
                            Text(item.title).font(ATHLTHTrainDesign.cardTitle)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption)
                        }
                        Text(item.selectedBranchesLabel).font(.caption).foregroundStyle(ATHLTHTrainDesign.secondary)
                        if let end = item.raceRules.endDate, item.status == "active" {
                            Label("Frist " + end.formatted(date: .abbreviated, time: .shortened), systemImage: "clock").font(.caption)
                        }
                    }.foregroundStyle(ATHLTHTrainDesign.ink).padding(15).athlthTrainEditorialCard()
                }.buttonStyle(.plain)
            }
        }
    }
    private func status(_ item: ATHLTHTournamentRemote) -> String {
        if invitedIDs.contains(item.id) && item.status == "inviting" { return "Svar på invitasjon" }
        switch item.status {
        case "active": return "Pågår"
        case "completed": return "Fullført"
        case "cancelled": return "Avlyst"
        default: return "Venter på deltakere"
        }
    }
    @MainActor private func reloadHub() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        let userID = session.profile.userID
        do {
            async let records = cloud.visibleTournaments()
            async let memberIDs = cloud.myTournamentIDs(userID: userID)
            async let invitations = cloud.pendingInvitationIDs(userID: userID)
            let (all, mine, invited) = try await (records, memberIDs, invitations)
            guard session.profile.userID == userID else { return }
            tournaments = all.filter { mine.contains($0.id) || invited.contains($0.id) }
            invitedIDs = invited.intersection(Set(tournaments.filter { $0.status == "inviting" }.map(\.id)))
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
}

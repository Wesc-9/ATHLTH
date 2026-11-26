import SwiftUI

/// Competition form is the first choice; sports are configured in the rules.
struct ATHLTHCompetitionEntryView: View {
    var preselectedFriend: SocialProfileCard? = nil
    var initialFormat: ATHLTHCompetitionFormat? = nil
    var locksRunningActivity = false
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
                choosesActivityInRules: !locksRunningActivity
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
        }.sorted {
            if hubTab == .history { return historyDate($0) > historyDate($1) }
            return $0.createdAt > $1.createdAt
        }
    }

    private var hubContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            competitionDashboard
            HStack(spacing: 6) {
                ForEach(HubTab.allCases) { tab in
                    Button {
                        hubTab = tab
                    } label: {
                        VStack(spacing: 5) {
                            Text(tab.rawValue).font(.subheadline.weight(.semibold))
                            Text(String(tabCount(tab))).font(.caption.monospacedDigit())
                        }
                        .foregroundStyle(hubTab == tab ? ATHLTHTrainDesign.bronze : ATHLTHTrainDesign.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background {
                            if hubTab == tab {
                                RoundedRectangle(cornerRadius: 14).fill(Color.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(hubTab == tab ? .isSelected : [])
                }
            }
            .padding(4)
            .background(ATHLTHTrainDesign.paleGold, in: RoundedRectangle(cornerRadius: 18))
            if loading && tournaments.isEmpty { ProgressView("Henter konkurranser…") }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
                Button("Prøv igjen") { Task { await reloadHub() } }.font(.subheadline)
            }
            if filtered.isEmpty && !loading && errorMessage == nil {
                emptyCompetitionState
            }
            if hubTab == .history && !filtered.isEmpty {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { item in
                        Button { selectedTournament = item } label: { historyRow(item) }
                            .buttonStyle(.plain)
                        if item.id != filtered.last?.id { Divider().padding(.leading, 54) }
                    }
                }
                .padding(.horizontal, 12)
                .athlthTrainEditorialCard()
            } else {
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
    }

    private func tabCount(_ tab: HubTab) -> Int {
        tournaments.filter { item in
            switch tab {
            case .mine: return !invitedIDs.contains(item.id) && ["active", "inviting"].contains(item.status)
            case .invitations: return invitedIDs.contains(item.id) && item.status == "inviting"
            case .history: return ["completed", "cancelled"].contains(item.status)
            }
        }.count
    }

    private var competitionDashboard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("DIN KONKURRANSEARENA")
                        .font(.caption2.weight(.semibold)).tracking(1.6)
                    Text("Utfordre deg selv.\nKonkurrer sammen.")
                        .font(.system(size: 27, design: .serif))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "trophy")
                    .font(.system(size: 34, weight: .light))
                    .frame(width: 62, height: 62)
                    .background(.white.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)
            }
            HStack(spacing: 16) {
                dashboardMetric("Pågår", tournaments.filter { $0.status == "active" }.count)
                dashboardMetric("Fullført", tournaments.filter { $0.status == "completed" }.count)
            }
            Button { showingFormats = true } label: {
                HStack {
                    Text("Ny konkurranse").font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "plus.circle")
                }
                .foregroundStyle(ATHLTHTrainDesign.bronze)
                .padding(14)
                .background(.white, in: RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [ATHLTHTrainDesign.bronze, ATHLTHTrainDesign.ink],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24)
        )
    }

    private func dashboardMetric(_ label: String, _ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(String(count)).font(.system(size: 25, design: .serif)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyCompetitionState: some View {
        VStack(spacing: 10) {
            Image(systemName: hubTab == .invitations ? "envelope" : hubTab == .history ? "clock.arrow.circlepath" : "flag.checkered")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(ATHLTHTrainDesign.bronze)
                .frame(width: 54, height: 54)
                .background(ATHLTHTrainDesign.paleGold, in: Circle())
            Text(hubTab == .invitations ? "Ingen nye invitasjoner" : hubTab == .history ? "Ingen avsluttede konkurranser" : "Klar for en utfordring?")
                .font(ATHLTHTrainDesign.cardTitle)
            Text(hubTab == .invitations ? "Invitasjoner fra andre vises her." : hubTab == .history ? "Fullførte og avlyste konkurranser samles her." : "Opprett en konkurranse og utfordre en venn eller en gruppe.")
                .font(.subheadline)
                .foregroundStyle(ATHLTHTrainDesign.secondary)
                .multilineTextAlignment(.center)
            if hubTab == .mine {
                Button("Velg konkurranseform") { showingFormats = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                    .padding(.top, 5)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .athlthTrainEditorialCard()
    }

    private func historyDate(_ item: ATHLTHTournamentRemote) -> Date {
        item.completedAt ?? item.startedAt ?? item.createdAt
    }

    private func historyRow(_ item: ATHLTHTournamentRemote) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.displayFormatSymbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(ATHLTHTrainDesign.bronze)
                .frame(width: 42, height: 42)
                .background(ATHLTHTrainDesign.paleGold, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTrainDesign.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.displayFormatTitle + (item.seasonLabel.map { " · " + $0 } ?? ""))
                    .font(.caption).foregroundStyle(ATHLTHTrainDesign.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 4) {
                Text(historyDate(item).formatted(.dateTime.day().month(.abbreviated).year()))
                    .font(.caption2).foregroundStyle(ATHLTHTrainDesign.secondary)
                Text(status(item))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(item.status == "cancelled" ? Color.red : ATHLTHTrainDesign.bronze)
                if item.completedAt == nil {
                    Text(item.startedAt == nil ? "Opprettet" : "Startet")
                        .font(.caption2).foregroundStyle(ATHLTHTrainDesign.secondary)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            Image(systemName: "chevron.right").font(.caption2)
                .foregroundStyle(ATHLTHTrainDesign.secondary)
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
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

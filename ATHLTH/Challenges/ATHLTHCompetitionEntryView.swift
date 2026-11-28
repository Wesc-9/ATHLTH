import SwiftUI

/// Width is the Studio detail column, not the entire device display.
enum ATHLTHCompetitionStudioLayout {
    static let padding: CGFloat = 20
    static let spacing: CGFloat = 16
    static let formatSpacing: CGFloat = 12

    // Keep a little breathing room at the outer edge of the right column.
    static func formatGridWidth(available: CGFloat) -> CGFloat {
        max(0, available.isFinite ? available - 8 : 0)
    }

    static func formatImageHeight(isGhost: Bool, accessibilityText: Bool) -> CGFloat {
        if accessibilityText { return isGhost ? 150 : 142 }
        return isGhost ? 100 : 116
    }

    static func formatTextMinimumHeight(isGhost: Bool, accessibilityText: Bool) -> CGFloat {
        if accessibilityText { return isGhost ? 86 : 112 }
        return isGhost ? 64 : 90
    }

    static func usesColumns(width: CGFloat, accessibilityText: Bool) -> Bool {
        width >= 800 && !accessibilityText
    }

    static func overviewWidth(contentWidth: CGFloat) -> CGFloat {
        max(0, min(contentWidth - spacing, max(285, (contentWidth - spacing) * 0.37)))
    }

    static func formatColumnCount(width: CGFloat, accessibilityText: Bool) -> Int {
        width >= 470 && !accessibilityText ? 2 : 1
    }
}

/// Competition form is the first choice; sports are configured in the rules.
struct ATHLTHCompetitionEntryView: View {
    var preselectedFriend: SocialProfileCard? = nil
    var initialFormat: ATHLTHCompetitionFormat? = nil
    var locksRunningActivity = false
    var openGhostInitially = false
    var usesStudioHubLayout = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: AppSessionStore
    @State private var hubTab: HubTab = .mine
    @State private var tournaments: [ATHLTHTournamentRemote] = []
    @State private var invitedIDs: Set<UUID> = []
    @State private var selectedTournament: ATHLTHTournamentRemote?
    @State private var showingFormats = false
    @State private var showingPersonalGhost = false
    @State private var dismissAfterPersonalGhost = false
    @State private var loading = false
    @State private var errorMessage: String?
    private let cloud = ATHLTHTournamentCloudService()
    private enum HubTab: String, CaseIterable, Identifiable {
        case mine = "Mine", invitations = "Invitasjoner", history = "Historikk"
        var id: String { rawValue }
    }
    private var isDirectEntry: Bool { preselectedFriend != nil || initialFormat != nil }
    private var isStudioHub: Bool { usesStudioHubLayout && !isDirectEntry }
    private var isChoosingFormats: Bool { showingFormats && !isDirectEntry && !isStudioHub }
    @State private var selectedFormat: ATHLTHCompetitionFormat?
    @State private var initialized = false

    var body: some View {
        NavigationStack {
            Group {
                if isStudioHub {
                    GeometryReader { geometry in
                        ScrollView {
                            studioHub(width: geometry.size.width)
                        }
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 15) {
                            ATHLTHTrainPageTitle(title: "Konkurranse")
                            if !isDirectEntry && !showingFormats {
                                hubContent
                            } else {
                                Text("Velg hvordan du vil konkurrere.")
                                    .font(ATHLTHTrainDesign.pageSubtitle)
                                    .foregroundStyle(ATHLTHTrainDesign.secondary)
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
                                    formatButtons
                                    if !isDirectEntry { ghostButton }
                                }
                            }
                        }
                        .padding(18).frame(maxWidth: 820)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .background(ATHLTHTrainDesign.canvas.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await reloadHub() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChoosingFormats ? "Tilbake" : "Lukk") {
                        if isChoosingFormats { showingFormats = false; Task { await reloadHub() } }
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
        .fullScreenCover(isPresented: $showingPersonalGhost, onDismiss: {
            if dismissAfterPersonalGhost {
                dismissAfterPersonalGhost = false
                dismiss()
            }
        }) {
            NavigationStack {
                ATHLTHSoloGhostSetupView(onStarted: {
                    dismissAfterPersonalGhost = true
                    showingPersonalGhost = false
                })
            }
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
            if openGhostInitially { showingPersonalGhost = true }
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

    private func studioHub(width: CGFloat) -> some View {
        let layout = ATHLTHCompetitionStudioLayout.self
        let contentWidth = max(0, width - 2 * layout.padding)
        let overviewWidth = layout.overviewWidth(contentWidth: contentWidth)
        let formsWidth = max(0, contentWidth - overviewWidth - layout.spacing)
        let accessibilityText = dynamicTypeSize.isAccessibilitySize

        return VStack(alignment: .leading, spacing: 16) {
            ATHLTHTrainPageTitle(title: "Konkurranse")
            studioDashboard(wide: layout.usesColumns(width: width, accessibilityText: accessibilityText))
            if layout.usesColumns(width: width, accessibilityText: accessibilityText) {
                HStack(alignment: .top, spacing: layout.spacing) {
                    studioOverview
                        .frame(width: overviewWidth, alignment: .topLeading)
                        .accessibilityIdentifier("athlth-ipad-competition-overview")
                    studioFormats(width: formsWidth)
                        .frame(width: formsWidth, alignment: .topLeading)
                }
            } else {
                // Keep both sections on one page in portrait and Stage Manager.
                studioOverview
                    .accessibilityIdentifier("athlth-ipad-competition-overview")
                studioFormats(width: contentWidth)
            }
        }
        .padding(layout.padding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("athlth-ipad-competition-workspace")
    }

    private var studioOverview: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dine konkurranser")
                    .font(.system(.title2, design: .serif).weight(.semibold))
                    .foregroundStyle(ATHLTHTrainDesign.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("Følg med på invitasjoner og resultater.")
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
            }
            hubContent
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func studioDashboard(wide: Bool) -> some View {
        Group {
            if wide {
                HStack(alignment: .center, spacing: 24) {
                    studioDashboardHeading
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Rectangle().fill(Color(red: 0.83, green: 0.71, blue: 0.53).opacity(0.40)).frame(width: 1, height: 58)
                        .accessibilityHidden(true)
                    studioDashboardMetrics
                        .frame(maxWidth: 390)
                }
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    studioDashboardHeading
                    studioDashboardMetrics
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(stops: [
                    .init(color: Color(red: 0.45, green: 0.35, blue: 0.25), location: 0),
                    .init(color: Color(red: 0.29, green: 0.24, blue: 0.20), location: 0.44),
                    .init(color: Color(red: 0.13, green: 0.14, blue: 0.15), location: 1)
                ], startPoint: .leading, endPoint: .trailing))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(RadialGradient(colors: [Color(red: 0.86, green: 0.70, blue: 0.46).opacity(0.16), .clear],
                                             center: .topLeading, startRadius: 0, endRadius: 280))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                }
        }
    }

    private var studioDashboardHeading: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "trophy")
                .font(.system(size: 27, weight: .light))
                .frame(width: 52, height: 52)
                .foregroundStyle(Color(red: 0.98, green: 0.91, blue: 0.79))
                .background(.white.opacity(0.10), in: Circle())
                .overlay { Circle().strokeBorder(.white.opacity(0.20), lineWidth: 1) }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("DIN KONKURRANSEARENA")
                    .font(.caption2.weight(.semibold)).tracking(1.5)
                    .foregroundStyle(.white.opacity(0.82))
                Text("Utfordre deg selv. Konkurrer sammen.")
                    .font(.system(.title2, design: .serif))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var studioDashboardMetrics: some View {
        HStack(alignment: .top, spacing: 12) {
            dashboardMetric("Pågår", tournaments.filter { $0.status == "active" }.count)
            dashboardMetric("Invitasjoner", tabCount(.invitations))
            dashboardMetric("Fullført", tournaments.filter { $0.status == "completed" }.count)
        }
    }

    private func studioFormats(width: CGFloat) -> some View {
        let layout = ATHLTHCompetitionStudioLayout.self
        let gridWidth = layout.formatGridWidth(available: width)
        let count = layout.formatColumnCount(
            width: gridWidth, accessibilityText: dynamicTypeSize.isAccessibilitySize
        )
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ny konkurranse")
                    .font(.system(.title2, design: .serif).weight(.semibold))
                    .foregroundStyle(ATHLTHTrainDesign.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("Velg hvordan du vil konkurrere.")
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: layout.formatSpacing, alignment: .top), count: count), spacing: layout.formatSpacing) {
                formatButtons
            }
            // Solo competition gets the full final row, not an empty grid cell.
            ghostButton
        }
        .frame(width: gridWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("athlth-ipad-competition-formats")
    }

    private var formatButtons: some View {
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

    private var ghostButton: some View {
        Button { showingPersonalGhost = true } label: {
            competitionArtworkCard(
                artwork: "GoalRunning",
                participants: "1 deltaker · Alene",
                symbol: "figure.run",
                title: "Ghost Race",
                subtitle: "Løp alene mot en tidligere økt eller en digital fartsholder."
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ghost Race, løp alene mot en tidligere økt eller en digital fartsholder.")
        .accessibilityValue("1 deltaker")
        .accessibilityIdentifier("athlth-competition-entry-ghost")
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
            case "Liga": return isStudioHub ? "ATHLTHTrackTeam" : "GoalRunning"
            case "Cup": return "GoalAdventure"
            default: return "TrainHero"
            }
        }()
        return competitionArtworkCard(artwork: artwork, participants: participantLabel(format),
                                      symbol: format.symbol, title: format.title, subtitle: format.subtitle)
    }

    private func competitionArtworkCard(artwork: String, participants: String, symbol: String,
                                        title: String, subtitle: String) -> some View {
        Group {
            if isStudioHub {
                studioArtworkCard(artwork: artwork, participants: participants,
                                  symbol: symbol, title: title, subtitle: subtitle)
            } else {
                compactArtworkCard(artwork: artwork, participants: participants,
                                   symbol: symbol, title: title, subtitle: subtitle)
            }
        }
    }

    private func compactArtworkCard(artwork: String, participants: String, symbol: String,
                                   title: String, subtitle: String) -> some View {
        ZStack(alignment: .bottomLeading) {
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
                    Label(participants, systemImage: symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(red: 0.97, green: 0.88, blue: 0.68))
                    Text(title)
                        .font(.system(.title2, design: .serif).weight(.semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
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

    /// Studio has space for an editorial image and a separate readable text
    /// surface. Avoid forcing long Norwegian titles onto dark photographs.
    private func studioArtworkCard(artwork: String, participants: String, symbol: String,
                                    title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: ATHLTHCompetitionStudioLayout.formatImageHeight(
                    isGhost: title == "Ghost Race", accessibilityText: dynamicTypeSize.isAccessibilitySize))
                .overlay {
                    GeometryReader { geometry in
                        Image(artwork)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    }
                }
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, .black.opacity(0.24)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .overlay(alignment: .topLeading) {
                    Label(participants, systemImage: symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.7), in: Capsule())
                        .padding(9)
                }
                .clipped()
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .center, spacing: 6) {
                    Text(title)
                        .font(.system(.title3, design: .serif).weight(.semibold))
                        .foregroundStyle(ATHLTHTrainDesign.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                        .frame(width: 28, height: 28)
                        .background(ATHLTHTrainDesign.canvas, in: Circle())
                        .accessibilityHidden(true)
                }
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: ATHLTHCompetitionStudioLayout.formatTextMinimumHeight(
                isGhost: title == "Ghost Race", accessibilityText: dynamicTypeSize.isAccessibilitySize), alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: ATHLTHTrainDesign.cardRadius, style: .continuous))
        .athlthTrainEditorialCard()
        .contentShape(RoundedRectangle(cornerRadius: ATHLTHTrainDesign.cardRadius, style: .continuous))
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
            if !isStudioHub { competitionDashboard }
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
            .background(isStudioHub ? ATHLTHTrainDesign.canvas : ATHLTHTrainDesign.paleGold, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                if isStudioHub {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(ATHLTHTrainDesign.rule.opacity(0.55), lineWidth: 0.8)
                        .allowsHitTesting(false)
                }
            }
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
            if !isStudioHub {
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
        VStack(spacing: 0) {
            if hubTab == .mine {
                emptyCompetitionArtwork
            }
            VStack(spacing: 10) {
                if hubTab != .mine {
                    Image(systemName: hubTab == .invitations ? "envelope" : "clock.arrow.circlepath")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                        .frame(width: 54, height: 54)
                        .background(ATHLTHTrainDesign.paleGold, in: Circle())
                        .accessibilityHidden(true)
                }
                Text(hubTab == .invitations ? "Ingen nye invitasjoner" : hubTab == .history ? "Ingen avsluttede konkurranser" : "Klar for en utfordring?")
                    .font(ATHLTHTrainDesign.cardTitle)
                    .foregroundStyle(ATHLTHTrainDesign.ink)
                    .multilineTextAlignment(.center)
                Text(hubTab == .invitations ? "Invitasjoner fra andre vises her." : hubTab == .history ? "Fullførte og avlyste konkurranser samles her." : "Opprett en konkurranse og utfordre en venn eller en gruppe.")
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if hubTab == .mine && !isStudioHub {
                    Button("Velg konkurranseform") { showingFormats = true }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                        .frame(minHeight: 44)
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, hubTab == .mine ? 18 : 24)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: ATHLTHTrainDesign.cardRadius, style: .continuous))
        .athlthTrainEditorialCard()
    }

    /// Fixed bundled artwork, shared by compact and Studio hub layouts.
    /// A top-aligned crop keeps the two foreground athletes visible.
    private var emptyCompetitionArtwork: some View {
        Color.clear
            .aspectRatio(2, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    Image("ATHLTHTrackRace")
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                        .clipped()
                        .overlay {
                            LinearGradient(
                                colors: [.clear, ATHLTHTrainDesign.bronze.opacity(0.12)],
                                startPoint: .top, endPoint: .bottom
                            )
                        }
                }
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
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

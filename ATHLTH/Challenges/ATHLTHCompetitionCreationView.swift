import SwiftUI
import UIKit

/// Shared competition entry. Every format publishes through the tournament service.
enum ATHLTHCompetitionFormat: String, CaseIterable, Identifiable {
    case duel, single, league, cup
    var id: String { rawValue }

    var title: String {
        switch self {
        case .duel: "Duell"
        case .single: "Enkeltkonkurranse"
        case .league: "Liga"
        case .cup: "Cup"
        }
    }
    var subtitle: String {
        switch self {
        case .duel: return ATHLTHLocalization.choose(
            english: "One opponent, one or more exercises.",
            norwegian: "Én motstander. Én eller flere øvelser.")
        case .single: return ATHLTHLocalization.choose(
            english: "One shared competition with one or more exercises, for three or more athletes.",
            norwegian: "Én felles konkurranse med én eller flere øvelser.")
        case .league: return ATHLTHLocalization.choose(
            english: "Compete in multiple exercises and collect points in a league table.",
            norwegian: "Konkurrer i flere øvelser og samle poeng i en ligatabell.")
        case .cup: return ATHLTHLocalization.choose(
            english: "Knockout rounds lead to one champion.",
            norwegian: "Utslagsrunder frem til én vinner.")
        }
    }
    var symbol: String {
        switch self {
        case .duel: "person.2.fill"
        case .single: "person.3.sequence.fill"
        case .league: "list.number"
        case .cup: "trophy.fill"
        }
    }
}

enum ATHLTHRunningCompetitionBranch: String, CaseIterable, Identifiable {
    case running, sprint
    var id: String { rawValue }
    var title: String { self == .sprint ? "Sprint" : "Vanlig løping" }
}

enum ATHLTHSprintGoal: String, CaseIterable, Identifiable {
    case distance, time, route
    var id: String { rawValue }
    var title: String {
        switch self {
        case .distance: "Distanse"
        case .time: "Tid"
        case .route: "Rute"
        }
    }
}

/// Pure entry policy. A tournament or duel cannot be published with
/// nonexistent rivals, duplicated participants or invalid measures.
enum ATHLTHCompetitionCreationPolicy {
    static func duelName(owner: String, opponent: String?, branches: [String]) -> String {
        let opponentName = opponent?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rival = opponentName.flatMap { $0.isEmpty ? nil : $0 } ?? "motstander"
        let prefix = "Duell "
        let suffix = branches.isEmpty ? " i valgt gren" : " i " + branches.joined(separator: " og ")
        let namesBudget = max(2, 80 - prefix.count - suffix.count - 4)
        let firstBudget = min(owner.count, namesBudget / 2)
        let secondBudget = max(1, namesBudget - firstBudget)
        return String((prefix + String(owner.prefix(firstBudget)) + " vs " +
            String(rival.prefix(secondBudget)) + suffix).prefix(80))
    }

    /// The canonical activity grid never hides unsupported categories.
    /// Do not silently map cycling, mobility or custom to a different sport.
    /// These categories stay visible but cannot create unscorable events.
    static func quickStartActivity(for type: ATHLTHPlannedWorkoutType) -> ATHLTHQuickStartActivity? {
        switch type {
        case .running: return .running
        case .walking: return .walking
        case .strength: return .strength
        case .cycling, .mobility, .custom: return nil
        }
    }

    static func sport(_ activity: ATHLTHQuickStartActivity) -> ATHLTHChallengeSport {
        switch activity {
        case .running: .running
        case .walking: .walking
        case .strength: .strength
        }
    }
    static func tournamentActivity(
        _ activity: ATHLTHQuickStartActivity
    ) -> ATHLTHTournamentActivity {
        switch activity {
        case .running: .running
        case .walking: .walking
        case .strength: .strength
        }
    }
    static func defaultScoring(
        for activity: ATHLTHQuickStartActivity
    ) -> ATHLTHChallengeScoring {
        switch activity {
        case .running: .fastestDistance
        case .walking: .mostDistance
        case .strength: .workoutVolume
        }
    }

    static func minOpponents(_ format: ATHLTHCompetitionFormat) -> Int {
        switch format {
        case .duel: 1
        case .single: 2
        case .league: 1
        case .cup: 3
        }
    }

    static func canContinueToRules(name: String, ownerID: UUID, opponents: Set<UUID>,
                                   format: ATHLTHCompetitionFormat) -> Bool {
        let length = name.trimmingCharacters(in: .whitespacesAndNewlines).count
        return (3...80).contains(length) && !opponents.contains(ownerID) &&
            opponents.count >= minOpponents(format) &&
            opponents.count <= (format == .duel ? 1 : 20)
    }

    static func opponentsAfterFormatChange(
        _ chosen: Set<UUID>, format: ATHLTHCompetitionFormat, preferred: UUID?
    ) -> Set<UUID> {
        guard format == .duel, chosen.count > 1 else { return chosen }
        if let preferred, chosen.contains(preferred) { return [preferred] }
        return Set(chosen.sorted { $0.uuidString < $1.uuidString }.prefix(1))
    }

    static func canPublish(
        name: String,
        ownerID: UUID,
        opponents: Set<UUID>,
        format: ATHLTHCompetitionFormat,
        metric: ATHLTHChallengeScoring,
        activity: ATHLTHQuickStartActivity,
        distanceKM: Double,
        durationMinutes: Double,
        exerciseName: String,
        hasRoute: Bool = false,
        endsAt: Date,
        now: Date
    ) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (3...80).contains(trimmed.count),
              !opponents.contains(ownerID),
              opponents.count >= minOpponents(format),
              opponents.count <= 20,
              (format != .duel || opponents.count == 1),
              (format != .duel ||
               (endsAt > now.addingTimeInterval(600) &&
                endsAt <= now.addingTimeInterval(90 * 86_400)))
        else { return false }
        guard format == .duel else { return true }

        switch activity {
        case .running, .walking:
            guard [.fastestDistance, .fastestRoute, .farthestInTime, .mostDistance]
                .contains(metric) else { return false }
            if metric == .fastestRoute { return hasRoute }
            if metric == .fastestDistance {
                return distanceKM.isFinite && (0.1...500).contains(distanceKM)
            }
            if metric == .farthestInTime {
                return durationMinutes.isFinite &&
                    ((10.0 / 60.0)...1_440.0).contains(durationMinutes)
            }
        case .strength:
            guard [.workoutVolume, .mostReps, .heaviestWeight, .exerciseVolume]
                .contains(metric) else { return false }
            if metric != .workoutVolume {
                return !exerciseName.trimmingCharacters(
                    in: .whitespacesAndNewlines).isEmpty
            }
        }
        return true
    }
}

/// iPad uses a live review alongside the editor; phones retain the review step.
@MainActor
enum ATHLTHCompetitionWorkspacePolicy {
    static var usesLiveSummary: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    static func sidebarWidth(available: CGFloat) -> CGFloat? {
        guard available >= 900 else { return nil }
        return min(440, max(320, available * 0.33))
    }
}

/// One adaptive workspace for both creation stages. Independent scroll
/// surfaces keep the overview accessible without moving the editor.
struct ATHLTHCompetitionWorkspace: View {
    let editor: AnyView
    let summary: AnyView
    @State private var compactSummaryExpanded = false

    var body: some View {
        GeometryReader { geometry in
            if let width = ATHLTHCompetitionWorkspacePolicy.sidebarWidth(available: geometry.size.width) {
                HStack(alignment: .top, spacing: 0) {
                    editor
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    ScrollView {
                        summaryContent
                    }
                    .scrollIndicators(.hidden)
                    .frame(width: width)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(ATHLTHTrainDesign.canvas)
                }
            } else {
                VStack(spacing: 0) {
                    Button {
                        compactSummaryExpanded.toggle()
                    } label: {
                        HStack {
                            Label("Sammendrag", systemImage: "list.bullet.rectangle")
                            Spacer()
                            Image(systemName: compactSummaryExpanded ? "chevron.up" : "chevron.down")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(compactSummaryExpanded ? "Utvidet" : "Sammenfoldet")
                    if compactSummaryExpanded {
                        ScrollView { summaryContent }
                            .frame(maxHeight: min(320, geometry.size.height * 0.42))
                    }
                    Divider()
                    editor
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private var summaryContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sammendrag")
                .font(ATHLTHTrainDesign.cardTitle)
                .accessibilityAddTraits(.isHeader)
            summary
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Shared step one: format, name, participants. Dates and sports are rules.
/// A local recovery checkpoint, separate from saved/published competitions.
struct ATHLTHCompetitionCreationCheckpoint: Codable {
    let owner: UUID
    let format: String
    let leagueStyle: ATHLTHTournamentFormat
    let customTitle: String
    let opponents: [UUID]
    let rules: ATHLTHTournamentDraft?
    let inRules: Bool
    let scrollID: String?
    var updatedAt: Date? = Date()

    var hasProgress: Bool { inRules || rules != nil || !opponents.isEmpty || (!customTitle.isEmpty && customTitle != ATHLTHCompetitionFormat(rawValue: format)?.title) }

    static func key(owner: UUID, entry: String) -> String {
        "athlth.competition.creation.v1." + owner.uuidString + "." + entry
    }
    static func load(owner: UUID, entry: String, defaults: UserDefaults = .standard) -> Self? {
        guard let data = defaults.data(forKey: key(owner: owner, entry: entry)),
              let checkpoint = try? JSONDecoder().decode(Self.self, from: data),
              checkpoint.owner == owner, checkpoint.rules.map({ $0.ownerID == owner }) ?? true
        else { return nil }
        return checkpoint
    }
    func save(entry: String, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.key(owner: owner, entry: entry))
        }
    }
    static func clear(owner: UUID, entry: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(owner: owner, entry: entry))
    }
}

/// Live rule autosaves must not mutate the presenting view's SwiftUI state.
@MainActor
private final class ATHLTHCompetitionLiveCheckpoint {
    var draft: ATHLTHTournamentDraft?
    var scrollID: String?
    func reset() { draft = nil; scrollID = nil }
}

struct ATHLTHCompetitionCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var social: SocialStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var checkpointOwner: UUID?
    @State private var restoredRuleScrollID: String?
    @State private var confirmDiscard = false
    @State private var closeAfterDraftDecision = false

    // Keep the caller interface for the route and activity shortcuts.
    let initialActivity: ATHLTHQuickStartActivity
    let advanced: Bool
    var initialFormat: ATHLTHCompetitionFormat? = nil
    var preselectedFriend: SocialProfileCard? = nil
    var preselectedRoute: TrainingRoute? = nil
    var preselectedDistanceKM: Double? = nil
    var choosesActivityInRules = false

    @State private var format: ATHLTHCompetitionFormat = .duel
    @State private var leagueStyle: ATHLTHTournamentFormat = .league
    @State private var competitionTitle = ""
    @State private var chosenIDs: Set<UUID> = []
    @State private var showingParticipantChoices = false
    @State private var showingRules = false
    @State private var finishAfterRules = false
    @State private var ruleDraft: ATHLTHTournamentDraft?
    @State private var liveRuleCheckpoint = ATHLTHCompetitionLiveCheckpoint()
    @State private var didInitialize = false

    private var selectedPeople: [SocialProfileCard] {
        social.mutualFollows.filter { chosenIDs.contains($0.userID) }
    }

    private var checkpointEntry: String {
        (initialFormat?.rawValue ?? "any") + "." + (preselectedFriend?.userID.uuidString ?? "none") + "." +
            String(describing: initialActivity) + "." + String(choosesActivityInRules)
    }
    private var suggestedTitle: String {
        if format == .duel {
            let branches = ruleDraft?.allowedActivities.map(\.title) ??
                (choosesActivityInRules ? [] : [ATHLTHCompetitionCreationPolicy.tournamentActivity(initialActivity).title])
            return ATHLTHCompetitionCreationPolicy.duelName(
                owner: session.profile.username.isEmpty ? "Du" : session.profile.username,
                opponent: selectedPeople.first.map { $0.username ?? $0.resolvedName },
                branches: branches)
        }
        return format.title
    }
    private var effectiveTitle: String {
        let clean = competitionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? suggestedTitle : clean
    }

    private func persistCheckpoint(inRules: Bool? = nil) {
        guard let owner = checkpointOwner, owner == session.profile.userID,
              session.signedIn, !finishAfterRules, !closeAfterDraftDecision else { return }
        ATHLTHCompetitionCreationCheckpoint(owner: owner, format: format.rawValue,
            leagueStyle: leagueStyle, customTitle: competitionTitle,
            opponents: chosenIDs.sorted { $0.uuidString < $1.uuidString },
            rules: liveRuleCheckpoint.draft ?? ruleDraft, inRules: inRules ?? showingRules,
            scrollID: liveRuleCheckpoint.draft == nil ? restoredRuleScrollID : liveRuleCheckpoint.scrollID).save(entry: checkpointEntry)
    }
    private func clearCheckpoint() {
        liveRuleCheckpoint.reset()
        if let owner = checkpointOwner {
            ATHLTHCompetitionCreationCheckpoint.clear(owner: owner, entry: checkpointEntry)
        }
    }

    private var readyForRules: Bool {
        ATHLTHCompetitionCreationPolicy.canContinueToRules(
            name: effectiveTitle, ownerID: session.profile.userID,
            opponents: chosenIDs, format: format) &&
            selectedPeople.count == chosenIDs.count
    }

    private var participants: [ATHLTHTournamentParticipant] {
        chosenIDs.sorted { $0.uuidString < $1.uuidString }.compactMap { id in
            if let person = selectedPeople.first(where: { $0.userID == id }) {
                return ATHLTHTournamentParticipant(id: id, username: person.username ?? person.resolvedName)
            }
            return ruleDraft?.participants.first { $0.id == id }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if ATHLTHCompetitionWorkspacePolicy.usesLiveSummary {
                    ATHLTHCompetitionWorkspace(editor: AnyView(setupEditor), summary: AnyView(setupSummary))
                } else {
                    setupEditor
                }
            }
            .background(ATHLTHTrainDesign.canvas.ignoresSafeArea())
            .navigationTitle("Konkurranse").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { confirmDiscard = true }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    liveRuleCheckpoint.reset()
                    showingRules = true
                    persistCheckpoint(inRules: true)
                } label: {
                    Label("Fortsett til regler", systemImage: "arrow.right")
                        .font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(ATHLTHTrainDesign.bronze, in: RoundedRectangle(cornerRadius: 17))
                }
                .disabled(!readyForRules).opacity(readyForRules ? 1 : 0.48)
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(ATHLTHTrainDesign.canvas)
                .accessibilityIdentifier("athlth-competition-publish")
            }
        }
        .fullScreenCover(isPresented: $showingRules.keepingPresentedWhenInactive(scenePhase), onDismiss: {
            if finishAfterRules { clearCheckpoint(); dismiss() }
            else if scenePhase == .active {
                if let latest = liveRuleCheckpoint.draft {
                    ruleDraft = latest
                    restoredRuleScrollID = liveRuleCheckpoint.scrollID
                    liveRuleCheckpoint.reset()
                }
                persistCheckpoint(inRules: false)
            }
        }) {
            ATHLTHTournamentCreator(
                preset: format == .cup ? .cup : format == .league ? leagueStyle : .league,
                fixedClubID: nil,
                singleEventMode: format == .single || format == .duel,
                duelMode: format == .duel,
                initialTitle: effectiveTitle,
                continuation: ruleDraft,
                fixedInvitees: participants,
                initialActivity: choosesActivityInRules ? nil :
                    ATHLTHCompetitionCreationPolicy.tournamentActivity(initialActivity),
                onBack: { draft in
                    ruleDraft = draft
                    if liveRuleCheckpoint.draft != nil { restoredRuleScrollID = liveRuleCheckpoint.scrollID }
                    liveRuleCheckpoint.reset()
                    persistCheckpoint(inRules: false)
                },
                automaticDuelName: format == .duel && competitionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                restoredScrollID: restoredRuleScrollID,
                onCheckpoint: { draft, scrollID in
                    guard !finishAfterRules, !closeAfterDraftDecision else { return }
                    liveRuleCheckpoint.draft = draft
                    liveRuleCheckpoint.scrollID = scrollID
                    persistCheckpoint(inRules: true)
                },
                onPublished: { _ in finishAfterRules = true; clearCheckpoint() },
                onSave: { draft in
                    var saved = ATHLTHTournamentDraftStore.load(session.profile.userID)
                    saved.removeAll { $0.id == draft.id }
                    saved.append(draft)
                    ATHLTHTournamentDraftStore.save(saved, owner: session.profile.userID)
                    finishAfterRules = true
                    clearCheckpoint()
                }
            )
        }
        .presentationDetents([.large])
        .onAppear {
            guard !didInitialize else { return }
            didInitialize = true
            format = initialFormat ?? .duel
            competitionTitle = format == .duel ? "" : format.title
            checkpointOwner = session.signedIn ? session.profile.userID : nil
            if let owner = checkpointOwner,
               let saved = ATHLTHCompetitionCreationCheckpoint.load(owner: owner, entry: checkpointEntry),
               let savedFormat = ATHLTHCompetitionFormat(rawValue: saved.format),
               initialFormat == nil || initialFormat == savedFormat {
                format = savedFormat
                leagueStyle = saved.leagueStyle
                competitionTitle = saved.customTitle
                chosenIDs = Set(saved.opponents)
                ruleDraft = saved.rules
                restoredRuleScrollID = saved.scrollID
                showingRules = saved.inRules
                return
            }
            if let friend = preselectedFriend, friend.userID != session.profile.userID {
                chosenIDs = [friend.userID]
            }
            persistCheckpoint()
        }
        .onChange(of: competitionTitle) { _, _ in persistCheckpoint() }
        .onChange(of: chosenIDs) { _, _ in persistCheckpoint() }
        .onChange(of: format) { _, _ in persistCheckpoint() }
        .onChange(of: leagueStyle) { _, _ in persistCheckpoint() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active && !showingRules { persistCheckpoint() }
        }
        .onChange(of: session.profile.userID) { _, _ in dismiss() }
        .onChange(of: session.signedIn) { _, signedIn in if !signedIn { dismiss() } }
        .sensoryFeedback(.selection, trigger: confirmDiscard) { _, isPresented in isPresented }
        .sheet(isPresented: $confirmDiscard, onDismiss: {
            // Swipe down or continue editing closes only the decision sheet.
            // Close the setup after the sheet transition, not simultaneously.
            if closeAfterDraftDecision { dismiss() }
        }) {
            ATHLTHDiscardDraftSheet(
                kind: .competition,
                onKeepEditing: {},
                onSaveDraftAndClose: {
                    persistCheckpoint(inRules: false)
                    closeAfterDraftDecision = true
                    confirmDiscard = false
                },
                onDiscard: {
                    // Prevent a scene change during dismissal from recreating
                    // the checkpoint immediately after the explicit discard.
                    closeAfterDraftDecision = true
                    clearCheckpoint()
                    confirmDiscard = false
                }
            )
        }
    }

    private var setupEditor: some View {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: ATHLTHTrainDesign.cardSpacing) {
                    ATHLTHTrainPageTitle(title: format.title)
                    Text(format.subtitle).font(ATHLTHTrainDesign.pageSubtitle)
                        .foregroundStyle(ATHLTHTrainDesign.secondary)
                    if initialFormat == nil {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Konkurranseform").font(ATHLTHTrainDesign.sectionHeading)
                            ForEach(ATHLTHCompetitionFormat.allCases) { item in
                                Button {
                                    format = item
                                    chosenIDs = ATHLTHCompetitionCreationPolicy.opponentsAfterFormatChange(
                                        chosenIDs, format: item, preferred: preselectedFriend?.userID)
                                    competitionTitle = item == .duel ? "" : item.title
                                    ruleDraft = nil
                                    restoredRuleScrollID = nil
                                    liveRuleCheckpoint.reset()
                                } label: {
                                    HStack {
                                        Label(item.title, systemImage: item.symbol)
                                        Spacer()
                                        Image(systemName: format == item ? "checkmark.circle.fill" : "circle")
                                    }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                                    .padding(12).athlthTrainEditorialCard(compact: true, selected: format == item)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    detailsCard
                    if format == .league { leagueCard }
                    if preselectedRoute != nil || preselectedDistanceKM != nil {
                        Text("Velg ønsket distanse eller øvelse i reglene. Ruteverifisering støttes ikke i alle konkurranseformer ennå.")
                            .font(.caption).foregroundStyle(ATHLTHTrainDesign.secondary)
                    }
                    Text("Alle deltakerne må godkjenne de samme reglene før start.")
                        .font(.caption).foregroundStyle(ATHLTHTrainDesign.secondary)
                }
                .padding(18)
                .frame(maxWidth: ATHLTHCompetitionWorkspacePolicy.usesLiveSummary ? .infinity : 650)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollDismissesKeyboard(.interactively)
    }

    private var setupSummary: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(format.title, systemImage: format.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHTrainDesign.bronze)
            Text(effectiveTitle)
                .font(ATHLTHTrainDesign.cardTitle)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                Text("Deltakere").font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(chosenIDs.count + 1)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
            }
            Label("Du (arrangør)", systemImage: "person.crop.circle")
                .font(.subheadline)
            ForEach(selectedPeople, id: \.userID) { friend in
                HStack(spacing: 9) {
                    SocialAvatar(profile: friend, size: 30)
                    Text(friend.resolvedName).font(.subheadline)
                }
            }
            if format == .league {
                Divider()
                Label(leagueStyle == .groups ? "Gruppeliga" : "Stor liga", systemImage: "list.number")
                    .font(.subheadline)
            }
            if let draft = ruleDraft {
                Divider()
                Text(draft.allowedActivities.map(\.title).sorted().joined(separator: " · "))
                    .font(.subheadline)
                Text("\(draft.exerciseCount) konkurranseøvelser")
                    .font(.caption)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
            }
            Divider()
            Label(readyForRules ? "Klar for å velge regler" : "Legg til deltakere for å fortsette",
                  systemImage: readyForRules ? "checkmark.circle" : "info.circle")
                .font(.caption.weight(.medium))
                .foregroundStyle(ATHLTHTrainDesign.secondary)
            Text("Ingen invitasjon er sendt.")
                .font(.caption)
                .foregroundStyle(ATHLTHTrainDesign.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .athlthTrainEditorialCard()
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 12) {
                Image(systemName: format.symbol).font(.title2)
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                    .frame(width: 48, height: 48)
                    .background(ATHLTHTrainDesign.paleGold, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text("KONKURRANSEFORM").font(ATHLTHTrainDesign.cardEyebrow).tracking(1.2)
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                    Text(format.title).font(ATHLTHTrainDesign.cardTitle)
                }
            }
            Divider()
            Text("Navn på konkurransen").font(ATHLTHTrainDesign.rowTitle)
            TextField("", text: $competitionTitle, prompt: Text(suggestedTitle).foregroundStyle(ATHLTHTrainDesign.secondary))
                .padding(12).background(ATHLTHTrainDesign.canvas, in: RoundedRectangle(cornerRadius: 12))
                .onChange(of: competitionTitle) { _, value in
                    if value.count > 80 { competitionTitle = String(value.prefix(80)) }
                }
            Divider()
            HStack {
                Text("Deltakere").font(ATHLTHTrainDesign.cardTitle)
                Spacer()
                Text(format == .duel ? "\(chosenIDs.count + 1)/2" :
                    "\(chosenIDs.count + 1) deltakere")
                    .font(.caption.weight(.semibold)).foregroundStyle(ATHLTHTrainDesign.bronze)
            }
            Label("Du (arrangør)", systemImage: "person.crop.circle.fill")
                .font(.subheadline)
            ForEach(selectedPeople, id: \.userID) { friend in
                HStack {
                    SocialAvatar(profile: friend, size: 36)
                    Text(friend.resolvedName).font(.subheadline)
                    Spacer()
                    Button { chosenIDs.remove(friend.userID); ruleDraft = nil } label: {
                        Image(systemName: "xmark.circle").frame(width: 44, height: 44)
                    }.buttonStyle(.plain)
                }
            }
            Button { showingParticipantChoices.toggle() } label: {
                Label(format == .duel && !chosenIDs.isEmpty ? "Bytt motstander" : "Legg til venner",
                    systemImage: showingParticipantChoices ? "chevron.up" : "plus.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.buttonStyle(.plain)
            if showingParticipantChoices {
                LazyVStack(spacing: 8) {
                ForEach(social.mutualFollows.filter {
                    $0.userID != session.profile.userID && !chosenIDs.contains($0.userID)
                }, id: \.userID) { friend in
                    Button {
                        if format == .duel {
                            chosenIDs = [friend.userID]
                            showingParticipantChoices = false
                        } else if chosenIDs.count < 20 { chosenIDs.insert(friend.userID) }
                        ruleDraft = nil
                    } label: {
                        HStack {
                            SocialAvatar(profile: friend, size: 30)
                            Text(friend.resolvedName)
                            Spacer()
                            Image(systemName: "plus.circle")
                        }
                        .font(.subheadline).padding(10)
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                        .athlthTrainEditorialCard(compact: true)
                    }.buttonStyle(.plain)
                }
                }
            }
            Text(format == .duel ? "Nøyaktig to deltakere, inkludert deg." :
                "Minst \(ATHLTHCompetitionCreationPolicy.minOpponents(format) + 1) deltakere, inkludert deg.")
                .font(.caption).foregroundStyle(ATHLTHTrainDesign.secondary)
        }
        .padding(ATHLTHTrainDesign.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .athlthTrainEditorialCard()
    }

    private var leagueCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ligatype").font(ATHLTHTrainDesign.cardTitle)
            ForEach([ATHLTHTournamentFormat.league, .groups], id: \.self) { item in
                Button { leagueStyle = item; ruleDraft = nil } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item == .league ? "Stor liga" : "Gruppeliga").font(.subheadline.weight(.semibold))
                            Text(item.subtitle).font(.caption)
                        }
                        Spacer()
                        Image(systemName: leagueStyle == item ? "checkmark.circle.fill" : "circle")
                    }
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                    .padding(12).athlthTrainEditorialCard(compact: true, selected: leagueStyle == item)
                }.buttonStyle(.plain)
            }
        }
        .padding(ATHLTHTrainDesign.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .athlthTrainEditorialCard()
    }
}

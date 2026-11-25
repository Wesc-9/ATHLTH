import SwiftUI

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

/// Shared step one: format, name, participants. Dates and sports are rules.
struct ATHLTHCompetitionCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var social: SocialStore

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
    @State private var ruleDraft: ATHLTHTournamentDraft?
    @State private var didInitialize = false

    private var selectedPeople: [SocialProfileCard] {
        social.mutualFollows.filter { chosenIDs.contains($0.userID) }
    }

    private var readyForRules: Bool {
        ATHLTHCompetitionCreationPolicy.canContinueToRules(
            name: competitionTitle, ownerID: session.profile.userID,
            opponents: chosenIDs, format: format) &&
            selectedPeople.count == chosenIDs.count
    }

    private var participants: [ATHLTHTournamentParticipant] {
        selectedPeople.map { ATHLTHTournamentParticipant(id: $0.userID,
            username: $0.username ?? $0.resolvedName) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ATHLTHTrainDesign.cardSpacing) {
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
                                    competitionTitle = item.title
                                    ruleDraft = nil
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
                .padding(18).frame(maxWidth: 650).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(ATHLTHTrainDesign.canvas.ignoresSafeArea())
            .navigationTitle("Konkurranse").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button { showingRules = true } label: {
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
        .sheet(isPresented: $showingRules) {
            ATHLTHTournamentCreator(
                preset: format == .cup ? .cup : format == .league ? leagueStyle : .league,
                fixedClubID: nil,
                singleEventMode: format == .single || format == .duel,
                duelMode: format == .duel,
                initialTitle: competitionTitle,
                continuation: ruleDraft,
                fixedInvitees: participants,
                initialActivity: choosesActivityInRules ? nil :
                    ATHLTHCompetitionCreationPolicy.tournamentActivity(initialActivity),
                onBack: { ruleDraft = $0 },
                onPublished: { _ in showingRules = false; dismiss() },
                onSave: { draft in
                    var saved = ATHLTHTournamentDraftStore.load(session.profile.userID)
                    saved.append(draft)
                    ATHLTHTournamentDraftStore.save(saved, owner: session.profile.userID)
                    showingRules = false
                    dismiss()
                }
            )
        }
        .presentationDetents([.large])
        .onAppear {
            guard !didInitialize else { return }
            didInitialize = true
            format = initialFormat ?? .duel
            competitionTitle = format.title
            if let friend = preselectedFriend, friend.userID != session.profile.userID {
                chosenIDs = [friend.userID]
            }
        }
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
            TextField("Navn", text: $competitionTitle)
                .padding(12).background(ATHLTHTrainDesign.canvas, in: RoundedRectangle(cornerRadius: 12))
                .onChange(of: competitionTitle) { _, _ in ruleDraft = nil }
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
            Text(format == .duel ? "Nøyaktig to deltakere, inkludert deg." :
                "Minst \(ATHLTHCompetitionCreationPolicy.minOpponents(format) + 1) deltakere, inkludert deg.")
                .font(.caption).foregroundStyle(ATHLTHTrainDesign.secondary)
        }
        .padding(ATHLTHTrainDesign.cardPadding).athlthTrainEditorialCard()
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
        .padding(ATHLTHTrainDesign.cardPadding).athlthTrainEditorialCard()
    }
}

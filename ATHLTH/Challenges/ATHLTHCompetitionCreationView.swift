import SwiftUI

/// Single, safe creation entry for all three workout sports. Duel uses the
/// existing Challenge backend; League/Cup use the server-authoritative
/// tournament service. Nothing starts a HealthKit recording here.
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
            english: "One opponent. One challenge.",
            norwegian: "Én motstander. Én utfordring.")
        case .single: return ATHLTHLocalization.choose(
            english: "One event for three or more athletes.",
            norwegian: "Én konkurranse med minst tre deltakere.")
        case .league: return ATHLTHLocalization.choose(
            english: "Everyone competes; a league table determines the winner.",
            norwegian: "Alle møter alle. En tabell avgjør.")
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

struct ATHLTHCompetitionCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var challenges: ChallengeStore
    @EnvironmentObject private var messaging: MessagingStore

    let initialActivity: ATHLTHQuickStartActivity
    let advanced: Bool
    var initialFormat: ATHLTHCompetitionFormat? = nil
    var preselectedFriend: SocialProfileCard? = nil
    var preselectedRoute: TrainingRoute? = nil
    var preselectedDistanceKM: Double? = nil

    @State private var format: ATHLTHCompetitionFormat = .duel
    @State private var leagueStyle: ATHLTHTournamentFormat = .league
    @State private var showingExistingTournamentRules = false
    @State private var showingSavedCompetitionTemplates = false
    @State private var restoredCompetitionTemplate: ATHLTHTournamentDraft?
    @State private var showingSprintRoutePicker = false
    @State private var competitionTitle = ""
    @State private var chosenIDs: Set<UUID> = []
    @State private var scoring: ATHLTHChallengeScoring = .fastestDistance
    @State private var runningBranch: ATHLTHRunningCompetitionBranch = .running
    @State private var sprintGoal: ATHLTHSprintGoal = .distance
    @State private var distanceKM = 5.0
    @State private var chosenRoute: TrainingRoute?
    @State private var durationMinutes = 30.0
    @State private var exerciseName = ""
    @State private var startsAt = Date().addingTimeInterval(86_400)
    @State private var endsAt = Date().addingTimeInterval(7 * 86_400)
    @State private var simpleStartLater = false
    @State private var duelAgreement = ATHLTHCompetitionAgreement()
    @State private var duelRaceSettings = ATHLTHTournamentCompetitionSettings()
    @State private var duelInvitationDays = 3
    @State private var multipleAttempts = true
    @State private var roundsPerWeek = 7
    @State private var reviewHours = 48
    @State private var winPoints = 3
    @State private var drawPoints = 1
    @State private var showingAdvancedRules = false
    @State private var sending = false
    @State private var errorMessage: String?
    @State private var successful = false
    @State private var didInitialize = false
    @State private var showingDuelRules = false
    @State private var showingParticipantChoices = false
    @State private var groupStartMode: ATHLTHCompetitionStartMode = .manual
    @State private var setupScrollTarget: String?
    @State private var rulesScrollTarget: String?

    private let ink = ATHLTHPlanDesign.ink
    private let bronze = ATHLTHPlanDesign.accentInk
    private let muted = ATHLTHPlanDesign.secondaryInk

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    private var selectedPeople: [SocialProfileCard] {
        social.mutualFollows.filter { chosenIDs.contains($0.userID) }
    }

    private var readyForRules: Bool {
        !chosenIDs.contains(session.profile.userID) &&
        chosenIDs.count >= ATHLTHCompetitionCreationPolicy.minOpponents(format) &&
        chosenIDs.count <= (format == .duel ? 1 : 20) &&
        selectedPeople.count == chosenIDs.count &&
        (format != .duel || (startsAt >= Date().addingTimeInterval(-60) &&
                             endsAt > startsAt &&
                             endsAt > Date().addingTimeInterval(600))) &&
        (format == .duel || groupStartMode != .scheduled ||
         startsAt >= Date().addingTimeInterval(-60))
    }

    private var competitionAthletes: [ATHLTHTournamentParticipant] {
        selectedPeople.map {
            ATHLTHTournamentParticipant(id: $0.userID,
                username: $0.username ?? $0.resolvedName)
        }
    }

    private var effectiveStart: Date {
        advanced ? startsAt :
            (simpleStartLater ? startsAt : Date())
    }
    private var effectiveEnd: Date {
        advanced ? endsAt :
            effectiveStart.addingTimeInterval(7 * 86_400)
    }

    private var chosenDuelRoute: TrainingRoute? {
        guard advanced && format == .duel &&
              duelRaceSettings.race.routeID != nil else {
            return chosenRoute
        }
        return session.savedRoutes.first {
            $0.id == duelRaceSettings.race.routeID
        }
    }

    private var effectiveDuelMetric: ATHLTHChallengeScoring {
        guard advanced, format == .duel else { return scoring }
        switch duelRaceSettings.race.discipline {
        case .sprint:
            switch duelRaceSettings.race.sprintTarget {
            case .distance: return .fastestDistance
            case .duration: return .farthestInTime
            case .route: return .fastestRoute
            }
        case .distance: return .fastestDistance
        case .duration: return .farthestInTime
        case .workout, .laps: return scoring
        }
    }

    private var effectiveDuelDistance: Double {
        advanced && format == .duel &&
        (duelRaceSettings.race.discipline == .sprint ||
         duelRaceSettings.race.discipline == .distance)
        ? Double(duelRaceSettings.race.targetDistanceMeters) / 1_000 : distanceKM
    }

    private var effectiveDuelMinutes: Double {
        advanced && format == .duel &&
        (duelRaceSettings.race.discipline == .sprint ||
         duelRaceSettings.race.discipline == .duration)
        ? Double(duelRaceSettings.race.targetDurationSeconds) / 60 :
          durationMinutes
    }

    private var duelEngineSupportsRule: Bool {
        guard advanced, format == .duel else { return true }
        let race = duelRaceSettings.race
        return race.isValid && race.isOperational &&
            race.discipline != .laps
    }

    private var isValid: Bool {
        ATHLTHCompetitionCreationPolicy.canPublish(
            name: competitionTitle,
            ownerID: session.profile.userID,
            opponents: chosenIDs,
            format: format,
            metric: effectiveDuelMetric,
            activity: initialActivity,
            distanceKM: effectiveDuelDistance,
            durationMinutes: effectiveDuelMinutes,
            exerciseName: exerciseName,
            hasRoute: chosenDuelRoute != nil,
            endsAt: effectiveEnd,
            now: Date()
        ) && (runningBranch != .sprint || format != .duel ||
                (sprintGoal != .route || chosenRoute != nil)) &&
        selectedPeople.count == chosenIDs.count &&
        effectiveStart >= Date().addingTimeInterval(-60) &&
        effectiveStart < effectiveEnd && duelAgreement.isValid &&
        duelEngineSupportsRule
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if showingDuelRules {
                        competitionRules.id("rules")
                    } else {
                        competitionDetails.id("details")
                        titleBlock(tr("Competition format", "Konkurranseform"))
                            .id("format-heading")
                        VStack(spacing: 9) {
                            ForEach(ATHLTHCompetitionFormat.allCases) { option in
                                formatOption(option)
                            }
                        }
                        .id("formats")
                    if initialFormat == nil || initialFormat != .duel {
                        Button {
                            showingSavedCompetitionTemplates = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "square.stack.3d.up")
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Hent lagret konkurransemal")
                                        .font(.subheadline.weight(.semibold))
                                    Text("Velg en mal før du setter opp konkurransen")
                                        .font(.caption)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .foregroundStyle(bronze)
                            .padding(15)
                            .background(.white,
                                in: RoundedRectangle(cornerRadius: 17))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("athlth-competition-load-template")
                        .id("template")
                    }
                        if initialActivity == .running && format == .duel && !advanced {
                            sprintSection.id("sprint")
                        }
                        if !advanced {
                            simpleCompetitionRules.id("simple")
                        } else if format == .league {
                            leagueOrCupSetup.id("league")
                        }
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(tr(
                        "Invited athletes must accept before results count. Only confirmed results determine winners.",
                        "Deltakerne må godta invitasjonen. Kun godkjente resultater teller."
                    ))
                    .font(.caption)
                    .foregroundStyle(muted)
                    .padding(.horizontal, 3)
                }
                .scrollTargetLayout()
                .padding(16)
                .frame(maxWidth: 650)
                .frame(maxWidth: .infinity)
            }
            .scrollPosition(id: Binding<String?>(
                get: { showingDuelRules ? rulesScrollTarget : setupScrollTarget },
                set: { if showingDuelRules { rulesScrollTarget = $0 }
                       else { setupScrollTarget = $0 } }
            ))
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(showingDuelRules ? tr("Rules", "Regler") : tr("Competition", "Konkurranse"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(showingDuelRules ? tr("Back", "Tilbake") : tr("Cancel", "Avbryt")) {
                        if showingDuelRules { showingDuelRules = false }
                        else { dismiss() }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider().opacity(0.32)
                    Button {
                        if showingDuelRules || !advanced {
                            Task { await publish() }
                        } else if format == .duel {
                            rulesScrollTarget = "rules"
                            showingDuelRules = true
                        } else {
                            showingExistingTournamentRules = true
                        }
                    } label: {
                        HStack(spacing: 9) {
                            if sending { ProgressView().tint(.white) }
                            Text(sending
                                ? tr("Creating…", "Oppretter…")
                                : showingDuelRules || !advanced
                                  ? tr("Create and invite", "Opprett og inviter")
                                  : tr("Continue to rules", "Fortsett til regler"))
                                .font(.headline)
                            Image(systemName: "arrow.right")
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 53)
                        .background(bronze, in: RoundedRectangle(cornerRadius: 17))
                    }
                    .disabled(
                        sending || successful ||
                        ((showingDuelRules || !advanced) ? !isValid : !readyForRules)
                    )
                    .opacity(
                        !sending && !successful &&
                        ((showingDuelRules || !advanced) ? isValid : readyForRules) ? 1 : 0.48
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .accessibilityIdentifier("athlth-competition-publish")
                }
                .background(.regularMaterial)
            }
        }
        .sheet(isPresented: $showingSprintRoutePicker) {
            NavigationStack {
                SavedRoutesView(selectionTitle: "Velg sprint-rute") { route in
                    chosenRoute = route
                    scoring = .fastestRoute
                    showingSprintRoutePicker = false
                }
            }
        }
        .sheet(isPresented: $showingSavedCompetitionTemplates) {
            ATHLTHTournamentTemplatePicker { selected in
                let fixedSport = ATHLTHCompetitionCreationPolicy
                    .tournamentActivity(initialActivity)
                guard selected.allowedActivities.contains(fixedSport) else {
                    errorMessage = "Denne malen gjelder en annen treningsform."
                    restoredCompetitionTemplate = nil
                    return
                }
                if let initialFormat,
                   (initialFormat == .cup ? selected.format != .cup :
                    initialFormat == .single ? !selected.singleEventMode :
                    initialFormat == .league
                      ? (selected.format == .cup || selected.singleEventMode)
                      : true) {
                    errorMessage = "Malen har en annen konkurranseform."
                    restoredCompetitionTemplate = nil
                    return
                }
                restoredCompetitionTemplate = selected
                competitionTitle = selected.title
                format = selected.singleEventMode ? .single :
                    (selected.format == .cup ? .cup : .league)
                leagueStyle = selected.format
            }
        }
        .sheet(isPresented: $showingExistingTournamentRules) {
            ATHLTHTournamentCreator(
                preset: format == .cup ? .cup : leagueStyle,
                fixedClubID: nil,
                fixedActivity: ATHLTHCompetitionCreationPolicy.tournamentActivity(
                    initialActivity
                ),
                singleEventMode: format == .single,
                initialTitle: competitionTitle,
                continuation: restoredCompetitionTemplate,
                fixedInvitees: competitionAthletes,
                fixedStartMode: groupStartMode,
                fixedStartDate: groupStartMode == .scheduled ? startsAt : nil,
                onBack: { draft in
                    restoredCompetitionTemplate = draft
                },
                onPublished: { _ in
                    showingExistingTournamentRules = false
                    successful = true
                    dismiss()
                },
                onSave: { newDraft in
                    var saved = ATHLTHTournamentDraftStore.load(
                        session.profile.userID
                    )
                    saved.append(newDraft)
                    ATHLTHTournamentDraftStore.save(
                        saved, owner: session.profile.userID
                    )
                    showingExistingTournamentRules = false
                    dismiss()
                }
            )
        }
        .presentationDetents([.large])
        .onAppear {
            guard !didInitialize else { return }
            didInitialize = true
            format = initialFormat ?? .duel
            scoring = ATHLTHCompetitionCreationPolicy.defaultScoring(
                for: initialActivity
            )
            if let preselectedDistanceKM,
               preselectedDistanceKM.isFinite,
               (0.1...500).contains(preselectedDistanceKM) {
                distanceKM = preselectedDistanceKM
            }
            if let preselectedRoute {
                chosenRoute = preselectedRoute
                scoring = .fastestRoute
                sprintGoal = .route
            }
            if let preselectedFriend, preselectedFriend.userID != session.profile.userID {
                chosenIDs.insert(preselectedFriend.userID)
            }
            if advanced && initialActivity != .strength {
                duelRaceSettings.race.discipline = .distance
                duelRaceSettings.race.targetDistanceMeters =
                    Int(max(100, distanceKM * 1_000))
                if let route = preselectedRoute, initialActivity == .running {
                    duelRaceSettings.race.discipline = .workout
                    chosenRoute = route
                }
            }
            if competitionTitle.isEmpty {
                competitionTitle = "\(format.title) · \(initialActivity.title)"
            }
        }
        .task {
            if social.mutualFollows.isEmpty {
                // Opening the picker only needs mutual friends; a full
                // social refresh also fetches feed, inbox, sessions and
                // challenges and can stall the entire editor.
                await social.refreshHomeFriends()
            }
        }
    }

    private func titleBlock(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 20, weight: .semibold, design: .serif))
            .foregroundStyle(ink)
    }

    private func formatOption(_ option: ATHLTHCompetitionFormat) -> some View {
        Button {
            if format != option { restoredCompetitionTemplate = nil }
            format = option
            chosenIDs = ATHLTHCompetitionCreationPolicy.opponentsAfterFormatChange(
                chosenIDs, format: option, preferred: preselectedFriend?.userID
            )
            competitionTitle = "\(option.title) · \(initialActivity.title)"
            errorMessage = nil
        } label: {
            HStack(spacing: 13) {
                Image(systemName: option.symbol)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(bronze)
                    .frame(width: 46, height: 46)
                    .background(ATHLTHPlanDesign.selectedSurface,
                                in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.title)
                        .font(.headline)
                        .foregroundStyle(ink)
                    Text(option.subtitle)
                        .font(.caption)
                        .foregroundStyle(muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 5)
                Image(systemName: format == option
                      ? "checkmark.circle.fill" : "chevron.right")
                    .foregroundStyle(bronze)
            }
            .padding(14)
            .background(
                format == option ? ATHLTHPlanDesign.selectedSurface : .white,
                in: RoundedRectangle(cornerRadius: 18)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(bronze.opacity(format == option ? 0.55 : 0.12),
                                  lineWidth: format == option ? 1.4 : 0.7)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("athlth-competition-format-\(option.rawValue)")
    }

    private var sprintSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleBlock("Løpegren")
            Picker("Løpegren", selection: $runningBranch) {
                ForEach(ATHLTHRunningCompetitionBranch.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            if runningBranch == .sprint {
                Text("Sprint · samme treningsmotor, med tid, distanse eller lagret rute som mål.")
                    .font(.caption)
                    .foregroundStyle(muted)
                Picker("Sprintmål", selection: $sprintGoal) {
                    ForEach(ATHLTHSprintGoal.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                switch sprintGoal {
                case .distance:
                    HStack {
                        Text("Fast sprintdistanse")
                        Spacer()
                        TextField("100", value: Binding(
                            get: { Int(distanceKM * 1_000) },
                            set: { distanceKM = Double(max(100, min($0, 5_000))) / 1_000 }
                        ), format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                        Text("m")
                    }
                    .font(.subheadline)
                case .time:
                    Stepper("Sprint i \(Int(durationMinutes)) min",
                            value: $durationMinutes, in: 1...10, step: 1)
                        .font(.subheadline)
                case .route:
                    if let chosenRoute {
                        Label(chosenRoute.title, systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(bronze)
                    } else {
                        Text("En lagret rute er påkrevd for å sammenligne tider på samme løype.")
                            .font(.caption)
                            .foregroundStyle(muted)
                    }
                    Button {
                        showingSprintRoutePicker = true
                    } label: {
                        Label(chosenRoute == nil ? "Velg lagret rute" : "Endre rute",
                              systemImage: "map")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(bronze)
                    }
                }
            }
        }
        .padding(15)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .onChange(of: runningBranch) { _, _ in updateSprintScoring() }
        .onChange(of: sprintGoal) { _, _ in updateSprintScoring() }
    }

    private func updateSprintScoring() {
        guard runningBranch == .sprint else {
            scoring = .fastestDistance
            return
        }
        switch sprintGoal {
        case .distance: scoring = .fastestDistance
        case .time:
            scoring = .farthestInTime
            if durationMinutes > 10 { durationMinutes = 1 }
        case .route: scoring = .fastestRoute
        }
        if sprintGoal == .distance &&
           (distanceKM >= 5 || distanceKM < 0.1) {
            distanceKM = 0.1
        }
    }

    private var competitionDetails: some View {
        ATHLTHWorkoutDetailsCard(
            activityTitle: initialActivity.title,
            symbol: initialActivity.symbol,
            showsTimingLabel: false
        ) {
            Label(format.title, systemImage: format.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(bronze)
            Divider()
            if advanced && format == .duel {
                DatePicker(tr("From", "Fra"), selection: $startsAt,
                           in: Date().addingTimeInterval(-60)...,
                           displayedComponents: [.date, .hourAndMinute])
                    .font(.subheadline)
                DatePicker(tr("To", "Til"), selection: $endsAt,
                           in: startsAt.addingTimeInterval(60)...,
                           displayedComponents: [.date, .hourAndMinute])
                    .font(.subheadline)
            } else if advanced {
                Picker(tr("Start", "Start"), selection: $groupStartMode) {
                    ForEach(ATHLTHCompetitionStartMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .font(.subheadline)
                .pickerStyle(.menu)
                if groupStartMode == .scheduled {
                    DatePicker(tr("Date and time", "Dato og klokkeslett"),
                               selection: $startsAt, in: Date().addingTimeInterval(-60)...,
                               displayedComponents: [.date, .hourAndMinute])
                        .font(.subheadline)
                }
            } else {
                Toggle(tr("Set start date", "Velg startdato"), isOn: $simpleStartLater)
                    .font(.subheadline)
                    .tint(bronze)
                if simpleStartLater {
                    DatePicker(tr("Starts", "Starter"), selection: $startsAt,
                               in: Date().addingTimeInterval(-60)...,
                               displayedComponents: [.date, .hourAndMinute])
                        .font(.subheadline)
                }
            }
            Divider()
            participantsCard
        }
        .onChange(of: startsAt) { _, value in
            if endsAt <= value { endsAt = value.addingTimeInterval(7 * 86_400) }
        }
    }

    /// Keep the existing, tested tournament editor for the advanced
    /// rules. This screen is only the common first-class entry and choice.
    private var leagueOrCupSetup: some View {
        VStack(alignment: .leading, spacing: 13) {
            titleBlock(tr("Competition details", "Konkurransedetaljer"))
            if format == .league {
                Text(tr("League format", "Ligatype"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(bronze)
                ForEach(
                    [ATHLTHTournamentFormat.league, .groups],
                    id: \.self
                ) { value in
                    Button { leagueStyle = value } label: {
                        HStack(spacing: 12) {
                            Image(systemName: value.symbol)
                                .foregroundStyle(bronze)
                                .frame(width: 33)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(value == .league ? "Stor liga" : "Gruppeliga")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ink)
                                Text(value.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(muted)
                            }
                            Spacer()
                            Image(systemName: leagueStyle == value
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(bronze)
                        }
                        .padding(13)
                        .background(
                            leagueStyle == value ?
                                ATHLTHPlanDesign.selectedSurface : Color.white,
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(
                        "athlth-league-type-\(value.rawValue)"
                    )
                }
            }
        }
        .padding(15)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
    }

    private var participantsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(tr("Participants", "Deltakere"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(chosenIDs.count)/\(format == .duel ? 1 : 20)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(bronze)
            }
            ForEach(selectedPeople, id: \.userID) { friend in
                HStack(spacing: 10) {
                    SocialAvatar(profile: friend, size: 36)
                    Text(friend.resolvedName).font(.subheadline.weight(.medium))
                    Spacer()
                    Button {
                        chosenIDs.remove(friend.userID)
                    } label: {
                        Image(systemName: "xmark.circle").foregroundStyle(bronze)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tr("Remove", "Fjern") + " " + friend.resolvedName)
                }
            }
            Button {
                showingParticipantChoices.toggle()
            } label: {
                Label(format == .duel && !chosenIDs.isEmpty
                      ? tr("Change opponent", "Bytt motstander") : tr("Add friends", "Legg til venner"),
                      systemImage: showingParticipantChoices ? "chevron.up" : "plus.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(bronze)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            }
            .buttonStyle(.plain)
            if showingParticipantChoices {
                ForEach(social.mutualFollows.filter {
                    $0.userID != session.profile.userID && !chosenIDs.contains($0.userID)
                }, id: \.userID) { friend in
                    Button {
                        if format == .duel {
                            chosenIDs = [friend.userID]
                            showingParticipantChoices = false
                        } else if chosenIDs.count < 20 {
                            chosenIDs.insert(friend.userID)
                        }
                    } label: {
                        HStack {
                            Text(friend.resolvedName).font(.subheadline)
                            Spacer()
                            Image(systemName: "plus.circle").foregroundStyle(bronze)
                        }
                        .padding(10)
                        .frame(minHeight: 44)
                        .background(ATHLTHPlanDesign.canvas, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
                if social.mutualFollows.isEmpty {
                    Text(tr("No mutual friends found yet.", "Ingen gjensidige venner funnet ennå."))
                        .font(.caption).foregroundStyle(muted)
                }
            }
            if chosenIDs.count < ATHLTHCompetitionCreationPolicy.minOpponents(format) {
                Text(tr("Minimum participants (including you): ", "Minst antall deltakere (inkludert deg): ") +
                     String(ATHLTHCompetitionCreationPolicy.minOpponents(format) + 1))
                    .font(.caption).foregroundStyle(muted)
            }
        }
    }

    /// Basic does not open the Advanced tournament wizard. Three choices:
    /// competition, friends and optional start. The real default exercise
    /// is chosen from the existing server catalogue in one publish request.
    private var simpleCompetitionRules: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleBlock(tr("The challenge", "Konkurransen"))
            let preset: String = {
                if format == .duel {
                    switch initialActivity {
                    case .running: return "Løp 5 km"
                    case .walking: return "Gå lengst"
                    case .strength: return "Størst treningsvolum"
                    }
                }
                switch initialActivity {
                case .running: return "Løp 5 km"
                case .walking: return "Gå 5 km"
                case .strength: return "Knebøy · flest repetisjoner"
                }
            }()
            HStack(spacing: 10) {
                Image(systemName: initialActivity.symbol)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(bronze)
                VStack(alignment: .leading, spacing: 4) {
                    Text(preset).font(.subheadline.weight(.semibold))
                    Text(tr("Ready to use · 7 days per round",
                            "Ferdig oppsett · 7 dager per runde"))
                        .font(.caption)
                        .foregroundStyle(muted)
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(bronze)
            }
            .padding(13)
            .background(ATHLTHPlanDesign.selectedSurface,
                        in: RoundedRectangle(cornerRadius: 15))
            Label("Svarfrist for invitasjoner: 3 dager",
                  systemImage: "clock")
                .font(.caption)
                .foregroundStyle(muted)
            Text(format == .duel
                ? tr("Your friend accepts in your existing chat. The duel lasts seven days.",
                     "Vennen godtar i samtalen dere allerede har. Duellen varer i syv dager.")
                : tr("Each friend receives the competition group chat. Everyone must accept and press Ready.",
                     "Alle får samme konkurransechat i Innboks. Alle må godta og trykke Klar."))
                .font(.caption)
                .foregroundStyle(muted)
        }
        .padding(15)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
    }

    private var competitionRules: some View {
        VStack(alignment: .leading, spacing: 13) {
            titleBlock(tr("Rules", "Regler"))
            if format == .duel && advanced {
                ATHLTHCompetitionRaceRulesSection(
                    settings: $duelRaceSettings,
                    activities: Set([
                        ATHLTHCompetitionCreationPolicy.tournamentActivity(
                            initialActivity
                        )
                    ])
                )
                if !duelEngineSupportsRule {
                    Label("Runder, lagsprint og verifisert Apple Watch-kilde krever videre integrasjon med treningsmotoren før duellen kan publiseres.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            if format == .duel {
                Text(tr("What determines the winner?", "Hva avgjør vinneren?"))
                    .font(.caption)
                    .foregroundStyle(muted)
                if runningBranch != .sprint &&
                   (!advanced || duelRaceSettings.race.discipline == .workout) {
                    Picker(tr("Result", "Resultat"), selection: $scoring) {
                        ForEach(duelMetrics, id: \.self) { metric in
                            Text(metric.title).tag(metric)
                        }
                    }
                    .pickerStyle(.menu)
                }
                if scoring == .fastestRoute {
                    Text(chosenRoute?.title ?? tr(
                        "Choose a route", "Velg en rute"
                    ))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(bronze)
                    if chosenRoute == nil {
                        Text(tr("A saved route is required.",
                                "Du må velge en lagret rute."))
                            .font(.caption)
                            .foregroundStyle(muted)
                    }
                }
                if scoring == .fastestDistance &&
                    (!advanced || duelRaceSettings.race.discipline == .workout) {
                    HStack {
                        Text(tr("Distance", "Distanse"))
                        Spacer()
                        TextField("5", value: $distanceKM,
                                  format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 72)
                        Text("km")
                    }
                    .font(.subheadline)
                } else if scoring == .farthestInTime &&
                    (!advanced || duelRaceSettings.race.discipline == .workout) {
                    Stepper(
                        tr("Time: \(Int(durationMinutes)) min",
                           "Tid: \(Int(durationMinutes)) min"),
                        value: $durationMinutes, in: 1...240, step: 5
                    )
                    .font(.subheadline)
                } else if initialActivity == .strength &&
                            scoring != .workoutVolume {
                    TextField(tr("Which exercise?", "Hvilken øvelse?"),
                              text: $exerciseName)
                        .padding(12)
                        .background(ATHLTHPlanDesign.selectedSurface,
                                    in: RoundedRectangle(cornerRadius: 12))
                }
            } else {
                HStack {
                    Label(format == .league
                        ? tr("Round-robin table", "Alle-mot-alle-tabell")
                        : tr("Knockout bracket", "Utslagsturnering"),
                        systemImage: format.symbol)
                    Spacer()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(bronze)
            }

            if format == .duel {
                Stepper("Svarfrist for invitasjonen: \(duelInvitationDays) dager",
                        value: $duelInvitationDays, in: 1...30)
                    .font(.subheadline)
                Text("Invitasjonen utløper automatisk hvis den ikke besvares.")
                    .font(.caption)
                    .foregroundStyle(muted)
            } else {
                Label(
                    tr("One round every \(roundsPerWeek) day(s) · \(reviewHours) hours to submit",
                       "Ny runde hver \(roundsPerWeek). dag · \(reviewHours) timer resultatfrist"),
                    systemImage: "calendar"
                )
                .font(.subheadline)
                .foregroundStyle(muted)
                Text(tr(
                    "The organizer and participants finalize match rules and the schedule in Arena before the tournament starts.",
                    "Arrangøren og deltakerne fullfører kampregler og tidsplan i Arena før turneringen starter."
                ))
                .font(.caption)
                .foregroundStyle(muted)
            }

            if advanced {
                if format == .duel && initialActivity != .strength {
                    HStack(spacing: 8) {
                        Text(tr("Race route", "Konkurranserute"))
                            .font(.subheadline)
                        Spacer()
                        Menu {
                            Button(tr("No route", "Ingen rute")) {
                                chosenRoute = nil
                                if scoring == .fastestRoute {
                                    scoring = .fastestDistance
                                }
                            }
                            ForEach(session.savedRoutes) { route in
                                Button(route.title) {
                                    chosenRoute = route
                                    scoring = .fastestRoute
                                }
                            }
                        } label: {
                            Label(chosenRoute?.title ?? tr(
                                "Choose route", "Velg rute"
                            ), systemImage: "map")
                            .font(.subheadline)
                            .lineLimit(1)
                        }
                    }
                }
                DisclosureGroup(
                    tr("Advanced rules", "Avanserte regler"),
                    isExpanded: $showingAdvancedRules
                ) {
                    VStack(alignment: .leading, spacing: 13) {
                        if format == .duel {
                            Toggle(
                                tr("Allow multiple attempts", "Tillat flere forsøk"),
                                isOn: $multipleAttempts
                            )
                            duelAgreementEditor
                        } else {
                            Stepper(
                                tr("New round every \(roundsPerWeek) days",
                                   "Ny runde hver \(roundsPerWeek). dag"),
                                value: $roundsPerWeek, in: 1...28
                            )
                            Picker(tr("Result deadline", "Resultatfrist"),
                                   selection: $reviewHours) {
                                ForEach(ATHLTHTournamentCadence.completionHours,
                                        id: \.self) { hours in
                                    Text(ATHLTHTournamentCadence.window(hours))
                                        .tag(hours)
                                }
                            }
                            if format == .league {
                                Stepper(
                                    tr("Win: \(winPoints) points",
                                       "Seier: \(winPoints) poeng"),
                                    value: $winPoints, in: 2...5
                                )
                                Stepper(
                                    tr("Draw: \(drawPoints) points",
                                       "Uavgjort: \(drawPoints) poeng"),
                                    value: $drawPoints, in: 0...2
                                )
                            }
                        }
                        Text(tr(
                            "Results require verification. Invitation acceptance is mandatory.",
                            "Resultater må godkjennes. Deltakerne må akseptere invitasjonen."
                        ))
                        .font(.caption)
                        .foregroundStyle(muted)
                    }
                    .padding(.top, 11)
                }
                .tint(bronze)
            }
        }
        .padding(15)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
    }

    private var duelAgreementEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hva er lov og ikke lov?")
                .font(.subheadline.weight(.semibold))
            TextField("Dette er lov", text: $duelAgreement.allowed,
                      axis: .vertical)
                .lineLimit(1...3)
            TextField("Dette er ikke lov", text: $duelAgreement.prohibited,
                      axis: .vertical)
                .lineLimit(1...3)
            Divider()
            TextField("Premie til vinner (valgfritt)",
                      text: $duelAgreement.firstPrize, axis: .vertical)
                .lineLimit(1...3)
            TextField("Frivillig konsekvens for taper (valgfritt)",
                      text: $duelAgreement.loserConsequence, axis: .vertical)
                .lineLimit(1...3)
            Text("Begge må godta reglene. Premier og konsekvenser må være trygge og frivillige.")
                .font(.caption)
                .foregroundStyle(muted)
        }
    }

    private var duelMetrics: [ATHLTHChallengeScoring] {
        switch initialActivity {
        case .running, .walking:
            [.fastestDistance, .mostDistance, .farthestInTime] +
                (chosenRoute == nil ? [] : [.fastestRoute])
        case .strength:
            [.workoutVolume, .mostReps, .heaviestWeight, .exerciseVolume]
        }
    }

    @MainActor
    private func publish() async {
        guard !sending, isValid else { return }
        sending = true
        errorMessage = nil
        defer { sending = false }

        do {
            switch format {
            case .duel:
                try await publishDuel()
            case .single, .league, .cup:
                try await publishTournament()
            }
            successful = true
            dismiss()
        } catch {
            // A remote failure must keep the form and its selections intact.
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func publishDuel() async throws {
        guard let rival = selectedPeople.first, selectedPeople.count == 1 else {
            throw ATHLTHCompetitionError.missingOpponents
        }
        // Prevent duplicate accidental invites, including rapid double taps.
        let now = Date()
        if challenges.visibleChallenges.contains(where: {
            $0.creatorID == session.profile.userID &&
            $0.status != .completed && $0.status != .cancelled &&
            $0.sport == ATHLTHCompetitionCreationPolicy.sport(initialActivity) &&
            $0.title.localizedCaseInsensitiveCompare(competitionTitle)
                == .orderedSame &&
            $0.participants.contains { $0.userID == rival.userID }
        }) {
            throw ATHLTHCompetitionError.duplicate
        }
        let duelMetric = effectiveDuelMetric
        let routeSnapshot: ChallengeRouteSnapshot? = duelMetric == .fastestRoute
            ? chosenDuelRoute.map {
                ChallengeRouteSnapshot(
                    routeID: $0.id, title: $0.title,
                    distanceKilometers: $0.distanceKilometers,
                    coordinates: $0.coordinates
                )
            } : nil
        var rules = ATHLTHChallengeRules(
            scoring: duelMetric,
            verificationPolicy: initialActivity == .strength
                ? .manualAllowed : .verifiedRequired,
            targetDistanceMeters: duelMetric == .fastestDistance
                ? effectiveDuelDistance * 1_000 : nil,
            targetDurationSeconds: duelMetric == .farthestInTime
                ? effectiveDuelMinutes * 60 : nil,
            timeBasis: .elapsed,
            route: routeSnapshot,
            gpsRequired: initialActivity != .strength,
            minimumRouteMatchPercent: routeSnapshot == nil ? nil : 90,
            exerciseName: initialActivity == .strength &&
                scoring != .workoutVolume ? exerciseName : nil,
            fixedWeightKilograms: nil,
            allowedActions: duelAgreement.allowed.isEmpty
                ? nil : duelAgreement.allowed,
            prohibitedActions: duelAgreement.prohibited.isEmpty
                ? nil : duelAgreement.prohibited,
            firstPrize: duelAgreement.firstPrize.isEmpty
                ? nil : duelAgreement.firstPrize,
            loserConsequence: duelAgreement.loserConsequence.isEmpty
                ? nil : duelAgreement.loserConsequence,
            startsAt: effectiveStart,
            endsAt: effectiveEnd,
            allowMultipleAttempts: multipleAttempts,
            lockRulesAtStart: true,
            meetup: nil
        )
        if advanced {
            rules.competitionRace = duelRaceSettings.race
        } else if initialActivity == .running && runningBranch == .sprint {
            var quickSprint = ATHLTHCompetitionRaceRules()
            quickSprint.discipline = .sprint
            quickSprint.sprintTarget =
                sprintGoal == .time ? .duration :
                sprintGoal == .route ? .route : .distance
            quickSprint.targetDistanceMeters = Int(distanceKM * 1_000)
            quickSprint.targetDurationSeconds = Int(durationMinutes * 60)
            quickSprint.routeID = chosenRoute?.id
            quickSprint.routeName = chosenRoute?.title ?? ""
            rules.competitionRace = quickSprint
        }
        let creator = ChallengeParticipant(
            userID: session.profile.userID,
            username: session.profile.username,
            displayName: session.profile.displayName,
            state: .creator
        )
        let opponent = ChallengeParticipant(
            userID: rival.userID,
            username: rival.username,
            displayName: rival.resolvedName,
            state: .invited
        )
        let challenge = ATHLTHChallenge(
            creatorID: session.profile.userID,
            title: String(competitionTitle.trimmingCharacters(
                in: .whitespacesAndNewlines).prefix(80)),
            sport: ATHLTHCompetitionCreationPolicy.sport(initialActivity),
            participants: [creator, opponent],
            rules: rules,
            visibility: .privateOnly
        )
        let synced = await social.syncChallenge(challenge)
        guard synced else {
            throw ATHLTHCompetitionError.server(
                social.errorMessage ?? tr(
                    "Could not send invitation", "Kunne ikke sende invitasjonen"
                )
            )
        }
        challenges.mergeRemoteChallenges([challenge])
        do {
            try await ATHLTHDuelReplyDeadlineCloud().update(
                challenge.id, days: advanced ? duelInvitationDays : 3
            )
        } catch {
            // The database default of three days still protects the invite.
            errorMessage = "Duellen er opprettet, men svarfristen kunne ikke tilpasses."
        }
        // A duel is a private inbox conversation, not a new group chat.
        // The challenge invitation itself already exists independently
        // if the message cannot be delivered.
        do {
            let conversationID = try await messaging.openConversation(
                with: rival.userID
            )
            let attachment = try MessageShareDraft(
                kind: .challenge,
                title: challenge.title,
                subtitle: "Duell · \(initialActivity.title)",
                snapshot: challenge,
                sourceObjectID: challenge.id,
                sourceOwnerID: session.profile.userID,
                requiresMutualFollow: true
            )
            _ = await messaging.send(
                to: rival.userID, conversationID: conversationID,
                body: "Invitasjon til duell: \(challenge.title)",
                attachment: attachment
            )
        } catch {
            // Do not retry creating the already-published duel just
            // because a private message failed. The inbox event remains.
            errorMessage = "Duellen er opprettet, men chatmeldingen kunne ikke sendes: " +
                error.localizedDescription
        }
    }

    @MainActor
    private func publishTournament() async throws {
        if !advanced {
            guard isValid else {
                throw ATHLTHCompetitionError.missingOpponents
            }
            if format == .single {
                _ = try await ATHLTHTournamentCloudService().createSimpleSingleEvent(
                    title: competitionTitle,
                    activity: ATHLTHCompetitionCreationPolicy.tournamentActivity(
                        initialActivity
                    ),
                    invitees: selectedPeople.map(\.userID),
                    startsAt: simpleStartLater ? startsAt : nil
                )
                return
            }
            _ = try await ATHLTHTournamentCloudService().createSimple(
                title: competitionTitle,
                format: format == .cup ? .cup : .league,
                activity: ATHLTHCompetitionCreationPolicy.tournamentActivity(
                    initialActivity
                ),
                invitees: selectedPeople.map(\.userID),
                startsAt: simpleStartLater ? startsAt : nil
            )
            return
        }
        let ownName = session.profile.username.isEmpty
            ? session.profile.displayName : session.profile.username
        let athletes = [
            ATHLTHTournamentParticipant(
                id: session.profile.userID, username: ownName
            )
        ] + selectedPeople.map {
            ATHLTHTournamentParticipant(
                id: $0.userID,
                username: $0.username ?? $0.resolvedName
            )
        }
        let draft = ATHLTHTournamentDraft(
            ownerID: session.profile.userID,
            clubID: nil,
            title: String(competitionTitle.trimmingCharacters(
                in: .whitespacesAndNewlines).prefix(80)),
            format: format == .league ? .league : .cup,
            groupSize: 4,
            qualifiersPerGroup: 2,
            participants: athletes,
            allowedActivities: [
                ATHLTHCompetitionCreationPolicy.tournamentActivity(
                    initialActivity
                )
            ],
            cadenceDays: roundsPerWeek,
            completionHours: reviewHours,
            winPoints: winPoints,
            drawPoints: drawPoints
        )
        try ATHLTHTournamentEngine.validate(
            draft.participants,
            groupSize: draft.groupSize,
            qualifiersPerGroup: draft.qualifiersPerGroup
        )
        _ = try await ATHLTHTournamentCloudService().create(from: draft)
    }
}

enum ATHLTHCompetitionError: LocalizedError {
    case missingOpponents, duplicate, server(String)

    var errorDescription: String? {
        switch self {
        case .missingOpponents: return ATHLTHLocalization.choose(
            english: "Choose a valid mutual friend.",
            norwegian: "Velg en gyldig gjensidig venn.")
        case .duplicate: return ATHLTHLocalization.choose(
            english: "An identical duel is already awaiting a response.",
            norwegian: "En tilsvarende duell venter allerede på svar.")
        case .server(let message): return message
        }
    }
}

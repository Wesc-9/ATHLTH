import SwiftUI

/// Single, safe creation entry for all three workout sports. Duel uses the
/// existing Challenge backend; League/Cup use the server-authoritative
/// tournament service. Nothing starts a HealthKit recording here.
enum ATHLTHCompetitionFormat: String, CaseIterable, Identifiable {
    case duel, league, cup
    var id: String { rawValue }

    var title: String {
        switch self {
        case .duel: "Duell"
        case .league: "Liga"
        case .cup: "Cup"
        }
    }
    var subtitle: String {
        switch self {
        case .duel: return ATHLTHLocalization.choose(
            english: "One opponent. One challenge.",
            norwegian: "Én motstander. Én utfordring.")
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
        case .league: "list.number"
        case .cup: "trophy.fill"
        }
    }
}

/// Pure entry policy. A tournament or duel cannot be published with
/// nonexistent rivals, duplicated participants or invalid measures.
enum ATHLTHCompetitionCreationPolicy {
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
        case .league: 2
        case .cup: 3
        }
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
              endsAt > now.addingTimeInterval(600),
              endsAt <= now.addingTimeInterval(90 * 86_400)
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
                    (1...1_440).contains(durationMinutes)
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

    let initialActivity: ATHLTHQuickStartActivity
    let advanced: Bool
    var initialFormat: ATHLTHCompetitionFormat? = nil
    var preselectedFriend: SocialProfileCard? = nil
    var preselectedRoute: TrainingRoute? = nil
    var preselectedDistanceKM: Double? = nil

    @State private var format: ATHLTHCompetitionFormat = .duel
    @State private var competitionTitle = ""
    @State private var chosenIDs: Set<UUID> = []
    @State private var scoring: ATHLTHChallengeScoring = .fastestDistance
    @State private var distanceKM = 5.0
    @State private var chosenRoute: TrainingRoute?
    @State private var durationMinutes = 30.0
    @State private var exerciseName = ""
    @State private var endsAt = Date().addingTimeInterval(7 * 86_400)
    @State private var multipleAttempts = true
    @State private var roundsPerWeek = 7
    @State private var reviewHours = 48
    @State private var winPoints = 3
    @State private var drawPoints = 1
    @State private var showingAdvancedRules = false
    @State private var sending = false
    @State private var errorMessage: String?
    @State private var successful = false

    private let ink = ATHLTHPlanDesign.ink
    private let bronze = ATHLTHPlanDesign.accentInk
    private let muted = ATHLTHPlanDesign.secondaryInk

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    private var selectedPeople: [SocialProfileCard] {
        social.mutualFollows.filter { chosenIDs.contains($0.userID) }
    }

    private var isValid: Bool {
        ATHLTHCompetitionCreationPolicy.canPublish(
            name: competitionTitle,
            ownerID: session.profile.userID,
            opponents: chosenIDs,
            format: format,
            metric: scoring,
            activity: initialActivity,
            distanceKM: distanceKM,
            durationMinutes: durationMinutes,
            exerciseName: exerciseName,
            hasRoute: chosenRoute != nil,
            endsAt: endsAt,
            now: Date()
        ) && selectedPeople.count == chosenIDs.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if advanced {
                        ATHLTHWorkoutDetailsCard(
                            activityTitle: initialActivity.title,
                            symbol: initialActivity.symbol
                        ) {
                            Label(
                                tr("Competition setup", "Konkurranseoppsett"),
                                systemImage: "trophy"
                            )
                            .font(.subheadline)
                            .foregroundStyle(bronze)
                        }
                    } else {
                        ATHLTHQuickStartSimpleDetailsCard(
                            activity: initialActivity,
                            summary: tr(
                                "Choose how to compete",
                                "Velg hvordan du vil konkurrere"
                            )
                        )
                    }

                    titleBlock(tr("Competition format", "Konkurranseform"))
                    VStack(spacing: 9) {
                        ForEach(ATHLTHCompetitionFormat.allCases) { option in
                            formatOption(option)
                        }
                    }

                    if advanced {
                        advancedIdentity
                    } else {
                        simpleIdentity
                    }

                    participantsCard
                    competitionRules

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
                .padding(16)
                .frame(maxWidth: 650)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(tr("Competition", "Konkurranse"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel", "Avbryt")) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider().opacity(0.32)
                    Button {
                        Task { await publish() }
                    } label: {
                        HStack(spacing: 9) {
                            if sending { ProgressView().tint(.white) }
                            Text(sending
                                ? tr("Creating…", "Oppretter…")
                                : tr("Create and invite", "Opprett og inviter"))
                                .font(.headline)
                            Image(systemName: "arrow.right")
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 53)
                        .background(bronze, in: RoundedRectangle(cornerRadius: 17))
                    }
                    .disabled(!isValid || sending || successful)
                    .opacity(isValid && !sending ? 1 : 0.48)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .accessibilityIdentifier("athlth-competition-publish")
                }
                .background(.regularMaterial)
            }
        }
        .presentationDetents([.large])
        .onAppear {
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
            }
            if let preselectedFriend, preselectedFriend.userID != session.profile.userID {
                chosenIDs.insert(preselectedFriend.userID)
            }
            if competitionTitle.isEmpty {
                competitionTitle = "\(format.title) · \(initialActivity.title)"
            }
        }
        .task {
            if social.mutualFollows.isEmpty {
                await social.refresh()
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
            format = option
            if competitionTitle.isEmpty ||
                competitionTitle.hasPrefix("Duell ·") ||
                competitionTitle.hasPrefix("Liga ·") ||
                competitionTitle.hasPrefix("Cup ·") {
                competitionTitle = "\(option.title) · \(initialActivity.title)"
            }
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

    private var simpleIdentity: some View {
        VStack(alignment: .leading, spacing: 9) {
            titleBlock(tr("Name", "Navn"))
            TextField(tr("Name the competition", "Gi konkurransen et navn"),
                      text: $competitionTitle)
                .font(.subheadline)
                .padding(15)
                .background(.white, in: RoundedRectangle(cornerRadius: 15))
                .accessibilityIdentifier("athlth-competition-name")
        }
    }

    /// The advanced identity card reuses the same workout-header principle
    /// as Advanced Quick Train, but its fields belong to the competition.
    private var advancedIdentity: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleBlock(tr("Competition details", "Konkurransedetaljer"))
            TextField(tr("Name", "Navn"), text: $competitionTitle)
                .textInputAutocapitalization(.sentences)
                .padding(14)
                .background(.white, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityIdentifier("athlth-competition-name")
            HStack {
                Label(initialActivity.title, systemImage: initialActivity.symbol)
                Spacer()
                Label(format.title, systemImage: format.symbol)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(bronze)
        }
        .padding(15)
        .background(ATHLTHPlanDesign.selectedSurface,
                    in: RoundedRectangle(cornerRadius: 20))
    }

    private var participantsCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                titleBlock(tr("Participants", "Deltakere"))
                Spacer()
                Text("\(chosenIDs.count)/\(format == .duel ? 1 : 20)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(bronze)
            }
            Text(format == .duel
                ? tr("Choose one mutual friend.", "Velg én venn dere følger gjensidig.")
                : tr("Invite mutual friends. Everyone must accept.",
                     "Inviter venner dere følger gjensidig. Alle må godta."))
                .font(.caption)
                .foregroundStyle(muted)
            if social.mutualFollows.isEmpty {
                Text(tr("No mutual friends found yet.",
                        "Ingen gjensidige venner funnet ennå."))
                    .font(.subheadline)
                    .foregroundStyle(muted)
            } else {
                ForEach(social.mutualFollows.filter {
                    $0.userID != session.profile.userID
                }, id: \.userID) { friend in
                    Button {
                        if chosenIDs.contains(friend.userID) {
                            chosenIDs.remove(friend.userID)
                        } else if format == .duel {
                            chosenIDs = [friend.userID]
                        } else if chosenIDs.count < 20 {
                            chosenIDs.insert(friend.userID)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "person.crop.circle")
                                .foregroundStyle(bronze)
                            Text(friend.resolvedName)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(ink)
                            Spacer()
                            Image(systemName: chosenIDs.contains(friend.userID)
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(bronze)
                        }
                        .padding(12)
                        .frame(minHeight: 46)
                        .background(chosenIDs.contains(friend.userID)
                            ? ATHLTHPlanDesign.selectedSurface : Color.white,
                            in: RoundedRectangle(cornerRadius: 13))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(tr(
                "Minimum: \(ATHLTHCompetitionCreationPolicy.minOpponents(format)) opponent(s).",
                "Minst \(ATHLTHCompetitionCreationPolicy.minOpponents(format)) motstander(e)."
            ))
            .font(.caption)
            .foregroundStyle(muted)
        }
        .padding(15)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
    }

    private var competitionRules: some View {
        VStack(alignment: .leading, spacing: 13) {
            titleBlock(tr("Rules", "Regler"))
            if format == .duel {
                Text(tr("What determines the winner?", "Hva avgjør vinneren?"))
                    .font(.caption)
                    .foregroundStyle(muted)
                Picker(tr("Result", "Resultat"), selection: $scoring) {
                    ForEach(duelMetrics, id: \.self) { metric in
                        Text(metric.title).tag(metric)
                    }
                }
                .pickerStyle(.menu)
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
                if scoring == .fastestDistance {
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
                } else if scoring == .farthestInTime {
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

            DatePicker(tr("Competition ends", "Konkurransen avsluttes"),
                       selection: $endsAt, in: Date().addingTimeInterval(600)...,
                       displayedComponents: [.date, .hourAndMinute])
                .font(.subheadline)

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
            case .league, .cup:
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
        let routeSnapshot: ChallengeRouteSnapshot? = scoring == .fastestRoute
            ? chosenRoute.map {
                ChallengeRouteSnapshot(
                    routeID: $0.id, title: $0.title,
                    distanceKilometers: $0.distanceKilometers,
                    coordinates: $0.coordinates
                )
            } : nil
        let rules = ATHLTHChallengeRules(
            scoring: scoring,
            verificationPolicy: initialActivity == .strength
                ? .manualAllowed : .verifiedRequired,
            targetDistanceMeters: scoring == .fastestDistance
                ? distanceKM * 1_000 : nil,
            targetDurationSeconds: scoring == .farthestInTime
                ? durationMinutes * 60 : nil,
            timeBasis: .elapsed,
            route: routeSnapshot,
            gpsRequired: initialActivity != .strength,
            minimumRouteMatchPercent: routeSnapshot == nil ? nil : 90,
            exerciseName: initialActivity == .strength &&
                scoring != .workoutVolume ? exerciseName : nil,
            fixedWeightKilograms: nil,
            startsAt: now,
            endsAt: endsAt,
            allowMultipleAttempts: multipleAttempts,
            lockRulesAtStart: true,
            meetup: nil
        )
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
    }

    @MainActor
    private func publishTournament() async throws {
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

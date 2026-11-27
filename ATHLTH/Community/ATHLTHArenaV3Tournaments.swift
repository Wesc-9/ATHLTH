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
    let isSingleEvent: Bool
    let isDuel: Bool
    let continuationParentID: UUID?
    let continuationSeasonNumber: Int?
    private var isRematch: Bool { isDuel && continuationParentID != nil }
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingExerciseLibrary = false
    @State private var exerciseTemplatesOnly: Bool? = nil
    @State private var showingDuelRoute = false
    @State private var expandedScoringExample = false
    @State private var rulesScrollID: String?
    @State private var draftID: UUID
    @State private var draftCreatedAt: Date
    @State private var rematchNames: [UUID: String] = [:]
    @State private var exerciseMetrics: [UUID: String] = [:]
    @State private var exerciseActivities: [UUID: ATHLTHTournamentActivity] = [:]
    private var usesExplicitExercises: Bool { isRematch || competitionSettings.selectedExerciseIDs != nil || competitionSettings.race.effectiveScoringMode.needsGoal }
    private var scoringValid: Bool {
        guard competitionSettings.race.discipline == .workout else { return true }
        guard proofMode == .opponent else { return false }
        let ids = competitionSettings.selectedExerciseIDs ?? []
        if ids.contains(where: { id in
            guard let activity = exerciseActivities[id] else { return true }
            return !activity.isAvailableForCreation || !allowedActivities.contains(activity)
        }) { return false }
        if usesExplicitExercises && (ids.isEmpty || exerciseMode != .owner || ids.count != exerciseCount) { return false }
        if competitionSettings.race.effectiveScoringMode.needsGoal {
            return ids.allSatisfy { competitionSettings.race.goal(for: $0).map { $0.isFinite && $0 > 0 } == true }
        }
        return true
    }
    @State private var rematchSearchError: String?
    /// Sports chosen from Quick Train cannot silently change to another mode.
    let fixedActivity: ATHLTHTournamentActivity?
    /// Entry flows choose a single competition format. The detailed rules
    /// screen must not silently switch a group league into a cup.
    let restrictFormat: Bool
    let fixedInvitees: [ATHLTHTournamentParticipant]?
    let fixedStartMode: ATHLTHCompetitionStartMode?
    let fixedStartDate: Date?
    let onBack: ((ATHLTHTournamentDraft) -> Void)?
    let automaticDuelName: Bool
    let onCheckpoint: ((ATHLTHTournamentDraft, String?) -> Void)?
    let onSave: (ATHLTHTournamentDraft) -> Void
    let onPublished: ((UUID) -> Void)?
    private let tournamentCloud = ATHLTHTournamentCloudService()

    @State private var publishing = false
    @State private var format: ATHLTHTournamentFormat
    @State private var title = ""
    @State private var groupSize = 4
    @State private var qualifiersPerGroup = 2
    @State private var allowedActivities: Set<ATHLTHTournamentActivity> = []
    @State private var rulesAuthority: ATHLTHTournamentRulesAuthority = .owner
    @State private var cadenceDays = 7
    @State private var completionHours = 48
    @State private var rotationMode: ATHLTHTournamentRotationMode = .all
    @State private var restWeekdays: Set<Int> = []
    @State private var winPoints = 3
    @State private var drawPoints = 1
    @State private var competitionSettings = ATHLTHTournamentCompetitionSettings()
    @State private var showingCompetitionCoach = false
    @State private var coachNames: [String] = []
    @State private var showingTemplatePicker = false
    @State private var showingSaveTemplate = false
    @State private var templateName = ""
    @State private var templateSaving = false
    @State private var allowExtensions = true
    @State private var publicResults = false
    @State private var proofMode: ATHLTHTournamentProofMode = .opponent
    @State private var exerciseMode: ATHLTHTournamentExerciseMode = .owner
    @State private var exerciseCount = 4
    @State private var proposalsCloseAt =
        Date().addingTimeInterval(2 * 86_400)
    @State private var votesCloseAt =
        Date().addingTimeInterval(3 * 86_400)
    @State private var approvePlayerChanges = false
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
        fixedActivity: ATHLTHTournamentActivity? = nil,
        singleEventMode: Bool = false,
        duelMode: Bool = false,
        initialTitle: String? = nil,
        continuation: ATHLTHTournamentDraft? = nil,
        fixedInvitees: [ATHLTHTournamentParticipant]? = nil,
        fixedStartMode: ATHLTHCompetitionStartMode? = nil,
        fixedStartDate: Date? = nil,
        initialActivity: ATHLTHTournamentActivity? = nil,
        onBack: ((ATHLTHTournamentDraft) -> Void)? = nil,
        automaticDuelName: Bool = false,
        restoredScrollID: String? = nil,
        onCheckpoint: ((ATHLTHTournamentDraft, String?) -> Void)? = nil,
        onPublished: ((UUID) -> Void)? = nil,
        onSave: @escaping (ATHLTHTournamentDraft) -> Void
    ) {
        self.preset = preset
        self.fixedClubID = fixedClubID
        self.isDuel = continuation?.competitionSettings.race.duelMode == true || duelMode
        self.continuationParentID = continuation?.competitionSettings.race.previousCompetitionID
        self.continuationSeasonNumber = continuation?.competitionSettings.race.seasonNumber
        self.isSingleEvent = continuation?.singleEventMode ?? (singleEventMode || duelMode)
        self.fixedActivity = fixedActivity
        self.restrictFormat = fixedActivity != nil || continuation != nil || fixedInvitees != nil
        self.fixedInvitees = fixedInvitees
        self.fixedStartMode = fixedStartMode
        self.fixedStartDate = fixedStartDate
        self.onBack = onBack
        self.automaticDuelName = automaticDuelName
        self.onCheckpoint = onCheckpoint
        _rulesScrollID = State(initialValue: restoredScrollID)
        _draftID = State(initialValue: continuation?.id ?? UUID())
        _draftCreatedAt = State(initialValue: continuation?.createdAt ?? Date())
        self.onSave = onSave
        self.onPublished = onPublished
        _format = State(initialValue:
            (continuation?.singleEventMode ?? (singleEventMode || duelMode))
                ? .league : (continuation?.format ?? preset))
        _title = State(initialValue: initialTitle ?? continuation?.title ?? "")
        _groupSize = State(initialValue: continuation?.groupSize ?? 4)
        _qualifiersPerGroup = State(initialValue:
            continuation?.qualifiersPerGroup ?? 2)
        _allowedActivities = State(initialValue:
            Set(continuation?.allowedActivities ??
                fixedActivity.map { [$0] } ?? initialActivity.map { [$0] } ?? []))
        _rulesAuthority = State(initialValue:
            continuation?.rulesAuthority ?? .owner)
        _cadenceDays = State(initialValue:
            continuation?.cadenceDays ?? 7)
        _completionHours = State(initialValue:
            continuation?.completionHours ?? 48)
        _rotationMode = State(initialValue:
            continuation?.rotationMode ?? .all)
        _restWeekdays = State(initialValue:
            Set(continuation?.restWeekdays ?? []))
        _winPoints = State(initialValue:
            continuation?.winPoints ?? 3)
        _drawPoints = State(initialValue:
            continuation?.drawPoints ?? 1)
        var initialSettings = continuation?.competitionSettings ?? .init()
        if duelMode || continuation?.competitionSettings.race.duelMode == true {
            initialSettings.race.duelMode = true
            if continuation == nil { initialSettings.selectedExerciseIDs = [] }
            initialSettings.race.discipline = .workout
            initialSettings.unansweredPolicy = .cancel
            initialSettings.invitationPermission = .admin
            initialSettings.joinApproval = .admin
        }
        if let fixedStartMode {
            initialSettings.startMode = fixedStartMode
            initialSettings.startsAt = fixedStartDate
        }
        _competitionSettings = State(initialValue: initialSettings)
        _allowExtensions = State(initialValue:
            continuation?.allowExtensions ?? true)
        _publicResults = State(initialValue:
            continuation?.publicResults ?? false)
        _proofMode = State(initialValue:
            continuation?.proofMode ?? .opponent)
        _exerciseMode = State(initialValue:
            continuation?.exerciseMode ?? .owner)
        _exerciseCount = State(initialValue:
            initialSettings.selectedExerciseIDs?.count ?? continuation?.exerciseCount ?? (duelMode ? 0 : 4))
        _approvePlayerChanges = State(initialValue:
            continuation?.approvePlayerChanges ?? false)
        _warmupRounds = State(initialValue:
            continuation?.warmupRounds ?? [])
        _selectedSeasonID = State(initialValue: continuation?.seasonID)
        _proposalsCloseAt = State(initialValue:
            continuation?.proposalsCloseAt ??
                Date().addingTimeInterval(2 * 86_400))
        _votesCloseAt = State(initialValue:
            continuation?.votesCloseAt ??
                Date().addingTimeInterval(3 * 86_400))
        _chosenIDs = State(initialValue: Set(
            fixedInvitees?.map(\.id) ?? continuation?.participants.map(\.id).filter {
                $0 != continuation?.ownerID
            } ?? []
        ))
        var previousNames: [UUID: String] = [:]
        for athlete in fixedInvitees ?? continuation?.participants ?? [] {
            previousNames[athlete.id] = athlete.username
        }
        _chosenNames = State(initialValue: previousNames)
        _selectedClubID = State(initialValue:
            fixedInvitees == nil ? fixedClubID ?? continuation?.clubID : nil)
        _inviteSource = State(initialValue:
            fixedInvitees != nil || (fixedClubID ?? continuation?.clubID) == nil ? .friends : .club)
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

    private var effectiveTitle: String {
        if automaticDuelName && isDuel {
            return ATHLTHCompetitionCreationPolicy.duelName(owner: athletes.first?.username ?? "Du", opponent: athletes.dropFirst().first?.username, branches: ATHLTHTournamentActivity.allCases.filter { allowedActivities.contains($0) }.map(\.title))
        }
        return String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
    }

    private var publishHint: String {
        if allowedActivities.isEmpty { return "Velg minst én gren." }
        if !ATHLTHTournamentActivity.canCreate(with: allowedActivities) { return "Fjern grener som ikke er tilgjengelige ennå." }
        if isDuel && athletes.count != 2 { return "Velg én motstander." }
        if usesExplicitExercises && (competitionSettings.selectedExerciseIDs ?? []).isEmpty { return "Legg til minst én konkurranseøvelse." }
        if !scoringValid { return "Kontroller øvelser, mål og resultatgodkjenning." }
        if !competitionSettings.environmentsCanPublish(activities: allowedActivities) {
            return "Valgte miljøkrav støttes ikke ved publisering ennå."
        }
        return "Kontroller regler og obligatoriske felt før invitasjon."
    }

    private var canSaveTemplate: Bool {
        effectiveTitle.count >= 3 &&
        ATHLTHTournamentActivity.canCreate(with: allowedActivities) && competitionSettings.isValid &&
        competitionSettings.environmentsValid(activities: allowedActivities, exerciseActivities: exerciseActivities) &&
        !templateSaving && !publishing
    }

    private var canSave: Bool {
        effectiveTitle.count >= 3 &&
        // The shared event engine has distinct roster limits for duel and single event.
        (isDuel ? athletes.count == 2 : athletes.count >= (isSingleEvent ? 3 : format == .cup ? 4 : 2)) &&
        !busy && ATHLTHTournamentActivity.canCreate(with: allowedActivities) &&
        (!isDuel || competitionSettings.race.discipline == .workout) &&
        (!isSingleEvent || competitionSettings.race.discipline == .workout ||
            (allowedActivities.count == 1 && exerciseCount == 1 && exerciseMode != .open)) &&
        competitionSettings.isValid &&
        competitionSettings.race.isOperational && competitionSettings.environmentsCanPublish(activities: allowedActivities) &&
        competitionSettings.environmentsValid(activities: allowedActivities, exerciseActivities: exerciseActivities) && scoringValid &&
        (!isRematch || (exerciseMode == .owner && competitionSettings.selectedExerciseIDs?.count == exerciseCount && exerciseCount > 0)) &&
        (!(isSingleEvent && competitionSettings.race.discipline == .workout && proofMode == .verified)) &&
        (competitionSettings.coachExerciseIDs.isEmpty ||
          (exerciseMode == .owner &&
           competitionSettings.coachExerciseIDs.count == exerciseCount)) &&
        (fixedActivity.map { allowedActivities == Set([$0]) } ?? true) &&
        ATHLTHTournamentCadence.options.contains(cadenceDays) &&
        ATHLTHTournamentCadence.completionHours.contains(
            competitionSettings.completionHours
        ) &&
        (inviteSource != .club || selectedClubID != nil) &&
        (exerciseMode != .vote || (
            proposalsCloseAt > Date().addingTimeInterval(120) &&
            votesCloseAt > proposalsCloseAt &&
            votesCloseAt < Date().addingTimeInterval(30 * 86_400)
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if fixedInvitees == nil {
                        titleSection.id("title")
                        formatSection.id("format")
                    }
                    ATHLTHTournamentRuleConfigurationSection(
                        activities: Binding(
                            get: {
                                fixedActivity.map { Set([$0]) } ?? allowedActivities
                            },
                            set: { newValue in
                                if fixedActivity == nil {
                                    if usesExplicitExercises && newValue != allowedActivities {
                                        let removed = Set((competitionSettings.selectedExerciseIDs ?? []).filter {
                                            guard let activity = exerciseActivities[$0] else { return false }
                                            return !newValue.contains(activity)
                                        })
                                        competitionSettings.selectedExerciseIDs?.removeAll { removed.contains($0) }
                                        for id in removed {
                                            competitionSettings.exerciseEnvironments.removeValue(forKey: id)
                                            competitionSettings.race.scoringGoals?.removeValue(forKey: ATHLTHCompetitionRaceRules.key(id))
                                            competitionSettings.race.exerciseWeights?.removeValue(forKey: ATHLTHCompetitionRaceRules.key(id))
                                        }
                                        exerciseCount = competitionSettings.selectedExerciseIDs?.count ?? 0
                                    }
                                    competitionSettings.activityEnvironments = competitionSettings.activityEnvironments.filter { key, _ in
                                         newValue.contains { $0.rawValue == key }
                                     }
                                     allowedActivities = newValue
                                }
                            }
                        ),
                        authority: $rulesAuthority,
                        cadenceDays: $cadenceDays,
                        completionHours: $competitionSettings.completionHours,
                        showsLegacyRoundTiming: false
                    ).id("activities")
                    if isSingleEvent {
                        Label(competitionSettings.race.discipline == .workout
                              ? "Hver øvelse får en egen resultatmåling. Plasseringen i hver øvelse gir poeng til sammenlagtlisten."
                              : "Sprint, distanse, tid og runder krever én gren og én øvelse. Velg Treningsøkt for å kombinere flere øvelser og grener.",
                              systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(ATHLTHArenaV3Style.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let fixedActivity {
                        Label(
                            "Konkurransen gjelder bare \(fixedActivity.title)",
                            systemImage: fixedActivity.symbol
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHArenaV3Style.gold)
                    }
                    if isSingleEvent && competitionSettings.race.discipline == .workout && proofMode == .verified {
                        Label("Automatisk kildeverifisering dekker ikke alle øvelser ennå. Velg godkjenning av deltaker eller arrangør for å publisere.", systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if !competitionSettings.race.isOperational {
                        Label("Dette oppsettet kan lagres som mal, men publisering krever videre støtte i den universelle treningsmotoren for valgt utstyr, rute, lagstart eller GPS-runder.",
                              systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(13)
                            .background(ATHLTHArenaV3Style.panel())
                    }
                    if competitionSettings.race.discipline == .workout {
                        rematchExerciseSection.id("exercises")
                    }
                    if competitionSettings.race.discipline == .workout { scoringSettingsSection.id("scoring") }
                    if !(competitionSettings.race.discipline == .workout && usesExplicitExercises) {
                        coachEntry.id("coach")
                        templateEntry.id("template")
                        exerciseRulesSection.id("exercise-rules")
                    }
                    ATHLTHTournamentAdvancedRulesSection(
                        rotation: $rotationMode,
                        restDays: $restWeekdays,
                        winPoints: $winPoints,
                        drawPoints: $drawPoints,
                        allowExtensions: $allowExtensions,
                        publicResults: isDuel ? .constant(false) : $publicResults,
                        proof: $proofMode,
                        sharedEvent: isSingleEvent,
                        duel: isDuel
                    ).id("advanced")
                    ATHLTHCompetitionRaceRulesSection(
                        settings: $competitionSettings,
                        activities: fixedActivity.map { Set([$0]) } ?? allowedActivities,
                        workoutOnly: isDuel
                    ).id("capture")
                    ATHLTHTournamentCompetitionRulesSection(
                        settings: $competitionSettings,
                        activities: fixedActivity.map { Set([$0]) } ?? allowedActivities,
                        showsStartTiming: fixedStartMode == nil,
                        isDuel: isDuel,
                        isSharedEvent: isSingleEvent,
                        usesIndividualExerciseDeadlines: isSingleEvent && competitionSettings.race.discipline == .workout
                    ).id("timing")
                    if !isSingleEvent { warmupSection }
                    if format == .groups { groupsSection.id("groups") }
                    if fixedInvitees == nil {
                        inviteSection.id("participants")
                        if activeClubID != nil { seasonSection.id("season") }
                    }
                    preview.id("review")
                    Text("Invitasjoner og regler godkjennes før start. Konkurransen starter manuelt, automatisk når alle er klare eller på valgt tidspunkt, slik du har valgt.")
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let errorMessage {
                        Text(errorMessage).font(.caption).foregroundStyle(.red)
                    }
                }
                .scrollTargetLayout()
                .padding(18)
                .frame(maxWidth: 650)
                .frame(maxWidth: .infinity)
            }
            .scrollPosition(id: $rulesScrollID, anchor: .top)
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            .background(ATHLTHArenaV3Style.cream.ignoresSafeArea())
            .navigationTitle(fixedInvitees == nil ? "Ny konkurranse" : "Regler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(fixedInvitees == nil ? "Avbryt" : "Tilbake") {
                        onCheckpoint?(makeDraft(forCheckpoint: true), rulesScrollID)
                        onBack?(makeDraft(forCheckpoint: true))
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if !canSave && !publishing {
                        Text(publishHint).font(.caption)
                            .foregroundStyle(ATHLTHArenaV3Style.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Button {
                        Task { await publishTournament() }
                    } label: {
                        HStack(spacing: 8) {
                            if publishing { ProgressView().tint(.white) }
                            Text(publishing ? "Publiserer…" : "Publiser og inviter")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(ATHLTHArenaV3Style.ink, in: Capsule())
                    }
                    .disabled(!canSave || publishing)
                    .opacity(canSave ? 1 : 0.5)

                    HStack(spacing: 12) {
                        Button {
                            onSave(makeDraft())
                            dismiss()
                        } label: {
                            Text("Lagre som utkast")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ATHLTHArenaV3Style.ink)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .disabled(publishing)
                        Button {
                            templateName = effectiveTitle
                            showingSaveTemplate = true
                        } label: {
                            Label("Lagre som mal", systemImage: "square.stack.3d.up")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(ATHLTHArenaV3Style.gold)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .disabled(!canSaveTemplate)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(ATHLTHArenaV3Style.cream)
            }
        }
        .sheet(isPresented: $showingExerciseLibrary.keepingPresentedWhenInactive(scenePhase)) {
            ATHLTHCompetitionExercisePicker(allowed: allowedActivities,
                selected: Set(competitionSettings.selectedExerciseIDs ?? []), templatesOnly: exerciseTemplatesOnly) { item in
                var ids = competitionSettings.selectedExerciseIDs ?? []
                guard ids.count < 12, !ids.contains(item.id), item.activity.isAvailableForCreation, allowedActivities.contains(item.activity) else { return }
                exerciseMode = .owner
                competitionSettings.coachExerciseIDs = []
                ids.append(item.id)
                rematchNames[item.id] = item.name
                exerciseMetrics[item.id] = item.metric
                exerciseActivities[item.id] = item.activity
                competitionSettings.selectedExerciseIDs = ids
                exerciseCount = ids.count
            }
        }
        .fullScreenCover(isPresented: $showingDuelRoute.keepingPresentedWhenInactive(scenePhase)) {
            NavigationStack {
                SavedRoutesView(selectionTitle: "Konkurranserute") { route in
                    competitionSettings.race.routeID = route.id
                    competitionSettings.race.routeName = String(route.title.prefix(120))
                    showingDuelRoute = false
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Lukk") { showingDuelRoute = false }
                    }
                }
            }
        }
        .task(id: competitionSettings.selectedExerciseIDs ?? []) {
            let missing = (competitionSettings.selectedExerciseIDs ?? []).filter {
                rematchNames[$0] == nil || exerciseActivities[$0] == nil || exerciseMetrics[$0] == nil
            }
            guard !missing.isEmpty else { return }
            do {
                let service = ATHLTHTournamentLobbyCloudService()
                async let labels = service.exerciseLabels(ids: missing)
                async let metrics = service.exerciseMetrics(ids: missing)
                async let activities = service.exerciseActivities(ids: missing)
                let (names, measures, kinds) = try await (labels, metrics, activities)
                guard !Task.isCancelled else { return }
                for (id, name) in names { rematchNames[id] = name }
                for (id, metric) in measures { exerciseMetrics[id] = metric }
                for (id, activity) in kinds {
                    exerciseActivities[id] = activity
                    if exerciseMetrics[id] == nil { exerciseMetrics[id] = "repetitions" }
                }
                rematchSearchError = nil
            } catch {
                if !Task.isCancelled { rematchSearchError = "Kunne ikke hente øvelsesdetaljer. Prøv igjen når du er tilkoblet." }
            }
        }
        .onChange(of: competitionSettings) { _, _ in checkpoint() }
        .onChange(of: allowedActivities) { _, _ in checkpoint() }
        .onChange(of: rulesAuthority) { _, _ in checkpoint() }
        .onChange(of: proofMode) { _, _ in checkpoint() }
        .onChange(of: exerciseCount) { _, _ in checkpoint() }
        .onChange(of: exerciseMode) { _, _ in checkpoint() }
        .onChange(of: additionalCheckpointFields) { _, _ in checkpoint() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { checkpoint() } }
        .onAppear { checkpoint() }
        .environment(\.colorScheme, .light)
        .interactiveDismissDisabled(fixedInvitees != nil)
        .task {
            guard fixedInvitees == nil else { return }
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
        .fullScreenCover(isPresented: $showingTemplatePicker) {
            ATHLTHTournamentTemplatePicker { saved in
                applyTemplate(saved)
            }
        }
        .alert("Lagre konkurransemal", isPresented: $showingSaveTemplate) {
            TextField("Navn på mal", text: $templateName)
            Button("Avbryt", role: .cancel) {}
            Button("Lagre") {
                Task { await storeTemplate() }
            }
        } message: {
            Text("Malen lagrer regler og øvelser, men ingen venner, invitasjoner eller gamle startdatoer.")
        }
        .fullScreenCover(isPresented: $showingCompetitionCoach) {
            ATHLTHTournamentCoachWizard(
                format: format,
                activities: fixedActivity.map { [$0] } ??
                    allowedActivities.sorted { $0.rawValue < $1.rawValue }
            ) { proposal in
                let suggested = proposal.exerciseIDs
                guard !suggested.isEmpty else { return }
                if fixedInvitees == nil { title = String(proposal.title.prefix(80)) }
                exerciseMode = .owner
                rulesAuthority = .owner
                exerciseCount = suggested.count
                competitionSettings.coachExerciseIDs = suggested
                if fixedStartMode == nil {
                    competitionSettings.startMode =
                        ATHLTHCompetitionStartMode(rawValue: proposal.startMode) ?? .manual
                    competitionSettings.startsAt = nil
                }
                competitionSettings.environment =
                    ATHLTHCompetitionEnvironment(rawValue: proposal.environment)
                    ?? .any
                competitionSettings.unit = .day
                competitionSettings.every = min(28, max(1, proposal.releaseEvery))
                if ATHLTHTournamentCadence.completionHours
                    .contains(proposal.completionHours) {
                    competitionSettings.completionHours = proposal.completionHours
                }
                competitionSettings.agreement.allowed =
                    proposal.allowedRules
                competitionSettings.agreement.prohibited =
                    proposal.prohibitedRules
                coachNames = proposal.exerciseNames
            }
        }
        .fullScreenCover(isPresented: $showingSeasonCreation) {
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

    // A cheap value snapshot of the small editable fields not covered by
    // competitionSettings. Scroll movement is saved on lifecycle transitions,
    // not on every frame.
    private var additionalCheckpointFields: [String] {
        var fields = [title, format.rawValue, String(groupSize), String(qualifiersPerGroup),
                      String(cadenceDays), rotationMode.rawValue]
        fields.append(restWeekdays.sorted().map { String($0) }.joined(separator: ","))
        fields.append(contentsOf: [String(winPoints), String(drawPoints), String(allowExtensions),
                                   String(publicResults), String(approvePlayerChanges)])
        fields.append(String(proposalsCloseAt.timeIntervalSinceReferenceDate))
        fields.append(String(votesCloseAt.timeIntervalSinceReferenceDate))
        fields.append(selectedSeasonID?.uuidString ?? "")
        fields.append(selectedClubID?.uuidString ?? "")
        fields.append(inviteSource.rawValue)
        fields.append(chosenIDs.map(\.uuidString).sorted().joined(separator: ","))
        fields.append(warmupRounds.map { $0.id.uuidString + ":" + $0.title }.joined(separator: "|"))
        return fields
    }

    private func checkpoint() {
        guard !publishing, let onCheckpoint else { return }
        onCheckpoint(makeDraft(forCheckpoint: true), rulesScrollID)
    }

    private func makeDraft(forCheckpoint: Bool = false) -> ATHLTHTournamentDraft {
        var configured = competitionSettings
        if configured.race.discipline == .workout {
            configured.race.scoringMode = configured.race.effectiveScoringMode
            configured.race.pointsPerExercise = configured.race.pointsPerExercise ?? 1
            configured.race.reviewHours = configured.race.reviewHours ?? 48
            let keys = Set((configured.selectedExerciseIDs ?? []).map(ATHLTHCompetitionRaceRules.key))
            let roster = Set(athletes.map { ATHLTHCompetitionRaceRules.key($0.id) })
            configured.race.scoringGoals = configured.race.effectiveScoringMode.needsGoal
                ? configured.race.scoringGoals?.filter { keys.contains($0.key) } : nil
            configured.race.exerciseWeights = configured.race.exerciseWeights?.filter { keys.contains($0.key) }
            configured.race.handicapPercentages = configured.race.handicapPercentages?.filter { roster.contains($0.key) && $0.value > 0 }
        } else {
            configured.race.scoringMode = nil
            configured.race.pointsPerExercise = nil
            configured.race.reviewHours = nil
            configured.race.scoringGoals = nil
            configured.race.exerciseWeights = nil
            configured.race.handicapPercentages = nil
        }
        configured.race.exerciseScoringVersion = isSingleEvent && configured.race.discipline == .workout ? 2 : nil
        configured.race.competitionEndsAt = configured.endsAt.map { ISO8601DateFormatter().string(from: $0) }
        configured.race.duelMode = isDuel ? true : nil
        configured.race.previousCompetitionID = continuationParentID
        configured.race.seasonNumber = isSingleEvent ? nil : (continuationSeasonNumber ?? 1)
        if isDuel {
            configured.unansweredPolicy = .cancel
            configured.invitationPermission = .admin
            configured.joinApproval = .admin
        }
        var draft = ATHLTHTournamentDraft(
            id: draftID,
            ownerID: session.profile.userID,
            clubID: activeClubID,
            seasonID: activeClubID == nil ? nil : selectedSeasonID,
            title: forCheckpoint ? title : effectiveTitle,
            format: format,
            singleEventMode: isSingleEvent,
            groupSize: groupSize,
            qualifiersPerGroup: qualifiersPerGroup,
            participants: athletes,
            warmupRounds: forCheckpoint ? warmupRounds : warmupRounds.enumerated().map { index, round in
                var copy = round
                let clean = round.title.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                copy.title = String(
                    (clean.isEmpty ? "Oppvarmingsrunde \(index + 1)" : clean)
                        .prefix(60)
                )
                return copy
            },
            exerciseMode: exerciseMode,
            exerciseCount: exerciseCount,
            proposalsCloseAt: exerciseMode == .vote ? proposalsCloseAt : nil,
            votesCloseAt: exerciseMode == .vote ? votesCloseAt : nil,
            approvePlayerChanges: approvePlayerChanges,
            allowedActivities: (fixedActivity.map { [$0] } ??
                allowedActivities.sorted { $0.rawValue < $1.rawValue }),
            rulesAuthority: rulesAuthority,
            // Legacy cadence still controls tournament match rounds.
            // The new per-exercise release is governed separately by
            // competitionSettings, and both UIs share one deadline value.
            cadenceDays: cadenceDays,
            completionHours: competitionSettings.completionHours,
            rotationMode: isSingleEvent ? .all : rotationMode,
            restWeekdays: isSingleEvent ? [] : Array(restWeekdays).sorted(),
            proofMode: proofMode,
            publicResults: isSingleEvent ? false : publicResults,
            allowExtensions: isSingleEvent ? false : allowExtensions,
            winPoints: winPoints,
            drawPoints: drawPoints,
            competitionSettings: forCheckpoint ? competitionSettings : configured,
            createdAt: draftCreatedAt
        )
        if forCheckpoint { draft.exerciseCount = exerciseCount }
        return draft
    }

    @MainActor
    private func publishTournament() async {
        guard canSave, !publishing else { return }
        publishing = true
        defer { publishing = false }
        do {
            let publishedID = try await tournamentCloud.create(from: makeDraft())
            onPublished?(publishedID)
            dismiss()
        } catch {
            errorMessage = "Kunne ikke publisere: " + error.localizedDescription
        }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("KONKURRANSE")
                .font(.caption2.weight(.semibold))
                .tracking(2)
                .foregroundStyle(ATHLTHArenaV3Style.gold)
            TextField(isSingleEvent ? "Navn på enkeltkonkurranse" :
                      "Navn på liga eller cup", text: $title)
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
            if isSingleEvent {
                Label(isDuel ? "Duell · nøyaktig to deltakere" : "Enkeltkonkurranse · én hendelse for minst tre",
                      systemImage: "person.3.sequence.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHArenaV3Style.gold)
            }
            ForEach(isSingleEvent ? [] :
                    (restrictFormat ? [format] : ATHLTHTournamentFormat.allCases)) {
                option in
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

    private var templateEntry: some View {
        Button {
            showingTemplatePicker = true
        } label: {
            HStack(spacing: 11) {
                Image(systemName: "square.stack.3d.up")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Hent konkurransemal")
                        .font(.subheadline.weight(.semibold))
                    Text("Bruk et oppsett du har lagret tidligere")
                        .font(.caption)
                }
                Spacer()
                Image(systemName: "chevron.right")
            }
            .foregroundStyle(ATHLTHArenaV3Style.gold)
            .padding(15)
            .background(ATHLTHArenaV3Style.panel())
        }
        .buttonStyle(.plain)
    }

    @MainActor private func storeTemplate() async {
        guard canSaveTemplate else { return }
        templateSaving = true
        defer { templateSaving = false }
        do {
            try await ATHLTHTournamentTemplateCloudService().save(
                makeDraft(), name: templateName, userID: session.profile.userID
            )
            errorMessage = nil
        } catch {
            errorMessage = "Kunne ikke lagre malen: " + error.localizedDescription
        }
    }

    private func applyTemplate(_ saved: ATHLTHTournamentDraft) {
        if restrictFormat && (saved.format != format ||
                              saved.singleEventMode != isSingleEvent ||
                              (saved.competitionSettings.race.duelMode == true) != isDuel) {
            errorMessage = "Denne malen har en annen konkurranseform."
            return
        }
        guard ATHLTHTournamentActivity.canCreate(with: Set(saved.allowedActivities)) else {
            errorMessage = "Malen inneholder grener som ikke er tilgjengelige ennå."
            return
        }
        if let fixedActivity,
           !saved.allowedActivities.contains(fixedActivity) {
            errorMessage = "Denne malen er ikke laget for \(fixedActivity.title)."
            return
        }
        format = saved.format
        if fixedInvitees == nil { title = saved.title }
        groupSize = saved.groupSize
        qualifiersPerGroup = saved.qualifiersPerGroup
        allowedActivities = fixedActivity.map { Set([$0]) } ??
            Set(saved.allowedActivities)
        rulesAuthority = saved.rulesAuthority
        cadenceDays = saved.cadenceDays
        rotationMode = saved.rotationMode
        restWeekdays = Set(saved.restWeekdays)
        winPoints = saved.winPoints
        drawPoints = saved.drawPoints
        competitionSettings = saved.competitionSettings
        competitionSettings.race.previousCompetitionID = continuationParentID
        competitionSettings.race.seasonNumber = continuationSeasonNumber
        allowExtensions = saved.allowExtensions
        publicResults = saved.publicResults
        proofMode = saved.proofMode
        exerciseMode = saved.exerciseMode
        exerciseCount = saved.exerciseCount
        proposalsCloseAt = saved.proposalsCloseAt ??
            Date().addingTimeInterval(2 * 86_400)
        votesCloseAt = saved.votesCloseAt ??
            Date().addingTimeInterval(3 * 86_400)
        approvePlayerChanges = saved.approvePlayerChanges
        warmupRounds = saved.warmupRounds
        if fixedInvitees == nil {
            chosenIDs = []
            chosenNames = [:]
            selectedSeasonID = nil
        }
        errorMessage = nil
    }

    private var coachEntry: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                showingCompetitionCoach = true
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: "sparkles")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("La Coach sette opp konkurransen")
                            .font(.subheadline.weight(.semibold))
                        Text("Foreslå øvelser, regler og progresjon")
                            .font(.caption)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .foregroundStyle(ATHLTHArenaV3Style.gold)
                .padding(15)
                .background(ATHLTHArenaV3Style.panel())
            }
            .buttonStyle(.plain)
            .disabled(allowedActivities.isEmpty)
            if !competitionSettings.coachExerciseIDs.isEmpty {
                Text("Coach har valgt \(competitionSettings.coachExerciseIDs.count) eksisterende øvelser. Forslaget kan gjennomgås nedenfor før publisering.")
                    .font(.caption)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
                ForEach(coachNames, id: \.self) { name in
                    Label(name, systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaV3Style.gold)
                }
                Button("Fjern Coach-forslaget") {
                    competitionSettings.coachExerciseIDs = []
                    coachNames = []
                }
                .font(.caption)
                .tint(ATHLTHArenaV3Style.gold)
            }
        }
    }

    private var scoringSettingsSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionTitle("Resultater og poeng")
            Picker("Poengmetode", selection: Binding(
                get: { competitionSettings.race.effectiveScoringMode },
                set: { mode in
                    competitionSettings.race.scoringMode = mode
                    if mode.needsGoal {
                        exerciseMode = .owner
                        competitionSettings.coachExerciseIDs = []
                        if competitionSettings.selectedExerciseIDs == nil {
                            competitionSettings.selectedExerciseIDs = []
                            exerciseCount = 0
                        }
                    }
                })) {
                ForEach(ATHLTHCompetitionScoringMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }.pickerStyle(.menu)
            Text(competitionSettings.race.effectiveScoringMode.detail)
                .font(.caption).foregroundStyle(ATHLTHArenaV3Style.secondary)
            Stepper(value: Binding(get: { competitionSettings.race.pointsPerExercise ?? 1 },
                set: { competitionSettings.race.pointsPerExercise = $0 }), in: 1...10) {
                Text("Grunnpoeng: \(competitionSettings.race.pointsPerExercise ?? 1)")
            }.font(.subheadline)
            Divider()
            Text("Godkjenningsfrist").font(.subheadline.weight(.semibold))
            Picker("Tid til å godkjenne eller bestride", selection: Binding(
                get: { competitionSettings.race.reviewHours ?? 48 },
                set: { competitionSettings.race.reviewHours = $0 })) {
                ForEach([12, 24, 48, 72, 168], id: \.self) { hours in
                    Text(ATHLTHTournamentCadence.window(hours)).tag(hours)
                }
            }.pickerStyle(.menu)
            Text("Et innsendt resultat som ikke bestrides innen fristen godkjennes automatisk etter den avtalte regelen. Dette er ikke sensorverifisering. Bestridte resultater må korrigeres før øvelsesfristen.")
                .font(.caption).foregroundStyle(ATHLTHArenaV3Style.secondary)
            Divider()
            Text("Handicap").font(.subheadline.weight(.semibold))
            Toggle("Bruk handicap", isOn: Binding(
                get: { competitionSettings.race.handicapPercentages != nil },
                set: { competitionSettings.race.handicapPercentages = $0 ? [:] : nil }))
            if competitionSettings.race.handicapPercentages != nil {
                Text("Avtal en fordel på 0–30 % per deltaker. Tiden reduseres ved tidskonkurranse; andre målinger økes. Originalmålingen endres ikke. Alle må godkjenne.")
                    .font(.caption).foregroundStyle(ATHLTHArenaV3Style.secondary)
                ForEach(athletes, id: \.id) { athlete in
                    Stepper(value: Binding(
                        get: { competitionSettings.race.handicap(for: athlete.id) },
                        set: { competitionSettings.race.handicapPercentages?[ATHLTHCompetitionRaceRules.key(athlete.id)] = $0 }),
                        in: 0...30) {
                        Text(athlete.username + " · " + String(competitionSettings.race.handicap(for: athlete.id)) + " %")
                    }.font(.subheadline)
                }
            }
            if proofMode != .opponent {
                Text("Velg godkjenning fra deltaker eller arrangør. Full sensorverifisering er foreløpig ikke tilgjengelig for alle måletyper.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }.padding(15).background(ATHLTHArenaV3Style.panel())
        .tint(ATHLTHArenaV3Style.gold)
    }

    private var rematchExerciseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(isRematch ? "Velg øvelser til rematch" : "Konkurranseøvelser")
            Text(isRematch ? "Behold øvelsene fra forrige duell, eller velg nye." : isDuel ? "Velg øvelser og treningsøkter før invitasjonen sendes." : "Velg fra biblioteket nå, eller la deltakerne velge øvelser senere.")
                .font(.caption).foregroundStyle(ATHLTHArenaV3Style.secondary)
            if !usesExplicitExercises {
                Label("Øvelser velges senere · " + exerciseMode.title, systemImage: "clock")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
            }
            ForEach(competitionSettings.selectedExerciseIDs ?? [], id: \.self) { id in
                VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(rematchNames[id] ?? "Valgt øvelse").font(.subheadline)
                    Spacer()
                    Button {
                        competitionSettings.selectedExerciseIDs?.removeAll { $0 == id }
                        competitionSettings.exerciseEnvironments.removeValue(forKey: id)
                        competitionSettings.race.scoringGoals?.removeValue(forKey: ATHLTHCompetitionRaceRules.key(id))
                        competitionSettings.race.exerciseWeights?.removeValue(forKey: ATHLTHCompetitionRaceRules.key(id))
                        exerciseCount = competitionSettings.selectedExerciseIDs?.count ?? 0
                    } label: { Image(systemName: "minus.circle").frame(width: 44, height: 44) }
                    .buttonStyle(.plain)
                }
                if let activity = exerciseActivities[id] {
                    DisclosureGroup("Eget treningsmiljø (valgfritt)") {
                        exerciseVenuePicker(id: id, activity: activity)
                            .padding(.top, 6)
                    }
                    .font(.caption.weight(.medium))
                    .tint(ATHLTHArenaV3Style.gold)
                } else {
                    Text("Henter treningsform for miljøregel…").font(.caption)
                }
                if competitionSettings.race.effectiveScoringMode.needsGoal {
                    let metric = exerciseMetrics[id] ?? "repetitions"
                    let unit = metric == "duration" ? "meter" : metric == "distance" || metric == "time" ? "sekunder" : "repetisjoner"
                    TextField("Mål i " + unit, value: Binding<Double?>(
                        get: { competitionSettings.race.goal(for: id) },
                        set: { value in
                            var goals = competitionSettings.race.scoringGoals ?? [:]
                            goals[ATHLTHCompetitionRaceRules.key(id)] = value
                            competitionSettings.race.scoringGoals = goals
                        }), format: .number)
                        .keyboardType(.decimalPad)
                        .padding(9).background(ATHLTHArenaV3Style.cream, in: RoundedRectangle(cornerRadius: 10))
                }
                Stepper(value: Binding(
                    get: { competitionSettings.race.weight(for: id) },
                    set: { value in
                        var weights = competitionSettings.race.exerciseWeights ?? [:]
                        weights[ATHLTHCompetitionRaceRules.key(id)] = value
                        competitionSettings.race.exerciseWeights = weights
                    }), in: 1...5) {
                    Text("Poengvekt: \(competitionSettings.race.weight(for: id))×").font(.caption)
                }
                Divider()
                }
            }
            Menu {
                Button {
                    exerciseTemplatesOnly = false
                    showingExerciseLibrary = true
                } label: {
                    Label("Øvelser fra bibliotek", systemImage: "books.vertical")
                }
                Button {
                    exerciseTemplatesOnly = true
                    showingExerciseLibrary = true
                } label: {
                    Label("Forhåndsdefinerte øvelser og treningsøkter", systemImage: "list.bullet")
                }
                Button {
                    exerciseTemplatesOnly = nil
                    showingExerciseLibrary = true
                } label: {
                    Label("Søk i alle", systemImage: "magnifyingglass")
                }
            } label: {
                Label("Legg til konkurranseøvelse", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHArenaV3Style.gold)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(ATHLTHArenaV3Style.cream, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(!ATHLTHTournamentActivity.canCreate(with: allowedActivities) || (competitionSettings.selectedExerciseIDs?.count ?? 0) >= 12)
            if isDuel && allowedActivities.contains(.running) {
                Divider()
                Button {
                    showingDuelRoute = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Felles løperute").font(.subheadline.weight(.semibold))
                            Text(competitionSettings.race.routeName.isEmpty ? "Velg lagret rute" : competitionSettings.race.routeName)
                                .font(.caption)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .foregroundStyle(ATHLTHArenaV3Style.gold)
                    .padding(12)
                    .background(ATHLTHArenaV3Style.cream, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                if competitionSettings.race.routeID != nil {
                    Button("Fjern rute", role: .destructive) {
                        competitionSettings.race.routeID = nil
                        competitionSettings.race.routeName = ""
                    }.font(.caption)
                    Text("Felles rute for frivillig Live Ghost-deling. Ruten er foreløpig ikke en separat resultatøvelse.")
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                }
            }
            if allowedActivities.isEmpty {
                Text("Velg minst én gren først.").font(.caption).foregroundStyle(ATHLTHArenaV3Style.secondary)
            }
            if let rematchSearchError { Text(rematchSearchError).font(.caption).foregroundStyle(.red) }
            if usesExplicitExercises {
                Text("\(competitionSettings.selectedExerciseIDs?.count ?? 0) av 12 valgt").font(.caption).foregroundStyle(ATHLTHArenaV3Style.secondary)
                if !isDuel && !isRematch && !competitionSettings.race.effectiveScoringMode.needsGoal {
                    Button("Velg øvelser senere i stedet") {
                        competitionSettings.selectedExerciseIDs = nil
                        competitionSettings.exerciseEnvironments = [:]
                        competitionSettings.race.scoringGoals = nil
                        competitionSettings.race.exerciseWeights = nil
                        exerciseCount = 4
                        exerciseMode = .owner
                    }
                    .font(.caption.weight(.medium))
                    .tint(ATHLTHArenaV3Style.gold)
                }
            }
        }
        .padding(15).background(ATHLTHArenaV3Style.panel())

    }

    private func exerciseVenuePicker(id: UUID, activity: ATHLTHTournamentActivity) -> some View {
        let inherited = competitionSettings.effectiveEnvironment(activity: activity)
        let options = competitionSettings.allowedEnvironments(activity: activity, exerciseID: id)
        let current = competitionSettings.exerciseEnvironments[id]
        return VStack(alignment: .leading, spacing: 4) {
            Picker("Treningsmiljø", selection: Binding<ATHLTHCompetitionEnvironment?>(
                get: { competitionSettings.exerciseEnvironments[id] },
                set: { competitionSettings.exerciseEnvironments[id] = $0 }
            )) {
                Text("Samme som fellesregelen").tag(ATHLTHCompetitionEnvironment?.none)
                ForEach(ATHLTHCompetitionEnvironment.allCases.filter {
                    ($0 != inherited && options.contains($0)) || $0 == current
                }) { value in
                    Text(value.title).tag(Optional(value))
                }
            }
            .pickerStyle(.menu)
            if let current, !options.contains(current) {
                Text("Miljøregelen strider mot treningsformen eller fellesregelen.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var exerciseRulesSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionTitle("Velg øvelser")
            Text("Bestem hvordan konkurransens øvelser skal settes sammen.")
                .font(.caption)
                .foregroundStyle(ATHLTHArenaV3Style.secondary)

            ForEach(ATHLTHTournamentExerciseMode.allCases) { mode in
                Button {
                    exerciseMode = mode
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: mode.symbol)
                            .font(.system(size: 18, weight: .light))
                            .foregroundStyle(ATHLTHArenaV3Style.gold)
                            .frame(width: 34)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mode.title)
                                .font(.subheadline.weight(.semibold))
                            Text(mode.detail)
                                .font(.caption)
                                .foregroundStyle(ATHLTHArenaV3Style.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 5)
                        Image(systemName: exerciseMode == mode
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(ATHLTHArenaV3Style.gold)
                    }
                    .foregroundStyle(ATHLTHArenaV3Style.ink)
                    .padding(13)
                    .background(ATHLTHArenaV3Style.panel())
                }
                .buttonStyle(.plain)
            }

            if exerciseMode == .open {
                Label("Alle øvelsene deltakerne legger til blir med – det er ingen fast grense på fire.",
                      systemImage: "person.3.sequence")
                    .font(.caption)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity,alignment: .leading)
                    .background(ATHLTHArenaV3Style.panel())
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Antall øvelser")
                            .font(.subheadline.weight(.medium))
                        Text("Velg mellom 1 og 12")
                            .font(.caption)
                            .foregroundStyle(ATHLTHArenaV3Style.secondary)
                    }
                    Spacer()
                    Stepper(value: $exerciseCount, in: 1...12) {
                        Text("\(exerciseCount)")
                            .font(.headline.monospacedDigit())
                    }
                    .fixedSize()
                }
                .padding(14)
                .background(ATHLTHArenaV3Style.panel())
            }

            if exerciseMode == .vote {
                VStack(spacing: 12) {
                    DatePicker("Forslagsfrist", selection: $proposalsCloseAt,
                               in: Date().addingTimeInterval(120)...,
                               displayedComponents: [.date, .hourAndMinute])
                    DatePicker("Stemmefrist", selection: $votesCloseAt,
                               in: proposalsCloseAt.addingTimeInterval(60)...,
                               displayedComponents: [.date, .hourAndMinute])
                    Text("Alle får inntil \(exerciseCount) stemmer – én per øvelse. Å ikke stemme er helt greit. De \(exerciseCount) med flest stemmer velges. Ved likt resultat avgjør en tilfeldig trekning.")
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.subheadline)
                .padding(15)
                .background(ATHLTHArenaV3Style.panel())
            }

            Toggle(isOn: $approvePlayerChanges) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Alle må godkjenne spillerbytter")
                        .font(.subheadline.weight(.medium))
                    Text("Erstattere må godkjennes av gjenværende deltakere.")
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                }
            }
            .tint(ATHLTHArenaV3Style.gold)
            .padding(14)
            .background(ATHLTHArenaV3Style.panel())
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

    /// Uses hypothetical measurements, never an actual result or predicted winner.
    @ViewBuilder
    private var scoringExample: some View {
        let race = competitionSettings.race
        let exercise = (competitionSettings.selectedExerciseIDs ?? []).first {
            exerciseMetrics[$0] != nil && (!race.effectiveScoringMode.needsGoal || race.goal(for: $0) != nil)
        }
        let metric = exercise.flatMap { exerciseMetrics[$0] } ?? "repetitions"
        let goal = exercise.flatMap { race.goal(for: $0) }
        let weight = exercise.map { race.weight(for: $0) } ?? 1
        let sample = goal.map { [$0 * 0.9, $0 * 1.1] } ?? [10.0, 12.0]
        let participants = Array(athletes.prefix(2))
        let unit = metric == "duration" ? "m" : metric == "distance" || metric == "time" ? "sek" : "repetisjoner"
        if participants.count == 2,
           let points = ATHLTHCompetitionRaceRules.previewPoints(
                mode: race.effectiveScoringMode, metric: metric, values: sample,
                handicaps: participants.map { race.handicap(for: $0.id) },
                basePoints: race.pointsPerExercise ?? 1, weight: weight, goal: goal) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Eksempel på poengberegning", systemImage: "calculator")
                    .font(.subheadline.weight(.semibold))
                Text("Illustrasjon med to deltakere og eksempelverdier. Serveren beregner faktiske poeng.")
                    .font(.caption).foregroundStyle(ATHLTHArenaV3Style.secondary)
                ForEach(participants.indices, id: \.self) { index in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(participants[index].username)
                            Text(sample[index].formatted(.number.precision(.fractionLength(0...2))) + " " + unit
                                 + " · " + String(race.handicap(for: participants[index].id)) + " % handicap")
                                .font(.caption2).foregroundStyle(ATHLTHArenaV3Style.secondary)
                        }
                        Spacer()
                        Text("\(points[index]) p").font(.headline.monospacedDigit())
                    }.font(.subheadline)
                }
            }
            .padding(12)
            .background(ATHLTHArenaV3Style.cream, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func reviewRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).foregroundStyle(ATHLTHArenaV3Style.secondary)
            Spacer(minLength: 8)
            Text(value).fontWeight(.medium)
                .foregroundStyle(ATHLTHArenaV3Style.ink)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("KLAR FOR INVITASJON").font(.caption2.weight(.semibold))
                .tracking(1.5).foregroundStyle(ATHLTHArenaV3Style.gold)
            Text(effectiveTitle).font(.system(size: 25, weight: .semibold, design: .serif))
                .foregroundStyle(ATHLTHArenaV3Style.ink)
            if isDuel {
                HStack(spacing: 12) {
                    ForEach(Array(athletes.prefix(2).enumerated()), id: \.element.id) { index, athlete in
                        if index == 1 {
                            Text("VS").font(.caption.weight(.bold)).foregroundStyle(ATHLTHArenaV3Style.gold)
                        }
                        VStack(spacing: 6) {
                            Text(String(athlete.username.prefix(2)).uppercased())
                                .font(.headline)
                                .frame(width: 45, height: 45)
                                .background(ATHLTHArenaV3Style.cream, in: Circle())
                            Text(athlete.username).font(.caption.weight(.medium))
                                .lineLimit(2).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 8)
            } else {
                reviewRow("Deltakere", "\(athletes.count)")
                if !isSingleEvent { reviewRow("Sesong", "\(continuationSeasonNumber ?? 1)") }
                if !warmupRounds.isEmpty { reviewRow("Oppvarming", "\(warmupRounds.count) runder · 0 poeng") }
            }
            Divider()
            Text("Konkurransen").font(.headline)
            reviewRow("Grener", ATHLTHTournamentActivity.allCases.filter { allowedActivities.contains($0) }.map(\.title).joined(separator: " · "))
            reviewRow("Øvelser", exerciseMode == .open ? "Åpen liste" : "\(exerciseCount)")
            if competitionSettings.race.routeID != nil {
                reviewRow("Felles løperute", competitionSettings.race.routeName)
            }
            ForEach(competitionSettings.selectedExerciseIDs ?? [], id: \.self) { id in
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: exerciseActivities[id]?.symbol ?? "figure.mixed.cardio")
                        .foregroundStyle(ATHLTHArenaV3Style.gold)
                    Text(rematchNames[id] ?? "Valgt øvelse").fontWeight(.medium)
                    Spacer()
                    if let goal = competitionSettings.race.goal(for: id), competitionSettings.race.effectiveScoringMode.needsGoal {
                        Text(goal.formatted())
                    }
                    Text("\(competitionSettings.race.weight(for: id))×")
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                }.font(.caption)
            }
            Divider()
            Text("Start og frister").font(.headline)
            reviewRow("Start", competitionSettings.startMode.title)
            if let start = competitionSettings.startsAt { reviewRow("Tidspunkt", start.formatted(date: .abbreviated, time: .shortened)) }
            reviewRow("Tilgjengelighet", competitionSettings.unlock.title)
            reviewRow("Gjennomføringsfrist", ATHLTHTournamentCadence.window(competitionSettings.completionHours))
            if let end = competitionSettings.endsAt { reviewRow("Slutt", end.formatted(date: .abbreviated, time: .shortened)) }
            reviewRow("Svarfrist", "\(competitionSettings.invitationDays) dager")
            Divider()
            Text("Regler og poeng").font(.headline)
            reviewRow("Treningsmiljø", competitionSettings.environment.title)
            reviewRow("Registrering", competitionSettings.race.recordingDevice.title)
            if competitionSettings.race.discipline == .workout {
                reviewRow("Poeng", competitionSettings.race.scoringSummary)
                reviewRow("Resultatgodkjenning", ATHLTHTournamentCadence.window(competitionSettings.race.reviewHours ?? 48))
                ForEach(athletes.filter { competitionSettings.race.handicap(for: $0.id) > 0 }, id: \.id) { athlete in
                    reviewRow("Handicap · " + athlete.username, "\(competitionSettings.race.handicap(for: athlete.id)) %")
                }
                if !(competitionSettings.selectedExerciseIDs ?? []).isEmpty {
                    DisclosureGroup("Eksempel på poengberegning", isExpanded: $expandedScoringExample) {
                        if expandedScoringExample { scoringExample }
                    }
                    .font(.caption.weight(.medium)).tint(ATHLTHArenaV3Style.gold)
                }
            }
            Text("Alle deltakere må godkjenne reglene før start.")
                .font(.caption)
                .foregroundStyle(ATHLTHArenaV3Style.secondary)
        }
        .padding(16)
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
    @Environment(\.dismiss) private var dismiss
    let draft: ATHLTHTournamentDraft
    let onPublished: ((UUID) -> Void)?
    @State private var publishing = false
    @State private var publishError: String?

    init(
        draft: ATHLTHTournamentDraft,
        onPublished: ((UUID) -> Void)? = nil
    ) {
        self.draft = draft
        self.onPublished = onPublished
    }

    private let tournamentCloud = ATHLTHTournamentCloudService()
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
                    Text((draft.singleEventMode
                          ? (draft.competitionSettings.race.duelMode == true ? "DUELL" : "ENKELTKONKURRANSE") : draft.format.title.uppercased()) +
                          " · UTKAST")
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
                if let publishError {
                    Label(publishError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Button {
                    Task { await publish() }
                } label: {
                    HStack(spacing: 10) {
                        if publishing { ProgressView().tint(.white) }
                        Image(systemName: "paperplane")
                        Text(publishing ? "Publiserer…" : "Publiser og inviter")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(16)
                    .background(ATHLTHArenaV3Style.ink,
                                in: RoundedRectangle(cornerRadius: 17))
                }
                .buttonStyle(.plain)
                .disabled(publishing)
                if !draft.warmupRounds.isEmpty {
                    warmupSection
                }
                if draft.singleEventMode {
                    VStack(alignment: .leading, spacing: 9) {
                        Label("Én konkurranse for alle deltakerne",
                              systemImage: "flag.checkered")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ATHLTHArenaV3Style.gold)
                        Text("Øvelse: " + draft.competitionSettings.race.discipline.title)
                            .font(.subheadline)
                        Text("Ingen ligakamper eller cupoppsett opprettes. Alle må godta og trykke Klar.")
                            .font(.caption)
                            .foregroundStyle(ATHLTHArenaV3Style.secondary)
                    }
                    .padding(15)
                    .background(ATHLTHArenaV3Style.panel())
                } else if draft.format == .cup {
                    cupView
                } else if draft.format == .groups {
                    groupsView
                } else {
                    tableView(draft.participants, title: "Ligatabell")
                }
                Text(draft.singleEventMode
                     ? "Etter publisering opprettes én gruppesamtale med invitasjoner. Startsignalet og resultatgodkjenningen håndteres av konkurransen."
                     : "Forhåndsvisningen viser bare kampstrukturen. Ved publisering sendes invitasjoner, men ingen oppgjør eller resultater teller før alle har svart og arrangøren starter.")
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

    @MainActor private func publish() async {
        guard !publishing else { return }
        publishing = true
        defer { publishing = false }
        do {
            let id = try await tournamentCloud.create(from: draft)
            onPublished?(id)
            dismiss()
        } catch {
            publishError = "Kunne ikke publisere: " + error.localizedDescription
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
            Text("Kun en forhåndsvisning. Deltakerne trekkes tilfeldig ved start, og frirunder gir ingen poeng.")
                .font(.caption)
                .foregroundStyle(ATHLTHArenaV3Style.secondary)
        }
    }
}

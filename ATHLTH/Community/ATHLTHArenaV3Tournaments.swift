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
    /// Sports chosen from Quick Train cannot silently change to another mode.
    let fixedActivity: ATHLTHTournamentActivity?
    /// Entry flows choose a single competition format. The detailed rules
    /// screen must not silently switch a group league into a cup.
    let restrictFormat: Bool
    let fixedInvitees: [ATHLTHTournamentParticipant]?
    let fixedStartMode: ATHLTHCompetitionStartMode?
    let fixedStartDate: Date?
    let onBack: ((ATHLTHTournamentDraft) -> Void)?
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
        onPublished: ((UUID) -> Void)? = nil,
        onSave: @escaping (ATHLTHTournamentDraft) -> Void
    ) {
        self.preset = preset
        self.fixedClubID = fixedClubID
        self.isDuel = continuation?.competitionSettings.race.duelMode == true || duelMode
        self.isSingleEvent = continuation?.singleEventMode ?? (singleEventMode || duelMode)
        self.fixedActivity = fixedActivity
        self.restrictFormat = fixedActivity != nil || continuation != nil || fixedInvitees != nil
        self.fixedInvitees = fixedInvitees
        self.fixedStartMode = fixedStartMode
        self.fixedStartDate = fixedStartDate
        self.onBack = onBack
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
            continuation?.exerciseCount ?? 4)
        _approvePlayerChanges = State(initialValue:
            continuation?.approvePlayerChanges ?? false)
        _warmupRounds = State(initialValue:
            continuation?.warmupRounds ?? [])
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

    private var canSaveTemplate: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 &&
        !allowedActivities.isEmpty && competitionSettings.isValid &&
        !templateSaving && !publishing
    }

    private var canSave: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 &&
        // The shared event engine has distinct roster limits for duel and single event.
        (isDuel ? athletes.count == 2 : athletes.count >= (isSingleEvent ? 3 : format == .cup ? 4 : 2)) &&
        !busy && !allowedActivities.isEmpty &&
        (!isDuel || competitionSettings.race.discipline == .workout) &&
        (!isSingleEvent || competitionSettings.race.discipline == .workout ||
            (allowedActivities.count == 1 && exerciseCount == 1 && exerciseMode != .open)) &&
        competitionSettings.isValid &&
        competitionSettings.race.isOperational &&
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
                VStack(alignment: .leading, spacing: 22) {
                    if fixedInvitees == nil {
                        titleSection
                        formatSection
                    }
                    ATHLTHTournamentRuleConfigurationSection(
                        activities: Binding(
                            get: {
                                fixedActivity.map { Set([$0]) } ?? allowedActivities
                            },
                            set: { newValue in
                                if fixedActivity == nil {
                                    allowedActivities = newValue
                                }
                            }
                        ),
                        authority: $rulesAuthority,
                        cadenceDays: $cadenceDays,
                        completionHours: $competitionSettings.completionHours,
                        showsLegacyRoundTiming: false
                    )
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
                    coachEntry
                    templateEntry
                    exerciseRulesSection
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
                    )
                    ATHLTHCompetitionRaceRulesSection(
                        settings: $competitionSettings,
                        activities: fixedActivity.map { Set([$0]) } ?? allowedActivities,
                        workoutOnly: isDuel
                    )
                    ATHLTHTournamentCompetitionRulesSection(
                        settings: $competitionSettings,
                        activities: fixedActivity.map { Set([$0]) } ?? allowedActivities,
                        showsStartTiming: fixedStartMode == nil,
                        isDuel: isDuel,
                        isSharedEvent: isSingleEvent,
                        usesIndividualExerciseDeadlines: isSingleEvent && competitionSettings.race.discipline == .workout
                    )
                    if !isSingleEvent { warmupSection }
                    if format == .groups { groupsSection }
                    if fixedInvitees == nil {
                        inviteSection
                        if activeClubID != nil { seasonSection }
                    }
                    preview
                    Text("Invitasjoner og regler godkjennes før start. Konkurransen starter manuelt, automatisk når alle er klare eller på valgt tidspunkt, slik du har valgt.")
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let errorMessage {
                        Text(errorMessage).font(.caption).foregroundStyle(.red)
                    }
                }
                .padding(18)
                .frame(maxWidth: 650)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(ATHLTHArenaV3Style.cream.ignoresSafeArea())
            .navigationTitle(fixedInvitees == nil ? "Ny konkurranse" : "Regler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(fixedInvitees == nil ? "Avbryt" : "Tilbake") {
                        onBack?(makeDraft())
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 9) {
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

                    Button {
                        onSave(makeDraft())
                        dismiss()
                    } label: {
                        Text("Lagre som utkast")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ATHLTHArenaV3Style.ink)
                            .frame(maxWidth: .infinity, minHeight: 35)
                    }
                    .disabled(!canSave || publishing)
                    Button {
                        templateName = title
                        showingSaveTemplate = true
                    } label: {
                        Label("Lagre som mal", systemImage: "square.stack.3d.up")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(ATHLTHArenaV3Style.gold)
                            .frame(maxWidth: .infinity, minHeight: 29)
                    }
                    .disabled(!canSaveTemplate)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.regularMaterial)
            }
        }
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
        .sheet(isPresented: $showingTemplatePicker) {
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
        .sheet(isPresented: $showingCompetitionCoach) {
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
        .sheet(isPresented: $showingSeasonCreation) {
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

    private func makeDraft() -> ATHLTHTournamentDraft {
        var configured = competitionSettings
        configured.race.exerciseScoringVersion = isSingleEvent && configured.race.discipline == .workout ? 2 : nil
        configured.race.competitionEndsAt = configured.endsAt.map { ISO8601DateFormatter().string(from: $0) }
        configured.race.duelMode = isDuel ? true : nil
        if isDuel {
            configured.unansweredPolicy = .cancel
            configured.invitationPermission = .admin
            configured.joinApproval = .admin
        }
        return ATHLTHTournamentDraft(
            ownerID: session.profile.userID,
            clubID: activeClubID,
            seasonID: activeClubID == nil ? nil : selectedSeasonID,
            title: String(title.trimmingCharacters(
                in: .whitespacesAndNewlines).prefix(80)),
            format: format,
            singleEventMode: isSingleEvent,
            groupSize: groupSize,
            qualifiersPerGroup: qualifiersPerGroup,
            participants: athletes,
            warmupRounds: warmupRounds.enumerated().map { index, round in
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
            competitionSettings: configured
        )
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

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Gjennomgang før invitasjon")
            Text(title).font(ATHLTHTrainDesign.cardTitle)
            Label("Valgt gren: " + allowedActivities.sorted { $0.rawValue < $1.rawValue }.map(\.title).joined(separator: " og "), systemImage: "figure.mixed.cardio")
                .font(.subheadline)
            Label(exerciseMode == .open ? "Åpen øvelsesliste" : "\(exerciseCount) øvelser", systemImage: "list.bullet").font(.subheadline)
            Label(competitionSettings.startMode.title, systemImage: "calendar").font(.subheadline)
            Label(competitionSettings.unlock.title, systemImage: "list.bullet").font(.subheadline)
            if let start = competitionSettings.startsAt {
                Text(start.formatted(date: .abbreviated, time: .shortened)).font(.caption)
            }
            if let end = competitionSettings.endsAt {
                Label("Slutt: " + end.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar.badge.clock").font(.caption)
            }
            ForEach(athletes, id: \.id) { athlete in
                Label(athlete.username, systemImage: "person.crop.circle").font(.caption)
            }
            Text(isSingleEvent
                ? "Én felles hendelse · \(athletes.count) deltakere"
                : format == .cup
                ? "\(ATHLTHTournamentStructure.bracketSize(athletes.count))-plassers cupoppsett"
                : format == .league
                ? "\(ATHLTHTournamentStructure.leagueMatchCount(athletes.count)) oppgjør i én liga"
                : "\(ATHLTHTournamentStructure.groups(athletes, size: groupSize).count) grupper")
                .font(.headline)
                .foregroundStyle(ATHLTHArenaV3Style.ink)
            if !warmupRounds.isEmpty {
                Label("\(warmupRounds.count) oppvarmingsrunder · 0 poeng · ingen utslag",
                      systemImage: "figure.run")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ATHLTHArenaV3Style.gold)
            }
            if let season = clubSeasons.first(where: { $0.id == selectedSeasonID }) {
                Label(season.title, systemImage: "calendar")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ATHLTHArenaV3Style.gold)
            }
            Text(isSingleEvent
                ? "Én konkurranse for alle inviterte. Alle må godta og trykke Klar. Resultater vises når alle er ferdige."
                : "Oppsettet er et utkast. Trekningen gjøres ved start, og bare godkjente resultater teller.")
                .font(.caption)
                .foregroundStyle(ATHLTHArenaV3Style.secondary)
        }
        .padding(15)
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

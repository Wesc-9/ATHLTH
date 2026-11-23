import SwiftUI

/// One creation path for a named group (one event, several values) and
/// a standalone command (one event, one value). No changes are persisted
/// until the athlete presses Save.
struct ATHLTHCoachEditorTarget: Identifiable {
    let id = UUID()
    let groupID: UUID?
    let ruleID: UUID?
    let isGroup: Bool
    var startAtTrigger: Bool = false
    var legacyOption: ATHLTHAudioCoachOption? = nil

    static func newGroup() -> Self {
        .init(groupID: nil, ruleID: nil, isGroup: true)
    }
    static func newCommand() -> Self {
        .init(groupID: nil, ruleID: nil, isGroup: false)
    }
    static func group(_ id: UUID, editTrigger: Bool = false) -> Self {
        .init(groupID: id, ruleID: nil, isGroup: true,
              startAtTrigger: editTrigger)
    }
    static func command(_ id: UUID) -> Self {
        .init(groupID: nil, ruleID: id, isGroup: false)
    }
    static func legacy(_ option: ATHLTHAudioCoachOption) -> Self {
        .init(groupID: nil, ruleID: nil, isGroup: false,
              startAtTrigger: true, legacyOption: option)
    }
}

/// A scene-local editing checkpoint. Saving a Coach group remains explicit;
/// this snapshot only preserves the unfinished wizard if UIKit temporarily
/// reconstructs its sheet while the user switches apps.
struct ATHLTHCoachComposerCheckpoint: Equatable {
    let targetID: UUID
    let stage: String
    let groupName: String
    let trigger: ATHLTHAudioCoachRule.Trigger
    let interval: Int
    let eventSelection: ATHLTHCoachEventSelection
    let allowedPhases: [ATHLTHCoachWorkoutPhase]?
    let metrics: [ATHLTHAudioCoachRule.Metric]
    let motivationPhrase: String
    let motivationStyle: ATHLTHCoachEncouragementStyle
    let historicalWorkoutID: UUID?
    let activityFilter: ATHLTHCoachActivityFilter
}

/// Presentation policy only. Keep the persisted rule and its speech formatter
/// authoritative across global templates and the workout-specific editor.
enum ATHLTHCoachCommandSelection {
    typealias Metric = ATHLTHAudioCoachRule.Metric

    static func available(
        activity: ATHLTHCoachActivityFilter,
        structured: Bool, routes: Bool, distance: Bool
    ) -> [Metric] {
        Metric.allCases.filter { metric in
            switch metric {
            case .stepName, .stepRemainingTime, .groupRemainingTime,
                 .remainingExercises, .nextExercise, .previousExerciseSummary,
                 .previousMainSectionSummary:
                guard structured else { return false }
            case .routeRemainingDistance, .estimatedRouteTime:
                guard routes else { return false }
            case .distance:
                guard distance else { return false }
            default: break
            }
            switch activity {
            case .strength:
                let probe = ATHLTHAudioCoachRule(trigger: .time, metric: metric, interval: 60)
                return !ATHLTHAudioCoachSportPolicy.eligibleStrengthRules([probe]).isEmpty
            case .cycling, .swimming, .functional:
                switch metric {
                case .pace, .averagePace, .lastKilometerPace, .speed,
                     .personalRecord, .routeRemainingDistance, .estimatedRouteTime,
                     .stepName, .stepRemainingTime, .groupRemainingTime,
                     .workoutRemainingTime, .estimatedFinishTime, .remainingExercises,
                     .nextExercise, .previousExerciseSummary, .previousMainSectionSummary:
                    return false
                case .distance: return activity != .functional && distance
                default: return true
                }
            default: return true
            }
        }
    }

    static func adding(_ metric: Metric, to selected: [Metric], multiple: Bool) -> [Metric] {
        if multiple {
            return selected.contains(metric) ? selected : selected + [metric]
        }
        return [metric]
    }

    static func moving(_ metric: Metric, earlierIn selected: [Metric]) -> [Metric] {
        guard let index = selected.firstIndex(of: metric), index > 0 else { return selected }
        var result = selected
        result.swapAt(index, index - 1)
        return result
    }

    static func example(
        for rule: ATHLTHAudioCoachRule, activity: ATHLTHCoachActivityFilter,
        norwegian: Bool
    ) -> String? {
        let strength = activity == .strength
        let walking = activity == .walking
        var context = ATHLTHCoachReadoutContext()
        context.stepName = strength ? (norwegian ? "Knebøy" : "Squat")
            : walking ? (norwegian ? "Gåing" : "Walking") : (norwegian ? "Løping" : "Running")
        context.stepRemainingSeconds = 45
        context.groupRemainingSeconds = 240
        context.workoutRemainingSeconds = 900
        context.routeRemainingMeters = 2400
        context.lastKilometerPaceSecondsPerKilometer = walking ? 600 : 330
        context.overallPaceSecondsPerKilometer = walking ? 600 : 330
        context.remainingExerciseCount = 3
        context.nextExerciseName = strength ? (norwegian ? "Skulderpress" : "Shoulder press")
            : (norwegian ? "Aktiv pause" : "Active recovery")
        context.nextExerciseDetails = strength ? (norwegian ? "3 sett, 10 repetisjoner" : "3 sets, 10 repetitions") : nil
        context.previousExerciseName = context.stepName
        context.previousExerciseSeconds = 120
        context.previousExerciseDistanceMeters = strength ? nil : 400
        context.previousMainSectionExerciseCount = 4
        context.previousMainSectionSeconds = 600
        context.verifiedPersonalRecordNorwegian = "Ny personlig rekord!"
        context.verifiedPersonalRecordEnglish = "New personal record!"
        return rule.phrase(
            distanceMeters: strength ? 0 : 2000,
            elapsedSeconds: walking ? 1200 : 660,
            paceSecondsPerKilometer: strength ? nil : walking ? 600 : 320,
            heartRateBPM: 154, norwegian: norwegian, maximumHeartRateBPM: 190,
            context: context
        )
    }
}

struct ATHLTHCoachRuleComposer: View {
    @EnvironmentObject private var session: AppSessionStore
    @Binding private var draft: AudioCoachDraft
    let target: ATHLTHCoachEditorTarget
    let supportsStructured: Bool
    let showsRoutes: Bool
    let triggerAvailability: ATHLTHCoachTriggerAvailability
    let onClose: () -> Void
    var restoreCheckpoint: ATHLTHCoachComposerCheckpoint? = nil
    var onCheckpoint: ((ATHLTHCoachComposerCheckpoint) -> Void)? = nil

    private enum Stage: String {
        case name, trigger, commands
    }

    @State private var stage: Stage
    @State private var groupName: String
    @State private var trigger: ATHLTHAudioCoachRule.Trigger
    @State private var interval: Int
    @State private var eventSelection: ATHLTHCoachEventSelection
    @State private var allowedPhases: [ATHLTHCoachWorkoutPhase]?
    @State private var metrics: [ATHLTHAudioCoachRule.Metric]
    @State private var motivationPhrase: String
    @State private var motivationStyle: ATHLTHCoachEncouragementStyle
    @State private var historicalReferences: [ATHLTHCoachHistoricalRunReference] = []
    @State private var historicalWorkoutID: UUID?
    @State private var activityFilter: ATHLTHCoachActivityFilter

    private var currentCheckpoint: ATHLTHCoachComposerCheckpoint {
        ATHLTHCoachComposerCheckpoint(
            targetID: target.id, stage: stage.rawValue,
            groupName: groupName, trigger: trigger, interval: interval,
            eventSelection: eventSelection, allowedPhases: allowedPhases,
            metrics: metrics, motivationPhrase: motivationPhrase,
            motivationStyle: motivationStyle,
            historicalWorkoutID: historicalWorkoutID,
            activityFilter: activityFilter
        )
    }

    private let bronze = ATHLTHPlanDesign.accentInk
    private let ink = ATHLTHPlanDesign.ink
    private let muted = ATHLTHPlanDesign.secondaryInk

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    init(
        draft: Binding<AudioCoachDraft>,
        target: ATHLTHCoachEditorTarget,
        supportsStructured: Bool,
        showsRoutes: Bool,
        triggerAvailability: ATHLTHCoachTriggerAvailability = .global,
        onClose: @escaping () -> Void,
        restoreCheckpoint: ATHLTHCoachComposerCheckpoint? = nil,
        onCheckpoint: ((ATHLTHCoachComposerCheckpoint) -> Void)? = nil
    ) {
        _draft = draft
        self.target = target
        self.supportsStructured = supportsStructured
        self.showsRoutes = showsRoutes
        self.triggerAvailability = triggerAvailability
        self.onClose = onClose
        self.restoreCheckpoint = restoreCheckpoint
        self.onCheckpoint = onCheckpoint
        let checkpoint = restoreCheckpoint?.targetID == target.id
            ? restoreCheckpoint : nil
        let value = draft.wrappedValue
        let group = value.coachGroups.first { $0.id == target.groupID }
        let original = target.ruleID.flatMap { id in
            value.customRules.first { $0.id == id }
        } ?? group?.ruleIDs.compactMap { id in
            value.customRules.first { $0.id == id }
        }.first
        let allMetrics = group == nil ? (original?.selectedMetrics ?? []) :
            group!.ruleIDs.compactMap { id in
                value.customRules.first { $0.id == id }
            }.flatMap(\.selectedMetrics)
        var uniqueMetrics: [ATHLTHAudioCoachRule.Metric] = []
        for metric in allMetrics where !uniqueMetrics.contains(metric) {
            uniqueMetrics.append(metric)
        }

        _stage = State(initialValue:
            checkpoint.flatMap { Stage(rawValue: $0.stage) } ??
            (target.startAtTrigger ? .trigger :
                (target.groupID != nil || target.ruleID != nil) ? .commands :
                (target.isGroup ? .name : .trigger)))
        _groupName = State(initialValue:
            checkpoint?.groupName ?? group?.name ?? "")
        _trigger = State(initialValue: checkpoint?.trigger ??
            group?.trigger ?? original?.trigger ??
            Self.legacyTrigger(target.legacyOption))
        _interval = State(initialValue: checkpoint?.interval ??
            group?.interval ?? original?.interval ??
            Self.legacyInterval(target.legacyOption, draft: value))
        _eventSelection = State(initialValue:
            checkpoint?.eventSelection ?? group?.eventSelection ??
            original?.eventSelection ?? .every)
        _allowedPhases = State(initialValue:
            checkpoint?.allowedPhases ?? group?.phases ?? original?.allowedPhases)
        _metrics = State(initialValue: checkpoint?.metrics ??
            (target.isGroup ? uniqueMetrics :
            Array((uniqueMetrics.isEmpty
                ? target.legacyOption.map { [Self.legacyMetric($0)] } ?? []
                : uniqueMetrics).prefix(1))))
        _motivationPhrase = State(initialValue:
            checkpoint?.motivationPhrase ?? original?.customPhrase ?? "")
        _motivationStyle = State(initialValue:
            checkpoint?.motivationStyle ??
            original?.encouragementStyle ?? .encouragement)
        _historicalWorkoutID = State(initialValue:
            checkpoint?.historicalWorkoutID ?? original?.historicalWorkoutID)
        _activityFilter = State(initialValue:
            checkpoint?.activityFilter ?? group?.activityFilter ??
            original?.activityFilter ?? .all)
    }

    private var isEditing: Bool {
        target.groupID != nil || target.ruleID != nil ||
            target.legacyOption != nil
    }

    private static func legacyTrigger(
        _ option: ATHLTHAudioCoachOption?
    ) -> ATHLTHAudioCoachRule.Trigger {
        switch option {
        case .distanceUpdates, .distance, .averagePace,
             .routeRemaining, .routeETA: return .distance
        case .workoutStart: return .workoutStart
        case .currentZone: return .zoneEnter
        case .pauseResume: return .recoveryStart
        case .workoutFinish: return .cooldownEnd
        default: return .time
        }
    }

    private static func legacyInterval(
        _ option: ATHLTHAudioCoachOption?,
        draft: AudioCoachDraft
    ) -> Int {
        switch option {
        case .distanceUpdates, .distance, .averagePace,
             .routeRemaining, .routeETA:
            return max(100, Int((draft.distanceIntervalKilometers * 1_000).rounded()))
        case .currentZone: return 3
        case .timedUpdates, .elapsedTime, .clockTime, .heartRate:
            return max(15, draft.timeIntervalSeconds)
        default: return 1
        }
    }

    private static func legacyMetric(
        _ option: ATHLTHAudioCoachOption
    ) -> ATHLTHAudioCoachRule.Metric {
        switch option {
        case .distance, .distanceUpdates: return .distance
        case .averagePace: return .averagePace
        case .timedUpdates, .elapsedTime: return .elapsedTime
        case .clockTime: return .clockTime
        case .heartRate: return .heartRate
        case .currentZone: return .heartRateZone
        case .routeRemaining: return .routeRemainingDistance
        case .routeETA: return .estimatedRouteTime
        case .currentStep: return .stepName
        case .remainingStepTime: return .stepRemainingTime
        case .remainingStepDistance: return .stepRemainingTime
        case .workoutFinish: return .workoutRemainingTime
        case .workoutStart, .pauseResume, .motivation,
             .randomEncouragement, .adaptiveMotivation, .contextual:
            return .motivation
        default: return .elapsedTime
        }
    }
    private var selectedHistory: ATHLTHCoachHistoricalRunReference? {
        historicalReferences.first { $0.id == historicalWorkoutID }
    }

    private var canAdvanceTrigger: Bool {
        triggerAvailability.supports(trigger, for: activityFilter) &&
            (trigger != .slowerThanPreviousWorkout || selectedHistory != nil)
    }

    private var canSave: Bool {
        canAdvanceTrigger && !metrics.isEmpty && unavailableSelected.isEmpty && (!target.isGroup ||
            !groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) &&
            (isEditing || draft.customRules.count < 20)
    }

    private var effectiveActivity: ATHLTHCoachActivityFilter {
        activityFilter == .all ? (triggerAvailability.workoutActivity ?? .all) : activityFilter
    }

    private var availableMetrics: [ATHLTHAudioCoachRule.Metric] {
        ATHLTHCoachCommandSelection.available(
            activity: effectiveActivity, structured: supportsStructured,
            routes: showsRoutes, distance: triggerAvailability.supportsDistance
        )
    }

    private var unavailableSelected: [ATHLTHAudioCoachRule.Metric] {
        metrics.filter { !availableMetrics.contains($0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(stageLabel)
                            .font(.caption2.weight(.bold))
                            .tracking(1.5)
                            .foregroundStyle(bronze)
                        Text(stageHeadline)
                            .font(.system(size: 27, weight: .medium, design: .serif))
                            .foregroundStyle(ink)
                        Text(stageHelp)
                            .font(.subheadline)
                            .foregroundStyle(muted)
                    }
                    .padding(.bottom, 4)

                    switch stage {
                    case .name:
                        nameStep
                    case .trigger:
                        ATHLTHCoachSimpleTriggerEditor(
                            trigger: $trigger,
                            interval: $interval,
                            eventSelection: $eventSelection,
                            phases: $allowedPhases,
                            supportsStructured: supportsStructured,
                            triggerAvailability: triggerAvailability,
                            activityFilter: $activityFilter,
                            historicalReferences: historicalReferences,
                            historicalWorkoutID: $historicalWorkoutID
                        )
                    case .commands:
                        commandStep
                    }

                    if stage != .commands {
                        Button { next() } label: {
                            HStack {
                                Text(tr("Continue", "Fortsett"))
                                Spacer()
                                Image(systemName: "arrow.right")
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(17)
                            .background(bronze, in: RoundedRectangle(cornerRadius: 17))
                        }
                        .buttonStyle(.plain)
                        .disabled(
                            (stage == .name &&
                                groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ||
                            (stage == .trigger && !canAdvanceTrigger)
                        )
                        .opacity(
                            (stage == .name &&
                                groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ||
                            (stage == .trigger && !canAdvanceTrigger)
                            ? 0.45 : 1
                        )
                    }
                }
                .padding(18)
                .frame(maxWidth: 650)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if stage == .commands { commandFooter }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(target.isGroup
                ? tr("Coach group", "Coach-gruppe")
                : tr("Command", "Kommando"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(stage == .name || (stage == .trigger && !target.isGroup)
                        ? tr("Cancel", "Avbryt") : tr("Back", "Tilbake")) {
                        if stage == .commands { stage = .trigger }
                        else if stage == .trigger && target.isGroup { stage = .name }
                        else { onClose() }
                    }
                }
            }
        }
        .presentationDetents([.large])
        .task(id: session.profile.userID) {
            historicalReferences = ATHLTHCoachHistoricalRunEvidence.available(
                userID: session.profile.userID
            )
        }
        .onAppear {
            onCheckpoint?(currentCheckpoint)
        }
        .onChange(of: currentCheckpoint) { _, checkpoint in
            onCheckpoint?(checkpoint)
        }
        .accessibilityIdentifier("athlth-coach-rule-composer")
    }

    private var stageLabel: String {
        switch stage {
        case .name: tr("STEP 1 OF 3", "STEG 1 AV 3")
        case .trigger: target.isGroup
            ? tr("STEP 2 OF 3", "STEG 2 AV 3") : tr("STEP 1 OF 2", "STEG 1 AV 2")
        case .commands: target.isGroup
            ? tr("STEP 3 OF 3", "STEG 3 AV 3") : tr("STEP 2 OF 2", "STEG 2 AV 2")
        }
    }
    private var stageHeadline: String {
        switch stage {
        case .name: tr("Name your group", "Gi gruppen et navn")
        case .trigger: tr("When should Coach speak?", "Når skal Coach snakke?")
        case .commands: tr("What should Coach say?", "Hva skal Coach si?")
        }
    }
    private var stageHelp: String {
        switch stage {
        case .name: tr(
            "Use a name that describes the announcement.",
            "Velg et navn som beskriver hva gruppen skal gjøre.")
        case .trigger: tr(
            "Choose one trigger. It controls every command in this group or single command.",
            "Velg én trigger. Den styrer alle kommandoene i gruppen eller enkeltkommandoen.")
        case .commands: target.isGroup
            ? tr("Build one message, in the order you want to hear it.",
                 "Sett sammen én melding, i den rekkefølgen du vil høre den.")
            : tr("Choose what Coach should read aloud.",
                 "Velg hva Coach skal lese opp.")
        }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(tr("GROUP NAME", "GRUPPENAVN"))
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(bronze)
            TextField(tr("For example: Every kilometre", "F.eks. Hver kilometer"),
                      text: $groupName)
                .font(.subheadline)
                .textInputAutocapitalization(.sentences)
                .padding(16)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityIdentifier("athlth-coach-group-name")
        }
    }

    // The old duplicated selected/list interface is replaced by one
    // ordered composer and a compact, unselected-only catalogue.
    private var commandStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            commandPreview
            selectedCommandCard
            if metrics.contains(.motivation) { motivationEditor }
            commandCatalogue
            if draft.customRules.count >= 20 && !isEditing {
                Text(tr("Maximum 20 active rules per template.",
                        "Maks 20 regler per mal."))
                    .font(.caption)
                    .foregroundStyle(muted)
            }
        }
        .accessibilityIdentifier("athlth-coach-command-builder")
    }

    private var exampleText: String? {
        guard let first = metrics.first else { return nil }
        var rule = ATHLTHAudioCoachRule(
            trigger: trigger, metric: first, interval: interval,
            additionalMetrics: Array(metrics.dropFirst())
        )
        rule.encouragementStyle = motivationStyle
        let phrase = motivationPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        rule.customPhrase = phrase.isEmpty ? nil : String(phrase.prefix(180))
        if let reference = selectedHistory {
            rule.historicalWorkoutFirstKilometerSeconds = reference.firstKilometerSeconds
        }
        return ATHLTHCoachCommandSelection.example(
            for: rule, activity: effectiveActivity,
            norwegian: tr("en", "nb") == "nb"
        )
    }

    private var commandPreview: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "waveform")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(bronze)
                    .frame(width: 46, height: 46)
                    .background(ATHLTHPlanDesign.selectedSurface, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("WHEN COACH SPEAKS", "NÅR COACH SNAKKER"))
                        .font(.caption2.weight(.semibold))
                        .tracking(1.1)
                        .foregroundStyle(muted)
                    Text(trigger.summary(interval: interval))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            Divider()
            Text(tr("Message preview", "Forhåndsvisning"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(bronze)
            Text(exampleText ?? tr(
                "Add content to see your message here.",
                "Legg til innhold for å se meldingen her."))
                .font(.system(.title3, design: .serif))
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("athlth-coach-command-preview")
            Text(tr("Example values. Coach uses available live data during your workout.",
                    "Eksempelverdier. Coach bruker tilgjengelige sanntidsdata under økten."))
                .font(.caption)
                .foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ATHLTHPlanDesign.selectedSurface, in: RoundedRectangle(cornerRadius: 24))
    }

    private var commandColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 148), spacing: 8, alignment: .top)]
    }

    private var selectedCommandCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(tr("Your message", "Din melding"))
                    .font(.headline)
                    .foregroundStyle(ink)
                Spacer()
                Text("\(metrics.count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(bronze)
            }
            if metrics.isEmpty {
                Text(tr("Choose content from the options below.",
                        "Velg innhold fra alternativene nedenfor."))
                    .font(.subheadline)
                    .foregroundStyle(muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
            } else {
                if target.isGroup && metrics.count > 1 {
                    Text(tr("Numbered in speaking order. Use the arrow to move a choice earlier.",
                            "Nummerert i opplesningsrekkefølge. Bruk pilen for å flytte et valg frem."))
                        .font(.caption)
                        .foregroundStyle(muted)
                }
                LazyVGrid(columns: commandColumns, alignment: .leading, spacing: 8) {
                    ForEach(metrics) { metric in
                        selectedCommand(metric)
                    }
                }
            }
            if !unavailableSelected.isEmpty {
                Text(tr("Some saved choices are unavailable for this activity. Remove them before saving.",
                        "Noen lagrede valg er ikke tilgjengelige for denne aktiviteten. Fjern dem før du lagrer."))
                    .font(.caption)
                    .foregroundStyle(bronze)
            }
        }
    }

    private func selectedCommand(_ metric: ATHLTHAudioCoachRule.Metric) -> some View {
        let index = metrics.firstIndex(of: metric) ?? 0
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                Text(String(index + 1))
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(bronze)
                    .frame(width: 24, height: 24)
                    .background(Color.white, in: Circle())
                    .accessibilityLabel(tr("Speaking order", "Opplesningsrekkefølge") + " " + String(index + 1))
                Spacer(minLength: 0)
                if target.isGroup && index > 0 {
                    Button {
                        metrics = ATHLTHCoachCommandSelection.moving(metric, earlierIn: metrics)
                    } label: {
                        Image(systemName: "arrow.left")
                            .font(.caption.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(tr("Move earlier", "Flytt frem") + " " + metric.title)
                }
                Button {
                    metrics.removeAll { $0 == metric }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(tr("Remove", "Fjern") + " " + metric.title)
            }
            .buttonStyle(.plain)
            .foregroundStyle(bronze)
            Label(metric.title, systemImage: commandSymbol(metric))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)
            if unavailableSelected.contains(metric) {
                Text(tr("Unavailable", "Ikke tilgjengelig"))
                    .font(.caption2)
                    .foregroundStyle(muted)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ATHLTHPlanDesign.selectedSurface, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier("athlth-coach-selected-" + metric.rawValue)
    }

    private var commandCatalogue: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(tr("Add content", "Velg innhold"))
                    .font(.headline)
                    .foregroundStyle(ink)
                Spacer()
                Text(effectiveActivity.title)
                    .font(.caption)
                    .foregroundStyle(muted)
            }
            let remaining = availableMetrics.filter { !metrics.contains($0) }
            if remaining.isEmpty {
                Text(tr("All available content has been added.",
                        "Alt tilgjengelig innhold er lagt til."))
                    .font(.caption)
                    .foregroundStyle(muted)
            }
            ForEach(ATHLTHCoachMetricCategory.allCases) { category in
                let choices = remaining.filter { $0.category == category }
                if !choices.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(category.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(bronze)
                        LazyVGrid(columns: commandColumns, alignment: .leading, spacing: 8) {
                            ForEach(choices) { metric in
                                commandTile(metric)
                            }
                        }
                    }
                }
            }
        }
    }

    private func commandTile(_ metric: ATHLTHAudioCoachRule.Metric) -> some View {
        Button {
            metrics = ATHLTHCoachCommandSelection.adding(metric, to: metrics, multiple: target.isGroup)
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Image(systemName: commandSymbol(metric))
                        .font(.system(size: 19, weight: .medium))
                    Spacer()
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                        .padding(7)
                        .background(ATHLTHPlanDesign.selectedSurface, in: Circle())
                }
                .foregroundStyle(bronze)
                Text(metric.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("Add", "Legg til") + " " + metric.title)
        .accessibilityIdentifier("athlth-coach-add-" + metric.rawValue)
    }

    private func commandSymbol(_ metric: ATHLTHAudioCoachRule.Metric) -> String {
        switch metric {
        case .pace, .averagePace, .lastKilometerPace: return "figure.run"
        case .speed: return "speedometer"
        case .distance, .routeRemainingDistance: return "point.topleft.down.to.point.bottomright.curvepath"
        case .heartRate: return "heart.fill"
        case .heartRateZone: return "heart.text.square"
        case .motivation: return "quote.bubble"
        case .hydrationReminder: return "drop"
        case .clockTime, .estimatedFinishTime: return "clock"
        case .date: return "calendar"
        case .personalRecord: return "trophy"
        case .stepName, .nextExercise: return "list.bullet"
        case .remainingExercises: return "list.number"
        case .previousExerciseSummary, .previousMainSectionSummary: return "chart.bar"
        case .estimatedRouteTime: return "map"
        case .elapsedTime, .stepRemainingTime, .groupRemainingTime,
             .workoutRemainingTime: return "timer"
        }
    }

    private var motivationEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Make it personal", "Gjør meldingen personlig"))
                .font(.headline)
                .foregroundStyle(ink)
            Picker(tr("Style", "Stil"), selection: $motivationStyle) {
                Text(tr("Encourage", "Motiver")).tag(ATHLTHCoachEncouragementStyle.encouragement)
                Text(tr("Push", "Push")).tag(ATHLTHCoachEncouragementStyle.push)
                Text(tr("Praise", "Ros")).tag(ATHLTHCoachEncouragementStyle.praise)
            }
            .pickerStyle(.segmented)
            TextField(tr("Your own message (optional)", "Din egen melding (valgfritt)"),
                      text: $motivationPhrase, axis: .vertical)
                .lineLimit(2...5)
                .padding(13)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var commandFooter: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    metrics.removeAll()
                } label: {
                    Text(tr("Clear", "Tøm valg"))
                        .font(.subheadline.weight(.medium))
                        .frame(minHeight: 48)
                        .padding(.horizontal, 10)
                }
                .buttonStyle(.plain)
                .foregroundStyle(bronze)
                .disabled(metrics.isEmpty)
                Button(action: save) {
                    Label(target.isGroup ? tr("Save group", "Lagre gruppe")
                          : tr("Save command", "Lagre kommando"),
                          systemImage: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(bronze.opacity(canSave ? 1 : 0.45),
                                    in: RoundedRectangle(cornerRadius: 17))
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .accessibilityIdentifier("athlth-coach-composer-save")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(maxWidth: 650)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }

    private func next() {
        switch stage {
        case .name:
            if !groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                stage = .trigger
            }
        case .trigger:
            guard canAdvanceTrigger else { return }
            // New triggers should work on first save without searching a
            // 20-item command list for the obvious matching readout.
            if metrics.isEmpty {
                switch trigger {
                case .heartRateAbove, .heartRateBelow:
                    metrics = [.heartRate]
                case .zoneEnter, .zoneExit, .zoneBelow,
                     .plannedZoneBelow, .plannedZoneOutside:
                    metrics = [.heartRateZone]
                case .randomMotivation, .nearFinishTime, .nearFinishDistance,
                     .elevationGain, .uphillDetected,
                     .paceFasterThanTarget, .paceSlowerThanTarget,
                     .slowerThanPreviousWorkout:
                    metrics = [.motivation]
                default: break
                }
            }
            stage = .commands
        case .commands: save()
        }
    }

    private func save() {
        guard canSave, let primary = metrics.first else { return }
        let name = String(groupName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        let phrase = String(motivationPhrase.trimmingCharacters(
            in: .whitespacesAndNewlines).prefix(180))
        let oldGroup = draft.coachGroups.first { $0.id == target.groupID }
        let oldRuleIDs = oldGroup?.ruleIDs ?? []
        let previous = target.ruleID.flatMap { id in
            draft.customRules.first { $0.id == id }
        } ?? oldRuleIDs.compactMap { id in
            draft.customRules.first { $0.id == id }
        }.first

        var rule = ATHLTHAudioCoachRule(
            trigger: trigger, metric: primary, interval: interval,
            additionalMetrics: target.isGroup ? Array(metrics.dropFirst()) : nil,
            enabled: true,
            allowedPhases: allowedPhases,
            scope: .workout,
            eventSelection: eventSelection
        )
        if let previous { rule.id = previous.id }
        rule.activityFilter = activityFilter == .all ? nil : activityFilter
        if trigger == .slowerThanPreviousWorkout,
           let reference = selectedHistory {
            rule.historicalWorkoutID = reference.id
            rule.historicalWorkoutFirstKilometerSeconds =
                reference.firstKilometerSeconds
            rule.historicalWorkoutTitle = reference.title
        }
        if metrics.contains(.motivation) {
            rule.encouragementStyle = motivationStyle
        }
        if metrics.contains(.motivation), !phrase.isEmpty {
            rule.customPhrase = phrase
        }

        // Old standard commands are replaced, not layered on top of the
        // newly authored rule; this prevents duplicate speech.
        if let legacyOption = target.legacyOption {
            legacyOption.setActive(false, in: &draft)
        }

        if target.isGroup {
            if let groupID = target.groupID,
               let groupIndex = draft.coachGroups.firstIndex(where: { $0.id == groupID }) {
                // Old grouped options must not continue to speak alongside
                // the new single-rule bundle after this group is saved.
                let previousOptions = draft.coachGroups[groupIndex].optionIDs
                for rawValue in previousOptions {
                    ATHLTHAudioCoachOption(rawValue: rawValue)?
                        .setActive(false, in: &draft)
                }
                draft.coachGroups[groupIndex].optionIDs = []
                draft.customRules.removeAll { oldRuleIDs.contains($0.id) }
                draft.customRules.append(rule)
                draft.coachGroups[groupIndex].name = name
                draft.coachGroups[groupIndex].trigger = trigger
                draft.coachGroups[groupIndex].interval = interval
                draft.coachGroups[groupIndex].ruleIDs = [rule.id]
                draft.coachGroups[groupIndex].eventSelection = eventSelection
                draft.coachGroups[groupIndex].phases = allowedPhases
                draft.coachGroups[groupIndex].activityFilter = rule.activityFilter
            } else {
                var group = ATHLTHAudioCoachGroup(name: name)
                group.trigger = trigger
                group.interval = interval
                group.ruleIDs = [rule.id]
                group.eventSelection = eventSelection
                group.phases = allowedPhases
                group.activityFilter = rule.activityFilter
                group.enabled = true
                draft.customRules.append(rule)
                draft.coachGroups.append(group)
            }
        } else if let id = target.ruleID,
                  let index = draft.customRules.firstIndex(where: { $0.id == id }) {
            draft.customRules[index] = rule
        } else {
            draft.customRules.append(rule)
        }
        onClose()
    }
}

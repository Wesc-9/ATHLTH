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

struct ATHLTHCoachRuleComposer: View {
    @Binding private var draft: AudioCoachDraft
    let target: ATHLTHCoachEditorTarget
    let supportsStructured: Bool
    let showsRoutes: Bool
    let onClose: () -> Void

    private enum Stage {
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
        onClose: @escaping () -> Void
    ) {
        _draft = draft
        self.target = target
        self.supportsStructured = supportsStructured
        self.showsRoutes = showsRoutes
        self.onClose = onClose
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
            target.startAtTrigger ? .trigger :
                (target.groupID != nil || target.ruleID != nil) ? .commands :
                (target.isGroup ? .name : .trigger))
        _groupName = State(initialValue: group?.name ?? "")
        _trigger = State(initialValue: group?.trigger ?? original?.trigger ??
            Self.legacyTrigger(target.legacyOption))
        _interval = State(initialValue: group?.interval ?? original?.interval ??
            Self.legacyInterval(target.legacyOption, draft: value))
        _eventSelection = State(initialValue:
            group?.eventSelection ?? original?.eventSelection ?? .every)
        _allowedPhases = State(initialValue:
            group?.phases ?? original?.allowedPhases)
        _metrics = State(initialValue: target.isGroup ? uniqueMetrics :
            Array((uniqueMetrics.isEmpty
                ? target.legacyOption.map { [Self.legacyMetric($0)] } ?? []
                : uniqueMetrics).prefix(1)))
        _motivationPhrase = State(initialValue: original?.customPhrase ?? "")
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
            return max(100, draft.distanceIntervalMeters)
        case .currentZone: return 3
        case .time, .timedUpdates, .elapsedTime, .clockTime, .heartRate:
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
    private var canSave: Bool {
        !metrics.isEmpty && (!target.isGroup ||
            !groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) &&
            (isEditing || draft.customRules.count < 20)
    }

    private var availableMetrics: [ATHLTHAudioCoachRule.Metric] {
        let wanted: [ATHLTHAudioCoachRule.Metric] = [
            .distance, .elapsedTime, .pace, .averagePace,
            .lastKilometerPace, .speed, .clockTime, .heartRate,
            .heartRateZone, .motivation, .hydrationReminder, .stepName,
            .stepRemainingTime, .workoutRemainingTime, .estimatedFinishTime,
            .remainingExercises, .nextExercise, .previousExerciseSummary,
            .previousMainSectionSummary, .routeRemainingDistance,
            .estimatedRouteTime, .personalRecord, .groupRemainingTime
        ]
        return wanted.filter {
            switch $0 {
            case .stepName, .stepRemainingTime, .remainingExercises,
                 .nextExercise, .previousExerciseSummary,
                 .previousMainSectionSummary, .groupRemainingTime:
                return supportsStructured
            case .routeRemainingDistance, .estimatedRouteTime:
                return showsRoutes
            default: return true
            }
        }
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
                            supportsStructured: supportsStructured
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
                        .disabled(stage == .name &&
                            groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity(stage == .name &&
                            groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? 0.45 : 1)
                    } else {
                        Button(action: save) {
                            Text(target.isGroup
                                ? tr("Save group", "Lagre gruppe")
                                : tr("Save command", "Lagre kommando"))
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(bronze)
                        .disabled(!canSave)
                        .accessibilityIdentifier("athlth-coach-composer-save")
                    }
                }
                .padding(18)
                .frame(maxWidth: 650)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
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
                ToolbarItem(placement: .confirmationAction) {
                    if stage == .commands {
                        Button(tr("Save", "Lagre"), action: save)
                            .disabled(!canSave)
                    }
                }
            }
        }
        .presentationDetents([.large])
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
            ? tr("Select several values. Coach speaks them together once per trigger.",
                 "Velg flere verdier. Coach leser dem samlet én gang per trigger.")
            : tr("Choose exactly one command.",
                 "Velg nøyaktig én kommando.")
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

    private var commandStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(trigger.summary(interval: interval), systemImage: "waveform")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(bronze)
            if !metrics.isEmpty {
                Text(tr("SELECTED", "VALGT"))
                    .font(.caption2.weight(.bold))
                    .tracking(1.3)
                    .foregroundStyle(bronze)
                VStack(spacing: 4) {
                    ForEach(metrics) { metric in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(bronze)
                            Text(metric.title)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Button {
                                metrics.removeAll { $0 == metric }
                            } label: {
                                Image(systemName: "xmark.circle")
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel(tr("Remove", "Fjern") + " " + metric.title)
                        }
                    }
                }
                .padding(13)
                .background(ATHLTHPlanDesign.selectedSurface,
                            in: RoundedRectangle(cornerRadius: 16))
            }
            ForEach(ATHLTHCoachMetricCategory.allCases) { category in
                let choices = availableMetrics.filter { $0.category == category }
                if !choices.isEmpty {
                    Text(category.title.uppercased())
                        .font(.caption2.weight(.bold))
                        .tracking(1.1)
                        .foregroundStyle(bronze)
                        .padding(.top, 8)
                    VStack(spacing: 5) {
                        ForEach(choices) { metric in
                            Button {
                                if target.isGroup {
                                    if metrics.contains(metric) {
                                        metrics.removeAll { $0 == metric }
                                    } else {
                                        metrics.append(metric)
                                    }
                                } else {
                                    metrics = [metric]
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: metrics.contains(metric)
                                        ? "checkmark.circle.fill" : "plus.circle")
                                        .font(.title3)
                                        .foregroundStyle(bronze)
                                    Text(metric.title)
                                        .font(.subheadline)
                                        .foregroundStyle(ink)
                                    Spacer()
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(metrics.contains(metric)
                                    ? ATHLTHPlanDesign.selectedSurface : Color.white,
                                    in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if metrics.contains(.motivation) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(tr("PERSONAL MESSAGE (OPTIONAL)", "EGEN MELDING (VALGFRITT)"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(bronze)
                    TextField(tr("Your own encouragement", "Din egen motivasjon"),
                              text: $motivationPhrase, axis: .vertical)
                        .lineLimit(2...5)
                        .padding(13)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            if draft.customRules.count >= 20 && !isEditing {
                Text(tr("Maximum 20 active rules per template.",
                        "Maks 20 regler per mal."))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func next() {
        switch stage {
        case .name:
            if !groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                stage = .trigger
            }
        case .trigger: stage = .commands
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
                draft.customRules.removeAll { oldRuleIDs.contains($0.id) }
                draft.customRules.append(rule)
                draft.coachGroups[groupIndex].name = name
                draft.coachGroups[groupIndex].trigger = trigger
                draft.coachGroups[groupIndex].interval = interval
                draft.coachGroups[groupIndex].ruleIDs = [rule.id]
                draft.coachGroups[groupIndex].eventSelection = eventSelection
                draft.coachGroups[groupIndex].phases = allowedPhases
            } else {
                var group = ATHLTHAudioCoachGroup(name: name)
                group.trigger = trigger
                group.interval = interval
                group.ruleIDs = [rule.id]
                group.eventSelection = eventSelection
                group.phases = allowedPhases
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

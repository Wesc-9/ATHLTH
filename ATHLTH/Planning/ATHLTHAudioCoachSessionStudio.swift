import SwiftUI

/// Session-scoped Audio Coach. The single active-list workspace edits the
/// original Watch configuration draft without altering global defaults.
struct ATHLTHAudioCoachSessionStudio: View {
    @Binding var draft: AudioCoachDraft
    let showRouteOptions: Bool
    let showStructuredOptions: Bool
    var triggerAvailability: ATHLTHCoachTriggerAvailability? = nil
    var simpleMode = false

    var body: some View {
        if simpleMode {
            ATHLTHBasicAudioCoachView(draft: $draft, availability: triggerAvailability ?? .session(hasRoute: showRouteOptions, structured: showStructuredOptions))
        } else {
        ATHLTHAudioCoachActiveListView(
            draft: $draft,
            showRouteOptions: showRouteOptions,
            showStructuredOptions: showStructuredOptions,
            triggerAvailability: triggerAvailability
        )
        }
    }
}

enum ATHLTHCoachRequestIntent: String, CaseIterable {
    case beforeEffort, everyTime, everyDistance, beforeRestEnd, everySets
}

enum ATHLTHCoachRequestParser {
    static func number(_ input: String) -> Int? {
        let parts = input.split(whereSeparator: { !$0.isNumber })
        guard parts.count == 1, let value = Int(parts[0]), (1...42000).contains(value) else { return nil }
        return value
    }
    static func normalized(_ input: String) -> String {
        input.lowercased().replacingOccurrences(of: "-", with: " ")
    }
    static func intent(_ input: String) -> ATHLTHCoachRequestIntent? {
        let t = normalized(input)
        let before = t.contains("før") || t.contains("before")
        let every = t.contains("hver") || t.contains("every")
        if before && (t.contains("drag") || t.contains("interval")) { return .beforeEffort }
        if before && (t.contains("pause") || t.contains("hvile") || t.contains("rest")) && restEnds(t) { return .beforeRestEnd }
        if every && (t.contains("sett") || t.contains(" set")) { return .everySets }
        if every && (t.contains("km") || t.contains("kilometer") || t.contains(" meter")) { return .everyDistance }
        if every && (t.contains("sek") || t.contains("min") || t.contains("sec")) { return .everyTime }
        return nil
    }
    private static func restEnds(_ text: String) -> Bool {
        ["ferdig", "slutt", "over", "utløp", "igjen", "end", "remaining"].contains(where: { text.contains($0) })
    }
    static func rule(_ input: String, intent: ATHLTHCoachRequestIntent,
                     availability: ATHLTHCoachTriggerAvailability) -> ATHLTHAudioCoachRule? {
        let t = normalized(input)
        guard !t.contains("ikke"), !t.contains("don't"), !t.contains("do not"),
              let amount = number(t) else { return nil }
        let words = t.split(whereSeparator: { !$0.isLetter }).map(String.init)
        let seconds = words.contains { $0 == "s" || $0 == "sek" || $0.hasPrefix("sekund") || $0.hasPrefix("sec") }
        let minutes = words.contains { $0 == "min" || $0.hasPrefix("minutt") || $0.hasPrefix("minute") }
        let km = words.contains { $0 == "km" || $0.hasPrefix("kilometer") || $0.hasPrefix("kilometre") }
        let meters = words.contains { $0 == "m" || $0.hasPrefix("meter") || $0.hasPrefix("metre") }
        let trigger: ATHLTHAudioCoachRule.Trigger
        let metric: ATHLTHAudioCoachRule.Metric
        let interval: Int
        switch intent {
        case .beforeEffort:
            guard seconds, !minutes, (5...60).contains(amount) else { return nil }
            trigger = .beforeEffort; metric = .motivation; interval = amount
        case .beforeRestEnd:
            guard seconds, !minutes, restEnds(t), (5...60).contains(amount) else { return nil }
            trigger = .strengthRestEnding; metric = .stepRemainingTime; interval = amount
        case .everySets:
            guard t.contains("sett") || t.contains("set"), (1...10).contains(amount) else { return nil }
            trigger = .strengthSetCompleted; metric = .remainingSets; interval = amount
        case .everyTime:
            guard seconds != minutes else { return nil }
            interval = minutes ? amount * 60 : amount
            guard (15...7200).contains(interval) else { return nil }
            trigger = .time
            metric = t.contains("puls") || t.contains("heart rate") ? .heartRate :
                t.contains("motivat") || t.contains("motivasjon") ? .motivation : .elapsedTime
        case .everyDistance:
            guard km || meters else { return nil }
            interval = km ? amount * 1000 : amount
            guard (100...42000).contains(interval) else { return nil }
            trigger = .distance
            metric = t.contains("puls") || t.contains("heart rate") ? .heartRate :
                t.contains("tempo") || t.contains("pace") ? .averagePace : .distance
        }
        let activity: ATHLTHCoachActivityFilter = trigger.isStrengthEvent ? .strength : (availability.workoutActivity ?? .all)
        guard availability.supports(trigger, for: activity) else { return nil }
        // Phone strength currently delivers only shared strength-event rules.
        guard activity != .strength || trigger.isStrengthEvent else { return nil }
        var rule = ATHLTHAudioCoachRule(trigger: trigger, metric: metric, interval: interval)
        rule.activityFilter = activity == .all ? nil : activity
        return rule
    }
    static func same(_ a: ATHLTHAudioCoachRule, _ b: ATHLTHAudioCoachRule) -> Bool {
        a.trigger == b.trigger && a.validatedInterval == b.validatedInterval &&
        a.selectedMetrics == b.selectedMetrics && a.activityFilter == b.activityFilter &&
        a.triggerConditions == b.triggerConditions && a.allowedPhases == b.allowedPhases &&
        a.scope == b.scope && (a.eventSelection ?? .every) == (b.eventSelection ?? .every)
    }
}

struct ATHLTHCoachRequestView: View {
    @Binding var rules: [ATHLTHAudioCoachRule]
    let availability: ATHLTHCoachTriggerAvailability
    var showSaved = false
    var protectedRuleIDs: Set<UUID> = []
    @State private var request = ""
    @State private var proposal: ATHLTHAudioCoachRule?
    @State private var status: String?
    @State private var loading = false
    @State private var task: Task<Void, Never>?
    @State private var generation = UUID()
    private func tr(_ en: String, _ no: String) -> String { ATHLTHLocalization.choose(english: en, norwegian: no) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(tr("Tell Coach what you want", "Fortell coach hva du ønsker"), systemImage: "sparkles")
                .font(.headline)
            TextField(tr("E.g. tell me every 5 minutes", "F.eks. gi meg beskjed hvert 5. minutt"), text: $request, axis: .vertical)
                .lineLimit(2...4)
                .padding(12)
                .background(ATHLTHPlanDesign.canvas, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("athlth-coach-request-input")
                .onChange(of: request) { _, _ in
                    task?.cancel(); generation = UUID(); loading = false; proposal = nil; status = nil
                }
            Button(action: search) {
                HStack {
                    if loading { ProgressView() }
                    Text(tr("Create suggestion", "Lag forslag"))
                }.frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(loading || request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if let proposal {
                VStack(alignment: .leading, spacing: 8) {
                    Text(proposal.trigger.summary(interval: proposal.validatedInterval)).font(.headline)
                    Text(proposal.metric.title).font(.subheadline)
                    if proposal.trigger == .beforeEffort {
                        Text(tr("Only when time to the next effort is known.", "Bare når tiden frem til neste drag er kjent.")).font(.caption)
                    }
                    Button {
                        guard rules.count < 20 else { return }
                        if rules.contains(where: { ATHLTHCoachRequestParser.same($0, proposal) && $0.isEnabled }) {
                            status = tr("Already added.", "Denne beskjeden finnes allerede.")
                        } else {
                            rules.append(proposal)
                            status = tr("Reminder added.", "Beskjed lagt til.")
                        }
                        self.proposal = nil
                    } label: {
                        Label(tr("Add reminder", "Legg til beskjed"), systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.borderedProminent).disabled(rules.count >= 20)
                    if rules.count >= 20 { Text(tr("Maximum 20 rules.", "Maks 20 regler.")).font(.caption) }
                }.padding(12).background(ATHLTHPlanDesign.selectedSurface, in: RoundedRectangle(cornerRadius: 12))
            }
            if let status { Text(status).font(.subheadline).foregroundStyle(ATHLTHPlanDesign.secondaryInk) }
            if showSaved {
                let standalone = rules.filter { !protectedRuleIDs.contains($0.id) }
                if !standalone.isEmpty {
                    Divider()
                    Text(tr("My reminders", "Mine beskjeder")).font(.subheadline.weight(.semibold))
                    ForEach(standalone) { rule in
                        HStack(alignment: .center, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(rule.trigger.summary(interval: rule.validatedInterval)).font(.subheadline.weight(.medium))
                                Text(rule.metric.title).font(.caption).foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            }
                            Spacer(minLength: 0)
                            Menu {
                                Button(rule.isEnabled ? tr("Turn off", "Slå av") : tr("Turn on", "Slå på")) {
                                    if let index = rules.firstIndex(where: { $0.id == rule.id }) { rules[index].enabled = !rule.isEnabled }
                                }
                                Button(tr("Remove", "Fjern"), role: .destructive) { rules.removeAll { $0.id == rule.id } }
                            } label: {
                                Image(systemName: "ellipsis.circle").frame(width: 44, height: 44)
                            }.accessibilityLabel(tr("Reminder options", "Valg for beskjed"))
                        }.opacity(rule.isEnabled ? 1 : 0.55)
                    }
                }
            }
        }
        .foregroundStyle(ATHLTHPlanDesign.ink)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .tint(ATHLTHPlanDesign.accentInk)
        .onDisappear { task?.cancel(); generation = UUID(); loading = false }
    }
    private func search() {
        let input = String(request.prefix(400))
        proposal = nil; status = nil
        if let intent = ATHLTHCoachRequestParser.intent(input) { finish(input, intent); return }
        guard ATHLTHCoachRequestParser.number(input) != nil else { finish(input, nil); return }
        loading = true
        let token = UUID(); generation = token
        task = Task { @MainActor in
            let intent = await ATHLTHIntelligenceEngine.localAudioCoachRequestIntent(input)
            guard !Task.isCancelled, generation == token else { return }
            loading = false; finish(input, intent)
        }
    }
    private func finish(_ input: String, _ intent: ATHLTHCoachRequestIntent?) {
        proposal = intent.flatMap { ATHLTHCoachRequestParser.rule(input, intent: $0, availability: availability) }
        if proposal == nil {
            status = tr("Try one supported reminder with a number and unit.", "Fant ingen passende beskjed. Prøv én påminnelse med tall og enhet.")
        }
    }
}

struct ATHLTHBasicAudioCoachView: View {
    @Binding var draft: AudioCoachDraft
    let availability: ATHLTHCoachTriggerAvailability
    private func tr(_ en: String, _ no: String) -> String { ATHLTHLocalization.choose(english: en, norwegian: no) }
    private var intervalRule: ATHLTHAudioCoachRule {
        var rule = ATHLTHAudioCoachRule(trigger: .beforeEffort, metric: .motivation, interval: 10)
        rule.activityFilter = availability.workoutActivity
        return rule
    }
    private var intervalBinding: Binding<Bool> {
        Binding(get: {
            let grouped = Set(draft.coachGroups.flatMap(\.ruleIDs))
            return draft.customRules.contains { !grouped.contains($0.id) && ATHLTHCoachRequestParser.same($0, intervalRule) && $0.isEnabled }
        }, set: { value in
            if value {
                let grouped = Set(draft.coachGroups.flatMap(\.ruleIDs))
                if let index = draft.customRules.firstIndex(where: { !grouped.contains($0.id) && ATHLTHCoachRequestParser.same($0, intervalRule) }) {
                    draft.customRules[index].enabled = true
                    return
                }
                guard draft.customRules.count < 20 else { return }
                draft.customRules.append(intervalRule)
            } else {
                let grouped = Set(draft.coachGroups.flatMap(\.ruleIDs))
                draft.customRules.removeAll { !grouped.contains($0.id) && ATHLTHCoachRequestParser.same($0, intervalRule) }
            }
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 16) {
                Toggle(isOn: $draft.enabled) { Label("Audio Coach", systemImage: "waveform").font(.title3.weight(.semibold)) }
                Text(tr("Choose what to hear during exercise.", "Velg hva du vil høre mens du trener."))
                    .font(.subheadline).foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                if draft.enabled {
                    Divider()
                    if availability.supportsDistance {
                        Toggle(tr("How far I have gone", "Hvor langt jeg har kommet"), isOn: Binding(
                            get: { draft.distanceTriggerEnabled && draft.announceDistance },
                            set: { draft.distanceTriggerEnabled = $0; draft.announceDistance = $0 }))
                        if draft.distanceTriggerEnabled && draft.announceDistance {
                            Picker(tr("How often?", "Hvor ofte?"), selection: $draft.distanceIntervalKilometers) {
                                ForEach(Array(Set([0.5, 1.0, 2.0, 5.0, draft.distanceIntervalKilometers])).sorted(), id: \.self) {
                                    Text($0.formatted(.number.precision(.fractionLength(0...2))) + " km").tag($0)
                                }
                            }
                        }
                    }
                    Toggle(tr("How long I have exercised", "Hvor lenge jeg har trent"), isOn: Binding(
                        get: { draft.timeTriggerEnabled && draft.announceElapsedTime },
                        set: { draft.timeTriggerEnabled = $0; draft.announceElapsedTime = $0 }))
                    if draft.timeTriggerEnabled && draft.announceElapsedTime {
                        Picker(tr("How often?", "Hvor ofte?"), selection: Binding(
                            get: { draft.timeIntervalSeconds },
                            set: { draft.timeIntervalSeconds = $0; draft.timeIntervalMinutes = max(1, $0 / 60) })) {
                            ForEach(Array(Set([60, 300, 600, 900, draft.timeIntervalSeconds])).sorted(), id: \.self) {
                                Text($0 % 60 == 0 ? "\($0 / 60) min" : "\($0) s").tag($0)
                            }
                        }
                    }
                    Toggle(tr("Encouragement along the way", "Litt oppmuntring underveis"), isOn: $draft.smartPrompts.motivationEnabled)
                    if availability.supports(.beforeEffort, for: availability.workoutActivity ?? .all) {
                        Toggle(tr("10 seconds before the next interval", "Si fra 10 sekunder før neste drag"), isOn: intervalBinding)
                            .disabled(draft.customRules.count >= 20 && !intervalBinding.wrappedValue)
                    }
                    Toggle(tr("When I start, pause or finish", "Når jeg starter, tar pause eller avslutter"), isOn: Binding(
                        get: { draft.announceWorkoutStart && draft.announcePauseResume && draft.announceWorkoutComplete },
                        set: { draft.announceWorkoutStart = $0; draft.announcePauseResume = $0; draft.announceWorkoutComplete = $0 }))
                    if !draft.customRules.isEmpty || !draft.coachGroups.isEmpty {
                        Text(tr("Other saved commands stay active. Edit them in Advanced.", "Andre lagrede beskjeder beholdes. Du kan endre dem i Avansert."))
                            .font(.caption).foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                }
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 20))
            if draft.enabled {
                DisclosureGroup(tr("Want another reminder?", "Ønsker du en annen beskjed?")) {
                    ATHLTHCoachRequestView(rules: $draft.customRules, availability: availability,
                        showSaved: true, protectedRuleIDs: Set(draft.coachGroups.flatMap(\.ruleIDs)))
                }.padding(12)
            }
        }
        .foregroundStyle(ATHLTHPlanDesign.ink)
        .tint(ATHLTHPlanDesign.accentInk)
        .accessibilityIdentifier("athlth-basic-audio-coach")
    }
}

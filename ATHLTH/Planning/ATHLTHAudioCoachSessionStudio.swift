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

/// The model only proposes values from this closed, typed schema. It never
/// decodes directly into the persisted rule type or assigns rule identities.
struct ATHLTHCoachRequestSpecification: Decodable {
    let trigger: ATHLTHAudioCoachRule.Trigger
    let interval: Int?
    let metrics: [ATHLTHAudioCoachRule.Metric]
    let activity: ATHLTHCoachActivityFilter?
    let phases: [ATHLTHCoachWorkoutPhase]?
    let scope: ATHLTHAudioCoachRule.Scope?
    let selection: ATHLTHCoachEventSelection?
    let sustainedSeconds: Int?
    let repeatDelaySeconds: Int?
    let maximumZone: Int?
}

enum ATHLTHCoachAdvancedRequest {
    typealias Rule = ATHLTHAudioCoachRule
    typealias Spec = ATHLTHCoachRequestSpecification

    // A historical-reference trigger cannot be authored without selecting
    // the actual workout. Own messages also need the separate text editor.
    static let triggers = Rule.Trigger.allCases.filter { $0 != .slowerThanPreviousWorkout }
    static let metrics = Rule.Metric.allCases.filter { $0 != .ownMessage }

    private static func captures(_ pattern: String, _ input: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let text = input as NSString
        return regex.matches(in: input, range: NSRange(location: 0, length: text.length)).map { match in
            (1..<match.numberOfRanges).map { i in
                let range = match.range(at: i)
                return range.location == NSNotFound ? "" : text.substring(with: range)
            }
        }
    }
    private static func amounts(_ input: String, units: String, multiplier: Int = 1) -> Set<Int> {
        Set(captures("(?<![\\d.,])([0-9]{1,5})\\.?\\s*(" + units + ")(?!\\p{L})", input)
            .compactMap { Int($0[0]) }.map { $0 * multiplier })
    }
    private static func seconds(_ input: String) -> Set<Int> {
        amounts(input, units: "sekunder|sekund|sek|seconds|second|secs|sec|s")
            .union(amounts(input, units: "minutter|minutt|min|minutes|minute|mins", multiplier: 60))
    }
    private static func meters(_ input: String) -> Set<Int> {
        amounts(input, units: "meter|metres|meters|m")
            .union(amounts(input, units: "kilometer|kilometre|kilometers|kilometres|km", multiplier: 1000))
    }
    private static func integers(_ input: String) -> Set<Int> {
        Set(captures("(?<![\\d.,])([0-9]{1,5})(?!\\d|[.,]\\d)", input).compactMap { Int($0[0]) })
    }
    private static func paces(_ input: String) -> Set<Int> {
        Set(captures("(?<!\\d)([0-9]{1,2}):([0-5][0-9])(?!\\d)", input).compactMap {
            guard let m = Int($0[0]), let s = Int($0[1]) else { return nil }
            return m * 60 + s
        })
    }
    private static func interval(_ spec: Spec, input: String) -> Int? {
        let n = spec.interval ?? 1
        switch spec.trigger {
        case .time, .randomMotivation, .nearFinishTime, .strengthRestEnding,
             .beforeNextStep, .beforeMain, .beforeCooldown, .beforeEffort:
            return seconds(input).contains(n) ? n : nil
        case .distance, .nearFinishDistance, .elevationGain:
            return meters(input).contains(n) ? n : nil
        case .paceFasterOverall, .paceFasterLastKilometer:
            return paces(input).contains(n) ? n : nil
        case .workoutTimeProgress, .workoutDistanceProgress, .stepTimeProgress:
            if n == 50 && ["halvveis", "halfway"].contains(where: { input.lowercased().contains($0) }) { return n }
            return amounts(input, units: "%|prosent|percent").contains(n) ? n : nil
        case .heartRateAbove, .heartRateBelow, .zoneEnter, .zoneExit, .zoneBelow,
             .cadenceBelow, .cadenceAbove, .strengthSetCompleted:
            return integers(input).contains(n) ? n : nil
        default:
            return spec.interval == nil || n == 1 ? 1 : nil
        }
    }

    static func validate(_ specs: [Spec], input: String,
                         availability: ATHLTHCoachTriggerAvailability) -> [Rule]? {
        guard (1...5).contains(specs.count), !input.isEmpty else { return nil }
        let lower = " " + input.lowercased() + " "
        // Do not accept a model that drops explicit unsupported OR logic
        // or obvious required clauses from the proposed rule batch.
        guard !lower.contains(" eller "), !lower.contains(" or ") else { return nil }
        if lower.contains("mellom") && (lower.contains("beskjed") || lower.contains("varsl")) &&
            !specs.contains(where: { $0.repeatDelaySeconds != nil }) { return nil }
        if ["maks sone", "maksimal pulssone", "maximum zone", "at most zone"].contains(where: { lower.contains($0) }) &&
            !specs.contains(where: { $0.maximumZone != nil }) { return nil }
        if ["under drag", "during efforts", "during intervals"].contains(where: { lower.contains($0) }) &&
            !specs.contains(where: { $0.scope == .effort }) { return nil }
        var result: [Rule] = []
        for spec in specs {
            guard triggers.contains(spec.trigger), (1...6).contains(spec.metrics.count),
                  Set(spec.metrics).count == spec.metrics.count,
                  spec.metrics.allSatisfy({ metrics.contains($0) }),
                  let interval = interval(spec, input: input) else { return nil }
            let activity = spec.activity ?? (spec.trigger.isStrengthEvent ? .strength : (availability.workoutActivity ?? .all))
            guard [.all, .running, .walking, .strength, .intervals].contains(activity),
                  availability.supports(spec.trigger, for: activity),
                  activity != .strength || spec.trigger.isStrengthEvent else { return nil }
            if spec.trigger.isStrengthEvent && activity != .strength { return nil }
            if spec.trigger.needsStructuredStep && activity == .strength { return nil }
            let available = ATHLTHCoachCommandSelection.available(
                activity: activity, structured: availability.hasStructuredSteps,
                routes: availability.hasDistanceGoal, distance: availability.supportsDistance
            )
            guard spec.metrics.allSatisfy({ available.contains($0) }),
                  let metric = spec.metrics.first else { return nil }
            if spec.metrics.contains(.personalRecord) && spec.trigger != .personalRecordConfirmed { return nil }
            if spec.metrics.contains(where: { [.ghostTimeDifference, .ghostDistanceDifference].contains($0) }) &&
                !spec.trigger.isGhostCondition { return nil }
            if let phases = spec.phases {
                guard !phases.isEmpty, Set(phases).count == phases.count,
                      availability.hasStructuredSteps, activity != .strength else { return nil }
            }
            if let scope = spec.scope, scope != .workout {
                // Effort/group scope is implemented for periodic readouts;
                // threshold rules may use effort scope as a work-only gate.
                guard availability.hasStructuredSteps, activity != .strength,
                      spec.trigger.isPeriodic || (scope == .effort && spec.trigger.supportsThresholdConditions) else { return nil }
            }
            if let selection = spec.selection, selection != .every {
                let selectable: [Rule.Trigger] = [.beforeNextStep, .stepStart, .stepEnd, .recoveryStart, .recoveryEnd]
                guard selectable.contains(spec.trigger) else { return nil }
            }
            var conditions = ATHLTHCoachTriggerConditions()
            if let duration = spec.sustainedSeconds {
                guard (1...300).contains(duration), seconds(input).contains(duration) else { return nil }
                conditions.sustainedSeconds = duration
            }
            if let delay = spec.repeatDelaySeconds {
                guard (1...1800).contains(delay), seconds(input).contains(delay) else { return nil }
                conditions.repeatDelaySeconds = delay
            }
            if let zone = spec.maximumZone {
                guard (1...5).contains(zone), integers(input).contains(zone) else { return nil }
                conditions.maximumZone = zone
            }
            guard conditions.isEmpty || spec.trigger.supportsThresholdConditions else { return nil }
            // The existing threshold engine requires actual fresh pulse,
            // and never accepts a missing sample as meeting the zone gate.
            var rule = Rule(trigger: spec.trigger, metric: metric, interval: interval,
                            additionalMetrics: spec.metrics.count > 1 ? Array(spec.metrics.dropFirst()) : nil)
            guard rule.validatedInterval == interval else { return nil }
            rule.activityFilter = activity == .all ? nil : activity
            rule.allowedPhases = spec.phases
            rule.scope = spec.scope == .workout ? nil : spec.scope
            rule.eventSelection = spec.selection == .every ? nil : spec.selection
            rule.triggerConditions = conditions.isEmpty ? nil : conditions
            guard !result.contains(where: { ATHLTHCoachRequestParser.same($0, rule) }) else { return nil }
            result.append(rule)
        }
        return result
    }

    static func decode(_ json: String, input: String,
                       availability: ATHLTHCoachTriggerAvailability) -> [Rule]? {
        guard json.utf8.count <= 16000, let data = json.data(using: .utf8) else { return nil }
        // Reject unknown keys instead of silently dropping unsupported logic
        // such as OR, a minimum pulse zone, or a second threshold.
        let keys: Set<String> = ["trigger", "interval", "metrics", "activity", "phases",
            "scope", "selection", "sustainedSeconds", "repeatDelaySeconds", "maximumZone"]
        guard let objects = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]],
              objects.allSatisfy({ Set($0.keys).isSubset(of: keys) }),
              let specs = try? JSONDecoder().decode([Spec].self, from: data) else { return nil }
        return validate(specs, input: input, availability: availability)
    }

    /// Offline deterministic path for explicitly separated simple reminders
    /// and the common periodic multi-metric request. Never discard conditions
    /// or interpret a complex request as a simpler one.
    static func offline(_ input: String, availability: ATHLTHCoachTriggerAvailability) -> [Rule]? {
        let clauses = input.split(whereSeparator: { $0 == ";" || $0.isNewline })
        guard (1...5).contains(clauses.count) else { return nil }
        var result: [Rule] = []
        for clause in clauses {
            let t = String(clause).trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = t.lowercased()
            let complex = ["bare", "kun ", "only", "if ", "hvis", " dersom", "minst", "maks", "under drag", "during", "utenfor", "tilbake", "sone", " eller ", " or ", " ikke ", "ikke ", "don't", "do not", "første", "siste", "first", "last"]
            guard !complex.contains(where: { lower.contains($0) }),
                  let intent = ATHLTHCoachRequestParser.intent(t),
                  var rule = ATHLTHCoachRequestParser.rule(t, intent: intent, availability: availability) else { return nil }
            if intent == .everyTime || intent == .everyDistance {
                var requested: [Rule.Metric] = []
                if lower.contains("puls") || lower.contains("heart rate") { requested.append(.heartRate) }
                if lower.contains("tempo") || lower.contains("pace") { requested.append(.averagePace) }
                if lower.contains("distanse") || lower.contains("hvor langt") || lower.contains("distance") { requested.append(.distance) }
                if lower.contains("hvor lenge") || lower.contains("elapsed") { requested.append(.elapsedTime) }
                if lower.contains("motiver") || lower.contains("motivasjon") || lower.contains("encourag") { requested.append(.motivation) }
                if lower.contains("drikke") || lower.contains("hydration") || lower.contains("drink") { requested.append(.hydrationReminder) }
                if lower.contains(" og ") || lower.contains(" and ") {
                    guard requested.count >= 2 else { return nil }
                }
                if let first = requested.first {
                    rule.metric = first
                    rule.additionalMetrics = requested.count > 1 ? Array(requested.dropFirst()) : nil
                }
            } else if lower.contains(" og ") || lower.contains(" and ") { return nil }
            let available = ATHLTHCoachCommandSelection.available(
                activity: rule.activityFilter ?? .all, structured: availability.hasStructuredSteps,
                routes: availability.hasDistanceGoal, distance: availability.supportsDistance
            )
            guard rule.selectedMetrics.allSatisfy({ available.contains($0) }),
                  !result.contains(where: { ATHLTHCoachRequestParser.same($0, rule) }) else { return nil }
            result.append(rule)
        }
        return result
    }
}

struct ATHLTHCoachRequestView: View {
    @Binding var rules: [ATHLTHAudioCoachRule]
    let availability: ATHLTHCoachTriggerAvailability
    var showSaved = false
    var protectedRuleIDs: Set<UUID> = []
    @State private var request = ""
    @State private var proposals: [ATHLTHAudioCoachRule] = []
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
                    task?.cancel(); generation = UUID(); loading = false; proposals = []; status = nil
                }
            Button(action: search) {
                HStack {
                    if loading { ProgressView() }
                    Text(tr("Create suggestion", "Lag forslag"))
                }.frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(loading || request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if !proposals.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(tr("Review your suggestions", "Se gjennom forslagene")).font(.headline)
                    ForEach(proposals) { proposal in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top) {
                                Text(proposal.trigger.summary(interval: proposal.validatedInterval)).font(.headline)
                                Spacer(minLength: 0)
                                Button {
                                    proposals.removeAll { $0.id == proposal.id }
                                } label: {
                                    Image(systemName: "xmark.circle").frame(width: 44, height: 44)
                                }.buttonStyle(.plain).accessibilityLabel(tr("Remove suggestion", "Fjern forslag"))
                            }
                            Text(proposal.selectedMetrics.map(\.title).joined(separator: " · ")).font(.subheadline)
                            if let conditions = proposal.triggerConditions {
                                Text(conditions.summary).font(.subheadline)
                            }
                            if let phases = proposal.allowedPhases {
                                Text(tr("Only in: ", "Kun i: ") + phases.map(\.title).joined(separator: ", ")).font(.caption)
                            }
                            if let scope = proposal.scope {
                                Text(scope.title).font(.caption)
                            }
                            if let selection = proposal.eventSelection {
                                Text(selection.title).font(.caption)
                            }
                            if let activity = proposal.activityFilter {
                                Text(activity.title).font(.caption)
                            }
                            if proposal.trigger == .beforeEffort {
                                Text(tr("Only when time to the next effort is known.", "Bare når tiden frem til neste drag er kjent.")).font(.caption)
                            }
                            if let sample = ATHLTHCoachCommandSelection.example(for: proposal,
                                activity: proposal.activityFilter ?? .all,
                                norwegian: tr("en", "no") == "no") {
                                Text(tr("Example: ", "Eksempel: ") + sample)
                                    .font(.caption).foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            }
                        }
                        .padding(10)
                        .background(.white, in: RoundedRectangle(cornerRadius: 10))
                    }
                    let additions = proposals.filter { proposed in
                        !rules.contains(where: { ATHLTHCoachRequestParser.same($0, proposed) && $0.isEnabled })
                    }
                    Button {
                        guard rules.count + additions.count <= 20 else { return }
                        rules.append(contentsOf: additions)
                        status = additions.isEmpty ? tr("Already added.", "Disse beskjedene finnes allerede.") :
                            tr("Reminders added.", "Beskjedene er lagt til.")
                        proposals = []
                    } label: {
                        Label(tr("Add reminders", "Legg til beskjeder"), systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.borderedProminent).disabled(rules.count + additions.count > 20)
                    if rules.count + additions.count > 20 {
                        Text(tr("Maximum 20 rules. Remove a suggestion or an old rule.", "Maks 20 regler. Fjern et forslag eller en gammel regel.")).font(.caption)
                    }
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
        let input = request.trimmingCharacters(in: .whitespacesAndNewlines)
        proposals = []; status = nil
        guard !input.isEmpty, input.count <= 1200 else {
            status = tr("Describe up to five reminders in 1200 characters.", "Beskriv opptil fem beskjeder med maks 1200 tegn.")
            return
        }
        task?.cancel()
        loading = true
        let token = UUID(); generation = token
        let capabilities = availability
        task = Task { @MainActor in
            let generated = await ATHLTHIntelligenceEngine.localAudioCoachRequestRules(input, availability: capabilities)
            guard !Task.isCancelled, generation == token else { return }
            loading = false
            proposals = generated ?? ATHLTHCoachAdvancedRequest.offline(input, availability: capabilities) ?? []
            if proposals.isEmpty {
                status = tr("No complete supported suggestion. Describe the reminder more precisely or use Advanced.",
                    "Fant ikke et fullstendig støttet forslag. Beskriv ønsket mer presist eller bruk Avansert.")
            }
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

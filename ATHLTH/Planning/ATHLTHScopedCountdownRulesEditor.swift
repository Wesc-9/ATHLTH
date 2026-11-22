import SwiftUI

/// Shared editor mounted ONLY inside Audio Coach; no countdown controls are
/// added to exercise, phase, group, or workout builders.
struct ATHLTHScopedCountdownRulesEditor: View {
    @Binding var rules: [ATHLTHCoachBoundaryCountdownRule]?
    var strengthOnly = false

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    private func binding<Value>(
        at index: Int, keyPath: WritableKeyPath<ATHLTHCoachBoundaryCountdownRule, Value>,
        fallback: Value
    ) -> Binding<Value> {
        Binding(
            get: {
                guard let list = rules, list.indices.contains(index) else { return fallback }
                return list[index][keyPath: keyPath]
            },
            set: { value in
                guard var list = rules, list.indices.contains(index) else { return }
                list[index][keyPath: keyPath] = value
                rules = list
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(tr("Countdowns before transitions", "Nedtelling før overganger"))
                .font(.headline)
            Text(tr(
                "Create independent rules for each effort, section, group, or the end of a planned session. Before-start cues are counted during the preceding timed segment. Numbers follow the actual timer; open-ended and distance targets are never estimated.",
                "Lag separate regler for hvert drag, deløkt, gruppe eller slutten på en planlagt økt. Før-start telles i den foregående tidsstyrte delen. Tallene følger faktisk klokke; åpne eller distansestyrte mål blir aldri gjettet."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)

            ForEach(0..<(rules?.count ?? 0), id: \.self) { index in
                countdownRuleCard(at: index)
            }

            Button {
                guard (rules?.count ?? 0) < 20 else { return }
                var list = rules ?? []
                list.append(ATHLTHCoachBoundaryCountdownRule())
                rules = list
            } label: {
                Label(tr("New countdown rule", "Ny nedtellingsregel"),
                      systemImage: "plus.circle")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled((rules?.count ?? 0) >= 20)

            if strengthOnly {
                Text(tr(
                    "For strength, exact timing is available for timed sets and timed training modes such as EMOM/AMRAP. Ordinary repetition-based sets have no known end time.",
                    "For styrke er presis tid tilgjengelig for tidsstyrte sett og moduser som EMOM/AMRAP. Vanlige repetisjonssett har ingen kjent sluttid."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func countdownRuleCard(at index: Int) -> some View {
        if let rules, rules.indices.contains(index) {
            let rule = rules[index]
            VStack(alignment: .leading, spacing: 10) {
                ruleHeader(at: index)
                ruleSelectors(at: index, scope: rule.scope)
                ruleFooter(for: rule)
            }
            .padding(12)
            .background(ATHLTHPlanDesign.surface,
                        in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(ATHLTHPlanDesign.outline, lineWidth: 0.8)
            }
        }
    }

    private func ruleHeader(at index: Int) -> some View {
        HStack(spacing: 8) {
            Toggle(tr("Active", "Aktiv"), isOn:
                binding(at: index, keyPath: \.enabled, fallback: true))
            Spacer()
            Button(role: .destructive) {
                guard var list = rules, list.indices.contains(index) else { return }
                list.remove(at: index)
                rules = list
            } label: {
                Image(systemName: "trash").frame(width: 36, height: 36)
            }
        }
    }

    private func ruleSelectors(
        at index: Int, scope: ATHLTHCoachBoundaryCountdownRule.Scope
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(tr("Applies to", "Gjelder for"), selection:
                binding(at: index, keyPath: \.scope, fallback: .step)) {
                ForEach(ATHLTHCoachBoundaryCountdownRule.Scope.allCases) { value in
                    Text(value.title).tag(value)
                }
            }
            .onChange(of: scope) { _, newScope in
                if newScope == .plannedWorkout {
                    binding(at: index, keyPath: \.boundary,
                            fallback: .ends).wrappedValue = .ends
                }
            }

            Picker(tr("Countdown", "Nedtelling"), selection:
                binding(at: index, keyPath: \.boundary, fallback: .ends)) {
                ForEach(ATHLTHCoachBoundaryCountdownRule.Boundary.allCases) { edge in
                    if scope != .plannedWorkout || edge == .ends {
                        Text(edge.title).tag(edge)
                    }
                }
            }
            if scope == .section && !strengthOnly {
                sectionFilterPicker(at: index)
            }
            Picker(tr("Count from", "Start å telle fra"), selection:
                binding(at: index, keyPath: \.seconds, fallback: 10)) {
                ForEach(ATHLTHCoachSecondCountdown.offeredLengths, id: \.self) { seconds in
                    Text("\(seconds) s").tag(seconds)
                }
            }
            Picker(tr("After the last number", "Etter siste tall"), selection:
                binding(at: index, keyPath: \.after, fallback: .numbersOnly)) {
                ForEach(ATHLTHCoachCountdownAfter.allCases) { after in
                    Text(after.title).tag(after)
                }
            }
        }
    }

    private func sectionFilterPicker(at index: Int) -> some View {
        Picker(tr("Section", "Deløkt"), selection:
            binding(at: index, keyPath: \.sectionFilter, fallback: nil)) {
            Text(tr("All sections", "Alle deløkter")).tag(String?.none)
            Text(tr("Warm-up", "Oppvarming")).tag(String?.some("warmup"))
            Text(tr("Main section", "Hoveddel")).tag(String?.some("main"))
            Text(tr("Cooldown", "Nedjogging")).tag(String?.some("cooldown"))
        }
    }

    private func ruleFooter(for rule: ATHLTHCoachBoundaryCountdownRule) -> some View {
        Text(rule.scope == .plannedWorkout
            ? tr("The planned session must have a timed ending. Recording may continue afterwards.",
                 "Den planlagte økten må ha en tidsbestemt slutt. Registreringen kan fortsette etterpå.")
            : tr("A spoken countdown is triggered only when the exact next boundary is known.",
                 "Nedtelling starter bare når neste overgang har en kjent tidsfrist."))
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

}

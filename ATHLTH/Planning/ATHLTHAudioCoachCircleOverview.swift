import SwiftUI

/// The premium, athlete-owned Audio Coach workspace. Coach groups are named
/// by their creator, never inferred from workout phases. They are presentation
/// containers for the existing Watch/iPhone triggers, not a second cue engine.
struct ATHLTHAudioCoachCircleOverview: View {
    @EnvironmentObject private var settings: AppSettingsStore

    @Binding var draft: AudioCoachDraft
    @Binding var selectedProfileName: String?
    let showStructuredOptions: Bool
    let showRouteOptions: Bool
    let onEditRule: (UUID) -> Void
    let onEditOption: (ATHLTHAudioCoachOption) -> Void
    let onShowProfiles: () -> Void
    let onSaveAsNew: () -> Void
    let onUseStandard: () -> Void
    let onAddTrigger: (UUID) -> Void
    let onShowAdvanced: () -> Void

    @State private var expandedGroups: Set<UUID> = []
    @State private var showingGroupNameEditor = false
    @State private var editingGroupID: UUID?
    @State private var groupNameInput = ""
    @State private var showingLegacyOptions = false

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    private var gold: Color { ATHLTHPlanDesign.accentInk }
    private var ink: Color { ATHLTHPlanDesign.ink }
    private var dim: Color { ATHLTHPlanDesign.secondaryInk }

    private var activeTitle: String {
        guard let selectedProfileName, !selectedProfileName.isEmpty else {
            return tr("Standard", "Standard")
        }
        return selectedProfileName
    }

    private var activeMessageCount: Int {
        draft.customRules.filter(\.isEnabled).count +
        ATHLTHAudioCoachOption.allCases.filter { $0.isActive(in: draft) &&
            $0.isVisible(route: showRouteOptions, structured: showStructuredOptions)
        }.count
    }

    private var ungroupedRules: [ATHLTHAudioCoachRule] {
        let assigned = Set(draft.coachGroups.flatMap(\.ruleIDs))
        return draft.customRules.filter { !assigned.contains($0.id) }
    }

    private var legacyOptions: [ATHLTHAudioCoachOption] {
        let assigned = Set(draft.coachGroups.flatMap(\.optionIDs))
        let primary: [ATHLTHAudioCoachOption] = [
            .distanceUpdates, .timedUpdates, .motivation, .targetZoneCoach,
            .randomEncouragement, .scopedCountdowns, .workoutStart,
            .pauseResume, .workoutFinish, .currentStep
        ]
        return primary.filter {
            !assigned.contains($0.rawValue) &&
            $0.isVisible(route: showRouteOptions, structured: showStructuredOptions) &&
            $0.isActive(in: draft)
        }
    }

    private func cycleTemplate(_ step: Int) {
        let profiles = settings.audioCoachProfiles
        let current = selectedProfileName.flatMap { name in
            profiles.firstIndex(where: { $0.name == name })
        }.map { $0 + 1 } ?? 0
        let next = (current + step + profiles.count + 1) % (profiles.count + 1)
        if next == 0 {
            onUseStandard()
        } else {
            let profile = profiles[next - 1]
            draft.load(profile: profile)
            selectedProfileName = profile.name
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AUDIO COACH")
                        .font(.caption.weight(.bold))
                        .tracking(2)
                        .foregroundStyle(gold)
                    Text(tr("Your personal voice guidance", "Din personlige stemmeveiledning"))
                        .font(.caption)
                        .foregroundStyle(dim)
                }
                Spacer(minLength: 0)
                Button(action: onShowProfiles) {
                    Image(systemName: "square.3.layers.3d")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .background(ATHLTHPlanDesign.selectedSurface, in: Circle())
                }
                .accessibilityLabel(tr("Coach templates", "Coach-maler"))
                .accessibilityIdentifier("athlth-coach-templates-icon")
                Button(action: onSaveAsNew) {
                    Image(systemName: "bookmark.badge.plus")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .background(ATHLTHPlanDesign.selectedSurface, in: Circle())
                }
                .accessibilityLabel(tr("Save new template", "Lagre som ny mal"))
                .accessibilityIdentifier("athlth-coach-save-template-icon")
            }

            HStack(spacing: 8) {
                Button { cycleTemplate(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                        .frame(width: 40, height: 56)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(tr("Previous template", "Forrige mal"))
                Spacer(minLength: 0)
                ZStack {
                    Circle()
                        .stroke(gold.opacity(0.12), lineWidth: 13)
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [gold.opacity(0.3), gold, gold.opacity(0.7), gold],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                    Circle()
                        .stroke(ATHLTHPlanDesign.warmDivider, lineWidth: 1)
                        .padding(12)
                    VStack(spacing: 8) {
                        Image(systemName: "waveform")
                            .font(.title2)
                            .foregroundStyle(gold)
                        Text(tr("ACTIVE TEMPLATE", "AKTIV MAL"))
                            .font(.caption2.weight(.bold))
                            .tracking(1.4)
                            .foregroundStyle(dim)
                        Text(activeTitle)
                            .font(.system(size: 24, weight: .medium, design: .serif))
                            .foregroundStyle(ink)
                            .lineLimit(2)
                            .minimumScaleFactor(0.72)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                        Text(tr("\(draft.coachGroups.count) groups", "\(draft.coachGroups.count) grupper"))
                            .font(.caption)
                            .foregroundStyle(dim)
                    }
                }
                .frame(width: 210, height: 210)
                .accessibilityIdentifier("athlth-coach-template-circle")
                Spacer(minLength: 0)
                Button { cycleTemplate(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.title3.weight(.semibold))
                        .frame(width: 40, height: 56)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(tr("Next template", "Neste mal"))
            }
            .foregroundStyle(gold)

            HStack {
                Text(tr("COACH GROUPS", "COACH-GRUPPER"))
                    .font(.caption.weight(.bold))
                    .tracking(1.9)
                    .foregroundStyle(gold)
                Spacer()
                Text(tr("\(activeMessageCount) active", "\(activeMessageCount) aktive"))
                    .font(.caption)
                    .foregroundStyle(dim)
            }

            if draft.coachGroups.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text(tr("Make your Coach your own", "Lag din personlige coach"))
                        .font(.headline)
                        .foregroundStyle(ink)
                    Text(tr("Create a group, choose its name and add as many triggers as you need.",
                            "Opprett en gruppe, gi den et eget navn og legg til triggerne du ønsker."))
                        .font(.subheadline)
                        .foregroundStyle(dim)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 20))
            }

            VStack(spacing: 9) {
                ForEach(draft.coachGroups) { group in
                    coachGroupCard(group)
                }
            }

            Button {
                editingGroupID = nil
                groupNameInput = ""
                showingGroupNameEditor = true
            } label: {
                Label(tr("Add coach group", "Legg til coach-gruppe"),
                      systemImage: "plus.circle")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(gold)
            .accessibilityIdentifier("athlth-coach-add-group")

            if !ungroupedRules.isEmpty || !legacyOptions.isEmpty {
                DisclosureGroup(isExpanded: $showingLegacyOptions) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr(
                            "Existing settings keep working. Add new triggers inside the named groups above.",
                            "Eksisterende varsler fungerer fortsatt. Legg til nye triggere i de navngitte gruppene over."
                        ))
                        .font(.caption)
                        .foregroundStyle(dim)
                        ForEach(ungroupedRules) { rule in
                            Button {
                                onEditRule(rule.id)
                            } label: {
                                rowLabel(rule.beforeEndSeconds.map {
                                    tr("\($0 / 60) min before finish", "\($0 / 60) min før slutt")
                                } ?? rule.selectedMetrics.map(\.title).joined(separator: " · "),
                                symbol: "waveform")
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(legacyOptions) { option in
                            Button { onEditOption(option) } label: {
                                rowLabel(option.title, symbol: option.symbol)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 9)
                } label: {
                    Text(tr("Other active messages", "Andre aktive beskjeder"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                }
                .padding(16)
                .background(.white, in: RoundedRectangle(cornerRadius: 18))
            }

            Button(action: onShowAdvanced) {
                Label(tr("Voice, music and advanced settings", "Stemme, musikk og avanserte valg"),
                      systemImage: "slider.horizontal.3")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(gold)
        }
        .alert(
            editingGroupID == nil
                ? tr("New coach group", "Ny coach-gruppe")
                : tr("Rename coach group", "Endre navn på coach-gruppe"),
            isPresented: $showingGroupNameEditor
        ) {
            TextField(tr("Group name", "Gruppenavn"), text: $groupNameInput)
            Button(tr("Save", "Lagre")) {
                saveGroupName()
            }
            Button(tr("Cancel", "Avbryt"), role: .cancel) {}
        } message: {
            Text(tr("Choose a name that makes sense to you.",
                    "Du bestemmer selv hva gruppen skal hete."))
        }
        .accessibilityIdentifier("athlth-audio-coach-circle-overview")
    }

    private func coachGroupCard(_ group: ATHLTHAudioCoachGroup) -> some View {
        let rules = group.ruleIDs.compactMap { id in
            draft.customRules.first(where: { $0.id == id })
        }
        let options = group.optionIDs.compactMap(ATHLTHAudioCoachOption.init(rawValue:))
        let expanded = expandedGroups.contains(group.id)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if expanded { expandedGroups.remove(group.id) }
                        else { expandedGroups.insert(group.id) }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "waveform")
                            .foregroundStyle(gold)
                            .frame(width: 34, height: 34)
                            .background(ATHLTHPlanDesign.selectedSurface, in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(group.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ink)
                            Text(tr(
                                "\(rules.count + options.count) triggers",
                                "\(rules.count + options.count) triggere"
                            ))
                            .font(.caption)
                            .foregroundStyle(dim)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(dim)
                    }
                    .frame(minHeight: 57)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Menu {
                    Button(tr("Rename", "Endre navn"), systemImage: "pencil") {
                        editingGroupID = group.id
                        groupNameInput = group.name
                        showingGroupNameEditor = true
                    }
                    Button(tr("Duplicate", "Dupliser"), systemImage: "square.on.square") {
                        duplicateGroup(group)
                    }
                    Button(tr("Move up", "Flytt opp"), systemImage: "arrow.up") {
                        moveGroup(group.id, by: -1)
                    }
                    Button(tr("Move down", "Flytt ned"), systemImage: "arrow.down") {
                        moveGroup(group.id, by: 1)
                    }
                    Button(tr("Delete", "Slett"), systemImage: "trash", role: .destructive) {
                        removeGroup(group)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .foregroundStyle(dim)
                        .frame(width: 36, height: 44)
                }
                .accessibilityLabel(tr("Group options", "Gruppevalg"))
            }

            if expanded {
                Divider().overlay(ATHLTHPlanDesign.warmDivider)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(rules) { rule in
                        Button { onEditRule(rule.id) } label: {
                            rowLabel(
                                rule.beforeEndSeconds.map {
                                    tr("\($0 / 60) min before finish", "\($0 / 60) min før slutt")
                                } ?? (rule.trigger == .time
                                      ? tr("Every \(rule.validatedInterval) seconds",
                                           "Hvert \(rule.validatedInterval) sekund")
                                      : tr("Every \(rule.validatedInterval) m",
                                           "Hver \(rule.validatedInterval) m")),
                                symbol: rule.beforeEndSeconds == nil ? "waveform" : "flag",
                                detail: rule.selectedMetrics.map(\.title).joined(separator: " · ")
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(options) { option in
                        Button { onEditOption(option) } label: {
                            rowLabel(option.title, symbol: option.symbol,
                                     detail: option.detail(in: draft))
                        }
                        .buttonStyle(.plain)
                    }

                    Button { onAddTrigger(group.id) } label: {
                        Label(tr("Add trigger", "Legg til trigger"),
                              systemImage: "plus.circle")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(gold)
                    .disabled(draft.customRules.count >= 20 &&
                              group.optionIDs.count >= ATHLTHAudioCoachOption.allCases.count)
                    .accessibilityIdentifier("athlth-coach-add-trigger")
                }
                .padding(.top, 11)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20)
            .stroke(ATHLTHPlanDesign.warmDivider, lineWidth: 1))
    }

    private func rowLabel(_ title: String, symbol: String, detail: String? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(gold)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ink)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(dim)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(dim)
        }
        .frame(minHeight: 46)
        .contentShape(Rectangle())
    }

    private func saveGroupName() {
        let name = String(groupNameInput.trimmingCharacters(
            in: .whitespacesAndNewlines).prefix(60))
        guard !name.isEmpty else { return }
        if let editingGroupID,
           let index = draft.coachGroups.firstIndex(where: { $0.id == editingGroupID }) {
            draft.coachGroups[index].name = name
        } else {
            let group = ATHLTHAudioCoachGroup(name: name)
            draft.coachGroups.append(group)
            expandedGroups.insert(group.id)
        }
        groupNameInput = ""
        editingGroupID = nil
    }

    private func removeGroup(_ group: ATHLTHAudioCoachGroup) {
        let ids = Set(group.ruleIDs)
        draft.customRules.removeAll { ids.contains($0.id) }
        draft.coachGroups.removeAll { $0.id == group.id }
        expandedGroups.remove(group.id)
    }

    private func duplicateGroup(_ group: ATHLTHAudioCoachGroup) {
        var copy = ATHLTHAudioCoachGroup(
            name: tr("\(group.name) copy", "\(group.name) kopi"))
        for id in group.ruleIDs where draft.customRules.count < 20 {
            guard var rule = draft.customRules.first(where: { $0.id == id }) else {
                continue
            }
            rule.id = UUID()
            draft.customRules.append(rule)
            copy.ruleIDs.append(rule.id)
        }
        copy.optionIDs = group.optionIDs
        draft.coachGroups.append(copy)
        expandedGroups.insert(copy.id)
    }

    private func moveGroup(_ id: UUID, by delta: Int) {
        guard let index = draft.coachGroups.firstIndex(where: { $0.id == id }),
              draft.coachGroups.indices.contains(index + delta) else { return }
        draft.coachGroups.swapAt(index, index + delta)
    }
}

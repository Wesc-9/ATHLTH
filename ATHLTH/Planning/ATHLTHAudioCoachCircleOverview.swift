import SwiftUI

/// The premium, athlete-owned Audio Coach workspace. Coach groups are named
/// by their creator, never inferred from workout phases. They are presentation
/// containers for the existing Watch/iPhone triggers, not a second cue engine.
struct ATHLTHAudioCoachCircleOverview: View {
     @Binding var draft: AudioCoachDraft
    @Binding var selectedProfileName: String?
    let showStructuredOptions: Bool
    let showRouteOptions: Bool
    let onEditRule: (UUID) -> Void
    let onEditOption: (ATHLTHAudioCoachOption) -> Void
    let onShowProfiles: () -> Void
    let onCreateTemplate: () -> Void
    let onSaveTemplate: () -> Void
    let onSwitchTemplate: (Int) -> Void
    let previousTemplateName: String?
    let nextTemplateName: String?
    let onResetStandard: () -> Void
    let isDirty: Bool
    let onAddCommand: (UUID) -> Void
    let onEditGroupTrigger: (UUID) -> Void
    let onMoveCommand: (String, UUID?) -> Bool
    let onAddGroup: () -> Void
    let onAddGeneralCommand: () -> Void

    @State private var expandedGroups: Set<UUID> = []
    @State private var showingGroupNameEditor = false
    @State private var editingGroupID: UUID?
    @State private var groupNameInput = ""
    @State private var showingLegacyOptions = true

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
        ATHLTHAudioCoachOption.allCases.filter {
            $0 != .customAnnouncements &&
            $0.isActive(in: draft) &&
            $0.isVisible(route: showRouteOptions, structured: showStructuredOptions)
        }.count
    }

    // Built-in messages predate named groups. Present them as one virtual
    // group without rewriting the Watch payload or duplicating spoken cues.
    private var visibleGroupCount: Int {
        draft.coachGroups.count +
            ((!legacyOptions.isEmpty || !ungroupedRules.isEmpty) ? 1 : 0)
    }

    private var ungroupedRules: [ATHLTHAudioCoachRule] {
        let assigned = Set(draft.coachGroups.flatMap(\.ruleIDs))
        return draft.customRules.filter { !assigned.contains($0.id) }
    }

    private var legacyOptions: [ATHLTHAudioCoachOption] {
        let assigned = Set(draft.coachGroups.flatMap(\.optionIDs))
        // Include every enabled built-in option, including the individual
        // spoken values used by Standard (distance, elapsed time, pace, etc.).
        return ATHLTHAudioCoachOption.allCases.filter {
            $0 != .customAnnouncements &&
            !assigned.contains($0.rawValue) &&
            $0.isVisible(route: showRouteOptions, structured: showStructuredOptions) &&
            $0.isActive(in: draft)
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
                Button(action: onCreateTemplate) {
                    Image(systemName: "plus")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .background(ATHLTHPlanDesign.selectedSurface, in: Circle())
                }
                .accessibilityLabel(tr("New empty template", "Lag ny tom mal"))
                .accessibilityIdentifier("athlth-coach-new-template-icon")
                Button(action: onSaveTemplate) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .background(ATHLTHPlanDesign.selectedSurface, in: Circle())
                }
                .accessibilityLabel(tr("Save template", "Lagre mal"))
                .accessibilityIdentifier("athlth-coach-save-template-icon")
            }

            HStack(spacing: 8) {
                Button { onSwitchTemplate(-1) } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.headline.weight(.semibold))
                        Text(previousTemplateName ?? " ")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(dim)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(width: 49, height: 78)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(tr("Previous template", "Forrige mal"))
                .disabled(previousTemplateName == nil)
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
                        Text(tr("\(visibleGroupCount) groups", "\(visibleGroupCount) grupper"))
                            .font(.caption)
                            .foregroundStyle(dim)
                    }
                }
                .frame(width: 210, height: 210)
                .accessibilityIdentifier("athlth-coach-template-circle")
                .overlay(alignment: .topTrailing) {
                    if isDirty {
                        Circle()
                            .fill(gold)
                            .frame(width: 9, height: 9)
                            .padding(17)
                            .accessibilityLabel(tr("Unsaved changes", "Ulagrede endringer"))
                    }
                }
                Spacer(minLength: 0)
                Button { onSwitchTemplate(1) } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.headline.weight(.semibold))
                        Text(nextTemplateName ?? " ")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(dim)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(width: 49, height: 78)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(tr("Next template", "Neste mal"))
                .disabled(nextTemplateName == nil)
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

            if draft.coachGroups.isEmpty && legacyOptions.isEmpty &&
                ungroupedRules.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text(tr("Make your Coach your own", "Lag din personlige coach"))
                        .font(.headline)
                        .foregroundStyle(ink)
                    Text(tr("Choose a trigger and select what Coach will say together.",
                            "Velg en trigger og hva coachen skal si samlet."))
                        .font(.subheadline)
                        .foregroundStyle(dim)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 20))
            }

            VStack(spacing: 9) {
                if !legacyOptions.isEmpty || !ungroupedRules.isEmpty {
                    builtInCoachGroupCard
                }
                ForEach(draft.coachGroups) { group in
                    coachGroupCard(group)
                }
            }

            HStack(spacing: 10) {
                Button(action: onAddGroup) {
                    Label(tr("Add coach group", "Legg til coach-gruppe"),
                          systemImage: "plus.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(gold)
                .accessibilityIdentifier("athlth-coach-add-group")

                Button(action: onAddGeneralCommand) {
                    Label(tr("Add command", "Legg til kommando"),
                          systemImage: "waveform.badge.plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.bordered)
                .tint(gold)
                .accessibilityIdentifier("athlth-coach-add-general-command")
            }

            if selectedProfileName == nil {
                Button(action: onResetStandard) {
                    Label(tr("Restore original Standard", "Tilbakestill til opprinnelig Standard"),
                          systemImage: "arrow.counterclockwise")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(dim)
            }
        }
        .alert(
            tr("Rename coach group", "Endre navn på coach-gruppe"),
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

    /// The standard template has enabled commands but no stored named
    /// groups. Keep all of them visible under COACH-GRUPPER, editable in place.
    private var builtInCoachGroupCard: some View {
        DisclosureGroup(isExpanded: $showingLegacyOptions) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(legacyOptions) { option in
                    Button { onEditOption(option) } label: {
                        rowLabel(option.title, symbol: option.symbol,
                                 detail: option.detail(in: draft))
                    }
                    .buttonStyle(.plain)
                }
                ForEach(ungroupedRules) { rule in
                    ForEach(rule.selectedMetrics) { metric in
                        Button { onEditRule(rule.id) } label: {
                            rowLabel(
                                metric.title, symbol: "waveform",
                                detail: rule.trigger.summary(interval: rule.validatedInterval)
                            )
                        }
                        .buttonStyle(.plain)
                        .draggable("metric:\(rule.id.uuidString):\(metric.rawValue)")
                    }
                }
            }
            .padding(.top, 10)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .foregroundStyle(gold)
                    .frame(width: 34, height: 34)
                    .background(ATHLTHPlanDesign.selectedSurface, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("Standalone commands", "Enkeltkommandoer"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                    Text(tr(
                        "\(legacyOptions.count + ungroupedRules.count) settings",
                        "\(legacyOptions.count + ungroupedRules.count) innstillinger"
                    ))
                    .font(.caption)
                    .foregroundStyle(dim)
                }
            }
        }
        .tint(gold)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(ATHLTHPlanDesign.warmDivider, lineWidth: 1)
        }
        .accessibilityIdentifier("athlth-coach-standard-group")
    }

    private func coachGroupCard(_ group: ATHLTHAudioCoachGroup) -> some View {
        let rules = group.ruleIDs.compactMap { id in
            draft.customRules.first(where: { $0.id == id })
        }
        let options = group.optionIDs.compactMap(ATHLTHAudioCoachOption.init(rawValue:))
        let spokenValues = rules.reduce(0) { $0 + $1.selectedMetrics.count }
        let expanded = expandedGroups.contains(group.id)
        let displayTrigger = group.trigger ?? rules.first?.trigger
        let displayInterval = group.interval ?? rules.first?.interval
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
                            Text((displayTrigger?.summary(interval: displayInterval ?? 1) ??
                                  tr("No trigger", "Ingen trigger")) + " · " +
                                 tr("\(spokenValues + options.count) commands",
                                    "\(spokenValues + options.count) kommandoer"))
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
                    Button(tr("Edit group trigger", "Endre gruppens trigger"),
                           systemImage: "clock.arrow.circlepath") {
                        onEditGroupTrigger(group.id)
                    }
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
                    Button(tr("Delete group and commands", "Slett gruppe og kommandoer"), systemImage: "trash", role: .destructive) {
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
                        ForEach(rule.selectedMetrics) { metric in
                            Button { onEditRule(rule.id) } label: {
                                rowLabel(
                                    metric.title,
                                    symbol: rule.beforeEndSeconds == nil ? "waveform" : "flag",
                                    detail: rule.trigger.summary(interval: rule.validatedInterval)
                                )
                            }
                            .buttonStyle(.plain)
                            .draggable("metric:\(rule.id.uuidString):\(metric.rawValue)")
                        }
                    }
                    ForEach(options) { option in
                        Button { onEditOption(option) } label: {
                            rowLabel(option.title, symbol: option.symbol,
                                     detail: option.detail(in: draft))
                        }
                        .buttonStyle(.plain)
                    }

                    Button { onAddCommand(group.id) } label: {
                        Label(tr("Add command", "Legg til kommando"),
                              systemImage: "plus.circle")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(gold)
                    .disabled(draft.customRules.count >= 20 &&
                              group.optionIDs.count >= ATHLTHAudioCoachOption.allCases.count)
                    .accessibilityIdentifier("athlth-coach-add-command")
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
        .dropDestination(for: String.self) { items, _ in
            guard let item = items.first else { return false }
            return onMoveCommand(item, group.id)
        }
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
        guard let editingGroupID,
              let index = draft.coachGroups.firstIndex(where: { $0.id == editingGroupID })
        else { return }
        draft.coachGroups[index].name = name
        groupNameInput = ""
        self.editingGroupID = nil
    }

    private func removeGroup(_ group: ATHLTHAudioCoachGroup) {
        // A rule cannot remain without its group trigger when its group is removed.
        let ids = Set(group.ruleIDs)
        draft.customRules.removeAll { ids.contains($0.id) }
        for rawValue in group.optionIDs {
            if let option = ATHLTHAudioCoachOption(rawValue: rawValue) {
                option.setActive(false, in: &draft)
            }
        }
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
        // Built-in options have a single owner. Do not silently attach
        // them to two groups when duplicating an ordinary container.
        copy.trigger = group.trigger
        copy.interval = group.interval
        draft.coachGroups.append(copy)
        expandedGroups.insert(copy.id)
    }

    private func moveGroup(_ id: UUID, by delta: Int) {
        guard let index = draft.coachGroups.firstIndex(where: { $0.id == id }),
              draft.coachGroups.indices.contains(index + delta) else { return }
        draft.coachGroups.swapAt(index, index + delta)
    }
}

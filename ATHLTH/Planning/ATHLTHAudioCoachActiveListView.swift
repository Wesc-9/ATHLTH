import SwiftUI
import MapKit
import CoreLocation

/// One compact editor for workout-specific and default Audio Coach settings.
/// Only enabled items are displayed; options not in use live in Add.
struct ATHLTHAudioCoachActiveListView: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @Binding var draft: AudioCoachDraft
    let showRouteOptions: Bool
    let showStructuredOptions: Bool
    var globalScope: Bool = false

    // Every new workout opens the uncluttered Basic screen; the athlete's
    // actual Coach settings and profiles remain unchanged.
    @State private var editorMode = "basic"
    @State private var showingCatalogue = false
    @State private var showingVoice = false
    @State private var showingProfiles = false
    @State private var editingOption: ATHLTHAudioCoachOption?
    @State private var selectedRule: SelectedRule?
    @State private var expandedCoachGroups: Set<UUID> = []

    private struct SelectedRule: Identifiable {
        let id: UUID
    }
    @State private var nextEditor: ATHLTHAudioCoachOption?
    @State private var pendingRemoval: ATHLTHAudioCoachOption?
    @State private var confirmReplaceWithStandard = false
    @State private var profileName = ""
    @State private var selectedProfileName: String?
    @State private var pendingProfileAction: ProfileAction?
    @State private var ruleSetName = ""
    @State private var phraseText = ""
    @State private var newRuleTrigger: ATHLTHAudioCoachRule.Trigger = .distance
    @State private var newRuleScope: ATHLTHAudioCoachRule.Scope = .workout
    @State private var newRuleMetric: ATHLTHAudioCoachRule.Metric = .pace
    @State private var newRuleAdditionalMetrics: [ATHLTHAudioCoachRule.Metric] = []
    @State private var newRuleInterval = 1_000

    @State private var placeQuery = ""
    @State private var placeSide: ATHLTHCoachLandmarkSide = .unspecified
    @State private var placeKind: ATHLTHCoachLandmarkKind = .ordinary
    @State private var placeResults: [PlaceCandidate] = []
    @State private var searchingPlaces = false
    @State private var placeError: String?

    private enum ProfileAction {
        case replace(UUID)
        case delete(UUID)
    }

    private struct PlaceCandidate: Identifiable {
        var id = UUID()
        var title: String
        var subtitle: String
        var latitude: Double
        var longitude: Double
    }

    private var timeSeconds: Binding<Int> {
        Binding(
            get: { draft.timeIntervalSeconds },
            set: { seconds in
                let valid = min(max(seconds, 15), 7_200)
                draft.timeIntervalSeconds = valid
                draft.timeIntervalMinutes = max(1, Int((Double(valid) / 60).rounded()))
            }
        )
    }

    private let bronze = ATHLTHPlanDesign.accentInk
    private let ink = ATHLTHPlanDesign.ink
    private let dim = ATHLTHPlanDesign.secondaryInk

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    // Periodic triggers and their payload belong to one announcement group,
    // not separate rows that appear to speak independently.
    private var activeOptions: [ATHLTHAudioCoachOption] {
        let bundled: Set<ATHLTHAudioCoachOption> = [
            .distanceUpdates, .timedUpdates, .distance, .elapsedTime,
            .averagePace, .clockTime, .heartRate
        ]
        return ATHLTHAudioCoachOption.allCases.filter { option in
            option.isVisible(route: showRouteOptions, structured: showStructuredOptions)
                && option.isActive(in: draft)
                && !bundled.contains(option)
                && option != .customAnnouncements
                && option != .motivation
        }
    }

    private var standardAnnouncementMetrics: [String] {
        var metrics: [String] = []
        if draft.announceDistance { metrics.append(tr("Distance", "Distanse")) }
        if draft.announceElapsedTime { metrics.append(tr("Elapsed time", "Medgått tid")) }
        if draft.announceAveragePace { metrics.append(tr("Average pace", "Gjennomsnittstempo")) }
        if draft.announceClockTime { metrics.append(tr("Clock time", "Klokkeslett")) }
        if draft.announceHeartRate { metrics.append(tr("Heart rate", "Puls")) }
        return metrics
    }

    private var hasStandardAnnouncements: Bool {
        draft.distanceTriggerEnabled || draft.timeTriggerEnabled
    }

    private var hasScheduledMotivation: Bool {
        draft.customRules.contains {
            $0.isEnabled && $0.selectedMetrics.contains(.motivation)
        }
    }

    private var activeAnnouncementCount: Int {
        activeOptions.count + draft.customRules.filter(\.isEnabled).count
            + (draft.smartPrompts.motivationEnabled && !hasScheduledMotivation ? 1 : 0)
            + (hasStandardAnnouncements ? (draft.distanceTriggerEnabled ? 1 : 0)
                + (draft.timeTriggerEnabled ? 1 : 0) : 0)
    }

    private func announcementGroupRow(
        title: String,
        detail: String,
        edit: @escaping () -> Void
    ) -> some View {
        Button(action: edit) {
            HStack(spacing: 11) {
                Image(systemName: "waveform.path")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(bronze)
                    .frame(width: 29)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(ink)
                    Text(detail).font(.caption).foregroundStyle(dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(dim)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var hasAdvancedConfiguration: Bool {
        draft.smartPrompts.intervalCountdownToRecoverySeconds != nil ||
        draft.smartPrompts.intervalCountdownFromRecoverySeconds != nil ||
        !(draft.smartPrompts.boundaryCountdownRules ?? []).isEmpty ||
        !draft.customRules.isEmpty ||
        draft.smartPrompts.coachingMode == .custom ||
        draft.smartPrompts.preferredHeartRateZone != nil ||
        draft.smartPrompts.measuredZoneAnnouncementIntervalSeconds != nil ||
        draft.smartPrompts.targetZoneVoiceAlertsEnabled != nil ||
        draft.smartPrompts.pushWhenBelowTargetPace == true ||
        draft.smartPrompts.pushWhenBelowTargetZone == true ||
        draft.smartPrompts.pushOnUnexpectedPaceDrop == true ||
        !draft.smartPrompts.customEncouragements.isEmpty ||
        !draft.smartPrompts.landmarks.isEmpty
    }

    private var inactiveOptions: [ATHLTHAudioCoachOption] {
        ATHLTHAudioCoachOption.allCases.filter {
            $0.isVisible(route: showRouteOptions, structured: showStructuredOptions)
                && !$0.isActive(in: draft)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            masterCard
            if draft.enabled {
                Picker(tr("Editor mode", "Redigeringsmodus"), selection: $editorMode) {
                    Text(tr("Basic", "Enkel")).tag("basic")
                    Text(tr("Advanced", "Avansert")).tag("advanced")
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("athlth-audio-coach-editor-mode")

                if editorMode == "basic" {
                    basicCard
                } else {
                    advancedCard
                }
                compactNavigationCard
            }
            Text(globalScope
                 ? tr("Defaults for new workouts. Saved workouts keep their own settings.",
                      "Standard for nye økter. Lagrede økter beholder sine egne innstillinger.")
                 : tr("These choices apply only to this workout. You can save them as a profile.",
                      "Valgene gjelder bare denne økten. Du kan lagre dem som en profil."))
                .font(.caption)
                .foregroundStyle(dim)
                .padding(.horizontal, 4)
        }
        .tint(bronze)
        .sheet(isPresented: $showingCatalogue, onDismiss: {
            if let nextEditor {
                editingOption = nextEditor
                self.nextEditor = nil
            }
        }) {
            catalogueSheet
        }
        .sheet(item: $selectedRule) { selection in
            NavigationStack {
                ScrollView {
                    ruleGroupEditor(selection.id)
                        .padding(16)
                }
                .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
                .navigationTitle(tr("Announcement group", "Varslingsgruppe"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(tr("Done", "Ferdig")) { selectedRule = nil }
                    }
                }
            }
            .presentationDetents([.large])
        }
        .sheet(item: $editingOption) { option in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 15) {
                        editorFields(for: option)
                    }
                    .padding(17)
                }
                .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
                .navigationTitle(option.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(tr("Done", "Ferdig")) { editingOption = nil }
                    }
                }
            }
            .presentationDetents([.large])
        }
        .alert(
            tr("Replace Coach settings?", "Erstatte coach-oppsett?"),
            isPresented: $confirmReplaceWithStandard
        ) {
            Button(tr("Use standard", "Bruk standard")) {
                draft.applySimpleAudioCoach()
                selectedProfileName = nil
            }
            Button(tr("Cancel", "Avbryt"), role: .cancel) {}
        } message: {
            Text(tr(
                "Your current rules will be replaced by the simple coach. Saved profiles will still be available.",
                "Aktive regler blir erstattet av enkel coach. Lagrede profiler er fortsatt tilgjengelige."
            ))
        }
        .sheet(isPresented: $showingVoice) { voiceSheet }
        .sheet(isPresented: $showingProfiles) { profilesSheet }
        .confirmationDialog(
            tr("Remove active setting?", "Fjerne aktivt valg?"),
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(tr("Remove", "Fjern"), role: .destructive) {
                if let pendingRemoval {
                    pendingRemoval.setActive(false, in: &draft)
                }
                pendingRemoval = nil
            }
            Button(tr("Cancel", "Avbryt"), role: .cancel) {
                pendingRemoval = nil
            }
        } message: {
            Text(tr(
                "This also removes the saved entries in this list from the current coach setup.",
                "Dette fjerner også innholdet i den valgte listen fra coach-oppsettet."
            ))
        }
    }

    private var masterCard: some View {
        ATHLTHPlanSurface(ghost: false) {
            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(bronze)
                    .frame(width: 44, height: 44)
                    .background(ATHLTHPlanDesign.selectedSurface,
                                in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Audio Coach")
                        .font(.headline)
                        .foregroundStyle(ink)
                    Text(draft.enabled
                        ? (globalScope
                            ? tr("On for new workouts", "På for nye økter")
                            : tr("Active for this workout", "Aktiv stemmeveiledning"))
                        : tr("Voice guidance is off", "Stemmeveiledning er av"))
                        .font(.caption)
                        .foregroundStyle(dim)
                }
                Spacer(minLength: 4)
                Toggle("Audio Coach", isOn: $draft.enabled)
                    .labelsHidden()
                    .tint(bronze)
                    .accessibilityIdentifier("athlth-audio-coach-enabled")
            }
        }
    }

    private var basicCard: some View {
        ATHLTHPlanSurface(ghost: false) {
            Label(tr("Coach, ready to go", "Coachen er klar"),
                  systemImage: "checkmark.circle")
                .font(.headline)
                .foregroundStyle(ink)
            if let selectedProfileName {
                Label(selectedProfileName, systemImage: "square.stack")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(bronze)
            }
            Text(hasAdvancedConfiguration
                ? tr(
                    "Your customized Coach setup is active. Open Advanced to see every rule, or choose the standard setup below.",
                    "Det tilpassede coach-oppsettet ditt er aktivt. Åpne Avansert for å se alle reglene, eller velg standardoppsettet nedenfor."
                )
                : tr(
                    "Start running with concise distance, time and pace updates, encouragement and a finish summary.",
                    "Løp med enkle oppdateringer om distanse, tid og tempo, oppmuntring og oppsummering ved mål."
                )
            )
            .font(.subheadline)
            .foregroundStyle(dim)
            VStack(alignment: .leading, spacing: 8) {
                if draft.distanceTriggerEnabled && draft.customRules.isEmpty {
                    Label(
                        ATHLTHAudioCoachOption.distanceUpdates.detail(in: draft),
                        systemImage: "point.bottomleft.forward.to.point.topright.scurvepath"
                    )
                }
                if draft.smartPrompts.motivationEnabled {
                    Label(tr("Motivational coaching", "Motivasjonssnakk"),
                          systemImage: "sparkles")
                }
                if draft.announceWorkoutComplete {
                    Label(tr("Finish summary", "Oppsummering ved mål"),
                          systemImage: "flag.checkered")
                }
                if !draft.customRules.isEmpty {
                    Label(tr("Custom rules are active", "Egne regler er aktive"),
                          systemImage: "waveform.badge.plus")
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(ink)
            .padding(.vertical, 5)

            HStack(spacing: 10) {
                Menu {
                    ForEach(settings.audioCoachProfiles) { profile in
                        Button(profile.name) {
                            draft.load(profile: profile)
                            selectedProfileName = profile.name
                            editorMode = "basic"
                        }
                    }
                } label: {
                    Label(tr("Use a saved profile", "Bruk lagret profil"),
                          systemImage: "square.stack")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(settings.audioCoachProfiles.isEmpty)
                .buttonStyle(.bordered)
                Button {
                    editorMode = "advanced"
                } label: {
                    Label(tr("Edit Coach", "Rediger coach"),
                          systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
            Button {
                if hasAdvancedConfiguration {
                    confirmReplaceWithStandard = true
                } else {
                    draft.applySimpleAudioCoach()
                    selectedProfileName = nil
                }
            } label: {
                Label(tr("Use recommended basic setup", "Bruk anbefalt enkel oppsett"),
                      systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity, minHeight: 45)
            }
            .buttonStyle(.borderedProminent)
            .tint(bronze)

            if activeOptions.count > 7 {
                Button {
                    editorMode = "advanced"
                } label: {
                    Label(tr("See all active choices", "Se alle aktive valg"),
                          systemImage: "slider.horizontal.3")
                }
                .font(.caption.weight(.medium))
            }
        }
    }

    private var advancedCard: some View {
        ATHLTHPlanSurface(ghost: false) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("ANNOUNCEMENTS", "VARSLINGSGRUPPER"))
                        .font(.caption2.weight(.bold)).tracking(1.4)
                        .foregroundStyle(bronze)
                    Text(tr("Your Audio Coach", "Dine coach-varsler"))
                        .font(.system(size: 20, weight: .semibold, design: .serif))
                        .foregroundStyle(ink)
                }
                Spacer()
                Text("\(activeAnnouncementCount)")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(bronze)
            }

            if activeAnnouncementCount == 0 {
                Text(tr("Create a coach message or choose a preset to get started.",
                        "Opprett en coach-beskjed eller velg et ferdig oppsett."))
                    .font(.subheadline).foregroundStyle(dim)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(tr("Choose what activates the coach", "Velg hva som aktiverer coachen"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
                Text(tr(
                    "Distance and time are only two options. Use event alerts for heart-rate zones, pace, workout phases and interval transitions.",
                    "Tid og distanse er bare to muligheter. Under hendelsesvarsler finner du pulssoner, tempo, øktfaser og intervalloverganger."
                ))
                .font(.caption)
                .foregroundStyle(dim)
            }

            VStack(spacing: 0) {
                if hasStandardAnnouncements {
                    if draft.distanceTriggerEnabled {
                        announcementGroupRow(
                            title: tr("Every distance", "Etter distanse"),
                            detail: "\(Int((draft.distanceIntervalKilometers * 1_000).rounded())) m · " +
                                standardAnnouncementMetrics.joined(separator: ", ")
                        ) { editingOption = .distanceUpdates }
                        Divider().overlay(ATHLTHPlanDesign.warmDivider)
                    }
                    if draft.timeTriggerEnabled {
                        announcementGroupRow(
                            title: tr("Every time interval", "Etter tidsintervall"),
                            detail: "\(draft.timeIntervalSeconds) s · " +
                                standardAnnouncementMetrics.joined(separator: ", ")
                        ) { editingOption = .timedUpdates }
                        Divider().overlay(ATHLTHPlanDesign.warmDivider)
                    }
                }
                if draft.smartPrompts.motivationEnabled && !hasScheduledMotivation {
                    announcementGroupRow(
                        title: tr("Automatic motivation", "Automatisk motivasjon"),
                        detail: tr("Approximately every", "Omtrent hvert") +
                            " \(draft.smartPrompts.motivationIntervalSeconds) s"
                    ) { editingOption = .motivation }
                    Divider().overlay(ATHLTHPlanDesign.warmDivider)
                }
                ForEach(draft.customRules.filter(\.isEnabled)) { rule in
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                if expandedCoachGroups.contains(rule.id) {
                                    expandedCoachGroups.remove(rule.id)
                                } else {
                                    expandedCoachGroups.insert(rule.id)
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "waveform")
                                    .foregroundStyle(bronze)
                                    .frame(width: 34, height: 34)
                                    .background(ATHLTHPlanDesign.selectedSurface, in: Circle())
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(rule.trigger == .distance
                                         ? tr("Every \(rule.validatedInterval) m", "Hver \(rule.validatedInterval) m")
                                         : tr("Every \(rule.validatedInterval) s", "Hvert \(rule.validatedInterval) s"))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(ink)
                                    Text(rule.selectedMetrics.map(\.title).joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(dim)
                                        .lineLimit(2)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: expandedCoachGroups.contains(rule.id)
                                      ? "chevron.up" : "chevron.down")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(dim)
                            }
                            .frame(minHeight: 56)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if expandedCoachGroups.contains(rule.id) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(tr("Coach will announce", "Coachen leser opp"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(dim)
                                ForEach(Array(rule.selectedMetrics.enumerated()), id: \.offset) { index, metric in
                                    HStack(spacing: 10) {
                                        Text(String(format: "%02d", index + 1))
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(bronze)
                                        Text(metric.title)
                                            .font(.subheadline)
                                            .foregroundStyle(ink)
                                        Spacer()
                                    }
                                }
                                HStack {
                                    Spacer()
                                    Button {
                                        selectedRule = SelectedRule(id: rule.id)
                                    } label: {
                                        Label(tr("Edit group", "Rediger gruppe"), systemImage: "pencil")
                                            .font(.subheadline.weight(.medium))
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(bronze)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
                            .padding(.bottom, 8)
                        }
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 6)
                    .background(
                        ATHLTHPlanDesign.selectedSurface.opacity(0.35),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(ATHLTHPlanDesign.warmDivider, lineWidth: 1)
                    }
                    .padding(.bottom, 7)
                }
                ForEach(activeOptions) { option in
                    activeRow(option)
                    if option != activeOptions.last {
                        Divider().overlay(ATHLTHPlanDesign.warmDivider)
                    }
                }
            }
            Button {
                guard draft.customRules.count < 20 else { return }
                let group = ATHLTHAudioCoachRule(
                    trigger: .distance,
                    metric: .distance,
                    interval: 1_000,
                    additionalMetrics: [.elapsedTime, .heartRateZone]
                )
                draft.customRules.append(group)
                selectedRule = SelectedRule(id: group.id)
            } label: {
                Label(tr("Create coach message", "Opprett coach-beskjed"),
                      systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 47)
            }
            .buttonStyle(.borderedProminent)
            .tint(bronze)
            .disabled(draft.customRules.count >= 20)

            if !draft.customRules.contains(where: {
                $0.trigger == .time && $0.validatedInterval == 60 &&
                $0.selectedMetrics == [.motivation]
            }) {
                Button {
                    guard draft.customRules.count < 20 else { return }
                    let group = ATHLTHAudioCoachRule(
                        trigger: .time, metric: .motivation, interval: 60
                    )
                    draft.customRules.append(group)
                    selectedRule = SelectedRule(id: group.id)
                } label: {
                    Label(tr("Add every-minute motivation", "Legg til motivasjon hvert minutt"),
                          systemImage: "sparkles")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(draft.customRules.count >= 20)
            }

            if !draft.smartPrompts.motivationEnabled && !hasScheduledMotivation {
                Button {
                    draft.smartPrompts.motivationEnabled = true
                    editingOption = .motivation
                } label: {
                    Label(tr("Add automatic motivation", "Legg til automatisk motivasjon"),
                          systemImage: "bolt.heart")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }

            Button {
                showingCatalogue = true
            } label: {
                Label(tr("Heart rate, pace, intervals and event alerts", "Puls, tempo, intervaller og hendelsesvarsler"),
                      systemImage: "slider.horizontal.3")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("athlth-audio-coach-add-option")

            if !draft.customRules.isEmpty {
                Text(tr(
                    "Custom groups and standard intervals are independent. Shared measurements are read only once when they trigger together.",
                    "Egne grupper og standardintervaller virker uavhengig. Samme måleverdi leses bare én gang når de utløses samtidig."
                ))
                .font(.caption).foregroundStyle(dim)
            }
        }
    }

    private func activeRow(_ option: ATHLTHAudioCoachOption) -> some View {
        HStack(spacing: 10) {
            Image(systemName: option.symbol)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(bronze)
                .frame(width: 29)
            Button {
                editingOption = option
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(option.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                    Text(option.detail(in: draft))
                        .font(.caption)
                        .foregroundStyle(dim)
                }
                .frame(maxWidth: .infinity, minHeight: 45,
                       alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                if option.isContentList {
                    pendingRemoval = option
                } else {
                    option.setActive(false, in: &draft)
                }
            } label: {
                Image(systemName: "minus.circle")
                    .font(.title3)
                    .foregroundStyle(dim)
                    .frame(width: 43, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("Remove", "Fjern") + " " + option.title)
        }
        .padding(.vertical, 4)
    }

    private var catalogueSheet: some View {
        NavigationStack {
            List {
                ForEach([
                    tr("Workout updates", "Øktoppdateringer"),
                    tr("Heart rate", "Puls"),
                    tr("Motivation", "Motivasjon"),
                    tr("Events", "Hendelser"),
                    tr("Workout guidance", "Rute og intervaller"),
                    tr("My rules", "Egne regler")
                ], id: \.self) { category in
                    let options = inactiveOptions.filter { $0.category == category }
                    if !options.isEmpty {
                        Section(category) {
                            ForEach(options) { option in
                                Button {
                                    if !option.isContentList {
                                        option.setActive(true, in: &draft)
                                    }
                                    nextEditor = option.requiresConfiguration ? option : nil
                                    showingCatalogue = false
                                } label: {
                                    Label(option.title, systemImage: option.symbol)
                                        .foregroundStyle(ink)
                                        .frame(minHeight: 39, alignment: .leading)
                                }
                                .accessibilityIdentifier("athlth-audio-add-\(option.rawValue)")
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(tr("Add to Audio Coach", "Legg til i Audio Coach"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Done", "Ferdig")) { showingCatalogue = false }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var standardMetricsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("Read together in one announcement", "Les opp samlet i én beskjed"))
                .font(.subheadline.weight(.semibold))
            Toggle(tr("Distance", "Distanse"), isOn: $draft.announceDistance)
            Toggle(tr("Elapsed time", "Medgått tid"), isOn: $draft.announceElapsedTime)
            Toggle(tr("Average pace", "Gjennomsnittstempo"), isOn: $draft.announceAveragePace)
            Toggle(tr("Clock time", "Klokkeslett"), isOn: $draft.announceClockTime)
            Toggle(tr("Heart rate", "Puls"), isOn: $draft.announceHeartRate)
            Text(tr("The selected values use the same distance/time schedule. To set a separate schedule, create an independent group.",
                    "Valgene bruker samme intervall. Opprett en egen varslingsgruppe hvis du vil ha et annet intervall."))
                .font(.caption).foregroundStyle(dim)
        }
        .tint(bronze)
    }

    @ViewBuilder
    private func editorFields(for option: ATHLTHAudioCoachOption) -> some View {
        switch option {
        case .distanceUpdates:
            editorCard {
                Text(tr("Read updates after distance", "Les opp etter distanse"))
                    .font(.headline)
                Picker(tr("Every", "Hver"), selection: $draft.distanceIntervalKilometers) {
                    Text("250 m").tag(0.25)
                    Text("500 m").tag(0.5)
                    Text("1 km").tag(1.0)
                    Text("2 km").tag(2.0)
                    Text("5 km").tag(5.0)
                }
                .pickerStyle(.menu)
                standardMetricsEditor
            }
        case .timedUpdates:
            editorCard {
                Text(tr("Read updates after time", "Les opp etter tid")).font(.headline)
                Picker(tr("Every", "Hvert"), selection: timeSeconds) {
                    ForEach([30, 60, 90, 120, 180, 300, 600, 900, 1_800, 3_600], id: \.self) {
                        seconds in
                        Text(seconds < 60 ? "\(seconds) s" :
                            seconds.isMultiple(of: 60)
                                ? "\(seconds / 60) min"
                                : "\(seconds / 60) min \(seconds % 60) s")
                            .tag(seconds)
                    }
                }
                .pickerStyle(.menu)
                standardMetricsEditor
            }
        case .scopedCountdowns:
            editorCard {
                ATHLTHScopedCountdownRulesEditor(rules: $draft.smartPrompts.boundaryCountdownRules)
            }
        case .intervalRecoveryCountdown:
            editorCard {
                Text(tr("Spoken interval rest countdown", "Hørbar nedtelling ved intervallpause"))
                    .font(.headline)
                Text(tr(
                    "Individual numbers are spoken against the interval timer, not queued as ordinary reminders. Requires timed intervals.",
                    "Enkeltall leses etter intervallklokken, ikke som vanlige varsler i kø. Krever tidsstyrte intervaller."
                ))
                .font(.caption)
                .foregroundStyle(dim)

                Toggle(
                    tr("Count down into rest", "Tell ned til pausen starter"),
                    isOn: Binding(
                        get: { draft.smartPrompts.intervalCountdownToRecoverySeconds != nil },
                        set: { draft.smartPrompts.intervalCountdownToRecoverySeconds = $0 ? 10 : nil }
                    )
                )
                .tint(bronze)
                if draft.smartPrompts.intervalCountdownToRecoverySeconds != nil {
                    Picker(tr("Start counting from", "Start nedtelling fra"),
                           selection: Binding(
                            get: { draft.smartPrompts.intervalCountdownToRecoverySeconds ?? 10 },
                            set: { draft.smartPrompts.intervalCountdownToRecoverySeconds = $0 }
                           )) {
                        ForEach(ATHLTHCoachSecondCountdown.offeredLengths, id: \.self) { seconds in
                            Text("\(seconds) s").tag(seconds)
                        }
                    }
                    Picker(tr("After countdown", "Etter nedtelling"),
                           selection: Binding(
                            get: { draft.smartPrompts.intervalAfterCountdownToRecovery ?? .shortAlert },
                            set: { draft.smartPrompts.intervalAfterCountdownToRecovery = $0 }
                           )) {
                        ForEach(ATHLTHCoachCountdownAfter.allCases) { action in
                            Text(action.title).tag(action)
                        }
                    }
                }

                Divider()

                Toggle(
                    tr("Count down while resting", "Tell ned til pausen er ferdig"),
                    isOn: Binding(
                        get: { draft.smartPrompts.intervalCountdownFromRecoverySeconds != nil },
                        set: { draft.smartPrompts.intervalCountdownFromRecoverySeconds = $0 ? 10 : nil }
                    )
                )
                .tint(bronze)
                if draft.smartPrompts.intervalCountdownFromRecoverySeconds != nil {
                    Picker(tr("Start counting from", "Start nedtelling fra"),
                           selection: Binding(
                            get: { draft.smartPrompts.intervalCountdownFromRecoverySeconds ?? 10 },
                            set: { draft.smartPrompts.intervalCountdownFromRecoverySeconds = $0 }
                           )) {
                        ForEach(ATHLTHCoachSecondCountdown.offeredLengths, id: \.self) { seconds in
                            Text("\(seconds) s").tag(seconds)
                        }
                    }
                    Picker(tr("After countdown", "Etter nedtelling"),
                           selection: Binding(
                            get: { draft.smartPrompts.intervalAfterCountdownFromRecovery ?? .nextStep },
                            set: { draft.smartPrompts.intervalAfterCountdownFromRecovery = $0 }
                           )) {
                        ForEach(ATHLTHCoachCountdownAfter.allCases) { action in
                            Text(action.title).tag(action)
                        }
                    }
                }
                Text(tr(
                    "Numbers only: silence after 1. Short announcement: 'Rest begins/ends'. Announce what is next: include the next interval details.",
                    "Bare tallene: stille etter 1. Kort beskjed: «Pause starter/ferdig». Fortell hva som er neste: inkluder neste drag."
                ))
                .font(.caption)
                .foregroundStyle(dim)
            }
        case .currentZone:
            editorCard {
                Text(tr("Measured heart-rate zone", "Målt pulssone")).font(.headline)
                Text(tr(
                    "Uses a valid maximum heart rate and fresh Watch measurements. Target-zone warnings have higher priority.",
                    "Krever gyldig makspuls og ferske målinger fra Apple Watch. Målsonevarsler prioriteres."
                ))
                .font(.caption)
                .foregroundStyle(dim)
                Toggle(tr("Override max HR for this workout", "Overstyr makspuls"),
                       isOn: Binding(
                        get: { draft.smartPrompts.maximumHeartRateBPM != nil },
                        set: { draft.smartPrompts.maximumHeartRateBPM = $0 ? 185 : nil }
                       ))
                    .tint(bronze)
                if draft.smartPrompts.maximumHeartRateBPM != nil {
                    Stepper(value: Binding(
                        get: { Int(draft.smartPrompts.maximumHeartRateBPM ?? 185) },
                        set: { draft.smartPrompts.maximumHeartRateBPM = Double($0) }
                    ), in: 100...240) {
                        Text("\(Int(draft.smartPrompts.maximumHeartRateBPM ?? 185)) bpm")
                    }
                }
                Picker(tr("Announce current zone every", "Les pulssone hvert"),
                       selection: Binding(
                        get: { draft.smartPrompts.measuredZoneAnnouncementIntervalSeconds ?? 180 },
                        set: { draft.smartPrompts.measuredZoneAnnouncementIntervalSeconds = $0 }
                       )) {
                    Text("30 s").tag(30)
                    Text("1 min").tag(60)
                    Text("2 min").tag(120)
                    Text("3 min").tag(180)
                    Text("5 min").tag(300)
                }
                .pickerStyle(.menu)
            }
        case .targetZoneCoach:
            ATHLTHAudioCoachTargetZoneEditor(smart: $draft.smartPrompts)
        case .adaptiveMotivation:
            ATHLTHAudioCoachAdaptiveRulesEditor(smart: $draft.smartPrompts)
        case .motivation:
            editorCard {
                Text(tr("Motivational coaching", "Motivasjonssnakk")).font(.headline)
                Picker(tr("Frequency", "Hyppighet"),
                       selection: $draft.smartPrompts.motivationIntervalSeconds) {
                    ForEach([30, 60, 120, 180, 300, 600], id: \.self) { sec in
                        Text("\(sec) s").tag(sec)
                    }
                }
                .pickerStyle(.menu)
                Picker(tr("Tone", "Motivasjonsstil"), selection: Binding(
                    get: { draft.smartPrompts.encouragementStyle ?? .encouragement },
                    set: { draft.smartPrompts.encouragementStyle = $0 }
                )) {
                    ForEach(ATHLTHCoachEncouragementStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.menu)
            }
        case .randomEncouragement:
            editorCard {
                Text(tr("Surprise encouragement", "Tilfeldig oppmuntring")).font(.headline)
                Picker(tr("Approximately every", "Omtrent hvert"),
                       selection: $draft.smartPrompts.randomIntervalSeconds) {
                    ForEach([120, 180, 240, 360, 600, 900], id: \.self) { sec in
                        Text("\(sec / 60) min").tag(sec)
                    }
                }
                .pickerStyle(.menu)
            }
        case .customAnnouncements:
            independentRulesEditor
        case .customPhrases:
            phrasesEditor
        case .landmarks:
            placesEditor
        default:
            editorCard {
                Text(option.title).font(.headline)
                Text(tr(
                    "This announcement is active. Remove it from the active list when you no longer want to hear it.",
                    "Denne beskjeden er aktiv. Fjern den fra listen hvis du ikke lenger ønsker den."
                ))
                .font(.subheadline)
                .foregroundStyle(dim)
            }
        }
    }

    private var independentRulesEditor: some View {
        editorCard {
            Text(tr("Independent announcements", "Egne beskjeder"))
                .font(.headline)
            Text(tr(
                "Each announcement has its own metric and time/distance interval. Custom rules replace the standard periodic triggers.",
                "Hver beskjed har eget innhold og tids- eller distanseintervall. Egne regler erstatter de vanlige periodiske utløserne."
            ))
            .font(.caption)
            .foregroundStyle(dim)
            ForEach($draft.customRules) { $rule in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(rule.metric.title).font(.subheadline.weight(.semibold))
                        Spacer()
                        Button(role: .destructive) {
                            let id = rule.id
                            draft.customRules.removeAll { $0.id == id }
                        } label: {
                            Image(systemName: "trash").frame(width: 44, height: 44)
                        }
                    }
                    Picker(tr("First value", "Første verdi"), selection: $rule.metric) {
                        ForEach(ATHLTHAudioCoachRule.Metric.allCases) { metric in
                            Text(metric.title).tag(metric)
                        }
                    }
                    multiMetricChoices(
                        primary: rule.metric,
                        selected: Binding(
                            get: { rule.additionalMetrics ?? [] },
                            set: { rule.additionalMetrics = $0 }
                        )
                    )
                    ruleScopePicker(selection: Binding(
                        get: { rule.scope ?? .workout },
                        set: { rule.scope = $0 }
                    ))
                    Picker(tr("When", "Utløser"), selection: $rule.trigger) {
                        ForEach(ATHLTHAudioCoachRule.Trigger.allCases) { trigger in
                            Text(trigger.title).tag(trigger)
                        }
                    }
                    Stepper(value: $rule.interval,
                            in: rule.trigger == .time
                                ? 15...7_200 : 100...42_000,
                            step: rule.trigger == .time ? 15 : 100) {
                        Text("\(rule.validatedInterval) " +
                            (rule.trigger == .time ? "s" : "m"))
                    }
                    Divider().overlay(ATHLTHPlanDesign.warmDivider)
                }
            }
            Text(tr("New announcement", "Ny beskjed"))
                .font(.subheadline.weight(.semibold))
            Button {
                // One tap saves the full bundle. No separate Add operation.
                if draft.addKilometerMetricsBundle() {
                    editingOption = nil
                }
            } label: {
                Label(tr("Add: Every kilometre · distance, time and pulse",
                         "Legg til: Hver km · distanse, tid og puls"),
                      systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(draft.customRules.count >= 20 || draft.customRules.contains {
                $0.trigger == .distance && $0.validatedInterval == 1_000 &&
                $0.selectedMetrics == [.distance, .elapsedTime, .heartRate]
            })
            Picker(tr("First value", "Første verdi"), selection: $newRuleMetric) {
                ForEach(ATHLTHAudioCoachRule.Metric.allCases) { metric in
                    Text(metric.title).tag(metric)
                }
            }
            multiMetricChoices(primary: newRuleMetric,
                               selected: $newRuleAdditionalMetrics)
            ruleScopePicker(selection: $newRuleScope)
            Picker(tr("When", "Utløser"), selection: $newRuleTrigger) {
                ForEach(ATHLTHAudioCoachRule.Trigger.allCases) { trigger in
                    Text(trigger.title).tag(trigger)
                }
            }
            .onChange(of: newRuleTrigger) { _, kind in
                newRuleInterval = kind == .time ? 60 : 1_000
            }
            Stepper(value: $newRuleInterval,
                    in: newRuleTrigger == .time ? 15...7_200 : 100...42_000,
                    step: newRuleTrigger == .time ? 15 : 100) {
                Text("\(newRuleInterval) " + (newRuleTrigger == .time ? "s" : "m"))
            }
            Button {
                guard draft.customRules.count < 20 else { return }
                draft.customRules.append(ATHLTHAudioCoachRule(
                    trigger: newRuleTrigger, metric: newRuleMetric, interval: newRuleInterval,
                    additionalMetrics: newRuleAdditionalMetrics.filter {
                        $0 != newRuleMetric
                    },
                    scope: newRuleScope
                ))
            } label: {
                Label(tr("Add rule", "Legg til regel"), systemImage: "plus")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(draft.customRules.count >= 20)
        }
    }

    // Resolve by stable rule ID on every access. A sheet can outlive its row
    // while SwiftUI finishes dismissing it after a deletion.
    private func ruleBinding(for id: UUID) -> Binding<ATHLTHAudioCoachRule>? {
        guard let initial = draft.customRules.first(where: { $0.id == id }) else {
            return nil
        }
        return Binding(
            get: { draft.customRules.first(where: { $0.id == id }) ?? initial },
            set: { updated in
                guard let index = draft.customRules.firstIndex(where: { $0.id == id }) else {
                    return
                }
                draft.customRules[index] = updated
            }
        )
    }

    @ViewBuilder
    private func ruleGroupEditor(_ id: UUID) -> some View {
        if let rule = ruleBinding(for: id) {
            editorCard {
                Toggle(tr("Active", "Aktiv"), isOn: Binding(
                    get: { rule.wrappedValue.isEnabled },
                    set: { rule.wrappedValue.enabled = $0 }
                ))
                .tint(bronze)

                ruleScopePicker(selection: Binding(
                    get: { rule.wrappedValue.scope ?? .workout },
                    set: { rule.wrappedValue.scope = $0 }
                ))
                Text(tr("1 · When should this message play?", "1 · Når skal beskjeden komme?"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
                Text(tr("For heart-rate zone, pace or interval events, use the event alert catalogue.", "For pulssone, tempo eller intervallhendelser bruker du hendelsesvarslene."))
                    .font(.caption)
                    .foregroundStyle(dim)
                Picker(tr("Trigger", "Utløser"), selection: rule.trigger) {
                    ForEach(ATHLTHAudioCoachRule.Trigger.allCases) { trigger in
                        Text(trigger.title).tag(trigger)
                    }
                }
                .pickerStyle(.segmented)

                Stepper(
                    value: rule.interval,
                    in: rule.wrappedValue.trigger == .time ? 15...7_200 : 100...42_000,
                    step: rule.wrappedValue.trigger == .time ? 15 : 100
                ) {
                    Text(rule.wrappedValue.trigger == .time
                         ? tr("Every \(rule.wrappedValue.validatedInterval) seconds",
                              "Hvert \(rule.wrappedValue.validatedInterval) sekund")
                         : tr("Every \(rule.wrappedValue.validatedInterval) metres",
                              "Hver \(rule.wrappedValue.validatedInterval) meter"))
                }
                .onChange(of: rule.wrappedValue.trigger) { _, newValue in
                    rule.wrappedValue.interval = newValue == .time ? 60 : 1_000
                }

                Text(tr("2 · What should the coach say?", "2 · Hva skal coachen si?"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
                Picker(tr("First message item", "Første innhold"), selection: rule.metric) {
                    ForEach(ATHLTHAudioCoachRule.Metric.allCases) { metric in
                        Text(metric.title).tag(metric)
                    }
                }
                .pickerStyle(.menu)

                multiMetricChoices(
                    primary: rule.wrappedValue.metric,
                    selected: Binding(
                        get: { rule.wrappedValue.additionalMetrics ?? [] },
                        set: { rule.wrappedValue.additionalMetrics = $0 }
                    )
                )
                if rule.wrappedValue.selectedMetrics.contains(.motivation) {
                    Picker(tr("Motivation style", "Motivasjonsstil"), selection: Binding(
                        get: { rule.wrappedValue.encouragementStyle ?? .encouragement },
                        set: { rule.wrappedValue.encouragementStyle = $0 }
                    )) {
                        ForEach(ATHLTHCoachEncouragementStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Divider()
                Button {
                    guard draft.customRules.count < 20 else { return }
                    var duplicate = rule.wrappedValue
                    duplicate.id = UUID()
                    draft.customRules.append(duplicate)
                    selectedRule = SelectedRule(id: duplicate.id)
                } label: {
                    Label(tr("Duplicate group", "Dupliser gruppe"),
                          systemImage: "square.on.square")
                        .frame(minHeight: 44)
                }
                .disabled(draft.customRules.count >= 20)
                Button(role: .destructive) {
                    draft.customRules.removeAll { $0.id == id }
                    selectedRule = nil
                } label: {
                    Label(tr("Delete group", "Slett gruppe"), systemImage: "trash")
                        .frame(minHeight: 44)
                }
            }
        }
    }

    private func ruleScopePicker(selection: Binding<ATHLTHAudioCoachRule.Scope>) -> some View {
        Picker(tr("Count from", "Tell fra"), selection: selection) {
            ForEach(ATHLTHAudioCoachRule.Scope.allCases) { scope in
                Text(scope.title).tag(scope)
            }
        }
    }

    /// Additional metrics are read in the same sentence and at the SAME
    /// milestone; unlike three independent rules they cannot overlap.
    private func multiMetricChoices(
        primary: ATHLTHAudioCoachRule.Metric,
        selected: Binding<[ATHLTHAudioCoachRule.Metric]>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tr("Also read out", "Les også opp"))
                .font(.subheadline.weight(.semibold))
            ForEach(ATHLTHAudioCoachRule.Metric.allCases.filter {
                $0 != primary
            }) { metric in
                Toggle(metric.title, isOn: Binding(
                    get: { selected.wrappedValue.contains(metric) },
                    set: { included in
                        var values = selected.wrappedValue.filter {
                            $0 != primary && $0 != metric
                        }
                        if included { values.append(metric) }
                        selected.wrappedValue = values
                    }
                ))
                .tint(bronze)
            }
            Text(tr(
                "These values will be spoken together in one announcement.",
                "Verdiene leses opp samlet i én beskjed."
            ))
            .font(.caption)
            .foregroundStyle(dim)
        }
    }

    private var phrasesEditor: some View {
        editorCard {
            Text(tr("Personal motivation phrases", "Egne motivasjonsmeldinger"))
                .font(.headline)
            ForEach(Array(draft.smartPrompts.customEncouragements.enumerated()),
                    id: \.offset) { index, phrase in
                HStack {
                    Text(phrase).font(.subheadline)
                    Spacer()
                    Button(role: .destructive) {
                        draft.smartPrompts.customEncouragements.remove(at: index)
                    } label: {
                        Image(systemName: "trash").frame(width: 44, height: 44)
                    }
                }
            }
            TextField(tr("A personal message", "En personlig beskjed"),
                      text: $phraseText, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
            Button {
                let phrase = phraseText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !phrase.isEmpty,
                      draft.smartPrompts.customEncouragements.count < 40 else { return }
                draft.smartPrompts.customEncouragements.append(
                    String(phrase.prefix(180))
                )
                draft.smartPrompts.randomEncouragementEnabled = true
                phraseText = ""
            } label: {
                Label(tr("Add phrase", "Legg til melding"), systemImage: "plus")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(phraseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                      draft.smartPrompts.customEncouragements.count >= 40)
        }
    }

    private var placesEditor: some View {
        editorCard {
            Text(tr("Places along the route", "Steder langs ruten")).font(.headline)
            Text(tr(
                "Only places you choose can trigger environmental comments.",
                "Bare steder du selv velger kan utløse stedsbaserte beskjeder."
            ))
            .font(.caption)
            .foregroundStyle(dim)
            ForEach(draft.smartPrompts.landmarks) { place in
                HStack {
                    VStack(alignment: .leading) {
                        Text(place.name).font(.subheadline.weight(.medium))
                        Text((place.kind ?? .ordinary).title)
                            .font(.caption).foregroundStyle(dim)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        draft.smartPrompts.landmarks.removeAll { $0.id == place.id }
                    } label: {
                        Image(systemName: "trash").frame(width: 44, height: 44)
                    }
                }
            }
            TextField(tr("Search for a place", "Søk etter et sted"), text: $placeQuery)
                .submitLabel(.search)
                .onSubmit(searchForPlace)
                .textFieldStyle(.roundedBorder)
            Picker(tr("Place type", "Stedstype"), selection: $placeKind) {
                ForEach(ATHLTHCoachLandmarkKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            Picker(tr("Which side?", "Hvilken side?"), selection: $placeSide) {
                ForEach(ATHLTHCoachLandmarkSide.allCases) { side in
                    Text(side.title).tag(side)
                }
            }
            .pickerStyle(.segmented)
            Button(action: searchForPlace) {
                Label(tr("Find place", "Finn sted"), systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .disabled(searchingPlaces || placeQuery.isEmpty)
            if let placeError {
                Text(placeError).font(.caption).foregroundStyle(dim)
            }
            ForEach(placeResults) { place in
                Button {
                    guard draft.smartPrompts.landmarks.count < 30 else { return }
                    draft.smartPrompts.landmarks.append(ATHLTHCoachLandmark(
                        name: place.title, latitude: place.latitude,
                        longitude: place.longitude, side: placeSide, kind: placeKind
                    ))
                    placeResults = []
                    placeQuery = ""
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(place.title).font(.subheadline.weight(.medium))
                            Text(place.subtitle).font(.caption).foregroundStyle(dim)
                        }
                        Spacer()
                        Image(systemName: "plus.circle")
                    }
                }
                .disabled(draft.smartPrompts.landmarks.count >= 30)
            }
        }
    }

    private func searchForPlace() {
        let query = placeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !searchingPlaces else { return }
        searchingPlaces = true
        placeResults = []
        placeError = nil
        Task { @MainActor in
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = [.pointOfInterest, .address]
            do {
                let result = try await MKLocalSearch(request: request).start()
                placeResults = result.mapItems.prefix(6).compactMap { item in
                    let coordinate = item.placemark.coordinate
                    guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
                    return PlaceCandidate(
                        title: item.name ?? query,
                        subtitle: item.placemark.title ?? "",
                        latitude: coordinate.latitude,
                        longitude: coordinate.longitude
                    )
                }
                if placeResults.isEmpty {
                    placeError = tr("No matches found", "Fant ingen steder")
                }
            } catch {
                placeError = tr("Place search is unavailable", "Stedssøk er ikke tilgjengelig")
            }
            searchingPlaces = false
        }
    }

    private var compactNavigationCard: some View {
        ATHLTHPlanSurface(ghost: false) {
            Button { showingVoice = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "speaker.wave.2").foregroundStyle(bronze)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tr("Voice and music", "Stemme og musikk"))
                            .font(.subheadline.weight(.semibold))
                        Text(tr("Language, voice and music ducking",
                                "Språk, stemme og musikkdemping"))
                            .font(.caption)
                            .foregroundStyle(dim)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(dim)
                }
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if editorMode == "advanced" {
                Divider().overlay(ATHLTHPlanDesign.warmDivider)
                Button { showingProfiles = true } label: {
                    HStack {
                        Label(tr("Saved Coach profiles", "Lagrede coach-profiler"),
                              systemImage: "square.stack")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(settings.audioCoachProfiles.count)")
                            .foregroundStyle(dim)
                        Image(systemName: "chevron.right").foregroundStyle(dim)
                    }
                    .frame(minHeight: 50)
                }
                .buttonStyle(.plain)
            }
            if globalScope {
                Divider().overlay(ATHLTHPlanDesign.warmDivider)
                NavigationLink {
                    AthleteFuelView()
                } label: {
                    HStack {
                        Label(tr("Fuel and hydration reminders", "Energi og væske"),
                              systemImage: "drop")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(dim)
                    }
                    .frame(minHeight: 50)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var voiceSheet: some View {
        NavigationStack {
            ScrollView {
                editorCard {
                    Picker(tr("Language", "Språk"), selection: $draft.language) {
                        ForEach(WatchAudioCoachLanguage.allCases, id: \.rawValue) { language in
                            Text(language.title).tag(language)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: draft.language) { _, _ in
                        draft.voiceIdentifier = nil
                    }
                    Picker(tr("Speaking style", "Snakkestil"),
                           selection: $draft.speechStyle) {
                        ForEach(ATHLTHCoachSpeechStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                    // Keep voice selection in the same sheet. A nested
                    // NavigationLink had no guaranteed navigation host when
                    // this view was opened from a modal workout setup.
                    DisclosureGroup {
                        ATHLTHCoachVoiceChoices(
                            selectedIdentifier: $draft.voiceIdentifier,
                            language: draft.language,
                            speechRate: draft.speechRate,
                            speechVolume: draft.speechVolume,
                            duckOtherAudio: draft.duckOtherAudio,
                            speechStyle: draft.speechStyle
                        )
                        .padding(.top, 8)
                    } label: {
                        Label(tr("Choose and preview voice", "Velg og test stemme"),
                              systemImage: "waveform")
                            .frame(minHeight: 44)
                    }
                    HStack {
                        Text(tr("Voice speed", "Stemmehastighet"))
                        Spacer()
                        Text(draft.speechRate.formatted(
                            .number.precision(.fractionLength(2))
                        )).monospacedDigit()
                    }
                    Slider(value: $draft.speechRate, in: 0.35...0.65, step: 0.01)
                    HStack {
                        Text(tr("Coach volume", "Coachvolum"))
                        Spacer()
                        Text("\(Int((draft.speechVolume * 100).rounded())) %")
                    }
                    Slider(value: $draft.speechVolume, in: 0.2...1, step: 0.05)
                    Toggle(tr("Lower music only while coach speaks",
                              "Demp musikken bare når coachen snakker"),
                           isOn: $draft.duckOtherAudio)
                        .tint(bronze)
                    Picker(tr("Quiet period after alerts", "Stilleperiode etter varsler"),
                           selection: $draft.guidanceQuietPeriodSeconds) {
                        ForEach([0.0, 5.0, 10.0, 15.0, 30.0], id: \.self) { seconds in
                            Text("\(Int(seconds)) s").tag(seconds)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding(16)
            }
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(tr("Voice and music", "Stemme og musikk"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done", "Ferdig")) { showingVoice = false }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var profilesSheet: some View {
        NavigationStack {
            ScrollView {
                editorCard {
                    Text(tr("Saved Coach profiles", "Lagrede coach-profiler"))
                        .font(.headline)
                    if !settings.audioCoachProfiles.isEmpty {
                        ForEach(settings.audioCoachProfiles) { profile in
                            HStack(spacing: 12) {
                                Button {
                                    draft.load(profile: profile)
                                    selectedProfileName = profile.name
                                    showingProfiles = false
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(profile.name).font(.subheadline.weight(.semibold))
                                        Text(profile.configurationSummary)
                                            .font(.caption)
                                            .foregroundStyle(dim)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 47,
                                           alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                Menu {
                                    Button(tr("Use profile", "Bruk profil")) {
                                        draft.load(profile: profile)
                                        selectedProfileName = profile.name
                                        showingProfiles = false
                                    }
                                    Button(tr("Update from current setup",
                                              "Oppdater fra nåværende oppsett")) {
                                        pendingProfileAction = .replace(profile.id)
                                    }
                                    Button(tr("Delete profile", "Slett profil"),
                                           role: .destructive) {
                                        pendingProfileAction = .delete(profile.id)
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .frame(width: 44, height: 44)
                                }
                                .accessibilityLabel(tr("Profile options", "Profilvalg"))
                            }
                        }
                    }
                    TextField(tr("Profile name", "Navn på oppsett"),
                              text: $profileName)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        let name = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty, settings.audioCoachProfiles.count < 30 else {
                            return
                        }
                        settings.audioCoachProfiles.append(ATHLTHAudioCoachProfile(
                            name: String(name.prefix(60)), configuration: draft.configuration()
                        ))
                        profileName = ""
                        showingProfiles = false
                    } label: {
                        Label(tr("Save current setup", "Lagre aktivt oppsett"),
                              systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(profileName.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty || settings.audioCoachProfiles.count >= 30)

                    Divider().overlay(ATHLTHPlanDesign.warmDivider)
                    Text(tr("Saved announcement lists", "Lagrede beskjedlister"))
                        .font(.headline)
                    if !settings.audioCoachSavedRuleSets.isEmpty {
                        ForEach(settings.audioCoachSavedRuleSets) { saved in
                            HStack {
                                Button {
                                    draft.customRules = Array(saved.rules.prefix(20))
                                    showingProfiles = false
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(saved.title).font(.subheadline.weight(.medium))
                                        Text("\(saved.rules.count) " +
                                             tr("rules", "regler"))
                                            .font(.caption)
                                            .foregroundStyle(dim)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Button(role: .destructive) {
                                    settings.audioCoachSavedRuleSets.removeAll {
                                        $0.id == saved.id
                                    }
                                } label: {
                                    Image(systemName: "trash")
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    TextField(tr("Rule list name", "Navn på beskjedliste"),
                              text: $ruleSetName)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        let title = ruleSetName.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        guard !title.isEmpty,
                              !draft.customRules.isEmpty,
                              settings.audioCoachSavedRuleSets.count < 30
                        else { return }
                        settings.audioCoachSavedRuleSets.append(
                            ATHLTHAudioCoachRuleSet(
                                title: String(title.prefix(60)),
                                rules: draft.customRules
                            )
                        )
                        ruleSetName = ""
                    } label: {
                        Label(tr("Save current rule list", "Lagre aktiv beskjedliste"),
                              systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(ruleSetName.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty || draft.customRules.isEmpty ||
                    settings.audioCoachSavedRuleSets.count >= 30)
                }
                .padding(16)
            }
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(tr("Coach profiles", "Coach-profiler"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done", "Ferdig")) { showingProfiles = false }
                }
            }
        }
        .confirmationDialog(
            tr("Manage Coach profile", "Behandle coach-profil"),
            isPresented: Binding(
                get: { pendingProfileAction != nil },
                set: { if !$0 { pendingProfileAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(
                {
                    switch pendingProfileAction {
                    case .delete: return tr("Delete saved profile", "Slett lagret profil")
                    case .replace: return tr("Replace saved profile", "Erstatt lagret profil")
                    case nil: return tr("Confirm", "Bekreft")
                    }
                }(),
                role: .destructive
            ) {
                switch pendingProfileAction {
                case let .delete(id):
                    settings.audioCoachProfiles.removeAll { $0.id == id }
                    if settings.activeAudioCoachProfileID == id {
                        settings.activeAudioCoachProfileID = nil
                    }
                case let .replace(id):
                    if let index = settings.audioCoachProfiles.firstIndex(where: {
                        $0.id == id
                    }) {
                        settings.audioCoachProfiles[index].configuration = draft.configuration()
                    }
                case nil: break
                }
                pendingProfileAction = nil
            }
            Button(tr("Cancel", "Avbryt"), role: .cancel) {
                pendingProfileAction = nil
            }
        } message: {
            Text(tr(
                "Changes to saved profiles are only made after you confirm.",
                "Lagrede profiler endres først når du bekrefter."
            ))
        }
    }

    private func editorCard<Content: View>(
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        ATHLTHPlanSurface(ghost: false) {
            VStack(alignment: .leading, spacing: 14, content: content)
        }
    }
}


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

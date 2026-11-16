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
    @State private var showingQuickMessage = false
    @State private var showingGroupBuilder = false
    @State private var showingGroupCommandBuilder = false
    @State private var pendingGroupCommandID: UUID?
    @State private var groupCommandMetric: ATHLTHAudioCoachRule.Metric = .heartRate
    @State private var groupCommandPhrase = ""
    @State private var showingVoiceOptions = false
    @State private var showingSaveChoices = false
    @State private var showingDirtyTemplatePrompt = false
    @State private var showingResetStandardPrompt = false
    @State private var baselineConfiguration: WatchAudioCoachConfiguration?
    @State private var selectedTemplateID: UUID?
    @State private var pendingTemplateDestination: TemplateDestination?
    @State private var selectedFromProfiles: TemplateDestination?
    @State private var isNewEmptyTemplate = false
    @State private var groupDraftName = ""
    @State private var editingGroupTriggerID: UUID?
    @State private var groupDraftTrigger: ATHLTHAudioCoachRule.Trigger = .distance
    @State private var groupDraftInterval = 1_000
    @State private var openAdvancedAfterQuickMessage = false
    @State private var quickTrigger: ATHLTHAudioCoachRule.Trigger = .time
    @State private var quickMetric: ATHLTHAudioCoachRule.Metric = .heartRate
    @State private var quickInterval = 60
    @State private var showingProfiles = false
    @State private var showingSaveNewProfile = false
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
        case delete(UUID)
    }

    private enum TemplateDestination {
        case standard
        case profile(UUID)
        case new
    }

    private var hasUnsavedTemplateChanges: Bool {
        guard let baselineConfiguration else { return false }
        return draft.configuration() != baselineConfiguration
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
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("Voice guidance", "Stemmeveiledning"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                    Text(draft.enabled
                         ? tr("Coach is on", "Coach er på")
                         : tr("Coach is off", "Coach er av"))
                        .font(.caption)
                        .foregroundStyle(dim)
                }
                Spacer(minLength: 0)
                Toggle("Audio Coach", isOn: $draft.enabled)
                    .labelsHidden()
                    .tint(bronze)
                    .accessibilityIdentifier("athlth-audio-coach-enabled")
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 5)
            if draft.enabled {
                if editorMode == "basic" {
                    ATHLTHAudioCoachCircleOverview(
                        draft: $draft,
                        selectedProfileName: $selectedProfileName,
                        showStructuredOptions: showStructuredOptions,
                        showRouteOptions: showRouteOptions,
                        onEditRule: { id in
                            selectedRule = SelectedRule(id: id)
                        },
                        onEditOption: { option in
                            editingOption = option
                        },
                        onShowProfiles: {
                            showingProfiles = true
                        },
                        onCreateTemplate: {
                            requestTemplateChange(.new)
                        },
                        onSaveTemplate: {
                            showingSaveChoices = true
                        },
                        onSwitchTemplate: { step in
                            cycleSavedTemplates(step)
                        },
                        onResetStandard: {
                            showingResetStandardPrompt = true
                        },
                        isDirty: hasUnsavedTemplateChanges,
                        onAddCommand: { groupID in
                            pendingGroupCommandID = groupID
                            groupCommandMetric = .heartRate
                            groupCommandPhrase = ""
                            showingGroupCommandBuilder = true
                        },
                        onEditGroupTrigger: { groupID in
                            guard let group = draft.coachGroups.first(where: {
                                $0.id == groupID
                            }) else { return }
                            let rule = group.ruleIDs.compactMap { id in
                                draft.customRules.first(where: { $0.id == id })
                            }.first
                            editingGroupTriggerID = groupID
                            groupDraftName = group.name
                            groupDraftTrigger = group.trigger ?? rule?.trigger ?? .time
                            groupDraftInterval = group.interval ?? rule?.interval ?? 60
                            showingGroupBuilder = true
                        },
                        onMoveCommand: { token, destination in
                            ATHLTHAudioCoachCommandMoves.move(
                                token, to: destination, draft: &draft
                            )
                        },
                        onAddGroup: {
                            editingGroupTriggerID = nil
                            groupDraftName = ""
                            groupDraftTrigger = .distance
                            groupDraftInterval = 1_000
                            showingGroupBuilder = true
                        },
                        onAddSpeechCommand: {
                            quickTrigger = .time
                            quickInterval = 60
                            quickMetric = .heartRate
                            showingQuickMessage = true
                        },
                        onShowAdvanced: {
                            editorMode = "advanced"
                        }
                    )
                } else {
                    Button {
                        editorMode = "basic"
                    } label: {
                        Label(tr("Back to my Coach", "Tilbake til min coach"),
                              systemImage: "arrow.left")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(bronze)
                    advancedCard
                }
                DisclosureGroup(isExpanded: $showingVoiceOptions) {
                    voiceAndMusicContent
                        .padding(.top, 12)
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: "speaker.wave.2")
                            .foregroundStyle(bronze)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr("Voice and music", "Stemme og musikk"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ink)
                            Text(tr("Language, Azure voices and playback",
                                    "Språk, Azure-stemmer og avspilling"))
                                .font(.caption)
                                .foregroundStyle(dim)
                        }
                    }
                }
                .tint(bronze)
                .padding(17)
                .background(.white, in: RoundedRectangle(cornerRadius: 19))
                .overlay {
                    RoundedRectangle(cornerRadius: 19)
                        .strokeBorder(ATHLTHPlanDesign.warmDivider, lineWidth: 1)
                }
                .accessibilityIdentifier("athlth-coach-voice-music-expand")
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
        .sheet(isPresented: $showingGroupBuilder, onDismiss: {
            if pendingGroupCommandID != nil {
                showingGroupCommandBuilder = true
            }
        }) {
            groupBuilderSheet
        }
        .sheet(isPresented: $showingGroupCommandBuilder) {
            groupCommandSheet
        }
        .sheet(isPresented: $showingQuickMessage, onDismiss: {
            if openAdvancedAfterQuickMessage {
                openAdvancedAfterQuickMessage = false
                showingCatalogue = true
            }
        }) {
            quickMessageSheet
        }
        .sheet(isPresented: $showingCatalogue, onDismiss: {
            if let nextEditor {
                editingOption = nextEditor
                self.nextEditor = nil
            }
        }) {
            catalogueSheet
        }
        .sheet(isPresented: $showingSaveNewProfile) {
            saveNewProfileSheet
        }
        .sheet(item: $selectedRule) { selection in
            NavigationStack {
                ScrollView {
                    ruleGroupEditor(selection.id)
                        .padding(16)
                }
                .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
                .navigationTitle(tr("Edit trigger", "Rediger trigger"))
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
        .sheet(isPresented: $showingProfiles, onDismiss: {
            if let selectedFromProfiles {
                self.selectedFromProfiles = nil
                requestTemplateChange(selectedFromProfiles)
            }
        }) { profilesSheet }
        .confirmationDialog(
            tr("Save this template?", "Lagre denne malen?"),
            isPresented: $showingSaveChoices,
            titleVisibility: .visible
        ) {
            if !isNewEmptyTemplate {
                Button(tr("Save changes", "Lagre endringer")) {
                    saveCurrentTemplate()
                }
            }
            Button(tr("Save as new", "Lagre som ny")) {
                profileName = isNewEmptyTemplate ? "" : (selectedProfileName ?? "")
                showingSaveNewProfile = true
            }
            Button(tr("Cancel", "Avbryt"), role: .cancel) {}
        }
        .confirmationDialog(
            tr("Unsaved changes", "Ulagrede endringer"),
            isPresented: $showingDirtyTemplatePrompt,
            titleVisibility: .visible
        ) {
            Button(tr("Save", "Lagre")) {
                saveCurrentTemplate()
                if !isNewEmptyTemplate {
                    if let destination = pendingTemplateDestination {
                        applyTemplateDestination(destination)
                    }
                    pendingTemplateDestination = nil
                } else {
                    profileName = ""
                    showingSaveNewProfile = true
                }
            }
            Button(tr("Discard changes", "Forkast endringer"), role: .destructive) {
                if let destination = pendingTemplateDestination {
                    applyTemplateDestination(destination)
                }
                pendingTemplateDestination = nil
            }
            Button(tr("Cancel", "Avbryt"), role: .cancel) {
                pendingTemplateDestination = nil
            }
        } message: {
            Text(tr("Save your changes or discard them before changing templates.",
                    "Lagre eller forkast endringene før du bytter mal."))
        }
        .confirmationDialog(
            tr("Restore Standard?", "Tilbakestille Standard?"),
            isPresented: $showingResetStandardPrompt,
            titleVisibility: .visible
        ) {
            Button(tr("Restore original Standard", "Tilbakestill til opprinnelig Standard"),
                   role: .destructive) {
                draft.applySimpleAudioCoach()
                selectedProfileName = nil
                selectedTemplateID = nil
                isNewEmptyTemplate = false
            }
            Button(tr("Cancel", "Avbryt"), role: .cancel) {}
        }
        .onAppear {
            if baselineConfiguration == nil {
                baselineConfiguration = draft.configuration()
                selectedTemplateID = settings.activeAudioCoachProfileID
                if let selectedTemplateID,
                   let profile = settings.audioCoachProfiles.first(where: { $0.id == selectedTemplateID }) {
                    selectedProfileName = profile.name
                }
            }
        }
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

    /// The everyday flow asks only when to speak and what to read.
    /// Advanced editing still uses the SAME underlying custom-rule model.

    private func saveCurrentTemplate() {
        if let selectedTemplateID,
           let index = settings.audioCoachProfiles.firstIndex(where: {
               $0.id == selectedTemplateID
           }) {
            settings.audioCoachProfiles[index].configuration = draft.configuration()
            settings.activeAudioCoachProfileID = selectedTemplateID
        } else if !isNewEmptyTemplate {
            // Standard is the durable, non-deletable default template.
            settings.updateAudioCoachDefaults(from: draft)
            settings.activeAudioCoachProfileID = nil
        } else {
            profileName = ""
            showingSaveNewProfile = true
            return
        }
        baselineConfiguration = draft.configuration()
    }

    private func requestTemplateChange(_ destination: TemplateDestination) {
        if hasUnsavedTemplateChanges {
            pendingTemplateDestination = destination
            showingDirtyTemplatePrompt = true
        } else {
            applyTemplateDestination(destination)
        }
    }

    private func cycleSavedTemplates(_ step: Int) {
        let ids = settings.audioCoachProfiles.map(\.id)
        let current = selectedTemplateID.flatMap(ids.firstIndex(of:)).map { $0 + 1 } ?? 0
        let next = (current + step + ids.count + 1) % (ids.count + 1)
        requestTemplateChange(next == 0 ? .standard : .profile(ids[next - 1]))
    }

    private func applyTemplateDestination(_ destination: TemplateDestination) {
        switch destination {
        case .standard:
            var defaults = AudioCoachDraft()
            defaults.load(from: settings)
            draft = defaults
            selectedTemplateID = nil
            selectedProfileName = nil
            isNewEmptyTemplate = false
        case let .profile(id):
            guard let profile = settings.audioCoachProfiles.first(where: {
                $0.id == id
            }) else { return }
            draft.load(profile: profile)
            selectedTemplateID = profile.id
            selectedProfileName = profile.name
            isNewEmptyTemplate = false
        case .new:
            var empty = AudioCoachDraft()
            empty.distanceTriggerEnabled = false
            empty.timeTriggerEnabled = false
            empty.customRules = []
            empty.coachGroups = []
            empty.announceDistance = false
            empty.announceElapsedTime = false
            empty.announceAveragePace = false
            empty.announceClockTime = false
            empty.announceHeartRate = false
            empty.announceRemainingRouteDistance = false
            empty.announceEstimatedRemainingRouteTime = false
            empty.announceCurrentWorkoutStep = false
            empty.announceRemainingStepTime = false
            empty.announceRemainingStepDistance = false
            empty.announceWorkoutStart = false
            empty.announcePauseResume = false
            empty.announceWorkoutComplete = false
            empty.smartPrompts = ATHLTHAudioCoachSmartSettings()
            empty.smartPrompts.motivationEnabled = false
            empty.smartPrompts.randomEncouragementEnabled = false
            empty.smartPrompts.contextualFeedbackEnabled = false
            empty.smartPrompts.announceCurrentHeartRateZone = false
            empty.smartPrompts.targetZoneVoiceAlertsEnabled = false
            empty.smartPrompts.boundaryCountdownRules = []
            empty.smartPrompts.intervalCountdownToRecoverySeconds = nil
            empty.smartPrompts.intervalCountdownFromRecoverySeconds = nil
            empty.language = draft.language
            empty.voiceIdentifier = draft.voiceIdentifier
            draft = empty
            selectedTemplateID = nil
            selectedProfileName = tr("New template", "Ny mal")
            isNewEmptyTemplate = true
        }
        baselineConfiguration = draft.configuration()
    }

    private var saveNewProfileSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(tr("Template name", "Navn på mal"), text: $profileName)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text(tr("Save current Coach as new", "Lagre aktiv coach som ny mal"))
                } footer: {
                    Text(tr("Includes named groups and every configured trigger.",
                            "Lagrer gruppenavnene og alle triggerne."))
                }
                Section {
                    Button {
                        let name = String(profileName.trimmingCharacters(
                            in: .whitespacesAndNewlines).prefix(60))
                        guard !name.isEmpty, settings.audioCoachProfiles.count < 30 else { return }
                        let profile = ATHLTHAudioCoachProfile(
                            name: name, configuration: draft.configuration()
                        )
                        settings.audioCoachProfiles.append(profile)
                        settings.activeAudioCoachProfileID = profile.id
                        selectedProfileName = profile.name
                        selectedTemplateID = profile.id
                        isNewEmptyTemplate = false
                        baselineConfiguration = draft.configuration()
                        profileName = ""
                        showingSaveNewProfile = false
                        if let destination = pendingTemplateDestination {
                            pendingTemplateDestination = nil
                            applyTemplateDestination(destination)
                        }
                    } label: {
                        Label(tr("Save as new template", "Lagre som ny mal"),
                              systemImage: "bookmark.badge.plus")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(bronze)
                    .disabled(profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              settings.audioCoachProfiles.count >= 30)
                }
            }
            .scrollContentBackground(.hidden)
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(tr("New Coach template", "Ny coach-mal"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel", "Avbryt")) { showingSaveNewProfile = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var availableGroupContents: [ATHLTHAudioCoachRule.Metric] {
        ATHLTHAudioCoachRule.Metric.allCases.filter { metric in
            switch metric {
            case .stepName, .stepRemainingTime, .groupRemainingTime:
                return showStructuredOptions
            case .routeRemainingDistance, .estimatedRouteTime:
                return showRouteOptions
            default:
                return true
            }
        }
    }

    /// First establish the one shared group trigger. Spoken values are
    /// added afterwards so the group never schedules multiple overlapping cues.
    private var groupBuilderSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        tr("Group name (optional)", "Gruppenavn (valgfritt)"),
                        text: $groupDraftName
                    )
                    .textInputAutocapitalization(.sentences)
                } header: {
                    Text(tr("NAME", "NAVN"))
                }
                Section {
                    Picker(tr("Choose trigger", "Velg trigger"),
                           selection: $groupDraftTrigger) {
                        ForEach(ATHLTHAudioCoachRule.Trigger.allCases) { trigger in
                            Text(trigger.title).tag(trigger)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: groupDraftTrigger) { _, trigger in
                        groupDraftInterval = trigger == .time ? 60 : 1_000
                    }
                    Stepper(
                        value: $groupDraftInterval,
                        in: groupDraftTrigger == .time ? 15...7_200 : 100...42_000,
                        step: groupDraftTrigger == .time ? 15 : 100
                    ) {
                        Text(groupDraftTrigger == .time
                             ? tr("Every \(groupDraftInterval) seconds",
                                  "Hvert \(groupDraftInterval) sekund")
                             : tr("Every \(groupDraftInterval) metres",
                                  "Hver \(groupDraftInterval) meter"))
                    }
                } header: {
                    Text(tr("1 · Choose trigger", "1 · Velg trigger"))
                } footer: {
                    Text(tr(
                        "Create a group first. Then add one or more commands to be spoken together on this trigger.",
                        "Opprett gruppen først. Legg deretter til kommandoer som leses samlet på denne triggeren."
                    ))
                }
                Section {
                    Button(action: createCoachGroup) {
                        Label(
                            editingGroupTriggerID == nil
                                ? tr("Continue to commands", "Fortsett til kommandoer")
                                : tr("Save group trigger", "Lagre gruppens trigger"),
                            systemImage: "arrow.right"
                        )
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(bronze)
                    .accessibilityIdentifier("athlth-coach-save-group")
                }
            }
            .scrollContentBackground(.hidden)
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(
                editingGroupTriggerID == nil
                    ? tr("New coach group", "Ny coach-gruppe")
                    : tr("Group trigger", "Gruppens trigger")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel", "Avbryt")) { showingGroupBuilder = false }
                }
            }
        }
        .presentationDetents([.large])
        .accessibilityIdentifier("athlth-coach-group-builder")
    }

    private func createCoachGroup() {
        if let editingGroupTriggerID,
           let index = draft.coachGroups.firstIndex(where: {
               $0.id == editingGroupTriggerID
           }) {
            draft.coachGroups[index].trigger = groupDraftTrigger
            draft.coachGroups[index].interval = groupDraftInterval
            for id in draft.coachGroups[index].ruleIDs {
                if let ruleIndex = draft.customRules.firstIndex(where: { $0.id == id }),
                   draft.customRules[ruleIndex].beforeEndSeconds == nil {
                    draft.customRules[ruleIndex].trigger = groupDraftTrigger
                    draft.customRules[ruleIndex].interval = groupDraftInterval
                }
            }
            self.editingGroupTriggerID = nil
            showingGroupBuilder = false
            return
        }
        let name = String(groupDraftName.trimmingCharacters(
            in: .whitespacesAndNewlines).prefix(60))
        let fallback = groupDraftTrigger == .time
            ? tr("Time updates", "Tidsoppdateringer")
            : tr("Distance updates", "Distanseoppdateringer")
        var group = ATHLTHAudioCoachGroup(name: name.isEmpty ? fallback : name)
        group.trigger = groupDraftTrigger
        group.interval = groupDraftInterval
        draft.coachGroups.append(group)
        pendingGroupCommandID = group.id
        groupCommandMetric = groupDraftTrigger == .time ? .elapsedTime : .distance
        groupCommandPhrase = ""
        showingGroupBuilder = false
    }

    private var groupCommandSheet: some View {
        NavigationStack {
            Form {
                if let group = draft.coachGroups.first(where: {
                    $0.id == pendingGroupCommandID
                }) {
                    Section {
                        Label(
                            group.trigger == .time
                                ? tr("Every \(group.interval ?? 60) seconds",
                                     "Hvert \(group.interval ?? 60) sekund")
                                : tr("Every \(group.interval ?? 1_000) metres",
                                     "Hver \(group.interval ?? 1_000) meter"),
                            systemImage: group.trigger == .time ? "clock" : "figure.run"
                        )
                        .foregroundStyle(bronze)
                    } header: {
                        Text(tr("GROUP TRIGGER", "GRUPPENS TRIGGER"))
                    }

                    Section {
                        Picker(tr("What should Coach say?", "Hva skal Coach si?"),
                               selection: $groupCommandMetric) {
                            ForEach(availableGroupContents) { metric in
                                Text(metric.title).tag(metric)
                            }
                        }
                        .pickerStyle(.menu)
                        if groupCommandMetric == .motivation {
                            TextField(
                                tr("Personal phrase (optional)",
                                   "Egen setning (valgfritt)"),
                                text: $groupCommandPhrase,
                                axis: .vertical
                            )
                            .lineLimit(2...4)
                        }
                    } header: {
                        Text(tr("ADD ONE COMMAND", "LEGG TIL ÉN KOMMANDO"))
                    } footer: {
                        Text(tr(
                            "Add as many commands as you wish, one at a time. They share the group's trigger and play as one message.",
                            "Legg til én kommando om gangen. Alle bruker gruppens trigger og leses som én beskjed."
                        ))
                    }

                    Section {
                        Button(action: addCommandToGroup) {
                            Label(tr("Add command", "Legg til kommando"),
                                  systemImage: "plus.circle")
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(bronze)
                        .disabled(draft.customRules.count >= 20 &&
                                  group.ruleIDs.isEmpty)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(tr("Group commands", "Gruppekommandoer"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done", "Ferdig")) {
                        pendingGroupCommandID = nil
                        showingGroupCommandBuilder = false
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func addCommandToGroup() {
        guard let groupID = pendingGroupCommandID,
              let groupIndex = draft.coachGroups.firstIndex(where: {
                  $0.id == groupID
              })
        else { return }
        let group = draft.coachGroups[groupIndex]
        let metric = groupCommandMetric
        let phrase = String(groupCommandPhrase.trimmingCharacters(
            in: .whitespacesAndNewlines).prefix(180))
        let existingID = group.ruleIDs.first(where: { id in
            draft.customRules.contains {
                $0.id == id && $0.beforeEndSeconds == nil
            }
        })

        if let existingID,
           let index = draft.customRules.firstIndex(where: { $0.id == existingID }) {
            if !draft.customRules[index].selectedMetrics.contains(metric) {
                draft.customRules[index].additionalMetrics =
                    (draft.customRules[index].additionalMetrics ?? []) + [metric]
            }
            if metric == .motivation && !phrase.isEmpty {
                draft.customRules[index].customPhrase = phrase
            }
        } else {
            guard draft.customRules.count < 20 else { return }
            var rule = ATHLTHAudioCoachRule(
                trigger: group.trigger ?? .time,
                metric: metric,
                interval: group.interval ?? 60,
                scope: .workout
            )
            if metric == .motivation && !phrase.isEmpty {
                rule.customPhrase = phrase
            }
            draft.customRules.append(rule)
            draft.coachGroups[groupIndex].ruleIDs.append(rule.id)
        }
        groupCommandPhrase = ""
        // Keep this sheet open so the next command can be added immediately.
    }

    private var quickMessageSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(tr("When should Coach speak?", "Når skal Coach snakke?"),
                           selection: $quickTrigger) {
                        Text(tr("After time", "Etter tid"))
                            .tag(ATHLTHAudioCoachRule.Trigger.time)
                        Text(tr("After distance", "Etter distanse"))
                            .tag(ATHLTHAudioCoachRule.Trigger.distance)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: quickTrigger) { _, next in
                        quickInterval = next == .time ? 60 : 1_000
                    }

                    Stepper(
                        value: $quickInterval,
                        in: quickTrigger == .time ? 15...7_200 : 100...42_000,
                        step: quickTrigger == .time ? 15 : 100
                    ) {
                        HStack {
                            Text(tr("Every", "Hvert"))
                            Spacer()
                            Text(quickTrigger == .time
                                 ? tr("\(quickInterval) seconds", "\(quickInterval) sekunder")
                                 : "\(quickInterval) m")
                                .fontWeight(.semibold)
                                .foregroundStyle(bronze)
                        }
                    }
                } header: {
                    Text(tr("1 · When?", "1 · Når?"))
                }

                Section {
                    Picker(tr("What should Coach say?", "Hva skal Coach si?"),
                           selection: $quickMetric) {
                        ForEach([
                            ATHLTHAudioCoachRule.Metric.heartRate,
                            .elapsedTime,
                            .distance,
                            .pace,
                            .motivation
                        ], id: \.self) { metric in
                            Text(metric.title).tag(metric)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text(tr("2 · What?", "2 · Hva?"))
                }

                Section {
                    Button {
                        guard draft.customRules.count < 20 else { return }
                        draft.customRules.append(ATHLTHAudioCoachRule(
                            trigger: quickTrigger,
                            metric: quickMetric,
                            interval: quickInterval,
                            scope: .workout
                        ))
                        showingQuickMessage = false
                    } label: {
                        Label(tr("Add Coach message", "Legg til Coach-beskjed"),
                              systemImage: "checkmark")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(bronze)
                    .disabled(draft.customRules.count >= 20)
                    .accessibilityIdentifier("athlth-coach-quick-add-save")

                    Button {
                        openAdvancedAfterQuickMessage = true
                        showingQuickMessage = false
                    } label: {
                        Label(tr("More message types", "Flere beskjedtyper"),
                              systemImage: "slider.horizontal.3")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(bronze)
                } footer: {
                    Text(tr(
                        "Your message belongs only to this workout. All advanced metrics and rules are still available.",
                        "Beskjeden gjelder denne økten. Alle avanserte målinger og regler er fortsatt tilgjengelige."
                    ))
                }
            }
            .scrollContentBackground(.hidden)
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(tr("New Coach message", "Ny Coach-beskjed"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Close", "Lukk")) { showingQuickMessage = false }
                }
            }
        }
        .presentationDetents([.large])
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

                if rule.wrappedValue.metric != .hydrationReminder {
                    ruleScopePicker(selection: Binding(
                        get: { rule.wrappedValue.scope ?? .workout },
                        set: { rule.wrappedValue.scope = $0 }
                    ))
                }
                Text(tr("1 · When should this message play?", "1 · Når skal beskjeden komme?"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
                Text(tr("For heart-rate zone, pace or interval events, use the event alert catalogue.", "For pulssone, tempo eller intervallhendelser bruker du hendelsesvarslene."))
                    .font(.caption)
                    .foregroundStyle(dim)
                if rule.wrappedValue.beforeEndSeconds != nil {
                    Stepper(
                        value: Binding(
                            get: { (rule.wrappedValue.beforeEndSeconds ?? 900) / 60 },
                            set: { rule.wrappedValue.beforeEndSeconds = $0 * 60 }
                        ),
                        in: 1...120, step: 1
                    ) {
                        Text(tr(
                            "\((rule.wrappedValue.beforeEndSeconds ?? 900) / 60) min before finish",
                            "\((rule.wrappedValue.beforeEndSeconds ?? 900) / 60) min før slutt"
                        ))
                    }
                    Text(tr(
                        "Only plays when a reliable estimated finish time exists.",
                        "Spilles bare når økten har en beregnbar sluttid."
                    ))
                    .font(.caption).foregroundStyle(dim)
                    TextField(
                        tr("Personal message (optional)", "Personlig beskjed (valgfritt)"),
                        text: Binding(
                            get: { rule.wrappedValue.customPhrase ?? "" },
                            set: { rule.wrappedValue.customPhrase = $0.isEmpty ? nil : $0 }
                        ),
                        axis: .vertical
                    )
                    .lineLimit(2...4)
                } else if rule.wrappedValue.metric == .hydrationReminder {
                    Picker(tr("Remind every", "Minn meg på å drikke hvert"), selection: Binding(
                        get: { rule.wrappedValue.validatedInterval / 60 },
                        set: { minutes in
                            rule.wrappedValue.trigger = .time
                            rule.wrappedValue.scope = .workout
                            rule.wrappedValue.interval = minutes * 60
                        }
                    )) {
                        ForEach([5, 10, 15, 20, 30, 45, 60], id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                    .pickerStyle(.menu)
                    Text(tr("Coach reminds you without pausing the workout.",
                            "Coachen minner deg på å drikke uten å sette økten på pause."))
                        .font(.caption).foregroundStyle(dim)
                } else {
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
                    if let index = draft.coachGroups.firstIndex(where: {
                        $0.ruleIDs.contains(id)
                    }) {
                        draft.coachGroups[index].ruleIDs.append(duplicate.id)
                    }
                    selectedRule = SelectedRule(id: duplicate.id)
                } label: {
                    Label(tr("Duplicate group", "Dupliser gruppe"),
                          systemImage: "square.on.square")
                        .frame(minHeight: 44)
                }
                .disabled(draft.customRules.count >= 20)
                Button(role: .destructive) {
                    draft.customRules.removeAll { $0.id == id }
                    for index in draft.coachGroups.indices {
                        draft.coachGroups[index].ruleIDs.removeAll { $0 == id }
                    }
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

    /// One expandable, premium editor. Language choice and the provider's
    /// available voices sit alongside each other; no hidden second settings
    /// screen and no fake Azure voice IDs.
    private var voiceAndMusicContent: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 11) {
                    Text(tr("LANGUAGE", "SPRÅK"))
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(bronze)

                    ForEach(WatchAudioCoachLanguage.allCases, id: \.rawValue) { language in
                        Button {
                            draft.language = language
                            draft.voiceIdentifier = nil
                        } label: {
                            HStack(spacing: 7) {
                                Text(language.title)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(2)
                                Spacer(minLength: 0)
                                if draft.language == language {
                                    Image(systemName: "checkmark")
                                        .font(.caption2)
                                }
                            }
                            .foregroundStyle(draft.language == language ? bronze : ink)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 40)
                            .background(
                                draft.language == language
                                    ? ATHLTHPlanDesign.selectedSurface : .white,
                                in: RoundedRectangle(cornerRadius: 11)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 125, alignment: .leading)
                .padding(10)
                .background(ATHLTHPlanDesign.canvas, in: RoundedRectangle(cornerRadius: 15))

                VStack(alignment: .leading, spacing: 7) {
                    Text(tr("AZURE VOICES", "AZURE-STEMMER"))
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(bronze)

                    ATHLTHAzureCoachVoicePreviewView(
                        selectedIdentifier: $draft.voiceIdentifier,
                        language: $draft.language,
                        duckOtherAudio: draft.duckOtherAudio
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(ATHLTHPlanDesign.canvas, in: RoundedRectangle(cornerRadius: 15))
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

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
                Label(tr("Installed Apple voices", "Installerte Apple-stemmer"),
                      systemImage: "iphone")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
                    .frame(minHeight: 42)
            }
            .tint(bronze)

            Divider().overlay(ATHLTHPlanDesign.warmDivider)

            Picker(tr("Speaking style", "Snakkestil"),
                   selection: $draft.speechStyle) {
                ForEach(ATHLTHCoachSpeechStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.menu)

            HStack {
                Text(tr("Speaking speed", "Stemmehastighet"))
                Spacer()
                Text(draft.speechRate.formatted(
                    .number.precision(.fractionLength(2))
                ))
                .monospacedDigit()
                .foregroundStyle(dim)
            }
            .font(.subheadline)
            Slider(value: $draft.speechRate, in: 0.35...0.65, step: 0.01)
                .tint(bronze)

            HStack {
                Text(tr("Coach volume", "Coachvolum"))
                Spacer()
                Text("\(Int((draft.speechVolume * 100).rounded())) %")
                    .monospacedDigit()
                    .foregroundStyle(dim)
            }
            .font(.subheadline)
            Slider(value: $draft.speechVolume, in: 0.2...1, step: 0.05)
                .tint(bronze)

            Toggle(tr("Lower music while Coach speaks",
                      "Demp musikken mens Coach snakker"),
                   isOn: $draft.duckOtherAudio)
                .font(.subheadline)
                .tint(bronze)

            Picker(tr("Quiet time after announcements",
                      "Stilleperiode etter varsler"),
                   selection: $draft.guidanceQuietPeriodSeconds) {
                ForEach([0.0, 5.0, 10.0, 15.0, 30.0], id: \.self) { seconds in
                    Text("\(Int(seconds)) s").tag(seconds)
                }
            }
            .pickerStyle(.menu)

            if globalScope {
                NavigationLink {
                    AthleteFuelView()
                } label: {
                    Label(tr("Fuel and hydration reminders", "Energi og væske"),
                          systemImage: "drop")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(ink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var profilesSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(tr("Your saved templates", "Dine lagrede maler"))
                        .font(.system(size: 25, weight: .regular, design: .serif))
                        .foregroundStyle(ink)
                    Text(tr(
                        "Choose a template. Changes are not lost when switching.",
                        "Velg en mal. Ulagrede endringer beskyttes ved bytte."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(dim)

                    Button {
                        selectedFromProfiles = .standard
                        showingProfiles = false
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "waveform")
                                .foregroundStyle(bronze)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Standard")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ink)
                                Text(tr("Always available · can be reset",
                                        "Alltid tilgjengelig · kan tilbakestilles"))
                                    .font(.caption)
                                    .foregroundStyle(dim)
                            }
                            Spacer(minLength: 0)
                            if selectedTemplateID == nil && !isNewEmptyTemplate {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(bronze)
                            }
                        }
                        .padding(14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 15))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("athlth-coach-select-standard")

                    ForEach(settings.audioCoachProfiles) { profile in
                        HStack(spacing: 9) {
                            Button {
                                selectedFromProfiles = .profile(profile.id)
                                showingProfiles = false
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "square.stack")
                                        .foregroundStyle(bronze)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(profile.name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(ink)
                                        Text(profile.configurationSummary)
                                            .font(.caption)
                                            .foregroundStyle(dim)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    if selectedTemplateID == profile.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(bronze)
                                    }
                                }
                                .padding(14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Menu {
                                Button(tr("Use template", "Bruk mal")) {
                                    selectedFromProfiles = .profile(profile.id)
                                    showingProfiles = false
                                }
                                Button(tr("Delete saved template", "Slett lagret mal"),
                                       systemImage: "trash", role: .destructive) {
                                    pendingProfileAction = .delete(profile.id)
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .foregroundStyle(dim)
                                    .frame(width: 40, height: 42)
                            }
                        }
                        .background(.white, in: RoundedRectangle(cornerRadius: 15))
                    }
                    if settings.audioCoachProfiles.isEmpty {
                        Text(tr("No saved personal templates yet.",
                                "Du har ingen lagrede personlige maler ennå."))
                            .font(.caption)
                            .foregroundStyle(dim)
                            .padding(.vertical, 12)
                    }
                }
                .padding(18)
            }
            .scrollIndicators(.hidden)
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(tr("Saved templates", "Lagrede maler"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done", "Ferdig")) { showingProfiles = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .confirmationDialog(
            tr("Delete saved template?", "Slette lagret mal?"),
            isPresented: Binding(
                get: { pendingProfileAction != nil },
                set: { if !$0 { pendingProfileAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(tr("Delete template", "Slett mal"), role: .destructive) {
                if case let .delete(id) = pendingProfileAction {
                    settings.audioCoachProfiles.removeAll { $0.id == id }
                    if settings.activeAudioCoachProfileID == id {
                        settings.activeAudioCoachProfileID = nil
                    }
                    if selectedTemplateID == id {
                        selectedTemplateID = nil
                        selectedProfileName = tr("New template", "Ny mal")
                        isNewEmptyTemplate = true
                    }
                }
                pendingProfileAction = nil
            }
            Button(tr("Cancel", "Avbryt"), role: .cancel) {
                pendingProfileAction = nil
            }
        } message: {
            Text(tr("Only this saved template is deleted. Standard remains available.",
                    "Bare denne lagrede malen slettes. Standard beholdes."))
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

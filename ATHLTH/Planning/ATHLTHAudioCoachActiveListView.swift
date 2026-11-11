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
    @State private var nextEditor: ATHLTHAudioCoachOption?
    @State private var pendingRemoval: ATHLTHAudioCoachOption?
    @State private var confirmReplaceWithStandard = false
    @State private var profileName = ""
    @State private var selectedProfileName: String?
    @State private var pendingProfileAction: ProfileAction?
    @State private var ruleSetName = ""
    @State private var phraseText = ""
    @State private var newRuleTrigger: ATHLTHAudioCoachRule.Trigger = .distance
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

    private var activeOptions: [ATHLTHAudioCoachOption] {
        ATHLTHAudioCoachOption.allCases.filter {
            $0.isVisible(route: showRouteOptions, structured: showStructuredOptions)
                && $0.isActive(in: draft)
        }
    }

    private var hasAdvancedConfiguration: Bool {
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

    // A schedule and the values spoken at that schedule are ONE group.
    // The underlying Watch/iPhone rule engine and saved profiles remain shared.
    private var periodicGroupCount: Int {
        let scheduled = draft.customRules.isEmpty
            ? (draft.distanceTriggerEnabled ? 1 : 0) +
              (draft.timeTriggerEnabled ? 1 : 0)
            : draft.customRules.count
        return scheduled + (draft.smartPrompts.motivationEnabled ? 1 : 0)
    }

    private var standardSpokenValues: String {
        var values: [String] = []
        if draft.announceDistance { values.append(tr("Distance", "Distanse")) }
        if draft.announceElapsedTime { values.append(tr("Time", "Tid")) }
        if draft.announceAveragePace { values.append(tr("Pace", "Tempo")) }
        if draft.announceHeartRate { values.append(tr("Heart rate", "Puls")) }
        if draft.announceClockTime { values.append(tr("Clock time", "Klokkeslett")) }
        return values.isEmpty
            ? tr("Choose values to announce", "Velg hva som skal leses opp")
            : values.joined(separator: " · ")
    }

    private var extraActiveOptions: [ATHLTHAudioCoachOption] {
        activeOptions.filter { option in
            switch option {
            case .distanceUpdates, .timedUpdates, .distance, .elapsedTime,
                 .averagePace, .clockTime, .heartRate, .motivation,
                 .customAnnouncements:
                return false
            default:
                return true
            }
        }
    }

    private var advancedCard: some View {
        ATHLTHPlanSurface(ghost: false) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("SCHEDULED COACH", "PLANLAGT COACH"))
                        .font(.caption2.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(bronze)
                    Text(tr("Announcement groups", "Varslingsgrupper"))
                        .font(.system(size: 20, weight: .semibold, design: .serif))
                        .foregroundStyle(ink)
                }
                Spacer()
                Text("\(periodicGroupCount)")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(bronze)
            }

            Text(tr(
                "Choose WHEN to speak and WHAT to say together. Each group creates one announcement at its interval.",
                "Velg NÅR coachen skal snakke og HVA han skal si samlet. Hver gruppe gir én beskjed per intervall."
            ))
            .font(.caption)
            .foregroundStyle(dim)

            if draft.customRules.isEmpty {
                if draft.distanceTriggerEnabled {
                    announcementGroupRow(
                        title: tr("Every distance", "Etter distanse") +
                            " · " + ATHLTHAudioCoachOption.distanceUpdates.detail(in: draft),
                        detail: standardSpokenValues,
                        icon: "point.bottomleft.forward.to.point.topright.scurvepath"
                    ) { editingOption = .distanceUpdates }
                }
                if draft.timeTriggerEnabled {
                    announcementGroupRow(
                        title: tr("Every time interval", "Etter tid") +
                            " · " + ATHLTHAudioCoachOption.timedUpdates.detail(in: draft),
                        detail: standardSpokenValues,
                        icon: "clock.arrow.circlepath"
                    ) { editingOption = .timedUpdates }
                }
            } else {
                ForEach(draft.customRules) { rule in
                    announcementGroupRow(
                        title: rule.trigger == .distance
                            ? tr("Every", "Hver") + " \(rule.validatedInterval) m"
                            : tr("Every", "Hvert") + " \(rule.validatedInterval) s",
                        detail: rule.selectedMetrics.map(\.title).joined(separator: " · "),
                        icon: rule.trigger == .distance
                            ? "point.bottomleft.forward.to.point.topright.scurvepath"
                            : "clock.arrow.circlepath"
                    ) { editingOption = .customAnnouncements }
                }
            }
            if draft.smartPrompts.motivationEnabled {
                announcementGroupRow(
                    title: tr("Motivation", "Motivasjon") +
                        " · " + tr("every", "hvert") +
                        " \(draft.smartPrompts.motivationIntervalSeconds) s",
                    detail: tr("Motivational words, according to chosen style",
                               "Motiverende ord i valgt stil"),
                    icon: "sparkles"
                ) { editingOption = .motivation }
            }
            if periodicGroupCount == 0 {
                Text(tr("No recurring announcements", "Ingen gjentakende beskjeder"))
                    .font(.subheadline)
                    .foregroundStyle(dim)
                    .padding(.vertical, 6)
            }

            Button { editingOption = .customAnnouncements } label: {
                Label(tr("Create announcement group", "Opprett varslingsgruppe"),
                      systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(bronze)
            .accessibilityIdentifier("athlth-audio-coach-add-option")

            if !extraActiveOptions.isEmpty {
                Divider().overlay(ATHLTHPlanDesign.warmDivider)
                Text(tr("Events and special alerts", "Hendelser og spesialvarsler"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
                VStack(spacing: 0) {
                    ForEach(extraActiveOptions) { option in
                        activeRow(option)
                        if option != extraActiveOptions.last {
                            Divider().overlay(ATHLTHPlanDesign.warmDivider)
                        }
                    }
                }
            }
            Button { showingCatalogue = true } label: {
                Label(tr("Add other alert", "Legg til annet varsel"),
                      systemImage: "plus")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
        }
    }

    private func announcementGroupRow(
        title: String, detail: String, icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(bronze)
                    .frame(width: 36, height: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(dim)
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
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
                standardAnnouncementContents
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
                standardAnnouncementContents
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

    private var standardAnnouncementContents: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(tr("Read these values together", "Les opp disse verdiene samlet"))
                .font(.subheadline.weight(.semibold))
            Toggle(tr("Distance", "Distanse"), isOn: $draft.announceDistance)
            Toggle(tr("Elapsed time", "Medgått tid"), isOn: $draft.announceElapsedTime)
            Toggle(tr("Average pace", "Gjennomsnittstempo"),
                   isOn: $draft.announceAveragePace)
            Toggle(tr("Heart rate", "Puls"), isOn: $draft.announceHeartRate)
            Toggle(tr("Clock time", "Klokkeslett"), isOn: $draft.announceClockTime)
            Text(tr(
                "These values apply to standard distance/time updates. To give each interval different content, create a separate announcement group.",
                "Verdiene gjelder standard distanse- og tidsvarsler. Opprett egne varslingsgrupper for forskjellig innhold per intervall."
            ))
            .font(.caption)
            .foregroundStyle(dim)
        }
        .tint(bronze)
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
                        Text(rule.selectedMetrics.map(\.title).joined(separator: " · "))
                            .font(.subheadline.weight(.semibold))
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
            Text(tr("New announcement group", "Ny varslingsgruppe"))
                .font(.subheadline.weight(.semibold))
            Button {
                draft.enabled = true
                draft.smartPrompts.motivationEnabled = true
                draft.smartPrompts.motivationIntervalSeconds = 60
                editingOption = nil
            } label: {
                Label(tr("Every minute · motivational words",
                         "Hvert minutt · motiverende ord"),
                      systemImage: "sparkles")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            Button {
                // One tap saves the full bundle. No separate Add operation.
                if draft.addKilometerMetricsBundle() {
                    editingOption = nil
                }
            } label: {
                Label(tr("Add: Every kilometre · distance, time and heart-rate zone",
                         "Legg til: Hver km · distanse, tid og pulssone"),
                      systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(draft.customRules.count >= 20 || draft.customRules.contains {
                $0.trigger == .distance && $0.validatedInterval == 1_000 &&
                $0.selectedMetrics == [.distance, .elapsedTime, .heartRateZone]
            })
            Picker(tr("First value", "Første verdi"), selection: $newRuleMetric) {
                ForEach(ATHLTHAudioCoachRule.Metric.allCases) { metric in
                    Text(metric.title).tag(metric)
                }
            }
            multiMetricChoices(primary: newRuleMetric,
                               selected: $newRuleAdditionalMetrics)
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
                    }
                ))
            } label: {
                Label(tr("Add rule", "Legg til regel"), systemImage: "plus")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(draft.customRules.count >= 20)
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
                    .onChange(of: draft.language) { _, language in
                        // Azure selection sets Norwegian and a voice in the
                        // same action. Keep it; clear incompatible old voices.
                        if language != .norwegian ||
                           ATHLTHAzureCoachVoice.key(draft.voiceIdentifier) == nil {
                            draft.voiceIdentifier = nil
                        }
                    }
                    Picker(tr("Speaking style", "Snakkestil"),
                           selection: $draft.speechStyle) {
                        ForEach(ATHLTHCoachSpeechStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                    Text(tr("Choose and preview voice", "Velg og test stemme"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                    ATHLTHCoachVoiceChoices(
                        selectedIdentifier: $draft.voiceIdentifier,
                        language: draft.language,
                        speechRate: draft.speechRate,
                        speechVolume: draft.speechVolume,
                        duckOtherAudio: draft.duckOtherAudio,
                        speechStyle: draft.speechStyle
                    )
                    Divider().overlay(ATHLTHPlanDesign.warmDivider)
                    ATHLTHAzureCoachVoicePreviewView(
                        workoutVoiceIdentifier: $draft.voiceIdentifier,
                        workoutLanguage: $draft.language,
                        workoutDuckOtherAudio: draft.duckOtherAudio
                    )
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

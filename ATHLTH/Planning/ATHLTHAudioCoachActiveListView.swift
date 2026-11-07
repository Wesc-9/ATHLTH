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

    @AppStorage("athlth.audioCoach.editorMode.v2") private var editorMode = "basic"
    @State private var showingCatalogue = false
    @State private var showingVoice = false
    @State private var showingProfiles = false
    @State private var editingOption: ATHLTHAudioCoachOption?
    @State private var nextEditor: ATHLTHAudioCoachOption?
    @State private var pendingRemoval: ATHLTHAudioCoachOption?
    @State private var profileName = ""
    @State private var ruleSetName = ""
    @State private var phraseText = ""
    @State private var newRuleTrigger: ATHLTHAudioCoachRule.Trigger = .distance
    @State private var newRuleMetric: ATHLTHAudioCoachRule.Metric = .pace
    @State private var newRuleInterval = 1_000

    @State private var placeQuery = ""
    @State private var placeSide: ATHLTHCoachLandmarkSide = .unspecified
    @State private var placeKind: ATHLTHCoachLandmarkKind = .ordinary
    @State private var placeResults: [PlaceCandidate] = []
    @State private var searchingPlaces = false
    @State private var placeError: String?

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
            Text(tr(
                "Start running with concise distance, time and pace updates, encouragement and a finish summary.",
                "Løp med enkle oppdateringer om distanse, tid og tempo, oppmuntring og oppsummering ved mål."
            ))
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

            Button {
                draft.applySimpleAudioCoach()
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
                    Text(tr("ACTIVE COACH", "AKTIV COACH"))
                        .font(.caption2.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(bronze)
                    Text(tr("Active announcements", "Aktive beskjeder"))
                        .font(.system(size: 20, weight: .semibold, design: .serif))
                        .foregroundStyle(ink)
                }
                Spacer()
                Text("\(activeOptions.count)")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(bronze)
            }

            if activeOptions.isEmpty {
                Text(tr(
                    "Nothing is scheduled to be spoken. Add a message or trigger below.",
                    "Ingen beskjeder er aktivert. Legg til ønskede varsler nedenfor."
                ))
                .font(.subheadline)
                .foregroundStyle(dim)
            } else {
                VStack(spacing: 0) {
                    ForEach(activeOptions) { option in
                        activeRow(option)
                        if option != activeOptions.last {
                            Divider().overlay(ATHLTHPlanDesign.warmDivider)
                        }
                    }
                }
            }

            Button {
                showingCatalogue = true
            } label: {
                Label(tr("Add announcement or rule", "Legg til beskjed eller regel"),
                      systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 47)
            }
            .buttonStyle(.borderedProminent)
            .tint(bronze)
            .accessibilityIdentifier("athlth-audio-coach-add-option")

            if !draft.customRules.isEmpty {
                Text(tr(
                    "Independent rules replace the usual distance/time triggers to avoid duplicate announcements.",
                    "Egne regler erstatter de vanlige distanse- og tidsutløserne for å unngå doble beskjeder."
                ))
                .font(.caption)
                .foregroundStyle(dim)
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
            }
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
                    Picker(tr("Metric", "Innhold"), selection: $rule.metric) {
                        ForEach(ATHLTHAudioCoachRule.Metric.allCases) { metric in
                            Text(metric.title).tag(metric)
                        }
                    }
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
            Picker(tr("Metric", "Innhold"), selection: $newRuleMetric) {
                ForEach(ATHLTHAudioCoachRule.Metric.allCases) { metric in
                    Text(metric.title).tag(metric)
                }
            }
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
                    trigger: newRuleTrigger, metric: newRuleMetric, interval: newRuleInterval
                ))
            } label: {
                Label(tr("Add rule", "Legg til regel"), systemImage: "plus")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(draft.customRules.count >= 20)
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
                    NavigationLink {
                        ATHLTHCoachVoiceChoices(
                            selectedIdentifier: $draft.voiceIdentifier,
                            language: draft.language,
                            speechRate: draft.speechRate,
                            speechVolume: draft.speechVolume,
                            duckOtherAudio: draft.duckOtherAudio,
                            speechStyle: draft.speechStyle
                        )
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
                            Button {
                                draft.load(profile: profile)
                                showingProfiles = false
                            } label: {
                                HStack {
                                    Text(profile.name)
                                    Spacer()
                                    Image(systemName: "arrow.down.circle")
                                }
                                .frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
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
    }

    private func editorCard<Content: View>(
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        ATHLTHPlanSurface(ghost: false) {
            VStack(alignment: .leading, spacing: 14, content: content)
        }
    }
}

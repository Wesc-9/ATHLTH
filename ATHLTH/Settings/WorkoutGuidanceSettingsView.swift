import SwiftUI

struct ATHLTHWorkoutGuidanceSettingsView: View {
    @EnvironmentObject private var settings: AppSettingsStore

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        ATHLTHSettingsScreen(title: tr("Workout guidance", "Øktveiledning"),
                             subtitle: tr("Choose how ATHLTH guides you during workouts.", "Velg hvordan ATHLTH veileder deg under trening.")) {
            ATHLTHSettingsGroup(title: tr("Guidance", "Veiledning")) {
                PremiumSettingsCard {
                    guidanceLink("Audio coach", tr("Voice, motivation and custom triggers", "Stemme, motivasjon og egne triggere"),
                                 "waveform", settings.audioCoachEnabledByDefault ? tr("Active", "Aktiv") : tr("Customize", "Tilpass")) {
                        ATHLTHAudioCoachSettingsView()
                    }
                    SettingsDivider()
                    guidanceLink(tr("Strength coaching", "Styrkeveiledning"),
                                 tr("Rest countdown and set announcements", "Hvilenedtelling, sett og øvelser"),
                                 "dumbbell", nil) { ATHLTHStrengthCoachGlobalSettingsView() }
                    SettingsDivider()
                    guidanceLink(tr("Navigation", "Navigasjon"),
                                 tr("Turns and route deviation", "Svinger og ruteavvik"),
                                 "location.north.line", settings.routeAlertsEnabled ? "\(Int(settings.routeAlertDeviationMeters)) m" : tr("Off", "Av")) {
                        ATHLTHRouteGuardianSettingsView()
                    }
                    SettingsDivider()
                    guidanceLink("Ghost race", tr("Pacing and comparison updates", "Tempo og sammenligning"),
                                 "flag.checkered", settings.ghostRaceAudioEnabled ? tr("Voice on", "Stemme på") : tr("Silent", "Stille")) {
                        ATHLTHGhostUpdatesSettingsView()
                    }
                }
            }
            ATHLTHSettingsGroup(title: tr("Workout experience", "Øktopplevelse")) {
                PremiumSettingsCard {
                    guidanceLink(tr("Alert priority", "Prioritering av varsler"),
                                 tr("Order of guidance messages", "Rekkefølge på veiledningsmeldinger"),
                                 "list.number", nil) { ATHLTHGuidancePrioritySettingsView() }
                    SettingsDivider()
                    guidanceLink(tr("Watch, Lock Screen & Dynamic Island", "Klokke, låseskjerm og Dynamic Island"),
                                 tr("Widgets and live surfaces", "Widgeter og livevisninger"),
                                 "rectangle.3.group", nil) { ATHLTHWidgetsAndSurfacesSettingsView() }
                }
            }
            Text(tr("Changes never overwrite previously planned workouts.", "Endringer overskriver ikke tidligere planlagte økter."))
                .font(.caption).foregroundStyle(ATHLTHTheme.mutedText).padding(.horizontal, 8)
        }
    }

    private func guidanceLink<Destination: View>(
        _ title: String, _ subtitle: String, _ icon: String, _ status: String?,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            PremiumSettingsRow(icon: icon, iconTint: ATHLTHTheme.accentDeep,
                               iconBackground: ATHLTHTheme.premiumGoldSoft, title: title, subtitle: subtitle) {
                HStack(spacing: 8) {
                    if let status { Text(status).font(.caption).foregroundStyle(ATHLTHTheme.mutedText) }
                    Image(systemName: "chevron.right").foregroundStyle(ATHLTHTheme.mutedText)
                }
            }
        }.buttonStyle(.plain)
    }
}

/// Shares the same premium route editor as the workout's own Navigation
/// settings. Global changes update defaults; existing planned workouts remain
/// independent snapshots and are never silently overwritten.
struct ATHLTHRouteGuardianSettingsView: View {
    @EnvironmentObject private var settings: AppSettingsStore

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var routeDraft: Binding<RouteGuardianDraft> {
        Binding(
            get: {
                RouteGuardianDraft(
                    enabled: settings.routeAlertsEnabled,
                    deviationMeters: settings.routeAlertDeviationMeters,
                    graceSeconds: settings.routeAlertGraceSeconds,
                    repeatSeconds: settings.routeAlertRepeatSeconds,
                    delivery: settings.routeAlertDelivery,
                    announceBackOnRoute: settings.routeAlertAnnounceBackOnRoute,
                    announceUpcomingTurns: settings.routeAlertAnnounceUpcomingTurns,
                    turnCueLeadMeters: settings.routeAlertTurnCueLeadMeters
                )
            },
            set: { next in
                if settings.routeAlertsEnabled != next.enabled {
                    settings.routeAlertsEnabled = next.enabled
                }
                if settings.routeAlertDeviationMeters != next.deviationMeters {
                    settings.routeAlertDeviationMeters = next.deviationMeters
                }
                if settings.routeAlertGraceSeconds != next.graceSeconds {
                    settings.routeAlertGraceSeconds = next.graceSeconds
                }
                if settings.routeAlertRepeatSeconds != next.repeatSeconds {
                    settings.routeAlertRepeatSeconds = next.repeatSeconds
                }
                if settings.routeAlertDelivery != next.delivery {
                    settings.routeAlertDelivery = next.delivery
                }
                if settings.routeAlertAnnounceBackOnRoute != next.announceBackOnRoute {
                    settings.routeAlertAnnounceBackOnRoute = next.announceBackOnRoute
                }
                if settings.routeAlertAnnounceUpcomingTurns != next.announceUpcomingTurns {
                    settings.routeAlertAnnounceUpcomingTurns = next.announceUpcomingTurns
                }
                if settings.routeAlertTurnCueLeadMeters != next.turnCueLeadMeters {
                    settings.routeAlertTurnCueLeadMeters = next.turnCueLeadMeters
                }
            }
        )
    }

    var body: some View {
        ScrollView {
            ATHLTHRouteGuidanceStudioView(draft: routeDraft)
                .frame(maxWidth: ATHLTHPlanDesign.maxContentWidth)
                .frame(maxWidth: .infinity)
                .padding(16)
        }
        .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
        .tint(ATHLTHPlanDesign.accentInk)
        .navigationTitle(tr("Navigation", "Navigasjon"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private enum GhostRaceUpdatePreset:
    String,
    CaseIterable,
    Identifiable
{
    case quiet
    case normal
    case competition
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quiet:
            return ATHLTHLocalization.choose(
                english: "Quiet",
                norwegian: "Rolig"
            )
        case .normal:
            return ATHLTHLocalization.choose(
                english: "Normal",
                norwegian: "Normal"
            )
        case .competition:
            return ATHLTHLocalization.choose(
                english: "Competition",
                norwegian: "Konkurranse"
            )
        case .custom:
            return ATHLTHLocalization.choose(
                english: "Custom",
                norwegian: "Egendefinert"
            )
        }
    }


}

struct ATHLTHGhostUpdatesSettingsView: View {
    @EnvironmentObject private var settings:
        AppSettingsStore

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                ATHLTHPlanSectionIntro(
                    eyebrow: tr("RACE EXPERIENCE", "KONKURRANSEOPPLEVELSE"),
                    title: "Ghost Race",
                    subtitle: tr(
                        "Race a target with useful updates, not constant interruptions.",
                        "Konkurrer mot et mål med nyttige oppdateringer, ikke stadige avbrytelser."
                    ),
                    icon: "figure.run.circle"
                )

                ATHLTHPlanSurface(ghost: false) {
                    Toggle(isOn: $settings.ghostRaceAudioEnabled) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tr("Spoken Ghost updates", "Oppleste Ghost-oppdateringer"))
                                .font(.headline)
                            Text(tr("The on-screen Ghost stays visible if voice is off.",
                                    "Ghost vises fortsatt på skjermen når lyd er av."))
                                .font(.caption)
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                    }
                    .tint(ATHLTHPlanDesign.accentInk)
                }

                if settings.ghostRaceAudioEnabled {
                    presetCard
                    cadenceCard
                    eventCard
                    advancedCard
                }

                Text(tr(
                    "These are defaults. Target time, pacing strategy and spoken updates can also be tailored to each workout.",
                    "Dette er standardvalg. Måltid, tempotaktikk og taleoppdateringer kan også tilpasses hver enkelt økt."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                .padding(.horizontal, 4)
            }
            .frame(maxWidth: ATHLTHPlanDesign.maxContentWidth)
            .frame(maxWidth: .infinity)
            .padding(16)
        }
        .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
        .tint(ATHLTHPlanDesign.accentInk)
        .navigationTitle("Ghost Race")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var presetCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(tr("HOW OFTEN SHOULD GHOST SPEAK?", "HVOR OFTE SKAL GHOST SNAKKE?"))
                .font(.caption.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            HStack(spacing: 9) {
                ForEach([
                    GhostRaceUpdatePreset.quiet,
                    .normal,
                    .competition
                ]) { preset in
                    let selected = presetBinding.wrappedValue == preset
                    Button {
                        applyPreset(preset)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: preset == .quiet
                                  ? "speaker.slash" :
                                  preset == .competition
                                    ? "flag.checkered" : "waveform")
                                .font(.title3)
                            Text(preset.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 72)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .background(
                            selected
                                ? Color(red: 0.18, green: 0.20, blue: 0.23)
                                : Color(red: 0.95, green: 0.95, blue: 0.94),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            if presetBinding.wrappedValue == .custom {
                Label(tr("Custom settings", "Egendefinerte innstillinger"),
                      systemImage: "slider.horizontal.3")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(presetDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
    }

    private var cadenceCard: some View {
        ATHLTHPlanSurface(ghost: false) {
            heading(tr("Live comparison", "Sammenligning underveis"), "stopwatch")
            Toggle(tr("Status after distance", "Status etter distanse"),
                   isOn: $settings.ghostRaceAudioUseDistance)
            if settings.ghostRaceAudioUseDistance {
                Picker(tr("Distance interval", "Distanseintervall"),
                       selection: $settings.ghostRaceAudioDistanceIntervalKilometers) {
                    Text("250 m").tag(0.25)
                    Text("500 m").tag(0.5)
                    Text("1 km").tag(1.0)
                    Text("2 km").tag(2.0)
                    Text("5 km").tag(5.0)
                }
                .pickerStyle(.menu)
            }
            Toggle(tr("Status after time", "Status etter tid"),
                   isOn: $settings.ghostRaceAudioUseTime)
            if settings.ghostRaceAudioUseTime {
                Picker(tr("Time interval", "Tidsintervall"),
                       selection: $settings.ghostRaceAudioTimeIntervalMinutes) {
                    Text("2 min").tag(2)
                    Text("5 min").tag(5)
                    Text("10 min").tag(10)
                    Text("15 min").tag(15)
                }
                .pickerStyle(.menu)
            }
            Picker(tr("Status includes", "Status inneholder"),
                   selection: $settings.ghostRaceStatusDetailMode) {
                ForEach(GhostRaceStatusDetailMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)
            Picker(tr("Status delivery", "Status varsles med"),
                   selection: $settings.ghostRaceAudioDelivery) {
                ForEach(WatchAlertDelivery.allCases) { delivery in
                    Text(delivery.title).tag(delivery)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var eventCard: some View {
        ATHLTHPlanSurface(ghost: false) {
            heading(tr("Race moments", "Løpsøyeblikk"), "flag.checkered")
            Toggle(tr("Overtaking alerts", "Forbikjøringsvarsler"),
                   isOn: $settings.ghostRaceAnnounceOvertakes)
            Toggle(tr("Final stretch", "Siste etappe"),
                   isOn: $settings.ghostRaceFinalPhaseEnabled)
            if settings.ghostRaceFinalPhaseEnabled {
                Picker(tr("Final stretch begins", "Start siste etappe"),
                       selection: $settings.ghostRaceFinalPhaseStartMeters) {
                    Text("200 m").tag(200.0)
                    Text("500 m").tag(500.0)
                    Text("1 km").tag(1_000.0)
                }
                .pickerStyle(.menu)
            }
            Toggle(tr("Live connection alerts", "Varsler om live-tilkobling"),
                   isOn: $settings.ghostRaceLiveConnectionAlerts)
        }
    }

    private var advancedCard: some View {
        ATHLTHPlanSurface(ghost: false) {
            DisclosureGroup {
                Toggle(tr("Extra lead changes", "Ekstra ledelsesendringer"),
                       isOn: $settings.ghostRaceAudioAnnounceLeadChanges)
                if settings.ghostRaceAudioAnnounceLeadChanges {
                    Picker(tr("Lead-change threshold", "Terskel for endring"),
                           selection: $settings.ghostRaceAudioLeadChangeMeters) {
                        Text("15 m").tag(15.0)
                        Text("25 m").tag(25.0)
                        Text("50 m").tag(50.0)
                        Text("100 m").tag(100.0)
                    }
                    Picker(tr("Normal change delivery", "Vanlige endringer"),
                           selection: $settings.ghostRaceAudioLeadChangeDelivery) {
                        ForEach(WatchAlertDelivery.allCases) { delivery in
                            Text(delivery.title).tag(delivery)
                        }
                    }
                    Picker(tr("Important change threshold", "Stor endring"),
                           selection: $settings.ghostRaceAudioImportantLeadChangeMeters) {
                        Text("50 m").tag(50.0)
                        Text("75 m").tag(75.0)
                        Text("100 m").tag(100.0)
                        Text("150 m").tag(150.0)
                    }
                    Picker(tr("Important change delivery", "Viktig endring varsles med"),
                           selection: $settings.ghostRaceAudioImportantLeadChangeDelivery) {
                        ForEach(WatchAlertDelivery.allCases) { delivery in
                            Text(delivery.title).tag(delivery)
                        }
                    }
                }
                Text(tr(
                    "Small GPS variations around equal pace are automatically filtered.",
                    "Små GPS-variasjoner ved jevn konkurranse filtreres automatisk."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            } label: {
                heading(tr("Advanced race alerts", "Avanserte konkurransevarsler"),
                        "slider.horizontal.3")
            }
        }
    }

    private func heading(_ title: String, _ icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 19, weight: .semibold, design: .serif))
            .foregroundStyle(ATHLTHPlanDesign.ink)
    }

    private var presetBinding:
        Binding<GhostRaceUpdatePreset> {
        Binding(
            get: { currentPreset },
            set: { applyPreset($0) }
        )
    }

    private var currentPreset:
        GhostRaceUpdatePreset {
        let distance =
            settings
                .ghostRaceAudioUseDistance
        let time =
            settings
                .ghostRaceAudioUseTime
        let km =
            settings
                .ghostRaceAudioDistanceIntervalKilometers
        let leads =
            settings
                .ghostRaceAudioAnnounceLeadChanges
        let overtakes =
            settings
                .ghostRaceAnnounceOvertakes
        let finalPhase =
            settings
                .ghostRaceFinalPhaseEnabled
        let finalMeters =
            settings
                .ghostRaceFinalPhaseStartMeters
        let statusMode =
            settings
                .ghostRaceStatusDetailMode
        let connectionAlerts =
            settings
                .ghostRaceLiveConnectionAlerts

        if distance &&
            !time &&
            abs(km - 1.0) < 0.01 &&
            !leads &&
            !overtakes &&
            !finalPhase &&
            statusMode == .both &&
            connectionAlerts {
            return .quiet
        }

        if distance &&
            !time &&
            abs(km - 1.0) < 0.01 &&
            !leads &&
            overtakes &&
            finalPhase &&
            abs(finalMeters - 500) < 1 &&
            statusMode == .both &&
            connectionAlerts {
            return .normal
        }

        if distance &&
            !time &&
            abs(km - 0.5) < 0.01 &&
            leads &&
            overtakes &&
            finalPhase &&
            abs(finalMeters - 1_000) < 1 &&
            statusMode == .both &&
            connectionAlerts {
            return .competition
        }

        return .custom
    }

    private var presetDescription:
        String {
        switch currentPreset {
        case .quiet:
            return ATHLTHLocalization.choose(
                english:
                    "Only calm periodic status updates.",
                norwegian:
                    "Kun rolige, faste statusoppdateringer."
            )
        case .normal:
            return ATHLTHLocalization.choose(
                english:
                    "1 km status, overtakes and a 500 m final-phase alert.",
                norwegian:
                    "Status hver kilometer, forbikjøringer og sluttfase ved 500 meter."
            )
        case .competition:
            return ATHLTHLocalization.choose(
                english:
                    "More active racing: 500 m status, overtakes, final phase and meaningful lead changes.",
                norwegian:
                    "Mer aktiv konkurranse: status hver 500 meter, forbikjøringer, sluttfase og tydelige ledelsesendringer."
            )
        case .custom:
            return ATHLTHLocalization.choose(
                english:
                    "Uses your custom Ghost settings below.",
                norwegian:
                    "Bruker dine egendefinerte Ghost-innstillinger under."
            )
        }
    }

    private func applyPreset(
        _ preset: GhostRaceUpdatePreset
    ) {
        guard preset != .custom else {
            return
        }

        settings.ghostRaceStatusDetailMode =
            .both
        settings.ghostRaceAudioUseDistance =
            true
        settings.ghostRaceAudioUseTime =
            false
        settings.ghostRaceAudioDelivery =
            .voice
        settings.ghostRaceLiveConnectionAlerts =
            true
        settings.ghostRaceAudioLeadChangeDelivery =
            .haptic
        settings
            .ghostRaceAudioImportantLeadChangeDelivery =
            .both

        switch preset {
        case .quiet:
            settings
                .ghostRaceAudioDistanceIntervalKilometers =
                1.0
            settings
                .ghostRaceAnnounceOvertakes =
                false
            settings
                .ghostRaceFinalPhaseEnabled =
                false
            settings
                .ghostRaceAudioAnnounceLeadChanges =
                false

        case .normal:
            settings
                .ghostRaceAudioDistanceIntervalKilometers =
                1.0
            settings
                .ghostRaceAnnounceOvertakes =
                true
            settings
                .ghostRaceFinalPhaseEnabled =
                true
            settings
                .ghostRaceFinalPhaseStartMeters =
                500
            settings
                .ghostRaceAudioAnnounceLeadChanges =
                false

        case .competition:
            settings
                .ghostRaceAudioDistanceIntervalKilometers =
                0.5
            settings
                .ghostRaceAnnounceOvertakes =
                true
            settings
                .ghostRaceFinalPhaseEnabled =
                true
            settings
                .ghostRaceFinalPhaseStartMeters =
                1_000
            settings
                .ghostRaceAudioAnnounceLeadChanges =
                true
            settings
                .ghostRaceAudioLeadChangeMeters =
                50
            settings
                .ghostRaceAudioImportantLeadChangeMeters =
                100

        case .custom:
            break
        }
    }
}

struct ATHLTHGuidancePrioritySettingsView: View {
    @EnvironmentObject private var settings:
        AppSettingsStore
    @EnvironmentObject private var watchConnection:
        AppleWatchConnectionStore

    @State private var liveConfiguration =
        ATHLTHLiveWorkoutPreferencesStore
            .load()

    var body: some View {
        Form {
            Section("Master delivery") {
                Toggle(
                    "Haptic alerts",
                    isOn:
                        $liveConfiguration
                            .hapticsEnabled
                )

                Toggle(
                    "Voice alerts",
                    isOn:
                        $liveConfiguration
                            .audioAlertsEnabled
                )

                Text(
                    "These master switches control Navigation, target and Ghost alerts. Routine Audio Coach has its own on/off setting."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Priority order") {
                priorityRow(
                    "1",
                    ATHLTHLocalization.choose(english: "Navigation", norwegian: "Navigasjon"),
                    "Off-route and return-to-route"
                )
                priorityRow(
                    "2",
                    "Workout target",
                    "Heart-rate or pace target alerts"
                )
                priorityRow(
                    "3",
                    "Workout step",
                    "Interval and structured-step changes"
                )
                priorityRow(
                    "4",
                    "Important Ghost",
                    "Lead flips and large changes"
                )
                priorityRow(
                    "5",
                    "Ghost status",
                    "Periodic race comparison"
                )
                priorityRow(
                    "6",
                    "Audio Coach",
                    "Routine workout metrics"
                )
            }

            Section("After an important cue") {
                Picker(
                    "Quiet period",
                    selection:
                        $settings
                            .guidanceQuietPeriodSeconds
                ) {
                    Text("5 sec").tag(5)
                    Text("8 sec").tag(8)
                    Text("10 sec").tag(10)
                    Text("12 sec").tag(12)
                    Text("15 sec").tag(15)
                }

                Text(
                    "Routine Audio Coach and periodic Ghost updates are dropped during this period instead of being queued and played late."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .athlthBrandedForm()
        .navigationTitle("Alert Priority")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            liveConfiguration =
                ATHLTHLiveWorkoutPreferencesStore
                    .load()
        }
        .onChange(
            of: liveConfiguration
        ) { _, configuration in
            ATHLTHLiveWorkoutPreferencesStore
                .save(configuration)
            watchConnection
                .sendLiveSurfaceConfiguration(
                    configuration
                )
        }
    }

    @ViewBuilder
    private func priorityRow(
        _ number: String,
        _ title: String,
        _ subtitle: String
    ) -> some View {
        HStack(spacing: 12) {
            Text(number)
                .font(
                    .caption.weight(.bold)
                )
                .frame(width: 26, height: 26)
                .background(
                    ATHLTHTheme
                        .surfaceSage,
                    in: Circle()
                )

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(title)
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

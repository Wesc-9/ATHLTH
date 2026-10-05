import SwiftUI

struct ATHLTHWorkoutGuidanceSettingsView: View {
    @EnvironmentObject private var settings:
        AppSettingsStore

    var body: some View {
        List {
            Section {
                NavigationLink {
                    ATHLTHAudioCoachSettingsView()
                } label: {
                    guidanceRow(
                        title: "Audio Coach",
                        subtitle:
                            audioCoachSummary,
                        icon:
                            "waveform.and.mic",
                        tint:
                            ATHLTHTheme
                                .premiumGold
                    )
                }

                NavigationLink {
                    ATHLTHRouteGuardianSettingsView()
                } label: {
                    guidanceRow(
                        title: "Route Guardian",
                        subtitle:
                            routeGuardianSummary,
                        icon:
                            "location.fill",
                        tint:
                            ATHLTHTheme.vitality
                    )
                }

                NavigationLink {
                    ATHLTHGhostUpdatesSettingsView()
                } label: {
                    guidanceRow(
                        title: "Ghost Updates",
                        subtitle:
                            ghostSummary,
                        icon:
                            "figure.run.circle",
                        tint:
                            ATHLTHTheme.accent
                    )
                }

                NavigationLink {
                    ATHLTHGuidancePrioritySettingsView()
                } label: {
                    guidanceRow(
                        title: "Alert priority",
                        subtitle:
                            "Critical guidance always wins over routine updates",
                        icon:
                            "list.number",
                        tint:
                            .orange
                    )
                }

                NavigationLink {
                    ATHLTHWidgetsAndSurfacesSettingsView()
                } label: {
                    guidanceRow(
                        title: "Live workout display",
                        subtitle:
                            "Dynamic Island, Lock Screen and Apple Watch focus",
                        icon:
                            "rectangle.3.group.bubble.left.fill",
                        tint:
                            ATHLTHTheme.recoveryBlue
                    )
                }
            } header: {
                Text("Workout guidance")
            } footer: {
                Text(
                    "Audio Coach reports your workout. Route Guardian keeps you on course. Ghost Updates compares you with a reference run. ATHLTH prioritizes safety and workout instructions when several signals happen together."
                )
            }
        }
        .navigationTitle("Workout Guidance")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func guidanceRow(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(
                    .system(
                        size: 17,
                        weight: .semibold
                    )
                )
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(
                    tint.opacity(0.11),
                    in:
                        RoundedRectangle(
                            cornerRadius: 11,
                            style: .continuous
                        )
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
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 3)
    }

    private var audioCoachSummary: String {
        settings.audioCoachEnabledByDefault
            ? "On by default · pace, distance and workout instructions"
            : "Off by default · configurable per workout"
    }

    private var routeGuardianSummary: String {
        guard settings.routeAlertsEnabled
        else {
            return "Off"
        }

        return
            "Alert at " +
            String(
                format:
                    "%.0f m",
                settings
                    .routeAlertDeviationMeters
            ) +
            " off route"
    }

    private var ghostSummary: String {
        guard settings.ghostRaceAudioEnabled
        else {
            return "Silent · live comparison still stays visible"
        }

        return ATHLTHLocalization.choose(
            english:
                "Race status + selected race events",
            norwegian:
                "Løpsstatus + valgte løpshendelser"
        )
    }
}

struct ATHLTHRouteGuardianSettingsView: View {
    @EnvironmentObject private var settings:
        AppSettingsStore

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Off-route alerts",
                    isOn:
                        $settings
                            .routeAlertsEnabled
                )
            } footer: {
                Text(
                    "Route Guardian is independent from Audio Coach and Ghost Updates. Critical route warnings have the highest guidance priority."
                )
            }

            if settings.routeAlertsEnabled {
                Section("Trigger") {
                    Picker(
                        "Alert when off route",
                        selection:
                            $settings
                                .routeAlertDeviationMeters
                    ) {
                        Text("25 m").tag(25.0)
                        Text("50 m").tag(50.0)
                        Text("80 m").tag(80.0)
                        Text("100 m").tag(100.0)
                        Text("150 m").tag(150.0)
                        Text("250 m").tag(250.0)
                    }

                    Picker(
                        "Wait before alert",
                        selection:
                            $settings
                                .routeAlertGraceSeconds
                    ) {
                        Text("Immediately").tag(0)
                        Text("5 sec").tag(5)
                        Text("10 sec").tag(10)
                        Text("20 sec").tag(20)
                        Text("30 sec").tag(30)
                    }

                    Picker(
                        "Repeat while off route",
                        selection:
                            $settings
                                .routeAlertRepeatSeconds
                    ) {
                        Text("30 sec").tag(30)
                        Text("1 min").tag(60)
                        Text("2 min").tag(120)
                        Text("5 min").tag(300)
                    }
                }

                Section("Delivery") {
                    Picker(
                        "Alert style",
                        selection:
                            $settings
                                .routeAlertDelivery
                    ) {
                        ForEach(
                            WatchAlertDelivery
                                .allCases
                        ) { delivery in
                            Text(delivery.title)
                                .tag(delivery)
                        }
                    }

                    Toggle(
                        "Tell me when I'm back on route",
                        isOn:
                            $settings
                                .routeAlertAnnounceBackOnRoute
                    )
                }
            }
        }
        .navigationTitle("Route Guardian")
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

    var body: some View {
        Form {
            Section {
                Toggle(
                    ATHLTHLocalization.choose(
                        english: "Ghost Updates",
                        norwegian: "Ghost-oppdateringer"
                    ),
                    isOn:
                        $settings
                            .ghostRaceAudioEnabled
                )
            } footer: {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Ghost remains visible even when updates are off. These settings apply to iPhone and Apple Watch.",
                        norwegian:
                            "Ghost er fortsatt synlig selv om oppdateringer er av. Innstillingene gjelder både iPhone og Apple Watch."
                    )
                )
            }

            if settings.ghostRaceAudioEnabled {
                Section(
                    ATHLTHLocalization.choose(
                        english: "Update style",
                        norwegian: "Oppdateringsstil"
                    )
                ) {
                    Picker(
                        ATHLTHLocalization.choose(
                            english: "Preset",
                            norwegian: "Oppsett"
                        ),
                        selection: presetBinding
                    ) {
                        ForEach(
                            GhostRaceUpdatePreset
                                .allCases
                        ) { preset in
                            Text(preset.title)
                                .tag(preset)
                        }
                    }

                    Text(presetDescription)
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                }

                Section(
                    ATHLTHLocalization.choose(
                        english: "Periodic race status",
                        norwegian: "Fast løpsstatus"
                    )
                ) {
                    Toggle(
                        ATHLTHLocalization.choose(
                            english: "Every distance interval",
                            norwegian: "Etter fast avstand"
                        ),
                        isOn:
                            $settings
                                .ghostRaceAudioUseDistance
                    )

                    if settings
                        .ghostRaceAudioUseDistance {
                        Picker(
                            ATHLTHLocalization.choose(
                                english: "Distance interval",
                                norwegian: "Avstandsintervall"
                            ),
                            selection:
                                $settings
                                    .ghostRaceAudioDistanceIntervalKilometers
                        ) {
                            Text("0.5 km")
                                .tag(0.5)
                            Text("1 km")
                                .tag(1.0)
                            Text("2 km")
                                .tag(2.0)
                            Text("5 km")
                                .tag(5.0)
                        }
                    }

                    Toggle(
                        ATHLTHLocalization.choose(
                            english: "Every time interval",
                            norwegian: "Etter fast tid"
                        ),
                        isOn:
                            $settings
                                .ghostRaceAudioUseTime
                    )

                    if settings
                        .ghostRaceAudioUseTime {
                        Picker(
                            ATHLTHLocalization.choose(
                                english: "Time interval",
                                norwegian: "Tidsintervall"
                            ),
                            selection:
                                $settings
                                    .ghostRaceAudioTimeIntervalMinutes
                        ) {
                            Text("2 min")
                                .tag(2)
                            Text("5 min")
                                .tag(5)
                            Text("10 min")
                                .tag(10)
                            Text("15 min")
                                .tag(15)
                        }
                    }

                    Picker(
                        ATHLTHLocalization.choose(
                            english: "Status includes",
                            norwegian: "Status inneholder"
                        ),
                        selection:
                            $settings
                                .ghostRaceStatusDetailMode
                    ) {
                        ForEach(
                            GhostRaceStatusDetailMode
                                .allCases
                        ) { mode in
                            Text(mode.title)
                                .tag(mode)
                        }
                    }

                    Picker(
                        ATHLTHLocalization.choose(
                            english: "Periodic delivery",
                            norwegian: "Levering"
                        ),
                        selection:
                            $settings
                                .ghostRaceAudioDelivery
                    ) {
                        ForEach(
                            WatchAlertDelivery
                                .allCases
                        ) { delivery in
                            Text(delivery.title)
                                .tag(delivery)
                        }
                    }
                }

                Section(
                    ATHLTHLocalization.choose(
                        english: "Race events",
                        norwegian: "Løpshendelser"
                    )
                ) {
                    Toggle(
                        ATHLTHLocalization.choose(
                            english: "Overtake alerts",
                            norwegian: "Forbikjøringsvarsler"
                        ),
                        isOn:
                            $settings
                                .ghostRaceAnnounceOvertakes
                    )

                    Toggle(
                        ATHLTHLocalization.choose(
                            english: "Final phase alert",
                            norwegian: "Sluttfasevarsel"
                        ),
                        isOn:
                            $settings
                                .ghostRaceFinalPhaseEnabled
                    )

                    if settings
                        .ghostRaceFinalPhaseEnabled {
                        Picker(
                            ATHLTHLocalization.choose(
                                english: "Final phase starts",
                                norwegian: "Sluttfasen starter"
                            ),
                            selection:
                                $settings
                                    .ghostRaceFinalPhaseStartMeters
                        ) {
                            Text("200 m")
                                .tag(200.0)
                            Text("500 m")
                                .tag(500.0)
                            Text("1 km")
                                .tag(1_000.0)
                        }
                    }

                    Toggle(
                        ATHLTHLocalization.choose(
                            english: "Live connection alerts",
                            norwegian: "Live-tilkoblingsvarsler"
                        ),
                        isOn:
                            $settings
                                .ghostRaceLiveConnectionAlerts
                    )
                }

                Section(
                    ATHLTHLocalization.choose(
                        english: "Advanced lead changes",
                        norwegian: "Avanserte ledelsesendringer"
                    )
                ) {
                    Toggle(
                        ATHLTHLocalization.choose(
                            english: "Extra lead-change alerts",
                            norwegian: "Ekstra ledelsesvarsler"
                        ),
                        isOn:
                            $settings
                                .ghostRaceAudioAnnounceLeadChanges
                    )

                    if settings
                        .ghostRaceAudioAnnounceLeadChanges {
                        Picker(
                            ATHLTHLocalization.choose(
                                english: "Change threshold",
                                norwegian: "Endringsterskel"
                            ),
                            selection:
                                $settings
                                    .ghostRaceAudioLeadChangeMeters
                        ) {
                            Text("15 m")
                                .tag(15.0)
                            Text("25 m")
                                .tag(25.0)
                            Text("50 m")
                                .tag(50.0)
                            Text("100 m")
                                .tag(100.0)
                        }

                        Picker(
                            ATHLTHLocalization.choose(
                                english: "Normal lead change",
                                norwegian: "Normal ledelsesendring"
                            ),
                            selection:
                                $settings
                                    .ghostRaceAudioLeadChangeDelivery
                        ) {
                            ForEach(
                                WatchAlertDelivery
                                    .allCases
                            ) { delivery in
                                Text(delivery.title)
                                    .tag(delivery)
                            }
                        }

                        Picker(
                            ATHLTHLocalization.choose(
                                english: "Important change",
                                norwegian: "Viktig endring"
                            ),
                            selection:
                                $settings
                                    .ghostRaceAudioImportantLeadChangeMeters
                        ) {
                            Text("50 m")
                                .tag(50.0)
                            Text("75 m")
                                .tag(75.0)
                            Text("100 m")
                                .tag(100.0)
                            Text("150 m")
                                .tag(150.0)
                        }

                        Picker(
                            ATHLTHLocalization.choose(
                                english: "Important delivery",
                                norwegian: "Viktig levering"
                            ),
                            selection:
                                $settings
                                    .ghostRaceAudioImportantLeadChangeDelivery
                        ) {
                            ForEach(
                                WatchAlertDelivery
                                    .allCases
                            ) { delivery in
                                Text(delivery.title)
                                    .tag(delivery)
                            }
                        }
                    }
                }

                Section {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Distance/time is the normal cadence. Overtakes, final phase and optional lead changes are separate events between those updates. Small GPS movement around neck-and-neck is filtered automatically.",
                            norwegian:
                                "Avstand/tid er den normale rytmen. Forbikjøring, sluttfase og valgfrie ledelsesendringer er egne hendelser mellom disse oppdateringene. Små GPS-svingninger rundt helt jevnt filtreres automatisk."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(
            ATHLTHLocalization.choose(
                english: "Ghost Updates",
                norwegian: "Ghost-oppdateringer"
            )
        )
        .navigationBarTitleDisplayMode(.inline)
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
                    "These master switches control Route Guardian, target and Ghost alerts. Routine Audio Coach has its own on/off setting."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Priority order") {
                priorityRow(
                    "1",
                    "Route Guardian",
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

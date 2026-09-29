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

        return
            "Race status + meaningful lead changes"
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

struct ATHLTHGhostUpdatesSettingsView: View {
    @EnvironmentObject private var settings:
        AppSettingsStore

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Ghost Updates",
                    isOn:
                        $settings
                            .ghostRaceAudioEnabled
                )
            } footer: {
                Text(
                    "Ghost remains visible even when spoken updates are off. These settings apply to iPhone and Apple Watch."
                )
            }

            if settings.ghostRaceAudioEnabled {
                Section("Periodic race status") {
                    Toggle(
                        "Every distance interval",
                        isOn:
                            $settings
                                .ghostRaceAudioUseDistance
                    )

                    if settings
                        .ghostRaceAudioUseDistance {
                        Picker(
                            "Distance interval",
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
                        "Every time interval",
                        isOn:
                            $settings
                                .ghostRaceAudioUseTime
                    )

                    if settings
                        .ghostRaceAudioUseTime {
                        Picker(
                            "Time interval",
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
                        "Periodic delivery",
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

                Section("Lead changes") {
                    Toggle(
                        "Meaningful lead changes",
                        isOn:
                            $settings
                                .ghostRaceAudioAnnounceLeadChanges
                    )

                    if settings
                        .ghostRaceAudioAnnounceLeadChanges {
                        Picker(
                            "Change threshold",
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
                            "Normal lead change",
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
                            "Important change",
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
                            "Important delivery",
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
                        "A switch from ahead to behind is always treated as important. Important Ghost events can use voice; smaller changes can stay haptic-only."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Ghost Updates")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ATHLTHGuidancePrioritySettingsView: View {
    @EnvironmentObject private var settings:
        AppSettingsStore

    var body: some View {
        Form {
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

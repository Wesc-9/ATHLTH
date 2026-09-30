import SwiftUI

struct RouteGuardianDraft {
    var enabled = true
    var deviationMeters = 80.0
    var graceSeconds = 10
    var repeatSeconds = 120
    var delivery:
        WatchAlertDelivery = .both
    var announceBackOnRoute = true

    @MainActor
    mutating func load(
        from settings: AppSettingsStore
    ) {
        enabled =
            settings.routeAlertsEnabled
        deviationMeters =
            settings.routeAlertDeviationMeters
        graceSeconds =
            settings.routeAlertGraceSeconds
        repeatSeconds =
            settings.routeAlertRepeatSeconds
        delivery =
            settings.routeAlertDelivery
        announceBackOnRoute =
            settings
                .routeAlertAnnounceBackOnRoute
    }

    var configuration:
        WatchRouteAlertConfiguration {
        WatchRouteAlertConfiguration(
            enabled: enabled,
            deviationMeters:
                min(
                    max(
                        deviationMeters,
                        20
                    ),
                    500
                ),
            graceSeconds:
                TimeInterval(
                    min(
                        max(
                            graceSeconds,
                            0
                        ),
                        120
                    )
                ),
            repeatSeconds:
                TimeInterval(
                    min(
                        max(
                            repeatSeconds,
                            30
                        ),
                        600
                    )
                ),
            delivery: delivery,
            announceBackOnRoute:
                announceBackOnRoute
        )
    }
}

struct GhostQuickStartDraft {
    var enabled = false
    var targetTimeText = ""
    var updatesEnabled = true
    private var loadedRouteID: UUID?

    init() {}

    @MainActor
    mutating func load(
        route: TrainingRoute?,
        settings: AppSettingsStore
    ) {
        updatesEnabled =
            settings
                .ghostRaceAudioEnabled

        guard let route else {
            loadedRouteID = nil
            targetTimeText = ""
            enabled = false
            return
        }

        guard loadedRouteID != route.id
        else {
            return
        }

        loadedRouteID = route.id

        let seconds =
            route
                .expectedTravelTimeSeconds ??
            max(
                route.distanceKilometers *
                    330,
                5 * 60
            )
        targetTimeText =
            GhostTargetTimeFormatter
                .string(seconds)
    }

    var targetDuration:
        TimeInterval? {
        guard enabled else {
            return nil
        }

        return GhostTargetTimeFormatter
            .parse(targetTimeText)
    }
}

struct RunGuidanceSetupView: View {
    @Binding var audioCoach:
        AudioCoachDraft
    @Binding var routeGuardian:
        RouteGuardianDraft
    @Binding var ghost:
        GhostQuickStartDraft

    let route: TrainingRoute?
    let structuredWorkout:
        RunningWorkoutTemplate?

    var body: some View {
        List {
            Section {
                NavigationLink {
                    PerWorkoutAudioCoachView(
                        draft:
                            $audioCoach,
                        showRouteOptions:
                            route != nil ||
                            structuredWorkout?
                                .routeID != nil,
                        showStructuredOptions:
                            structuredWorkout != nil
                    )
                } label: {
                    guidanceRow(
                        title: "Audio Coach",
                        subtitle:
                            audioCoach.enabled
                                ? "On for this workout"
                                : "Off for this workout",
                        icon:
                            "waveform.and.mic"
                    )
                }

                NavigationLink {
                    PerWorkoutRouteGuardianView(
                        draft:
                            $routeGuardian
                    )
                } label: {
                    guidanceRow(
                        title: "Route Guardian",
                        subtitle:
                            routeGuardian.enabled
                                ? "Alert at \(Int(routeGuardian.deviationMeters.rounded())) m"
                                : "Off for this workout",
                        icon:
                            "location.fill"
                    )
                }

                if route != nil {
                    NavigationLink {
                        PerWorkoutGhostView(
                            draft: $ghost,
                            route: route
                        )
                    } label: {
                        guidanceRow(
                            title: "Ghost Updates",
                            subtitle:
                                ghost.enabled
                                    ? "Target \(ghost.targetTimeText)"
                                    : "Off for this workout",
                            icon:
                                "figure.run.circle"
                        )
                    }
                }
            } header: {
                Text("Guidance & Alerts")
            } footer: {
                Text(
                    "These choices apply only to this workout. Your defaults remain unchanged in Settings → Workout Guidance."
                )
            }

            Section {
                NavigationLink {
                    ATHLTHWorkoutGuidanceSettingsView()
                } label: {
                    Label(
                        "Edit global defaults",
                        systemImage: "gearshape"
                    )
                }
            }
        }
        .navigationTitle("Guidance & Alerts")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func guidanceRow(
        title: String,
        subtitle: String,
        icon: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(
                    ATHLTHTheme.vitality
                )
                .frame(width: 30)

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
        .padding(.vertical, 3)
    }
}

struct PerWorkoutAudioCoachView:
    View
{
    @EnvironmentObject private var session:
        AppSessionStore

    @Binding var draft:
        AudioCoachDraft
    let showRouteOptions: Bool
    let showStructuredOptions: Bool

    var body: some View {
        ScrollView {
            ATHLTHPlusFeatureGate(
                feature: .audioCoach,
                title:
                    "Audio Coach · ATHLTH+",
                message:
                    "Spoken workout guidance is available with ATHLTH+ on iPhone and Apple Watch."
            ) {
                AudioCoachSetupCard(
                    draft: $draft,
                    showRouteOptions:
                        showRouteOptions,
                    showStructuredOptions:
                        showStructuredOptions
                )
            }
            .padding()
        }
        .background(
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
        )
        .navigationTitle("Audio Coach")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PerWorkoutRouteGuardianView:
    View
{
    @Binding var draft:
        RouteGuardianDraft

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Route Guardian",
                    isOn: $draft.enabled
                )
            }

            if draft.enabled {
                Section("Trigger") {
                    Picker(
                        "Alert when off route",
                        selection:
                            $draft
                                .deviationMeters
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
                            $draft.graceSeconds
                    ) {
                        Text("Immediately").tag(0)
                        Text("5 sec").tag(5)
                        Text("10 sec").tag(10)
                        Text("20 sec").tag(20)
                        Text("30 sec").tag(30)
                    }

                    Picker(
                        "Repeat",
                        selection:
                            $draft.repeatSeconds
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
                            $draft.delivery
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
                            $draft
                                .announceBackOnRoute
                    )
                }
            }
        }
        .navigationTitle("Route Guardian")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PerWorkoutGhostView: View {
    @Binding var draft:
        GhostQuickStartDraft
    let route: TrainingRoute?

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Use target Ghost",
                    isOn: $draft.enabled
                )
            } footer: {
                Text(
                    "Target Ghost compares your live progress against a finish time on the selected route. It works with iPhone and Apple Watch."
                )
            }

            if draft.enabled {
                Section("Target") {
                    TextField(
                        "45:00",
                        text:
                            $draft.targetTimeText
                    )
                    .keyboardType(
                        .numbersAndPunctuation
                    )
                    .font(
                        .title3
                            .monospacedDigit()
                    )

                    if let route,
                       let duration =
                            draft
                                .targetDuration {
                        HStack {
                            Text("Target pace")
                            Spacer()
                            Text(
                                GhostTargetTimeFormatter
                                    .paceText(
                                        distanceKilometers:
                                            route
                                                .distanceKilometers,
                                        duration:
                                            duration
                                    )
                            )
                            .foregroundStyle(
                                .secondary
                            )
                        }
                    }
                }

                Section("Updates") {
                    Toggle(
                        "Ghost Updates",
                        isOn:
                            $draft
                                .updatesEnabled
                    )

                    NavigationLink {
                        ATHLTHGhostUpdatesSettingsView()
                    } label: {
                        Text(
                            "Adjust Ghost Updates defaults"
                        )
                    }
                }
            }
        }
        .navigationTitle("Ghost Updates")
        .navigationBarTitleDisplayMode(.inline)
    }
}

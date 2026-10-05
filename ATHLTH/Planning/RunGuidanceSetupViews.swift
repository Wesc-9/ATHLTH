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

    mutating func load(
        configuration:
            WatchRouteAlertConfiguration
    ) {
        enabled = configuration.enabled
        deviationMeters =
            configuration.deviationMeters
        graceSeconds =
            Int(
                configuration
                    .graceSeconds
                    .rounded()
            )
        repeatSeconds =
            Int(
                configuration
                    .repeatSeconds
                    .rounded()
            )
        delivery = configuration.delivery
        announceBackOnRoute =
            configuration.announceBackOnRoute
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

    @MainActor
    mutating func load(
        targetDuration:
            TimeInterval?,
        updates:
            WatchGhostRaceAudioConfiguration?,
        route:
            TrainingRoute?,
        settings:
            AppSettingsStore
    ) {
        load(
            route: route,
            settings: settings
        )

        if let targetDuration,
           targetDuration > 0 {
            enabled = true
            targetTimeText =
                GhostTargetTimeFormatter
                    .string(
                        targetDuration
                    )
        }

        if let updates {
            updatesEnabled =
                updates.enabled
        }
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
        ScrollView {
            VStack(spacing: 14) {
                guidanceHero

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
                    guidanceFeatureCard(
                        title: "Audio Coach",
                        subtitle:
                            audioCoach.enabled
                                ? ATHLTHLocalization.choose(
                                    english:
                                        "On · spoken pace, distance and workout cues",
                                    norwegian:
                                        "På · tempo, distanse og øktinstruksjoner"
                                )
                                : ATHLTHLocalization.choose(
                                    english:
                                        "Off · tap to configure spoken guidance",
                                    norwegian:
                                        "Av · trykk for å sette opp talestyring"
                                ),
                        icon:
                            "waveform.and.person.filled",
                        tint:
                            ATHLTHTheme
                                .premiumGold,
                        enabled:
                            audioCoach.enabled
                    )
                }
                .buttonStyle(.plain)

                if route != nil {
                    NavigationLink {
                        PerWorkoutGhostView(
                            draft: $ghost,
                            route: route
                        )
                    } label: {
                        guidanceFeatureCard(
                            title: "Ghost",
                            subtitle:
                                ghost.enabled
                                    ? ATHLTHLocalization.format(
                                        english:
                                            "On · target %@ with live race updates",
                                        norwegian:
                                            "På · mål %@ med live sammenligning",
                                        ghost.targetTimeText
                                    )
                                    : ATHLTHLocalization.choose(
                                        english:
                                            "Race a target time on this route",
                                        norwegian:
                                            "Konkurrer mot en måltid på denne ruten"
                                    ),
                            icon:
                                "figure.run.circle.fill",
                            tint:
                                ATHLTHTheme
                                    .accentDeep,
                            enabled:
                                ghost.enabled
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        PerWorkoutRouteGuardianView(
                            draft:
                                $routeGuardian
                        )
                    } label: {
                        guidanceFeatureCard(
                            title:
                                "Route Guardian",
                            subtitle:
                                routeGuardian.enabled
                                    ? ATHLTHLocalization.format(
                                        english:
                                            "On · alert after %.0f m off route",
                                        norwegian:
                                            "På · varsle etter %.0f m utenfor ruten",
                                        routeGuardian
                                            .deviationMeters
                                    )
                                    : ATHLTHLocalization.choose(
                                        english:
                                            "Off · tap to configure route alerts",
                                        norwegian:
                                            "Av · trykk for å sette opp rutevarsler"
                                    ),
                            icon:
                                "location.fill",
                            tint:
                                ATHLTHTheme
                                    .vitality,
                            enabled:
                                routeGuardian
                                    .enabled
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    ATHLTHCard {
                        HStack(spacing: 12) {
                            Image(
                                systemName:
                                    "map.circle"
                            )
                            .font(
                                .system(
                                    size: 20,
                                    weight: .semibold
                                )
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .mutedText
                            )
                            .frame(
                                width: 44,
                                height: 44
                            )
                            .background(
                                Color.primary
                                    .opacity(0.04),
                                in:
                                    RoundedRectangle(
                                        cornerRadius: 13,
                                        style: .continuous
                                    )
                            )

                            VStack(
                                alignment: .leading,
                                spacing: 3
                            ) {
                                Text(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Ghost + Route Guardian",
                                        norwegian:
                                            "Ghost + Route Guardian"
                                    )
                                )
                                .font(
                                    .subheadline
                                        .weight(.semibold)
                                )

                                Text(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Choose a route to unlock route-aware guidance.",
                                        norwegian:
                                            "Velg en rute for å aktivere ruteavhengig veiledning."
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    .secondary
                                )
                            }
                        }
                    }
                    .opacity(0.72)
                }

                NavigationLink {
                    ATHLTHWorkoutGuidanceSettingsView()
                } label: {
                    HStack(spacing: 11) {
                        Image(
                            systemName:
                                "gearshape.fill"
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Global Workout Guidance defaults",
                                norwegian:
                                    "Standardvalg for treningsveiledning"
                            )
                        )
                        .font(
                            .subheadline
                                .weight(.semibold)
                        )

                        Spacer()

                        Image(
                            systemName:
                                "chevron.right"
                        )
                        .font(.caption.bold())
                        .foregroundStyle(
                            .tertiary
                        )
                    }
                    .padding(14)
                    .background(
                        Color.white
                            .opacity(0.70),
                        in:
                            RoundedRectangle(
                                cornerRadius: 18,
                                style: .continuous
                            )
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .background(
            LinearGradient(
                colors: [
                    ATHLTHTheme.canvasTop,
                    ATHLTHTheme.canvasBottom
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle(
            ATHLTHLocalization.choose(
                english:
                    "Run Tools",
                norwegian:
                    "Løpsverktøy"
            )
        )
        .navigationBarTitleDisplayMode(
            .inline
        )
    }

    private var guidanceHero:
        some View {
        ATHLTHCard {
            VStack(
                alignment: .leading,
                spacing: 12
            ) {
                Text("RUN SMARTER")
                    .font(
                        .system(
                            size: 10,
                            weight: .bold
                        )
                    )
                    .tracking(2.2)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Coach. Compare. Stay on route.",
                        norwegian:
                            "Coach. Sammenlign. Hold ruten."
                    )
                )
                .font(
                    .title3
                        .weight(.bold)
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .primaryText
                )

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "These tools run live on iPhone and Apple Watch and are configured for this workout only.",
                        norwegian:
                            "Disse verktøyene følger økten live på iPhone og Apple Watch, og gjelder kun denne økten."
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    .secondary
                )
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )

                HStack(spacing: 8) {
                    heroPill(
                        "Coach",
                        icon:
                            "waveform.and.mic"
                    )
                    heroPill(
                        "Ghost",
                        icon:
                            "figure.run"
                    )
                    heroPill(
                        ATHLTHLocalization.choose(
                            english: "Alerts",
                            norwegian: "Varsler"
                        ),
                        icon:
                            "bell.badge"
                    )
                }
            }
        }
    }

    private func heroPill(
        _ title: String,
        icon: String
    ) -> some View {
        Label(
            title,
            systemImage: icon
        )
        .font(
            .system(
                size: 10,
                weight: .semibold
            )
        )
        .foregroundStyle(
            ATHLTHTheme
                .accentDeep
        )
        .padding(
            .horizontal,
            10
        )
        .frame(height: 30)
        .background(
            ATHLTHTheme
                .accentSoft,
            in: Capsule()
        )
    }

    private func guidanceFeatureCard(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        enabled: Bool
    ) -> some View {
        ATHLTHCard {
            HStack(spacing: 13) {
                Image(
                    systemName: icon
                )
                .font(
                    .system(
                        size: 19,
                        weight: .semibold
                    )
                )
                .foregroundStyle(tint)
                .frame(
                    width: 46,
                    height: 46
                )
                .background(
                    tint.opacity(0.10),
                    in:
                        RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                )

                VStack(
                    alignment: .leading,
                    spacing: 4
                ) {
                    HStack(spacing: 7) {
                        Text(title)
                            .font(
                                .headline
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .primaryText
                            )

                        Text(
                            enabled
                                ? ATHLTHLocalization.choose(
                                    english: "ON",
                                    norwegian: "PÅ"
                                )
                                : ATHLTHLocalization.choose(
                                    english: "OFF",
                                    norwegian: "AV"
                                )
                        )
                        .font(
                            .system(
                                size: 8,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(
                            enabled
                                ? ATHLTHTheme
                                    .vitality
                                : ATHLTHTheme
                                    .mutedText
                        )
                        .padding(
                            .horizontal,
                            6
                        )
                        .padding(
                            .vertical,
                            3
                        )
                        .background(
                            (
                                enabled
                                    ? ATHLTHTheme
                                        .vitalitySoft
                                    : Color.primary
                                        .opacity(0.04)
                            ),
                            in: Capsule()
                        )
                    }

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                }

                Spacer()

                Image(
                    systemName:
                        "chevron.right"
                )
                .font(.caption.bold())
                .foregroundStyle(
                    .tertiary
                )
            }
        }
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

struct PerWorkoutRouteGuardianView:
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

struct PerWorkoutGhostView: View {
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

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
    @Binding var audioCoach: AudioCoachDraft
    @Binding var routeGuardian: RouteGuardianDraft
    @Binding var ghost: GhostQuickStartDraft

    let route: TrainingRoute?
    let structuredWorkout: RunningWorkoutTemplate?

    private var routeAvailable: Bool { route != nil }
    private var enabledCount: Int {
        (audioCoach.enabled ? 1 : 0) +
        (routeAvailable && ghost.enabled ? 1 : 0) +
        (routeAvailable && routeGuardian.enabled ? 1 : 0)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                ATHLTHPlanSectionIntro(
                    eyebrow: ATHLTHLocalization.choose(
                        english: "YOUR RUN · ADVANCED",
                        norwegian: "DIN LØPEØKT · AVANSERT"
                    ),
                    title: ATHLTHLocalization.choose(
                        english: "Run tools", norwegian: "Løpsverktøy"
                    ),
                    subtitle: ATHLTHLocalization.choose(
                        english: "Fine-tune this workout before you start.",
                        norwegian: "Tilpass veiledningen til akkurat denne økten."
                    ),
                    icon: "waveform.and.person.filled"
                )

                ATHLTHPlanSurface(ghost: false, density: .comfortable) {
                    HStack {
                        Text(ATHLTHLocalization.choose(
                            english: "WORKOUT GUIDANCE",
                            norwegian: "ØKTENS VEILEDNING"
                        ))
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.6)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        Spacer()
                        Text(ATHLTHLocalization.format(
                            english: "%d active",
                            norwegian: "%d aktive",
                            enabledCount
                        ))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(ATHLTHPlanDesign.selectedSurface, in: Capsule())
                    }

                    NavigationLink {
                        PerWorkoutAudioCoachView(
                            draft: $audioCoach,
                            showRouteOptions:
                                routeAvailable || structuredWorkout?.routeID != nil,
                            showStructuredOptions: structuredWorkout != nil
                        )
                    } label: {
                        featureRow(
                            icon: "waveform.and.person.filled",
                            title: "Audio Coach",
                            detail: audioCoach.enabled
                                ? ATHLTHLocalization.choose(
                                    english: "Spoken coaching · edit triggers, voice and volume",
                                    norwegian: "Talecoach · juster varsler, stemme og lyd"
                                )
                                : ATHLTHLocalization.choose(
                                    english: "Configure voice guidance for your run",
                                    norwegian: "Tilpass stemmeveiledningen for økten"
                                ),
                            enabled: audioCoach.enabled
                        )
                    }
                    .buttonStyle(.plain)

                    Divider().overlay(ATHLTHPlanDesign.warmDivider)

                    if routeAvailable {
                        NavigationLink {
                            PerWorkoutGhostView(draft: $ghost, route: route)
                        } label: {
                            featureRow(
                                icon: "figure.run.circle",
                                title: "Ghost Race",
                                detail: ghost.enabled
                                    ? ATHLTHLocalization.format(
                                        english: "Target %@ · timing and updates",
                                        norwegian: "Mål %@ · tid og oppdateringer",
                                        ghost.targetTimeText
                                    )
                                    : ATHLTHLocalization.choose(
                                        english: "Choose a target time and Ghost updates",
                                        norwegian: "Velg måltid og Ghost-oppdateringer"
                                    ),
                                enabled: ghost.enabled
                            )
                        }
                        .buttonStyle(.plain)

                        Divider().overlay(ATHLTHPlanDesign.warmDivider)

                        NavigationLink {
                            PerWorkoutRouteGuardianView(draft: $routeGuardian)
                        } label: {
                            featureRow(
                                icon: "point.topleft.down.curvedto.point.bottomright.up",
                                title: ATHLTHLocalization.choose(
                                    english: "Route Guardian",
                                    norwegian: "Ruteveiledning"
                                ),
                                detail: routeGuardian.enabled
                                    ? ATHLTHLocalization.format(
                                        english: "Alerts when more than %.0f m off route",
                                        norwegian: "Varsel ved mer enn %.0f m utenfor ruten",
                                        routeGuardian.deviationMeters
                                    )
                                    : ATHLTHLocalization.choose(
                                        english: "Deviation, recovery and alert settings",
                                        norwegian: "Avvik, retur til ruten og varsler"
                                    ),
                                enabled: routeGuardian.enabled
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        HStack(spacing: 10) {
                            Image(systemName: "map")
                                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                            Text(ATHLTHLocalization.choose(
                                english: "Select a route to set up Ghost Race and Route Guardian.",
                                norwegian: "Velg en rute for å tilpasse Ghost Race og ruteveiledning."
                            ))
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 5)
                    }
                }

                ATHLTHPlanSurface(ghost: false, density: .compact) {
                    NavigationLink {
                        ATHLTHWorkoutGuidanceSettingsView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                .frame(width: 39, height: 39)
                                .background(
                                    ATHLTHPlanDesign.selectedSurface,
                                    in: RoundedRectangle(cornerRadius: 12)
                                )
                            VStack(alignment: .leading, spacing: 3) {
                                Text(ATHLTHLocalization.choose(
                                    english: "Default guidance settings",
                                    norwegian: "Standardinnstillinger for veiledning"
                                ))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ATHLTHPlanDesign.ink)
                                Text(ATHLTHLocalization.choose(
                                    english: "For future workouts",
                                    norwegian: "Gjelder kommende økter"
                                ))
                                .font(.caption)
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Text(ATHLTHLocalization.choose(
                    english: "Changes here apply to this workout only. They are ready when you return.",
                    norwegian: "Endringer her gjelder bare denne økten, og lagres når du går tilbake."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                .padding(.horizontal, 3)
            }
            .frame(maxWidth: ATHLTHPlanDesign.maxContentWidth)
            .frame(maxWidth: .infinity)
            .padding(16)
        }
        .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
        .tint(ATHLTHPlanDesign.accentInk)
        .navigationTitle(ATHLTHLocalization.choose(
            english: "Run tools", norwegian: "Løpsverktøy"
        ))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func featureRow(
        icon: String,
        title: String,
        detail: String,
        enabled: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                .frame(width: 44, height: 44)
                .background(
                    ATHLTHPlanDesign.selectedSurface,
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(ATHLTHPlanDesign.ink)

                    Text(enabled
                        ? ATHLTHLocalization.choose(english: "On", norwegian: "På")
                        : ATHLTHLocalization.choose(english: "Off", norwegian: "Av")
                    )
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(enabled
                        ? ATHLTHPlanDesign.accentInk
                        : ATHLTHPlanDesign.secondaryInk)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        enabled
                            ? ATHLTHPlanDesign.selectedSurface
                            : ATHLTHPlanDesign.canvas,
                        in: Capsule()
                    )
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 2)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
        }
        .frame(minHeight: 59)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
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

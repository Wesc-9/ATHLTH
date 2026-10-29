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
    var targetPaceText = ""
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
            targetPaceText = ""
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
        targetPaceText = ATHLTHGhostPaceTimeConversion.paceText(
            duration: seconds,
            distanceKilometers: route.distanceKilometers
        ) ?? ""
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
            targetPaceText = ATHLTHGhostPaceTimeConversion.paceText(
                duration: targetDuration,
                distanceKilometers: route?.distanceKilometers
            ) ?? ""
        }

        if let updates {
            updatesEnabled =
                updates.enabled
        }
    }

    /// Editing either field recalculates the other immediately. Keep raw
    /// text in the active field so typing "5:30" doesn't jump the cursor.
    mutating func setTargetTimeText(
        _ value: String,
        distanceKilometers: Double?
    ) {
        targetTimeText = value
        targetPaceText = ATHLTHGhostPaceTimeConversion.paceText(
            duration: GhostTargetTimeFormatter.parse(value),
            distanceKilometers: distanceKilometers
        ) ?? ""
    }

    mutating func setTargetPaceText(
        _ value: String,
        distanceKilometers: Double?
    ) {
        targetPaceText = value
        guard let duration = ATHLTHGhostPaceTimeConversion.targetDuration(
            paceText: value,
            distanceKilometers: distanceKilometers
        ) else {
            // Never silently launch with the old time after an invalid pace.
            targetTimeText = ""
            return
        }
        targetTimeText = GhostTargetTimeFormatter.string(duration)
    }

    var targetDuration: TimeInterval? {
        guard enabled,
              let duration = GhostTargetTimeFormatter.parse(targetTimeText),
              duration > 0 else { return nil }
        return duration
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
                                icon: "location.north.line",
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

struct PerWorkoutAudioCoachView: View {
    @EnvironmentObject private var session: AppSessionStore
    @Binding var draft: AudioCoachDraft
    let showRouteOptions: Bool
    let showStructuredOptions: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ATHLTHPlanSectionIntro(
                    eyebrow: ATHLTHLocalization.choose(
                        english: "VOICE GUIDANCE",
                        norwegian: "STEMMEVEILEDNING"
                    ),
                    title: "Audio Coach",
                    subtitle: ATHLTHLocalization.choose(
                        english: "Your voice, your pace, your workout.",
                        norwegian: "Din stemme, ditt tempo og din økt."
                    ),
                    icon: "waveform.and.person.filled"
                )

                ATHLTHPlusFeatureGate(
                    feature: .audioCoach,
                    title: "Audio Coach · ATHLTH+",
                    message: "Spoken workout guidance is available with ATHLTH+ on iPhone and Apple Watch."
                ) {
                    AudioCoachSetupCard(
                        draft: $draft,
                        showRouteOptions: showRouteOptions,
                        showStructuredOptions: showStructuredOptions
                    )
                }
            }
            .frame(maxWidth: ATHLTHPlanDesign.maxContentWidth)
            .frame(maxWidth: .infinity)
            .padding(16)
        }
        .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
        .tint(ATHLTHPlanDesign.accentInk)
        .navigationTitle("Audio Coach")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PerWorkoutRouteGuardianView: View {
    @Binding var draft: RouteGuardianDraft

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ATHLTHPlanSectionIntro(
                    eyebrow: ATHLTHLocalization.choose(
                        english: "ROUTE GUIDANCE",
                        norwegian: "RUTEVEILEDNING"
                    ),
                    title: ATHLTHLocalization.choose(
                        english: "Route Guardian",
                        norwegian: "Hold deg på ruten"
                    ),
                    subtitle: ATHLTHLocalization.choose(
                        english: "Choose when and how the coach warns you about route deviation.",
                        norwegian: "Velg når og hvordan coachen varsler at du er utenfor ruten."
                    ),
                    icon: "location.north.line"
                )

                ATHLTHPlanSurface(ghost: false) {
                    Toggle(isOn: $draft.enabled) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ATHLTHLocalization.choose(
                                english: "Route Guardian",
                                norwegian: "Ruteveiledning"
                            ))
                            .font(.headline)
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                            Text(ATHLTHLocalization.choose(
                                english: "Alerts during this run",
                                norwegian: "Varsler under denne økten"
                            ))
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                    }
                    .tint(ATHLTHPlanDesign.accentInk)
                    if draft.enabled {
                        Divider().overlay(ATHLTHPlanDesign.warmDivider)
                        Text(ATHLTHLocalization.choose(
                            english: "DEVIATION",
                            norwegian: "AVVIK FRA RUTEN"
                        ))
                        .font(.caption2.weight(.bold))
                        .tracking(1.25)
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)

                        HStack {
                            Text(ATHLTHLocalization.choose(
                                english: "Alert distance", norwegian: "Avstand for varsel"
                            ))
                            .font(.subheadline)
                            Spacer()
                            Picker(ATHLTHLocalization.choose(
                                english: "Alert distance", norwegian: "Avstand for varsel"
                            ), selection: $draft.deviationMeters) {
                                ForEach([25.0, 50.0, 80.0, 100.0, 150.0, 250.0],
                                        id: \.self) { value in
                                    Text("\(Int(value)) m").tag(value)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        .frame(minHeight: 44)

                        Divider().overlay(ATHLTHPlanDesign.warmDivider)
                        HStack {
                            Text(ATHLTHLocalization.choose(
                                english: "Wait before alert", norwegian: "Vent før varsel"
                            ))
                            .font(.subheadline)
                            Spacer()
                            Picker(ATHLTHLocalization.choose(
                                english: "Wait before alert", norwegian: "Vent før varsel"
                            ), selection: $draft.graceSeconds) {
                                Text(ATHLTHLocalization.choose(
                                    english: "Immediately", norwegian: "Straks"
                                )).tag(0)
                                Text("5 s").tag(5)
                                Text("10 s").tag(10)
                                Text("20 s").tag(20)
                                Text("30 s").tag(30)
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        .frame(minHeight: 44)

                        Divider().overlay(ATHLTHPlanDesign.warmDivider)
                        HStack {
                            Text(ATHLTHLocalization.choose(
                                english: "Repeat interval", norwegian: "Gjenta varsel"
                            ))
                            .font(.subheadline)
                            Spacer()
                            Picker(ATHLTHLocalization.choose(
                                english: "Repeat interval", norwegian: "Gjenta varsel"
                            ), selection: $draft.repeatSeconds) {
                                Text("30 s").tag(30)
                                Text("1 min").tag(60)
                                Text("2 min").tag(120)
                                Text("5 min").tag(300)
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        .frame(minHeight: 44)
                    }
                }

                if draft.enabled {
                    ATHLTHPlanSurface(ghost: false) {
                        Text(ATHLTHLocalization.choose(
                            english: "HOW YOU'RE NOTIFIED",
                            norwegian: "SLIK VARSLES DU"
                        ))
                        .font(.caption2.weight(.bold))
                        .tracking(1.25)
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)

                        HStack {
                            Text(ATHLTHLocalization.choose(
                                english: "Alert style", norwegian: "Varseltype"
                            ))
                            .font(.subheadline)
                            Spacer()
                            Picker(ATHLTHLocalization.choose(
                                english: "Alert style", norwegian: "Varseltype"
                            ), selection: $draft.delivery) {
                                ForEach(WatchAlertDelivery.allCases) { delivery in
                                    Text(delivery.title).tag(delivery)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        .frame(minHeight: 44)

                        Divider().overlay(ATHLTHPlanDesign.warmDivider)
                        Toggle(isOn: $draft.announceBackOnRoute) {
                            Text(ATHLTHLocalization.choose(
                                english: "Announce when back on route",
                                norwegian: "Gi beskjed når jeg er tilbake på ruten"
                            ))
                            .font(.subheadline)
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                        }
                        .tint(ATHLTHPlanDesign.accentInk)
                    }
                }
            }
            .frame(maxWidth: ATHLTHPlanDesign.maxContentWidth)
            .frame(maxWidth: .infinity)
            .padding(16)
        }
        .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
        .tint(ATHLTHPlanDesign.accentInk)
        .navigationTitle(ATHLTHLocalization.choose(
            english: "Route Guardian", norwegian: "Ruteveiledning"
        ))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PerWorkoutGhostView: View {
    @Binding var draft: GhostQuickStartDraft
    let route: TrainingRoute?

    private var targetTimeBinding: Binding<String> {
        Binding(
            get: { draft.targetTimeText },
            set: { value in
                draft.setTargetTimeText(
                    value,
                    distanceKilometers: route?.distanceKilometers
                )
            }
        )
    }

    private var targetPaceBinding: Binding<String> {
        Binding(
            get: { draft.targetPaceText },
            set: { value in
                draft.setTargetPaceText(
                    value,
                    distanceKilometers: route?.distanceKilometers
                )
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ATHLTHPlanSectionIntro(
                    eyebrow: "GHOST RACE",
                    title: ATHLTHLocalization.choose(
                        english: "Run against a goal", norwegian: "Løp mot et mål"
                    ),
                    subtitle: ATHLTHLocalization.choose(
                        english: "Your Ghost follows the chosen route and target finish time.",
                        norwegian: "Ghost følger den valgte ruten og din måltid."
                    ),
                    icon: "figure.run.circle"
                )

                ATHLTHPlanSurface(ghost: false) {
                    Toggle(isOn: $draft.enabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ATHLTHLocalization.choose(
                                english: "Target Ghost", norwegian: "Mål-Ghost"
                            ))
                            .font(.headline)
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                            Text(ATHLTHLocalization.choose(
                                english: "Compare your progress on this route",
                                norwegian: "Sammenlign fremdrift langs ruten"
                            ))
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                    }
                    .tint(ATHLTHPlanDesign.accentInk)

                    if draft.enabled {
                        Divider().overlay(ATHLTHPlanDesign.warmDivider)
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(ATHLTHLocalization.choose(
                                    english: "TARGET FINISH TIME",
                                    norwegian: "MÅLTID"
                                ))
                                .font(.caption2.weight(.bold))
                                .tracking(1.2)
                                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                TextField("1:00:00", text: targetTimeBinding)
                                    .keyboardType(.numbersAndPunctuation)
                                    .font(.system(size: 27, weight: .semibold,
                                                  design: .rounded))
                                    .foregroundStyle(ATHLTHPlanDesign.ink)
                                    .monospacedDigit()
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .accessibilityLabel(ATHLTHLocalization.choose(
                                        english: "Target finish time",
                                        norwegian: "Måltid"
                                    ))
                            }
                            Spacer()
                            Image(systemName: "stopwatch")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        }

                        if let route {
                            Divider().overlay(ATHLTHPlanDesign.warmDivider)
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(ATHLTHLocalization.choose(
                                        english: "TARGET PACE",
                                        norwegian: "MÅLTEMPO"
                                    ))
                                    .font(.caption2.weight(.bold))
                                    .tracking(1.2)
                                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                        TextField("5:30", text: targetPaceBinding)
                                            .keyboardType(.numbersAndPunctuation)
                                            .font(.system(size: 24, weight: .semibold,
                                                          design: .rounded))
                                            .foregroundStyle(ATHLTHPlanDesign.ink)
                                            .monospacedDigit()
                                            .textInputAutocapitalization(.never)
                                            .autocorrectionDisabled()
                                            .accessibilityLabel(ATHLTHLocalization.choose(
                                                english: "Target pace in minutes and seconds per kilometer",
                                                norwegian: "Måltempo i minutter og sekunder per kilometer"
                                            ))
                                        Text("/km")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                    }
                                }
                                Spacer()
                                Image(systemName: "speedometer")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                            }
                            Divider().overlay(ATHLTHPlanDesign.warmDivider)
                            Text(ATHLTHLocalization.choose(
                                english: "Change either value — the other updates automatically. Calculated for the selected route of",
                                norwegian: "Endre tid eller tempo – det andre oppdateres automatisk. Beregnet for valgt rute på"
                            ) + " " + route.distanceKilometers.formatted(
                                .number.precision(.fractionLength(0...2))
                            ) + " km.")
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                            if draft.targetDuration == nil {
                                Text(ATHLTHLocalization.choose(
                                    english: "Enter a valid time or pace to enable Target Ghost.",
                                    norwegian: "Skriv inn en gyldig tid eller et tempo for å bruke Mål-Ghost."
                                ))
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .accessibilityAddTraits(.updatesFrequently)
                            }
                        }
                    }
                }

                if draft.enabled {
                    ATHLTHPlanSurface(ghost: false) {
                        Toggle(isOn: $draft.updatesEnabled) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Ghost Updates")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ATHLTHPlanDesign.ink)
                                Text(ATHLTHLocalization.choose(
                                    english: "Hear race updates while running",
                                    norwegian: "Få oppdateringer mens du løper"
                                ))
                                .font(.caption)
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            }
                        }
                        .tint(ATHLTHPlanDesign.accentInk)

                        NavigationLink {
                            ATHLTHGhostUpdatesSettingsView()
                        } label: {
                            HStack {
                                Label(ATHLTHLocalization.choose(
                                    english: "Adjust update preferences",
                                    norwegian: "Juster oppdateringene"
                                ), systemImage: "slider.horizontal.3")
                                .font(.subheadline.weight(.medium))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                            .frame(minHeight: 42)
                        }
                        .buttonStyle(.plain)
                    }
                }
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
}

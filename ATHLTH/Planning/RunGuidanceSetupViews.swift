import SwiftUI

struct RouteGuardianDraft {
    var enabled = true
    var deviationMeters = 80.0
    var graceSeconds = 10
    var repeatSeconds = 120
    var delivery:
        WatchAlertDelivery = .both
    var announceBackOnRoute = true
    var announceUpcomingTurns = true
    var turnCueLeadMeters = 85.0

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
        announceBackOnRoute = settings.routeAlertAnnounceBackOnRoute
        announceUpcomingTurns = settings.routeAlertAnnounceUpcomingTurns
        turnCueLeadMeters = settings.routeAlertTurnCueLeadMeters
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
        announceBackOnRoute = configuration.announceBackOnRoute
        announceUpcomingTurns = configuration.shouldAnnounceUpcomingTurns
        turnCueLeadMeters = configuration.resolvedTurnCueLeadMeters
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
            announceBackOnRoute: announceBackOnRoute,
            announceUpcomingTurns: announceUpcomingTurns,
            turnCueLeadMeters: turnCueLeadMeters
        )
    }
}

struct GhostQuickStartDraft {
    var enabled = false
    // Selecting a strategy does not alter the requested pace / finish time.
    // It is applied only when generating the recorded target Ghost timeline.
    var pacingStrategy: GhostTargetPacingStrategy = .even
    var targetTimeText = ""
    var targetPaceText = ""
    var updatesEnabled = true
    // Complete workout-scoped update snapshot, never a direct write to Settings.
    var updatesConfiguration: WatchGhostRaceAudioConfiguration?
    private var loadedRouteID: UUID?

    init() {}

    @MainActor
    mutating func load(
        route: TrainingRoute?,
        settings: AppSettingsStore
    ) {
        if updatesConfiguration == nil {
            updatesConfiguration = settings.ghostRaceAudioConfiguration
            updatesEnabled = settings.ghostRaceAudioEnabled
        }

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
            updatesConfiguration = updates
            updatesEnabled = updates.enabled
        }
    }

    func resolvedUpdates(
        fallback: WatchGhostRaceAudioConfiguration
    ) -> WatchGhostRaceAudioConfiguration {
        var configuration = updatesConfiguration ?? fallback
        configuration.enabled = updatesEnabled
        return configuration
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

    /// Complete shorthand when the field loses focus. Keep raw input during
    /// editing so people can type either "5", "5:00" or "5:30".
    mutating func finalizeTargetPaceText(distanceKilometers: Double?) {
        guard let normalized = ATHLTHGhostPaceTimeConversion.normalizedPaceText(
            from: targetPaceText
        ) else { return }
        setTargetPaceText(normalized, distanceKilometers: distanceKilometers)
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
                                enabled: routeAvailable && ghost.enabled
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!routeAvailable)

                        Divider().overlay(ATHLTHPlanDesign.warmDivider)

                        NavigationLink {
                            PerWorkoutRouteGuardianView(draft: $routeGuardian)
                        } label: {
                            featureRow(
                                icon: "location.north.line",
                                title: ATHLTHLocalization.choose(
                                    english: "Navigation",
                                    norwegian: "Navigasjon"
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
                                enabled: routeAvailable && routeGuardian.enabled
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!routeAvailable)

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
            ATHLTHRouteGuidanceStudioView(draft: $draft)
                .frame(maxWidth: ATHLTHPlanDesign.maxContentWidth)
                .frame(maxWidth: .infinity)
                .padding(16)
        }
        .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
        .tint(ATHLTHPlanDesign.accentInk)
        .navigationTitle(ATHLTHLocalization.choose(
            english: "Navigation", norwegian: "Navigasjon"
        ))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A single visual and behavioural editor for global Navigation defaults
/// and workout-scoped Route Coach. No new GPS/voice engine is introduced.
struct ATHLTHRouteGuidanceStudioView: View {
    @Binding var draft: RouteGuardianDraft

    @State private var routeCoachExpanded = true
    @State private var deviationExpanded = true
    @State private var deliveryExpanded = false

    private let gold = ATHLTHPlanDesign.accentInk
    private let ink = ATHLTHPlanDesign.ink
    private let dim = ATHLTHPlanDesign.secondaryInk

    private struct Preset: Identifiable {
        let id: Int
        let nameEnglish: String
        let nameNorwegian: String
        let distance: Double
        let grace: Int
        let icon: String
    }

    private let presets = [
        Preset(id: 0, nameEnglish: "Precise", nameNorwegian: "Presis",
               distance: 50, grace: 10, icon: "scope"),
        Preset(id: 1, nameEnglish: "Balanced", nameNorwegian: "Balansert",
               distance: 80, grace: 20, icon: "location.north.line"),
        Preset(id: 2, nameEnglish: "Relaxed", nameNorwegian: "Rolig",
               distance: 150, grace: 30, icon: "leaf")
    ]

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var currentPresetIndex: Int? {
        presets.firstIndex {
            draft.deviationMeters == $0.distance &&
            draft.graceSeconds == $0.grace
        }
    }

    private var title: String {
        guard draft.enabled else { return tr("Off", "Av") }
        guard let index = currentPresetIndex else { return tr("Custom", "Egendefinert") }
        return tr(presets[index].nameEnglish, presets[index].nameNorwegian)
    }

    private func selectPreset(_ index: Int) {
        guard presets.indices.contains(index) else { return }
        let preset = presets[index]
        draft.deviationMeters = preset.distance
        draft.graceSeconds = preset.grace
        draft.enabled = true
    }

    private func cyclePreset(_ offset: Int) {
        let current = currentPresetIndex ?? 1
        selectPreset((current + offset + presets.count) % presets.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ATHLTHPlanSectionIntro(
                eyebrow: tr("ROUTE GUIDANCE", "RUTEVEILEDNING"),
                title: tr("Navigation & Route Coach", "Navigasjon og Rute-coach"),
                subtitle: tr(
                    "Stay on your route, hear upcoming bends and get calmly guided back if you stray.",
                    "Følg ruten, få beskjed om kommende svinger og finn rolig tilbake hvis du havner utenfor."
                ),
                icon: "location.north.line"
            )

            ATHLTHPlanSurface(ghost: false) {
                HStack(spacing: 12) {
                    Image(systemName: "location.north.line")
                        .font(.title3)
                        .foregroundStyle(gold)
                        .frame(width: 45, height: 45)
                        .background(ATHLTHPlanDesign.selectedSurface,
                                    in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tr("Navigation", "Navigasjon"))
                            .font(.headline)
                            .foregroundStyle(ink)
                        Text(tr("Route guidance during a workout",
                                "Ruteveiledning under økten"))
                            .font(.caption)
                            .foregroundStyle(dim)
                    }
                    Spacer(minLength: 6)
                    Toggle(tr("Navigation", "Navigasjon"), isOn: $draft.enabled)
                        .labelsHidden()
                        .tint(gold)
                        .accessibilityIdentifier("athlth-navigation-enabled")
                }
            }

            if draft.enabled {
                VStack(spacing: 12) {
                    HStack {
                        Text(tr("ROUTE SENSITIVITY", "FØLSOMHET FOR RUTEAVVIK"))
                            .font(.caption.weight(.bold))
                            .tracking(1.7)
                            .foregroundStyle(gold)
                        Spacer()
                    }

                    HStack(spacing: 5) {
                        Button { withAnimation(.easeInOut(duration: 0.2)) {
                            cyclePreset(-1)
                        }} label: {
                            Image(systemName: "chevron.left")
                                .font(.title3.weight(.semibold))
                                .frame(width: 40, height: 60)
                        }
                        .accessibilityLabel(tr("Previous mode", "Forrige modus"))

                        Spacer(minLength: 0)
                        ZStack {
                            Circle()
                                .stroke(gold.opacity(0.12), lineWidth: 12)
                            Circle()
                                .stroke(
                                    AngularGradient(colors: [
                                        gold.opacity(0.30), gold, gold.opacity(0.72), gold
                                    ], center: .center),
                                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                                )
                            Circle()
                                .stroke(ATHLTHPlanDesign.warmDivider, lineWidth: 1)
                                .padding(13)
                            VStack(spacing: 7) {
                                Image(systemName: "location.north.line")
                                    .font(.system(size: 29, weight: .medium))
                                    .foregroundStyle(gold)
                                Text(tr("ACTIVE MODE", "AKTIV MODUS"))
                                    .font(.caption2.weight(.bold))
                                    .tracking(1.2)
                                    .foregroundStyle(dim)
                                Text(title)
                                    .font(.system(size: 23, weight: .medium, design: .serif))
                                    .foregroundStyle(ink)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                Text("\(Int(draft.deviationMeters)) m · \(draft.graceSeconds) s")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(dim)
                            }
                        }
                        .frame(width: 208, height: 208)
                        .accessibilityIdentifier("athlth-route-mode-circle")
                        Spacer(minLength: 0)

                        Button { withAnimation(.easeInOut(duration: 0.2)) {
                            cyclePreset(1)
                        }} label: {
                            Image(systemName: "chevron.right")
                                .font(.title3.weight(.semibold))
                                .frame(width: 40, height: 60)
                        }
                        .accessibilityLabel(tr("Next mode", "Neste modus"))
                    }
                    .foregroundStyle(gold)

                    HStack(spacing: 9) {
                        ForEach(presets) { preset in
                            let selected = currentPresetIndex == preset.id
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectPreset(preset.id)
                                }
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: preset.icon)
                                        .font(.subheadline)
                                    Text(tr(preset.nameEnglish, preset.nameNorwegian))
                                        .font(.caption.weight(.semibold))
                                    Text("\(Int(preset.distance)) m")
                                        .font(.caption2.monospacedDigit())
                                }
                                .foregroundStyle(selected ? gold : dim)
                                .frame(maxWidth: .infinity, minHeight: 72)
                                .background(
                                    selected
                                        ? ATHLTHPlanDesign.selectedSurface
                                        : Color.white,
                                    in: RoundedRectangle(cornerRadius: 17)
                                )
                                .overlay(RoundedRectangle(cornerRadius: 17)
                                    .stroke(selected ? gold.opacity(0.6) :
                                            ATHLTHPlanDesign.warmDivider))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }
                .padding(.vertical, 2)

                ATHLTHPlanSurface(ghost: false) {
                    DisclosureGroup(isExpanded: $routeCoachExpanded) {
                        VStack(alignment: .leading, spacing: 12) {
                            Divider().overlay(ATHLTHPlanDesign.warmDivider)
                            Toggle(isOn: $draft.announceUpcomingTurns) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(tr("Announce approaching bends",
                                            "Varsle før kommende svinger"))
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(ink)
                                    Text(tr("Uses the actual saved route line",
                                            "Bruker den lagrede rutelinjen"))
                                        .font(.caption)
                                        .foregroundStyle(dim)
                                }
                            }
                            .tint(gold)
                            if draft.announceUpcomingTurns {
                                HStack(spacing: 10) {
                                    Text(tr("How early?", "Hvor tidlig?"))
                                        .font(.subheadline)
                                        .foregroundStyle(ink)
                                    Spacer()
                                    Picker(tr("Lead distance", "Avstand før sving"),
                                           selection: $draft.turnCueLeadMeters) {
                                        Text(tr("Near · 40 m", "Nært · 40 m")).tag(40.0)
                                        Text(tr("Normal · 85 m", "Normal · 85 m")).tag(85.0)
                                        Text(tr("Early · 140 m", "Tidlig · 140 m")).tag(140.0)
                                    }
                                    .pickerStyle(.menu)
                                }
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "arrow.turn.up.left")
                                        .foregroundStyle(gold)
                                        .frame(width: 29)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(tr("EXAMPLE", "EKSEMPEL"))
                                            .font(.caption2.weight(.bold))
                                            .tracking(1.3)
                                            .foregroundStyle(gold)
                                        Text(tr(
                                            "In \(Int(draft.turnCueLeadMeters)) metres, the route bends left.",
                                            "Om \(Int(draft.turnCueLeadMeters)) meter svinger ruten mot venstre."
                                        ))
                                        .font(.subheadline)
                                        .foregroundStyle(ink)
                                    }
                                }
                                .padding(13)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(ATHLTHPlanDesign.selectedSurface,
                                            in: RoundedRectangle(cornerRadius: 15))
                                Text(tr(
                                    "Only clear turns with reliable GPS are announced. This is route-line guidance, not street-by-street directions.",
                                    "Bare tydelige svinger med pålitelig GPS varsles. Dette er ruteveiledning, ikke veinavigasjon med gatenavn."
                                ))
                                .font(.caption)
                                .foregroundStyle(dim)
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        sectionLabel(
                            tr("Route Coach", "Rute-coach"),
                            subtitle: draft.announceUpcomingTurns
                                ? tr("Upcoming bends", "Kommende svinger")
                                : tr("Turn guidance off", "Svingvarsler av"),
                            icon: "arrow.triangle.turn.up.right.diamond"
                        )
                    }
                    .accessibilityIdentifier("athlth-route-coach-card")
                }

                ATHLTHPlanSurface(ghost: false) {
                    DisclosureGroup(isExpanded: $deviationExpanded) {
                        VStack(alignment: .leading, spacing: 12) {
                            Divider().overlay(ATHLTHPlanDesign.warmDivider)
                            fieldMenu(
                                tr("Off-route distance", "Avstand fra ruten"),
                                selection: $draft.deviationMeters,
                                options: [25.0, 50.0, 80.0, 100.0, 150.0, 250.0],
                                label: { "\(Int($0)) m" }
                            )
                            Divider().overlay(ATHLTHPlanDesign.warmDivider)
                            fieldMenu(
                                tr("Wait for stable deviation", "Vent på stabilt avvik"),
                                selection: $draft.graceSeconds,
                                options: [0, 5, 10, 20, 30],
                                label: { $0 == 0 ? tr("Immediately", "Straks") : "\($0) s" }
                            )
                            Divider().overlay(ATHLTHPlanDesign.warmDivider)
                            fieldMenu(
                                tr("Repeat while off route", "Gjenta ved fortsatt avvik"),
                                selection: $draft.repeatSeconds,
                                options: [30, 60, 120, 300],
                                label: { $0 >= 60 ? "\($0 / 60) min" : "\($0) s" }
                            )
                            Divider().overlay(ATHLTHPlanDesign.warmDivider)
                            Toggle(tr("Tell me when I'm back on route",
                                      "Gi beskjed når jeg er tilbake på ruten"),
                                   isOn: $draft.announceBackOnRoute)
                                .tint(gold)
                                .font(.subheadline)
                            Text(tr(
                                "GPS uncertainty is discounted before warnings. The original route remains unchanged.",
                                "GPS-usikkerhet trekkes fra før varsling. Den opprinnelige ruten endres ikke."
                            ))
                            .font(.caption)
                            .foregroundStyle(dim)
                        }
                        .padding(.top, 8)
                    } label: {
                        sectionLabel(
                            tr("Off-route alerts", "Ruteavvik"),
                            subtitle: tr("Warn and find the route again", "Varsle og finn tilbake"),
                            icon: "location.slash"
                        )
                    }
                    .accessibilityIdentifier("athlth-route-deviation-card")
                }

                ATHLTHPlanSurface(ghost: false) {
                    DisclosureGroup(isExpanded: $deliveryExpanded) {
                        VStack(alignment: .leading, spacing: 12) {
                            Divider().overlay(ATHLTHPlanDesign.warmDivider)
                            HStack {
                                Text(tr("Alert delivery", "Slik varsles du"))
                                    .font(.subheadline)
                                    .foregroundStyle(ink)
                                Spacer()
                                Picker(tr("Delivery", "Varseltype"),
                                       selection: $draft.delivery) {
                                    ForEach(WatchAlertDelivery.allCases) { kind in
                                        Text(kind.title).tag(kind)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                            Text(tr(
                                "Voice and/or watch vibrations apply to both route turns and off-route alerts. Critical route alerts take priority over routine motivational cues.",
                                "Stemme og/eller klokkevibrasjon gjelder både svinger og ruteavvik. Viktige rutevarsler prioriteres foran vanlig motivasjon."
                            ))
                            .font(.caption)
                            .foregroundStyle(dim)
                        }
                        .padding(.top, 8)
                    } label: {
                        sectionLabel(
                            tr("Voice and haptics", "Stemme og vibrasjon"),
                            subtitle: draft.delivery.title,
                            icon: "speaker.wave.2"
                        )
                    }
                    .accessibilityIdentifier("athlth-route-delivery-card")
                }
            }

            Text(tr(
                "Navigation needs an actual saved route and reliable GPS. Your settings do not turn a route into road-level turn-by-turn directions. The route remains available on screen even when voice is off.",
                "Navigasjon krever en lagret rute og pålitelig GPS. Innstillingene gir ikke gatenavigasjon. Ruten vises fortsatt på skjermen selv om stemmen er av."
            ))
            .font(.caption)
            .foregroundStyle(dim)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
        }
    }

    private func sectionLabel(_ title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(gold)
                .frame(width: 37, height: 37)
                .background(ATHLTHPlanDesign.selectedSurface, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 19, weight: .medium, design: .serif))
                    .foregroundStyle(ink)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(dim)
            }
        }
        .frame(minHeight: 52)
    }

    private func fieldMenu<Value: Hashable>(
        _ title: String, selection: Binding<Value>,
        options: [Value], label: @escaping (Value) -> String
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(ink)
            Spacer(minLength: 0)
            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(label(option)).tag(option)
                }
            }
            .pickerStyle(.menu)
        }
        .frame(minHeight: 43)
    }
}

struct PerWorkoutGhostView: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @Binding var draft: GhostQuickStartDraft
    let route: TrainingRoute?
    @FocusState private var paceFieldFocused: Bool

    private var updatesBinding: Binding<WatchGhostRaceAudioConfiguration> {
        Binding(
            get: {
                draft.resolvedUpdates(fallback: settings.ghostRaceAudioConfiguration)
            },
            set: { value in
                draft.updatesConfiguration = value
                draft.updatesEnabled = value.enabled
            }
        )
    }

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
                                            .focused($paceFieldFocused)
                                            .onSubmit {
                                                draft.finalizeTargetPaceText(
                                                    distanceKilometers: route.distanceKilometers
                                                )
                                            }
                                            .onChange(of: paceFieldFocused) { _, focused in
                                                if !focused {
                                                    draft.finalizeTargetPaceText(
                                                        distanceKilometers: route.distanceKilometers
                                                    )
                                                }
                                            }
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

                if draft.enabled, route != nil {
                    ATHLTHPlanSurface(ghost: false) {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(ATHLTHLocalization.choose(
                                english: "How should Ghost run?",
                                norwegian: "Hvordan skal Ghost løpe?"
                            ), systemImage: "figure.run")
                            .font(.headline)
                            .foregroundStyle(ATHLTHPlanDesign.ink)

                            Text(ATHLTHLocalization.choose(
                                english: "The selected finish time stays the same. Only how Ghost distributes its pace changes.",
                                norwegian: "Ghost beholder samme sluttid. Du bestemmer hvordan farten fordeles underveis."
                            ))
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: 8),
                                    GridItem(.flexible(), spacing: 8)
                                ],
                                spacing: 8
                            ) {
                                ForEach(GhostTargetPacingStrategy.allCases) { strategy in
                                    Button {
                                        draft.pacingStrategy = strategy
                                    } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack {
                                                Image(systemName: strategy.icon)
                                                Spacer()
                                                if draft.pacingStrategy == strategy {
                                                    Image(systemName: "checkmark.circle.fill")
                                                }
                                            }
                                            .font(.subheadline.weight(.bold))
                                            Text(strategy.title)
                                                .font(.subheadline.weight(.semibold))
                                                .lineLimit(2)
                                            Text(strategy.subtitle)
                                                .font(.caption2)
                                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        .foregroundStyle(ATHLTHPlanDesign.ink)
                                        .frame(maxWidth: .infinity, minHeight: 89, alignment: .topLeading)
                                        .padding(11)
                                        .background(
                                            draft.pacingStrategy == strategy
                                                ? ATHLTHTheme.accentSoft
                                                : ATHLTHPlanDesign.surface,
                                            in: RoundedRectangle(cornerRadius: 14)
                                        )
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 14)
                                                .strokeBorder(
                                                    draft.pacingStrategy == strategy
                                                        ? ATHLTHPlanDesign.accentInk
                                                        : ATHLTHPlanDesign.warmDivider,
                                                    lineWidth: 1
                                                )
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityAddTraits(
                                        draft.pacingStrategy == strategy
                                            ? [.isSelected] : []
                                    )
                                }
                            }
                        }
                    }
                }

                if draft.enabled {
                    ATHLTHPlanSurface(ghost: false) {
                        Toggle(isOn: $draft.updatesEnabled) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(ATHLTHLocalization.choose(english: "Ghost updates", norwegian: "Ghost-oppdateringer"))
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

                        if draft.updatesEnabled {
                            Divider().overlay(ATHLTHPlanDesign.warmDivider)
                            ATHLTHGhostSessionUpdatesControls(
                                configuration: updatesBinding
                            )
                        }
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

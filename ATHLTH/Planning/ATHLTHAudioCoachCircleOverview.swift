import SwiftUI

/// One approachable Audio Coach home for iPhone and iPad. All controls edit
/// the SAME AudioCoachDraft used by Watch, saved profiles and the advanced
/// editors. This view never introduces a separate coach configuration.
struct ATHLTHAudioCoachCircleOverview: View {
    @EnvironmentObject private var settings: AppSettingsStore

    @Binding var draft: AudioCoachDraft
    @Binding var selectedProfileName: String?
    let showStructuredOptions: Bool
    let showRouteOptions: Bool
    let onEditRule: (UUID) -> Void
    let onEditOption: (ATHLTHAudioCoachOption) -> Void
    let onShowProfiles: () -> Void
    let onUseStandard: () -> Void
    let onAddMessage: () -> Void
    let onShowAdvanced: () -> Void

    @State private var zoneExpanded = true

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    private var gold: Color { ATHLTHPlanDesign.accentInk }
    private var ink: Color { ATHLTHPlanDesign.ink }
    private var dim: Color { ATHLTHPlanDesign.secondaryInk }

    private var zoneVoiceAlerts: Binding<Bool> {
        Binding(
            get: { draft.smartPrompts.targetZoneVoiceAlertsEnabled != false },
            set: { draft.smartPrompts.targetZoneVoiceAlertsEnabled = $0 }
        )
    }

    private var zoneRecovery: Binding<Bool> {
        Binding(
            get: { draft.smartPrompts.confirmWhenBackInZone != false },
            set: { draft.smartPrompts.confirmWhenBackInZone = $0 }
        )
    }

    private var shownOptions: [ATHLTHAudioCoachOption] {
        let standalone: Set<ATHLTHAudioCoachOption> = [
            .distanceUpdates, .timedUpdates, .distance, .elapsedTime,
            .averagePace, .clockTime, .heartRate, .targetZoneCoach,
            .motivation, .customAnnouncements
        ]
        return ATHLTHAudioCoachOption.allCases.filter { option in
            !standalone.contains(option) &&
            option.isVisible(route: showRouteOptions, structured: showStructuredOptions) &&
            option.isActive(in: draft)
        }
    }

    private var coachMessageCount: Int {
        let timed = (draft.distanceTriggerEnabled ? 1 : 0) +
            (draft.timeTriggerEnabled ? 1 : 0)
        let motivational = draft.smartPrompts.motivationEnabled ? 1 : 0
        let zone = (showStructuredOptions ||
                    draft.smartPrompts.preferredHeartRateZone != nil) &&
            draft.smartPrompts.targetZoneVoiceAlertsEnabled != false ? 1 : 0
        return timed + motivational + zone +
            draft.customRules.filter(\.isEnabled).count + shownOptions.count
    }

    private var activeTitle: String {
        guard let selectedProfileName, !selectedProfileName.isEmpty
        else { return tr("My Audio Coach", "Min Audio Coach") }
        return selectedProfileName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack(alignment: .center, spacing: 12) {
                Text("AUDIO COACH")
                    .font(.caption.weight(.bold))
                    .tracking(2.4)
                    .foregroundStyle(gold)

                Spacer(minLength: 0)

                Menu {
                    if settings.audioCoachProfiles.isEmpty {
                        Text(tr("No saved templates", "Ingen lagrede maler"))
                    } else {
                        ForEach(settings.audioCoachProfiles) { profile in
                            Button(profile.name) {
                                draft.load(profile: profile)
                                selectedProfileName = profile.name
                            }
                        }
                    }
                    Divider()
                    Button {
                        onUseStandard()
                    } label: {
                        Label(tr("Use standard Coach", "Bruk standard-coach"),
                              systemImage: "checkmark.circle")
                    }
                    Button {
                        onShowProfiles()
                    } label: {
                        Label(tr("Manage templates", "Administrer maler"),
                              systemImage: "square.stack")
                    }
                } label: {
                    Label(tr("My coach templates", "Mine coach-maler"),
                          systemImage: "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(gold)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(
                            ATHLTHPlanDesign.selectedSurface,
                            in: Capsule()
                        )
                }
                .accessibilityIdentifier("athlth-coach-circle-templates")
            }

            HStack {
                Spacer(minLength: 0)
                ZStack {
                    Circle()
                        .stroke(gold.opacity(0.09), lineWidth: 15)
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [gold.opacity(0.32), gold, gold.opacity(0.75), gold],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 9, lineCap: .round)
                        )
                    Circle()
                        .stroke(ATHLTHPlanDesign.warmDivider, lineWidth: 1)
                        .padding(17)

                    VStack(spacing: 8) {
                        Image(systemName: "waveform")
                            .font(.system(size: 27, weight: .medium))
                            .foregroundStyle(gold)
                            .accessibilityHidden(true)
                        Text(activeTitle)
                            .font(.system(size: 23, weight: .medium, design: .serif))
                            .foregroundStyle(ink)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.78)
                            .padding(.horizontal, 18)
                        Text(
                            draft.enabled
                            ? tr("\(coachMessageCount) active messages",
                                 "\(coachMessageCount) aktive beskjeder")
                            : tr("Voice guidance off", "Stemmeveiledning av")
                        )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(dim)
                    }
                }
                .frame(width: 225, height: 225)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("athlth-coach-template-circle")
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text(tr("Coach messages in the group",
                            "Coach-beskjeder i gruppen"))
                        .font(.system(size: 21, weight: .medium, design: .serif))
                        .foregroundStyle(ink)
                    Spacer(minLength: 6)
                    Button(action: onAddMessage) {
                        Label(tr("Add", "Legg til"), systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(gold)
                    .accessibilityIdentifier("athlth-coach-circle-add-message")
                }

                if showStructuredOptions ||
                   draft.smartPrompts.preferredHeartRateZone != nil {
                    DisclosureGroup(isExpanded: $zoneExpanded) {
                        VStack(alignment: .leading, spacing: 13) {
                            Text(tr(
                                "The target changes automatically with each interval. You do not need a separate message for every effort.",
                                "Målsonen følger hvert intervall automatisk. Du trenger ikke en egen beskjed for hvert drag."
                            ))
                            .font(.caption)
                            .foregroundStyle(dim)

                            HStack {
                                Text(tr("Target", "Mål"))
                                    .font(.subheadline)
                                Spacer()
                                Text(showStructuredOptions
                                    ? tr("From workout", "Fra treningsøkten")
                                    : draft.smartPrompts.preferredHeartRateZone.map {
                                        "Z\($0)"
                                    } ?? tr("From workout", "Fra treningsøkten"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(gold)
                            }

                            Toggle(tr("Warn when outside the zone",
                                      "Varsle når jeg er utenfor sonen"),
                                   isOn: zoneVoiceAlerts)
                                .tint(gold)
                                .accessibilityIdentifier("athlth-coach-zone-outside")

                            if zoneVoiceAlerts.wrappedValue {
                                Toggle(tr("Tell me when I'm back",
                                          "Si fra når jeg er tilbake"),
                                       isOn: zoneRecovery)
                                    .tint(gold)
                            }

                            if zoneVoiceAlerts.wrappedValue {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text(tr("Wait before alert", "Vent før varsel"))
                                            .font(.subheadline)
                                        Spacer(minLength: 8)
                                        Picker(tr("Wait before alert", "Vent før varsel"),
                                               selection: Binding(
                                                get: { draft.smartPrompts.targetZoneGraceSeconds ?? 10 },
                                                set: { draft.smartPrompts.targetZoneGraceSeconds = $0 }
                                               )) {
                                            ForEach([5, 10, 15, 20, 30], id: \.self) { seconds in
                                                Text("\(seconds) s").tag(seconds)
                                            }
                                        }
                                        .labelsHidden()
                                        .pickerStyle(.menu)
                                    }
                                    HStack {
                                        Text(tr("Repeat if still outside",
                                                "Gjenta hvis fortsatt utenfor"))
                                            .font(.subheadline)
                                        Spacer(minLength: 8)
                                        Picker(tr("Repeat if still outside",
                                                  "Gjenta hvis fortsatt utenfor"),
                                               selection: Binding(
                                                get: { draft.smartPrompts.targetZoneRepeatSeconds ?? 120 },
                                                set: { draft.smartPrompts.targetZoneRepeatSeconds = $0 }
                                               )) {
                                            ForEach([30, 45, 60, 90, 120, 180, 300], id: \.self) { seconds in
                                                Text(seconds.isMultiple(of: 60)
                                                    ? "\(seconds / 60) min" : "\(seconds) s")
                                                    .tag(seconds)
                                            }
                                        }
                                        .labelsHidden()
                                        .pickerStyle(.menu)
                                    }
                                    Text(tr(
                                        "Alerts restart for each new interval. No warning is sent for a pause without a target zone.",
                                        "Varslingen starter på nytt for hvert drag. Pauser uten pulsmål gir ingen varsler."
                                    ))
                                    .font(.caption)
                                    .foregroundStyle(dim)
                                }
                                .accessibilityIdentifier("athlth-coach-zone-timing")
                            }

                            Button {
                                onEditOption(.targetZoneCoach)
                            } label: {
                                Label(tr("Adjust target zone", "Juster målsone"),
                                      systemImage: "slider.horizontal.3")
                            }
                            .font(.subheadline)
                            .foregroundStyle(gold)
                        }
                        .padding(.top, 12)
                    } label: {
                        Label(tr("Heart-rate zone alerts", "Pulssonevarsler"),
                              systemImage: "heart.text.square")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ink)
                    }
                    .accessibilityIdentifier("athlth-coach-circle-zone-message")
                    Divider().overlay(ATHLTHPlanDesign.warmDivider)
                }

                if draft.timeTriggerEnabled {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(tr("Announces: ", "Leser opp: ") +
                                 standardMetrics.joined(separator: ", "))
                                .font(.subheadline)
                                .foregroundStyle(dim)
                            Button(tr("Edit message", "Rediger beskjed")) {
                                onEditOption(.timedUpdates)
                            }
                            .font(.subheadline.weight(.medium))
                        }
                        .padding(.top, 10)
                    } label: {
                        messageLabel(
                            tr("Every \(draft.timeIntervalSeconds) seconds",
                               "Hvert \(draft.timeIntervalSeconds) sekund"),
                            symbol: "clock"
                        )
                    }
                    Divider().overlay(ATHLTHPlanDesign.warmDivider)
                }

                if draft.distanceTriggerEnabled {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(tr("Announces: ", "Leser opp: ") +
                                 standardMetrics.joined(separator: ", "))
                                .font(.subheadline)
                                .foregroundStyle(dim)
                            Button(tr("Edit message", "Rediger beskjed")) {
                                onEditOption(.distanceUpdates)
                            }
                            .font(.subheadline.weight(.medium))
                        }
                        .padding(.top, 10)
                    } label: {
                        messageLabel(tr("Every \(Int(draft.distanceIntervalKilometers * 1000)) m",
                                        "Hver \(Int(draft.distanceIntervalKilometers * 1000)) m"),
                                     symbol: "figure.run")
                    }
                    Divider().overlay(ATHLTHPlanDesign.warmDivider)
                }

                ForEach(draft.customRules.filter(\.isEnabled)) { rule in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(rule.selectedMetrics.map(\.title)
                                .joined(separator: " · "))
                                .font(.subheadline)
                                .foregroundStyle(dim)
                            Button(tr("Edit message", "Rediger beskjed")) {
                                onEditRule(rule.id)
                            }
                            .font(.subheadline.weight(.medium))
                        }
                        .padding(.top, 10)
                    } label: {
                        messageLabel(
                            rule.trigger == .distance
                                ? tr("Every \(rule.validatedInterval) m",
                                     "Hver \(rule.validatedInterval) m")
                                : tr("Every \(rule.validatedInterval) seconds",
                                     "Hvert \(rule.validatedInterval) sekund"),
                            symbol: "waveform"
                        )
                    }
                    Divider().overlay(ATHLTHPlanDesign.warmDivider)
                }

                if draft.smartPrompts.motivationEnabled {
                    DisclosureGroup {
                        Button(tr("Edit encouragement", "Rediger motivasjon")) {
                            onEditOption(.motivation)
                        }
                        .padding(.top, 10)
                    } label: {
                        messageLabel(tr("Motivation", "Motivasjon"),
                                     symbol: "sparkles")
                    }
                    Divider().overlay(ATHLTHPlanDesign.warmDivider)
                }

                ForEach(shownOptions) { option in
                    DisclosureGroup {
                        Button(tr("Edit message", "Rediger beskjed")) {
                            onEditOption(option)
                        }
                        .padding(.top, 10)
                    } label: {
                        messageLabel(option.title, symbol: option.symbol)
                    }
                    Divider().overlay(ATHLTHPlanDesign.warmDivider)
                }

                if coachMessageCount == 0 {
                    Text(tr("Add your first coach message.",
                            "Legg til din første coach-beskjed."))
                        .font(.subheadline)
                        .foregroundStyle(dim)
                }
            }
            .padding(19)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 20))

            Button {
                onShowAdvanced()
            } label: {
                Label(tr("All settings", "Alle innstillinger"),
                      systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(gold)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .accessibilityIdentifier("athlth-audio-coach-circle-overview")
    }

    private var standardMetrics: [String] {
        var metrics: [String] = []
        if draft.announceDistance { metrics.append(tr("distance", "distanse")) }
        if draft.announceElapsedTime { metrics.append(tr("elapsed time", "medgått tid")) }
        if draft.announceHeartRate { metrics.append(tr("heart rate", "puls")) }
        if draft.announceAveragePace { metrics.append(tr("average pace", "snittempo")) }
        if draft.announceClockTime { metrics.append(tr("clock time", "klokkeslett")) }
        return metrics.isEmpty ? [tr("No metrics selected", "Ingen målinger valgt")] : metrics
    }

    private func messageLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .foregroundStyle(gold)
                .frame(width: 26)
            Text(title)
                .foregroundStyle(ink)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.leading)
        }
        .frame(minHeight: 44)
    }
}

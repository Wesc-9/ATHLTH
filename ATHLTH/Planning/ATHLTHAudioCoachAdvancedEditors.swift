import SwiftUI

/// Reactive rules are optional and use the existing Watch/iPhone coach engine.
/// The editor never stores a second, disconnected copy of audio preferences.
struct ATHLTHAudioCoachTargetZoneEditor: View {
    @Binding var smart: ATHLTHAudioCoachSmartSettings
    private let bronze = ATHLTHPlanDesign.accentInk
    private let ink = ATHLTHPlanDesign.ink
    private let dim = ATHLTHPlanDesign.secondaryInk

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    private var speakOutsideZone: Binding<Bool> {
        Binding(
            get: { smart.targetZoneVoiceAlertsEnabled ?? true },
            set: { smart.targetZoneVoiceAlertsEnabled = $0 }
        )
    }

    private var confirmRecovery: Binding<Bool> {
        Binding(
            get: { smart.confirmWhenBackInZone ?? true },
            set: { smart.confirmWhenBackInZone = $0 }
        )
    }

    var body: some View {
        ATHLTHPlanSurface(ghost: false) {
            VStack(alignment: .leading, spacing: 15) {
                Label(tr("Target-zone coaching", "Veiledning for målsone"),
                      systemImage: "heart.text.square")
                    .font(.headline)
                    .foregroundStyle(ink)
                Text(tr(
                    "Uses your planned heart-rate zone and live Watch measurements. It does not infer an unplanned target.",
                    "Bruker planlagt pulssone og ferske målinger fra Apple Watch. Dersom økten mangler en målsone, finner ikke ATHLTH på en."
                ))
                .font(.subheadline)
                .foregroundStyle(dim)

                Picker(tr("Target zone", "Målsone"), selection: Binding(
                get: { smart.preferredHeartRateZone ?? 0 },
                set: { smart.preferredHeartRateZone = $0 == 0 ? nil : $0 }
            )) {
                Text(tr("From workout", "Fra treningsøkt")).tag(0)
                ForEach(1...5, id: \.self) { zone in
                    Text(tr("Zone", "Sone") + " \(zone)").tag(zone)
                }
            }
            .pickerStyle(.menu)

            Toggle(tr("Alert me when I leave the target zone",
                          "Varsle når jeg går ut av målsonen"),
                       isOn: speakOutsideZone)
                    .tint(bronze)

                Toggle(tr("Confirm when I am back in the zone",
                          "Bekreft når jeg er tilbake i målsonen"),
                       isOn: confirmRecovery)
                    .tint(bronze)

                Text(tr(
                    "Short sensor fluctuations are filtered before any alert. Critical zone warnings take priority over regular announcements and motivation.",
                    "Korte pulsvariasjoner filtreres før varsling. Viktige målsonevarsler prioriteres foran vanlige oppdateringer og motivasjon."
                ))
                .font(.caption)
                .foregroundStyle(dim)
            }
        }
    }
}

/// Athlete-directed motivation on top of, or instead of, ATHLTH's automatic
/// contextual coach. Watch is the owner for live measurements; mirrored iPhone
/// uses the same source configuration and avoids terrain claims it cannot prove.
struct ATHLTHAudioCoachAdaptiveRulesEditor: View {
    @Binding var smart: ATHLTHAudioCoachSmartSettings

    private let bronze = ATHLTHPlanDesign.accentInk
    private let ink = ATHLTHPlanDesign.ink
    private let dim = ATHLTHPlanDesign.secondaryInk

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    private var controlMode: Binding<ATHLTHCoachMotivationControlMode> {
        Binding(
            get: { smart.coachingMode ?? .automatic },
            set: { smart.coachingMode = $0 }
        )
    }

    private var startSeconds: Binding<Int> {
        Binding(
            get: { smart.strongStartDurationSeconds ?? 0 },
            set: { smart.strongStartDurationSeconds = $0 }
        )
    }

    private var belowZone: Binding<Bool> {
        Binding(
            get: { smart.pushWhenBelowTargetZone ?? false },
            set: { smart.pushWhenBelowTargetZone = $0 }
        )
    }

    private var belowPace: Binding<Bool> {
        Binding(
            get: { smart.pushWhenBelowTargetPace ?? false },
            set: { smart.pushWhenBelowTargetPace = $0 }
        )
    }

    private var unexpectedDrop: Binding<Bool> {
        Binding(
            get: { smart.pushOnUnexpectedPaceDrop ?? false },
            set: { smart.pushOnUnexpectedPaceDrop = $0 }
        )
    }

    private var dropPercentage: Binding<Int> {
        Binding(
            get: { smart.paceDropThresholdPercent ?? 15 },
            set: { smart.paceDropThresholdPercent = $0 }
        )
    }

    private var cooldownSeconds: Binding<Int> {
        Binding(
            get: { smart.adaptiveCooldownSeconds ?? 150 },
            set: { smart.adaptiveCooldownSeconds = $0 }
        )
    }

    var body: some View {
        ATHLTHPlanSurface(ghost: false) {
            VStack(alignment: .leading, spacing: 16) {
                Label(tr("Situational motivation", "Situasjonsstyrt motivasjon"),
                      systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(ink)
                Text(tr(
                    "Choose when ATHLTH should intervene, instead of receiving only scheduled encouragement.",
                    "Bestem når ATHLTH skal gripe inn, i stedet for bare å få motivasjon til faste tider."
                ))
                .font(.subheadline)
                .foregroundStyle(dim)

                Picker(tr("Who decides?", "Hvem bestemmer?"), selection: controlMode) {
                    ForEach(ATHLTHCoachMotivationControlMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if controlMode.wrappedValue == .custom {
                    Divider().overlay(ATHLTHPlanDesign.warmDivider)
                    Label(tr("Start of the workout", "Starten av økten"),
                          systemImage: "bolt.heart")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                    Picker(tr("Extra motivation for the first", "Ekstra motivasjon første"),
                           selection: startSeconds) {
                        Text(tr("Off", "Av")).tag(0)
                        ForEach([60, 120, 180, 300, 600], id: \.self) { seconds in
                            Text("\(seconds / 60) min").tag(seconds)
                        }
                    }
                    .pickerStyle(.menu)

                    Divider().overlay(ATHLTHPlanDesign.warmDivider)
                    Label(tr("React to live training", "Reager på treningen"),
                          systemImage: "waveform.path.ecg")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                    Toggle(tr("Push when below my planned heart-rate zone",
                              "Push når jeg er under planlagt pulssone"),
                           isOn: belowZone)
                        .tint(bronze)
                    Toggle(tr("Push when slower than planned pace",
                              "Push når jeg løper saktere enn måltempo"),
                           isOn: belowPace)
                        .tint(bronze)
                    Toggle(tr("Push after a significant unexpected pace drop",
                              "Push ved et betydelig uventet fartsfall"),
                           isOn: unexpectedDrop)
                        .tint(bronze)

                    if unexpectedDrop.wrappedValue {
                        Stepper(value: dropPercentage, in: 8...35, step: 1) {
                            HStack {
                                Text(tr("Pace drop threshold", "Grense for fartsfall"))
                                Spacer()
                                Text("\(dropPercentage.wrappedValue)%")
                                    .monospacedDigit()
                            }
                        }
                        Text(tr(
                            "Only if good altitude data show that you are not climbing. Unknown terrain prevents this trigger.",
                            "Bare hvis pålitelige høydedata viser at du ikke løper i motbakke. Ved ukjent terreng varsler ikke denne regelen."
                        ))
                        .font(.caption)
                        .foregroundStyle(dim)
                    }

                    Picker(tr("How strongly should Coach push?",
                              "Hvor hardt skal coachen pushe?"),
                           selection: Binding(
                            get: { smart.encouragementStyle ?? .encouragement },
                            set: { smart.encouragementStyle = $0 }
                           )) {
                        ForEach(ATHLTHCoachEncouragementStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.menu)

                    if belowZone.wrappedValue {
                        Picker(tr("Repeat zone encouragement no sooner than",
                                  "Gjenta puls-push tidligst etter"),
                               selection: Binding(
                                get: { smart.belowZoneRepeatSeconds ?? 180 },
                                set: { smart.belowZoneRepeatSeconds = $0 }
                               )) {
                            ForEach([60, 120, 180, 300, 600], id: \.self) { seconds in
                                Text("\(seconds / 60) min").tag(seconds)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    if belowPace.wrappedValue {
                        Picker(tr("Repeat pace encouragement no sooner than",
                                  "Gjenta tempo-push tidligst etter"),
                               selection: Binding(
                                get: { smart.belowPaceRepeatSeconds ?? 180 },
                                set: { smart.belowPaceRepeatSeconds = $0 }
                               )) {
                            ForEach([60, 120, 180, 300, 600], id: \.self) { seconds in
                                Text("\(seconds / 60) min").tag(seconds)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    if unexpectedDrop.wrappedValue {
                        Picker(tr("Repeat pace-drop prompt no sooner than",
                                  "Gjenta tempofall-push tidligst etter"),
                               selection: Binding(
                                get: { smart.unexpectedDropRepeatSeconds ?? 240 },
                                set: { smart.unexpectedDropRepeatSeconds = $0 }
                               )) {
                            ForEach([60, 120, 180, 240, 300, 600], id: \.self) { seconds in
                                Text("\(seconds / 60) min").tag(seconds)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Divider().overlay(ATHLTHPlanDesign.warmDivider)
                    Picker(tr("Quiet time between interventions",
                              "Minst tid mellom push"),
                           selection: cooldownSeconds) {
                        ForEach([60, 90, 120, 150, 180, 300, 600], id: \.self) { seconds in
                            Text(seconds.isMultiple(of: 60)
                                 ? "\(seconds / 60) min"
                                 : "\(seconds) s")
                                .tag(seconds)
                        }
                    }
                    .pickerStyle(.menu)
                    Text(tr(
                        "The coach waits for a stable deviation, uses recent sensor readings and avoids repeating encouragement too often. Target zone and pace reminders only work where those goals are set.",
                        "Coachen venter på et stabilt avvik, krever ferske målinger og unngår hyppige gjentakelser. Pulssone- og fartspush krever at du har satt slike mål for økten."
                    ))
                    .font(.caption)
                    .foregroundStyle(dim)
                } else {
                    Text(tr(
                        "ATHLTH balances encouragement, effort, terrain and the finish while keeping routine announcements unobtrusive.",
                        "ATHLTH velger passende motivasjon etter innsats, terreng og hvor langt du har igjen, uten å overøse deg med beskjeder."
                    ))
                    .font(.caption)
                    .foregroundStyle(dim)
                }
            }
        }
    }
}

import SwiftUI

/// Advanced Audio Coach controls operate on the same Codable smart settings
/// that the Apple Watch engine receives. They never create new recorded data.
struct ATHLTHAudioCoachTargetZoneEditor: View {
    @Binding var smart: ATHLTHAudioCoachSmartSettings

    private let accent = ATHLTHPlanDesign.accentInk
    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        ATHLTHPlanSurface(ghost: false) {
            Text(tr("Target-zone guidance", "Veiledning for målsone"))
                .font(.headline)
            Text(tr(
                "Use the planned interval zone, or choose a zone for a free run. Requires fresh Watch heart-rate measurements and a valid maximum.",
                "Bruk planlagt pulssone i intervaller, eller velg målsone for fri løping. Krever ferske pulsmålinger fra Apple Watch og gyldig makspuls."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

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

            Toggle(tr("Warn when outside the target zone",
                      "Si fra når jeg går ut av målsonen"),
                   isOn: Binding(
                    get: { smart.targetZoneVoiceAlertsEnabled ?? true },
                    set: { smart.targetZoneVoiceAlertsEnabled = $0 }
                   ))
                .tint(accent)
            Toggle(tr("Confirm when holding or returning to target",
                      "Bekreft når jeg holder eller kommer tilbake i målsonen"),
                   isOn: Binding(
                    get: { smart.confirmWhenBackInZone ?? true },
                    set: { smart.confirmWhenBackInZone = $0 }
                   ))
                .tint(accent)
            Text(tr(
                "A short deviation does not trigger an alert. The Watch checks stable samples, applies grace periods and avoids repeated warnings.",
                "Kortvarige avvik varsles ikke. Klokken krever stabile målinger, bruker ventetid og begrenser gjentatte varsler."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
        }
    }
}

struct ATHLTHAudioCoachAdaptiveRulesEditor: View {
    @Binding var smart: ATHLTHAudioCoachSmartSettings

    private let accent = ATHLTHPlanDesign.accentInk
    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        ATHLTHPlanSurface(ghost: false) {
            Text(tr("Situational motivation", "Situasjonsstyrt motivasjon"))
                .font(.headline)
            Text(tr(
                "Let ATHLTH choose, or define exactly which situations should trigger a push.",
                "La ATHLTH velge selv, eller definer situasjonene som skal utløse ekstra motivasjon."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

            Picker(tr("Control", "Styring"), selection: Binding(
                get: { smart.coachingMode ?? .automatic },
                set: { smart.coachingMode = $0 }
            )) {
                ForEach(ATHLTHCoachMotivationControlMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if smart.coachingMode == .custom {
                Picker(tr("Push me harder at the start", "Mer push i starten"),
                       selection: Binding(
                        get: { smart.strongStartDurationSeconds ?? 0 },
                        set: { smart.strongStartDurationSeconds = $0 }
                       )) {
                    Text(tr("Off", "Av")).tag(0)
                    Text("1 min").tag(60)
                    Text("2 min").tag(120)
                    Text("3 min").tag(180)
                    Text("5 min").tag(300)
                }
                .pickerStyle(.menu)

                Toggle(tr("Encourage me below my target heart-rate zone",
                          "Motiver meg når pulsen er under målsonen"),
                       isOn: Binding(
                        get: { smart.pushWhenBelowTargetZone ?? false },
                        set: { smart.pushWhenBelowTargetZone = $0 }
                       ))
                    .tint(accent)

                Toggle(tr("Encourage me when slower than target pace",
                          "Motiver meg når farten er lavere enn måltempo"),
                       isOn: Binding(
                        get: { smart.pushWhenBelowTargetPace ?? false },
                        set: { smart.pushWhenBelowTargetPace = $0 }
                       ))
                    .tint(accent)

                Toggle(tr("Push me after an unexpected pace drop",
                          "Push meg ved uventet tempofall"),
                       isOn: Binding(
                        get: { smart.pushOnUnexpectedPaceDrop ?? false },
                        set: { smart.pushOnUnexpectedPaceDrop = $0 }
                       ))
                    .tint(accent)
                if smart.pushOnUnexpectedPaceDrop == true {
                    Picker(tr("Pace drop threshold", "Grense for tempofall"),
                           selection: Binding(
                            get: { smart.paceDropThresholdPercent ?? 15 },
                            set: { smart.paceDropThresholdPercent = $0 }
                           )) {
                        ForEach([10, 12, 15, 20, 25], id: \.self) { percent in
                            Text("\(percent) %").tag(percent)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Picker(tr("Minimum pause between prompts",
                          "Minimum pause mellom motiveringer"),
                       selection: Binding(
                        get: { smart.adaptiveCooldownSeconds ?? 150 },
                        set: { smart.adaptiveCooldownSeconds = $0 }
                       )) {
                    Text("1 min").tag(60)
                    Text("1:30").tag(90)
                    Text("2 min").tag(120)
                    Text("2:30").tag(150)
                    Text("3 min").tag(180)
                    Text("5 min").tag(300)
                }
                .pickerStyle(.menu)

                Text(tr(
                    "Unexpected pace-drop messages require accurate GPS altitude proving you're not climbing. Unknown terrain and stale measurements never trigger this warning.",
                    "Varsel om uventet tempofall krever nøyaktige GPS-høydedata som bekrefter at du ikke løper i motbakke. Ukjent terreng og gamle målinger utløser ingen slik beskjed."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
        }
    }
}

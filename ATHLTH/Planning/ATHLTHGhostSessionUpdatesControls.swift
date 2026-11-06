import SwiftUI

/// Edit the copied Ghost update configuration of one planned/quick workout.
/// This does not change the global Ghost notification preferences.
struct ATHLTHGhostSessionUpdatesControls: View {
    @Binding var configuration: WatchGhostRaceAudioConfiguration

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var distanceEnabled: Binding<Bool> {
        Binding(
            get: { configuration.distanceIntervalMeters != nil },
            set: { configuration.distanceIntervalMeters = $0 ? 1_000 : nil }
        )
    }

    private var timeEnabled: Binding<Bool> {
        Binding(
            get: { configuration.timeIntervalSeconds != nil },
            set: { configuration.timeIntervalSeconds = $0 ? 300 : nil }
        )
    }

    private var distanceInterval: Binding<Double> {
        Binding(
            get: { configuration.distanceIntervalMeters ?? 1_000 },
            set: { configuration.distanceIntervalMeters = $0 }
        )
    }

    private var timeInterval: Binding<TimeInterval> {
        Binding(
            get: { configuration.timeIntervalSeconds ?? 300 },
            set: { configuration.timeIntervalSeconds = $0 }
        )
    }

    private var statusMode: Binding<GhostRaceStatusDetailMode> {
        Binding(
            get: { configuration.resolvedStatusDetailMode },
            set: { configuration.statusDetailMode = $0 }
        )
    }

    private var periodicDelivery: Binding<WatchAlertDelivery> {
        Binding(
            get: { configuration.resolvedPeriodicDelivery },
            set: { configuration.periodicDelivery = $0 }
        )
    }

    private var overtakeAlerts: Binding<Bool> {
        Binding(
            get: { configuration.shouldAnnounceOvertakes },
            set: { configuration.announceOvertakes = $0 }
        )
    }

    private var finishAlert: Binding<Bool> {
        Binding(
            get: { configuration.shouldAnnounceFinalPhase },
            set: { configuration.finalPhaseEnabled = $0 }
        )
    }

    private var finishDistance: Binding<Double> {
        Binding(
            get: { configuration.resolvedFinalPhaseStartMeters },
            set: { configuration.finalPhaseStartMeters = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(tr("When Ghost speaks", "Når Ghost skal snakke"),
                  systemImage: "waveform.path")
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .foregroundStyle(ATHLTHPlanDesign.ink)
            Text(tr("These updates apply only to this race.",
                    "Disse oppdateringene gjelder bare denne konkurransen."))
                .font(.caption)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

            Toggle(tr("Periodic distance status", "Status etter distanse"),
                   isOn: distanceEnabled)
            if configuration.distanceIntervalMeters != nil {
                Picker(tr("Every", "Hver"), selection: distanceInterval) {
                    Text("250 m").tag(250.0)
                    Text("500 m").tag(500.0)
                    Text("1 km").tag(1_000.0)
                    Text("2 km").tag(2_000.0)
                    Text("5 km").tag(5_000.0)
                }
                .pickerStyle(.menu)
            }

            Toggle(tr("Periodic time status", "Status etter tid"),
                   isOn: timeEnabled)
            if configuration.timeIntervalSeconds != nil {
                Picker(tr("Every", "Hvert"), selection: timeInterval) {
                    Text("2 min").tag(120.0)
                    Text("5 min").tag(300.0)
                    Text("10 min").tag(600.0)
                    Text("15 min").tag(900.0)
                }
                .pickerStyle(.menu)
            }

            Divider().overlay(ATHLTHPlanDesign.warmDivider)
            Picker(tr("Compare", "Sammenlign"), selection: statusMode) {
                ForEach(GhostRaceStatusDetailMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)
            Picker(tr("Status delivery", "Levering av status"),
                   selection: periodicDelivery) {
                ForEach(WatchAlertDelivery.allCases) { method in
                    Text(method.title).tag(method)
                }
            }
            .pickerStyle(.menu)

            Divider().overlay(ATHLTHPlanDesign.warmDivider)
            Toggle(tr("Tell me when I overtake", "Varsle ved forbikjøring"),
                   isOn: overtakeAlerts)
            Toggle(tr("Extra lead-change updates", "Ekstra varsler ved ledelsesendringer"),
                   isOn: $configuration.announceLeadChanges)
            if configuration.announceLeadChanges {
                Picker(tr("Meaningful change", "Tydelig endring"),
                       selection: $configuration.leadChangeThresholdMeters) {
                    Text("25 m").tag(25.0)
                    Text("50 m").tag(50.0)
                    Text("100 m").tag(100.0)
                }
                .pickerStyle(.menu)
            }
            Toggle(tr("Final-stretch push", "Oppmuntring på siste etappe"),
                   isOn: finishAlert)
            if configuration.shouldAnnounceFinalPhase {
                Picker(tr("Start final stretch", "Start siste etappe"),
                       selection: finishDistance) {
                    Text("200 m").tag(200.0)
                    Text("500 m").tag(500.0)
                    Text("1 km").tag(1_000.0)
                }
                .pickerStyle(.menu)
            }
        }
        .foregroundStyle(ATHLTHPlanDesign.ink)
        .tint(ATHLTHPlanDesign.accentInk)
    }
}

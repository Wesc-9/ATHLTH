import SwiftUI

/// The same trigger catalogue is used for a named Coach group and for a
/// standalone command. Only configurations that the shared Watch/iPhone
/// engine can execute are offered here.
struct ATHLTHAudioCoachTriggerEditor: View {
    @Binding var trigger: ATHLTHAudioCoachRule.Trigger
    @Binding var interval: Int
    var supportsStructured: Bool

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }
    private let ink = ATHLTHPlanDesign.ink
    private let gold = ATHLTHPlanDesign.accentInk
    private let muted = ATHLTHPlanDesign.secondaryInk

    private var categories: [(String, [ATHLTHAudioCoachRule.Trigger])] {
        [
            (tr("TIME & DISTANCE", "TID OG DISTANSE"), [
                .time, .distance
            ]),
            (tr("HEART RATE", "PULS OG PULSSONE"), [
                .heartRateAbove, .heartRateBelow, .zoneEnter, .zoneExit
            ]),
            (tr("WORKOUT EVENTS", "ØKTHENDELSER"), [
                .workoutStart, .stepStart, .beforeNextStep
            ]),
            (tr("EFFORT & RECOVERY", "DRAG OG PAUSER"), [
                .effortStart, .effortEnd, .recoveryStart, .recoveryEnd,
                .activeRecoveryStart, .activeRecoveryEnd
            ]),
            (tr("WORKOUT SECTIONS", "ØKTDELER"), [
                .warmupStart, .warmupEnd, .beforeMain,
                .mainStart, .mainEnd, .beforeCooldown,
                .cooldownStart, .cooldownEnd
            ])
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(categories.enumerated()), id: \.offset) { _, category in
                VStack(alignment: .leading, spacing: 6) {
                    Text(category.0)
                        .font(.caption2.weight(.bold))
                        .tracking(1.3)
                        .foregroundStyle(gold)
                        .padding(.horizontal, 2)
                    VStack(spacing: 0) {
                        ForEach(Array(category.1.enumerated()), id: \.element) { index, item in
                            let unavailable = item.needsStructuredStep && !supportsStructured
                            Button {
                                trigger = item
                                switch item {
                                case .time: interval = 60
                                case .distance: interval = 1_000
                                case .heartRateAbove, .heartRateBelow: interval = 150
                                case .zoneEnter, .zoneExit: interval = 3
                                case .beforeNextStep, .beforeMain, .beforeCooldown: interval = 10
                                default: interval = 1
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: trigger == item
                                          ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(gold)
                                    Text(item.title)
                                        .font(.subheadline.weight(trigger == item
                                                                 ? .semibold : .regular))
                                        .foregroundStyle(ink)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if unavailable {
                                        Image(systemName: "lock")
                                            .foregroundStyle(muted)
                                    }
                                }
                                .padding(.horizontal, 13)
                                .frame(minHeight: 46)
                                .background(
                                    trigger == item
                                        ? ATHLTHPlanDesign.selectedSurface : Color.white,
                                    in: RoundedRectangle(cornerRadius: 12)
                                )
                            }
                            .disabled(unavailable)
                            .buttonStyle(.plain)
                            if index < category.1.count - 1 {
                                Divider().overlay(ATHLTHPlanDesign.warmDivider)
                                    .padding(.leading, 46)
                            }
                        }
                    }
                    .padding(7)
                    .background(.white, in: RoundedRectangle(cornerRadius: 17))
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(tr("TRIGGER DETAILS", "TRIGGERDETALJER"))
                    .font(.caption2.weight(.bold))
                    .tracking(1.3)
                    .foregroundStyle(gold)
                switch trigger {
                case .time:
                    Stepper(value: $interval, in: 15...7_200, step: 15) {
                        Text(tr("Every ", "Hvert ") + String(interval) +
                             tr(" seconds", " sekund"))
                    }
                case .distance:
                    Stepper(value: $interval, in: 100...42_000, step: 100) {
                        Text(tr("Every ", "Hver ") + String(interval) +
                             tr(" metres", " meter"))
                    }
                case .heartRateAbove, .heartRateBelow:
                    Stepper(value: $interval, in: 40...220, step: 5) {
                        Text(String(interval) + " bpm")
                    }
                case .zoneEnter, .zoneExit:
                    Picker(tr("Heart-rate zone", "Pulssone"), selection: $interval) {
                        ForEach(1...5, id: \.self) { zone in
                            Text("S" + String(zone)).tag(zone)
                        }
                    }
                    .pickerStyle(.segmented)
                case .beforeNextStep, .beforeMain, .beforeCooldown:
                    Picker(tr("Announce before", "Gi beskjed før"), selection: $interval) {
                        ForEach([5, 10, 15, 30, 60], id: \.self) { seconds in
                            Text(String(seconds) + " s").tag(seconds)
                        }
                    }
                    .pickerStyle(.menu)
                    Text(tr(
                        "Requires a planned step with a known remaining time.",
                        "Krever en planlagt deløkt der gjenværende tid kan beregnes."
                    ))
                    .font(.caption)
                    .foregroundStyle(muted)
                default:
                    Text(tr("Coach speaks when this event occurs.",
                            "Coach snakker når denne hendelsen inntreffer."))
                        .font(.caption)
                        .foregroundStyle(muted)
                }
            }
            .font(.subheadline)
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 17))
        }
    }
}

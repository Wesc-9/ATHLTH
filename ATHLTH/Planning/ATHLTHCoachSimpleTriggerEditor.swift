import SwiftUI

/// Simple, shared trigger picker for a single Coach command or a named group.
/// Time and distance are stored in SI units for iPhone/Watch scheduling.
struct ATHLTHCoachSimpleTriggerEditor: View {
    @Binding var trigger: ATHLTHAudioCoachRule.Trigger
    @Binding var interval: Int
    @Binding var eventSelection: ATHLTHCoachEventSelection
    @Binding var phases: [ATHLTHCoachWorkoutPhase]?
    let supportsStructured: Bool

    @State private var distanceUnit = 0
    @State private var timeUnit = 1

    private enum Family: String, CaseIterable, Identifiable {
        case distance, time, section, step, pause, heartZone
        var id: String { rawValue }
        var label: String {
            switch self {
            case .distance: return ATHLTHLocalization.choose(english: "Distance", norwegian: "Distanse")
            case .time: return ATHLTHLocalization.choose(english: "Time", norwegian: "Tid")
            case .section: return ATHLTHLocalization.choose(english: "Section", norwegian: "Del")
            case .step: return ATHLTHLocalization.choose(english: "Workout step", norwegian: "Deløkt")
            case .pause: return ATHLTHLocalization.choose(english: "Rest", norwegian: "Pause")
            case .heartZone: return ATHLTHLocalization.choose(english: "Heart-rate zone", norwegian: "Pulssone")
            }
        }
        var icon: String {
            switch self {
            case .distance: "point.bottomleft.forward.to.point.topright.scurvepath"
            case .time: "clock"
            case .section: "rectangle.split.3x1"
            case .step: "figure.run"
            case .pause: "pause.circle"
            case .heartZone: "heart"
            }
        }
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var family: Family {
        switch trigger {
        case .distance: .distance
        case .time: .time
        case .zoneEnter, .zoneExit, .heartRateAbove, .heartRateBelow: .heartZone
        case .warmupStart, .warmupEnd, .mainStart, .mainEnd,
             .cooldownStart, .cooldownEnd, .beforeMain, .beforeCooldown: .section
        case .recoveryStart, .recoveryEnd, .activeRecoveryStart,
             .activeRecoveryEnd: .pause
        default: .step
        }
    }

    private var distanceMultiplier: Double {
        switch distanceUnit {
        case 1: 1_000
        case 2: 10_000
        default: 1
        }
    }
    private var timeMultiplier: Double {
        switch timeUnit {
        case 1: 60
        case 2: 3_600
        default: 1
        }
    }
    private var amount: Binding<Double> {
        Binding(
            get: {
                Double(interval) / (trigger == .distance
                    ? distanceMultiplier : timeMultiplier)
            },
            set: { newValue in
                guard newValue.isFinite else { return }
                let unit = trigger == .distance ? distanceMultiplier : timeMultiplier
                let limits = trigger == .distance ? 100...42_000 : 15...7_200
                interval = min(max(Int((newValue * unit).rounded()), limits.lowerBound),
                               limits.upperBound)
            }
        )
    }

    private func choose(_ choice: Family) {
        switch choice {
        case .distance: trigger = .distance; interval = 1_000
        case .time: trigger = .time; interval = 60
        case .section: trigger = .warmupStart; interval = 1
        case .step: trigger = .stepStart; interval = 1
        case .pause: trigger = .recoveryStart; interval = 1
        case .heartZone: trigger = .zoneEnter; interval = 3
        }
        eventSelection = .every
        phases = nil
    }

    private func choice(_ item: ATHLTHAudioCoachRule.Trigger) -> some View {
        Button {
            trigger = item
        } label: {
            HStack(spacing: 10) {
                Image(systemName: trigger == item ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                Text(item.title)
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                Spacer()
            }
            .padding(.horizontal, 13)
            .frame(minHeight: 46)
            .background(trigger == item
                ? ATHLTHPlanDesign.selectedSurface : Color.white,
                in: RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(tr("CHOOSE TRIGGER", "VELG TRIGGER"))
                .font(.caption2.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                ForEach(Family.allCases) { item in
                    Button { choose(item) } label: {
                        HStack(spacing: 9) {
                            Image(systemName: item.icon)
                                .frame(width: 20)
                            Text(item.label).font(.subheadline.weight(.semibold))
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .foregroundStyle(family == item ? Color.white : ATHLTHPlanDesign.ink)
                        .background(family == item
                            ? ATHLTHPlanDesign.accentInk : Color.white,
                            in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .disabled(!supportsStructured && [.section, .step, .pause].contains(item))
                    .opacity(!supportsStructured && [.section, .step, .pause].contains(item)
                        ? 0.48 : 1)
                }
            }

            if trigger == .distance || trigger == .time {
                VStack(alignment: .leading, spacing: 9) {
                    Text(tr("EVERY", "HVER"))
                        .font(.caption2.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    HStack(spacing: 12) {
                        TextField("1", value: amount,
                                  format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .font(.title3.weight(.semibold))
                            .padding(12)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityIdentifier("athlth-coach-trigger-value")
                        Picker(tr("Unit", "Enhet"), selection:
                               trigger == .distance ? $distanceUnit : $timeUnit) {
                            if trigger == .distance {
                                Text("m").tag(0)
                                Text("km").tag(1)
                                Text("mil").tag(2)
                            } else {
                                Text(tr("sec", "sek")).tag(0)
                                Text(tr("min", "min")).tag(1)
                                Text(tr("hours", "timer")).tag(2)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(minWidth: 110)
                    }
                    Text(trigger == .distance
                        ? tr("Range: 100 m–42 km", "Område: 100 m–42 km")
                        : tr("Range: 15 seconds–2 hours", "Område: 15 sekunder–2 timer"))
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
            } else if family == .section {
                ForEach([
                    ATHLTHAudioCoachRule.Trigger.warmupStart, .warmupEnd,
                    .mainStart, .mainEnd, .cooldownStart, .cooldownEnd
                ], id: \.self) { choice($0) }
            } else if family == .step {
                choice(.stepStart)
                choice(.stepEnd)
                eventPicker([
                    .every, .first, .last, .mainOnly, .withoutRest
                ])
            } else if family == .pause {
                choice(.recoveryStart)
                choice(.recoveryEnd)
                eventPicker([.every, .first, .last])
            } else if family == .heartZone {
                choice(.zoneEnter)
                choice(.zoneExit)
                Text(tr("HEART-RATE ZONE", "PULSSONE"))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                Picker(tr("Zone", "Sone"), selection: $interval) {
                    ForEach(1...5, id: \.self) { zone in
                        Text("S\(zone)").tag(zone)
                    }
                }
                .pickerStyle(.segmented)
            }

            if family == .distance || family == .time || family == .heartZone ||
                family == .step || family == .pause {
                VStack(alignment: .leading, spacing: 8) {
                    Text(tr("APPLIES TO", "GJELDER FOR"))
                        .font(.caption2.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    Picker(tr("Section", "Del av økten"), selection: phaseBinding) {
                        Text(tr("Whole workout", "Hele økten")).tag("all")
                        Text(tr("Warm-up", "Oppvarming")).tag("warmup")
                        Text(tr("Main section", "Hoveddel")).tag("main")
                        Text(tr("Cool-down", "Avslutning")).tag("cooldown")
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(16)
        .background(ATHLTHPlanDesign.canvas, in: RoundedRectangle(cornerRadius: 20))
        .onAppear {
            if trigger == .distance {
                distanceUnit = interval >= 10_000 && interval % 10_000 == 0 ? 2 :
                    (interval >= 1_000 && interval % 1_000 == 0 ? 1 : 0)
            } else if trigger == .time {
                timeUnit = interval >= 3_600 && interval % 3_600 == 0 ? 2 :
                    (interval >= 60 && interval % 60 == 0 ? 1 : 0)
            }
        }
    }

    private func eventPicker(_ values: [ATHLTHCoachEventSelection]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(tr("WHICH ONES?", "HVILKE?"))
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
            ForEach(values) { value in
                Button { eventSelection = value } label: {
                    HStack {
                        Image(systemName: eventSelection == value
                              ? "checkmark.circle.fill" : "circle")
                        Text(value.title)
                        Spacer()
                    }
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                    .padding(12)
                    .background(eventSelection == value
                        ? ATHLTHPlanDesign.selectedSurface : Color.white,
                        in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var phaseBinding: Binding<String> {
        Binding(
            get: {
                guard let phase = phases?.first, phases?.count == 1 else {
                    return "all"
                }
                return phase.rawValue
            },
            set: { value in
                phases = value == "all" ? nil :
                    ATHLTHCoachWorkoutPhase(rawValue: value).map { [$0] }
            }
        )
    }
}

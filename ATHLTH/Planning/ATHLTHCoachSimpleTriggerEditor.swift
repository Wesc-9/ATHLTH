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
        case motivation, finish, elevation, pace
        var id: String { rawValue }
        var label: String {
            switch self {
            case .distance: return ATHLTHLocalization.choose(english: "Distance", norwegian: "Distanse")
            case .time: return ATHLTHLocalization.choose(english: "Time", norwegian: "Tid")
            case .section: return ATHLTHLocalization.choose(english: "Section", norwegian: "Del")
            case .step: return ATHLTHLocalization.choose(english: "Workout step", norwegian: "Deløkt")
            case .pause: return ATHLTHLocalization.choose(english: "Rest", norwegian: "Pause")
            case .heartZone: return ATHLTHLocalization.choose(english: "Heart rate", norwegian: "Puls")
            case .motivation: return ATHLTHLocalization.choose(english: "Motivation", norwegian: "Motivasjon")
            case .finish: return ATHLTHLocalization.choose(english: "Near goal", norwegian: "Nær mål")
            case .elevation: return ATHLTHLocalization.choose(english: "Elevation", norwegian: "Høydemeter")
            case .pace: return ATHLTHLocalization.choose(english: "Target pace", norwegian: "Måltempo")
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
            case .motivation: "sparkles"
            case .finish: "flag.checkered"
            case .elevation: "mountain.2"
            case .pace: "speedometer"
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
        case .zoneEnter, .zoneExit, .heartRateAbove, .heartRateBelow,
             .zoneBelow, .plannedZoneBelow, .plannedZoneOutside: .heartZone
        case .randomMotivation: .motivation
        case .nearFinishTime, .nearFinishDistance: .finish
        case .elevationGain, .uphillDetected: .elevation
        case .paceFasterThanTarget, .paceSlowerThanTarget,
             .paceFasterOverall, .paceFasterLastKilometer: .pace
        case .workoutStart, .warmupStart, .warmupEnd, .mainStart, .mainEnd,
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
                Double(interval) / (usesDistanceUnit
                    ? distanceMultiplier : timeMultiplier)
            },
            set: { newValue in
                guard newValue.isFinite else { return }
                let unit = usesDistanceUnit ? distanceMultiplier : timeMultiplier
                let limits: ClosedRange<Int>
                switch trigger {
                case .nearFinishDistance: limits = 25...5_000
                case .elevationGain: limits = 10...5_000
                case .nearFinishTime: limits = 10...1_800
                case .randomMotivation: limits = 120...900
                case .distance: limits = 100...42_000
                default: limits = 15...7_200
                }
                interval = min(max(Int((newValue * unit).rounded()), limits.lowerBound),
                               limits.upperBound)
            }
        )
    }

    private var usesDistanceUnit: Bool {
        trigger == .distance || trigger == .nearFinishDistance ||
            trigger == .elevationGain
    }

    private func choose(_ choice: Family) {
        switch choice {
        case .distance: trigger = .distance; interval = 1_000
        case .time: trigger = .time; interval = 60
        case .section: trigger = .warmupStart; interval = 1
        case .step: trigger = .stepStart; interval = 1
        case .pause: trigger = .recoveryStart; interval = 1
        case .heartZone: trigger = .zoneEnter; interval = 3
        case .motivation: trigger = .randomMotivation; interval = 240
        case .finish: trigger = .nearFinishTime; interval = 60
        case .elevation: trigger = .elevationGain; interval = 50
        case .pace: trigger = .paceSlowerThanTarget; interval = 1
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
                    .disabled(!supportsStructured && [.step, .pause].contains(item))
                    .opacity(!supportsStructured && [.step, .pause].contains(item)
                        ? 0.48 : 1)
                }
            }

            if family == .finish {
                choice(.nearFinishTime)
                choice(.nearFinishDistance)
            }
            if family == .elevation {
                choice(.elevationGain)
                choice(.uphillDetected)
                Text(tr("Uphill detection uses reliable outdoor GPS altitude and ignores uncertain terrain.",
                        "Motbakkeregistrering krever pålitelige høydemålinger utendørs."))
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }

            if trigger == .distance || trigger == .time ||
                trigger == .randomMotivation || trigger == .nearFinishTime ||
                trigger == .nearFinishDistance || trigger == .elevationGain {
                VStack(alignment: .leading, spacing: 9) {
                    Text((trigger == .nearFinishTime || trigger == .nearFinishDistance)
                        ? tr("WHEN REMAINING", "NÅR DET GJENSTÅR")
                        : trigger == .randomMotivation
                            ? tr("AVERAGE INTERVAL", "GJENNOMSNITTLIG INTERVALL")
                            : tr("EVERY", "HVER"))
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
                               usesDistanceUnit ? $distanceUnit : $timeUnit) {
                            if usesDistanceUnit {
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
                    Text(trigger == .randomMotivation
                        ? tr("Randomized within each interval. Coach prioritizes safety cues.",
                             "Tilfeldig tidspunkt innenfor intervallet. Viktige varsler prioriteres.")
                        : trigger == .nearFinishTime || trigger == .nearFinishDistance
                            ? tr("Only when the workout has a reliable goal.",
                                 "Kun når økten har et kjent og pålitelig mål.")
                            : trigger == .elevationGain
                                ? tr("Measured outdoor ascent only; GPS noise is ignored.",
                                     "Kun målt stigning utendørs. GPS-støy filtreres.")
                                : trigger == .distance
                                    ? tr("Range: 100 m–42 km", "Område: 100 m–42 km")
                                    : tr("Range: 15 seconds–2 hours", "Område: 15 sekunder–2 timer"))
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
            } else if family == .section {
                choice(.workoutStart)
                if supportsStructured {
                    ForEach([
                        ATHLTHAudioCoachRule.Trigger.warmupStart, .warmupEnd,
                        .mainStart, .mainEnd, .cooldownStart, .cooldownEnd
                    ], id: \.self) { choice($0) }
                }
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
                Text(tr("CHOOSE HEART-RATE TYPE", "VELG PULSTYPE"))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                Picker(tr("Type", "Type"), selection: heartType) {
                    Text(tr("BPM", "Puls")).tag(0)
                    Text(tr("Zone", "Pulssone")).tag(1)
                    Text(tr("Workout target", "Øktens målsone")).tag(2)
                }
                .pickerStyle(.segmented)
                if trigger == .heartRateAbove || trigger == .heartRateBelow {
                    choice(.heartRateAbove)
                    choice(.heartRateBelow)
                    TextField(tr("Heart rate BPM", "Puls i slag/min"),
                              value: $interval, format: .number)
                        .keyboardType(.numberPad)
                        .padding(12)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    Text(tr("40–220 BPM", "40–220 slag/min"))
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                } else if trigger == .plannedZoneBelow ||
                          trigger == .plannedZoneOutside {
                    choice(.plannedZoneBelow)
                    choice(.plannedZoneOutside)
                    Text(tr("Coach speaks only when the measured zone drops below the current exercise's prescribed zone.",
                            "Coach snakker bare når pulssonen faller under øktens angitte målsone."))
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                } else {
                    choice(.zoneEnter)
                    choice(.zoneExit)
                    choice(.zoneBelow)
                    Picker(tr("Zone", "Sone"), selection: $interval) {
                        ForEach(1...5, id: \.self) { zone in
                            Text("S\(zone)").tag(zone)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            } else if family == .pace {
                choice(.paceFasterThanTarget)
                choice(.paceSlowerThanTarget)
                Text(tr("Only fires when the active exercise has an authored pace target.",
                        "Varsler bare når den aktive øvelsen har angitt måltempo."))
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }

            if supportsStructured &&
                (family == .distance || family == .time || family == .heartZone ||
                 family == .step || family == .pause || family == .motivation ||
                 family == .finish || family == .elevation || family == .pace) {
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

    private var heartType: Binding<Int> {
        Binding(
            get: {
                switch trigger {
                case .heartRateAbove, .heartRateBelow: return 0
                case .plannedZoneBelow, .plannedZoneOutside: return 2
                default: return 1
                }
            },
            set: { selected in
                switch selected {
                case 0: trigger = .heartRateAbove; interval = 150
                case 2: trigger = .plannedZoneBelow; interval = 1
                default: trigger = .zoneEnter; interval = 3
                }
            }
        )
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

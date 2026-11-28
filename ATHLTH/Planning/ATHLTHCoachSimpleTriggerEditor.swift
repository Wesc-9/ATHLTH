import SwiftUI

/// Simple, shared trigger picker for a single Coach command or a named group.
/// Time and distance are stored in SI units for iPhone/Watch scheduling.
struct ATHLTHCoachSimpleTriggerEditor: View {
    @Binding var trigger: ATHLTHAudioCoachRule.Trigger
    @Binding var interval: Int
    @Binding var eventSelection: ATHLTHCoachEventSelection
    @Binding var phases: [ATHLTHCoachWorkoutPhase]?
    let supportsStructured: Bool
    var triggerAvailability: ATHLTHCoachTriggerAvailability = .global
    @Binding var activityFilter: ATHLTHCoachActivityFilter
    var historicalReferences: [ATHLTHCoachHistoricalRunReference] = []
    @Binding var historicalWorkoutID: UUID?
    @Binding var conditions: ATHLTHCoachTriggerConditions

    @State private var distanceUnit = 0
    @State private var timeUnit = 1

    private enum Family: String, CaseIterable, Identifiable {
        case distance, time, section, step, pause, heartZone
        case motivation, finish, elevation, pace, history, record
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
            case .history: return ATHLTHLocalization.choose(english: "Previous workout", norwegian: "Tidligere økt")
            case .record: return ATHLTHLocalization.choose(english: "Personal record", norwegian: "Personlig rekord")
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
            case .history: "clock.arrow.circlepath"
            case .record: "trophy"
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
        case .personalRecordConfirmed: .record
        case .nearFinishTime: .finish
        case .nearFinishDistance: .finish
        case .slowerThanPreviousWorkout: .history
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

    private func familyAvailable(_ item: Family) -> Bool {
        let available: (ATHLTHAudioCoachRule.Trigger) -> Bool = {
            triggerAvailability.supports($0, for: activityFilter)
        }
        switch item {
        case .distance: return available(.distance)
        case .time: return available(.time)
        case .section: return available(.workoutStart)
        case .heartZone: return available(.heartRateAbove)
        case .motivation: return available(.randomMotivation)
        case .step: return supportsStructured && available(.stepStart)
        case .pause: return supportsStructured && available(.recoveryStart)
        case .finish: return available(.nearFinishTime) ||
            available(.nearFinishDistance)
        case .elevation: return available(.elevationGain)
        case .pace: return available(.paceSlowerThanTarget) ||
            available(.paceFasterOverall) || available(.paceFasterLastKilometer)
        case .record: return available(.personalRecordConfirmed)
        case .history: return !historicalReferences.isEmpty &&
            available(.slowerThanPreviousWorkout)
        }
    }

    private func choose(_ choice: Family) {
        guard familyAvailable(choice), family != choice else { return }
        switch choice {
        case .distance: trigger = .distance; interval = 1_000
        case .time: trigger = .time; interval = 60
        case .section: trigger = .workoutStart; interval = 1
        case .step: trigger = .stepStart; interval = 1
        case .pause: trigger = .recoveryStart; interval = 1
        case .heartZone: trigger = .zoneEnter; interval = 3
        case .motivation: trigger = .randomMotivation; interval = 240
        case .finish:
            if triggerAvailability.supports(.nearFinishTime, for: activityFilter) {
                trigger = .nearFinishTime; interval = 60
            } else {
                trigger = .nearFinishDistance; interval = 100
            }
        case .elevation: trigger = .elevationGain; interval = 50
        case .pace:
            if triggerAvailability.supports(.paceSlowerThanTarget, for: activityFilter) {
                trigger = .paceSlowerThanTarget; interval = 1
            } else {
                trigger = .paceFasterOverall; interval = 300
            }
        case .record: trigger = .personalRecordConfirmed; interval = 1
        case .history: trigger = .slowerThanPreviousWorkout; interval = 1
        }
        eventSelection = .every
        phases = nil
    }

    private func choice(
        _ item: ATHLTHAudioCoachRule.Trigger,
        title: String? = nil,
        enabled: Bool = true
    ) -> some View {
        let isAvailable = enabled &&
            triggerAvailability.supports(item, for: activityFilter)
        return Button {
            guard isAvailable else { return }
            guard trigger != item else { return }
            trigger = item
            switch item {
            case .beforeNextStep, .beforeMain, .beforeCooldown:
                interval = 15
                eventSelection = item == .beforeNextStep ? .withoutRest : .every
                phases = nil
            case .nearFinishTime: interval = 30
            case .nearFinishDistance: interval = 100
            case .distance: interval = 1000
            case .elevationGain: interval = 50
            case .paceFasterOverall, .paceFasterLastKilometer:
                interval = 300
            case .heartRateAbove, .heartRateBelow:
                interval = (40...220).contains(interval) ? interval : 150
            case .zoneEnter, .zoneExit, .zoneBelow:
                interval = (1...5).contains(interval) ? interval : 3
            case .stepStart, .stepEnd, .effortStart, .effortEnd,
                 .activeRecoveryStart, .activeRecoveryEnd, .recoveryStart, .recoveryEnd:
                eventSelection = .every
            default: break
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: trigger == item ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                Text(title ?? item.title)
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
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.42)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(tr("WORKOUT MODE", "TRENINGSFORM"))
                .font(.caption2.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
            Picker(tr("Applies to", "Gjelder for"), selection: $activityFilter) {
                ForEach(ATHLTHCoachActivityFilter.allCases) { activity in
                    Text(activity.title).tag(activity)
                        .disabled(
                            triggerAvailability.isWorkoutSpecific &&
                            triggerAvailability.workoutActivity != nil &&
                            activity != .all &&
                            activity != triggerAvailability.workoutActivity &&
                            !(activity == .intervals &&
                              triggerAvailability.workoutActivity == .running &&
                              supportsStructured)
                        )
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
            .onChange(of: activityFilter) { _, next in
                if !triggerAvailability.supports(trigger, for: next) {
                    // An incompatible trigger must not remain selected or
                    // survive a save while its new sport lacks that metric.
                    trigger = .time
                    interval = 60
                }
            }

            Text(tr("CHOOSE TRIGGER", "VELG TRIGGER"))
                .font(.caption2.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
            triggerCategory(tr("Time and distance", "Tid og distanse"),
                            families: [.time, .distance, .finish])
            triggerCategory(tr("Heart rate and intensity", "Puls og intensitet"),
                            families: [.heartZone])
            triggerCategory(tr("Pace and performance", "Tempo og prestasjon"),
                            families: [.pace, .record, .elevation, .history])
            triggerCategory(tr("Workout and intervals", "Økt og intervaller"),
                            families: [.section, .step, .pause])
            triggerCategory(tr("Smart coaching", "Smart coaching"),
                            families: [.motivation])

            Text(tr("SETTINGS", "INNSTILLINGER"))
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
            Label(family.label, systemImage: family.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHPlanDesign.ink)

            if family == .finish {
                choice(.nearFinishTime)
                choice(.nearFinishDistance)
            }
            if !triggerAvailability.supports(trigger, for: activityFilter) {
                Text(tr(
                    "This workout does not have the required measured data or programmed target. Choose another trigger.",
                    "Denne økten mangler nødvendige målinger eller et definert mål. Velg en annen trigger."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
            if family == .history {
                if historicalReferences.isEmpty {
                    Text(tr(
                        "No previous workout with a verified first-kilometre recording. This trigger is unavailable.",
                        "Ingen tidligere økt med registrert første kilometer. Triggeren er deaktivert."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                } else {
                    Text(tr("COMPARE WITH", "SAMMENLIGN MED"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    Picker(tr("Workout", "Økt"), selection: $historicalWorkoutID) {
                        Text(tr("Select earlier workout", "Velg tidligere økt"))
                            .tag(nil as UUID?)
                        ForEach(historicalReferences) { workout in
                            Text(
                                "\(workout.title) · \(Int(workout.firstKilometerSeconds / 60)):\(String(format: "%02d", Int(workout.firstKilometerSeconds) % 60))/km"
                            )
                            .tag(workout.id as UUID?)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(tr(
                        "After the first kilometre, Coach compares your measured pace with this previously recorded split.",
                        "Etter første kilometer sammenlignes faktisk tempo med den valgte øktens målte tid."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
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
                    choice(.beforeMain)
                    choice(.beforeCooldown)
                    if trigger == .beforeMain || trigger == .beforeCooldown {
                        boundaryLeadPicker
                    }
                }
            } else if family == .step {
                choice(.stepStart)
                choice(.stepEnd)
                choice(.effortStart)
                choice(.effortEnd)
                choice(.beforeNextStep)
                if trigger == .beforeNextStep { boundaryLeadPicker }
                if trigger == .stepStart || trigger == .stepEnd || trigger == .beforeNextStep {
                    eventPicker([.every, .first, .last, .mainOnly, .withoutRest])
                }
            } else if family == .pause {
                choice(.recoveryStart)
                choice(.recoveryEnd)
                choice(.activeRecoveryStart)
                choice(.activeRecoveryEnd)
                if trigger == .recoveryStart || trigger == .recoveryEnd {
                    eventPicker([.every, .first, .last])
                }
            } else if family == .heartZone {
                Text(tr("CHOOSE HEART-RATE TYPE", "VELG PULSTYPE"))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                Picker(tr("Type", "Type"), selection: heartType) {
                    Text(tr("BPM", "Puls")).tag(0)
                    Text(tr("Zone", "Pulssone")).tag(1)
                    if triggerAvailability.supports(.plannedZoneBelow, for: activityFilter) {
                        Text(tr("Workout target", "Øktens målsone")).tag(2)
                    }
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
                    Text(tr("Uses the current exercise's prescribed zone. Choose below target or outside target.",
                            "Bruker målsone fra den aktive øvelsen. Velg under eller utenfor målsone."))
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
                choice(.paceFasterOverall)
                choice(.paceFasterLastKilometer)
                if trigger == .paceFasterOverall || trigger == .paceFasterLastKilometer {
                    Stepper(String(format: "%d:%02d min/km", interval / 60, interval % 60),
                            value: $interval, in: 120...1800, step: 5)
                        .padding(12)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                } else {
                    Text(tr("Only fires when the active exercise has an authored pace target.",
                            "Varsler bare når den aktive øvelsen har angitt måltempo."))
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
            } else if family == .record {
                Text(tr("Only announces a verified personal record, never an estimated result.",
                        "Varsler kun ved en bekreftet personlig rekord, aldri et estimert resultat."))
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
                        Text(tr("Recovery", "Pause")).tag("recovery")
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if trigger.supportsThresholdConditions {
                thresholdConditions
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("PREVIEW", "FORHÅNDSVISNING"))
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                Text(trigger.summary(interval: interval))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                if trigger.supportsThresholdConditions && !conditions.isEmpty {
                    Text(conditions.summary)
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
                if eventSelection != .every {
                    Text(eventSelection.title)
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
                if let phases, !phases.isEmpty {
                    Text(phases.map(\.title).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityIdentifier("athlth-coach-trigger-preview")
        }
        .padding(16)
        .background(ATHLTHPlanDesign.canvas, in: RoundedRectangle(cornerRadius: 20))
        .onAppear {
            if trigger == .distance || trigger == .nearFinishDistance || trigger == .elevationGain {
                distanceUnit = interval >= 10_000 && interval % 10_000 == 0 ? 2 :
                    (interval >= 1_000 && interval % 1_000 == 0 ? 1 : 0)
            } else if trigger == .time || trigger == .randomMotivation || trigger == .nearFinishTime {
                timeUnit = interval >= 3_600 && interval % 3_600 == 0 ? 2 :
                    (interval >= 60 && interval % 60 == 0 ? 1 : 0)
            }
        }
    }

    private var thresholdConditions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("ADDITIONAL CONDITIONS", "TILLEGGSBETINGELSER"))
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
            Picker(tr("Condition duration", "Varighet på avvik"), selection: $conditions.sustainedSeconds) {
                Text(tr("Immediately", "Med en gang")).tag(nil as Int?)
                ForEach([10, 20, 30, 60, 120], id: \.self) { value in
                    Text("\(value) " + tr("sec", "sek")).tag(value as Int?)
                }
            }
            Picker(tr("Minimum between cues", "Minst mellom varsler"), selection: $conditions.repeatDelaySeconds) {
                Text(tr("No extra limit", "Ingen ekstra grense")).tag(nil as Int?)
                ForEach([30, 60, 120, 180, 300], id: \.self) { value in
                    Text("\(value) " + tr("sec", "sek")).tag(value as Int?)
                }
            }
            Picker(tr("Maximum heart-rate zone", "Maksimal pulssone"), selection: $conditions.maximumZone) {
                Text(tr("Any zone", "Alle soner")).tag(nil as Int?)
                ForEach(1...5, id: \.self) { value in
                    Text("S\(value)").tag(value as Int?)
                }
            }
            Text(tr("All selected conditions must be satisfied. Missing heart-rate data cannot satisfy a zone limit.",
                    "Alle valgte betingelser må være oppfylt. Manglende pulsdata kan ikke oppfylle en sonegrense."))
                .font(.caption)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
        }
        .pickerStyle(.menu)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func triggerCategory(_ title: String, families: [Family]) -> some View {
        let available = families.filter { familyAvailable($0) || family == $0 }
        if !available.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                ForEach(available) { item in
                    Button { choose(item) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.icon)
                                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                .frame(width: 24)
                            Text(item.label)
                                .font(.subheadline.weight(.medium))
                            Spacer(minLength: 0)
                            Image(systemName: family == item ? "checkmark.circle.fill" : "chevron.right")
                                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        }
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(family == item ? ATHLTHPlanDesign.selectedSurface : Color.white,
                                    in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(!familyAvailable(item))
                    .opacity(familyAvailable(item) ? 1 : 0.42)
                    .accessibilityAddTraits(family == item ? .isSelected : [])
                }
            }
        }
    }

    private var boundaryLeadPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("SECONDS BEFORE", "SEKUNDER FØR"))
                .font(.caption2.weight(.bold))
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
            Stepper("\(min(max(interval, 5), 60)) " + tr("sec", "sek"),
                    value: $interval, in: 5...60)
                .padding(12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            Text(tr("Uses the current timed step's remaining time.",
                    "Bruker gjenstående tid i deløkten som pågår."))
                .font(.caption)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
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

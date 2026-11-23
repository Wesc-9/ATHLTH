import Foundation

/// Workout phases for named Coach groups. Existing groups remain enabled for
/// the entire workout unless the athlete explicitly selects a phase.
enum ATHLTHCoachWorkoutPhase: String, Codable, CaseIterable, Identifiable {
    case warmup, main, recovery, cooldown

    var id: String { rawValue }
    var title: String {
        switch self {
        case .warmup: return ATHLTHLocalization.choose(english: "Warm-up", norwegian: "Oppvarming")
        case .main: return ATHLTHLocalization.choose(english: "Main section", norwegian: "Hoveddel")
        case .recovery: return ATHLTHLocalization.choose(english: "Recovery / rest", norwegian: "Pause")
        case .cooldown: return ATHLTHLocalization.choose(english: "Cool-down", norwegian: "Nedjogging")
        }
    }

    func matches(stepPhase: String?) -> Bool {
        switch self {
        case .warmup: return stepPhase == "warmup"
        case .main:
            return stepPhase == "work" || stepPhase == "steady" ||
                stepPhase == "main" || stepPhase == "recovery"
        case .recovery: return stepPhase == "recovery"
        case .cooldown: return stepPhase == "cooldown"
        }
    }
}

/// Additional choice for structured step/rest triggers. Optional on persisted
/// rules to preserve decoding of existing plans and Watch transfers.
enum ATHLTHCoachEventSelection: String, Codable, CaseIterable, Identifiable {
    case every, first, last, mainOnly, withoutRest
    var id: String { rawValue }
    var title: String {
        switch self {
        case .every: return ATHLTHLocalization.choose(english: "Every", norwegian: "Alle")
        case .first: return ATHLTHLocalization.choose(english: "First", norwegian: "Første")
        case .last: return ATHLTHLocalization.choose(english: "Last", norwegian: "Siste")
        case .mainOnly: return ATHLTHLocalization.choose(english: "All in main section", norwegian: "Alle i hoveddelen")
        case .withoutRest: return ATHLTHLocalization.choose(english: "All except rests", norwegian: "Alle uten pause")
        }
    }
}

enum ATHLTHCoachMetricCategory: String, CaseIterable, Identifiable {
    case workout, heartRate, exercises, motivation, navigation
    var id: String { rawValue }
    var title: String {
        switch self {
        case .workout: return ATHLTHLocalization.choose(english: "Workout data", norwegian: "Øktdata")
        case .heartRate: return ATHLTHLocalization.choose(english: "Heart rate", norwegian: "Puls")
        case .exercises: return ATHLTHLocalization.choose(english: "Exercises", norwegian: "Øvelser")
        case .motivation: return ATHLTHLocalization.choose(english: "Motivation", norwegian: "Motivasjon")
        case .navigation: return ATHLTHLocalization.choose(english: "Route", norwegian: "Rute")
        }
    }
}

/// Independent periodic Audio Coach rules. Stored as part of the iPhone
/// settings and copied unchanged to a Watch workout's configuration.
struct ATHLTHAudioCoachRule: Codable, Hashable, Identifiable {
    /// Persisted in the same rules transferred to Watch. Existing raw values
    /// remain intact; newly configured event rules share the normal cue ledger.
    enum Trigger: String, Codable, CaseIterable, Identifiable {
        case distance, time
        // New user-configured events are optional for older saved templates.
        case randomMotivation, nearFinishTime, nearFinishDistance
        case elevationGain, uphillDetected
        case heartRateAbove, heartRateBelow, zoneEnter, zoneExit
        case zoneBelow, plannedZoneBelow, plannedZoneOutside
        // Thresholds are expressed in seconds per kilometre (300 = 5:00).
        case paceFasterOverall, paceFasterLastKilometer
        // The currently planned exercise/treadmill pace target is consulted live.
        case paceFasterThanTarget, paceSlowerThanTarget
        case personalRecordConfirmed
        case workoutStart
        case effortStart, effortEnd, recoveryStart, recoveryEnd
        case activeRecoveryStart, activeRecoveryEnd
        case warmupStart, warmupEnd, mainStart, mainEnd
        case cooldownStart, cooldownEnd
        case stepStart, stepEnd, beforeNextStep, beforeMain, beforeCooldown

        var id: String { rawValue }
        var isPeriodic: Bool {
            self == .time || self == .distance || self == .elevationGain
        }
        var usesLiveContext: Bool {
            switch self {
            case .nearFinishTime, .nearFinishDistance, .elevationGain,
                 .uphillDetected, .plannedZoneBelow, .plannedZoneOutside: return true
            default: return false
            }
        }
        var isPaceCondition: Bool {
            switch self {
            case .paceFasterOverall, .paceFasterLastKilometer,
                 .paceFasterThanTarget, .paceSlowerThanTarget: return true
            default: return false
            }
        }
        var isHeartRateCondition: Bool {
            switch self {
            case .heartRateAbove, .heartRateBelow, .zoneEnter, .zoneExit,
                 .zoneBelow, .plannedZoneBelow, .plannedZoneOutside:
                return true
            default:
                return false
            }
        }
        var needsStructuredStep: Bool {
            !isPeriodic && !isHeartRateCondition && !isPaceCondition &&
                self != .personalRecordConfirmed && self != .workoutStart &&
                self != .randomMotivation && self != .nearFinishTime &&
                self != .nearFinishDistance && self != .uphillDetected
        }
        func summary(interval: Int) -> String {
            let value: Int
            switch self {
            case .time: value = min(max(interval, 15), 7_200)
            case .distance: value = min(max(interval, 100), 42_000)
            case .randomMotivation: value = min(max(interval, 120), 900)
            case .nearFinishTime: value = min(max(interval, 10), 1_800)
            case .nearFinishDistance: value = min(max(interval, 25), 5_000)
            case .elevationGain: value = min(max(interval, 10), 5_000)
            case .heartRateAbove, .heartRateBelow: value = min(max(interval, 40), 220)
            case .paceFasterOverall, .paceFasterLastKilometer: value = min(max(interval, 120), 1_800)
            case .zoneEnter, .zoneExit, .zoneBelow: value = min(max(interval, 1), 5)
            case .beforeNextStep, .beforeMain, .beforeCooldown:
                value = min(max(interval, 5), 60)
            default: return title
            }
            switch self {
            case .time, .randomMotivation, .nearFinishTime:
                return title + " · " + String(value) + " s"
            case .distance, .nearFinishDistance, .elevationGain:
                return title + " · " + String(value) + " m"
            case .heartRateAbove, .heartRateBelow:
                return title + " · " + String(value) + " bpm"
            case .paceFasterOverall, .paceFasterLastKilometer:
                return title + " · " + String(format: "%d:%02d min/km", value / 60, value % 60)
            case .zoneEnter, .zoneExit, .zoneBelow:
                return title + " · S" + String(value)
            case .beforeNextStep, .beforeMain, .beforeCooldown:
                return title + " · " + String(value) + " s"
            default: return title
            }
        }

        var title: String {
            func tr(_ en: String, _ no: String) -> String {
                ATHLTHLocalization.choose(english: en, norwegian: no)
            }
            switch self {
            case .distance: return tr("Distance", "Distanse")
            case .time: return tr("Time", "Tid")
            case .randomMotivation: return tr("Random motivation", "Tilfeldig motivasjon")
            case .nearFinishTime: return tr("Near time goal", "Nær tidsmålet")
            case .nearFinishDistance: return tr("Near distance goal", "Nær distansemålet")
            case .elevationGain: return tr("Elevation gained", "Høydemeter")
            case .uphillDetected: return tr("When climbing", "Når du løper oppover")
            case .zoneBelow: return tr("Below heart-rate zone", "Under pulssone")
            case .plannedZoneBelow: return tr("Below workout target zone", "Under øktens målsone")
            case .plannedZoneOutside: return tr("Outside workout target zone", "Utenfor øktens målsone")
            case .heartRateAbove: return tr("Heart rate above", "Puls over")
            case .heartRateBelow: return tr("Heart rate below", "Puls under")
            case .paceFasterOverall: return tr("Total pace faster than", "Snittempo raskere enn")
            case .paceFasterLastKilometer: return tr("Last-km pace faster than", "Siste kilometer raskere enn")
            case .paceFasterThanTarget: return tr("Faster than exercise target", "Raskere enn målfart")
            case .paceSlowerThanTarget: return tr("Slower than exercise target", "Saktere enn målfart")
            case .personalRecordConfirmed: return tr("Confirmed personal record", "Bekreftet personlig rekord")
            case .zoneEnter: return tr("Enter HR zone", "Inn i pulssone")
            case .zoneExit: return tr("Leave HR zone", "Ut av pulssone")
            case .workoutStart: return tr("Workout starts", "Økten starter")
            case .effortStart: return tr("Effort starts", "Drag starter")
            case .effortEnd: return tr("Effort ends", "Drag avsluttes")
            case .recoveryStart: return tr("Recovery starts", "Pause starter")
            case .recoveryEnd: return tr("Recovery ends", "Pause avsluttes")
            case .activeRecoveryStart: return tr("Active recovery starts", "Aktiv pause starter")
            case .activeRecoveryEnd: return tr("Active recovery ends", "Aktiv pause avsluttes")
            case .warmupStart: return tr("Warm-up starts", "Oppvarming starter")
            case .warmupEnd: return tr("Warm-up ends", "Oppvarming avsluttes")
            case .mainStart: return tr("Main part starts", "Hoveddel starter")
            case .mainEnd: return tr("Main part ends", "Hoveddel avsluttes")
            case .cooldownStart: return tr("Cool-down starts", "Nedjogging starter")
            case .cooldownEnd: return tr("Cool-down ends", "Nedjogging avsluttes")
            case .stepStart: return tr("Each workout step starts", "Hver deløkt starter")
            case .stepEnd: return tr("Each workout step ends", "Hver deløkt avsluttes")
            case .beforeNextStep: return tr("Before next step", "Før neste deløkt")
            case .beforeMain: return tr("Before main part", "Før hoveddelen")
            case .beforeCooldown: return tr("Before cool-down", "Før nedjogging")
            }
        }
    }

    enum Metric: String, Codable, CaseIterable, Identifiable {
        case pace
        case elapsedTime
        case distance
        case heartRate
        case heartRateZone
        case motivation
        case hydrationReminder
        case averagePace
        case lastKilometerPace
        case personalRecord
        case speed
        case clockTime
        case date
        case stepName
        case stepRemainingTime
        case groupRemainingTime
        case workoutRemainingTime
        case estimatedFinishTime
        case routeRemainingDistance
        case estimatedRouteTime
        case remainingExercises
        case nextExercise
        case previousExerciseSummary
        case previousMainSectionSummary
        var id: String { rawValue }
        /// Sensor readings, measured pace and device-verified records do not
        /// require connectivity. When online commands are introduced, flag
        /// ONLY those commands rather than incorrectly marking local PRs.
        var requiresInternet: Bool { false }
        var category: ATHLTHCoachMetricCategory {
            switch self {
            case .heartRate, .heartRateZone: return .heartRate
            case .stepName, .stepRemainingTime, .groupRemainingTime,
                 .remainingExercises, .nextExercise, .previousExerciseSummary,
                 .previousMainSectionSummary: return .exercises
            case .motivation, .hydrationReminder: return .motivation
            case .personalRecord: return .workout
            case .routeRemainingDistance, .estimatedRouteTime: return .navigation
            default: return .workout
            }
        }
        var title: String {
            switch self {
            case .pace: return ATHLTHLocalization.choose(
                english: "Pace", norwegian: "Tempo")
            case .elapsedTime: return ATHLTHLocalization.choose(
                english: "Elapsed time", norwegian: "Medgått tid")
            case .distance: return ATHLTHLocalization.choose(
                english: "Distance", norwegian: "Distanse")
            case .heartRate: return ATHLTHLocalization.choose(
                english: "Heart rate", norwegian: "Puls")
            case .heartRateZone: return ATHLTHLocalization.choose(
                english: "Heart-rate zone", norwegian: "Pulssone")
            case .motivation: return ATHLTHLocalization.choose(
                english: "Motivation", norwegian: "Motivasjon")
            case .hydrationReminder: return ATHLTHLocalization.choose(
                english: "Hydration reminder", norwegian: "Drikkepåminnelse")
            case .averagePace: return ATHLTHLocalization.choose(english: "Overall average pace", norwegian: "Snittempo hele løpet")
            case .lastKilometerPace: return ATHLTHLocalization.choose(english: "Last-kilometre pace", norwegian: "Tempo siste kilometer")
            case .personalRecord: return ATHLTHLocalization.choose(english: "New personal record", norwegian: "Ny personlig rekord")
            case .speed: return ATHLTHLocalization.choose(english: "Speed", norwegian: "Hastighet")
            case .clockTime: return ATHLTHLocalization.choose(english: "Clock time", norwegian: "Klokkeslett")
            case .date: return ATHLTHLocalization.choose(english: "Date", norwegian: "Dato")
            case .stepName: return ATHLTHLocalization.choose(english: "Current phase", norwegian: "Gjeldende deløvelse")
            case .stepRemainingTime: return ATHLTHLocalization.choose(english: "Time left in phase", norwegian: "Tid igjen av deløvelsen")
            case .groupRemainingTime: return ATHLTHLocalization.choose(english: "Estimated time left in group", norwegian: "Estimert tid igjen av gruppen")
            case .workoutRemainingTime: return ATHLTHLocalization.choose(english: "Estimated time left in workout", norwegian: "Estimert tid igjen av økten")
            case .estimatedFinishTime: return ATHLTHLocalization.choose(english: "Estimated finish time", norwegian: "Estimert sluttid")
            case .routeRemainingDistance: return ATHLTHLocalization.choose(english: "Route distance remaining", norwegian: "Distanse igjen av ruten")
            case .estimatedRouteTime: return ATHLTHLocalization.choose(english: "Estimated route time remaining", norwegian: "Estimert tid igjen av ruten")
            case .remainingExercises: return ATHLTHLocalization.choose(english: "Remaining exercises", norwegian: "Gjenstående øvelser")
            case .nextExercise: return ATHLTHLocalization.choose(english: "Next exercise", norwegian: "Neste øvelse")
            case .previousExerciseSummary: return ATHLTHLocalization.choose(english: "Previous exercise summary", norwegian: "Sammendrag forrige øvelse")
            case .previousMainSectionSummary: return ATHLTHLocalization.choose(english: "Previous main section summary", norwegian: "Sammendrag forrige hoveddel")
            }
        }
    }

    enum Scope: String, Codable, CaseIterable, Identifiable {
        case workout, effort, group
        var id: String { rawValue }
        var title: String {
            switch self {
            case .workout: return ATHLTHLocalization.choose(english: "Whole workout", norwegian: "Hele økten")
            case .effort: return ATHLTHLocalization.choose(english: "Each effort", norwegian: "Hvert drag")
            case .group: return ATHLTHLocalization.choose(english: "Each interval group", norwegian: "Hver draggruppe")
            }
        }
    }

    var id: UUID = UUID()
    var trigger: Trigger
    var metric: Metric
    /// Metres for distance rules, seconds for time rules.
    var interval: Int
    /// Optional for compatibility with existing stored one-metric rules.
    /// A single scheduled event can read several metrics as ONE spoken cue.
    var additionalMetrics: [Metric]? = nil
    /// Optional for old saved profiles and existing Watch transfers.
    /// Disabled groups remain visible/editable but never create a spoken cue.
    var enabled: Bool? = nil
    /// Rule-effective phase selection is assembled from its Coach group when
    /// a workout starts, leaving the saved authored rule untouched.
    var allowedPhases: [ATHLTHCoachWorkoutPhase]? = nil
    var encouragementStyle: ATHLTHCoachEncouragementStyle? = nil
    var scope: Scope? = nil
    /// Optional first/last/main/non-rest matching for structured step cues.
    var eventSelection: ATHLTHCoachEventSelection? = nil
    /// An optional single-shot cue before a planned finish. Nothing is
    /// announced if the workout has no reliable remaining-duration estimate.
    var beforeEndSeconds: Int? = nil
    var customPhrase: String? = nil

    var isEnabled: Bool { enabled ?? true }

    func matchesEventSelection(_ context: ATHLTHCoachReadoutContext) -> Bool {
        let selection = eventSelection ?? .every
        guard selection != .every else { return true }
        guard let index = context.stepIndex, index >= 0 else { return false }
        switch trigger {
        case .stepStart, .stepEnd, .beforeNextStep:
            switch selection {
            case .every: return true
            case .first: return index == 0
            case .last: return index == (context.stepCount ?? 0) - 1
            case .mainOnly:
                return ["work", "steady", "main", "recovery"].contains(
                    context.stepPhase ?? ""
                )
            case .withoutRest: return context.stepPhase != "recovery"
            }
        case .recoveryStart, .recoveryEnd:
            switch selection {
            case .every, .mainOnly: return true
            case .first: return context.firstRecoveryStepIndex == index
            case .last: return context.lastRecoveryStepIndex == index
            case .withoutRest: return false
            }
        default: return true
        }
    }

    func matchesPhase(_ context: ATHLTHCoachReadoutContext) -> Bool {
        guard let allowedPhases, !allowedPhases.isEmpty else { return true }
        return allowedPhases.contains { $0.matches(stepPhase: context.stepPhase) }
    }

    var selectedMetrics: [Metric] {
        var ordered: [Metric] = [metric]
        for next in additionalMetrics ?? [] where !ordered.contains(next) {
            ordered.append(next)
        }
        return ordered
    }

    var validatedInterval: Int {
        switch trigger {
        case .distance: return min(max(interval, 100), 42_000)
        case .time: return min(max(interval, 15), 7_200)
        case .randomMotivation: return min(max(interval, 120), 900)
        case .nearFinishTime: return min(max(interval, 10), 1_800)
        case .nearFinishDistance: return min(max(interval, 25), 5_000)
        case .elevationGain: return min(max(interval, 10), 5_000)
        case .heartRateAbove, .heartRateBelow: return min(max(interval, 40), 220)
        case .paceFasterOverall, .paceFasterLastKilometer: return min(max(interval, 120), 1_800)
        case .zoneEnter, .zoneExit, .zoneBelow: return min(max(interval, 1), 5)
        case .beforeNextStep, .beforeMain, .beforeCooldown:
            return min(max(interval, 5), 60)
        default: return 1
        }
    }

    func phrase(
        distanceMeters: Double,
        elapsedSeconds: TimeInterval,
        paceSecondsPerKilometer: TimeInterval?,
        heartRateBPM: Double?,
        norwegian: Bool,
        maximumHeartRateBPM: Double? = nil,
        context: ATHLTHCoachReadoutContext = .init(),
        now: Date = .now,
        excluding excludedMetrics: Set<Metric> = []
    ) -> String? {
        if beforeEndSeconds != nil,
           let phrase = customPhrase?.trimmingCharacters(in: .whitespacesAndNewlines),
           !phrase.isEmpty {
            return phrase
        }
        let intervalValue = trigger == .distance ? distanceMeters : elapsedSeconds
        let motivationSlot = intervalValue.isFinite && intervalValue >= 0
            ? Int(min(floor(intervalValue / Double(validatedInterval)),
                      Double(Int.max / 2)))
            : 0
        let personal = customPhrase?.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = selectedMetrics.filter {
            !excludedMetrics.contains($0)
        }.compactMap { item -> String? in
            if item == .motivation, let personal, !personal.isEmpty {
                return personal
            }
            return component(
                item, distanceMeters: distanceMeters,
                elapsedSeconds: elapsedSeconds,
                paceSecondsPerKilometer: paceSecondsPerKilometer,
                heartRateBPM: heartRateBPM, norwegian: norwegian,
                maximumHeartRateBPM: maximumHeartRateBPM,
                motivationSlot: motivationSlot, context: context, now: now
            )
        }
        return parts.isEmpty ? nil : parts.joined(separator: ". ")
    }

    private func component(
        _ metric: Metric,
        distanceMeters: Double,
        elapsedSeconds: TimeInterval,
        paceSecondsPerKilometer: TimeInterval?,
        heartRateBPM: Double?,
        norwegian: Bool,
        maximumHeartRateBPM: Double?,
        motivationSlot: Int,
        context: ATHLTHCoachReadoutContext,
        now: Date
    ) -> String? {
        switch metric {
        case .pace:
            guard let pace = paceSecondsPerKilometer, pace.isFinite,
                  pace > 0, pace < 3_600 else { return nil }
            let seconds = Int(pace.rounded())
            let minutes = seconds / 60
            let remainder = seconds % 60
            return norwegian
                ? "Tempo \(minutes) minutter \(remainder) sekunder per kilometer"
                : "Pace \(minutes) minutes \(remainder) seconds per kilometer"
        case .elapsedTime:
            guard elapsedSeconds.isFinite, elapsedSeconds >= 0 else { return nil }
            let seconds = Int(elapsedSeconds.rounded(.down))
            let minutes = seconds / 60
            let remainder = seconds % 60
            return norwegian
                ? "Tid \(minutes) minutter \(remainder) sekunder"
                : "Time \(minutes) minutes \(remainder) seconds"
        case .distance:
            guard distanceMeters.isFinite, distanceMeters >= 0 else { return nil }
            return norwegian
                ? String(format: "Distanse %.2f kilometer", distanceMeters / 1_000)
                : String(format: "Distance %.2f kilometers", distanceMeters / 1_000)
        case .heartRate:
            guard let heartRateBPM, heartRateBPM.isFinite,
                  (30...230).contains(heartRateBPM) else { return nil }
            return norwegian ? "Puls \(Int(heartRateBPM.rounded()))"
                : "Heart rate \(Int(heartRateBPM.rounded()))"
        case .heartRateZone:
            guard let zone = ATHLTHHeartRateZones.measuredZone(
                heartRateBPM: heartRateBPM, maximumBPM: maximumHeartRateBPM
            ) else { return nil }
            return norwegian ? "Pulssone \(zone)" : "Heart-rate zone \(zone)"
        case .lastKilometerPace:
            guard let pace = context.lastKilometerPaceSecondsPerKilometer,
                  pace.isFinite, (120...1_800).contains(pace) else { return nil }
            let seconds = Int(pace.rounded())
            return norwegian
                ? String(format: "Tempo siste kilometer %d:%02d minutter per kilometer", seconds / 60, seconds % 60)
                : String(format: "Last kilometre pace %d:%02d minutes per kilometre", seconds / 60, seconds % 60)
        case .personalRecord:
            let phrase = norwegian ? context.verifiedPersonalRecordNorwegian : context.verifiedPersonalRecordEnglish
            return phrase?.isEmpty == false ? phrase : nil
        case .averagePace:
            guard distanceMeters >= 100 else { return nil }
            return component(.pace, distanceMeters: distanceMeters, elapsedSeconds: elapsedSeconds,
                             paceSecondsPerKilometer: elapsedSeconds * 1000 / distanceMeters,
                             heartRateBPM: nil, norwegian: norwegian, maximumHeartRateBPM: nil,
                             motivationSlot: motivationSlot, context: context, now: now)
                .map { (norwegian ? "Gjennomsnitt. " : "Average. ") + $0 }
        case .speed:
            guard let pace = paceSecondsPerKilometer, pace.isFinite, (30...3_600).contains(pace) else { return nil }
            let speed = (3600 / pace).formatted(.number.precision(.fractionLength(1)))
            return norwegian ? "Hastighet \(speed) kilometer i timen" : "Speed \(speed) kilometers per hour"
        case .clockTime:
            let time = now.formatted(.dateTime.hour().minute().locale(Locale(identifier: norwegian ? "nb_NO" : "en_US")))
            return norwegian ? "Klokken er \(time)" : "The time is \(time)"
        case .date:
            return now.formatted(.dateTime.weekday(.wide).day().month(.wide)
                .locale(Locale(identifier: norwegian ? "nb_NO" : "en_US")))
        case .stepName:
            return context.stepName
        case .stepRemainingTime:
            return context.stepRemainingSeconds.flatMap {
                Self.remaining($0, label: norwegian ? "Igjen av deløvelsen" : "Time left in this phase", norwegian: norwegian)
            }
        case .groupRemainingTime:
            return context.groupRemainingSeconds.flatMap {
                Self.remaining($0, label: norwegian ? "Estimert igjen av gruppen" : "Estimated time left in group", norwegian: norwegian)
            }
        case .workoutRemainingTime:
            return context.workoutRemainingSeconds.flatMap {
                Self.remaining($0, label: norwegian ? "Estimert igjen av økten" : "Estimated time left in workout", norwegian: norwegian)
            }
        case .estimatedFinishTime:
            guard let seconds = context.workoutRemainingSeconds, seconds.isFinite,
                  (0...604_800).contains(seconds) else { return nil }
            let time = now.addingTimeInterval(seconds).formatted(.dateTime.hour().minute()
                .locale(Locale(identifier: norwegian ? "nb_NO" : "en_US")))
            return norwegian ? "Estimert ferdig klokken \(time)" : "Estimated finish at \(time)"
        case .routeRemainingDistance:
            guard let meters = context.routeRemainingMeters, meters.isFinite, meters >= 0 else { return nil }
            let km = (meters / 1000).formatted(.number.precision(.fractionLength(2)))
            return norwegian ? "\(km) kilometer igjen av ruten" : "\(km) kilometers left on route"
        case .estimatedRouteTime:
            guard let meters = context.routeRemainingMeters, let pace = paceSecondsPerKilometer,
                  pace.isFinite, (30...3_600).contains(pace) else { return nil }
            return Self.remaining(meters * pace / 1000,
                                  label: norwegian ? "Estimert igjen av ruten" : "Estimated route time left",
                                  norwegian: norwegian)
        case .remainingExercises:
            guard let count = context.remainingExerciseCount else { return nil }
            return norwegian
                ? (count == 1 ? "1 øvelse gjenstår" : "\(count) øvelser gjenstår")
                : (count == 1 ? "1 exercise remaining" : "\(count) exercises remaining")
        case .nextExercise:
            guard let name = context.nextExerciseName, !name.isEmpty else { return nil }
            let detail = context.nextExerciseDetails.map { ". " + $0 } ?? ""
            return norwegian ? "Neste øvelse: \(name)\(detail)" : "Next exercise: \(name)\(detail)"
        case .previousExerciseSummary:
            guard let name = context.previousExerciseName else { return nil }
            guard let seconds = context.previousExerciseSeconds,
                  seconds.isFinite, seconds >= 0 else {
                return context.previousExerciseCompleted == true
                    ? (norwegian ? "Forrige øvelse \(name) er fullført"
                                 : "Previous exercise \(name) completed")
                    : nil
            }
            let minutes = Int(seconds.rounded()) / 60
            let remainder = Int(seconds.rounded()) % 60
            let distance = context.previousExerciseDistanceMeters ?? 0
            let portion = distance.isFinite && distance >= 1
                ? (norwegian ? String(format: ", %.0f meter", distance) : String(format: ", %.0f meters", distance))
                : ""
            return norwegian
                ? "Forrige øvelse \(name): \(minutes) minutter og \(remainder) sekunder\(portion)"
                : "Previous exercise \(name): \(minutes) minutes and \(remainder) seconds\(portion)"
        case .previousMainSectionSummary:
            guard let count = context.previousMainSectionExerciseCount else { return nil }
            guard let seconds = context.previousMainSectionSeconds,
                  seconds.isFinite, seconds >= 0 else {
                return norwegian ? "Forrige hoveddel: \(count) øvelser fullført"
                    : "Previous section: \(count) exercises completed"
            }
            let minutes = Int(seconds.rounded()) / 60
            let remainder = Int(seconds.rounded()) % 60
            let distance = context.previousMainSectionDistanceMeters ?? 0
            let portion = distance.isFinite && distance >= 1
                ? (norwegian ? String(format: ", %.0f meter", distance) : String(format: ", %.0f meters", distance))
                : ""
            return norwegian
                ? "Forrige hoveddel: \(count) øvelser, \(minutes) minutter og \(remainder) sekunder\(portion)"
                : "Previous main section: \(count) exercises, \(minutes) minutes and \(remainder) seconds\(portion)"
        case .hydrationReminder:
            // A short, optional reminder; never imply a fixed drinking dose
            // or pause the running workout/interval timers.
            return norwegian
                ? "Husk å ta en slurk vann når det passer."
                : "Remember to take a sip of water when convenient."
        case .motivation:
            // Context-specific motivation for goals, rather than a generic
            // encouragement which does not explain what was achieved.
            if trigger == .nearFinishTime {
                return norwegian ? "Du er snart ved tidsmålet. Hold flyten!"
                    : "You're close to your time goal. Keep it going!"
            }
            if trigger == .nearFinishDistance {
                return norwegian ? "Det er kort vei igjen til målet. Fortsett!"
                    : "The finish is close. Keep going!"
            }
            if trigger == .elevationGain {
                return norwegian ? "Flott klatring! Du har passert et høydemetermål."
                    : "Great climbing! You've reached an elevation milestone."
            }
            if trigger == .uphillDetected {
                return norwegian ? "Motbakke foran deg. Finn din rytme!"
                    : "You're climbing. Find your rhythm!"
            }
            if trigger == .plannedZoneOutside {
                return norwegian ? "Pulsen er utenfor øktens målsone. Finn tilbake til riktig intensitet."
                    : "Heart rate is outside your workout target zone. Find your way back."
            }
            if trigger == .plannedZoneBelow || trigger == .zoneBelow {
                return norwegian ? "Pulsen ligger under valgt sone. Juster innsatsen om det passer."
                    : "Heart rate is below your chosen zone. Adjust if appropriate."
            }
            return ATHLTHAudioCoachScheduledMotivation.phrase(
                slot: motivationSlot,
                style: encouragementStyle ?? .encouragement,
                norwegian: norwegian
            )
        }
    }

    private static func remaining(_ value: Double, label: String, norwegian: Bool) -> String? {
        guard value.isFinite, (0...604_800).contains(value) else { return nil }
        let seconds = Int(value.rounded())
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let tail = seconds % 60
        let duration = norwegian ? "\(minutes) minutter og \(tail) sekunder"
            : "\(minutes) minutes and \(tail) seconds"
        let prefix = hours > 0 ? (norwegian ? "\(hours) timer, " : "\(hours) hours, ") : ""
        return "\(label): \(prefix)\(duration)"
    }
}

/// Deterministic, offline motivational cues. A rule generates one short phrase
/// per distance/time milestone, without waiting for a network coach service.
enum ATHLTHAudioCoachScheduledMotivation {
    static func phrase(
        slot: Int,
        style: ATHLTHCoachEncouragementStyle,
        norwegian: Bool
    ) -> String {
        let phrases: [String]
        switch (style, norwegian) {
        case (.praise, true):
            phrases = ["Bra jobbet! Du holder det gående.", "Sterk innsats. Fortsett slik!",
                       "Dette gjør du bra. Finn din rytme."]
        case (.praise, false):
            phrases = ["Great work! Keep going.", "Strong effort. Keep it up!",
                       "You're doing well. Find your rhythm."]
        case (.push, true):
            phrases = ["Hold fokus, du har mer å gi!", "Finn rytmen og jobb videre!",
                       "Fortsett å presse kontrollert, du klarer dette!"]
        case (.push, false):
            phrases = ["Stay focused, you've got more to give!", "Find your rhythm and keep going!",
                       "Keep pushing with control. You've got this!"]
        case (.encouragement, true):
            phrases = ["Du er i gang. Ett steg om gangen!", "Hold flyten, du gjør en god jobb!",
                       "Fortsett i ditt tempo. Du har dette!"]
        case (.encouragement, false):
            phrases = ["You're moving. One step at a time!", "Keep the flow, you're doing great!",
                       "Stay with your pace. You've got this!"]
        }
        return phrases[max(slot, 0) % phrases.count]
    }
}

/// A spoken rule together with the metrics it covers. Used by both voice
/// owners to combine scheduled/default updates without repeating a metric.
struct ATHLTHAudioCoachDueAnnouncement {
    let text: String
    let metrics: Set<ATHLTHAudioCoachRule.Metric>
    /// Deterministic milestone identity, stable across Watch and phone.
    let milestoneKey: String
}

/// Keep simultaneous ordinary announcements short and deterministic.
/// Critical navigation, target alerts and countdowns use higher-priority
/// voice events and are handled outside this routine message composer.
enum ATHLTHCoachRoutineComposition {
    static let maximumParts = 3

    static func compose(
        regular: String,
        customDue: [ATHLTHAudioCoachDueAnnouncement]
    ) -> String {
        let ranked = customDue.enumerated().sorted { lhs, rhs in
            let first = rank(lhs.element.metrics)
            let second = rank(rhs.element.metrics)
            return first == second ? lhs.offset < rhs.offset : first > second
        }
        var choices: [String] = []
        for candidate in ranked {
            let phrase = candidate.element.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !phrase.isEmpty, !choices.contains(phrase) else { continue }
            choices.append(phrase)
            if choices.count == maximumParts { break }
        }
        if choices.count < maximumParts,
           !regular.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            choices.append(regular)
        }
        // Once a milestone is consumed, omitted low-priority status is NOT
        // queued later while the athlete is already at a new exercise.
        return choices.joined(separator: ". ")
    }

    private static func rank(_ metrics: Set<ATHLTHAudioCoachRule.Metric>) -> Int {
        if !metrics.isDisjoint(with: [
            .heartRateZone, .nextExercise, .previousMainSectionSummary,
            .previousExerciseSummary, .remainingExercises
        ]) { return 3 }
        if !metrics.isDisjoint(with: [.heartRate, .stepRemainingTime, .groupRemainingTime]) {
            return 2
        }
        if !metrics.isDisjoint(with: [.motivation, .hydrationReminder]) { return 0 }
        return 1
    }
}

/// Evaluates each user's distance/time rule independently. The slot journal
/// prevents repeats when workout snapshots arrive more than once per second.
enum ATHLTHAudioCoachRuleDelivery {
    static func initialSlots(
        rules: [ATHLTHAudioCoachRule],
        distanceMeters: Double,
        elapsedSeconds: TimeInterval
    ) -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        for rule in rules where (rule.scope ?? .workout) == .workout {
            // One-shot finish cues use remaining time, not elapsed-time slots.
            // A nonzero elapsed slot would otherwise suppress the first cue.
            result[rule.id] = rule.trigger == .workoutStart && elapsedSeconds > 3
                ? 1
                : rule.trigger == .randomMotivation
                    ? randomMotivationSlot(for: rule, elapsedSeconds: elapsedSeconds)
                    : rule.trigger == .elevationGain
                        ? 0  // Elevation is a separate measured sensor, not distance.
                        : rule.trigger.isPeriodic && rule.beforeEndSeconds == nil
                            ? slot(
                                for: rule,
                                distanceMeters: distanceMeters,
                                elapsedSeconds: elapsedSeconds
                            ) : 0
        }
        return result
    }

    static func dueMessages(
        rules: [ATHLTHAudioCoachRule],
        distanceMeters: Double,
        elapsedSeconds: TimeInterval,
        paceSecondsPerKilometer: TimeInterval?,
        heartRateBPM: Double?,
        norwegian: Bool,
        maximumHeartRateBPM: Double? = nil,
        context: ATHLTHCoachReadoutContext = .init(),
        lastSlots: inout [UUID: Int]
    ) -> [String] {
        dueAnnouncements(
            rules: rules,
            distanceMeters: distanceMeters,
            elapsedSeconds: elapsedSeconds,
            paceSecondsPerKilometer: paceSecondsPerKilometer,
            heartRateBPM: heartRateBPM,
            norwegian: norwegian,
            maximumHeartRateBPM: maximumHeartRateBPM,
            context: context,
            lastSlots: &lastSlots
        ).map(\.text)
    }

    static func dueAnnouncements(
        rules: [ATHLTHAudioCoachRule],
        distanceMeters: Double,
        elapsedSeconds: TimeInterval,
        paceSecondsPerKilometer: TimeInterval?,
        heartRateBPM: Double?,
        norwegian: Bool,
        maximumHeartRateBPM: Double? = nil,
        context: ATHLTHCoachReadoutContext = .init(),
        lastSlots: inout [UUID: Int]
    ) -> [ATHLTHAudioCoachDueAnnouncement] {
        var messages: [ATHLTHAudioCoachDueAnnouncement] = []
        var spokenByScope: [ATHLTHAudioCoachRule.Scope: Set<ATHLTHAudioCoachRule.Metric>] = [:]
        for rule in rules.prefix(20) {
            let scope = rule.scope ?? .workout
            let distance: Double
            let elapsed: Double
            let segment: Int?
            switch scope {
            case .workout:
                distance = distanceMeters
                elapsed = elapsedSeconds
                segment = nil
            case .effort:
                guard context.isEffort, let index = context.stepIndex else { continue }
                distance = context.stepDistanceMeters
                elapsed = context.stepElapsedSeconds
                segment = index
            case .group:
                guard let index = context.groupStartIndex else { continue }
                distance = context.groupDistanceMeters
                elapsed = context.groupElapsedSeconds
                segment = index
            }
            let milestone: Int
            var alreadyConsumed = false

            if rule.trigger.isHeartRateCondition || rule.trigger.isPaceCondition ||
               rule.trigger == .uphillDetected {
                // Each threshold crossing is one event, with a new delivery
                // identity on later re-entry. Invalid HR samples do not reset
                // the condition or cause spurious zone-exit announcements.
                let state: Bool?
                if rule.trigger == .uphillDetected {
                    state = context.isUphill
                } else if rule.trigger.isPaceCondition {
                    state = paceCondition(
                        rule, context: context,
                        measuredPace: paceSecondsPerKilometer,
                        previousActive: (lastSlots[rule.id] ?? 0) % 2 == 1
                    )
                } else {
                    state = heartRateCondition(
                        rule, bpm: heartRateBPM, maximumBPM: maximumHeartRateBPM,
                        context: context,
                        previousActive: (lastSlots[rule.id] ?? 0) % 2 == 1
                    )
                }
                guard let active = state else { continue }
                let previousState = lastSlots[rule.id] ?? 0
                let wasActive = previousState % 2 == 1
                guard active != wasActive else { continue }
                let updatedState = previousState + 1
                lastSlots[rule.id] = updatedState
                alreadyConsumed = true
                let shouldAnnounce = rule.trigger == .zoneExit
                    ? (wasActive && !active) : (!wasActive && active)
                guard shouldAnnounce else { continue }
                milestone = (updatedState + 1) / 2
            } else if rule.trigger == .randomMotivation {
                milestone = randomMotivationSlot(
                    for: rule, elapsedSeconds: elapsed
                )
            } else if rule.trigger == .nearFinishTime {
                guard let remaining = context.workoutRemainingSeconds,
                      remaining.isFinite, remaining >= 0 else { continue }
                milestone = remaining <= Double(rule.validatedInterval) ? 1 : 0
            } else if rule.trigger == .nearFinishDistance {
                // Only an explicit route or prescribed distance can make this
                // statement. Never infer a finish from an open-ended run.
                guard let remaining = context.workoutRemainingMeters ??
                        context.routeRemainingMeters,
                      remaining.isFinite, remaining >= 0 else { continue }
                milestone = remaining <= Double(rule.validatedInterval) ? 1 : 0
            } else if rule.trigger == .elevationGain {
                guard let gain = context.elevationGainMeters,
                      gain.isFinite, gain >= 0 else { continue }
                milestone = Int(min(
                    floor(gain / Double(rule.validatedInterval)),
                    Double(Int.max / 2)
                ))
            } else if rule.trigger == .personalRecordConfirmed {
                guard context.verifiedPersonalRecordEnglish != nil ||
                      context.verifiedPersonalRecordNorwegian != nil else { continue }
                milestone = 1
            } else if rule.trigger.needsStructuredStep ||
                      rule.trigger == .workoutStart {
                guard let occurrence = eventOccurrence(
                    rule, context: context, elapsedSeconds: elapsedSeconds
                ) else { continue }
                milestone = occurrence
            } else if let beforeEnd = rule.beforeEndSeconds {
                guard let remaining = context.workoutRemainingSeconds,
                      remaining.isFinite, remaining >= 0 else { continue }
                milestone = remaining <= Double(max(1, beforeEnd)) ? 1 : 0
            } else {
                milestone = slot(for: rule, distanceMeters: distance, elapsedSeconds: elapsed)
            }
            guard milestone > 0 else { continue }
            let current = segment.map {
                ($0 + 1) * 100_000 + min(milestone, 99_999)
            } ?? milestone
            let previous = lastSlots[rule.id] ?? 0
            if !alreadyConsumed {
                guard current > previous else { continue }
            }
            // Consume the crossed milestone even if a sensor value is missing.
            // It must not be announced much later after that value recovers.
            if !alreadyConsumed {
                lastSlots[rule.id] = current
            }
            guard rule.isEnabled,
                  rule.matchesPhase(context),
                  rule.matchesEventSelection(context) else { continue }
            // Simultaneous rules are composed into one speech event. A
            // metric already included by another rule is not repeated.
            let available = rule.selectedMetrics.filter { metric in
                switch metric {
                case .heartRate: return heartRateBPM != nil
                case .heartRateZone:
                    return ATHLTHHeartRateZones.measuredZone(
                        heartRateBPM: heartRateBPM,
                        maximumBPM: maximumHeartRateBPM
                    ) != nil
                case .pace: return paceSecondsPerKilometer != nil
                case .lastKilometerPace:
                    return context.lastKilometerPaceSecondsPerKilometer != nil
                case .personalRecord:
                    return context.verifiedPersonalRecordEnglish != nil ||
                           context.verifiedPersonalRecordNorwegian != nil
                default: return true
                }
            }
            let effective = available.filter { !(spokenByScope[scope] ?? []).contains($0) }
            guard !effective.isEmpty,
                  let message = rule.phrase(
                    distanceMeters: distance,
                    elapsedSeconds: elapsed,
                    paceSecondsPerKilometer: paceSecondsPerKilometer,
                    heartRateBPM: heartRateBPM,
                    norwegian: norwegian,
                    maximumHeartRateBPM: maximumHeartRateBPM,
                    context: context,
                    excluding: Set(rule.selectedMetrics).subtracting(effective)
                  ) else { continue }
            let covered = Set(effective)
            messages.append(ATHLTHAudioCoachDueAnnouncement(
                text: message,
                metrics: scope == .workout ? covered : covered.subtracting([.distance, .elapsedTime, .averagePace]),
                milestoneKey: rule.id.uuidString + ":" +
                    String(alreadyConsumed ? milestone : current)
            ))
            spokenByScope[scope, default: []].formUnion(covered)
        }
        return messages
    }

    /// Event receipts must identify the scheduled milestone, not the
    /// exact live distance/time when speech starts. Watch/iPhone snapshots
    /// arrive at different moments and otherwise produce different keys.
    /// A small deterministic digest also stays beneath receipt length limits
    /// when several custom rules happen together.
    static func stableDeliveryKey(
        standardMilestones: [String],
        customAnnouncements: [ATHLTHAudioCoachDueAnnouncement]
    ) -> String {
        let pieces = (
            standardMilestones.map { "s:" + $0 } +
            customAnnouncements.map { "c:" + $0.milestoneKey }
        ).sorted()
        var digest: UInt64 = 0xcbf29ce484222325
        for byte in pieces.joined(separator: "|").utf8 {
            digest = (digest ^ UInt64(byte)) &* 0x100000001b3
        }
        return "audio:" + String(digest, radix: 16)
    }

    /// Faster means fewer seconds/km. Ten seconds/km of hysteresis lets the
    /// athlete cross back before the same alert can fire again.
    /// A missing/unreliable sensor never changes the latched state.
    private static func paceCondition(
        _ rule: ATHLTHAudioCoachRule,
        context: ATHLTHCoachReadoutContext,
        measuredPace: Double?,
        previousActive: Bool
    ) -> Bool? {
        let pace: Double?
        let threshold: Double?
        let slowerThan: Bool
        switch rule.trigger {
        case .paceFasterOverall:
            pace = context.overallPaceSecondsPerKilometer
            threshold = Double(rule.validatedInterval)
            slowerThan = false
        case .paceFasterLastKilometer:
            pace = context.lastKilometerPaceSecondsPerKilometer
            threshold = Double(rule.validatedInterval)
            slowerThan = false
        case .paceFasterThanTarget, .paceSlowerThanTarget:
            pace = measuredPace
            // A prescribed 4:40–5:00 range warns faster than 4:40 or
            // slower than 5:00, never against the wrong side of the range.
            threshold = rule.trigger == .paceSlowerThanTarget
                ? (context.targetSlowestPaceSecondsPerKilometer ??
                   context.targetPaceSecondsPerKilometer)
                : (context.targetPaceSecondsPerKilometer ??
                   context.targetSlowestPaceSecondsPerKilometer)
            slowerThan = rule.trigger == .paceSlowerThanTarget
        default:
            return nil
        }
        guard let pace, pace.isFinite, (120...1_800).contains(pace),
              let threshold, threshold.isFinite,
              (120...1_800).contains(threshold) else { return nil }
        if slowerThan {
            return previousActive ? pace > threshold - 10 : pace > threshold
        }
        return previousActive ? pace < threshold + 10 : pace < threshold
    }

    private static func heartRateCondition(
        _ rule: ATHLTHAudioCoachRule,
        bpm: Double?,
        maximumBPM: Double?,
        context: ATHLTHCoachReadoutContext,
        previousActive: Bool
    ) -> Bool? {
        guard let bpm, bpm.isFinite, (35...250).contains(bpm) else {
            return nil
        }
        switch rule.trigger {
        case .heartRateAbove:
            let threshold = Double(rule.validatedInterval)
            return bpm >= (previousActive ? threshold - 3 : threshold)
        case .heartRateBelow:
            let threshold = Double(rule.validatedInterval)
            return bpm <= (previousActive ? threshold + 3 : threshold)
        case .zoneEnter, .zoneExit, .zoneBelow, .plannedZoneBelow,
             .plannedZoneOutside:
            guard let zone = ATHLTHHeartRateZones.measuredZone(
                heartRateBPM: bpm, maximumBPM: maximumBPM
            ) else { return nil }
            if rule.trigger == .plannedZoneBelow ||
               rule.trigger == .plannedZoneOutside {
                guard let target = context.plannedHeartRateZone,
                      (1...5).contains(target) else { return nil }
                return rule.trigger == .plannedZoneBelow
                    ? zone < target : zone != target
            }
            if rule.trigger == .zoneBelow {
                return zone < rule.validatedInterval
            }
            return zone == rule.validatedInterval
        default: return nil
        }
    }

    /// Deterministic per-rule jitter. Each window fires at most once.
    /// No timer, extra thread, or network call; the existing cue ledger and
    /// routine-coach priority queue still suppress overlapping speech.
    private static func randomMotivationSlot(
        for rule: ATHLTHAudioCoachRule,
        elapsedSeconds: Double
    ) -> Int {
        guard elapsedSeconds.isFinite, elapsedSeconds >= 0 else { return 0 }
        let seconds = Double(rule.validatedInterval)
        let window = Int(min(floor(elapsedSeconds / seconds), 10_000_000))
        guard window >= 1 else { return 0 }
        // Stable jitter within each window (up to 50% into the window).
        let seed = rule.id.uuidString.utf8.reduce(UInt64(14_695), {
            ($0 ^ UInt64($1)) &* 1_099_511_628_211
        })
        let hash = (seed ^ UInt64(window) &* 2_654_435_761) &* 2_246_822_519
        let offset = Double(hash % 501) / 1_000 * seconds
        return elapsedSeconds >= Double(window) * seconds + offset
            ? window : window - 1
    }

    private static func eventOccurrence(
        _ rule: ATHLTHAudioCoachRule,
        context: ATHLTHCoachReadoutContext,
        elapsedSeconds: TimeInterval
    ) -> Int? {
        if rule.trigger == .workoutStart {
            return (0...3).contains(elapsedSeconds) ? 1 : nil
        }
        guard let index = context.stepIndex, index >= 0,
              (context.stepCount ?? 0) > index else { return nil }

        let phase = context.stepPhase
        let previous = context.previousStepPhase
        let next = context.nextStepPhase
        let nearStart = context.stepElapsedSeconds <= 4
        let remaining = context.stepRemainingSeconds
        let nearEnd = remaining.map { $0.isFinite && $0 >= 0 && $0 <= 2 } == true
        let beforeBoundary = remaining.map {
            $0.isFinite && $0 >= 0 && $0 <= Double(rule.validatedInterval)
        } == true

        // Index of the step that caused the event (1-based). All event
        // milestones are monotonic even when the plan contains many intervals.
        switch rule.trigger {
        case .stepStart:
            return nearStart ? index + 1 : nil
        case .stepEnd:
            if nearEnd { return index + 1 }
            return index > 0 && nearStart ? index : nil
        case .effortStart:
            return phase == "work" && nearStart ? index + 1 : nil
        case .effortEnd:
            if phase == "work" && nearEnd { return index + 1 }
            return previous == "work" && nearStart ? index : nil
        case .recoveryStart:
            return phase == "recovery" && nearStart ? index + 1 : nil
        case .recoveryEnd:
            if phase == "recovery" && nearEnd { return index + 1 }
            return previous == "recovery" && nearStart ? index : nil
        case .activeRecoveryStart:
            return context.isActiveRecovery == true && nearStart ? index + 1 : nil
        case .activeRecoveryEnd:
            if context.isActiveRecovery == true && nearEnd { return index + 1 }
            return context.previousWasActiveRecovery == true && nearStart ? index : nil
        case .warmupStart:
            return phase == "warmup" && nearStart && previous != "warmup"
                ? index + 1 : nil
        case .warmupEnd:
            if phase == "warmup" && nearEnd { return index + 1 }
            return previous == "warmup" && phase != "warmup" && nearStart
                ? index : nil
        case .mainStart:
            return (phase == "work" || phase == "recovery") && nearStart &&
                (index == 0 || previous == "warmup") ? index + 1 : nil
        case .mainEnd:
            if (phase == "work" || phase == "recovery") &&
               next == "cooldown" && nearEnd { return index + 1 }
            return phase == "cooldown" && nearStart &&
                (previous == "work" || previous == "recovery") ? index : nil
        case .cooldownStart:
            return phase == "cooldown" && nearStart && previous != "cooldown"
                ? index + 1 : nil
        case .cooldownEnd:
            return phase == "cooldown" &&
                index == (context.stepCount ?? 0) - 1 && nearEnd ? index + 1 : nil
        case .beforeNextStep:
            return context.hasNextStep == true && beforeBoundary ? index + 1 : nil
        case .beforeMain:
            return phase == "warmup" &&
                (next == "work" || next == "recovery") &&
                beforeBoundary ? index + 1 : nil
        case .beforeCooldown:
            return (phase == "work" || phase == "recovery") &&
                next == "cooldown" && beforeBoundary ? index + 1 : nil
        default: return nil
        }
    }

    private static func slot(
        for rule: ATHLTHAudioCoachRule,
        distanceMeters: Double,
        elapsedSeconds: TimeInterval
    ) -> Int {
        guard rule.trigger.isPeriodic else { return 0 }
        let value = rule.trigger == .distance ? distanceMeters : elapsedSeconds
        guard value.isFinite, value >= 0 else { return 0 }
        return Int(min(
            floor(value / Double(rule.validatedInterval)),
            Double(Int.max / 2)
        ))
    }
}

/// Athlete-named, ordered presentation groups. A group does not change the
/// scheduling model: every linked rule stays owned by the existing Watch and
/// iPhone voice engine. Optional groups in the transfer payload preserve older
/// saved workout and profile decoding.
struct ATHLTHAudioCoachGroup: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var ruleIDs: [UUID] = []
    /// Existing smart/structured Audio Coach options belonging to this group.
    var optionIDs: [String] = []
    /// One shared trigger for commands added to this group. Optional to
    /// preserve existing profiles and Watch transfers that predate v2.2.2.
    var trigger: ATHLTHAudioCoachRule.Trigger? = nil
    var interval: Int? = nil
    /// Nil for existing saved templates and older Watch payloads (enabled).
    var enabled: Bool? = nil
    /// Nil means all workout phases (legacy behavior). Empty also means all.
    var phases: [ATHLTHCoachWorkoutPhase]? = nil
    var eventSelection: ATHLTHCoachEventSelection? = nil

    var isEnabled: Bool { enabled ?? true }
}

/// Disabled groups remain editable, but their linked rules never speak.
extension WatchAudioCoachConfiguration {
    /// Runtime-only view of a saved setup. Suppress built-in options owned
    /// by a disabled group without mutating the authored configuration.
    /// This keeps exact text, cadence, custom phrases and music settings
    /// available when the athlete re-enables the group.
    var deliveryConfiguration: WatchAudioCoachConfiguration {
        let mutedOptions = Set((coachGroups ?? [])
            .filter { !$0.isEnabled }
            .flatMap(\.optionIDs))
        guard !mutedOptions.isEmpty else { return self }
        var copy = self
        if mutedOptions.contains("distanceUpdates") { copy.distanceIntervalMeters = nil }
        if mutedOptions.contains("timedUpdates") { copy.timeIntervalSeconds = nil }
        if mutedOptions.contains("distance") { copy.announceDistance = false }
        if mutedOptions.contains("elapsedTime") { copy.announceElapsedTime = false }
        if mutedOptions.contains("averagePace") { copy.announceAveragePace = false }
        if mutedOptions.contains("clockTime") { copy.announceClockTime = false }
        if mutedOptions.contains("heartRate") { copy.announceHeartRate = false }
        if mutedOptions.contains("routeRemaining") { copy.announceRemainingRouteDistance = false }
        if mutedOptions.contains("routeETA") { copy.announceEstimatedRemainingRouteTime = false }
        if mutedOptions.contains("currentStep") { copy.announceCurrentWorkoutStep = false }
        if mutedOptions.contains("remainingStepTime") { copy.announceRemainingStepTime = false }
        if mutedOptions.contains("remainingStepDistance") { copy.announceRemainingStepDistance = false }
        if mutedOptions.contains("workoutStart") { copy.announceWorkoutStart = false }
        if mutedOptions.contains("pauseResume") { copy.announcePauseResume = false }
        if mutedOptions.contains("workoutFinish") { copy.announceWorkoutComplete = false }
        var smart = copy.smartPrompts
        if mutedOptions.contains("currentZone") {
            smart?.announceCurrentHeartRateZone = false
            smart?.measuredZoneAnnouncementIntervalSeconds = nil
        }
        if mutedOptions.contains("targetZoneCoach") {
            smart?.targetZoneVoiceAlertsEnabled = false
            smart?.preferredHeartRateZone = nil
        }
        if mutedOptions.contains("motivation") { smart?.motivationEnabled = false }
        if mutedOptions.contains("contextual") { smart?.contextualFeedbackEnabled = false }
        if mutedOptions.contains("adaptiveMotivation") { smart?.coachingMode = .automatic }
        if mutedOptions.contains("randomEncouragement") { smart?.randomEncouragementEnabled = false }
        if mutedOptions.contains("customPhrases") { smart?.customEncouragements = [] }
        if mutedOptions.contains("landmarks") { smart?.landmarks = [] }
        if mutedOptions.contains("scopedCountdowns") { smart?.boundaryCountdownRules = nil }
        if mutedOptions.contains("intervalRecoveryCountdown") {
            smart?.intervalCountdownToRecoverySeconds = nil
            smart?.intervalCountdownFromRecoverySeconds = nil
            copy.intervalCountdownToRecoverySeconds = nil
            copy.intervalCountdownFromRecoverySeconds = nil
        }
        copy.smartPrompts = smart
        return copy
    }

    var activeCustomRules: [ATHLTHAudioCoachRule] {
        let groups = coachGroups ?? []
        let muted = Set(groups.filter { !$0.isEnabled }.flatMap(\.ruleIDs))
        return (customRules ?? []).compactMap { authored -> ATHLTHAudioCoachRule? in
            guard authored.isEnabled && !muted.contains(authored.id) else { return nil }
            var effective = authored
            if let group = groups.first(where: { $0.ruleIDs.contains(authored.id) }) {
                effective.allowedPhases = group.phases
                effective.eventSelection = group.eventSelection
            }
            return effective
        }
    }
}

/// Deterministic sample data for one group's test playback. Never reads
/// personal HealthKit samples, and cannot claim to be an actual workout recap.
enum ATHLTHAudioCoachGroupPreview {
    static func text(
        group: ATHLTHAudioCoachGroup,
        rules: [ATHLTHAudioCoachRule],
        norwegian: Bool
    ) -> String {
        var context = ATHLTHCoachReadoutContext()
        context.stepName = norwegian ? "Intervall 2" : "Interval 2"
        context.stepIndex = 1
        context.stepCount = 4
        context.stepPhase = "work"
        context.stepElapsedSeconds = 95
        context.stepRemainingSeconds = 25
        context.groupRemainingSeconds = 180
        context.workoutRemainingSeconds = 900
        context.routeRemainingMeters = 2100
        context.overallPaceSecondsPerKilometer = 330
        context.lastKilometerPaceSecondsPerKilometer = 285
        context.targetPaceSecondsPerKilometer = 300
        context.verifiedPersonalRecordEnglish = "New verified personal best at 5 kilometres"
        context.verifiedPersonalRecordNorwegian = "Ny bekreftet personlig rekord på 5 kilometer"
        context.remainingExerciseCount = 2
        context.nextExerciseName = norwegian ? "Knebøy" : "Squats"
        context.previousExerciseName = norwegian ? "Utfall" : "Lunges"
        context.previousExerciseSeconds = 120
        context.previousExerciseDistanceMeters = 400
        context.previousMainSectionExerciseCount = 3
        context.previousMainSectionSeconds = 420
        context.previousMainSectionDistanceMeters = 1300
        let groupRules = group.ruleIDs.compactMap { id in
            rules.first(where: { $0.id == id })
        }
        let messages = groupRules.compactMap { rule in
            rule.phrase(
                distanceMeters: 2_000,
                elapsedSeconds: 750,
                paceSecondsPerKilometer: 330,
                heartRateBPM: 145,
                norwegian: norwegian,
                maximumHeartRateBPM: 190,
                context: context
            )
        }
        // Standard/built-in voice options can also belong to a named
        // Coach group. Preview those as sample readouts instead of playing
        // a generic sentence that hides the group's actual contents.
        var allMessages = messages
        for raw in group.optionIDs {
            let phrase: String?
            switch raw {
            case "distanceUpdates", "distance":
                phrase = norwegian ? "Distanse 2 kilometer" : "Distance 2 kilometers"
            case "timedUpdates", "elapsedTime":
                phrase = norwegian ? "Tid 12 minutter" : "Time 12 minutes"
            case "averagePace":
                phrase = norwegian ? "Gjennomsnittstempo 5 minutter og 30 sekunder per kilometer"
                                   : "Average pace 5 minutes 30 seconds per kilometer"
            case "heartRate":
                phrase = norwegian ? "Puls 145" : "Heart rate 145"
            case "currentZone", "targetZoneCoach":
                phrase = norwegian ? "Pulssone 3" : "Heart-rate zone 3"
            case "workoutStart":
                phrase = norwegian ? "Økten har startet" : "Workout started"
            case "workoutFinish":
                phrase = norwegian ? "Økten er fullført" : "Workout completed"
            case "remainingStepTime":
                phrase = norwegian ? "25 sekunder igjen av draget"
                                   : "25 seconds remaining in the effort"
            case "currentStep":
                phrase = norwegian ? "Neste drag: Intervall 2" : "Next effort: Interval 2"
            case "motivation", "randomEncouragement", "adaptiveMotivation":
                phrase = norwegian ? "Du holder god fart. Fortsett slik!" : "Strong pace. Keep going!"
            case "routeRemaining":
                phrase = norwegian ? "2,1 kilometer igjen av ruten"
                                   : "2.1 kilometers remaining on the route"
            default:
                phrase = nil
            }
            if let phrase, !allMessages.contains(phrase) {
                allMessages.append(phrase)
            }
        }
        let sample = allMessages.joined(separator: ". ")
        return sample.isEmpty
            ? (norwegian ? "Dette er en test av gruppens stemme." : "This is a preview of the group's voice.")
            : sample
    }
}

struct ATHLTHAudioCoachRuleSet: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var rules: [ATHLTHAudioCoachRule]
}


/// Planned estimates and segment measurements supplied by the recording owner.
struct ATHLTHCoachReadoutContext: Codable, Hashable {
    var stepName: String?
    var stepIndex: Int?
    var isEffort = false
    var stepElapsedSeconds: Double = 0
    var stepDistanceMeters: Double = 0
    var groupStartIndex: Int?
    var groupElapsedSeconds: Double = 0
    var groupDistanceMeters: Double = 0
    var stepRemainingSeconds: Double?
    var groupRemainingSeconds: Double?
    var workoutRemainingSeconds: Double?
    var routeRemainingMeters: Double?
    /// Explicit distance remaining for a workout with fully known distance
    /// steps. Nil for timed/open-ended sessions without a reliable goal.
    var workoutRemainingMeters: Double? = nil
    /// Verified cumulative uphill gain, not planned route elevation.
    var elevationGainMeters: Double? = nil
    /// Nil when terrain accuracy is insufficient.
    var isUphill: Bool? = nil
    /// Active exercise target HR zone, not the user's currently measured zone.
    var plannedHeartRateZone: Int? = nil
    // Measured values, not prescribed pace. The rolling kilometre is only
    // available after a full kilometre of monotonic recorded distance.
    var overallPaceSecondsPerKilometer: Double? = nil
    var lastKilometerPaceSecondsPerKilometer: Double? = nil
    // Faster and slower edges of an authored target range. For an exact
    // target, both values are equal.
    var targetPaceSecondsPerKilometer: Double? = nil
    var targetSlowestPaceSecondsPerKilometer: Double? = nil
    var verifiedPersonalRecordEnglish: String? = nil
    var verifiedPersonalRecordNorwegian: String? = nil
    // Optional computed plan context; older Watch/iPhone snapshots decode with nil.
    var stepPhase: String?
    var previousStepPhase: String?
    var nextStepPhase: String?
    var hasNextStep: Bool? = nil
    // Optional: older iPhone/Watch snapshots have no event metadata.
    var isActiveRecovery: Bool? = nil
    var previousWasActiveRecovery: Bool? = nil
    var nextIsActiveRecovery: Bool? = nil
    var stepCount: Int? = nil
    var firstRecoveryStepIndex: Int? = nil
    var lastRecoveryStepIndex: Int? = nil
    // Optional fields keep old Watch/phone snapshots backwards compatible.
    var remainingExerciseCount: Int? = nil
    var nextExerciseName: String? = nil
    var nextExerciseDetails: String? = nil
    var previousExerciseName: String? = nil
    var previousExerciseCompleted: Bool? = nil
    var previousExerciseSeconds: Double? = nil
    var previousExerciseDistanceMeters: Double? = nil
    var previousMainSectionExerciseCount: Int? = nil
    var previousMainSectionSeconds: Double? = nil
    var previousMainSectionDistanceMeters: Double? = nil

    static func needsSegmentData(_ rules: [ATHLTHAudioCoachRule]) -> Bool {
        rules.contains { rule in
            rule.isEnabled && ((rule.allowedPhases?.isEmpty == false) ||
                rule.trigger.isPaceCondition ||
                rule.trigger.usesLiveContext ||
                rule.beforeEndSeconds != nil ||
                rule.trigger.needsStructuredStep ||
                (rule.scope ?? .workout) != .workout ||
                rule.selectedMetrics.contains { metric in
                    switch metric {
                    case .stepName, .stepRemainingTime, .groupRemainingTime,
                         .workoutRemainingTime, .estimatedFinishTime,
                         .remainingExercises, .nextExercise, .previousExerciseSummary,
                         .previousMainSectionSummary, .lastKilometerPace: return true
                    default: return false
                    }
                })
        }
    }

    /// Strength uses the Watch's actual completed/pending exercise queue.
    /// Planned repetitions and weight are only announced as NEXT targets.
    /// A completed exercise is not given an invented duration or load.
    static func make(strength snapshot: WatchStrengthSessionSnapshot) -> Self {
        var context = Self()
        let exercises = (snapshot.exerciseQueue ?? []).sorted { $0.index < $1.index }
        context.stepIndex = snapshot.exerciseIndex
        context.stepCount = max(snapshot.exerciseCount, exercises.count)
        context.stepName = snapshot.exerciseName
        context.stepPhase = snapshot.isResting ? "recovery"
            : snapshot.isWarmUp == true ? "warmup" : "work"
        context.remainingExerciseCount = exercises.filter {
            $0.index > snapshot.exerciseIndex && $0.isCompleted != true
        }.count

        if let next = exercises.first(where: {
            $0.index > snapshot.exerciseIndex && $0.isCompleted != true
        }) {
            context.nextExerciseName = next.name
            var parts: [String] = []
            if next.setCount > 0 { parts.append("\(next.setCount) × sett") }
            if let first = next.setPlans?.first {
                if let reps = first.reps, reps > 0 {
                    parts.append("\(reps) reps")
                } else if let seconds = first.durationSeconds, seconds > 0 {
                    parts.append("\(seconds) s")
                }
                if let kilograms = first.weightKilograms,
                   kilograms.isFinite, kilograms > 0 {
                    parts.append("\(kilograms.formatted(.number.precision(.fractionLength(0...1)))) kg mål")
                }
            }
            context.nextExerciseDetails = parts.joined(separator: ", ")
        }
        if let completed = exercises.last(where: {
            $0.index < snapshot.exerciseIndex && $0.isCompleted == true
        }) {
            context.previousExerciseName = completed.name
            context.previousExerciseCompleted = true
        }
        let previous = exercises.last(where: { $0.index < snapshot.exerciseIndex })
        let currentGroupID = exercises.first(where: {
            $0.index == snapshot.exerciseIndex
        })?.strengthGroupID
        if let previousGroupID = previous?.strengthGroupID,
           currentGroupID != previousGroupID {
            let earlier = exercises.filter { $0.strengthGroupID == previousGroupID }
            if !earlier.isEmpty && earlier.allSatisfy({ $0.isCompleted == true }) {
                context.previousMainSectionExerciseCount = earlier.count
            }
        }
        return context
    }

    static func make(
        plan: WatchRunningWorkoutTransfer?, index: Int?,
        elapsed: Double, distance: Double,
        recorded: [ATHLTHRecordedRunningStep], routeRemainingMeters: Double?
    ) -> Self {
        var context = Self(routeRemainingMeters: routeRemainingMeters)
        guard let steps = plan?.steps, let index, steps.indices.contains(index) else { return context }
        let step = steps[index]
        context.stepName = step.title
        context.stepIndex = index
        context.plannedHeartRateZone = step.targetHeartRateZone
        // A distance-based finish is available only when every remaining
        // executable step has a defined distance. Timed/open steps are not
        // assigned invented metres.
        let remaining = steps[index...]
        if remaining.allSatisfy({ candidate in
            if candidate.phase == "recovery" &&
               candidate.distanceMeters == nil { return true }
            guard let value = candidate.distanceMeters else { return false }
            return value.isFinite && value >= 0
        }) {
            let future = remaining.dropFirst().reduce(0.0) {
                $0 + ($1.distanceMeters ?? 0)
            }
            context.workoutRemainingMeters =
                max(0, (step.distanceMeters ?? 0) - max(0, distance)) + future
        }
        context.stepCount = steps.count
        context.firstRecoveryStepIndex = steps.firstIndex { $0.phase == "recovery" }
        context.lastRecoveryStepIndex = steps.lastIndex { $0.phase == "recovery" }
        // Recovery steps are pauses, not exercises. Count only actual
        // upcoming activities (work, warm-up, cool-down, etc.).
        let isExercise: (WatchRunningWorkoutStep) -> Bool = {
            $0.phase != "recovery"
        }
        context.remainingExerciseCount = steps[(index + 1)...]
            .filter(isExercise).count
        if let nextIndex = ((index + 1)..<steps.count).first(where: {
            isExercise(steps[$0])
        }) {
            let next = steps[nextIndex]
            context.nextExerciseName = next.title
            var details: [String] = []
            if let seconds = next.durationSeconds, seconds.isFinite, seconds > 0 {
                details.append("\(Int(seconds.rounded())) s")
            } else if let meters = next.distanceMeters, meters.isFinite, meters > 0 {
                details.append("\(Int(meters.rounded())) m")
            }
            if let zone = next.targetHeartRateZone, (1...5).contains(zone) {
                details.append("Z\(zone)")
            } else if let intensity = next.intensityText, !intensity.isEmpty {
                details.append(intensity)
            }
            context.nextExerciseDetails = details.isEmpty ? nil : details.joined(separator: ", ")
        }
        if let previousIndex = (0..<index).last(where: { isExercise(steps[$0]) }),
           let previous = recorded.last(where: { $0.index == previousIndex }) {
            context.previousExerciseName = steps[previousIndex].title
            context.previousExerciseSeconds = previous.activeSeconds
            context.previousExerciseDistanceMeters = previous.distanceMeters
        }
        // A main-part report only exists when that section is complete.
        // Never turn planned targets into claimed achieved measurements.
        let isMain: (WatchRunningWorkoutStep) -> Bool = {
            $0.phase == "work" || $0.phase == "recovery" ||
                $0.phase == "steady" || $0.phase == "main"
        }
        if !isMain(step), index > 0, isMain(steps[index - 1]) {
            let completedMain = recorded.filter { entry in
                entry.index < index && steps.indices.contains(entry.index) &&
                    isMain(steps[entry.index])
            }
            let completedExercises = completedMain.filter {
                steps[$0.index].phase != "recovery"
            }
            if !completedMain.isEmpty {
                context.previousMainSectionExerciseCount = completedExercises.count
                context.previousMainSectionSeconds = completedMain.reduce(0) { $0 + max(0, $1.activeSeconds) }
                context.previousMainSectionDistanceMeters = completedMain.reduce(0) { $0 + max(0, $1.distanceMeters) }
            }
        }
        context.stepPhase = step.phase
        context.previousStepPhase = index > 0 ? steps[index - 1].phase : nil
        context.nextStepPhase = index + 1 < steps.count ? steps[index + 1].phase : nil
        context.hasNextStep = index + 1 < steps.count
        context.isActiveRecovery = step.phase == "recovery" && step.recoveryStyle == .activeJog
        context.previousWasActiveRecovery = index > 0 &&
            steps[index - 1].phase == "recovery" &&
            steps[index - 1].recoveryStyle == .activeJog
        context.nextIsActiveRecovery = index + 1 < steps.count &&
            steps[index + 1].phase == "recovery" &&
            steps[index + 1].recoveryStyle == .activeJog
        context.isEffort = step.phase == "work"
        context.stepElapsedSeconds = max(0, elapsed)
        context.stepDistanceMeters = max(0, distance)
        context.stepRemainingSeconds = estimate(step, elapsed: elapsed, distance: distance)
        context.workoutRemainingSeconds = total(steps[index...], elapsed: elapsed, distance: distance)

        // Use explicit drag-group IDs where present. Older sessions group the
        // contiguous work/recovery phases of the main section.
        let inGroup: (WatchRunningWorkoutStep) -> Bool = { candidate in
            if let groupID = step.coachGroupID { return candidate.coachGroupID == groupID }
            return candidate.coachGroupID == nil &&
                (candidate.phase == "work" || candidate.phase == "recovery")
        }
        if inGroup(step) {
            var first = index
            while first > 0, inGroup(steps[first - 1]) { first -= 1 }
            var end = index + 1
            while end < steps.count, inGroup(steps[end]) { end += 1 }
            context.groupStartIndex = first
            context.groupRemainingSeconds = total(steps[index..<end], elapsed: elapsed, distance: distance)
            let previous = recorded.filter { (first..<index).contains($0.index) }
            context.groupElapsedSeconds = context.stepElapsedSeconds + previous.reduce(0) { $0 + $1.activeSeconds }
            context.groupDistanceMeters = context.stepDistanceMeters + previous.reduce(0) { $0 + $1.distanceMeters }
        }
        return context
    }

    private static func total(_ steps: ArraySlice<WatchRunningWorkoutStep>, elapsed: Double, distance: Double) -> Double? {
        var sum: Double = 0
        for index in steps.indices {
            let current = index == steps.startIndex
            guard let seconds = estimate(steps[index], elapsed: current ? elapsed : 0,
                                         distance: current ? distance : 0) else { return nil }
            sum += seconds
        }
        return sum
    }

    private static func estimate(_ step: WatchRunningWorkoutStep, elapsed: Double, distance: Double) -> Double? {
        switch step.measure {
        case .time:
            guard let duration = step.durationSeconds, duration.isFinite, duration > 0 else { return nil }
            return max(0, duration - elapsed)
        case .distance:
            guard let meters = step.distanceMeters, meters.isFinite, meters > 0,
                  let pace = step.targetPaceMinSecondsPerKilometer ?? step.targetPaceMaxSecondsPerKilometer,
                  pace.isFinite, (30...3_600).contains(pace) else { return nil }
            return max(0, meters - distance) * pace / 1000
        case .open:
            return nil
        }
    }
}

/// Activity-specific eligibility for the existing audio coach. Stored
/// templates are unchanged; unsuitable running rules are skipped only
/// while a different sport is active. This does not open a second coach.
enum ATHLTHAudioCoachSportPolicy {
    private static func key(_ sport: String) -> String {
        sport.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func supportsRunningSteps(_ sport: String) -> Bool {
        ["running", "walking", "treadmill", "hiking"].contains(key(sport))
    }

    static func supportsDistance(_ sport: String) -> Bool {
        ["running", "walking", "treadmill", "hiking",
         "cycling", "rowing"].contains(key(sport))
    }

    static func supportsRunningPace(_ sport: String) -> Bool {
        supportsRunningSteps(sport)
    }

    /// Strength has a separately verified exercise queue. Do not combine
    /// its exercise readouts with a running PR or pace in one spoken cue.
    static func eligibleStrengthRules(
        _ rules: [ATHLTHAudioCoachRule]
    ) -> [ATHLTHAudioCoachRule] {
        rules.filter { rule in
            guard rule.trigger != .distance,
                  rule.trigger != .nearFinishDistance,
                  rule.trigger != .elevationGain,
                  rule.trigger != .uphillDetected,
                  !rule.trigger.isPaceCondition,
                  rule.trigger != .personalRecordConfirmed else {
                return false
            }
            return rule.selectedMetrics.allSatisfy { metric in
                switch metric {
                case .remainingExercises, .nextExercise,
                     .previousExerciseSummary, .previousMainSectionSummary,
                     .stepName, .elapsedTime, .motivation,
                     .heartRate, .heartRateZone, .hydrationReminder,
                     .clockTime, .date, .workoutRemainingTime:
                    return true
                default: return false
                }
            }
        }
    }

    /// Keep generic time, measured pulse, hydration and eligible measured
    /// distance rules on non-running sports. Do not misread running pace,
    /// route, PR, or step evidence as cycling/rowing/HIIT measurements.
    static func eligibleRules(
        _ rules: [ATHLTHAudioCoachRule],
        sport: String,
        measuredDistanceSupported: Bool = true
    ) -> [ATHLTHAudioCoachRule] {
        guard !supportsRunningSteps(sport) else { return rules }
        let distanceAvailable = supportsDistance(sport) &&
            measuredDistanceSupported
        return rules.filter { rule in
            if rule.trigger.needsStructuredStep ||
                rule.trigger.isPaceCondition ||
                rule.trigger == .personalRecordConfirmed { return false }
            if (rule.trigger == .distance ||
                rule.trigger == .nearFinishDistance) && !distanceAvailable {
                return false
            }
            if rule.trigger == .elevationGain ||
               rule.trigger == .uphillDetected {
                return false
            }
            return rule.selectedMetrics.allSatisfy { metric in
                switch metric {
                case .pace, .averagePace, .lastKilometerPace,
                     .personalRecord, .routeRemainingDistance,
                     .estimatedRouteTime, .stepName, .stepRemainingTime,
                     .groupRemainingTime, .workoutRemainingTime,
                     .estimatedFinishTime, .remainingExercises, .nextExercise,
                     .previousExerciseSummary, .previousMainSectionSummary,
                     .speed:
                    return false
                case .distance:
                    return distanceAvailable
                default: return true
                }
            }
        }
    }
}

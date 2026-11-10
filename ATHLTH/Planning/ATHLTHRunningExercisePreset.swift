import Foundation

/// Run-only choices for the planned workout timeline. Every result uses the
/// existing run/interval execution model rather than a parallel exercise type.
enum ATHLTHRunningExercisePreset: String, CaseIterable, Identifiable {
    case running, treadmill, progressive, drills, easy, strides, threshold, hills
    case fourByFour, thirtyThirty, fortyFiveFifteen, fiveByThree
    case sixByFourHundred, fiveByOneKilometer, shortIntervals, fartlek
    case sixMinuteTest, cooperTest, oneKilometerTest, fiveKilometerTest
    case tenKilometerTest, longRun, recoveryRun, cooldown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .running: return tr("Running", "Løping")
        case .treadmill: return tr("Treadmill running", "Løping på tredemølle")
        case .progressive: return tr("Progressive jog", "Progressiv jogg")
        case .drills: return tr("Running drills", "Løpsdriller")
        case .easy: return tr("Easy run", "Rolig løping")
        case .strides: return tr("Strides · 6 × 20 sec", "Stigningsløp · 6 × 20 sek")
        case .threshold: return tr("Threshold run", "Terskelløp")
        case .hills: return tr("Hill repeats · 8 × 45 sec", "Bakkedrag · 8 × 45 sek")
        case .fourByFour: return tr("Intervals · 4 × 4 min", "Intervaller · 4 × 4 min")
        case .thirtyThirty: return tr("30/30 · 20 repeats", "30/30 · 20 drag")
        case .fortyFiveFifteen: return tr("45/15 · 15 repeats", "45/15 · 15 drag")
        case .fiveByThree: return tr("Intervals · 5 × 3 min", "Intervaller · 5 × 3 min")
        case .sixByFourHundred: return tr("Intervals · 6 × 400 m", "Intervaller · 6 × 400 m")
        case .fiveByOneKilometer: return tr("Threshold · 5 × 1 km", "Terskel · 5 × 1 km")
        case .shortIntervals: return tr("Sprint · 10 × 30 sec", "Sprint · 10 × 30 sek")
        case .fartlek: return tr("Fartlek · 10 × 1 min", "Fartslek · 10 × 1 min")
        case .sixMinuteTest: return tr("6-minute running test", "6-minutters løpstest")
        case .cooperTest: return tr("Cooper test · 12 min", "Coopertest · 12 min")
        case .oneKilometerTest: return tr("1 km time trial", "1 km testløp")
        case .fiveKilometerTest: return tr("5 km time trial", "5 km testløp")
        case .tenKilometerTest: return tr("10 km time trial", "10 km testløp")
        case .longRun: return tr("Long run", "Langtur")
        case .recoveryRun: return tr("Recovery run", "Restitusjonsløping")
        case .cooldown: return tr("Very easy jog", "Svært rolig nedjogg")
        }
    }

    var detail: String {
        switch self {
        case .running: return tr("20 min · adjust time or distance", "20 min · juster tid eller distanse")
        case .treadmill: return tr("20 min · indoor, adjustable speed and incline", "20 min · innendørs, juster fart og stigning")
        case .progressive: return tr(
            "15 min · 3 progressively faster, editable pace steps",
            "15 min · 3 deløkter med økende, justerbart tempo"
        )
        case .drills: return tr("5 min · technique and coordination", "5 min · teknikk og koordinasjon")
        case .easy: return tr("20 min · conversational pace", "20 min · rolig snakketempo")
        case .strides: return tr("6 repeats with 60 sec recovery", "6 drag med 60 sek pause")
        case .threshold: return tr("20 min · controlled hard effort", "20 min · kontrollert hard innsats")
        case .hills: return tr("8 hill efforts, jog back down", "8 bakkedrag med rolig jogg ned")
        case .fourByFour: return tr("4 × 4 min · 3 min easy recovery", "4 × 4 min · 3 min rolig pause")
        case .thirtyThirty: return tr("20 × 30 sec fast / 30 sec easy", "20 × 30 sek raskt / 30 sek rolig")
        case .fortyFiveFifteen: return tr("15 × 45 sec fast / 15 sec easy", "15 × 45 sek raskt / 15 sek rolig")
        case .fiveByThree: return tr("5 × 3 min · 90 sec recovery", "5 × 3 min · 90 sek pause")
        case .sixByFourHundred: return tr("6 × 400 m · 90 sec recovery", "6 × 400 m · 90 sek pause")
        case .fiveByOneKilometer: return tr("5 × 1 km · 2 min recovery", "5 × 1 km · 2 min pause")
        case .shortIntervals: return tr("10 × 30 sec · 90 sec recovery", "10 × 30 sek · 90 sek pause")
        case .fartlek: return tr("10 × 1 min fast / 1 min easy", "10 × 1 min raskt / 1 min rolig")
        case .sixMinuteTest: return tr("6 min · greatest distance possible", "6 min · løp så langt du kan")
        case .cooperTest: return tr("12 min · greatest distance possible", "12 min · løp så langt du kan")
        case .oneKilometerTest: return tr("1 km · best time", "1 km · best mulig tid")
        case .fiveKilometerTest: return tr("5 km · best time", "5 km · best mulig tid")
        case .tenKilometerTest: return tr("10 km · best time", "10 km · best mulig tid")
        case .longRun: return tr("75 min · easy aerobic effort", "75 min · rolig aerob langtur")
        case .recoveryRun: return tr("25 min · easy HR zone", "25 min · rolig pulssone")
        case .cooldown: return tr("10 min · very gentle pace", "10 min · svært rolig tempo")
        }
    }

    func blocks(in phase: WorkoutPhaseKind) -> [WorkoutTemplateBlock] {
        switch self {
        case .running:
            return [Self.run(title: title, seconds: 1_200, effort: 4, phase: phase)]
        case .treadmill:
            var block = Self.run(title: title, seconds: 1_200, effort: 4, phase: phase)
            block.isIndoor = true
            block.treadmillInclinePercent = 0
            block.targetPaceSecondsPerKilometer = 360
            return [block]
        case .progressive:
            // Each step has a real, editable pace target. Do not show
            // "progressive" for one flat effort with no speed progression.
            // These are example paces, not claims about athlete ability.
            let paces: [TimeInterval] = [420, 390, 360]
            return paces.enumerated().map { index, pace in
                var step = Self.run(
                    title: tr("Progressive step", "Progressivt drag") + " \(index + 1)",
                    seconds: 300, effort: index + 3, phase: phase
                )
                step.targetPaceSecondsPerKilometer = pace
                step.notes = tr(
                    "Example target pace; adjust each step to your fitness.",
                    "Eksempeltempo. Tilpass hvert drag til ditt nivå."
                )
                return step
            }
        case .drills:
            var block = Self.run(title: title, seconds: 300, effort: 3, phase: phase)
            block.notes = tr("Running technique, cadence and acceleration drills.",
                             "Løpsteknikk, frekvens og gradvis akselerasjon.")
            return [block]
        case .easy:
            return [Self.run(title: title, seconds: 1_200, effort: 3, phase: phase)]
        case .strides:
            return Self.intervals(work: 20, recovery: 60, rounds: 6,
                                  effort: 7, phase: phase,
                                  workName: tr("Stride", "Stigningsløp"))
        case .threshold:
            var step = Self.run(title: title, seconds: 1_200, effort: 7, phase: phase)
            // Threshold varies by athlete. Provide an editable initial zone
            // without incorrectly claiming a personally measured threshold.
            step.targetHeartRateZone = 4
            step.notes = tr(
                "Suggested HR zone 4. Adjust to your measured threshold or pace.",
                "Foreslått pulssone 4. Juster etter målt terskel eller terskeltempo."
            )
            return [step]
        case .hills:
            return Self.intervals(work: 45, recovery: 90, rounds: 8,
                                  effort: 8, phase: phase,
                                  workName: tr("Hill effort", "Bakkedrag"),
                                  recoveryName: tr("Jog down the hill", "Jogg rolig ned bakken"),
                                  activeRecovery: true)
        case .fourByFour:
            return Self.intervals(work: 240, recovery: 180,
                                  rounds: 4, effort: 8, phase: phase,
                                  activeRecovery: true)
        case .thirtyThirty:
            return Self.intervals(work: 30, recovery: 30,
                                  rounds: 20, effort: 8, phase: phase,
                                  activeRecovery: true)
        case .fortyFiveFifteen:
            return Self.intervals(work: 45, recovery: 15,
                                  rounds: 15, effort: 8, phase: phase,
                                  activeRecovery: true)
        case .fiveByThree:
            return Self.intervals(work: 180, recovery: 90,
                                  rounds: 5, effort: 8, phase: phase)
        case .sixByFourHundred:
            return Self.intervals(work: nil, workDistanceMeters: 400,
                                  recovery: 90, rounds: 6, effort: 8, phase: phase)
        case .fiveByOneKilometer:
            return Self.intervals(work: nil, workDistanceMeters: 1_000,
                                  recovery: 120, rounds: 5, effort: 7, phase: phase)
        case .shortIntervals:
            return Self.intervals(work: 30, recovery: 90,
                                  rounds: 10, effort: 9, phase: phase,
                                  workName: tr("Sprint", "Sprint"))
        case .fartlek:
            // Pyramid rather than another static 1/1 interval preset:
            // fast 1-2-3-2-1 minutes, matched easy jogs, independently editable.
            return [60.0, 120, 180, 120, 60].enumerated().flatMap { index, seconds in
                var fast = Self.run(
                    title: tr("Fartlek effort", "Fartslekdrag") + " \(index + 1)",
                    seconds: seconds, effort: 7, phase: phase
                )
                fast.notes = tr("Comfortably fast; adjust effort or pace.",
                                "Kontrollert raskt. Juster intensitet eller tempo.")
                var easy = Self.run(
                    title: tr("Easy jog", "Rolig jogg") + " \(index + 1)",
                    seconds: seconds, effort: 2, phase: phase
                )
                easy.activityTag = "active_recovery"
                easy.targetHeartRateZone = 2
                return [fast, easy]
            }
        case .sixMinuteTest:
            return [Self.run(title: title, seconds: 360, effort: 9, phase: phase)]
        case .cooperTest:
            return [Self.run(title: title, seconds: 720, effort: 9, phase: phase)]
        case .oneKilometerTest, .fiveKilometerTest, .tenKilometerTest:
            var test = Self.run(title: title, seconds: 600, effort: 9, phase: phase)
            test.durationSeconds = nil
            test.distanceMeters = self == .oneKilometerTest
                ? 1_000 : self == .fiveKilometerTest ? 5_000 : 10_000
            return [test]
        case .longRun:
            var long = Self.run(title: title, seconds: 4_500, effort: 3, phase: phase)
            long.targetHeartRateZone = 2
            long.notes = tr(
                "Aerobic long run. Adjust zone, duration and optionally add a faster finish.",
                "Rolig langtur. Juster sone og varighet, eller legg til en rask avslutning."
            )
            return [long]
        case .recoveryRun:
            var easy = Self.run(title: title, seconds: 1_500, effort: 2, phase: phase)
            easy.targetHeartRateZone = 1
            easy.notes = tr("Stay easy; slow down if heart rate rises.",
                            "Hold lav intensitet og senk farten hvis pulsen stiger.")
            return [easy]
        case .cooldown:
            return [Self.run(title: title, seconds: 600, effort: 2, phase: phase)]
        }
    }

    private static func run(
        title: String, seconds: TimeInterval, effort: Int, phase: WorkoutPhaseKind
    ) -> WorkoutTemplateBlock {
        var block = WorkoutTemplateBlock(
            sequence: 0, kind: .run, title: title, exerciseSlug: nil,
            distanceMeters: nil, repetitions: nil, durationSeconds: seconds,
            targetWeightKilograms: nil, loadNote: nil, notes: nil, phase: phase
        )
        block.cardioActivity = .running
        // RPE is still decodable on older workouts, but is not assigned
        // automatically to any newly inserted running library exercise.
        return block
    }

    /// Library presets are inserted as actual, independently editable steps.
    /// Unlike a manually created interval group, the editor must show every
    /// effort and every recovery, including the final requested pause.
    private static func intervals(
        work: TimeInterval?, workDistanceMeters: Double? = nil,
        recovery: TimeInterval, rounds: Int, effort: Int, phase: WorkoutPhaseKind,
        workName: String? = nil, recoveryName: String? = nil,
        activeRecovery: Bool = false
    ) -> [WorkoutTemplateBlock] {
        let count = min(max(rounds, 1), 20)
        let groupID = UUID()
        let effortLabel = workName ?? tr("Effort", "Drag")
        let recoveryLabel = recoveryName ?? tr("Recovery", "Pause")
        var steps: [WorkoutTemplateBlock] = []
        steps.reserveCapacity(count * 2)

        for round in 1...count {
            var running = run(
                title: "\(effortLabel) \(round)", seconds: work ?? 600,
                effort: effort, phase: phase
            )
            if let workDistanceMeters {
                running.durationSeconds = nil
                running.distanceMeters = workDistanceMeters
            }
            running.groupID = groupID
            running.groupKind = .intervals
            running.groupRounds = 1
            steps.append(running)

            var pause = run(
                title: "\(recoveryLabel) \(round)", seconds: recovery,
                effort: 2, phase: phase
            )
            pause.kind = activeRecovery ? .run : .rest
            pause.activityTag = activeRecovery ? "active_recovery" : nil
            pause.cardioActivity = activeRecovery ? .running : nil
            pause.targetHeartRateZone = activeRecovery ? 1 : nil
            pause.groupID = groupID
            pause.groupKind = .intervals
            pause.groupRounds = 1
            steps.append(pause)
        }
        return steps
    }

    private func tr(_ english: String, _ norwegian: String) -> String {
        Self.tr(english, norwegian)
    }

    private static func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }
}

import Foundation

/// Run-only choices for the planned workout timeline. Every result uses the
/// existing run/interval execution model rather than a parallel exercise type.
enum ATHLTHRunningExercisePreset: String, CaseIterable, Identifiable {
    case progressive, drills, easy, strides, threshold, hills, fourByFour
    case shortIntervals, fartlek, sixMinuteTest, cooldown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .progressive: return tr("Progressive jog", "Progressiv jogg")
        case .drills: return tr("Running drills", "Løpsdriller")
        case .easy: return tr("Easy run", "Rolig løping")
        case .strides: return tr("Strides · 6 × 20 sec", "Stigningsløp · 6 × 20 sek")
        case .threshold: return tr("Threshold run", "Terskelløp")
        case .hills: return tr("Hill repeats · 8 × 45 sec", "Bakkedrag · 8 × 45 sek")
        case .fourByFour: return tr("Intervals · 4 × 4 min", "Intervaller · 4 × 4 min")
        case .shortIntervals: return tr("Sprint · 10 × 30 sec", "Sprint · 10 × 30 sek")
        case .fartlek: return tr("Fartlek · 10 × 1 min", "Fartslek · 10 × 1 min")
        case .sixMinuteTest: return tr("6-minute running test", "6-minutters løpstest")
        case .cooldown: return tr("Very easy jog", "Svært rolig nedjogg")
        }
    }

    var detail: String {
        switch self {
        case .progressive: return tr("10 min · increasing pace", "10 min · gradvis økende fart")
        case .drills: return tr("5 min · technique and coordination", "5 min · teknikk og koordinasjon")
        case .easy: return tr("20 min · conversational pace", "20 min · rolig snakketempo")
        case .strides: return tr("6 repeats with 60 sec recovery", "6 drag med 60 sek pause")
        case .threshold: return tr("20 min · controlled hard effort", "20 min · kontrollert hard innsats")
        case .hills: return tr("8 hill efforts, jog back down", "8 bakkedrag med rolig jogg ned")
        case .fourByFour: return tr("4 × 4 min · 3 min easy recovery", "4 × 4 min · 3 min rolig pause")
        case .shortIntervals: return tr("10 × 30 sec · 90 sec recovery", "10 × 30 sek · 90 sek pause")
        case .fartlek: return tr("10 × 1 min fast / 1 min easy", "10 × 1 min raskt / 1 min rolig")
        case .sixMinuteTest: return tr("6 min · greatest distance possible", "6 min · løp så langt du kan")
        case .cooldown: return tr("10 min · very gentle pace", "10 min · svært rolig tempo")
        }
    }

    func blocks(in phase: WorkoutPhaseKind) -> [WorkoutTemplateBlock] {
        switch self {
        case .progressive:
            return [Self.run(title: title, seconds: 600, effort: 4, phase: phase)]
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
            return [Self.run(title: title, seconds: 1_200, effort: 7, phase: phase)]
        case .hills:
            return Self.intervals(work: 45, recovery: 90, rounds: 8,
                                  effort: 8, phase: phase,
                                  workName: tr("Hill effort", "Bakkedrag"),
                                  recoveryName: tr("Jog down the hill", "Jogg rolig ned bakken"))
        case .fourByFour:
            return Self.intervals(work: 240, recovery: 180,
                                  rounds: 4, effort: 8, phase: phase)
        case .shortIntervals:
            return Self.intervals(work: 30, recovery: 90,
                                  rounds: 10, effort: 9, phase: phase,
                                  workName: tr("Sprint", "Sprint"))
        case .fartlek:
            return Self.intervals(work: 60, recovery: 60,
                                  rounds: 10, effort: 7, phase: phase,
                                  workName: tr("Fast effort", "Hurtig drag"))
        case .sixMinuteTest:
            return [Self.run(title: title, seconds: 360, effort: 9, phase: phase)]
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
        block.targetEffortRPE = effort
        return block
    }

    /// Library presets are inserted as actual, independently editable steps.
    /// Unlike a manually created interval group, the editor must show every
    /// effort and every recovery, including the final requested pause.
    private static func intervals(
        work: TimeInterval, recovery: TimeInterval,
        rounds: Int, effort: Int, phase: WorkoutPhaseKind,
        workName: String? = nil, recoveryName: String? = nil
    ) -> [WorkoutTemplateBlock] {
        let count = min(max(rounds, 1), 20)
        let effortLabel = workName ?? tr("Effort", "Drag")
        let recoveryLabel = recoveryName ?? tr("Recovery", "Pause")
        var steps: [WorkoutTemplateBlock] = []
        steps.reserveCapacity(count * 2)

        for round in 1...count {
            let running = run(
                title: "\(effortLabel) \(round)", seconds: work,
                effort: effort, phase: phase
            )
            steps.append(running)

            var pause = run(
                title: "\(recoveryLabel) \(round)", seconds: recovery,
                effort: 2, phase: phase
            )
            pause.kind = .rest
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

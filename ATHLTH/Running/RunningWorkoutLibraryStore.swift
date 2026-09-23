import Foundation

@MainActor
final class RunningWorkoutLibraryStore: ObservableObject {
    @Published private(set) var customTemplates: [RunningWorkoutTemplate] = []

    init() {
        customTemplates = Self.loadCustomTemplates()
    }

    var allTemplates: [RunningWorkoutTemplate] {
        Self.builtInTemplates + customTemplates.sorted {
            $0.updatedAt > $1.updatedAt
        }
    }

    func save(_ template: RunningWorkoutTemplate) {
        var copy = template
        copy.updatedAt = Date()
        copy.isBuiltIn = false

        if let index = customTemplates.firstIndex(where: { $0.id == copy.id }) {
            customTemplates[index] = copy
        } else {
            customTemplates.append(copy)
        }

        persist()
    }

    func delete(_ id: UUID) {
        customTemplates.removeAll { $0.id == id }
        persist()
    }

    func saveShared(
        _ source: RunningWorkoutTemplate,
        sourceOwnerID: UUID?,
        sourceWorkoutID: UUID?
    ) -> RunningWorkoutTemplate {
        var copy = RunningWorkoutTemplate(
            id: UUID(),
            title: source.title,
            type: source.type,
            summary: source.summary,
            blocks: source.blocks,
            routeID: source.routeID,
            isBuiltIn: false,
            createdAt: Date(),
            updatedAt: Date()
        )
        copy.sharedSourceOwnerID =
            source.sharedSourceOwnerID ?? sourceOwnerID
        copy.sharedSourceWorkoutID =
            source.sharedSourceWorkoutID ?? sourceWorkoutID ?? source.id

        customTemplates.append(copy)
        persist()
        return copy
    }

    func duplicate(_ source: RunningWorkoutTemplate) -> RunningWorkoutTemplate {
        let duplicate = RunningWorkoutTemplate(
            id: UUID(),
            title: "\(source.title) Copy",
            type: source.type,
            summary: source.summary,
            blocks: source.blocks.map {
                RunningWorkoutBlock(
                    kind: $0.kind,
                    title: $0.title,
                    repetitions: $0.repetitions,
                    work: $0.work,
                    recovery: $0.recovery,
                    notes: $0.notes
                )
            },
            routeID: source.routeID,
            isBuiltIn: false,
            createdAt: Date(),
            updatedAt: Date()
        )

        customTemplates.append(duplicate)
        persist()
        return duplicate
    }

    private func persist() {
        guard let url = Self.storageURL else { return }

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(customTemplates)
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
    }

    private static func loadCustomTemplates() -> [RunningWorkoutTemplate] {
        guard let url = storageURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(
                  [RunningWorkoutTemplate].self,
                  from: data
              )
        else {
            return []
        }

        return decoded
    }

    private static var storageURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("ATHLTH", isDirectory: true)
            .appendingPathComponent("running-workout-templates.json")
    }

    private static func rpe(_ value: Double) -> RunningIntensityTarget {
        RunningIntensityTarget(
            kind: .rpe,
            paceMinSecondsPerKilometer: nil,
            paceMaxSecondsPerKilometer: nil,
            heartRateZone: nil,
            rpe: value
        )
    }

    private static func template(
        _ number: Int,
        title: String,
        type: RunningWorkoutType,
        summary: String,
        blocks: [RunningWorkoutBlock]
    ) -> RunningWorkoutTemplate {
        RunningWorkoutTemplate(
            id: UUID(
                uuidString: String(
                    format: "A1000000-0000-0000-0000-%012d",
                    number
                )
            )!,
            title: title,
            type: type,
            summary: summary,
            blocks: blocks,
            routeID: nil,
            isBuiltIn: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private static func timeBlock(
        _ kind: RunningBlockKind,
        _ title: String,
        minutes: Double,
        intensity: RunningIntensityTarget,
        repetitions: Int = 1,
        recoverySeconds: TimeInterval? = nil
    ) -> RunningWorkoutBlock {
        RunningWorkoutBlock(
            kind: kind,
            title: title,
            repetitions: repetitions,
            work: .time(minutes * 60, intensity: intensity),
            recovery: recoverySeconds.map {
                .time($0, intensity: .easy)
            }
        )
    }

    private static func distanceBlock(
        _ kind: RunningBlockKind,
        _ title: String,
        meters: Double,
        intensity: RunningIntensityTarget,
        repetitions: Int = 1,
        recoverySeconds: TimeInterval? = nil,
        recoveryMeters: Double? = nil
    ) -> RunningWorkoutBlock {
        let recovery: RunningStepTarget?
        if let recoveryMeters {
            recovery = .distance(recoveryMeters, intensity: .easy)
        } else if let recoverySeconds {
            recovery = .time(recoverySeconds, intensity: .easy)
        } else {
            recovery = nil
        }

        return RunningWorkoutBlock(
            kind: kind,
            title: title,
            repetitions: repetitions,
            work: .distance(meters, intensity: intensity),
            recovery: recovery
        )
    }

    static let builtInTemplates: [RunningWorkoutTemplate] = [
        template(
            1,
            title: "Easy 30",
            type: .easy,
            summary: "30 minutes at a relaxed conversational effort.",
            blocks: [
                timeBlock(.steady, "Easy running", minutes: 30, intensity: .easy)
            ]
        ),
        template(
            2,
            title: "Recovery 25",
            type: .recovery,
            summary: "Short recovery run with low effort throughout.",
            blocks: [
                timeBlock(.steady, "Recovery running", minutes: 25, intensity: rpe(3))
            ]
        ),
        template(
            3,
            title: "Long Run 15K",
            type: .longRun,
            summary: "A steady 15 km long run at an easy, controlled effort.",
            blocks: [
                distanceBlock(.steady, "Long run", meters: 15_000, intensity: .easy)
            ]
        ),
        template(
            4,
            title: "Tempo 3 × 10",
            type: .tempo,
            summary: "Three controlled ten-minute tempo blocks with short easy recoveries.",
            blocks: [
                timeBlock(.warmup, "Warm-up", minutes: 10, intensity: .easy),
                timeBlock(.work, "Tempo", minutes: 10, intensity: rpe(7), repetitions: 3, recoverySeconds: 120),
                timeBlock(.cooldown, "Cool-down", minutes: 10, intensity: .easy)
            ]
        ),
        template(
            5,
            title: "6 × 400 m",
            type: .intervals,
            summary: "Short, fast repetitions with relaxed jogging recovery.",
            blocks: [
                timeBlock(.warmup, "Warm-up", minutes: 12, intensity: .easy),
                distanceBlock(.work, "400 m repeats", meters: 400, intensity: rpe(8), repetitions: 6, recoverySeconds: 90),
                timeBlock(.cooldown, "Cool-down", minutes: 10, intensity: .easy)
            ]
        ),
        template(
            6,
            title: "4 × 1 km",
            type: .threshold,
            summary: "Four kilometre repeats around threshold effort.",
            blocks: [
                timeBlock(.warmup, "Warm-up", minutes: 15, intensity: .easy),
                distanceBlock(.work, "1 km repeats", meters: 1_000, intensity: rpe(8), repetitions: 4, recoverySeconds: 120),
                timeBlock(.cooldown, "Cool-down", minutes: 10, intensity: .easy)
            ]
        ),
        template(
            7,
            title: "8 × 60 sec Hills",
            type: .hills,
            summary: "Eight strong uphill efforts with easy recovery between reps.",
            blocks: [
                timeBlock(.warmup, "Warm-up", minutes: 15, intensity: .easy),
                timeBlock(.work, "Uphill reps", minutes: 1, intensity: rpe(9), repetitions: 8, recoverySeconds: 90),
                timeBlock(.cooldown, "Cool-down", minutes: 10, intensity: .easy)
            ]
        ),
        template(
            8,
            title: "Fartlek 10 × 1",
            type: .fartlek,
            summary: "Ten one-minute surges with one minute easy between.",
            blocks: [
                timeBlock(.warmup, "Warm-up", minutes: 10, intensity: .easy),
                timeBlock(.work, "Fast / easy", minutes: 1, intensity: rpe(8), repetitions: 10, recoverySeconds: 60),
                timeBlock(.cooldown, "Cool-down", minutes: 10, intensity: .easy)
            ]
        ),
        template(
            9,
            title: "Easy 20",
            type: .easy,
            summary: "A short, relaxed run for low-stress aerobic volume.",
            blocks: [
                timeBlock(.steady, "Easy running", minutes: 20, intensity: .easy)
            ]
        ),
        template(
            10,
            title: "Easy 40",
            type: .easy,
            summary: "Forty minutes of comfortable, conversational running.",
            blocks: [
                timeBlock(.steady, "Easy running", minutes: 40, intensity: .easy)
            ]
        ),
        template(
            11,
            title: "Easy 50",
            type: .easy,
            summary: "Fifty minutes at an easy effort with no pace pressure.",
            blocks: [
                timeBlock(.steady, "Easy running", minutes: 50, intensity: .easy)
            ]
        ),
        template(
            12,
            title: "Easy 60",
            type: .easy,
            summary: "One hour of easy aerobic running at a controlled effort.",
            blocks: [
                timeBlock(.steady, "Easy running", minutes: 60, intensity: .easy)
            ]
        ),
        template(
            13,
            title: "Recovery 20",
            type: .recovery,
            summary: "Twenty minutes of very light running to keep the legs moving.",
            blocks: [
                timeBlock(.steady, "Recovery running", minutes: 20, intensity: rpe(2.5))
            ]
        ),
        template(
            14,
            title: "Recovery 30",
            type: .recovery,
            summary: "Thirty minutes of gentle running at an intentionally low effort.",
            blocks: [
                timeBlock(.steady, "Recovery running", minutes: 30, intensity: rpe(3))
            ]
        ),
        template(
            15,
            title: "Shakeout 15",
            type: .recovery,
            summary: "A very short shakeout for the day before a hard session or race.",
            blocks: [
                timeBlock(.steady, "Shakeout", minutes: 15, intensity: rpe(2.5))
            ]
        ),
        template(
            16,
            title: "Long Run 8K",
            type: .longRun,
            summary: "An approachable eight-kilometre long run at easy effort.",
            blocks: [
                distanceBlock(.steady, "Long run", meters: 8_000, intensity: .easy)
            ]
        ),
        template(
            17,
            title: "Long Run 10K",
            type: .longRun,
            summary: "Ten kilometres of steady easy running.",
            blocks: [
                distanceBlock(.steady, "Long run", meters: 10_000, intensity: .easy)
            ]
        ),
        template(
            18,
            title: "Long Run 12K",
            type: .longRun,
            summary: "Twelve kilometres at a sustainable conversational effort.",
            blocks: [
                distanceBlock(.steady, "Long run", meters: 12_000, intensity: .easy)
            ]
        ),
        template(
            19,
            title: "Long Run 18K",
            type: .longRun,
            summary: "Eighteen kilometres of controlled aerobic running.",
            blocks: [
                distanceBlock(.steady, "Long run", meters: 18_000, intensity: .easy)
            ]
        ),
        template(
            20,
            title: "Long Run 90",
            type: .longRun,
            summary: "Ninety minutes at an easy effort for aerobic endurance.",
            blocks: [
                timeBlock(.steady, "Long run", minutes: 90, intensity: .easy)
            ]
        ),
        template(
            21,
            title: "Tempo 20 Continuous",
            type: .tempo,
            summary: "A continuous twenty-minute tempo segment between easy running.",
            blocks: [
                timeBlock(.warmup, "Warm-up", minutes: 12, intensity: .easy),
                timeBlock(.work, "Tempo", minutes: 20, intensity: rpe(7)),
                timeBlock(.cooldown, "Cool-down", minutes: 10, intensity: .easy)
            ]
        ),
        template(
            22,
            title: "Tempo 2 × 15",
            type: .tempo,
            summary: "Two longer tempo blocks with three minutes easy between.",
            blocks: [
                timeBlock(.warmup, "Warm-up", minutes: 12, intensity: .easy),
                timeBlock(.work, "Tempo", minutes: 15, intensity: rpe(7), repetitions: 2, recoverySeconds: 180),
                timeBlock(.cooldown, "Cool-down", minutes: 10, intensity: .easy)
            ]
        ),
        template(
            23,
            title: "Tempo 4 × 8",
            type: .tempo,
            summary: "Four controlled eight-minute tempo blocks with short recoveries.",
            blocks: [
                timeBlock(.warmup, "Warm-up", minutes: 12, intensity: .easy),
                timeBlock(.work, "Tempo", minutes: 8, intensity: rpe(7), repetitions: 4, recoverySeconds: 120),
                timeBlock(.cooldown, "Cool-down", minutes: 10, intensity: .easy)
            ]
        ),
        template(
            24,
            title: "Tempo 5 × 6",
            type: .tempo,
            summary: "Five six-minute tempo repetitions with ninety seconds easy.",
            blocks: [
                timeBlock(.warmup, "Warm-up", minutes: 12, intensity: .easy),
                timeBlock(.work, "Tempo", minutes: 6, intensity: rpe(7), repetitions: 5, recoverySeconds: 90),
                timeBlock(.cooldown, "Cool-down", minutes: 10, intensity: .easy)
            ]
        ),
        template(
            25,
            title: "Threshold 3 × 1 km",
            type: .threshold,
            summary: "Three kilometre repeats at controlled threshold effort.",
            blocks: [
                timeBlock(.warmup, "Warm-up", minutes: 15, intensity: .easy),
                distanceBlock(.work, "Threshold reps", meters: 1_000, intensity: rpe(8), repetitions: 3, recoverySeconds: 120),
                timeBlock(.cooldown, "Cool-down", minutes: 10, intensity: .easy)
            ]
        ),
        template(
            26,
            title: "Threshold 5 × 1 km",
            type: .threshold,
            summary: "Five kilometre repeats at a strong but repeatable effort.",
            blocks: [
                timeBlock(.warmup, "Warm-up", minutes: 15, intensity: .easy),
                distanceBlock(.work, "Threshold reps", meters: 1_000, intensity: rpe(8), repetitions: 5, recoverySeconds: 120),
                timeBlock(.cooldown, "Cool-down", minutes: 10, intensity: .easy)
            ]
        ),
        template(
            27,
            title: "Threshold 3 × 2 km",
            type: .threshold,
            summary: "Three longer threshold repeats with easy recovery between.",
            blocks: [
                timeBlock(.warmup, "Warm-up", minutes: 15, intensity: .easy),
                distanceBlock(.work, "Threshold reps", meters: 2_000, intensity: rpe(8), repetitions: 3, recoverySeconds: 180),
                timeBlock(.cooldown, "Cool-down", minutes: 10, intensity: .easy)
            ]
        ),
        template(
            28,
            title: "Threshold 4 × 6 min",
            type: .threshold,
            summary: "Four six-minute threshold efforts with two minutes easy.",
            blocks: [
                timeBlock(.warmup, "Warm-up", minutes: 15, intensity: .easy),
                timeBlock(.work, "Threshold", minutes: 6, intensity: rpe(8), repetitions: 4, recoverySeconds: 120),
                timeBlock(.cooldown, "Cool-down", minutes: 10, intensity: .easy)
            ]
        ),
        template(
            29,
            title: "Threshold 5 × 5 min",
            type: .threshold,
            summary: "Five five-minute threshold efforts with ninety seconds easy.",
            blocks: [
                timeBlock(.warmup, "Warm-up", minutes: 15, intensity: .easy),
                timeBlock(.work, "Threshold", minutes: 5, intensity: rpe(8), repetitions: 5, recoverySeconds: 90),
                timeBlock(.cooldown, "Cool-down", minutes: 10, intensity: .easy)
            ]
        ),
        template(
            30,
            title: "8 × 200 m",
            type: .intervals,
            summary: "Eight quick 200 m repetitions with short jogging recovery.",
            blocks: [
                timeBlock(.warmup, "Warm-up", minutes: 12, intensity: .easy),
                distanceBlock(.work, "200 m repeats", meters: 200, intensity: rpe(8.5), repetitions: 8, recoveryMeters: 200),
                timeBlock(.cooldown, "Cool-down", minutes: 10, intensity: .easy)
            ]
        ),
        template(
            31,
            title: "10 × 400 m",
            type: .intervals,
            summary: "Ten 400 m repetitions with controlled recovery.",
            blocks: [
                timeBlock(.warmup, "Warm-up", minutes: 15, intensity: .easy),
                distanceBlock(.work, "400 m repeats", meters: 400, intensity: rpe(8.5), repetitions: 10, recoverySeconds: 90),
                timeBlock(.cooldown, "Cool-down", minutes: 10, intensity: .easy)
            ]
        ),
        template(
            32,
            title: "5 × 800 m",
            type: .intervals,
            summary: "Five 800 m intervals at a strong controlled effort.",
            blocks: [
                timeBlock(.warmup, "Warm-up", minutes: 15, intensity: .easy),
                distanceBlock(.work, "800 m repeats", meters: 800, intensity: rpe(8.5), repetitions: 5, recoverySeconds: 120),
                timeBlock(.cooldown, "Cool-down", minutes: 10, intensity: .easy)
            ]
        ),
        template(
            33,
            title: "6 × 800 m",
            type: .intervals,
            summary: "Six 800 m repetitions with two minutes easy recovery.",
            blocks: [
                timeBlock(.warmup, "Warm-up", minutes: 15, intensity: .easy),
                distanceBlock(.work, "800 m repeats", meters: 800, intensity: rpe(8.5), repetitions: 6, recoverySeconds: 120),
                timeBlock(.cooldown, "Cool-down", minutes: 10, intensity: .easy)
            ]
        ),
        template(
            34,
            title: "12 × 1 min",
            type: .intervals,
            summary: "Twelve one-minute hard efforts with one minute easy between.",
            blocks: [
                timeBlock(.warmup, "Warm-up", minutes: 12, intensity: .easy),
                timeBlock(.work, "Fast reps", minutes: 1, intensity: rpe(9), repetitions: 12, recoverySeconds: 60),
                timeBlock(.cooldown, "Cool-down", minutes: 10, intensity: .easy)
            ]
        ),
        template(
            35,
            title: "8 × 2 min",
            type: .intervals,
            summary: "Eight two-minute hard repetitions with equal easy recovery.",
            blocks: [
                timeBlock(.warmup, "Warm-up", minutes: 12, intensity: .easy),
                timeBlock(.work, "Fast reps", minutes: 2, intensity: rpe(8.5), repetitions: 8, recoverySeconds: 120),
                timeBlock(.cooldown, "Cool-down", minutes: 10, intensity: .easy)
            ]
        ),
        template(
            36,
            title: "Fartlek 6 × 2",
            type: .fartlek,
            summary: "Six two-minute surges with ninety seconds relaxed running.",
            blocks: [
                timeBlock(.warmup, "Warm-up", minutes: 10, intensity: .easy),
                timeBlock(.work, "Surges", minutes: 2, intensity: rpe(8), repetitions: 6, recoverySeconds: 90),
                timeBlock(.cooldown, "Cool-down", minutes: 10, intensity: .easy)
            ]
        ),
        template(
            37,
            title: "Fartlek Ladder",
            type: .fartlek,
            summary: "A 1-2-3-4-3-2-1 minute ladder with easy running between efforts.",
            blocks: [
                timeBlock(.warmup, "Warm-up", minutes: 10, intensity: .easy),
                timeBlock(.work, "1 min fast", minutes: 1, intensity: rpe(8), recoverySeconds: 60),
                timeBlock(.work, "2 min fast", minutes: 2, intensity: rpe(8), recoverySeconds: 60),
                timeBlock(.work, "3 min fast", minutes: 3, intensity: rpe(8), recoverySeconds: 90),
                timeBlock(.work, "4 min fast", minutes: 4, intensity: rpe(8), recoverySeconds: 120),
                timeBlock(.work, "3 min fast", minutes: 3, intensity: rpe(8), recoverySeconds: 90),
                timeBlock(.work, "2 min fast", minutes: 2, intensity: rpe(8), recoverySeconds: 60),
                timeBlock(.work, "1 min fast", minutes: 1, intensity: rpe(8)),
                timeBlock(.cooldown, "Cool-down", minutes: 10, intensity: .easy)
            ]
        ),
        template(
            38,
            title: "Fartlek 5-4-3-2-1",
            type: .fartlek,
            summary: "Descending five-to-one-minute efforts with two minutes easy between.",
            blocks: [
                timeBlock(.warmup, "Warm-up", minutes: 10, intensity: .easy),
                timeBlock(.work, "5 min fast", minutes: 5, intensity: rpe(7.5), recoverySeconds: 120),
                timeBlock(.work, "4 min fast", minutes: 4, intensity: rpe(8), recoverySeconds: 120),
                timeBlock(.work, "3 min fast", minutes: 3, intensity: rpe(8), recoverySeconds: 120),
                timeBlock(.work, "2 min fast", minutes: 2, intensity: rpe(8.5), recoverySeconds: 120),
                timeBlock(.work, "1 min fast", minutes: 1, intensity: rpe(9)),
                timeBlock(.cooldown, "Cool-down", minutes: 10, intensity: .easy)
            ]
        ),
        template(
            39,
            title: "Fartlek 12 × 30 sec",
            type: .fartlek,
            summary: "Twelve short surges to add speed without a rigid interval session.",
            blocks: [
                timeBlock(.warmup, "Warm-up", minutes: 10, intensity: .easy),
                timeBlock(.work, "30 sec surge", minutes: 0.5, intensity: rpe(8.5), repetitions: 12, recoverySeconds: 60),
                timeBlock(.cooldown, "Cool-down", minutes: 10, intensity: .easy)
            ]
        ),
        template(
            40,
            title: "10 × 45 sec Hills",
            type: .hills,
            summary: "Ten compact uphill efforts with a relaxed return recovery.",
            blocks: [
                timeBlock(.warmup, "Warm-up", minutes: 15, intensity: .easy),
                timeBlock(.work, "Uphill reps", minutes: 0.75, intensity: rpe(9), repetitions: 10, recoverySeconds: 75),
                timeBlock(.cooldown, "Cool-down", minutes: 10, intensity: .easy)
            ]
        ),
        template(
            41,
            title: "6 × 90 sec Hills",
            type: .hills,
            summary: "Six longer hill repetitions at strong controlled effort.",
            blocks: [
                timeBlock(.warmup, "Warm-up", minutes: 15, intensity: .easy),
                timeBlock(.work, "Uphill reps", minutes: 1.5, intensity: rpe(8.5), repetitions: 6, recoverySeconds: 120),
                timeBlock(.cooldown, "Cool-down", minutes: 10, intensity: .easy)
            ]
        ),
        template(
            42,
            title: "Hill Pyramid",
            type: .hills,
            summary: "A varied uphill ladder from 30 to 90 seconds and back down.",
            blocks: [
                timeBlock(.warmup, "Warm-up", minutes: 15, intensity: .easy),
                timeBlock(.work, "30 sec uphill", minutes: 0.5, intensity: rpe(8), recoverySeconds: 60),
                timeBlock(.work, "45 sec uphill", minutes: 0.75, intensity: rpe(8), recoverySeconds: 75),
                timeBlock(.work, "60 sec uphill", minutes: 1, intensity: rpe(8.5), recoverySeconds: 90),
                timeBlock(.work, "90 sec uphill", minutes: 1.5, intensity: rpe(8.5), recoverySeconds: 120),
                timeBlock(.work, "60 sec uphill", minutes: 1, intensity: rpe(8.5), recoverySeconds: 90),
                timeBlock(.work, "45 sec uphill", minutes: 0.75, intensity: rpe(8), recoverySeconds: 75),
                timeBlock(.work, "30 sec uphill", minutes: 0.5, intensity: rpe(8)),
                timeBlock(.cooldown, "Cool-down", minutes: 10, intensity: .easy)
            ]
        ),
        template(
            43,
            title: "5K Pace 5 × 1 km",
            type: .racePace,
            summary: "Five one-kilometre repetitions around a strong 5K-style effort.",
            blocks: [
                timeBlock(.warmup, "Warm-up", minutes: 15, intensity: .easy),
                distanceBlock(.work, "5K effort", meters: 1_000, intensity: rpe(8.5), repetitions: 5, recoverySeconds: 120),
                timeBlock(.cooldown, "Cool-down", minutes: 10, intensity: .easy)
            ]
        ),
        template(
            44,
            title: "10K Pace 3 × 2 km",
            type: .racePace,
            summary: "Three two-kilometre blocks around a controlled 10K-style effort.",
            blocks: [
                timeBlock(.warmup, "Warm-up", minutes: 15, intensity: .easy),
                distanceBlock(.work, "10K effort", meters: 2_000, intensity: rpe(8), repetitions: 3, recoverySeconds: 180),
                timeBlock(.cooldown, "Cool-down", minutes: 10, intensity: .easy)
            ]
        ),
        template(
            45,
            title: "Half Marathon Pace 2 × 4 km",
            type: .racePace,
            summary: "Two longer blocks at a steady half-marathon-style effort.",
            blocks: [
                timeBlock(.warmup, "Warm-up", minutes: 15, intensity: .easy),
                distanceBlock(.work, "Half marathon effort", meters: 4_000, intensity: rpe(7), repetitions: 2, recoverySeconds: 180),
                timeBlock(.cooldown, "Cool-down", minutes: 10, intensity: .easy)
            ]
        ),
        template(
            46,
            title: "Marathon Pace 3 × 3 km",
            type: .racePace,
            summary: "Three three-kilometre blocks at a controlled marathon-style effort.",
            blocks: [
                timeBlock(.warmup, "Warm-up", minutes: 15, intensity: .easy),
                distanceBlock(.work, "Marathon effort", meters: 3_000, intensity: rpe(6.5), repetitions: 3, recoverySeconds: 180),
                timeBlock(.cooldown, "Cool-down", minutes: 10, intensity: .easy)
            ]
        ),
        template(
            47,
            title: "Progression 45",
            type: .progression,
            summary: "Start easy, build through a steady middle section, and finish strong.",
            blocks: [
                timeBlock(.steady, "Easy start", minutes: 15, intensity: .easy),
                timeBlock(.steady, "Steady middle", minutes: 15, intensity: rpe(5)),
                timeBlock(.work, "Strong finish", minutes: 15, intensity: rpe(7))
            ]
        ),
        template(
            48,
            title: "Progression 60",
            type: .progression,
            summary: "A one-hour progression from easy running to a controlled strong finish.",
            blocks: [
                timeBlock(.steady, "Easy start", minutes: 20, intensity: .easy),
                timeBlock(.steady, "Steady middle", minutes: 20, intensity: rpe(5.5)),
                timeBlock(.work, "Strong finish", minutes: 20, intensity: rpe(7))
            ]
        ),
        template(
            49,
            title: "Progressive 10K",
            type: .progression,
            summary: "Ten kilometres split into easy, steady and strong closing sections.",
            blocks: [
                distanceBlock(.steady, "Easy start", meters: 4_000, intensity: .easy),
                distanceBlock(.steady, "Steady middle", meters: 3_000, intensity: rpe(5.5)),
                distanceBlock(.work, "Strong finish", meters: 3_000, intensity: rpe(7))
            ]
        ),
        template(
            50,
            title: "Fast Finish Long Run 16K",
            type: .progression,
            summary: "Twelve easy kilometres followed by four kilometres at a stronger controlled effort.",
            blocks: [
                distanceBlock(.steady, "Easy long run", meters: 12_000, intensity: .easy),
                distanceBlock(.work, "Fast finish", meters: 4_000, intensity: rpe(7))
            ]
        )
    ]

}

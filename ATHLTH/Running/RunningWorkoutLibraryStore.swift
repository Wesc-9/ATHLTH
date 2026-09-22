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

    static let builtInTemplates: [RunningWorkoutTemplate] = [
        RunningWorkoutTemplate(
            id: UUID(uuidString: "A1000000-0000-0000-0000-000000000001")!,
            title: "Easy 30",
            type: .easy,
            summary: "30 minutes at a relaxed conversational effort.",
            blocks: [
                RunningWorkoutBlock(
                    kind: .steady,
                    title: "Easy running",
                    work: .time(30 * 60, intensity: .easy)
                )
            ],
            routeID: nil,
            isBuiltIn: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        ),
        RunningWorkoutTemplate(
            id: UUID(uuidString: "A1000000-0000-0000-0000-000000000002")!,
            title: "Recovery 25",
            type: .recovery,
            summary: "Short recovery run with low effort throughout.",
            blocks: [
                RunningWorkoutBlock(
                    kind: .steady,
                    title: "Recovery running",
                    work: .time(
                        25 * 60,
                        intensity: RunningIntensityTarget(
                            kind: .rpe,
                            paceMinSecondsPerKilometer: nil,
                            paceMaxSecondsPerKilometer: nil,
                            heartRateZone: nil,
                            rpe: 3
                        )
                    )
                )
            ],
            routeID: nil,
            isBuiltIn: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        ),
        RunningWorkoutTemplate(
            id: UUID(uuidString: "A1000000-0000-0000-0000-000000000003")!,
            title: "Long Run",
            type: .longRun,
            summary: "A steady long run with an easy-effort target.",
            blocks: [
                RunningWorkoutBlock(
                    kind: .steady,
                    title: "Long run",
                    work: .distance(15_000, intensity: .easy)
                )
            ],
            routeID: nil,
            isBuiltIn: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        ),
        RunningWorkoutTemplate(
            id: UUID(uuidString: "A1000000-0000-0000-0000-000000000004")!,
            title: "Tempo 3 × 10",
            type: .tempo,
            summary: "Warm-up, three controlled tempo blocks, then cool-down.",
            blocks: [
                RunningWorkoutBlock(
                    kind: .warmup,
                    title: "Warm-up",
                    work: .time(10 * 60, intensity: .easy)
                ),
                RunningWorkoutBlock(
                    kind: .work,
                    title: "Tempo",
                    repetitions: 3,
                    work: .time(
                        10 * 60,
                        intensity: RunningIntensityTarget(
                            kind: .rpe,
                            paceMinSecondsPerKilometer: nil,
                            paceMaxSecondsPerKilometer: nil,
                            heartRateZone: nil,
                            rpe: 7
                        )
                    ),
                    recovery: .time(2 * 60, intensity: .easy)
                ),
                RunningWorkoutBlock(
                    kind: .cooldown,
                    title: "Cool-down",
                    work: .time(10 * 60, intensity: .easy)
                )
            ],
            routeID: nil,
            isBuiltIn: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        ),
        RunningWorkoutTemplate(
            id: UUID(uuidString: "A1000000-0000-0000-0000-000000000005")!,
            title: "6 × 400 m",
            type: .intervals,
            summary: "Classic short intervals with jogging recovery.",
            blocks: [
                RunningWorkoutBlock(
                    kind: .warmup,
                    title: "Warm-up",
                    work: .time(12 * 60, intensity: .easy)
                ),
                RunningWorkoutBlock(
                    kind: .work,
                    title: "400 m repeats",
                    repetitions: 6,
                    work: .distance(
                        400,
                        intensity: RunningIntensityTarget(
                            kind: .rpe,
                            paceMinSecondsPerKilometer: nil,
                            paceMaxSecondsPerKilometer: nil,
                            heartRateZone: nil,
                            rpe: 8
                        )
                    ),
                    recovery: .time(90, intensity: .easy)
                ),
                RunningWorkoutBlock(
                    kind: .cooldown,
                    title: "Cool-down",
                    work: .time(10 * 60, intensity: .easy)
                )
            ],
            routeID: nil,
            isBuiltIn: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        ),
        RunningWorkoutTemplate(
            id: UUID(uuidString: "A1000000-0000-0000-0000-000000000006")!,
            title: "4 × 1 km",
            type: .threshold,
            summary: "Four kilometre repeats around threshold effort.",
            blocks: [
                RunningWorkoutBlock(
                    kind: .warmup,
                    title: "Warm-up",
                    work: .time(15 * 60, intensity: .easy)
                ),
                RunningWorkoutBlock(
                    kind: .work,
                    title: "1 km repeats",
                    repetitions: 4,
                    work: .distance(
                        1_000,
                        intensity: RunningIntensityTarget(
                            kind: .rpe,
                            paceMinSecondsPerKilometer: nil,
                            paceMaxSecondsPerKilometer: nil,
                            heartRateZone: nil,
                            rpe: 8
                        )
                    ),
                    recovery: .time(2 * 60, intensity: .easy)
                ),
                RunningWorkoutBlock(
                    kind: .cooldown,
                    title: "Cool-down",
                    work: .time(10 * 60, intensity: .easy)
                )
            ],
            routeID: nil,
            isBuiltIn: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        ),
        RunningWorkoutTemplate(
            id: UUID(uuidString: "A1000000-0000-0000-0000-000000000007")!,
            title: "Hill Repeats",
            type: .hills,
            summary: "Eight hard uphill reps with easy return recovery.",
            blocks: [
                RunningWorkoutBlock(
                    kind: .warmup,
                    title: "Warm-up",
                    work: .time(15 * 60, intensity: .easy)
                ),
                RunningWorkoutBlock(
                    kind: .work,
                    title: "Uphill reps",
                    repetitions: 8,
                    work: .time(
                        60,
                        intensity: RunningIntensityTarget(
                            kind: .rpe,
                            paceMinSecondsPerKilometer: nil,
                            paceMaxSecondsPerKilometer: nil,
                            heartRateZone: nil,
                            rpe: 9
                        )
                    ),
                    recovery: .time(90, intensity: .easy)
                ),
                RunningWorkoutBlock(
                    kind: .cooldown,
                    title: "Cool-down",
                    work: .time(10 * 60, intensity: .easy)
                )
            ],
            routeID: nil,
            isBuiltIn: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        ),
        RunningWorkoutTemplate(
            id: UUID(uuidString: "A1000000-0000-0000-0000-000000000008")!,
            title: "Fartlek 10 × 1",
            type: .fartlek,
            summary: "Ten one-minute surges with one minute easy between.",
            blocks: [
                RunningWorkoutBlock(
                    kind: .warmup,
                    title: "Warm-up",
                    work: .time(10 * 60, intensity: .easy)
                ),
                RunningWorkoutBlock(
                    kind: .work,
                    title: "Fast / easy",
                    repetitions: 10,
                    work: .time(
                        60,
                        intensity: RunningIntensityTarget(
                            kind: .rpe,
                            paceMinSecondsPerKilometer: nil,
                            paceMaxSecondsPerKilometer: nil,
                            heartRateZone: nil,
                            rpe: 8
                        )
                    ),
                    recovery: .time(60, intensity: .easy)
                ),
                RunningWorkoutBlock(
                    kind: .cooldown,
                    title: "Cool-down",
                    work: .time(10 * 60, intensity: .easy)
                )
            ],
            routeID: nil,
            isBuiltIn: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    ]
}

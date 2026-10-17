import Foundation

/// Durable last-completion receipt for strength workouts. A completed log is
/// written here before clearing its active checkpoint; after an app crash the
/// receipt is merged back into account-scoped history by workout UUID.
enum StrengthWorkoutCompletionJournal {
    private static func url(userID: UUID) throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent(
            "ATHLTH/StrengthCompletionJournal", isDirectory: true
        )
        return directory.appendingPathComponent(
            userID.uuidString.lowercased() + ".json"
        )
    }

    static func save(_ workout: StrengthWorkoutLog, userID: UUID) throws {
        guard workout.endedAt != nil else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let data = try JSONEncoder().encode(workout)
        let target = try url(userID: userID)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(
            to: target,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    static func read(userID: UUID) -> StrengthWorkoutLog? {
        guard let target = try? url(userID: userID),
              let data = try? Data(contentsOf: target),
              let workout = try? JSONDecoder().decode(
                  StrengthWorkoutLog.self, from: data
              ),
              workout.endedAt != nil else { return nil }
        return workout
    }

    static func remove(userID: UUID) {
        if let target = try? url(userID: userID) {
            try? FileManager.default.removeItem(at: target)
        }
    }
}

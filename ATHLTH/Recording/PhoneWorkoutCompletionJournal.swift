import Foundation

/// Keep the most recent completion durable until the next completion replaces it.
/// If the process ends before UserDefaults flushes, recovery merges this record
/// before deciding whether an old active checkpoint should be offered again.
enum PhoneWorkoutCompletionJournal {
    private static func url(userID: UUID) throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("ATHLTH/CompletionJournal", isDirectory: true)
        return directory.appendingPathComponent(userID.uuidString.lowercased() + ".json")
    }

    static func save(_ workout: PhoneWorkout, userID: UUID) throws {
        let data = try JSONEncoder().encode(workout)
        let target = try url(userID: userID)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func read(userID: UUID) -> PhoneWorkout? {
        guard let target = try? url(userID: userID),
              let data = try? Data(contentsOf: target),
              let workout = try? JSONDecoder().decode(PhoneWorkout.self, from: data),
              workout.end != nil else { return nil }
        return workout
    }

    static func remove(userID: UUID) {
        if let target = try? url(userID: userID) { try? FileManager.default.removeItem(at: target) }
    }
}

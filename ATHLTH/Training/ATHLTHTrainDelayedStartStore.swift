import Foundation

/// Account-scoped foreground reminder checkpoint. This stores no sensor or
/// HealthKit data and never initiates a recording on restoration.
enum ATHLTHTrainDelayedStartStore {
    struct Checkpoint: Codable, Equatable {
        let planID: UUID
        let workoutID: UUID
        let startsAt: Date
    }

    private static func key(for userID: UUID) -> String {
        "athlth.train.delayedStart.v1." + userID.uuidString
    }

    static func save(
        _ checkpoint: Checkpoint, for userID: UUID,
        defaults: UserDefaults = .standard
    ) {
        guard let data = try? JSONEncoder().encode(checkpoint) else { return }
        defaults.set(data, forKey: key(for: userID))
    }

    static func load(
        for userID: UUID, now: Date = .now,
        defaults: UserDefaults = .standard
    ) -> Checkpoint? {
        guard let data = defaults.data(forKey: key(for: userID)) else { return nil }
        guard let checkpoint = try? JSONDecoder().decode(Checkpoint.self, from: data),
              checkpoint.startsAt.timeIntervalSince(now) >= -1_800,
              checkpoint.startsAt.timeIntervalSince(now) <= 86_400
        else {
            remove(for: userID, defaults: defaults)
            return nil
        }
        return checkpoint
    }

    static func remove(
        for userID: UUID, defaults: UserDefaults = .standard
    ) {
        defaults.removeObject(forKey: key(for: userID))
    }
}

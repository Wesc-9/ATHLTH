import Foundation
import Supabase

/// Minimal account-private strength status for a second signed-in device.
/// No GPS, HealthKit samples, set notes, medical values or contacts are sent.
struct ATHLTHPrivateLiveStrengthSnapshot: Codable, Hashable, Identifiable {
    struct Exercise: Codable, Hashable, Identifiable {
        let id: UUID
        let name: String
        let completedSets: Int
        let plannedSets: Int
        let skippedSets: Int
        let isCurrent: Bool
    }

    let id: UUID
    let title: String
    let sourceDevice: String
    let startedAtEpoch: TimeInterval
    let capturedAtEpoch: TimeInterval
    let currentExercise: String?
    let currentSetNumber: Int?
    let currentSetCount: Int
    let completedSets: Int
    let totalPlannedSets: Int
    let skippedSets: Int
    let restEndsAtEpoch: TimeInterval?
    let plannedReps: Int?
    let plannedWeightKilograms: Double?
    let exercises: [Exercise]

    /// Never show a disconnected athlete as actively training indefinitely.
    func isFresh(at date: Date = .now) -> Bool {
        let age = date.timeIntervalSince1970 - capturedAtEpoch
        return age >= -10 && age < 85
    }

    @MainActor
    static func make(from store: StrengthWorkoutStore) -> Self? {
        guard let workout = store.activeWorkout else { return nil }
        let currentSet = store.currentSet
        return Self(
            id: workout.id,
            title: String(workout.title.prefix(130)),
            sourceDevice: workout.captureDevice == .appleWatch
                ? "Apple Watch" : "iPhone",
            startedAtEpoch: workout.startedAt.timeIntervalSince1970,
            capturedAtEpoch: Date().timeIntervalSince1970,
            currentExercise: store.currentExercise.map {
                String($0.exercise.name.prefix(120))
            },
            currentSetNumber: currentSet?.setNumber,
            currentSetCount: store.currentExercise?.sets.count ?? 0,
            completedSets: workout.totalCompletedSets,
            totalPlannedSets: workout.exercises.reduce(0) {
                $0 + $1.sets.count + ($1.skippedPlannedSetCount ?? 0)
            },
            skippedSets: workout.exercises.reduce(0) {
                $0 + ($1.skippedPlannedSetCount ?? 0)
            },
            restEndsAtEpoch: store.restEndsAt?.timeIntervalSince1970,
            plannedReps: currentSet?.plannedReps,
            plannedWeightKilograms: currentSet?.plannedWeightKilograms,
            exercises: workout.exercises.prefix(30).enumerated().map {
                index, entry in
                Exercise(
                    id: entry.id,
                    name: String(entry.exercise.name.prefix(120)),
                    completedSets: entry.sets.filter(\.isCompleted).count,
                    plannedSets: entry.sets.count +
                        (entry.skippedPlannedSetCount ?? 0),
                    skippedSets: entry.skippedPlannedSetCount ?? 0,
                    isCurrent: index == store.currentExerciseIndex
                )
            }
        )
    }
}

/// Same account only, optional and short-lived. The existing iPad-to-iPhone
/// workout command relay remains independent of this read-only status channel.
@MainActor
enum ATHLTHPrivateLiveStrengthStatusStore {
    private static let table = "private_active_strength_status"
    private static let preference = "sharePrivateActiveStrengthStatus"
    private static let client = SupabaseEnvironment.client

    private struct Write: Encodable {
        let user_id: UUID
        let snapshot: ATHLTHPrivateLiveStrengthSnapshot
        let updated_at: String
        let expires_at: String
    }

    private struct Read: Decodable {
        let snapshot: ATHLTHPrivateLiveStrengthSnapshot
    }

    static func isEnabled(for userID: UUID) -> Bool {
        // The user-facing iPhone/iPad companion is on by default for a
        // signed-in account. A persisted false remains an explicit opt-out.
        AccountLocalStorage.read(Bool.self, name: preference, userID: userID) ?? true
    }

    static func setEnabled(_ enabled: Bool, for userID: UUID) {
        AccountLocalStorage.write(enabled, name: preference, userID: userID)
    }

    /// Only the recording iPhone publishes. The Watch communicates with it
    /// using the existing durable Watch connectivity journal.
    static func publish(
        _ snapshot: ATHLTHPrivateLiveStrengthSnapshot?,
        userID: UUID
    ) async {
        guard !ATHLTHDeviceRole.isIPad,
              client.auth.currentUser?.id == userID else { return }

        guard isEnabled(for: userID) else {
            await clear(for: userID)
            return
        }

        guard let snapshot,
              ATHLTHCrossDeviceWorkoutStore.shared.isApprovedForSession(
                snapshot.id
              ) else {
            // Legacy status must never bypass the new per-workout opt-in.
            await clear(for: userID)
            return
        }

        let now = Date()
        let formatter = ISO8601DateFormatter()
        let update = Write(
            user_id: userID,
            snapshot: snapshot,
            updated_at: formatter.string(from: now),
            expires_at: formatter.string(from: now.addingTimeInterval(120))
        )
        do {
            try await client.from(table)
                .upsert(update, onConflict: "user_id")
                .execute()
        } catch {
            // Network outages must never prevent local workout recording.
            // A timed-out status expires automatically on the reader.
        }
    }

    static func clear(for userID: UUID) async {
        guard client.auth.currentUser?.id == userID else { return }
        do {
            try await client.from(table)
                .delete()
                .eq("user_id", value: userID)
                .execute()
        } catch {
            // The last remote status expires; never block workout completion.
        }
    }

    static func fetch(for userID: UUID) async -> ATHLTHPrivateLiveStrengthSnapshot? {
        guard client.auth.currentUser?.id == userID else { return nil }
        do {
            let rows: [Read] = try await client.from(table)
                .select("snapshot")
                .eq("user_id", value: userID)
                .limit(1)
                .execute()
                .value
            guard let snapshot = rows.first?.snapshot, snapshot.isFresh() else {
                return nil
            }
            return snapshot
        } catch {
            return nil
        }
    }
}

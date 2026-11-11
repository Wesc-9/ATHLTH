import Foundation
import SwiftUI
import Supabase

/// Read-only, owner-scoped active workout summary for a second signed-in device.
/// The recording and HealthKit ownership always remain on the source iPhone.
struct ATHLTHCrossDeviceWorkoutSnapshot: Codable, Equatable, Identifiable {
    let sessionID: UUID
    let kind: String
    let title: String
    let startedAt: Date
    let elapsedSeconds: TimeInterval
    let distanceMeters: Double?
    let currentStep: String?
    let nextStep: String?
    let completedSets: Int?
    let totalSets: Int?

    var id: UUID { sessionID }
    var symbol: String { kind == "strength" ? "dumbbell.fill" : "figure.run" }
}

private struct ATHLTHCrossDeviceWorkoutRow: Codable {
    let userID: UUID
    let snapshot: ATHLTHCrossDeviceWorkoutSnapshot
    let updatedAt: Date
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case snapshot
        case updatedAt = "updated_at"
        case expiresAt = "expires_at"
    }
}

/// Polling deliberately shares only a compact spectator state; no second
/// HKWorkoutSession, no mirrored GPS track, no public/social presence.
/// Server-side RLS additionally enforces user_id = auth.uid().
@MainActor
final class ATHLTHCrossDeviceWorkoutStore: ObservableObject {
    @Published private(set) var remote: ATHLTHCrossDeviceWorkoutSnapshot?
    @Published private(set) var isExpanded = false

    private let client = SupabaseEnvironment.client
    private var lastPublishedID: UUID?
    private var hasLoadedRemote = false
    private var foregroundedSinceLastPoll = false

    func setExpanded(_ expanded: Bool) {
        isExpanded = expanded
    }

    func didBackground() {
        foregroundedSinceLastPoll = false
        isExpanded = false
    }

    func didForeground() {
        foregroundedSinceLastPoll = true
    }

    func clearLocalState() {
        remote = nil
        lastPublishedID = nil
        hasLoadedRemote = false
        foregroundedSinceLastPoll = false
        isExpanded = false
        ATHLTHSurfaceCoordinator.setRemoteWorkout(nil)
    }

    func track(
        signedIn: Bool,
        accountID: UUID,
        phone: IPhoneWorkoutStore,
        strength: StrengthWorkoutStore
    ) async {
        guard signedIn else {
            clearLocalState()
            return
        }
        hasLoadedRemote = false
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        while !Task.isCancelled {
            // Do not trust local profile IDs as authorization: every request
            // also requires the active Supabase session to match that ID.
            if client.auth.currentUser?.id == accountID {
                if isPad {
                    await readRemote(accountID: accountID)
                } else {
                    await publishLocal(accountID: accountID, phone: phone, strength: strength)
                }
            } else {
                remote = nil
                ATHLTHSurfaceCoordinator.setRemoteWorkout(nil)
            }

            do {
                try await Task.sleep(for: .seconds(4))
            } catch {
                break
            }
        }
    }

    private func liveSnapshot(
        phone: IPhoneWorkoutStore,
        strength: StrengthWorkoutStore
    ) -> ATHLTHCrossDeviceWorkoutSnapshot? {
        if let log = strength.activeWorkout {
            let exercise = strength.currentExerciseIndex
            let activeName = log.exercises.indices.contains(exercise)
                ? log.exercises[exercise].exercise.displayName
                : nil
            return ATHLTHCrossDeviceWorkoutSnapshot(
                sessionID: log.id,
                kind: "strength",
                title: log.title,
                startedAt: log.startedAt,
                elapsedSeconds: max(0, Date().timeIntervalSince(log.startedAt)),
                distanceMeters: nil,
                currentStep: activeName,
                nextStep: nil,
                completedSets: log.totalCompletedSets,
                totalSets: log.exercises.reduce(0) { $0 + $1.sets.count }
            )
        }
        if let run = phone.active, !run.walking {
            let index = run.structuredStepIndex ?? 0
            let steps = run.structuredRunningWorkout?.steps ?? []
            return ATHLTHCrossDeviceWorkoutSnapshot(
                sessionID: run.id,
                kind: "running",
                title: run.title,
                startedAt: run.start,
                elapsedSeconds: max(0, run.elapsed(at: Date())),
                distanceMeters: run.distanceMeters.isFinite
                    ? max(0, run.distanceMeters) : nil,
                currentStep: steps.indices.contains(index)
                    ? steps[index].title : nil,
                nextStep: steps.indices.contains(index + 1)
                    ? steps[index + 1].title : nil,
                completedSets: nil,
                totalSets: nil
            )
        }
        return nil
    }

    private func publishLocal(
        accountID: UUID,
        phone: IPhoneWorkoutStore,
        strength: StrengthWorkoutStore
    ) async {
        let active = liveSnapshot(phone: phone, strength: strength)
        if let active {
            let now = Date()
            let row = ATHLTHCrossDeviceWorkoutRow(
                userID: accountID,
                snapshot: active,
                updatedAt: now,
                expiresAt: now.addingTimeInterval(30)
            )
            do {
                try await client.from("private_active_workout_status")
                    .upsert(row, onConflict: "user_id")
                    .execute()
                lastPublishedID = active.id
            } catch {
                // Never interrupt a locally recorded workout for spectator sync.
            }
        } else if lastPublishedID != nil {
            do {
                try await client.from("private_active_workout_status")
                    .delete()
                    .eq("user_id", value: accountID)
                    .execute()
                lastPublishedID = nil
            } catch {
                // TTL clears an abandoned session when the network returns.
            }
        }
    }

    private func readRemote(accountID: UUID) async {
        do {
            let rows: [ATHLTHCrossDeviceWorkoutRow] = try await client
                .from("private_active_workout_status")
                .select()
                .eq("user_id", value: accountID)
                .limit(1)
                .execute()
                .value
            let row = rows.first
            let next = row.flatMap {
                $0.expiresAt > Date() ? $0.snapshot : nil
            }
            let previous = remote?.id
            if previous != next?.id {
                if hasLoadedRemote && foregroundedSinceLastPoll && next != nil {
                    isExpanded = true
                } else {
                    isExpanded = false
                }
            }
            remote = next
            hasLoadedRemote = true
            ATHLTHSurfaceCoordinator.setRemoteWorkout(next.map {
                ATHLTHSurfaceWorkoutSnapshot(
                    title: $0.title,
                    systemImage: $0.symbol,
                    state: $0.kind == "strength" ? "remote_strength" : "running",
                    startedAt: $0.startedAt,
                    elapsedTime: $0.elapsedSeconds,
                    distanceMeters: $0.distanceMeters ?? 0,
                    heartRate: 0,
                    updatedAt: row?.updatedAt ?? .now
                )
            })
        } catch {
            // Keep the last short-lived state while temporarily offline,
            // but do not present a false permanently active workout.
            hasLoadedRemote = true
        }
    }
}

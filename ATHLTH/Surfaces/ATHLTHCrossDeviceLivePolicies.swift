import Foundation
import SwiftUI
import Supabase

/// A reconnecting iPad must not render stale, wrong-account or expired
/// workout telemetry. The iPad remains read-only and never opens HealthKit.
/// Legacy snapshots without capturedAt use the server row heartbeat.
enum ATHLTHCrossDeviceLiveReadPolicy {
    static func accepts(
        _ snapshot: ATHLTHCrossDeviceWorkoutSnapshot,
        updatedAt: Date,
        expiresAt: Date,
        at now: Date = Date()
    ) -> Bool {
        let rowAge = now.timeIntervalSince(updatedAt)
        let sampleAge = now.timeIntervalSince(snapshot.capturedAt ?? updatedAt)
        let startAge = now.timeIntervalSince(snapshot.startedAt)
        return expiresAt > now &&
            rowAge >= -10 && rowAge <= 35 &&
            sampleAge >= -10 && sampleAge <= 35 &&
            startAge >= -10 &&
            snapshot.elapsedSeconds.isFinite &&
            snapshot.elapsedSeconds >= 0 &&
            // An original source may be paused for a long time, but active
            // workout duration must never exceed wall-clock time. Reject
            // corrupted/incorrectly decoded values before they reach iPad.
            snapshot.elapsedSeconds <= max(0, startAge) + 120 &&
            snapshot.elapsedSeconds <= 366 * 86_400
    }
}

/// A valid row can arrive out of order after a reconnect. Keep the last
/// verified frame only while its own lease remains fresh; after expiry,
/// clear the display rather than rewinding an old session by accepting an
/// older but newly re-heartbeated database row.
enum ATHLTHCrossDeviceSnapshotOrderPolicy {
    enum Decision: Equatable {
        case acceptIncoming, keepCurrent, clearExpired
    }

    static func decision(
        current: ATHLTHCrossDeviceWorkoutSnapshot?,
        incoming: ATHLTHCrossDeviceWorkoutSnapshot?,
        currentExpiry: Date?,
        at now: Date = Date()
    ) -> Decision {
        guard let current, let incoming,
              current.sessionID == incoming.sessionID,
              let previousTime = current.capturedAt,
              let incomingTime = incoming.capturedAt,
              incomingTime < previousTime else {
            return .acceptIncoming
        }
        guard let currentExpiry, currentExpiry > now,
              now.timeIntervalSince(previousTime) <= 35 else {
            return .clearExpired
        }
        return .keepCurrent
    }
}

/// A pending iPad access request has its own local expiry independent of
/// network callbacks. The offline spectator must never show "waiting" forever
/// when its original source-session request has expired.
enum ATHLTHiPadLiveRequestExpiryPolicy {
    static func isExpired(
        state: ATHLTHLiveViewRequestState,
        expiry: Date?,
        at now: Date = Date()
    ) -> Bool {
        guard state == .pending || state == .sending,
              let expiry,
              expiry.timeIntervalSince1970.isFinite,
              now.timeIntervalSince1970.isFinite else { return false }
        return now >= expiry
    }
}

/// Stage Manager may create one AppRoot .task per scene. The account's
/// spectator status is a shared store, so concurrent scene pollers must not
/// race to publish or clear the same status row. Waiting scenes take over
/// after the owner task is canceled, without canceling each other's work.
struct ATHLTHCrossDevicePollingLease {
    private(set) var ownerToken: UUID?

    mutating func claim(_ token: UUID) -> Bool {
        if ownerToken == nil { ownerToken = token }
        return ownerToken == token
    }

    mutating func release(_ token: UUID) {
        if ownerToken == token { ownerToken = nil }
    }

    mutating func reset() {
        ownerToken = nil
    }
}

/// Only display state belongs to a Stage Manager window. Permission and
/// verified workout snapshots remain in ATHLTHCrossDeviceWorkoutStore.shared.
struct ATHLTHiPadSceneLivePresentationState: Equatable {
    private(set) var lastSeenSessionID: UUID?
    private(set) var minimizedSessionID: UUID?
    private(set) var isExpanded = false

    mutating func receive(
        sessionID: UUID?,
        autoExpand: Bool
    ) {
        // An intermittent network gap must not reset a deliberate minimize.
        guard let sessionID, lastSeenSessionID != sessionID else { return }
        lastSeenSessionID = sessionID
        isExpanded = autoExpand && minimizedSessionID != sessionID
    }

    mutating func expand(sessionID: UUID?) {
        guard let sessionID else { return }
        lastSeenSessionID = sessionID
        minimizedSessionID = nil
        isExpanded = true
    }

    mutating func minimize(sessionID: UUID?) {
        isExpanded = false
        if let sessionID {
            lastSeenSessionID = sessionID
            minimizedSessionID = sessionID
        }
    }

    mutating func resetForAccountChange() {
        lastSeenSessionID = nil
        minimizedSessionID = nil
        isExpanded = false
    }
}

/// Each AppRootView owns an instance; opening and minimizing one window
/// cannot present/dismiss another window's SwiftUI fullScreenCover.
@MainActor
final class ATHLTHiPadLiveScenePresentation: ObservableObject {
    @Published private(set) var state = ATHLTHiPadSceneLivePresentationState()

    var isExpanded: Bool { state.isExpanded }

    func receive(sessionID: UUID?, autoExpand: Bool) {
        state.receive(sessionID: sessionID, autoExpand: autoExpand)
    }

    func expand(sessionID: UUID?) {
        state.expand(sessionID: sessionID)
    }

    func minimize(sessionID: UUID?) {
        state.minimize(sessionID: sessionID)
    }

    func resetForAccountChange() {
        state.resetForAccountChange()
    }
}

enum ATHLTHCrossDevicePresenceRefreshPolicy {
    static func needsWrite(sessionID: UUID, source: String, previousSessionID: UUID?,
                           previousSource: String?, previousWrite: Date?, now: Date) -> Bool {
        guard sessionID == previousSessionID, source == previousSource,
              let previousWrite else { return true }
        return !(0..<12).contains(now.timeIntervalSince(previousWrite))
    }
}

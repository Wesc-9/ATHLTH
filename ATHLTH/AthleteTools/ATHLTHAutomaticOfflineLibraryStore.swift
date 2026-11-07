import Foundation
import Network
import SwiftUI

/// Automatically protects ordinary saved plans without an "offline pack"
/// button. Original plans, workouts and routes remain in AppSessionStore's
/// account-local journal. This cache only adds optional static map previews
/// and downloaded exercise illustrations.
enum ATHLTHOfflineLibraryPreparationPolicy {
    static func routeIDs(in plan: TrainingPlan) -> Set<UUID> {
        let sessions = plan.weeks.flatMap(\.days).flatMap(\.sessions)
        return Set(
            sessions.compactMap(\.routeID) +
            sessions.compactMap { $0.runningWorkout?.routeID } +
            sessions.flatMap { $0.runningWorkouts ?? [] }.compactMap(\.routeID)
        )
    }

    static func relatedRoutes(
        for plan: TrainingPlan, from routes: [TrainingRoute]
    ) -> [TrainingRoute] {
        let referenced = routeIDs(in: plan)
        return routes.filter { referenced.contains($0.id) }
    }

    static func needsLocalSnapshot(
        plan: TrainingPlan, routes: [TrainingRoute],
        existing: AthleteOfflinePack?
    ) -> Bool {
        guard let existing else { return true }
        let encoder = JSONEncoder()
        // Dictionary keys otherwise may encode in a different order and
        // repeatedly invalidate a perfectly good offline snapshot.
        encoder.outputFormatting = [.sortedKeys]
        // Codable equality also detects nested workout target and route
        // changes, not merely the plan title/date.
        guard let planned = try? encoder.encode(plan),
              let stored = try? encoder.encode(existing.plan),
              let related = try? encoder.encode(
                relatedRoutes(for: plan, from: routes)
              ),
              let storedRoutes = try? encoder.encode(existing.routes)
        else { return true }
        return planned != stored || related != storedRoutes
    }

    static func needsMedia(
        plan: TrainingPlan, routes: [TrainingRoute],
        existing: AthleteOfflinePack?
    ) -> Bool {
        guard let existing else { return true }
        let mapIDs = Set(relatedRoutes(for: plan, from: routes)
            .filter { $0.coordinates.count >= 2 }.map(\.id))
        let sessions = plan.weeks.flatMap(\.days).flatMap(\.sessions)
        let images = Set(sessions.flatMap(\.exercises)
            .filter { $0.embeddedExercise.imageURL?.scheme == "https" }
            .map(\.id))
        return !mapIDs.isSubset(of: Set(existing.mapRouteIDs)) ||
            !images.isSubset(of: Set(existing.exerciseImageIDs))
    }

    static func canRetryMedia(
        lastAttempt: Date?, now: Date, retryAfter: TimeInterval = 15 * 60
    ) -> Bool {
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= retryAfter
    }
}

/// Background-safe, account-isolated incremental *asset* preparation.
/// Local workout data never waits for this service or for network availability.
@MainActor
final class ATHLTHAutomaticOfflineLibraryStore: ObservableObject {
    private let packs = AthleteOfflinePackStore()
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(
        label: "com.athlth.offline-library.network"
    )
    private var isUnmeteredOnline = false
    private var isOnline = false
    private var signedInAccountID: UUID?
    private var latestPlans: [TrainingPlan] = []
    private var latestRoutes: [TrainingRoute] = []
    private var active = false
    private var work: Task<Void, Never>?
    private var lastMediaAttemptByPlan: [UUID: Date] = [:]

    init() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            let unmetered = connected &&
                !path.isExpensive && !path.isConstrained
            Task { @MainActor [weak self] in
                guard let self else { return }
                let reconnected = connected && !self.isOnline
                let mediaChanged = self.isUnmeteredOnline != unmetered
                self.isOnline = connected
                self.isUnmeteredOnline = unmetered
                if mediaChanged && unmetered { self.schedule() }
                if reconnected {
                    // Reuse the app's opt-in sync engines. This never
                    // uploads training data unless user consent exists.
                    NotificationCenter.default.post(
                        name: .athlthNetworkConnectivityRestored,
                        object: nil
                    )
                }
            }
        }
        networkMonitor.start(queue: networkQueue)
    }

    deinit {
        networkMonitor.cancel()
    }

    func update(
        userID: UUID?, plans: [TrainingPlan], routes: [TrainingRoute],
        isForeground: Bool
    ) {
        if signedInAccountID != userID {
            work?.cancel()
            work = nil
            signedInAccountID = userID
            lastMediaAttemptByPlan = [:]
            if let userID {
                packs.load(userID: userID)
            } else {
                packs.clearActiveAccount()
            }
        }
        latestPlans = userID == nil ? [] : plans
        latestRoutes = userID == nil ? [] : routes
        active = userID != nil && isForeground
        if active {
            schedule()
        } else {
            work?.cancel()
            work = nil
        }
    }

    private func schedule() {
        guard active, signedInAccountID != nil else { return }
        work?.cancel()
        work = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(550))
            } catch { return }
            guard let self else { return }
            await self.prepareCurrentLibrary()
        }
    }

    private func prepareCurrentLibrary() async {
        guard active, let accountID = signedInAccountID else { return }
        let plans = latestPlans
        let routes = latestRoutes
        for plan in plans {
            guard !Task.isCancelled, active,
                  signedInAccountID == accountID else { return }
            let stored = packs.packs.first { $0.id == plan.id }
            if ATHLTHOfflineLibraryPreparationPolicy.needsLocalSnapshot(
                plan: plan, routes: routes, existing: stored
            ) {
                // First persist JSON plus referenced route coordinates.
                // A disconnected save must not touch the network.
                await packs.download(
                    plan: plan, routes: routes, userID: accountID,
                    includeMedia: false
                )
            }
            guard !Task.isCancelled, active,
                  signedInAccountID == accountID,
                  isUnmeteredOnline else { continue }
            let current = packs.packs.first { $0.id == plan.id }
            guard ATHLTHOfflineLibraryPreparationPolicy.needsMedia(
                plan: plan, routes: routes, existing: current
            ),
                  ATHLTHOfflineLibraryPreparationPolicy.canRetryMedia(
                    lastAttempt: lastMediaAttemptByPlan[plan.id], now: Date()
                  )
            else { continue }
            lastMediaAttemptByPlan[plan.id] = Date()
            await packs.download(
                plan: plan, routes: routes, userID: accountID,
                includeMedia: true
            )
        }
        work = nil
    }
}

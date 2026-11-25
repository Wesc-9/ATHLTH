#if ATHLTH_GARMIN_PERSONAL && (DEBUG || ATHLTH_GARMIN_INTERNAL_TEST)
import Foundation
import SwiftUI

/// Account-scoped, device-memory-only Garmin cache. Never inject this into
/// HealthKitManager, social publishing, workout backups, analytics or Coach.
@MainActor
final class GarminPersonalLocalStore: ObservableObject {
    static let shared = GarminPersonalLocalStore()
    @Published private(set) var accountID: UUID?
    @Published private(set) var connected = false
    @Published private(set) var needsKeyRemoval = false
    @Published private(set) var displayPreference: WearableDisplayPreference = .automatic
    @Published private var metricPreferences: [String: String] = [:]
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    struct SyncEvent: Identifiable {
        let id = UUID()
        let date = Date()
        let success: Bool
        let message: String
    }
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var syncEvents: [SyncEvent] = []
    @Published private var preview: GarminPersonalPreview?
    private var generation = UUID()
    private var job: Task<Void, Never>?
    private var client: GarminPersonalClient?
    private var lastAttempt: Date?

    private init() {}

    func activate(account: UUID?) {
        guard account != accountID else { return }
        reset()
        accountID = account
        displayPreference = account.flatMap {
            UserDefaults.standard.string(forKey: preferenceKey($0))
                .flatMap(WearableDisplayPreference.init(rawValue:))
        } ?? .automatic
        metricPreferences = account.flatMap {
            UserDefaults.standard.dictionary(forKey: preferenceKey($0) + ".metrics") as? [String: String]
        } ?? [:]
        if let account {
            do { connected = try GarminPersonalKeychain.read(account) != nil }
            catch { message = "Unable to access the local Keychain." }
        }
    }

    private func preferenceKey(_ account: UUID) -> String {
        "garmin.private.displayPreference." + account.uuidString
    }
    func preference(for account: UUID) -> WearableDisplayPreference {
        accountID == account ? displayPreference : .automatic
    }
    func setPreference(_ value: WearableDisplayPreference, account: UUID) {
        guard accountID == account else { return }
        displayPreference = value
        UserDefaults.standard.set(value.rawValue, forKey: preferenceKey(account))
    }

    func preference(for metric: WearableDisplayMetric, account: UUID) -> WearableDisplayPreference {
        guard accountID == account else { return .automatic }
        return metricPreferences[metric.rawValue].flatMap(WearableDisplayPreference.init(rawValue:))
            ?? displayPreference
    }

    func setPreference(_ value: WearableDisplayPreference, metric: WearableDisplayMetric, account: UUID) {
        guard accountID == account else { return }
        metricPreferences[metric.rawValue] = value.rawValue
        UserDefaults.standard.set(metricPreferences, forKey: preferenceKey(account) + ".metrics")
    }

    func isConnected(to account: UUID) -> Bool {
        accountID == account && connected
    }

    func snapshot(for account: UUID) -> GarminPersonalPreview? {
        accountID == account && connected ? preview : nil
    }

    func connect(_ key: String, account: UUID) {
        guard accountID == account, !busy, !needsKeyRemoval else { return }
        begin(account: account, key: key, replaceKey: true)
    }

    func refresh(account: UUID, force: Bool = false) {
        guard accountID == account, !busy, connected else { return }
        if !force, let lastAttempt, Date().timeIntervalSince(lastAttempt) < 300 { return }
        do {
            guard let key = try GarminPersonalKeychain.read(account) else {
                reset()
                return
            }
            begin(account: account, key: key, replaceKey: false)
        } catch { message = "Unable to access the local Keychain." }
    }

    func disconnect(account: UUID) {
        guard accountID == account else { return }
        reset()
        do {
            try GarminPersonalKeychain.remove(account)
            message = "Local key and cached Garmin data removed. Revoke the key at Garmin if needed."
        } catch {
            // Keep a visible retry action, but never resume sync in this session.
            needsKeyRemoval = true
            message = "Local data cleared, but key removal failed. Retry disconnect or revoke at Garmin."
        }
    }

    private func reset() {
        generation = UUID()
        job?.cancel()
        client?.close()
        job = nil
        client = nil
        connected = false
        needsKeyRemoval = false
        busy = false
        preview = nil
        lastAttempt = nil
        lastRefresh = nil
        syncEvents = []
        message = nil
    }

    private func recordSync(success: Bool, message: String) {
        syncEvents.insert(.init(success: success, message: message), at: 0)
        if syncEvents.count > 20 { syncEvents.removeLast(syncEvents.count - 20) }
    }

    private func begin(account: UUID, key: String, replaceKey: Bool) {
        generation = UUID()
        let requestID = generation
        let api = GarminPersonalClient()
        client = api
        busy = true
        message = nil
        lastAttempt = Date()
        job = Task { @MainActor [weak self] in
            defer { api.close() }
            do {
                let result = try await api.preview(key: key)
                try Task.checkCancellation()
                guard let self, self.accountID == account, self.generation == requestID else { return }
                if replaceKey { try GarminPersonalKeychain.save(key, account: account) }
                self.connected = true
                self.preview = result
                self.lastRefresh = Date()
                self.message = "Garmin data refreshed locally."
                self.recordSync(success: true, message: ATHLTHLocalization.choose(english: "Data refreshed", norwegian: "Data oppdatert"))
            } catch {
                guard let self, self.accountID == account, self.generation == requestID,
                      !Task.isCancelled else { return }
                switch error as? GarminPersonalClientError {
                case .some(.unauthorized):
                    self.preview = nil
                    self.lastRefresh = nil
                    self.message = "Garmin rejected access. Replace or revoke your key."
                case .some(.throttled):
                    self.message = "Garmin rate limit reached. Try again later."
                default:
                    self.message = "Garmin refresh failed. Check your connection or key."
                }
                self.recordSync(success: false, message: ATHLTHLocalization.choose(english: "Refresh failed", norwegian: "Oppdatering mislyktes"))
            }
            guard let self, self.accountID == account, self.generation == requestID else { return }
            self.busy = false
            self.client = nil
            self.job = nil
        }
    }
}

/// Invalidate on sign-out/account switch; suspend the cached preview and in-flight
/// work on lock/background. Only the explicitly saved, local key survives.
@MainActor
struct GarminPersonalAccountBoundary: View {
    @EnvironmentObject private var session: AppSessionStore
    @Environment(\.scenePhase) private var scenePhase
    private var account: UUID? {
        scenePhase == .active && session.signedIn && !session.previewModeEnabled &&
            session.currentRole.canAccessControlCenter
            ? session.profile.userID : nil
    }
    var body: some View {
        Color.clear
            .onChange(of: account, initial: true) { _, account in
                GarminPersonalLocalStore.shared.activate(account: account)
            }
            .onDisappear { GarminPersonalLocalStore.shared.activate(account: nil) }
    }
}
#endif

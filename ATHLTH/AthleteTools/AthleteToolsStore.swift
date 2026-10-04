import Combine
import Foundation
import UserNotifications

@MainActor
final class AthleteToolsStore: ObservableObject {
    static let shared = AthleteToolsStore()
    @Published var data = AthleteToolsData() { didSet { persist() } }
    @Published private(set) var cycleEntries: [AthleteCycleEntry] = []
    @Published private(set) var userID: UUID?
    @Published var error: String?
    @Published private(set) var fuelEndsAt: Date?
    private var restoring = false
    private var cycleReady = false
    private var checkingGear = false
    private var checkingLoad = false

    func switchAccount(_ id: UUID?) async {
        guard userID != id else { return }
        let oldID = userID
        restoring = true
        userID = id
        data = AthleteToolsData()
        cycleEntries = []
        cycleReady = false
        fuelEndsAt = nil
        error = nil
        if let id {
            data = AccountLocalStorage.read(AthleteToolsData.self, name: "athleteTools", userID: id) ?? AthleteToolsData()
            do {
                let file = try cycleFile(for: id)
                if FileManager.default.fileExists(atPath: file.path) {
                    cycleEntries = try JSONDecoder().decode([AthleteCycleEntry].self, from: Data(contentsOf: file))
                }
                cycleReady = true
            } catch { self.error = "Unable to open the private diary. Existing data has been preserved." }
        }
        restoring = false
        if let oldID { await cancelNotifications(for: oldID) }
    }

    private func persist() {
        guard !restoring, let userID else { return }
        AccountLocalStorage.write(data, name: "athleteTools", userID: userID)
    }

    private func cycleFile(for id: UUID) throws -> URL {
        var folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("PrivateAthleteDiary", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                               attributes: [.protectionKey: FileProtectionType.complete])
        var attributes = URLResourceValues()
        attributes.isExcludedFromBackup = true
        try folder.setResourceValues(attributes)
        return folder.appendingPathComponent(id.uuidString + ".json")
    }
    func replaceCycleEntries(_ entries: [AthleteCycleEntry]) {
        guard let userID, cycleReady else { error = "Unlock the device and reopen the diary before saving. Existing entries have been preserved."; return }
        guard entries.allSatisfy({ (1...5).contains($0.energy) && $0.symptoms.count <= 2000 && $0.notes.count <= 2000 }) else { return }
        do {
            let file = try cycleFile(for: userID)
            try JSONEncoder().encode(entries).write(to: file, options: [.atomic, .completeFileProtection])
            cycleEntries = entries.sorted { $0.date > $1.date }
        } catch { self.error = "The private diary could not be saved. Try again after unlocking the device." }
    }

    func requestNotifications() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            if !granted { error = "Notifications are disabled. Enable them in iOS Settings to receive reminders." }
            return granted
        } catch { self.error = error.localizedDescription; return false }
    }

    private func prefix(for id: UUID) -> String { "athlete-tools.\(id.uuidString)." }
    private func cancelNotifications(for id: UUID, category: String? = nil) async {
        let center = UNUserNotificationCenter.current()
        let prefix = prefix(for: id) + (category ?? "")
        let requests = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: requests.filter { $0.identifier.hasPrefix(prefix) }.map(\.identifier))
        let delivered = await center.deliveredNotifications()
        center.removeDeliveredNotifications(withIdentifiers: delivered.filter { $0.request.identifier.hasPrefix(prefix) }.map { $0.request.identifier })
    }
    func stopFuelReminders() async {
        guard let id = userID else { return }
        fuelEndsAt = nil
        await cancelNotifications(for: id, category: "fuel.")
    }
    func startFuelReminders(at start: Date) async {
        guard let id = userID, data.fuel.valid, await requestNotifications(), userID == id else { return }
        await stopFuelReminders()
        guard userID == id else { return }
        let plan = data.fuel
        let center = UNUserNotificationCenter.current()
        let existing = await center.pendingNotificationRequests()
        guard existing.count + plan.reminderOffsets.count <= 60 else {
            error = "Too many reminders are already scheduled. Stop another reminder plan or increase this interval."
            return
        }
        do {
            for offset in plan.reminderOffsets {
                guard userID == id else { await cancelNotifications(for: id, category: "fuel."); return }
                let content = UNMutableNotificationContent()
                content.title = "ATHLTH · Fuel reminder"
                content.body = String(format: "Your plan: %.0f g carbohydrate and %.0f ml fluid. Adjust to your needs.", plan.gramsPerReminder, plan.fluidPerReminder)
                content.sound = .default
                let fire = start.addingTimeInterval(Double(offset) * 60)
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, fire.timeIntervalSinceNow), repeats: false)
                try await center.add(UNNotificationRequest(identifier: prefix(for: id) + "fuel.\(offset)", content: content, trigger: trigger))
            }
            guard userID == id else { await cancelNotifications(for: id, category: "fuel."); return }
            fuelEndsAt = start.addingTimeInterval(Double(plan.durationMinutes) * 60)
        } catch {
            await cancelNotifications(for: id, category: "fuel.")
            self.error = "Reminders could not be scheduled. No partial plan was kept."
        }
    }

    func checkLoad(_ assessment: AthleteLoadAssessment) async {
        guard !checkingLoad else { return }
        checkingLoad = true; defer { checkingLoad = false }
        guard let id = userID, data.loadNotifications, assessment.shouldWarn,
              data.lastLoadWarning.map({ Date().timeIntervalSince($0) > 7 * 86_400 }) ?? true else { return }
        do {
            try await notify(id: id, category: "load", title: "Review your training load", body: "Your recent load is above your baseline. Open Athlete Tools to review the data and recovery context.")
            guard userID == id else { return }
            data.lastLoadWarning = Date()
        } catch { self.error = "The training-load notification could not be scheduled." }
    }
    func checkGear(_ gear: ProfileGearStore) async {
        guard !checkingGear else { return }
        checkingGear = true; defer { checkingGear = false }
        guard let id = userID else { return }
        for item in gear.items where item.userID == id {
            guard var rule = data.gearRules[item.id], rule.notifications, !rule.notified,
                  rule.intervalKM > 0, rule.remaining(at: gear.usageStats(for: item).totalDistanceMeters / 1000) <= 0 else { continue }
            do {
                try await notify(id: id, category: "gear.\(item.id.uuidString)", title: "Gear maintenance due", body: "\(item.name) has reached your selected service interval.")
                guard userID == id else { return }
                rule.notified = true
                data.gearRules[item.id] = rule
            } catch { self.error = "The gear-maintenance notification could not be scheduled." }
        }
    }
    private func notify(id: UUID, category: String, title: String, body: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body; content.sound = .default
        let identifier = prefix(for: id) + category
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
        if userID != id { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier]) }
    }
}

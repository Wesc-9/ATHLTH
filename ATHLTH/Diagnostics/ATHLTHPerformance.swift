import Foundation
import os
import MetricKit

enum ATHLTHPerformance {
    private static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "com.wesc9.athlth",
        category: "Performance"
    )

    static func begin(
        _ name: StaticString
    ) -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(
            .begin,
            log: log,
            name: name,
            signpostID: id
        )
        return id
    }

    static func end(
        _ name: StaticString,
        id: OSSignpostID
    ) {
        os_signpost(
            .end,
            log: log,
            name: name,
            signpostID: id
        )
    }

    static func event(
        _ name: StaticString
    ) {
        os_signpost(
            .event,
            log: log,
            name: name
        )
    }
}


/// A view-local, single-entry memo. It does not publish observable changes,
/// retain historical accounts or use a global cache. Keys must include every
/// input affecting the pure projection, including nil results.
final class ATHLTHProjectionMemo<Key: Equatable, Value> {
    private var entry: (key: Key, value: Value)?

    func value(for key: Key, compute: () -> Value) -> Value {
        if let entry, entry.key == key { return entry.value }
        let result = compute()
        entry = (key, result)
        return result
    }

    func clear() { entry = nil }
}

/// Small, owner-local LRU for pure UI projections. No published state,
/// no task scheduling, no global account data. Call on the owning actor.
/// Keys must capture all inputs; clear on account/data revision changes.
final class ATHLTHBoundedProjectionMemo<Key: Equatable, Value> {
    private let capacity: Int
    private var entries: [(key: Key, value: Value)] = []

    init(capacity: Int) { self.capacity = max(1, capacity) }

    func cachedValue(for key: Key) -> Value? {
        guard let index = entries.firstIndex(where: { $0.key == key }) else { return nil }
        let entry = entries.remove(at: index)
        entries.append(entry)
        return entry.value
    }

    func insert(_ value: Value, for key: Key) {
        entries.removeAll { $0.key == key }
        entries.append((key, value))
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
    }

    func value(for key: Key, compute: () -> Value) -> Value {
        if let value = cachedValue(for: key) { return value }
        let value = compute()
        insert(value, for: key)
        return value
    }

    func clear() { entries.removeAll(keepingCapacity: true) }
}


/// One shared request per resource and account. Callers arriving during an
/// in-flight read await that read, even when they request a forced refresh.
/// Failed/cancelled reads never advance the successful freshness timestamp.
/// The owning store must reset on account changes.
@MainActor
final class ATHLTHRefreshCoalescer {
    private var pending: (id: UUID, task: Task<Bool, Never>)?
    private var lastSuccess: Date?

    func run(maxAge: TimeInterval, force: Bool = false,
             work: @escaping @MainActor () async -> Bool) async {
        guard !Task.isCancelled else { return }
        if let pending {
            _ = await pending.task.value
            return
        }
        if !force, let lastSuccess {
            let age = Date().timeIntervalSince(lastSuccess)
            if age >= 0 && age < maxAge { return }
        }
        let id = UUID()
        let task = Task { @MainActor in
            guard !Task.isCancelled else { return false }
            return await work()
        }
        pending = (id, task)
        let succeeded = await task.value
        guard pending?.id == id else { return }
        pending = nil
        if succeeded && !task.isCancelled { lastSuccess = Date() }
    }

    func reset() {
        pending?.task.cancel()
        pending = nil
        lastSuccess = nil
    }
}


/// Owner-local change detection for derived view state. Unlike endpoint or
/// count signatures, equal-length edits to the middle of a collection are
/// observed. Updating the gate itself does not publish SwiftUI changes.
final class ATHLTHProjectionChangeGate<Key: Equatable> {
    private var last: Key?

    func changed(_ key: Key) -> Bool {
        if let last, last == key { return false }
        last = key
        return true
    }

    func reset() { last = nil }
}


/// Read the system only at lifecycle or optional-work boundaries, never at
/// frame cadence. A constrained device must still record and save workouts.
enum ATHLTHSystemResourcePolicy: Equatable, Sendable {
    case normal, constrained, critical

    static func resolve(lowPower: Bool, thermal: ProcessInfo.ThermalState) -> Self {
        switch thermal {
        case .critical: return .critical
        case .serious: return .constrained
        case .fair, .nominal: return lowPower ? .constrained : .normal
        @unknown default: return .constrained
        }
    }

    static var current: Self {
        let process = ProcessInfo.processInfo
        return resolve(lowPower: process.isLowPowerModeEnabled, thermal: process.thermalState)
    }

    var allowsOptionalPreparation: Bool { self == .normal }
    var storageImageBudget: Int { self == .normal ? 20 * 1024 * 1024 : 8 * 1024 * 1024 }
    var exerciseThumbnailBudget: Int { self == .normal ? 24 * 1024 * 1024 : 10 * 1024 * 1024 }

    var title: String {
        switch self {
        case .normal: return ATHLTHLocalization.choose(english: "Normal", norwegian: "Normal")
        case .constrained: return ATHLTHLocalization.choose(english: "Reduced optional work", norwegian: "Redusert tilleggsarbeid")
        case .critical: return ATHLTHLocalization.choose(english: "Critical temperature", norwegian: "Kritisk temperatur")
        }
    }
}

/// MetricKit owns the collection schedule. Retain only the latest delivery
/// timestamps and aggregate counts, without stacks, account identifiers,
/// health values, raw JSON, custom telemetry network requests or polling.
final class ATHLTHMetricDeliveryObserver: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    private static let shared = ATHLTHMetricDeliveryObserver()
    @MainActor private static var installed = false
    private static let metricDateKey = "athlth.diagnostics.metricKit.lastMetricDate"
    private static let diagnosticDateKey = "athlth.diagnostics.metricKit.lastDiagnosticDate"
    private static let crashKey = "athlth.diagnostics.metricKit.lastCrashCount"
    private static let hangKey = "athlth.diagnostics.metricKit.lastHangCount"

    @MainActor static func install() {
        guard !installed else { return }
        installed = true
        MXMetricManager.shared.add(shared)
    }

    static var lastMetricDate: Date? { UserDefaults.standard.object(forKey: metricDateKey) as? Date }
    static var lastDiagnosticDate: Date? { UserDefaults.standard.object(forKey: diagnosticDateKey) as? Date }
    static var lastCrashCount: Int { UserDefaults.standard.integer(forKey: crashKey) }
    static var lastHangCount: Int { UserDefaults.standard.integer(forKey: hangKey) }

    func didReceive(_ payloads: [MXMetricPayload]) {
        guard !payloads.isEmpty else { return }
        UserDefaults.standard.set(Date(), forKey: Self.metricDateKey)
        ATHLTHPerformance.event("MetricKitMetricsReceived")
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        guard !payloads.isEmpty else { return }
        let defaults = UserDefaults.standard
        defaults.set(payloads.reduce(0) { $0 + ($1.crashDiagnostics?.count ?? 0) }, forKey: Self.crashKey)
        defaults.set(payloads.reduce(0) { $0 + ($1.hangDiagnostics?.count ?? 0) }, forKey: Self.hangKey)
        defaults.set(Date(), forKey: Self.diagnosticDateKey)
        ATHLTHPerformance.event("MetricKitDiagnosticsReceived")
    }
}

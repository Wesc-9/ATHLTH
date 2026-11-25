import Foundation
import os

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

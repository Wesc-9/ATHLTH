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

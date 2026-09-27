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

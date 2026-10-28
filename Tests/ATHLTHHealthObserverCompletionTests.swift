import Foundation
import XCTest
@testable import ATHLTH

private final class HealthObserverCompletionTestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

final class ATHLTHHealthObserverCompletionTests: XCTestCase {
    func testMultipleCompletionPathsCallHealthKitExactlyOnce() {
        let counter = HealthObserverCompletionTestCounter()
        let callback = ATHLTHHealthObserverCompletion {
            counter.increment()
        }
        DispatchQueue.concurrentPerform(iterations: 48) { _ in
            callback.call()
        }
        XCTAssertEqual(counter.value, 1)
        callback.call()
        XCTAssertEqual(counter.value, 1)
    }
}

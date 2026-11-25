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
    func testBackgroundDeliveryStatusUsesActualRegistrationResults() {
        XCTAssertEqual(ATHLTHBackgroundDeliveryStatus.registrationResult(accepted: 0, total: 0), .unavailable)
        XCTAssertEqual(ATHLTHBackgroundDeliveryStatus.registrationResult(accepted: 0, total: 18), .unavailable)
        XCTAssertEqual(ATHLTHBackgroundDeliveryStatus.registrationResult(accepted: 1, total: 18), .partial)
        XCTAssertEqual(ATHLTHBackgroundDeliveryStatus.registrationResult(accepted: 18, total: 18), .active)
    }

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

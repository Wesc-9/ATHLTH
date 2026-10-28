import Foundation

/// HealthKit background-observer callbacks may finish via the refresh task
/// or its safety timeout. The completion handler must run exactly once.
final class ATHLTHHealthObserverCompletion: @unchecked Sendable {
    private let handler: () -> Void
    private let lock = NSLock()
    private var finished = false

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    func call() {
        lock.lock()
        let shouldCall = !finished
        finished = true
        lock.unlock()
        if shouldCall { handler() }
    }
}

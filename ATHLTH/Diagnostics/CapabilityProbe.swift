import Foundation

enum CapabilityProbe {
    static let healthKitEntitlementConfigured = true

    // Kept off in the first Personal Team build on purpose.
    // Once the base app installs successfully, we can enable the entitlement
    // and test whether the free signing profile accepts it.
    static let backgroundDeliveryEntitlementConfigured = false

    static var workoutKitFrameworkAvailable: Bool {
        #if canImport(WorkoutKit)
        true
        #else
        false
        #endif
    }

    static var runningOnSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    static var osDescription: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }
}

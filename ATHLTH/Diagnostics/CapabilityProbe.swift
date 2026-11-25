import Foundation

enum CapabilityProbe {
    static let healthKitEntitlementConfigured = true

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

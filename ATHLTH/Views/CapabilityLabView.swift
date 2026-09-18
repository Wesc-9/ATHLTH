import SwiftUI

struct CapabilityLabView: View {
    @EnvironmentObject private var health: HealthKitManager

    @State private var authorizationStatus = "Not checked"
    @State private var checkingAuthorization = false
    @State private var checkingRoute = false
    @State private var checkingBackground = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Capability Lab")
                            .font(.largeTitle.weight(.bold))
                        Text("A temporary V0.1 test bench for the free Apple Personal Team.")
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        CapabilityRow(
                            title: "Apple Health",
                            detail: health.healthDataAvailable ? "HealthKit is available on this device." : "HealthKit is unavailable on this device.",
                            state: health.healthDataAvailable ? .ready : .failed
                        )

                        CapabilityRow(
                            title: "HealthKit entitlement",
                            detail: CapabilityProbe.healthKitEntitlementConfigured ? "Configured in the ATHLTH build." : "Not configured.",
                            state: CapabilityProbe.healthKitEntitlementConfigured ? .ready : .failed
                        )

                        CapabilityRow(
                            title: "WorkoutKit framework",
                            detail: CapabilityProbe.workoutKitFrameworkAvailable ? "Framework is available in this SDK/build." : "Framework is not available in this build.",
                            state: CapabilityProbe.workoutKitFrameworkAvailable ? .ready : .warning
                        )

                        CapabilityRow(
                            title: "Background delivery entitlement",
                            detail: CapabilityProbe.backgroundDeliveryEntitlementConfigured
                                ? "Configured in this build."
                                : "Intentionally not signed into the first Personal Team build.",
                            state: CapabilityProbe.backgroundDeliveryEntitlementConfigured ? .ready : .warning
                        )

                        CapabilityRow(
                            title: "Environment",
                            detail: CapabilityProbe.runningOnSimulator
                                ? "Simulator — use a physical iPhone for HealthKit testing."
                                : "Physical Apple device · \(CapabilityProbe.osDescription)",
                            state: CapabilityProbe.runningOnSimulator ? .warning : .ready
                        )
                    }
                    .padding(18)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))

                    TestSection(
                        title: "Health authorization",
                        description: authorizationStatus
                    ) {
                        Button {
                            checkingAuthorization = true
                            Task {
                                authorizationStatus = await health.authorizationRequestStatusDescription()
                                checkingAuthorization = false
                            }
                        } label: {
                            testButtonLabel("Check authorization", loading: checkingAuthorization)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(checkingAuthorization)
                    }

                    TestSection(
                        title: "Workout GPS route",
                        description: health.routeCapabilityTestResult ?? "Checks up to 10 recent run/walk workouts for an HKWorkoutRoute."
                    ) {
                        Button {
                            checkingRoute = true
                            Task {
                                if health.workouts.isEmpty {
                                    await health.refreshAll()
                                }
                                await health.testWorkoutRouteCapability()
                                checkingRoute = false
                            }
                        } label: {
                            testButtonLabel("Test route access", loading: checkingRoute)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(checkingRoute)
                    }

                    TestSection(
                        title: "Background delivery",
                        description: health.backgroundDeliveryTestResult
                            ?? "Attempts to enable immediate workout background delivery. In this first Personal Team build, failure due to a missing entitlement is expected and useful."
                    ) {
                        Button {
                            checkingBackground = true
                            Task {
                                await health.testBackgroundDelivery()
                                checkingBackground = false
                            }
                        } label: {
                            testButtonLabel("Test background delivery", loading: checkingBackground)
                        }
                        .buttonStyle(.bordered)
                        .disabled(checkingBackground)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Privacy note", systemImage: "lock.shield.fill")
                            .font(.headline)
                        Text("These tests run on-device. V0.1 has no ATHLTH account, analytics SDK, cloud backend, or Home Assistant connection.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(18)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
                }
                .padding()
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Lab")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func testButtonLabel(_ title: String, loading: Bool) -> some View {
        if loading {
            ProgressView()
                .frame(maxWidth: .infinity)
        } else {
            Text(title)
                .frame(maxWidth: .infinity)
        }
    }
}

private struct TestSection<Content: View>: View {
    let title: String
    let description: String
    @ViewBuilder let content: Content

    init(
        title: String,
        description: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.description = description
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            content
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
    }
}

private struct CapabilityRow: View {
    enum State {
        case ready
        case warning
        case failed

        var icon: String {
            switch self {
            case .ready: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .failed: return "xmark.circle.fill"
            }
        }
    }

    let title: String
    let detail: String
    let state: State

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: state.icon)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

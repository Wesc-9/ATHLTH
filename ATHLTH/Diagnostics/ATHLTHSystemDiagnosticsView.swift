import SwiftUI
import UserNotifications

struct ATHLTHSystemDiagnosticsView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var notifications: ATHLTHNotificationStore
    @EnvironmentObject private var accountService: SupabaseAccountService

    @ObservedObject private var push = APNsPushManager.shared

    var body: some View {
        List {
            Section("Build") {
                diagnosticRow(
                    "ATHLTH",
                    value: "\(appVersion) (\(buildNumber))",
                    icon: "app.badge"
                )
                diagnosticRow(
                    "Environment",
                    value: CapabilityProbe.runningOnSimulator
                        ? "Simulator"
                        : CapabilityProbe.osDescription,
                    icon: "iphone"
                )
            }

            Section("Account") {
                diagnosticRow(
                    "Signed in",
                    value: session.signedIn ? "Yes" : "No",
                    icon: "person.crop.circle"
                )
                diagnosticRow(
                    "Role",
                    value: session.currentRole.title,
                    icon: "person.badge.key"
                )
                diagnosticRow(
                    "Email",
                    value: accountService.currentEmail ?? "Unavailable",
                    icon: "envelope"
                )
            }

            Section("Apple Health") {
                diagnosticRow(
                    "Authorization requested",
                    value: health.hasRequestedAuthorization ? "Yes" : "No",
                    icon: "heart.fill"
                )
                diagnosticRow(
                    "Readable data",
                    value: health.hasReadableHealthData ? "Available" : "No data yet",
                    icon: "waveform.path.ecg"
                )
                diagnosticRow(
                    "Last successful sync",
                    value: health.lastSuccessfulRefreshAt?.formatted(
                        date: .abbreviated,
                        time: .standard
                    ) ?? "Never",
                    icon: "arrow.triangle.2.circlepath"
                )

                if let error = health.authorizationError, !error.isEmpty {
                    diagnosticError("Health authorization", detail: error)
                }

                if let error = health.backgroundSyncError, !error.isEmpty {
                    diagnosticError("Background sync", detail: error)
                }
            }

            Section("Apple Watch") {
                diagnosticRow(
                    "Connection",
                    value: watchConnection.statusText,
                    icon: "applewatch"
                )
                diagnosticRow(
                    "Paired",
                    value: booleanText(watchConnection.paired),
                    icon: "link"
                )
                diagnosticRow(
                    "Watch app",
                    value: booleanText(
                        watchConnection.watchAppInstalled,
                        yes: "Installed",
                        no: "Not installed"
                    ),
                    icon: "square.stack.3d.up"
                )
                diagnosticRow(
                    "Reachable now",
                    value: watchConnection.reachable ? "Yes" : "No",
                    icon: "antenna.radiowaves.left.and.right"
                )
                diagnosticRow(
                    "WCSession",
                    value: watchConnection.activationStateText,
                    icon: "wave.3.right"
                )

                if let verified = watchConnection.lastVerifiedAt {
                    diagnosticRow(
                        "Last verified",
                        value: verified.formatted(
                            date: .abbreviated,
                            time: .standard
                        ),
                        icon: "checkmark.circle"
                    )
                }

                if let error = watchConnection.connectivityError,
                   !error.isEmpty {
                    diagnosticError("Watch connectivity", detail: error)
                }

                if let error = watchConnection.workoutLaunchError,
                   !error.isEmpty {
                    diagnosticError("Workout launch", detail: error)
                }
            }

            Section("Notifications") {
                diagnosticRow(
                    "iOS permission",
                    value: notificationAuthorizationTitle,
                    icon: "bell"
                )
                diagnosticRow(
                    "APNs backend",
                    value: push.isRegisteredWithBackend
                        ? "Registered"
                        : "Not registered",
                    icon: "paperplane"
                )

                if let error = push.lastRegistrationError,
                   !error.isEmpty {
                    diagnosticError("Push registration", detail: error)
                }
            }

            Section("Capabilities") {
                diagnosticRow(
                    "HealthKit entitlement",
                    value: CapabilityProbe.healthKitEntitlementConfigured
                        ? "Configured"
                        : "Missing",
                    icon: "heart.text.square"
                )
                diagnosticRow(
                    "Background delivery",
                    value: CapabilityProbe.backgroundDeliveryEntitlementConfigured
                        ? "Configured"
                        : "Unavailable",
                    icon: "arrow.clockwise.icloud"
                )
                diagnosticRow(
                    "WorkoutKit",
                    value: CapabilityProbe.workoutKitFrameworkAvailable
                        ? "Available"
                        : "Unavailable",
                    icon: "figure.run"
                )
            }

            Section {
                Button {
                    watchConnection.refreshStatus()
                    Task {
                        await notifications.refreshAuthorizationStatus()
                    }
                } label: {
                    Label(
                        "Refresh System Status",
                        systemImage: "arrow.clockwise"
                    )
                }

                NavigationLink {
                    CapabilityLabView()
                } label: {
                    Label(
                        "Open Capability Tests",
                        systemImage: "testtube.2"
                    )
                }
            } footer: {
                Text(
                    "Diagnostics are read-only except for refreshing local connection status. No passwords, Health values or push tokens are displayed."
                )
            }
        }
        .navigationTitle("System Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            watchConnection.refreshStatus()
            await notifications.refreshAuthorizationStatus()
        }
    }

    private var appVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "—"
    }

    private var notificationAuthorizationTitle: String {
        switch notifications.authorizationStatus {
        case .notDetermined:
            return "Not requested"
        case .denied:
            return "Denied"
        case .authorized:
            return "Authorized"
        case .provisional:
            return "Provisional"
        case .ephemeral:
            return "Ephemeral"
        @unknown default:
            return "Unknown"
        }
    }

    private func booleanText(
        _ value: Bool?,
        yes: String = "Yes",
        no: String = "No"
    ) -> String {
        guard let value else { return "Unknown" }
        return value ? yes : no
    }

    private func diagnosticRow(
        _ title: String,
        value: String,
        icon: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(width: 24)

            Text(title)

            Spacer(minLength: 12)

            Text(value)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func diagnosticError(
        _ title: String,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)

            Text(detail)
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .textSelection(.enabled)
        }
        .padding(.vertical, 3)
    }
}

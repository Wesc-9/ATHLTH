import SwiftUI

struct AppleWatchSetupView: View {
    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore

    @State private var healthSetupInProgress = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    iphoneHealthStep
                    watchInstallStep
                    watchHealthStep
                }
                .padding(20)
            }
            .background(OnboardingBackground().ignoresSafeArea())
            .navigationTitle("Configure Apple Watch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                watchConnection.connect()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(OnboardingTheme.green.opacity(0.12))
                    .frame(width: 86, height: 86)

                Image(systemName: "applewatch")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.deepGreen)
            }

            Text("Set up ATHLTH on Apple Watch")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text("ATHLTH checks your iPhone Health access, Watch installation, live connection and Health access on Apple Watch in one setup flow.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 4)
    }

    private var iphoneHealthStep: some View {
        setupCard(
            number: 1,
            title: "Apple Health on iPhone",
            complete: health.hasRequestedAuthorization
        ) {
            if health.hasRequestedAuthorization {
                Label(
                    "Apple Health access has been requested",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(OnboardingTheme.green)
            } else {
                Text("Allow ATHLTH to request the Health data it needs on your iPhone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    Task {
                        healthSetupInProgress = true
                        await health.requestAuthorization()
                        await health.configureBackgroundSync(
                            allowed: session.canAccess(.backgroundHealthSync)
                        )
                        healthSetupInProgress = false
                    }
                } label: {
                    HStack {
                        Text("Configure Apple Health")
                        Spacer()
                        if healthSetupInProgress {
                            ProgressView()
                                .tint(.white)
                        }
                    }
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .disabled(healthSetupInProgress)
            }
        }
    }

    private var watchInstallStep: some View {
        setupCard(
            number: 2,
            title: "ATHLTH on Apple Watch",
            complete: watchConnection.isReady
        ) {
            switch watchConnection.state {
            case .checking:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Checking paired Apple Watch…")
                        .foregroundStyle(.secondary)
                }

            case .unsupported:
                statusMessage(
                    icon: "exclamationmark.triangle.fill",
                    text: "Apple Watch connectivity is unavailable on this iPhone.",
                    tint: .orange
                )

            case .notPaired:
                statusMessage(
                    icon: "applewatch.slash",
                    text: "No paired Apple Watch was found. Pair your Watch in Apple’s Watch app, then return here.",
                    tint: .orange
                )

            case .appNotInstalled:
                statusMessage(
                    icon: "arrow.down.app.fill",
                    text: "ATHLTH is not installed on your Apple Watch.",
                    tint: .orange
                )

                VStack(alignment: .leading, spacing: 8) {
                    instructionRow(1, "Open the Watch app on this iPhone")
                    instructionRow(2, "Find ATHLTH under Available Apps")
                    instructionRow(3, "Tap Install and open ATHLTH once on Apple Watch")
                }

                Text("Apple does not provide an API that lets ATHLTH install the Watch app automatically. Installation must be confirmed in the Watch app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                checkAgainButton

            case .ready:
                statusMessage(
                    icon: "checkmark.circle.fill",
                    text: watchConnection.connectionDetail
                        ?? "ATHLTH is installed on Apple Watch.",
                    tint: OnboardingTheme.green
                )

                if !watchConnection.isReachable {
                    Text("Open ATHLTH once on Apple Watch, keep it visible, then tap Check again to verify the live connection.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                checkAgainButton
            }
        }
    }

    private var watchHealthStep: some View {
        setupCard(
            number: 3,
            title: "Health access on Apple Watch",
            complete: watchConnection.watchHealthAuthorizationDetail
                == "Apple Watch Health setup completed."
        ) {
            if !watchConnection.isReady {
                Text("Install and connect ATHLTH on Apple Watch before configuring Watch Health access.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Open ATHLTH on Apple Watch. When you continue, the Health permission sheet appears on the Watch so you can approve workout, heart-rate, energy, distance and route access.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let detail = watchConnection.watchHealthAuthorizationDetail {
                    Text(LocalizedStringKey(detail))
                        .font(.caption)
                        .foregroundStyle(
                            detail == "Apple Watch Health setup completed."
                                ? OnboardingTheme.green
                                : Color.secondary
                        )
                }

                Button {
                    watchConnection.requestWatchHealthAuthorization()
                } label: {
                    HStack {
                        Text("Configure Health on Apple Watch")
                        Spacer()
                        if watchConnection.watchHealthAuthorizationInProgress {
                            ProgressView()
                                .tint(.white)
                        }
                    }
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .disabled(
                    !watchConnection.isReachable
                    || watchConnection.watchHealthAuthorizationInProgress
                )

                if !watchConnection.isReachable {
                    Text("Open ATHLTH on Apple Watch first. The Watch must be reachable before ATHLTH can ask watchOS to show the Health permission sheet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var checkAgainButton: some View {
        Button {
            watchConnection.connect()
        } label: {
            Label("Check again", systemImage: "arrow.clockwise")
                .frame(maxWidth: .infinity)
                .frame(height: 48)
        }
        .buttonStyle(.bordered)
        .tint(OnboardingTheme.deepGreen)
    }

    @ViewBuilder
    private func setupCard<Content: View>(
        number: Int,
        title: LocalizedStringKey,
        complete: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        OnboardingCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(
                                complete
                                    ? OnboardingTheme.green.opacity(0.14)
                                    : Color.black.opacity(0.055)
                            )
                            .frame(width: 34, height: 34)

                        if complete {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(OnboardingTheme.green)
                        } else {
                            Text("\(number)")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(title)
                        .font(.headline)

                    Spacer()
                }

                content()
            }
        }
    }

    private func statusMessage(
        icon: String,
        text: String,
        tint: Color
    ) -> some View {
        Label {
            Text(LocalizedStringKey(text))
        } icon: {
            Image(systemName: icon)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(tint)
    }

    private func instructionRow(
        _ number: Int,
        _ text: LocalizedStringKey
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(OnboardingTheme.deepGreen, in: Circle())

            Text(text)
                .font(.subheadline)
        }
    }
}

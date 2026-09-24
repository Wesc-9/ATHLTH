import SwiftUI

struct AppleWatchConnectionView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore

    var body: some View {
        Form {
            Section("Status") {
                LabeledContent("Pairing", value: pairedText)
                LabeledContent("ATHLTH Watch app", value: installedText)
                LabeledContent(
                    "WatchConnectivity",
                    value: watchConnection.activationStateText
                )
                LabeledContent(
                    "Immediate reachability",
                    value: watchConnection.reachable ? "Active now" : "Background"
                )

                if let verifiedAt = watchConnection.lastVerifiedAt {
                    LabeledContent(
                        "ATHLTH link verified",
                        value: verifiedAt.formatted(
                            date: .omitted,
                            time: .shortened
                        )
                    )
                } else {
                    LabeledContent(
                        "ATHLTH link verified",
                        value: watchConnection.verificationInProgress
                            ? "Checking…"
                            : "Not yet"
                    )
                }
            }

            Section {
                Button {
                    watchConnection.connect()
                } label: {
                    HStack {
                        Label("Check Apple Watch again", systemImage: "arrow.clockwise")
                        Spacer()
                        if watchConnection.state == .checking ||
                            watchConnection.verificationInProgress {
                            ProgressView()
                        }
                    }
                }

                Text(watchConnection.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let error = watchConnection.connectivityError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("How the check works") {
                Text(
                    "ATHLTH first waits for WatchConnectivity to activate. Only then does it read Apple's paired-Watch and app-installed status. If ATHLTH is installed, the iPhone also sends a small handshake so the Watch app can confirm that the ATHLTH link is working."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(
                    "“Background” is normal when the Watch app is not open. Apple only reports immediate reachability while the counterpart app is active; background transfers can still work."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if watchConnection.state == .appNotInstalled {
                Section("Install ATHLTH on Apple Watch") {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(
                            "Your Watch is paired — only the ATHLTH app is missing.",
                            systemImage: "applewatch"
                        )
                        .font(.subheadline.weight(.semibold))

                        VStack(alignment: .leading, spacing: 9) {
                            installStep(
                                "1",
                                "Open Apple’s Watch app"
                            )
                            installStep(
                                "2",
                                "Scroll to Available Apps"
                            )
                            installStep(
                                "3",
                                "Tap Install next to ATHLTH"
                            )
                        }

                        Button {
                            AppleWatchInstallSupport.openWatchApp()
                        } label: {
                            Label(
                                "Install ATHLTH on Apple Watch",
                                systemImage: "arrow.down.app.fill"
                            )
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Text(
                            "When you return to ATHLTH, installation status is checked automatically."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Apple Watch")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            watchConnection.connect()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refreshAfterInstallReturn()
        }
    }

    private func refreshAfterInstallReturn() {
        watchConnection.connect()

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard watchConnection.state == .appNotInstalled else {
                return
            }

            watchConnection.connect()

            try? await Task.sleep(for: .seconds(2))
            guard watchConnection.state == .appNotInstalled else {
                return
            }

            watchConnection.connect()
        }
    }

    private func installStep(
        _ number: String,
        _ title: String
    ) -> some View {
        HStack(spacing: 10) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(
                    ATHLTHTheme.accentDeep,
                    in: Circle()
                )

            Text(title)
                .font(.subheadline)
        }
    }

    private var pairedText: String {
        switch watchConnection.paired {
        case true:
            return "Paired"
        case false:
            return "Not paired"
        case nil:
            return "Checking…"
        }
    }

    private var installedText: String {
        switch watchConnection.watchAppInstalled {
        case true:
            return "Installed"
        case false:
            return "Not installed"
        case nil:
            return "Checking…"
        }
    }
}

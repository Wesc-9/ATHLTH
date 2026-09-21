import SwiftUI

struct AppleWatchConnectionView: View {
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
                    Text(
                        "Install the ATHLTH Watch app on the paired Apple Watch, then return here and tap “Check Apple Watch again”."
                    )
                    .font(.subheadline)
                }
            }
        }
        .navigationTitle("Apple Watch")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            watchConnection.connect()
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

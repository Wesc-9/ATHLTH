import SwiftUI

struct HomeAssistantSettingsView: View {
    @EnvironmentObject private var homeAssistant:
        HomeAssistantConnectionStore

    @State private var manualAddress = ""
    @State private var showingDisconnectConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                if homeAssistant.isConnected {
                    connectedCard
                } else {
                    discoveryCard
                    manualConnectionCard
                }

                securityCard

                if let error = homeAssistant.lastErrorMessage,
                   !error.isEmpty {
                    errorCard(error)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 36)
        }
        .background(ATHLTHTheme.background.ignoresSafeArea())
        .navigationTitle("Home Assistant")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !homeAssistant.isConnected {
                homeAssistant.startDiscovery()
            }
        }
        .onDisappear {
            homeAssistant.stopDiscovery()
        }
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english: "Disconnect Home Assistant?",
                norwegian: "Koble fra Home Assistant?"
            ),
            isPresented: $showingDisconnectConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                ATHLTHLocalization.choose(
                    english: "Disconnect",
                    norwegian: "Koble fra"
                ),
                role: .destructive
            ) {
                Task {
                    await homeAssistant.disconnect()
                    homeAssistant.startDiscovery()
                }
            }

            Button(
                ATHLTHLocalization.choose(
                    english: "Cancel",
                    norwegian: "Avbryt"
                ),
                role: .cancel
            ) {}
        } message: {
            Text(
                ATHLTHLocalization.choose(
                    english:
                        "ATHLTH will remove the Home Assistant pairing from this device.",
                    norwegian:
                        "ATHLTH fjerner Home Assistant-paringen fra denne enheten."
                )
            )
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        Color(
                            red: 0.12,
                            green: 0.58,
                            blue: 0.86
                        )
                        .opacity(0.12)
                    )
                    .frame(width: 62, height: 62)

                Image(systemName: "house.fill")
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(
                        Color(
                            red: 0.12,
                            green: 0.58,
                            blue: 0.86
                        )
                    )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Home Assistant")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(ATHLTHTheme.primaryText)

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Connect ATHLTH to your home without copying API keys or long-lived tokens.",
                        norwegian:
                            "Koble ATHLTH til hjemmet ditt uten å kopiere API-nøkler eller langtids-tokens."
                    )
                )
                .font(.subheadline)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var connectedCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "Connected securely",
                            norwegian: "Sikkert tilkoblet"
                        )
                    )
                    .font(.headline)
                    .foregroundStyle(ATHLTHTheme.primaryText)

                    Text(
                        homeAssistant.connectedInstanceName
                            ?? "Home Assistant"
                    )
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }

                Spacer()
            }

            if let url = homeAssistant.connectedInstanceURL {
                HStack(spacing: 9) {
                    Image(systemName: "network")
                        .foregroundStyle(ATHLTHTheme.mutedText)

                    Text(url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                connectionDetail(
                    icon: "key.slash",
                    title: ATHLTHLocalization.choose(
                        english: "No API key stored",
                        norwegian: "Ingen API-nøkkel lagret"
                    )
                )

                connectionDetail(
                    icon: "lock.shield",
                    title: ATHLTHLocalization.choose(
                        english: "Signed webhook requests",
                        norwegian: "Signerte webhook-forespørsler"
                    )
                )

                connectionDetail(
                    icon: "key.fill",
                    title: ATHLTHLocalization.choose(
                        english: "Pairing secret kept in Keychain",
                        norwegian: "Paringsnøkkel lagret i Keychain"
                    )
                )
            }

            HStack(spacing: 12) {
                Button {
                    Task {
                        await homeAssistant.sendConnectionTest()
                    }
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Test connection",
                            norwegian: "Test tilkobling"
                        ),
                        systemImage: "bolt.horizontal.circle"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) {
                    showingDisconnectConfirmation = true
                } label: {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "Disconnect",
                            norwegian: "Koble fra"
                        )
                    )
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(18)
        .background(
            ATHLTHTheme.surface,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    private var discoveryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "Nearby Home Assistant",
                            norwegian: "Home Assistant i nærheten"
                        )
                    )
                    .font(.headline)
                    .foregroundStyle(ATHLTHTheme.primaryText)

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "ATHLTH searches your local network automatically.",
                            norwegian:
                                "ATHLTH søker automatisk på lokalnettet ditt."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }

                Spacer()

                if homeAssistant.connectionState == .discovering {
                    ProgressView()
                } else {
                    Button {
                        homeAssistant.startDiscovery()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                }
            }

            if homeAssistant.discoveredInstances.isEmpty {
                HStack(spacing: 11) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .foregroundStyle(ATHLTHTheme.mutedText)

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Searching for _home-assistant._tcp on your network…",
                            norwegian:
                                "Søker etter _home-assistant._tcp på nettverket ditt…"
                        )
                    )
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(
                        Array(
                            homeAssistant.discoveredInstances
                                .enumerated()
                        ),
                        id: \.element.id
                    ) { index, instance in
                        Button {
                            homeAssistant.connect(to: instance)
                        } label: {
                            HStack(spacing: 13) {
                                ZStack {
                                    Circle()
                                        .fill(
                                            Color(
                                                red: 0.12,
                                                green: 0.58,
                                                blue: 0.86
                                            )
                                            .opacity(0.11)
                                        )
                                        .frame(width: 42, height: 42)

                                    Image(systemName: "house.fill")
                                        .foregroundStyle(
                                            Color(
                                                red: 0.12,
                                                green: 0.58,
                                                blue: 0.86
                                            )
                                        )
                                }

                                VStack(
                                    alignment: .leading,
                                    spacing: 3
                                ) {
                                    Text(instance.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(
                                            ATHLTHTheme.primaryText
                                        )

                                    Text(instance.displayURL)
                                        .font(.caption)
                                        .foregroundStyle(
                                            ATHLTHTheme.mutedText
                                        )
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }

                                Spacer()

                                if let version = instance.version {
                                    Text(version)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(
                                            ATHLTHTheme.mutedText
                                        )
                                }

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(
                                        ATHLTHTheme.mutedText.opacity(0.7)
                                    )
                            }
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)

                        if index <
                            homeAssistant.discoveredInstances.count - 1 {
                            Divider()
                                .padding(.leading, 55)
                        }
                    }
                }
            }

            if !homeAssistant.isOAuthClientConfigured {
                Label(
                    ATHLTHLocalization.choose(
                        english:
                            "OAuth client metadata must be published before sign-in can be enabled in a release build.",
                        norwegian:
                            "OAuth-klientmetadata må publiseres før innlogging kan aktiveres i en release-build."
                    ),
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
            }
        }
        .padding(18)
        .background(
            ATHLTHTheme.surface,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    private var manualConnectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(
                ATHLTHLocalization.choose(
                    english: "Enter address manually",
                    norwegian: "Skriv inn adresse manuelt"
                )
            )
            .font(.headline)
            .foregroundStyle(ATHLTHTheme.primaryText)

            Text(
                ATHLTHLocalization.choose(
                    english:
                        "Use this only if your Home Assistant instance is not discovered automatically.",
                    norwegian:
                        "Bruk dette kun dersom Home Assistant ikke blir funnet automatisk."
                )
            )
            .font(.caption)
            .foregroundStyle(ATHLTHTheme.mutedText)

            TextField(
                "http://homeassistant.local:8123",
                text: $manualAddress
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(
                ATHLTHTheme.background,
                in: RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
            )

            Button {
                homeAssistant.connectManually(
                    address: manualAddress
                )
            } label: {
                Text(
                    ATHLTHLocalization.choose(
                        english: "Continue",
                        norwegian: "Fortsett"
                    )
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                manualAddress.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .isEmpty
            )
        }
        .padding(18)
        .background(
            ATHLTHTheme.surface,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    private var securityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                ATHLTHLocalization.choose(
                    english: "How the connection works",
                    norwegian: "Slik fungerer tilkoblingen"
                ),
                systemImage: "lock.shield.fill"
            )
            .font(.headline)
            .foregroundStyle(ATHLTHTheme.primaryText)

            Text(
                ATHLTHLocalization.choose(
                    english:
                        "You approve ATHLTH once in Home Assistant. The temporary OAuth token is used only to create the pairing and is then revoked. Normal updates use a signed webhook with a random secret stored in iOS Keychain.",
                    norwegian:
                        "Du godkjenner ATHLTH én gang i Home Assistant. Det midlertidige OAuth-tokenet brukes kun til å opprette paringen og blir deretter tilbakekalt. Vanlige oppdateringer sendes via en signert webhook med en tilfeldig nøkkel lagret i iOS Keychain."
                )
            )
            .font(.subheadline)
            .foregroundStyle(ATHLTHTheme.mutedText)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(
            ATHLTHTheme.surface,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(ATHLTHTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.orange.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private func connectionDetail(
        icon: String,
        title: String
    ) -> some View {
        Label {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(ATHLTHTheme.primaryText)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(ATHLTHTheme.mutedText)
        }
    }
}

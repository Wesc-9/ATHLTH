import SwiftUI

/// Canonical Apple Watch settings page; status reflects the actual connection
/// rather than conflating installation, pairing and live reachability.
struct AppleWatchConnectionView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var session: AppSessionStore
    @State private var routeTransferMessage: String?
    @State private var selectedTestRouteID: UUID?

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        ATHLTHSettingsScreen(title: "Apple Watch",
            subtitle: tr("Connection, app and workout readiness", "Tilkobling, app og treningsklarhet")) {
            ATHLTHSettingsGroup(title: tr("Connection status", "Tilkoblingsstatus")) {
                PremiumSettingsCard {
                    statusRow("applewatch", tr("Pairing", "Sammenkobling"), pairedText)
                    SettingsDivider()
                    statusRow("app.badge.checkmark", tr("ATHLTH app", "ATHLTH-app"), installedText)
                    SettingsDivider()
                    statusRow("arrow.triangle.2.circlepath", tr("Connection service", "Tilkoblingstjeneste"), watchConnection.activationStateText)
                    SettingsDivider()
                    statusRow("antenna.radiowaves.left.and.right", tr("Reachability", "Tilgjengelighet"),
                        watchConnection.reachable ? tr("Active now", "Aktiv nå") : tr("Not reachable now", "Ikke aktiv nå"))
                    SettingsDivider()
                    statusRow("checkmark.shield", tr("Last verified", "Sist verifisert"), verificationText)
                }
            }

            ATHLTHSettingsGroup(title: tr("Actions", "Handlinger")) {
                PremiumSettingsCard {
                    if watchConnection.state == .appNotInstalled {
                        Button { AppleWatchInstallSupport.openWatchApp() } label: {
                            PremiumSettingsRow(icon: "arrow.down.app", iconTint: ATHLTHTheme.accentDeep,
                                title: tr("Install ATHLTH on Apple Watch", "Installer ATHLTH på Apple Watch"),
                                subtitle: tr("Open the Watch app and find ATHLTH under available apps.", "Åpne Watch-appen og finn ATHLTH under tilgjengelige apper.")) {
                                Image(systemName: "chevron.right").foregroundStyle(ATHLTHTheme.mutedText)
                            }
                        }.buttonStyle(.plain)
                        SettingsDivider()
                    }
                    Button { watchConnection.connect() } label: {
                        PremiumSettingsRow(icon: "arrow.clockwise", iconTint: ATHLTHTheme.accentDeep,
                            title: tr("Check connection", "Kontroller tilkobling"),
                            subtitle: tr("Refresh pairing and verify the ATHLTH link", "Oppdater sammenkobling og verifiser ATHLTH-forbindelsen")) {
                            if watchConnection.state == .checking || watchConnection.verificationInProgress {
                                ProgressView()
                            } else {
                                Image(systemName: "chevron.right").foregroundStyle(ATHLTHTheme.mutedText)
                            }
                        }
                    }.buttonStyle(.plain)
                    .disabled(watchConnection.state == .checking || watchConnection.verificationInProgress)
                }
                if let error = watchConnection.connectivityError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(ATHLTHTheme.mutedText)
                        .padding(.horizontal, 12)
                }
            }
            ATHLTHSettingsGroup(title: tr("Supported functions", "Støttede funksjoner")) {
                PremiumSettingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(tr("Workout recording and live data", "Øktregistrering og livedata"), systemImage: "figure.run")
                        Label(tr("Routes and workout transfers", "Ruter og overføring av økter"), systemImage: "map")
                        Label(tr("Audio Coach and haptic feedback", "Audio Coach og vibrasjon"), systemImage: "waveform")
                        Text(tr("Requires a compatible watch and the ATHLTH watch app. Each feature can depend on workout type and device state.", "Krever kompatibel klokke og ATHLTH-appen på klokken. Funksjoner kan avhenge av økttype og enhetsstatus."))
                            .font(.caption).foregroundStyle(ATHLTHTheme.mutedText)
                    }.font(.subheadline).padding(16)
                }
            }
            if watchConnection.isReady {
                ATHLTHSettingsGroup(title: tr("Transfer test", "Testoverføring")) {
                    PremiumSettingsCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker(tr("Choose saved route", "Velg lagret rute"), selection: $selectedTestRouteID) {
                                Text(tr("Select", "Velg")).tag(UUID?.none)
                                ForEach(session.savedRoutes) { route in
                                    Text(route.title).tag(Optional(route.id))
                                }
                            }
                            Button {
                                guard let route = session.savedRoutes.first(where: { $0.id == selectedTestRouteID }) else { return }
                                do {
                                    try watchConnection.sendRoute(route)
                                    routeTransferMessage = tr("Route queued. Open Routes on your watch to confirm receipt.", "Rute lagt i overføringskø. Åpne Ruter på klokken for å bekrefte mottak.")
                                } catch { routeTransferMessage = error.localizedDescription }
                            } label: {
                                Label(tr("Send test route", "Send testrute"), systemImage: "paperplane")
                            }
                            .buttonStyle(.bordered)
                            .disabled(selectedTestRouteID == nil || !watchConnection.isReady)
                            if let routeTransferMessage {
                                Text(routeTransferMessage).font(.caption).foregroundStyle(ATHLTHTheme.mutedText)
                            }
                            Text(tr("Does not start a workout.", "Starter ingen treningsøkt."))
                                .font(.caption).foregroundStyle(ATHLTHTheme.mutedText)
                        }.padding(16)
                    }
                }
            }
            ATHLTHSettingsGroup(title: tr("Workout readiness", "Klar for trening")) {
                PremiumSettingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(readinessText, systemImage: watchConnection.isReady ? "checkmark.circle" : "info.circle")
                            .font(.subheadline.weight(.medium))
                        Text(tr("The watch may be unavailable for immediate messages while the app is closed. Background transfers can still work.", "Klokken kan være utilgjengelig for direkte meldinger når appen er lukket. Overføring i bakgrunnen kan fortsatt fungere."))
                            .font(.caption).foregroundStyle(ATHLTHTheme.mutedText)
                        Text(tr("Choose your preferred watch under Settings → Training.", "Velg foretrukket klokke under Innstillinger → Trening."))
                            .font(.caption).foregroundStyle(ATHLTHTheme.mutedText)
                    }
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .padding(16)
                }
            }
        }
        .task { watchConnection.connect() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            watchConnection.connect()
            Task { @MainActor in
                for delay in [1, 2] {
                    try? await Task.sleep(for: .seconds(delay))
                    guard scenePhase == .active, watchConnection.state == .appNotInstalled else { return }
                    watchConnection.connect()
                }
            }
        }
    }

    private func statusRow(_ icon: String, _ title: String, _ value: String) -> some View {
        PremiumSettingsRow(icon: icon, iconTint: ATHLTHTheme.accentDeep, title: title) {
            Text(value).font(.subheadline).foregroundStyle(ATHLTHTheme.mutedText)
                .multilineTextAlignment(.trailing)
        }
    }

    private var pairedText: String {
        switch watchConnection.paired {
        case true: return tr("Paired", "Sammenkoblet")
        case false: return tr("Not paired", "Ikke sammenkoblet")
        case nil: return tr("Checking…", "Sjekker…")
        }
    }

    private var installedText: String {
        switch watchConnection.watchAppInstalled {
        case true: return tr("Installed", "Installert")
        case false: return tr("Not installed", "Ikke installert")
        case nil: return tr("Checking…", "Sjekker…")
        }
    }

    private var verificationText: String {
        if let date = watchConnection.lastVerifiedAt {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return watchConnection.verificationInProgress
            ? tr("Checking…", "Sjekker…") : tr("Not yet verified", "Ikke verifisert ennå")
    }

    private var readinessText: String {
        switch watchConnection.state {
        case .ready: return tr("ATHLTH is installed on your paired watch", "ATHLTH er installert på den sammenkoblede klokken")
        case .appNotInstalled: return tr("Install the ATHLTH Watch app first", "Installer ATHLTH på klokken først")
        case .notPaired: return tr("Pair Apple Watch in the Watch app first", "Koble sammen Apple Watch i Watch-appen først")
        case .checking: return tr("Checking Apple Watch", "Sjekker Apple Watch")
        case .unsupported: return tr("Apple Watch is unavailable on this device", "Apple Watch er ikke tilgjengelig på denne enheten")
        }
    }
}

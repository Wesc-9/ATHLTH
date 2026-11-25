import SwiftUI

/// Canonical Apple Watch settings page; status reflects the actual connection
/// rather than conflating installation, pairing and live reachability.
struct AppleWatchConnectionView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore

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
            if phase == .active { watchConnection.connect() }
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

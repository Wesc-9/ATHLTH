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
            ATHLTHSettingsGroup(title: tr("Training sensors", "Treningssensorer")) {
                PremiumSettingsCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(tr("External heart rate", "Ekstern pulsmåling"), systemImage: "heart.text.square")
                            .font(.subheadline.weight(.semibold))
                        Text(tr("Pair a compatible Bluetooth heart-rate belt in Settings → Bluetooth on your Apple Watch. Apple Health handles measurements during your workout. ATHLTH uses the existing HealthKit pulse stream.", "Koble til et kompatibelt Bluetooth-pulsbelte i Innstillinger → Bluetooth på Apple Watch. Apple Helse håndterer målingene under økten. ATHLTH bruker den eksisterende pulsstrømmen fra HealthKit."))
                            .font(.footnote).foregroundStyle(ATHLTHTheme.mutedText)
                        Text(tr("This screen does not confirm an external sensor is connected.", "Denne visningen bekrefter ikke at en ekstern sensor er tilkoblet."))
                            .font(.caption).foregroundStyle(ATHLTHTheme.mutedText)
                    }.padding(12)
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

}

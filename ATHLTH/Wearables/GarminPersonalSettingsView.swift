#if ATHLTH_GARMIN_PERSONAL && DEBUG
import SwiftUI

@MainActor
struct GarminPersonalSettingsView: View {
    let accountID: UUID
    @EnvironmentObject private var session: AppSessionStore
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var store = GarminPersonalLocalStore.shared
    @State private var key = ""

    private var accountMatches: Bool {
        scenePhase == .active && session.signedIn && !session.previewModeEnabled &&
        session.profile.userID == accountID && session.currentRole.canAccessControlCenter
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        ATHLTHSettingsScreen(title: "Garmin Connect",
            subtitle: tr("Private developer test", "Privat utviklertest")) {
            if accountMatches {
                ATHLTHSettingsGroup(title: tr("Connection", "Tilkobling")) {
                    PremiumSettingsCard {
                        PremiumSettingsRow(icon: "watch.analog", iconTint: ATHLTHTheme.accentDeep,
                            title: "Garmin Connect") {
                            Text(store.isConnected(to: accountID)
                                 ? tr("Connected", "Tilkoblet") : tr("Not connected", "Ikke tilkoblet"))
                                .font(.caption).foregroundStyle(ATHLTHTheme.mutedText)
                        }
                        SettingsDivider()
                        VStack(alignment: .leading, spacing: 12) {
                            Text(tr("Use your own personal key. Data stays on this device and is not shared with Coach or ATHLTH cloud services.", "Bruk din egen personlige nøkkel. Data blir på denne enheten og deles ikke med Coach eller ATHLTHs skytjenester."))
                                .font(.caption).foregroundStyle(ATHLTHTheme.mutedText)
                            Link(tr("Create or revoke personal key", "Opprett eller tilbakekall personlig nøkkel"),
                                 destination: URL(string: "https://connect.garmin.com/app/settings/personalApiToken")!)
                                .font(.subheadline.weight(.medium))
                            SecureField(tr("Personal API key", "Personlig API-nøkkel"), text: $key)
                                .textContentType(.password)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(12)
                                .background(ATHLTHTheme.premiumGoldSoft, in: RoundedRectangle(cornerRadius: 12))
                            Button {
                                guard accountMatches else { return }
                                let entered = key.trimmingCharacters(in: .whitespacesAndNewlines)
                                key = ""
                                store.connect(entered, account: accountID)
                            } label: {
                                Text(tr("Connect", "Koble til")).frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(ATHLTHTheme.accentDeep)
                            .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.busy || store.needsKeyRemoval)
                        }
                        .padding(16)
                    }
                }
                if store.isConnected(to: accountID) || (store.accountID == accountID && store.needsKeyRemoval) {
                    ATHLTHSettingsGroup(title: tr("Data and sync", "Data og synkronisering")) {
                        PremiumSettingsCard {
                            if store.isConnected(to: accountID) {
                                Picker(tr("Data source", "Datakilde"), selection: Binding(
                                    get: { store.preference(for: accountID) },
                                    set: { if accountMatches { store.setPreference($0, account: accountID) } }
                                )) {
                                    ForEach(WearableDisplayPreference.allCases) { value in
                                        Text(value.title).tag(value)
                                    }
                                }
                                .padding(16)
                                SettingsDivider()
                                Button {
                                    guard accountMatches else { return }
                                    store.refresh(account: accountID, force: true)
                                } label: {
                                    PremiumSettingsRow(icon: "arrow.clockwise", iconTint: ATHLTHTheme.accentDeep,
                                        title: tr("Refresh Garmin data", "Oppdater Garmin-data")) {
                                        if store.busy { ProgressView() }
                                    }
                                }.buttonStyle(.plain).disabled(store.busy)
                                SettingsDivider()
                            }
                            Button(role: .destructive) {
                                guard accountMatches else { return }
                                key = ""
                                store.disconnect(account: accountID)
                            } label: {
                                PremiumSettingsRow(icon: "link.badge.minus", iconTint: .red,
                                    title: tr("Disconnect and remove local key", "Koble fra og fjern lokal nøkkel"),
                                    titleColor: .red) { EmptyView() }
                            }.buttonStyle(.plain)
                        }
                    }
                }
                if store.accountID == accountID {
                    if store.busy { ProgressView() }
                    if let message = store.message { Text(message).font(.caption).foregroundStyle(ATHLTHTheme.mutedText) }
                    if let last = store.lastRefresh {
                        Text(tr("Last successful refresh", "Sist vellykkede synkronisering") + ": " + last.formatted())
                            .font(.caption).foregroundStyle(ATHLTHTheme.mutedText)
                    }
                }
                if let snapshot = store.snapshot(for: accountID) {
                    ATHLTHSettingsGroup(title: tr("Garmin measurements", "Garmin-målinger")) {
                        PremiumSettingsCard {
                            GarminPersonalMetricsView(snapshot: snapshot, expanded: true)
                        }
                    }
                    ATHLTHSettingsGroup(title: tr("Recent workouts · 30 days", "Siste økter · 30 dager")) {
                        PremiumSettingsCard {
                            GarminPersonalHistoryRows(snapshot: snapshot, existing: [], startDate: nil, endDate: nil)
                        }
                    }
                }
            } else {
                ContentUnavailableView(tr("Developer access required", "Utviklertilgang kreves"), systemImage: "lock")
            }
        }
        .task(id: accountMatches) {
            guard accountMatches else { key = ""; return }
            store.activate(account: accountID)
            store.refresh(account: accountID)
        }
        .onDisappear { key = "" }
    }
}
#endif

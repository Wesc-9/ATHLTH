#if ATHLTH_GARMIN_PERSONAL && (DEBUG || ATHLTH_GARMIN_INTERNAL_TEST)
import SwiftUI

@MainActor
struct GarminPersonalSettingsView: View {
    let accountID: UUID
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
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
                            SecureField(tr("Auth key · personal API key", "Auth key · personlig API-nøkkel"), text: $key)
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
                            Link(tr("Create or revoke personal key", "Opprett eller tilbakekall personlig nøkkel"),
                                 destination: URL(string: "https://connect.garmin.com/app/settings/personalApiToken")!)
                                .font(.subheadline.weight(.medium))
                            Text(tr("Use only your own key. Data stays on this device and is not shared with Coach or ATHLTH cloud services.", "Bruk kun din egen nøkkel. Data blir på denne enheten og deles ikke med Coach eller ATHLTHs skytjenester."))
                                .font(.caption).foregroundStyle(ATHLTHTheme.mutedText)
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
                ATHLTHSettingsGroup(title: tr("Supported functions", "Støttede funksjoner")) {
                    PremiumSettingsCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(tr("Personal workout and health data", "Personlige trenings- og helsedata"), systemImage: "heart.text.clipboard")
                            Label(tr("Local read-only preview", "Lokal, skrivebeskyttet forhåndsvisning"), systemImage: "lock.shield")
                            Label(tr("Live start, Audio Coach and workout/route transfer not available yet", "Live-start, Audio Coach og økt-/ruteoverføring er ikke tilgjengelig ennå"), systemImage: "info.circle")
                            Text(tr("Possible duplicates are flagged without deleting either record.", "Mulige duplikater markeres uten at noen av originaløktene slettes."))
                                .font(.caption).foregroundStyle(ATHLTHTheme.mutedText)
                        }
                        .font(.subheadline).foregroundStyle(ATHLTHTheme.primaryText)
                        .padding(16)
                    }
                }
                if store.accountID == accountID && !store.syncEvents.isEmpty {
                    ATHLTHSettingsGroup(title: tr("Sync history · this session", "Synkroniseringshistorikk · denne økten")) {
                        PremiumSettingsCard {
                            ForEach(store.syncEvents) { event in
                                PremiumSettingsRow(icon: event.success ? "checkmark.circle" : "exclamationmark.circle",
                                    iconTint: ATHLTHTheme.accentDeep, title: event.message,
                                    subtitle: event.date.formatted(date: .abbreviated, time: .shortened)) { EmptyView() }
                            }
                        }
                    }
                }
                if let snapshot = store.snapshot(for: accountID) {
                    ATHLTHSettingsGroup(title: tr("Preferred health sources · private preview", "Foretrukne helsekilder · privat visning")) {
                        PremiumSettingsCard {
                            ForEach(WearableDisplayMetric.allCases) { metric in
                                VStack(alignment: .leading, spacing: 6) {
                                    Picker(metric.title, selection: Binding(
                                        get: { store.preference(for: metric, account: accountID) },
                                        set: { if accountMatches { store.setPreference($0, metric: metric, account: accountID) } }
                                    )) {
                                        ForEach(WearableDisplayPreference.allCases) { value in
                                            Text(value.title).tag(value)
                                        }
                                    }
                                    Text(preferredReading(metric, snapshot: snapshot))
                                        .font(.caption).foregroundStyle(ATHLTHTheme.mutedText)
                                }
                                .padding(16)
                                if metric != WearableDisplayMetric.allCases.last { SettingsDivider() }
                            }
                            Text(tr("HRV methods differ between providers. Values are not averaged or combined; this preference changes only the private display.", "HRV-metodene er forskjellige. Verdiene slås ikke sammen eller gjennomsnittsberegnes; valget gjelder kun privat visning."))
                                .font(.caption).foregroundStyle(ATHLTHTheme.mutedText)
                                .padding(16)
                        }
                    }
                    ATHLTHSettingsGroup(title: tr("Garmin measurements", "Garmin-målinger")) {
                        PremiumSettingsCard {
                            GarminPersonalMetricsView(snapshot: snapshot, expanded: true)
                        }
                    }
                    ATHLTHSettingsGroup(title: tr("Recent workouts · 30 days", "Siste økter · 30 dager")) {
                        PremiumSettingsCard {
                            GarminPersonalHistoryRows(snapshot: snapshot, existing: [], startDate: nil, endDate: nil, healthWorkouts: health.workouts)
                                .padding(16)
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

    private func preferredReading(_ metric: WearableDisplayMetric, snapshot: GarminPersonalPreview) -> String {
        let apple: Double?
        let garmin: Double?
        switch metric {
        case .sleep: apple = health.sleep.totalAsleep; garmin = snapshot.sleepSeconds
        case .steps: apple = health.training.stepsToday.map(Double.init); garmin = snapshot.steps.map(Double.init)
        case .hrv: apple = health.heart.hrvMilliseconds; garmin = snapshot.overnightHRV
        case .restingHeartRate: apple = health.heart.restingHeartRate; garmin = snapshot.restingHeartRate
        }
        if Calendar.current.isDateInToday(snapshot.measurementDay),
           let reading = WearableDisplaySourcePolicy.garminReading(metric: metric, apple: apple,
            garmin: garmin, preference: store.preference(for: metric, account: accountID)) {
            return reading.formattedValue + " · " + reading.sourceLabel
        }
        if let apple, apple.isFinite, apple >= 0, metric == .steps || apple > 0 {
            let reading = GarminDisplayReading(metric: metric, value: apple)
            return reading.formattedValue + " · Apple Health"
        }
        return tr("No data available", "Ingen tilgjengelige data")
    }
}
#endif

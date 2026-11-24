#if ATHLTH_GARMIN_PERSONAL && DEBUG
import SwiftUI

@MainActor
struct GarminPersonalSettingsView: View {
    let accountID: UUID
    @EnvironmentObject private var session: AppSessionStore
    @ObservedObject private var store = GarminPersonalLocalStore.shared
    @State private var key = ""

    private var accountMatches: Bool {
        session.signedIn && !session.previewModeEnabled && session.profile.userID == accountID
    }

    var body: some View {
        Form {
            if accountMatches {
                Section("Garmin Connect – Private testing") {
                    Text("Use only your own Garmin account. Data stays on this device and is not sent to ATHLTH cloud services or Coach.")
                    Link("Create or revoke personal key", destination: URL(string: "https://connect.garmin.com/app/settings/personalApiToken")!)
                    SecureField("Personal API key", text: $key)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Connect") {
                        let entered = key.trimmingCharacters(in: .whitespacesAndNewlines)
                        key = ""
                        store.connect(entered, account: accountID)
                    }
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.busy)
                    if store.isConnected(to: accountID) {
                        Button("Refresh Garmin data") { store.refresh(account: accountID, force: true) }
                            .disabled(store.busy)
                        Button("Disconnect and remove local key", role: .destructive) {
                            key = ""
                            store.disconnect(account: accountID)
                        }
                    }
                    if store.accountID == accountID {
                        if store.busy { ProgressView() }
                        if let message = store.message { Text(message).font(.caption) }
                        if let last = store.lastRefresh {
                            LabeledContent("Last successful refresh", value: last.formatted())
                        }
                    }
                }
                if let snapshot = store.snapshot(for: accountID) {
                    Section("Garmin measurements") {
                        GarminPersonalMetricsView(snapshot: snapshot, expanded: true)
                    }
                    Section("Recent Garmin workouts · last 30 days") {
                        GarminPersonalHistoryRows(snapshot: snapshot, existing: [], startDate: nil, endDate: nil)
                    }
                }
            }
        }
        .navigationTitle("Garmin")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: accountMatches) {
            guard accountMatches else { key = ""; return }
            store.activate(account: accountID)
            store.refresh(account: accountID)
        }
        .onDisappear { key = "" }
    }
}
#endif

#if ATHLTH_GARMIN_PERSONAL && DEBUG
import SwiftUI

@MainActor
struct GarminPersonalSettingsView: View {
    let accountID: UUID
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: AppSessionStore
    @State private var key = ""
    @State private var saved = false
    @State private var busy = false
    @State private var message: String?
    @State private var preview: GarminPersonalPreview?
    @State private var syncTask: Task<Void, Never>?
    @State private var lastRefresh: Date?

    private var accountMatches: Bool {
        session.signedIn && !session.previewModeEnabled && session.profile.userID == accountID
    }

    var body: some View {
        Form {
            Section("Garmin Connect – Private testing") {
                Text("Use only your own Garmin account. Data is fetched directly to this device and is not sent to ATHLTH cloud services or Coach.")
                Link("Create or revoke personal key", destination: URL(string: "https://connect.garmin.com/app/settings/personalApiToken")!)
                SecureField("Personal API key", text: $key)
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Connect") { startSync(replacingKey: true) }
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy || !accountMatches)
                if saved {
                    Button("Refresh Garmin data") { startSync() }.disabled(busy || !accountMatches)
                    Button("Disconnect and remove local key", role: .destructive) { disconnect() }
                }
                if busy { ProgressView() }
                if let message { Text(message).font(.caption) }
                if let lastRefresh {
                    LabeledContent("Last successful refresh", value: lastRefresh.formatted())
                }
            }
            if let preview, accountMatches {
                Section("Today's Garmin measurements") {
                    metric("Steps", preview.steps.map(Double.init), unit: "")
                    metric("Sleep", preview.sleepSeconds.map { $0 / 3600 }, unit: "h")
                    metric("Resting heart rate", preview.restingHeartRate, unit: "bpm")
                    metric("Overnight Garmin HRV", preview.overnightHRV, unit: "ms")
                    metric("Average stress", preview.averageStress, unit: "")
                    metric("Body Battery daily high", preview.bodyBatteryHigh, unit: "")
                    metric("Body Battery daily low", preview.bodyBatteryLow, unit: "")
                    if preview.unavailableSections > 0 {
                        Text("Some Garmin endpoints were unavailable. Missing measurements are not estimated.")
                            .font(.caption)
                    }
                }
                Section("Recent Garmin workouts · last 30 days (max 500)") {
                    ForEach(preview.workouts, id: \.workout.id) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.originalActivityType.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.headline)
                            Text(item.workout.startedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                            Text(Duration.seconds(item.workout.duration).formatted(.units(allowed: [.hours, .minutes, .seconds])))
                                .font(.subheadline)
                            if let distance = item.workout.distanceMeters {
                                Text((distance / 1000).formatted(.number.precision(.fractionLength(2))) + " km")
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Garmin")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard accountMatches else { return }
            do { saved = try GarminPersonalKeychain.read(accountID) != nil }
            catch { message = "Unable to access the local Keychain." }
            if saved { startSync() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && saved && !busy && accountMatches &&
                (lastRefresh?.timeIntervalSinceNow ?? -.infinity) < -300 { startSync() }
        }
        .onChange(of: accountMatches) { _, matches in
            if !matches { clearPreview() }
        }
        .onDisappear { clearPreview() }
    }

    private func metric(_ title: String, _ value: Double?, unit: String) -> some View {
        let valid = value.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        return LabeledContent(title, value: valid.map {
            $0.formatted(.number.precision(.fractionLength(0...1))) + (unit.isEmpty ? "" : " " + unit)
        } ?? "—")
    }

    private func startSync(replacingKey: Bool = false) {
        guard accountMatches, !busy else { return }
        busy = true
        message = nil
        preview = nil
        let entered = key.trimmingCharacters(in: .whitespacesAndNewlines)
        key = ""
        syncTask = Task { @MainActor in
            let client = GarminPersonalClient()
            defer { client.close(); busy = false }
            do {
                let credential: String
                if replacingKey { credential = entered }
                else if let stored = try GarminPersonalKeychain.read(accountID) { credential = stored }
                else { saved = false; return }
                let result = try await client.preview(key: credential)
                try Task.checkCancellation()
                guard accountMatches else { return }
                if replacingKey { try GarminPersonalKeychain.save(credential, account: accountID) }
                saved = true
                preview = result
                lastRefresh = Date()
                message = "Garmin data refreshed on this device."
            } catch is CancellationError {
                return
            } catch GarminPersonalClientError.unauthorized {
                if !Task.isCancelled && accountMatches { message = "Garmin rejected access. Check or replace your key." }
            } catch GarminPersonalClientError.throttled {
                if !Task.isCancelled && accountMatches { message = "Garmin rate limit reached. Try again later." }
            } catch {
                if !Task.isCancelled && accountMatches { message = "Garmin sync failed. Check your connection or key." }
            }
        }
    }

    private func clearPreview() {
        syncTask?.cancel()
        key = ""
        preview = nil
        lastRefresh = nil
        message = nil
    }

    private func disconnect() {
        clearPreview()
        do {
            try GarminPersonalKeychain.remove(accountID)
            saved = false
            message = "Local access removed. Revoke the key in Garmin Connect if you no longer need it."
        } catch { message = "Unable to remove the local key. Please try again." }
    }
}
#endif

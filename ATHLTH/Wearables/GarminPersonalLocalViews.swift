#if ATHLTH_GARMIN_PERSONAL && DEBUG
import SwiftUI

enum GarminPersonalSurface {
    case home, insights
}

/// Separate Garmin measurements, not a merged Apple Health or AI readiness score.
@MainActor
struct GarminPersonalLocalCard: View {
    let surface: GarminPersonalSurface
    let isActive: Bool
    @EnvironmentObject private var session: AppSessionStore
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var store = GarminPersonalLocalStore.shared
    private var account: UUID? {
        isActive && scenePhase == .active && session.signedIn && !session.previewModeEnabled
            ? session.profile.userID : nil
    }
    var body: some View {
        if let account, store.isConnected(to: account) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(surface == .home ? "Garmin · Dagens form" : "Garmin · Innsikt",
                          systemImage: "watch.analog")
                        .font(.headline)
                    Spacer()
                    Button {
                        store.refresh(account: account, force: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(store.busy)
                    .accessibilityLabel("Oppdater Garmin")
                }
                if let snapshot = store.snapshot(for: account) {
                    GarminPersonalMetricsView(snapshot: snapshot, expanded: surface == .insights)
                    if let last = store.lastRefresh {
                        Text("Oppdatert " + last.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                } else if store.busy {
                    ProgressView()
                } else {
                    Text(store.message ?? "Ingen Garmin-data tilgjengelig.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let message = store.message, store.snapshot(for: account) != nil {
                    Text(message).font(.caption2).foregroundStyle(.secondary)
                }
                Text("Privat · Garmin Connect · vises separat fra Apple Helse")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ATHLTHUnifiedDesign.surface, in: RoundedRectangle(cornerRadius: 20))
            .task(id: account) {
                guard self.account == account else { return }
                store.refresh(account: account)
            }
        }
    }
}

struct GarminPersonalMetricsView: View {
    let snapshot: GarminPersonalPreview
    let expanded: Bool
    var body: some View {
        if Calendar.current.isDateInToday(snapshot.measurementDay) {
            metric("Skritt", snapshot.steps.map(Double.init), unit: "")
            metric("Søvn", snapshot.sleepSeconds.map { $0 / 3600 }, unit: "t")
            metric("Hvilepuls", snapshot.restingHeartRate, unit: "bpm")
            metric("Garmin natt-HRV", snapshot.overnightHRV, unit: "ms")
            if expanded {
                metric("Gjennomsnittlig stress", snapshot.averageStress, unit: "")
                metric("Body Battery · høyeste", snapshot.bodyBatteryHigh, unit: "")
                metric("Body Battery · laveste", snapshot.bodyBatteryLow, unit: "")
            }
            if snapshot.unavailableSections > 0 {
                Text("Noen målinger er ikke tilgjengelige.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else {
            Text("Dagens Garmin-data må oppdateres.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func metric(_ title: String, _ value: Double?, unit: String) -> some View {
        let valid = value.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        return LabeledContent(title, value: valid.map {
            $0.formatted(.number.precision(.fractionLength(0...1))) + (unit.isEmpty ? "" : " " + unit)
        } ?? "—")
        .font(.subheadline)
    }
}

@MainActor
struct GarminPersonalHistoryEntry: View {
    let existing: [SocialPublishableWorkout]
    let startDate: Date?
    let endDate: Date?
    @EnvironmentObject private var session: AppSessionStore
    @ObservedObject private var store = GarminPersonalLocalStore.shared
    @Environment(\.scenePhase) private var scenePhase
    private var account: UUID? {
        scenePhase == .active && session.signedIn && !session.previewModeEnabled
            ? session.profile.userID : nil
    }
    var body: some View {
        if let account, store.isConnected(to: account) {
            NavigationLink {
                GarminPersonalHistoryScreen(accountID: account, existing: existing,
                                            startDate: startDate, endDate: endDate)
            } label: {
                Label("Garmin · privat treningshistorikk", systemImage: "watch.analog")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(ATHLTHUnifiedDesign.surface, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
    }
}

@MainActor
private struct GarminPersonalHistoryScreen: View {
    let accountID: UUID
    let existing: [SocialPublishableWorkout]
    let startDate: Date?
    let endDate: Date?
    @EnvironmentObject private var session: AppSessionStore
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var store = GarminPersonalLocalStore.shared
    private var accountMatches: Bool {
        scenePhase == .active && session.signedIn && !session.previewModeEnabled &&
        session.profile.userID == accountID
    }
    var body: some View {
        List {
            if accountMatches && store.isConnected(to: accountID) {
                if let snapshot = store.snapshot(for: accountID) {
                    GarminPersonalHistoryRows(snapshot: snapshot, existing: existing,
                                              startDate: startDate, endDate: endDate)
                } else if store.busy {
                    ProgressView()
                } else {
                    Text(store.message ?? "Ingen Garmin-økter tilgjengelig.")
                }
            }
        }
        .navigationTitle("Garmin")
        .task(id: accountMatches) {
            guard accountMatches else { return }
            store.refresh(account: accountID)
        }
        .refreshable {
            guard accountMatches else { return }
            store.refresh(account: accountID, force: true)
        }
    }
}

struct GarminPersonalHistoryRows: View {
    let snapshot: GarminPersonalPreview
    let existing: [SocialPublishableWorkout]
    let startDate: Date?
    let endDate: Date?
    private var workouts: [GarminImportedActivity] {
        snapshot.workouts.filter { item in
            (startDate.map { item.workout.startedAt >= $0 } ?? true) &&
            (endDate.map { item.workout.startedAt <= $0 } ?? true)
        }
    }
    var body: some View {
        Text("Garmin · siste 30 dager. Øktene vises separat og inngår ikke i ATHLTHs summer.")
            .font(.caption).foregroundStyle(.secondary)
        if snapshot.historyPossiblyTruncated {
            Text("Importgrensen på 500 økter er nådd. Historikken kan være ufullstendig.")
                .font(.caption).foregroundStyle(.secondary)
        }
        ForEach(workouts, id: \.workout.id) { item in
            VStack(alignment: .leading, spacing: 5) {
                Text(item.originalActivityType.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.headline)
                Text(item.workout.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                Text(Duration.seconds(item.workout.duration).formatted(.units(allowed: [.hours, .minutes, .seconds])))
                if let distance = item.workout.distanceMeters {
                    Text((distance / 1000).formatted(.number.precision(.fractionLength(2))) + " km")
                }
                if let heartRate = item.workout.averageHeartRate {
                    Text(heartRate.formatted(.number.precision(.fractionLength(0))) + " bpm")
                }
                if existing.contains(where: { GarminHistoryMatchPolicy.possibleMatch(item.workout, $0) }) {
                    Label("Mulig duplikat i Apple Helse / ATHLTH", systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        if workouts.isEmpty { Text("Ingen Garmin-økter i valgt periode.") }
    }
}
#endif

#if ATHLTH_GARMIN_PERSONAL && DEBUG
import SwiftUI

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
@MainActor
struct GarminExistingMetricDetailView: View {
    let kind: HomeHealthMetricKind
    let accountID: UUID
    @EnvironmentObject private var session: AppSessionStore
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var store = GarminPersonalLocalStore.shared
    private var reading: GarminDisplayReading? {
        guard scenePhase == .active, session.signedIn, !session.previewModeEnabled,
              session.profile.userID == accountID, let snapshot = store.snapshot(for: accountID),
              Calendar.current.isDateInToday(snapshot.measurementDay) else { return nil }
        switch kind {
        case .sleep:
            return WearableDisplaySourcePolicy.garminReading(metric: .sleep, apple: nil, garmin: snapshot.sleepSeconds, preference: .garmin)
        case .steps:
            return WearableDisplaySourcePolicy.garminReading(metric: .steps, apple: nil, garmin: snapshot.steps.map(Double.init), preference: .garmin)
        case .hrv:
            return WearableDisplaySourcePolicy.garminReading(metric: .hrv, apple: nil, garmin: snapshot.overnightHRV, preference: .garmin)
        default: return nil
        }
    }
    var body: some View {
        Form {
            Section("Siste verdi") {
                LabeledContent(kind.title, value: reading?.formattedValue ?? "—")
                LabeledContent("Kilde", value: reading?.sourceLabel ?? "Garmin")
                Text("Historiske trender fra Garmin er ikke tilgjengelige ennå.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if kind == .hrv {
                Text("Garmin natt-HRV vises separat fra Apple Helses HRV-metode. Verdiene blandes ikke i en grunnlinje.")
                    .font(.caption)
            }
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct GarminExistingWorkoutRow: View {
    let item: GarminImportedActivity
    let possibleDuplicate: Bool
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: GarminHistoryMatchPolicy.activity(for: item).icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.accent)
                .frame(width: 42, height: 42)
                .background(ATHLTHTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.originalActivityType.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.subheadline.weight(.semibold))
                Text(item.workout.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2).foregroundStyle(.secondary)
                if possibleDuplicate {
                    Text("Mulig duplikat").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(Duration.seconds(item.workout.duration).formatted(.units(allowed: [.hours, .minutes])))
                    .font(.caption.weight(.semibold))
                Text("Garmin").font(.caption2).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").font(.caption2.bold()).foregroundStyle(.secondary)
        }
    }
}

@MainActor
struct GarminReadOnlyWorkoutDetail: View {
    let accountID: UUID
    let activityID: String
    @EnvironmentObject private var session: AppSessionStore
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var store = GarminPersonalLocalStore.shared
    private var activity: GarminImportedActivity? {
        guard scenePhase == .active, session.signedIn, !session.previewModeEnabled,
              session.profile.userID == accountID else { return nil }
        return store.snapshot(for: accountID)?.workouts.first { $0.workout.id == activityID }
    }
    var body: some View {
        Form {
            if let activity {
                Section("Økta i tall") {
                    LabeledContent("Aktivitet", value: activity.originalActivityType)
                    LabeledContent("Dato", value: activity.workout.startedAt.formatted())
                    LabeledContent("Tid", value: Duration.seconds(activity.workout.duration).formatted(.units(allowed: [.hours, .minutes, .seconds])))
                    if let distance = activity.workout.distanceMeters {
                        LabeledContent("Distanse", value: (distance / 1000).formatted(.number.precision(.fractionLength(2))) + " km")
                    }
                    if let pulse = activity.workout.averageHeartRate {
                        LabeledContent("Gjennomsnittspuls", value: pulse.formatted() + " bpm")
                    }
                    LabeledContent("Kilde", value: "Garmin")
                }
            } else {
                Text("Økten er ikke tilgjengelig.")
            }
        }
        .navigationTitle("Øktdetaljer")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif

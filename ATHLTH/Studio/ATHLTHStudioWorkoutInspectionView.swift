import SwiftUI
@preconcurrency import HealthKit

/// Native iOS 27 zone readings use the local HealthKit store only.
/// Workout and HR read authorization must already be granted in ATHLTH.
/// An empty result cannot distinguish no data from denied read permission.
struct ATHLTHStudioWorkoutInspectionView: View {
    let workout: WorkoutSummary
    @State private var heartRateZones: [ZoneDuration] = []
    @State private var zoneLoading = false

    private struct ZoneDuration: Identifiable, Sendable {
        let index: Int
        let seconds: TimeInterval
        var id: Int { index }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(workout.activity.rawValue)
                    .font(.title2.weight(.semibold))
                Text(workout.startDate.formatted(date: .complete, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                LabeledContent(
                    ATHLTHLocalization.choose(english: "Duration", norwegian: "Varighet"),
                    value: "\(Int(workout.duration / 60)) min"
                )
                if let distance = workout.distanceKilometers {
                    LabeledContent(
                        ATHLTHLocalization.choose(english: "Distance", norwegian: "Distanse"),
                        value: String(format: "%.2f km", distance)
                    )
                }
                if let energy = workout.activeEnergyKilocalories {
                    LabeledContent(
                        ATHLTHLocalization.choose(english: "Active energy", norwegian: "Aktiv energi"),
                        value: "\(Int(energy)) kcal"
                    )
                }
                Divider()
                HStack(spacing: 9) {
                    Image(systemName: "heart.text.square")
                        .foregroundStyle(ATHLTHStudioStyle.gold)
                    Text(ATHLTHLocalization.choose(
                        english: "Native HealthKit heart-rate zones",
                        norwegian: "Pulssoner fra Apple HealthKit"
                    ))
                    .font(.headline)
                }
                if #available(iOS 27, *) {
                    if zoneLoading {
                        ProgressView()
                    } else if heartRateZones.isEmpty {
                        Text(ATHLTHLocalization.choose(
                            english: "No native zone data available for this workout. Health access, supported watchOS, and recorded samples may vary.",
                            norwegian: "Ingen native sonedata tilgjengelig for denne økten. Tilgang, watchOS-versjon og registrerte målinger kan variere."
                        ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    } else {
                        let maxSeconds = max(1, heartRateZones.map(\.seconds).max() ?? 1)
                        ForEach(heartRateZones) { entry in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text("\(ATHLTHLocalization.choose(english: "Zone", norwegian: "Sone")) \(entry.index + 1)")
                                    Spacer()
                                    Text("\(Int(entry.seconds / 60)) min")
                                        .foregroundStyle(.secondary)
                                }
                                .font(.caption)
                                GeometryReader { geometry in
                                    Capsule().fill(ATHLTHStudioStyle.outline.opacity(0.45))
                                        .overlay(alignment: .leading) {
                                            Capsule()
                                                .fill(ATHLTHStudioStyle.gold)
                                                .frame(width: max(0, geometry.size.width * entry.seconds / maxSeconds))
                                        }
                                }
                                .frame(height: 8)
                            }
                        }
                        Text(ATHLTHLocalization.choose(
                            english: "Zone boundaries may differ between workouts; the values above use Apple's recorded durations.",
                            norwegian: "Sonegrensene kan variere mellom økter. Verdiene er varigheten Apple har registrert."
                        ))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                } else {
                    Text(ATHLTHLocalization.choose(
                        english: "Native workout zones require iOS/iPadOS 27 or later.",
                        norwegian: "Native treningssoner krever iOS/iPadOS 27 eller nyere."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(22)
        }
        .task(id: workout.id) {
            await loadNativeZones()
        }
    }

    private func loadNativeZones() async {
        heartRateZones = []
        guard #available(iOS 27, *), HKHealthStore.isHealthDataAvailable() else { return }
        zoneLoading = true
        defer { zoneLoading = false }
        let id = workout.id
        let rows: [ZoneDuration] = await withCheckedContinuation {
            (continuation: CheckedContinuation<[ZoneDuration], Never>) in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: HKQuery.predicateForObject(with: id),
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, _ in
                guard let sample = samples?.first as? HKWorkout else {
                    continuation.resume(returning: [])
                    return
                }
                if #available(iOS 27, *),
                   let group = sample.zoneGroupsByType?[HKQuantityType(.heartRate)] {
                    let values = group.zoneDurations.map {
                        ZoneDuration(index: $0.zone.index, seconds: $0.duration)
                    }
                    continuation.resume(returning: values)
                } else {
                    continuation.resume(returning: [])
                }
            }
            HKHealthStore().execute(query)
        }
        guard !Task.isCancelled else { return }
        heartRateZones = rows
    }
}

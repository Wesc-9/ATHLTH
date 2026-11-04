import SwiftUI
@preconcurrency import HealthKit

/// Studio reads Apple's stored workout zones directly from HealthKit.
/// No zone history is sent to ATHLTH servers or synthesized from a readiness
/// model. Empty HealthKit queries do not reveal whether read access was denied.
struct ATHLTHStudioWorkoutInspectionView: View {
    let workout: WorkoutSummary
    @State private var nativeGroups: [NativeZoneGroup] = []
    @State private var zoneLoading = false

    private enum Metric: String, Sendable {
        case heartRate, cyclingPower

        var title: String {
            switch self {
            case .heartRate:
                ATHLTHLocalization.choose(
                    english: "Heart-rate zones", norwegian: "Pulssoner"
                )
            case .cyclingPower:
                ATHLTHLocalization.choose(
                    english: "Cycling power zones", norwegian: "Effektsoner for sykling"
                )
            }
        }

        var unitLabel: String {
            switch self {
            case .heartRate: "bpm"
            case .cyclingPower: "W"
            }
        }
    }

    private struct ZoneDuration: Identifiable, Sendable {
        let ordinal: Int
        let seconds: TimeInterval
        let minValue: Double?
        let maxValue: Double?
        var id: Int { ordinal }
    }

    private struct NativeZoneGroup: Identifiable, Sendable {
        let metric: Metric
        let source: String
        let zones: [ZoneDuration]
        var id: String { metric.rawValue }
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
                        english: "Native HealthKit workout zones",
                        norwegian: "Treningssoner fra Apple HealthKit"
                    ))
                    .font(.headline)
                }
                if #available(iOS 27, *) {
                    if zoneLoading {
                        ProgressView()
                    } else if nativeGroups.isEmpty {
                        Text(ATHLTHLocalization.choose(
                            english: "No native zone data is available for this workout. Health permissions, recording source, and OS version may affect availability.",
                            norwegian: "Ingen native sonedata er tilgjengelige for økten. Health-tillatelser, datakilde og OS-versjon kan påvirke tilgjengeligheten."
                        ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    } else {
                        ForEach(nativeGroups) { group in
                            zoneGroupCard(group)
                        }
                        Text(ATHLTHLocalization.choose(
                            english: "These are Apple's recorded zone durations. Zone thresholds can vary between workouts; compare them only when configurations match.",
                            norwegian: "Dette er sonetider registrert av Apple. Sonegrenser kan variere mellom økter. Sammenlign bare økter med tilsvarende soneoppsett."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } else {
                    Text(ATHLTHLocalization.choose(
                        english: "Native heart-rate and cycling power zones require iOS/iPadOS 27 or later.",
                        norwegian: "Native puls- og effektsoner krever iOS/iPadOS 27 eller nyere."
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

    private func zoneGroupCard(_ group: NativeZoneGroup) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(group.metric.title)
                .font(.headline)
            Text(ATHLTHLocalization.choose(
                english: "Zone configuration: \(group.source)",
                norwegian: "Kilde til soneoppsett: \(group.source)"
            ))
            .font(.caption)
            .foregroundStyle(.secondary)

            let maxSeconds = max(1, group.zones.map(\.seconds).max() ?? 1)
            ForEach(group.zones) { entry in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text("\(ATHLTHLocalization.choose(english: "Zone", norwegian: "Sone")) \(entry.ordinal)")
                            .font(.subheadline.weight(.medium))
                        Text(zoneRangeText(entry, metric: group.metric))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(entry.seconds / 60)) min")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                    }
                    GeometryReader { geometry in
                        Capsule()
                            .fill(ATHLTHStudioStyle.outline.opacity(0.45))
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(ATHLTHStudioStyle.gold)
                                    .frame(width: max(0, geometry.size.width * entry.seconds / maxSeconds))
                            }
                    }
                    .frame(height: 8)
                }
            }
        }
        .padding(15)
        .background(ATHLTHStudioStyle.canvas, in: RoundedRectangle(cornerRadius: 16))
    }

    private func zoneRangeText(_ zone: ZoneDuration, metric: Metric) -> String {
        let suffix = metric.unitLabel
        switch (zone.minValue, zone.maxValue) {
        case let (lower?, upper?):
            return "\(Int(lower.rounded()))–\(Int(upper.rounded())) \(suffix)"
        case let (nil, upper?):
            return "< \(Int(upper.rounded())) \(suffix)"
        case let (lower?, nil):
            return "≥ \(Int(lower.rounded())) \(suffix)"
        default:
            return suffix
        }
    }

    private func loadNativeZones() async {
        nativeGroups = []
        guard #available(iOS 27, *),
              HKHealthStore.isHealthDataAvailable()
        else { return }
        zoneLoading = true
        defer { zoneLoading = false }

        let id = workout.id
        let result: [NativeZoneGroup] = await withCheckedContinuation {
            (continuation: CheckedContinuation<[NativeZoneGroup], Never>) in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: HKQuery.predicateForObject(with: id),
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, _ in
                guard let saved = samples?.first as? HKWorkout else {
                    continuation.resume(returning: [])
                    return
                }
                guard #available(iOS 27, *) else {
                    continuation.resume(returning: [])
                    return
                }

                let metrics: [(Metric, HKQuantityType, HKUnit)] = [
                    (.heartRate, HKQuantityType(.heartRate),
                     HKUnit.count().unitDivided(by: .minute())),
                    (.cyclingPower, HKQuantityType(.cyclingPower), .watt())
                ]
                var groups: [NativeZoneGroup] = []
                for (metric, quantity, unit) in metrics {
                    guard let group = saved.zoneGroupsByType?[quantity],
                          !group.zoneDurations.isEmpty
                    else { continue }

                    let entries = group.zoneDurations.enumerated().map { offset, duration in
                        ZoneDuration(
                            ordinal: offset + 1,
                            seconds: duration.duration,
                            minValue: duration.zone.minimum?.doubleValue(for: unit),
                            maxValue: duration.zone.maximum?.doubleValue(for: unit)
                        )
                    }
                    groups.append(NativeZoneGroup(
                        metric: metric,
                        source: String(describing: group.configuration.source),
                        zones: entries
                    ))
                }
                continuation.resume(returning: groups)
            }
            HKHealthStore().execute(query)
        }
        guard !Task.isCancelled else { return }
        nativeGroups = result
    }
}

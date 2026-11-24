import Charts
import CoreLocation
import SwiftUI

/// Two completed runs on the same normalized route-progress axis.
/// Only GPS altitude is drawn as a curve; summary HR and average pace are
/// labelled as whole-workout averages, never presented as per-split samples.
struct ATHLTHStudioWorkoutComparisonLabView: View {
    let workouts: [WorkoutSummary]
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var session: AppSessionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var details: [UUID: WorkoutDetail] = [:]
    @State private var cachedElevationPoints: [ElevationPoint] = []
    @State private var intervalRecords: [ATHLTHCompletedRunningPerformance] = []
    @State private var loading = false
    @State private var markerProgress = 50.0

    private struct ElevationPoint: Identifiable {
        let run: Int
        let percent: Double
        let altitude: Double
        var id: String { "\(run)-\(percent)" }
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var points: [ElevationPoint] { cachedElevationPoints }

    private struct IntervalPoint: Identifiable {
        let run: Int
        let index: Int
        let speed: Double
        var id: String { "\(run)-\(index)" }
    }

    /// Compare only recorded efforts with an exact local/HealthKit identity.
    /// Never substitute planned target speed or match an ambiguous session.
    private var intervalPoints: [IntervalPoint] {
        guard intervalRecords.count == 2 else { return [] }
        let first = intervalRecords[0].workSteps
        let second = intervalRecords[1].workSteps
        guard first.count >= 2, first.count == second.count,
              first.count <= 80,
              ATHLTHWorkoutSearch.normalized(intervalRecords[0].title) ==
                ATHLTHWorkoutSearch.normalized(intervalRecords[1].title)
        else { return [] }
        return intervalRecords.enumerated().flatMap { run, record in
            record.workSteps.enumerated().compactMap { index, step in
                guard let speed = step.actualSpeedKilometersPerHour,
                      speed.isFinite, speed > 0 else { return nil }
                return IntervalPoint(run: run, index: index + 1, speed: speed)
            }
        }
    }

    private func makeElevationPoints(
        from loaded: [UUID: WorkoutDetail]
    ) -> [ElevationPoint] {
        workouts.enumerated().flatMap { index, workout in
            guard let route = loaded[workout.id]?.route, route.count >= 3 else {
                return [ElevationPoint]()
            }
            // Discard invalid altitude measurements and avoid gigantic
            // Chart datasets when a GPS workout contains thousands of points.
            let samples = route.filter {
                $0.altitude.isFinite && $0.verticalAccuracy >= 0 &&
                $0.coordinate.latitude.isFinite &&
                $0.coordinate.longitude.isFinite
            }
            guard samples.count >= 3 else { return [] }
            var progress: [Double] = [0]
            for k in 1..<samples.count {
                let step = samples[k].distance(from: samples[k - 1])
                progress.append(progress.last! +
                    (step.isFinite && step >= 0 && step < 1_000 ? step : 0))
            }
            guard let total = progress.last, total > 50 else { return [] }
            let strideLength = max(1, samples.count / 220)
            return stride(from: 0, to: samples.count, by: strideLength).map {
                ElevationPoint(
                    run: index,
                    percent: progress[$0] / total * 100,
                    altitude: samples[$0].altitude
                )
            }
        }
    }

    private var hasTwoUsableAltitudeProfiles: Bool {
        guard workouts.count == 2 else { return false }
        let grouped = Set(points.map(\.run))
        return grouped.contains(0) && grouped.contains(1) &&
            points.filter { $0.run == 0 }.count >= 3 &&
            points.filter { $0.run == 1 }.count >= 3
    }

    private func pace(_ workout: WorkoutSummary) -> String {
        guard let km = workout.distanceKilometers, km > 0.25,
              workout.duration.isFinite, workout.duration > 0 else { return "—" }
        let seconds = workout.duration / km
        guard (120...3_600).contains(seconds) else { return "—" }
        let rounded = Int(seconds.rounded())
        return String(format: "%d:%02d /km", rounded / 60, rounded % 60)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Label(tr("WORKOUT LAB", "ØKTLABORATORIUM"),
                              systemImage: "waveform.path.ecg")
                            .font(.caption.weight(.bold))
                            .tracking(1.4)
                            .foregroundStyle(ATHLTHStudioStyle.gold)
                        Text(tr("Compare recorded runs at the same course progress",
                                "Sammenlign løpeturer ved samme ruteprogresjon"))
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(ATHLTHStudioStyle.ink)

                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 13) {
                                ForEach(Array(workouts.enumerated()), id: \.element.id) {
                                    index, workout in
                                    comparisonCard(workout, index: index)
                                }
                            }
                            VStack(spacing: 13) {
                                ForEach(Array(workouts.enumerated()), id: \.element.id) {
                                    index, workout in
                                    comparisonCard(workout, index: index)
                                }
                            }
                        }

                        if !intervalPoints.isEmpty {
                            intervalComparisonCard(wide: geo.size.width >= 800 && !dynamicTypeSize.isAccessibilitySize)
                        }

                        VStack(alignment: .leading, spacing: 13) {
                            Text(tr("Elevation along each recorded GPS route",
                                    "Høyde langs hver registrerte GPS-rute"))
                                .font(.headline)
                            if hasTwoUsableAltitudeProfiles {
                                Chart {
                                    ForEach(points) { point in
                                        LineMark(
                                            x: .value("Course %", point.percent),
                                            y: .value("Altitude (m)", point.altitude),
                                            series: .value("Run", point.run)
                                        )
                                        .foregroundStyle(point.run == 0
                                            ? ATHLTHStudioStyle.gold :
                                                ATHLTHStudioStyle.ink)
                                    }
                                    RuleMark(x: .value("Selected %", markerProgress))
                                        .foregroundStyle(ATHLTHStudioStyle.outline)
                                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                }
                                .frame(height: geo.size.width >= 800 ? 300 : 210)
                                Slider(value: $markerProgress, in: 0...100, step: 5) {
                                    Text(tr("Route position", "Posisjon på ruten"))
                                }
                                HStack {
                                    Text(tr("Start", "Start"))
                                    Spacer()
                                    Text("\(Int(markerProgress))%")
                                        .font(.subheadline.monospacedDigit())
                                    Spacer()
                                    Text(tr("Finish", "Mål"))
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            } else if loading {
                                ProgressView(tr("Reading recorded GPS routes…",
                                                "Henter registrerte GPS-ruter…"))
                            } else {
                                Text(tr(
                                    "Both runs need usable GPS altitude to show a comparison. Missing HealthKit routes are not interpolated or invented.",
                                    "Begge løp trenger brukbare GPS-høydedata for å kunne sammenlignes. Manglende HealthKit-ruter beregnes eller diktes ikke opp."
                                ))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            }
                            Text(tr(
                                "Altitude is aligned by percentage of each recorded route. It is not a comparison of the same geographical point unless the routes match.",
                                "Høyden er justert etter prosent av hver registrerte rute. Det er ikke samme geografiske punkt med mindre rutene er identiske."
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(18)
                        .background(.white, in: RoundedRectangle(cornerRadius: 20))
                        Text(tr(
                            "Heart-rate numbers are whole-workout averages and peaks. Per-second pulse and pace curves are not shown until their actual HealthKit samples can be paired reliably.",
                            "Pulsverdiene er gjennomsnitt og topper for hele økten. Puls- og tempokurver per sekund vises ikke før de faktiske HealthKit-målingene kan kobles sikkert."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 1_150, alignment: .leading)
                    .padding(geo.size.width < 650 ? 14 : 28)
                    .frame(maxWidth: .infinity)
                }
                .background(ATHLTHStudioStyle.canvas.ignoresSafeArea())
            }
            .navigationTitle(tr("Workout Lab", "Øktlaboratorium"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done", "Ferdig")) { dismiss() }
                }
            }
            .task(id: session.profile.userID.uuidString + workouts.map(\.id).map(\.uuidString).joined()) {
                guard workouts.count == 2 else { return }
                loading = true
                cachedElevationPoints = []
                details = [:]
                intervalRecords = []
                let history = ATHLTHRunningPerformanceHistory.load(userID: session.profile.userID)
                let matched = workouts.compactMap { workout -> ATHLTHCompletedRunningPerformance? in
                    let exact = history.filter { $0.healthWorkoutUUID == workout.id || $0.id == workout.id }
                    return exact.count == 1 ? exact.first : nil
                }
                if matched.count == 2, matched[0].id != matched[1].id {
                    intervalRecords = matched
                }
                defer { loading = false }
                var loaded: [UUID: WorkoutDetail] = [:]
                for workout in workouts {
                    guard !Task.isCancelled else { return }
                    loaded[workout.id] = await health.workoutDetail(for: workout)
                }
                guard !Task.isCancelled else { return }
                cachedElevationPoints = makeElevationPoints(from: loaded)
                details = loaded
            }
            .accessibilityIdentifier("athlth-ipad-workout-lab")
        }
    }

    private func intervalComparisonCard(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("Recorded effort speeds", "Registrert fart per drag"))
                .font(.headline)
            Chart(intervalPoints) { point in
                BarMark(
                    x: .value(tr("Effort", "Drag"), String(point.index)),
                    y: .value("km/t", point.speed)
                )
                .position(by: .value("Session", point.run))
                .foregroundStyle(point.run == 0 ? ATHLTHStudioStyle.gold : ATHLTHStudioStyle.ink)
            }
            .frame(height: wide ? 250 : 180)
            ForEach(Array(intervalRecords.enumerated()), id: \.element.id) { index, record in
                HStack {
                    Circle().fill(index == 0 ? ATHLTHStudioStyle.gold : ATHLTHStudioStyle.ink)
                        .frame(width: 9, height: 9)
                    Text(record.completedAt.formatted(date: .abbreviated, time: .shortened))
                    Spacer()
                    if let speed = record.averageWorkSpeed {
                        Text(String(format: "%.1f km/t", speed)).monospacedDigit()
                    }
                }
                .font(.caption)
            }
            Text(tr("Efforts are aligned by their recorded order. Missing measured speeds are omitted; treadmill data may be user reported.",
                    "Dragene sammenlignes etter registrert rekkefølge. Manglende fart vises ikke; tredemølleverdier kan være manuelt registrert."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityIdentifier("athlth-ipad-compare-recorded-intervals")
    }

    private func comparisonCard(
        _ workout: WorkoutSummary, index: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Circle()
                    .fill(index == 0
                        ? ATHLTHStudioStyle.gold : ATHLTHStudioStyle.ink)
                    .frame(width: 10, height: 10)
                Text(workout.startDate.formatted(
                    date: .abbreviated, time: .shortened
                ))
                .font(.headline)
            }
            LabeledContent(tr("Duration", "Varighet"),
                           value: "\(Int(workout.duration / 60)) min")
            LabeledContent(tr("Distance", "Distanse"),
                value: workout.distanceKilometers.map {
                    String(format: "%.2f km", $0)
                } ?? "—"
            )
            LabeledContent(tr("Average pace", "Snittempo"),
                           value: pace(workout))
            LabeledContent(tr("Average heart rate", "Snittpuls"),
                value: details[workout.id]?.averageHeartRate.map {
                    "\(Int($0.rounded())) bpm"
                } ?? "—"
            )
            LabeledContent(tr("Peak heart rate", "Makspuls"),
                value: details[workout.id]?.maxHeartRate.map {
                    "\(Int($0.rounded())) bpm"
                } ?? "—"
            )
        }
        .font(.subheadline)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
    }
}

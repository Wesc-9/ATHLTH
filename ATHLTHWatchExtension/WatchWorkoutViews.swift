import MapKit
import SwiftUI

struct WatchWorkoutStartView: View {
    @EnvironmentObject private var workoutManager: WatchWorkoutManager

    let route: WatchRouteTransfer?

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if let route {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(route.title)
                            .font(.headline)
                        Text(String(format: "%.1f km route", route.distanceKilometers))
                            .font(.caption2)
                            .foregroundStyle(WatchTheme.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(11)
                    .watchSurface()
                }

                workoutButton(.running)
                workoutButton(.walking)

                if route == nil {
                    workoutButton(.strength)
                }

                if let errorMessage = workoutManager.errorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
        }
        .background(WatchTheme.canvas.ignoresSafeArea())
        .navigationTitle(route == nil ? "Workout" : "Start Route")
    }

    @ViewBuilder
    private func workoutButton(_ kind: WatchWorkoutKind) -> some View {
        Button {
            Task {
                await workoutManager.start(
                    kind: kind,
                    route: route
                )
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(WatchTheme.green.opacity(0.11))
                        .frame(width: 36, height: 36)

                    Image(systemName: kind.systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(WatchTheme.green)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)

                    Text(
                        kind.supportsDistanceMetric
                            ? "Heart rate · GPS · distance"
                            : "Heart rate · calories · duration"
                    )
                    .font(.system(size: 9))
                    .foregroundStyle(WatchTheme.muted)
                }

                Spacer()

                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WatchTheme.green)
            }
            .padding(11)
            .watchSurface()
        }
        .buttonStyle(.plain)
        .disabled(workoutManager.state == .preparing)
        .opacity(workoutManager.state == .preparing ? 0.6 : 1)
    }
}

struct WatchActiveWorkoutView: View {
    @EnvironmentObject private var workoutManager: WatchWorkoutManager

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if workoutManager.state == .completed {
                    completedContent
                } else {
                    activeContent
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
        }
        .background(WatchTheme.canvas.ignoresSafeArea())
        .interactiveDismissDisabled(workoutManager.state != .completed)
    }

    private var activeContent: some View {
        Group {
            VStack(spacing: 8) {
                HStack {
                    Label(
                        workoutManager.kind.title,
                        systemImage: workoutManager.kind.systemImage
                    )
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WatchTheme.green)

                    Spacer()

                    HStack(spacing: 4) {
                        Circle()
                            .fill(
                                workoutManager.state == .paused
                                    ? Color.orange
                                    : WatchTheme.green
                            )
                            .frame(width: 6, height: 6)

                        Text(stateTitle)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(WatchTheme.muted)
                    }
                }

                Text(durationText(workoutManager.elapsedTime))
                    .font(
                        .system(
                            size: 34,
                            weight: .semibold,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
            }
            .padding(11)
            .watchSurface(radius: 18)

            if let structured =
                    workoutManager.structuredRunningWorkout,
               let step =
                    workoutManager.currentStructuredRunningStep {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(structured.title)
                            .font(
                                .system(
                                    size: 10,
                                    weight: .semibold
                                )
                            )
                            .foregroundStyle(WatchTheme.muted)
                            .lineLimit(1)

                        Spacer()

                        Text(
                            "\(workoutManager.structuredStepIndex + 1)/\(structured.steps.count)"
                        )
                        .font(
                            .system(
                                size: 9,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(WatchTheme.green)
                    }

                    Text(step.title)
                        .font(
                            .system(
                                size: 14,
                                weight: .bold
                            )
                        )
                        .lineLimit(2)

                    if let target =
                            structuredStepTargetText(step) {
                        Text(target)
                            .font(.system(size: 10))
                            .foregroundStyle(WatchTheme.muted)
                    }
                }
                .padding(10)
                .watchSurface()
            }

            HStack(spacing: 0) {
                metric(
                    icon: "heart.fill",
                    value: workoutManager.heartRate > 0
                        ? "\(Int(workoutManager.heartRate.rounded()))"
                        : "—",
                    label: "BPM"
                )

                Divider()

                metric(
                    icon: "flame.fill",
                    value: "\(Int(workoutManager.activeCalories.rounded()))",
                    label: "KCAL"
                )

                if workoutManager.kind.supportsDistanceMetric {
                    Divider()

                    metric(
                        icon: "location.fill",
                        value: String(
                            format: "%.2f",
                            workoutManager.distanceMeters / 1000
                        ),
                        label: "KM"
                    )
                }
            }
            .padding(.vertical, 9)
            .watchSurface()

            workoutMap

            if let errorMessage = workoutManager.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 8) {
                Button {
                    if workoutManager.state == .paused {
                        workoutManager.resume()
                    } else {
                        workoutManager.pause()
                    }
                } label: {
                    Image(
                        systemName: workoutManager.state == .paused
                            ? "play.fill"
                            : "pause.fill"
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                }
                .buttonStyle(.plain)
                .background(
                    Color.black.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .disabled(workoutManager.state == .ending)

                Button {
                    workoutManager.end()
                } label: {
                    Image(systemName: "stop.fill")
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(
                    Color.red,
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .disabled(workoutManager.state == .ending)
            }
        }
    }

    private func structuredStepTargetText(
        _ step: WatchRunningWorkoutStep
    ) -> String? {
        var parts: [String] = []

        switch step.measure {
        case .distance:
            if let meters = step.distanceMeters {
                parts.append(
                    meters >= 1_000
                        ? String(
                            format: "%.1f km",
                            meters / 1_000
                        )
                        : "\(Int(meters.rounded())) m"
                )
            }

        case .time:
            if let seconds = step.durationSeconds {
                parts.append(durationText(seconds))
            }

        case .open:
            parts.append("Open")
        }

        if let intensity = step.intensityText,
           !intensity.isEmpty {
            parts.append(intensity)
        }

        return parts.isEmpty
            ? nil
            : parts.joined(separator: " · ")
    }

    private var completedContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 42))
                .foregroundStyle(WatchTheme.green)

            Text("Workout Saved")
                .font(.system(size: 17, weight: .bold))

            if let result = workoutManager.completedResult {
                Text(durationText(result.duration))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()

                HStack(spacing: 0) {
                    metric(
                        icon: "heart.fill",
                        value: result.averageHeartRate.map {
                            "\(Int($0.rounded()))"
                        } ?? "—",
                        label: "AVG BPM"
                    )

                    Divider()

                    metric(
                        icon: "flame.fill",
                        value: "\(Int(result.activeCalories.rounded()))",
                        label: "KCAL"
                    )

                    if result.kind != .strength {
                        Divider()

                        metric(
                            icon: "location.fill",
                            value: String(
                                format: "%.2f",
                                result.distanceMeters / 1000
                            ),
                            label: "KM"
                        )
                    }
                }
                .padding(.vertical, 9)
                .watchSurface()
            }

            Button("Done") {
                workoutManager.reset()
            }
            .buttonStyle(.borderedProminent)
            .tint(WatchTheme.green)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var workoutMap: some View {
        let liveCoordinates = workoutManager.routePoints
            .sorted { $0.sequence < $1.sequence }
            .map {
                CLLocationCoordinate2D(
                    latitude: $0.latitude,
                    longitude: $0.longitude
                )
            }

        let plannedCoordinates = workoutManager.plannedRoute?.points
            .sorted { $0.sequence < $1.sequence }
            .map {
                CLLocationCoordinate2D(
                    latitude: $0.latitude,
                    longitude: $0.longitude
                )
            } ?? []

        let coordinates = liveCoordinates.count >= 2
            ? liveCoordinates
            : plannedCoordinates

        if workoutManager.kind != .strength, coordinates.count >= 2 {
            Map {
                MapPolyline(coordinates: coordinates)
                    .stroke(WatchTheme.green, lineWidth: 4)
            }
            .frame(height: 104)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
                .stroke(WatchTheme.border, lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private func metric(
        icon: String,
        value: String,
        label: String
    ) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WatchTheme.green)

            Text(value)
                .font(.system(size: 12, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Text(label)
                .font(.system(size: 7))
                .foregroundStyle(WatchTheme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    private var stateTitle: String {
        switch workoutManager.state {
        case .preparing: return "Starting"
        case .running: return "Live"
        case .paused: return "Paused"
        case .ending: return "Saving"
        case .completed: return "Saved"
        case .idle: return "Ready"
        case .failed: return "Error"
        }
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }
}

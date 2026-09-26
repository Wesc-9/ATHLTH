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
        Group {
            if workoutManager.state == .completed {
                ScrollView {
                    VStack(spacing: 10) {
                        completedContent
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
                }
            } else if workoutManager.kind == .running ||
                        workoutManager.kind == .walking {
                WatchRunWalkWorkoutPager()
                    .environmentObject(workoutManager)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        activeContent
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
                }
            }
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

            if workoutManager.kind == .strength {
                strengthTrackingContent
            } else if let structured =
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

    @ViewBuilder
    private var strengthTrackingContent: some View {
        if let snapshot = workoutManager.strengthSession {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(
                        snapshot.exerciseName ??
                        "Strength"
                    )
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(2)

                    Spacer()

                    if snapshot.exerciseCount > 0 {
                        Text(
                            "\(snapshot.exerciseIndex + 1)/\(snapshot.exerciseCount)"
                        )
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(WatchTheme.green)
                    }
                }

                if !snapshot.primaryMuscles.isEmpty {
                    Text(
                        snapshot.primaryMuscles
                            .prefix(2)
                            .joined(separator: " · ")
                    )
                    .font(.system(size: 9))
                    .foregroundStyle(WatchTheme.muted)
                    .lineLimit(1)
                }

                if let setNumber = snapshot.setNumber,
                   snapshot.setCount > 0 {
                    Text(
                        "Set \(setNumber) of \(snapshot.setCount) · \(snapshot.completedSets)/\(snapshot.totalSets) total"
                    )
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WatchTheme.muted)
                }
            }
            .padding(10)
            .watchSurface()

            if snapshot.isResting,
               let restEndsAt = snapshot.restEndsAt {
                WatchStrengthRestView(
                    restEndsAt: restEndsAt,
                    onAdd: {
                        workoutManager
                            .addStrengthRest(
                                seconds: 30
                            )
                    },
                    onSkip: {
                        workoutManager
                            .skipStrengthRest()
                    }
                )
            } else if snapshot.currentExerciseComplete {
                VStack(spacing: 8) {
                    Image(
                        systemName:
                            snapshot.allExercisesComplete
                                ? "checkmark.circle.fill"
                                : "checkmark.seal.fill"
                    )
                    .font(.system(size: 24))
                    .foregroundStyle(WatchTheme.green)

                    Text(
                        snapshot.allExercisesComplete
                            ? "Workout exercises complete"
                            : "Exercise complete"
                    )
                    .font(.system(size: 12, weight: .bold))
                    .multilineTextAlignment(.center)

                    if snapshot.hasNextExercise {
                        Button {
                            workoutManager
                                .moveToNextStrengthExercise()
                        } label: {
                            Label(
                                "Next Exercise",
                                systemImage: "arrow.right"
                            )
                            .font(.system(size: 12, weight: .bold))
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(WatchTheme.green)
                    } else {
                        Text(
                            "Use the red stop button below when you're finished."
                        )
                        .font(.system(size: 8))
                        .foregroundStyle(WatchTheme.muted)
                        .multilineTextAlignment(.center)
                    }
                }
                .padding(10)
                .watchSurface()
            } else if snapshot.exerciseName != nil {
                WatchStrengthCrownControl(
                    title: "Weight",
                    valueText: String(
                        format: "%.1f kg",
                        snapshot.draftWeightKilograms
                    ),
                    value: strengthWeightBinding,
                    range: 0...500,
                    step: 0.5,
                    icon: "scalemass.fill"
                )

                WatchStrengthCrownControl(
                    title: "Reps",
                    valueText: "\(snapshot.draftReps)",
                    value: strengthRepsBinding,
                    range: 0...100,
                    step: 1,
                    icon: "repeat"
                )

                WatchStrengthCrownControl(
                    title: "Rest",
                    valueText:
                        strengthRestText(
                            snapshot.draftRestSeconds
                        ),
                    value: strengthRestBinding,
                    range: 0...600,
                    step: 15,
                    icon: "timer"
                )

                Button {
                    workoutManager.completeStrengthSet()
                } label: {
                    Label(
                        "Complete Set",
                        systemImage:
                            "checkmark.circle.fill"
                    )
                    .font(.system(size: 13, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchTheme.green)
            } else {
                VStack(spacing: 7) {
                    Image(systemName: "iphone")
                        .font(.title3)
                        .foregroundStyle(WatchTheme.green)

                    Text("Add an exercise on iPhone")
                        .font(.system(size: 11, weight: .bold))
                        .multilineTextAlignment(.center)

                    Text(
                        "The Watch will update automatically."
                    )
                    .font(.system(size: 8))
                    .foregroundStyle(WatchTheme.muted)
                    .multilineTextAlignment(.center)
                }
                .padding(10)
                .frame(maxWidth: .infinity)
                .watchSurface()
            }
        } else {
            VStack(spacing: 8) {
                ProgressView()
                    .tint(WatchTheme.green)

                Text("Syncing strength workout…")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WatchTheme.muted)
                    .multilineTextAlignment(.center)

                Button("Sync") {
                    workoutManager
                        .requestStrengthSnapshot()
                }
                .buttonStyle(.bordered)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .watchSurface()
        }
    }

    private var strengthWeightBinding: Binding<Double> {
        Binding(
            get: {
                workoutManager
                    .strengthSession?
                    .draftWeightKilograms ?? 0
            },
            set: {
                workoutManager.updateStrengthDraft(
                    weightKilograms: $0
                )
            }
        )
    }

    private var strengthRepsBinding: Binding<Double> {
        Binding(
            get: {
                Double(
                    workoutManager
                        .strengthSession?
                        .draftReps ?? 0
                )
            },
            set: {
                workoutManager.updateStrengthDraft(
                    reps: max(Int($0.rounded()), 0)
                )
            }
        )
    }

    private var strengthRestBinding: Binding<Double> {
        Binding(
            get: {
                Double(
                    workoutManager
                        .strengthSession?
                        .draftRestSeconds ?? 0
                )
            },
            set: {
                let rounded = Int(
                    ($0 / 15).rounded()
                ) * 15

                workoutManager.updateStrengthDraft(
                    restSeconds:
                        min(max(rounded, 0), 600)
                )
            }
        )
    }

    private func strengthRestText(
        _ seconds: Int
    ) -> String {
        if seconds == 0 {
            return "None"
        }

        if seconds >= 60,
           seconds % 60 == 0 {
            return "\(seconds / 60) min"
        }

        return "\(seconds) sec"
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


private struct WatchStrengthCrownControl: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let icon: String

    @FocusState private var crownFocused: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WatchTheme.green)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(WatchTheme.muted)

                Text(valueText)
                    .font(
                        .system(
                            size: 17,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()
            }

            Spacer()

            Image(systemName: "digitalcrown.horizontal.arrow.clockwise")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(
                    crownFocused
                        ? WatchTheme.green
                        : WatchTheme.muted
                )
        }
        .padding(9)
        .watchSurface()
        .contentShape(Rectangle())
        .focusable()
        .focused($crownFocused)
        .digitalCrownRotation(
            $value,
            from: range.lowerBound,
            through: range.upperBound,
            by: step,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onTapGesture {
            crownFocused = true
        }
    }
}


private struct WatchStrengthRestView: View {
    let restEndsAt: Date
    let onAdd: () -> Void
    let onSkip: () -> Void

    @State private var sentCompletion = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) {
            context in
            let remaining = max(
                restEndsAt.timeIntervalSince(
                    context.date
                ),
                0
            )

            VStack(spacing: 8) {
                Text("REST")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(WatchTheme.muted)

                if remaining > 0 {
                    Text(durationText(remaining))
                        .font(
                            .system(
                                size: 34,
                                weight: .bold,
                                design: .rounded
                            )
                        )
                        .monospacedDigit()

                    HStack(spacing: 7) {
                        Button("+30") {
                            onAdd()
                        }
                        .buttonStyle(.bordered)

                        Button("Skip") {
                            onSkip()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(WatchTheme.green)
                    }
                } else {
                    Label(
                        "Next set",
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WatchTheme.green)
                    .onAppear {
                        guard !sentCompletion else {
                            return
                        }
                        sentCompletion = true
                        onSkip()
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(10)
            .watchSurface()
        }
    }

    private func durationText(
        _ duration: TimeInterval
    ) -> String {
        let total = max(
            Int(duration.rounded(.down)),
            0
        )

        return String(
            format: "%02d:%02d",
            total / 60,
            total % 60
        )
    }
}


private struct WatchRunWalkWorkoutPager: View {
    @EnvironmentObject private var workoutManager: WatchWorkoutManager

    @State private var selectedPage = 0

    var body: some View {
        TabView(selection: $selectedPage) {
            ScrollView {
                livePage
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
            }
            .tag(0)

            ScrollView {
                workoutRoutePage
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
            }
            .tag(1)

            ScrollView {
                controlsPage
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
            }
            .tag(2)
        }
        .tabViewStyle(.verticalPage)
        .background(
            WatchTheme.canvas
                .ignoresSafeArea()
        )
    }

    private var livePage: some View {
        VStack(spacing: 10) {
            pageHeader(
                title: workoutManager.kind.title,
                subtitle:
                    workoutManager.state == .paused
                        ? "Paused"
                        : "Live",
                icon: workoutManager.kind.systemImage
            )

            VStack(spacing: 2) {
                Text("CURRENT PACE")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(WatchTheme.muted)

                Text(
                    paceText(
                        workoutManager
                            .currentPaceSecondsPerKilometer
                    )
                )
                .font(
                    .system(
                        size: 34,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .monospacedDigit()
                .minimumScaleFactor(0.72)

                Text("/km")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WatchTheme.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .watchSurface(radius: 18)

            HStack(spacing: 7) {
                runMetric(
                    title: "DISTANCE",
                    value: String(
                        format: "%.2f",
                        workoutManager.distanceMeters / 1_000
                    ),
                    suffix: "km"
                )

                runMetric(
                    title: "AVG PACE",
                    value: paceText(
                        workoutManager
                            .averagePaceSecondsPerKilometer
                    ),
                    suffix: "/km"
                )
            }

            HStack(spacing: 7) {
                runMetric(
                    title: "HEART RATE",
                    value:
                        workoutManager.heartRate > 0
                            ? "\(Int(workoutManager.heartRate.rounded()))"
                            : "—",
                    suffix: "bpm"
                )

                runMetric(
                    title: "TIME",
                    value: durationText(
                        workoutManager.elapsedTime
                    ),
                    suffix: ""
                )
            }

            if workoutManager.lapCount > 0 {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Label(
                            "Lap \(workoutManager.lapCount + 1)",
                            systemImage: "flag.fill"
                        )
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(WatchTheme.green)

                        Spacer()

                        Text(
                            durationText(
                                workoutManager
                                    .currentLapElapsedTime
                            )
                        )
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                    }

                    HStack {
                        Text(
                            String(
                                format: "%.2f km",
                                workoutManager
                                    .currentLapDistanceMeters /
                                    1_000
                            )
                        )
                        .font(.system(size: 10, weight: .semibold))

                        Spacer()

                        Text(
                            paceText(
                                workoutManager
                                    .currentLapPaceSecondsPerKilometer
                            ) + " /km"
                        )
                        .font(.system(size: 10, weight: .semibold))
                    }
                }
                .padding(10)
                .watchSurface()
            }

            pageHint(
                "Swipe or use the Digital Crown for Workout & Route"
            )
        }
    }

    private var workoutRoutePage: some View {
        VStack(spacing: 10) {
            pageHeader(
                title: "Workout & Route",
                subtitle: routePageSubtitle,
                icon: "map.fill"
            )

            if let workout =
                    workoutManager.structuredRunningWorkout,
               let step =
                    workoutManager.currentStructuredRunningStep {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(workout.title)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(WatchTheme.muted)
                                .lineLimit(1)

                            Text(step.title)
                                .font(.system(size: 15, weight: .bold))
                                .lineLimit(2)
                        }

                        Spacer()

                        Text(
                            "\(workoutManager.structuredStepIndex + 1)/\(workout.steps.count)"
                        )
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(WatchTheme.green)
                    }

                    ProgressView(
                        value: structuredStepProgress(
                            step
                        )
                    )
                    .tint(WatchTheme.green)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("TARGET")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(WatchTheme.muted)

                            Text(
                                structuredStepTargetText(
                                    step
                                ) ?? "Open"
                            )
                            .font(.system(size: 10, weight: .semibold))
                        }

                        Spacer()

                        if step.targetPaceMinSecondsPerKilometer != nil ||
                            step.targetPaceMaxSecondsPerKilometer != nil {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("ACTUAL")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(WatchTheme.muted)

                                Text(
                                    paceText(
                                        workoutManager
                                            .currentPaceSecondsPerKilometer
                                    ) + " /km"
                                )
                                .font(.system(size: 10, weight: .semibold))
                            }
                        }
                    }

                    if let status = paceTargetStatus(
                        step
                    ) {
                        Label(
                            status.text,
                            systemImage: status.icon
                        )
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(status.color)
                    }

                    if let next =
                            workoutManager
                                .nextStructuredRunningStep {
                        Divider()

                        HStack {
                            Text("NEXT")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(WatchTheme.muted)

                            Spacer()

                            Text(next.title)
                                .font(.system(size: 9, weight: .semibold))
                                .lineLimit(1)
                        }
                    }
                }
                .padding(10)
                .watchSurface()
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    Label(
                        "Free \(workoutManager.kind.title)",
                        systemImage:
                            workoutManager.kind.systemImage
                    )
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WatchTheme.green)

                    Text(
                        "No structured steps. Pace, distance and route tracking continue normally."
                    )
                    .font(.system(size: 9))
                    .foregroundStyle(WatchTheme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .watchSurface()
            }

            if let target =
                    workoutManager.targetAlertConfiguration {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Label(
                            "Live targets",
                            systemImage: "scope"
                        )
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(WatchTheme.green)

                        Spacer()

                        if let status =
                                workoutManager.liveTargetStatus {
                            Text(status)
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(
                                    status == "On target"
                                        ? WatchTheme.green
                                        : .orange
                                )
                                .lineLimit(1)
                        }
                    }

                    if target.heartRateEnabled,
                       let minimum =
                            target.heartRateMinimumBPM,
                       let maximum =
                            target.heartRateMaximumBPM {
                        HStack {
                            Text(
                                target.heartRateZone.map {
                                    "Heart rate · Zone \($0)"
                                } ??
                                "Heart rate"
                            )
                            .font(.system(size: 9, weight: .semibold))

                            Spacer()

                            Text(
                                "\(Int(minimum.rounded()))–\(Int(maximum.rounded())) bpm"
                            )
                            .font(.system(size: 9, weight: .bold))
                            .monospacedDigit()
                        }
                    }

                    if target.paceAlertsEnabled {
                        HStack {
                            Text("Pace alerts")
                                .font(.system(size: 9, weight: .semibold))

                            Spacer()

                            Text(
                                "±\(Int(target.paceToleranceSecondsPerKilometer.rounded())) sec/km"
                            )
                            .font(.system(size: 9, weight: .bold))
                        }
                    }

                    HStack {
                        Text(
                            target.delivery.title
                        )
                        .font(.system(size: 8))
                        .foregroundStyle(WatchTheme.muted)

                        Spacer()

                        Text(
                            target.graceSeconds > 0
                                ? "after \(Int(target.graceSeconds)) sec"
                                : "immediately"
                        )
                        .font(.system(size: 8))
                        .foregroundStyle(WatchTheme.muted)
                    }
                }
                .padding(10)
                .watchSurface()
            }

            if let route =
                    workoutManager.plannedRoute {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(route.title)
                            .font(.system(size: 12, weight: .bold))
                            .lineLimit(1)

                        Spacer()

                        if let progress =
                                workoutManager
                                    .routeProgressPercent {
                            Text(
                                "\(Int(progress.rounded()))%"
                            )
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(WatchTheme.green)
                        }
                    }

                    if let progress =
                            workoutManager
                                .routeProgressPercent {
                        ProgressView(
                            value: progress,
                            total: 100
                        )
                        .tint(WatchTheme.green)
                    }

                    HStack(spacing: 7) {
                        runMetric(
                            title: "REMAINING",
                            value:
                                routeRemainingText,
                            suffix: ""
                        )

                        runMetric(
                            title: "ROUTE",
                            value:
                                routeDeviationText,
                            suffix: ""
                        )
                    }

                    routeMap
                }
                .padding(10)
                .watchSurface()
            } else {
                routeMap
            }

            pageHint(
                "Swipe for controls"
            )
        }
    }

    private var controlsPage: some View {
        VStack(spacing: 10) {
            pageHeader(
                title: "Controls",
                subtitle:
                    workoutManager.state == .paused
                        ? "Workout paused"
                        : "Workout running",
                icon: "slider.horizontal.3"
            )

            Button {
                if workoutManager.state == .paused {
                    workoutManager.resume()
                } else {
                    workoutManager.pause()
                }
            } label: {
                Label(
                    workoutManager.state == .paused
                        ? "Resume"
                        : "Pause",
                    systemImage:
                        workoutManager.state == .paused
                            ? "play.fill"
                            : "pause.fill"
                )
                .font(.system(size: 13, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(height: 38)
            }
            .buttonStyle(.borderedProminent)
            .tint(
                workoutManager.state == .paused
                    ? WatchTheme.green
                    : .orange
            )
            .disabled(
                workoutManager.state == .ending
            )

            Button {
                workoutManager.markLap()
            } label: {
                HStack {
                    Label(
                        "Lap",
                        systemImage: "flag.fill"
                    )

                    Spacer()

                    Text(
                        "#\(workoutManager.lapCount + 1)"
                    )
                    .font(.caption2.monospacedDigit())
                }
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
            }
            .buttonStyle(.bordered)
            .disabled(
                workoutManager.state != .running
            )

            if workoutManager.audioCoachConfigured {
                Button {
                    workoutManager.setAudioCoachEnabled(
                        !workoutManager
                            .audioCoachConfiguration
                            .enabled
                    )
                } label: {
                    HStack {
                        Label(
                            "Audio Coach",
                            systemImage:
                                workoutManager
                                    .audioCoachConfiguration
                                    .enabled
                                    ? "speaker.wave.2.fill"
                                    : "speaker.slash.fill"
                        )

                        Spacer()

                        Text(
                            workoutManager
                                .audioCoachConfiguration
                                .enabled
                                ? "On"
                                : "Muted"
                        )
                        .font(.caption2.weight(.bold))
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                }
                .buttonStyle(.bordered)
            }

            if let error =
                    workoutManager.errorMessage {
                Text(error)
                    .font(.system(size: 8))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
            }

            Button(role: .destructive) {
                workoutManager.end()
            } label: {
                Label(
                    "Finish Workout",
                    systemImage: "stop.fill"
                )
                .font(.system(size: 13, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(height: 38)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(
                workoutManager.state == .ending
            )

            pageHint(
                "Audio Coach runs on Apple Watch during the workout."
            )
        }
    }

    private var routePageSubtitle: String {
        if workoutManager.plannedRoute != nil,
           workoutManager.structuredRunningWorkout != nil {
            return "Plan · Route"
        }

        if workoutManager.plannedRoute != nil {
            return "Route"
        }

        if workoutManager.structuredRunningWorkout != nil {
            return "Workout"
        }

        return "Free session"
    }

    private var routeRemainingText: String {
        guard let meters =
                workoutManager.routeRemainingMeters
        else {
            return "—"
        }

        if meters >= 1_000 {
            return String(
                format: "%.1f km",
                meters / 1_000
            )
        }

        return "\(Int(meters.rounded())) m"
    }

    private var routeDeviationText: String {
        guard let meters =
                workoutManager.routeDeviationMeters
        else {
            return "Locating"
        }

        if meters <= 80 {
            return "On route"
        }

        return "\(Int(meters.rounded())) m off"
    }

    @ViewBuilder
    private var routeMap: some View {
        let planned =
            workoutManager.plannedRoute?
                .points
                .sorted {
                    $0.sequence < $1.sequence
                }
                .map {
                    CLLocationCoordinate2D(
                        latitude: $0.latitude,
                        longitude: $0.longitude
                    )
                } ?? []

        let live =
            workoutManager.routePoints
                .sorted {
                    $0.sequence < $1.sequence
                }
                .map {
                    CLLocationCoordinate2D(
                        latitude: $0.latitude,
                        longitude: $0.longitude
                    )
                }

        if planned.count >= 2 ||
            live.count >= 2 {
            Map {
                if planned.count >= 2 {
                    MapPolyline(
                        coordinates: planned
                    )
                    .stroke(
                        WatchTheme.muted.opacity(0.55),
                        lineWidth: 3
                    )
                }

                if live.count >= 2 {
                    MapPolyline(
                        coordinates: live
                    )
                    .stroke(
                        WatchTheme.green,
                        lineWidth: 4
                    )
                }
            }
            .frame(height: 116)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 15,
                    style: .continuous
                )
            )
        }
    }

    private func pageHeader(
        title: String,
        subtitle: String,
        icon: String
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WatchTheme.green)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))

                Text(subtitle)
                    .font(.system(size: 8))
                    .foregroundStyle(WatchTheme.muted)
            }

            Spacer()
        }
        .padding(.horizontal, 2)
    }

    private func runMetric(
        title: String,
        value: String,
        suffix: String
    ) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(WatchTheme.muted)
                .lineLimit(1)

            Text(value)
                .font(
                    .system(
                        size: 16,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            if !suffix.isEmpty {
                Text(suffix)
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(WatchTheme.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 54)
        .padding(.vertical, 6)
        .watchSurface()
    }

    private func pageHint(
        _ text: String
    ) -> some View {
        Text(text)
            .font(.system(size: 7))
            .foregroundStyle(WatchTheme.muted)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
    }

    private func paceText(
        _ pace: TimeInterval?
    ) -> String {
        guard let pace,
              pace.isFinite,
              pace > 0
        else {
            return "—"
        }

        let total =
            max(
                Int(pace.rounded()),
                0
            )

        return String(
            format: "%d:%02d",
            total / 60,
            total % 60
        )
    }

    private func durationText(
        _ duration: TimeInterval
    ) -> String {
        let total =
            max(
                Int(duration.rounded(.down)),
                0
            )
        let hours = total / 3_600
        let minutes =
            (total % 3_600) / 60
        let seconds = total % 60

        if hours > 0 {
            return String(
                format: "%d:%02d:%02d",
                hours,
                minutes,
                seconds
            )
        }

        return String(
            format: "%02d:%02d",
            minutes,
            seconds
        )
    }

    private func structuredStepProgress(
        _ step: WatchRunningWorkoutStep
    ) -> Double {
        switch step.measure {
        case .time:
            guard let target =
                    step.durationSeconds,
                  target > 0
            else {
                return 0
            }

            return min(
                workoutManager
                    .currentStructuredStepElapsedTime /
                    target,
                1
            )

        case .distance:
            guard let target =
                    step.distanceMeters,
                  target > 0
            else {
                return 0
            }

            return min(
                workoutManager
                    .currentStructuredStepDistanceMeters /
                    target,
                1
            )

        case .open:
            return 0
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
            if let seconds =
                    step.durationSeconds {
                parts.append(
                    durationText(seconds)
                )
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
            : parts.joined(
                separator: " · "
            )
    }

    private func paceTargetStatus(
        _ step: WatchRunningWorkoutStep
    ) -> (
        text: String,
        icon: String,
        color: Color
    )? {
        guard let actual =
                workoutManager
                    .currentPaceSecondsPerKilometer
        else {
            return nil
        }

        let first =
            step.targetPaceMinSecondsPerKilometer
        let second =
            step.targetPaceMaxSecondsPerKilometer

        guard first != nil || second != nil else {
            return nil
        }

        let low = min(
            first ?? second ?? actual,
            second ?? first ?? actual
        )
        let high = max(
            first ?? second ?? actual,
            second ?? first ?? actual
        )

        if actual < low {
            return (
                "Faster than target",
                "arrow.up.circle.fill",
                .orange
            )
        }

        if actual > high {
            return (
                "Slower than target",
                "arrow.down.circle.fill",
                .orange
            )
        }

        return (
            "On target",
            "checkmark.circle.fill",
            WatchTheme.green
        )
    }
}

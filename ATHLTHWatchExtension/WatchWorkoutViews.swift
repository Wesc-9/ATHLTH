import MapKit
import SwiftUI
import WatchKit

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
                        .foregroundStyle(WatchTheme.textPrimary)

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
    @Environment(\.isLuminanceReduced)
    private var isLuminanceReduced
    @State private var selectedNonRunningPage = 0
    @State private var showingStrengthSetOptions = false

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
                WatchRunWorkoutExperienceView()
                    .environmentObject(workoutManager)
            } else if isLuminanceReduced {
                nonRunningAlwaysOnPage
            } else {
                TabView(
                    selection:
                        $selectedNonRunningPage
                ) {
                    if workoutManager.kind ==
                        .strength {
                        strengthOneScreenPage
                            .tag(0)
                    } else {
                        ScrollView {
                            VStack(spacing: 10) {
                                activeContent
                            }
                            .padding(
                                .horizontal,
                                8
                            )
                            .padding(
                                .bottom,
                                10
                            )
                        }
                        .tag(0)
                    }

                    WatchSpotifyRemotePage()
                        .tag(1)

                    nonRunningControlsPage
                        .tag(2)
                }
                .tabViewStyle(.verticalPage)
            }
        }
        .background(
            Group {
                if isLuminanceReduced &&
                    workoutManager.state != .completed {
                    Color.black
                } else {
                    WatchTheme.canvas
                }
            }
            .ignoresSafeArea()
        )
        .interactiveDismissDisabled(workoutManager.state != .completed)
        .sheet(
            isPresented:
                $showingStrengthSetOptions
        ) {
            strengthSetOptionsSheet
        }
    }

    private var nonRunningAlwaysOnPage: some View {
        VStack(spacing: 9) {
            HStack(spacing: 7) {
                Image(
                    systemName:
                        workoutManager
                            .kind.systemImage
                )
                .font(
                    .system(
                        size: 10,
                        weight: .bold
                    )
                )

                Text(
                    stateTitle.uppercased()
                )
                .font(
                    .system(
                        size: 9,
                        weight: .bold
                    )
                )
                .tracking(0.8)

                Spacer()

                Text(
                    durationText(
                        workoutManager
                            .elapsedTime
                    )
                )
                .font(
                    .system(
                        size: 12,
                        weight: .semibold,
                        design: .rounded
                    )
                )
                .monospacedDigit()
            }
            .foregroundStyle(
                Color.white.opacity(0.70)
            )

            if let snapshot =
                    workoutManager
                        .strengthSession {
                VStack(
                    alignment: .leading,
                    spacing: 5
                ) {
                    HStack(
                        alignment:
                            .firstTextBaseline
                    ) {
                        Text(
                            snapshot
                                .exerciseName ??
                            "Strength"
                        )
                        .font(
                            .system(
                                size: 18,
                                weight: .bold,
                                design: .rounded
                            )
                        )
                        .lineLimit(1)

                        Spacer()

                        if let setNumber =
                                snapshot
                                    .setNumber,
                           snapshot
                            .setCount > 0 {
                            Text(
                                "SET \(setNumber)/\(snapshot.setCount)"
                            )
                            .font(
                                .system(
                                    size: 9,
                                    weight: .bold
                                )
                            )
                            .foregroundStyle(
                                Color.white
                                    .opacity(0.58)
                            )
                        }
                    }

                    if snapshot.isResting,
                       let restEndsAt =
                            snapshot
                                .restEndsAt {
                        TimelineView(
                            .periodic(
                                from: .now,
                                by: 1
                            )
                        ) { context in
                            let remaining =
                                max(
                                    Int(
                                        restEndsAt
                                            .timeIntervalSince(
                                                context.date
                                            )
                                            .rounded(.up)
                                    ),
                                    0
                                )

                            HStack(
                                alignment:
                                    .firstTextBaseline
                            ) {
                                Text("REST")
                                    .font(
                                        .system(
                                            size: 8,
                                            weight: .bold
                                        )
                                    )
                                    .foregroundStyle(
                                        Color.white
                                            .opacity(0.52)
                                    )

                                Text(
                                    "\(remaining) s"
                                )
                                .font(
                                    .system(
                                        size: 28,
                                        weight: .bold,
                                        design: .rounded
                                    )
                                )
                                .monospacedDigit()
                            }
                        }
                    } else if snapshot
                        .exerciseName != nil {
                        HStack(spacing: 14) {
                            Label(
                                String(
                                    format:
                                        "%.1f kg",
                                    snapshot
                                        .draftWeightKilograms
                                ),
                                systemImage:
                                    "scalemass"
                            )

                            Label(
                                "\(snapshot.draftReps) reps",
                                systemImage:
                                    "repeat"
                            )
                        }
                        .font(
                            .system(
                                size: 10,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(
                            Color.white
                                .opacity(0.66)
                        )
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
            } else {
                Text(
                    workoutManager
                        .kind.title
                )
                .font(
                    .system(
                        size: 20,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
            }

            Rectangle()
                .fill(
                    Color.white
                        .opacity(0.13)
                )
                .frame(height: 0.5)

            HStack(spacing: 0) {
                alwaysOnMetric(
                    value:
                        workoutManager
                            .heartRate > 0
                            ? "\(Int(workoutManager.heartRate.rounded()))"
                            : "—",
                    label: "BPM"
                )

                alwaysOnMetric(
                    value:
                        "\(Int(workoutManager.activeCalories.rounded()))",
                    label: "KCAL"
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .top
        )
        .foregroundStyle(
            Color.white.opacity(0.88)
        )
    }

    private func alwaysOnMetric(
        value: String,
        label: String
    ) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(
                    .system(
                        size: 19,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .monospacedDigit()

            Text(label)
                .font(
                    .system(
                        size: 7,
                        weight: .bold
                    )
                )
                .tracking(0.7)
                .foregroundStyle(
                    Color.white.opacity(0.48)
                )
        }
        .frame(maxWidth: .infinity)
    }

    private var activeContent: some View {
        Group {
            if workoutManager.kind == .strength {
                strengthWorkoutHeader
            } else {
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
            }

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


        }
    }

    @ViewBuilder
    private var strengthOneScreenPage:
        some View {
        if let snapshot =
                workoutManager
                    .strengthSession {
            if snapshot.isResting,
               let restEndsAt =
                    snapshot.restEndsAt {
                VStack(spacing: 6) {
                    compactStrengthTopBar(
                        snapshot
                    )

                    WatchStrengthRestView(
                        restEndsAt:
                            restEndsAt,
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
                }
                .padding(
                    .horizontal,
                    7
                )
                .padding(
                    .vertical,
                    4
                )
            } else if snapshot
                .currentExerciseComplete {
                VStack(spacing: 7) {
                    compactStrengthTopBar(
                        snapshot
                    )

                    Image(
                        systemName:
                            snapshot
                                .allExercisesComplete
                                ? "checkmark.circle.fill"
                                : "checkmark.seal.fill"
                    )
                    .font(
                        .system(size: 30)
                    )
                    .foregroundStyle(
                        WatchTheme.green
                    )

                    Text(
                        snapshot
                            .allExercisesComplete
                            ? ATHLTHLocalization
                                .choose(
                                    english:
                                        "Workout exercises complete",
                                    norwegian:
                                        "Alle øvelser er fullført"
                                )
                            : ATHLTHLocalization
                                .choose(
                                    english:
                                        "Exercise complete",
                                    norwegian:
                                        "Øvelse fullført"
                                )
                    )
                    .font(
                        .system(
                            size: 12,
                            weight: .bold
                        )
                    )
                    .multilineTextAlignment(
                        .center
                    )

                    if snapshot.hasNextExercise {
                        Button {
                            workoutManager
                                .moveToNextStrengthExercise()
                        } label: {
                            Label(
                                ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Next Exercise",
                                        norwegian:
                                            "Neste øvelse"
                                    ),
                                systemImage:
                                    "arrow.right"
                            )
                            .font(
                                .system(
                                    size: 12,
                                    weight: .bold
                                )
                            )
                            .frame(
                                maxWidth:
                                    .infinity,
                                minHeight: 36
                            )
                        }
                        .buttonStyle(
                            .borderedProminent
                        )
                        .tint(
                            WatchTheme.green
                        )
                        .disabled(
                            workoutManager
                                .strengthActionPending
                        )
                    }
                }
                .padding(
                    .horizontal,
                    8
                )
                .padding(
                    .vertical,
                    4
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .top
                )
            } else if snapshot.exerciseName != nil {
                VStack(spacing: 6) {
                    compactStrengthTopBar(
                        snapshot
                    )

                    if let setNumber =
                            snapshot.setNumber,
                       snapshot.setCount > 0 {
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Set \(setNumber) of \(snapshot.setCount) · \(snapshot.completedSets)/\(snapshot.totalSets) total",
                                norwegian:
                                    "Sett \(setNumber) av \(snapshot.setCount) · \(snapshot.completedSets)/\(snapshot.totalSets) totalt"
                            )
                        )
                        .font(
                            .system(
                                size: 8,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(
                            WatchTheme.muted
                        )
                        .frame(
                            maxWidth:
                                .infinity,
                            alignment:
                                .leading
                        )
                    }

                    HStack(spacing: 6) {
                        if snapshot
                            .targetKindRaw ==
                            "time" {
                            WatchStrengthPrimaryCrownMetric(
                                title:
                                    ATHLTHLocalization
                                        .choose(
                                            english:
                                                "Duration",
                                            norwegian:
                                                "Varighet"
                                        ),
                                valueText:
                                    durationText(
                                        TimeInterval(
                                            snapshot
                                                .draftDurationSeconds ??
                                            60
                                        )
                                    ),
                                value:
                                    strengthDurationBinding,
                                range:
                                    15...7_200,
                                step: 15,
                                icon: "timer",
                                tint:
                                    WatchTheme.accent,
                                compact: true
                            )
                        } else {
                            WatchStrengthPrimaryCrownMetric(
                                title: "Reps",
                                valueText:
                                    "\(snapshot.draftReps)",
                                value:
                                    strengthRepsBinding,
                                range: 0...100,
                                step: 1,
                                icon: "repeat",
                                tint:
                                    WatchTheme.accent,
                                compact: true
                            )
                        }

                        if snapshot
                            .loadKindRaw ==
                            "resistanceLevel" {
                            WatchStrengthPrimaryCrownMetric(
                                title:
                                    ATHLTHLocalization
                                        .choose(
                                            english:
                                                "Resistance",
                                            norwegian:
                                                "Motstand"
                                        ),
                                valueText:
                                    ATHLTHLocalization
                                        .choose(
                                            english:
                                                "Level \(snapshot.draftResistanceLevel ?? 5)",
                                            norwegian:
                                                "Steg \(snapshot.draftResistanceLevel ?? 5)"
                                        ),
                                value:
                                    strengthResistanceBinding,
                                range: 1...10,
                                step: 1,
                                icon:
                                    "dial.medium",
                                tint:
                                    WatchTheme.slate,
                                compact: true
                            )
                        } else {
                            WatchStrengthPrimaryCrownMetric(
                                title:
                                    ATHLTHLocalization
                                        .choose(
                                            english:
                                                "Weight",
                                            norwegian:
                                                "Vekt"
                                        ),
                                valueText:
                                    String(
                                        format:
                                            "%.1f kg",
                                        snapshot
                                            .draftWeightKilograms
                                    ),
                                value:
                                    strengthWeightBinding,
                                range: 0...500,
                                step: 0.5,
                                icon:
                                    "scalemass.fill",
                                tint:
                                    WatchTheme.slate,
                                compact: true
                            )
                        }
                    }

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Tap a value · turn Digital Crown",
                            norwegian:
                                "Trykk verdi · bruk Digital Crown"
                        )
                    )
                    .font(
                        .system(size: 7)
                    )
                    .foregroundStyle(
                        WatchTheme.muted
                    )
                    .lineLimit(1)

                    Button {
                        workoutManager
                            .completeStrengthSet()
                    } label: {
                        Label(
                            workoutManager
                                .strengthActionPending
                                ? ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Syncing…",
                                        norwegian:
                                            "Synkroniserer…"
                                    )
                                : (
                                    snapshot.setCount > 0 &&
                                    snapshot.setIndex + 1 >=
                                        snapshot.setCount
                                        ? ATHLTHLocalization
                                            .choose(
                                                english:
                                                    "Complete Exercise",
                                                norwegian:
                                                    "Fullfør øvelse"
                                            )
                                        : ATHLTHLocalization
                                            .choose(
                                                english:
                                                    "Complete Set",
                                                norwegian:
                                                    "Fullfør sett"
                                            )
                                ),
                            systemImage:
                                workoutManager
                                    .strengthActionPending
                                    ? "arrow.triangle.2.circlepath"
                                    : "checkmark.circle.fill"
                        )
                        .font(
                            .system(
                                size: 11,
                                weight: .bold
                            )
                        )
                        .frame(
                            maxWidth:
                                .infinity,
                            minHeight: 34
                        )
                    }
                    .buttonStyle(
                        .borderedProminent
                    )
                    .tint(
                        WatchTheme.green
                    )
                    .disabled(
                        workoutManager
                            .strengthActionPending
                    )
                }
                .padding(
                    .horizontal,
                    7
                )
                .padding(
                    .vertical,
                    3
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .top
                )
            } else {
                VStack(spacing: 8) {
                    Image(
                        systemName: "iphone"
                    )
                    .font(.title3)
                    .foregroundStyle(
                        WatchTheme.green
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Add an exercise on iPhone",
                            norwegian:
                                "Legg til en øvelse på iPhone"
                        )
                    )
                    .font(
                        .system(
                            size: 11,
                            weight: .bold
                        )
                    )
                    .multilineTextAlignment(
                        .center
                    )
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
            }
        } else {
            VStack(spacing: 8) {
                ProgressView()
                    .tint(
                        WatchTheme.green
                    )

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Preparing strength workout…",
                        norwegian:
                            "Klargjør styrkeøkt…"
                    )
                )
                .font(
                    .system(
                        size: 10,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    WatchTheme.muted
                )
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
        }
    }

    private func compactStrengthTopBar(
        _ snapshot:
            WatchStrengthSessionSnapshot
    ) -> some View {
        HStack(spacing: 5) {
            Text(
                snapshot.exerciseName ??
                ATHLTHLocalization.choose(
                    english: "Strength",
                    norwegian: "Styrke"
                )
            )
            .font(
                .system(
                    size: 14,
                    weight: .bold,
                    design: .rounded
                )
            )
            .lineLimit(1)
            .minimumScaleFactor(0.68)

            Spacer(minLength: 3)

            if snapshot.exerciseCount > 0 {
                Text(
                    "\(snapshot.exerciseIndex + 1)/\(snapshot.exerciseCount)"
                )
                .font(
                    .system(
                        size: 8,
                        weight: .bold
                    )
                )
                .foregroundStyle(
                    WatchTheme.green
                )
            }

            Text(
                durationText(
                    workoutManager
                        .elapsedTime
                )
            )
            .font(
                .system(
                    size: 9,
                    weight: .semibold,
                    design: .rounded
                )
            )
            .monospacedDigit()
            .foregroundStyle(
                WatchTheme.muted
            )

            Button {
                showingStrengthSetOptions =
                    true
            } label: {
                Image(
                    systemName:
                        "ellipsis.circle"
                )
                .font(
                    .system(
                        size: 15,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    WatchTheme.accentDeep
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                ATHLTHLocalization.choose(
                    english:
                        "Set options",
                    norwegian:
                        "Settvalg"
                )
            )
        }
        .padding(
            .horizontal,
            8
        )
        .padding(
            .vertical,
            6
        )
        .watchSurface(radius: 16)
    }

    @ViewBuilder
    private var strengthSetOptionsSheet:
        some View {
        if let snapshot =
                workoutManager
                    .strengthSession {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 8) {
                        WatchStrengthCrownControl(
                            title:
                                ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Rest after set",
                                        norwegian:
                                            "Pause etter sett"
                                    ),
                            valueText:
                                strengthRestText(
                                    snapshot
                                        .draftRestSeconds
                                ),
                            value:
                                strengthRestBinding,
                            range:
                                0...600,
                            step: 15,
                            icon: "timer",
                            tint:
                                WatchTheme
                                    .accentDeep
                        )

                        if snapshot
                            .effortMetricRaw ==
                            "rpe" {
                            WatchStrengthCrownControl(
                                title: "RPE",
                                valueText:
                                    String(
                                        format:
                                            "%.1f",
                                        snapshot
                                            .draftRPE ??
                                        8
                                    ),
                                value:
                                    strengthRPEBinding,
                                range: 1...10,
                                step: 0.5,
                                icon:
                                    "gauge.with.dots.needle.50percent",
                                tint:
                                    WatchTheme.accent
                            )
                        } else if snapshot
                            .effortMetricRaw ==
                            "rir" {
                            WatchStrengthCrownControl(
                                title: "RIR",
                                valueText:
                                    String(
                                        format:
                                            "%.1f",
                                        snapshot
                                            .draftRIR ??
                                        2
                                    ),
                                value:
                                    strengthRIRBinding,
                                range: 0...10,
                                step: 0.5,
                                icon:
                                    "repeat.circle",
                                tint:
                                    WatchTheme.accent
                            )
                        }

                        Button {
                            workoutManager
                                .updateStrengthDraft(
                                    isWarmUp:
                                        !(snapshot
                                            .isWarmUp ??
                                          false)
                                )
                        } label: {
                            Label(
                                snapshot
                                    .isWarmUp ==
                                    true
                                    ? ATHLTHLocalization
                                        .choose(
                                            english:
                                                "Warm-up set",
                                            norwegian:
                                                "Oppvarmingssett"
                                        )
                                    : ATHLTHLocalization
                                        .choose(
                                            english:
                                                "Working set",
                                            norwegian:
                                                "Arbeidssett"
                                        ),
                                systemImage:
                                    snapshot
                                        .isWarmUp ==
                                        true
                                        ? "flame.fill"
                                        : "dumbbell.fill"
                            )
                            .font(
                                .system(
                                    size: 10,
                                    weight: .semibold
                                )
                            )
                            .frame(
                                maxWidth:
                                    .infinity
                            )
                        }
                        .buttonStyle(
                            .bordered
                        )
                    }
                    .padding(8)
                }
                .background(
                    WatchTheme.canvas
                        .ignoresSafeArea()
                )
                .navigationTitle(
                    ATHLTHLocalization.choose(
                        english:
                            "Set Options",
                        norwegian:
                            "Settvalg"
                    )
                )
                .navigationBarTitleDisplayMode(
                    .inline
                )
            }
        }
    }

    private var strengthWorkoutHeader: some View {
        HStack(spacing: 7) {
            Label(
                ATHLTHLocalization.choose(
                    english: "Strength",
                    norwegian: "Styrke"
                ),
                systemImage: "dumbbell.fill"
            )
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(WatchTheme.green)

            Spacer()

            Circle()
                .fill(
                    workoutManager.state == .paused
                        ? Color.orange
                        : WatchTheme.green
                )
                .frame(width: 5, height: 5)

            Text(
                workoutManager.state == .paused
                    ? ATHLTHLocalization.choose(
                        english: "Paused",
                        norwegian: "Pause"
                    )
                    : "Live"
            )
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(WatchTheme.muted)

            Text(durationText(workoutManager.elapsedTime))
                .font(
                    .system(
                        size: 11,
                        weight: .semibold,
                        design: .rounded
                    )
                )
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .watchSurface(radius: 18)
    }

    private var nonRunningControlsPage: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(
                    systemName:
                        "slider.horizontal.3"
                )
                .foregroundStyle(
                    WatchTheme.accent
                )

                Text("CONTROLS")
                    .font(
                        .system(
                            size: 9,
                            weight: .bold
                        )
                    )
                    .tracking(1)

                Spacer()
            }

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
                .font(
                    .system(
                        size: 13,
                        weight: .bold
                    )
                )
                .foregroundStyle(.white)
                .frame(
                    maxWidth: .infinity,
                    minHeight: 48
                )
                .background(
                    WatchTheme.accent,
                    in: RoundedRectangle(
                        cornerRadius: 17,
                        style: .continuous
                    )
                )
            }
            .buttonStyle(.plain)
            .disabled(
                workoutManager.state ==
                    .ending
            )

            Button {
                workoutManager.end()
            } label: {
                Label(
                    "End Workout",
                    systemImage: "stop.fill"
                )
                .font(
                    .system(
                        size: 12,
                        weight: .bold
                    )
                )
                .foregroundStyle(.white)
                .frame(
                    maxWidth: .infinity,
                    minHeight: 44
                )
                .background(
                    WatchTheme.danger,
                    in: RoundedRectangle(
                        cornerRadius: 17,
                        style: .continuous
                    )
                )
            }
            .buttonStyle(.plain)
            .disabled(
                workoutManager.state ==
                    .ending
            )

            Text(
                "Swipe up for workout · Spotify · controls"
            )
            .font(.system(size: 8))
            .foregroundStyle(
                WatchTheme.muted
            )
            .multilineTextAlignment(
                .center
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var strengthTrackingContent: some View {
        if let snapshot = workoutManager.strengthSession {
            if snapshot.inputMode == .iPhone {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(
                            snapshot.exerciseName ??
                            ATHLTHLocalization.choose(
                                english: "Strength",
                                norwegian: "Styrke"
                            )
                        )
                        .font(.system(size: 16, weight: .bold, design: .rounded))
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

                    if snapshot.exerciseName != nil {
                        HStack(spacing: 8) {
                            WatchStrengthStaticPrimaryMetric(
                                title: ATHLTHLocalization.choose(
                                    english: "Reps",
                                    norwegian: "Reps"
                                ),
                                valueText: "\(snapshot.draftReps)",
                                icon: "repeat",
                                tint: WatchTheme.accent
                            )

                            WatchStrengthStaticPrimaryMetric(
                                title: ATHLTHLocalization.choose(
                                    english: "Weight",
                                    norwegian: "Vekt"
                                ),
                                valueText: String(
                                    format: "%.1f kg",
                                    snapshot.draftWeightKilograms
                                ),
                                icon: "scalemass.fill",
                                tint: WatchTheme.slate
                            )
                        }
                    }

                    Text(
                        snapshot.isResting
                            ? ATHLTHLocalization.choose(
                                english: "Rest timer stays synchronized with iPhone.",
                                norwegian: "Pausetid synkroniseres med iPhone."
                            )
                            : ATHLTHLocalization.choose(
                                english: "Logging is controlled on iPhone.",
                                norwegian: "Registreringen styres på iPhone."
                            )
                    )
                    .font(.system(size: 8))
                    .foregroundStyle(WatchTheme.muted)
                }
                .padding(10)
                .watchSurface(radius: 18)

                if snapshot.isResting,
                   let restEndsAt = snapshot.restEndsAt {
                    WatchStrengthRestView(
                        restEndsAt: restEndsAt,
                        onAdd: {
                            workoutManager.addStrengthRest(seconds: 30)
                        },
                        onSkip: {
                            workoutManager.skipStrengthRest()
                        }
                    )
                }
            } else if snapshot.isResting,
                      let restEndsAt = snapshot.restEndsAt {
                VStack(alignment: .leading, spacing: 5) {
                    Text(
                        snapshot.exerciseName ??
                        ATHLTHLocalization.choose(
                            english: "Strength",
                            norwegian: "Styrke"
                        )
                    )
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .lineLimit(1)

                    if snapshot.currentExerciseComplete,
                       snapshot.hasNextExercise,
                       let nextName = strengthNextExerciseName(snapshot) {
                        Text(
                            ATHLTHLocalization.choose(
                                english: "Next: \(nextName)",
                                norwegian: "Neste: \(nextName)"
                            )
                        )
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(WatchTheme.muted)
                        .lineLimit(1)
                    } else if let setNumber = snapshot.setNumber,
                              snapshot.setCount > 0 {
                        Text(
                            ATHLTHLocalization.choose(
                                english: "Next set: \(setNumber)/\(snapshot.setCount)",
                                norwegian: "Neste sett: \(setNumber)/\(snapshot.setCount)"
                            )
                        )
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(WatchTheme.muted)
                    }
                }
                .padding(.horizontal, 2)

                WatchStrengthRestView(
                    restEndsAt: restEndsAt,
                    onAdd: {
                        workoutManager.addStrengthRest(seconds: 30)
                    },
                    onSkip: {
                        workoutManager.skipStrengthRest()
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
                            ? ATHLTHLocalization.choose(
                                english: "Workout exercises complete",
                                norwegian: "Alle øvelser er fullført"
                            )
                            : ATHLTHLocalization.choose(
                                english: "Exercise complete",
                                norwegian: "Øvelse fullført"
                            )
                    )
                    .font(.system(size: 12, weight: .bold))
                    .multilineTextAlignment(.center)

                    if snapshot.hasNextExercise {
                        Button {
                            workoutManager.moveToNextStrengthExercise()
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Next Exercise",
                                    norwegian: "Neste øvelse"
                                ),
                                systemImage: "arrow.right"
                            )
                            .font(.system(size: 12, weight: .bold))
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(WatchTheme.green)
                        .disabled(workoutManager.strengthActionPending)
                    } else {
                        Text(
                            ATHLTHLocalization.choose(
                                english: "End the workout when you are finished.",
                                norwegian: "Avslutt økten når du er ferdig."
                            )
                        )
                        .font(.system(size: 8))
                        .foregroundStyle(WatchTheme.muted)
                        .multilineTextAlignment(.center)
                    }
                }
                .padding(10)
                .watchSurface()
            } else if snapshot.exerciseName != nil {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(snapshot.exerciseName ?? "")
                            .font(
                                .system(
                                    size: 18,
                                    weight: .bold,
                                    design: .rounded
                                )
                            )
                            .lineLimit(2)
                            .minimumScaleFactor(0.76)

                        Spacer(minLength: 4)

                        if snapshot.exerciseCount > 0 {
                            Text(
                                "\(snapshot.exerciseIndex + 1)/\(snapshot.exerciseCount)"
                            )
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(WatchTheme.green)
                        }
                    }

                    if let setNumber = snapshot.setNumber,
                       snapshot.setCount > 0 {
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Set \(setNumber) of \(snapshot.setCount) · \(snapshot.completedSets)/\(snapshot.totalSets) total",
                                norwegian:
                                    "Sett \(setNumber) av \(snapshot.setCount) · \(snapshot.completedSets)/\(snapshot.totalSets) totalt"
                            )
                        )
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(WatchTheme.muted)
                    }

                    HStack(spacing: 7) {
                        if snapshot.targetKindRaw == "time" {
                            WatchStrengthPrimaryCrownMetric(
                                title: ATHLTHLocalization.choose(
                                    english: "Duration",
                                    norwegian: "Varighet"
                                ),
                                valueText: durationText(
                                    TimeInterval(
                                        snapshot.draftDurationSeconds ?? 60
                                    )
                                ),
                                value: strengthDurationBinding,
                                range: 15...7_200,
                                step: 15,
                                icon: "timer",
                                tint: WatchTheme.accent
                            )
                        } else {
                            WatchStrengthPrimaryCrownMetric(
                                title: ATHLTHLocalization.choose(
                                    english: "Reps",
                                    norwegian: "Reps"
                                ),
                                valueText: "\(snapshot.draftReps)",
                                value: strengthRepsBinding,
                                range: 0...100,
                                step: 1,
                                icon: "repeat",
                                tint: WatchTheme.accent
                            )
                        }

                        if snapshot.loadKindRaw == "resistanceLevel" {
                            WatchStrengthPrimaryCrownMetric(
                                title: ATHLTHLocalization.choose(
                                    english: "Resistance",
                                    norwegian: "Motstand"
                                ),
                                valueText: ATHLTHLocalization.choose(
                                    english:
                                        "Level \(snapshot.draftResistanceLevel ?? 5)",
                                    norwegian:
                                        "Steg \(snapshot.draftResistanceLevel ?? 5)"
                                ),
                                value: strengthResistanceBinding,
                                range: 1...10,
                                step: 1,
                                icon: "dial.medium",
                                tint: WatchTheme.slate
                            )
                        } else {
                            WatchStrengthPrimaryCrownMetric(
                                title: ATHLTHLocalization.choose(
                                    english: "Weight",
                                    norwegian: "Vekt"
                                ),
                                valueText: String(
                                    format: "%.1f kg",
                                    snapshot.draftWeightKilograms
                                ),
                                value: strengthWeightBinding,
                                range: 0...500,
                                step: 0.5,
                                icon: "scalemass.fill",
                                tint: WatchTheme.slate
                            )
                        }
                    }

                    Text(
                        ATHLTHLocalization.choose(
                            english: "Tap reps or load, then turn the Digital Crown.",
                            norwegian: "Trykk reps eller belastning, og bruk Digital Crown."
                        )
                    )
                    .font(.system(size: 7))
                    .foregroundStyle(WatchTheme.muted)
                    .lineLimit(2)
                }
                .padding(10)
                .watchSurface(radius: 18)

                Button {
                    workoutManager.completeStrengthSet()
                } label: {
                    Label(
                        workoutManager.strengthActionPending
                            ? ATHLTHLocalization.choose(
                                english: "Syncing…",
                                norwegian: "Synkroniserer…"
                            )
                            : (
                                snapshot.setCount > 0 &&
                                snapshot.setIndex + 1 >= snapshot.setCount
                                    ? ATHLTHLocalization.choose(
                                        english: "Complete Exercise",
                                        norwegian: "Fullfør øvelse"
                                    )
                                    : ATHLTHLocalization.choose(
                                        english: "Complete Set",
                                        norwegian: "Fullfør sett"
                                    )
                            ),
                        systemImage:
                            workoutManager.strengthActionPending
                                ? "arrow.triangle.2.circlepath"
                                : "checkmark.circle.fill"
                    )
                    .font(.system(size: 13, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchTheme.green)
                .disabled(workoutManager.strengthActionPending)

                WatchStrengthCrownControl(
                    title: ATHLTHLocalization.choose(
                        english: "Rest after set",
                        norwegian: "Pause etter sett"
                    ),
                    valueText: strengthRestText(
                        snapshot.draftRestSeconds
                    ),
                    value: strengthRestBinding,
                    range: 0...600,
                    step: 15,
                    icon: "timer",
                    tint: WatchTheme.accentDeep
                )

                if snapshot.effortMetricRaw == "rpe" {
                    WatchStrengthCrownControl(
                        title: "RPE",
                        valueText: String(
                            format: "%.1f",
                            snapshot.draftRPE ?? 8
                        ),
                        value: strengthRPEBinding,
                        range: 1...10,
                        step: 0.5,
                        icon: "gauge.with.dots.needle.50percent",
                        tint: WatchTheme.accent
                    )
                } else if snapshot.effortMetricRaw == "rir" {
                    WatchStrengthCrownControl(
                        title: "RIR",
                        valueText: String(
                            format: "%.1f",
                            snapshot.draftRIR ?? 2
                        ),
                        value: strengthRIRBinding,
                        range: 0...10,
                        step: 0.5,
                        icon: "repeat.circle",
                        tint: WatchTheme.accent
                    )
                }

                Button {
                    workoutManager.updateStrengthDraft(
                        isWarmUp: !(snapshot.isWarmUp ?? false)
                    )
                } label: {
                    Label(
                        snapshot.isWarmUp == true
                            ? ATHLTHLocalization.choose(
                                english: "Warm-up set",
                                norwegian: "Oppvarmingssett"
                            )
                            : ATHLTHLocalization.choose(
                                english: "Working set",
                                norwegian: "Arbeidssett"
                            ),
                        systemImage:
                            snapshot.isWarmUp == true
                                ? "flame.fill"
                                : "dumbbell.fill"
                    )
                    .font(.system(size: 10, weight: .semibold))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                VStack(spacing: 7) {
                    Image(systemName: "iphone")
                        .font(.title3)
                        .foregroundStyle(WatchTheme.green)

                    Text(
                        ATHLTHLocalization.choose(
                            english: "Add an exercise on iPhone",
                            norwegian: "Legg til en øvelse på iPhone"
                        )
                    )
                    .font(.system(size: 11, weight: .bold))
                    .multilineTextAlignment(.center)

                    Text(
                        ATHLTHLocalization.choose(
                            english: "The Watch will update automatically.",
                            norwegian: "Klokken oppdateres automatisk."
                        )
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

                Text(
                    ATHLTHLocalization.choose(
                        english: "Preparing strength workout…",
                        norwegian: "Klargjør styrkeøkt…"
                    )
                )
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WatchTheme.muted)
                .multilineTextAlignment(.center)

                Button(
                    ATHLTHLocalization.choose(
                        english: "Sync",
                        norwegian: "Synkroniser"
                    )
                ) {
                    workoutManager.requestStrengthSnapshot()
                }
                .buttonStyle(.bordered)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .watchSurface()
        }
    }

    private func strengthNextExerciseName(
        _ snapshot: WatchStrengthSessionSnapshot
    ) -> String? {
        snapshot.exerciseQueue?
            .first(
                where: {
                    $0.index > snapshot.exerciseIndex
                }
            )?
            .name
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

    private var strengthResistanceBinding:
        Binding<Double> {
        Binding(
            get: {
                Double(
                    workoutManager
                        .strengthSession?
                        .draftResistanceLevel ??
                    5
                )
            },
            set: {
                workoutManager
                    .updateStrengthDraft(
                        resistanceLevel:
                            min(
                                max(
                                    Int(
                                        $0.rounded()
                                    ),
                                    1
                                ),
                                10
                            )
                    )
            }
        )
    }

    private var strengthDurationBinding:
        Binding<Double> {
        Binding(
            get: {
                Double(
                    workoutManager
                        .strengthSession?
                        .draftDurationSeconds ??
                    60
                )
            },
            set: {
                let rounded =
                    Int(
                        ($0 / 15)
                            .rounded()
                    ) * 15

                workoutManager
                    .updateStrengthDraft(
                        durationSeconds:
                            min(
                                max(
                                    rounded,
                                    15
                                ),
                                7_200
                            )
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

    private var strengthRPEBinding: Binding<Double> {
        Binding(
            get: {
                workoutManager
                    .strengthSession?
                    .draftRPE ?? 8
            },
            set: {
                workoutManager.updateStrengthDraft(
                    rpe: $0
                )
            }
        )
    }

    private var strengthRIRBinding: Binding<Double> {
        Binding(
            get: {
                workoutManager
                    .strengthSession?
                    .draftRIR ?? 2
            },
            set: {
                workoutManager.updateStrengthDraft(
                    rir: $0
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
            VStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(WatchTheme.green)

                Text(
                    ATHLTHLocalization.choose(
                        english: "Workout Saved",
                        norwegian: "Økt lagret"
                    )
                )
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(
                    WatchTheme.textPrimary
                )
            }
            .padding(.top, 4)

            if let result = workoutManager.completedResult {
                Text(durationText(result.duration))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(
                        WatchTheme.textPrimary
                    )

                HStack(spacing: 0) {
                    metric(
                        icon: "heart.fill",
                        value: result.averageHeartRate.map {
                            "\(Int($0.rounded()))"
                        } ?? "—",
                        label: "AVG BPM"
                    )

                    Divider()
                        .overlay(
                            WatchTheme.border
                        )

                    metric(
                        icon: "flame.fill",
                        value: "\(Int(result.activeCalories.rounded()))",
                        label: "KCAL"
                    )

                    if result.kind != .strength {
                        Divider()
                            .overlay(
                                WatchTheme.border
                            )

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

                if let laps =
                        result.lapSummaries,
                   !laps.isEmpty {
                    VStack(
                        alignment: .leading,
                        spacing: 7
                    ) {
                        HStack {
                            Label(
                                "Laps",
                                systemImage:
                                    "flag.fill"
                            )
                            .font(
                                .system(
                                    size: 10,
                                    weight: .bold
                                )
                            )
                            .foregroundStyle(
                                WatchTheme.accent
                            )

                            Spacer()

                            Text(
                                "\(laps.count)"
                            )
                            .font(
                                .system(
                                    size: 9,
                                    weight: .bold
                                )
                            )
                            .foregroundStyle(
                                WatchTheme.muted
                            )
                        }

                        ForEach(
                            Array(
                                laps
                                    .suffix(6)
                                    .enumerated()
                            ),
                            id: \.offset
                        ) { _, lap in
                            HStack {
                                Text(
                                    ATHLTHLocalization.format(
                                    "Lap %d",
                                    lap.number
                                )
                                )
                                .font(
                                    .system(
                                        size: 9,
                                        weight: .semibold
                                    )
                                )

                                Spacer()

                                Text(
                                    durationText(
                                        lap.elapsedTime
                                    )
                                )
                                .font(
                                    .system(
                                        size: 9,
                                        weight: .semibold,
                                        design: .rounded
                                    )
                                )
                                .monospacedDigit()

                                if let pace =
                                        lap.averagePaceSecondsPerKilometer {
                                    Text(
                                        lapPaceText(
                                            pace
                                        )
                                    )
                                    .font(
                                        .system(
                                            size: 8,
                                            weight: .semibold,
                                            design: .rounded
                                        )
                                    )
                                    .monospacedDigit()
                                    .foregroundStyle(
                                        WatchTheme.muted
                                    )
                                }
                            }
                        }

                        if let count =
                                result.automaticPauseCount,
                           count > 0 {
                            Label(
                                ATHLTHLocalization.format(
                                    "Auto-Pause %dx",
                                    count
                                ),
                                systemImage:
                                    "pause.circle.fill"
                            )
                            .font(
                                .system(
                                    size: 8,
                                    weight: .semibold
                                )
                            )
                            .foregroundStyle(
                                WatchTheme.muted
                            )
                        }
                    }
                    .padding(10)
                    .watchSurface()
                }

                if let match =
                        result.routeMatchPercent {
                    VStack(
                        alignment: .leading,
                        spacing: 7
                    ) {
                        HStack {
                            Label(
                                "Route match",
                                systemImage:
                                    "checkmark.seal.fill"
                            )
                            .font(
                                .system(
                                    size: 10,
                                    weight: .bold
                                )
                            )
                            .foregroundStyle(
                                WatchTheme.green
                            )

                            Spacer()

                            Text(
                                "\(Int(match.rounded()))%"
                            )
                            .font(
                                .system(
                                    size: 13,
                                    weight: .bold
                                )
                            )
                            .monospacedDigit()
                        }

                        if let average =
                                result
                                    .routeAverageDeviationMeters,
                           let maximum =
                                result
                                    .routeMaxDeviationMeters {
                            Text(
                                ATHLTHLocalization.format(
                                    "Avg %d m · Max %d m deviation",
                                    Int(average.rounded()),
                                    Int(maximum.rounded())
                                )
                            )
                            .font(
                                .system(size: 8)
                            )
                            .foregroundStyle(
                                WatchTheme.muted
                            )
                        }

                        Label(
                            result
                                .routeLeaderboardEligible ==
                                true
                                ? "Leaderboard eligible"
                                : "Route match below leaderboard requirements",
                            systemImage:
                                result
                                    .routeLeaderboardEligible ==
                                    true
                                    ? "trophy.fill"
                                    : "info.circle"
                        )
                        .font(
                            .system(
                                size: 8,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(
                            result
                                .routeLeaderboardEligible ==
                                true
                                ? WatchTheme.green
                                : WatchTheme.muted
                        )
                    }
                    .padding(10)
                    .watchSurface()
                }
            }

            Button {
                workoutManager.reset()
            } label: {
                Text(
                    ATHLTHLocalization.choose(
                        english: "Done",
                        norwegian: "Ferdig"
                    )
                )
                .font(
                    .system(
                        size: 14,
                        weight: .bold
                    )
                )
                .foregroundStyle(
                    Color.white
                )
                .frame(
                    maxWidth: .infinity
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(WatchTheme.green)
        }
        .foregroundStyle(
            WatchTheme.textPrimary
        )
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

    private func lapPaceText(
        _ secondsPerKilometer:
            TimeInterval
    ) -> String {
        guard secondsPerKilometer.isFinite,
              secondsPerKilometer > 0
        else {
            return "—"
        }

        let total =
            max(
                Int(
                    secondsPerKilometer
                        .rounded()
                ),
                0
            )

        return String(
            format:
                "%d:%02d/km",
            total / 60,
            total % 60
        )
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

struct WatchSpotifyRemotePage: View {
    var body: some View {
        // Native watchOS Now Playing controls the audio source that is
        // actually active on the Watch (including third-party apps such as
        // Spotify). Keeping this page system-owned also means downloaded
        // Spotify playback can be controlled while the iPhone is left behind.
        NowPlayingView()
            .ignoresSafeArea()
    }
}


private struct WatchStrengthPrimaryCrownMetric: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let icon: String
    let tint: Color
    var compact: Bool = false

    @FocusState private var crownFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(tint)

                Text(title)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(WatchTheme.muted)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            Text(valueText)
                .font(
                    .system(
                        size:
                            compact
                                ? 20
                                : 22,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            HStack(spacing: 3) {
                Image(
                    systemName:
                        "digitalcrown.horizontal.arrow.clockwise"
                )
                .font(.system(size: 8, weight: .bold))

                Text(
                    ATHLTHLocalization.choose(
                        english: "Crown",
                        norwegian: "Krone"
                    )
                )
                .font(.system(size: 7, weight: .semibold))
            }
            .foregroundStyle(
                crownFocused
                    ? tint
                    : WatchTheme.muted
            )
        }
        .padding(
            compact
                ? 6
                : 8
        )
        .frame(
            maxWidth: .infinity,
            minHeight:
                compact
                    ? 64
                    : 76,
            alignment: .leading
        )
        .background(
            tint.opacity(
                crownFocused ? 0.15 : 0.07
            ),
            in: RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
            .stroke(
                tint.opacity(
                    crownFocused ? 0.48 : 0.14
                ),
                lineWidth:
                    crownFocused ? 1.2 : 0.8
            )
        }
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

private struct WatchStrengthStaticPrimaryMetric: View {
    let title: String
    let valueText: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(tint)

                Text(title)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(WatchTheme.muted)

                Spacer(minLength: 0)
            }

            Text(valueText)
                .font(
                    .system(
                        size: 21,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .padding(8)
        .frame(
            maxWidth: .infinity,
            minHeight: 64,
            alignment: .leading
        )
        .background(
            tint.opacity(0.07),
            in: RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
        )
    }
}


private struct WatchStrengthCrownControl: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let icon: String
    let tint: Color

    @FocusState private var crownFocused: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
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
                        ? tint
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

            WatchLiveWorkoutFocusCard()

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

            if workoutManager.ghostRaceTitle != nil {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Label(
                            "GHOST RACE",
                            systemImage: "figure.run"
                        )
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(WatchTheme.green)

                        Spacer()

                        if let timeDelta =
                                workoutManager
                                    .ghostTimeDeltaSeconds {
                            Text(
                                ghostTimeText(timeDelta)
                            )
                            .font(.system(size: 10, weight: .bold))
                            .monospacedDigit()
                        }
                    }

                    if let distanceDelta =
                            workoutManager
                                .ghostDistanceDeltaMeters {
                        Text(
                            ghostDistanceText(distanceDelta)
                        )
                        .font(
                            .system(
                                size: 17,
                                weight: .bold,
                                design: .rounded
                            )
                        )
                        .minimumScaleFactor(0.72)

                        HStack {
                            Text("YOU")
                            Spacer()
                            Text("GHOST")
                        }
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(WatchTheme.muted)

                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(
                                        WatchTheme.muted
                                            .opacity(0.20)
                                    )
                                Capsule()
                                    .fill(WatchTheme.green)
                                    .frame(
                                        width:
                                            proxy.size.width *
                                            ghostProgressWidth(
                                                distanceDelta
                                            )
                                    )
                            }
                        }
                        .frame(height: 5)
                    } else {
                        Text("Finding both runners on the route…")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(WatchTheme.muted)
                    }
                }
                .padding(10)
                .watchSurface()
            }

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

                    if let toStart =
                            workoutManager
                                .routeDistanceToStartMeters,
                       toStart > 250,
                       (
                            workoutManager
                                .routeProgressPercent ??
                            0
                       ) < 3 {
                        Label(
                            routeDistanceText(toStart) +
                                " to start",
                            systemImage:
                                "location.circle.fill"
                        )
                        .font(
                            .system(
                                size: 9,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(.orange)
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

            if workoutManager.audioCoachConfigured {
                NavigationLink {
                    WatchAudioCoachLiveSettingsView(
                        workoutManager: workoutManager
                    )
                } label: {
                    HStack {
                        Label(
                            "Coach settings",
                            systemImage: "slider.horizontal.3"
                        )

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption2)
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

    private func routeDistanceText(
        _ meters: Double
    ) -> String {
        if meters >= 1_000 {
            return String(
                format: "%.1f km",
                meters / 1_000
            )
        }

        return "\(Int(meters.rounded())) m"
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

        if meters <=
            workoutManager
                .routeAlertConfiguration
                .deviationMeters {
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

    private func ghostDistanceText(
        _ delta: Double
    ) -> String {
        let meters =
            Int(abs(delta).rounded())

        if meters < 8 {
            return "Neck and neck"
        }

        return delta >= 0
            ? "You +\(meters) m"
            : "Ghost +\(meters) m"
    }

    private func ghostTimeText(
        _ delta: TimeInterval
    ) -> String {
        let seconds =
            Int(abs(delta).rounded())
        let prefix =
            delta >= 0 ? "−" : "+"

        return prefix +
            String(
                format: "%d:%02d",
                seconds / 60,
                seconds % 60
            )
    }

    private func ghostProgressWidth(
        _ delta: Double
    ) -> Double {
        let normalized =
            min(
                abs(delta) / 150,
                1
            )

        if abs(delta) < 8 {
            return 0.5
        }

        return delta >= 0
            ? 0.5 + normalized * 0.5
            : 0.5 - normalized * 0.5
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


private struct WatchAudioCoachLiveSettingsView: View {
    @ObservedObject var workoutManager: WatchWorkoutManager

    var body: some View {
        Form {
            Section("Audio Coach") {
                Toggle(
                    "Enabled",
                    isOn: boolBinding(\.enabled)
                )

                Text(
                    "Changes apply immediately to this workout only."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            if configuration.enabled {
                Section("When to speak") {
                    Toggle(
                        "Distance",
                        isOn: distanceTriggerBinding
                    )

                    if configuration.distanceIntervalMeters != nil {
                        Stepper(
                            distanceIntervalLabel,
                            value: distanceIntervalBinding,
                            in: 250...10_000,
                            step: 250
                        )
                    }

                    Toggle(
                        "Time",
                        isOn: timeTriggerBinding
                    )

                    if configuration.timeIntervalSeconds != nil {
                        Stepper(
                            timeIntervalLabel,
                            value: timeIntervalBinding,
                            in: 60...3_600,
                            step: 60
                        )
                    }
                }

                Section("Workout updates") {
                    Toggle(
                        "Distance",
                        isOn: boolBinding(\.announceDistance)
                    )
                    Toggle(
                        "Elapsed time",
                        isOn: boolBinding(\.announceElapsedTime)
                    )
                    Toggle(
                        "Average pace",
                        isOn: boolBinding(\.announceAveragePace)
                    )
                    Toggle(
                        "Current time",
                        isOn: boolBinding(\.announceClockTime)
                    )
                    Toggle(
                        "Heart rate",
                        isOn: boolBinding(\.announceHeartRate)
                    )
                }

                Section("Route") {
                    Toggle(
                        "Remaining distance",
                        isOn:
                            boolBinding(
                                \.announceRemainingRouteDistance
                            )
                    )
                    Toggle(
                        "Estimated time left",
                        isOn:
                            boolBinding(
                                \.announceEstimatedRemainingRouteTime
                            )
                    )
                }

                Section("Structured workout") {
                    Toggle(
                        "Current / next step",
                        isOn:
                            boolBinding(
                                \.announceCurrentWorkoutStep
                            )
                    )
                    Toggle(
                        "Remaining step time",
                        isOn:
                            boolBinding(
                                \.announceRemainingStepTime
                            )
                    )
                    Toggle(
                        "Remaining step distance",
                        isOn:
                            boolBinding(
                                \.announceRemainingStepDistance
                            )
                    )
                }

                Section("Music") {
                    Toggle(
                        "Lower music for coach",
                        isOn: duckOtherAudioBinding
                    )

                    Text(
                        configuration.shouldDuckOtherAudio
                            ? "Spotify returns to normal volume after each cue."
                            : "Coach mixes with music at full music volume."
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Section("Voice") {
                    Picker(
                        "Language",
                        selection: languageBinding
                    ) {
                        ForEach(
                            WatchAudioCoachLanguage.allCases,
                            id: \.self
                        ) { language in
                            Text(language.title)
                                .tag(language)
                        }
                    }
                }
            }
        }
        .navigationTitle("Audio Coach")
    }

    private var configuration:
        WatchAudioCoachConfiguration {
        workoutManager.audioCoachConfiguration
    }

    private func update(
        _ mutate:
            (inout WatchAudioCoachConfiguration) -> Void
    ) {
        var updated = configuration
        mutate(&updated)
        workoutManager.updateAudioCoachDuringWorkout(updated)
    }

    private func boolBinding(
        _ keyPath:
            WritableKeyPath<
                WatchAudioCoachConfiguration,
                Bool
            >
    ) -> Binding<Bool> {
        Binding(
            get: {
                configuration[keyPath: keyPath]
            },
            set: { value in
                update {
                    $0[keyPath: keyPath] = value
                }
            }
        )
    }

    private var languageBinding:
        Binding<WatchAudioCoachLanguage> {
        Binding(
            get: {
                configuration.language
            },
            set: { value in
                update {
                    $0.language = value
                }
            }
        )
    }

    private var duckOtherAudioBinding:
        Binding<Bool> {
        Binding(
            get: {
                configuration.shouldDuckOtherAudio
            },
            set: { value in
                update {
                    $0.duckOtherAudio = value
                }
            }
        )
    }

    private var distanceTriggerBinding:
        Binding<Bool> {
        Binding(
            get: {
                configuration.distanceIntervalMeters != nil
            },
            set: { enabled in
                update {
                    $0.distanceIntervalMeters =
                        enabled
                            ? (
                                $0.distanceIntervalMeters ??
                                1_000
                            )
                            : nil
                }
            }
        )
    }

    private var timeTriggerBinding:
        Binding<Bool> {
        Binding(
            get: {
                configuration.timeIntervalSeconds != nil
            },
            set: { enabled in
                update {
                    $0.timeIntervalSeconds =
                        enabled
                            ? (
                                $0.timeIntervalSeconds ??
                                600
                            )
                            : nil
                }
            }
        )
    }

    private var distanceIntervalBinding:
        Binding<Double> {
        Binding(
            get: {
                configuration.distanceIntervalMeters ??
                1_000
            },
            set: { value in
                update {
                    $0.distanceIntervalMeters = value
                }
            }
        )
    }

    private var timeIntervalBinding:
        Binding<Double> {
        Binding(
            get: {
                configuration.timeIntervalSeconds ??
                600
            },
            set: { value in
                update {
                    $0.timeIntervalSeconds = value
                }
            }
        )
    }

    private var distanceIntervalLabel: String {
        let meters =
            configuration.distanceIntervalMeters ??
            1_000

        if meters >= 1_000 {
            return String(
                format: "%.2g km",
                meters / 1_000
            )
        }

        return "\(Int(meters.rounded())) m"
    }

    private var timeIntervalLabel: String {
        let minutes =
            max(
                Int(
                    (
                        (
                            configuration
                                .timeIntervalSeconds ??
                            600
                        ) / 60
                    ).rounded()
                ),
                1
            )

        return "\(minutes) min"
    }
}

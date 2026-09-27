import SwiftUI

enum GhostTargetTimeFormatter {
    static func parse(
        _ text: String
    ) -> TimeInterval? {
        let cleaned =
            text
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        guard !cleaned.isEmpty else {
            return nil
        }

        let parts =
            cleaned.split(
                separator: ":",
                omittingEmptySubsequences: false
            )

        guard (1...3).contains(parts.count),
              parts.allSatisfy({
                  Int($0) != nil
              })
        else {
            return nil
        }

        let values =
            parts.compactMap {
                Int($0)
            }

        let total: Int

        switch values.count {
        case 1:
            total =
                values[0] * 60
        case 2:
            guard values[1] < 60 else {
                return nil
            }
            total =
                values[0] * 60 +
                values[1]
        case 3:
            guard values[1] < 60,
                  values[2] < 60
            else {
                return nil
            }
            total =
                values[0] * 3_600 +
                values[1] * 60 +
                values[2]
        default:
            return nil
        }

        guard total >= 60 else {
            return nil
        }

        return TimeInterval(total)
    }

    static func string(
        _ seconds: TimeInterval
    ) -> String {
        let total =
            max(
                Int(seconds.rounded()),
                0
            )
        let hours = total / 3_600
        let minutes =
            (total % 3_600) / 60
        let remainder =
            total % 60

        if hours > 0 {
            return String(
                format:
                    "%d:%02d:%02d",
                hours,
                minutes,
                remainder
            )
        }

        return String(
            format: "%d:%02d",
            minutes,
            remainder
        )
    }

    static func paceText(
        distanceKilometers: Double,
        duration: TimeInterval
    ) -> String {
        guard distanceKilometers > 0,
              duration > 0
        else {
            return "— /km"
        }

        let secondsPerKilometer =
            duration /
            distanceKilometers
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
                "%d:%02d /km",
            total / 60,
            total % 60
        )
    }
}

struct TargetGhostRoutePickerView: View {
    @EnvironmentObject private var session:
        AppSessionStore

    var body: some View {
        List {
            Section {
                Text(
                    "Choose a saved route, set the finish time you want, and ATHLTH creates a synthetic ghost that follows the course at the required average pace."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Section("My routes") {
                if session.savedRoutes.isEmpty {
                    ContentUnavailableView(
                        "No saved routes",
                        systemImage:
                            "map.fill",
                        description: Text(
                            "Create or save a route first."
                        )
                    )
                } else {
                    ForEach(
                        session.savedRoutes
                            .sorted {
                                $0.createdAt >
                                $1.createdAt
                            }
                    ) { route in
                        NavigationLink {
                            TargetGhostSetupView(
                                route: route
                            )
                        } label: {
                            HStack(spacing: 12) {
                                Image(
                                    systemName:
                                        "timer.circle.fill"
                                )
                                .font(.title3)
                                .foregroundStyle(
                                    ATHLTHTheme.vitality
                                )

                                VStack(
                                    alignment: .leading,
                                    spacing: 3
                                ) {
                                    Text(route.title)
                                        .font(
                                            .subheadline
                                                .weight(
                                                    .semibold
                                                )
                                        )

                                    Text(
                                        String(
                                            format:
                                                "%.2f km",
                                            route
                                                .distanceKilometers
                                        )
                                    )
                                    .font(.caption)
                                    .foregroundStyle(
                                        .secondary
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Target Ghost")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TargetGhostSetupView: View {
    @Environment(\.dismiss)
    private var dismiss

    @EnvironmentObject private var session:
        AppSessionStore
    @EnvironmentObject private var settings:
        AppSettingsStore
    @EnvironmentObject private var watchConnection:
        AppleWatchConnectionStore
    @EnvironmentObject private var ghostRace:
        GhostRaceStore

    let route: TrainingRoute
    var challengeTitle: String? = nil

    @State private var targetTimeText: String
    @State private var starting = false
    @State private var errorMessage: String?

    init(
        route: TrainingRoute,
        challengeTitle: String? = nil
    ) {
        self.route = route
        self.challengeTitle = challengeTitle

        let suggested =
            route.expectedTravelTimeSeconds ??
            max(
                route.distanceKilometers *
                    330,
                5 * 60
            )

        _targetTimeText =
            State(
                initialValue:
                    GhostTargetTimeFormatter
                        .string(suggested)
            )
    }

    private var targetDuration:
        TimeInterval? {
        GhostTargetTimeFormatter.parse(
            targetTimeText
        )
    }

    private var canStart: Bool {
        targetDuration != nil &&
        settings.trainingDeviceProvider ==
            .appleWatch &&
        watchConnection.isReady &&
        !watchConnection
            .workoutLaunchInProgress &&
        !starting
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ATHLTHCard {
                    VStack(
                        alignment: .leading,
                        spacing: 12
                    ) {
                        Label(
                            "TARGET GHOST",
                            systemImage:
                                "timer.circle.fill"
                        )
                        .font(
                            .caption
                                .weight(.bold)
                        )
                        .tracking(1.5)
                        .foregroundStyle(
                            ATHLTHTheme.vitality
                        )

                        Text(
                            challengeTitle ??
                            route.title
                        )
                        .font(.title2.bold())

                        Text(
                            "The ghost is synthetic. It moves along the selected route at the pace required to reach the finish at your chosen time."
                        )
                        .font(.subheadline)
                        .foregroundStyle(
                            .secondary
                        )

                        HStack(spacing: 18) {
                            Label(
                                String(
                                    format:
                                        "%.2f km",
                                    route
                                        .distanceKilometers
                                ),
                                systemImage:
                                    "location.fill"
                            )

                            if let targetDuration {
                                Label(
                                    GhostTargetTimeFormatter
                                        .paceText(
                                            distanceKilometers:
                                                route
                                                    .distanceKilometers,
                                            duration:
                                                targetDuration
                                        ),
                                    systemImage:
                                        "gauge.with.dots.needle.50percent"
                                )
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                    }
                }

                ATHLTHCard {
                    VStack(
                        alignment: .leading,
                        spacing: 12
                    ) {
                        Text("Target finish time")
                            .font(.headline)

                        TextField(
                            "45:00",
                            text:
                                $targetTimeText
                        )
                        .font(
                            .system(
                                size: 34,
                                weight: .bold,
                                design: .rounded
                            )
                        )
                        .monospacedDigit()
                        .keyboardType(
                            .numbersAndPunctuation
                        )
                        .textInputAutocapitalization(
                            .never
                        )
                        .autocorrectionDisabled()
                        .padding(14)
                        .background(
                            ATHLTHTheme
                                .surfaceSage,
                            in:
                                RoundedRectangle(
                                    cornerRadius:
                                        16
                                )
                        )

                        Text(
                            "Use MM:SS or H:MM:SS. Example: 45:00 or 1:30:00."
                        )
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )

                        if let targetDuration {
                            HStack {
                                Text(
                                    "Required average pace"
                                )
                                Spacer()
                                Text(
                                    GhostTargetTimeFormatter
                                        .paceText(
                                            distanceKilometers:
                                                route
                                                    .distanceKilometers,
                                            duration:
                                                targetDuration
                                        )
                                )
                                .bold()
                                .monospacedDigit()
                            }
                            .font(.subheadline)
                        }
                    }
                }

                Button {
                    Task {
                        await start()
                    }
                } label: {
                    if starting {
                        ProgressView()
                            .frame(
                                maxWidth:
                                    .infinity
                            )
                    } else {
                        Label(
                            "Start Target Ghost",
                            systemImage:
                                "figure.run"
                        )
                        .frame(
                            maxWidth:
                                .infinity
                        )
                    }
                }
                .buttonStyle(
                    .borderedProminent
                )
                .tint(
                    ATHLTHTheme.vitality
                )
                .controlSize(.large)
                .disabled(!canStart)

                if settings
                    .trainingDeviceProvider !=
                    .appleWatch ||
                    !watchConnection.isReady {
                    Label(
                        "Target Ghost currently requires a connected Apple Watch.",
                        systemImage:
                            "applewatch.slash"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        .orange
                    )
                }
            }
            .padding()
            .frame(
                maxWidth: 680
            )
            .frame(
                maxWidth: .infinity
            )
        }
        .navigationTitle("Target Ghost")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Target Ghost",
            isPresented: Binding(
                get: {
                    errorMessage != nil
                },
                set: { visible in
                    if !visible {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button(
                "OK",
                role: .cancel
            ) {}
        } message: {
            Text(
                errorMessage ?? ""
            )
        }
    }

    @MainActor
    private func start() async {
        guard let targetDuration else {
            errorMessage =
                "Enter a valid target finish time."
            return
        }

        starting = true
        defer {
            starting = false
        }

        do {
            try await GhostRaceStartService
                .startTarget(
                    route: route,
                    targetDurationSeconds:
                        targetDuration,
                    ownerID:
                        session.profile.userID,
                    ghostRace:
                        ghostRace,
                    watchConnection:
                        watchConnection,
                    settings:
                        settings
                )

            dismiss()
        } catch {
            errorMessage =
                error.localizedDescription
        }
    }
}

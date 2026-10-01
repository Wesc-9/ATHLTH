import SwiftUI

struct WatchLiveWorkoutFocusCard: View {
    @EnvironmentObject private var workoutManager: WatchWorkoutManager

    var body: some View {
        if workoutManager.liveSurfaceConfiguration.watchEnabled {
            content
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .watchSurface(radius: 18)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch focus {
        case .routeGuardian:
            routeContent
        case .zoneLock:
            zoneContent
        case .ghostGap:
            ghostContent
        case .liveChallenge:
            challengeContent
        case .liveShare:
            liveShareContent
        case .workout:
            workoutContent
        }
    }

    private var focus: ATHLTHLiveWorkoutFocus {
        ATHLTHLiveWorkoutPriorityResolver.resolve(
            configuration: workoutManager.liveSurfaceConfiguration,
            state: ATHLTHLiveWorkoutPriorityState(
                hasRoute:
                    workoutManager.plannedRoute != nil ||
                    workoutManager.routeProgressPercent != nil,
                routeDeviationMeters:
                    workoutManager.routeDeviationMeters,
                routeDeviationThresholdMeters:
                    workoutManager.routeAlertConfiguration
                        .deviationMeters,
                hasZoneTarget:
                    workoutManager.targetAlertConfiguration?
                        .heartRateEnabled == true,
                zoneStatus:
                    workoutManager.liveTargetStatus,
                hasGhost:
                    workoutManager.ghostRaceTitle != nil ||
                    workoutManager.liveSurfaceContext
                        .liveGhost != nil,
                hasChallenge:
                    workoutManager.liveSurfaceContext
                        .challenge != nil,
                hasLiveShare:
                    workoutManager.liveSurfaceContext
                        .liveShare?.isSharing == true
            )
        )
    }

    private var routeContent: some View {
        let deviation =
            workoutManager.routeDeviationMeters
        let threshold =
            workoutManager.routeAlertConfiguration
                .deviationMeters
        let offRoute =
            deviation.map { $0 > threshold } ?? false

        return VStack(alignment: .leading, spacing: 6) {
            Label(
                offRoute ? "OFF ROUTE" : "ROUTE GUARDIAN",
                systemImage:
                    offRoute
                        ? "exclamationmark.triangle.fill"
                        : "location.fill"
            )
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(offRoute ? .orange : WatchTheme.green)

            HStack(alignment: .firstTextBaseline) {
                Text(
                    offRoute
                        ? distanceText(deviation)
                        : distanceText(
                            workoutManager.routeRemainingMeters
                        )
                )
                .font(.system(
                    size: 25,
                    weight: .bold,
                    design: .rounded
                ))
                .monospacedDigit()

                Spacer()

                Text(offRoute ? "RETURN" : "REMAINING")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(WatchTheme.muted)
            }

            if let progress = workoutManager.routeProgressPercent {
                ProgressView(
                    value: min(
                        max(progress / 100, 0),
                        1
                    )
                )
                    .tint(offRoute ? .orange : WatchTheme.green)
            }
        }
    }

    private var zoneContent: some View {
        let target =
            workoutManager.targetAlertConfiguration

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(
                    target?.heartRateZone.map { "ZONE \($0)" } ??
                        "ZONE LOCK",
                    systemImage: "heart.fill"
                )
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(WatchTheme.green)

                Spacer()

                Text(
                    workoutManager.liveTargetStatus ??
                    "Live"
                )
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(
                    workoutManager.liveTargetStatus == "On target"
                        ? WatchTheme.green
                        : .orange
                )
                .lineLimit(1)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(
                    workoutManager.heartRate > 0
                        ? "\(Int(workoutManager.heartRate.rounded()))"
                        : "—"
                )
                .font(.system(
                    size: 28,
                    weight: .bold,
                    design: .rounded
                ))
                .monospacedDigit()

                Text("BPM")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(WatchTheme.muted)

                Spacer()

                if let min = target?.heartRateMinimumBPM,
                   let max = target?.heartRateMaximumBPM {
                    Text(
                        "\(Int(min.rounded()))–\(Int(max.rounded()))"
                    )
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                }
            }
        }
    }

    private var ghostContent: some View {
        let liveGhost =
            workoutManager
                .liveSurfaceContext
                .liveGhost
        let title =
            workoutManager
                .ghostRaceTitle ??
            liveGhost?.title ??
            "Ghost"
        let distance =
            workoutManager
                .ghostDistanceDeltaMeters ??
            liveGhost?
                .distanceDeltaMeters
        let time =
            workoutManager
                .ghostTimeDeltaSeconds ??
            liveGhost?
                .estimatedTimeDeltaSeconds
        let liveGhostAge =
            liveGhost.map {
                max(
                    Date().timeIntervalSince(
                        $0.updatedAt
                    ),
                    0
                )
            }
        let liveGhostIsStale =
            liveGhostAge.map {
                $0 > 10
            } ?? false

        return VStack(
            alignment: .leading,
            spacing: 6
        ) {
            HStack {
                Label(
                    liveGhost != nil &&
                    workoutManager
                        .ghostRaceTitle == nil
                        ? (
                            liveGhostIsStale
                                ? "GHOST STALE"
                                : "LIVE GHOST"
                        )
                        : "GHOST GAP",
                    systemImage:
                        liveGhostIsStale
                            ? "arrow.triangle.2.circlepath"
                            : "figure.run"
                )
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(
                    liveGhostIsStale
                        ? .orange
                        : WatchTheme.green
                )

                Spacer()

                if let time {
                    Text(ghostTime(time))
                        .font(.system(size: 11, weight: .bold))
                        .monospacedDigit()
                }
            }

            if let distance {
                Text(ghostDistance(distance))
                    .font(.system(
                        size: 20,
                        weight: .bold,
                        design: .rounded
                    ))
                    .minimumScaleFactor(0.72)

                Text(
                    liveGhostIsStale,
                    format: .number
                )
                .hidden()
                .frame(width: 0, height: 0)

                Text(
                    liveGhostIsStale,
                    format: .number
                )
                .hidden()
                .frame(width: 0, height: 0)

                Text(
                    liveGhostIsStale,
                    format: .number
                )
                .hidden()
                .frame(width: 0, height: 0)

                Text(
                    liveGhostIsStale &&
                    liveGhostAge != nil
                        ? "\(title) · \(Int((liveGhostAge ?? 0).rounded()))s ago"
                        : title
                )
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(WatchTheme.muted)
                .lineLimit(1)
            } else {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)
            }
        }
    }

    private var challengeContent: some View {
        let challenge =
            workoutManager.liveSurfaceContext.challenge

        return VStack(alignment: .leading, spacing: 6) {
            Label(
                "LIVE CHALLENGE",
                systemImage: "trophy.fill"
            )
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(WatchTheme.green)

            Text(challenge?.title ?? "Challenge")
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)

            if let target = challenge?.targetDistanceMeters,
               target > 0 {
                HStack {
                    Text(
                        String(
                            format: "%.1f / %.1f km",
                            workoutManager.distanceMeters / 1_000,
                            target / 1_000
                        )
                    )
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()

                    Spacer()

                    ProgressView(
                        value: min(
                            max(
                                workoutManager.distanceMeters / target,
                                0
                            ),
                            1
                        )
                    )
                    .frame(width: 48)
                    .tint(WatchTheme.green)
                }
            }
        }
    }

    private var liveShareContent: some View {
        let share =
            workoutManager.liveSurfaceContext.liveShare

        return VStack(alignment: .leading, spacing: 6) {
            Label(
                "LIVE SHARE",
                systemImage: "dot.radiowaves.left.and.right"
            )
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(WatchTheme.green)

            Text("LIVE · \(max(share?.viewerCount ?? 0, 0))")
                .font(.system(
                    size: 22,
                    weight: .bold,
                    design: .rounded
                ))

            Text(
                share?.viewerSummary ??
                "Location sharing active"
            )
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(WatchTheme.muted)
            .lineLimit(1)
        }
    }

    private var workoutContent: some View {
        HStack {
            Label(
                workoutManager.state == .paused
                    ? "PAUSED"
                    : "LIVE WORKOUT",
                systemImage: workoutManager.kind.systemImage
            )
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(WatchTheme.green)

            Spacer()

            Text(durationText(workoutManager.elapsedTime))
                .font(.system(size: 12, weight: .bold))
                .monospacedDigit()
        }
    }

    private func distanceText(_ meters: Double?) -> String {
        guard let meters, meters.isFinite else {
            return "—"
        }

        if meters >= 1_000 {
            return String(format: "%.1f km", meters / 1_000)
        }

        return "\(Int(max(meters, 0).rounded())) m"
    }

    private func ghostDistance(_ delta: Double) -> String {
        let meters = Int(abs(delta).rounded())

        if meters < 8 {
            return "Neck and neck"
        }

        return delta >= 0
            ? "You +\(meters) m"
            : "Ghost +\(meters) m"
    }

    private func ghostTime(_ delta: TimeInterval) -> String {
        let seconds = Int(abs(delta).rounded())
        let prefix = delta >= 0 ? "−" : "+"

        if seconds >= 60 {
            return prefix + String(
                format: "%d:%02d",
                seconds / 60,
                seconds % 60
            )
        }

        return prefix + "\(seconds)s"
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let total = max(Int(duration.rounded(.down)), 0)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
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
}

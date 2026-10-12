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

    /// Periodic evaluation also works when the iPhone stops sending
    /// contexts entirely. A stale Ghost lead must expire on Watch itself.
    private var ghostContent: some View {
        TimelineView(.periodic(from: .now, by: 5)) { timeline in
            ghostContent(at: timeline.date)
        }
    }

    private func ghostContent(at now: Date) -> some View {
        let liveGhost = workoutManager.liveSurfaceContext.liveGhost
        let signal = ATHLTHLiveGhostWatchSignal.resolve(
            context: liveGhost,
            isPaused: workoutManager.state == .paused,
            now: now
        )
        let opponent = liveGhost?.opponentName ??
            workoutManager.ghostRaceTitle ??
            liveGhost?.title ?? "Ghost"
        let isLiveDuel = liveGhost != nil
        let distance = isLiveDuel
            ? (signal == .live ? liveGhost?.distanceDeltaMeters : nil)
            : workoutManager.ghostDistanceDeltaMeters
        let time = isLiveDuel
            ? (signal == .live ? liveGhost?.estimatedTimeDeltaSeconds : nil)
            : workoutManager.ghostTimeDeltaSeconds
        let status: String = {
            if !isLiveDuel { return "GHOST GAP" }
            switch signal {
            case .live: return ATHLTHLocalization.choose(
                english: "LIVE DUEL", norwegian: "LIVE DUELL"
            )
            case .paused: return ATHLTHLocalization.choose(
                english: "RACE PAUSED", norwegian: "DUELL PAUSET"
            )
            case .delayed: return ATHLTHLocalization.choose(
                english: "GPS DELAYED", norwegian: "GPS FORSINKET"
            )
            case .waiting: return ATHLTHLocalization.choose(
                english: "WAITING FOR GPS", norwegian: "VENTER PÅ GPS"
            )
            }
        }()
        let color: Color = isLiveDuel && signal != .live
            ? (signal == .paused ? WatchTheme.muted : .orange)
            : WatchTheme.green

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(
                    status,
                    systemImage: isLiveDuel && signal != .live
                        ? (signal == .paused ? "pause.circle.fill" : "wifi.exclamationmark")
                        : "figure.run"
                )
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

                Spacer(minLength: 4)

                if let time, time.isFinite {
                    Text(ghostTime(time))
                        .font(.system(size: 11, weight: .bold))
                        .monospacedDigit()
                }
            }

            if let distance, distance.isFinite {
                if isLiveDuel {
                    Text(abs(distance) < 8
                        ? ATHLTHLocalization.choose(
                            english: "SIDE BY SIDE", norwegian: "SIDE OM SIDE"
                        )
                        : (distance > 0
                            ? ATHLTHLocalization.choose(
                                english: "YOU LEAD", norwegian: "DU LEDER"
                            )
                            : ATHLTHLocalization.choose(
                                english: "RIVAL LEADS", norwegian: "MOTSTANDER LEDER"
                            )
                        )
                    )
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(WatchTheme.muted)

                    Text("\(Int(abs(distance).rounded())) m")
                        .font(.system(
                            size: 27, weight: .bold, design: .rounded
                        ))
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                } else {
                    Text(ghostDistance(distance))
                        .font(.system(
                            size: 22, weight: .bold, design: .rounded
                        ))
                        .minimumScaleFactor(0.72)
                        .lineLimit(1)
                }
            } else if isLiveDuel {
                Text(
                    signal == .paused
                        ? ATHLTHLocalization.choose(
                            english: "Workout paused", norwegian: "Økten er pauset"
                        )
                        : ATHLTHLocalization.choose(
                            english: "No current race gap", norwegian: "Ingen fersk avstand"
                        )
                )
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(2)
            } else {
                Text(opponent)
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)
            }

            if isLiveDuel {
                Text(opponent)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WatchTheme.muted)
                    .lineLimit(1)

                if signal == .live,
                   let own = liveGhost?.ownProgressPercent,
                   let rival = liveGhost?.opponentProgressPercent,
                   own.isFinite, rival.isFinite {
                    ProgressView(value: min(max(own / 100, 0), 1))
                        .tint(WatchTheme.green)
                        .accessibilityLabel(ATHLTHLocalization.choose(
                            english: "Your route progress",
                            norwegian: "Din fremdrift på ruten"
                        ))
                }
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

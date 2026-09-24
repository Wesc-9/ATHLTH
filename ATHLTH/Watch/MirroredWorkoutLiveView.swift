import SwiftUI

struct MirroredWorkoutLiveView: View {
    @EnvironmentObject private var mirroring: WorkoutMirroringStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header

                    if let snapshot = mirroring.snapshot {
                        timer(snapshot)

                        HStack(spacing: 12) {
                            metricCard(
                                title: "Heart rate",
                                value: snapshot.heartRate > 0
                                    ? "\(Int(snapshot.heartRate.rounded()))"
                                    : "—",
                                unit: "bpm",
                                icon: "heart.fill"
                            )

                            metricCard(
                                title: "Calories",
                                value: "\(Int(snapshot.activeCalories.rounded()))",
                                unit: "kcal",
                                icon: "flame.fill"
                            )

                            if snapshot.kind.supportsDistanceMetric {
                                metricCard(
                                    title: "Distance",
                                    value: String(
                                        format: "%.2f",
                                        snapshot.distanceMeters / 1000
                                    ),
                                    unit: "km",
                                    icon: "location.fill"
                                )
                            }
                        }

                        ATHLTHCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Apple Watch")
                                        .font(.headline)

                                    Text(mirroring.connectionText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Label(
                                    statusTitle(snapshot.state),
                                    systemImage: statusIcon(snapshot.state)
                                )
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(statusColor(snapshot.state))
                            }
                        }

                        if let errorMessage = mirroring.errorMessage {
                            Label(
                                errorMessage,
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        controls(snapshot)
                    } else {
                        ContentUnavailableView(
                            "Waiting for Apple Watch",
                            systemImage: "applewatch",
                            description: Text(
                                "Start an ATHLTH workout on Apple Watch to mirror it here."
                            )
                        )
                    }
                }
                .padding()
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Live Workout")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(mirroring.hasActiveMirroredWorkout)
    }

    @ViewBuilder
    private var header: some View {
        if let snapshot = mirroring.snapshot {
            ATHLTHCard {
                HStack(spacing: 14) {
                    Image(systemName: snapshot.kind.systemImage)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.accent)
                        .frame(width: 50, height: 50)
                        .background(ATHLTHTheme.accent.opacity(0.10), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(snapshot.kind.title)
                            .font(.title2.weight(.bold))

                        Text("Live from Apple Watch")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Circle()
                        .fill(
                            mirroring.hasActiveMirroredWorkout
                                ? ATHLTHTheme.accent
                                : Color.secondary
                        )
                        .frame(width: 10, height: 10)
                }
            }
        }
    }

    @ViewBuilder
    private func timer(_ snapshot: WatchWorkoutLiveSnapshot) -> some View {
        ATHLTHCard {
            VStack(spacing: 6) {
                Text("Duration")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(
                        durationText(
                            displayedElapsedTime(
                                snapshot: snapshot,
                                now: context.date
                            )
                        )
                    )
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func metricCard(
        title: String,
        value: String,
        unit: String,
        icon: String
    ) -> some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(ATHLTHTheme.accent)

                Text(value)
                    .font(.title2.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(unit)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func controls(_ snapshot: WatchWorkoutLiveSnapshot) -> some View {
        if snapshot.state == .completed || snapshot.state == .failed {
            Button {
                mirroring.dismissSummary()
            } label: {
                Label("Done", systemImage: "checkmark")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(ATHLTHTheme.accent)
        } else {
            HStack(spacing: 12) {
                Button {
                    mirroring.sendCommand(
                        snapshot.state == .paused ? .resume : .pause
                    )
                } label: {
                    Label(
                        snapshot.state == .paused ? "Resume" : "Pause",
                        systemImage: snapshot.state == .paused
                            ? "play.fill"
                            : "pause.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(
                    snapshot.state == .preparing ||
                    snapshot.state == .ending
                )

                Button(role: .destructive) {
                    mirroring.sendCommand(.end)
                } label: {
                    Label("Finish", systemImage: "stop.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.red)
                .disabled(snapshot.state == .ending)
            }
        }
    }

    private func displayedElapsedTime(
        snapshot: WatchWorkoutLiveSnapshot,
        now: Date
    ) -> TimeInterval {
        guard snapshot.state == .running else {
            return snapshot.elapsedTime
        }

        return max(
            snapshot.elapsedTime,
            snapshot.elapsedTime + now.timeIntervalSince(snapshot.capturedAt)
        )
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return String(
                format: "%d:%02d:%02d",
                hours,
                minutes,
                seconds
            )
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func statusTitle(
        _ state: WatchWorkoutMirrorState
    ) -> String {
        switch state {
        case .preparing: return "Starting"
        case .running: return "Live"
        case .paused: return "Paused"
        case .ending: return "Saving"
        case .completed: return "Completed"
        case .failed: return "Error"
        }
    }

    private func statusIcon(
        _ state: WatchWorkoutMirrorState
    ) -> String {
        switch state {
        case .preparing: return "hourglass"
        case .running: return "waveform.path.ecg"
        case .paused: return "pause.circle.fill"
        case .ending: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private func statusColor(
        _ state: WatchWorkoutMirrorState
    ) -> Color {
        switch state {
        case .running, .completed:
            return ATHLTHTheme.accent
        case .paused, .preparing, .ending:
            return .orange
        case .failed:
            return .red
        }
    }
}

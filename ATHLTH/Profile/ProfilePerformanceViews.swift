import SwiftUI

struct ProfilePerformanceSection: View {
    let stats: ProfilePerformanceStats?
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Performance Stats")
                        .font(.title3.weight(.bold))

                    Label("Verified from Apple Health", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.accent)
                }

                Spacer()

                NavigationLink {
                    PerformanceStatsView(stats: stats)
                } label: {
                    HStack(spacing: 4) {
                        Text("View All")
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accent)
                }
                .disabled(stats == nil)
            }

            if isLoading && stats == nil {
                HStack {
                    ProgressView()
                    Text("Reading your all-time performance…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 18)
            } else if let stats {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    performanceTile(
                        icon: "figure.run",
                        title: "Fastest 1K",
                        value: stats.fastestOneKilometer?.formattedTime ?? "—",
                        detail: stats.fastestOneKilometer?.formattedPace ?? "GPS verified",
                        tint: .green
                    )

                    performanceTile(
                        icon: "figure.run.circle.fill",
                        title: "Fastest 5K",
                        value: stats.fastestFiveKilometers?.formattedTime ?? "—",
                        detail: stats.fastestFiveKilometers?.formattedPace ?? "GPS verified",
                        tint: .blue
                    )

                    performanceTile(
                        icon: "flag.checkered",
                        title: "Marathon",
                        value: stats.fastestMarathon?.formattedTime ?? "—",
                        detail: stats.fastestMarathon?.formattedPace ?? "No verified 42.2K yet",
                        tint: .purple
                    )

                    performanceTile(
                        icon: "point.topleft.down.to.point.bottomright.curvepath",
                        title: "Longest Run",
                        value: formatDistance(stats.longestRunMeters),
                        detail: formatMil(stats.longestRunMeters),
                        tint: .orange
                    )

                    performanceTile(
                        icon: "clock.fill",
                        title: "Longest Session",
                        value: formatDuration(stats.longestWorkoutDuration),
                        detail: stats.longestWorkoutActivity?.rawValue ?? "Workout",
                        tint: .cyan
                    )

                    performanceTile(
                        icon: "figure.run",
                        title: "Running Distance",
                        value: formatDistance(stats.totalRunningDistanceMeters),
                        detail: formatMil(stats.totalRunningDistanceMeters),
                        tint: ATHLTHTheme.accent
                    )
                }
                .padding(.top, 12)
            } else {
                Text("Connect Apple Health to build verified performance stats.")
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .padding(.vertical, 12)
            }
        }
        .padding(18)
        .background(
            Color.white.opacity(0.82),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(ATHLTHTheme.border.opacity(0.72), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.035), radius: 16, x: 0, y: 8)
    }

    private func performanceTile(
        icon: String,
        title: String,
        value: String,
        detail: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.10), in: Circle())

                Spacer()

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(ATHLTHTheme.accentDeep.opacity(0.55))
            }

            Text(value)
                .font(.title3.monospacedDigit().weight(.bold))
                .foregroundStyle(ATHLTHTheme.primaryText)
                .minimumScaleFactor(0.68)
                .lineLimit(1)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.primaryText)
                .lineLimit(1)

            Text(detail)
                .font(.system(size: 9))
                .foregroundStyle(ATHLTHTheme.mutedText)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    tint.opacity(0.08),
                    Color.white.opacity(0.72)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.10), lineWidth: 1)
        }
    }
}

struct PerformanceStatsView: View {
    let stats: ProfilePerformanceStats?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                passportHero

                if let stats {
                    runningSection(stats)
                    volumeSection(stats)
                    verificationSection
                } else {
                    ContentUnavailableView(
                        "No performance data",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("ATHLTH needs Apple Health workout data to build your Performance Passport.")
                    )
                    .padding(.top, 60)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Performance Stats")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var passportHero: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    Color.black,
                    ATHLTHTheme.accent.opacity(0.78),
                    Color.black.opacity(0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            ATHLTHMarkShape()
                .fill(.white.opacity(0.08))
                .frame(width: 190, height: 140)
                .rotationEffect(.degrees(-10))
                .offset(x: 170, y: -28)

            VStack(alignment: .leading, spacing: 6) {
                Text("ATHLTH")
                    .font(.system(size: 14, weight: .black))
                    .tracking(4)
                    .foregroundStyle(.white.opacity(0.72))

                Text("Performance Passport")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)

                Label(
                    "Verified performance from your training history",
                    systemImage: "checkmark.seal.fill"
                )
                .font(.caption)
                .foregroundStyle(.white.opacity(0.76))
            }
            .padding(20)
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func runningSection(_ stats: ProfilePerformanceStats) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionHeader(
                title: "Running PRs",
                subtitle: "Fastest actual route segments"
            )

            statRow(
                icon: "1.circle.fill",
                title: "Fastest 1K",
                value: stats.fastestOneKilometer?.formattedTime ?? "—",
                detail: timedRecordDetail(stats.fastestOneKilometer)
            )

            Divider().opacity(0.5)

            statRow(
                icon: "5.circle.fill",
                title: "Fastest 5K",
                value: stats.fastestFiveKilometers?.formattedTime ?? "—",
                detail: timedRecordDetail(stats.fastestFiveKilometers)
            )

            Divider().opacity(0.5)

            statRow(
                icon: "flag.checkered",
                title: "Fastest Marathon",
                value: stats.fastestMarathon?.formattedTime ?? "—",
                detail: timedRecordDetail(stats.fastestMarathon)
            )

            Divider().opacity(0.5)

            statRow(
                icon: "point.topleft.down.to.point.bottomright.curvepath",
                title: "Longest Run",
                value: formatDistance(stats.longestRunMeters),
                detail: dateAndMil(
                    date: stats.longestRunDate,
                    meters: stats.longestRunMeters
                )
            )
        }
        .padding()
        .performanceCard()
    }

    private func volumeSection(_ stats: ProfilePerformanceStats) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionHeader(
                title: "Training Volume",
                subtitle: "All-time totals from Apple Health"
            )

            statRow(
                icon: "clock.fill",
                title: "Longest Workout",
                value: formatDuration(stats.longestWorkoutDuration),
                detail: activityAndDate(
                    activity: stats.longestWorkoutActivity,
                    date: stats.longestWorkoutDate
                )
            )

            Divider().opacity(0.5)

            statRow(
                icon: stats.longestWorkoutDistanceActivity?.icon ?? "location.fill",
                title: "Longest Distance Workout",
                value: formatDistance(stats.longestWorkoutDistanceMeters),
                detail: activityDateAndMil(
                    activity: stats.longestWorkoutDistanceActivity,
                    date: stats.longestWorkoutDistanceDate,
                    meters: stats.longestWorkoutDistanceMeters
                )
            )

            Divider().opacity(0.5)

            statRow(
                icon: "checkmark.circle.fill",
                title: "Total Workouts",
                value: stats.totalWorkoutCount.formatted(),
                detail: "All recorded workout types"
            )

            Divider().opacity(0.5)

            statRow(
                icon: "timer",
                title: "Total Training Time",
                value: formatLongDuration(stats.totalTrainingDuration),
                detail: "All recorded workouts"
            )

            Divider().opacity(0.5)

            statRow(
                icon: "figure.run",
                title: "Total Running Distance",
                value: formatDistance(stats.totalRunningDistanceMeters),
                detail: formatMil(stats.totalRunningDistanceMeters)
            )
        }
        .padding()
        .performanceCard()
    }

    private var verificationSection: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title3)
                .foregroundStyle(ATHLTHTheme.accent)

            VStack(alignment: .leading, spacing: 4) {
                Text("Verified Stats")
                    .font(.headline)

                Text("Fastest 1K, 5K and marathon require a recorded GPS route. ATHLTH does not estimate a segment time from the average pace of the full workout.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .performanceCard()
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title3.bold())
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func statRow(
        icon: String,
        title: String,
        value: String,
        detail: String
    ) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.accent)
                .frame(width: 38, height: 38)
                .background(
                    ATHLTHTheme.accent.opacity(0.09),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Text(value)
                .font(.title3.monospacedDigit().weight(.bold))
                .multilineTextAlignment(.trailing)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
    }

    private func timedRecordDetail(_ record: TimedDistancePerformanceRecord?) -> String {
        guard let record else {
            return "No GPS-verified result yet"
        }

        return "\(record.formattedPace) · \(record.date.formatted(date: .abbreviated, time: .omitted))"
    }

    private func activityAndDate(
        activity: WorkoutActivity?,
        date: Date?
    ) -> String {
        let activityName = activity?.rawValue ?? "Workout"
        guard let date else { return activityName }
        return "\(activityName) · \(date.formatted(date: .abbreviated, time: .omitted))"
    }

    private func dateAndMil(date: Date?, meters: Double?) -> String {
        let mil = formatMil(meters)

        if let date {
            return "\(mil) · \(date.formatted(date: .abbreviated, time: .omitted))"
        }

        return mil
    }

    private func activityDateAndMil(
        activity: WorkoutActivity?,
        date: Date?,
        meters: Double?
    ) -> String {
        var components: [String] = []

        if let activity {
            components.append(activity.rawValue)
        }

        if meters != nil {
            components.append(formatMil(meters))
        }

        if let date {
            components.append(date.formatted(date: .abbreviated, time: .omitted))
        }

        return components.isEmpty ? "—" : components.joined(separator: " · ")
    }
}

private func formatDistance(_ meters: Double?) -> String {
    guard let meters, meters > 0 else { return "—" }

    let kilometers = meters / 1_000

    if kilometers >= 1_000 {
        return String(format: "%.0f km", kilometers)
    }

    if kilometers >= 100 {
        return String(format: "%.1f km", kilometers)
    }

    return String(format: "%.2f km", kilometers)
}

private func formatMil(_ meters: Double?) -> String {
    guard let meters, meters >= 10_000 else {
        return "Distance verified"
    }

    return String(format: "%.2f mil", meters / 10_000)
}

private func formatDuration(_ duration: TimeInterval?) -> String {
    guard let duration, duration > 0 else { return "—" }

    let totalMinutes = Int((duration / 60).rounded())
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60

    if hours > 0 {
        return "\(hours)h \(minutes)m"
    }

    return "\(minutes) min"
}

private func formatLongDuration(_ duration: TimeInterval) -> String {
    guard duration > 0 else { return "—" }

    let totalHours = duration / 3_600

    if totalHours >= 100 {
        return String(format: "%.0f h", totalHours)
    }

    return String(format: "%.1f h", totalHours)
}

private extension View {
    func performanceCard() -> some View {
        self
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            }
    }
}

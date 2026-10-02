import SwiftUI

struct ProfilePerformanceSection: View {
    let stats: ProfilePerformanceStats?
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "Performance highlights",
                            norwegian: "Prestasjonshøydepunkter"
                        )
                    )
                    .font(.title3.weight(.bold))

                    Label(
                        ATHLTHLocalization.choose(
                            english: "Verified from Apple Health",
                            norwegian: "Verifisert fra Apple Health"
                        ),
                        systemImage: "checkmark.seal.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.accent)
                }

                Spacer()

                NavigationLink {
                    PerformanceStatsView(stats: stats)
                } label: {
                    HStack(spacing: 4) {
                        Text(
                            ATHLTHLocalization.choose(
                                english: "View all",
                                norwegian: "Se alle"
                            )
                        )
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
                    Text(
                        ATHLTHLocalization.choose(
                            english: "Reading your performance…",
                            norwegian: "Leser prestasjonene dine…"
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 18)
            } else if let stats {
                HStack(spacing: 8) {
                    compactMetric(
                        icon: "figure.run.circle.fill",
                        title: ATHLTHLocalization.choose(
                            english: "Fastest 5K",
                            norwegian: "Raskeste 5 km"
                        ),
                        value:
                            stats.fastestFiveKilometers?
                                .formattedTime ?? "—",
                        tint: .green
                    )

                    compactMetric(
                        icon:
                            "point.topleft.down.to.point.bottomright.curvepath",
                        title: ATHLTHLocalization.choose(
                            english: "Longest run",
                            norwegian: "Lengste løpetur"
                        ),
                        value: formatDistance(
                            stats.longestRunMeters
                        ),
                        tint: .orange
                    )

                    compactMetric(
                        icon: "checkmark.circle.fill",
                        title: ATHLTHLocalization.choose(
                            english: "Workouts",
                            norwegian: "Økter"
                        ),
                        value: stats.totalWorkoutCount.formatted(),
                        tint: ATHLTHTheme.accent
                    )
                }
                .padding(.top, 12)
            } else {
                Text(
                    ATHLTHLocalization.choose(
                        english: "Connect Apple Health to build verified performance highlights.",
                        norwegian: "Koble til Apple Health for å bygge verifiserte prestasjonshøydepunkter."
                    )
                )
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .padding(.vertical, 12)
            }
        }
        .padding(18)
        .background(
            Color.white.opacity(0.82),
            in: RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
            .stroke(
                ATHLTHTheme.border.opacity(0.72),
                lineWidth: 1
            )
        }
        .shadow(
            color: .black.opacity(0.035),
            radius: 16,
            x: 0,
            y: 8
        )
    }

    private func compactMetric(
        icon: String,
        title: String,
        value: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(
                    tint.opacity(0.10),
                    in: Circle()
                )

            Text(value)
                .font(
                    .subheadline
                        .monospacedDigit()
                        .weight(.bold)
                )
                .foregroundStyle(ATHLTHTheme.primaryText)
                .minimumScaleFactor(0.64)
                .lineLimit(1)

            Text(title)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.mutedText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(10)
        .frame(
            maxWidth: .infinity,
            minHeight: 92,
            alignment: .leading
        )
        .background(
            LinearGradient(
                colors: [
                    tint.opacity(0.07),
                    Color.white.opacity(0.72)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
            .stroke(
                tint.opacity(0.09),
                lineWidth: 1
            )
        }
    }
}

struct PerformanceStatsView: View {
    let stats: ProfilePerformanceStats?
    var healthRecords: [HealthPersonalRecord] = []

    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strengthWorkout: StrengthWorkoutStore
    @State private var fetchedHealthRecords: [HealthPersonalRecord] = []

    private let gridColumns = [
        GridItem(
            .adaptive(minimum: 168, maximum: 320),
            spacing: 12,
            alignment: .top
        )
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                passportHero
                privacyCard

                if stats != nil ||
                    !resolvedHealthRecords.isEmpty ||
                    !strengthWorkout.workoutHistory.isEmpty ||
                    health.hasTrainingHealthData {
                    LazyVGrid(
                        columns: gridColumns,
                        alignment: .leading,
                        spacing: 12
                    ) {
                        metricSection(
                            title: text("Running PRs", "Løpe-PRer"),
                            subtitle: text(
                                "GPS-verified personal records",
                                "GPS-verifiserte personlige rekorder"
                            ),
                            icon: "figure.run",
                            accent: .blue,
                            items: runningItems
                        )

                        metricSection(
                            title: text("Training volume", "Treningsvolum"),
                            subtitle: text(
                                "Your complete training history",
                                "Hele treningshistorikken din"
                            ),
                            icon: "chart.bar.fill",
                            accent: ATHLTHTheme.accentDeep,
                            items: volumeItems
                        )

                        metricSection(
                            title: text("Strength", "Styrke"),
                            subtitle: text(
                                "Records tracked in ATHLTH",
                                "Rekorder sporet i ATHLTH"
                            ),
                            icon: "dumbbell.fill",
                            accent: ATHLTHTheme.premiumGold,
                            items: strengthItems
                        )

                        metricSection(
                            title: text(
                                "Health & recovery",
                                "Helse og restitusjon"
                            ),
                            subtitle: text(
                                "Private Health signals",
                                "Private helsesignaler"
                            ),
                            icon: "heart.fill",
                            accent: .red,
                            items: recoveryItems
                        )

                        metricSection(
                            title: text(
                                "More records",
                                "Flere prestasjoner"
                            ),
                            subtitle: text(
                                "Other activities and peaks",
                                "Andre aktiviteter og høydepunkter"
                            ),
                            icon: "sparkles",
                            accent: .purple,
                            items: otherItems
                        )

                        verificationCard
                    }
                } else {
                    ContentUnavailableView(
                        text("No performance data", "Ingen prestasjonsdata"),
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text(
                            text(
                                "Connect Apple Health or complete workouts in ATHLTH to start building your Performance Passport.",
                                "Koble til Apple Health eller fullfør økter i ATHLTH for å begynne å bygge Prestasjonspasset ditt."
                            )
                        )
                    )
                    .padding(.top, 44)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 120)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .background(
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
        )
        .navigationTitle(
            text("Performance Statistics", "Prestasjonsstatistikk")
        )
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard healthRecords.isEmpty,
                  fetchedHealthRecords.isEmpty,
                  health.hasRequestedAuthorization
            else {
                return
            }

            fetchedHealthRecords =
                (try? await health.personalRecords()) ?? []
        }
    }

    private var passportHero: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                Image("ProgressHero")
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFill()
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height
                    )
                    .clipped()
                    .accessibilityHidden(true)

                LinearGradient(
                    stops: [
                        .init(
                            color: .black.opacity(0.28),
                            location: 0
                        ),
                        .init(
                            color: .black.opacity(0.38),
                            location: 0.46
                        ),
                        .init(
                            color: .black.opacity(0.86),
                            location: 1
                        )
                    ],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )

                Path { path in
                    let w = proxy.size.width
                    let h = proxy.size.height

                    path.move(
                        to: CGPoint(
                            x: w * 0.42,
                            y: h * 0.76
                        )
                    )
                    path.addCurve(
                        to: CGPoint(
                            x: w * 0.98,
                            y: h * 0.34
                        ),
                        control1: CGPoint(
                            x: w * 0.60,
                            y: h * 0.79
                        ),
                        control2: CGPoint(
                            x: w * 0.78,
                            y: h * 0.38
                        )
                    )
                }
                .stroke(
                    ATHLTHTheme.premiumGold.opacity(0.72),
                    style: StrokeStyle(
                        lineWidth: 1.6,
                        lineCap: .round
                    )
                )
                .shadow(
                    color: ATHLTHTheme.premiumGold.opacity(0.45),
                    radius: 7
                )
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 7) {
                    Text("ATHLTH")
                        .font(.system(size: 13, weight: .black))
                        .tracking(4)
                        .foregroundStyle(.white.opacity(0.82))

                    Text(
                        text(
                            "Performance Passport",
                            "Prestasjonspass"
                        )
                    )
                    .font(
                        .system(
                            size: 31,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)

                    Text(
                        text(
                            "Your personal performance, built from your training history.",
                            "Dine personlige prestasjoner, bygget fra treningshistorikken din."
                        )
                    )
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
        }
        .frame(height: 220)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.12),
                lineWidth: 0.8
            )
        }
        .shadow(
            color: .black.opacity(0.12),
            radius: 18,
            y: 8
        )
    }

    private var privacyCard: some View {
        NavigationLink {
            ATHLTHPrivacyCenterView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(
                        ATHLTHTheme.premiumGold
                    )
                    .frame(width: 40, height: 40)
                    .background(
                        ATHLTHTheme.premiumGold.opacity(0.10),
                        in: Circle()
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        text(
                            "Personal by default",
                            "Personlig som standard"
                        )
                    )
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ATHLTHTheme.primaryText)

                    Text(
                        text(
                            "Choose which results, if any, others can see.",
                            "Velg hvilke resultater andre eventuelt kan se."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .lineLimit(2)
                }

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    Text(
                        text(
                            "Choose",
                            "Velg"
                        )
                    )
                    Image(systemName: "chevron.right")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
            }
            .padding(14)
            .background(
                LinearGradient(
                    colors: [
                        ATHLTHTheme.premiumGold.opacity(0.08),
                        Color(.secondarySystemGroupedBackground)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
                .stroke(
                    ATHLTHTheme.premiumGold.opacity(0.12),
                    lineWidth: 1
                )
            }
        }
        .buttonStyle(.plain)
    }

    private func metricSection(
        title: String,
        subtitle: String,
        icon: String,
        accent: Color,
        items: [PerformanceMetricItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(width: 36, height: 36)
                    .background(
                        accent.opacity(0.10),
                        in: RoundedRectangle(
                            cornerRadius: 11,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(ATHLTHTheme.primaryText)

                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }

            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Divider()
                        .opacity(0.5)
                }

                metricRow(item)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .stroke(
                Color.primary.opacity(0.05),
                lineWidth: 1
            )
        }
        .shadow(
            color: .black.opacity(0.035),
            radius: 12,
            y: 6
        )
    }

    private func metricRow(
        _ item: PerformanceMetricItem
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(item.tint)
                .frame(width: 34, height: 34)
                .background(
                    item.tint.opacity(0.09),
                    in: RoundedRectangle(
                        cornerRadius: 10,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .lineLimit(2)

                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 6)

            Text(item.value)
                .font(
                    .subheadline
                        .monospacedDigit()
                        .weight(.bold)
                )
                .foregroundStyle(ATHLTHTheme.primaryText)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.66)
        }
    }

    private var verificationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(ATHLTHTheme.premiumGold)
                    .frame(width: 36, height: 36)
                    .background(
                        ATHLTHTheme.premiumGold.opacity(0.10),
                        in: RoundedRectangle(
                            cornerRadius: 11,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        text(
                            "Verified results",
                            "Verifiserte resultater"
                        )
                    )
                    .font(.headline.weight(.bold))

                    Text(
                        text(
                            "ATHLTH uses recorded data instead of estimating a result that was not measured.",
                            "ATHLTH bruker registrerte data i stedet for å estimere et resultat som ikke er målt."
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }

            Text(
                text(
                    "Running segment records require a recorded GPS route. Strength records are based on completed sets saved in ATHLTH.",
                    "Løpesegmentrekorder krever registrert GPS-rute. Styrkerekorder bygger på fullførte sett lagret i ATHLTH."
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    ATHLTHTheme.premiumGold.opacity(0.08),
                    Color(.secondarySystemGroupedBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .stroke(
                ATHLTHTheme.premiumGold.opacity(0.12),
                lineWidth: 1
            )
        }
    }

    private var resolvedHealthRecords:
        [HealthPersonalRecord] {
        healthRecords.isEmpty
            ? fetchedHealthRecords
            : healthRecords
    }

    private var runningItems: [PerformanceMetricItem] {
        [
            runningRecordItem(
                kind: .fastest1K,
                title: text("Fastest 1K", "Raskeste 1 km"),
                icon: "1.circle.fill",
                tint: .blue,
                fallback: stats?.fastestOneKilometer
            ),
            runningRecordItem(
                kind: .fastestMile,
                title: text("Fastest mile", "Raskeste mile"),
                icon: "m.circle.fill",
                tint: .cyan
            ),
            runningRecordItem(
                kind: .fastest5K,
                title: text("Fastest 5K", "Raskeste 5 km"),
                icon: "5.circle.fill",
                tint: .green,
                fallback: stats?.fastestFiveKilometers
            ),
            runningRecordItem(
                kind: .fastest10K,
                title: text("Fastest 10K", "Raskeste 10 km"),
                icon: "10.circle.fill",
                tint: .orange
            ),
            runningRecordItem(
                kind: .fastestHalfMarathon,
                title: text("Half marathon", "Halvmaraton"),
                icon: "mountain.2.fill",
                tint: .indigo
            ),
            runningRecordItem(
                kind: .fastestMarathon,
                title: text("Marathon", "Maraton"),
                icon: "flag.checkered",
                tint: ATHLTHTheme.premiumGold,
                fallback: stats?.fastestMarathon
            ),
            longestRunItem
        ]
    }

    private var volumeItems: [PerformanceMetricItem] {
        guard let stats else {
            return [
                emptyItem(
                    icon: "clock.fill",
                    title: text("Longest workout", "Lengste økt")
                ),
                emptyItem(
                    icon: "point.topleft.down.to.point.bottomright.curvepath",
                    title: text(
                        "Longest distance workout",
                        "Lengste distanseøkt"
                    )
                ),
                emptyItem(
                    icon: "checkmark.circle.fill",
                    title: text("Total workouts", "Totalt antall økter")
                ),
                emptyItem(
                    icon: "timer",
                    title: text("Total training time", "Total treningstid")
                ),
                emptyItem(
                    icon: "figure.run",
                    title: text(
                        "Running distance",
                        "Total løpsdistanse"
                    )
                )
            ]
        }

        return [
            PerformanceMetricItem(
                icon: "clock.fill",
                title: text("Longest workout", "Lengste økt"),
                value: formatDuration(stats.longestWorkoutDuration),
                detail: activityAndDate(
                    activity: stats.longestWorkoutActivity,
                    date: stats.longestWorkoutDate
                ),
                tint: .indigo
            ),
            PerformanceMetricItem(
                icon:
                    stats.longestWorkoutDistanceActivity?.icon ??
                    "location.fill",
                title: text(
                    "Longest distance workout",
                    "Lengste distanseøkt"
                ),
                value: formatDistance(
                    stats.longestWorkoutDistanceMeters
                ),
                detail: activityDateAndMil(
                    activity:
                        stats.longestWorkoutDistanceActivity,
                    date:
                        stats.longestWorkoutDistanceDate,
                    meters:
                        stats.longestWorkoutDistanceMeters
                ),
                tint: .blue
            ),
            PerformanceMetricItem(
                icon: "checkmark.circle.fill",
                title: text(
                    "Total workouts",
                    "Totalt antall økter"
                ),
                value: stats.totalWorkoutCount.formatted(),
                detail: text(
                    "All recorded workout types",
                    "Alle registrerte økttyper"
                ),
                tint: .green
            ),
            PerformanceMetricItem(
                icon: "timer",
                title: text(
                    "Total training time",
                    "Total treningstid"
                ),
                value: formatLongDuration(
                    stats.totalTrainingDuration
                ),
                detail: text(
                    "All recorded workouts",
                    "Alle registrerte økter"
                ),
                tint: .orange
            ),
            PerformanceMetricItem(
                icon: "figure.run",
                title: text(
                    "Running distance",
                    "Total løpsdistanse"
                ),
                value: formatDistance(
                    stats.totalRunningDistanceMeters
                ),
                detail: formatMil(
                    stats.totalRunningDistanceMeters
                ),
                tint: .blue
            )
        ]
    }

    private var strengthItems: [PerformanceMetricItem] {
        let records = strengthWorkout.personalRecords
        let heaviest =
            records
                .filter { $0.kind == .heaviestSet }
                .max { $0.score < $1.score }
        let estimatedOneRM =
            records.first {
                $0.kind == .estimatedOneRepMax
            }
        let workoutVolumeRecord =
            records.first {
                $0.kind == .workoutVolume
            }
        let completed =
            strengthWorkout.workoutHistory
                .filter(\.isFinished)
        let lifetimeVolume =
            completed.reduce(0.0) {
                $0 + max($1.totalVolumeKilograms, 0)
            }
        let bestRep =
            strengthWorkout.repPersonalRecords.max {
                if $0.weightKilograms ==
                    $1.weightKilograms {
                    return $0.reps < $1.reps
                }
                return $0.weightKilograms <
                    $1.weightKilograms
            }

        return [
            PerformanceMetricItem(
                icon: "trophy.fill",
                title: text("Heaviest set", "Tyngste sett"),
                value: heaviest?.value ?? "—",
                detail:
                    heaviest.map {
                        "\($0.title) · \(formatDate($0.date))"
                    } ??
                    text(
                        "No weighted record yet",
                        "Ingen vektet rekord ennå"
                    ),
                tint: ATHLTHTheme.premiumGold
            ),
            PerformanceMetricItem(
                icon: "bolt.fill",
                title: text(
                    "Estimated 1RM",
                    "Estimert 1RM"
                ),
                value: estimatedOneRM?.value ?? "—",
                detail:
                    estimatedOneRM.map {
                        "\($0.title) · \(formatDate($0.date))"
                    } ??
                    text(
                        "Built from completed sets",
                        "Bygges fra fullførte sett"
                    ),
                tint: .orange
            ),
            PerformanceMetricItem(
                icon: "chart.bar.fill",
                title: text(
                    "Best workout volume",
                    "Høyeste øktvolum"
                ),
                value: workoutVolumeRecord?.value ?? "—",
                detail:
                    workoutVolumeRecord.map {
                        formatDate($0.date)
                    } ??
                    text(
                        "No volume record yet",
                        "Ingen volumrekord ennå"
                    ),
                tint: .blue
            ),
            PerformanceMetricItem(
                icon: "repeat",
                title: text("Best rep PR", "Beste repetisjons-PR"),
                value: bestRep?.value ?? "—",
                detail:
                    bestRep.map {
                        "\($0.exerciseName) · \(formatDate($0.date))"
                    } ??
                    text(
                        "No rep PR yet",
                        "Ingen repetisjons-PR ennå"
                    ),
                tint: .purple
            ),
            PerformanceMetricItem(
                icon: "list.number",
                title: text(
                    "Strength workouts",
                    "Styrkeøkter"
                ),
                value: completed.count.formatted(),
                detail: text(
                    "Completed in ATHLTH",
                    "Fullført i ATHLTH"
                ),
                tint: .green
            ),
            PerformanceMetricItem(
                icon: "scalemass.fill",
                title: text(
                    "Lifetime volume",
                    "Totalt styrkevolum"
                ),
                value: formatKilograms(lifetimeVolume),
                detail: text(
                    "Working-set volume",
                    "Volum fra arbeidssett"
                ),
                tint: ATHLTHTheme.accentDeep
            )
        ]
    }

    private var recoveryItems: [PerformanceMetricItem] {
        let sleepValue =
            health.sleep.totalAsleep > 0
                ? formatDuration(health.sleep.totalAsleep)
                : "—"
        let sleepDetail: String
        if let end = health.sleep.sleepEnd {
            sleepDetail =
                text("Last sleep · ", "Siste søvn · ") +
                formatDate(end)
        } else {
            sleepDetail =
                text(
                    "No recent sleep data",
                    "Ingen nyere søvndata"
                )
        }

        return [
            PerformanceMetricItem(
                icon: "moon.fill",
                title: text("Last sleep", "Siste søvn"),
                value: sleepValue,
                detail: sleepDetail,
                tint: .indigo
            ),
            PerformanceMetricItem(
                icon: "waveform.path.ecg",
                title: "HRV",
                value:
                    health.heart.hrvMilliseconds.map {
                        "\(Int($0.rounded())) ms"
                    } ?? "—",
                detail:
                    health.heart.hrvDate.map {
                        formatDate($0)
                    } ??
                    text(
                        "No recent HRV",
                        "Ingen nyere HRV"
                    ),
                tint: .blue
            ),
            PerformanceMetricItem(
                icon: "heart.fill",
                title: text(
                    "Resting heart rate",
                    "Hvilepuls"
                ),
                value:
                    health.heart.restingHeartRate.map {
                        "\(Int($0.rounded())) bpm"
                    } ?? "—",
                detail:
                    health.heart.restingHeartRateDate.map {
                        formatDate($0)
                    } ??
                    text(
                        "No recent resting HR",
                        "Ingen nyere hvilepuls"
                    ),
                tint: .red
            ),
            PerformanceMetricItem(
                icon: "leaf.fill",
                title: text(
                    "Recovery score",
                    "Restitusjonsscore"
                ),
                value:
                    health.recovery.score.map {
                        "\($0)"
                    } ?? "—",
                detail:
                    health.recovery.score == nil
                        ? text(
                            "Building your baseline",
                            "Bygger grunnlaget ditt"
                        )
                        : health.recovery.detail,
                tint: .green
            )
        ]
    }

    private var otherItems: [PerformanceMetricItem] {
        [
            healthRecordItem(
                kind: .longestRide,
                title: text(
                    "Longest ride",
                    "Lengste sykkeltur"
                ),
                icon: "figure.outdoor.cycle",
                tint: .green
            ),
            healthRecordItem(
                kind: .longestWalkOrHike,
                title: text(
                    "Longest walk / hike",
                    "Lengste gåtur / fjelltur"
                ),
                icon: "figure.hiking",
                tint: .brown
            ),
            healthRecordItem(
                kind: .mostActiveCalories,
                title: text(
                    "Most active calories",
                    "Flest aktive kalorier"
                ),
                icon: "flame.fill",
                tint: .orange
            ),
            healthRecordItem(
                kind: .longestWorkout,
                title: text(
                    "Longest workout",
                    "Lengste økt"
                ),
                icon: "clock.fill",
                tint: .indigo
            )
        ]
    }

    private var longestRunItem: PerformanceMetricItem {
        if let record = record(.longestRun) {
            return PerformanceMetricItem(
                icon:
                    "point.topleft.down.to.point.bottomright.curvepath",
                title: text(
                    "Longest run",
                    "Lengste løpetur"
                ),
                value: record.formattedValue,
                detail: formatDate(record.date),
                tint: .purple
            )
        }

        return PerformanceMetricItem(
            icon:
                "point.topleft.down.to.point.bottomright.curvepath",
            title: text(
                "Longest run",
                "Lengste løpetur"
            ),
            value:
                formatDistance(
                    stats?.longestRunMeters
                ),
            detail:
                stats?.longestRunDate.map {
                    formatDate($0)
                } ??
                text(
                    "No run recorded yet",
                    "Ingen løpetur registrert ennå"
                ),
            tint: .purple
        )
    }

    private func runningRecordItem(
        kind: HealthPersonalRecordKind,
        title: String,
        icon: String,
        tint: Color,
        fallback: TimedDistancePerformanceRecord? = nil
    ) -> PerformanceMetricItem {
        if let record = record(kind) {
            return PerformanceMetricItem(
                icon: icon,
                title: title,
                value: record.formattedValue,
                detail: runningRecordDetail(record),
                tint: tint
            )
        }

        if let fallback {
            return PerformanceMetricItem(
                icon: icon,
                title: title,
                value: fallback.formattedTime,
                detail:
                    "\(fallback.formattedPace) · " +
                    formatDate(fallback.date),
                tint: tint
            )
        }

        return emptyItem(
            icon: icon,
            title: title,
            tint: tint,
            detail: text(
                "No GPS-verified result yet",
                "Ingen GPS-verifisert rekord ennå"
            )
        )
    }

    private func healthRecordItem(
        kind: HealthPersonalRecordKind,
        title: String,
        icon: String,
        tint: Color
    ) -> PerformanceMetricItem {
        guard let record = record(kind) else {
            return emptyItem(
                icon: icon,
                title: title,
                tint: tint
            )
        }

        return PerformanceMetricItem(
            icon: icon,
            title: title,
            value: record.formattedValue,
            detail: formatDate(record.date),
            tint: tint
        )
    }

    private func emptyItem(
        icon: String,
        title: String,
        tint: Color = ATHLTHTheme.accentDeep,
        detail: String? = nil
    ) -> PerformanceMetricItem {
        PerformanceMetricItem(
            icon: icon,
            title: title,
            value: "—",
            detail:
                detail ??
                text(
                    "No recorded result yet",
                    "Ingen registrert verdi ennå"
                ),
            tint: tint
        )
    }

    private func record(
        _ kind: HealthPersonalRecordKind
    ) -> HealthPersonalRecord? {
        resolvedHealthRecords.first {
            $0.kind == kind
        }
    }

    private func runningRecordDetail(
        _ record: HealthPersonalRecord
    ) -> String {
        guard let distance =
                record.kind.targetDistanceMeters,
              distance > 0
        else {
            return formatDate(record.date)
        }

        let pace =
            record.value /
            (distance / 1_000)

        return
            "\(formatPace(pace)) · " +
            formatDate(record.date)
    }

    private func text(
        _ english: String,
        _ norwegian: String
    ) -> String {
        ATHLTHLocalization.choose(
            english: english,
            norwegian: norwegian
        )
    }

    private func formatDate(
        _ date: Date
    ) -> String {
        date.formatted(
            date: .abbreviated,
            time: .omitted
        )
    }

    private func activityAndDate(
        activity: WorkoutActivity?,
        date: Date?
    ) -> String {
        let activityName =
            activity?.rawValue ??
            text("Workout", "Trening")

        guard let date else {
            return activityName
        }

        return
            "\(activityName) · " +
            formatDate(date)
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
            components.append(formatDate(date))
        }

        return components.isEmpty
            ? "—"
            : components.joined(separator: " · ")
    }

    private func formatPace(
        _ secondsPerKilometer: TimeInterval
    ) -> String {
        guard secondsPerKilometer.isFinite,
              secondsPerKilometer > 0
        else {
            return "—"
        }

        let total = Int(secondsPerKilometer.rounded())
        return String(
            format:
                "%d:%02d /km",
            total / 60,
            total % 60
        )
    }

    private func formatKilograms(
        _ kilograms: Double
    ) -> String {
        guard kilograms > 0 else {
            return "—"
        }

        if kilograms >= 1_000_000 {
            return String(
                format:
                    "%.2fM kg",
                kilograms / 1_000_000
            )
        }

        if kilograms >= 10_000 {
            return String(
                format:
                    "%.0f kg",
                kilograms
            )
        }

        return String(
            format:
                "%.1f kg",
            kilograms
        )
    }
}

private struct PerformanceMetricItem {
    let icon: String
    let title: String
    let value: String
    let detail: String
    let tint: Color
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
        return ATHLTHLocalization.choose(
            english: "Distance verified",
            norwegian: "Distanse verifisert"
        )
    }

    return String(format: "%.2f mil", meters / 10_000)
}

private func formatDuration(_ duration: TimeInterval?) -> String {
    guard let duration, duration > 0 else { return "—" }

    let totalMinutes = Int((duration / 60).rounded())
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60

    if hours > 0 {
        return ATHLTHLocalization.isNorwegian
            ? "\(hours)t \(minutes)m"
            : "\(hours)h \(minutes)m"
    }

    return "\(minutes) min"
}

private func formatLongDuration(_ duration: TimeInterval) -> String {
    guard duration > 0 else { return "—" }

    let totalMinutes = Int((duration / 60).rounded())
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60

    if hours >= 100 {
        return "\(hours) h"
    }

    if hours > 0 {
        return ATHLTHLocalization.isNorwegian
            ? "\(hours)t \(minutes)m"
            : "\(hours)h \(minutes)m"
    }

    return "\(minutes) min"
}

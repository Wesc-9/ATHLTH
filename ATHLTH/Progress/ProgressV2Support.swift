import Charts
import SwiftUI

enum ProgressTrendMetric: String, CaseIterable, Identifiable {
    case training
    case workouts
    case distance
    case steps
    case sleep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .training: return "Training"
        case .workouts: return "Workouts"
        case .distance: return "Distance"
        case .steps: return "Steps"
        case .sleep: return "Sleep"
        }
    }

    var icon: String {
        switch self {
        case .training: return "clock.fill"
        case .workouts: return "figure.run"
        case .distance: return "point.topleft.down.to.point.bottomright.curvepath"
        case .steps: return "shoeprints.fill"
        case .sleep: return "moon.fill"
        }
    }
}

enum ProgressMetricDetailKind: String, Identifiable {
    case training
    case distance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .training: return "Training Time"
        case .distance: return "Distance"
        }
    }

    var icon: String {
        switch self {
        case .training: return "clock.fill"
        case .distance: return "point.topleft.down.to.point.bottomright.curvepath"
        }
    }
}

struct ProgressTrendCard: View {
    let snapshot: HealthProgressSnapshot
    @Binding var metric: ProgressTrendMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Performance Trends")
                        .font(.title3.weight(.bold))

                    Text("Longer-term development belongs here, not in Recovery.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(currentValue)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ATHLTHTheme.accent)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    ForEach(ProgressTrendMetric.allCases) { option in
                        Button {
                            metric = option
                        } label: {
                            Label(option.title, systemImage: option.icon)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(
                                    metric == option
                                        ? Color.white
                                        : ATHLTHTheme.primaryText
                                )
                                .padding(.horizontal, 11)
                                .frame(height: 34)
                                .background(
                                    metric == option
                                        ? ATHLTHTheme.accent
                                        : Color.primary.opacity(0.045),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)

            if snapshot.buckets.isEmpty {
                ContentUnavailableView(
                    "Not enough data",
                    systemImage: metric.icon
                )
                .frame(height: 180)
            } else {
                Chart(snapshot.buckets) { bucket in
                    AreaMark(
                        x: .value("Date", bucket.startDate),
                        y: .value("Value", value(for: bucket))
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                ATHLTHTheme.accent.opacity(0.18),
                                ATHLTHTheme.accent.opacity(0.015)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Date", bucket.startDate),
                        y: .value("Value", value(for: bucket))
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(ATHLTHTheme.accent)
                    .lineStyle(
                        StrokeStyle(
                            lineWidth: 2.5,
                            lineCap: .round
                        )
                    )

                    PointMark(
                        x: .value("Date", bucket.startDate),
                        y: .value("Value", value(for: bucket))
                    )
                    .foregroundStyle(ATHLTHTheme.accent)
                    .symbolSize(22)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) {
                        AxisGridLine()
                            .foregroundStyle(
                                Color.black.opacity(0.04)
                            )
                        AxisValueLabel()
                            .font(.system(size: 9))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) {
                        AxisValueLabel(
                            format: .dateTime
                                .month(.abbreviated)
                                .day()
                        )
                        .font(.system(size: 8))
                    }
                }
                .frame(height: 190)
            }

            HStack {
                Label(
                    comparisonText,
                    systemImage:
                        comparisonChange.map {
                            $0 >= 0 ? "arrow.up.right" : "arrow.down.right"
                        } ?? "minus"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    comparisonChange.map {
                        $0 >= 0
                            ? ATHLTHTheme.accent
                            : Color.orange
                    } ?? .secondary
                )

                Spacer()

                Text("vs previous period")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .progressReferenceCard()
    }

    private func value(
        for bucket: HealthProgressBucket
    ) -> Double {
        switch metric {
        case .training:
            return bucket.trainingDuration / 3_600
        case .workouts:
            return Double(bucket.workoutCount)
        case .distance:
            return bucket.workoutDistanceMeters / 1_000
        case .steps:
            return bucket.averageDailySteps ?? 0
        case .sleep:
            return (bucket.averageSleepDuration ?? 0) / 3_600
        }
    }

    private var currentValue: String {
        switch metric {
        case .training:
            return snapshot.trainingDuration.shortDuration
        case .workouts:
            return "\(snapshot.workoutCount)"
        case .distance:
            return String(
                format: "%.1f km",
                snapshot.workoutDistanceMeters / 1_000
            )
        case .steps:
            return snapshot.averageDailySteps.map {
                Int($0.rounded()).formatted()
            } ?? "—"
        case .sleep:
            return snapshot.averageSleepDuration?
                .shortDuration ?? "—"
        }
    }

    private var comparisonChange: Double? {
        switch metric {
        case .training:
            return snapshot.trainingDurationChangePercent
        case .workouts:
            return snapshot.workoutChangePercent
        case .distance:
            return snapshot.workoutDistanceChangePercent
        case .steps:
            return snapshot.stepsChangePercent
        case .sleep:
            return snapshot.sleepChangePercent
        }
    }

    private var comparisonText: String {
        guard let change = comparisonChange else {
            return "No comparison yet"
        }

        return "\(Int(abs(change).rounded()))% " +
            (change >= 0 ? "higher" : "lower")
    }
}

struct ProgressMetricDetailView: View {
    let kind: ProgressMetricDetailKind
    let snapshot: HealthProgressSnapshot
    let periodLabel: String

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                hero
                chart
                summary
            }
            .padding()
        }
        .background(
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
        )
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(kind.title, systemImage: kind.icon)
                .font(.headline)
                .foregroundStyle(ATHLTHTheme.accent)

            Text(valueText)
                .font(
                    .system(
                        size: 42,
                        weight: .bold,
                        design: .rounded
                    )
                )

            Text(periodLabel)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let change = changePercent {
                Label(
                    "\(Int(abs(change).rounded()))% " +
                    (change >= 0 ? "above" : "below") +
                    " the previous period",
                    systemImage:
                        change >= 0
                            ? "arrow.up.right"
                            : "arrow.down.right"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(
                    change >= 0
                        ? ATHLTHTheme.accent
                        : Color.orange
                )
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .progressReferenceCard()
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Period development")
                .font(.headline)

            Chart(snapshot.buckets) { bucket in
                BarMark(
                    x: .value("Date", bucket.startDate),
                    y: .value("Value", value(for: bucket))
                )
                .foregroundStyle(
                    ATHLTHTheme.accent.gradient
                )
                .cornerRadius(5)
            }
            .chartYAxis {
                AxisMarks(position: .leading) {
                    AxisGridLine()
                        .foregroundStyle(
                            Color.black.opacity(0.045)
                        )
                    AxisValueLabel()
                        .font(.system(size: 9))
                }
            }
            .frame(height: 230)
        }
        .padding(18)
        .progressReferenceCard()
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What this tells you")
                .font(.headline)

            Text(detailText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .progressReferenceCard()
    }

    private func value(
        for bucket: HealthProgressBucket
    ) -> Double {
        switch kind {
        case .training:
            return bucket.trainingDuration / 3_600
        case .distance:
            return bucket.workoutDistanceMeters / 1_000
        }
    }

    private var valueText: String {
        switch kind {
        case .training:
            return snapshot.trainingDuration.shortDuration
        case .distance:
            return String(
                format: "%.1f km",
                snapshot.workoutDistanceMeters / 1_000
            )
        }
    }

    private var changePercent: Double? {
        switch kind {
        case .training:
            return snapshot.trainingDurationChangePercent
        case .distance:
            return snapshot.workoutDistanceChangePercent
        }
    }

    private var detailText: String {
        switch kind {
        case .training:
            return "Training time shows your total recorded workout duration in the selected period. Use it together with consistency and performance rather than treating more time as automatically better."
        case .distance:
            return "Distance combines distance-bearing workouts recorded in Apple Health, such as running, walking and cycling. Strength sessions normally contribute no distance."
        }
    }
}

struct ProgressConsistencyCard: View {
    let snapshot: HealthProgressSnapshot?

    var body: some View {
        NavigationLink {
            ProgressConsistencyDetailView(
                snapshot: snapshot
            )
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Consistency")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(
                                ATHLTHTheme.primaryText
                            )

                        Text("Your training rhythm over recent weeks.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(activeDaysLast30)")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(
                                ATHLTHTheme.primaryText
                            )
                        Text("active days / 30")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }

                heatmap(days: 35)

                HStack(spacing: 14) {
                    miniStat(
                        title: "Current",
                        value: "\(currentStreak) day streak"
                    )
                    miniStat(
                        title: "Best",
                        value: "\(longestStreak) day streak"
                    )
                }
            }
            .padding(18)
            .progressReferenceCard()
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func heatmap(
        days: Int
    ) -> some View {
        let dates = dateWindow(days: days)
        let active = activeDateSet

        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: 5),
                count: 7
            ),
            spacing: 5
        ) {
            ForEach(dates, id: \.self) { day in
                RoundedRectangle(
                    cornerRadius: 4,
                    style: .continuous
                )
                .fill(
                    active.contains(
                        Calendar.current.startOfDay(for: day)
                    )
                        ? ATHLTHTheme.accent
                        : Color.primary.opacity(0.055)
                )
                .frame(height: 16)
                .accessibilityLabel(
                    day.formatted(date: .abbreviated, time: .omitted)
                )
            }
        }
    }

    private func miniStat(
        title: String,
        value: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var activeDateSet: Set<Date> {
        Set(
            (snapshot?.activeWorkoutDays ?? []).map {
                Calendar.current.startOfDay(for: $0)
            }
        )
    }

    private var activeDaysLast30: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(
            byAdding: .day,
            value: -29,
            to: today
        ) ?? today

        return activeDateSet.filter {
            $0 >= start && $0 <= today
        }.count
    }

    private var currentStreak: Int {
        let calendar = Calendar.current
        let active = activeDateSet
        let today = calendar.startOfDay(for: Date())

        var cursor =
            active.contains(today)
                ? today
                : calendar.date(
                    byAdding: .day,
                    value: -1,
                    to: today
                ) ?? today
        var count = 0

        while active.contains(cursor) {
            count += 1
            guard let previous = calendar.date(
                byAdding: .day,
                value: -1,
                to: cursor
            ) else {
                break
            }
            cursor = previous
        }

        return count
    }

    private var longestStreak: Int {
        let sorted = activeDateSet.sorted()
        guard !sorted.isEmpty else { return 0 }

        let calendar = Calendar.current
        var longest = 1
        var current = 1

        for index in 1..<sorted.count {
            let previous = sorted[index - 1]
            let currentDate = sorted[index]
            let gap = calendar.dateComponents(
                [.day],
                from: previous,
                to: currentDate
            ).day ?? 0

            if gap == 1 {
                current += 1
                longest = max(longest, current)
            } else if gap > 1 {
                current = 1
            }
        }

        return longest
    }

    private func dateWindow(
        days: Int
    ) -> [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return (0..<days).compactMap { offset in
            calendar.date(
                byAdding: .day,
                value: offset - (days - 1),
                to: today
            )
        }
    }
}

struct ProgressConsistencyDetailView: View {
    let snapshot: HealthProgressSnapshot?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Training consistency")
                        .font(.title2.weight(.bold))
                    Text(
                        "A long-term view of the days where a workout was recorded."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                calendarGrid

                Text(
                    "Consistency is useful as a rhythm signal, not a target to train every day. Recovery and planned rest days still matter."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(16)
                .progressReferenceCard()
            }
            .padding()
        }
        .background(
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
        )
        .navigationTitle("Consistency")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var calendarGrid: some View {
        let dates = dateWindow(days: 91)
        let active = Set(
            (snapshot?.activeWorkoutDays ?? []).map {
                Calendar.current.startOfDay(for: $0)
            }
        )

        return VStack(alignment: .leading, spacing: 12) {
            Text("Last 13 weeks")
                .font(.headline)

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 6),
                    count: 7
                ),
                spacing: 6
            ) {
                ForEach(dates, id: \.self) { day in
                    VStack(spacing: 4) {
                        RoundedRectangle(
                            cornerRadius: 5,
                            style: .continuous
                        )
                        .fill(
                            active.contains(
                                Calendar.current.startOfDay(for: day)
                            )
                                ? ATHLTHTheme.accent
                                : Color.primary.opacity(0.055)
                        )
                        .frame(height: 24)

                        if Calendar.current.component(
                            .day,
                            from: day
                        ) == 1 {
                            Text(
                                day.formatted(
                                    .dateTime
                                        .month(.narrow)
                                )
                            )
                            .font(.system(size: 7))
                            .foregroundStyle(.secondary)
                        } else {
                            Text(" ")
                                .font(.system(size: 7))
                        }
                    }
                }
            }
        }
        .padding(18)
        .progressReferenceCard()
    }

    private func dateWindow(
        days: Int
    ) -> [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return (0..<days).compactMap { offset in
            calendar.date(
                byAdding: .day,
                value: offset - (days - 1),
                to: today
            )
        }
    }
}

struct ProgressPerformanceCard: View {
    let runningWorkouts: [WorkoutSummary]
    let strengthWorkouts: [StrengthWorkoutLog]
    let healthRecords: [HealthPersonalRecord]
    let strengthRecords: [StrengthPersonalRecord]
    let repRecords: [StrengthRepPersonalRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Performance")
                    .font(.title3.weight(.bold))
                Text("What is actually getting faster or stronger.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 10) {
                NavigationLink {
                    RunningProgressDetailView(
                        workouts: runningWorkouts,
                        records: healthRecords
                    )
                } label: {
                    performanceTile(
                        title: "Running",
                        icon: "figure.run",
                        primary: runningPrimary,
                        secondary: runningSecondary
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    StrengthProgressDetailView(
                        workouts: strengthWorkouts,
                        records: strengthRecords,
                        repRecords: repRecords
                    )
                } label: {
                    performanceTile(
                        title: "Strength",
                        icon: "dumbbell.fill",
                        primary: strengthPrimary,
                        secondary: strengthSecondary
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .progressReferenceCard()
    }

    private func performanceTile(
        title: String,
        icon: String,
        primary: String,
        secondary: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accent)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }

            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(ATHLTHTheme.primaryText)

            Text(primary)
                .font(.title3.weight(.bold))
                .foregroundStyle(ATHLTHTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(secondary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(
            Color.primary.opacity(0.025),
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    private var runningPrimary: String {
        let meters = runningWorkouts
            .compactMap(\.distanceMeters)
            .reduce(0, +)

        return meters > 0
            ? String(format: "%.1f km", meters / 1_000)
            : "—"
    }

    private var runningSecondary: String {
        "\(runningWorkouts.count) runs in selected period"
    }

    private var strengthPrimary: String {
        let volume = strengthWorkouts.reduce(0) {
            $0 + $1.totalVolumeKilograms
        }

        guard volume > 0 else {
            return "\(strengthWorkouts.count) sessions"
        }

        if volume >= 1_000 {
            return String(format: "%.1f t", volume / 1_000)
        }

        return "\(Int(volume.rounded())) kg"
    }

    private var strengthSecondary: String {
        strengthWorkouts.isEmpty
            ? "No ATHLTH strength sessions in this period"
            : "\(strengthWorkouts.count) ATHLTH strength sessions"
    }
}

struct RunningProgressDetailView: View {
    let workouts: [WorkoutSummary]
    let records: [HealthPersonalRecord]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    stat(
                        title: "Runs",
                        value: "\(workouts.count)"
                    )
                    stat(
                        title: "Distance",
                        value: distanceText
                    )
                }

                if let best5K = records.first(
                    where: { $0.kind == .fastest5K }
                ) {
                    recordCard(
                        title: "Fastest 5K",
                        value: best5K.formattedValue,
                        date: best5K.date
                    )
                }

                if let longest = records.first(
                    where: { $0.kind == .longestRun }
                ) {
                    recordCard(
                        title: "Longest Run",
                        value: longest.formattedValue,
                        date: longest.date
                    )
                }

                if workouts.isEmpty {
                    ContentUnavailableView(
                        "No runs in this period",
                        systemImage: "figure.run"
                    )
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Recent runs")
                            .font(.headline)

                        ForEach(workouts.prefix(10)) { workout in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(
                                        workout.startDate.formatted(
                                            date: .abbreviated,
                                            time: .omitted
                                        )
                                    )
                                    .font(.subheadline.weight(.semibold))

                                    Text(
                                        workout.duration.shortDuration
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(
                                    workout.distanceKilometers.map {
                                        String(
                                            format: "%.1f km",
                                            $0
                                        )
                                    } ?? "—"
                                )
                                .font(.subheadline.weight(.bold))
                            }
                            .padding(12)
                            .background(
                                Color.primary.opacity(0.025),
                                in: RoundedRectangle(
                                    cornerRadius: 14
                                )
                            )
                        }
                    }
                    .padding(18)
                    .progressReferenceCard()
                }
            }
            .padding()
        }
        .background(
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
        )
        .navigationTitle("Running Progress")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var distanceText: String {
        let meters = workouts
            .compactMap(\.distanceMeters)
            .reduce(0, +)

        return String(format: "%.1f km", meters / 1_000)
    }

    private func stat(
        title: String,
        value: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.title2.weight(.bold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .progressReferenceCard()
    }

    private func recordCard(
        title: String,
        value: String,
        date: Date
    ) -> some View {
        HStack {
            Image(systemName: "trophy.fill")
                .foregroundStyle(ATHLTHTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(
                    date.formatted(
                        date: .abbreviated,
                        time: .omitted
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(value)
                .font(.headline)
        }
        .padding(16)
        .progressReferenceCard()
    }
}

struct StrengthProgressDetailView: View {
    let workouts: [StrengthWorkoutLog]
    let records: [StrengthPersonalRecord]
    let repRecords: [StrengthRepPersonalRecord]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    stat(
                        title: "Sessions",
                        value: "\(workouts.count)"
                    )
                    stat(
                        title: "Volume",
                        value: volumeText
                    )
                }

                if !records.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Strength records")
                            .font(.headline)

                        ForEach(records.prefix(6)) { record in
                            HStack {
                                Image(systemName: record.kind.systemImage)
                                    .foregroundStyle(ATHLTHTheme.accent)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(record.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text(
                                        record.date.formatted(
                                            date: .abbreviated,
                                            time: .omitted
                                        )
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(record.value)
                                    .font(.subheadline.weight(.bold))
                            }
                        }
                    }
                    .padding(18)
                    .progressReferenceCard()
                }

                if !repRecords.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Rep PRs")
                            .font(.headline)

                        ForEach(repRecords.prefix(8)) { record in
                            HStack {
                                Text(record.exerciseName)
                                    .font(.subheadline)
                                Spacer()
                                Text(record.value)
                                    .font(.subheadline.weight(.bold))
                            }
                        }
                    }
                    .padding(18)
                    .progressReferenceCard()
                }
            }
            .padding()
        }
        .background(
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
        )
        .navigationTitle("Strength Progress")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var volumeText: String {
        let volume = workouts.reduce(0) {
            $0 + $1.totalVolumeKilograms
        }

        if volume >= 1_000 {
            return String(format: "%.1f t", volume / 1_000)
        }

        return "\(Int(volume.rounded())) kg"
    }

    private func stat(
        title: String,
        value: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.title2.weight(.bold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .progressReferenceCard()
    }
}

struct ProgressPersonalRecordsView: View {
    let healthRecords: [HealthPersonalRecord]
    let strengthRecords: [StrengthPersonalRecord]
    let repRecords: [StrengthRepPersonalRecord]

    var body: some View {
        List {
            if !healthRecords.isEmpty {
                Section("Endurance") {
                    ForEach(healthRecords) { record in
                        HStack {
                            Label(
                                record.kind.title,
                                systemImage: record.kind.systemImage
                            )
                            Spacer()
                            Text(record.formattedValue)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }

            if !strengthRecords.isEmpty {
                Section("Strength") {
                    ForEach(strengthRecords) { record in
                        HStack {
                            Label(
                                record.title,
                                systemImage: record.kind.systemImage
                            )
                            Spacer()
                            Text(record.value)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }

            if !repRecords.isEmpty {
                Section("Rep Records") {
                    ForEach(repRecords) { record in
                        HStack {
                            Text(record.exerciseName)
                            Spacer()
                            Text(record.value)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
        }
        .navigationTitle("Personal Records")
        .navigationBarTitleDisplayMode(.inline)
    }
}

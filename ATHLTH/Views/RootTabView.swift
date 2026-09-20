import Charts
import MapKit
import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "sparkles") }

            TrainView()
                .tabItem { Label("Train", systemImage: "figure.run") }

            WorkoutsView()
                .tabItem { Label("Workouts", systemImage: "map") }

            SleepView()
                .tabItem { Label("Sleep", systemImage: "moon.stars.fill") }

            HeartView()
                .tabItem { Label("Heart", systemImage: "heart.fill") }

            CapabilityLabView()
                .tabItem { Label("Lab", systemImage: "testtube.2") }
        }
    }
}

struct HealthAccessView: View {
    @EnvironmentObject private var health: HealthKitManager
    @State private var requesting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 66))

                VStack(spacing: 10) {
                    Text("ATHLTH")
                        .font(.largeTitle.weight(.bold))
                    Text("Your private training companion")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Label("Workouts and outdoor routes", systemImage: "figure.run")
                    Label("Sleep duration and stages", systemImage: "moon.stars.fill")
                    Label("Heart rate, resting HR and HRV", systemImage: "heart.fill")
                    Label("Health data stays on this device in V0.1", systemImage: "lock.shield.fill")
                }
                .padding(20)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 26))

                if let error = health.authorizationError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button {
                    requesting = true
                    Task {
                        await health.requestAuthorization()
                        requesting = false
                    }
                } label: {
                    if requesting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Connect Apple Health")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(requesting || !health.healthDataAvailable)

                Spacer()
            }
            .padding()
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
    }
}

struct TodayView: View {
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var plan: TrainingPlanStore
    @EnvironmentObject private var membership: ATHLTHPlusStore

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 18 { return "Good afternoon" }
        return "Good evening"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(greeting.uppercased())
                                .font(.caption.weight(.semibold))
                                .tracking(1.8)
                                .foregroundStyle(.secondary)
                            Text("Today")
                                .font(.system(size: 38, weight: .bold, design: .rounded))
                            Text("Move better. Live longer.")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if membership.hasATHLTHPlus {
                            Label("ATHLTH+", systemImage: "crown.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 8)
                                .background(.green.opacity(0.1), in: Capsule())
                        }
                    }

                    HStack(spacing: 12) {
                        Image(systemName: plan.selectedActivity.icon)
                            .font(.title2)
                            .foregroundStyle(.green)
                            .frame(width: 50, height: 50)
                            .background(.green.opacity(0.1), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text("TODAY'S TRAINING")
                                .font(.caption2.weight(.semibold))
                                .tracking(1.4)
                                .foregroundStyle(.secondary)
                            Text(plan.selectedActivity.title)
                                .font(.title3.weight(.bold))
                            if plan.selectedActivity == .strength {
                                Text(plan.selectedStrengthSplit.title)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .padding(18)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26))
                    .overlay(RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.4)))

                    Text("Your health")
                        .font(.title2.weight(.bold))

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        MetricCard(title: "Sleep", value: health.sleep.totalAsleep > 0 ? health.sleep.totalAsleep.shortDuration : "—", systemImage: "moon.stars.fill")
                        MetricCard(title: "Resting HR", value: health.heart.restingHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "—", systemImage: "heart.circle.fill")
                        MetricCard(title: "HRV", value: health.heart.hrvMilliseconds.map { "\(Int($0.rounded())) ms" } ?? "—", systemImage: "waveform.path.ecg")
                    }

                    if let latest = health.workouts.first {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Latest workout").font(.title3.weight(.bold))
                                Spacer()
                                Text(latest.startDate, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            WorkoutRow(summary: latest)
                        }
                        .padding(18)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26))
                    }

                    if membership.hasATHLTHPlus {
                        HStack(spacing: 13) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.green)
                                .frame(width: 44, height: 44)
                                .background(.green.opacity(0.1), in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text("ATHLTH+ insights").font(.headline)
                                Text("Premium training and recovery insights will appear here as they become available.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(18)
                        .background(.green.opacity(0.055), in: RoundedRectangle(cornerRadius: 26))
                    }
                }
                .padding(20)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .background(LinearGradient(colors: [.green.opacity(0.025), .clear], startPoint: .top, endPoint: .center).ignoresSafeArea())
            .refreshable { await health.refreshAll() }
        }
    }
}

struct TrainView: View {
    @EnvironmentObject private var plan: TrainingPlanStore
    @State private var saved = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("What are we training?")
                            .font(.largeTitle.weight(.bold))
                        Text("Choose today's focus. Adaptive planning comes later.")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(PlannedActivity.allCases) { activity in
                        Button {
                            withAnimation(.snappy) {
                                plan.selectedActivity = activity
                                saved = false
                            }
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: activity.icon)
                                    .font(.title2)
                                    .frame(width: 38)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(activity.title).font(.headline)
                                    Text(activity.subtitle)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: plan.selectedActivity == activity ? "checkmark.circle.fill" : "circle")
                            }
                            .padding(18)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
                        }
                        .buttonStyle(.plain)
                    }

                    if plan.selectedActivity == .strength {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Choose your split")
                                .font(.title2.weight(.semibold))

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                                ForEach(StrengthSplit.allCases) { split in
                                    Button(split.title) {
                                        plan.selectedStrengthSplit = split
                                        saved = false
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(plan.selectedStrengthSplit == split ? .primary : nil)
                                }
                            }

                            Text("Exercises, sets, reps, weights and progression arrive in the next strength milestone.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        plan.save()
                        withAnimation { saved = true }
                    } label: {
                        Label(
                            saved ? "Training selected" : "Set today's training",
                            systemImage: saved ? "checkmark" : "calendar.badge.plus"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    if saved {
                        Text("Saved locally on this device.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding()
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Train")
        }
    }
}

struct WorkoutsView: View {
    @EnvironmentObject private var health: HealthKitManager

    var body: some View {
        NavigationStack {
            Group {
                if health.workouts.isEmpty {
                    ContentUnavailableView(
                        "No workouts yet",
                        systemImage: "figure.run",
                        description: Text("Recent Apple Health workouts will appear here.")
                    )
                } else {
                    List(health.workouts) { workout in
                        NavigationLink(value: workout) {
                            WorkoutRow(summary: workout)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Workouts")
            .navigationDestination(for: WorkoutSummary.self) { workout in
                WorkoutDetailView(summary: workout)
            }
            .refreshable { await health.refreshAll() }
        }
    }
}

struct WorkoutDetailView: View {
    @EnvironmentObject private var health: HealthKitManager
    let summary: WorkoutSummary

    @State private var detail = WorkoutDetail()
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Label(summary.activity.rawValue, systemImage: summary.activity.icon)
                        .font(.title.weight(.bold))
                    Text(summary.startDate, format: .dateTime.weekday(.wide).day().month(.wide).year().hour().minute())
                        .foregroundStyle(.secondary)
                }

                if !detail.route.isEmpty {
                    Map {
                        MapPolyline(coordinates: detail.route.map(\.coordinate))
                            .stroke(.primary, lineWidth: 5)
                    }
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 26))
                } else if loading {
                    RoundedRectangle(cornerRadius: 26)
                        .fill(.thinMaterial)
                        .frame(height: 220)
                        .overlay { ProgressView("Loading workout details…") }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    MetricCard(title: "Duration", value: summary.duration.shortDuration, systemImage: "timer")
                    MetricCard(title: "Distance", value: distanceText, systemImage: "location.fill")
                    MetricCard(title: "Avg. pace", value: paceText, systemImage: "speedometer")
                    MetricCard(
                        title: "Avg. heart rate",
                        value: detail.averageHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "—",
                        systemImage: "heart.fill"
                    )
                    MetricCard(
                        title: "Max heart rate",
                        value: detail.maxHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "—",
                        systemImage: "waveform.path.ecg"
                    )
                    MetricCard(
                        title: "Active energy",
                        value: summary.activeEnergyKilocalories.map { "\(Int($0.rounded())) kcal" } ?? "—",
                        systemImage: "flame.fill"
                    )
                }
            }
            .padding()
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            detail = await health.workoutDetail(for: summary)
            loading = false
        }
    }

    private var distanceText: String {
        guard let km = summary.distanceKilometers else { return "—" }
        return km.formatted(.number.precision(.fractionLength(2))) + " km"
    }

    private var paceText: String {
        guard let pace = summary.paceMinutesPerKilometer else { return "—" }
        let minutes = Int(pace)
        let seconds = Int((pace - Double(minutes)) * 60)
        return String(format: "%d:%02d /km", minutes, seconds)
    }
}

struct SleepView: View {
    @EnvironmentObject private var health: HealthKitManager

    private var stages: [(String, Double)] {
        [
            ("Core", health.sleep.core / 60),
            ("Deep", health.sleep.deep / 60),
            ("REM", health.sleep.rem / 60),
            ("Awake", health.sleep.awake / 60)
        ].filter { $0.1 > 0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Sleep")
                        .font(.largeTitle.weight(.bold))

                    MetricCard(
                        title: "Total sleep",
                        value: health.sleep.totalAsleep > 0 ? health.sleep.totalAsleep.shortDuration : "—",
                        detail: sleepWindow,
                        systemImage: "moon.stars.fill"
                    )

                    if !stages.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Sleep stages").font(.headline)
                            Chart(stages, id: \.0) { stage in
                                BarMark(
                                    x: .value("Minutes", stage.1),
                                    y: .value("Stage", stage.0)
                                )
                            }
                            .frame(height: 190)
                        }
                        .padding(18)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
                    } else {
                        ContentUnavailableView(
                            "No sleep data",
                            systemImage: "bed.double.fill",
                            description: Text("Authorized Apple Health sleep stages will appear here.")
                        )
                    }
                }
                .padding()
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await health.refreshAll() }
        }
    }

    private var sleepWindow: String? {
        guard let start = health.sleep.sleepStart, let end = health.sleep.sleepEnd else {
            return nil
        }
        return "\(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))"
    }
}

struct HeartView: View {
    @EnvironmentObject private var health: HealthKitManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Heart")
                        .font(.largeTitle.weight(.bold))

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                        MetricCard(
                            title: "Latest heart rate",
                            value: health.heart.latestHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "—",
                            detail: health.heart.latestHeartRateDate?.relativeDescription,
                            systemImage: "heart.fill"
                        )
                        MetricCard(
                            title: "Resting heart rate",
                            value: health.heart.restingHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "—",
                            detail: health.heart.restingHeartRateDate?.relativeDescription,
                            systemImage: "heart.circle.fill"
                        )
                        MetricCard(
                            title: "HRV",
                            value: health.heart.hrvMilliseconds.map { "\(Int($0.rounded())) ms" } ?? "—",
                            detail: health.heart.hrvDate?.relativeDescription,
                            systemImage: "waveform.path.ecg"
                        )
                    }

                    Text("ATHLTH V0.1 displays health data but does not diagnose or medically interpret it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await health.refreshAll() }
        }
    }
}

struct WorkoutRow: View {
    let summary: WorkoutSummary

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: summary.activity.icon)
                .font(.title2)
                .frame(width: 42, height: 42)
                .background(.thinMaterial, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(summary.activity.rawValue).font(.headline)
                Text(summary.startDate, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let km = summary.distanceKilometers {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(km, format: .number.precision(.fractionLength(2)))
                        .font(.headline)
                    Text("km")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(summary.duration.shortDuration)
                    .font(.headline)
            }
        }
        .padding(.vertical, 4)
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    var detail: String? = nil
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .contentTransition(.numericText())
            Text(title)
                .font(.subheadline.weight(.medium))
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }
}

private extension Date {
    var relativeDescription: String {
        RelativeDateTimeFormatter().localizedString(for: self, relativeTo: Date())
    }
}

extension TimeInterval {
    var shortDuration: String {
        let totalMinutes = Int(self / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}

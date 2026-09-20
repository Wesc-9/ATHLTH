import Charts
import MapKit
import SwiftUI
import UniformTypeIdentifiers

struct ProductRootTabView: View {
    var body: some View {
        TabView {
            ATHLTHHomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }

            ATHLTHTrainView()
                .tabItem { Label("Train", systemImage: "dumbbell.fill") }

            ATHLTHRecoveryView()
                .tabItem { Label("Recovery", systemImage: "leaf.fill") }

            ATHLTHProgressView()
                .tabItem { Label("Progress", systemImage: "chart.bar.fill") }

            ATHLTHProfileView()
                .tabItem { Label("Profile", systemImage: "person.fill") }
        }
        .tint(.green)
    }
}

struct ATHLTHHomeView: View {
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var session: AppSessionStore

    private var snapshot: HealthSnapshot {
        HealthSnapshot(
            activeCalories: PreviewData.healthSnapshot.activeCalories,
            activeCaloriesGoal: PreviewData.healthSnapshot.activeCaloriesGoal,
            steps: PreviewData.healthSnapshot.steps,
            sleepDuration: health.sleep.totalAsleep > 0
                ? health.sleep.totalAsleep
                : PreviewData.healthSnapshot.sleepDuration,
            restingHeartRate: health.heart.restingHeartRate ?? PreviewData.healthSnapshot.restingHeartRate,
            hrvMilliseconds: health.heart.hrvMilliseconds ?? PreviewData.healthSnapshot.hrvMilliseconds,
            recoveryScore: PreviewData.healthSnapshot.recoveryScore
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ATHLTHPageHeader(
                        title: "Good morning, \(session.profile.displayName)",
                        subtitle: session.profile.presence.state == .training
                            ? "Training now · \(session.profile.presence.workoutTitle ?? "Workout")"
                            : "Ready to train"
                    )

                    ATHLTHCard {
                        ATHLTHSectionHeader(title: "Today's Activity", actionTitle: "Apple Health")
                        HStack(spacing: 8) {
                            ATHLTHProgressRing(
                                title: "Move",
                                value: "\(Int(snapshot.activeCalories))",
                                progress: snapshot.activeCalories / max(snapshot.activeCaloriesGoal, 1),
                                icon: "figure.run",
                                tint: .green
                            )
                            ATHLTHProgressRing(
                                title: "Recovery",
                                value: "\(snapshot.recoveryScore ?? 0)%",
                                progress: Double(snapshot.recoveryScore ?? 0) / 100,
                                icon: "heart.fill",
                                tint: .blue
                            )
                            ATHLTHProgressRing(
                                title: "Sleep",
                                value: snapshot.sleepDuration.shortDuration,
                                progress: snapshot.sleepDuration / (8 * 3600),
                                icon: "moon.fill",
                                tint: .purple
                            )
                        }
                        .padding(.top, 14)
                    }

                    HStack(alignment: .top, spacing: 12) {
                        ATHLTHCard {
                            ATHLTHSectionHeader(title: "Train Today")
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                ForEach([WorkoutKind.running, .walking, .strength, .custom]) { kind in
                                    VStack(spacing: 7) {
                                        Image(systemName: kind.systemImage)
                                            .font(.title2)
                                            .foregroundStyle(.green)
                                        Text(kind.title)
                                            .font(.caption.weight(.semibold))
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 70)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                                }
                            }
                            .padding(.top, 10)
                        }

                        ATHLTHCard {
                            ATHLTHSectionHeader(title: "Next Workout")
                            if let workout = session.activePlan?.weeks.first?.days.first?.sessions.first {
                                Text(workout.title)
                                    .font(.headline)
                                    .padding(.top, 8)
                                Text("\(workout.durationMinutes ?? 0) min")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Button {
                                    session.beginTrainingStatus(for: workout)
                                } label: {
                                    Label("Start", systemImage: "play.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                                .padding(.top, 8)
                            }
                        }
                    }

                    ATHLTHCard {
                        ATHLTHSectionHeader(title: "Health Metrics")
                        HStack {
                            ATHLTHMetric(
                                title: "Heart Rate",
                                value: snapshot.restingHeartRate.map { "\(Int($0)) bpm" } ?? "—",
                                icon: "heart.fill",
                                tint: .red
                            )
                            ATHLTHMetric(
                                title: "Sleep",
                                value: snapshot.sleepDuration.shortDuration,
                                icon: "moon.fill",
                                tint: .purple
                            )
                            ATHLTHMetric(
                                title: "Steps",
                                value: snapshot.steps.formatted(),
                                icon: "shoeprints.fill",
                                tint: .blue
                            )
                            ATHLTHMetric(
                                title: "Recovery",
                                value: "\(snapshot.recoveryScore ?? 0)",
                                icon: "leaf.fill",
                                tint: .green
                            )
                        }
                        .padding(.top, 10)
                    }

                    HStack(spacing: 12) {
                        ATHLTHCard {
                            ATHLTHSectionHeader(title: "Consistency")
                            Text("5/7")
                                .font(.largeTitle.weight(.bold))
                                .padding(.top, 6)
                            Text("sessions this week")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ATHLTHCard {
                            ATHLTHSectionHeader(title: "Insights")
                            Text("Sleep is trending up.")
                                .font(.headline)
                                .padding(.top, 6)
                            Text("Keep the routine consistent and use recovery to guide intensity.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .background(
                LinearGradient(
                    colors: [.blue.opacity(0.08), .green.opacity(0.05), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .refreshable { await health.refreshAll() }
        }
    }
}

struct ATHLTHTrainView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var strengthWorkout: StrengthWorkoutStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var spotifyPlayback: SpotifyPlaybackStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore

    @State private var selectedSection = 0
    @State private var showingFileImporter = false
    @State private var importMessage: String?
    @State private var importError: String?
    @State private var watchTransferMessage: String?
    @State private var watchTransferError: String?
    @State private var selectedStrengthSession: PlannedSession?
    @State private var showingStrengthWorkout = false

    private let gpxImporter = GPXRouteImporter()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ATHLTHPageHeader(title: "Train", subtitle: "Build a stronger, healthier you.")

                    Picker("Training section", selection: $selectedSection) {
                        Text("Today").tag(0)
                        Text("Calendar").tag(1)
                        Text("Plans").tag(2)
                    }
                    .pickerStyle(.segmented)

                    switch selectedSection {
                    case 1:
                        AdvancedPlannerView()
                    case 2:
                        TrainingPlanManagerView()
                    default:
                        todayContent
                    }
                }
                .padding()
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .sheet(item: $selectedStrengthSession) { workout in
                WorkoutStartOptionsView(
                    session: workout,
                    watchConnected: watchConnection.isReady,
                    defaultCapture: settings.preferredWorkoutCapture,
                    defaultTracking: settings.defaultStrengthTracking,
                    linkedSpotifyPlaylist: session.activePlan?.spotifyPlaylist,
                    spotifyAutoplayEnabled:
                        settings.spotifyAutoplayLinkedPlaylists &&
                        (session.activePlan?.spotifyAutoplayOnWorkoutStart ?? false)
                ) { captureDevice, trackingMode in
                    startPlanSpotifyIfNeeded()
                    session.beginTrainingStatus(for: workout)
                    strengthWorkout.start(
                        session: workout,
                        watchSessionID: captureDevice == .appleWatch ? UUID() : nil,
                        trackingMode: trackingMode,
                        captureDevice: captureDevice
                    )
                    showingStrengthWorkout = true
                }
            }
            .fullScreenCover(isPresented: $showingStrengthWorkout) {
                ActiveStrengthWorkoutView()
                    .environmentObject(strengthWorkout)
                    .environmentObject(session)
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.xml, .data],
                allowsMultipleSelection: false
            ) { result in
                Task {
                    await importGPX(result)
                }
            }
            .alert("Routes", isPresented: Binding(
                get: {
                    importMessage != nil ||
                    importError != nil ||
                    watchTransferMessage != nil ||
                    watchTransferError != nil
                },
                set: { newValue in
                    if !newValue {
                        importMessage = nil
                        importError = nil
                        watchTransferMessage = nil
                        watchTransferError = nil
                    }
                }
            )) {
                Button("OK", role: .cancel) {
                    importMessage = nil
                    importError = nil
                    watchTransferMessage = nil
                    watchTransferError = nil
                }
            } message: {
                Text(
                    watchTransferError ??
                    importError ??
                    watchTransferMessage ??
                    importMessage ??
                    ""
                )
            }
        }
    }

    @ViewBuilder
    private var todayContent: some View {
        if let plan = session.activePlan {
            ATHLTHCard {
                ATHLTHSectionHeader(title: "Today's Plan", actionTitle: plan.title)
                VStack(spacing: 14) {
                    ForEach(Array((plan.weeks.first?.days.flatMap(\.sessions) ?? []).prefix(3))) { workout in
                        HStack {
                            Image(systemName: workout.kind.systemImage)
                                .foregroundStyle(.green)
                                .frame(width: 34)
                            VStack(alignment: .leading) {
                                Text(workout.title)
                                    .font(.headline)
                                Text("\(workout.durationMinutes ?? 0) min · \(workout.kind.title)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.top, 10)
            }
        }

        ATHLTHCard {
            ATHLTHSectionHeader(title: "Quick Start")
            HStack {
                ForEach([WorkoutKind.running, .walking, .strength, .custom]) { kind in
                    VStack(spacing: 7) {
                        Image(systemName: kind.systemImage)
                            .font(.title2)
                            .foregroundStyle(.green)
                        Text(kind.title)
                            .font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 76)
                }
            }
            .padding(.top, 10)
        }

        ATHLTHCard {
            HStack {
                ATHLTHSectionHeader(title: "Routes & Challenges", actionTitle: "See All")
                Spacer()
                Button {
                    showingFileImporter = true
                } label: {
                    Label("Import GPX", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
            }

            if let route = session.savedRoutes.first {
                Map(initialPosition: .region(routeRegion(route))) {
                    MapPolyline(coordinates: route.coordinates.map(\.coordinate))
                        .stroke(.green, lineWidth: 5)
                }
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .padding(.top, 10)

                HStack {
                    VStack(alignment: .leading) {
                        Text(route.title)
                            .font(.headline)
                        Text("\(route.distanceKilometers, specifier: "%.1f") km · \(Int(route.elevationGainMeters ?? 0)) m ascent")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let challenge = session.challenges.first {
                        Label(challenge.title, systemImage: "trophy.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.blue)
                    }
                }
                .padding(.top, 8)

                HStack(spacing: 10) {
                    Button {
                        sendRouteToWatch(route)
                    } label: {
                        Label("Send to Apple Watch", systemImage: "applewatch")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(!watchConnection.isReady)

                    if !watchConnection.isReady {
                        Text(watchConnection.state.subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.top, 8)
            } else {
                ContentUnavailableView(
                    "No routes yet",
                    systemImage: "map",
                    description: Text("Import a GPX route or create one later.")
                )
                .frame(height: 190)
            }
        }

        ATHLTHCard {
            ATHLTHSectionHeader(title: "Exercises", actionTitle: "Library + Custom")
            HStack {
                exerciseChip(PreviewData.benchPress)
                exerciseChip(PreviewData.customExercise)
            }
            .padding(.top, 10)
        }

        if let workout = session.activePlan?.weeks.first?.days.first?.sessions.first {
            Button {
                if workout.kind == .strength {
                    selectedStrengthSession = workout
                } else {
                    startPlanSpotifyIfNeeded()
                    session.beginTrainingStatus(for: workout)
                }
            } label: {
                Label(
                    "Start Workout",
                    systemImage: "play.fill"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.green)
        }
    }

    private func sendRouteToWatch(_ route: TrainingRoute) {
        do {
            try watchConnection.sendRoute(route)
            watchTransferMessage = "Sent \(route.title) to Apple Watch."
        } catch {
            watchTransferError = error.localizedDescription
        }
    }

    private func startPlanSpotifyIfNeeded() {
        guard
            let plan = session.activePlan,
            plan.spotifyAutoplayOnWorkoutStart,
            let playlist = plan.spotifyPlaylist
        else {
            return
        }

        Task {
            await spotifyPlayback.startLinkedPlaylist(
                playlist,
                settings: settings
            )
        }
    }

    @ViewBuilder
    private func exerciseChip(_ exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: exercise.origin == .custom ? "person.crop.circle.badge.plus" : "dumbbell.fill")
                .font(.title2)
                .foregroundStyle(.green)
            Text(exercise.name)
                .font(.subheadline.weight(.semibold))
            Text(exercise.primaryMuscles.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func routeRegion(_ route: TrainingRoute) -> MKCoordinateRegion {
        guard let first = route.coordinates.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 66.3126, longitude: 14.1428),
                span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
            )
        }

        return MKCoordinateRegion(
            center: first.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
        )
    }

    private func importGPX(_ result: Result<[URL], Error>) async {
        do {
            guard let url = try result.get().first else { return }

            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            let route = try await gpxImporter.importGPX(data: data, filename: url.lastPathComponent)

            await MainActor.run {
                session.addImportedRoute(route)
                importMessage = "Imported \(route.title) · \(String(format: "%.1f", route.distanceKilometers)) km"
            }
        } catch {
            await MainActor.run {
                importError = error.localizedDescription
            }
        }
    }
}

struct ATHLTHRecoveryView: View {
    private let recovery = PreviewData.recoverySnapshot

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ATHLTHPageHeader(
                        title: "Recovery",
                        subtitle: "Use sleep and recovery signals to guide today's load."
                    )

                    ATHLTHCard {
                        ATHLTHSectionHeader(title: "Recovery Score", actionTitle: "Today")
                        HStack(spacing: 24) {
                            ATHLTHProgressRing(
                                title: recovery.readinessText,
                                value: "\(recovery.score)",
                                progress: Double(recovery.score) / 100,
                                icon: "leaf.fill",
                                tint: .green
                            )
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Well recovered")
                                    .font(.title2.weight(.bold))
                                Text("Your sleep and HRV support a normal training session today.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 12)
                    }

                    HStack(spacing: 12) {
                        ATHLTHCard {
                            ATHLTHSectionHeader(title: "Sleep")
                            ATHLTHMetric(
                                title: "Sleep quality",
                                value: recovery.sleepDuration.shortDuration,
                                icon: "moon.fill",
                                tint: .purple
                            )
                            .padding(.top, 10)
                        }

                        ATHLTHCard {
                            ATHLTHSectionHeader(title: "Heart & HRV")
                            HStack {
                                ATHLTHMetric(
                                    title: "HRV",
                                    value: recovery.hrvMilliseconds.map { "\(Int($0)) ms" } ?? "—",
                                    icon: "waveform.path.ecg",
                                    tint: .blue
                                )
                                ATHLTHMetric(
                                    title: "Resting HR",
                                    value: recovery.restingHeartRate.map { "\(Int($0)) bpm" } ?? "—",
                                    icon: "heart.fill",
                                    tint: .red
                                )
                            }
                            .padding(.top, 10)
                        }
                    }

                    ATHLTHCard {
                        ATHLTHSectionHeader(title: "Recovery Trend")
                        Chart {
                            ForEach(Array([72, 75, 81, 84, 79, 86, 82].enumerated()), id: \.offset) { index, value in
                                BarMark(
                                    x: .value("Day", index),
                                    y: .value("Recovery", value)
                                )
                                .foregroundStyle(.green.gradient)
                            }
                        }
                        .frame(height: 170)
                        .padding(.top, 12)
                    }

                    HStack(spacing: 12) {
                        ATHLTHCard {
                            ATHLTHSectionHeader(title: "Breathing & Mobility")
                            Label("5 min box breathing", systemImage: "wind")
                                .font(.headline)
                                .padding(.top, 10)
                            Text("Calm down and reset before training.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ATHLTHCard {
                            ATHLTHSectionHeader(title: "Today's Training")
                            Label("Moderate intensity", systemImage: "dumbbell.fill")
                                .font(.headline)
                                .foregroundStyle(.green)
                                .padding(.top, 10)
                            Text("Recovery looks good. Keep some reserve.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

struct ATHLTHProgressView: View {
    private let weekly = [2, 4, 3, 5, 2, 4, 3]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ATHLTHPageHeader(title: "Your Progress", subtitle: "Small steps. Big results.")

                    ATHLTHCard {
                        ATHLTHSectionHeader(title: "Weekly Overview", actionTitle: "This week")
                        HStack {
                            ATHLTHMetric(title: "Workouts", value: "5", icon: "dumbbell.fill")
                            ATHLTHMetric(title: "Steps/day", value: "8,432", icon: "shoeprints.fill", tint: .blue)
                            ATHLTHMetric(title: "Sleep/day", value: "7h 24m", icon: "moon.fill", tint: .purple)
                            ATHLTHMetric(title: "Recovery", value: "82", icon: "leaf.fill")
                        }
                        .padding(.top, 12)
                    }

                    ATHLTHCard {
                        ATHLTHSectionHeader(title: "Workouts Completed")
                        Chart {
                            ForEach(Array(weekly.enumerated()), id: \.offset) { index, value in
                                BarMark(
                                    x: .value("Day", index),
                                    y: .value("Workouts", value)
                                )
                                .foregroundStyle(.green.gradient)
                            }
                        }
                        .frame(height: 190)
                        .padding(.top, 12)
                    }

                    HStack(spacing: 12) {
                        ATHLTHCard {
                            ATHLTHSectionHeader(title: "Consistency Streak")
                            Label("12 days", systemImage: "flame.fill")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.green)
                                .padding(.top, 10)
                            Text("Keep it going.")
                                .foregroundStyle(.secondary)
                        }

                        ATHLTHCard {
                            ATHLTHSectionHeader(title: "Personal Records")
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Squat · 100 kg", systemImage: "dumbbell.fill")
                                Label("Longest run · 7.2 km", systemImage: "figure.run")
                                Label("Fastest 5K · 24:18", systemImage: "stopwatch.fill")
                            }
                            .font(.subheadline)
                            .padding(.top, 10)
                        }
                    }

                    ATHLTHCard {
                        ATHLTHSectionHeader(title: "Achievements", actionTitle: "See All")
                        HStack {
                            achievement(icon: "dumbbell.fill", title: "10 Workouts")
                            achievement(icon: "shoeprints.fill", title: "50K Steps")
                            achievement(icon: "mountain.2.fill", title: "New PR")
                        }
                        .padding(.top, 10)
                    }
                }
                .padding()
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func achievement(icon: String, title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(.green)
                .frame(width: 58, height: 58)
                .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
            Text(title)
                .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
    }
}

struct ATHLTHProfileView: View {
    @EnvironmentObject private var session: AppSessionStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    HStack(spacing: 18) {
                        Circle()
                            .fill(.green.opacity(0.12))
                            .frame(width: 96, height: 96)
                            .overlay {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 42))
                                    .foregroundStyle(.green)
                            }

                        VStack(alignment: .leading, spacing: 5) {
                            Text(session.profile.displayName)
                                .font(.title.weight(.bold))
                            Text("@\(session.profile.username)")
                                .foregroundStyle(.secondary)

                            Label(
                                session.profile.presence.state == .training
                                    ? "Training now"
                                    : "Ready to train",
                                systemImage: session.profile.presence.state == .training
                                    ? "figure.run"
                                    : "circle.fill"
                            )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                        }

                        Spacer()
                    }

                    HStack {
                        profileStat("\(session.profile.followersCount)", "Followers")
                        profileStat("\(session.profile.followingCount)", "Following")
                        profileStat("\(session.profile.workoutsCount)", "Workouts")
                    }

                    HStack(spacing: 12) {
                        summaryCard(icon: "bookmark.fill", value: "12", title: "Saved Plans", tint: .green)
                        summaryCard(icon: "point.topleft.down.to.point.bottomright.curvepath", value: "\(session.savedRoutes.count)", title: "Saved Routes", tint: .blue)
                        summaryCard(icon: "trophy.fill", value: "14", title: "Achievements", tint: .orange)
                    }

                    ATHLTHCard {
                        ATHLTHSectionHeader(title: "Share Your Plans")
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Public, friends or private")
                                    .font(.headline)
                                Text("Plan visibility is stored per plan and can be changed at any time.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let plan = session.activePlan {
                                Text(plan.visibility.title)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(.green.opacity(0.12), in: Capsule())
                            }
                        }
                        .padding(.top, 10)
                    }

                    ATHLTHCard {
                        ATHLTHSectionHeader(title: "Recent Activities", actionTitle: "See All")
                        HStack {
                            recentActivity("Morning Run", icon: "figure.run", detail: "12.5 km")
                            recentActivity("Upper Body", icon: "dumbbell.fill", detail: "6 exercises")
                            recentActivity("Evening Walk", icon: "figure.walk", detail: "7.1 km")
                        }
                        .padding(.top, 10)
                    }

                    ATHLTHCard {
                        ATHLTHSectionHeader(title: "Friends", actionTitle: "Find Friends")
                        HStack {
                            ForEach(["Sara", "Erik", "Live", "Marcus"], id: \.self) { name in
                                VStack(spacing: 7) {
                                    Circle()
                                        .fill(.blue.opacity(0.1))
                                        .frame(width: 52, height: 52)
                                        .overlay {
                                            Image(systemName: "person.fill")
                                                .foregroundStyle(.blue)
                                        }
                                    Text(name)
                                        .font(.caption)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.top, 10)
                    }
                }
                .padding()
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("ATHLTH")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }

                    Button {
                    } label: {
                        Image(systemName: "pencil")
                    }

                    NavigationLink {
                        ATHLTHSettingsView()
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func profileStat(_ value: String, _ title: String) -> some View {
        VStack {
            Text(value)
                .font(.title2.weight(.bold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func summaryCard(icon: String, value: String, title: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(value)
                .font(.title2.weight(.bold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private func recentActivity(_ title: String, icon: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.green)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

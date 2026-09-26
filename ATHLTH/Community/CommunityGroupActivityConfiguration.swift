import Foundation
import SwiftUI

enum CommunityGroupActivityMode: String, Codable, Hashable {
    case free
    case route
    case workout
    case strength
}

struct CommunityGroupRouteSnapshot: Codable, Hashable {
    let id: UUID
    let title: String
    let coordinates: [RouteCoordinate]
    let distanceKilometers: Double
    let elevationGainMeters: Double?
    let startName: String?
    let endName: String?

    init(route: TrainingRoute) {
        id = route.id
        title = route.title
        coordinates = route.coordinates
        distanceKilometers = route.distanceKilometers
        elevationGainMeters = route.elevationGainMeters
        startName = route.startName
        endName = route.endName
    }
}

struct CommunityGroupStrengthExerciseSnapshot:
    Codable,
    Hashable,
    Identifiable
{
    let id: UUID
    let name: String
    let instructions: [String]
    let primaryMuscles: [String]
    let equipment: [String]

    init(entry: ExerciseLibraryEntry) {
        id = entry.exercise.id
        name = entry.exercise.name
        instructions = entry.exercise.instructions
        primaryMuscles = entry.exercise.primaryMuscles
        equipment = entry.exercise.equipment
    }
}

struct CommunityGroupActivityConfiguration:
    Codable,
    Hashable
{
    let activityType: String
    let mode: CommunityGroupActivityMode
    let distanceKilometers: Double?
    let route: CommunityGroupRouteSnapshot?
    let runningWorkout: RunningWorkoutTemplate?
    let strengthDurationMinutes: Int?
    let strengthExercises:
        [CommunityGroupStrengthExerciseSnapshot]?

    enum CodingKeys: String, CodingKey {
        case activityType = "activity_type"
        case mode
        case distanceKilometers = "distance_kilometers"
        case route
        case runningWorkout = "running_workout"
        case strengthDurationMinutes =
            "strength_duration_minutes"
        case strengthExercises = "strength_exercises"
    }

    var compactSummary: String {
        switch activityType {
        case "running":
            switch mode {
            case .free:
                return distanceKilometers.map {
                    String(format: "Free run · %.1f km", $0)
                } ?? "Free run"
            case .route:
                return route.map {
                    String(
                        format:
                            "Route · %@ · %.1f km",
                        $0.title,
                        $0.distanceKilometers
                    )
                } ?? "Route"
            case .workout:
                return runningWorkout.map {
                    "Workout · \($0.title)"
                } ?? "Running workout"
            case .strength:
                return "Run"
            }

        case "walking":
            switch mode {
            case .free:
                return distanceKilometers.map {
                    String(format: "Free walk · %.1f km", $0)
                } ?? "Free walk"
            case .route:
                return route.map {
                    String(
                        format:
                            "Route · %@ · %.1f km",
                        $0.title,
                        $0.distanceKilometers
                    )
                } ?? "Route"
            default:
                return "Walk"
            }

        case "cycling":
            switch mode {
            case .free:
                return distanceKilometers.map {
                    String(format: "Free ride · %.1f km", $0)
                } ?? "Free ride"
            case .route:
                return route.map {
                    String(
                        format:
                            "Route · %@ · %.1f km",
                        $0.title,
                        $0.distanceKilometers
                    )
                } ?? "Route"
            default:
                return "Cycling"
            }

        case "strength":
            var parts: [String] = ["Strength"]

            if let strengthDurationMinutes {
                parts.append("\(strengthDurationMinutes) min")
            }

            if let count = strengthExercises?.count,
               count > 0 {
                parts.append(
                    "\(count) exercise\(count == 1 ? "" : "s")"
                )
            }

            return parts.joined(separator: " · ")

        default:
            return activityType.capitalized
        }
    }
}

struct CommunityGroupActivityDraft {
    var activityType = "running"
    var mode: CommunityGroupActivityMode = .free
    var distanceText = "5"
    var selectedRoute: TrainingRoute?
    var selectedRunningWorkout: RunningWorkoutTemplate?
    var strengthDurationText = ""
    var selectedExercises: [ExerciseLibraryEntry] = []

    var distanceKilometers: Double? {
        Double(
            distanceText
                .replacingOccurrences(of: ",", with: ".")
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
        )
    }

    var strengthDurationMinutes: Int? {
        let clean = strengthDurationText
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !clean.isEmpty else {
            return nil
        }

        return Int(clean)
    }

    var validationMessage: String? {
        switch activityType {
        case "running", "walking", "cycling":
            switch mode {
            case .free:
                guard let distanceKilometers,
                      distanceKilometers > 0
                else {
                    return "Choose a distance greater than 0 km."
                }

            case .route:
                guard selectedRoute != nil else {
                    return "Choose a route."
                }

            case .workout:
                guard activityType == "running",
                      selectedRunningWorkout != nil
                else {
                    return "Choose a running workout."
                }

            case .strength:
                return "Choose Free, Route or Workout."
            }

        case "strength":
            if let duration = strengthDurationMinutes,
               duration <= 0 {
                return "Strength duration must be greater than zero."
            }

        default:
            break
        }

        return nil
    }

    var configuration: CommunityGroupActivityConfiguration {
        switch activityType {
        case "running", "walking", "cycling":
            return CommunityGroupActivityConfiguration(
                activityType: activityType,
                mode: mode,
                distanceKilometers:
                    mode == .free
                        ? distanceKilometers
                        : (
                            mode == .route
                                ? selectedRoute?
                                    .distanceKilometers
                                : selectedRunningWorkout
                                    .flatMap {
                                        $0.estimatedDistanceMeters
                                    }
                                    .map { $0 / 1_000 }
                        ),
                route:
                    mode == .route
                        ? selectedRoute.map {
                            CommunityGroupRouteSnapshot(
                                route: $0
                            )
                        }
                        : nil,
                runningWorkout:
                    activityType == "running" &&
                    mode == .workout
                        ? selectedRunningWorkout
                        : nil,
                strengthDurationMinutes: nil,
                strengthExercises: nil
            )

        case "strength":
            return CommunityGroupActivityConfiguration(
                activityType: "strength",
                mode: .strength,
                distanceKilometers: nil,
                route: nil,
                runningWorkout: nil,
                strengthDurationMinutes:
                    strengthDurationMinutes,
                strengthExercises:
                    selectedExercises.isEmpty
                        ? nil
                        : selectedExercises.map {
                            CommunityGroupStrengthExerciseSnapshot(
                                entry: $0
                            )
                        }
            )

        default:
            return CommunityGroupActivityConfiguration(
                activityType: activityType,
                mode: .free,
                distanceKilometers: nil,
                route: nil,
                runningWorkout: nil,
                strengthDurationMinutes: nil,
                strengthExercises: nil
            )
        }
    }

    mutating func normalizeForActivityChange() {
        selectedRoute = nil
        selectedRunningWorkout = nil

        switch activityType {
        case "running", "walking", "cycling":
            mode = .free
        case "strength":
            mode = .strength
        default:
            mode = .free
        }
    }
}

struct CommunityGroupActivityEditor: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var runningLibrary:
        RunningWorkoutLibraryStore
    @EnvironmentObject private var exerciseLibrary:
        ExerciseLibraryStore

    @Binding var draft: CommunityGroupActivityDraft

    @State private var showingRoutes = false
    @State private var showingRunningWorkouts = false
    @State private var showingExercises = false

    var body: some View {
        Section("Activity") {
            Picker(
                "Type",
                selection: $draft.activityType
            ) {
                Label("Run", systemImage: "figure.run")
                    .tag("running")
                Label("Walk", systemImage: "figure.walk")
                    .tag("walking")
                Label(
                    "Cycling",
                    systemImage: "figure.outdoor.cycle"
                )
                .tag("cycling")
                Label("Strength", systemImage: "dumbbell.fill")
                    .tag("strength")
            }

            if draft.activityType == "strength" {
                strengthConfiguration
            } else {
                enduranceConfiguration
            }
        }
        .onChange(of: draft.activityType) { _, _ in
            draft.normalizeForActivityChange()
        }
        .sheet(isPresented: $showingRoutes) {
            NavigationStack {
                SavedRoutesView(
                    selectionTitle: "Choose Route"
                ) { route in
                    draft.selectedRoute = route
                    draft.mode = .route
                    showingRoutes = false
                }
            }
        }
        .sheet(isPresented: $showingRunningWorkouts) {
            NavigationStack {
                RunningWorkoutLibraryView(
                    selectionTitle:
                        "Choose Running Workout",
                    onSelect: { workout in
                        draft.selectedRunningWorkout =
                            workout
                        draft.mode = .workout
                        showingRunningWorkouts = false
                    }
                )
            }
            .environmentObject(runningLibrary)
        }
        .sheet(isPresented: $showingExercises) {
            NavigationStack {
                ExerciseLibraryView(
                    selectionTitle: "Add Exercise"
                ) { entry in
                    if !draft.selectedExercises.contains(
                        where: { $0.id == entry.id }
                    ) {
                        draft.selectedExercises.append(entry)
                    }
                    showingExercises = false
                }
            }
            .environmentObject(exerciseLibrary)
            .environmentObject(session)
        }
    }

    @ViewBuilder
    private var enduranceConfiguration: some View {
        Picker(
            "Format",
            selection: $draft.mode
        ) {
            Text(freeTitle)
                .tag(CommunityGroupActivityMode.free)
            Text("Route")
                .tag(CommunityGroupActivityMode.route)

            if draft.activityType == "running" {
                Text("Workout")
                    .tag(CommunityGroupActivityMode.workout)
            }
        }
        .pickerStyle(.segmented)

        switch draft.mode {
        case .free:
            HStack {
                TextField(
                    "Distance",
                    text: $draft.distanceText
                )
                .keyboardType(.decimalPad)

                Text("km")
                    .foregroundStyle(.secondary)
            }

            Text(
                "A distance is required for a free \(activityNoun)."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

        case .route:
            Button {
                showingRoutes = true
            } label: {
                selectionRow(
                    icon: "map.fill",
                    title:
                        draft.selectedRoute?.title ??
                        "Choose Route",
                    subtitle:
                        draft.selectedRoute.map {
                            String(
                                format:
                                    "%.1f km",
                                $0.distanceKilometers
                            )
                        }
                )
            }
            .buttonStyle(.plain)

        case .workout:
            Button {
                showingRunningWorkouts = true
            } label: {
                selectionRow(
                    icon: "figure.run.circle",
                    title:
                        draft.selectedRunningWorkout?
                            .title ??
                        "Choose Running Workout",
                    subtitle:
                        draft.selectedRunningWorkout.map {
                            $0.isBuiltIn
                                ? "ATHLTH Library"
                                : "My Workout"
                        }
                )
            }
            .buttonStyle(.plain)

            Text(
                "Choose from the ATHLTH running library or your own saved workouts."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

        case .strength:
            EmptyView()
        }
    }

    @ViewBuilder
    private var strengthConfiguration: some View {
        HStack {
            TextField(
                "Duration (optional)",
                text: $draft.strengthDurationText
            )
            .keyboardType(.numberPad)

            Text("min")
                .foregroundStyle(.secondary)
        }

        if !draft.selectedExercises.isEmpty {
            ForEach(draft.selectedExercises) { entry in
                HStack(spacing: 10) {
                    Image(systemName: "dumbbell.fill")
                        .foregroundStyle(
                            ATHLTHTheme.accentDeep
                        )

                    VStack(
                        alignment: .leading,
                        spacing: 2
                    ) {
                        Text(entry.name)
                            .font(
                                .subheadline
                                    .weight(.semibold)
                            )

                        Text(
                            entry.source == .custom
                                ? "My Exercise"
                                : "Exercise Library"
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(role: .destructive) {
                        draft.selectedExercises.removeAll {
                            $0.id == entry.id
                        }
                    } label: {
                        Image(
                            systemName: "minus.circle.fill"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        Button {
            showingExercises = true
        } label: {
            Label(
                "Add Exercises",
                systemImage: "plus.circle.fill"
            )
        }

        Text(
            "Exercises and duration are optional. Choose from the exercise library or My Exercises."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var freeTitle: String {
        switch draft.activityType {
        case "walking":
            return "Free Walk"
        case "cycling":
            return "Free Ride"
        default:
            return "Free Run"
        }
    }

    private var activityNoun: String {
        switch draft.activityType {
        case "walking":
            return "walk"
        case "cycling":
            return "ride"
        default:
            return "run"
        }
    }

    private func selectionRow(
        icon: String,
        title: String,
        subtitle: String?
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )
                .frame(width: 34, height: 34)
                .background(
                    ATHLTHTheme.accentSoft,
                    in: RoundedRectangle(
                        cornerRadius: 10
                    )
                )

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(title)
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2.bold())
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

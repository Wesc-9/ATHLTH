import SwiftUI

/// Separate iPad presentation over the same stores used by iPhone.
/// The sidebar is permanent in regular-width landscape windows; the system
/// collapses columns naturally when Stage Manager provides a narrow window.
private enum ATHLTHStudioDestination: String, CaseIterable, Identifiable {
    case overview, planner, insights, history, explore, community, coach, settings
    var id: String { rawValue }

    var label: String {
        switch self {
        case .overview: return ATHLTHLocalization.choose(english: "Overview", norwegian: "Oversikt")
        case .planner: return ATHLTHLocalization.choose(english: "Plan Studio", norwegian: "Plan Studio")
        case .insights: return ATHLTHLocalization.choose(english: "Insights Lab", norwegian: "Innsiktslab")
        case .history: return ATHLTHLocalization.choose(english: "Workout history", norwegian: "Treningshistorikk")
        case .explore: return ATHLTHLocalization.choose(english: "Routes & Explore", norwegian: "Ruter og utforsk")
        case .community: return ATHLTHLocalization.choose(english: "Community", norwegian: "Fellesskap")
        case .coach: return "ATHLTH Coach"
        case .settings: return ATHLTHLocalization.choose(english: "Settings", norwegian: "Innstillinger")
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .planner: "calendar"
        case .insights: "chart.xyaxis.line"
        case .history: "clock.arrow.circlepath"
        case .explore: "map"
        case .community: "person.3"
        case .coach: "sparkles"
        case .settings: "gearshape"
        }
    }
}

struct ATHLTHiPadStudioRootView: View {
    @EnvironmentObject private var session: AppSessionStore
    @State private var selection: ATHLTHStudioDestination = .overview
    @State private var selectedWorkout: WorkoutSummary?
    @State private var showingInspector = false
    @State private var inspectorShowsCoach = false
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var trainRequest: ATHLTHTrainNavigationRequest?
    @State private var showingTrain = false
    @State private var selectedStandaloneWorkout: PlannedSession?

    private let canvas = Color(red: 0.985, green: 0.979, blue: 0.965)
    private let ink = Color(red: 0.19, green: 0.18, blue: 0.16)
    private let gold = Color(red: 0.69, green: 0.54, blue: 0.32)

    init() {
        // Reuse the smoke-test tab argument to inspect actual Studio pages.
        let argument = ProcessInfo.processInfo.arguments.first {
            $0.hasPrefix("--athlth-compatibility-tab=")
        }
        let index = argument.flatMap {
            Int($0.dropFirst("--athlth-compatibility-tab=".count))
        } ?? 0
        let destinations: [ATHLTHStudioDestination] = [
            .overview, .planner, .insights, .explore, .community
        ]
        _selection = State(initialValue: destinations[min(max(0, index), 4)])
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 244, max: 280)
        } detail: {
            NavigationStack {
                page
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(canvas.ignoresSafeArea())
                    .navigationTitle(selection.label)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    sidebarVisibility =
                                        sidebarVisibility == .detailOnly ? .all : .detailOnly
                                }
                            } label: {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english: "Show or hide sidebar",
                                        norwegian: "Vis eller skjul sidemeny"
                                    ),
                                    systemImage: "sidebar.left"
                                )
                            }
                            .accessibilityHint(ATHLTHLocalization.choose(
                                english: "Give the current Studio view more room",
                                norwegian: "Gi den åpne Studio-visningen mer plass"
                            ))
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                inspectorShowsCoach = true
                                showingInspector = true
                            } label: {
                                Label("ATHLTH Coach", systemImage: "sparkles")
                            }
                        }
                    }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(gold)
        .sheet(isPresented: $showingTrain) {
            ATHLTHTrainView(
                navigationRequest: $trainRequest,
                isActive: true
            )
        }
        .sheet(item: $selectedStandaloneWorkout) { workout in
            ATHLTHStudioStandaloneWorkoutDetailView(workoutID: workout.id)
        }
        .onChange(of: selection) { _, _ in
            showingInspector = false
        }
        .inspector(isPresented: $showingInspector) {
            if inspectorShowsCoach {
                RecoveryCoachInboxDestinationView()
                    .inspectorColumnWidth(min: 300, ideal: 370, max: 480)
            } else if let selectedWorkout {
                ATHLTHStudioWorkoutInspectionView(workout: selectedWorkout)
                    .inspectorColumnWidth(min: 270, ideal: 320, max: 400)
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("ATHLTH")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .tracking(2.2)
                    .foregroundStyle(ink)
                Text("STUDIO")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(3)
                    .foregroundStyle(gold)
            }
            .padding(.horizontal, 23)
            .padding(.top, 27)
            .padding(.bottom, 26)

            ScrollView {
                VStack(spacing: 5) {
                    ForEach(ATHLTHStudioDestination.allCases) { destination in
                        Button {
                            selection = destination
                        } label: {
                            HStack(spacing: 13) {
                                Image(systemName: destination.symbol)
                                    .font(.system(size: 17))
                                    .frame(width: 24)
                                Text(destination.label)
                                    .font(.system(size: 14, weight: selection == destination ? .semibold : .medium))
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 15)
                            .frame(minHeight: 46)
                            .foregroundStyle(selection == destination ? ink : ink.opacity(0.68))
                            .background {
                                if selection == destination {
                                    RoundedRectangle(cornerRadius: 13).fill(.white)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selection == destination ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 11)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(session.profile.displayName.isEmpty ? "ATHLTH" : session.profile.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(ATHLTHLocalization.choose(
                    english: "Your body. Your data. Your progress.",
                    norwegian: "Din kropp. Dine data. Din fremgang."
                ))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
            .padding(20)
        }
        .background(canvas)
    }

    @ViewBuilder
    private var page: some View {
        switch selection {
        case .overview:
            ATHLTHStudioDashboardView(
                onInspect: inspect,
                onOpenPlanner: { selection = .planner },
                onOpenInsights: { selection = .insights },
                onOpenHistory: { selection = .history },
                onOpenSettings: { selection = .settings },
                onOpenWorkout: { entry in
                    if let planID = entry.planID {
                        trainRequest = .workout(
                            planID: planID,
                            workoutID: entry.workout.id
                        )
                        showingTrain = true
                    } else {
                        // Open this precise standalone entry, not the
                        // generic Train landing page.
                        selectedStandaloneWorkout = entry.workout
                    }
                },
                onStartQuick: {
                    trainRequest = .customQuick
                    showingTrain = true
                }
            )
        case .planner:
            ATHLTHStudioPlannerView()
        case .insights:
            ATHLTHStudioInsightsView()
        case .history:
            ATHLTHStudioHistoryView(onInspect: inspect)
        case .explore:
            ATHLTHExploreView()
        case .community:
            ATHLTHCommunityV5View()
        case .coach:
            RecoveryCoachInboxDestinationView()
        case .settings:
            ATHLTHSettingsView()
        }
    }

    private func inspect(_ workout: WorkoutSummary) {
        selectedWorkout = workout
        inspectorShowsCoach = false
        showingInspector = true
    }
}

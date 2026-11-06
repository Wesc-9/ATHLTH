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
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var studioPlanSync = ATHLTHStudioPlanSyncStore()
    @SceneStorage("athlth.studio.selectedDestination")
    private var savedDestination = ATHLTHStudioDestination.overview.rawValue
    @State private var selection: ATHLTHStudioDestination = .overview
    @State private var selectedWorkout: WorkoutSummary?
    @State private var showingInspector = false
    @State private var inspectorShowsCoach = false
    @State private var inspectorShowsInbox = false
    @State private var showingProfile = false
    @State private var studioUtility: ATHLTHSideMenuDestination?
    @State private var studioFeature: ATHLTHSideMenuDestination?
    @SceneStorage("athlth.studio.libraryExpanded") private var libraryExpanded = false
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var focusedPlanningDate: Date?
    @State private var trainRequest: ATHLTHTrainNavigationRequest?
    @State private var showingTrain = false
    @State private var selectedStandaloneWorkout: PlannedSession?
    @State private var showingPlanSync = false
    @State private var showingPresentation = false

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
        let initial = destinations[min(max(0, index), 4)]
        _selection = State(initialValue: initial)
        // Plan Studio starts with an icon rail instead of consuming a quarter
        // of the landscape iPad with a full navigation sidebar.
        _sidebarVisibility = State(initialValue:
            initial == .planner ? .detailOnly : .all)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 244, max: 280)
        } detail: {
            NavigationStack {
                studioDetail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(canvas.ignoresSafeArea())
                    // Overview owns its compact title/metrics inside the
                    // content. Avoid the duplicate large "Overview" title
                    // that previously consumed substantial iPad space.
                    .navigationTitle(selection == .overview ? "" : selection.label)
                    .navigationBarTitleDisplayMode(.inline)
                    // Keep the Overview scroll edge clean: a visible bar
                    // previously rendered as an empty translucent title tile.
                    .toolbarBackground(canvas, for: .navigationBar)
                    .toolbarBackground(
                        selection == .overview ? .hidden : .visible,
                        for: .navigationBar
                    )
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
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            Button {
                                let closing = showingInspector && inspectorShowsCoach
                                inspectorShowsCoach = true
                                inspectorShowsInbox = false
                                showingInspector = !closing
                            } label: {
                                Label("ATHLTH Coach", systemImage: "sparkles")
                            }
                            .help("ATHLTH Coach")
                            .accessibilityIdentifier("athlth-ipad-coach-panel")

                            Button {
                                let closing = showingInspector && inspectorShowsInbox
                                inspectorShowsCoach = false
                                inspectorShowsInbox = true
                                showingInspector = !closing
                            } label: {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english: "Inbox", norwegian: "Innboks"
                                    ),
                                    systemImage: "bubble.left.and.bubble.right"
                                )
                            }
                            .help(ATHLTHLocalization.choose(
                                english: "Open messages alongside your work",
                                norwegian: "Åpne meldinger ved siden av arbeidet"
                            ))
                            .accessibilityIdentifier("athlth-ipad-inbox-panel")

                            Button {
                                showingPlanSync = true
                            } label: {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english: "Plan sync", norwegian: "Plansynkronisering"
                                    ),
                                    systemImage: !studioPlanSync.conflicts.isEmpty
                                        ? "exclamationmark.icloud"
                                        : studioPlanSync.enabled ? "checkmark.icloud" : "icloud.slash"
                                )
                            }
                            .help(studioPlanSync.status)
                            .accessibilityIdentifier("athlth-ipad-plan-sync")

                            Button {
                                showingPresentation = true
                            } label: {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english: "Presentation mode",
                                        norwegian: "Presentasjonsmodus"
                                    ),
                                    systemImage: "rectangle.on.rectangle"
                                )
                            }
                            .help(ATHLTHLocalization.choose(
                                english: "Show an aggregate, private-safe training overview",
                                norwegian: "Vis en samlet treningsoversikt uten personlige detaljer"
                            ))
                            .accessibilityIdentifier("athlth-ipad-presentation-button")

                            Menu {
                                Button {
                                    selection = .overview
                                } label: { Label(ATHLTHStudioDestination.overview.label,
                                                 systemImage: "square.grid.2x2") }
                                    .keyboardShortcut("1", modifiers: [.command])
                                Button {
                                    selection = .planner
                                } label: { Label(ATHLTHStudioDestination.planner.label,
                                                 systemImage: "calendar") }
                                    .keyboardShortcut("2", modifiers: [.command])
                                Button {
                                    selection = .insights
                                } label: { Label(ATHLTHStudioDestination.insights.label,
                                                 systemImage: "chart.xyaxis.line") }
                                    .keyboardShortcut("3", modifiers: [.command])
                                Button {
                                    selection = .history
                                } label: { Label(ATHLTHStudioDestination.history.label,
                                                 systemImage: "clock.arrow.circlepath") }
                                    .keyboardShortcut("4", modifiers: [.command])
                                Button {
                                    selection = .explore
                                } label: { Label(ATHLTHStudioDestination.explore.label,
                                                 systemImage: "map") }
                                    .keyboardShortcut("5", modifiers: [.command])
                                Button {
                                    selection = .community
                                } label: { Label(ATHLTHStudioDestination.community.label,
                                                 systemImage: "person.3") }
                                    .keyboardShortcut("6", modifiers: [.command])
                                Button {
                                    selection = .coach
                                } label: { Label(ATHLTHStudioDestination.coach.label,
                                                 systemImage: "sparkles") }
                                    .keyboardShortcut("7", modifiers: [.command])
                                Button {
                                    selection = .settings
                                } label: { Label(ATHLTHStudioDestination.settings.label,
                                                 systemImage: "gearshape") }
                                    .keyboardShortcut("8", modifiers: [.command])
                                Divider()
                                Button {
                                    trainRequest = .customQuick
                                    showingTrain = true
                                } label: {
                                    Label(
                                        ATHLTHLocalization.choose(
                                            english: "New quick workout",
                                            norwegian: "Ny hurtigøkt"
                                        ),
                                        systemImage: "plus"
                                    )
                                }
                                .keyboardShortcut("n", modifiers: [.command, .shift])
                            } label: {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english: "Studio shortcuts",
                                        norwegian: "Studio-hurtigtaster"
                                    ),
                                    systemImage: "keyboard"
                                )
                            }
                            .help(ATHLTHLocalization.choose(
                                english: "Navigate with Command 1–8",
                                norwegian: "Naviger med Kommando 1–8"
                            ))
                        }
                    }
            }
        }
        .navigationSplitViewStyle(.balanced)
        // iPhone/iPad share the workout engine; only Studio navigation and
        // adaptive side-by-side presentation differ on iPad.
        .environment(\.athlthStudioFullscreenEditing, true)
        .tint(gold)
        .fullScreenCover(isPresented: $showingTrain) {
            ATHLTHStudioTrainWorkspaceView(navigationRequest: $trainRequest)
        }
        .sheet(isPresented: $showingPlanSync) {
            ATHLTHStudioPlanSyncPanel(sync: studioPlanSync)
                .environmentObject(session)
        }
        .fullScreenCover(isPresented: $showingPresentation) {
            ATHLTHStudioPresentationView()
        }
        .sheet(item: $selectedStandaloneWorkout) { workout in
            ATHLTHStudioStandaloneWorkoutDetailView(workoutID: workout.id)
        }
        .sheet(item: $studioUtility) { destination in
            ATHLTHSideMenuUtilitiesView(destination: destination)
        }
        .sheet(item: $studioFeature) { destination in
            ATHLTHSideMenuDeepLinkView(destination: destination)
                .frame(minWidth: 420, minHeight: 520)
        }
        .sheet(isPresented: $showingProfile) {
            // The existing iPhone profile stays unchanged inside a tall,
            // phone-width sheet rather than stretching across the iPad.
            ATHLTHSideMenuDeepLinkView(destination: .profile)
                .frame(width: 430)
                .presentationSizing(.fitted)
                .presentationDetents([.large])
        }
        .onAppear {
            // Scene-local, not shared across windows: Stage Manager windows
            // can keep different destinations without fighting each other.
            let compatibilityLaunch = ProcessInfo.processInfo.arguments
                .contains { $0.hasPrefix("--athlth-compatibility-tab=") }
            if !compatibilityLaunch,
               let restored = ATHLTHStudioDestination(rawValue: savedDestination) {
                selection = restored
            }
            studioPlanSync.switchAccount(
                session.signedIn ? session.profile.userID : nil
            )
            if studioPlanSync.enabled {
                Task { await studioPlanSync.sync(session: session) }
            }
        }
        .onChange(of: session.profile.userID) { _, _ in
            studioPlanSync.switchAccount(
                session.signedIn ? session.profile.userID : nil
            )
        }
        .onChange(of: session.signedIn) { _, signedIn in
            studioPlanSync.switchAccount(signedIn ? session.profile.userID : nil)
        }
        .onChange(of: session.trainingPlans) { _, _ in
            // Saving the local plan remains immediate and independent of
            // network; upload only follows explicit account-scoped consent.
            studioPlanSync.scheduleSync(session: session)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && studioPlanSync.enabled {
                Task { await studioPlanSync.sync(session: session) }
            }
        }
        .onChange(of: selection) { _, destination in
            savedDestination = destination.rawValue
            // Keep Coach and Inbox docked while navigating Studio.
            if destination != .overview { focusedPlanningDate = nil }
            withAnimation(.easeInOut(duration: 0.18)) {
                sidebarVisibility = destination == .planner
                    ? .detailOnly : .all
            }
        }
        .onChange(of: focusedPlanningDate) { _, newDate in
            withAnimation(.easeInOut(duration: 0.18)) {
                sidebarVisibility = newDate != nil ? .detailOnly :
                    selection == .planner ? .detailOnly : .all
            }
        }
        .inspector(isPresented: $showingInspector) {
            if inspectorShowsCoach {
                RecoveryCoachInboxDestinationView()
                    .inspectorColumnWidth(min: 300, ideal: 370, max: 480)
            } else if inspectorShowsInbox {
                NavigationStack {
                    MessageInboxDestinationView()
                }
                .inspectorColumnWidth(min: 320, ideal: 390, max: 480)
            } else if let selectedWorkout {
                ATHLTHStudioWorkoutInspectionView(workout: selectedWorkout)
                    .inspectorColumnWidth(min: 270, ideal: 320, max: 400)
            }
        }
    }

    @ViewBuilder
    private var studioDetail: some View {
        if selection == .planner {
            HStack(spacing: 0) {
                compactPlannerRail
                    .frame(width: 62)

                ATHLTHStudioStyle.outline.opacity(0.55)
                    .frame(width: 1)

                page
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            page
        }
    }

    /// Studio owns only navigation chrome. Every destination continues to
    /// use its original shared iPhone/iPad stores and feature implementation.
    private var compactPlannerRail: some View {
        VStack(spacing: 11) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(gold)
                .padding(.top, 12)
                .accessibilityHidden(true)

            ScrollView {
                VStack(spacing: 7) {
                    ForEach(ATHLTHStudioDestination.allCases) { destination in
                        Button {
                            selection = destination
                        } label: {
                            Image(systemName: destination.symbol)
                                .font(.system(size: 18, weight: selection == destination
                                    ? .semibold : .regular))
                                .foregroundStyle(selection == destination
                                    ? ink : ink.opacity(0.62))
                                .frame(width: 44, height: 44)
                                .background {
                                    if selection == destination {
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(.white)
                                    }
                                }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(destination.label)
                        .accessibilityLabel(destination.label)
                        .accessibilityAddTraits(
                            selection == destination ? .isSelected : []
                        )
                    }
                }
                .frame(maxWidth: .infinity)

                Menu {
                    Button {
                        openPersonalLibrary(.exercises)
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "My exercises", norwegian: "Mine øvelser"
                        ), systemImage: "dumbbell")
                    }
                    Button {
                        openPersonalLibrary(.routes)
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "My routes", norwegian: "Mine ruter"
                        ), systemImage: "map")
                    }
                    Button {
                        openPersonalLibrary(.trainingPlans)
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "My training plans", norwegian: "Mine treningsplaner"
                        ), systemImage: "calendar")
                    }
                    Button {
                        openPersonalLibrary(.workouts)
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "My workouts", norwegian: "Mine treningsøkter"
                        ), systemImage: "bookmark")
                    }
                } label: {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 18))
                        .foregroundStyle(ink.opacity(0.7))
                        .frame(width: 44, height: 44)
                }
                .help(ATHLTHLocalization.choose(
                    english: "My training library", norwegian: "Mitt treningsbibliotek"
                ))
                .accessibilityIdentifier("athlth-ipad-library-rail")
            }
        }
        .background(canvas)
    }

    /// The iPad sidebar follows the same information architecture as the
    /// iPhone Home menu, but opens the real iPad destinations and inspectors.
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ATHLTH")
                    .font(.system(size: 24, weight: .semibold))
                    .tracking(3)
                    .foregroundStyle(ink)
                Text("STUDIO")
                    .font(.caption.weight(.medium))
                    .tracking(2)
                    .foregroundStyle(gold)
            }
            .padding(.horizontal, 22)
            .padding(.top, 26)
            .padding(.bottom, 17)

            sidebarProfileRow
                .padding(.horizontal, 11)
                .padding(.bottom, 14)

            Divider().padding(.horizontal, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    sidebarAction(
                        ATHLTHLocalization.choose(english: "Home", norwegian: "Hjem"),
                        symbol: "house",
                        selected: selection == .overview
                    ) { selection = .overview }

                    sidebarAction(
                        ATHLTHLocalization.choose(english: "Inbox", norwegian: "Innboks"),
                        symbol: "envelope"
                    ) {
                        inspectorShowsCoach = false
                        inspectorShowsInbox = true
                        showingInspector = true
                    }
                    sidebarAction(
                        ATHLTHLocalization.choose(english: "Notifications", norwegian: "Varsler"),
                        symbol: "bell"
                    ) { studioUtility = .notifications }

                    sidebarAction(
                        ATHLTHLocalization.choose(english: "Search", norwegian: "Søk"),
                        symbol: "magnifyingglass"
                    ) { studioUtility = .search }

                    Divider().padding(.vertical, 7).padding(.horizontal, 10)

                    sidebarAction(
                        ATHLTHLocalization.choose(english: "Plan Studio", norwegian: "Plan Studio"),
                        symbol: "calendar"
                    ) { selection = .planner }

                    trainingLibraryShortcut

                    sidebarAction(
                        ATHLTHLocalization.choose(english: "Train Together", norwegian: "Tren sammen"),
                        symbol: "person.2"
                    ) { studioFeature = .trainTogether }

                    sidebarAction("Ghost Race", symbol: "flag.checkered") {
                        trainRequest = .ghost
                        showingTrain = true
                    }

                    sidebarAction("Arena", symbol: "trophy") {
                        studioFeature = .arena
                    }

                    sidebarAction(
                        ATHLTHLocalization.choose(english: "Clubs", norwegian: "Klubber"),
                        symbol: "person.3"
                    ) { studioFeature = .clubs }

                    Divider().padding(.vertical, 7).padding(.horizontal, 10)

                    sidebarAction(
                        ATHLTHLocalization.choose(english: "Progress", norwegian: "Fremgang"),
                        symbol: "chart.xyaxis.line",
                        selected: selection == .insights
                    ) { selection = .insights }

                    sidebarAction("ATHLTH Coach", symbol: "sparkles",
                                  selected: selection == .coach) {
                        selection = .coach
                    }

                    sidebarAction(
                        ATHLTHLocalization.choose(english: "Profile", norwegian: "Profil"),
                        symbol: "person.crop.circle"
                    ) { showingProfile = true }

                    Menu {
                        Button {
                            selection = .history
                        } label: {
                            Label(ATHLTHStudioDestination.history.label,
                                  systemImage: "clock.arrow.circlepath")
                        }
                        Button {
                            selection = .explore
                        } label: {
                            Label(ATHLTHStudioDestination.explore.label,
                                  systemImage: "map")
                        }
                        Button {
                            selection = .community
                        } label: {
                            Label(ATHLTHStudioDestination.community.label,
                                  systemImage: "person.3")
                        }
                        Button {
                            studioFeature = .exerciseProgress
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Exercise progression",
                                    norwegian: "Øvelsesfremdrift"
                                ),
                                systemImage: "chart.bar"
                            )
                        }
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(english: "More", norwegian: "Mer"),
                            systemImage: "ellipsis.circle"
                        )
                        .foregroundStyle(ink)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.horizontal, 15)
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 10)
            }
            .scrollIndicators(.hidden)

            Divider().padding(.horizontal, 18)

            sidebarAction(
                ATHLTHLocalization.choose(english: "Settings", norwegian: "Innstillinger"),
                symbol: "gearshape",
                selected: selection == .settings
            ) { selection = .settings }
                .padding(.horizontal, 11)
                .padding(.vertical, 12)
        }
        .background(canvas)
    }

    private func sidebarAction(
        _ title: String,
        symbol: String,
        selected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 17))
                    .frame(width: 24)
                Text(title)
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? ink : ink.opacity(0.78))
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 11)
                        .fill(Color.white)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var sidebarProfileRow: some View {
        Button {
            showingProfile = true
        } label: {
            HStack(spacing: 11) {
                Group {
                    if let avatarURL = session.profile.avatarURL {
                        ATHLTHStorageImage(url: avatarURL, maxPixelSize: 140) { phase in
                            if case .success(let image) = phase {
                                image.resizable().scaledToFill()
                            } else {
                                profileFallback
                            }
                        }
                    } else {
                        profileFallback
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.profile.displayName.isEmpty
                         ? "ATHLTH" : session.profile.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                    Text(session.profile.username.isEmpty
                         ? ATHLTHLocalization.choose(english: "My profile", norwegian: "Min profil")
                         : "@\(session.profile.username)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("athlth-ipad-profile-footer")
    }

    private var profileFallback: some View {
        Circle()
            .fill(ATHLTHStudioStyle.paper)
            .overlay {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(gold)
            }
    }

    private var trainingLibraryShortcut: some View {
        VStack(spacing: 1) {
            HStack(spacing: 0) {
                Button {
                    trainRequest = .library
                    showingTrain = true
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Training library", norwegian: "Treningsbibliotek"
                    ), systemImage: "books.vertical")
                        .font(.subheadline)
                        .foregroundStyle(ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        libraryExpanded.toggle()
                    }
                } label: {
                    Image(systemName: libraryExpanded ? "chevron.up" : "chevron.down")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Expand personal library",
                    norwegian: "Vis snarveier til mitt bibliotek"
                ))
                .accessibilityIdentifier("athlth-ipad-library-expand")
            }
            if libraryExpanded {
                libraryLink(.exercises, "My exercises", "Mine øvelser", symbol: "dumbbell")
                libraryLink(.routes, "My routes", "Mine ruter", symbol: "map")
                libraryLink(.trainingPlans, "My training plans", "Mine treningsplaner", symbol: "calendar")
                libraryLink(.workouts, "My workouts", "Mine treningsøkter", symbol: "bookmark")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 5)
    }

    private func libraryLink(
        _ section: ATHLTHPersonalLibrarySection,
        _ english: String,
        _ norwegian: String,
        symbol: String
    ) -> some View {
        Button {
            openPersonalLibrary(section)
        } label: {
            Label(ATHLTHLocalization.choose(english: english, norwegian: norwegian),
                  systemImage: symbol)
                .font(.subheadline)
                .foregroundStyle(ink.opacity(0.77))
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
    }

    private func openPersonalLibrary(_ section: ATHLTHPersonalLibrarySection) {
        trainRequest = .personalLibrary(section)
        showingTrain = true
    }

    @ViewBuilder
    private var page: some View {
        switch selection {
        case .overview:
            ATHLTHStudioEditorialDashboardView(
                onInspect: inspect,
                onOpenPlanner: { selection = .planner },
                onOpenInsights: { selection = .insights },
                onOpenHistory: { selection = .history },
                onOpenSettings: { selection = .settings },
                onOpenLibrary: {
                    trainRequest = .library
                    showingTrain = true
                },
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
                },
                onStartWorkout: { entry in
                    if let planID = entry.planID {
                        trainRequest = .startPlannedWorkout(
                            planID: planID, workoutID: entry.workout.id
                        )
                        showingTrain = true
                    } else {
                        selectedStandaloneWorkout = entry.workout
                    }
                },
                onSendToWatch: { entry in
                    guard let planID = entry.planID else { return }
                    trainRequest = .sendPlannedWorkoutToWatch(
                        planID: planID, workoutID: entry.workout.id
                    )
                    showingTrain = true
                },
                onStartAfter: { entry, seconds in
                    guard let planID = entry.planID else { return }
                    trainRequest = .startPlannedWorkoutAfter(
                        planID: planID, workoutID: entry.workout.id,
                        seconds: seconds
                    )
                    showingTrain = true
                },
                onOpenCoach: {
                    inspectorShowsCoach = true
                    inspectorShowsInbox = false
                    showingInspector = true
                },
                focusedPlanningDate: $focusedPlanningDate
            )
        case .planner:
            ATHLTHStudioPlannerView(
                onStartWorkout: { planID, workoutID in
                    trainRequest = .startPlannedWorkout(
                        planID: planID, workoutID: workoutID
                    )
                    showingTrain = true
                },
                onSendToWatch: { planID, workoutID in
                    trainRequest = .sendPlannedWorkoutToWatch(
                        planID: planID, workoutID: workoutID
                    )
                    showingTrain = true
                },
                onStartAfter: { planID, workoutID, seconds in
                    trainRequest = .startPlannedWorkoutAfter(
                        planID: planID, workoutID: workoutID, seconds: seconds
                    )
                    showingTrain = true
                },
                onOpenCoach: {
                    inspectorShowsCoach = true
                    inspectorShowsInbox = false
                    showingInspector = true
                }
            )
        case .insights:
            ATHLTHStudioInsightsView()
        case .history:
            ATHLTHStudioHistoryView(onInspect: inspect)
        case .explore:
            ATHLTHStudioRouteWorkspaceView()
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
        inspectorShowsInbox = false
        showingInspector = true
    }
}

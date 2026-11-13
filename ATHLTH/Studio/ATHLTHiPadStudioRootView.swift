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

/// Intent thresholds for the iPad message-panel grip and header.
/// The conversation area never installs these gestures: it must retain
/// exactly the same horizontal scroll, attachments and interactions as iPhone.
enum ATHLTHStudioInboxPanelGesturePolicy {
    static func shouldOpen(translation: CGSize) -> Bool {
        translation.width <= -30 &&
            abs(translation.height) <= abs(translation.width) * 0.55
    }

    static func shouldClose(translation: CGSize) -> Bool {
        translation.width >= 85 &&
            abs(translation.height) <= abs(translation.width) * 0.55
    }
}

/// Only the inbox controls observe MessagingStore. A message arriving should
/// not cause Studio's entire navigation tree to observe messaging changes.
private struct ATHLTHStudioInboxToolbarButton: View {
    @EnvironmentObject private var messaging: MessagingStore
    let toggle: () -> Void

    private var unread: Int {
        max(0, messaging.unreadCount + messaging.messageRequestCount)
    }

    var body: some View {
        Button(action: toggle) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 42, height: 42)
                if unread > 0 {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                        .offset(x: -3, y: 3)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel(ATHLTHLocalization.choose(
            english: "Inbox", norwegian: "Innboks"
        ))
        .accessibilityValue(unread > 0
            ? ATHLTHLocalization.choose(
                english: "\(unread) unread",
                norwegian: "\(unread) uleste"
            )
            : ATHLTHLocalization.choose(
                english: "No unread messages",
                norwegian: "Ingen uleste meldinger"
            )
        )
        .help(ATHLTHLocalization.choose(
            english: "Open or close Inbox", norwegian: "Åpne eller lukk innboksen"
        ))
        .accessibilityIdentifier("athlth-ipad-inbox-panel")
        .keyboardShortcut("m", modifiers: [.command, .shift])
    }
}

private struct ATHLTHStudioInboxUnreadPill: View {
    @EnvironmentObject private var messaging: MessagingStore
    let ink: Color
    let gold: Color

    private var unread: Int {
        max(0, messaging.unreadCount + messaging.messageRequestCount)
    }

    var body: some View {
        if unread > 0 {
            Text(unread > 99 ? "99+" : "\(unread)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ink)
                .padding(.horizontal, 9)
                .frame(minHeight: 25)
                .background(gold.opacity(0.12), in: Capsule())
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "\(unread) unread messages",
                    norwegian: "\(unread) uleste meldinger"
                ))
        }
    }
}

struct ATHLTHiPadStudioRootView: View {
    @EnvironmentObject private var session: AppSessionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMessagePanelMotion
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var studioPlanSync: ATHLTHStudioPlanSyncStore
    @EnvironmentObject private var goalStore: GoalStore
    @EnvironmentObject private var goalAccountSync: ATHLTHGoalAccountSyncStore
    @SceneStorage("athlth.studio.selectedDestination")
    private var savedDestination = ATHLTHStudioDestination.overview.rawValue
    @State private var selection: ATHLTHStudioDestination = .overview
    @State private var selectedWorkout: WorkoutSummary?
    @State private var inspectedWeekDate: Date?
    @State private var showingWorkoutDetail = false
    @State private var pendingWeekTrainLaunch = false
    @State private var pendingWeekStandaloneWorkout: PlannedSession?
    @State private var selectedHomeWeekDate: Date = .now
    /// Side-menu libraries live in the Studio detail column.
    @State private var libraryPage: ATHLTHStudioLibraryPage?
    /// Reset pushed detail cards when switching sidebar destinations.
    @State private var detailNavigationPath = NavigationPath()
    // Some destination-based links do not round-trip through NavigationPath.
    // Recreating the detail stack when a sidebar item is tapped guarantees
    // that a deep Settings/Widgets page cannot remain above the new destination.
    @State private var detailNavigationIdentity = UUID()
    /// The right inspector is for Messages only; Activity remains in Notifications.
    @State private var showingInspector = false
    /// Secondary Studio tools also replace the detail column, not modal sheets.
    @State private var sidebarPage: ATHLTHSideMenuDestination?
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

    private var messagePanelAnimation: Animation? {
        reduceMessagePanelMotion ? nil : .easeInOut(duration: 0.20)
    }

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
        let libraryArgument = ProcessInfo.processInfo.arguments.first {
            $0.hasPrefix("--athlth-compatibility-library=")
        }
        let libraryPreview = libraryArgument.flatMap {
            ATHLTHStudioLibraryPage(
                rawValue: String(
                    $0.dropFirst("--athlth-compatibility-library=".count)
                )
            )
        }
        // Exercise the real Profile destination in iPad crash regression smoke.
        let sidebarArgument = ProcessInfo.processInfo.arguments.first {
            $0.hasPrefix("--athlth-compatibility-sidebar=")
        }
        let sidebarPreview = sidebarArgument.flatMap {
            ATHLTHSideMenuDestination(rawValue: String(
                $0.dropFirst("--athlth-compatibility-sidebar=".count)
            ))
        }
        _selection = State(initialValue: initial)
        _libraryPage = State(initialValue: libraryPreview)
        _sidebarPage = State(initialValue: sidebarPreview)
        // Plan Studio starts with its sidebar fully hidden; library pages
        // keep their sidebar visible in both preview and normal navigation.
        _sidebarVisibility = State(initialValue:
            libraryPreview == nil && initial == .planner ? .detailOnly : .all)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 244, max: 280)
        } detail: {
            NavigationStack(path: $detailNavigationPath) {
                studioDetail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(canvas.ignoresSafeArea())
                    .overlay(alignment: .trailing) {
                        if selection == .overview && !showingInspector &&
                            libraryPage == nil && sidebarPage == nil {
                            Button {
                                openMessageHub()
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(gold)
                                    .frame(width: 26, height: 64)
                                    .background(canvas, in: RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12)
                                        .stroke(gold.opacity(0.3)))
                                    // Preserve the slim visual grip while
                                    // offering a full-size touch target.
                                    .frame(width: 44, height: 72)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                ATHLTHLocalization.choose(
                                    english: "Open Inbox",
                                    norwegian: "Åpne innboks"
                                )
                            )
                            .accessibilityIdentifier("athlth-ipad-message-edge")
                            .accessibilityHint(ATHLTHLocalization.choose(
                                english: "Tap or swipe left on this handle to open Inbox",
                                norwegian: "Trykk eller sveip mot venstre på håndtaket for å åpne Innboks"
                            ))
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 15)
                                    .onEnded { value in
                                        if ATHLTHStudioInboxPanelGesturePolicy.shouldOpen(
                                            translation: value.translation
                                        ) {
                                            openMessageHub()
                                        }
                                    }
                            )
                        }
                    }
                    // Overview owns its compact title/metrics inside the
                    // content. Avoid the duplicate large "Overview" title
                    // that previously consumed substantial iPad space.
                    .navigationTitle(
                        libraryPage?.title ??
                            (sidebarPage != nil ? "" :
                                (selection == .overview ? "" : selection.label))
                    )
                    .navigationBarTitleDisplayMode(.inline)
                    // Keep the Overview scroll edge clean: a visible bar
                    // previously rendered as an empty translucent title tile.
                    .toolbarBackground(canvas, for: .navigationBar)
                    .toolbarBackground(
                        selection == .overview && libraryPage == nil
                            && sidebarPage == nil ? .hidden : .visible,
                        for: .navigationBar
                    )
                    .toolbar(removing: .sidebarToggle)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                withAnimation { sidebarVisibility = sidebarVisibility == .detailOnly ? .all : .detailOnly }
                            } label: { Image(systemName: "line.3.horizontal") }
                            .accessibilityLabel(ATHLTHLocalization.choose(english: "Side menu", norwegian: "Sidemeny"))
                        }
                        // NavigationSplitView supplies the native sidebar
                        // visibility control. Do not draw a second identical
                        // leading button in the detail NavigationStack.
                        ToolbarItem(placement: .topBarTrailing) {
                            ATHLTHStudioInboxToolbarButton {
                                if showingInspector {
                                    withAnimation(messagePanelAnimation) {
                                        showingInspector = false
                                    }
                                } else {
                                    openMessageHub()
                                }
                            }
                        }
                    }
            }
            .id(detailNavigationIdentity)
        }
        .navigationSplitViewStyle(.balanced)
        // A single root-level, read-only full-screen spectator handles both
        // running and strength. Do not display a second legacy floating card.
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
        // Keep goal sync live while Studio is foregrounded, as on iPhone.
        .task(id: "\(session.profile.userID.uuidString)|\(session.signedIn)|\(String(describing: scenePhase))") {
            guard session.signedIn, scenePhase == .active else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(20)) }
                catch { return }
                guard !Task.isCancelled, session.signedIn, scenePhase == .active else { return }
                await goalAccountSync.sync(session: session, goals: goalStore)
            }
        }
        .onAppear {
            // Scene-local, not shared across windows: Stage Manager windows
            // can keep different destinations without fighting each other.
            let compatibilityLaunch = ProcessInfo.processInfo.arguments
                .contains {
                    $0.hasPrefix("--athlth-compatibility-tab=") ||
                        $0.hasPrefix("--athlth-compatibility-library=") ||
                        $0.hasPrefix("--athlth-compatibility-sidebar=")
                }
            if !compatibilityLaunch,
               let restored = ATHLTHStudioDestination(rawValue: savedDestination) {
                selection = restored
            }
            studioPlanSync.switchAccount(
                session.signedIn ? session.profile.userID : nil
            )
            goalAccountSync.switchAccount(
                session.signedIn ? session.profile.userID : nil
            )
            goalAccountSync.scheduleSync(session: session, goals: goalStore)
            if studioPlanSync.enabled {
                Task { await studioPlanSync.sync(session: session) }
            }
        }
        .onChange(of: session.profile.userID) { _, _ in
            showingInspector = false
            studioPlanSync.switchAccount(
                session.signedIn ? session.profile.userID : nil
            )
            goalAccountSync.switchAccount(
                session.signedIn ? session.profile.userID : nil
            )
            goalAccountSync.scheduleSync(session: session, goals: goalStore)
        }
        .onChange(of: session.signedIn) { _, signedIn in
            if !signedIn { showingInspector = false }
            studioPlanSync.switchAccount(signedIn ? session.profile.userID : nil)
            goalAccountSync.switchAccount(signedIn ? session.profile.userID : nil)
            if signedIn {
                goalAccountSync.scheduleSync(session: session, goals: goalStore)
            }
        }
        .onChange(of: goalStore.goals) { _, _ in
            goalAccountSync.scheduleSync(session: session, goals: goalStore)
        }
        .onReceive(NotificationCenter.default.publisher(
            for: Notification.Name("athlth.goalDocumentDidChange")
        )) { notification in
            guard let accountID = notification.userInfo?["accountID"] as? UUID,
                  session.signedIn, accountID == session.profile.userID else { return }
            goalAccountSync.scheduleSync(session: session, goals: goalStore)
        }
        .onReceive(NotificationCenter.default.publisher(
            for: Notification.Name("athlth.privateMeasurementsDidChange")
        )) { notification in
            guard let accountID = notification.userInfo?["accountID"] as? UUID,
                  session.signedIn, accountID == session.profile.userID else { return }
            goalAccountSync.scheduleSync(session: session, goals: goalStore)
        }
        .onChange(of: session.trainingPlans) { _, _ in
            // Saving the local plan remains immediate and independent of
            // network; account sync preserves legacy opt-outs and conflict checks.
            studioPlanSync.scheduleSync(session: session)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                goalAccountSync.scheduleSync(session: session, goals: goalStore)
                if studioPlanSync.enabled {
                    Task { await studioPlanSync.sync(session: session) }
                }
            }
        }
        .onChange(of: selection) { _, destination in
            clearWeekInspectorIfNeeded()
            // Switching to a main Studio destination clears the inline
            // library selection without dismissing any modal.
            libraryPage = nil
            sidebarPage = nil
            resetDetailNavigation()
            savedDestination = destination.rawValue
            // Inbox stays docked until the user closes it; Coach is a page.
            if destination != .overview { focusedPlanningDate = nil }
            withAnimation(.easeInOut(duration: 0.18)) {
                sidebarVisibility = destination == .planner
                    ? .detailOnly : .all
            }
        }
        .onChange(of: selectedHomeWeekDate) { _, date in
            // Keep the selected day accurate if the week changes while
            // its dedicated detail sheet is displayed.
            if inspectedWeekDate != nil && showingWorkoutDetail &&
                selectedWorkout == nil {
                inspectedWeekDate = Calendar.current.startOfDay(for: date)
            }
        }
        .onChange(of: focusedPlanningDate) { _, newDate in
            if newDate != nil {
                clearWeekInspectorIfNeeded()
                showingInspector = false
            }
            withAnimation(.easeInOut(duration: 0.18)) {
                sidebarVisibility = (libraryPage != nil || sidebarPage != nil)
                    ? .all :
                    (newDate != nil || selection == .planner) ? .detailOnly : .all
            }
        }
        .inspector(isPresented: $showingInspector) {
            // Reuse the actual iPhone inbox and DirectMessageThreadView.
            // Do not create a separate iPad conversation design or composer.
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Inbox panel", norwegian: "Innbokspanel"
                        ),
                        systemImage: "bubble.left.and.bubble.right"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ink)
                    .labelStyle(.titleAndIcon)
                    Spacer(minLength: 4)
                    ATHLTHStudioInboxUnreadPill(ink: ink, gold: gold)
                    inspectorCollapseButton
                }
                .padding(.horizontal, 17)
                .padding(.top, 8)
                .padding(.bottom, 7)
                .contentShape(Rectangle())
                // Only the panel chrome responds to a dismiss swipe. The
                // unchanged iPhone conversation keeps its own gestures.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 24)
                        .onEnded { value in
                            if ATHLTHStudioInboxPanelGesturePolicy.shouldClose(
                                translation: value.translation
                            ) {
                                withAnimation(messagePanelAnimation) {
                                    showingInspector = false
                                }
                            }
                        }
                )
                Rectangle()
                    .fill(gold.opacity(0.18))
                    .frame(height: 1)
                    .padding(.horizontal, 17)
                NavigationStack {
                    MessageInboxDestinationView()
                }
                // Ensure a previous account's open thread cannot be reused.
                .id(session.profile.userID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(canvas)
            .inspectorColumnWidth(min: 340, ideal: 420, max: 510)
            // Deliberately no inspector-wide swipe recognizer: it would
            // compete with gestures within the unchanged iPhone thread.
        }
        .sheet(isPresented: $showingWorkoutDetail, onDismiss: {
            inspectedWeekDate = nil
            selectedWorkout = nil
            // Launch a selected workout only after the detail sheet has
            // fully dismissed, avoiding competing modal presentations.
            if pendingWeekTrainLaunch {
                pendingWeekTrainLaunch = false
                showingTrain = true
            } else if let standalone = pendingWeekStandaloneWorkout {
                pendingWeekStandaloneWorkout = nil
                selectedStandaloneWorkout = standalone
            }
        }) {
            // Week days and recorded workouts remain accessible without
            // occupying the Inbox-only right panel.
            NavigationStack {
                VStack(spacing: 0) {
                    HStack {
                        if selectedWorkout != nil && inspectedWeekDate != nil {
                            Button {
                                selectedWorkout = nil
                            } label: {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english: "Back to selected day",
                                        norwegian: "Tilbake til valgt dag"
                                    ),
                                    systemImage: "chevron.left"
                                )
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(ink)
                        }
                        Spacer(minLength: 0)
                        Button {
                            showingWorkoutDetail = false
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Close", norwegian: "Lukk"
                                ),
                                systemImage: "xmark"
                            )
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(ink)
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)

                    Divider().opacity(0.35)

                    if let selectedWorkout {
                        ATHLTHStudioWorkoutInspectionView(workout: selectedWorkout)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let inspectedWeekDate {
                        ATHLTHStudioWeekDayInspectorView(
                            date: inspectedWeekDate,
                            onOpenWorkout: { openWeekWorkout($0, start: false) },
                            onStartWorkout: { openWeekWorkout($0, start: true) },
                            onSendToWatch: sendWeekWorkoutToWatch,
                            onInspectRecorded: inspectRecordedFromWeek,
                            onPlanWorkout: planFromWeekDay
                        )
                        .id(Calendar.current.startOfDay(for: inspectedWeekDate))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .background(canvas.ignoresSafeArea())
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private func openMessageHub() {
        withAnimation(messagePanelAnimation) {
            showingInspector = true
        }
    }

    /// Compact collapse affordance; the header remains visible at all widths.
    private var inspectorCollapseButton: some View {
        Button {
            withAnimation(messagePanelAnimation) {
                showingInspector = false
            }
        } label: {
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ink)
                .frame(width: 42, height: 42)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(gold.opacity(0.22)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ATHLTHLocalization.choose(
            english: "Close messages",
            norwegian: "Lukk meldinger"
        ))
        .accessibilityIdentifier("athlth-ipad-hide-inspector")
    }

    @ViewBuilder
    private var studioDetail: some View {
        if let libraryPage {
            ATHLTHiPadLibraryWorkspaceView(
                page: libraryPage,
                onSelect: openLibrary,
                onBack: { returnFromSidebarPage() }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let sidebarPage {
            ATHLTHiPadSidebarPageView(
                destination: sidebarPage,
                onBack: { returnFromSidebarPage() }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Plan Studio uses the full detail width. The native sidebar
            // control switches between fully hidden and the regular sidebar.
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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

            // Keep the top area dedicated to ATHLTH navigation.
            // The signed-in athlete profile is pinned below Settings,
            // matching the iPhone side menu.
            Divider().padding(.horizontal, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    sidebarAction(
                        ATHLTHLocalization.choose(english: "Home", norwegian: "Hjem"),
                        symbol: "house",
                        selected: selection == .overview && libraryPage == nil &&
                            sidebarPage == nil
                    ) { openStudio(.overview) }

                    sidebarAction(
                        ATHLTHLocalization.choose(english: "Notifications", norwegian: "Varsler"),
                        symbol: "bell",
                        selected: sidebarPage == .notifications
                    ) { openSidebarPage(.notifications) }

                    sidebarAction(
                        ATHLTHLocalization.choose(english: "Search", norwegian: "Søk"),
                        symbol: "magnifyingglass",
                        selected: sidebarPage == .search
                    ) { openSidebarPage(.search) }

                    Divider().padding(.vertical, 7).padding(.horizontal, 10)

                    sidebarAction(
                        ATHLTHLocalization.choose(english: "Plan Studio", norwegian: "Plan Studio"),
                        symbol: "calendar",
                        selected: selection == .planner && libraryPage == nil &&
                            sidebarPage == nil
                    ) { openStudio(.planner) }

                    trainingLibraryShortcut

                    sidebarAction(
                        ATHLTHLocalization.choose(english: "Train Together", norwegian: "Tren sammen"),
                        symbol: "person.2",
                        selected: sidebarPage == .trainTogether
                    ) { openSidebarPage(.trainTogether) }

                    sidebarAction(
                        "Ghost Race", symbol: "flag.checkered",
                        selected: sidebarPage == .ghostRace
                    ) {
                        openSidebarPage(.ghostRace)
                    }

                    sidebarAction(
                        "Arena", symbol: "trophy",
                        selected: sidebarPage == .arena
                    ) {
                        openSidebarPage(.arena)
                    }

                    sidebarAction(
                        ATHLTHLocalization.choose(english: "Clubs", norwegian: "Klubber"),
                        symbol: "person.3",
                        selected: sidebarPage == .clubs
                    ) { openSidebarPage(.clubs) }
                    .contextMenu {
                        Button {
                            openStudio(.community)
                        } label: {
                            Label(ATHLTHLocalization.choose(
                                english: "Community", norwegian: "Fellesskap"
                            ), systemImage: "person.3")
                        }
                    }

                    Divider().padding(.vertical, 7).padding(.horizontal, 10)

                    sidebarAction(
                        ATHLTHLocalization.choose(english: "Progress", norwegian: "Fremgang"),
                        symbol: "chart.xyaxis.line",
                        selected: selection == .insights && libraryPage == nil &&
                            sidebarPage == nil
                    ) { openStudio(.insights) }
                    .contextMenu {
                        Button {
                            openStudio(.history)
                        } label: {
                            Label(ATHLTHLocalization.choose(
                                english: "Workout history", norwegian: "Treningshistorikk"
                            ), systemImage: "clock.arrow.circlepath")
                        }
                    }

                    sidebarAction("ATHLTH Coach", symbol: "sparkles",
                                  selected: selection == .coach &&
                                       libraryPage == nil && sidebarPage == nil) {
                        openStudio(.coach)
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
                selected: selection == .settings && libraryPage == nil &&
                    sidebarPage == nil
            ) { openStudio(.settings) }
                .contextMenu {
                    Button {
                        showingPlanSync = true
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Account sync", norwegian: "Kontosynkronisering"
                            ), systemImage: "icloud"
                        )
                    }
                    Button {
                        showingPresentation = true
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Presentation mode", norwegian: "Presentasjonsmodus"
                            ), systemImage: "rectangle.on.rectangle"
                        )
                    }
                }
                .padding(.horizontal, 11)
                .padding(.top, 10)
                .padding(.bottom, 8)

            Divider().padding(.horizontal, 18)

            sidebarProfileRow
                .padding(.horizontal, 11)
                .padding(.top, 10)
                .padding(.bottom, 12)
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
            openSidebarPage(.profile)
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

                VStack(alignment: .leading, spacing: 3) {
                    Text(session.profile.displayName.isEmpty
                         ? "ATHLTH" : session.profile.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .multilineTextAlignment(.leading)
                    Text(session.profile.username.isEmpty
                         ? ATHLTHLocalization.choose(english: "My profile", norwegian: "Min profil")
                         : "@\(session.profile.username)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(gold)
                    .frame(width: 28, height: 28)
                    .background(ATHLTHStudioStyle.paper, in: Circle())
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 74)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                sidebarPage == .profile ? ATHLTHPlanDesign.selectedSurface : Color.white,
                in: RoundedRectangle(cornerRadius: 17)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 17)
                    .strokeBorder(gold.opacity(0.19), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .contentShape(RoundedRectangle(cornerRadius: 17))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ATHLTHLocalization.choose(
            english: "Open my ATHLTH profile",
            norwegian: "Åpne ATHLTH-profilen min"
        ))
        .accessibilityAddTraits(sidebarPage == .profile ? .isSelected : [])
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
                    openLibrary(.overview)
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Training library", norwegian: "Treningsbibliotek"
                    ), systemImage: "books.vertical")
                        .font(.subheadline)
                        .foregroundStyle(libraryPage == .overview ? gold : ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("athlth-ipad-training-library-open")

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
                libraryLink(.exercises, "Exercises", "Øvelser", symbol: "dumbbell")
                libraryLink(.routes, "Routes", "Ruter", symbol: "map")
                libraryLink(.trainingPlans, "Training plans", "Treningsplaner", symbol: "calendar")
                libraryLink(.workouts, "Workouts", "Treningsøkter", symbol: "bookmark")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 5)
        .contextMenu {
            Button {
                openStudio(.explore)
            } label: {
                Label(ATHLTHLocalization.choose(
                    english: "Routes & Explore", norwegian: "Ruter og utforsk"
                ), systemImage: "map")
            }
        }
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
                .foregroundStyle(
                    libraryPage == section.studioLibraryPage
                        ? gold : ink.opacity(0.77)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44)
                .background {
                    if libraryPage == section.studioLibraryPage {
                        RoundedRectangle(cornerRadius: 11)
                            .fill(Color.white.opacity(0.92))
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(
            libraryPage == section.studioLibraryPage ? .isSelected : []
        )
        .accessibilityIdentifier(
            "athlth-ipad-sidebar-library-\(section.rawValue)"
        )
    }

    private func resetDetailNavigation() {
        detailNavigationPath = NavigationPath()
        detailNavigationIdentity = UUID()
    }

    private func openLibrary(_ page: ATHLTHStudioLibraryPage) {
        clearWeekInspectorIfNeeded()
        libraryExpanded = true
        focusedPlanningDate = nil
        resetDetailNavigation()
        sidebarPage = nil
        libraryPage = page
        // The selected library replaces the Studio detail page. It never
        // launches the full-screen Train shell.
        withAnimation(.easeInOut(duration: 0.18)) {
            sidebarVisibility = .all
        }
    }

    private func openPersonalLibrary(_ section: ATHLTHPersonalLibrarySection) {
        openLibrary(section.studioLibraryPage)
    }

    private func openSidebarPage(_ destination: ATHLTHSideMenuDestination) {
        clearWeekInspectorIfNeeded()
        focusedPlanningDate = nil
        resetDetailNavigation()
        libraryPage = nil
        sidebarPage = destination
        withAnimation(.easeInOut(duration: 0.18)) {
            sidebarVisibility = .all
        }
    }

    private func returnFromSidebarPage() {
        resetDetailNavigation()
        libraryPage = nil
        sidebarPage = nil
        withAnimation(.easeInOut(duration: 0.18)) {
            sidebarVisibility = selection == .planner ? .detailOnly : .all
        }
    }

    private func openStudio(_ destination: ATHLTHStudioDestination) {
        clearWeekInspectorIfNeeded()
        resetDetailNavigation()
        libraryPage = nil
        sidebarPage = nil
        selection = destination
        withAnimation(.easeInOut(duration: 0.18)) {
            sidebarVisibility = destination == .planner ? .detailOnly : .all
        }
    }

    @ViewBuilder
    private var page: some View {
        switch selection {
        case .overview:
            ATHLTHStudioEditorialDashboardView(
                onInspect: inspect,
                onSelectWeekDay: showWeekDay,
                onOpenPlanner: { openStudio(.planner) },
                onOpenInsights: { openStudio(.insights) },
                onOpenHistory: { openStudio(.history) },
                onOpenSettings: { openStudio(.settings) },
                onOpenLibrary: {
                    openLibrary(.overview)
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
                focusedPlanningDate: $focusedPlanningDate,
                selectedDate: $selectedHomeWeekDate
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
                onOpenCoach: { openStudio(.coach) }
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

    private func clearWeekInspectorIfNeeded() {
        guard inspectedWeekDate != nil || showingWorkoutDetail else { return }
        showingWorkoutDetail = false
        inspectedWeekDate = nil
        selectedWorkout = nil
    }

    private func showWeekDay(_ date: Date) {
        selectedHomeWeekDate = date
        selectedWorkout = nil
        inspectedWeekDate = Calendar.current.startOfDay(for: date)
        showingWorkoutDetail = true
    }

    private func inspectRecordedFromWeek(_ workout: WorkoutSummary) {
        // The detail sheet remains open; back returns to the selected day.
        selectedWorkout = workout
    }

    private func openWeekWorkout(
        _ item: ATHLTHStudioSchedule.Occurrence,
        start: Bool
    ) {
        if let planID = item.planID {
            trainRequest = start
                ? .startPlannedWorkout(
                    planID: planID, workoutID: item.workout.id
                )
                : .workout(
                    planID: planID, workoutID: item.workout.id
                )
            pendingWeekTrainLaunch = true
            showingWorkoutDetail = false
        } else {
            pendingWeekStandaloneWorkout = item.workout
            showingWorkoutDetail = false
        }
    }

    private func sendWeekWorkoutToWatch(
        _ item: ATHLTHStudioSchedule.Occurrence
    ) {
        guard let planID = item.planID else { return }
        trainRequest = .sendPlannedWorkoutToWatch(
            planID: planID, workoutID: item.workout.id
        )
        pendingWeekTrainLaunch = true
        showingWorkoutDetail = false
    }

    private func planFromWeekDay(_ date: Date) {
        showingWorkoutDetail = false
        focusedPlanningDate = Calendar.current.startOfDay(for: date)
    }

    private func inspect(_ workout: WorkoutSummary) {
        inspectedWeekDate = nil
        selectedWorkout = workout
        showingWorkoutDetail = true
    }
}

import Foundation
import Supabase
import SwiftUI

/// A content-first Library for ATHLTH.
/// The Library discovers, creates and organizes reusable training content.
/// It intentionally avoids a 'recently used' feed; the Today tab owns
/// in-progress activity and the Plan tab owns the active training schedule.
struct TrainingLibraryHomeView: View {
    @EnvironmentObject private var favorites: LibraryFavoritesStore
    @EnvironmentObject private var exerciseLibrary: ExerciseLibraryStore
    @EnvironmentObject private var runningLibrary: RunningWorkoutLibraryStore
    @EnvironmentObject private var session: AppSessionStore

    let onStartRunning: (RunningWorkoutTemplate) -> Void
    var onOpenPlan: ((UUID) -> Void)? = nil
    @State private var showingRecoveryRestPlanner = false
    @State private var displayMode: ATHLTHLibraryDisplayMode = .list
    @State private var libraryViewWidth: CGFloat = 390
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let ink = ATHLTHPlanDesign.ink
    private let muted = ATHLTHPlanDesign.secondaryInk
    private let gold = ATHLTHPlanDesign.accentInk
    private let slate = ATHLTHTheme.accentDeep
    private let green = ATHLTHTheme.vitality
    private let lavender = ATHLTHTheme.recoveryBlue

    private var layout: [GridItem] {
        ATHLTHLibraryGridColumns.make(
            mode: displayMode,
            width: libraryViewWidth,
            reservedHorizontalSpace: 0,
            spacing: 11,
            accessibilityText: dynamicTypeSize.isAccessibilitySize
        )
    }

    // Keep the image-led discovery cards large enough for legible titles:
    // unlike saved content, four top-level categories look better as 2 × 2.
    private var categoryLayout: [GridItem] {
        displayMode == .grid
            ? [GridItem(.flexible(), spacing: 11), GridItem(.flexible(), spacing: 11)]
            : [GridItem(.flexible())]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            introduction

            HStack {
                Text(tr("View", "Visning"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(muted)
                Spacer()
                ATHLTHLibraryDisplayPicker(selection: $displayMode)
            }

            exploreSection

            // One shared recovery/rest entry for single sessions and plans.
            ATHLTHRecoveryRestEntryCard {
                showingRecoveryRestPlanner = true
            }

            personalLibrarySection

            // One relevant hint, without fabricated recommendations or
            // additional empty 'recent' and 'recommended' carousels.
            learningHint
        }
        .frame(maxWidth: 720, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
            libraryViewWidth = width
        }
        .buttonStyle(.plain)
        .task {
            await favorites.refresh()
        }
        .onAppear {
            displayMode = .load(userID: session.profile.userID)
        }
        .onChange(of: session.profile.userID) { _, userID in
            displayMode = .load(userID: userID)
        }
        .onChange(of: displayMode) { _, mode in
            mode.save(userID: session.profile.userID)
        }
        .sheet(isPresented: $showingRecoveryRestPlanner) {
            ATHLTHRecoveryRestPlanningSheet()
                .presentationDetents([.large])
        }
    }

    private var introduction: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { geometry in
                Image("GoalMountain")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            }
            LinearGradient(
                colors: [.white.opacity(0.96), .white.opacity(0.72), .white.opacity(0.08)],
                startPoint: .leading,
                endPoint: .trailing
            )
            VStack(alignment: .leading, spacing: 7) {
                ATHLTHBrandMark(size: .compact)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(tr("Explore", "UTFORSK").uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(2)
                    .foregroundStyle(gold)
                    .padding(.top, 7)
                Text(tr("Training library", "Treningsbiblioteket"))
                    .font(.system(size: 27, weight: .semibold, design: .serif))
                    .foregroundStyle(ink)
                Text(tr(
                    "Discover plans, workouts, exercises and routes.",
                    "Finn treningsplaner, økter, øvelser og ruter."
                ))
                .font(.subheadline)
                .foregroundStyle(muted)
            }
            .padding(18)
        }
        .frame(height: 185)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var exploreSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading(
                tr("DISCOVER", "UTFORSK"),
                title: tr("Explore the library", "Utforsk biblioteket"),
                detail: tr("Ready-made content and exercises for every level.",
                           "Ferdig innhold og øvelser for alle nivåer.")
            )

            LazyVGrid(columns: categoryLayout, spacing: 11) {
                NavigationLink {
                    TrainingPlanLibraryView()
                } label: {
                    LibraryHubCategoryTile(
                        title: tr("Training plans", "Treningsplaner"),
                        detail: tr("Find a complete plan", "Finn en ferdig plan"),
                        symbol: "square.stack.3d.up.fill",
                        artwork: "GoalProgress",
                        tint: gold,
                        compact: displayMode == .list
                    )
                }

                NavigationLink {
                    WorkoutTemplateLibraryView(onStartRunning: onStartRunning)
                } label: {
                    LibraryHubCategoryTile(
                        title: tr("Workouts", "Treningsøkter"),
                        detail: tr("Strength, running and more",
                                   "Styrke, løping og mer"),
                        symbol: "dumbbell.fill",
                        artwork: "StrengthQuickHero",
                        tint: lavender,
                        compact: displayMode == .list
                    )
                }

                NavigationLink {
                    ExerciseLibraryView(source: .library)
                } label: {
                    LibraryHubCategoryTile(
                        title: tr("Exercises", "Øvelser"),
                        detail: tr("Search by muscle and equipment",
                                   "Søk på muskel og utstyr"),
                        symbol: "figure.strengthtraining.traditional",
                        artwork: "GoalStrength",
                        tint: slate,
                        compact: displayMode == .list
                    )
                }

                NavigationLink {
                    RouteLibraryListView(source: .database)
                } label: {
                    LibraryHubCategoryTile(
                        title: tr("Routes", "Ruter"),
                        detail: tr("Find a route to explore",
                                   "Finn en ny tur eller løperute"),
                        symbol: "map.fill",
                        artwork: "GoalAdventure",
                        tint: green,
                        compact: displayMode == .list
                    )
                }
            }
        }
    }

    private var personalLibrarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading(
                tr("YOUR COLLECTION", "DITT INNHOLD"),
                title: tr("My library", "Mitt bibliotek"),
                detail: tr("Everything you have created and saved.",
                           "Alt du har opprettet og lagret.")
            )
            LazyVGrid(
                columns: displayMode == .grid
                    ? layout : [GridItem(.flexible())],
                spacing: displayMode == .grid ? 11 : 0
            ) {
                NavigationLink {
                    MyTrainingPlansLibraryView(onOpenPlan: onOpenPlan)
                } label: {
                    LibraryHubCollectionRow(
                        title: tr("My training plans", "Mine treningsplaner"),
                        detail: tr("Created and scheduled", "Opprettede og planlagte"),
                        symbol: "calendar",
                        tint: gold,
                        count: session.trainingPlans.count,
                        grid: displayMode == .grid
                    )
                }
                if displayMode == .list { libraryDivider }
                NavigationLink {
                    LibrarySavedWorkoutsHubView(
                        onStartRunning: onStartRunning
                    )
                } label: {
                    LibraryHubCollectionRow(
                        title: tr("My workouts", "Mine økter"),
                        detail: tr("Strength, hybrid and running",
                                   "Styrke, kombinert og løping"),
                        symbol: "bookmark",
                        tint: slate,
                        count: session.savedWorkoutTemplates.count
                            + runningLibrary.customTemplates.count,
                        grid: displayMode == .grid
                    )
                }
                if displayMode == .list { libraryDivider }
                NavigationLink {
                    ExerciseLibraryView(source: .mine)
                } label: {
                    LibraryHubCollectionRow(
                        title: tr("My exercises", "Mine øvelser"),
                        detail: tr("Custom movements", "Egne øvelser"),
                        symbol: "dumbbell",
                        tint: lavender,
                        count: exerciseLibrary.customExercises.count,
                        grid: displayMode == .grid
                    )
                }
                if displayMode == .list { libraryDivider }
                NavigationLink {
                    RouteLibraryListView(source: .mine)
                } label: {
                    LibraryHubCollectionRow(
                        title: tr("My routes", "Mine ruter"),
                        detail: tr("Saved and created routes", "Lagrede og opprettede ruter"),
                        symbol: "map",
                        tint: green,
                        count: session.savedRoutes.count,
                        grid: displayMode == .grid
                    )
                }
                if displayMode == .list { libraryDivider }
                NavigationLink {
                    LibraryFavoritesView(onStartRunning: onStartRunning)
                } label: {
                    LibraryHubCollectionRow(
                        title: tr("Favorites", "Favoritter"),
                        detail: tr("Quick access to your favorites",
                                   "Dine favoritter på ett sted"),
                        symbol: "star",
                        tint: gold,
                        count: favorites.favorites.count,
                        grid: displayMode == .grid
                    )
                }
            }
            .background(displayMode == .list ? .white.opacity(0.92) : .clear,
                        in: RoundedRectangle(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(Color.black.opacity(0.035), lineWidth: 1)
            }
        }
    }

    private var learningHint: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "lightbulb")
                .font(.system(size: 15))
                .foregroundStyle(gold)
            VStack(alignment: .leading, spacing: 3) {
                Text(tr("Start simple. Add details when you need them.",
                        "Start enkelt. Legg til detaljer når du trenger dem."))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ink)
                Text(tr(
                    "The same workout builder works for single sessions and training plans.",
                    "Den samme øktbyggeren brukes til både enkeltøkter og treningsplaner."
                ))
                .font(.caption)
                .foregroundStyle(muted)
            }
            Spacer(minLength: 0)
        }
        .padding(15)
        .background(gold.opacity(0.065),
                    in: RoundedRectangle(cornerRadius: 17))
    }

    private var libraryDivider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.055))
            .frame(height: 0.5)
            .padding(.leading, 67)
    }

    private func sectionHeading(
        _ eyebrow: String,
        title: String,
        detail: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(eyebrow)
                .font(.caption2.weight(.semibold))
                .tracking(1.6)
                .foregroundStyle(gold)
            Text(title)
                .font(.system(size: 24, weight: .semibold, design: .serif))
                .foregroundStyle(ink)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }
}

private struct LibraryHubActionTile: View {
    let title: String
    let detail: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 45, height: 45)
                    .background(tint.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 15))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
            }
            Spacer(minLength: 1)
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(red: 0.17, green: 0.17, blue: 0.18))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(.caption)
                .foregroundStyle(Color(red: 0.47, green: 0.46, blue: 0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 166,
               alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [.white.opacity(0.98), tint.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(.white.opacity(0.90), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }
}

private struct LibraryHubCategoryTile: View {
    let title: String
    let detail: String
    let symbol: String
    let artwork: String
    let tint: Color
    var compact: Bool = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { geometry in
                Image(artwork)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            }
            LinearGradient(
                colors: [.black.opacity(0.02), .black.opacity(0.24), .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial,
                                in: RoundedRectangle(cornerRadius: 11))
                Spacer(minLength: 0)
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                HStack(alignment: .bottom, spacing: 5) {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding(13)
        }
        .frame(height: compact ? 91 : 160)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.6), lineWidth: 0.8)
        }
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(detail)")
    }
}

private struct LibraryHubCollectionRow: View {
    let title: String
    let detail: String
    let symbol: String
    let tint: Color
    let count: Int?
    var grid: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(red: 0.17, green: 0.17, blue: 0.18))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.47, green: 0.46, blue: 0.45))
                    .lineLimit(2)
            }
            Spacer(minLength: 2)
            if let count, count > 0 {
                Text("\(count)")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.gray.opacity(0.68))
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: grid ? 120 : 67,
               alignment: grid ? .topLeading : .center)
        .background(grid ? Color.white.opacity(0.96) : .clear,
                    in: RoundedRectangle(cornerRadius: 18))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// My Workouts unifies the two existing sources without duplicating them
/// on the library home screen. Opening either source still uses its existing
/// editor and launching behavior.
private struct LibrarySavedWorkoutsHubView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var runningLibrary: RunningWorkoutLibraryStore
    let onStartRunning: (RunningWorkoutTemplate) -> Void

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                Text(tr("All saved workouts", "Alle lagrede økter"))
                    .font(.system(size: 28, weight: .semibold, design: .serif))
                Text(tr(
                    "Your strength, hybrid and running workouts in one place.",
                    "Styrkeøkter, kombinasjonsøkter og løpeøkter samlet på ett sted."
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)

                NavigationLink {
                    MyWorkoutTemplatesView()
                } label: {
                    LibraryHubCollectionRow(
                        title: tr("Strength and mixed workouts", "Styrke og kombinasjonsøkter"),
                        detail: tr("Detailed sessions and templates", "Detaljerte økter og maler"),
                        symbol: "dumbbell",
                        tint: Color(red: 0.46, green: 0.41, blue: 0.66),
                        count: session.savedWorkoutTemplates.count
                    )
                }

                NavigationLink {
                    RunningWorkoutLibraryView(
                        source: .mine,
                        onStart: onStartRunning
                    )
                } label: {
                    LibraryHubCollectionRow(
                        title: tr("Running workouts", "Løpeøkter"),
                        detail: tr("Intervals, tempo and distance", "Intervaller, tempo og distanse"),
                        symbol: "figure.run",
                        tint: Color(red: 0.32, green: 0.47, blue: 0.40),
                        count: runningLibrary.customTemplates.count
                    )
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 720, alignment: .leading)
            .padding(18)
            .frame(maxWidth: .infinity)
        }
        .background(Color(red: 0.986, green: 0.978, blue: 0.964).ignoresSafeArea())
        .navigationTitle(tr("My workouts", "Mine økter"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LibraryPremiumIntro<Accessory: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let icon: String
    let accent: Color
    private let accessory: Accessory

    init(
        eyebrow: String,
        title: String,
        subtitle: String,
        icon: String,
        accent: Color,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.accent = accent
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 48, height: 48)
                    .background(
                        accent.opacity(0.10),
                        in: RoundedRectangle(
                            cornerRadius: 16,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow)
                        .font(.caption2.weight(.bold))
                        .tracking(2.6)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )

                    Text(title)
                        .font(
                            .system(
                                size: 30,
                                weight: .semibold,
                                design: .serif
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                }

                Spacer(minLength: 0)
            }

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )

            accessory
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.96),
                    accent.opacity(0.055)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
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
                Color.white.opacity(0.94),
                lineWidth: 1
            )
        }
        .shadow(
            color: ATHLTHTheme.accentDeep.opacity(0.035),
            radius: 18,
            y: 8
        )
    }
}

struct LibraryStatPill: View {
    let value: String
    let label: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
                .foregroundStyle(tint)

            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(ATHLTHTheme.primaryText)

            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(ATHLTHTheme.mutedText)
        }
        .padding(.horizontal, 10)
        .frame(height: 31)
        .background(
            Color.white.opacity(0.72),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(
                    Color.black.opacity(0.035),
                    lineWidth: 0.7
                )
        }
    }
}

enum LibraryFavoriteKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case plan
    case workout
    case exercise
    case route

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plan: return "Plans"
        case .workout: return "Workouts"
        case .exercise: return "Exercises"
        case .route: return "Routes"
        }
    }

    var systemImage: String {
        switch self {
        case .plan: return "calendar.badge.clock"
        case .workout: return "figure.run"
        case .exercise: return "dumbbell.fill"
        case .route: return "map.fill"
        }
    }
}

struct LibraryRecentRecord: Codable, Hashable, Identifiable {
    let itemType: LibraryFavoriteKind
    let itemID: String
    let title: String
    let subtitle: String?
    let icon: String?
    let lastOpenedAt: Date

    var id: String {
        "\(itemType.rawValue)|\(itemID)"
    }
}

@MainActor
final class LibraryRecentsStore: ObservableObject {
    @Published private(set) var items: [LibraryRecentRecord] = []

    private let client: SupabaseClient
    private var activeUserID: UUID?

    init(client: SupabaseClient = SupabaseEnvironment.client) {
        self.client = client
    }

    func refresh() {
        guard let user = client.auth.currentUser else {
            activeUserID = nil
            items = []
            return
        }

        guard activeUserID != user.id else { return }
        activeUserID = user.id
        items =
            AccountLocalStorage.read(
                [LibraryRecentRecord].self,
                name: "libraryRecents",
                userID: user.id
            ) ?? []
    }

    func markUsed(
        _ kind: LibraryFavoriteKind,
        itemID: String,
        title: String,
        subtitle: String? = nil,
        icon: String? = nil
    ) {
        guard let user = client.auth.currentUser else { return }

        if activeUserID != user.id {
            activeUserID = user.id
            items =
                AccountLocalStorage.read(
                    [LibraryRecentRecord].self,
                    name: "libraryRecents",
                    userID: user.id
                ) ?? []
        }

        let record = LibraryRecentRecord(
            itemType: kind,
            itemID: itemID,
            title: title,
            subtitle: subtitle,
            icon: icon,
            lastOpenedAt: Date()
        )

        items.removeAll { $0.id == record.id }
        items.insert(record, at: 0)

        if items.count > 20 {
            items = Array(items.prefix(20))
        }

        AccountLocalStorage.write(
            items,
            name: "libraryRecents",
            userID: user.id
        )
    }
}

struct LibraryFavoriteRecord: Codable, Hashable, Identifiable {
    let userID: UUID
    let itemType: LibraryFavoriteKind
    let itemID: String
    let title: String
    let subtitle: String?
    let icon: String?
    let createdAt: Date

    var id: String {
        "\(itemType.rawValue)|\(itemID)"
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case itemType = "item_type"
        case itemID = "item_id"
        case title
        case subtitle
        case icon
        case createdAt = "created_at"
    }
}

@MainActor
final class LibraryFavoritesStore: ObservableObject {
    @Published private(set) var favorites: [LibraryFavoriteRecord] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let client: SupabaseClient
    private var activeUserID: UUID?
    private var lastRefreshAt: Date?

    init(client: SupabaseClient = SupabaseEnvironment.client) {
        self.client = client
    }

    func refresh(force: Bool = false) async {
        guard let user = client.auth.currentUser else {
            activeUserID = nil
            favorites = []
            errorMessage = nil
            return
        }

        if activeUserID != user.id {
            activeUserID = user.id
            favorites =
                AccountLocalStorage.read(
                    [LibraryFavoriteRecord].self,
                    name: "libraryFavorites",
                    userID: user.id
                ) ?? []
            lastRefreshAt = nil
        }

        if !force,
           let lastRefreshAt,
           Date().timeIntervalSince(lastRefreshAt) < 120 {
            return
        }

        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let rows: [LibraryFavoriteRecord] =
                try await client
                    .from("library_favorites")
                    .select()
                    .eq("user_id", value: user.id)
                    .order("created_at", ascending: false)
                    .execute()
                    .value

            favorites = rows
            lastRefreshAt = Date()
            persistLocal()
            errorMessage = nil
        } catch {
            // Favorites remain fully usable from the account-local cache.
            // The next refresh retries Supabase automatically.
            errorMessage = error.localizedDescription
        }
    }

    func isFavorite(
        _ kind: LibraryFavoriteKind,
        itemID: String
    ) -> Bool {
        favorites.contains {
            $0.itemType == kind &&
            $0.itemID == itemID
        }
    }

    func count(for kind: LibraryFavoriteKind) -> Int {
        favorites.filter { $0.itemType == kind }.count
    }

    func toggle(
        _ kind: LibraryFavoriteKind,
        itemID: String,
        title: String,
        subtitle: String? = nil,
        icon: String? = nil
    ) {
        guard let user = client.auth.currentUser else { return }

        if activeUserID != user.id {
            activeUserID = user.id
            favorites =
                AccountLocalStorage.read(
                    [LibraryFavoriteRecord].self,
                    name: "libraryFavorites",
                    userID: user.id
                ) ?? []
        }

        if isFavorite(kind, itemID: itemID) {
            favorites.removeAll {
                $0.itemType == kind &&
                $0.itemID == itemID
            }
            persistLocal()

            Task {
                do {
                    try await client
                        .from("library_favorites")
                        .delete()
                        .eq("user_id", value: user.id)
                        .eq("item_type", value: kind.rawValue)
                        .eq("item_id", value: itemID)
                        .execute()
                    errorMessage = nil
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } else {
            let record = LibraryFavoriteRecord(
                userID: user.id,
                itemType: kind,
                itemID: itemID,
                title: title,
                subtitle: subtitle,
                icon: icon,
                createdAt: Date()
            )
            favorites.insert(record, at: 0)
            persistLocal()

            Task {
                do {
                    try await client
                        .from("library_favorites")
                        .upsert(record)
                        .execute()
                    errorMessage = nil
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func persistLocal() {
        guard let activeUserID else { return }
        AccountLocalStorage.write(
            favorites,
            name: "libraryFavorites",
            userID: activeUserID
        )
    }
}

struct LibraryFavoriteButton: View {
    @EnvironmentObject private var favorites: LibraryFavoritesStore

    let kind: LibraryFavoriteKind
    let itemID: String
    let title: String
    let subtitle: String?
    let icon: String?

    init(
        kind: LibraryFavoriteKind,
        itemID: String,
        title: String,
        subtitle: String? = nil,
        icon: String? = nil
    ) {
        self.kind = kind
        self.itemID = itemID
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
    }

    var body: some View {
        let selected = favorites.isFavorite(
            kind,
            itemID: itemID
        )

        Button {
            favorites.toggle(
                kind,
                itemID: itemID,
                title: title,
                subtitle: subtitle,
                icon: icon
            )
        } label: {
            Image(
                systemName:
                    selected
                        ? "star.fill"
                        : "star"
            )
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(
                selected
                    ? ATHLTHTheme.premiumGold
                    : ATHLTHTheme.mutedText
            )
            .frame(width: 38, height: 38)
            .background(
                Color.white.opacity(0.88),
                in: Circle()
            )
            .overlay {
                Circle()
                    .stroke(
                        Color.black.opacity(0.05),
                        lineWidth: 0.8
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            selected
                ? "Remove from favorites"
                : "Add to favorites"
        )
    }
}

enum TrainingPlanCatalogSessionBlueprint: String, Codable, Hashable {
    case running
    case walking
    case strength
    case mobility
    case recovery
    case custom
    case easyRun = "easy_run"
    case walkRun = "walk_run"
    case tempoRun = "tempo_run"
    case intervalRun = "interval_run"
    case longRun = "long_run"
    case fullBodyA = "full_body_a"
    case fullBodyB = "full_body_b"
    case fullBodyC = "full_body_c"
    // The program-specific recipes remain typed; never silently discard a
    // workout identifier and leave an empty calendar day.
    case upperBody = "upper_body"
    case lowerBody = "lower_body"
    case push
    case pull
    case legs
    case chest
    case back
    case shouldersCore = "shoulders_core"
    case quads
    case glutes
    case arms
    case core
    case home
    case powerSquat = "power_squat"
    case powerBench = "power_bench"
    case powerDeadlift = "power_deadlift"
    case racePaceRun = "race_pace_run"
    case hillRun = "hill_run"
    case hyroxSkills = "hyrox_skills"
    case hyroxCircuit = "hyrox_circuit"

    var kind: WorkoutKind {
        switch self {
        case .walking:
            return .walking
        case .strength, .fullBodyA, .fullBodyB, .fullBodyC,
             .upperBody, .lowerBody, .push, .pull, .legs,
             .chest, .back, .shouldersCore, .quads, .glutes,
             .arms, .core, .home, .powerSquat, .powerBench,
             .powerDeadlift:
            return .strength
        case .mobility:
            return .mobility
        case .recovery:
            return .recovery
        case .custom, .hyroxSkills, .hyroxCircuit:
            return .custom
        default:
            return .running
        }
    }

    var title: String {
        switch self {
        case .running: return "Run"
        case .walking: return "Walk"
        case .strength: return "Strength"
        case .mobility: return "Mobility"
        case .recovery: return "Recovery"
        case .custom: return "Workout"
        case .easyRun: return "Easy Run"
        case .walkRun: return "Run / Walk"
        case .tempoRun: return "Tempo Run"
        case .intervalRun: return "Intervals"
        case .longRun: return "Long Run"
        case .fullBodyA: return "Full Body A"
        case .fullBodyB: return "Full Body B"
        case .fullBodyC: return "Full Body C"
        case .upperBody: return ATHLTHLocalization.choose(english: "Upper Body", norwegian: "Overkropp")
        case .lowerBody: return ATHLTHLocalization.choose(english: "Lower Body", norwegian: "Underkropp")
        case .push: return "Push"
        case .pull: return "Pull"
        case .legs: return ATHLTHLocalization.choose(english: "Leg Day", norwegian: "Bein")
        case .chest: return ATHLTHLocalization.choose(english: "Chest & Triceps", norwegian: "Bryst og triceps")
        case .back: return ATHLTHLocalization.choose(english: "Back & Biceps", norwegian: "Rygg og biceps")
        case .shouldersCore: return ATHLTHLocalization.choose(english: "Shoulders & Core", norwegian: "Skuldre og kjerne")
        case .quads: return ATHLTHLocalization.choose(english: "Quads", norwegian: "Fremside lår")
        case .glutes: return ATHLTHLocalization.choose(english: "Glutes & Hamstrings", norwegian: "Sete og bakside lår")
        case .arms: return ATHLTHLocalization.choose(english: "Arms", norwegian: "Armer")
        case .core: return ATHLTHLocalization.choose(english: "Core", norwegian: "Kjerne")
        case .home: return ATHLTHLocalization.choose(english: "Home Strength", norwegian: "Hjemmestyrke")
        case .powerSquat: return ATHLTHLocalization.choose(english: "Squat Focus", norwegian: "Knebøyfokus")
        case .powerBench: return ATHLTHLocalization.choose(english: "Bench Focus", norwegian: "Benkpressfokus")
        case .powerDeadlift: return ATHLTHLocalization.choose(english: "Deadlift Focus", norwegian: "Markløftfokus")
        case .racePaceRun: return ATHLTHLocalization.choose(english: "Race-pace Practice", norwegian: "Konkurransetempo")
        case .hillRun: return ATHLTHLocalization.choose(english: "Hill Repeats", norwegian: "Bakkeintervaller")
        case .hyroxSkills: return ATHLTHLocalization.choose(english: "Hybrid Station Skills", norwegian: "Hybrid stasjonsteknikk")
        case .hyroxCircuit: return ATHLTHLocalization.choose(english: "Hybrid Circuit", norwegian: "Hybrid sirkeløkt")
        }
    }

    func durationMinutes(
        week: Int,
        totalWeeks: Int
    ) -> Int {
        let week = max(week, 1)
        let totalWeeks = max(totalWeeks, 1)
        let deload = week.isMultiple(of: 4) && week < totalWeeks
        let taper =
            totalWeeks >= 12 &&
            week >= totalWeeks - 1

        let value: Int
        switch self {
        case .easyRun, .running:
            value = 35 + min((week - 1) * 2, 25)
        case .walkRun:
            value = 30 + min((week - 1) * 3, 20)
        case .tempoRun:
            value = 35 + min((week - 1) * 2, 25)
        case .intervalRun:
            value = 35 + min((week - 1) * 2, 20)
        case .longRun:
            value = 50 + min((week - 1) * 5, 80)
        case .walking:
            value = 45
        case .strength, .fullBodyA, .fullBodyB, .fullBodyC, .upperBody,
             .lowerBody, .push, .pull, .legs, .chest, .back, .quads, .glutes, .arms:
            value = 50
        case .shouldersCore, .home:
            value = 40
        case .core:
            value = 30
        case .powerSquat, .powerBench, .powerDeadlift:
            value = 55
        case .racePaceRun, .hillRun:
            value = 45 + min((week - 1), 12)
        case .hyroxSkills:
            value = 45
        case .hyroxCircuit:
            value = 60
        case .mobility:
            value = 25
        case .recovery:
            value = 30
        case .custom:
            value = 45
        }

        if taper {
            return max(Int(Double(value) * 0.72), 25)
        }

        if deload {
            return max(Int(Double(value) * 0.82), 25)
        }

        return value
    }

    func note(
        week: Int,
        totalWeeks: Int
    ) -> String? {
        if totalWeeks >= 12 && week >= totalWeeks - 1 {
            return "Taper week · keep the effort controlled."
        }

        if week.isMultiple(of: 4) && week < totalWeeks {
            return "Deload week · absorb the previous training block."
        }

        switch self {
        case .easyRun:
            return "Conversational effort. Keep this genuinely easy."
        case .walkRun:
            return "Alternate comfortable running and walking as needed."
        case .tempoRun:
            return "Controlled quality work. Finish with something left."
        case .intervalRun:
            return "Quality intervals with easy recovery between efforts."
        case .longRun:
            return "Build endurance at an easy, sustainable effort."
        case .fullBodyA, .fullBodyB, .fullBodyC, .upperBody, .lowerBody,
             .push, .pull, .legs, .chest, .back, .quads, .glutes,
             .arms, .core, .home:
            return "Strength recipe with complete sets, repetitions and recovery. Adjust to your level."
        case .powerSquat, .powerBench, .powerDeadlift:
            return "Focus on technique and controlled effort; do not test a maximum during normal training."
        case .hyroxSkills, .hyroxCircuit:
            return "Practice station transitions with manageable loads and technique before speed."
        case .racePaceRun:
            return "Controlled race-pace intervals. Calibrate effort to your current fitness."
        case .hillRun:
            return "Run uphill with good form and recover easily downhill."
        default:
            return nil
        }
    }
}

struct TrainingPlanCatalogEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let slug: String
    let title: String
    let summary: String
    let category: String
    let goal: String
    let level: String
    let durationWeeks: Int
    let sessionsPerWeek: Int
    let workoutPattern: [String]
    let tags: [String]
    let sortOrder: Int
    let catalogVersion: Int

    enum CodingKeys: String, CodingKey {
        case id
        case slug
        case title
        case summary
        case category
        case goal
        case level
        case durationWeeks = "duration_weeks"
        case sessionsPerWeek = "sessions_per_week"
        case workoutPattern = "workout_pattern"
        case tags
        case sortOrder = "sort_order"
        case catalogVersion = "catalog_version"
    }

    var sessionBlueprints: [TrainingPlanCatalogSessionBlueprint] {
        workoutPattern.compactMap(
            TrainingPlanCatalogSessionBlueprint.init(rawValue:)
        )
    }

    var workoutKinds: [WorkoutKind] {
        sessionBlueprints.map(\.kind)
    }

    /// Derive the plan type from the actual programmed sessions.
    var trainingTypeTitle: String {
        let kinds = Set(workoutKinds)
        let cardio = kinds.contains(.running) || kinds.contains(.walking)
        let strength = kinds.contains(.strength)
        if category == "hybrid" || kinds.contains(.custom) || (cardio && strength) {
            return ATHLTHLocalization.choose(english: "Running + strength", norwegian: "Løping og styrke")
        }
        if strength {
            return ATHLTHLocalization.choose(english: "Strength plan", norwegian: "Styrkeplan")
        }
        if kinds.contains(.running) {
            return ATHLTHLocalization.choose(english: "Running plan", norwegian: "Løpeplan")
        }
        if kinds.contains(.walking) {
            return ATHLTHLocalization.choose(english: "Walking plan", norwegian: "Gåplan")
        }
        return ATHLTHLocalization.choose(english: "Training plan", norwegian: "Treningsplan")
    }

    var trainingTypeIcon: String {
        let kinds = Set(workoutKinds)
        if category == "hybrid" || kinds.contains(.custom) ||
           (kinds.contains(.strength) &&
            (kinds.contains(.running) || kinds.contains(.walking))) {
            return "figure.run.square.stack.fill"
        }
        if kinds.contains(.strength) { return "dumbbell.fill" }
        if kinds.contains(.walking) && !kinds.contains(.running) {
            return "figure.walk"
        }
        return "figure.run"
    }

    var sessionOutline: String {
        let titles = sessionBlueprints.prefix(sessionsPerWeek).map(\.title)
        return titles.isEmpty ? goal : titles.prefix(3).joined(separator: " · ")
    }

    /// A muscle filter means the plan explicitly names that muscle as a focus
    /// in its editorial tags, title or programmed session names. Do not
    /// advertise generic strength plans as specialized muscle plans.
    func explicitlyTargets(_ muscle: ExerciseMuscleGroup) -> Bool {
        let text = (tags + workoutPattern + [slug, title, goal])
            .joined(separator: " ")
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let aliases: [String]
        switch muscle {
        case .chest: aliases = ["chest", "bryst", "pecs"]
        case .back: aliases = ["back", "rygg", "pull"]
        case .shoulders: aliases = ["shoulders", "skuldre", "delts"]
        case .biceps: aliases = ["biceps"]
        case .triceps: aliases = ["triceps"]
        case .forearms: aliases = ["forearms", "underarmer"]
        case .core: aliases = ["core", "kjerne", "mage"]
        case .glutes: aliases = ["glutes", "sete"]
        case .quads: aliases = ["quads", "quadriceps", "fremside lår", "forside lår"]
        case .hamstrings: aliases = ["hamstrings", "bakside lår"]
        case .calves: aliases = ["calves", "legger"]
        }
        return aliases.contains { text.localizedStandardContains($0) }
    }

    var categoryTitle: String {
        switch category {
        case "muscle_focus":
            return ATHLTHLocalization.choose(english: "Muscle focus", norwegian: "Muskelgrupper")
        case "competition":
            return ATHLTHLocalization.choose(english: "Competition", norwegian: "Konkurranse")
        case "general_fitness":
            return ATHLTHLocalization.choose(english: "General fitness", norwegian: "Hverdagsform")
        case "strength": return ATHLTHLocalization.choose(english: "Strength", norwegian: "Styrke")
        case "running": return ATHLTHLocalization.choose(english: "Running", norwegian: "Løping")
        case "hybrid": return "Hybrid"
        default: return category.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// Local plans never disappear when the published server collection is
    /// unavailable or smaller; exact-slug server items are kept once.
    static var bundledCatalog: [TrainingPlanCatalogEntry] {
        fallbackCatalog + ATHLTHZonedPlanLibrary.catalogEntries + ATHLTHCuratedTrainingPlans.entries + ATHLTHGymCoachStrengthLibrary.catalogEntries
    }

    var usesCompetitionTaper: Bool {
        category == "competition" || ["marathon-build", "half-marathon-foundation"].contains(slug)
    }
}

@MainActor
final class TrainingPlanLibraryStore: ObservableObject {
    @Published private(set) var entries: [TrainingPlanCatalogEntry] =
        TrainingPlanCatalogEntry.bundledCatalog
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let client: SupabaseClient
    private var loadedRemote = false

    init(client: SupabaseClient = SupabaseEnvironment.client) {
        self.client = client
    }

    func refresh(force: Bool = false) async {
        if loadedRemote && !force { return }
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let remote: [TrainingPlanCatalogEntry] =
                try await client
                    .from("training_plan_catalog")
                    .select(
                        "id,slug,title,summary,category,goal,level,duration_weeks,sessions_per_week,workout_pattern,tags,sort_order,catalog_version"
                    )
                    .eq("is_published", value: true)
                    .order("sort_order", ascending: true)
                    .execute()
                    .value

            let remoteSlugs = Set(remote.map(\.slug))
            let bundled = TrainingPlanCatalogEntry.bundledCatalog
                .filter { !remoteSlugs.contains($0.slug) }
            entries = (remote + bundled).sorted {
                $0.sortOrder == $1.sortOrder
                    ? $0.title < $1.title : $0.sortOrder < $1.sortOrder
            }
            loadedRemote = true
            errorMessage = nil
        } catch {
            // Keep all local plans available even without the database.
            if !loadedRemote {
                entries = TrainingPlanCatalogEntry.bundledCatalog
            }
            errorMessage = error.localizedDescription
        }
    }
}

extension TrainingPlanCatalogEntry {
    static let fallbackCatalog: [TrainingPlanCatalogEntry] = [
        TrainingPlanCatalogEntry(
            id: UUID(uuidString: "B1000000-0000-0000-0000-000000000001")!,
            slug: "first-5k",
            title: "First 5K",
            summary: "An approachable 8-week run plan that builds consistency before speed.",
            category: "running",
            goal: "Complete a comfortable 5K",
            level: "Beginner",
            durationWeeks: 8,
            sessionsPerWeek: 3,
            workoutPattern: ["walk_run", "easy_run", "long_run"],
            tags: ["5k", "running", "beginner"],
            sortOrder: 10,
            catalogVersion: 2
        ),
        TrainingPlanCatalogEntry(
            id: UUID(uuidString: "B1000000-0000-0000-0000-000000000002")!,
            slug: "10k-builder",
            title: "10K Builder",
            summary: "Build aerobic volume with running plus one supporting strength session each week.",
            category: "running",
            goal: "Build toward 10K",
            level: "Intermediate",
            durationWeeks: 10,
            sessionsPerWeek: 4,
            workoutPattern: ["easy_run", "tempo_run", "strength", "long_run"],
            tags: ["10k", "running", "strength"],
            sortOrder: 20,
            catalogVersion: 2
        ),
        TrainingPlanCatalogEntry(
            id: UUID(uuidString: "B1000000-0000-0000-0000-000000000003")!,
            slug: "half-marathon-foundation",
            title: "Half Marathon Foundation",
            summary: "A balanced 12-week structure with easy running, long-run volume and strength support.",
            category: "running",
            goal: "Half marathon",
            level: "Intermediate",
            durationWeeks: 12,
            sessionsPerWeek: 4,
            workoutPattern: ["easy_run", "strength", "tempo_run", "long_run"],
            tags: ["half-marathon", "running"],
            sortOrder: 30,
            catalogVersion: 2
        ),
        TrainingPlanCatalogEntry(
            id: UUID(uuidString: "B1000000-0000-0000-0000-000000000004")!,
            slug: "marathon-build",
            title: "Marathon Build",
            summary: "A 16-week endurance structure for runners ready for higher weekly volume.",
            category: "running",
            goal: "Marathon",
            level: "Advanced",
            durationWeeks: 16,
            sessionsPerWeek: 5,
            workoutPattern: ["easy_run", "strength", "interval_run", "easy_run", "long_run"],
            tags: ["marathon", "running"],
            sortOrder: 40,
            catalogVersion: 2
        ),
        TrainingPlanCatalogEntry(
            id: UUID(uuidString: "B1000000-0000-0000-0000-000000000005")!,
            slug: "strength-foundations",
            title: "Strength Foundations",
            summary: "Three full-body sessions each week with room to customize exercises and progression.",
            category: "strength",
            goal: "Build strength",
            level: "Beginner",
            durationWeeks: 8,
            sessionsPerWeek: 3,
            workoutPattern: ["full_body_a", "full_body_b", "full_body_c"],
            tags: ["strength", "full-body"],
            sortOrder: 50,
            catalogVersion: 2
        ),
        TrainingPlanCatalogEntry(
            id: UUID(uuidString: "B1000000-0000-0000-0000-000000000006")!,
            slug: "hybrid-foundation",
            title: "Hybrid Foundation",
            summary: "Two running and two strength sessions each week for balanced all-round fitness.",
            category: "hybrid",
            goal: "General fitness",
            level: "All levels",
            durationWeeks: 8,
            sessionsPerWeek: 4,
            workoutPattern: ["easy_run", "full_body_a", "tempo_run", "full_body_b"],
            tags: ["hybrid", "running", "strength"],
            sortOrder: 60,
            catalogVersion: 2
        )
    ]
}

/// Plan collections: catalog and owned plans share one place. A separate
/// Favorites shortcut opens a dedicated catalog list with a fixed star filter.
struct TrainingPlanLibrarySheet: View {
    enum Section: String, Hashable {
        case library
        case mine
    }

    @Environment(\.dismiss) private var dismiss
    var favoritePlansOnly = false
    var onOpenSavedPlan: ((UUID) -> Void)? = nil
    @State private var selectedSection: Section = .library

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !favoritePlansOnly {
                    Picker(tr("Plans", "Planer"), selection: $selectedSection) {
                        Text(tr("Library plans", "Bibliotekets planer")).tag(Section.library)
                        Text(tr("My plans", "Mine planer")).tag(Section.mine)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                    .accessibilityLabel(tr("Choose plan collection", "Velg plansamling"))
                }

                if favoritePlansOnly {
                    TrainingPlanLibraryView(onPlanCreated: { dismiss() },
                                            favoritePlansOnly: true)
                } else if selectedSection == .library {
                    TrainingPlanLibraryView(onPlanCreated: { dismiss() })
                } else if let onOpenSavedPlan {
                    MyTrainingPlansLibraryView(onOpenPlan: { planID in
                        dismiss()
                        onOpenSavedPlan(planID)
                    })
                } else {
                    MyTrainingPlansLibraryView()
                }
            }
            .background(ATHLTHTrainDesign.canvas.ignoresSafeArea())
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(tr("Close", "Lukk")) { dismiss() }
                        .fontWeight(.medium)
                }
            }
        }
    }
}

struct TrainingPlanLibraryView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var favorites: LibraryFavoritesStore

    var onPlanCreated: (() -> Void)? = nil
    /// Dedicated Favorites view only. Not exposed as a catalog list filter.
    var favoritePlansOnly = false

    @StateObject private var catalog = TrainingPlanLibraryStore()
    @State private var query = ""
    @State private var selectedCategory = "all"
    @State private var selectedMuscle: ExerciseMuscleGroup?
    @State private var sessionsPerWeekFilter: Int?
    @State private var weeklySortAscending: Bool?
    @State private var displayMode: ATHLTHLibraryDisplayMode = .list
    @State private var libraryViewWidth: CGFloat = 390
    @FocusState private var searchFocused: Bool

    private let ink = ATHLTHTrainDesign.ink
    private let muted = ATHLTHTrainDesign.secondary
    private let bronze = ATHLTHTrainDesign.bronze
    private let canvas = ATHLTHTrainDesign.canvas

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var sessionsPerWeekOptions: [Int] {
        Array(Set(catalog.entries.map(\.sessionsPerWeek))).sorted()
    }

    private var categories: [String] {
        let available = Set(catalog.entries.map(\.category))
        let preferred = [
            "running", "strength", "hybrid", "competition",
            "general_fitness", "muscle_focus"
        ]
        return ["all"] + preferred.filter { available.contains($0) } +
            available.subtracting(preferred).sorted()
    }

    private func categoryTitle(_ category: String) -> String {
        switch category {
        case "all": return tr("All", "Alle")
        case "running": return tr("Running", "Løping")
        case "strength": return tr("Strength", "Styrke")
        case "hybrid": return "Hybrid"
        case "competition": return tr("Competition", "Konkurranse")
        case "general_fitness": return tr("Everyday fitness", "Hverdagsform")
        case "muscle_focus": return tr("Muscle focus", "Muskelgrupper")
        default:
            return catalog.entries.first(where: { $0.category == category })?
                .categoryTitle ?? category
        }
    }

    private func categoryIcon(_ category: String) -> String {
        switch category {
        case "all": return "square.grid.2x2"
        case "running": return "figure.run"
        case "strength", "muscle_focus": return "dumbbell"
        case "hybrid": return "figure.mixed.cardio"
        case "competition": return "trophy"
        case "general_fitness": return "heart"
        default: return "square.stack"
        }
    }

    /// Only use artwork bundled with ATHLTH; the cards never need remote
    /// image requests and the library stays usable when offline.
    private func categoryArtwork(_ entry: TrainingPlanCatalogEntry) -> String {
        switch entry.category {
        case "strength", "muscle_focus": return "StrengthFeedGym"
        case "hybrid": return "GoalEndurance"
        case "competition": return "GoalEvent"
        case "general_fitness": return "GoalWalking"
        default: return "GoalRunning"
        }
    }

    private func localizedLevel(_ level: String) -> String {
        switch level.lowercased() {
        case "beginner", "novice": return tr("Beginner", "Nybegynner")
        case "intermediate": return tr("Intermediate", "Middels")
        case "advanced": return tr("Advanced", "Avansert")
        case "expert": return tr("Expert", "Erfaren")
        default: return level
        }
    }

    private var hasActiveFilters: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        selectedCategory != "all" || favoritePlansOnly ||
        selectedMuscle != nil || sessionsPerWeekFilter != nil
    }

    private var filterCount: Int {
        (selectedMuscle == nil ? 0 : 1) +
        (sessionsPerWeekFilter == nil ? 0 : 1) +
        (weeklySortAscending == nil ? 0 : 1)
    }

    private var filteredEntries: [TrainingPlanCatalogEntry] {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let results = catalog.entries.filter { entry in
            let categoryMatches =
                selectedCategory == "all" || entry.category == selectedCategory
            let muscleMatches =
                selectedMuscle.map { entry.explicitlyTargets($0) } ?? true
            let favoriteMatches = !favoritePlansOnly || favorites.isFavorite(
                .plan, itemID: entry.id.uuidString
            )
            let searchMatches = ATHLTHWorkoutSearch.matches(
                cleanQuery,
                texts: [entry.title, entry.summary, entry.goal, entry.level,
                        entry.categoryTitle, entry.sessionOutline,
                        entry.tags.joined(separator: " ")]
            )

            return categoryMatches && muscleMatches && favoriteMatches &&
                (sessionsPerWeekFilter == nil ||
                    entry.sessionsPerWeek == sessionsPerWeekFilter) &&
                searchMatches
        }

        guard let weeklySortAscending else { return results }
        return results.sorted { left, right in
            if left.sessionsPerWeek != right.sessionsPerWeek {
                return weeklySortAscending
                    ? left.sessionsPerWeek < right.sessionsPerWeek
                    : left.sessionsPerWeek > right.sessionsPerWeek
            }
            if left.sortOrder == right.sortOrder { return left.slug < right.slug }
            return left.sortOrder < right.sortOrder
        }
    }

    /// Editorial picks: one running and one strength option if available.
    /// These are real catalog entries, never hard-coded demonstration plans.
    private var featuredEntries: [TrainingPlanCatalogEntry] {
        var selected: [TrainingPlanCatalogEntry] = []
        for category in ["running", "strength"] {
            if let entry = catalog.entries.first(where: { $0.category == category }) {
                selected.append(entry)
            }
        }
        for entry in catalog.entries where selected.count < 2 {
            if !selected.contains(where: { $0.id == entry.id }) {
                selected.append(entry)
            }
        }
        return selected
    }

    private var listedEntries: [TrainingPlanCatalogEntry] {
        if hasActiveFilters { return filteredEntries }
        let featuredIDs = Set(featuredEntries.map(\.id))
        let remaining = filteredEntries.filter { !featuredIDs.contains($0.id) }
        return remaining.isEmpty ? filteredEntries : remaining
    }

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    libraryHeading
                    inlineSearch
                    categoryStrip

                    if !hasActiveFilters && !featuredEntries.isEmpty {
                        featuredSection {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                scroll.scrollTo("all-training-plans", anchor: .top)
                            }
                        }
                    }

                    resultsHeader
                        .id("all-training-plans")
                    HStack {
                        Text(tr("View", "Visning"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(muted)
                        Spacer()
                        ATHLTHLibraryDisplayPicker(selection: $displayMode)
                    }

                    if filteredEntries.isEmpty {
                        ContentUnavailableView(
                            favoritePlansOnly
                                ? tr("No favorite plans yet", "Ingen favorittplaner ennå")
                                : tr("No plans found", "Fant ingen treningsplaner"),
                            systemImage: favoritePlansOnly
                                ? "star" : "calendar.badge.exclamationmark",
                            description: Text(favoritePlansOnly
                                ? tr("Mark a library plan with a star to save it here.",
                                     "Trykk på stjernen på en plan i biblioteket for å lagre den her.")
                                : tr("Try a different search or remove a filter.",
                                     "Prøv et annet søk eller fjern et filter."))
                        )
                        .padding(.top, 20)
                        .frame(maxWidth: .infinity)
                    } else {
                        LazyVGrid(
                            columns: ATHLTHLibraryGridColumns.make(
                                mode: displayMode,
                                width: libraryViewWidth,
                                reservedHorizontalSpace: 36,
                                accessibilityText: dynamicTypeSize.isAccessibilitySize
                            ),
                            spacing: 10
                        ) {
                            ForEach(listedEntries) { entry in
                                if displayMode == .grid {
                                    planGridItem(entry)
                                } else {
                                    planListItem(entry)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 44)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .background(canvas.ignoresSafeArea())
        .navigationTitle(favoritePlansOnly
            ? tr("Favorite plans", "Favorittplaner")
            : tr("Plans", "Planer"))
        .navigationBarTitleDisplayMode(.inline)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
            libraryViewWidth = width
        }
        .onAppear {
            displayMode = .load(userID: session.profile.userID)
        }
        .onChange(of: session.profile.userID) { _, userID in
            displayMode = .load(userID: userID)
        }
        .onChange(of: displayMode) { _, value in
            value.save(userID: session.profile.userID)
        }
        .task {
            async let plans: Void = catalog.refresh()
            async let saved: Void = favorites.refresh()
            _ = await (plans, saved)
        }
        .refreshable {
            async let plans: Void = catalog.refresh(force: true)
            async let saved: Void = favorites.refresh(force: true)
            _ = await (plans, saved)
        }
    }

    // Deliberately no full-width hero or photo at the top. The content
    // starts immediately, matching Train's restrained editorial styling.
    private var libraryHeading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(favoritePlansOnly
                 ? tr("FAVORITE PLANS", "FAVORITTPLANER")
                 : tr("PLAN LIBRARY", "PLANBIBLIOTEK"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(2.3)
                .foregroundStyle(bronze)

            Text(favoritePlansOnly
                 ? tr("Your favorite plans", "Dine favorittplaner")
                 : tr("Find your next plan", "Finn din neste plan"))
                .font(.system(size: 34, weight: .regular, design: .serif))
                .foregroundStyle(ink)
                .accessibilityAddTraits(.isHeader)

            Text(favoritePlansOnly
                 ? tr("Plans you've starred, ready when you need them.",
                      "Planene du har merket med stjerne, samlet på ett sted.")
                 : tr("Choose a plan and make it yours.",
                      "Finn en treningsplan som passer målene dine."))
                .font(.subheadline)
                .foregroundStyle(muted)

            HStack(spacing: 9) {
                Label(
                    tr("\(catalog.entries.count) plans", "\(catalog.entries.count) planer"),
                    systemImage: "square.stack.3d.up"
                )
                Label(
                    tr("\(favorites.count(for: .plan)) saved",
                       "\(favorites.count(for: .plan)) lagret"),
                    systemImage: "star"
                )
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(ink.opacity(0.78))
            .padding(.top, 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inlineSearch: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(ink)
                .accessibilityHidden(true)

            TextField(
                tr("Search plans, goals or workouts",
                   "Søk etter planer, mål eller økter"),
                text: $query
            )
            .font(.subheadline)
            .foregroundStyle(ink)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .focused($searchFocused)
            .accessibilityLabel(tr("Search training plans", "Søk i treningsplaner"))

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(muted)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("Clear search", "Tøm søk"))
            }
        }
        .padding(.horizontal, 17)
        .frame(minHeight: 54)
        .background(Color.white.opacity(0.85),
                    in: RoundedRectangle(cornerRadius: 21))
        .overlay {
            RoundedRectangle(cornerRadius: 21)
                .strokeBorder(ATHLTHPlanDesign.outline.opacity(0.55),
                              lineWidth: 0.8)
                .allowsHitTesting(false)
        }
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { category in
                    Button {
                        searchFocused = false
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedCategory = category
                        }
                    } label: {
                        categoryChip(
                            categoryTitle(category),
                            systemImage: categoryIcon(category),
                            selected: selectedCategory == category
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
        .contentMargins(.trailing, 2)
        .accessibilityElement(children: .contain)
    }

    private func categoryChip(
        _ title: String,
        systemImage: String,
        selected: Bool
    ) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(selected ? Color.white : ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 39)
            .background(selected ? ink : Color.white.opacity(0.90),
                        in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(
                        selected ? Color.clear : ATHLTHPlanDesign.outline.opacity(0.50),
                        lineWidth: 0.8
                    )
                    .allowsHitTesting(false)
            }
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func featuredSection(onSeeAll: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text(tr("Featured plans", "Utvalgte planer"))
                    .font(.system(size: 24, weight: .regular, design: .serif))
                    .foregroundStyle(ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: onSeeAll) {
                    HStack(spacing: 5) {
                        Text(tr("See all", "Se alle"))
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(muted)
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(featuredEntries) { entry in
                        featuredPlanItem(entry)
                    }
                }
                .padding(.vertical, 3)
            }
        }
    }

    private func featuredPlanItem(_ entry: TrainingPlanCatalogEntry) -> some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink {
                TrainingPlanCatalogDetailView(
                    entry: entry,
                    onPlanCreated: onPlanCreated
                )
            } label: {
                ZStack(alignment: .bottomLeading) {
                    GeometryReader { geometry in
                        Image(categoryArtwork(entry))
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width,
                                   height: geometry.size.height)
                            .clipped()
                            .accessibilityHidden(true)
                    }
                    LinearGradient(
                        colors: [.black.opacity(0.06), .black.opacity(0.23),
                                 .black.opacity(0.84)],
                        startPoint: .top, endPoint: .bottom
                    )
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entry.trainingTypeTitle.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.2)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(.white.opacity(0.88), in: Capsule())
                            .foregroundStyle(ink)
                        Spacer(minLength: 8)
                        Text(entry.title)
                            .font(.system(size: 24, weight: .regular, design: .serif))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Text(entry.goal)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(2)
                        HStack(spacing: 10) {
                            Label(
                                tr("\(entry.durationWeeks) weeks",
                                   "\(entry.durationWeeks) uker"),
                                systemImage: "calendar"
                            )
                            Label(localizedLevel(entry.level), systemImage: "chart.bar")
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                    }
                    .padding(15)
                    .padding(.trailing, 6)
                }
                .frame(
                    width: dynamicTypeSize.isAccessibilitySize ? 300 : 246,
                    height: dynamicTypeSize.isAccessibilitySize ? 280 : 228
                )
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .contentShape(RoundedRectangle(cornerRadius: 22))
            }
            .buttonStyle(.plain)

            LibraryFavoriteButton(
                kind: .plan,
                itemID: entry.id.uuidString,
                title: entry.title,
                subtitle: "\(entry.durationWeeks) weeks · \(entry.level)",
                icon: "calendar.badge.clock"
            )
            .padding(9)
        }
    }

    private var resultsHeader: some View {
        HStack(spacing: 8) {
            Text(hasActiveFilters
                 ? tr("Search results", "Søkeresultater")
                 : tr("All plans", "Alle planer"))
                .font(.system(size: 24, weight: .regular, design: .serif))
                .foregroundStyle(ink)
                .accessibilityAddTraits(.isHeader)
            Text("\(hasActiveFilters ? filteredEntries.count : listedEntries.count)")
                .font(.caption.weight(.medium))
                .foregroundStyle(muted)
            Spacer(minLength: 6)
            catalogFiltersMenu
        }
    }

    private var catalogFiltersMenu: some View {
        Menu {
            Menu(tr("Muscle group", "Muskelgruppe")) {
                Button {
                    selectedMuscle = nil
                } label: {
                    if selectedMuscle == nil {
                        Label(tr("All muscle groups", "Alle muskelgrupper"),
                              systemImage: "checkmark")
                    } else {
                        Text(tr("All muscle groups", "Alle muskelgrupper"))
                    }
                }
                ForEach(ExerciseMuscleGroup.allCases) { muscle in
                    Button {
                        selectedMuscle = muscle
                    } label: {
                        if selectedMuscle == muscle {
                            Label(muscle.title, systemImage: "checkmark")
                        } else {
                            Text(muscle.title)
                        }
                    }
                }
            }
            Menu(tr("Sessions per week", "Økter per uke")) {
                Button {
                    sessionsPerWeekFilter = nil
                } label: {
                    if sessionsPerWeekFilter == nil {
                        Label(tr("All", "Alle"), systemImage: "checkmark")
                    } else {
                        Text(tr("All", "Alle"))
                    }
                }
                ForEach(sessionsPerWeekOptions, id: \.self) { count in
                    Button {
                        sessionsPerWeekFilter = count
                    } label: {
                        if sessionsPerWeekFilter == count {
                            Label(tr("\(count) / week", "\(count) / uke"),
                                  systemImage: "checkmark")
                        } else {
                            Text(tr("\(count) / week", "\(count) / uke"))
                        }
                    }
                }
            }
            Menu(tr("Sort by", "Sorter etter")) {
                Button {
                    weeklySortAscending = nil
                } label: {
                    if weeklySortAscending == nil {
                        Label(tr("Recommended order", "Anbefalt rekkefølge"),
                              systemImage: "checkmark")
                    } else {
                        Text(tr("Recommended order", "Anbefalt rekkefølge"))
                    }
                }
                Button {
                    weeklySortAscending = true
                } label: {
                    if weeklySortAscending == true {
                        Label(tr("Fewest sessions first", "Færrest økter først"),
                              systemImage: "checkmark")
                    } else {
                        Text(tr("Fewest sessions first", "Færrest økter først"))
                    }
                }
                Button {
                    weeklySortAscending = false
                } label: {
                    if weeklySortAscending == false {
                        Label(tr("Most sessions first", "Flest økter først"),
                              systemImage: "checkmark")
                    } else {
                        Text(tr("Most sessions first", "Flest økter først"))
                    }
                }
            }
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                selectedCategory != "all" || selectedMuscle != nil ||
                filterCount > 0 {
                Divider()
                Button {
                    query = ""
                    selectedCategory = "all"
                    selectedMuscle = nil
                    sessionsPerWeekFilter = nil
                    weeklySortAscending = nil
                } label: {
                    Label(tr("Reset filters", "Nullstill filtre"),
                          systemImage: "arrow.counterclockwise")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                Text(tr("Filters", "Filtre"))
                if filterCount > 0 {
                    Text("\(filterCount)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(bronze)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(ink)
            .padding(.horizontal, 11)
            .frame(minHeight: 37)
            .background(.white.opacity(0.88), in: Capsule())
        }
        .accessibilityLabel(tr("Plan filters and sorting", "Filtre og sortering av planer"))
    }

    private func planGridItem(_ entry: TrainingPlanCatalogEntry) -> some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink {
                TrainingPlanCatalogDetailView(
                    entry: entry, onPlanCreated: onPlanCreated
                )
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Image(categoryArtwork(entry))
                        .resizable()
                        .scaledToFill()
                        .frame(height: 72)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 13))
                    Text(entry.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(tr("\(entry.durationWeeks) weeks", "\(entry.durationWeeks) uker"))
                        .font(.caption)
                        .foregroundStyle(muted)
                    Spacer(minLength: 0)
                }
                .padding(11)
                .frame(maxWidth: .infinity, minHeight: 195, alignment: .topLeading)
                .background(.white, in: RoundedRectangle(cornerRadius: 19))
            }
            .buttonStyle(.plain)

            LibraryFavoriteButton(
                kind: .plan,
                itemID: entry.id.uuidString,
                title: entry.title,
                subtitle: "\(entry.durationWeeks) weeks · \(entry.level)",
                icon: "calendar.badge.clock"
            )
            .padding(6)
        }
    }

    private func planListItem(_ entry: TrainingPlanCatalogEntry) -> some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink {
                TrainingPlanCatalogDetailView(
                    entry: entry, onPlanCreated: onPlanCreated
                )
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    GeometryReader { geometry in
                        Image(categoryArtwork(entry))
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width,
                                   height: geometry.size.height)
                            .clipped()
                    }
                    .frame(width: dynamicTypeSize.isAccessibilitySize ? 83 : 92,
                           height: dynamicTypeSize.isAccessibilitySize ? 113 : 103)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.trainingTypeTitle.uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(1.1)
                            .foregroundStyle(bronze)
                            .lineLimit(1)
                        Text(entry.title)
                            .font(.system(size: 19, weight: .semibold, design: .serif))
                            .foregroundStyle(ink)
                            .lineLimit(2)
                        Text(entry.summary)
                            .font(.caption)
                            .foregroundStyle(muted)
                            .lineLimit(2)
                        HStack(spacing: 9) {
                            Label(tr("\(entry.durationWeeks) weeks",
                                     "\(entry.durationWeeks) uker"),
                                  systemImage: "calendar")
                            Label(tr("\(entry.sessionsPerWeek) / week",
                                     "\(entry.sessionsPerWeek) / uke"),
                                  systemImage: "repeat")
                            if !dynamicTypeSize.isAccessibilitySize {
                                Text(localizedLevel(entry.level))
                                    .lineLimit(1)
                            }
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    }
                    .padding(.trailing, 24)
                    Spacer(minLength: 0)
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.92),
                            in: RoundedRectangle(cornerRadius: 19))
                .overlay {
                    RoundedRectangle(cornerRadius: 19)
                        .strokeBorder(ATHLTHPlanDesign.outline.opacity(0.55),
                                      lineWidth: 0.7)
                        .allowsHitTesting(false)
                }
                .contentShape(RoundedRectangle(cornerRadius: 19))
            }
            .buttonStyle(.plain)

            LibraryFavoriteButton(
                kind: .plan,
                itemID: entry.id.uuidString,
                title: entry.title,
                subtitle: "\(entry.durationWeeks) weeks · \(entry.level)",
                icon: "calendar.badge.clock"
            )
            .padding(8)
        }
    }
}

// A reusable light glass surface for catalog details and plan setup.
// The material adapts to system appearance without an opaque white slab.
private struct ATHLTHPlanGhostCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.70), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.045), radius: 15, y: 6)
    }
}

struct TrainingPlanCatalogDetailView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var favorites: LibraryFavoritesStore
    @EnvironmentObject private var recents: LibraryRecentsStore

    let entry: TrainingPlanCatalogEntry
    var onPlanCreated: (() -> Void)? = nil

    @State private var createEditableCopy = false
    @State private var showingPersonalizePlan = false
    @State private var showAllWeeks = false
    // One session is open by default so users see actual exercises and
    // targets immediately, without rendering every session for 16 weeks.
    @State private var expandedSessionKeys: Set<String> = ["1:0"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 13) {
                        Image(systemName: entry.trainingTypeIcon)
                            .font(.system(size: 23, weight: .semibold))
                            .foregroundStyle(detailAccent)
                            .frame(width: 54, height: 54)
                            .background(
                                detailAccent.opacity(0.10),
                                in: RoundedRectangle(
                                    cornerRadius: 17,
                                    style: .continuous
                                )
                            )

                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.trainingTypeTitle.uppercased())
                                .font(.caption2.weight(.bold))
                                .tracking(2.1)
                                .foregroundStyle(detailAccent)

                            Text(entry.title)
                                .font(
                                    .system(
                                        size: 34,
                                        weight: .semibold,
                                        design: .serif
                                    )
                                )
                                .foregroundStyle(
                                    ATHLTHTheme.primaryText
                                )
                        }

                        Spacer(minLength: 0)
                    }

                    Text(entry.summary)
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .lineSpacing(2)

                    HStack(spacing: 7) {
                        Label(
                            entry.level,
                            systemImage: "speedometer"
                        )
                        Label(
                            entry.goal,
                            systemImage: "scope"
                        )
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(
                        ATHLTHTheme.primaryText.opacity(0.68)
                    )
                    .lineLimit(1)
                }
                .padding(18)
                .athlthPlanCard()

                HStack(spacing: 10) {
                    detailMetric(
                        "\(entry.durationWeeks)",
                        label: ATHLTHLocalization.choose(english: "weeks", norwegian: "uker"),
                        icon: "calendar"
                    )
                    detailMetric(
                        "\(entry.sessionsPerWeek)",
                        label: ATHLTHLocalization.choose(english: "sessions / week", norwegian: "økter / uke"),
                        icon: "repeat"
                    )
                    detailMetric(
                        entry.level,
                        label: ATHLTHLocalization.choose(english: "level", norwegian: "nivå"),
                        icon: "speedometer"
                    )
                }

                ATHLTHPlanGhostCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(ATHLTHLocalization.choose(
                            english: "Weekly rhythm",
                            norwegian: "Ukerytme"
                        ))
                            .font(.headline)

                        HStack(spacing: 8) {
                            ForEach(
                                Array(
                                    entry.workoutKinds.enumerated()
                                ),
                                id: \.offset
                            ) { index, kind in
                                VStack(spacing: 6) {
                                    Image(
                                        systemName:
                                            kind.systemImage
                                    )
                                    .font(
                                        .system(
                                            size: 16,
                                            weight: .semibold
                                        )
                                    )

                                    Text("\(index + 1)")
                                        .font(.caption2.weight(.bold))
                                }
                                .foregroundStyle(
                                    ATHLTHTheme.accent
                                )
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(
                                    ATHLTHTheme.accentSoft,
                                    in: RoundedRectangle(
                                        cornerRadius: 12
                                    )
                                )
                            }
                        }

                        Text(ATHLTHLocalization.choose(
                            english: "Each session below includes its actual exercises and targets. Tap a session to expand it. You can edit all workouts after selecting a start date.",
                            norwegian: "Hver økt nedenfor viser faktiske øvelser og mål. Trykk på en økt for detaljer. Alt kan redigeres etter at du velger startdato."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                ATHLTHPlanGhostCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(ATHLTHLocalization.choose(
                            english: "Goal",
                            norwegian: "Mål"
                        ))
                            .font(.headline)
                        Text(entry.goal)
                            .font(.title3.weight(.semibold))
                        Text(ATHLTHLocalization.choose(
                            english: "Adapt sets, reps and volume to your training history.",
                            norwegian: "Tilpass sett, repetisjoner og mengde til treningshistorikken din."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                if let guidance = entry.readinessGuidance {
                    ATHLTHPlanGhostCard {
                        VStack(alignment: .leading, spacing: 9) {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Before starting",
                                    norwegian: "Før du starter"
                                ),
                                systemImage: "info.circle"
                            )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.primaryText)

                            Text(guidance)
                                .font(.subheadline)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                planPreview

                Button {
                    createEditableCopy = true
                    showingPersonalizePlan = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.on.square")
                            .font(.subheadline.weight(.semibold))
                        Text(
                            ATHLTHLocalization.choose(
                                english: "Build a plan using this plan",
                                norwegian: "Lag en plan med denne planen"
                            )
                        )
                        .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 4)
                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .padding(.horizontal, 17)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 53)
                    .background(
                        .regularMaterial,
                        in: RoundedRectangle(
                            cornerRadius: 17,
                            style: .continuous
                        )
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: 17,
                            style: .continuous
                        )
                        .stroke(.white.opacity(0.75), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(
            ATHLTHPlanDesign.warmCanvas
        )
        .safeAreaInset(edge: .bottom) {
            Button {
                createEditableCopy = false
                showingPersonalizePlan = true
            } label: {
                HStack {
                    Text(ATHLTHLocalization.choose(english: "Choose start date and use plan", norwegian: "Velg startdato og bruk planen"))
                        .font(.headline)
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.right")
                }
                .foregroundStyle(.white)
                .padding(18)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(ATHLTHPlanDesign.ink, in: RoundedRectangle(cornerRadius: 18))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            recents.markUsed(
                .plan,
                itemID: entry.id.uuidString,
                title: entry.title,
                subtitle:
                    "\(entry.durationWeeks) weeks · \(entry.level)",
                icon: "calendar.badge.clock"
            )
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                LibraryFavoriteButton(
                    kind: .plan,
                    itemID: entry.id.uuidString,
                    title: entry.title,
                    subtitle:
                        "\(entry.durationWeeks) weeks · \(entry.level)",
                    icon: "calendar.badge.clock"
                )
            }
        }
        .sheet(isPresented: $showingPersonalizePlan) {
            PersonalizeTrainingPlanView(
                entry: entry,
                onPlanCreated: onPlanCreated,
                createEditableCopy: createEditableCopy
            )
        }
    }

    @ViewBuilder
    private var planPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ATHLTHLocalization.choose(
                        english: "FULL PLAN PREVIEW",
                        norwegian: "HELE PLANEN"
                    ))
                        .font(.caption2.weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )

                    Text(ATHLTHLocalization.choose(
                        english: "Week by week",
                        norwegian: "Uke for uke"
                    ))
                        .font(.title3.weight(.semibold))
                }

                Spacer()

                Text(
                    "v\(entry.catalogVersion)"
                )
                .font(.caption2.weight(.bold))
                .foregroundStyle(detailAccent)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    detailAccent.opacity(0.09),
                    in: Capsule()
                )
            }

            ForEach(
                1...max(
                    showAllWeeks
                        ? entry.durationWeeks
                        : min(entry.durationWeeks, 4),
                    1
                ),
                id: \.self
            ) { week in
                previewWeekCard(week)
            }

            if entry.durationWeeks > 4 {
                Button {
                    withAnimation(
                        .easeInOut(duration: 0.20)
                    ) {
                        showAllWeeks.toggle()
                    }
                } label: {
                    HStack {
                        Text(
                            showAllWeeks
                                ? ATHLTHLocalization.choose(
                                    english: "Show fewer weeks",
                                    norwegian: "Vis færre uker"
                                )
                                : ATHLTHLocalization.format(
                                    english: "Show all %d weeks",
                                    norwegian: "Vis alle %d ukene",
                                    entry.durationWeeks
                                )
                        )
                        .font(.subheadline.weight(.semibold))

                        Spacer()

                        Image(
                            systemName:
                                showAllWeeks
                                    ? "chevron.up"
                                    : "chevron.down"
                        )
                        .font(.caption.bold())
                    }
                    .foregroundStyle(
                        ATHLTHTheme.accent
                    )
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .athlthPlanCard()
    }

    private func previewWeekCard(_ week: Int) -> some View {
        let zonedWeek = ATHLTHZonedPlanLibrary.plan(for: entry.slug)?
            .weeks.first(where: { $0.weekNumber == week })
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(ATHLTHLocalization.format(
                    english: "Week %d", norwegian: "Uke %d", week
                ))
                .font(.headline.weight(.bold))
                .foregroundStyle(ATHLTHPlanDesign.ink)
                Spacer()
                if let zonedWeek {
                    weekPhaseLabel(zonedWeek.isRecoveryWeek
                        ? ATHLTHLocalization.choose(english: "RECOVERY", norwegian: "RESTITUSJON")
                        : zonedWeek.phase.uppercased())
                } else if week.isMultiple(of: 4) && week < entry.durationWeeks {
                    weekPhaseLabel(ATHLTHLocalization.choose(
                        english: "RECOVERY WEEK", norwegian: "ROLIG UKE"
                    ))
                } else if entry.usesCompetitionTaper &&
                          week >= max(entry.durationWeeks - 1, 1) {
                    weekPhaseLabel(ATHLTHLocalization.choose(
                        english: "TAPER", norwegian: "NEDTRAPPING"
                    ))
                }
            }

            if let zonedWeek,
               let zonedPlan = ATHLTHZonedPlanLibrary.plan(for: entry.slug) {
                HStack(spacing: 9) {
                    if let km = zonedWeek.targetKm {
                        Label("\(km.formatted()) km", systemImage: "figure.run")
                    }
                    if let load = zonedWeek.weeklyLoadScore {
                        Label("Zoned load \(load.formatted())", systemImage: "waveform.path.ecg")
                    }
                }
                .font(.caption2)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

                ForEach(
                    Array(ATHLTHZonedPlanLibrary.orderedRequiredSessions(in: zonedWeek).enumerated()),
                    id: \.offset
                ) { index, source in
                    if let workout = ATHLTHZonedPlanLibrary.plannedSession(
                        source, week: zonedWeek, sourcePlan: zonedPlan
                    ) {
                        previewDetailedSessionRow(workout, week: week, index: index)
                    }
                }
                Text(ATHLTHLocalization.choose(
                    english: "Original Zoned heart-rate zones and percentages are shown for each step. Pace examples require individual calibration.",
                    norwegian: "Originale pulssoner og prosent av makspuls fra Zoned vises for hver del. Tempoeksempler må tilpasses individuelt."
                ))
                .font(.caption2)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            } else if let gymcoach = ATHLTHGymCoachStrengthLibrary.program(for: entry.slug) {
                Text(ATHLTHLocalization.choose(
                    english: "Real GymCoach working sets, reps, RIR and rest periods. This is a repeatable source template; percentage-based loading and future progress must be reviewed and personalized before use.",
                    norwegian: "GymCoach-malens arbeidssett, repetisjoner, RIR og pauser. Prosentbaserte vekter og videre progresjon må tilpasses og godkjennes før bruk."
                ))
                .font(.caption2)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                ForEach(
                    Array(ATHLTHGymCoachStrengthLibrary.sourceWorkouts(
                        for: gymcoach, week: week
                    ).enumerated()),
                    id: \.offset
                ) { index, source in
                    previewDetailedSessionRow(
                        ATHLTHGymCoachStrengthLibrary.plannedSession(
                            source, program: gymcoach, week: week
                        ), week: week, index: index
                    )
                }
            } else {
                ForEach(
                    Array(entry.sessionBlueprints
                        .prefix(entry.sessionsPerWeek).enumerated()),
                    id: \.offset
                ) { index, blueprint in
                    previewWeekSessionRow(blueprint, week: week, index: index)
                }
            }
        }
        .padding(14)
        .athlthPlanCard()
    }

    private func weekPhaseLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(ATHLTHPlanDesign.accentInk)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(ATHLTHPlanDesign.selectedSurface, in: Capsule())
    }

    // Split the session header and its blocks from the week view. The old
    // nested result-builder was too complex for Xcode to type-check and
    // prevented iOS builds even before the Quick Train redesign.
    private func previewWeekSessionRow(
        _ blueprint: TrainingPlanCatalogSessionBlueprint,
        week: Int,
        index: Int
    ) -> some View {
        let workout = ATHLTHCatalogPlanSessionFactory.session(
            entry: entry, blueprint: blueprint, week: week
        )
        return previewDetailedSessionRow(workout, week: week, index: index)
    }

    private func previewDetailedSessionRow(
        _ workout: PlannedSession,
        week: Int,
        index: Int
    ) -> some View {
        let key = "\(week):\(index)"
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if !expandedSessionKeys.insert(key).inserted {
                        expandedSessionKeys.remove(key)
                    }
                }
            } label: {
                previewSessionHeading(workout, isExpanded: expandedSessionKeys.contains(key))
            }
            .buttonStyle(.plain)
            .accessibilityHint(ATHLTHLocalization.choose(
                english: "Show or hide the programmed workout steps",
                norwegian: "Vis eller skjul øvelsene i økten"
            ))

            if expandedSessionKeys.contains(key) {
                previewSessionSteps(workout)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            }
        }
        .background(ATHLTHPlanDesign.warmSurface,
                    in: RoundedRectangle(cornerRadius: 14))
    }

    private func previewSessionHeading(
        _ workout: PlannedSession,
        isExpanded: Bool
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: workout.kind.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                .frame(width: 35, height: 35)
                .background(ATHLTHPlanDesign.selectedSurface,
                            in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(workout.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                Text(ATHLTHLocalization.choose(
                    english: "See exercises and targets",
                    norwegian: "Se øvelser, sett og mål"
                ))
                .font(.caption2)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
            Spacer(minLength: 5)
            Text("\(workout.durationMinutes ?? 0) min")
                .font(.caption.weight(.medium))
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption.bold())
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
        }
        .contentShape(Rectangle())
        .padding(11)
    }

    @ViewBuilder
    private func previewSessionSteps(_ workout: PlannedSession) -> some View {
        let blocks = (workout.workoutBlocks ?? []).filter { $0.kind != .note }
        VStack(alignment: .leading, spacing: 0) {
            if blocks.isEmpty {
                Text(ATHLTHLocalization.choose(
                    english: "No exercise steps available for this session.",
                    norwegian: "Ingen øvelsessteg er lagt til denne økten."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                .padding(12)
            } else {
                ForEach(blocks) { block in
                    previewWorkoutBlock(block)
                }
            }
        }
    }

    private func previewWorkoutBlock(_ block: WorkoutTemplateBlock) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: block.kind.systemImage)
                .font(.caption)
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                .frame(width: 19)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(block.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let target = block.targetText {
                    Text(target)
                        .font(.caption2)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if block.kind == .exercise,
                   let rest = block.restBetweenSetsSeconds, rest > 0 {
                    Text(ATHLTHLocalization.format(
                        english: "%d sec rest between sets",
                        norwegian: "%d sek pause mellom sett",
                        Int(rest)
                    ))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
            }
            Spacer(minLength: 2)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
    }

    private func detailMetric(
        _ value: String,
        label: String,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: icon)
                .foregroundStyle(ATHLTHTheme.accent)
            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ATHLTHPlanDesign.warmSurface,
                    in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(ATHLTHPlanDesign.warmDivider, lineWidth: 1)
        }
    }

    private var detailAccent: Color {
        ATHLTHPlanDesign.accentInk
    }

    private var detailIcon: String {
        switch entry.category {
        case "strength":
            return "dumbbell.fill"
        case "hybrid":
            return "figure.run.square.stack.fill"
        default:
            return "figure.run"
        }
    }
}


struct PersonalizeTrainingPlanView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore

    let entry: TrainingPlanCatalogEntry
    var onPlanCreated: (() -> Void)? = nil
    var createEditableCopy = false

    @State private var startDate = Date()
    @State private var selectedDays: Set<Int> = []
    @State private var configured = false
    @State private var scheduleError: String?
    @State private var existingPlanToOpen: TrainingPlan?

    private let dayLabels = [
        "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"
    ]

    private var hasValidDays: Bool {
        selectedDays.count == entry.sessionsPerWeek
    }

    private var resolvedStartDate: Date {
        AppSessionStore.catalogWeekStart(
            onOrAfter: startDate
        )
    }

    private var endDate: Date {
        Calendar.current.date(
            byAdding: .day,
            value: max(entry.durationWeeks * 7 - 1, 0),
            to: resolvedStartDate
        ) ?? resolvedStartDate
    }

    private var existingScheduledPlan: TrainingPlan? {
        guard !createEditableCopy else { return nil }
        return session.existingScheduledCatalogPlan(
            entry,
            startDate: resolvedStartDate
        )
    }

    private var conflictingPlan: TrainingPlan? {
        guard existingScheduledPlan == nil else {
            return nil
        }

        return session.trainingPlanConflict(
            startDate: resolvedStartDate,
            weekCount: entry.durationWeeks
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    LibraryPremiumIntro(
                        eyebrow: createEditableCopy
                            ? ATHLTHLocalization.choose(
                                english: "BUILD FROM TEMPLATE",
                                norwegian: "BYGG FRA MAL"
                            )
                            : ATHLTHLocalization.choose(
                                english: "MAKE IT MINE",
                                norwegian: "GJØR DEN TIL MIN"
                            ),
                        title: entry.title,
                        subtitle: createEditableCopy
                            ? ATHLTHLocalization.choose(
                                english: "Start with this plan's workouts, choose your days and edit your own version after creating it.",
                                norwegian: "Bruk øktene fra denne planen, velg treningsdager og rediger din egen versjon etter opprettelsen."
                            )
                            : ATHLTHLocalization.choose(
                                english: "Choose when this plan fits your life. ATHLTH keeps its structure and places workouts on your preferred days.",
                                norwegian: "Velg startdato og treningsdager. ATHLTH beholder oppbyggingen og legger øktene på dagene du ønsker."
                            ),
                        icon: "slider.horizontal.3",
                        accent: ATHLTHTheme.accent
                    ) {
                        HStack(spacing: 8) {
                            LibraryStatPill(
                                value: "\(entry.durationWeeks)",
                                label: "weeks",
                                icon: "calendar",
                                tint: ATHLTHTheme.accent
                            )

                            LibraryStatPill(
                                value: "\(entry.sessionsPerWeek)",
                                label: "days / week",
                                icon: "repeat",
                                tint: ATHLTHTheme.vitality
                            )
                        }
                    }

                    ATHLTHPlanGhostCard {
                        VStack(alignment: .leading, spacing: 13) {
                            Text("START")
                                .font(.caption2.weight(.bold))
                                .tracking(1.6)
                                .foregroundStyle(
                                    ATHLTHTheme.mutedText
                                )

                            DatePicker(
                                ATHLTHLocalization.choose(
                                    english: "Preferred start",
                                    norwegian: "Ønsket start"
                                ),
                                selection: $startDate,
                                in: Calendar.current.startOfDay(
                                    for: Date()
                                )...,
                                displayedComponents: .date
                            )

                            Divider()

                            HStack {
                                Text(ATHLTHLocalization.choose(
                                    english: "Plan begins", norwegian: "Planen starter"
                                ))
                                    .font(.subheadline)
                                    .foregroundStyle(
                                        ATHLTHTheme.mutedText
                                    )

                                Spacer()

                                Text(
                                    resolvedStartDate.formatted(
                                        date: .abbreviated,
                                        time: .omitted
                                    )
                                )
                                .font(.subheadline.weight(.semibold))
                            }

                            Text(
                                ATHLTHLocalization.choose(
                                    english: "Library plans run Monday–Sunday. ATHLTH starts this plan on the first Monday on or after your preferred date.",
                                    norwegian: "Bibliotekplaner går fra mandag til søndag. Planen starter første mandag på eller etter ønsket dato."
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            Divider()

                            HStack {
                                Text(ATHLTHLocalization.choose(
                                        english: "Estimated finish", norwegian: "Forventet sluttdato"
                                    ))
                                    .font(.subheadline)
                                    .foregroundStyle(
                                        ATHLTHTheme.mutedText
                                    )

                                Spacer()

                                Text(
                                    endDate.formatted(
                                        date: .abbreviated,
                                        time: .omitted
                                    )
                                )
                                .font(.subheadline.weight(.semibold))
                            }
                        }
                    }

                    ATHLTHPlanGhostCard {
                        VStack(alignment: .leading, spacing: 13) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(ATHLTHLocalization.choose(
                                        english: "TRAINING DAYS", norwegian: "TRENINGSDAGER"
                                    ))
                                        .font(
                                            .system(
                                                size: 9,
                                                weight: .bold
                                            )
                                        )
                                        .tracking(1.6)
                                        .foregroundStyle(
                                            ATHLTHTheme.mutedText
                                        )

                                    Text(
                                        "Choose \(entry.sessionsPerWeek) days"
                                    )
                                    .font(.headline)
                                }

                                Spacer()

                                Text(
                                    "\(selectedDays.count)/\(entry.sessionsPerWeek)"
                                )
                                .font(.caption.weight(.bold))
                                .foregroundStyle(
                                    hasValidDays
                                        ? ATHLTHTheme.vitality
                                        : ATHLTHTheme.accent
                                )
                            }

                            HStack(spacing: 7) {
                                ForEach(1...7, id: \.self) { day in
                                    let selected =
                                        selectedDays.contains(day)

                                    Button {
                                        toggleDay(day)
                                    } label: {
                                        Text(dayLabels[day - 1])
                                            .font(
                                                .system(
                                                    size: 11,
                                                    weight: .bold
                                                )
                                            )
                                            .foregroundStyle(
                                                selected
                                                    ? Color.white
                                                    : ATHLTHTheme
                                                        .primaryText
                                                        .opacity(0.72)
                                            )
                                            .frame(
                                                maxWidth: .infinity
                                            )
                                            .frame(height: 42)
                                            .background(
                                                selected
                                                    ? ATHLTHTheme.accent
                                                    : Color.white
                                                        .opacity(0.70),
                                                in: RoundedRectangle(
                                                    cornerRadius: 12,
                                                    style: .continuous
                                                )
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            Text(
                                "The plan keeps its workout order. ATHLTH maps session 1, 2, 3 and so on to your selected days each week."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }

                    ATHLTHPlanGhostCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(ATHLTHLocalization.choose(
                        english: "PLAN FIT", norwegian: "PLANPASSFORM"
                    ))
                                .font(.caption2.weight(.bold))
                                .tracking(1.6)
                                .foregroundStyle(
                                    ATHLTHTheme.mutedText
                                )

                            Label(
                                entry.level,
                                systemImage: "speedometer"
                            )
                            .font(.subheadline.weight(.semibold))

                            Label(
                                entry.goal,
                                systemImage: "scope"
                            )
                            .font(.subheadline.weight(.semibold))

                            Text(
                                "You can still edit individual workouts, exercises, routes and targets after the plan is created."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }

                    if let existing =
                        existingScheduledPlan {
                        HStack(
                            alignment: .top,
                            spacing: 11
                        ) {
                            Image(
                                systemName:
                                    "checkmark.circle.fill"
                            )
                            .foregroundStyle(
                                ATHLTHTheme.vitality
                            )

                            VStack(
                                alignment: .leading,
                                spacing: 3
                            ) {
                                Text(
                                    "Plan already scheduled"
                                )
                                .font(
                                    .subheadline
                                        .weight(
                                            .semibold
                                        )
                                )

                                Text(
                                    "\(existing.title) starts \((existing.startDate ?? resolvedStartDate).formatted(date: .abbreviated, time: .omitted)). Open it instead of creating a duplicate."
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    .secondary
                                )
                            }
                        }
                        .padding(14)
                        .background(
                            ATHLTHTheme
                                .vitalitySoft
                                .opacity(0.58),
                            in:
                                RoundedRectangle(
                                    cornerRadius: 16,
                                    style: .continuous
                                )
                        )
                    } else if let conflict =
                                conflictingPlan {
                        HStack(alignment: .top, spacing: 11) {
                            Image(
                                systemName:
                                    "calendar.badge.exclamationmark"
                            )
                            .foregroundStyle(Color.orange)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(ATHLTHLocalization.choose(
                                    english: "This overlaps another plan",
                                    norwegian: "Perioden overlapper en annen plan"
                                ))
                                    .font(.subheadline.weight(.semibold))

                                Text(
                                    ATHLTHLocalization.choose(
                                        english: "\(conflict.title) already covers part of these dates. Choose another start date.",
                                        norwegian: "\(conflict.title) dekker allerede deler av perioden. Velg en annen startdato."
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .padding(14)
                        .background(
                            Color.orange.opacity(0.08),
                            in: RoundedRectangle(
                                cornerRadius: 16,
                                style: .continuous
                            )
                        )
                    }

                    Button {
                        if let existing =
                            existingScheduledPlan {
                            existingPlanToOpen =
                                existing
                        } else {
                            createScheduledPlan()
                        }
                    } label: {
                        HStack {
                            Label(
                                createEditableCopy
                                    ? ATHLTHLocalization.choose(
                                        english: "Build my version",
                                        norwegian: "Bygg min versjon"
                                    )
                                    : existingScheduledPlan == nil
                                        ? ATHLTHLocalization.choose(
                                            english: "Create my plan",
                                            norwegian: "Opprett min plan"
                                        )
                                        : ATHLTHLocalization.choose(
                                            english: "Open existing plan",
                                            norwegian: "Åpne eksisterende plan"
                                        ),
                                systemImage:
                                    existingScheduledPlan == nil
                                        ? "calendar.badge.plus"
                                        : "calendar"
                            )
                            .font(.headline)

                            Spacer()

                            Image(systemName: "arrow.right")
                                .font(.caption.bold())
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 17)
                        .frame(height: 54)
                        .background(
                            existingScheduledPlan == nil
                                ? ATHLTHTheme.accentDeep
                                : ATHLTHTheme.vitality,
                            in: RoundedRectangle(
                                cornerRadius: 16,
                                style: .continuous
                            )
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(
                        !hasValidDays ||
                        (
                            conflictingPlan != nil &&
                            existingScheduledPlan == nil
                        )
                    )
                    .opacity(
                        !hasValidDays ||
                        (
                            conflictingPlan != nil &&
                            existingScheduledPlan == nil
                        )
                            ? 0.45
                            : 1
                    )

                }
                .padding(18)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(
                ATHLTHPremiumCanvas(
                    accent: ATHLTHTheme.accent.opacity(0.24)
                )
            )
            .navigationTitle(
                createEditableCopy
                    ? ATHLTHLocalization.choose(
                        english: "Build from this plan",
                        norwegian: "Bygg fra denne planen"
                    )
                    : ATHLTHLocalization.choose(
                        english: "Make it mine",
                        norwegian: "Gjør den til min"
                    )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Close",
                        norwegian: "Lukk"
                    )) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                guard !configured else { return }
                configured = true
                startDate =
                    session.suggestedTrainingPlanStartDate
                selectedDays = Set(
                    defaultDays(
                        for: entry.sessionsPerWeek
                    )
                )
            }
            .sheet(
                item: $existingPlanToOpen
            ) { plan in
                NavigationStack {
                    ScrollView {
                        AdvancedPlannerView(
                            planID: plan.id
                        )
                        .padding()
                    }
                    .background(
                        ATHLTHPremiumCanvas(
                            accent:
                                ATHLTHTheme
                                    .accent
                                    .opacity(0.35)
                        )
                    )
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(ATHLTHLocalization.choose(english: "Close", norwegian: "Lukk")) {
                                existingPlanToOpen = nil
                            }
                        }
                    }
                    .navigationTitle(plan.title)
                    .navigationBarTitleDisplayMode(
                        .inline
                    )
                }
            }
            .alert(
                "Could not create plan",
                isPresented: Binding(
                    get: { scheduleError != nil },
                    set: { shown in
                        if !shown {
                            scheduleError = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(scheduleError ?? "")
            }
        }
    }

    private func toggleDay(
        _ day: Int
    ) {
        if selectedDays.contains(day) {
            selectedDays.remove(day)
            return
        }

        guard selectedDays.count < entry.sessionsPerWeek
        else {
            return
        }

        selectedDays.insert(day)
    }

    private func defaultDays(
        for count: Int
    ) -> [Int] {
        switch count {
        case 2: return [2, 5]
        case 3: return [2, 4, 6]
        case 4: return [1, 3, 5, 7]
        case 5: return [1, 2, 4, 5, 7]
        default: return [1, 2, 3, 4, 5, 6]
        }
    }

    private func createScheduledPlan() {
        guard hasValidDays, conflictingPlan == nil else { return }

        let plan: TrainingPlan?
        if createEditableCopy {
            // A separate plan is scheduled from a private reusable copy.
            // The curated catalog entry itself is never mutated.
            if let template = session.saveCatalogPlanTemplate(
                entry,
                preferredDayIndexes: selectedDays.sorted()
            ) {
                let created = session.usePlanTemplate(
                    template.id,
                    startDate: resolvedStartDate
                )
                if created == nil {
                    // Do not leave a stray template if scheduling failed.
                    session.deletePlanTemplate(template.id)
                }
                plan = created
            } else {
                plan = nil
            }
        } else {
            plan = session.scheduleCatalogPlan(
                entry,
                startDate: resolvedStartDate,
                preferredDayIndexes: selectedDays.sorted()
            )
        }

        guard let plan else {
            scheduleError = ATHLTHLocalization.choose(
                english: "The plan could not be scheduled. Choose dates that do not overlap an existing plan.",
                norwegian: "Planen kunne ikke opprettes. Velg datoer som ikke overlapper en eksisterende plan."
            )
            return
        }

        existingPlanToOpen = plan
        onPlanCreated?()
    }
}

struct MyTrainingPlansLibraryView: View {
    var onOpenPlan: ((UUID) -> Void)? = nil

    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var exerciseLibrary: ExerciseLibraryStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strengthWorkout: StrengthWorkoutStore

    @State private var showingCreatePlan = false
    @State private var scheduleError: String?
    @State private var reviewingPlan: TrainingPlan?
    @State private var preparedShare: MessageShareDraft?
    @State private var shareError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                LibraryPremiumIntro(
                    eyebrow: "MY PLANS",
                    title: "Your training, organised",
                    subtitle:
                        "Keep reusable plans close, schedule what comes next and jump back into your active program.",
                    icon: "calendar.badge.clock",
                    accent: ATHLTHTheme.accent
                ) {
                    HStack(spacing: 8) {
                        LibraryStatPill(
                            value: "\(session.planTemplates.count)",
                            label: "saved",
                            icon: "bookmark.fill",
                            tint: ATHLTHTheme.premiumGold
                        )

                        LibraryStatPill(
                            value: "\(session.trainingPlans.count)",
                            label: "scheduled",
                            icon: "calendar",
                            tint: ATHLTHTheme.accent
                        )

                        if activePlanCount > 0 {
                            LibraryStatPill(
                                value: "\(activePlanCount)",
                                label: "active",
                                icon: "play.fill",
                                tint: ATHLTHTheme.vitality
                            )
                        }
                    }
                }

                if !session.planTemplates.isEmpty {
                    planSectionHeader(
                        "Saved Plans",
                        detail: "Reusable plans that are not on your calendar yet."
                    )

                    ForEach(session.planTemplates) { template in
                        templateCard(template)
                    }
                }

                if !session.trainingPlans.isEmpty {
                    planSectionHeader(
                        "Scheduled Plans",
                        detail: "Active, upcoming and completed plans."
                    )

                    ForEach(session.trainingPlans) { plan in
                        let progress = planProgress(plan)

                        VStack(spacing: 8) {
                            if let onOpenPlan {
                                Button {
                                    onOpenPlan(plan.id)
                                } label: {
                                    scheduledPlanCard(
                                        plan,
                                        progress: progress
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint(ATHLTHLocalization.choose(
                                    english: "Opens this program in Train, Plan.",
                                    norwegian: "Åpner programmet i Tren, Plan."
                                ))
                            } else {
                                NavigationLink {
                                    ScrollView {
                                        AdvancedPlannerView(
                                            planID: plan.id
                                        )
                                        .padding()
                                    }
                                    .background(
                                        ATHLTHPremiumCanvas(
                                            accent:
                                                ATHLTHTheme.accent
                                                .opacity(0.35)
                                        )
                                    )
                                    .navigationTitle(plan.title)
                                    .navigationBarTitleDisplayMode(.inline)
                                } label: {
                                    scheduledPlanCard(
                                        plan,
                                        progress: progress
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            Button {
                                preparePlanShare(plan)
                            } label: {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english: "Share plan", norwegian: "Del plan"
                                    ),
                                    systemImage: "square.and.arrow.up"
                                )
                                .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity, alignment: .trailing)

                            if !progress.missed.isEmpty {
                                Button {
                                    reviewingPlan = plan
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(
                                            systemName:
                                                "clock.arrow.circlepath"
                                        )

                                        Text(
                                            missedWorkoutReviewTitle(
                                                progress.missed.count
                                            )
                                        )
                                        .font(
                                            .caption.weight(.semibold)
                                        )

                                        Spacer()

                                        Image(
                                            systemName: "chevron.right"
                                        )
                                        .font(.caption2.bold())
                                    }
                                    .foregroundStyle(Color.orange)
                                    .padding(.horizontal, 12)
                                    .frame(height: 38)
                                    .background(
                                        Color.orange.opacity(0.08),
                                        in: RoundedRectangle(
                                            cornerRadius: 12,
                                            style: .continuous
                                        )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if session.planTemplates.isEmpty &&
                    session.trainingPlans.isEmpty {
                    ContentUnavailableView {
                        Label(
                            "No plans yet",
                            systemImage: "calendar.badge.plus"
                        )
                    } description: {
                        Text(
                            "Save a plan from Plan Library or create one from scratch."
                        )
                    } actions: {
                        Button("Create Plan") {
                            showingCreatePlan = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ATHLTHTheme.accent)
                    }
                    .padding(.top, 36)
                }
            }
            .padding(18)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(
            ATHLTHPremiumCanvas(
                accent: ATHLTHTheme.accent.opacity(0.26)
            )
        )
        .navigationTitle(ATHLTHLocalization.choose(
            english: "My Plans", norwegian: "Mine planer"
        ))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCreatePlan = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Create training plan", norwegian: "Opprett treningsplan"
                ))
            }
        }
        .sheet(isPresented: $showingCreatePlan) {
            TrainingPlanCreationView()
        }
        .sheet(item: $preparedShare) { draft in
            ATHLTHDirectShareSheet(draft: draft)
        }
        .alert(
            ATHLTHLocalization.choose(
                english: "Could not share plan", norwegian: "Kunne ikke dele planen"
            ),
            isPresented: Binding(
                get: { shareError != nil },
                set: { if !$0 { shareError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(shareError ?? "")
        }
        .sheet(item: $reviewingPlan) { plan in
            MissedWorkoutsReviewView(
                planID: plan.id
            )
        }
        .alert(
            "Could not schedule plan",
            isPresented: Binding(
                get: { scheduleError != nil },
                set: { shown in
                    if !shown { scheduleError = nil }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(scheduleError ?? "")
        }
    }

    private func preparePlanShare(_ plan: TrainingPlan) {
        do {
            preparedShare = try ATHLTHShareDraftFactory.plan(
                plan, library: exerciseLibrary.allExercises,
                ownerID: session.profile.userID
            )
        } catch {
            shareError = error.localizedDescription
        }
    }

    private func templateCard(
        _ template: TrainingPlan
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accent)
                    .frame(width: 48, height: 48)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: RoundedRectangle(
                            cornerRadius: 15,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: 5) {
                    Text(ATHLTHLocalization.choose(
                        english: "SAVED PLAN", norwegian: "LAGRET PLAN"
                    ))
                        .font(.caption2.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(ATHLTHTheme.accent)

                    Text(template.title)
                        .font(.headline)
                        .foregroundStyle(ATHLTHTheme.primaryText)

                    Text(
                        ATHLTHLocalization.format(
                                english: "%d weeks · ready to schedule",
                                norwegian: "%d uker · klar til planlegging",
                                template.weeks.count
                            )
                    )
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }

                Spacer()

                Button(role: .destructive) {
                    session.deletePlanTemplate(template.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(
                            ATHLTHTheme.mutedText.opacity(0.72)
                        )
                        .frame(width: 34, height: 34)
                        .background(
                            Color.white.opacity(0.68),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
            }

            if !template.summary.isEmpty {
                Text(template.summary)
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .lineLimit(2)
            }

            Button {
                if let created = session.usePlanTemplate(
                    template.id,
                    startDate:
                        session.suggestedTrainingPlanStartDate
                ) {
                    onOpenPlan?(created.id)
                } else {
                    scheduleError = ATHLTHLocalization.choose(
                        english: "Another plan overlaps the suggested start date. Choose a different date when creating or scheduling the plan.",
                        norwegian: "En annen plan overlapper foreslått startdato. Velg en annen periode for planen."
                    )
                }
            } label: {
                HStack {
                    Label(
                        "Schedule Plan",
                        systemImage: "calendar.badge.plus"
                    )
                    .font(.subheadline.weight(.semibold))

                    Spacer()

                    Image(systemName: "arrow.right")
                        .font(.caption.bold())
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(
                    LinearGradient(
                        colors: [
                            ATHLTHTheme.accent,
                            ATHLTHTheme.accentDeep
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(
                        cornerRadius: 14,
                        style: .continuous
                    )
                )
            }
            .buttonStyle(.plain)

            Button {
                preparePlanShare(template)
            } label: {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Share plan", norwegian: "Del plan"
                    ),
                    systemImage: "square.and.arrow.up"
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 39)
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.96),
                    ATHLTHTheme.accent.opacity(0.035)
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
                Color.white.opacity(0.94),
                lineWidth: 1
            )
        }
        .shadow(
            color: ATHLTHTheme.accentDeep.opacity(0.035),
            radius: 13,
            y: 6
        )
    }

    private func scheduledPlanCard(
        _ plan: TrainingPlan,
        progress: TrainingPlanProgressSnapshot
    ) -> some View {
        let status = session.trainingPlanStatus(plan)

        return VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 13) {
            Image(systemName: statusIcon(status))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(statusTint(status))
                .frame(width: 48, height: 48)
                .background(
                    statusTint(status).opacity(0.10),
                    in: RoundedRectangle(
                        cornerRadius: 15,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(plan.title)
                        .font(.headline)
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )
                        .lineLimit(1)

                    Text(statusTitle(status))
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(statusTint(status))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            statusTint(status).opacity(0.10),
                            in: Capsule()
                        )
                }

                Text(
                    "\(plan.weeks.count) weeks · \(scheduledDateText(plan))"
                )
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

                Image(systemName: "arrow.right")
                    .font(.caption.bold())
                    .foregroundStyle(statusTint(status))
                    .frame(width: 30, height: 30)
                    .background(
                        statusTint(status).opacity(0.08),
                        in: Circle()
                    )
            }

            if progress.totalSessions > 0 &&
                status != .upcoming {
                ProgressView(
                    value: progress.completionFraction
                )
                .tint(statusTint(status))

                HStack {
                    Text(
                        progressLabel(
                            plan,
                            progress: progress,
                            status: status
                        )
                    )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )

                    Spacer()

                    if progress.skippedSessions > 0 {
                        Text(
                            ATHLTHLocalization.format(
                                english: "%d skipped",
                                norwegian: "%d hoppet over",
                                progress.skippedSessions
                            )
                        )
                        .font(.caption2)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                    }
                }
            }
        }
        .padding(15)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.95),
                    statusTint(status).opacity(0.025)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
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
                Color.white.opacity(0.94),
                lineWidth: 0.8
            )
        }
    }

    private func missedWorkoutReviewTitle(
        _ count: Int
    ) -> String {
        count == 1
            ? "Review 1 missed workout"
            : "Review \(count) missed workouts"
    }

    private func planProgress(
        _ plan: TrainingPlan
    ) -> TrainingPlanProgressSnapshot {
        session.trainingPlanProgress(
            plan,
            healthWorkouts: health.workouts,
            strengthHistory: strengthWorkout.workoutHistory
        )
    }

    private func progressLabel(
        _ plan: TrainingPlan,
        progress: TrainingPlanProgressSnapshot,
        status: TrainingPlanTimingStatus
    ) -> String {
        switch status {
        case .active:
            return "Week \(max(progress.currentWeek, 1)) of \(max(progress.totalWeeks, 1)) · \(progress.completedSessions)/\(progress.totalSessions) sessions"
        case .completed:
            return "\(progress.completedSessions)/\(progress.totalSessions) sessions completed"
        case .upcoming:
            return scheduledDateText(plan)
        case .unscheduled:
            return "\(progress.completedSessions)/\(progress.totalSessions) sessions"
        }
    }

    private func planSectionHeader(
        _ title: String,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(1.8)
                .foregroundStyle(ATHLTHTheme.mutedText)

            Text(detail)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(
                    ATHLTHTheme.primaryText.opacity(0.72)
                )
        }
        .padding(.top, 2)
    }

    private var activePlanCount: Int {
        session.trainingPlans.filter {
            session.trainingPlanStatus($0) == .active
        }.count
    }

    private func statusTitle(
        _ status: TrainingPlanTimingStatus
    ) -> String {
        switch status {
        case .active: return "ACTIVE"
        case .upcoming: return "UPCOMING"
        case .completed: return "COMPLETED"
        case .unscheduled: return "UNSCHEDULED"
        }
    }

    private func statusIcon(
        _ status: TrainingPlanTimingStatus
    ) -> String {
        switch status {
        case .active: return "play.fill"
        case .upcoming: return "calendar.badge.clock"
        case .completed: return "checkmark"
        case .unscheduled: return "calendar"
        }
    }

    private func statusTint(
        _ status: TrainingPlanTimingStatus
    ) -> Color {
        switch status {
        case .active: return ATHLTHTheme.vitality
        case .upcoming: return ATHLTHTheme.accent
        case .completed: return ATHLTHTheme.mutedText
        case .unscheduled: return Color.orange
        }
    }

    private func scheduledDateText(
        _ plan: TrainingPlan
    ) -> String {
        guard let start = plan.startDate else {
            return "Not dated"
        }

        return start.formatted(
            date: .abbreviated,
            time: .omitted
        )
    }
}


struct MissedWorkoutsReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strengthWorkout: StrengthWorkoutStore
    @EnvironmentObject private var subscriptionStore: SubscriptionStore

    let planID: UUID

    @State private var actionError: String?
    @State private var pendingRecoveryWarning: TrainingPlanSessionOccurrence?
    @State private var showingCoach = false
    @State private var showingSubscriptionOffer = false

    private var plan: TrainingPlan? {
        session.trainingPlan(withID: planID)
    }

    private var progress: TrainingPlanProgressSnapshot? {
        guard let plan else { return nil }

        return session.trainingPlanProgress(
            plan,
            healthWorkouts: health.workouts,
            strengthHistory: strengthWorkout.workoutHistory
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let plan, let progress {
                        LibraryPremiumIntro(
                            eyebrow: "PLAN REVIEW",
                            title:
                                progress.missed.isEmpty
                                    ? "You’re caught up"
                                    : "Missed workouts",
                            subtitle:
                                progress.missed.isEmpty
                                    ? "There are no unresolved workouts in \(plan.title)."
                                    : "Decide what happens next. ATHLTH will never move or mark a missed workout without you choosing.",
                            icon: "clock.arrow.circlepath",
                            accent:
                                progress.missed.isEmpty
                                    ? ATHLTHTheme.vitality
                                    : Color.orange
                        ) {
                            HStack(spacing: 8) {
                                LibraryStatPill(
                                    value:
                                        "\(progress.completedSessions)",
                                    label: "completed",
                                    icon: "checkmark",
                                    tint: ATHLTHTheme.vitality
                                )

                                LibraryStatPill(
                                    value:
                                        "\(progress.missed.count)",
                                    label: "to review",
                                    icon: "clock",
                                    tint: Color.orange
                                )
                            }
                        }

                        if progress.missed.isEmpty {
                            VStack(spacing: 12) {
                                Image(
                                    systemName:
                                        "checkmark.circle.fill"
                                )
                                .font(.system(size: 34))
                                .foregroundStyle(
                                    ATHLTHTheme.vitality
                                )

                                Text(ATHLTHLocalization.choose(
                                    english: "Nothing needs your attention",
                                    norwegian: "Alt er i rute"
                                ))
                                    .font(.headline)

                                Text(
                                    ATHLTHLocalization.choose(
                                        english: "Your plan can continue exactly as scheduled.",
                                        norwegian: "Planen kan fortsette som planlagt."
                                    )
                                )
                                .font(.subheadline)
                                .foregroundStyle(
                                    ATHLTHTheme.mutedText
                                )
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 34)
                            .background(
                                Color.white.opacity(0.78),
                                in: RoundedRectangle(
                                    cornerRadius: 24,
                                    style: .continuous
                                )
                            )
                        } else {
                            ForEach(progress.missed) { occurrence in
                                missedCard(occurrence)
                            }

                            if session.activePlan?.id == planID {
                                Button {
                                    openCoach()
                                } label: {
                                    HStack {
                                        Label(
                                            "Ask ATHLTH Coach",
                                            systemImage: "sparkles"
                                        )
                                        .font(.subheadline.weight(.semibold))

                                        Spacer()

                                        Image(systemName: "arrow.right")
                                            .font(.caption.bold())
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 15)
                                    .frame(height: 48)
                                    .background(
                                        ATHLTHTheme.accentDeep,
                                        in: RoundedRectangle(
                                            cornerRadius: 15,
                                            style: .continuous
                                        )
                                    )
                                }
                                .buttonStyle(.plain)

                                Text(
                                    "Coach can review the active plan and suggest broader changes. Nothing changes until you accept the proposal."
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    ATHLTHTheme.mutedText
                                )
                            }
                        }
                    } else {
                        ContentUnavailableView(
                            "Plan unavailable",
                            systemImage: "calendar.badge.exclamationmark",
                            description: Text(
                                "This plan is no longer available."
                            )
                        )
                    }
                }
                .padding(18)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(
                ATHLTHPremiumCanvas(
                    accent: Color.orange.opacity(0.18)
                )
            )
            .navigationTitle("Missed Workouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingCoach) {
                CoachPlanAdaptationView()
            }
            .sheet(isPresented: $showingSubscriptionOffer) {
                SubscriptionOfferView {
                    session.applyStoreKitEntitlement(
                        subscriptionStore.activeEntitlement
                    )

                    if session.canAccess(.aiTrainingPrograms) {
                        showingSubscriptionOffer = false
                        showingCoach = true
                    }
                }
                .environmentObject(subscriptionStore)
            }
            .confirmationDialog(
                ATHLTHLocalization.choose(
                    english: "Strength sessions close together",
                    norwegian: "Styrkeøkter tett på hverandre"
                ),
                isPresented: Binding(
                    get: { pendingRecoveryWarning != nil },
                    set: { shown in
                        if !shown { pendingRecoveryWarning = nil }
                    }
                ),
                titleVisibility: .visible
            ) {
                if let occurrence = pendingRecoveryWarning {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Move anyway",
                            norwegian: "Flytt likevel"
                        )
                    ) {
                        moveToTomorrow(occurrence)
                        pendingRecoveryWarning = nil
                    }
                }
                Button(
                    ATHLTHLocalization.choose(
                        english: "Keep schedule",
                        norwegian: "Behold planen"
                    ),
                    role: .cancel
                ) {
                    pendingRecoveryWarning = nil
                }
            } message: {
                Text(
                    ATHLTHLocalization.choose(
                        english: "Another strength workout is planned on this day or the day before/after. Consider recovery before moving.",
                        norwegian: "En annen styrkeøkt er planlagt samme dag eller dagen før/etter. Vurder restitusjonen før du flytter."
                    )
                )
            }
            .alert(
                "Could not update workout",
                isPresented: Binding(
                    get: { actionError != nil },
                    set: { shown in
                        if !shown {
                            actionError = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(actionError ?? "")
            }
        }
    }

    private func missedCard(
        _ occurrence: TrainingPlanSessionOccurrence
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                Image(
                    systemName:
                        occurrence.session.kind.systemImage
                )
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.orange)
                .frame(width: 44, height: 44)
                .background(
                    Color.orange.opacity(0.09),
                    in: RoundedRectangle(
                        cornerRadius: 14,
                        style: .continuous
                    )
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        occurrence.date.formatted(
                            date: .abbreviated,
                            time: .omitted
                        )
                    )
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.orange)

                    Text(occurrence.session.title)
                        .font(.headline)
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )

                    Text(
                        ATHLTHLocalization.format(
                                english: "Week %d · %@",
                                norwegian: "Uke %d · %@",
                                occurrence.weekNumber,
                                sessionSummary(occurrence.session)
                            )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }

                Spacer()
            }

            HStack(spacing: 9) {
                Button {
                    if needsRecoveryWarning(whenMoving: occurrence) {
                        pendingRecoveryWarning = occurrence
                    } else {
                        moveToTomorrow(occurrence)
                    }
                } label: {
                    Label(
                        "Tomorrow",
                        systemImage: "arrow.right.circle"
                    )
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                }
                .buttonStyle(.bordered)
                .tint(ATHLTHTheme.accent)

                Button {
                    session.setPlanSessionSkipped(
                        planID: planID,
                        sessionID: occurrence.session.id,
                        skipped: true
                    )
                } label: {
                    Label(
                        "Skip",
                        systemImage: "forward.end"
                    )
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                }
                .buttonStyle(.bordered)
                .tint(ATHLTHTheme.mutedText)
            }
        }
        .padding(15)
        .background(
            Color.white.opacity(0.86),
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
                Color.orange.opacity(0.09),
                lineWidth: 0.8
            )
        }
    }

    private func needsRecoveryWarning(
        whenMoving occurrence: TrainingPlanSessionOccurrence
    ) -> Bool {
        guard occurrence.session.kind == .strength,
              let plan,
              let start = plan.startDate
        else { return false }

        let calendar = Calendar.current
        let tomorrow = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        )
        let firstDay = calendar.startOfDay(for: start)

        for (weekIndex, week) in plan.weeks.enumerated() {
            for day in week.days {
                let plannedDay = calendar.date(
                    byAdding: .day,
                    value: weekIndex * 7 + max(day.dayIndex - 1, 0),
                    to: firstDay
                ) ?? firstDay

                for workout in day.sessions
                where workout.id != occurrence.session.id && workout.kind == .strength {
                    let existingDay = calendar.startOfDay(
                        for: workout.scheduledStart ?? plannedDay
                    )
                    let gap = calendar.dateComponents(
                        [.day], from: tomorrow, to: existingDay
                    ).day ?? Int.max
                    if abs(gap) <= 1 {
                        return true
                    }
                }
            }
        }
        return false
    }

    private func moveToTomorrow(
        _ occurrence: TrainingPlanSessionOccurrence
    ) {
        let tomorrow =
            Calendar.current.date(
                byAdding: .day,
                value: 1,
                to: Date()
            ) ?? Date()

        guard session.movePlanSession(
            planID: planID,
            sessionID: occurrence.session.id,
            to: tomorrow
        ) else {
            actionError =
                "This workout cannot be moved to tomorrow because that date is outside the plan window."
            return
        }
    }

    private func openCoach() {
        guard session.canAccess(.aiTrainingPrograms) else {
            showingSubscriptionOffer = true
            return
        }

        showingCoach = true
    }

    private func sessionSummary(
        _ planned: PlannedSession
    ) -> String {
        var parts: [String] = []

        if let duration = planned.durationMinutes {
            parts.append("\(duration) min")
        }

        if !planned.exercises.isEmpty {
            parts.append(
                "\(planned.exercises.count) exercises"
            )
        }

        if let distance =
                planned.targetDistanceKilometers {
            parts.append(
                String(
                    format: "%.1f km",
                    distance
                )
            )
        }

        return parts.isEmpty
            ? planned.kind.title
            : parts.joined(separator: " · ")
    }
}

struct LibraryFavoritesView: View {
    @EnvironmentObject private var favorites: LibraryFavoritesStore
    @EnvironmentObject private var recents: LibraryRecentsStore
    @EnvironmentObject private var runningLibrary: RunningWorkoutLibraryStore
    @EnvironmentObject private var exerciseLibrary: ExerciseLibraryStore
    @EnvironmentObject private var session: AppSessionStore

    let onStartRunning: (RunningWorkoutTemplate) -> Void

    @StateObject private var planLibrary = TrainingPlanLibraryStore()
    @StateObject private var workoutLibrary =
        WorkoutTemplateCatalogStore()
    @State private var selectedKind: LibraryFavoriteKind?

    private var displayedFavorites: [LibraryFavoriteRecord] {
        guard let selectedKind else {
            return favorites.favorites
        }

        return favorites.favorites.filter {
            $0.itemType == selectedKind
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                LibraryPremiumIntro(
                    eyebrow: "FAVORITES",
                    title: "Your fastest way back",
                    subtitle:
                        "Keep the plans, workouts, exercises and routes you return to most in one place.",
                    icon: "star.fill",
                    accent: ATHLTHTheme.premiumGold
                ) {
                    HStack(spacing: 8) {
                        LibraryStatPill(
                            value: "\(favorites.favorites.count)",
                            label: "saved",
                            icon: "star.fill",
                            tint: ATHLTHTheme.premiumGold
                        )

                        if let selectedKind {
                            LibraryStatPill(
                                value: "\(favorites.count(for: selectedKind))",
                                label: selectedKind.title.lowercased(),
                                icon: selectedKind.systemImage,
                                tint: favoriteTint(selectedKind)
                            )
                        } else {
                            LibraryStatPill(
                                value: "\(favoriteKindsInUse)",
                                label: "types",
                                icon: "square.grid.2x2.fill",
                                tint: ATHLTHTheme.accent
                            )
                        }
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        favoriteFilter(
                            "All",
                            icon: "sparkles",
                            selected: selectedKind == nil
                        ) {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                selectedKind = nil
                            }
                        }

                        ForEach(LibraryFavoriteKind.allCases) { kind in
                            favoriteFilter(
                                kind.title,
                                icon: kind.systemImage,
                                selected: selectedKind == kind
                            ) {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    selectedKind = kind
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }

                if displayedFavorites.isEmpty {
                    VStack(spacing: 15) {
                        Image(systemName: "star")
                            .font(.system(size: 27, weight: .medium))
                            .foregroundStyle(
                                ATHLTHTheme.premiumGold
                            )
                            .frame(width: 66, height: 66)
                            .background(
                                ATHLTHTheme.premiumGold.opacity(0.10),
                                in: Circle()
                            )

                        VStack(spacing: 5) {
                            Text(ATHLTHLocalization.choose(
                                english: "Nothing saved here yet",
                                norwegian: "Ingen lagrede favoritter ennå"
                            ))
                                .font(.title3.weight(.semibold))

                            Text(
                                ATHLTHLocalization.choose(
                                    english: "Tap the star on a plan, workout, exercise or route and it will appear here.",
                                    norwegian: "Trykk på stjernen ved en plan, økt, øvelse eller rute for å lagre den her."
                                )
                            )
                            .font(.subheadline)
                            .foregroundStyle(
                                ATHLTHTheme.mutedText
                            )
                            .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 34)
                    .padding(.horizontal, 22)
                    .background(
                        Color.white.opacity(0.78),
                        in: RoundedRectangle(
                            cornerRadius: 25,
                            style: .continuous
                        )
                    )
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(displayedFavorites) { item in
                            HStack(spacing: 8) {
                                NavigationLink {
                                    favoriteDestination(item)
                                } label: {
                                    favoriteRow(item)
                                }
                                .buttonStyle(.plain)
                                .simultaneousGesture(
                                    TapGesture().onEnded {
                                        recents.markUsed(
                                            item.itemType,
                                            itemID: item.itemID,
                                            title: item.title,
                                            subtitle: item.subtitle,
                                            icon: item.icon
                                        )
                                    }
                                )

                                LibraryFavoriteButton(
                                    kind: item.itemType,
                                    itemID: item.itemID,
                                    title: item.title,
                                    subtitle: item.subtitle,
                                    icon: item.icon
                                )
                            }
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(
            ATHLTHPremiumCanvas(
                accent: ATHLTHTheme.premiumGold.opacity(0.20)
            )
        )
        .navigationTitle("Favorites")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            recents.refresh()
            async let saved: Void = favorites.refresh()
            async let plans: Void = planLibrary.refresh()
            async let workouts: Void = workoutLibrary.refresh()
            async let exercises: Void = exerciseLibrary.refresh()
            _ = await (
                saved,
                plans,
                workouts,
                exercises
            )
        }
    }

    @ViewBuilder
    private func favoriteDestination(
        _ item: LibraryFavoriteRecord
    ) -> some View {
        switch item.itemType {
        case .plan:
            if let entry = planLibrary.entries.first(
                where: {
                    $0.id.uuidString
                        .caseInsensitiveCompare(item.itemID)
                        == .orderedSame
                }
            ) {
                TrainingPlanCatalogDetailView(entry: entry)
            } else {
                TrainingPlanLibraryView()
            }

        case .workout:
            if let id = UUID(uuidString: item.itemID),
               let workout = runningLibrary.allTemplates.first(
                    where: { $0.id == id }
               ) {
                RunningWorkoutDetailView(
                    workout: workout,
                    selectionTitle: nil,
                    onSelect: nil,
                    onStart: onStartRunning
                )
            } else if let id =
                        UUID(uuidString: item.itemID),
                      let workout =
                        workoutLibrary.entries.first(
                            where: { $0.id == id }
                        ) {
                WorkoutTemplateDetailView(
                    entry: workout
                )
            } else {
                WorkoutTemplateLibraryView()
            }

        case .exercise:
            if let id = UUID(uuidString: item.itemID),
               let entry = exerciseLibrary.search(
                    query: "",
                    bodyPart: "All",
                    equipment: "All"
               ).first(
                    where: { $0.id == id }
               ) {
                ExerciseDetailView(
                    entry: entry,
                    selectionTitle: nil,
                    onSelect: nil
                )
            } else {
                ExerciseLibraryView(source: .library)
            }

        case .route:
            if let id = UUID(uuidString: item.itemID),
               let saved = session.savedRoutes.first(
                    where: { $0.id == id }
               ) {
                RouteDetailView(route: saved)
            } else if let id = UUID(uuidString: item.itemID) {
                RouteLibraryDetailLoader(routeID: id)
            } else {
                RouteLibraryListView(source: .database)
            }
        }
    }

    private func favoriteFilter(
        _ title: String,
        icon: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption2.weight(.bold))

                Text(title)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(
                selected
                    ? Color.white
                    : ATHLTHTheme.primaryText.opacity(0.80)
            )
            .padding(.horizontal, 13)
            .frame(height: 38)
            .background(
                selected
                    ? ATHLTHTheme.accentDeep
                    : Color.white.opacity(0.84),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(
                        selected
                            ? Color.white.opacity(0.16)
                            : Color.black.opacity(0.035),
                        lineWidth: 0.8
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private func favoriteRow(
        _ item: LibraryFavoriteRecord
    ) -> some View {
        let tint = favoriteTint(item.itemType)

        return HStack(spacing: 13) {
            Image(
                systemName:
                    item.icon ??
                    item.itemType.systemImage
            )
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 46, height: 46)
            .background(
                tint.opacity(0.10),
                in: RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(item.itemType.title.uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(tint)

                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .lineLimit(2)

                Text(
                    item.subtitle ??
                    item.itemType.title
                )
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "arrow.right")
                .font(.caption.bold())
                .foregroundStyle(tint)
                .frame(width: 29, height: 29)
                .background(
                    tint.opacity(0.08),
                    in: Circle()
                )
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.96),
                    tint.opacity(0.025)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 21,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 21,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.94),
                lineWidth: 0.8
            )
        }
    }

    private var favoriteKindsInUse: Int {
        Set(favorites.favorites.map(\.itemType)).count
    }

    private func favoriteTint(
        _ kind: LibraryFavoriteKind
    ) -> Color {
        switch kind {
        case .plan:
            return Color.orange
        case .workout:
            return ATHLTHTheme.vitality
        case .exercise:
            return Color.indigo
        case .route:
            return Color.green
        }
    }
}

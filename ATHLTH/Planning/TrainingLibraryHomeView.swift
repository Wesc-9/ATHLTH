import Foundation
import Supabase
import SwiftUI

struct TrainingLibraryHomeView: View {
    @EnvironmentObject private var favorites: LibraryFavoritesStore
    @EnvironmentObject private var recents: LibraryRecentsStore
    @EnvironmentObject private var runningLibrary: RunningWorkoutLibraryStore
    @EnvironmentObject private var exerciseLibrary: ExerciseLibraryStore
    @EnvironmentObject private var session: AppSessionStore

    let onStartRunning: (RunningWorkoutTemplate) -> Void

    @StateObject private var planCatalog = TrainingPlanLibraryStore()
    @State private var showingCreatePlan = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            LibraryPremiumIntro(
                eyebrow: "TRAINING LIBRARY",
                title: "Everything you train with",
                subtitle:
                    "Plans, workouts, exercises and routes — curated, saved and ready when you are.",
                icon: "square.grid.2x2.fill",
                accent: ATHLTHTheme.accent
            ) {
                HStack(spacing: 8) {
                    LibraryStatPill(
                        value: "\(favorites.favorites.count)",
                        label: "favorites",
                        icon: "star.fill",
                        tint: ATHLTHTheme.premiumGold
                    )

                    LibraryStatPill(
                        value: "4",
                        label: "collections",
                        icon: "square.stack.3d.up.fill",
                        tint: ATHLTHTheme.accent
                    )
                }
            }

            if !recents.items.isEmpty {
                recentSection
            }

            librarySection(
                "Your Library",
                subtitle: "Keep the things you use most close at hand."
            ) {
                NavigationLink {
                    LibraryFavoritesView(
                        onStartRunning: onStartRunning
                    )
                } label: {
                    LibraryDestinationTile(
                        title: "Favorites",
                        subtitle:
                            favorites.favorites.isEmpty
                                ? "Save plans, workouts & more"
                                : "\(favorites.favorites.count) saved items",
                        icon: "star.fill",
                        tint: ATHLTHTheme.premiumGold
                    )
                }

                NavigationLink {
                    MyTrainingPlansLibraryView()
                } label: {
                    LibraryDestinationTile(
                        title: "My Plans",
                        subtitle: "Created, saved & scheduled",
                        icon: "calendar.badge.clock",
                        tint: ATHLTHTheme.accent
                    )
                }
            }

            librarySection(
                "Training Plans",
                subtitle: "Start from a proven structure or build your own."
            ) {
                NavigationLink {
                    TrainingPlanLibraryView()
                } label: {
                    LibraryDestinationTile(
                        title: "Plan Library",
                        subtitle: "Running, strength & hybrid",
                        icon: "square.stack.3d.up.fill",
                        tint: Color.orange
                    )
                }

                Button {
                    showingCreatePlan = true
                } label: {
                    LibraryDestinationTile(
                        title: "Create Plan",
                        subtitle: "Build it your way",
                        icon: "plus.rectangle.on.rectangle",
                        tint: ATHLTHTheme.accent
                    )
                }
            }

            librarySection(
                "Running",
                subtitle: "Intervals, tempo sessions and saved workouts."
            ) {
                NavigationLink {
                    RunningWorkoutLibraryView(
                        source: .library,
                        onStart: onStartRunning
                    )
                } label: {
                    LibraryDestinationTile(
                        title: "Run Library",
                        subtitle: "Intervals, tempo & more",
                        icon: "figure.run",
                        tint: ATHLTHTheme.vitality
                    )
                }

                NavigationLink {
                    RunningWorkoutLibraryView(
                        source: .mine,
                        onStart: onStartRunning
                    )
                } label: {
                    LibraryDestinationTile(
                        title: "My Workouts",
                        subtitle: "Saved running sessions",
                        icon: "stopwatch",
                        tint: ATHLTHTheme.vitality
                    )
                }
            }

            librarySection(
                "Strength",
                subtitle: "Build from the exercise database or your own movements."
            ) {
                NavigationLink {
                    ExerciseLibraryView(source: .library)
                } label: {
                    LibraryDestinationTile(
                        title: "Exercises",
                        subtitle: "Muscles & equipment",
                        icon: "dumbbell.fill",
                        tint: Color.indigo
                    )
                }

                NavigationLink {
                    ExerciseLibraryView(source: .mine)
                } label: {
                    LibraryDestinationTile(
                        title: "My Exercises",
                        subtitle: "Created by you",
                        icon: "person.crop.square",
                        tint: Color.indigo
                    )
                }
            }

            librarySection(
                "Routes",
                subtitle: "Discover a new route or return to a favourite."
            ) {
                NavigationLink {
                    RouteLibraryListView(source: .database)
                } label: {
                    LibraryDestinationTile(
                        title: "Explore Routes",
                        subtitle: "Discover & filter",
                        icon: "map.fill",
                        tint: Color.green
                    )
                }

                NavigationLink {
                    RouteLibraryListView(source: .mine)
                } label: {
                    LibraryDestinationTile(
                        title: "My Routes",
                        subtitle: "Saved & created by you",
                        icon: "bookmark.fill",
                        tint: Color.green
                    )
                }
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingCreatePlan) {
            TrainingPlanCreationView()
        }
        .task {
            recents.refresh()
            async let favoriteRefresh: Void = favorites.refresh()
            async let planRefresh: Void = planCatalog.refresh()
            _ = await (favoriteRefresh, planRefresh)
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("RECENTLY USED")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.8)
                        .foregroundStyle(ATHLTHTheme.mutedText)

                    Text("Jump back in")
                        .font(.title3.weight(.bold))
                }

                Spacer()

                Text(ATHLTHLocalization.format(
                            english: "%d recent",
                            norwegian: "%d nylige",
                            min(recents.items.count, 4)
                        ))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.mutedText)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(recents.items.prefix(4)) { item in
                        NavigationLink {
                            recentDestination(item)
                        } label: {
                            recentCard(item)
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
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func recentCard(
        _ item: LibraryRecentRecord
    ) -> some View {
        let tint = recentTint(item.itemType)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(
                    systemName:
                        item.icon ??
                        item.itemType.systemImage
                )
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(
                    tint.opacity(0.10),
                    in: RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                )

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(
                        ATHLTHTheme.mutedText.opacity(0.72)
                    )
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .lineLimit(1)

                Text(
                    item.subtitle ??
                    item.itemType.title
                )
                .font(.caption2)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .lineLimit(1)
            }
        }
        .padding(13)
        .frame(width: 164, height: 116, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.94),
                    tint.opacity(0.03)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.94),
                lineWidth: 0.8
            )
        }
    }

    @ViewBuilder
    private func recentDestination(
        _ item: LibraryRecentRecord
    ) -> some View {
        switch item.itemType {
        case .plan:
            if let entry = planCatalog.entries.first(
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
            } else {
                RunningWorkoutLibraryView(
                    source: .library,
                    onStart: onStartRunning
                )
            }

        case .exercise:
            if let id = UUID(uuidString: item.itemID),
               let entry = exerciseLibrary.search(
                    query: "",
                    bodyPart: "All",
                    equipment: "All"
               ).first(where: { $0.id == id }) {
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

    private func recentTint(
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

    private func librarySection<Content: View>(
        _ title: String, subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.bold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                content()
            }
        }
    }
}

private struct LibraryDestinationTile: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 46, height: 46)
                    .background(
                        LinearGradient(
                            colors: [
                                tint.opacity(0.16),
                                tint.opacity(0.07)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(
                            cornerRadius: 15,
                            style: .continuous
                        )
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: 15,
                            style: .continuous
                        )
                        .stroke(
                            Color.white.opacity(0.82),
                            lineWidth: 0.8
                        )
                    }

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(
                        ATHLTHTheme.mutedText.opacity(0.76)
                    )
                    .frame(width: 30, height: 30)
                    .background(
                        Color.white.opacity(0.66),
                        in: Circle()
                    )
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(ATHLTHTheme.primaryText)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Capsule()
                .fill(tint.opacity(0.26))
                .frame(width: 34, height: 3)
        }
        .padding(16)
        .frame(
            maxWidth: .infinity,
            minHeight: 148,
            alignment: .topLeading
        )
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.96),
                    tint.opacity(0.035)
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
                Color.white.opacity(0.96),
                lineWidth: 1
            )
        }
        .shadow(
            color: ATHLTHTheme.accentDeep.opacity(0.035),
            radius: 14,
            y: 7
        )
        .contentShape(
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
    }
}

private struct LibraryPremiumIntro<Accessory: View>: View {
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
                        .font(.system(size: 10, weight: .bold))
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

private struct LibraryStatPill: View {
    let value: String
    let label: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
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

    var kind: WorkoutKind {
        switch self {
        case .walking:
            return .walking
        case .strength, .fullBodyA, .fullBodyB, .fullBodyC:
            return .strength
        case .mobility:
            return .mobility
        case .recovery:
            return .recovery
        case .custom:
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
        case .strength, .fullBodyA, .fullBodyB, .fullBodyC:
            value = 50
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
        case .fullBodyA, .fullBodyB, .fullBodyC:
            return "Full-body strength. Edit exercises to match your equipment."
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

    var categoryTitle: String {
        category
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

@MainActor
final class TrainingPlanLibraryStore: ObservableObject {
    @Published private(set) var entries: [TrainingPlanCatalogEntry] =
        TrainingPlanCatalogEntry.fallbackCatalog
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

            if !remote.isEmpty {
                entries = remote
                loadedRemote = true
            }
            errorMessage = nil
        } catch {
            // The curated local catalog intentionally remains available
            // offline and before a new backend migration is deployed.
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

struct TrainingPlanLibraryView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var favorites: LibraryFavoritesStore

    @StateObject private var catalog = TrainingPlanLibraryStore()
    @State private var query = ""
    @State private var selectedCategory = "All"
    @State private var favoritesOnly = false

    private var categories: [String] {
        ["All"] +
        Array(Set(catalog.entries.map(\.categoryTitle)))
            .sorted()
    }

    private var filteredEntries: [TrainingPlanCatalogEntry] {
        let cleanQuery = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        return catalog.entries.filter { entry in
            let categoryMatches =
                selectedCategory == "All" ||
                entry.categoryTitle == selectedCategory
            let favoriteMatches =
                !favoritesOnly ||
                favorites.isFavorite(
                    .plan,
                    itemID: entry.id.uuidString
                )
            let searchMatches =
                cleanQuery.isEmpty ||
                entry.title.localizedCaseInsensitiveContains(cleanQuery) ||
                entry.summary.localizedCaseInsensitiveContains(cleanQuery) ||
                entry.goal.localizedCaseInsensitiveContains(cleanQuery) ||
                entry.level.localizedCaseInsensitiveContains(cleanQuery)

            return categoryMatches &&
                favoriteMatches &&
                searchMatches
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                LibraryPremiumIntro(
                    eyebrow: "PLAN LIBRARY",
                    title: "Train with a clear direction",
                    subtitle:
                        "Start from a curated structure, save it to My Plans, then make every week and workout your own.",
                    icon: "sparkles.rectangle.stack.fill",
                    accent: Color.orange
                ) {
                    HStack(spacing: 8) {
                        LibraryStatPill(
                            value: "\(catalog.entries.count)",
                            label: "plans",
                            icon: "square.stack.3d.up.fill",
                            tint: Color.orange
                        )

                        LibraryStatPill(
                            value: "\(favorites.count(for: .plan))",
                            label: "saved",
                            icon: "star.fill",
                            tint: ATHLTHTheme.premiumGold
                        )
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button {
                            favoritesOnly.toggle()
                        } label: {
                            catalogChip(
                                "Favorites",
                                systemImage: "star.fill",
                                selected: favoritesOnly
                            )
                        }
                        .buttonStyle(.plain)

                        ForEach(categories, id: \.self) { category in
                            Button {
                                selectedCategory = category
                            } label: {
                                catalogChip(
                                    category,
                                    systemImage: nil,
                                    selected:
                                        selectedCategory == category
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if filteredEntries.isEmpty {
                    ContentUnavailableView(
                        favoritesOnly
                            ? "No favorite plans yet"
                            : "No plans found",
                        systemImage:
                            favoritesOnly
                                ? "star"
                                : "calendar.badge.exclamationmark",
                        description: Text(
                            favoritesOnly
                                ? "Tap the star on a plan to keep it here."
                                : "Try another search or category."
                        )
                    )
                    .padding(.top, 32)
                } else {
                    ForEach(filteredEntries) { entry in
                        ZStack(alignment: .topTrailing) {
                            NavigationLink {
                                TrainingPlanCatalogDetailView(
                                    entry: entry
                                )
                            } label: {
                                catalogCard(entry)
                            }
                            .buttonStyle(.plain)

                            LibraryFavoriteButton(
                                kind: .plan,
                                itemID: entry.id.uuidString,
                                title: entry.title,
                                subtitle:
                                    "\(entry.durationWeeks) weeks · \(entry.level)",
                                icon: "calendar.badge.clock"
                            )
                            .padding(12)
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
                accent: Color.orange.opacity(0.20)
            )
        )
        .navigationTitle("Plan Library")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $query,
            prompt: "Search plans or goals"
        )
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

    private func catalogChip(
        _ title: String,
        systemImage: String?,
        selected: Bool
    ) -> some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(
            selected
                ? Color.white
                : ATHLTHTheme.primaryText.opacity(0.82)
        )
        .padding(.horizontal, 13)
        .frame(height: 38)
        .background(
            selected
                ? ATHLTHTheme.accentDeep
                : Color.white.opacity(0.86),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(
                    selected
                        ? Color.white.opacity(0.18)
                        : Color.black.opacity(0.035),
                    lineWidth: 0.8
                )
        }
        .shadow(
            color: ATHLTHTheme.accentDeep.opacity(
                selected ? 0.10 : 0.025
            ),
            radius: selected ? 8 : 5,
            y: 3
        )
    }

    private func catalogCard(
        _ entry: TrainingPlanCatalogEntry
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 13) {
                Image(
                    systemName:
                        entry.category == "strength"
                            ? "dumbbell.fill"
                            : entry.category == "hybrid"
                                ? "figure.run.square.stack.fill"
                                : "figure.run"
                )
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(planAccent(entry))
                .frame(width: 50, height: 50)
                .background(
                    planAccent(entry).opacity(0.10),
                    in: RoundedRectangle(
                        cornerRadius: 16,
                        style: .continuous
                    )
                )

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(entry.categoryTitle.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.3)
                            .foregroundStyle(planAccent(entry))

                        Text("CURATED")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(ATHLTHTheme.mutedText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Color.black.opacity(0.035),
                                in: Capsule()
                            )
                    }

                    Text(entry.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        .padding(.trailing, 42)

                    Text(entry.goal)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(
                            ATHLTHTheme.primaryText.opacity(0.70)
                        )
                }

                Spacer(minLength: 0)
            }

            Text(entry.summary)
                .font(.subheadline)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .multilineTextAlignment(.leading)
                .lineSpacing(2)

            HStack(spacing: 7) {
                planMetric(
                    "\(entry.durationWeeks) wk",
                    icon: "calendar"
                )
                planMetric(
                    "\(entry.sessionsPerWeek)/wk",
                    icon: "repeat"
                )
                planMetric(
                    entry.level,
                    icon: "speedometer"
                )

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.caption.bold())
                    .foregroundStyle(planAccent(entry))
                    .frame(width: 30, height: 30)
                    .background(
                        planAccent(entry).opacity(0.08),
                        in: Circle()
                    )
            }
        }
        .padding(17)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.97),
                    planAccent(entry).opacity(0.035)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 25,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 25,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.96),
                lineWidth: 1
            )
        }
        .shadow(
            color: ATHLTHTheme.accentDeep.opacity(0.035),
            radius: 14,
            y: 7
        )
    }

    private func planMetric(
        _ text: String,
        icon: String
    ) -> some View {
        Label(text, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(ATHLTHTheme.mutedText)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                Color.white.opacity(0.62),
                in: Capsule()
            )
    }

    private func planAccent(
        _ entry: TrainingPlanCatalogEntry
    ) -> Color {
        switch entry.category {
        case "strength":
            return Color.indigo
        case "hybrid":
            return ATHLTHTheme.premiumGold
        default:
            return ATHLTHTheme.vitality
        }
    }
}

struct TrainingPlanCatalogDetailView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var favorites: LibraryFavoritesStore
    @EnvironmentObject private var recents: LibraryRecentsStore

    let entry: TrainingPlanCatalogEntry

    @State private var addedToLibrary = false
    @State private var showingPersonalizePlan = false
    @State private var showAllWeeks = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 13) {
                        Image(systemName: detailIcon)
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
                            Text(entry.categoryTitle.uppercased())
                                .font(.system(size: 10, weight: .bold))
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
                .background(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.96),
                            detailAccent.opacity(0.055)
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
                        Color.white.opacity(0.95),
                        lineWidth: 1
                    )
                }

                HStack(spacing: 10) {
                    detailMetric(
                        "\(entry.durationWeeks)",
                        label: "weeks",
                        icon: "calendar"
                    )
                    detailMetric(
                        "\(entry.sessionsPerWeek)",
                        label: "sessions / week",
                        icon: "repeat"
                    )
                    detailMetric(
                        entry.level,
                        label: "level",
                        icon: "speedometer"
                    )
                }

                ATHLTHCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Weekly rhythm")
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

                        Text(
                            "ATHLTH spreads these sessions across the week. Once saved, every day, workout, exercise and target can be changed."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                ATHLTHCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Goal")
                            .font(.headline)
                        Text(entry.goal)
                            .font(.title3.weight(.semibold))
                        Text(
                            "This is a reusable starting structure, not a fixed prescription. Adapt volume and intensity to your current training history."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                planPreview

                Button {
                    showingPersonalizePlan = true
                } label: {
                    HStack {
                        Label(
                            "Make it mine",
                            systemImage: "slider.horizontal.3"
                        )
                        .font(.headline)

                        Spacer()

                        Image(systemName: "arrow.right")
                            .font(.caption.bold())
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 17)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
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
                            cornerRadius: 16,
                            style: .continuous
                        )
                    )
                }
                .buttonStyle(.plain)

                Button {
                    _ = session.saveCatalogPlanTemplate(
                        entry
                    )
                    addedToLibrary = true
                } label: {
                    Label(
                        isAlreadySaved
                            ? "Saved for later"
                            : "Save for later",
                        systemImage:
                            isAlreadySaved
                                ? "checkmark.circle.fill"
                                : "bookmark"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                }
                .buttonStyle(.bordered)
                .tint(ATHLTHTheme.accent)
                .disabled(isAlreadySaved)
            }
            .padding(20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(
            ATHLTHPremiumCanvas(
                accent: ATHLTHTheme.accent.opacity(0.32)
            )
        )
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
            PersonalizeTrainingPlanView(entry: entry)
        }
        .alert(
            "Added to My Plans",
            isPresented: $addedToLibrary
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                ATHLTHLocalization.format(
                            english: "%@ is now saved as a reusable plan. Open My Plans when you are ready to schedule it.",
                            norwegian: "%@ er nå lagret som en gjenbrukbar plan. Åpne Mine planer når du er klar til å planlegge den.",
                            entry.title
                        )
            )
        }
    }

    private var isAlreadySaved: Bool {
        session.planTemplates.contains {
            $0.tags.contains(
                "catalog:\(entry.slug)"
            ) &&
            $0.tags.contains(
                "catalog-version:\(entry.catalogVersion)"
            )
        }
    }

    @ViewBuilder
    private var planPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("FULL PLAN PREVIEW")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.6)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )

                    Text("Week by week")
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
                                ? "Show fewer weeks"
                                : "Show all \(entry.durationWeeks) weeks"
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
        .background(
            Color.white.opacity(0.84),
            in: RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
    }

    private func previewWeekCard(
        _ week: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(ATHLTHLocalization.format(
                                english: "Week %d",
                                norwegian: "Uke %d",
                                week
                            ))
                    .font(.subheadline.weight(.bold))

                Spacer()

                if week.isMultiple(of: 4) &&
                    week < entry.durationWeeks {
                    Text("DELOAD")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Color.orange.opacity(0.09),
                            in: Capsule()
                        )
                } else if entry.durationWeeks >= 12 &&
                            week >= entry.durationWeeks - 1 {
                    Text("TAPER")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(
                            ATHLTHTheme.vitality
                        )
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            ATHLTHTheme.vitality.opacity(0.09),
                            in: Capsule()
                        )
                }
            }

            ForEach(
                Array(
                    entry.sessionBlueprints
                        .prefix(entry.sessionsPerWeek)
                        .enumerated()
                ),
                id: \.offset
            ) { _, blueprint in
                HStack(spacing: 10) {
                    Image(
                        systemName:
                            blueprint.kind.systemImage
                    )
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(detailAccent)
                    .frame(width: 30, height: 30)
                    .background(
                        detailAccent.opacity(0.08),
                        in: RoundedRectangle(
                            cornerRadius: 9
                        )
                    )

                    Text(blueprint.title)
                        .font(.caption.weight(.semibold))

                    Spacer()

                    Text(
                        "\(blueprint.durationMinutes(week: week, totalWeeks: entry.durationWeeks)) min"
                    )
                    .font(.caption2)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }
            }
        }
        .padding(13)
        .background(
            Color.white.opacity(0.70),
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
            .stroke(
                Color.black.opacity(0.035),
                lineWidth: 0.7
            )
        }
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
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.94),
                    detailAccent.opacity(0.025)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(
                Color.black.opacity(0.035),
                lineWidth: 0.7
            )
        }
    }

    private var detailAccent: Color {
        switch entry.category {
        case "strength":
            return Color.indigo
        case "hybrid":
            return ATHLTHTheme.premiumGold
        default:
            return ATHLTHTheme.vitality
        }
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

    @State private var startDate = Date()
    @State private var selectedDays: Set<Int> = []
    @State private var configured = false
    @State private var scheduleError: String?

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

    private var conflictingPlan: TrainingPlan? {
        session.trainingPlanConflict(
            startDate: resolvedStartDate,
            weekCount: entry.durationWeeks
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    LibraryPremiumIntro(
                        eyebrow: "MAKE IT MINE",
                        title: entry.title,
                        subtitle:
                            "Choose when this plan fits your life. ATHLTH keeps the training structure, but places the sessions on the days you prefer.",
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

                    ATHLTHCard {
                        VStack(alignment: .leading, spacing: 13) {
                            Text("START")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(1.6)
                                .foregroundStyle(
                                    ATHLTHTheme.mutedText
                                )

                            DatePicker(
                                "Preferred start",
                                selection: $startDate,
                                in: Calendar.current.startOfDay(
                                    for: Date()
                                )...,
                                displayedComponents: .date
                            )

                            Divider()

                            HStack {
                                Text("Plan begins")
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
                                "Library plans run Monday–Sunday. ATHLTH starts this plan on the first Monday on or after your preferred date."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            Divider()

                            HStack {
                                Text("Estimated finish")
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

                    ATHLTHCard {
                        VStack(alignment: .leading, spacing: 13) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("TRAINING DAYS")
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

                    ATHLTHCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("PLAN FIT")
                                .font(.system(size: 9, weight: .bold))
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

                    if let conflict = conflictingPlan {
                        HStack(alignment: .top, spacing: 11) {
                            Image(
                                systemName:
                                    "calendar.badge.exclamationmark"
                            )
                            .foregroundStyle(Color.orange)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("This overlaps another plan")
                                    .font(.subheadline.weight(.semibold))

                                Text(
                                    "\(conflict.title) already covers part of these dates. Choose another start date."
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
                        createScheduledPlan()
                    } label: {
                        HStack {
                            Label(
                                "Create My Plan",
                                systemImage: "calendar.badge.plus"
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
                            ATHLTHTheme.accentDeep,
                            in: RoundedRectangle(
                                cornerRadius: 16,
                                style: .continuous
                            )
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(
                        !hasValidDays ||
                        conflictingPlan != nil
                    )
                    .opacity(
                        !hasValidDays ||
                        conflictingPlan != nil
                            ? 0.45
                            : 1
                    )

                    Button {
                        _ = session.saveCatalogPlanTemplate(
                            entry,
                            preferredDayIndexes:
                                selectedDays.sorted()
                        )
                        dismiss()
                    } label: {
                        Label(
                            "Save for later",
                            systemImage: "bookmark"
                        )
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                    }
                    .buttonStyle(.bordered)
                    .tint(ATHLTHTheme.accent)
                    .disabled(!hasValidDays)
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
            .navigationTitle("Make it mine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
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
        guard hasValidDays else { return }

        guard session.scheduleCatalogPlan(
            entry,
            startDate: resolvedStartDate,
            preferredDayIndexes:
                selectedDays.sorted()
        ) != nil else {
            scheduleError =
                "The plan could not be scheduled. Check that its dates do not overlap another active or upcoming plan."
            return
        }

        dismiss()
    }
}

struct MyTrainingPlansLibraryView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strengthWorkout: StrengthWorkoutStore

    @State private var showingCreatePlan = false
    @State private var scheduleError: String?
    @State private var reviewingPlan: TrainingPlan?

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
        .navigationTitle("My Plans")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCreatePlan = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create training plan")
            }
        }
        .sheet(isPresented: $showingCreatePlan) {
            TrainingPlanCreationView()
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
                    Text("SAVED PLAN")
                        .font(.system(size: 9, weight: .bold))
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
                if session.usePlanTemplate(
                    template.id,
                    startDate:
                        session.suggestedTrainingPlanStartDate
                ) == nil {
                    scheduleError =
                        "Another plan overlaps the suggested start date. Choose a different date when creating or scheduling the plan."
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
                .font(.system(size: 10, weight: .bold))
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

                                Text("Nothing needs your attention")
                                    .font(.headline)

                                Text(
                                    "Your plan can continue exactly as scheduled."
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
                    moveToTomorrow(occurrence)
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
                            Text("Nothing saved here yet")
                                .font(.title3.weight(.semibold))

                            Text(
                                "Tap the star on a plan, workout, exercise or route and it will appear here."
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
            async let exercises: Void = exerciseLibrary.refresh()
            _ = await (saved, plans, exercises)
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
            } else {
                RunningWorkoutLibraryView(
                    source: .library,
                    onStart: onStartRunning
                )
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
                    .font(.system(size: 10, weight: .bold))

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

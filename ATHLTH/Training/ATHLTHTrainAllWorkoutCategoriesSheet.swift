import SwiftUI

/// Shared on-device account-scoped usage, using the existing Train tap
/// history so Home inherits preferences instead of starting a second ranking.
enum ATHLTHQuickActivityUsage {
    typealias Category = ATHLTHTrainAllWorkoutCategoriesSheet.Category

    static func storageKey(for owner: UUID) -> String {
        "athlth.train.today.quickTaps." + owner.uuidString
    }

    static func counts(for owner: UUID, defaults: UserDefaults = .standard) -> [String: Int] {
        defaults.dictionary(forKey: storageKey(for: owner)) as? [String: Int] ?? [:]
    }

    @discardableResult
    static func record(_ category: Category, for owner: UUID, defaults: UserDefaults = .standard) -> [String: Int] {
        var values = counts(for: owner, defaults: defaults)
        guard category.isAvailable else { return values }
        values[category.rawValue] = min(max(values[category.rawValue, default: 0], 0), 99_999) + 1
        defaults.set(values, forKey: storageKey(for: owner))
        return values
    }

    static func favorites(counts: [String: Int]) -> [Category] {
        let defaults: [Category] = [.running, .strength, .walking, .freeTraining, .sports, .custom]
        return Array(defaults.enumerated()
            .filter { $0.element.isAvailable }
            .sorted { lhs, rhs in
                let left = max(0, counts[lhs.element.rawValue, default: 0])
                let right = max(0, counts[rhs.element.rawValue, default: 0])
                return left == right ? lhs.offset < rhs.offset : left > right
            }
            .prefix(2)
            .map(\.element))
    }
}

/// Presents the primary training activities in a responsive three-column grid.
/// Supported activities reuse the existing Train start flow and recorder;
/// unavailable activities remain visible but cannot be started.
struct ATHLTHTrainAllWorkoutCategoriesSheet: View {
    enum Action {
        case freeRun
        case runIntervals
        case freeWalk
        case freeStrength
        case strengthLibrary
        case runningWorkouts
        case strengthExercises
        case competition(ATHLTHQuickStartActivity)
        case cycling
        case freeTraining
        case custom(CustomQuickWorkoutActivity)
    }

    /// The order here is the visual order in the activity grid.
    enum Category: String, CaseIterable, Identifiable {
        case freeTraining, walking, running
        case strength, cycling, swimming
        case yoga, meditation, sports, custom

        var id: String { rawValue }

        var isAvailable: Bool {
            switch self {
            case .freeTraining, .walking, .running, .strength, .sports, .custom:
                return true
            case .cycling, .swimming, .yoga, .meditation:
                return false
            }
        }

        var title: String {
            switch self {
            case .freeTraining: return tr("Free training", "Fri trening")
            case .walking: return tr("Walking", "Gå")
            case .running: return tr("Running", "Løping")
            case .strength: return tr("Strength", "Styrke")
            case .cycling: return tr("Cycling", "Sykling")
            case .swimming: return tr("Swimming", "Svømming")
            case .yoga: return "Yoga"
            case .meditation: return tr("Meditation", "Meditasjon")
            case .sports: return tr("Sports", "Idrett")
            case .custom: return tr("Custom", "Egendefinert")
            }
        }

        var subtitle: String {
            switch self {
            case .freeTraining:
                return tr("Start an open workout directly", "Start en åpen økt direkte")
            case .walking:
                return tr("Free walk or route", "Fri gåtur eller rute")
            case .running:
                return tr("Route, free run or intervals", "Rute, fri løping eller intervall")
            case .strength:
                return tr("Free strength or saved sessions", "Fri styrke eller lagrede økter")
            case .sports:
                return tr("Open timed sport", "Fri idrett med tidtaking")
            case .custom:
                return tr("Configure your own activity", "Tilpass en egen aktivitet")
            case .cycling, .swimming, .yoga, .meditation:
                return tr("Coming soon", "Kommer snart")
            }
        }

        var icon: String {
            switch self {
            case .freeTraining: return "figure.cross.training"
            case .walking: return "figure.walk"
            case .running: return "figure.run"
            case .strength: return "dumbbell.fill"
            case .cycling: return "bicycle"
            case .swimming: return "figure.pool.swim"
            case .yoga: return "figure.yoga"
            case .meditation: return "figure.mind.and.body"
            case .sports: return "sportscourt.fill"
            case .custom: return "figure.mixed.cardio"
            }
        }

        private func tr(_ english: String, _ norwegian: String) -> String {
            ATHLTHLocalization.choose(english: english, norwegian: norwegian)
        }
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedCategory: Category?

    let onSelect: (Action) -> Void

    // Three columns for standard text sizes, with two larger touch targets
    // when the user enables accessibility-sized type.
    private var activityColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 0), spacing: 11),
            count: dynamicTypeSize.isAccessibilitySize ? 2 : 3
        )
    }

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let selectedCategory {
                        subcategories(for: selectedCategory)
                    } else {
                        header(
                            tr("Choose an activity", "Velg aktivitet"),
                            subtitle: tr(
                                "Choose how you want to train",
                                "Velg hvordan du vil trene"
                            )
                        )
                        activityGrid
                    }
                }
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.top, 20)
                .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(tr("All workouts", "Alle økter"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if selectedCategory != nil {
                        Button {
                            selectedCategory = nil
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .accessibilityLabel(
                            tr("Back to activities", "Tilbake til aktiviteter")
                        )
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(tr("Close", "Lukk")) { dismiss() }
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                }
            }
        }
        .accessibilityIdentifier("athlth-train-all-workout-categories")
    }

    private var activityGrid: some View {
        LazyVGrid(columns: activityColumns, spacing: 11) {
            ForEach(Category.allCases) { category in
                Button {
                    select(category)
                } label: {
                    activityTile(for: category)
                }
                .buttonStyle(.plain)
                .disabled(!category.isAvailable)
                .accessibilityIdentifier(
                    "athlth-all-workouts-\(category.rawValue)"
                )
                .accessibilityLabel(category.title)
                .accessibilityValue(
                    category.isAvailable
                        ? tr("Available", "Tilgjengelig")
                        : tr("Coming soon", "Kommer snart")
                )
            }
        }
        .accessibilityIdentifier("athlth-all-workouts-activity-grid")
    }

    private func activityTile(for category: Category) -> some View {
        let enabled = category.isAvailable
        return VStack(spacing: 10) {
            Image(systemName: category.icon)
                .font(.system(size: 27, weight: .regular))
                .foregroundStyle(
                    enabled
                        ? ATHLTHTrainDesign.bronze
                        : ATHLTHTrainDesign.secondary.opacity(0.55)
                )
                .frame(width: 58, height: 58)
                .background(
                    enabled
                        ? ATHLTHTrainDesign.paleGold.opacity(0.56)
                        : ATHLTHPlanDesign.warmSurface.opacity(0.55),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .accessibilityHidden(true)

            Text(category.title)
                .font(.system(
                    size: dynamicTypeSize.isAccessibilitySize ? 16 : 15,
                    weight: .semibold
                ))
                .foregroundStyle(
                    enabled
                        ? ATHLTHTrainDesign.ink
                        : ATHLTHTrainDesign.secondary.opacity(0.70)
                )
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            if !enabled {
                Text(tr("Coming soon", "Kommer snart"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ATHLTHTrainDesign.secondary.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(
                        ATHLTHPlanDesign.warmSurface.opacity(0.50),
                        in: Capsule()
                    )
            } else {
                // Equal tile heights, without filler captions on active activities.
                Color.clear
                    .frame(height: 21)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 168 : 158)
        .padding(.horizontal, 5)
        .background(
            enabled ? Color.white.opacity(0.96) : Color.white.opacity(0.52),
            in: RoundedRectangle(cornerRadius: 23, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .strokeBorder(
                    ATHLTHTrainDesign.rule.opacity(enabled ? 0.60 : 0.27),
                    lineWidth: 0.9
                )
        }
        .shadow(
            color: ATHLTHTrainDesign.ink.opacity(enabled ? 0.055 : 0),
            radius: 13,
            x: 0,
            y: 5
        )
        .contentShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
    }

    private func select(_ category: Category) {
        // Keep the activity unavailable at the routing level as well,
        // not just visually disabled, so it cannot start via this sheet.
        guard category.isAvailable else { return }
        ATHLTHQuickActivityUsage.record(category, for: session.profile.userID)

        switch category {
        case .running, .walking, .strength:
            selectedCategory = category
        case .freeTraining:
            choose(.freeTraining)
        case .sports:
            choose(.custom(.sports))
        case .custom:
            choose(.custom(.other))
        case .cycling, .swimming, .yoga, .meditation:
            break
        }
    }

    private func header(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 29, weight: .regular, design: .serif))
                .foregroundStyle(ATHLTHTrainDesign.ink)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(ATHLTHTrainDesign.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func subcategories(for category: Category) -> some View {
        header(category.title, subtitle: category.subtitle)
        switch category {
        case .running:
            NavigationLink {
                routePicker(for: category)
            } label: {
                optionRow(icon: "map", title: tr("Route", "Rute"),
                          detail: tr("Choose a route before running", "Velg rute før løping"))
            }
            .buttonStyle(.plain)
            actionRow(icon: "figure.run", title: tr("Free run", "Fri løping"),
                      detail: tr("Run without a planned route", "Løp uten planlagt rute"),
                      action: .freeRun)
            actionRow(icon: "timer", title: tr("Intervals", "Intervall"),
                      detail: tr("Build intervals and recovery", "Lag drag og pauser"),
                      action: .runIntervals)
            actionRow(icon: "list.bullet.clipboard",
                      title: tr("Training workout", "Treningsøkt"),
                      detail: tr("Choose a saved running workout", "Velg en lagret løpeøkt"),
                      action: .runningWorkouts)
            actionRow(icon: "trophy", title: tr("Competition", "Konkurranse"),
                      detail: tr("Duel, league or cup", "Duell, liga eller cup"),
                      action: .competition(.running))
        case .walking:
            actionRow(icon: "figure.walk", title: tr("Free walk", "Fri gåtur"),
                      detail: tr("Walk without a route", "Gå uten valgt rute"),
                      action: .freeWalk)
            NavigationLink {
                routePicker(for: category)
            } label: {
                optionRow(icon: "map", title: tr("Route", "Rute"),
                          detail: tr("Browse walking routes", "Velg en turrute"))
            }
            .buttonStyle(.plain)
            actionRow(icon: "trophy", title: tr("Competition", "Konkurranse"),
                      detail: tr("Duel, league or cup", "Duell, liga eller cup"),
                      action: .competition(.walking))
        case .strength:
            actionRow(icon: "dumbbell.fill",
                      title: tr("Free strength", "Fri styrketrening"),
                      detail: tr("Set up an open strength workout",
                                 "Start med frie styrkeøvelser"),
                      action: .freeStrength)
            actionRow(icon: "square.grid.2x2", title: tr("Saved workouts", "Lagrede økter"),
                      detail: tr("Browse your workout library", "Se treningsbiblioteket"),
                      action: .strengthLibrary)
            actionRow(icon: "plus.circle", title: tr("Add exercises", "Legg til øvelser"),
                      detail: tr("Build an exercise workout", "Bygg en økt med øvelser"),
                      action: .strengthExercises)
            actionRow(icon: "trophy", title: tr("Competition", "Konkurranse"),
                      detail: tr("Duel, league or cup", "Duell, liga eller cup"),
                      action: .competition(.strength))
        case .freeTraining, .sports, .custom, .cycling, .swimming, .yoga, .meditation:
            EmptyView()
        }
    }

    private func routePicker(for category: Category) -> some View {
        RouteLibraryListView(
            source: .database,
            quickStartActivity: category == .walking ? .walking : .running
        )
            .navigationTitle(tr("Routes", "Ruter"))
            .navigationBarTitleDisplayMode(.inline)
    }

    private func actionRow(icon: String, title: String,
                           detail: String, action: Action) -> some View {
        Button { choose(action) } label: {
            optionRow(icon: icon, title: title, detail: detail)
        }
        .buttonStyle(.plain)
    }

    private func optionRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(ATHLTHTrainDesign.bronze)
                .frame(width: 44, height: 44)
                .background(ATHLTHTrainDesign.paleGold.opacity(0.48),
                            in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ATHLTHTrainDesign.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHTrainDesign.bronze)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.96),
                    in: RoundedRectangle(cornerRadius: 19))
        .overlay {
            RoundedRectangle(cornerRadius: 19)
                .strokeBorder(ATHLTHTrainDesign.rule.opacity(0.5), lineWidth: 0.8)
        }
        .contentShape(RoundedRectangle(cornerRadius: 19))
    }

    private func choose(_ action: Action) {
        dismiss()
        onSelect(action)
    }
}

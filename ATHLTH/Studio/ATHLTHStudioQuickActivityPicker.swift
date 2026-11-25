import SwiftUI

/// Reuses every Quick Start supported by the iPhone training engine.
/// Studio never creates a separate exercise or workout implementation.
enum ATHLTHStudioQuickActivityCatalog {
    struct Entry: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let symbol: String
        let request: ATHLTHTrainNavigationRequest
    }

    static var entries: [Entry] {
        [
            Entry(
                id: "running",
                title: ATHLTHLocalization.choose(english: "Run", norwegian: "Løping"),
                subtitle: ATHLTHLocalization.choose(
                    english: "Free, route or structured run",
                    norwegian: "Fri løping, rute eller treningsøkt"
                ),
                symbol: "figure.run",
                request: .quick(.running)
            ),
            Entry(
                id: "walking",
                title: ATHLTHLocalization.choose(english: "Walk", norwegian: "Gåtur"),
                subtitle: ATHLTHLocalization.choose(
                    english: "Indoor or outdoor walk",
                    norwegian: "Gåtur inne eller ute"
                ),
                symbol: "figure.walk",
                request: .quick(.walking)
            ),
            Entry(
                id: "strength",
                title: ATHLTHLocalization.choose(english: "Strength", norwegian: "Styrke"),
                subtitle: ATHLTHLocalization.choose(
                    english: "Gym or at home",
                    norwegian: "På treningssenter eller hjemme"
                ),
                symbol: "dumbbell.fill",
                request: .quick(.strength)
            )
        ] + CustomQuickWorkoutActivity.allCases.map { activity in
            Entry(
                id: activity.rawValue,
                title: activity.localizedTitle,
                subtitle: activity.localizedSubtitle,
                symbol: activity.systemImage,
                request: .customQuickActivity(activity)
            )
        }
    }
}

/// iPad-only activity selector, presented before the existing Quick Start.
/// Choosing an activity dismisses this sheet; the parent opens the training
/// workspace after dismissal so two modal presentations never overlap.
struct ATHLTHStudioQuickActivityPicker: View {
    @Environment(\.dismiss) private var dismiss

    let onSelect: (ATHLTHTrainNavigationRequest) -> Void

    private let ink = Color(red: 0.19, green: 0.18, blue: 0.16)
    private let gold = Color(red: 0.68, green: 0.53, blue: 0.32)
    private let outline = Color(red: 0.88, green: 0.85, blue: 0.80)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(ATHLTHLocalization.choose(
                            english: "What would you like to train?",
                            norwegian: "Hva vil du trene?"
                        ))
                        .font(.system(size: 30, weight: .regular, design: .serif))
                        .foregroundStyle(ink)

                        Text(ATHLTHLocalization.choose(
                            english: "Choose an activity to open its Quick Start. No workout is added to your calendar.",
                            norwegian: "Velg aktivitet for å åpne hurtigstart. Økten legges ikke til i kalenderen."
                        ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 174), spacing: 11)],
                        spacing: 11
                    ) {
                        ForEach(ATHLTHStudioQuickActivityCatalog.entries) { choice in
                            Button {
                                onSelect(choice.request)
                            } label: {
                                HStack(alignment: .top, spacing: 11) {
                                    Image(systemName: choice.symbol)
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundStyle(gold)
                                        .frame(width: 35, height: 35)
                                        .background(gold.opacity(0.11),
                                                    in: RoundedRectangle(cornerRadius: 12))

                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(choice.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(ink)
                                        Text(choice.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity, minHeight: 79,
                                       alignment: .topLeading)
                                .padding(12)
                                .background(.white,
                                            in: RoundedRectangle(cornerRadius: 17))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 17)
                                        .strokeBorder(outline.opacity(0.75), lineWidth: 0.8)
                                }
                                .contentShape(RoundedRectangle(cornerRadius: 17))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(choice.title)
                            .accessibilityHint(ATHLTHLocalization.choose(
                                english: "Open Quick Start setup",
                                norwegian: "Åpne oppsett for hurtigstart"
                            ))
                            .accessibilityIdentifier(
                                "athlth-ipad-quick-activity-" + choice.id
                            )
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Color(red: 0.986, green: 0.980, blue: 0.970))
            .navigationTitle(ATHLTHLocalization.choose(
                english: "Train now", norwegian: "Tren nå"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(ATHLTHLocalization.choose(
                        english: "Cancel", norwegian: "Avbryt"
                    )) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("athlth-ipad-quick-activity-picker")
    }
}


/// The iPad start surface is presentation only. All recorder ownership,
/// admission checks and workout setup remain in ATHLTHTrainView.
struct ATHLTHStudioTrainLandingView: View {
    @EnvironmentObject private var goalStore: GoalStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var availableWidth: CGFloat = 850

    let activeWorkout: AnyView?
    let occupied: Bool
    let onActivity: (ATHLTHTrainAllWorkoutCategoriesSheet.Category) -> Void
    let onAll: () -> Void
    let onFree: () -> Void
    let onRoute: () -> Void
    let onWorkout: () -> Void
    let onGhost: () -> Void
    let onCompetition: () -> Void
    let onLibrary: () -> Void
    let onPlan: () -> Void
    let onCustom: () -> Void
    let onTogether: () -> Void

    private let ink = ATHLTHTrainDesign.ink
    private let gold = ATHLTHTrainDesign.bronze

    static let featuredActivities: [ATHLTHTrainAllWorkoutCategoriesSheet.Category] = [
        .walking, .running, .strength
    ]

    private var activeGoal: ATHLTHGoal? {
        if let goal = goalStore.primaryGoal, goal.status == .active { return goal }
        return goalStore.activeGoals.first { $0.status == .active }
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                header
                if let activeWorkout {
                    activeWorkout
                } else if occupied {
                    Label(tr("A workout is in progress", "En økt pågår"), systemImage: "clock")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(gold)
                }
                topActions
                activitySection
                quickSection
                Divider().overlay(ATHLTHTrainDesign.rule.opacity(0.4))
                toolsSection
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 26)
            .frame(maxWidth: 1240)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.hidden)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            availableWidth = width
        }
        .background(ATHLTHStudioStyle.canvas.ignoresSafeArea())
        .accessibilityIdentifier("athlth-ipad-train-landing")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("ATHLTH")
                .font(.caption.weight(.semibold))
                .tracking(4)
                .foregroundStyle(gold)
            Text(tr("Train now", "Tren nå"))
                .font(.system(.largeTitle, design: .serif).weight(.semibold))
                .foregroundStyle(ink)
                .accessibilityAddTraits(.isHeader)
            Capsule().fill(gold).frame(width: 43, height: 3)
            Text(tr("Start a workout, choose an activity or find a session that suits you.",
                    "Start en økt, velg en treningsform eller finn en økt som passer deg."))
                .font(.subheadline)
                .foregroundStyle(ATHLTHTrainDesign.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func columns(maximum: Int, minimum: CGFloat, spacing: CGFloat = 12) -> [GridItem] {
        let width = max(0, min(availableWidth, 1240) - 48)
        let count = max(1, min(maximum, Int((width + spacing) / (minimum + spacing))))
        return Array(repeating: GridItem(.flexible(minimum: 0), spacing: spacing), count: count)
    }

    private var topActions: some View {
        LazyVGrid(columns: columns(maximum: 3, minimum: dynamicTypeSize.isAccessibilitySize ? 260 : 195), spacing: 12) {
            NavigationLink {
                if let activeGoal { GoalDetailView(goalID: activeGoal.id) }
                else { GoalsHubView() }
            } label: {
                actionLabel(tr("ACTIVE GOAL", "AKTIVT MÅL"),
                            activeGoal?.title ?? tr("Choose a goal", "Velg et mål"), "target")
            }
            .buttonStyle(.plain)
            NavigationLink {
                RecoveryCoachInboxDestinationView(
                    initialQuestion: tr("Help me create a workout that suits me.", "Hjelp meg å lage en treningsøkt som passer meg."),
                    submitInitialQuestion: false
                )
            } label: {
                actionLabel("COACH", tr("Find a workout with Coach", "La coach finne en økt"), "sparkles")
            }
            .buttonStyle(.plain)
            Button(action: onTogether) {
                actionLabel(tr("TRAIN TOGETHER", "TREN SAMMEN"),
                            tr("Start a shared workout", "Start en fellesøkt"), "person.2")
            }
            .buttonStyle(.plain)
            .disabled(occupied)
        }
    }

    private func actionLabel(_ eyebrow: String, _ title: String, _ symbol: String) -> some View {
        HStack(spacing: 11) {
            icon(symbol)
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow).font(.caption2.weight(.semibold)).tracking(1.2)
                    .foregroundStyle(gold)
                Text(title).font(.system(.subheadline, design: .serif).weight(.semibold))
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 2)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(gold)
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .athlthTrainEditorialCard()
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle(tr("Choose activity", "Velg treningsform"))
                Spacer(minLength: 5)
                Button(action: onAll) {
                    Label(tr("See all workouts", "Se alle økter"), systemImage: "arrow.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(gold)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .disabled(occupied)
            }
            LazyVGrid(columns: columns(maximum: 3, minimum: dynamicTypeSize.isAccessibilitySize ? 260 : 180, spacing: 13), spacing: 13) {
                ForEach(Self.featuredActivities) { category in
                    Button { onActivity(category) } label: {
                        activityCard(category)
                    }
                    .buttonStyle(.plain)
                    .disabled(occupied)
                    .opacity(occupied ? 0.55 : 1)
                    .accessibilityIdentifier("athlth-ipad-train-activity-" + category.rawValue)
                }
            }
        }
    }

    private func activityCard(_ category: ATHLTHTrainAllWorkoutCategoriesSheet.Category) -> some View {
        let artwork = category == .walking ? "GoalWalking" :
            category == .running ? "GoalRunning" : "StrengthQuickHero"
        return ZStack(alignment: .bottomLeading) {
            GeometryReader { proxy in
                Image(artwork)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .accessibilityHidden(true)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.10), .black.opacity(0.78)],
                           startPoint: .top, endPoint: .bottom)
            HStack(spacing: 12) {
                Image(systemName: category.icon).font(.system(size: 26, weight: .medium))
                Rectangle().fill(.white.opacity(0.6)).frame(width: 1, height: 30)
                Text(category.title).font(.system(.title2, design: .serif).weight(.semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(17)
        }
        .frame(height: 195)
        .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 21))
    }

    private var quickSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(tr("Quick start", "Hurtigstart"))
            LazyVGrid(columns: columns(maximum: 3, minimum: dynamicTypeSize.isAccessibilitySize ? 260 : 195), spacing: 12) {
                quickButton(tr("Free training", "Fri trening"), tr("Start an open workout.", "Start en økt med egne valg."), "bolt.fill", action: onFree)
                    .disabled(occupied)
                quickButton(tr("Route", "Rute"), tr("Choose a saved route.", "Tren en lagret rute."), "map", action: onRoute)
                quickButton(tr("Workout", "Treningsøkt"), tr("Choose a structured workout.", "Intervall, øvelser eller ferdig økt."), "dumbbell", action: onWorkout)
            }
        }
    }

    private func quickButton(_ title: String, _ detail: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon(symbol)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(.headline, design: .serif)).foregroundStyle(ink)
                    Text(detail).font(.caption).foregroundStyle(ATHLTHTrainDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 2)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(gold)
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .athlthTrainEditorialCard()
        }
        .buttonStyle(.plain)
    }

    private var toolsSection: some View {
        LazyVGrid(columns: columns(maximum: 5, minimum: dynamicTypeSize.isAccessibilitySize ? 200 : 125), spacing: 12) {
            tool("Ghost Race", "flag.checkered", action: onGhost)
            tool(tr("Competition", "Konkurranse"), "trophy", action: onCompetition)
            tool(tr("From library", "Fra bibliotek"), "book", action: onLibrary)
            tool(tr("Plan workout", "Planlegg økt"), "calendar.badge.plus", action: onPlan)
            tool(tr("Custom", "Egendefinert"), "figure.mixed.cardio", action: onCustom)
                .disabled(occupied)
        }
    }

    private func tool(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 11) {
                Image(systemName: symbol).font(.system(size: 24, weight: .medium)).foregroundStyle(gold)
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(ink)
                    .multilineTextAlignment(.center)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 98)
            .athlthTrainEditorialCard()
        }
        .buttonStyle(.plain)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(ATHLTHTrainDesign.sectionHeading).foregroundStyle(ink)
            .accessibilityAddTraits(.isHeader)
    }

    private func icon(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 21, weight: .medium))
            .foregroundStyle(gold)
            .frame(width: 44, height: 44)
            .background(ATHLTHTrainDesign.paleGold.opacity(0.45), in: RoundedRectangle(cornerRadius: 13))
            .accessibilityHidden(true)
    }
}

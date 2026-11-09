import SwiftUI

/// Library navigation is part of the iPad detail column, never presented
/// through Train's full-screen/modal shell. All category views below are the
/// existing shared views, so saved content, favorites and offline data remain
/// on their original stores.
enum ATHLTHStudioLibraryPage: String, CaseIterable, Identifiable, Hashable {
    case overview
    case exercises
    case workouts
    case trainingPlans
    case routes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            return ATHLTHLocalization.choose(
                english: "Training library", norwegian: "Treningsbibliotek"
            )
        case .exercises:
            return ATHLTHLocalization.choose(
                english: "Exercises", norwegian: "Øvelser"
            )
        case .workouts:
            return ATHLTHLocalization.choose(
                english: "Workouts", norwegian: "Treningsøkter"
            )
        case .trainingPlans:
            return ATHLTHLocalization.choose(
                english: "Training plans", norwegian: "Treningsplaner"
            )
        case .routes:
            return ATHLTHLocalization.choose(
                english: "Routes", norwegian: "Ruter"
            )
        }
    }

    var symbol: String {
        switch self {
        case .overview: "books.vertical"
        case .exercises: "dumbbell"
        case .workouts: "figure.run"
        case .trainingPlans: "calendar"
        case .routes: "map"
        }
    }

    var detail: String {
        switch self {
        case .overview:
            return ATHLTHLocalization.choose(
                english: "Everything for training, in one place.",
                norwegian: "Alt du trenger til treningen, samlet."
            )
        case .exercises:
            return ATHLTHLocalization.choose(
                english: "ATHLTH and your own exercises, with shared filters.",
                norwegian: "ATHLTH-øvelser og egne øvelser med felles filtre."
            )
        case .workouts:
            return ATHLTHLocalization.choose(
                english: "Discover workouts or open your saved sessions.",
                norwegian: "Finn nye økter eller åpne dine lagrede økter."
            )
        case .trainingPlans:
            return ATHLTHLocalization.choose(
                english: "Explore complete plans and manage your own.",
                norwegian: "Utforsk treningsplaner og administrer dine egne."
            )
        case .routes:
            return ATHLTHLocalization.choose(
                english: "Explore routes and find those you have saved.",
                norwegian: "Utforsk ruter og finn dem du har lagret."
            )
        }
    }
}

extension ATHLTHPersonalLibrarySection {
    /// Keep old deep-link identifiers intact while routing iPad taps to the
    /// canonical combined categories in Studio's detail area.
    var studioLibraryPage: ATHLTHStudioLibraryPage {
        switch self {
        case .exercises: .exercises
        case .routes: .routes
        case .trainingPlans: .trainingPlans
        case .workouts: .workouts
        }
    }
}

/// A responsive iPad library workspace in the main NavigationSplitView
/// detail column. The hub uses wide cards; individual categories use the
/// existing list/grid navigation and adapt to the actual detail-column width.
struct ATHLTHiPadLibraryWorkspaceView: View {
    let page: ATHLTHStudioLibraryPage
    let onSelect: (ATHLTHStudioLibraryPage) -> Void
    let onBack: () -> Void

    private let ink = ATHLTHStudioStyle.ink
    private let gold = ATHLTHStudioStyle.gold
    private let canvas = ATHLTHStudioStyle.canvas

    var body: some View {
        VStack(spacing: 0) {
            heading
            categoryNavigation
            Rectangle()
                .fill(ATHLTHStudioStyle.outline.opacity(0.55))
                .frame(height: 1)

            Group {
                if page == .overview {
                    categoryCards
                } else {
                    categoryContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(page)
        }
        .background(canvas.ignoresSafeArea())
        .accessibilityIdentifier("athlth-ipad-library-workspace")
    }

    private var heading: some View {
        HStack(alignment: .center, spacing: 14) {
            Button(action: onBack) {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Back to Studio", norwegian: "Tilbake til Studio"
                    ),
                    systemImage: "chevron.left"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ink)
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("athlth-ipad-library-back")

            Spacer(minLength: 8)

            Text("ATHLTH LIBRARY")
                .font(.caption2.weight(.semibold))
                .tracking(2.1)
                .foregroundStyle(gold)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 9)
    }

    private var categoryNavigation: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(ATHLTHStudioLibraryPage.allCases) { destination in
                    Button {
                        guard destination != page else { return }
                        onSelect(destination)
                    } label: {
                        Label(destination.title, systemImage: destination.symbol)
                            .font(.subheadline.weight(
                                destination == page ? .semibold : .medium
                            ))
                            .lineLimit(1)
                            .foregroundStyle(destination == page ? .white : ink)
                            .padding(.horizontal, 15)
                            .frame(minHeight: 43)
                            .background(
                                destination == page ? ink : Color.white.opacity(0.88),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(
                        destination == page ? .isSelected : []
                    )
                    .accessibilityIdentifier(
                        "athlth-ipad-library-nav-\(destination.rawValue)"
                    )
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
        }
    }

    private var categoryCards: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(ATHLTHLocalization.choose(
                            english: "YOUR TRAINING SPACE",
                            norwegian: "DITT TRENINGSBIBLIOTEK"
                        ))
                        .font(.caption2.weight(.semibold))
                        .tracking(2)
                        .foregroundStyle(gold)

                        Text(page.title)
                            .font(.system(size: 35, weight: .semibold, design: .serif))
                            .foregroundStyle(ink)

                        Text(page.detail)
                            .font(.subheadline)
                            .foregroundStyle(ink.opacity(0.65))
                    }

                    LazyVGrid(
                        columns: [
                            GridItem(
                                .adaptive(
                                    minimum: geometry.size.width >= 680 ? 270 : 235,
                                    maximum: 440
                                ),
                                spacing: 16
                            )
                        ],
                        spacing: 16
                    ) {
                        ForEach(ATHLTHStudioLibraryPage.allCases.filter {
                            $0 != .overview
                        }) { destination in
                            libraryCard(destination)
                        }
                    }
                }
                .frame(maxWidth: 1100, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 48)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func libraryCard(
        _ destination: ATHLTHStudioLibraryPage
    ) -> some View {
        Button {
            onSelect(destination)
        } label: {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: destination.symbol)
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(gold)
                        .frame(width: 56, height: 56)
                        .background(gold.opacity(0.10), in:
                            RoundedRectangle(cornerRadius: 17)
                        )
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(gold)
                        .frame(width: 35, height: 35)
                        .background(Color.white.opacity(0.9), in: Circle())
                }
                Spacer(minLength: 0)
                Text(destination.title)
                    .font(.system(size: 24, weight: .semibold, design: .serif))
                    .foregroundStyle(ink)
                Text(destination.detail)
                    .font(.subheadline)
                    .foregroundStyle(ink.opacity(0.63))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(21)
            .frame(maxWidth: .infinity, minHeight: 205, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [
                        .white,
                        Color(red: 0.973, green: 0.958, blue: 0.933)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 23, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 23, style: .continuous)
                    .strokeBorder(gold.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: ink.opacity(0.035), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(
            "athlth-ipad-library-card-\(destination.rawValue)"
        )
    }

    @ViewBuilder
    private var categoryContent: some View {
        switch page {
        case .overview:
            EmptyView()
        case .exercises:
            ExerciseLibraryView(source: .library)
        case .workouts:
            ATHLTHUnifiedWorkoutsLibraryView()
        case .trainingPlans:
            ATHLTHUnifiedPlansLibraryView()
        case .routes:
            RouteLibraryListView(source: .database)
        }
    }
}

import SwiftUI

/// Half-screen iPhone drawer. Keep the other half visible for outside-tap dismissal.
enum ATHLTHSideMenuLayoutPolicy {
    static func width(for viewportWidth: CGFloat) -> CGFloat {
        return max(0, viewportWidth * 0.5)
    }

    static func shouldDismiss(translation: CGSize) -> Bool {
        translation.width <= -60 &&
            abs(translation.height) <= abs(translation.width) * 0.65
    }
}

/// A light, premium slide-out menu that lives above the existing root tabs.
/// It does not create parallel copies of ATHLTH's workout or social screens.
struct ATHLTHSideMenuView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var messaging: MessagingStore
    @EnvironmentObject private var notificationStore: ATHLTHNotificationStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var health: HealthKitManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @SceneStorage("athlth.sideMenu.trainingLibraryExpanded")
    private var isTrainingLibraryExpanded = false

    let selectedTab: Int
    let onSelect: (ATHLTHSideMenuDestination) -> Void
    let onDismiss: () -> Void

    // A restrained porcelain-and-bronze palette, consistent with ATHLTH Home.
    private let menuSurface = ATHLTHTheme.canvasTop
    private let menuCard = Color(red: 0.997, green: 0.995, blue: 0.991)
    private let menuInk = Color(red: 0.19, green: 0.18, blue: 0.17)
    private let menuMuted = Color(red: 0.47, green: 0.45, blue: 0.42)
    private let menuBronze = Color(red: 0.60, green: 0.45, blue: 0.29)
    private let warmDivider = Color(red: 0.77, green: 0.72, blue: 0.65).opacity(0.30)

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Button(action: onDismiss) {
                    Color.black.opacity(0.40)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Close navigation menu",
                    norwegian: "Lukk sidemenyen"
                ))

                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.horizontal, 10)
                        .padding(.top, max(geometry.safeAreaInsets.top, 48) + 8)
                        .padding(.bottom, 15)

                    Rectangle()
                        .fill(warmDivider)
                        .frame(height: 1)
                        .padding(.horizontal, 10)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 17) {
                            menuSection(
                                english: "HOME",
                                norwegian: "HJEM"
                            ) {
                                menuRow(
                                    .home,
                                    english: "Home",
                                    norwegian: "Hjem",
                                    icon: "house",
                                    selected: selectedTab == 0
                                )
                                homeUtilityActions
                                    .padding(.top, 9)
                            }

                            menuSection(
                                english: "TRAINING TOOLS",
                                norwegian: "TRENING OG VERKTØY"
                            ) {
                                trainingLibraryMenu
                                menuRow(
                                    .trainTogether,
                                    english: "Train Together",
                                    norwegian: "Tren sammen",
                                    icon: "person.2"
                                )
                                menuRow(
                                    .ghostRace,
                                    english: "Ghost Race",
                                    norwegian: "Ghost Race",
                                    icon: "figure.run"
                                )
                                menuRow(
                                    .exerciseProgress,
                                    english: "Exercise progression",
                                    norwegian: "Øvelsesfremdrift",
                                    icon: "chart.xyaxis.line"
                                )
                            }

                            menuSection(
                                english: "COMPETITION & CLUBS",
                                norwegian: "KONKURRANSER OG KLUBBER"
                            ) {
                                menuRow(
                                    .arena,
                                    english: "Arena",
                                    norwegian: "Arena",
                                    icon: "trophy"
                                )
                                menuRow(
                                    .clubs,
                                    english: "Clubs",
                                    norwegian: "Klubber",
                                    icon: "person.3"
                                )
                            }
                        }
                        .padding(.horizontal, 7)
                        .padding(.top, 16)
                        .padding(.bottom, 16)
                    }
                    .scrollIndicators(.hidden)

                    footer
                        .padding(.horizontal, 7)
                        .padding(.top, 10)
                        .padding(.bottom, max(geometry.safeAreaInsets.bottom, 20) + 6)
                }
                .frame(
                    width: ATHLTHSideMenuLayoutPolicy.width(
                        for: geometry.size.width
                    ),
                    height: geometry.size.height
                )
                .background {
                    menuSurface
                        .ignoresSafeArea(edges: .vertical)
                }
                .overlay(alignment: .trailing) {
                    menuBronze.opacity(0.15)
                        .frame(width: 1)
                        .allowsHitTesting(false)
                }
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                )
                .shadow(color: .black.opacity(0.15), radius: 22, x: 8, y: 0)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 24)
                        .onEnded { value in
                            if ATHLTHSideMenuLayoutPolicy.shouldDismiss(
                                translation: value.translation
                            ) {
                                onDismiss()
                            }
                        }
                )
                .accessibilityIdentifier("athlth-side-menu-drawer")

            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        // The entire panel, not only its background, reaches both screen edges.
        .ignoresSafeArea(.container, edges: .vertical)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ATHLTH")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .tracking(1.0)
                        .foregroundStyle(menuInk)
                    Text(ATHLTHLocalization.choose(
                        english: "YOUR TRAINING SPACE",
                        norwegian: "DITT TRENINGSROM"
                    ))
                    .font(.system(size: 7, weight: .medium))
                    .tracking(0.5)
                    .lineLimit(2)
                    .foregroundStyle(menuMuted)
                }

                Spacer(minLength: 0)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(menuInk)
                        .frame(width: 32, height: 32)
                        .background(menuCard, in: Circle())
                        .overlay(Circle().strokeBorder(warmDivider, lineWidth: 1))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Close navigation menu",
                    norwegian: "Lukk sidemenyen"
                ))
            }


        }
    }

    @ViewBuilder
    private var profileImage: some View {
        Group {
            if let avatarURL = session.profile.avatarURL {
                ATHLTHStorageImage(url: avatarURL, maxPixelSize: 160) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        profilePlaceholder
                    }
                }
            } else {
                profilePlaceholder
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(Circle())
        .overlay {
            Circle()
                .strokeBorder(menuBronze.opacity(0.42), lineWidth: 1)
        }
    }

    private var profilePlaceholder: some View {
        Circle()
            .fill(menuSurface)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: 19))
                    .foregroundStyle(menuBronze)
            }
    }

    private func menuSection<Content: View>(
        english: String,
        norwegian: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(ATHLTHLocalization.choose(
                english: english,
                norwegian: norwegian
            ))
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.55)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(menuBronze)
            .padding(.leading, 7)

            VStack(spacing: 2, content: content)
        }
    }

    /// Tapping the name opens the library; only the trailing chevron expands
    /// the four personal destinations. Preserve these distinct actions.
    private var trainingLibraryMenu: some View {
        VStack(spacing: 2) {
            HStack(spacing: 0) {
                Button {
                    onSelect(.trainingLibrary)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "books.vertical")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(menuBronze)
                            .frame(width: 18)
                            .accessibilityHidden(true)

                        Text(ATHLTHLocalization.choose(
                            english: "Training library",
                            norwegian: "Treningsbibliotek"
                        ))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(menuInk)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 7)
                    .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 70 : 50)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("athlth-side-menu-training-library-open")
                .accessibilityHint(ATHLTHLocalization.choose(
                    english: "Opens the complete training library",
                    norwegian: "Åpner hele treningsbiblioteket"
                ))

                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.20)) {
                        isTrainingLibraryExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(menuBronze)
                        .rotationEffect(.degrees(isTrainingLibraryExpanded ? 180 : 0))
                        .frame(width: 25,
                               height: dynamicTypeSize.isAccessibilitySize ? 70 : 50)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: isTrainingLibraryExpanded
                        ? "Collapse training library shortcuts"
                        : "Expand training library shortcuts",
                    norwegian: isTrainingLibraryExpanded
                        ? "Skjul snarveier i treningsbiblioteket"
                        : "Vis snarveier i treningsbiblioteket"
                ))
                .accessibilityIdentifier("athlth-side-menu-training-library-expand")
            }
            .background {
                if isTrainingLibraryExpanded {
                    RoundedRectangle(cornerRadius: 13)
                        .fill(menuBronze.opacity(0.07))
                }
            }

            if isTrainingLibraryExpanded {
                VStack(spacing: 1) {
                    menuRow(
                        .myExercises,
                        english: "Exercises",
                        norwegian: "Øvelser",
                        icon: "dumbbell"
                    )
                    menuRow(
                        .myRoutes,
                        english: "Routes",
                        norwegian: "Ruter",
                        icon: "map"
                    )
                    menuRow(
                        .myTrainingPlans,
                        english: "Training plans",
                        norwegian: "Treningsplaner",
                        icon: "calendar"
                    )
                    menuRow(
                        .myWorkouts,
                        english: "Workouts",
                        norwegian: "Treningsøkter",
                        icon: "bookmark"
                    )
                }
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(menuBronze.opacity(0.30))
                        .frame(width: 2)
                        .padding(.vertical, 7)
                }
                .padding(.bottom, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func menuRow(
        _ destination: ATHLTHSideMenuDestination,
        english: String,
        norwegian: String,
        icon: String,
        selected: Bool = false
    ) -> some View {
        Button {
            onSelect(destination)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(menuBronze)
                    .frame(width: 18)
                    .accessibilityHidden(true)

                Text(ATHLTHLocalization.choose(
                    english: english, norwegian: norwegian
                ))
                .font(.system(size: 12, weight: selected ? .semibold : .medium))
                .foregroundStyle(menuInk)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
                if selected {
                    Circle()
                        .fill(menuBronze)
                        .frame(width: 5, height: 5)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(menuMuted.opacity(0.6))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 7)
            .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 70 : 50)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 13)
                        .fill(menuBronze.opacity(0.10))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var homeUnreadInbox: Int {
        max(
            0,
            messaging.unreadCount +
                messaging.messageRequestCount +
                social.inboxEvents.filter {
                    $0.kind == "challenge_invite" && $0.readAt == nil
                }.count
        )
    }

    private var homeUnreadNotifications: Int {
        max(
            0,
            notificationStore.notificationCenterUnreadCount +
                health.pendingWorkoutImportCount
        )
    }

    /// Quick actions live together rather than in three competing tiles.
    /// Their destinations and unread counters remain unchanged.
    private var homeUtilityActions: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(warmDivider)
                .frame(height: 1)
                .padding(.horizontal, 7)
                .padding(.bottom, 6)

            HStack(alignment: .center, spacing: 0) {
                utilityAction(
                    .search,
                    english: "Search",
                    norwegian: "Søk",
                    icon: "magnifyingglass"
                )
                utilitySeparator
                utilityAction(
                    .inbox,
                    english: "Inbox",
                    norwegian: "Innboks",
                    icon: "tray",
                    count: homeUnreadInbox
                )
                utilitySeparator
                utilityAction(
                    .notifications,
                    english: "Alerts",
                    norwegian: "Varsler",
                    icon: "bell",
                    count: homeUnreadNotifications
                )
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 3)
        .accessibilityIdentifier("athlth-side-menu-home-utilities")
    }

    private var utilitySeparator: some View {
        Rectangle()
            .fill(warmDivider)
            .frame(width: 1, height: 30)
            .padding(.bottom, 2)
            .accessibilityHidden(true)
    }

    private func utilityAction(
        _ destination: ATHLTHSideMenuDestination,
        english: String,
        norwegian: String,
        icon: String,
        count: Int = 0
    ) -> some View {
        let name = ATHLTHLocalization.choose(
            english: english, norwegian: norwegian
        )

        return Button {
            onSelect(destination)
        } label: {
            VStack(spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(menuBronze)
                        .frame(width: 27, height: 29)
                        .background(
                            menuSurface,
                            in: RoundedRectangle(cornerRadius: 10)
                        )

                    if count > 0 {
                        Text(count > 99 ? "99+" : "\(count)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .frame(minHeight: 17)
                            .background(Color.red, in: Capsule())
                            .offset(x: 10, y: -6)
                            .accessibilityHidden(true)
                    }
                }

                Text(name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(menuInk)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(0.84)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 80 : 61)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count > 0
            ? "\(name), \(count)"
            : name
        )
    }

    private var footer: some View {
        VStack(spacing: 11) {
            Rectangle()
                .fill(warmDivider)
                .frame(height: 1)

            Button {
                onSelect(.settings)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(menuBronze)
                        .frame(width: 26, height: 28)
                        .background(menuSurface, in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityHidden(true)

                    Text(ATHLTHLocalization.choose(
                        english: "Settings", norwegian: "Innstillinger"
                    ))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                    .foregroundStyle(menuInk)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(menuMuted.opacity(0.6))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 7)
                .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 68 : 47)
                .background(menuCard, in: RoundedRectangle(cornerRadius: 15))
                .overlay {
                    RoundedRectangle(cornerRadius: 15)
                        .strokeBorder(warmDivider, lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 15))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("athlth-side-menu-settings")

            Rectangle()
                .fill(warmDivider)
                .frame(height: 1)

            // Profile stays pinned to the bottom, outside the scroll area.
            Button {
                onSelect(.profile)
            } label: {
                HStack(spacing: 5) {
                    profileImage

                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.profile.displayName.isEmpty
                             ? "ATHLTH"
                             : session.profile.displayName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(menuInk)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)

                        Text(session.profile.username.isEmpty
                             ? ATHLTHLocalization.choose(
                                 english: "My profile", norwegian: "Min profil"
                               )
                             : "@\(session.profile.username)")
                            .font(.system(size: 9))
                            .foregroundStyle(menuMuted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(menuBronze)
                        .frame(width: 16, height: 20)
                        .background(menuSurface, in: Circle())
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 6)
                .frame(minHeight: 72)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(menuCard, in: RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(warmDivider, lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ATHLTHLocalization.choose(
                english: "Open my ATHLTH profile",
                norwegian: "Åpne ATHLTH-profilen min"
            ))
            .accessibilityIdentifier("athlth-side-menu-profile")

        }
    }
}

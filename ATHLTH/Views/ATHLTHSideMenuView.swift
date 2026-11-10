import SwiftUI

/// Keeps the iPhone drawer comfortably narrow while leaving enough of Home
/// visible to communicate that the menu is a temporary overlay.
enum ATHLTHSideMenuLayoutPolicy {
    static func width(for viewportWidth: CGFloat) -> CGFloat {
        let preferred = min(max(viewportWidth * 0.76, 260), 320)
        return max(0, min(preferred, viewportWidth - 56))
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
    private let menuSurface = Color(red: 0.983, green: 0.978, blue: 0.968)
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
                        .padding(.horizontal, 17)
                        .padding(.top, 12)
                        .padding(.bottom, 12)

                    Rectangle()
                        .fill(warmDivider)
                        .frame(height: 1)
                        .padding(.horizontal, 17)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
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
                        .padding(.horizontal, 14)
                        .padding(.top, 17)
                        .padding(.bottom, 24)
                    }
                    .scrollIndicators(.hidden)

                    footer
                        .padding(.horizontal, 17)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
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
                        bottomTrailingRadius: 28,
                        topTrailingRadius: 28
                    )
                )
                .shadow(color: .black.opacity(0.15), radius: 28, x: 8, y: 0)
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
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ATHLTH")
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                        .tracking(2.2)
                        .foregroundStyle(menuInk)
                    Text(ATHLTHLocalization.choose(
                        english: "YOUR TRAINING SPACE",
                        norwegian: "DITT TRENINGSROM"
                    ))
                    .font(.system(size: 9, weight: .medium))
                    .tracking(1.25)
                    .foregroundStyle(menuMuted)
                }

                Spacer(minLength: 8)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(menuInk)
                        .frame(width: 40, height: 40)
                        .background(menuCard, in: Circle())
                        .overlay(Circle().strokeBorder(warmDivider, lineWidth: 1))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Close navigation menu",
                    norwegian: "Lukk sidemenyen"
                ))
            }

            Button {
                onSelect(.profile)
            } label: {
                HStack(spacing: 11) {
                    profileImage

                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.profile.displayName.isEmpty
                             ? "ATHLTH"
                             : session.profile.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(menuInk)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Text(session.profile.username.isEmpty
                             ? ATHLTHLocalization.choose(
                                 english: "My profile", norwegian: "Min profil"
                               )
                             : "@\(session.profile.username)")
                            .font(.caption)
                            .foregroundStyle(menuMuted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 2)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(menuBronze)
                        .frame(width: 28, height: 28)
                        .background(menuSurface, in: Circle())
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 78)
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
        .frame(width: 50, height: 50)
        .clipShape(Circle())
        .overlay {
            Circle()
                .strokeBorder(menuBronze.opacity(0.42), lineWidth: 1)
        }
    }

    private var profilePlaceholder: some View {
        Circle()
            .fill(ATHLTHTheme.premiumGoldSoft)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: 19))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
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
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(menuMuted)
            .padding(.leading, 8)

            VStack(spacing: 2, content: content)
                .padding(5)
                .background(menuCard, in: RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(warmDivider, lineWidth: 1)
                }
        }
    }

    /// Library name opens the complete hub. Only the separate trailing
    /// chevron expands or collapses the four personal shortcuts.
    private var trainingLibraryMenu: some View {
        VStack(spacing: 2) {
            HStack(spacing: 0) {
                Button {
                    onSelect(.trainingLibrary)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "books.vertical")
                            .font(.system(size: 18, weight: .regular))
                            .frame(width: 22)
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .accessibilityHidden(true)

                        Text(ATHLTHLocalization.choose(
                            english: "Training library",
                            norwegian: "Treningsbibliotek"
                        ))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ATHLTHTheme.primaryText)

                        Spacer(minLength: 4)
                    }
                    .padding(.leading, 11)
                    .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 58 : 46)
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
                    Image(systemName: isTrainingLibraryExpanded
                          ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .frame(width: 48,
                               height: dynamicTypeSize.isAccessibilitySize ? 58 : 46)
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
                .padding(.leading, 18)
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
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(menuBronze)
                    .frame(width: 32, height: 32)
                    .background(
                        menuSurface.opacity(selected ? 1 : 0.74),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .accessibilityHidden(true)

                Text(ATHLTHLocalization.choose(
                    english: english, norwegian: norwegian
                ))
                .font(.subheadline.weight(selected ? .semibold : .medium))
                .foregroundStyle(menuInk)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(0.86)
                .multilineTextAlignment(.leading)

                Spacer(minLength: 2)
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
            .padding(.horizontal, 8)
            .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 58 : 48)
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

    /// The former Home hero actions now live immediately under Hjem. Their
    /// destinations and unread counters remain identical to the old toolbar.
    private var homeUtilityActions: some View {
        HStack(alignment: .top, spacing: 9) {
            utilityAction(
                .search,
                english: "Search",
                norwegian: "Søk",
                icon: "magnifyingglass"
            )
            utilityAction(
                .inbox,
                english: "Inbox",
                norwegian: "Innboks",
                icon: "tray",
                count: homeUnreadInbox
            )
            utilityAction(
                .notifications,
                english: "Alerts",
                norwegian: "Varsler",
                icon: "bell",
                count: homeUnreadNotifications
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
        .accessibilityIdentifier("athlth-side-menu-home-utilities")
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
            VStack(spacing: 7) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.88))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(warmDivider, lineWidth: 1)
                        }
                        .frame(height: 46)
                        .overlay {
                            Image(systemName: icon)
                                .font(.system(size: 19, weight: .medium))
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                        }

                    if count > 0 {
                        Text(count > 99 ? "99+" : "\(count)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .frame(minHeight: 18)
                            .background(Color.red, in: Capsule())
                            .offset(x: 3, y: -6)
                            .accessibilityHidden(true)
                    }
                }

                Text(name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count > 0
            ? "\(name), \(count)"
            : name
        )
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Rectangle()
                .fill(warmDivider)
                .frame(height: 1)

            Button {
                onSelect(.settings)
            } label: {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Settings",
                        norwegian: "Innstillinger"
                    ),
                    systemImage: "gearshape"
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 46)
                .foregroundStyle(.white)
                .background(
                    ATHLTHTheme.accentDeep,
                    in: RoundedRectangle(cornerRadius: 16)
                )
            }
            .buttonStyle(.plain)

            Text("YOUR BODY. YOUR DATA. YOUR PROGRESS.")
                .font(.system(size: 9, weight: .medium))
                .tracking(1.1)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

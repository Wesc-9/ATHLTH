import SwiftUI

/// iPhone drawer stays half screen for ordinary text sizes.
enum ATHLTHSideMenuLayoutPolicy {
    static func width(for viewportWidth: CGFloat) -> CGFloat {
        max(0, viewportWidth * 0.5)
    }

    static func shouldDismiss(translation: CGSize) -> Bool {
        translation.width <= -60 &&
            abs(translation.height) <= abs(translation.width) * 0.65
    }

    /// Horizontal drags follow the finger; ordinary vertical menu scrolling does not.
    static func interactiveOffset(for translation: CGSize) -> CGFloat {
        guard translation.width < 0,
              abs(translation.height) <= abs(translation.width) * 0.65
        else { return 0 }
        return translation.width
    }
}

/// Single badge calculation shared by the root app indicator and the side menu.
/// A challenge invitation imported into Notifications must not be counted twice.
enum ATHLTHSideMenuBadgePolicy {
    static func counts(
        messageUnread: Int,
        messageRequests: Int,
        backendChallengeInvites: Int,
        importedChallengeInvites: Int,
        notificationUnread: Int,
        pendingWorkoutImports: Int
    ) -> (inbox: Int, notifications: Int, total: Int) {
        let uncovered = max(backendChallengeInvites - importedChallengeInvites, 0)
        let inbox = max(0, messageUnread + messageRequests + uncovered)
        let alerts = max(0, notificationUnread + pendingWorkoutImports)
        return (inbox, alerts, inbox + alerts)
    }

    @MainActor
    static func counts(
        messaging: MessagingStore,
        social: SocialStore,
        notificationStore: ATHLTHNotificationStore,
        health: HealthKitManager
    ) -> (inbox: Int, notifications: Int, total: Int) {
        let backendInvites = social.inboxEvents.filter {
            $0.kind.lowercased() == "challenge_invite" && $0.readAt == nil
        }.count
        let importedInvites = notificationStore.notificationCenterItems.filter {
            $0.isUnread && $0.socialEventKind?.lowercased() == "challenge_invite"
        }.count
        return counts(
            messageUnread: messaging.unreadCount,
            messageRequests: messaging.messageRequestCount,
            backendChallengeInvites: backendInvites,
            importedChallengeInvites: importedInvites,
            notificationUnread: notificationStore.notificationCenterUnreadCount,
            pendingWorkoutImports: health.pendingWorkoutImportCount
        )
    }
}

/// Compact shortcuts, never copies of ATHLTH's canonical feature screens.
/// The backdrop and presentation animation are owned by ProductRootTabView.
struct ATHLTHSideMenuView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var messaging: MessagingStore
    @EnvironmentObject private var notificationStore: ATHLTHNotificationStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var health: HealthKitManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .subheadline) private var rowTextSize: CGFloat = 12
    @ScaledMetric(relativeTo: .caption) private var headingTextSize: CGFloat = 10
    @GestureState private var closingDragX: CGFloat = 0
    @SceneStorage("athlth.sideMenu.trainingLibraryExpanded")
    private var isTrainingLibraryExpanded = false

    let selectedTab: Int
    let onSelect: (ATHLTHSideMenuDestination) -> Void
    let onDismiss: () -> Void

    // Use canonical app colors; avoid slightly different hand-written whites.
    private let menuSurface = ATHLTHTheme.canvasTop
    private let menuCard = ATHLTHTheme.card
    private let menuInk = ATHLTHTheme.primaryText
    private let menuMuted = ATHLTHTrainDesign.secondary
    private let menuBronze = ATHLTHTrainDesign.bronze
    private let menuDivider = ATHLTHTheme.divider

    private var badges: (inbox: Int, notifications: Int, total: Int) {
        ATHLTHSideMenuBadgePolicy.counts(
            messaging: messaging,
            social: social,
            notificationStore: notificationStore,
            health: health
        )
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 9)
                    .padding(.top, max(geometry.safeAreaInsets.top, 48) + 6)
                    .padding(.bottom, 9)

                Rectangle().fill(menuDivider).frame(height: 1)

                homeUtilityActions
                    .padding(.horizontal, 5)
                    .padding(.vertical, 7)

                Rectangle()
                    .fill(menuDivider)
                    .frame(height: 1)
                    .padding(.horizontal, 9)

                ScrollView {
                    VStack(alignment: .leading, spacing: 15) {
                        menuSection(
                            english: "TRAINING", norwegian: "TRENING"
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
                        }

                        menuSection(
                            english: "COMMUNITY", norwegian: "FELLESSKAP"
                        ) {
                            menuRow(
                                .challenges,
                                english: "Challenges",
                                norwegian: "Challenges",
                                icon: "bolt"
                            )
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
                    .padding(.horizontal, 6)
                    .padding(.top, 14)
                    .padding(.bottom, 14)
                }
                .scrollIndicators(.hidden)

                footer
                    .padding(.horizontal, 7)
                    .padding(.top, 5)
                    .padding(.bottom, max(geometry.safeAreaInsets.bottom, 20) + 5)
            }
            .frame(
                width: ATHLTHSideMenuLayoutPolicy.width(for: geometry.size.width),
                height: geometry.size.height
            )
            .background(menuSurface.ignoresSafeArea(edges: .vertical))
            .overlay(alignment: .trailing) {
                menuDivider.frame(width: 1).allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.12), radius: 20, x: 6, y: 0)
            .offset(x: reduceMotion ? 0 : closingDragX)
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .updating($closingDragX) { value, state, _ in
                        guard !reduceMotion else { return }
                        state = ATHLTHSideMenuLayoutPolicy.interactiveOffset(
                            for: value.translation
                        )
                    }
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
        .ignoresSafeArea(.container, edges: .vertical)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 4) {
            ATHLTHBrandMark(
                size: .compact,
                wordmarkWeight: .semibold,
                markStrokeScale: 0.85
            )
            .foregroundStyle(menuInk)

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(menuInk)
                    .frame(width: 34, height: 34)
                    .background(menuCard, in: Circle())
                    .overlay(Circle().strokeBorder(menuDivider, lineWidth: 1))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ATHLTHLocalization.choose(
                english: "Close navigation menu",
                norwegian: "Lukk sidemenyen"
            ))
        }
    }

    private func menuSection<Content: View>(
        english: String,
        norwegian: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(ATHLTHLocalization.choose(english: english, norwegian: norwegian))
                .font(.system(size: headingTextSize, weight: .semibold))
                .tracking(0.45)
                .foregroundStyle(menuBronze)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 8)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 1, content: content)
        }
    }

    /// Row opens the library; separate trailing button expands its shortcuts.
    /// Both interactions have comfortable, independent touch targets.
    private var trainingLibraryMenu: some View {
        VStack(spacing: 1) {
            HStack(spacing: 0) {
                Button {
                    onSelect(.trainingLibrary)
                } label: {
                    HStack(spacing: 7) {
                        menuIcon("books.vertical")
                        menuLabel(
                            english: "Library", norwegian: "Bibliotek"
                        )
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 7)
                    .frame(minHeight: rowHeight)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("athlth-side-menu-training-library-open")
                .accessibilityHint(ATHLTHLocalization.choose(
                    english: "Open the complete training library",
                    norwegian: "Åpne hele treningsbiblioteket"
                ))

                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                        isTrainingLibraryExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(menuBronze)
                        .rotationEffect(.degrees(isTrainingLibraryExpanded ? 180 : 0))
                        .frame(width: 44, height: max(44, rowHeight))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: isTrainingLibraryExpanded
                        ? "Collapse library shortcuts" : "Expand library shortcuts",
                    norwegian: isTrainingLibraryExpanded
                        ? "Skjul bibliotek-snarveier" : "Vis bibliotek-snarveier"
                ))
                .accessibilityIdentifier("athlth-side-menu-training-library-expand")
            }
            .background {
                if isTrainingLibraryExpanded {
                    RoundedRectangle(cornerRadius: 12).fill(ATHLTHTheme.premiumGoldSoft)
                }
            }

            if isTrainingLibraryExpanded {
                VStack(spacing: 1) {
                    menuRow(.myExercises, english: "Exercises", norwegian: "Øvelser", icon: "dumbbell")
                    menuRow(.myRoutes, english: "Routes", norwegian: "Ruter", icon: "map")
                    menuRow(.myTrainingPlans, english: "Training plans", norwegian: "Treningsplaner", icon: "calendar")
                    menuRow(.myWorkouts, english: "Workouts", norwegian: "Treningsøkter", icon: "bookmark")
                }
                .padding(.leading, 5)
                .overlay(alignment: .leading) {
                    menuBronze.opacity(0.20)
                        .frame(width: 2)
                        .padding(.vertical, 6)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var rowHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 72 : 48
    }

    private func menuIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(menuBronze)
            .frame(width: 19, height: 24)
            .accessibilityHidden(true)
    }

    private func menuLabel(english: String, norwegian: String) -> some View {
        Text(ATHLTHLocalization.choose(english: english, norwegian: norwegian))
            .font(.system(size: rowTextSize, weight: .medium))
            .foregroundStyle(menuInk)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
    }

    private func menuRow(
        _ destination: ATHLTHSideMenuDestination,
        english: String,
        norwegian: String,
        icon: String
    ) -> some View {
        Button {
            onSelect(destination)
        } label: {
            HStack(spacing: 7) {
                menuIcon(icon)
                menuLabel(english: english, norwegian: norwegian)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(menuMuted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 7)
            .frame(minHeight: rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var homeUtilityActions: some View {
        HStack(spacing: 1) {
            Button { onSelect(.search) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(menuBronze)
                    Text(ATHLTHLocalization.choose(english: "Search", norwegian: "Søk"))
                        .font(.system(size: rowTextSize, weight: .medium))
                        .foregroundStyle(menuInk)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 7)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("athlth-side-menu-search")

            utilityIcon(
                .inbox,
                symbol: "tray",
                english: "Inbox",
                norwegian: "Innboks",
                count: badges.inbox
            )
            utilityIcon(
                .notifications,
                symbol: "bell",
                english: "Notifications",
                norwegian: "Varsler",
                count: badges.notifications
            )
        }
        .accessibilityIdentifier("athlth-side-menu-home-utilities")
    }

    private func utilityIcon(
        _ destination: ATHLTHSideMenuDestination,
        symbol: String,
        english: String,
        norwegian: String,
        count: Int
    ) -> some View {
        let title = ATHLTHLocalization.choose(english: english, norwegian: norwegian)
        return Button { onSelect(destination) } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(menuBronze)
                .frame(width: 44, height: 44)
                .overlay(alignment: .topTrailing) {
                    if count > 0 {
                        Text(count > 99 ? "99+" : "\(count)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .frame(minHeight: 16)
                            .background(.red, in: Capsule())
                            .offset(x: 2, y: -1)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count > 0 ? "\(title), \(count)" : title)
        .accessibilityIdentifier(
            destination == .inbox
                ? "athlth-side-menu-inbox"
                : "athlth-side-menu-notifications"
        )
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
            Circle().strokeBorder(menuBronze.opacity(0.25), lineWidth: 1)
        }
    }

    private var profilePlaceholder: some View {
        Circle()
            .fill(ATHLTHTheme.premiumGoldSoft)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(menuBronze)
            }
    }

    private var footer: some View {
        VStack(spacing: 7) {
            Rectangle().fill(menuDivider).frame(height: 1)

            Button { onSelect(.settings) } label: {
                HStack(spacing: 7) {
                    menuIcon("gearshape")
                    menuLabel(english: "Settings", norwegian: "Innstillinger")
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(menuMuted)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .background(menuCard, in: RoundedRectangle(cornerRadius: 13))
                .contentShape(RoundedRectangle(cornerRadius: 13))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("athlth-side-menu-settings")

            Button { onSelect(.profile) } label: {
                HStack(spacing: 6) {
                    profileImage
                    Text(session.profile.displayName.isEmpty
                         ? "ATHLTH" : session.profile.displayName)
                        .font(.system(size: rowTextSize, weight: .semibold))
                        .foregroundStyle(menuInk)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(menuBronze)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                .background(menuCard, in: RoundedRectangle(cornerRadius: 14))
                .contentShape(RoundedRectangle(cornerRadius: 14))
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

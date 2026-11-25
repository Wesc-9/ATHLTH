import SwiftUI

/// Keep a comfortably sized iPhone drawer without swallowing the Home screen.
/// A slightly wider canvas avoids cramped text and utility buttons, while
/// VoiceOver/Dynamic Type gets additional room for longer localized labels.
enum ATHLTHSideMenuLayoutPolicy {
    static func width(
        for viewportWidth: CGFloat,
        accessibilitySize: Bool = false
    ) -> CGFloat {
        guard viewportWidth > 0 else { return 0 }
        let ratio: CGFloat = accessibilitySize ? 0.78 : 0.60
        let maximum: CGFloat = accessibilitySize ? 350 : 280
        return min(viewportWidth * ratio, maximum)
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

/// One palette for the phone drawer and native iPad Studio sidebar.
enum ATHLTHSidebarPalette {
    static let canvas = Color(red: 0.985, green: 0.979, blue: 0.965)
    static let ink = Color(red: 0.19, green: 0.18, blue: 0.16)
    static let gold = Color(red: 0.69, green: 0.54, blue: 0.32)
}

/// Subtle touch feedback with no permanent colored tiles around each item.
private struct ATHLTHSideMenuPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 13)
                    .fill(configuration.isPressed
                        ? ATHLTHTheme.premiumGoldSoft.opacity(0.72)
                        : Color.clear)
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
    @ScaledMetric(relativeTo: .subheadline) private var rowTextSize: CGFloat = 15.5
    @GestureState private var closingDragX: CGFloat = 0

    let selectedTab: Int
    let onSelect: (ATHLTHSideMenuDestination) -> Void
    let onDismiss: () -> Void

    private let menuSurface = ATHLTHSidebarPalette.canvas
    private let menuInk = ATHLTHSidebarPalette.ink
    private let menuMuted = ATHLTHTrainDesign.secondary
    private let menuBronze = ATHLTHSidebarPalette.gold

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
                    .padding(.horizontal, 18)
                    .padding(.top, max(geometry.safeAreaInsets.top, 48) + 4)
                    .padding(.bottom, 16)

                // Only the container scrolls on small screens / large text.
                // Individual rows never expand or reveal submenus.
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(ATHLTHSideMenuDestination.phoneUtilityRows) { destination in
                            staticRow(destination)
                        }
                        Divider().padding(.vertical, 12).padding(.horizontal, 7)
                        ForEach(ATHLTHSideMenuDestination.phonePrimaryRows) { destination in
                            staticRow(destination)
                        }
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.hidden)

                Divider().padding(.horizontal, 18)
                footer
                    .padding(.horizontal, 13)
                    .padding(.top, 11)
                    .padding(.bottom, max(geometry.safeAreaInsets.bottom, 20) + 4)
            }
            .frame(
                width: ATHLTHSideMenuLayoutPolicy.width(
                    for: geometry.size.width,
                    accessibilitySize: dynamicTypeSize.isAccessibilitySize
                ),
                height: geometry.size.height
            )
            .background(menuSurface.ignoresSafeArea(edges: .vertical))
            .shadow(color: .black.opacity(0.09), radius: 18, x: 5, y: 0)
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
        HStack(alignment: .center, spacing: 6) {
            ATHLTHBrandMark(
                size: .compact,
                wordmarkWeight: .medium,
                markStrokeScale: 0.70
            )
            .foregroundStyle(menuInk)

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(menuInk)
                    .frame(width: 38, height: 38)
                    .background(menuBronze.opacity(0.075), in: Circle())
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

    private var rowHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 74 : 51
    }

    private func menuIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 18, weight: .regular))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(menuBronze)
            .frame(width: 24, height: 26)
            .accessibilityHidden(true)
    }

    private func menuLabel(english: String, norwegian: String) -> some View {
        Text(ATHLTHLocalization.choose(english: english, norwegian: norwegian))
            .font(.system(size: rowTextSize, weight: .medium))
            .foregroundStyle(menuInk)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
    }

    private func staticRow(_ destination: ATHLTHSideMenuDestination) -> some View {
        let item: (english: String, norwegian: String, icon: String, identifier: String)
        switch destination {
        case .search: item = ("Search", "Søk", "magnifyingglass", "search")
        case .notifications: item = ("Notifications", "Varsler", "bell", "notifications")
        case .inbox: item = ("Messages", "Meldinger", "bubble.left.and.bubble.right", "inbox")
        case .trainNow: item = ("Train now", "Tren nå", "play.circle", "train-now")
        case .trainingLibrary: item = ("Library", "Bibliotek", "books.vertical", "training-library-open")
        case .clubs: item = ("Club", "Klubb", "person.3", "clubs")
        case .arena: item = ("Competition", "Konkurranse", "trophy", "competition")
        default: item = ("", "", "circle", destination.rawValue)
        }
        let count = destination == .notifications ? badges.notifications :
            destination == .inbox ? badges.inbox : 0
        let selected = destination == .trainNow && selectedTab == 1
        let title = ATHLTHLocalization.choose(english: item.english, norwegian: item.norwegian)
        return Button { onSelect(destination) } label: {
            HStack(spacing: 12) {
                Image(systemName: item.icon)
                    .font(.system(size: 17, weight: .regular))
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: rowTextSize, weight: selected ? .semibold : .regular))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if count > 0 {
                    Text(count > 99 ? "99+" : "\(count)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(menuInk)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 22, minHeight: 22)
                        .background(menuBronze.opacity(0.14), in: Capsule())
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(selected ? menuInk : menuInk.opacity(0.78))
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 64 : 46, alignment: .leading)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 11).fill(.white)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(ATHLTHSideMenuPressStyle())
        .accessibilityLabel(count > 0 ? "\(title), \(count)" : title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("athlth-side-menu-" + item.identifier)
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
        .frame(width: 40, height: 40)
        .clipShape(Circle())
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
        VStack(spacing: 9) {
            Button { onSelect(.settings) } label: {
                HStack(spacing: 0) {
                    HStack(spacing: 11) {
                        menuIcon("gearshape")
                        menuLabel(english: "Settings", norwegian: "Innstillinger")
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(menuMuted.opacity(0.82))
                        .frame(width: 44, height: rowHeight)
                        .accessibilityHidden(true)
                }
                .padding(.leading, 8)
                .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(ATHLTHSideMenuPressStyle())
            .accessibilityIdentifier("athlth-side-menu-settings")

            Button { onSelect(.profile) } label: {
                HStack(spacing: 8) {
                    profileImage
                    Text(session.profile.displayName.isEmpty
                         ? "ATHLTH" : session.profile.displayName)
                        .font(.system(size: rowTextSize, weight: .semibold))
                        .foregroundStyle(menuInk)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        .minimumScaleFactor(0.88)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(menuBronze)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(ATHLTHSideMenuPressStyle())
            .accessibilityLabel(ATHLTHLocalization.choose(
                english: "Open my ATHLTH profile",
                norwegian: "Åpne ATHLTH-profilen min"
            ))
            .accessibilityIdentifier("athlth-side-menu-profile")
        }
    }
}

import SwiftUI

enum SubscriptionTier: String, Codable, CaseIterable, Identifiable, Hashable {
    case free
    case paid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free: return "Free"
        case .paid: return "Paid"
        }
    }
}

enum AdminAccountStatus: String, Codable, Hashable {
    case active
    case suspended

    var title: String {
        switch self {
        case .active: return "Active"
        case .suspended: return "Suspended"
        }
    }
}

struct AdminConnectionSummary: Codable, Hashable {
    var appleHealth: Bool
    var appleWatch: Bool
    var spotify: Bool
}

struct AdminUserRecord: Identifiable, Codable, Hashable {
    let id: UUID
    var username: String
    var email: String
    var role: AccountRole
    var subscription: SubscriptionTier
    var createdAt: Date
    var lastActiveAt: Date
    var onboardingCompleted: Bool
    var currentGoal: AchievementGoal?
    var interests: Set<ATHLTHInterest>
    var offerConsent: PersonalizedOfferConsent
    var connections: AdminConnectionSummary
    var status: AdminAccountStatus
}

struct AdminMetricBreakdown: Identifiable, Hashable {
    let id: String
    var title: String
    var count: Int
    var percentage: Double
}

struct AdminAnalyticsSnapshot: Hashable {
    var totalUsers: Int
    var freeUsers: Int
    var paidUsers: Int
    var privilegedUsers: Int
    var newUsers7Days: Int
    var newUsers30Days: Int
    var activeUsers7Days: Int
    var activeUsers30Days: Int
    var onboardingCompletionPercent: Double
    var appleHealthConnectedPercent: Double
    var appleWatchConnectedPercent: Double
    var spotifyConnectedPercent: Double
    var personalizedOfferConsentPercent: Double
    var goalBreakdown: [AdminMetricBreakdown]
    var interestBreakdown: [AdminMetricBreakdown]
}

struct AdminAuditEvent: Identifiable, Hashable {
    let id: UUID
    var actor: String
    var action: String
    var target: String
    var createdAt: Date
}

enum AdminSafetyStatus: String, Hashable {
    case open
    case reviewing
    case resolved

    var title: String {
        switch self {
        case .open: return "Open"
        case .reviewing: return "Reviewing"
        case .resolved: return "Resolved"
        }
    }
}

struct AdminSafetyCase: Identifiable, Hashable {
    let id: UUID
    var username: String
    var category: String
    var status: AdminSafetyStatus
    var createdAt: Date
}

enum MarketingDeliveryState: String, Codable {
    case disabled
    case previewOnly
    case enabled

    var title: String {
        switch self {
        case .disabled: return "Disabled"
        case .previewOnly: return "Preview only"
        case .enabled: return "Enabled"
        }
    }
}

struct OfferCampaignDraft: Identifiable, Hashable {
    let id: UUID
    var title: String
    var productName: String
    var targetGoal: AchievementGoal?
    var requiredInterests: Set<ATHLTHInterest>
    var minimumAccountAgeDays: Int
    var deliveryState: MarketingDeliveryState

    init(
        id: UUID = UUID(),
        title: String,
        productName: String,
        targetGoal: AchievementGoal?,
        requiredInterests: Set<ATHLTHInterest> = [],
        minimumAccountAgeDays: Int,
        deliveryState: MarketingDeliveryState = .disabled
    ) {
        self.id = id
        self.title = title
        self.productName = productName
        self.targetGoal = targetGoal
        self.requiredInterests = requiredInterests
        self.minimumAccountAgeDays = minimumAccountAgeDays
        self.deliveryState = deliveryState
    }
}

struct MarketingEligibilityResult {
    var segmentMatches: Bool
    var sendEligible: Bool
    var reasons: [String]
}

enum MarketingEligibilityEngine {
    static func evaluate(
        profile: OnboardingProfileData?,
        accountCreatedAt: Date,
        draft: OfferCampaignDraft
    ) -> MarketingEligibilityResult {
        var segmentReasons: [String] = []

        guard let profile else {
            return MarketingEligibilityResult(
                segmentMatches: false,
                sendEligible: false,
                reasons: [
                    "No onboarding personalization data is available.",
                    "Campaign sending is disabled in V0.1."
                ]
            )
        }

        if let targetGoal = draft.targetGoal,
           profile.currentGoal?.type != targetGoal {
            segmentReasons.append("Current self-declared goal does not match this draft.")
        }

        if !draft.requiredInterests.isSubset(of: profile.interests) {
            segmentReasons.append("Required self-declared interests are missing.")
        }

        let accountAgeDays = Calendar.current.dateComponents(
            [.day],
            from: accountCreatedAt,
            to: Date()
        ).day ?? 0

        if accountAgeDays < draft.minimumAccountAgeDays {
            segmentReasons.append("Account is younger than the draft's waiting period.")
        }

        let segmentMatches = segmentReasons.isEmpty
        var reasons = segmentReasons

        if segmentMatches {
            reasons.append("Self-declared goal/interests match this draft's preview segment.")
        }

        if profile.personalizedOfferConsent != .granted {
            reasons.append("Personalized-offer consent has not been granted.")
        }

        if draft.deliveryState != .enabled {
            reasons.append("Campaign sending is disabled in V0.1.")
        }

        return MarketingEligibilityResult(
            segmentMatches: segmentMatches,
            sendEligible:
                segmentMatches &&
                profile.personalizedOfferConsent == .granted &&
                draft.deliveryState == .enabled,
            reasons: reasons
        )
    }
}

@MainActor
final class AdminControlCenterStore: ObservableObject {
    @Published var users: [AdminUserRecord]
    @Published var auditEvents: [AdminAuditEvent]
    @Published var safetyCases: [AdminSafetyCase]
    @Published var campaignHistory: [CampaignHistoryRecord]

    let analytics: AdminAnalyticsSnapshot
    let campaignDrafts: [OfferCampaignDraft]

    init() {
        users = AdminPreviewData.users
        auditEvents = AdminPreviewData.auditEvents
        safetyCases = AdminPreviewData.safetyCases
        campaignHistory = AdminPreviewData.campaignHistory
        analytics = AdminPreviewData.analytics
        campaignDrafts = AdminPreviewData.campaignDrafts
    }

    func campaignEvents(for userID: UUID) -> [UserCampaignEvent] {
        campaignHistory
            .flatMap { campaign in
                campaign.recipients
                    .filter { $0.userID == userID }
                    .map { recipient in
                        UserCampaignEvent(
                            id: UUID(),
                            campaignID: campaign.id,
                            campaignTitle: campaign.title,
                            channels: campaign.channels,
                            status: campaign.status,
                            sentAt: recipient.deliveredAt ?? campaign.sentAt,
                            openedAt: recipient.openedAt,
                            convertedAt: recipient.convertedAt
                        )
                    }
            }
            .sorted { ($0.sentAt ?? .distantPast) > ($1.sentAt ?? .distantPast) }
    }

    func previewGeneralFreeAudience() -> Int {
        analytics.freeUsers
    }

    func saveBlockedFreeCampaignDraft(
        title: String,
        message: String,
        channels: Set<CampaignChannel>,
        actorUsername: String
    ) {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty, !cleanedMessage.isEmpty, !channels.isEmpty else { return }

        let record = CampaignHistoryRecord(
            id: UUID(),
            title: cleanedTitle,
            message: cleanedMessage,
            audience: .freeUsers,
            channels: channels,
            status: .blocked,
            createdByUsername: actorUsername,
            createdAt: Date(),
            sentAt: nil,
            audienceCount: analytics.freeUsers,
            deliveredCount: 0,
            openedCount: 0,
            convertedCount: 0,
            recipients: []
        )

        campaignHistory.insert(record, at: 0)

        auditEvents.insert(
            AdminAuditEvent(
                id: UUID(),
                actor: "@\(actorUsername)",
                action: "Prepared Free-user campaign",
                target: cleanedTitle,
                createdAt: Date()
            ),
            at: 0
        )
    }

    func setRole(
        userID: UUID,
        role: AccountRole,
        actingRole: AccountRole,
        actorUsername: String
    ) {
        guard actingRole.canManageAdmins else { return }
        guard let index = users.firstIndex(where: { $0.id == userID }) else { return }
        guard users[index].role != .owner else { return }

        let oldRole = users[index].role
        users[index].role = role

        auditEvents.insert(
            AdminAuditEvent(
                id: UUID(),
                actor: "@\(actorUsername)",
                action: "Changed role \(oldRole.title) → \(role.title)",
                target: "@\(users[index].username)",
                createdAt: Date()
            ),
            at: 0
        )
    }

    func setAccountStatus(
        userID: UUID,
        status: AdminAccountStatus,
        actingRole: AccountRole,
        actorUsername: String
    ) {
        guard actingRole.canAccessControlCenter else { return }
        guard let index = users.firstIndex(where: { $0.id == userID }) else { return }
        guard users[index].role != .owner else { return }

        users[index].status = status
        auditEvents.insert(
            AdminAuditEvent(
                id: UUID(),
                actor: "@\(actorUsername)",
                action: status == .suspended ? "Suspended account" : "Reactivated account",
                target: "@\(users[index].username)",
                createdAt: Date()
            ),
            at: 0
        )
    }
}

enum AdminPreviewData {
    private static func daysAgo(_ value: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -value, to: Date()) ?? Date()
    }

    static let users: [AdminUserRecord] = [
        AdminUserRecord(
            id: PreviewData.userID,
            username: "stian",
            email: "owner@athlth.app",
            role: .owner,
            subscription: .paid,
            createdAt: daysAgo(120),
            lastActiveAt: Date(),
            onboardingCompleted: true,
            currentGoal: .buildMuscle,
            interests: [.strength, .nutrition, .trainingPlans],
            offerConsent: .granted,
            connections: AdminConnectionSummary(
                appleHealth: true,
                appleWatch: true,
                spotify: true
            ),
            status: .active
        ),
        AdminUserRecord(
            id: UUID(uuidString: "91111111-1111-1111-1111-111111111111")!,
            username: "sara_demo",
            email: "sara@example.com",
            role: .admin,
            subscription: .free,
            createdAt: daysAgo(64),
            lastActiveAt: daysAgo(1),
            onboardingCompleted: true,
            currentGoal: .runBetter,
            interests: [.running, .trainingPlans, .social],
            offerConsent: .declined,
            connections: AdminConnectionSummary(
                appleHealth: true,
                appleWatch: true,
                spotify: false
            ),
            status: .active
        ),
        AdminUserRecord(
            id: UUID(uuidString: "92222222-2222-2222-2222-222222222222")!,
            username: "erik_demo",
            email: "erik@example.com",
            role: .user,
            subscription: .paid,
            createdAt: daysAgo(31),
            lastActiveAt: daysAgo(2),
            onboardingCompleted: true,
            currentGoal: .getStronger,
            interests: [.strength, .trainingPlans],
            offerConsent: .granted,
            connections: AdminConnectionSummary(
                appleHealth: true,
                appleWatch: false,
                spotify: true
            ),
            status: .active
        ),
        AdminUserRecord(
            id: UUID(uuidString: "93333333-3333-3333-3333-333333333333")!,
            username: "live_demo",
            email: "live@example.com",
            role: .user,
            subscription: .free,
            createdAt: daysAgo(8),
            lastActiveAt: daysAgo(6),
            onboardingCompleted: true,
            currentGoal: .loseWeight,
            interests: [.walking, .nutrition, .healthTracking],
            offerConsent: .declined,
            connections: AdminConnectionSummary(
                appleHealth: false,
                appleWatch: false,
                spotify: false
            ),
            status: .active
        )
    ]

    static let analytics = AdminAnalyticsSnapshot(
        totalUsers: 1_248,
        freeUsers: 1_173,
        paidUsers: 75,
        privilegedUsers: 2,
        newUsers7Days: 38,
        newUsers30Days: 164,
        activeUsers7Days: 684,
        activeUsers30Days: 1_012,
        onboardingCompletionPercent: 91,
        appleHealthConnectedPercent: 68,
        appleWatchConnectedPercent: 42,
        spotifyConnectedPercent: 31,
        personalizedOfferConsentPercent: 37,
        goalBreakdown: [
            AdminMetricBreakdown(id: "muscle", title: "Build muscle", count: 298, percentage: 23.9),
            AdminMetricBreakdown(id: "weight", title: "Lose weight", count: 246, percentage: 19.7),
            AdminMetricBreakdown(id: "stronger", title: "Get stronger", count: 214, percentage: 17.1),
            AdminMetricBreakdown(id: "run", title: "Run faster or farther", count: 172, percentage: 13.8),
            AdminMetricBreakdown(id: "other", title: "Other goals", count: 318, percentage: 25.5)
        ],
        interestBreakdown: [
            AdminMetricBreakdown(id: "strength", title: "Strength", count: 693, percentage: 55.5),
            AdminMetricBreakdown(id: "plans", title: "Training plans", count: 612, percentage: 49.0),
            AdminMetricBreakdown(id: "running", title: "Running", count: 508, percentage: 40.7),
            AdminMetricBreakdown(id: "nutrition", title: "Nutrition", count: 431, percentage: 34.5),
            AdminMetricBreakdown(id: "recovery", title: "Recovery", count: 387, percentage: 31.0)
        ]
    )

    static let campaignDrafts: [OfferCampaignDraft] = [
        OfferCampaignDraft(
            title: "Goal support · Weight",
            productName: "12-week Training + Nutrition Plan",
            targetGoal: .loseWeight,
            requiredInterests: [.nutrition, .trainingPlans],
            minimumAccountAgeDays: 21
        ),
        OfferCampaignDraft(
            title: "Goal support · Muscle",
            productName: "8-week Hypertrophy Plan",
            targetGoal: .buildMuscle,
            requiredInterests: [.strength, .trainingPlans],
            minimumAccountAgeDays: 14
        ),
        OfferCampaignDraft(
            title: "Goal support · Event",
            productName: "Event Preparation Plan",
            targetGoal: .event,
            requiredInterests: [.trainingPlans],
            minimumAccountAgeDays: 14
        )
    ]

    static let campaignHistory: [CampaignHistoryRecord] = [
        CampaignHistoryRecord(
            id: UUID(uuidString: "A1111111-1111-1111-1111-111111111111")!,
            title: "Welcome to ATHLTH Plus",
            message: "A preview offer for upgraded training-plan features.",
            audience: .freeUsers,
            channels: [.inApp, .email],
            status: .sent,
            createdByUsername: "stian",
            createdAt: daysAgo(28),
            sentAt: daysAgo(27),
            audienceCount: 1_105,
            deliveredCount: 1_074,
            openedCount: 536,
            convertedCount: 42,
            recipients: [
                CampaignRecipientSnapshot(
                    id: UUID(),
                    userID: UUID(uuidString: "93333333-3333-3333-3333-333333333333")!,
                    username: "live_demo",
                    deliveredAt: daysAgo(27),
                    openedAt: daysAgo(26),
                    convertedAt: nil
                )
            ]
        ),
        CampaignHistoryRecord(
            id: UUID(uuidString: "A2222222-2222-2222-2222-222222222222")!,
            title: "Strength plan launch",
            message: "Early access to the 8-week hypertrophy plan.",
            audience: .personalizedSegment,
            channels: [.inApp],
            status: .sent,
            createdByUsername: "stian",
            createdAt: daysAgo(18),
            sentAt: daysAgo(17),
            audienceCount: 184,
            deliveredCount: 181,
            openedCount: 112,
            convertedCount: 19,
            recipients: [
                CampaignRecipientSnapshot(
                    id: UUID(),
                    userID: PreviewData.userID,
                    username: "stian",
                    deliveredAt: daysAgo(17),
                    openedAt: daysAgo(17),
                    convertedAt: daysAgo(15)
                )
            ]
        ),
        CampaignHistoryRecord(
            id: UUID(uuidString: "A3333333-3333-3333-3333-333333333333")!,
            title: "Nutrition launch draft",
            message: "Future nutrition-plan introduction.",
            audience: .freeUsers,
            channels: [.inApp, .push],
            status: .blocked,
            createdByUsername: "stian",
            createdAt: daysAgo(3),
            sentAt: nil,
            audienceCount: 1_173,
            deliveredCount: 0,
            openedCount: 0,
            convertedCount: 0,
            recipients: []
        )
    ]

    static let auditEvents: [AdminAuditEvent] = [
        AdminAuditEvent(
            id: UUID(),
            actor: "@stian",
            action: "Control Center initialized",
            target: "ATHLTH",
            createdAt: Date()
        ),
        AdminAuditEvent(
            id: UUID(),
            actor: "@stian",
            action: "Campaign delivery kept disabled",
            target: "Marketing",
            createdAt: daysAgo(1)
        )
    ]

    static let safetyCases: [AdminSafetyCase] = [
        AdminSafetyCase(
            id: UUID(),
            username: "demo_report_1",
            category: "Profile report",
            status: .open,
            createdAt: daysAgo(1)
        ),
        AdminSafetyCase(
            id: UUID(),
            username: "demo_report_2",
            category: "Harassment report",
            status: .reviewing,
            createdAt: daysAgo(2)
        )
    ]
}

struct AdminCenterView: View {
    @EnvironmentObject private var session: AppSessionStore
    @StateObject private var store = AdminControlCenterStore()

    var body: some View {
        Group {
            if session.currentRole.canAccessControlCenter {
                dashboard
            } else {
                ContentUnavailableView(
                    "Admin access required",
                    systemImage: "lock.shield.fill",
                    description: Text("This account does not have access to ATHLTH Control Center.")
                )
            }
        }
        .navigationTitle("Control Center")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                previewBanner

                summaryGrid

                AdminSectionCard(title: "Growth", icon: "chart.line.uptrend.xyaxis") {
                    NavigationLink {
                        AdminGrowthView(analytics: store.analytics)
                    } label: {
                        VStack(spacing: 12) {
                            adminMetricRow("New users · 7 days", value: "+\(store.analytics.newUsers7Days)")
                            adminMetricRow("New users · 30 days", value: "+\(store.analytics.newUsers30Days)")
                            adminMetricRow("Active users · 7 days", value: formatNumber(store.analytics.activeUsers7Days))
                            adminMetricRow("Active users · 30 days", value: formatNumber(store.analytics.activeUsers30Days))
                        }
                    }
                    .buttonStyle(.plain)
                }

                AdminSectionCard(title: "Users & access", icon: "person.3.fill") {
                    NavigationLink {
                        AdminUsersView(store: store)
                    } label: {
                        adminNavigationRow(
                            title: "Users",
                            subtitle: "Search, plan, status and account activity",
                            icon: "person.2"
                        )
                    }
                    .buttonStyle(.plain)

                    Divider()

                    NavigationLink {
                        AdminRolesView(store: store)
                    } label: {
                        adminNavigationRow(
                            title: "Admins & owner",
                            subtitle: "See privileged accounts and role history",
                            icon: "person.badge.key.fill"
                        )
                    }
                    .buttonStyle(.plain)
                }

                AdminSectionCard(title: "Audience", icon: "target") {
                    NavigationLink {
                        AdminAudienceView(analytics: store.analytics)
                    } label: {
                        adminNavigationRow(
                            title: "Goals & interests",
                            subtitle: "Aggregated self-declared preferences",
                            icon: "scope"
                        )
                    }
                    .buttonStyle(.plain)

                    Divider()

                    NavigationLink {
                        AdminIntegrationsView(analytics: store.analytics)
                    } label: {
                        adminNavigationRow(
                            title: "Integrations",
                            subtitle: "Aggregated connection adoption",
                            icon: "link"
                        )
                    }
                    .buttonStyle(.plain)
                }

                AdminSectionCard(title: "Campaigns & offers", icon: "megaphone.fill") {
                    NavigationLink {
                        AdminGeneralCampaignComposerView(store: store)
                    } label: {
                        adminNavigationRow(
                            title: "New Free-user campaign",
                            subtitle: "Compose a general campaign for eligible Free users",
                            icon: "paperplane.fill"
                        )
                    }
                    .buttonStyle(.plain)

                    Divider()

                    NavigationLink {
                        AdminCampaignHistoryView(store: store)
                    } label: {
                        adminNavigationRow(
                            title: "Campaign history",
                            subtitle: "Sent, blocked and draft campaign records",
                            icon: "clock.arrow.circlepath"
                        )
                    }
                    .buttonStyle(.plain)

                    Divider()

                    NavigationLink {
                        AdminOffersView(store: store)
                    } label: {
                        adminNavigationRow(
                            title: "Personalized offer readiness",
                            subtitle: "Consent, segments and personalized drafts",
                            icon: "slider.horizontal.3"
                        )
                    }
                    .buttonStyle(.plain)

                    Text("HealthKit measurements and individual health results are excluded from campaign and offer targeting.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                AdminSectionCard(title: "Marketplace", icon: "bag.fill") {
                    NavigationLink {
                        AdminMarketplaceView()
                    } label: {
                        adminNavigationRow(
                            title: "Products & payments",
                            subtitle: "Prepared for plans, purchases and subscriptions",
                            icon: "creditcard.fill"
                        )
                    }
                    .buttonStyle(.plain)
                }

                AdminSectionCard(title: "Safety & audit", icon: "shield.lefthalf.filled") {
                    NavigationLink {
                        AdminSafetyView(store: store)
                    } label: {
                        adminNavigationRow(
                            title: "Safety",
                            subtitle: "\(openSafetyCount) open or reviewing cases",
                            icon: "exclamationmark.shield.fill"
                        )
                    }
                    .buttonStyle(.plain)

                    Divider()

                    NavigationLink {
                        AdminAuditLogView(store: store)
                    } label: {
                        adminNavigationRow(
                            title: "Audit log",
                            subtitle: "Administrative actions and role changes",
                            icon: "clock.arrow.circlepath"
                        )
                    }
                    .buttonStyle(.plain)
                }

                AdminSectionCard(title: "System", icon: "gearshape.2.fill") {
                    adminMetricRow("Marketing delivery", value: "Disabled")
                    adminMetricRow("Signed-in role", value: session.currentRole.title)

                    Label(
                        "Individual Apple Health / HealthKit values are not shown in Control Center.",
                        systemImage: "lock.shield.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.green)
                }
            }
            .padding(16)
        }
    }

    private var previewBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Development preview")
                    .font(.subheadline.weight(.semibold))
                Text("Analytics and user directory are demo data until the ATHLTH backend is connected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
    }

    private var summaryGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ],
            spacing: 10
        ) {
            summaryCard(
                title: "Users",
                value: formatNumber(store.analytics.totalUsers),
                subtitle: "+\(store.analytics.newUsers30Days) this month",
                icon: "person.3.fill"
            )

            summaryCard(
                title: "Free",
                value: formatNumber(store.analytics.freeUsers),
                subtitle: percentage(store.analytics.freeUsers, of: store.analytics.totalUsers),
                icon: "person.fill"
            )

            summaryCard(
                title: "Paid",
                value: formatNumber(store.analytics.paidUsers),
                subtitle: percentage(store.analytics.paidUsers, of: store.analytics.totalUsers),
                icon: "creditcard.fill"
            )

            summaryCard(
                title: "Admins",
                value: "\(store.users.filter { $0.role.canAccessControlCenter }.count)",
                subtitle: "Owner + admins",
                icon: "person.badge.key.fill"
            )
        }
    }

    private func summaryCard(
        title: String,
        value: String,
        subtitle: String,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.green)
                Spacer()
            }

            Text(value)
                .font(.title.bold())

            Text(title)
                .font(.headline)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private func adminMetricRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    private func adminNavigationRow(
        title: String,
        subtitle: String,
        icon: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 28)
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
    }

    private var openSafetyCount: Int {
        store.safetyCases.filter { $0.status != .resolved }.count
    }

    private func formatNumber(_ value: Int) -> String {
        value.formatted(.number)
    }

    private func percentage(_ value: Int, of total: Int) -> String {
        guard total > 0 else { return "0%" }
        return String(format: "%.1f%%", Double(value) / Double(total) * 100)
    }
}

private struct AdminSectionCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    init(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(title, systemImage: icon)
                .font(.headline)

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct AdminUsersView: View {
    @EnvironmentObject private var session: AppSessionStore
    @ObservedObject var store: AdminControlCenterStore
    @State private var searchText = ""
    @State private var tier: SubscriptionTier?

    var body: some View {
        List {
            Section {
                Picker("Plan", selection: $tier) {
                    Text("All").tag(SubscriptionTier?.none)
                    Text("Free").tag(SubscriptionTier?.some(.free))
                    Text("Paid").tag(SubscriptionTier?.some(.paid))
                }
                .pickerStyle(.segmented)
            }

            Section("Directory preview") {
                ForEach(filteredUsers) { user in
                    NavigationLink {
                        AdminUserDetailView(userID: user.id, store: store)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("@\(user.username)")
                                    .font(.headline)
                                Spacer()
                                Text(user.subscription.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(user.subscription == .paid ? .green : .secondary)
                            }

                            HStack(spacing: 8) {
                                Text(user.role.title)
                                Text("·")
                                Text(user.status.title)
                                Text("·")
                                Text("Active \(user.lastActiveAt.formatted(.relative(presentation: .named)))")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                Text("Individual HealthKit values are never exposed in this user directory.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .searchable(text: $searchText, prompt: "Username or email")
        .navigationTitle("Users")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var filteredUsers: [AdminUserRecord] {
        store.users.filter { user in
            let matchesSearch =
                searchText.isEmpty ||
                user.username.localizedCaseInsensitiveContains(searchText) ||
                user.email.localizedCaseInsensitiveContains(searchText)

            let matchesTier = tier == nil || user.subscription == tier
            return matchesSearch && matchesTier
        }
    }
}

private struct AdminUserDetailView: View {
    @EnvironmentObject private var session: AppSessionStore
    @ObservedObject var store: AdminControlCenterStore
    let userID: UUID

    private var user: AdminUserRecord? {
        store.users.first(where: { $0.id == userID })
    }

    var body: some View {
        List {
            if let user {
                Section("Account") {
                    LabeledContent("Username", value: "@\(user.username)")
                    LabeledContent("Email", value: user.email)
                    LabeledContent("Role", value: user.role.title)
                    LabeledContent("Plan", value: user.subscription.title)
                    LabeledContent("Status", value: user.status.title)
                    LabeledContent(
                        "Joined",
                        value: user.createdAt.formatted(date: .abbreviated, time: .omitted)
                    )
                    LabeledContent(
                        "Last active",
                        value: user.lastActiveAt.formatted(.relative(presentation: .named))
                    )
                    LabeledContent(
                        "Onboarding",
                        value: user.onboardingCompleted ? "Completed" : "Incomplete"
                    )
                }

                Section("Self-declared personalization") {
                    LabeledContent("Goal", value: user.currentGoal?.title ?? "Not set")
                    LabeledContent(
                        "Interests",
                        value: user.interests.isEmpty
                            ? "None"
                            : user.interests.map(\.title).sorted().joined(separator: ", ")
                    )
                    LabeledContent("Offer consent", value: user.offerConsent.title)
                }

                Section("Campaign & offer history") {
                    let events = store.campaignEvents(for: user.id)

                    if events.isEmpty {
                        Text("No campaign or offer history for this user.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(events) { event in
                            NavigationLink {
                                AdminUserCampaignEventView(event: event)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(event.campaignTitle)
                                        .font(.subheadline.weight(.semibold))

                                    HStack(spacing: 6) {
                                        Text(event.status.title)
                                        if let sentAt = event.sentAt {
                                            Text("·")
                                            Text(sentAt.formatted(date: .abbreviated, time: .omitted))
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("Connections") {
                    connectionStatus("Apple Health", connected: user.connections.appleHealth)
                    connectionStatus("Apple Watch", connected: user.connections.appleWatch)
                    connectionStatus("Spotify", connected: user.connections.spotify)

                    Text("Only connection status is shown. Health measurements are not available to administrators here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if user.role != .owner {
                    Section("Safety") {
                        Button(user.status == .suspended ? "Reactivate account" : "Suspend account") {
                            store.setAccountStatus(
                                userID: user.id,
                                status: user.status == .suspended ? .active : .suspended,
                                actingRole: session.currentRole,
                                actorUsername: session.profile.username
                            )
                        }
                        .foregroundStyle(user.status == .suspended ? .green : .red)
                    }
                }
            }
        }
        .navigationTitle(user.map { "@\($0.username)" } ?? "User")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func connectionStatus(_ title: String, connected: Bool) -> some View {
        LabeledContent(title) {
            Label(
                connected ? "Connected" : "Not connected",
                systemImage: connected ? "checkmark.circle.fill" : "circle"
            )
            .foregroundStyle(connected ? .green : .secondary)
        }
    }
}

private struct AdminRolesView: View {
    @EnvironmentObject private var session: AppSessionStore
    @ObservedObject var store: AdminControlCenterStore

    var body: some View {
        List {
            Section {
                ForEach(privilegedUsers) { user in
                    HStack(spacing: 12) {
                        Image(systemName: user.role == .owner ? "crown.fill" : "person.badge.key.fill")
                            .foregroundStyle(user.role == .owner ? .orange : .green)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("@\(user.username)")
                                .font(.headline)
                            Text(user.role.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if user.role == .admin && session.currentRole.canManageAdmins {
                            Menu {
                                Button("Remove admin access", role: .destructive) {
                                    store.setRole(
                                        userID: user.id,
                                        role: .user,
                                        actingRole: session.currentRole,
                                        actorUsername: session.profile.username
                                    )
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                    }
                }
            } header: {
                Text("Privileged accounts")
            } footer: {
                Text("Only Owner can add or remove admins. Owner access cannot be changed from this screen.")
            }

            if session.currentRole.canManageAdmins {
                Section("Owner controls") {
                    NavigationLink {
                        AdminAddAdminView(store: store)
                    } label: {
                        Label("Add admin", systemImage: "person.badge.plus")
                    }
                }
            }
        }
        .navigationTitle("Admins & Owner")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var privilegedUsers: [AdminUserRecord] {
        store.users
            .filter { $0.role.canAccessControlCenter }
            .sorted { lhs, rhs in
                if lhs.role == rhs.role { return lhs.username < rhs.username }
                return lhs.role == .owner
            }
    }
}

private struct AdminAddAdminView: View {
    @EnvironmentObject private var session: AppSessionStore
    @ObservedObject var store: AdminControlCenterStore
    @State private var searchText = ""

    var body: some View {
        List {
            Section {
                Text("Select a user to grant Admin access. Owner remains the only role that can manage admins.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Eligible users") {
                ForEach(filteredUsers) { user in
                    Button {
                        store.setRole(
                            userID: user.id,
                            role: .admin,
                            actingRole: session.currentRole,
                            actorUsername: session.profile.username
                        )
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("@\(user.username)")
                                Text(user.email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "plus.circle")
                                .foregroundStyle(.green)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search users")
        .navigationTitle("Add Admin")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var filteredUsers: [AdminUserRecord] {
        store.users.filter { user in
            user.role == .user &&
            (
                searchText.isEmpty ||
                user.username.localizedCaseInsensitiveContains(searchText) ||
                user.email.localizedCaseInsensitiveContains(searchText)
            )
        }
    }
}

private struct AdminGrowthView: View {
    let analytics: AdminAnalyticsSnapshot

    var body: some View {
        List {
            Section("Acquisition") {
                metric("New users · 7 days", value: analytics.newUsers7Days)
                metric("New users · 30 days", value: analytics.newUsers30Days)
            }

            Section("Activity") {
                metric("Active users · 7 days", value: analytics.activeUsers7Days)
                metric("Active users · 30 days", value: analytics.activeUsers30Days)
            }

            Section("Onboarding") {
                percentageRow("Completed onboarding", value: analytics.onboardingCompletionPercent)
            }

            Section {
                Text("Growth metrics are demo values until analytics events and the backend are connected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Growth")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func metric(_ title: String, value: Int) -> some View {
        LabeledContent(title, value: value.formatted(.number))
    }

    @ViewBuilder
    private func percentageRow(_ title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.0f%%", value))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: value, total: 100)
                .tint(.green)
        }
    }
}

private struct AdminAudienceView: View {
    let analytics: AdminAnalyticsSnapshot

    var body: some View {
        List {
            Section("Current goals") {
                ForEach(analytics.goalBreakdown) { item in
                    breakdownRow(item)
                }
            }

            Section("Interests") {
                ForEach(analytics.interestBreakdown) { item in
                    breakdownRow(item)
                }
            }

            Section {
                Text("These are aggregated self-declared goals and interests. This view intentionally does not expose individual HealthKit measurements.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Goals & Interests")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func breakdownRow(_ item: AdminMetricBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(item.title)
                Spacer()
                Text("\(item.count.formatted(.number)) · \(String(format: "%.1f%%", item.percentage))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: item.percentage, total: 100)
                .tint(.green)
        }
    }
}

private struct AdminIntegrationsView: View {
    let analytics: AdminAnalyticsSnapshot

    var body: some View {
        List {
            Section("Adoption") {
                percentageRow("Apple Health", value: analytics.appleHealthConnectedPercent)
                percentageRow("Apple Watch", value: analytics.appleWatchConnectedPercent)
                percentageRow("Spotify", value: analytics.spotifyConnectedPercent)
            }

            Section {
                Text("Only aggregate connection rates belong here. Individual health measurements remain outside Control Center.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Integrations")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func percentageRow(_ title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.0f%%", value))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: value, total: 100)
                .tint(.green)
        }
    }
}

private struct AdminOffersView: View {
    @EnvironmentObject private var session: AppSessionStore
    @ObservedObject var store: AdminControlCenterStore

    var body: some View {
        List {
            Section("System status") {
                LabeledContent("Marketing delivery", value: "Disabled")
                LabeledContent(
                    "Current-user consent",
                    value: session.onboardingProfile?.personalizedOfferConsent.title ?? "Not requested"
                )
                LabeledContent(
                    "Consent rate · demo",
                    value: String(format: "%.0f%%", store.analytics.personalizedOfferConsentPercent)
                )

                Label("No campaign can be sent from V0.1.", systemImage: "lock.shield.fill")
                    .foregroundStyle(.green)
            }

            Section("Campaign drafts") {
                ForEach(store.campaignDrafts) { draft in
                    NavigationLink {
                        AdminCampaignDetailView(draft: draft)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(draft.title)
                                .font(.headline)
                            Text(draft.productName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Delivery: \(draft.deliveryState.title)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            Section {
                Text("Segmentation may use self-declared ATHLTH goals, interests, consent and product timing. HealthKit measurements, workout results, weight changes, HRV, sleep and similar Apple Health data are excluded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Offer Readiness")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AdminCampaignDetailView: View {
    @EnvironmentObject private var session: AppSessionStore
    let draft: OfferCampaignDraft

    private var result: MarketingEligibilityResult {
        MarketingEligibilityEngine.evaluate(
            profile: session.onboardingProfile,
            accountCreatedAt: session.accountCreatedAt,
            draft: draft
        )
    }

    var body: some View {
        List {
            Section("Draft") {
                LabeledContent("Offer", value: draft.productName)
                LabeledContent("Delivery", value: draft.deliveryState.title)
                LabeledContent("Target goal", value: draft.targetGoal?.title ?? "Any")
                LabeledContent("Minimum account age", value: "\(draft.minimumAccountAgeDays) days")
                LabeledContent(
                    "Required interests",
                    value: draft.requiredInterests.isEmpty
                        ? "None"
                        : draft.requiredInterests.map(\.title).sorted().joined(separator: ", ")
                )
            }

            Section("Current-user preview") {
                LabeledContent(
                    "Segment preview",
                    value: result.segmentMatches ? "Match" : "No match"
                )

                Label(
                    result.sendEligible ? "Send eligible" : "Sending blocked",
                    systemImage: result.sendEligible ? "checkmark.circle.fill" : "lock.circle.fill"
                )
                .foregroundStyle(result.sendEligible ? .green : .secondary)

                ForEach(result.reasons, id: \.self) { reason in
                    Text(reason)
                        .font(.subheadline)
                }
            }

            Section {
                Button("Send campaign") {}
                    .disabled(true)

                Text("Sending is intentionally unavailable in V0.1.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(draft.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AdminMarketplaceView: View {
    var body: some View {
        List {
            Section("Marketplace readiness") {
                LabeledContent("Products", value: "0")
                LabeledContent("Paid users", value: "Tracked")
                LabeledContent("Revenue", value: "Not connected")
                LabeledContent("Subscriptions", value: "Not connected")
                LabeledContent("Refunds", value: "Not connected")
            }

            Section("Prepared product types") {
                Label("Training plans", systemImage: "figure.strengthtraining.traditional")
                Label("Nutrition plans", systemImage: "fork.knife")
                Label("Combined programs", systemImage: "square.grid.2x2.fill")
            }

            Section {
                Text("Payment-provider and App Store purchase logic will be connected later. Subscription tier is intentionally separate from account role.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Marketplace")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AdminSafetyView: View {
    @ObservedObject var store: AdminControlCenterStore

    var body: some View {
        List {
            Section("Cases") {
                ForEach(store.safetyCases) { safetyCase in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("@\(safetyCase.username)")
                                .font(.headline)
                            Spacer()
                            Text(safetyCase.status.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(
                                    safetyCase.status == .resolved ? .green : .orange
                                )
                        }

                        Text(safetyCase.category)
                            .font(.subheadline)

                        Text(safetyCase.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Text("Account suspension is available from the user detail screen. Production safety tooling will require backend enforcement and audit logging.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Safety")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AdminAuditLogView: View {
    @ObservedObject var store: AdminControlCenterStore

    var body: some View {
        List {
            ForEach(store.auditEvents) { event in
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.action)
                        .font(.headline)

                    Text("\(event.actor) → \(event.target)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(event.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .navigationTitle("Audit Log")
        .navigationBarTitleDisplayMode(.inline)
    }
}

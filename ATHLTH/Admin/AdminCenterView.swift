import SwiftUI

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

struct AdminCenterView: View {
    @EnvironmentObject private var session: AppSessionStore

    private let drafts: [OfferCampaignDraft] = [
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

    var body: some View {
        Group {
            if session.currentRole == .admin {
                adminContent
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

    private var adminContent: some View {
        List {
            Section("System status") {
                LabeledContent("Marketing delivery", value: "Disabled")
                LabeledContent(
                    "Personalized offers",
                    value: session.onboardingProfile?.personalizedOfferConsent.title ?? "Not requested"
                )

                Label(
                    "No campaign can be sent from V0.1.",
                    systemImage: "lock.shield.fill"
                )
                .foregroundStyle(.green)
            }

            Section("Allowed segmentation foundation") {
                Label("Self-declared current goal", systemImage: "target")
                Label("Self-declared interests", systemImage: "checklist")
                Label("Account age / product timing", systemImage: "calendar")

                Text("HealthKit measurements, workout results, weight changes, HRV, sleep and other Apple Health data are intentionally not inputs to this marketing engine.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Current local user") {
                if let profile = session.onboardingProfile {
                    LabeledContent(
                        "Goal",
                        value: profile.currentGoal?.type.title ?? "Not set"
                    )

                    LabeledContent(
                        "Interests",
                        value: profile.interests.isEmpty
                            ? "None"
                            : profile.interests.map(\.title).sorted().joined(separator: ", ")
                    )

                    LabeledContent(
                        "Offer consent",
                        value: profile.personalizedOfferConsent.title
                    )
                } else {
                    Text("No onboarding profile is stored for this local user.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Campaign drafts") {
                ForEach(drafts) { draft in
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

            Section("Production architecture") {
                Text("This in-app Admin Center is a development tool. A real administrator should use a separately authenticated backend/web dashboard with role-based access, audit logs and server-side consent checks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
                LabeledContent(
                    "Target goal",
                    value: draft.targetGoal?.title ?? "Any"
                )
                LabeledContent(
                    "Minimum account age",
                    value: "\(draft.minimumAccountAgeDays) days"
                )
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

                Text("Sending is intentionally unavailable. This screen only validates future segmentation logic.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(draft.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

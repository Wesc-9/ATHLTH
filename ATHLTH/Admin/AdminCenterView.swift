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
    var eligible: Bool
    var reasons: [String]
}

enum MarketingEligibilityEngine {
    static func evaluate(
        profile: OnboardingProfileData?,
        accountCreatedAt: Date,
        draft: OfferCampaignDraft
    ) -> MarketingEligibilityResult {
        var reasons: [String] = []

        guard draft.deliveryState != .enabled else {
            reasons.append("Campaign sending is not enabled in V0.1.")
            return MarketingEligibilityResult(eligible: false, reasons: reasons)
        }

        guard let profile else {
            reasons.append("No onboarding personalization data is available.")
            return MarketingEligibilityResult(eligible: false, reasons: reasons)
        }

        guard profile.personalizedOfferConsent == .granted else {
            reasons.append("Personalized-offer consent has not been granted.")
            return MarketingEligibilityResult(eligible: false, reasons: reasons)
        }

        if let targetGoal = draft.targetGoal,
           profile.currentGoal?.type != targetGoal {
            reasons.append("Current self-declared goal does not match this draft.")
        }

        if !draft.requiredInterests.isSubset(of: profile.interests) {
            reasons.append("Required self-declared interests are missing.")
        }

        let accountAgeDays = Calendar.current.dateComponents(
            [.day],
            from: accountCreatedAt,
            to: Date()
        ).day ?? 0

        if accountAgeDays < draft.minimumAccountAgeDays {
            reasons.append("Account is younger than the draft's waiting period.")
        }

        return MarketingEligibilityResult(
            eligible: reasons.isEmpty,
            reasons: reasons.isEmpty ? ["Eligible under preview rules."] : reasons
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
        .navigationTitle("Admin Center")
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
                Label(
                    result.eligible ? "Eligible" : "Not eligible",
                    systemImage: result.eligible ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .foregroundStyle(result.eligible ? .green : .secondary)

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

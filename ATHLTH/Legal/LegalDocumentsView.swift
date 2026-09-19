import SwiftUI

enum LegalDocumentKind: String, Identifiable {
    case terms
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terms: return "Terms of Service"
        case .privacy: return "Privacy Policy"
        }
    }
}

private struct LegalSectionData: Identifiable {
    let id = UUID()
    let title: String
    let body: String
}

struct LegalDocumentView: View {
    let kind: LegalDocumentKind

    private let effectiveDate = "20 September 2026"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(kind.title)
                    .font(.largeTitle.weight(.bold))

                Text("Effective: \(effectiveDate)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                #if DEBUG
                Label(
                    "V0.1 legal draft — controller/contact details and final legal review are required before public release.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(12)
                .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                #endif

                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(section.title)
                            .font(.headline)

                        Text(section.body)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sections: [LegalSectionData] {
        switch kind {
        case .terms:
            return termsSections
        case .privacy:
            return privacySections
        }
    }

    private var termsSections: [LegalSectionData] {
        [
            LegalSectionData(
                title: "1. About ATHLTH",
                body: "ATHLTH is a fitness and wellness service for planning workouts, recording training, reviewing health and activity information, managing routes, and optionally interacting with other users. Features may include Apple Health, Apple Watch, Spotify, Home Assistant, routes, challenges, training plans and social functionality."
            ),
            LegalSectionData(
                title: "2. Your account",
                body: "You are responsible for the information submitted through your account and for keeping your login credentials secure. Usernames must not impersonate another person, violate rights, or be used for abuse, fraud or unlawful activity. You must meet the minimum age and other eligibility requirements that apply where you live."
            ),
            LegalSectionData(
                title: "3. Fitness information — not medical advice",
                body: "ATHLTH provides fitness, training and wellness information. It is not a medical service, medical device, emergency service or substitute for professional medical advice, diagnosis or treatment. Training recommendations, recovery indicators and similar features are informational and may be incomplete or inaccurate. Stop exercising and seek appropriate professional help if you have health concerns or symptoms."
            ),
            LegalSectionData(
                title: "4. Apple Health and Apple Watch",
                body: "Apple Health and Apple Watch are optional. If you connect Apple Health, you choose which data categories ATHLTH may access. You can change those permissions through Apple at any time. ATHLTH is designed to keep HealthKit-derived data private unless you explicitly choose an allowed sharing action. HealthKit data is not used for advertising and is not sold to advertising platforms, data brokers or information resellers."
            ),
            LegalSectionData(
                title: "5. Workouts and training plans",
                body: "You may create, copy, follow and use training plans and workouts. Plans may contain estimates, targets or content provided by users or third-party exercise sources. You remain responsible for deciding whether a workout is appropriate for you. A plan shared by another user is not professional coaching unless that provider separately represents it as such."
            ),
            LegalSectionData(
                title: "6. Routes and location",
                body: "Route features may use or display location data. Sharing routes can reveal sensitive locations such as your home or workplace. ATHLTH may provide privacy controls such as hiding route start and end areas, but you are responsible for reviewing a route before sharing it."
            ),
            LegalSectionData(
                title: "7. Social features and user content",
                body: "If you post plans, activities, routes, comments, messages or other content, you remain responsible for that content. Do not post unlawful, threatening, abusive, deceptive, infringing or privacy-invasive material. ATHLTH may provide reporting, blocking and moderation tools and may restrict content or accounts when reasonably necessary to operate or protect the service."
            ),
            LegalSectionData(
                title: "8. Spotify and other integrations",
                body: "Third-party integrations are optional and subject to the third party's own terms and privacy practices. A linked Spotify playlist may start when a workout from a linked training plan begins if you enable that behavior. Home Assistant and other integrations are configured separately and are not required to use ATHLTH."
            ),
            LegalSectionData(
                title: "9. Availability and changes",
                body: "ATHLTH may change, add, remove or discontinue features as the product develops. Health, watch, location, Spotify and third-party functionality may depend on hardware, operating-system permissions, network access or third-party services outside ATHLTH's control."
            ),
            LegalSectionData(
                title: "10. Intellectual property",
                body: "ATHLTH's software, branding, original design and service content are protected by applicable intellectual-property laws. Your own user content remains yours. By making content visible to other users, you grant ATHLTH the limited rights necessary to host, display and deliver that content according to your selected privacy settings."
            ),
            LegalSectionData(
                title: "11. Suspension and deletion",
                body: "You may request account deletion through the service when that functionality is available. ATHLTH may suspend or restrict accounts for serious or repeated violations of these Terms, security threats, unlawful use or abuse of other users."
            ),
            LegalSectionData(
                title: "12. Disclaimers and liability",
                body: "ATHLTH is provided on an as-available basis to the extent permitted by applicable law. Nothing in these Terms excludes rights or remedies that cannot legally be excluded. You are responsible for exercising safely and for verifying information before relying on it."
            ),
            LegalSectionData(
                title: "13. Changes to these Terms",
                body: "These Terms may be updated as ATHLTH changes or legal requirements develop. Material changes should be communicated through the app or another appropriate channel before they take effect where required."
            ),
            LegalSectionData(
                title: "14. Contact",
                body: "The legal operator identity and formal contact details for ATHLTH must be published in the App Store listing and this document before public release."
            )
        ]
    }

    private var privacySections: [LegalSectionData] {
        [
            LegalSectionData(
                title: "1. What this policy covers",
                body: "This Privacy Policy explains how ATHLTH handles information when you use the app, including account information, training data, optional Apple Health data, routes, social features and optional integrations."
            ),
            LegalSectionData(
                title: "2. Account and profile information",
                body: "ATHLTH may process your email address or Sign in with Apple identifier, unique username, display name, profile image, biography, privacy settings, selected goals and account preferences. Optional profile information can include date of birth, sex used for health calculations, height and weight."
            ),
            LegalSectionData(
                title: "3. Apple Health data",
                body: "If you choose to connect Apple Health, ATHLTH may request access to health and fitness categories needed for features you use, such as workouts, workout routes, heart rate, resting heart rate, heart-rate variability, sleep, active energy, walking/running distance, height and body mass. Apple controls the permission sheet, and you can change permissions at any time. ATHLTH may receive less data than requested if you deny or limit access."
            ),
            LegalSectionData(
                title: "4. How HealthKit data is used",
                body: "HealthKit-derived data is used to provide health and fitness functionality to you, such as workout history, recovery context, activity summaries and linked workout metrics. ATHLTH does not use HealthKit data for advertising, marketing profiles or unrelated data mining, and does not sell HealthKit data to advertising platforms, data brokers or information resellers."
            ),
            LegalSectionData(
                title: "5. Workout, plan and exercise data",
                body: "ATHLTH may store workouts, planned sessions, exercises, sets, repetitions, weights, RPE, rest periods, training notes, progress records, achievements and related training data that you create in the app. Some of this data may be linked to a HealthKit workout when you choose to use Apple Health or Apple Watch."
            ),
            LegalSectionData(
                title: "6. Routes and location information",
                body: "If you import, create or record a route, ATHLTH may process route coordinates, distance, elevation and related workout information. Route sharing is controlled separately from HealthKit permissions. Location-related information can be sensitive, so route privacy settings should be reviewed before sharing."
            ),
            LegalSectionData(
                title: "7. Social information",
                body: "If social features are used, ATHLTH may process friendship relationships, followers/following, public or friends-only profiles, shared plans, shared routes, challenges, comments, messages and activity visibility. Content you choose to make public can be visible to other users."
            ),
            LegalSectionData(
                title: "8. Spotify, Apple Watch and Home Assistant",
                body: "Optional integrations may require identifiers, authorization tokens or connection state needed to provide the integration. Spotify is intended only to link playlists to training plans and optionally start the linked playlist with a workout. Home Assistant is optional and configured through Settings. Third-party services process data under their own privacy policies."
            ),
            LegalSectionData(
                title: "9. Why information is processed",
                body: "Information is processed to create and secure accounts, provide requested fitness and health features, save plans and settings, synchronize optional integrations, support social features, prevent abuse, troubleshoot the service and comply with applicable legal obligations. Where law requires consent — particularly for sensitive health data or optional permissions — ATHLTH will rely on the appropriate user choice or consent."
            ),
            LegalSectionData(
                title: "10. Sharing and disclosure",
                body: "ATHLTH does not make private HealthKit data public automatically. Information may be shared when you explicitly use a sharing feature, with processors needed to operate the service, with an integration you choose to connect, or when legally required. HealthKit-derived data must not be disclosed to third parties for advertising or unrelated purposes."
            ),
            LegalSectionData(
                title: "11. Data retention and deletion",
                body: "ATHLTH-owned account, workout, plan, route and social data may be retained while your account is active and for as long as reasonably necessary to provide the service, maintain security or meet legal obligations. Account-deletion functionality is intended to remove ATHLTH cloud account data subject to legitimate legal or technical backup-retention requirements. Data stored by Apple Health is controlled separately through Apple."
            ),
            LegalSectionData(
                title: "12. Your choices and rights",
                body: "Depending on where you live, you may have rights to access, correct, export, restrict or delete personal data and to withdraw consent. You can also manage HealthKit permissions through Apple, change ATHLTH privacy settings, disable integrations, block users and request account deletion when those features are available."
            ),
            LegalSectionData(
                title: "13. Security",
                body: "ATHLTH is designed to use appropriate technical and organizational safeguards for account and health-related information. No service can guarantee absolute security. Do not share credentials, and keep your devices and operating systems appropriately secured."
            ),
            LegalSectionData(
                title: "14. Children",
                body: "ATHLTH is not intended for people who do not meet the minimum age required to consent to the service and its data processing under applicable law. Age-related requirements will be finalized before public release."
            ),
            LegalSectionData(
                title: "15. Changes to this policy",
                body: "This policy may be updated as ATHLTH develops or legal requirements change. Material changes should be presented through the app or another appropriate notice where required."
            ),
            LegalSectionData(
                title: "16. Privacy contact",
                body: "The legal data-controller identity and privacy contact details must be inserted here and in the App Store listing before public release."
            )
        ]
    }
}

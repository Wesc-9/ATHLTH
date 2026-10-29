import Foundation
import SwiftUI
import UIKit
import UserNotifications


private enum ATHLTHSettingsCategory: String, CaseIterable, Identifiable {
    case health
    case training
    case account
    case app
    case membership
    case privacy
    case developer

    var id: Self { self }

    var title: String {
        switch self {
        case .health: return ATHLTHLocalization.choose(english: "Health & connections", norwegian: "Helse og tilkoblinger")
        case .training: return ATHLTHLocalization.choose(english: "Training & alerts", norwegian: "Trening og varsler")
        case .account: return ATHLTHLocalization.choose(english: "Profile & account", norwegian: "Profil og konto")
        case .app: return ATHLTHLocalization.choose(english: "App & language", norwegian: "App og språk")
        case .membership: return ATHLTHLocalization.choose(english: "Membership", norwegian: "Medlemskap")
        case .privacy: return ATHLTHLocalization.choose(english: "Privacy", norwegian: "Personvern")
        case .developer: return ATHLTHLocalization.choose(english: "Developer tools", norwegian: "Utviklerverktøy")
        }
    }

    var detail: String {
        switch self {
        case .health: return ATHLTHLocalization.choose(english: "Apple Health, Watch and services", norwegian: "Apple Health, Watch og tjenester")
        case .training: return ATHLTHLocalization.choose(english: "Workouts, guidance and notifications", norwegian: "Økter, veiledning og varslinger")
        case .account: return ATHLTHLocalization.choose(english: "Health profile, sign-in and security", norwegian: "Helseprofil, innlogging og sikkerhet")
        case .app: return ATHLTHLocalization.choose(english: "Language, units, time and widgets", norwegian: "Språk, enheter, tid og widgeter")
        case .membership: return ATHLTHLocalization.choose(english: "ATHLTH+, purchases and billing", norwegian: "ATHLTH+, kjøp og betaling")
        case .privacy: return ATHLTHLocalization.choose(english: "Privacy policy and terms", norwegian: "Personvernerklæring og vilkår")
        case .developer: return ATHLTHLocalization.choose(english: "Diagnostics, AI usage and testing", norwegian: "Diagnostikk, AI-bruk og testing")
        }
    }

    var icon: String {
        switch self {
        case .health: return "heart.text.square"
        case .training: return "figure.run"
        case .account: return "person.crop.circle"
        case .app: return "slider.horizontal.3"
        case .membership: return "crown"
        case .privacy: return "lock.shield"
        case .developer: return "wrench.and.screwdriver"
        }
    }

    var terms: String {
        switch self {
        case .health: return "health helse apple health watch klokke sync synkronisering import calendar kalender spotify garmin home assistant tilkobling connections"
        case .training: return "training trening workout styrke løping løp guidance veiledning audio coach ghost notifications varsler alarm achievements trophies medalje exercise data repdb øvelsesdatabase"
        case .account: return "profile profil account konto health helseprofil sign-in login innlogging password passord security sikkerhet data privacy"
        case .app: return "app språk language engelsk norsk måleenheter measurements units tid time format widget widgets lock screen siri"
        case .membership: return "medlemskap premium athlth plus abonnement billing betal kjøp purchase restore subscription trial"
        case .privacy: return "privacy personvern rettigheter vilkår terms policy legal"
        case .developer: return "utvikler developer support diagnostics diagnostikk debug usage ai lab control center"
        }
    }
}

struct ATHLTHSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var notifications: ATHLTHNotificationStore
    @EnvironmentObject private var calendarSync: AppleCalendarSyncStore
    @EnvironmentObject private var spotify: SpotifyPlaybackStore
    @EnvironmentObject private var homeAssistant: HomeAssistantConnectionStore

    @State private var showingMembership = false
    @State private var membershipRestoreMessage: String?
    @State private var healthRequestInProgress = false
    @State private var showingAppleHealthPauseConfirmation = false
    @State private var settingsSearchText = ""

    var body: some View {
        ZStack {
            settingsBackground

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    settingsSearchField

                    if settingsSearchText.isEmpty {
                        quickAccessSection
                    }

                    if filteredSettingsCategories.isEmpty &&
                        !matchesContactSearch &&
                        !matchesWebsiteSearch {
                        ContentUnavailableView.search(text: settingsSearchText)
                            .frame(maxWidth: .infinity)
                    } else {
                        VStack(alignment: .leading, spacing: 18) {
                            settingsCategoryGroup(
                                ATHLTHLocalization.choose(
                                    english: "YOUR TRAINING",
                                    norwegian: "DIN TRENING"
                                ),
                                categories: [.health, .training]
                            )

                            settingsCategoryGroup(
                                ATHLTHLocalization.choose(
                                    english: "PERSONAL",
                                    norwegian: "PERSONLIG"
                                ),
                                categories: [.account, .app]
                            )

                            settingsCategoryGroup(
                                "ATHLTH",
                                categories: [.membership, .privacy]
                            )

                            if canShowDeveloperSettings {
                                settingsCategoryGroup(
                                    ATHLTHLocalization.choose(
                                        english: "DEVELOPER",
                                        norwegian: "UTVIKLER"
                                    ),
                                    categories: [.developer]
                                )
                            }
                        }
                    }

                    if settingsSearchText.isEmpty || matchesContactSearch {
                        supportContactCard
                    }

                    HStack(spacing: 8) {
                        Link(destination: ATHLTHLegalIdentity.websiteURL) {
                            Text("ATHLTH.com")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(ATHLTHLocalization.choose(
                            english: "Open ATHLTH website",
                            norwegian: "Åpne ATHLTH-nettsiden"
                        ))

                        Text("·")

                        Text("ATHLTH \(appVersion)")
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.72))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                    .padding(.bottom, 22)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingMembership) {
            SubscriptionOfferView {
                showingMembership = false
            }
        }
        .task {
            await notifications.refreshAuthorizationStatus()
            _ = await health.restoreAuthorizationStateFromSystem()

            if settings.appleHealthIntegrationEnabled,
               health.hasRequestedAuthorization,
               health.lastSuccessfulRefreshAt == nil,
               !health.isRefreshing {
                health.resumeUserInitiatedHealthSync()
                await health.configureBackgroundSync(
                    allowed: settings.backgroundHealthSyncEnabled
                )
                await health.refreshAll()
            }
        }
    }

    private var matchesContactSearch: Bool {
        let query = settingsSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return "contact@athlth.com kontakt contact oss hjelp support epost email"
            .localizedStandardContains(query)
    }

    private var matchesWebsiteSearch: Bool {
        let query = settingsSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return "ATHLTH.com nettside website hjemmeside official offisiell web"
            .localizedStandardContains(query)
    }

    private var supportContactCard: some View {
        NavigationLink {
            ATHLTHContactSupportView()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "envelope.badge")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .frame(width: 52, height: 52)
                    .background(
                        ATHLTHTheme.premiumGoldSoft,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 5) {
                    Text(ATHLTHLocalization.choose(
                        english: "Contact us",
                        norwegian: "Kontakt oss"
                    ))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(ATHLTHTheme.primaryText)

                    Text(ATHLTHLegalIdentity.supportContactEmail)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text(ATHLTHLocalization.choose(
                        english: "Report an issue or share an idea without opening email.",
                        norwegian: "Meld inn feil eller forslag direkte i appen."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 2)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
            }
            .padding(16)
            .background(
                LinearGradient(
                    colors: [
                        Color.white,
                        ATHLTHTheme.champagneSoft.opacity(0.72)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 23, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 23, style: .continuous)
                    .stroke(ATHLTHTheme.premiumGold.opacity(0.23), lineWidth: 0.9)
            }
            .shadow(
                color: ATHLTHTheme.accentDeep.opacity(0.05),
                radius: 16, y: 6
            )
            .contentShape(RoundedRectangle(cornerRadius: 23))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                UIPasteboard.general.string = ATHLTHLegalIdentity.supportContactEmail
            } label: {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Copy email address",
                        norwegian: "Kopier e-postadresse"
                    ),
                    systemImage: "doc.on.doc"
                )
            }
        }
        .accessibilityLabel(ATHLTHLocalization.choose(
            english: "Open ATHLTH support form",
            norwegian: "Åpne kontaktskjema til ATHLTH"
        ))
    }

    @ViewBuilder
    private func settingsCategoryGroup(
        _ title: String,
        categories: [ATHLTHSettingsCategory]
    ) -> some View {
        let matches = filteredSettingsCategories.filter { categories.contains($0) }

        if !matches.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(2.1)
                    .foregroundStyle(ATHLTHTheme.accentDeep.opacity(0.80))
                    .padding(.leading, 5)

                PremiumSettingsCard {
                    ForEach(matches) { category in
                        NavigationLink {
                            settingsDetailPage(for: category)
                        } label: {
                            settingsCategoryRow(category)
                        }
                        .buttonStyle(.plain)

                        if category != matches.last {
                            SettingsDivider()
                        }
                    }
                }
            }
        }
    }

    private var filteredSettingsCategories: [ATHLTHSettingsCategory] {
        let query = settingsSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return ATHLTHSettingsCategory.allCases.filter { category in
            guard category != .developer || canShowDeveloperSettings else { return false }
            return query.isEmpty
                || category.title.localizedStandardContains(query)
                || category.detail.localizedStandardContains(query)
                || category.terms.localizedStandardContains(query)
        }
    }

    private var canShowDeveloperSettings: Bool {
        #if DEBUG
        return session.currentRole.canAccessControlCenter || session.previewModeEnabled
        #else
        return session.currentRole.canAccessControlCenter
        #endif
    }

    private var settingsSearchField: some View {
        HStack(spacing: 11) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(ATHLTHTheme.mutedText)
            TextField(
                ATHLTHLocalization.choose(
                    english: "Search settings, devices, notifications…",
                    norwegian: "Søk etter innstillinger, enheter, varsler…"
                ),
                text: $settingsSearchText
            )
            .font(.subheadline)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            if !settingsSearchText.isEmpty {
                Button {
                    settingsSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    ATHLTHLocalization.choose(english: "Clear search", norwegian: "Tøm søk")
                )
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 51)
        .background(
            LinearGradient(
                colors: [.white, ATHLTHTheme.cardWarm.opacity(0.30)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(ATHLTHTheme.border.opacity(0.80), lineWidth: 0.8)
        }
    }

    private var quickAccessSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(
                ATHLTHLocalization.choose(
                    english: "QUICK ACCESS",
                    norwegian: "HURTIGVALG"
                )
            )
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .tracking(1.5)
            .foregroundStyle(ATHLTHTheme.mutedText)
            .padding(.leading, 5)

            HStack(spacing: 10) {
                NavigationLink {
                    ATHLTHNotificationSettingsView()
                } label: {
                    quickAccessItem(
                        icon: "bell.badge",
                        title: ATHLTHLocalization.choose(english: "Alerts", norwegian: "Varsler")
                    )
                }

                NavigationLink {
                    PersonalHealthProfileView()
                } label: {
                    quickAccessItem(
                        icon: "heart.text.square",
                        title: ATHLTHLocalization.choose(english: "Health profile", norwegian: "Helseprofil")
                    )
                }

                NavigationLink {
                    ATHLTHAccountSecurityView()
                } label: {
                    quickAccessItem(
                        icon: "person.crop.circle",
                        title: ATHLTHLocalization.choose(english: "Account", norwegian: "Konto")
                    )
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func quickAccessItem(icon: String, title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(width: 38, height: 38)
                .background(
                    ATHLTHTheme.accentSoft,
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 92)
        .background(
            LinearGradient(
                colors: [.white, ATHLTHTheme.cardWarm.opacity(0.25)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(ATHLTHTheme.border.opacity(0.80), lineWidth: 0.8)
        }
        .shadow(color: ATHLTHTheme.accentDeep.opacity(0.035), radius: 10, y: 4)
    }

    private func settingsCategoryRow(
        _ category: ATHLTHSettingsCategory
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: category.icon)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(
                    category == .membership
                        ? ATHLTHTheme.premiumGold
                        : ATHLTHTheme.accentDeep
                )
                .frame(width: 44, height: 44)
                .background(
                    category == .membership
                        ? ATHLTHTheme.premiumGoldSoft
                        : ATHLTHTheme.accentSoft,
                    in: RoundedRectangle(cornerRadius: 14)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(category.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                Text(category.detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.68))
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func settingsDetailPage(
        for category: ATHLTHSettingsCategory
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(category.title)
                        .font(.system(size: 29, weight: .regular, design: .serif))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                    Text(category.detail)
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }
                .padding(.horizontal, 3)
                .padding(.bottom, 18)

                settingsContents(for: category)
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 32)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(settingsBackground)
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    @ViewBuilder
    private func settingsContents(for category: ATHLTHSettingsCategory) -> some View {
        switch category {
        case .health:
            connectionsSettingsSection
        case .training:
            trainingSettingsSection
        case .account:
            profileSettingsSection
            accountSettingsSection
        case .app:
            appSettingsSection
        case .membership:
            membershipSettingsSection
        case .privacy:
            privacySettingsSection
        case .developer:
            developerSettingsSections
        }
    }

    private var appSettingsSection: some View {
settingsSection("App") {
                        PremiumSettingsCard {
                            Menu {
                            ForEach(MeasurementPreference.allCases) { preference in
                                Button {
                                    settings.measurementPreference = preference
                                } label: {
                                    if settings.measurementPreference == preference {
                                        Label(preference.title, systemImage: "checkmark")
                                    } else {
                                        Text(preference.title)
                                    }
                                }
                            }
                        } label: {
                            PremiumSettingsRow(
                                icon: "ruler",
                                title: "Measurements",
                                subtitle: "Units for distance, weight and temperature"
                            ) {
                                HStack(spacing: 8) {
                                    Text(settings.measurementPreference.title)
                                        .foregroundStyle(ATHLTHTheme.mutedText)
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.72))
                                }
                            }
                            }
                            .buttonStyle(.plain)

                            SettingsDivider()

                            Menu {
                                ForEach(TimeFormatPreference.allCases) { preference in
                                    Button {
                                        settings.timeFormatPreference = preference
                                    } label: {
                                        if settings.timeFormatPreference == preference {
                                            Label(
                                                "\(preference.title) · \(preference.example)",
                                                systemImage: "checkmark"
                                            )
                                        } else {
                                            Text(
                                                "\(preference.title) · \(preference.example)"
                                            )
                                        }
                                    }
                                }
                            } label: {
                                PremiumSettingsRow(
                                    icon: "clock",
                                    title: ATHLTHLocalization.choose(
                                        english: "Time format",
                                        norwegian: "Tidsformat"
                                    ),
                                    subtitle: ATHLTHLocalization.choose(
                                        english: "Used for times throughout ATHLTH",
                                        norwegian: "Brukes for klokkeslett i hele ATHLTH"
                                    )
                                ) {
                                    HStack(spacing: 8) {
                                        Text(settings.timeFormatPreference.title)
                                            .foregroundStyle(ATHLTHTheme.mutedText)
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(
                                                ATHLTHTheme.mutedText.opacity(0.72)
                                            )
                                    }
                                }
                            }
                            .buttonStyle(.plain)

                            SettingsDivider()

                            Menu {
                                ForEach(
                                    AppLanguage
                                        .currentlySupported
                                ) { language in
                                    Button {
                                        settings.language =
                                            language
                                    } label: {
                                        if settings.language ==
                                            language {
                                            Label(
                                                language.title,
                                                systemImage:
                                                    "checkmark"
                                            )
                                        } else {
                                            Text(
                                                language.title
                                            )
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 14) {
                                    Image(
                                        systemName: "globe"
                                    )
                                    .font(
                                        .system(
                                            size: 18,
                                            weight: .medium
                                        )
                                    )
                                    .foregroundStyle(
                                        ATHLTHTheme
                                            .primaryText
                                    )
                                    .frame(
                                        width: 44,
                                        height: 44
                                    )
                                    .background(
                                        ATHLTHTheme
                                            .accentSoft,
                                        in:
                                            RoundedRectangle(
                                                cornerRadius: 14,
                                                style:
                                                    .continuous
                                            )
                                    )

                                    VStack(
                                        alignment: .leading,
                                        spacing: 3
                                    ) {
                                        Text("Language")
                                            .font(
                                                .system(
                                                    size: 16.5,
                                                    weight:
                                                        .medium
                                                )
                                            )
                                            .foregroundStyle(
                                                ATHLTHTheme
                                                    .primaryText
                                            )

                                        Text(
                                            "Choose English or Norwegian"
                                        )
                                        .font(.caption)
                                        .foregroundStyle(
                                            ATHLTHTheme
                                                .mutedText
                                        )
                                    }

                                    Spacer(
                                        minLength: 12
                                    )

                                    HStack(spacing: 8) {
                                        Text(
                                            settings
                                                .language
                                                .title
                                        )
                                        .foregroundStyle(
                                            ATHLTHTheme
                                                .mutedText
                                        )

                                        Image(
                                            systemName:
                                                "chevron.up.chevron.down"
                                        )
                                        .font(
                                            .caption2
                                                .weight(
                                                    .semibold
                                                )
                                        )
                                        .foregroundStyle(
                                            ATHLTHTheme
                                                .mutedText
                                                .opacity(
                                                    0.72
                                                )
                                        )
                                    }
                                }
                                .padding(
                                    .horizontal,
                                    16
                                )
                                .padding(
                                    .vertical,
                                    13
                                )
                                .contentShape(
                                    Rectangle()
                                )
                            }
                            .buttonStyle(.plain)

                            SettingsDivider()

                            NavigationLink {
                                ATHLTHWidgetsAndSurfacesSettingsView()
                            } label: {
                                PremiumSettingsRow(
                                    icon: "rectangle.grid.2x2",
                                    iconTint: ATHLTHTheme.vitality,
                                    iconBackground: ATHLTHTheme.vitalitySoft,
                                    title: "Widgets & Surfaces",
                                    subtitle: "Home Screen, Live Activities, Siri and Lock Screen"
                                ) {
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(
                                            ATHLTHTheme.mutedText.opacity(0.72)
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
    }

    private var profileSettingsSection: some View {
settingsSection("Profile") {
                        PremiumSettingsCard {
                            NavigationLink {
                                PersonalHealthProfileView()
                            } label: {
                                PremiumSettingsRow(
                                    icon: "heart.text.square",
                                    title: ATHLTHLocalization.choose(
                                        english: "Health & training profile",
                                        norwegian: "Helse- og treningsprofil"
                                    ),
                                    subtitle: ATHLTHLocalization.choose(
                                        english: "Apple Health, measurements, goals and limitations",
                                        norwegian: "Apple Helse, kroppsmål, mål og treningshensyn"
                                    )
                                ) {
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.72))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
    }

    private var healthSettingsSection: some View {
settingsSection(ATHLTHLocalization.choose(
    english: "Health & synchronization", norwegian: "Helse og synkronisering"
)) {
                        PremiumSettingsCard {
                            PremiumSettingsRow(
                                icon: "heart",
                                title: ATHLTHLocalization.choose(
                                    english: "Automatic Health sync",
                                    norwegian: "Automatisk Health-synkronisering"
                                ),
                                subtitle: backgroundHealthSubtitle
                            ) {
                                Toggle("", isOn: backgroundHealthSyncBinding)
                                    .labelsHidden()
                                    .tint(ATHLTHTheme.accent)
                            }
                            .opacity(1)

                            SettingsDivider()

                            Menu {
                                ForEach(
                                    ExternalWorkoutImportMode.allCases
                                ) { mode in
                                    Button {
                                        settings.externalWorkoutImportMode = mode
                                        Task {
                                            await health
                                                .applyExternalWorkoutImportMode(
                                                    mode
                                                )
                                        }
                                    } label: {
                                        if settings.externalWorkoutImportMode ==
                                            mode {
                                            Label(
                                                mode.title,
                                                systemImage: "checkmark"
                                            )
                                        } else {
                                            Text(mode.title)
                                        }
                                    }
                                }
                            } label: {
                                PremiumSettingsRow(
                                    icon: "square.and.arrow.down",
                                    title: ATHLTHLocalization.choose(
                                        english: "External workouts",
                                        norwegian: "Eksterne treningsøkter"
                                    ),
                                    subtitle:
                                        ATHLTHLocalization.choose(
                                            english: "Manage workouts imported from Apple Health",
                                            norwegian: "Styr import av økter fra Apple Health"
                                        )
                                ) {
                                    HStack(spacing: 8) {
                                        Text(
                                            settings
                                                .externalWorkoutImportMode
                                                .shortTitle
                                        )
                                        .foregroundStyle(
                                            ATHLTHTheme.mutedText
                                        )

                                        Image(
                                            systemName: "chevron.right"
                                        )
                                        .foregroundStyle(
                                            ATHLTHTheme.mutedText
                                                .opacity(0.72)
                                        )
                                    }
                                }
                            }
                            .buttonStyle(.plain)

                            SettingsDivider()

                            Button {
                                runHealthSync()
                            } label: {
                                PremiumSettingsRow(
                                    icon: healthSyncHasIssue
                                        ? "exclamationmark.triangle"
                                        : health.hasReadableHealthData
                                            ? "checkmark.circle"
                                            : "arrow.triangle.2.circlepath",
                                    iconTint: healthSyncHasIssue
                                        ? .orange
                                        : ATHLTHTheme.accentDeep,
                                    title: ATHLTHLocalization.choose(
                                        english: "Synchronization",
                                        norwegian: "Synkronisering"
                                    ),
                                    subtitle: healthSyncSummaryText
                                ) {
                                    connectionTrailing(
                                        healthRequestInProgress
                                            ? "Syncing"
                                            : health.hasRequestedAuthorization
                                                ? "Sync now"
                                                : "Connect",
                                        showChevron: false,
                                        loading: healthRequestInProgress
                                    )
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(healthRequestInProgress)
                        }
                    }
    }

    // Keep all Apple Health controls together; Home Assistant has its own
    // independent connection, sharing and refresh settings.
    private var appleHealthSettingsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                settingsSection("Apple Health") {
                    PremiumSettingsCard {
                        PremiumSettingsRow(
                            icon: "heart.fill",
                            iconTint: .pink,
                            iconBackground: Color.pink.opacity(0.10),
                            title: "Apple Health",
                            subtitle: appleHealthConnectionSubtitle
                        ) {
                            Text(settings.appleHealthIntegrationEnabled
                                ? healthSyncStateTitle
                                : ATHLTHLocalization.choose(
                                    english: "Paused", norwegian: "Deaktivert"
                                ))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.mutedText)
                        }

                        SettingsDivider()

                        Button {
                            if settings.appleHealthIntegrationEnabled {
                                showingAppleHealthPauseConfirmation = true
                            } else {
                                settings.appleHealthIntegrationEnabled = true
                                handleAppleHealthTap()
                            }
                        } label: {
                            PremiumSettingsRow(
                                icon: settings.appleHealthIntegrationEnabled
                                    ? "pause.circle" : "play.circle",
                                title: settings.appleHealthIntegrationEnabled
                                    ? ATHLTHLocalization.choose(
                                        english: "Pause Apple Health in ATHLTH",
                                        norwegian: "Deaktiver Apple Health i ATHLTH"
                                    )
                                    : ATHLTHLocalization.choose(
                                        english: "Enable Apple Health",
                                        norwegian: "Aktiver Apple Health"
                                    ),
                                subtitle: ATHLTHLocalization.choose(
                                    english: "Control Health data sync inside ATHLTH",
                                    norwegian: "Styr synkronisering av helsedata i ATHLTH"
                                )
                            ) {
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(healthRequestInProgress)

                        if !health.hasRequestedAuthorization &&
                           settings.appleHealthIntegrationEnabled {
                            SettingsDivider()
                            Button {
                                handleAppleHealthTap()
                            } label: {
                                PremiumSettingsRow(
                                    icon: "heart.text.square",
                                    title: ATHLTHLocalization.choose(
                                        english: "Connect Apple Health",
                                        norwegian: "Koble til Apple Health"
                                    ),
                                    subtitle: ATHLTHLocalization.choose(
                                        english: "Choose the Health data ATHLTH may access",
                                        norwegian: "Velg hvilke helsedata ATHLTH får tilgang til"
                                    )
                                ) {
                                    Image(systemName: "chevron.right")
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(healthRequestInProgress)
                        }
                    }
                }

                if settings.appleHealthIntegrationEnabled {
                    healthSettingsSection
                }

                settingsSection("iOS Permissions") {
                    PremiumSettingsCard {
                        Button {
                            if let url = URL(
                                string: UIApplication.openSettingsURLString
                            ) {
                                openURL(url)
                            }
                        } label: {
                            PremiumSettingsRow(
                                icon: "lock.shield",
                                title: ATHLTHLocalization.choose(
                                    english: "Manage Health permissions in iOS",
                                    norwegian: "Administrer helsetilgang i iOS"
                                ),
                                subtitle: ATHLTHLocalization.choose(
                                    english: "Revoke Apple Health permissions in the Health app",
                                    norwegian: "Trekk tilbake tillatelser i Helse-appen"
                                )
                            ) {
                                Image(systemName: "arrow.up.right")
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                            }
                        }
                        .buttonStyle(.plain)

                        Text(ATHLTHLocalization.choose(
                            english: "Turning off sync in ATHLTH does not revoke iOS permissions or erase previously imported data. To revoke access, open Health → profile → Apps → ATHLTH and switch off access. The button opens ATHLTH's iOS settings.",
                            norwegian: "Deaktivering i ATHLTH stopper synkroniseringen, men tilbakekaller ikke iOS-tillatelser eller sletter tidligere importerte data. For å trekke tilbake tilgang: Åpne Helse → profil → Apper → ATHLTH, og slå av tilgangen. Knappen åpner ATHLTHs iOS-innstillinger."
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .padding(.horizontal, 15)
                        .padding(.bottom, 15)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 34)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(settingsBackground)
        .navigationTitle("Apple Health")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english: "Pause Apple Health integration?",
                norwegian: "Deaktivere Apple Health i ATHLTH?"
            ),
            isPresented: $showingAppleHealthPauseConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                ATHLTHLocalization.choose(
                    english: "Pause integration",
                    norwegian: "Deaktiver integrasjonen"
                ),
                role: .destructive
            ) {
                settings.appleHealthIntegrationEnabled = false
                Task { await health.disableBackgroundSync() }
            }
            Button(
                ATHLTHLocalization.choose(
                    english: "Cancel", norwegian: "Avbryt"
                ), role: .cancel
            ) {}
        } message: {
            Text(ATHLTHLocalization.choose(
                english: "Automatic and manual Apple Health imports will stop. Existing Health permissions remain in iOS until you revoke them there.",
                norwegian: "Automatisk og manuell import fra Apple Health stoppes. iOS-tillatelsene beholdes til du trekker dem tilbake i Helse."
            ))
        }
    }

    private var connectionsSettingsSection: some View {
settingsSection("Connections") {
                        PremiumSettingsCard {
                            NavigationLink {
                                appleHealthSettingsPage
                            } label: {
                                PremiumSettingsRow(
                                    icon: "heart.fill",
                                    iconTint: .pink,
                                    iconBackground: Color.pink.opacity(0.10),
                                    title: "Apple Health",
                                    subtitle: appleHealthConnectionSubtitle
                                ) {
                                    connectionTrailing(
                                        !settings.appleHealthIntegrationEnabled
                                            ? "Off"
                                            : !health.hasRequestedAuthorization
                                                ? "Connect"
                                                : health.hasReadableHealthData
                                                    ? "Connected"
                                                    : "Configured",
                                        showChevron: true
                                    )
                                }
                            }
                            .buttonStyle(.plain)

                            SettingsDivider()

                            if session.subscriptionAccess.hasPaidAccess {
                                NavigationLink {
                                    AppleCalendarSettingsView()
                                } label: {
                                    PremiumSettingsRow(
                                        icon: "calendar",
                                        iconTint: .red,
                                        iconBackground: Color.red.opacity(0.09),
                                        title: "Calendar",
                                        subtitle: appleCalendarConnectionSubtitle
                                    ) {
                                        connectionTrailing(
                                            calendarSync.isSyncing
                                                ? "Syncing"
                                                : calendarSync.isEnabled
                                                    ? "Connected"
                                                    : calendarSync.hasFullAccess
                                                        ? "Ready"
                                                        : "Connect",
                                            showChevron: true,
                                            loading: calendarSync.isSyncing
                                        )
                                    }
                                }
                                .buttonStyle(.plain)
                            } else {
                                Button {
                                    showingMembership = true
                                } label: {
                                    PremiumSettingsRow(
                                        icon: "calendar",
                                        iconTint: .red,
                                        iconBackground: Color.red.opacity(0.09),
                                        title: "Calendar",
                                        subtitle:
                                            "ATHLTH+ · sync your training plan to Calendar"
                                    ) {
                                        HStack(spacing: 7) {
                                            Text("ATHLTH+")
                                                .font(.caption2.weight(.bold))
                                                .foregroundStyle(
                                                    ATHLTHTheme.premiumGold
                                                )

                                            Image(systemName: "chevron.right")
                                                .foregroundStyle(
                                                    ATHLTHTheme.mutedText
                                                        .opacity(0.72)
                                                )
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }

                            SettingsDivider()

                            if ATHLTHDeviceRole.isIPad {
                                PremiumSettingsRow(
                                    icon: "applewatch",
                                    iconTint:
                                        ATHLTHTheme.primaryText,
                                    title: "Apple Watch",
                                    subtitle:
                                        ATHLTHLocalization.choose(
                                            english:
                                                "Managed by your paired iPhone · workout starts can be sent from iPad",
                                            norwegian:
                                                "Styres av den parede iPhonen · økter kan startes fra iPad"
                                        )
                                ) {
                                    Text(
                                        ATHLTHLocalization.choose(
                                            english: "Via iPhone",
                                            norwegian: "Via iPhone"
                                        )
                                    )
                                    .font(
                                        .caption.weight(
                                            .semibold
                                        )
                                    )
                                    .foregroundStyle(
                                        ATHLTHTheme
                                            .mutedText
                                    )
                                }
                            } else {
                                NavigationLink {
                                    ATHLTHTrainingDeviceSettingsView()
                                } label: {
                                    PremiumSettingsRow(
                                        icon: "applewatch",
                                        iconTint: ATHLTHTheme.primaryText,
                                        title: "Watch",
                                        subtitle: trainingDeviceSubtitle
                                    ) {
                                        connectionTrailing(
                                            watchDeviceTrailingTitle,
                                            showChevron: true
                                        )
                                    }
                                }
                                .buttonStyle(.plain)
                            }

                            SettingsDivider()

                            NavigationLink {
                                SpotifySettingsView()
                            } label: {
                                PremiumSettingsRow(
                                    icon: "music.note",
                                    iconTint: spotifyGreen,
                                    iconBackground: spotifyGreen.opacity(0.12),
                                    title: "Spotify",
                                    subtitle: spotifyConnectionSubtitle
                                ) {
                                    connectionTrailing(
                                        spotify.connectionState.title,
                                        showChevron: true,
                                        loading:
                                            spotify.connectionState == .connecting
                                    )
                                }
                            }
                            .buttonStyle(.plain)

                            SettingsDivider()

                            NavigationLink {
                                HomeAssistantSettingsView()
                            } label: {
                                PremiumSettingsRow(
                                    icon: "house.fill",
                                    iconTint: Color(red: 0.12, green: 0.58, blue: 0.86),
                                    iconBackground: Color(red: 0.12, green: 0.58, blue: 0.86).opacity(0.11),
                                    title: "Home Assistant",
                                    subtitle: homeAssistant.connectionSubtitle
                                ) {
                                    connectionTrailing(
                                        homeAssistant.connectionState.title,
                                        showChevron: true,
                                        loading:
                                            homeAssistant.connectionState == .discovering ||
                                            homeAssistant.connectionState == .authorizing ||
                                            homeAssistant.connectionState == .pairing
                                    )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
    }

    private var trainingSettingsSection: some View {
settingsSection("Preferences") {
                        PremiumSettingsCard {
                            NavigationLink {
                                ATHLTHTrainingSettingsView()
                            } label: {
                                PremiumSettingsRow(
                                    icon: "figure.strengthtraining.traditional",
                                    title: "Training",
                                    subtitle: "Workout device, strength tracking and publishing"
                                ) {
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.72))
                                }
                            }
                            .buttonStyle(.plain)

                            SettingsDivider()

                            NavigationLink {
                                ATHLTHWorkoutGuidanceSettingsView()
                            } label: {
                                PremiumSettingsRow(
                                    icon: "waveform.and.mic",
                                    iconTint: ATHLTHTheme.premiumGold,
                                    iconBackground:
                                        ATHLTHTheme.premiumGoldSoft,
                                    title: "Workout Guidance",
                                    subtitle:
                                        "Audio Coach · Route Guardian · Ghost Updates"
                                ) {
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(
                                            ATHLTHTheme.mutedText
                                                .opacity(0.72)
                                        )
                                }
                            }
                            .buttonStyle(.plain)

                            SettingsDivider()

                            NavigationLink {
                                ATHLTHNotificationSettingsView()
                            } label: {
                                PremiumSettingsRow(
                                    icon: "bell",
                                    title: "Notifications",
                                    subtitle: notificationSummary
                                ) {
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.72))
                                }
                            }
                            .buttonStyle(.plain)

                            SettingsDivider()

                            NavigationLink {
                                ATHLTHAchievementSettingsView()
                            } label: {
                                PremiumSettingsRow(
                                    icon: "medal.fill",
                                    iconTint: ATHLTHTheme.premiumGold,
                                    iconBackground:
                                        ATHLTHTheme.premiumGoldSoft,
                                    title:
                                        ATHLTHLocalization.choose(
                                            english:
                                                "Achievements",
                                            norwegian:
                                                "Achievements"
                                        ),
                                    subtitle:
                                        ATHLTHLocalization.choose(
                                            english:
                                                "Unlock effects, sound and haptics",
                                            norwegian:
                                                "Unlock-effekter, lyd og haptikk"
                                        )
                                ) {
                                    HStack(spacing: 8) {
                                        Text(
                                            settings
                                                .achievementEffects
                                                .title
                                        )
                                        .font(.subheadline)
                                        .foregroundStyle(
                                            ATHLTHTheme
                                                .mutedText
                                        )

                                        Image(
                                            systemName:
                                                "chevron.right"
                                        )
                                        .foregroundStyle(
                                            ATHLTHTheme
                                                .mutedText
                                                .opacity(
                                                    0.72
                                                )
                                        )
                                    }
                                }
                            }
                            .buttonStyle(.plain)

                            SettingsDivider()

                            Link(destination: URL(string: "https://repdb.co")!) {
                                PremiumSettingsRow(
                                    icon: "figure.strengthtraining.traditional",
                                    title: ATHLTHLocalization.choose(
                                        english: "Exercise data",
                                        norwegian: "Øvelsesdata"
                                    ),
                                    subtitle: ATHLTHLocalization.choose(
                                        english: "Exercise catalog powered by RepDB",
                                        norwegian: "Øvelsesbibliotek levert av RepDB"
                                    )
                                ) {
                                    Image(systemName: "arrow.up.right")
                                        .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.72))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
    }

    private var membershipSettingsSection: some View {
settingsSection("Membership") {
                        PremiumSettingsCard {
                            Button {
                                showingMembership = true
                            } label: {
                                PremiumSettingsRow(
                                    icon: "crown.fill",
                                    iconTint: ATHLTHTheme.premiumGold,
                                    iconBackground: ATHLTHTheme.premiumGoldSoft,
                                    title: ATHLTHLocalization.choose(
                                        english: "Plan", norwegian: "Abonnement"
                                    ),
                                    subtitle: session.subscriptionAccess.source == .ownerOverride
                                        ? ATHLTHLocalization.choose(
                                            english: "Permanent owner access",
                                            norwegian: "Permanent eiertilgang"
                                        )
                                        : ATHLTHLocalization.choose(
                                            english: "Your current access",
                                            norwegian: "Din nåværende tilgang"
                                        )
                                ) {
                                    HStack(spacing: 8) {
                                        Text(session.subscriptionAccess.displayTitle)
                                            .foregroundStyle(ATHLTHTheme.mutedText)
                                            .lineLimit(1)
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.72))
                                    }
                                }
                            }
                            .buttonStyle(.plain)

                            if let billingPeriod = session.subscriptionAccess.billingPeriodTitle {
                                SettingsDivider()
                                PremiumSettingsRow(
                                    icon: "creditcard",
                                    title: "Billing",
                                    subtitle: "Your billing cycle"
                                ) {
                                    Text(billingPeriod)
                                        .foregroundStyle(ATHLTHTheme.mutedText)
                                }
                            }

                            if session.subscriptionAccess.trialIsActive,
                               let trialEndsAt = session.subscriptionAccess.trialEndsAt {
                                SettingsDivider()
                                PremiumSettingsRow(
                                    icon: "calendar",
                                    title: "7-day trial ends",
                                    subtitle: "Keep going. You’re almost there."
                                ) {
                                    Text(trialEndsAt.formatted(date: .abbreviated, time: .omitted))
                                        .foregroundStyle(ATHLTHTheme.mutedText)
                                        .multilineTextAlignment(.trailing)
                                }
                            }

                            if let periodEndsAt = session.subscriptionAccess.currentPeriodEndsAt {
                                switch session.subscriptionAccess.lifecycleState {
                                case .active:
                                    SettingsDivider()
                                    PremiumSettingsRow(
                                        icon: "calendar.badge.clock",
                                        title: "Current period",
                                        subtitle: "Your current ATHLTH+ access"
                                    ) {
                                        Text(periodEndsAt.formatted(date: .abbreviated, time: .omitted))
                                            .foregroundStyle(ATHLTHTheme.mutedText)
                                    }
                                case .expired:
                                    SettingsDivider()
                                    PremiumSettingsRow(
                                        icon: "calendar.badge.exclamationmark",
                                        title: "Access ended",
                                        subtitle: "Your ATHLTH+ access has ended"
                                    ) {
                                        Text(periodEndsAt.formatted(date: .abbreviated, time: .omitted))
                                            .foregroundStyle(ATHLTHTheme.mutedText)
                                    }
                                default:
                                    EmptyView()
                                }
                            }

                            SettingsDivider()

                            Button {
                                membershipRestoreMessage = nil
                                Task {
                                    let restored = await subscriptionStore.restorePurchases()
                                    if restored {
                                        session.applyStoreKitEntitlement(
                                            subscriptionStore.activeEntitlement
                                        )
                                        membershipRestoreMessage = ATHLTHLocalization.choose(
                                            english: "App Store purchase restored.",
                                            norwegian: "App Store-kjøpet er gjenopprettet."
                                        )
                                    } else if subscriptionStore.errorMessage == nil {
                                        membershipRestoreMessage = ATHLTHLocalization.choose(
                                            english: "No active App Store purchase was found for this Apple Account.",
                                            norwegian: "Fant ingen aktive App Store-kjøp for denne Apple-kontoen."
                                        )
                                    }
                                }
                            } label: {
                                PremiumSettingsRow(
                                    icon: "arrow.counterclockwise",
                                    title: ATHLTHLocalization.choose(
                                        english: "Restore purchases",
                                        norwegian: "Gjenopprett kjøp"
                                    ),
                                    subtitle: ATHLTHLocalization.choose(
                                        english: "Restore ATHLTH+ purchases made through Apple",
                                        norwegian: "Gjenopprett ATHLTH+-kjøp fra Apple"
                                    )
                                ) {
                                    if subscriptionStore.restoreInProgress {
                                        ProgressView()
                                            .tint(ATHLTHTheme.accent)
                                    } else {
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.72))
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(subscriptionStore.restoreInProgress)

                            if session.subscriptionAccess.hasPaidAccess &&
                               session.subscriptionAccess.billingPeriodTitle != nil {
                                SettingsDivider()

                                Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
                                    PremiumSettingsRow(
                                        icon: "creditcard",
                                        title: ATHLTHLocalization.choose(
                                            english: "Manage subscription",
                                            norwegian: "Administrer abonnement"
                                        ),
                                        subtitle: ATHLTHLocalization.choose(
                                            english: "Open Apple subscription settings",
                                            norwegian: "Åpne abonnementer hos Apple"
                                        )
                                    ) {
                                        Image(systemName: "arrow.up.right")
                                            .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.72))
                                    }
                                }
                                .buttonStyle(.plain)
                            }

                            if let membershipRestoreMessage {
                                SettingsDivider()
                                Text(membershipRestoreMessage)
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                            }

                            if let errorMessage = subscriptionStore.errorMessage {
                                SettingsDivider()
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                            }
                        }
                    }
    }

    private var accountSettingsSection: some View {
settingsSection("Account") {
                        PremiumSettingsCard {
                            NavigationLink {
                                ATHLTHAccountSecurityView()
                            } label: {
                                PremiumSettingsRow(
                                    icon: "person.badge.key",
                                    title: ATHLTHLocalization.choose(
                                        english: "Account & Security",
                                        norwegian: "Konto og sikkerhet"
                                    ),
                                    subtitle: ATHLTHLocalization.choose(
                                        english: "Sign-in, security, privacy and your data",
                                        norwegian: "Innlogging, sikkerhet, personvern og data"
                                    )
                                ) {
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.72))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
    }

    private var privacySettingsSection: some View {
        settingsSection("Privacy") {
            PremiumSettingsCard {
                NavigationLink {
                    LegalDocumentView(kind: .terms)
                } label: {
                    PremiumSettingsRow(
                        icon: "doc.text",
                        title: ATHLTHLocalization.choose(
                            english: "Terms of Service",
                            norwegian: "Brukervilkår"
                        ),
                        subtitle: ATHLTHLocalization.choose(
                            english: "Read the ATHLTH terms",
                            norwegian: "Les vilkårene for ATHLTH"
                        )
                    ) {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.72))
                    }
                }
                .buttonStyle(.plain)

                SettingsDivider()

                NavigationLink {
                    LegalDocumentView(kind: .privacy)
                } label: {
                    PremiumSettingsRow(
                        icon: "lock.shield",
                        title: ATHLTHLocalization.choose(
                            english: "Privacy Policy",
                            norwegian: "Personvernerklæring"
                        ),
                        subtitle: ATHLTHLocalization.choose(
                            english: "How ATHLTH handles your data",
                            norwegian: "Hvordan ATHLTH behandler opplysningene dine"
                        )
                    ) {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.72))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var developerSettingsSections: some View {
if session.currentRole.canAccessControlCenter {
                        settingsSection("Support") {
                            PremiumSettingsCard {
                                NavigationLink {
                                    ATHLTHSystemDiagnosticsView()
                                } label: {
                                    PremiumSettingsRow(
                                        icon: "stethoscope",
                                        title: "System Diagnostics",
                                        subtitle: "Health, Watch, push, account and build status"
                                    ) {
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.72))
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if session.currentRole.canAccessControlCenter {
                        settingsSection("Developer") {
                            PremiumSettingsCard {
                                NavigationLink {
                                    AdminAIUsageView()
                                } label: {
                                    PremiumSettingsRow(
                                        icon: "sparkles.rectangle.stack",
                                        title: "AI Usage",
                                        subtitle: "Live Groq quota and prompt-saving status"
                                    ) {
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.72))
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    #if DEBUG
                    if session.currentRole.canAccessControlCenter {
                        settingsSection("Admin") {
                            PremiumSettingsCard {
                                NavigationLink {
                                    AdminCenterView()
                                } label: {
                                    PremiumSettingsRow(
                                        icon: "lock.rectangle.stack",
                                        title: "Control Center",
                                        subtitle: "Development preview · not production data"
                                    ) {
                                        HStack(spacing: 8) {
                                            Text(session.currentRole.title)
                                                .font(.subheadline)
                                                .foregroundStyle(ATHLTHTheme.mutedText)
                                            Image(systemName: "chevron.right")
                                                .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.72))
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if session.previewModeEnabled || session.currentRole.canAccessControlCenter {
                        settingsSection("Developer Tools") {
                            PremiumSettingsCard {
                                NavigationLink {
                                    CapabilityLabView()
                                } label: {
                                    PremiumSettingsRow(
                                        icon: "testtube.2",
                                        title: "Capability Lab",
                                        subtitle: "Run low-level Health and capability tests"
                                    ) {
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.72))
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    #endif
    }

    private var settingsBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    ATHLTHTheme.canvasTop,
                    Color.white,
                    ATHLTHTheme.canvasBottom
                ],
                startPoint: .top,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    ATHLTHTheme.premiumGold.opacity(0.055),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 13) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .frame(width: 43, height: 43)
                    .background(Color.white.opacity(0.96), in: Circle())
                    .overlay {
                        Circle().stroke(ATHLTHTheme.border, lineWidth: 0.8)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                ATHLTHLocalization.choose(english: "Back", norwegian: "Tilbake")
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(
                    ATHLTHLocalization.choose(
                        english: "ATHLTH / SETTINGS",
                        norwegian: "ATHLTH / INNSTILLINGER"
                    )
                )
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2.1)
                    .foregroundStyle(ATHLTHTheme.premiumGold)

                Text(ATHLTHLocalization.choose(
                    english: "Settings", norwegian: "Innstillinger"
                ))
                .font(.system(size: 32, weight: .regular, design: .serif))
                .foregroundStyle(ATHLTHTheme.primaryText)

                Text(ATHLTHLocalization.choose(
                    english: "Make ATHLTH yours.",
                    norwegian: "Dine valg. Din trening."
                ))
                .font(.subheadline)
                .foregroundStyle(ATHLTHTheme.mutedText)
            }

            Spacer(minLength: 0)

            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(width: 44, height: 44)
                .background(ATHLTHTheme.premiumGoldSoft, in: Circle())
                .accessibilityHidden(true)
        }
        .padding(.top, 6)
        .padding(.bottom, 9)
    }

    @ViewBuilder
    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localizedSettingsSectionTitle(title).uppercased())
                .font(.caption.weight(.semibold))
                .tracking(2.8)
                .foregroundStyle(ATHLTHTheme.accentDeep.opacity(0.82))
                .padding(.leading, 16)

            content()
        }
        .padding(.bottom, 24)
    }

    private func localizedSettingsSectionTitle(
        _ title: String
    ) -> String {
        guard ATHLTHLocalization.isNorwegian else {
            return title
        }

        switch title {
        case "App":
            return "App"
        case "Profile":
            return "Profil"
        case "Privacy & Data":
            return "Personvern og data"
        case "Health & Sync":
            return "Helse og synkronisering"
        case "Connections":
            return "Tilkoblinger"
        case "Preferences":
            return "Preferanser"
        case "Membership":
            return "Medlemskap"
        case "Account":
            return "Konto"
        case "About":
            return "Om ATHLTH"
        case "Privacy":
            return "Personvern"
        case "Support":
            return "Brukerstøtte"
        case "Developer":
            return "Utvikler"
        case "Admin":
            return "Admin"
        case "Developer Tools":
            return "Utviklerverktøy"
        case "Tools":
            return "Verktøy"
        default:
            return title
        }
    }

    private var privacySummary: String {
        let profileTitle: String
        if let raw = social.privacy?.profileVisibility,
           let visibility = ProfileVisibility(rawValue: raw) {
            profileTitle = visibility.title
        } else {
            profileTitle = settings.profileVisibility.title
        }

        let routeTitle = settings.hideRouteStartAndEnd
            ? "route endpoints hidden"
            : "full routes"

        return "\(profileTitle) profile · \(routeTitle)"
    }

    private var trainingDeviceSubtitle: String {
        switch watchConnection.state {
        case .ready:
            return ATHLTHLocalization.choose(
                english: "Apple Watch connected",
                norwegian: "Apple Watch tilkoblet"
            )
        case .appNotInstalled:
            return ATHLTHLocalization.choose(
                english: "Apple Watch paired · install ATHLTH on Watch",
                norwegian: "Apple Watch sammenkoblet · installer ATHLTH på klokken"
            )
        case .notPaired:
            return ATHLTHLocalization.choose(
                english: "No Apple Watch connected",
                norwegian: "Ingen Apple Watch tilkoblet"
            )
        case .checking:
            return ATHLTHLocalization.choose(
                english: "Checking Apple Watch",
                norwegian: "Sjekker Apple Watch"
            )
        case .unsupported:
            return ATHLTHLocalization.choose(
                english: "Apple Watch unavailable on this device",
                norwegian: "Apple Watch er ikke tilgjengelig på denne enheten"
            )
        }
    }

    private var watchDeviceTrailingTitle: String {
        switch watchConnection.state {
        case .ready:
            return "Apple Watch"
        case .checking:
            return ATHLTHLocalization.choose(
                english: "Checking",
                norwegian: "Sjekker"
            )
        case .appNotInstalled, .notPaired, .unsupported:
            return ATHLTHLocalization.choose(
                english: "Setup",
                norwegian: "Oppsett"
            )
        }
    }

    private var spotifyConnectionSubtitle: String {
        if spotify.isConnected {
            if spotify.playlists.isEmpty {
                return ATHLTHLocalization.choose(
                    english: "Spotify connected",
                    norwegian: "Spotify tilkoblet"
                )
            }

            return ATHLTHLocalization.format(
                english: "Connected · %d playlists available",
                norwegian: "Tilkoblet · %d spillelister tilgjengelig",
                spotify.playlists.count
            )
        }

        switch spotify.connectionState {
        case .unavailable:
            return ATHLTHLocalization.choose(
                english: "Spotify setup is unavailable in this build",
                norwegian: "Spotify-oppsett er ikke tilgjengelig i denne versjonen"
            )
        case .connecting:
            return ATHLTHLocalization.choose(
                english: "Connecting to Spotify…",
                norwegian: "Kobler til Spotify…"
            )
        case .error:
            return ATHLTHLocalization.choose(
                english: "Connection needs attention",
                norwegian: "Tilkoblingen krever oppmerksomhet"
            )
        case .disconnected:
            return ATHLTHLocalization.choose(
                english: "Connect Spotify for workout playlists",
                norwegian: "Koble til Spotify for spillelister til trening"
            )
        case .connected:
            return ATHLTHLocalization.choose(
                english: "Spotify connected",
                norwegian: "Spotify tilkoblet"
            )
        }
    }

    private var notificationSummary: String {
        switch notifications.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return ATHLTHLocalization.choose(
                english: "System notifications allowed · choose what ATHLTH sends",
                norwegian: "Systemvarsler tillatt · velg hva ATHLTH skal sende"
            )
        case .denied:
            return ATHLTHLocalization.choose(
                english: "System notifications are disabled in iOS Settings",
                norwegian: "Systemvarsler er deaktivert i iOS-innstillinger"
            )
        case .notDetermined:
            return ATHLTHLocalization.choose(
                english: "System notification permission has not been requested",
                norwegian: "Tillatelse til systemvarsler er ikke forespurt"
            )
        @unknown default:
            return ATHLTHLocalization.choose(
                english: "Review notification preferences",
                norwegian: "Se gjennom varslingsinnstillingene"
            )
        }
    }

    private var healthSyncHasIssue: Bool {
        let backgroundIssue = !(health.backgroundSyncError?.isEmpty ?? true)
        let readIssue = !(health.authorizationError?.isEmpty ?? true)
        return backgroundIssue || readIssue
    }

    private var healthSyncStateTitle: String {
        guard settings.appleHealthIntegrationEnabled else {
            return ATHLTHLocalization.choose(
                english: "Paused", norwegian: "Deaktivert"
            )
        }
        guard settings.backgroundHealthSyncEnabled else {
            return ATHLTHLocalization.choose(
                english: "Off",
                norwegian: "Av"
            )
        }
        if health.isRefreshing {
            return ATHLTHLocalization.choose(
                english: "Syncing",
                norwegian: "Synkroniserer"
            )
        }
        if !health.hasRequestedAuthorization {
            return ATHLTHLocalization.choose(
                english: "Not connected",
                norwegian: "Ikke tilkoblet"
            )
        }
        if healthSyncHasIssue {
            return ATHLTHLocalization.choose(
                english: "Issue",
                norwegian: "Problem"
            )
        }
        if health.lastSuccessfulRefreshAt != nil && !health.hasTrainingHealthData {
            return health.personalDetails.hasAnyValue
                ? ATHLTHLocalization.choose(
                    english: "Profile only",
                    norwegian: "Kun profil"
                )
                : ATHLTHLocalization.choose(
                    english: "No data",
                    norwegian: "Ingen data"
                )
        }
        if health.lastSuccessfulRefreshAt != nil &&
            health.hasTrainingHealthData &&
            !health.canWriteWorkouts {
            return ATHLTHLocalization.choose(
                english: "Read only",
                norwegian: "Kun lesing"
            )
        }
        return health.lastSuccessfulRefreshAt != nil
            ? ATHLTHLocalization.choose(
                english: "Synced",
                norwegian: "Synkronisert"
            )
            : ATHLTHLocalization.choose(
                english: "Ready",
                norwegian: "Klar"
            )
    }

    private var healthSyncSummaryText: String {
        if !settings.appleHealthIntegrationEnabled {
            return ATHLTHLocalization.choose(
                english: "Synchronization is paused",
                norwegian: "Synkronisering er deaktivert"
            )
        }
        if healthSyncHasIssue { return healthSyncStatusText }
        if healthRequestInProgress || health.isRefreshing {
            return ATHLTHLocalization.choose(
                english: "Synchronizing…", norwegian: "Synkroniserer…"
            )
        }
        if let last = health.lastSuccessfulRefreshAt {
            let time = healthSyncTimestamp(last)
            return ATHLTHLocalization.choose(
                english: "Last synced \(time)",
                norwegian: "Sist synkronisert \(time)"
            )
        }
        return health.hasRequestedAuthorization
            ? ATHLTHLocalization.choose(
                english: "Ready for first sync",
                norwegian: "Klar for første synkronisering"
            )
            : ATHLTHLocalization.choose(
                english: "Connect to begin syncing",
                norwegian: "Koble til for å synkronisere"
            )
    }

    private var healthSyncStatusText: String {
        guard settings.appleHealthIntegrationEnabled else {
            return ATHLTHLocalization.choose(
                english: "Apple Health synchronization is paused in ATHLTH.",
                norwegian: "Apple Health-synkronisering er deaktivert i ATHLTH."
            )
        }
        if healthRequestInProgress {
            return ATHLTHLocalization.choose(
                english: "Reading workouts, activity, sleep, heart data and profile values from Apple Health.",
                norwegian: "Leser økter, aktivitet, søvn, hjertedata og profilverdier fra Apple Health."
            )
        }

        if let error = health.backgroundSyncError, !error.isEmpty {
            return ATHLTHLocalization.choose(
                english: "Background sync needs attention: \(error)",
                norwegian: "Bakgrunnssynkronisering krever oppmerksomhet: \(error)"
            )
        }

        if let error = health.authorizationError, !error.isEmpty {
            return ATHLTHLocalization.choose(
                english: "Apple Health read needs attention: \(error)",
                norwegian: "Lesetilgang til Apple Health krever oppmerksomhet: \(error)"
            )
        }

        guard health.hasRequestedAuthorization else {
            return ATHLTHLocalization.choose(
                english: "Apple Health is not connected yet. Tap here to connect.",
                norwegian: "Apple Health er ikke tilkoblet ennå. Trykk her for å koble til."
            )
        }

        if let lastRefresh = health.lastSuccessfulRefreshAt {
            let synced = healthSyncTimestamp(lastRefresh)

            if health.hasTrainingHealthData {
                if health.canWriteWorkouts {
                    return ATHLTHLocalization.choose(
                        english: "Apple Health training data imported successfully. Last synced \(synced).",
                        norwegian: "Treningsdata fra Apple Health er importert. Sist synkronisert \(synced)."
                    )
                }

                return ATHLTHLocalization.choose(
                    english: "Apple Health data was imported \(synced), but workout write access is off. Tap Sync now to review Health permissions.",
                    norwegian: "Apple Health-data ble importert \(synced), men skrivetilgang for økter er av. Trykk Synkroniser nå for å kontrollere Health-tillatelser."
                )
            }

            if health.personalDetails.hasAnyValue {
                return ATHLTHLocalization.choose(
                    english: "Apple Health profile values were imported, but ATHLTH found no readable workouts, activity, sleep or heart data. Review Health read access, then tap Sync now.",
                    norwegian: "Profilverdier fra Apple Health ble importert, men ATHLTH fant ingen lesbare økter, aktivitets-, søvn- eller hjertedata. Kontroller lesetilgangen i Health og trykk deretter Synkroniser nå."
                )
            }

            return ATHLTHLocalization.choose(
                english: "Apple Health responded, but ATHLTH found no readable compatible data. Review Health read access, then tap Sync now.",
                norwegian: "Apple Health svarte, men ATHLTH fant ingen kompatible data som kunne leses. Kontroller lesetilgangen i Health og trykk deretter Synkroniser nå."
            )
        }

        return settings.backgroundHealthSyncEnabled
            ? ATHLTHLocalization.choose(
                english: "Apple Health is configured. Tap Sync now to perform the first full import.",
                norwegian: "Apple Health er konfigurert. Trykk Synkroniser nå for å utføre første fullstendige import."
            )
            : ATHLTHLocalization.choose(
                english: "Apple Health is configured. Background sync is off, but you can still tap Sync now.",
                norwegian: "Apple Health er konfigurert. Bakgrunnssynkronisering er av, men du kan fortsatt trykke Synkroniser nå."
            )
    }

    private func healthSyncTimestamp(
        _ date: Date
    ) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return ATHLTHLocalization.choose(
                english: "today at ",
                norwegian: "i dag kl. "
            ) + date.formatted(
                date: .omitted,
                time: .shortened
            )
        }

        if calendar.isDateInYesterday(date) {
            return ATHLTHLocalization.choose(
                english: "yesterday at ",
                norwegian: "i går kl. "
            ) + date.formatted(
                date: .omitted,
                time: .shortened
            )
        }

        return date.formatted(
            date: .abbreviated,
            time: .shortened
        )
    }

    private var backgroundHealthSyncBinding: Binding<Bool> {
        Binding(
            get: {
                settings.backgroundHealthSyncEnabled
            },
            set: { enabled in
                settings.backgroundHealthSyncEnabled = enabled
                Task {
                    await health.configureBackgroundSync(
                        allowed: enabled &&
                            settings.appleHealthIntegrationEnabled
                    )
                }
            }
        )
    }

    private var backgroundHealthSubtitle: String {
        ATHLTHLocalization.choose(
            english: "Sync with Apple Health automatically in the background.",
            norwegian: "Synkroniser automatisk med Apple Health i bakgrunnen."
        )
    }

    private var appleHealthConnectionSubtitle: String {
        guard settings.appleHealthIntegrationEnabled else {
            return ATHLTHLocalization.choose(
                english: "Paused in ATHLTH · system permissions unchanged",
                norwegian: "Deaktivert i ATHLTH · iOS-tillatelser beholdt"
            )
        }
        guard health.hasRequestedAuthorization else {
            return ATHLTHLocalization.choose(
                english: "Connect your Apple Health data",
                norwegian: "Koble til Apple Health-data"
            )
        }

        if health.authorizationReviewNeeded {
            return ATHLTHLocalization.choose(
                english: "Connected · optional new Health permissions are available",
                norwegian: "Tilkoblet · valgfrie nye Health-tillatelser er tilgjengelige"
            )
        }

        if health.hasTrainingHealthData {
            return health.canWriteWorkouts
                ? ATHLTHLocalization.choose(
                    english: "Connected · training and health data is available",
                    norwegian: "Tilkoblet · trenings- og helsedata er tilgjengelig"
                )
                : ATHLTHLocalization.choose(
                    english: "Connected for reading · workout write access is off",
                    norwegian: "Tilkoblet for lesing · skrivetilgang for økter er av"
                )
        }

        if health.personalDetails.hasAnyValue {
            return ATHLTHLocalization.choose(
                english: "Configured · profile values available, no training data yet",
                norwegian: "Konfigurert · profilverdier tilgjengelig, ingen treningsdata ennå"
            )
        }

        if health.lastSuccessfulRefreshAt != nil {
            return ATHLTHLocalization.choose(
                english: "Permission configured · no readable data found yet",
                norwegian: "Tillatelse konfigurert · ingen lesbare data funnet ennå"
            )
        }

        return ATHLTHLocalization.choose(
            english: "Permission configured · run the first sync",
            norwegian: "Tillatelse konfigurert · kjør første synkronisering"
        )
    }

    private var appleCalendarConnectionSubtitle: String {
        if calendarSync.isEnabled {
            return ATHLTHLocalization.choose(
                english: "Training plan sync · ATHLTH calendar",
                norwegian: "Synkronisering av treningsplan · ATHLTH-kalender"
            )
        }

        if calendarSync.hasFullAccess {
            return ATHLTHLocalization.choose(
                english: "Calendar connected · training plan sync is off",
                norwegian: "Kalender tilkoblet · synkronisering av treningsplan er av"
            )
        }

        return ATHLTHLocalization.choose(
            english: "Sync planned workouts to a dedicated ATHLTH calendar",
            norwegian: "Synkroniser planlagte økter til en egen ATHLTH-kalender"
        )
    }

    private var spotifyGreen: Color {
        Color(red: 0.12, green: 0.72, blue: 0.35)
    }

    @ViewBuilder
    private func connectionTrailing(
        _ text: String,
        showChevron: Bool,
        loading: Bool = false
    ) -> some View {
        HStack(spacing: 8) {
            if loading {
                ProgressView()
                    .tint(ATHLTHTheme.accent)
            } else {
                Text(localizedConnectionStatus(text))
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.mutedText)
            }

            if showChevron {
                Image(systemName: "chevron.right")
                    .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.72))
            }
        }
    }

    private func localizedConnectionStatus(
        _ status: String
    ) -> String {
        guard ATHLTHLocalization.isNorwegian else {
            return status
        }

        switch status {
        case "Connected":
            return "Tilkoblet"
        case "Not connected":
            return "Ikke tilkoblet"
        case "Connect":
            return "Koble til"
        case "Syncing":
            return "Synkroniserer"
        case "Configured":
            return "Konfigurert"
        case "Ready":
            return "Klar"
        case "Checking":
            return "Sjekker"
        case "Setup":
            return "Oppsett"
        case "Connection issue":
            return "Tilkoblingsproblem"
        case "Needs setup":
            return "Må konfigureres"
        case "Connecting…":
            return "Kobler til…"
        default:
            return status
        }
    }

    private func handleAppleHealthTap() {
        guard settings.appleHealthIntegrationEnabled else { return }
        Task {
            healthRequestInProgress = true

            let restoredExistingSetup =
                await health.restoreAuthorizationStateFromSystem()

            if !restoredExistingSetup || health.authorizationReviewNeeded {
                // The Apple Health row is the explicit place to connect or
                // review newly introduced permissions. Normal sync never
                // reopens the Health permission flow.
                await health.requestAuthorization()
                await health.completeAuthorizationSetup()
            } else {
                health.resumeUserInitiatedHealthSync()
            }

            await health.configureBackgroundSync(
                allowed: settings.backgroundHealthSyncEnabled
            )
            _ = await health.refreshWorkoutImportInbox()
            await health.refreshAll()
            syncHealthProfileFromAppleHealthIfAppropriate()
            healthRequestInProgress = false
        }
    }

    private func runHealthSync() {
        guard settings.appleHealthIntegrationEnabled else { return }
        guard health.hasRequestedAuthorization else {
            handleAppleHealthTap()
            return
        }

        Task {
            healthRequestInProgress = true

            // Sync with the permissions that are already in place. Do not
            // reopen Health authorization simply because the app was updated
            // or because ATHLTH added another optional Health data type.
            _ = await health.restoreAuthorizationStateFromSystem()
            health.resumeUserInitiatedHealthSync()

            await health.configureBackgroundSync(
                allowed: settings.backgroundHealthSyncEnabled
            )
            _ = await health.refreshWorkoutImportInbox()
            await health.refreshAll()
            syncHealthProfileFromAppleHealthIfAppropriate()
            healthRequestInProgress = false
        }
    }

    private func syncHealthProfileFromAppleHealthIfAppropriate() {
        guard health.personalDetails.hasAnyValue else {
            return
        }

        session.mergePersonalDetailsFromAppleHealth(
            health.personalDetails
        )
    }

    private var appVersion: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "—"
        return version
    }
}

private struct AppleCalendarSettingsView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var calendarSync: AppleCalendarSyncStore
    @EnvironmentObject private var communityEvents: CommunityEventStore
    @EnvironmentObject private var communityGroups: CommunityGroupStore
    @EnvironmentObject private var challenges: ChallengeStore

    @State private var showingRemoveConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("CALENDAR")

                    PremiumSettingsCard {
                        HStack(spacing: 14) {
                            Image(systemName: "calendar")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.red)
                                .frame(width: 46, height: 46)
                                .background(
                                    Color.red.opacity(0.09),
                                    in: RoundedRectangle(
                                        cornerRadius: 14,
                                        style: .continuous
                                    )
                                )

                            VStack(alignment: .leading, spacing: 3) {
                                Text("ATHLTH Calendar")
                                    .font(.headline)
                                    .foregroundStyle(ATHLTHTheme.primaryText)

                                Text(calendarSync.authorizationTitle)
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                            }

                            Spacer()

                            if calendarSync.isSyncing {
                                ProgressView()
                                    .tint(ATHLTHTheme.accent)
                            } else {
                                Image(
                                    systemName:
                                        calendarSync.hasFullAccess
                                            ? "checkmark.circle.fill"
                                            : "circle"
                                )
                                .font(.title3)
                                .foregroundStyle(
                                    calendarSync.hasFullAccess
                                        ? ATHLTHTheme.accentDeep
                                        : Color.secondary.opacity(0.45)
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                        SettingsDivider()

                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Sync ATHLTH Calendar")
                                    .font(.system(size: 16.5, weight: .medium))
                                    .foregroundStyle(ATHLTHTheme.primaryText)

                                Text(ATHLTHLocalization.choose(
                                    english: "Sync planned workouts and confirmed or tentative event invitations.",
                                    norwegian: "Synkroniser planlagte økter og bekreftede eller foreløpige invitasjoner."
                                ))
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                            }

                            Spacer()

                            Toggle(
                                "",
                                isOn: calendarSyncBinding
                            )
                            .labelsHidden()
                            .tint(ATHLTHTheme.accent)
                            .disabled(calendarSync.isSyncing)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("SYNC STATUS")

                    PremiumSettingsCard {
                        statusRow(
                            title: "Calendar",
                            value: calendarSync.calendarExists
                                ? calendarSync.calendarName
                                : "Not created",
                            icon: "calendar.badge.checkmark"
                        )

                        SettingsDivider()

                        statusRow(
                            title: ATHLTHLocalization.choose(
                                english: "Last sync", norwegian: "Sist synkronisert"
                            ),
                            value: lastSyncText,
                            icon: "arrow.triangle.2.circlepath"
                        )

                        if let total = calendarSync.lastSyncEventCount {
                            SettingsDivider()
                            statusRow(
                                title: ATHLTHLocalization.choose(
                                    english: "Events in Calendar",
                                    norwegian: "Hendelser i Kalender"
                                ),
                                value: "\(total)",
                                icon: "checkmark.circle"
                            )
                            SettingsDivider()
                            statusRow(
                                title: ATHLTHLocalization.choose(
                                    english: "Planned workouts",
                                    norwegian: "Planlagte økter"
                                ),
                                value: "\(calendarSync.lastSyncWorkoutCount ?? 0)",
                                icon: "figure.run"
                            )
                            SettingsDivider()
                            statusRow(
                                title: ATHLTHLocalization.choose(
                                    english: "Tentative invitations",
                                    norwegian: "Foreløpige invitasjoner"
                                ),
                                value: "\(calendarSync.lastSyncTentativeCount ?? 0)",
                                icon: "envelope.badge"
                            )
                        }

                        SettingsDivider()

                        HStack(spacing: 12) {
                            Image(systemName: "clock")
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Default workout time")
                                    .font(.subheadline.weight(.medium))

                                Text(
                                    "Used only when the workout time is set to “–”."
                                )
                                .font(.caption)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                            }

                            Spacer()

                            DatePicker(
                                "",
                                selection: defaultCalendarTimeBinding,
                                displayedComponents: .hourAndMinute
                            )
                            .labelsHidden()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                        SettingsDivider()

                        Button {
                            Task {
                                if calendarSync.hasFullAccess &&
                                    calendarSync.isEnabled {
                                    await syncAllCalendarContent()
                                } else {
                                    await enableCalendarSync()
                                }
                            }
                        } label: {
                            HStack {
                                Label(
                                    calendarSync.hasFullAccess
                                        ? "Sync Now"
                                        : "Connect Calendar",
                                    systemImage: calendarSync.hasFullAccess
                                        ? "arrow.triangle.2.circlepath"
                                        : "calendar.badge.plus"
                                )
                                .font(.subheadline.weight(.semibold))

                                Spacer()

                                if calendarSync.isSyncing {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.caption.bold())
                                }
                            }
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .padding(.horizontal, 16)
                            .frame(height: 50)
                        }
                        .buttonStyle(.plain)
                        .disabled(calendarSync.isSyncing)

                        if calendarPermissionNeedsSettings {
                            SettingsDivider()

                            Button {
                                if let url = URL(
                                    string: UIApplication.openSettingsURLString
                                ) {
                                    openURL(url)
                                }
                            } label: {
                                HStack {
                                    Label(
                                        "Open iOS Settings",
                                        systemImage: "gear"
                                    )
                                    .font(.subheadline.weight(.semibold))

                                    Spacer()

                                    Image(systemName: "arrow.up.right")
                                        .font(.caption.bold())
                                }
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 16)
                                .frame(height: 50)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("HOW IT WORKS")

                    ATHLTHUnifiedCard {
                        VStack(alignment: .leading, spacing: 14) {
                            calendarInfoRow(
                                icon: "clock",
                                title: "Planned time",
                                text:
                                    "Workouts with a time use that exact start time and planned duration."
                            )

                            Divider()

                            calendarInfoRow(
                                icon: "calendar.day.timeline.left",
                                title: "No time set",
                                text:
                                    "A workout with “–” uses your default Calendar time (18:00 initially). A time set on the workout always takes priority."
                            )

                            Divider()

                            calendarInfoRow(
                                icon: "arrow.triangle.2.circlepath",
                                title: "Automatic updates",
                                text:
                                    "Adding, editing or removing workouts in the active plan updates the ATHLTH calendar automatically."
                            )

                            Divider()

                            calendarInfoRow(
                                icon: "arrow.right",
                                title: "One-way sync",
                                text:
                                    "ATHLTH remains the source of truth. Changes made directly in Calendar do not edit your training plan."
                            )
                        }
                    }
                }

                if calendarSync.calendarExists {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle("CALENDAR")

                        PremiumSettingsCard {
                            Button(role: .destructive) {
                                showingRemoveConfirmation = true
                            } label: {
                                HStack {
                                    Label(
                                        "Remove ATHLTH Calendar",
                                        systemImage: "trash"
                                    )
                                    .font(.subheadline.weight(.semibold))

                                    Spacer()
                                }
                                .foregroundStyle(.red)
                                .padding(.horizontal, 16)
                                .frame(height: 50)
                            }
                            .buttonStyle(.plain)
                        }

                        Text(
                            "Turning sync off keeps the calendar and its current events. Removing the calendar deletes the dedicated ATHLTH calendar."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 80)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(
            LinearGradient(
                colors: [
                    ATHLTHTheme.canvasTop,
                    Color.white,
                    ATHLTHTheme.canvasBottom
                ],
                startPoint: .top,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            calendarSync.refreshAuthorizationStatus()

            guard session.subscriptionAccess.hasPaidAccess else {
                return
            }

            if calendarSync.isEnabled {
                await syncAllCalendarContent()
            }
        }
        .confirmationDialog(
            "Remove ATHLTH Calendar?",
            isPresented: $showingRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                "Remove Calendar",
                role: .destructive
            ) {
                Task {
                    await calendarSync.removeATHLTHCalendar()
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This removes the dedicated ATHLTH calendar and all workout events synced into it. Your ATHLTH training plan is not changed."
            )
        }
        .alert(
            "Calendar",
            isPresented: Binding(
                get: {
                    calendarSync.errorMessage != nil
                },
                set: { visible in
                    if !visible {
                        calendarSync.errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                calendarSync.errorMessage ??
                "Calendar could not be updated."
            )
        }
    }

    private var defaultCalendarTimeBinding: Binding<Date> {
        Binding(
            get: {
                calendarSync.defaultStartTime
            },
            set: { newTime in
                guard session.subscriptionAccess.hasPaidAccess else {
                    return
                }

                calendarSync.setDefaultStartTime(
                    newTime
                )

                guard calendarSync.isEnabled else {
                    return
                }

                Task {
                    await syncAllCalendarContent()
                }
            }
        )
    }

    private var calendarSyncBinding: Binding<Bool> {
        Binding(
            get: {
                calendarSync.isEnabled
            },
            set: { enabled in
                guard session.subscriptionAccess.hasPaidAccess else {
                    return
                }

                if enabled {
                    Task {
                        await enableCalendarSync()
                    }
                } else {
                    calendarSync.disable()
                }
            }
        )
    }

    private func refreshCalendarSources() async {
        async let eventRefresh: Void =
            communityEvents.refresh()
        async let groupRefresh: Void =
            communityGroups.refreshCalendarContent()

        _ = await (
            eventRefresh,
            groupRefresh
        )
    }

    private func syncAllCalendarContent() async {
        await refreshCalendarSources()

        await calendarSync.sync(
            plan: session.activePlan,
            additionalPlans: session.scheduledPlans.filter {
                !session.isTrainingPlanPaused($0.id) &&
                !session.isTrainingPlanDeactivated($0.id)
            },
            standaloneSessions: session.standalonePlannedSessions,
            communityEvents: communityEvents.events,
            groupEvents: communityGroups.calendarEvents,
            groupEventRSVPs:
                communityGroups.calendarEventRSVPs,
            challenges: challenges.challenges,
            currentUserID: session.profile.userID
        )
    }

    private func enableCalendarSync() async {
        await refreshCalendarSources()

        await calendarSync.enable(
            plan: session.activePlan,
            additionalPlans: session.scheduledPlans.filter {
                !session.isTrainingPlanPaused($0.id) &&
                !session.isTrainingPlanDeactivated($0.id)
            },
            standaloneSessions: session.standalonePlannedSessions,
            communityEvents: communityEvents.events,
            groupEvents: communityGroups.calendarEvents,
            groupEventRSVPs:
                communityGroups.calendarEventRSVPs,
            challenges: challenges.challenges,
            currentUserID: session.profile.userID
        )
    }

    private var calendarPermissionNeedsSettings: Bool {
        switch calendarSync.authorizationStatus {
        case .denied, .restricted:
            return true
        default:
            return false
        }
    }

    private var lastSyncText: String {
        guard let date = calendarSync.lastSyncedAt else {
            return ATHLTHLocalization.choose(
                english: "Never",
                norwegian: "Aldri"
            )
        }

        return date.formatted(
            date: .abbreviated,
            time: .shortened
        )
    }

    private func sectionTitle(
        _ title: String
    ) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .tracking(2.4)
            .foregroundStyle(
                ATHLTHTheme.accentDeep.opacity(0.82)
            )
            .padding(.leading, 16)
    }

    private func statusRow(
        title: String,
        value: String,
        icon: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(width: 32)

            Text(title)
                .font(.subheadline.weight(.medium))

            Spacer()

            Text(value)
                .font(.subheadline)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func calendarInfoRow(
        icon: String,
        title: String,
        text: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.accent)
                .frame(width: 32, height: 32)
                .background(
                    ATHLTHTheme.accentSoft,
                    in: RoundedRectangle(
                        cornerRadius: 10,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
            }

            Spacer()
        }
    }
}

private struct PremiumSettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(
            LinearGradient(
                colors: [
                    Color.white,
                    ATHLTHTheme.cardWarm.opacity(0.27)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 23, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .stroke(ATHLTHTheme.border.opacity(0.75), lineWidth: 0.8)
        }
        .shadow(
            color: ATHLTHTheme.accentDeep.opacity(0.04),
            radius: 15,
            x: 0, y: 7
        )
    }
}

private struct PremiumSettingsRow<Trailing: View>: View {
    let icon: String
    var iconTint: Color = ATHLTHTheme.primaryText
    var iconBackground: Color = ATHLTHTheme.accentSoft
    let title: String
    let subtitle: String?
    var titleColor: Color = ATHLTHTheme.primaryText
    @ViewBuilder let trailing: Trailing

    init(
        icon: String,
        iconTint: Color = ATHLTHTheme.primaryText,
        iconBackground: Color = ATHLTHTheme.accentSoft,
        title: String,
        subtitle: String? = nil,
        titleColor: Color = ATHLTHTheme.primaryText,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.icon = icon
        self.iconTint = iconTint
        self.iconBackground = iconBackground
        self.title = title
        self.subtitle = subtitle
        self.titleColor = titleColor
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(iconTint)
                .frame(width: 44, height: 44)
                .background(
                    iconBackground,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(
                    LocalizedStringKey(title)
                )
                    .font(.system(size: 16.5, weight: .medium))
                    .foregroundStyle(titleColor)

                if let subtitle {
                    Text(
                        LocalizedStringKey(
                            subtitle
                        )
                    )
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 12)

            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(ATHLTHTheme.divider)
            .frame(height: 0.5)
            .padding(.leading, 74)
            .padding(.trailing, 16)
    }
}

private struct ATHLTHTrainingDeviceSettingsView: View {
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("APPLE WATCH")
                        .font(.caption.weight(.semibold))
                        .tracking(2.4)
                        .foregroundStyle(ATHLTHTheme.accentDeep.opacity(0.82))
                        .padding(.leading, 16)

                    PremiumSettingsCard {
                        VStack(alignment: .leading, spacing: 0) {
                            detailRow(
                                title: "Connection",
                                value: watchConnectionTitle,
                                icon: "applewatch"
                            )

                            SettingsDivider()

                            detailRow(
                                title: "Watch app",
                                value: watchAppTitle,
                                icon: watchConnection.isReady
                                    ? "checkmark.circle.fill"
                                    : "app.badge"
                            )

                            SettingsDivider()

                            VStack(alignment: .leading, spacing: 12) {
                                Text(watchSetupDetail)
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                                    .fixedSize(horizontal: false, vertical: true)

                                NavigationLink {
                                    AppleWatchConnectionView()
                                } label: {
                                    HStack {
                                        Label(
                                            watchConnection.isReady
                                                ? "Open Apple Watch details"
                                                : watchConnection.state == .appNotInstalled
                                                    ? "Install Watch app"
                                                    : "Open setup",
                                            systemImage: "applewatch"
                                        )
                                        .font(.subheadline.weight(.semibold))

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.bold))
                                    }
                                    .foregroundStyle(ATHLTHTheme.accentDeep)
                                    .padding(.horizontal, 14)
                                    .frame(height: 46)
                                    .background(
                                        ATHLTHTheme.accentSoft,
                                        in: RoundedRectangle(
                                            cornerRadius: 14,
                                            style: .continuous
                                        )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(16)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("HOW WORKOUT RECORDING WORKS")
                        .font(.caption.weight(.semibold))
                        .tracking(2.4)
                        .foregroundStyle(ATHLTHTheme.accentDeep.opacity(0.82))
                        .padding(.leading, 16)

                    PremiumSettingsCard {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: "figure.run.circle")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                                .frame(width: 44, height: 44)
                                .background(
                                    ATHLTHTheme.accentSoft,
                                    in: RoundedRectangle(
                                        cornerRadius: 14,
                                        style: .continuous
                                    )
                                )

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Choose when you start")
                                    .font(.system(size: 16.5, weight: .semibold))
                                    .foregroundStyle(ATHLTHTheme.primaryText)

                                Text(
                                    "iPhone and Apple Watch are chosen for each workout when you press Start. This screen only manages your Watch connection."
                                )
                                .font(.caption)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                                .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 8)
                        }
                        .padding(16)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("OTHER WATCHES")
                        .font(.caption.weight(.semibold))
                        .tracking(2.4)
                        .foregroundStyle(ATHLTHTheme.accentDeep.opacity(0.82))
                        .padding(.leading, 16)

                    PremiumSettingsCard {
                        HStack(spacing: 14) {
                            Image(systemName: "watch.analog")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(ATHLTHTheme.mutedText)
                                .frame(width: 44, height: 44)
                                .background(
                                    Color.primary.opacity(0.035),
                                    in: RoundedRectangle(
                                        cornerRadius: 14,
                                        style: .continuous
                                    )
                                )

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text("Garmin")
                                        .font(.system(size: 16.5, weight: .semibold))
                                        .foregroundStyle(ATHLTHTheme.primaryText)

                                    Text("COMING SOON")
                                        .font(.system(size: 8, weight: .bold))
                                        .tracking(0.7)
                                        .foregroundStyle(ATHLTHTheme.mutedText)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 4)
                                        .background(
                                            Color.primary.opacity(0.045),
                                            in: Capsule()
                                        )
                                }

                                Text("Garmin Connect support is planned and will appear here when it is ready.")
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                            }

                            Spacer()
                        }
                        .padding(16)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 48)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(
            LinearGradient(
                colors: [
                    ATHLTHTheme.canvasTop,
                    Color.white,
                    ATHLTHTheme.canvasBottom
                ],
                startPoint: .top,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Watch")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            watchConnection.connect()
        }
    }

    private func detailRow(
        title: String,
        value: String,
        icon: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(width: 32)

            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ATHLTHTheme.primaryText)

            Spacer()

            Text(value)
                .font(.subheadline)
                .foregroundStyle(
                    value == "Not installed" ||
                    value == "Not paired" ||
                    value == "Unavailable"
                        ? Color.orange
                        : ATHLTHTheme.mutedText
                )
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var watchConnectionTitle: String {
        switch watchConnection.state {
        case .ready, .appNotInstalled:
            return ATHLTHLocalization.choose(
                english: "Paired",
                norwegian: "Sammenkoblet"
            )
        case .notPaired:
            return ATHLTHLocalization.choose(
                english: "Not paired",
                norwegian: "Ikke sammenkoblet"
            )
        case .checking:
            return ATHLTHLocalization.choose(
                english: "Checking…",
                norwegian: "Sjekker…"
            )
        case .unsupported:
            return ATHLTHLocalization.choose(
                english: "Unavailable",
                norwegian: "Ikke tilgjengelig"
            )
        }
    }

    private var watchAppTitle: String {
        switch watchConnection.state {
        case .ready:
            return ATHLTHLocalization.choose(
                english: "Installed",
                norwegian: "Installert"
            )
        case .appNotInstalled:
            return ATHLTHLocalization.choose(
                english: "Not installed",
                norwegian: "Ikke installert"
            )
        case .notPaired, .unsupported:
            return ATHLTHLocalization.choose(
                english: "Unavailable",
                norwegian: "Ikke tilgjengelig"
            )
        case .checking:
            return ATHLTHLocalization.choose(
                english: "Checking…",
                norwegian: "Sjekker…"
            )
        }
    }

    private var watchSetupDetail: String {
        switch watchConnection.state {
        case .ready:
            return ATHLTHLocalization.choose(
                english: "ATHLTH Watch is ready for live workouts, routes and HealthKit sync.",
                norwegian: "ATHLTH på Apple Watch er klar for liveøkter, ruter og HealthKit-synkronisering."
            )
        case .appNotInstalled:
            return ATHLTHLocalization.choose(
                english: "Install the ATHLTH Watch app to start workouts, sync routes and use live tracking.",
                norwegian: "Installer ATHLTH på Apple Watch for å starte økter, synkronisere ruter og bruke live-sporing."
            )
        case .notPaired:
            return ATHLTHLocalization.choose(
                english: "Pair an Apple Watch with this iPhone first, then return here to finish ATHLTH setup.",
                norwegian: "Koble først en Apple Watch til denne iPhonen, og gå deretter tilbake hit for å fullføre ATHLTH-oppsettet."
            )
        case .checking:
            return ATHLTHLocalization.choose(
                english: "ATHLTH is checking the paired Apple Watch and app installation.",
                norwegian: "ATHLTH sjekker den sammenkoblede Apple Watch-en og appinstallasjonen."
            )
        case .unsupported:
            return ATHLTHLocalization.choose(
                english: "Apple Watch connectivity is unavailable on this device.",
                norwegian: "Apple Watch-tilkobling er ikke tilgjengelig på denne enheten."
            )
        }
    }
}

private struct GarminConnectionSetupView: View {
    var body: some View {
        Form {
            Section("Garmin Connect") {
                Label("Garmin integration is coming soon", systemImage: "watch.analog")
                    .font(.headline)

                Text(
                    "When Garmin access is enabled, this screen will guide you through account authorization, permissions and the data ATHLTH can sync."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Section("Planned sync") {
                Label("Workouts and routes", systemImage: "figure.run")
                Label("Heart rate and HRV", systemImage: "heart.fill")
                Label("Sleep and recovery", systemImage: "moon.fill")
                Label("Steps and activity", systemImage: "figure.walk")
            }
        }
        .navigationTitle("Garmin Setup")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ATHLTHTrainingSettingsView: View {
    @EnvironmentObject private var settings: AppSettingsStore

    var body: some View {
        Form {
            Section {
                Picker(
                    ATHLTHLocalization.choose(
                        english: "Default workout setup",
                        norwegian: "Standard oppsett"
                    ),
                    selection:
                        $settings
                            .workoutSetupPreference
                ) {
                    ForEach(
                        WorkoutSetupPreference
                            .allCases
                    ) { preference in
                        Text(preference.title)
                            .tag(preference)
                    }
                }

                Text(
                    settings
                        .workoutSetupPreference
                        .subtitle
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text(
                    ATHLTHLocalization.choose(
                        english: "Workout setup",
                        norwegian: "Oppsett av økt"
                    )
                )
            } footer: {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "This controls the starting mode only. You can still switch between Basic and Advanced for an individual workout without changing the preference.",
                        norwegian:
                            "Dette styrer bare hvilken modus økten åpner i. Du kan fortsatt bytte mellom Basic og Avansert for en enkeltøkt uten å endre standardvalget."
                    )
                )
            }

            Section {
                Toggle(
                    ATHLTHLocalization.choose(
                        english: "Auto-pause outdoor workouts",
                        norwegian: "Auto-pause utendørs trening"
                    ),
                    isOn:
                        $settings
                            .autoPauseOutdoorWorkouts
                )

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "This is the default for outdoor running and walking. Advanced setup on an individual workout can use this default or override it.",
                        norwegian:
                            "Dette er standarden for utendørs løping og gåing. Avansert oppsett på en enkelt økt kan bruke standarden eller overstyre den."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text(
                    ATHLTHLocalization.choose(
                        english: "Outdoor workouts",
                        norwegian: "Utendørsøkter"
                    )
                )
            }

            Section {
                NavigationLink {
                    ATHLTHWorkoutGuidanceSettingsView()
                } label: {
                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text("Workout Guidance")
                            .font(
                                .subheadline
                                    .weight(.semibold)
                            )

                        Text(
                            "Audio Coach, Route Guardian, Ghost Updates and alert priority"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                NavigationLink {
                    ATHLTHRouteGuardianSettingsView()
                } label: {
                    HStack {
                        Text("Route Guardian")
                        Spacer()
                        Text(
                            settings.routeAlertsEnabled
                                ? "\(Int(settings.routeAlertDeviationMeters.rounded())) m"
                                : "Off"
                        )
                        .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Guidance & alerts")
            } footer: {
                Text(
                    "Open a guidance category to adjust it. Training no longer expands all route and audio controls into one long page."
                )
            }

            Section("Activity sharing") {
                Toggle(
                    "Share completed workouts by default",
                    isOn: $settings.autoPublishCompletedWorkouts
                )
                .onChange(
                    of: settings.autoPublishCompletedWorkouts
                ) { _, enabled in
                    settings.workoutSharingChoiceCompleted = true

                    if enabled &&
                        settings.defaultActivityVisibility == .privateOnly {
                        settings.defaultActivityVisibility = .friends
                    }
                }

                if settings.autoPublishCompletedWorkouts {
                    Picker(
                        "Automatic visibility",
                        selection: $settings.defaultActivityVisibility
                    ) {
                        ForEach(ProfileVisibility.allCases) { visibility in
                            Text(visibility.title).tag(visibility)
                        }
                    }

                    Text(
                        "ATHLTH preselects your sharing visibility, but Workout Complete always opens before anything is published."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text(
                        "Completed workouts default to private. Workout Complete still opens after every session so you can choose what to share."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Training")
        .navigationBarTitleDisplayMode(.inline)
    }

}

private struct ATHLTHAchievementSettingsView:
    View
{
    @EnvironmentObject private var settings:
        AppSettingsStore
    @Environment(
        \.accessibilityReduceMotion
    ) private var reduceMotion
    @Environment(
        \.accessibilityReduceTransparency
    ) private var reduceTransparency

    var body: some View {
        Form {
            Section {
                Picker(
                    ATHLTHLocalization.choose(
                        english:
                            "Visual effects",
                        norwegian:
                            "Visuelle effekter"
                    ),
                    selection:
                        $settings
                            .achievementEffects
                ) {
                    ForEach(
                        AchievementEffectPreference
                            .allCases
                    ) {
                        preference in
                        Text(
                            preference.title
                        )
                        .tag(preference)
                    }
                }
                .pickerStyle(
                    .segmented
                )

                Text(
                    settings
                        .achievementEffects
                        .subtitle
                )
                .font(.caption)
                .foregroundStyle(
                    .secondary
                )
            } header: {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Achievement effects",
                        norwegian:
                            "Achievement-effekter"
                    )
                )
            } footer: {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "iOS Reduce Motion and Reduce Transparency always take priority over this setting.",
                        norwegian:
                            "iOS Reduser bevegelse og Reduser gjennomsiktighet har alltid prioritet over denne innstillingen."
                    )
                )
            }

            Section(
                ATHLTHLocalization.choose(
                    english:
                        "Unlock feedback",
                    norwegian:
                        "Unlock-feedback"
                )
            ) {
                Toggle(
                    ATHLTHLocalization.choose(
                        english:
                            "Unlock sounds",
                        norwegian:
                            "Unlock-lyder"
                    ),
                    isOn:
                        $settings
                            .achievementUnlockSoundsEnabled
                )

                Toggle(
                    ATHLTHLocalization.choose(
                        english:
                            "Unlock haptics",
                        norwegian:
                            "Unlock-haptikk"
                    ),
                    isOn:
                        $settings
                            .achievementUnlockHapticsEnabled
                )
            }

            if reduceMotion ||
               reduceTransparency {
                Section(
                    ATHLTHLocalization.choose(
                        english:
                            "Accessibility",
                        norwegian:
                            "Tilgjengelighet"
                    )
                ) {
                    if reduceMotion {
                        Label(
                            ATHLTHLocalization.choose(
                                english:
                                    "Reduce Motion is active. Tilt, particle movement and large reveal transitions are reduced.",
                                norwegian:
                                    "Reduser bevegelse er aktivert. Tilt, partikkelbevegelse og store reveal-animasjoner reduseres."
                            ),
                            systemImage:
                                "figure.walk.motion"
                        )
                    }

                    if reduceTransparency {
                        Label(
                            ATHLTHLocalization.choose(
                                english:
                                    "Reduce Transparency is active. Holographic and glass effects use solid alternatives.",
                                norwegian:
                                    "Reduser gjennomsiktighet er aktivert. Holografiske effekter og glassflater bruker solide alternativer."
                            ),
                            systemImage:
                                "circle.lefthalf.filled"
                        )
                    }
                }
                .font(.caption)
            }
        }
        .navigationTitle(
            ATHLTHLocalization.choose(
                english:
                    "Achievements",
                norwegian:
                    "Achievements"
            )
        )
        .navigationBarTitleDisplayMode(
            .inline
        )
    }
}

private struct ATHLTHNotificationSettingsView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var notifications: ATHLTHNotificationStore
    @ObservedObject private var push =
        APNsPushManager.shared

    var body: some View {
        Form {
            Section("System permission") {
                LabeledContent("iOS notifications", value: authorizationTitle)

                switch notifications.authorizationStatus {
                case .notDetermined:
                    Button("Allow Notifications") {
                        Task {
                            await notifications.requestSystemNotificationPermission()
                        }
                    }
                case .denied:
                    Button("Open iOS Notification Settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            openURL(url)
                        }
                    }
                default:
                    EmptyView()
                }
            }

            Section(
                ATHLTHLocalization.choose(
                    english: "Push status",
                    norwegian: "Push-status"
                )
            ) {
                LabeledContent(
                    ATHLTHLocalization.choose(
                        english: "APNs token",
                        norwegian: "APNs-token"
                    ),
                    value:
                        push.hasDeviceToken
                            ? ATHLTHLocalization.choose(
                                english: "Received",
                                norwegian: "Mottatt"
                            )
                            : ATHLTHLocalization.choose(
                                english: "Missing",
                                norwegian: "Mangler"
                            )
                )

                LabeledContent(
                    ATHLTHLocalization.choose(
                        english: "iOS registration",
                        norwegian: "iOS-registrering"
                    ),
                    value:
                        push.isSystemRegistered
                            ? ATHLTHLocalization.choose(
                                english: "Registered",
                                norwegian: "Registrert"
                            )
                            : ATHLTHLocalization.choose(
                                english: "Not registered",
                                norwegian: "Ikke registrert"
                            )
                )

                LabeledContent(
                    ATHLTHLocalization.choose(
                        english: "ATHLTH backend",
                        norwegian: "ATHLTH-backend"
                    ),
                    value:
                        push.isRegisteredWithBackend
                            ? ATHLTHLocalization.choose(
                                english: "Registered",
                                norwegian: "Registrert"
                            )
                            : ATHLTHLocalization.choose(
                                english: "Missing",
                                norwegian: "Mangler"
                            )
                )

                LabeledContent(
                    ATHLTHLocalization.choose(
                        english: "APNs environment",
                        norwegian: "APNs-miljø"
                    ),
                    value: push.environmentLabel
                )

                if let error =
                        push.lastRegistrationError,
                   !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button(
                    ATHLTHLocalization.choose(
                        english: "Repair push registration",
                        norwegian: "Reparer push-registrering"
                    )
                ) {
                    Task {
                        await push
                            .repairRegistrationIfAuthorized()
                        await push
                            .refreshBackendRegistrationStatus()
                    }
                }
            }

            Section(ATHLTHLocalization.choose(
                english: "Daily Insights check-in", norwegian: "Daglig innsjekk")) {
                Toggle(isOn: $settings.dailyCheckInRemindersEnabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ATHLTHLocalization.choose(
                            english: "Daily check-in reminder",
                            norwegian: "Daglig påminnelse om innsjekk"))
                        Text(ATHLTHLocalization.choose(
                            english: "One reminder in Activity plus a local iPhone notification at 09:00 if you have not checked in. Turn off here at any time.",
                            norwegian: "Én påminnelse i Aktivitet og et lokalt iPhone-varsel kl. 09.00 hvis du ikke har sjekket inn. Kan slås av her."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if settings.dailyCheckInRemindersEnabled {
                    if notifications.authorizationStatus == .notDetermined {
                        Button(ATHLTHLocalization.choose(
                            english: "Enable iPhone notifications",
                            norwegian: "Aktiver iPhone-varsler"
                        )) {
                            Task {
                                await notifications.requestSystemNotificationPermission()
                            }
                        }
                    } else if notifications.authorizationStatus == .denied {
                        Text(ATHLTHLocalization.choose(
                            english: "iPhone notifications are disabled for ATHLTH in iOS Settings. The reminder will still appear in Activity.",
                            norwegian: "iPhone-varsler for ATHLTH er deaktivert i iOS-innstillinger. Påminnelsen vises fortsatt i Aktivitet."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Section("ATHLTH alerts") {
                Toggle("Workout updates", isOn: $settings.workoutRemindersEnabled)
                Toggle("Friend activity", isOn: $settings.friendActivityNotificationsEnabled)
                Toggle("Challenges", isOn: $settings.challengeNotificationsEnabled)
                Toggle("Messages", isOn: $settings.messageNotificationsEnabled)
                Toggle("Mentions", isOn: $settings.mentionNotificationsEnabled)

                Text("These switches control system alerts. Events can still appear in the ATHLTH notification center so you do not lose your activity history.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: notifications.authorizationStatus) { _, _ in
            notifications.reconcileDailyCheckIn(
                enabled: settings.dailyCheckInRemindersEnabled,
                accountID: session.profile.userID,
                completed: RecoverySorenessStore().hasTodayCheckIn
            )
        }
        .task {
            await notifications.refreshAuthorizationStatus()
            await notifications.reconcileSystemPreferences()
            await push
                .repairRegistrationIfAuthorized()
            await push
                .refreshBackendRegistrationStatus()
        }
        .onChange(of: settings.challengeNotificationsEnabled) { _, _ in
            Task {
                await notifications.reconcileSystemPreferences()
            }
        }
    }

    private var authorizationTitle: String {
        switch notifications.authorizationStatus {
        case .notDetermined:
            return ATHLTHLocalization.choose(
                english: "Not requested",
                norwegian: "Ikke forespurt"
            )
        case .denied:
            return ATHLTHLocalization.choose(
                english: "Disabled",
                norwegian: "Deaktivert"
            )
        case .authorized:
            return ATHLTHLocalization.choose(
                english: "Allowed",
                norwegian: "Tillatt"
            )
        case .provisional:
            return ATHLTHLocalization.choose(
                english: "Provisional",
                norwegian: "Midlertidig tillatt"
            )
        case .ephemeral:
            return ATHLTHLocalization.choose(
                english: "Temporary",
                norwegian: "Midlertidig"
            )
        @unknown default:
            return ATHLTHLocalization.choose(
                english: "Unknown",
                norwegian: "Ukjent"
            )
        }
    }
}
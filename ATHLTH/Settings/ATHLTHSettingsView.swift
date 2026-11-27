import Foundation
import AVFoundation
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
        case .privacy: return ATHLTHLocalization.choose(english: "Sharing, privacy and legal information", norwegian: "Deling, personvern og juridisk informasjon")
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
        case .health: return "health helse apple health watch klokke sync synkronisering import calendar kalender spotify garmin airpods headphones hodetelefoner puls home assistant tilkobling connections"
        case .training: return "training trening workout styrke løping løp guidance veiledning audio coach ghost notifications varsler alarm achievements trophies medalje exercise data repdb øvelsesdatabase"
        case .account: return "profile profil account konto health helseprofil sign-in login innlogging password passord security sikkerhet data privacy pet pets kjæledyr hund katt dyr"
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
    #if ATHLTH_GARMIN_PERSONAL && (DEBUG || ATHLTH_GARMIN_INTERNAL_TEST)
    @ObservedObject private var garminConnectionStore = GarminPersonalLocalStore.shared
    #endif

    @State private var showingMembership = false
    @State private var membershipRestoreMessage: String?
    @State private var healthRequestInProgress = false
    @State private var showingAppleHealthPauseConfirmation = false
    @State private var settingsSearchText = ""
    @State private var airPodsRoute = ATHLTHAirPodsRoute.current()
    @AppStorage("athlth.airpods.recognizedAudioRoute") private var recognizedAirPodsRoute = ""

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
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        // Keep the enclosing iPad Studio sidebar and its navigation active
        // while the user opens nested settings and widget pages.
        .toolbar(
            UIDevice.current.userInterfaceIdiom == .pad ? .visible : .hidden,
            for: .navigationBar
        )
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
               !health.hasCompletedHealthReadThisLaunch,
               !health.shouldDeferAutomaticHealthWork,
               !health.isRefreshing {
                await health.refreshIfStale(maxAge: 90)
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

    @ViewBuilder
    private var appSettingsSection: some View {
        settingsSection("App") {
            PremiumSettingsCard {
                NavigationLink {
                    ATHLTHPremiumSettingsChoices(
                        title: ATHLTHLocalization.choose(english: "Measurements", norwegian: "Måleenheter"),
                        subtitle: ATHLTHLocalization.choose(english: "Choose units throughout ATHLTH.", norwegian: "Velg måleenheter i hele ATHLTH."),
                        options: MeasurementPreference.allCases,
                        selection: $settings.measurementPreference,
                        optionTitle: { $0.title },
                        optionDetail: { "\($0.distanceUnit) · \($0.runningSpeedUnit) · \($0.weightUnit) · \($0.temperatureUnit)" }
                    )
                } label: {
                    PremiumSettingsRow(
                        icon: "ruler",
                        title: ATHLTHLocalization.choose(english: "Measurements", norwegian: "Måleenheter"),
                        subtitle: ATHLTHLocalization.choose(english: "Distance, speed, weight and temperature", norwegian: "Distanse, hastighet, vekt og temperatur")
                    ) { settingsChoiceValue(settings.measurementPreference.title) }
                }
                .buttonStyle(.plain)
                SettingsDivider()

                NavigationLink {
                    ATHLTHPremiumSettingsChoices(
                        title: ATHLTHLocalization.choose(english: "Time format", norwegian: "Tidsformat"),
                        subtitle: ATHLTHLocalization.choose(english: "Used for times throughout ATHLTH", norwegian: "Brukes for klokkeslett i hele ATHLTH"),
                        options: TimeFormatPreference.allCases,
                        selection: $settings.timeFormatPreference,
                        optionTitle: { $0.title },
                        optionDetail: { $0.example }
                    )
                } label: {
                    PremiumSettingsRow(
                        icon: "clock",
                        title: ATHLTHLocalization.choose(english: "Time format", norwegian: "Tidsformat"),
                        subtitle: ATHLTHLocalization.choose(english: "Used for times throughout ATHLTH", norwegian: "Brukes for klokkeslett i hele ATHLTH")
                    ) { settingsChoiceValue(settings.timeFormatPreference.title) }
                }
                .buttonStyle(.plain)
                SettingsDivider()

                NavigationLink {
                    ATHLTHPremiumSettingsChoices(
                        title: ATHLTHLocalization.choose(english: "Language", norwegian: "Språk"),
                        subtitle: ATHLTHLocalization.choose(english: "Choose the app language", norwegian: "Velg appens visningsspråk"),
                        options: AppLanguage.currentlySupported,
                        selection: $settings.language,
                        optionTitle: { $0.title },
                        optionDetail: { _ in "" }
                    )
                } label: {
                    PremiumSettingsRow(
                        icon: "globe",
                        title: ATHLTHLocalization.choose(english: "Language", norwegian: "Språk"),
                        subtitle: ATHLTHLocalization.choose(english: "Choose English or Norwegian", norwegian: "Velg engelsk eller norsk")
                    ) { settingsChoiceValue(settings.language.title) }
                }
                .buttonStyle(.plain)
                SettingsDivider()

                NavigationLink {
                    ATHLTHWidgetsAndSurfacesSettingsView()
                } label: {
                    PremiumSettingsRow(
                        icon: "rectangle.grid.2x2",
                        title: ATHLTHLocalization.choose(english: "Widgets & Surfaces", norwegian: "Widgeter og flater"),
                        subtitle: ATHLTHLocalization.choose(english: "Home Screen, Live Activities, Siri and Lock Screen", norwegian: "Hjemskjerm, Live Activities, Siri og låseskjerm")
                    ) {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.72))
                    }
                }
                .buttonStyle(.plain)
            }
        }
        settingsSection("About") {
            PremiumSettingsCard {
                Link(destination: URL(string: "https://repdb.co")!) {
                    PremiumSettingsRow(icon: "book.closed", title: "RepDB",
                        subtitle: ATHLTHLocalization.choose(english: "Exercise catalog provider", norwegian: "Leverandør av øvelsesbibliotek")) {
                        Image(systemName: "arrow.up.right").foregroundStyle(ATHLTHTheme.mutedText)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func settingsChoiceValue(_ value: String) -> some View {
        HStack(spacing: 8) {
            Text(value).foregroundStyle(ATHLTHTheme.mutedText)
            Image(systemName: "chevron.right")
                .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.72))
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
                            SettingsDivider()
                            NavigationLink {
                                ATHLTHPetsSettingsView()
                            } label: {
                                PremiumSettingsRow(
                                    icon: "pawprint.fill",
                                    title: ATHLTHLocalization.choose(
                                        english: "My pets", norwegian: "Mine kjæledyr"),
                                    subtitle: ATHLTHLocalization.choose(
                                        english: "Companions, profiles and activity history",
                                        norwegian: "Turkamerater, profiler og aktivitetshistorikk")
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

                        if health.hasRequestedAuthorization &&
                           settings.appleHealthIntegrationEnabled {
                            SettingsDivider()

                            Button {
                                reviewAppleHealthPermissions()
                            } label: {
                                PremiumSettingsRow(
                                    icon: "checkmark.shield",
                                    title: ATHLTHLocalization.choose(
                                        english: "Review Health access",
                                        norwegian: "Oppdater helsetilgang"
                                    ),
                                    subtitle: ATHLTHLocalization.choose(
                                        english: "Ask iOS to review newly added data types, including cardio recovery",
                                        norwegian: "Be iOS om tilgang til nye målinger, blant annet pulsfall"
                                    )
                                ) {
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(ATHLTHTheme.mutedText)
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

    private enum ConnectionItem: String, CaseIterable, Identifiable {
        case health, calendar, watch, airPods, garmin, spotify, homeAssistant
        var id: String { rawValue }
    }

    private var canUsePersonalGarmin: Bool {
        #if ATHLTH_GARMIN_PERSONAL && (DEBUG || ATHLTH_GARMIN_INTERNAL_TEST)
        session.signedIn && !session.previewModeEnabled && session.currentRole.canAccessControlCenter
        #else
        false
        #endif
    }

    private func connectionIsActive(_ item: ConnectionItem) -> Bool {
        switch item {
        case .health: return HealthKitManager.isConfiguredConnection(
            enabled: settings.appleHealthIntegrationEnabled,
            available: health.healthDataAvailable,
            requested: health.hasRequestedAuthorization
        )
        case .calendar: return session.subscriptionAccess.hasPaidAccess && calendarSync.isEnabled && calendarSync.hasFullAccess
        case .watch: return !ATHLTHDeviceRole.isIPad && watchConnection.isReady
        case .airPods: return airPodsRoute.isRecognized(rememberedUID: recognizedAirPodsRoute)
        case .spotify: return spotify.isConnected
        case .homeAssistant: return homeAssistant.isConnected
        case .garmin:
            #if ATHLTH_GARMIN_PERSONAL && (DEBUG || ATHLTH_GARMIN_INTERNAL_TEST)
            return canUsePersonalGarmin &&
                garminConnectionStore.isConnected(to: session.profile.userID)
            #else
            return false
            #endif
        }
    }

    @ViewBuilder
    private var connectionsSettingsSection: some View {
        let active = ConnectionItem.allCases.filter { connectionIsActive($0) }
        let available = ConnectionItem.allCases.filter { !connectionIsActive($0) }
        Group {
            connectionGroup("Active connections", items: active)
            connectionGroup("Available connections", items: available)
        }
        .onAppear { airPodsRoute = ATHLTHAirPodsRoute.current() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification).receive(on: RunLoop.main)) { _ in
            airPodsRoute = ATHLTHAirPodsRoute.current()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            airPodsRoute = ATHLTHAirPodsRoute.current()
        }
    }

    private func connectionGroup(_ title: String, items: [ConnectionItem]) -> some View {
        settingsSection(title) {
            PremiumSettingsCard {
                if items.isEmpty {
                    Text(ATHLTHLocalization.choose(
                        english: "None", norwegian: "Ingen"))
                        .font(.subheadline).foregroundStyle(ATHLTHTheme.mutedText)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                } else {
                    ForEach(items) { item in
                        connectionRow(item)
                        if item != items.last { SettingsDivider() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func connectionRow(_ item: ConnectionItem) -> some View {
        switch item {
        case .health:
            NavigationLink {
                connectionDestination(.health)
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
                            : !health.healthDataAvailable
                                ? "Unavailable"
                                : !health.hasRequestedAuthorization
                                    ? "Connect"
                                    : (healthSyncStateTitle == ATHLTHLocalization.choose(english: "Synced", norwegian: "Synkronisert") ? ATHLTHLocalization.choose(english: "Connected", norwegian: "Tilkoblet") : healthSyncStateTitle),
                        showChevron: true,
                        loading: healthRequestInProgress || health.isRefreshing
                    )
                }
            }
            .buttonStyle(.plain)
        case .calendar:
            if session.subscriptionAccess.hasPaidAccess {
                NavigationLink {
                connectionDestination(.calendar)
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
                                : calendarSync.isEnabled && calendarSync.hasFullAccess
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
        case .watch:
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
                connectionDestination(.watch)
            } label: {
                    PremiumSettingsRow(
                        icon: "applewatch",
                        iconTint: ATHLTHTheme.primaryText,
                        title: "Apple Watch",
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
        case .airPods:
            NavigationLink {
                connectionDestination(.airPods)
            } label: {
                PremiumSettingsRow(
                    icon: "airpodspro",
                    iconTint: ATHLTHTheme.accentDeep,
                    title: "AirPods",
                    subtitle: connectionIsActive(.airPods)
                        ? (airPodsRoute.name ?? "AirPods")
                        : ATHLTHLocalization.choose(english: "Audio and compatible training sensors", norwegian: "Lyd og kompatible treningssensorer")
                ) {
                    connectionTrailing(
                        connectionIsActive(.airPods)
                            ? ATHLTHLocalization.choose(english: "Audio selected", norwegian: "Valgt lydutgang")
                            : ATHLTHLocalization.choose(english: "Set up", norwegian: "Konfigurer"),
                        showChevron: true
                    )
                }
            }
            .buttonStyle(.plain)
        case .garmin:
            NavigationLink {
                connectionDestination(.garmin)
            } label: {
                PremiumSettingsRow(
                    icon: "watch.analog",
                    iconTint: ATHLTHTheme.accentDeep,
                    iconBackground: ATHLTHTheme.premiumGoldSoft,
                    title: "Garmin",
                    subtitle: canUsePersonalGarmin
                        ? ATHLTHLocalization.choose(english: "Developer testing · connection and status", norwegian: "Utviklertest · tilkobling og status")
                        : ATHLTHLocalization.choose(english: "Garmin Connect integration", norwegian: "Garmin Connect-integrasjon")
                ) {
                    connectionTrailing(
                        canUsePersonalGarmin
                            ? (connectionIsActive(.garmin) ? ATHLTHLocalization.choose(english: "Connected", norwegian: "Tilkoblet") : ATHLTHLocalization.choose(english: "Test", norwegian: "Test"))
                            : ATHLTHLocalization.choose(english: "Coming soon", norwegian: "Kommer snart"),
                        showChevron: true
                    )
                }
            }
            .buttonStyle(.plain)
        case .spotify:
            NavigationLink {
                connectionDestination(.spotify)
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
        case .homeAssistant:
            NavigationLink {
                connectionDestination(.homeAssistant)
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

    @ViewBuilder
    private func connectionDestination(_ item: ConnectionItem) -> some View {
        switch item {
        case .health: appleHealthSettingsPage
        case .calendar: AppleCalendarSettingsView()
        case .watch: AppleWatchConnectionView()
        case .airPods: ATHLTHAirPodsSettingsView()
        case .spotify: SpotifySettingsView()
        case .homeAssistant: HomeAssistantSettingsView()
        case .garmin:
                #if ATHLTH_GARMIN_PERSONAL && (DEBUG || ATHLTH_GARMIN_INTERNAL_TEST)
                if canUsePersonalGarmin {
                    GarminPersonalSettingsView(accountID: session.profile.userID)
                        .id(session.profile.userID)
                } else {
                    GarminConnectionSetupView()
                }
                #else
                GarminConnectionSetupView()
                #endif

        }
    }

    private var trainingSettingsSection: some View {
        settingsSection("Preferences") {
            PremiumSettingsCard {
                NavigationLink { ATHLTHTrainingSettingsView() } label: {
                    trainingPreferenceRow("figure.strengthtraining.traditional", "Training", "Trening",
                                          "Workout setup, start time, equipment and sharing", "Øktoppsett, starttid, utstyr og deling")
                }
                .buttonStyle(.plain)
                SettingsDivider()
                NavigationLink { TrainingDataSettingsView() } label: {
                    trainingPreferenceRow("arrow.triangle.2.circlepath", "Training data & sync", "Treningsdata og synkronisering",
                                          "Account sync and recovery", "Kontosynkronisering og gjenoppretting")
                }
                .buttonStyle(.plain)
                SettingsDivider()
                NavigationLink { ATHLTHWorkoutGuidanceSettingsView() } label: {
                    trainingPreferenceRow("waveform.and.mic", "Workout guidance", "Øktveiledning",
                                          "Audio Coach · Ghost Race · Navigation", "Audio coach · Ghost race · Navigasjon")
                }
                .buttonStyle(.plain)
                SettingsDivider()
                NavigationLink { ATHLTHNotificationSettingsView() } label: {
                    trainingPreferenceRow("bell", "Notifications", "Varsler",
                                          "Reminders, training and community", "Påminnelser, trening og fellesskap")
                }
                .buttonStyle(.plain)
                SettingsDivider()
                NavigationLink { ATHLTHAchievementSettingsView() } label: {
                    trainingPreferenceRow("medal.fill", "Achievements", "Prestasjoner",
                                          "Animations, sound and haptics", "Animasjoner, lyd og vibrasjon")
                }
                .buttonStyle(.plain)
            }
        }

    }

    private func trainingPreferenceRow(_ icon: String, _ en: String, _ no: String,
                                       _ detailEn: String, _ detailNo: String) -> some View {
        PremiumSettingsRow(icon: icon, iconTint: ATHLTHTheme.accentDeep,
                           iconBackground: ATHLTHTheme.premiumGoldSoft,
                           title: ATHLTHLocalization.choose(english: en, norwegian: no),
                           subtitle: ATHLTHLocalization.choose(english: detailEn, norwegian: detailNo)) {
            Image(systemName: "chevron.right").foregroundStyle(ATHLTHTheme.mutedText)
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
                    ATHLTHPrivacyCenterView()
                } label: {
                    PremiumSettingsRow(
                        icon: "person.2.shield.checkmark",
                        title: ATHLTHLocalization.choose(
                            english: "Sharing & privacy",
                            norwegian: "Deling og personvern"
                        ),
                        subtitle: ATHLTHLocalization.choose(
                            english: "Friend feed, workout sharing and profile visibility",
                            norwegian: "Vennefeed, øktdeling og profilsynlighet"
                        )
                    ) {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.72))
                    }
                }
                .buttonStyle(.plain)

                SettingsDivider()

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
                                SettingsDivider()
                                NavigationLink {
                                    ATHLTHAdminUserDirectoryView()
                                } label: {
                                    PremiumSettingsRow(
                                        icon: "person.3.sequence.fill",
                                        title: ATHLTHLocalization.choose(
                                            english: "User database",
                                            norwegian: "Brukerdatabase"
                                        ),
                                        subtitle: ATHLTHLocalization.choose(
                                            english: "All accounts, roles and plans · read-only",
                                            norwegian: "Alle kontoer, roller og abonnement · kun lesing"
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
        case "Active connections":
            return "Aktive tilkoblinger"
        case "Available connections":
            return "Kan tilkobles"
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

        // Route-end hiding is configured for each shared route,
        // never as an account-wide privacy switch.
        return "\(profileTitle) profile"
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
            return ATHLTHLocalization.choose(english: "Connected", norwegian: "Tilkoblet")
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
        ATHLTHLocalization.choose(
            english: "Reminders, workouts and community",
            norwegian: "Påminnelser, trening og fellesskap"
        )
    }

    private var healthSyncHasIssue: Bool {
        let backgroundIssue = !(health.backgroundSyncError?.isEmpty ?? true)
        let readIssue = !(health.authorizationError?.isEmpty ?? true)
        let importIssue = !(health.workoutImportError?.isEmpty ?? true)
        return backgroundIssue || readIssue || importIssue
    }

    private var healthSyncStateTitle: String {
        guard settings.appleHealthIntegrationEnabled else {
            return ATHLTHLocalization.choose(
                english: "Paused", norwegian: "Deaktivert"
            )
        }
        if healthRequestInProgress || health.isRefreshing {
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
        if health.shouldDeferAutomaticHealthWork {
            return ATHLTHLocalization.choose(english: "Deferred", norwegian: "Utsatt")
        }
        if healthSyncHasIssue {
            return ATHLTHLocalization.choose(
                english: "Issue",
                norwegian: "Problem"
            )
        }
        if health.hasCompletedHealthReadThisLaunch && !health.hasTrainingHealthData {
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
        if health.hasTrainingHealthData &&
            !health.canWriteWorkouts {
            return ATHLTHLocalization.choose(
                english: "Read only",
                norwegian: "Kun lesing"
            )
        }
        return health.hasReadableHealthData
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
        if let last = health.lastSuccessfulRefreshAt, health.hasReadableHealthData {
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

        if let error = health.workoutImportError, !error.isEmpty {
            return ATHLTHLocalization.choose(
                english: "Workout import needs attention: \(error)",
                norwegian: "Øktimport krever oppmerksomhet: \(error)"
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

        if let lastRefresh = health.lastSuccessfulRefreshAt, health.hasCompletedHealthReadThisLaunch {
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

        if healthRequestInProgress || health.isRefreshing {
            return ATHLTHLocalization.choose(english: "Reading Apple Health data…", norwegian: "Leser data fra Apple Health…")
        }
        if health.shouldDeferAutomaticHealthWork {
            return ATHLTHLocalization.choose(english: "Configured · sync temporarily deferred", norwegian: "Konfigurert · synkronisering midlertidig utsatt")
        }
        if healthSyncHasIssue {
            return ATHLTHLocalization.choose(english: "Configured · synchronization needs attention", norwegian: "Konfigurert · synkronisering krever oppmerksomhet")
        }
        if health.authorizationReviewNeeded && health.hasReadableHealthData {
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

        if health.hasCompletedHealthReadThisLaunch {
            return ATHLTHLocalization.choose(
                english: "Permission configured · no readable data found yet",
                norwegian: "Tillatelse konfigurert · ingen lesbare data funnet ennå"
            )
        }

        return ATHLTHLocalization.choose(
            english: "Permission configured · awaiting data refresh",
            norwegian: "Tillatelse konfigurert · venter på oppdatering av data"
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
        case "Unavailable":
            return "Utilgjengelig"
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

    /// Existing connections can gain new HealthKit read types after updates.
    /// A regular sync must not reopen the permission sheet, so keep this
    /// explicit, user-initiated action available for connected accounts.
    private func reviewAppleHealthPermissions() {
        guard settings.appleHealthIntegrationEnabled,
              !healthRequestInProgress else { return }

        healthRequestInProgress = true
        Task {
            defer { healthRequestInProgress = false }

            await health.requestAuthorization()
            guard health.authorizationError == nil else { return }

            await health.completeAuthorizationSetup()
            await health.configureBackgroundSync(
                allowed: settings.backgroundHealthSyncEnabled
            )
            await health.refreshAll()
            syncHealthProfileFromAppleHealthIfAppropriate()
        }
    }

    private func handleAppleHealthTap() {
        guard settings.appleHealthIntegrationEnabled, !healthRequestInProgress else { return }
        healthRequestInProgress = true
        Task {
            defer { healthRequestInProgress = false }

            let restoredExistingSetup =
                await health.restoreAuthorizationStateFromSystem()

            if !restoredExistingSetup || health.authorizationReviewNeeded {
                // The Apple Health row is the explicit place to connect or
                // review newly introduced permissions. Normal sync never
                // reopens the Health permission flow.
                await health.requestAuthorization()
                guard health.authorizationError == nil else { return }
                await health.completeAuthorizationSetup()
            } else {
                health.resumeUserInitiatedHealthSync()
            }

            await health.configureBackgroundSync(
                allowed: settings.backgroundHealthSyncEnabled
            )
            await health.refreshAll()
            syncHealthProfileFromAppleHealthIfAppropriate()
        }
    }

    private func runHealthSync() {
        guard settings.appleHealthIntegrationEnabled, !healthRequestInProgress else { return }
        guard health.hasRequestedAuthorization else {
            handleAppleHealthTap()
            return
        }

        healthRequestInProgress = true
        Task {
            defer { healthRequestInProgress = false }

            // Sync with the permissions that are already in place. Do not
            // reopen Health authorization simply because the app was updated
            // or because ATHLTH added another optional Health data type.
            _ = await health.restoreAuthorizationStateFromSystem()
            health.resumeUserInitiatedHealthSync()

            await health.configureBackgroundSync(
                allowed: settings.backgroundHealthSyncEnabled
            )
            await health.refreshAll()
            syncHealthProfileFromAppleHealthIfAppropriate()
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
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore
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
        async let challengeRefresh: Void =
            communityGroups.refreshCalendarChallenges()

        _ = await (
            eventRefresh,
            groupRefresh,
            challengeRefresh
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
            workoutStatuses: session.calendarWorkoutStatuses(
                healthWorkouts: health.workouts,
                strengthHistory: strength.workoutHistory
            ),
            communityEvents: communityEvents.events,
            groupEvents: communityGroups.calendarEvents,
            groupEventRSVPs:
                communityGroups.calendarEventRSVPs,
            clubChallenges: communityGroups.calendarClubChallenges,
            clubChallengeParticipations:
                communityGroups.calendarChallengeParticipations,
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
            workoutStatuses: session.calendarWorkoutStatuses(
                healthWorkouts: health.workouts,
                strengthHistory: strength.workoutHistory
            ),
            communityEvents: communityEvents.events,
            groupEvents: communityGroups.calendarEvents,
            groupEventRSVPs:
                communityGroups.calendarEventRSVPs,
            clubChallenges: communityGroups.calendarClubChallenges,
            clubChallengeParticipations:
                communityGroups.calendarChallengeParticipations,
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

private struct ATHLTHPremiumSettingsChoices<Option: Identifiable & Equatable>: View {
    let title: String
    let subtitle: String
    let options: [Option]
    @Binding var selection: Option
    let optionTitle: (Option) -> String
    let optionDetail: (Option) -> String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(title)
                    .font(.system(size: 32, weight: .regular, design: .serif))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                ForEach(options) { option in
                    Button {
                        selection = option
                    } label: {
                        PremiumSettingsCard {
                            PremiumSettingsRow(
                                icon: selection == option ? "checkmark.circle.fill" : "circle",
                                iconTint: ATHLTHTheme.accentDeep,
                                iconBackground: ATHLTHTheme.premiumGoldSoft,
                                title: optionTitle(option),
                                subtitle: optionDetail(option).isEmpty ? nil : optionDetail(option)
                            ) {
                                if selection == option {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(ATHLTHTheme.accentDeep)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == option ? .isSelected : [])
                }
            }
            .padding(18)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background {
            LinearGradient(
                colors: [ATHLTHTheme.canvasTop, .white, ATHLTHTheme.canvasBottom],
                startPoint: .top, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Shared layout for settings subpages. Uses the same margins, theme and
/// lazy section loading on iPhone and iPad.
struct ATHLTHSettingsScreen<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.system(size: 32, design: .serif)).foregroundStyle(ATHLTHTheme.primaryText)
                    Text(subtitle).font(.subheadline).foregroundStyle(ATHLTHTheme.mutedText)
                }
                content
            }
            .padding(.horizontal, 18).padding(.vertical, 22)
            .frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
        .background {
            LinearGradient(colors: [ATHLTHTheme.canvasTop, .white, ATHLTHTheme.canvasBottom],
                           startPoint: .top, endPoint: .bottomTrailing).ignoresSafeArea()
        }
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}

struct ATHLTHSettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).tracking(2.4)
                .foregroundStyle(ATHLTHTheme.accentDeep.opacity(0.82)).padding(.leading, 16)
            content
        }
    }
}

struct PremiumSettingsCard<Content: View>: View {
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

struct PremiumSettingsRow<Trailing: View>: View {
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

struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(ATHLTHTheme.divider)
            .frame(height: 0.5)
            .padding(.leading, 74)
            .padding(.trailing, 16)
    }
}

private struct GarminConnectionSetupView: View {
    @EnvironmentObject private var session: AppSessionStore

    private var canTest: Bool {
        session.signedIn && !session.previewModeEnabled &&
            session.currentRole.canAccessControlCenter
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        ATHLTHSettingsScreen(title: "Garmin",
            subtitle: tr("Garmin Connect and compatible watches", "Garmin Connect og kompatible klokker")) {
            ATHLTHSettingsGroup(title: tr("Connection", "Tilkobling")) {
                PremiumSettingsCard {
                    PremiumSettingsRow(icon: "watch.analog",
                        iconTint: ATHLTHTheme.accentDeep,
                        iconBackground: ATHLTHTheme.premiumGoldSoft,
                        title: "Garmin Connect",
                        subtitle: canTest
                            ? tr("Restricted developer testing", "Begrenset utviklertest")
                            : tr("Not available for general use yet", "Ikke tilgjengelig for allmenn bruk ennå")) {
                        Text(canTest ? tr("Test", "Test") : tr("Coming soon", "Kommer snart"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                    if canTest {
                        SettingsDivider()
                        #if ATHLTH_GARMIN_PERSONAL && (DEBUG || ATHLTH_GARMIN_INTERNAL_TEST)
                        NavigationLink {
                            GarminPersonalSettingsView(accountID: session.profile.userID)
                                .id(session.profile.userID)
                        } label: {
                            PremiumSettingsRow(icon: "key", iconTint: ATHLTHTheme.accentDeep,
                                title: tr("Connect personal Garmin account", "Koble til personlig Garmin-konto"),
                                subtitle: tr("Private local test · your own data only", "Privat lokal test · kun dine egne data")) {
                                Image(systemName: "chevron.right").foregroundStyle(ATHLTHTheme.mutedText)
                            }
                        }
                        .buttonStyle(.plain)
                        #else
                        PremiumSettingsRow(icon: "lock.shield", iconTint: ATHLTHTheme.accentDeep,
                            title: tr("Developer access", "Utviklertilgang"),
                            subtitle: tr("Personal API requires a local development build or the separate internal test build. Public builds require approved Garmin authorization.", "Personal API krever et lokalt utviklingsbygg eller det separate interne testbygget. Offentlige bygg krever godkjent Garmin-autorisasjon.")) {
                            Image(systemName: "info.circle").foregroundStyle(ATHLTHTheme.mutedText)
                        }
                        #endif
                    }
                }
            }
            ATHLTHSettingsGroup(title: tr("Capabilities", "Funksjoner")) {
                PremiumSettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(tr("Activity and health data · planned", "Trenings- og helsedata · planlagt"), systemImage: "heart.text.clipboard")
                        Label(tr("Routes and training plans · planned", "Ruter og treningsplaner · planlagt"), systemImage: "map")
                        Label(tr("Direct workout start · not available", "Direkte øktstart · ikke tilgjengelig"), systemImage: "play.circle")
                        Text(tr("Connecting a data source does not enable live workout recording.", "En tilkoblet datakilde gir ikke automatisk støtte for live-registrering."))
                            .font(.caption).foregroundStyle(ATHLTHTheme.mutedText)
                    }
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .padding(16)
                }
            }
        }
    }
}

private struct ATHLTHTrainingSettingsView: View {
    @EnvironmentObject private var settings: AppSettingsStore
    private var watchSelection = ATHLTHWatchLaunchSelection()
    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }
    var body: some View {
        ATHLTHSettingsScreen(title: tr("Training", "Trening"),
                             subtitle: tr("Your defaults for new workouts.", "Dine standardvalg for nye økter.")) {
            ATHLTHSettingsGroup(title: tr("Workout setup", "Øktoppsett")) {
                PremiumSettingsCard {
                    NavigationLink {
                        ATHLTHPremiumSettingsChoices(title: tr("Default setup", "Standardoppsett"),
                            subtitle: tr("Can be changed for each workout.", "Kan endres for hver økt."),
                            options: WorkoutSetupPreference.allCases, selection: $settings.workoutSetupPreference,
                            optionTitle: { $0.title }, optionDetail: { $0.subtitle })
                    } label: {
                        row("slider.horizontal.3", tr("Default setup", "Standardoppsett"), settings.workoutSetupPreference.title)
                    }.buttonStyle(.plain)
                    SettingsDivider()
                    NavigationLink {
                        ATHLTHPremiumSettingsChoices(title: tr("Recording device", "Opptaksenhet"),
                            subtitle: tr("Preferred device when available.", "Foretrukket enhet når den er tilgjengelig."),
                            options: WorkoutCapturePreference.allCases, selection: $settings.preferredWorkoutCapture,
                            optionTitle: { $0.title }, optionDetail: { _ in "" })
                    } label: {
                        row("applewatch", tr("Recording device", "Opptaksenhet"), settings.preferredWorkoutCapture.title)
                    }.buttonStyle(.plain)
                    SettingsDivider()
                    VStack(alignment: .leading, spacing: 8) {
                        ATHLTHPreferredWatchPicker(selection: watchSelection)
                        Text(tr("Choose the watch used when starting a workout. You can choose another available watch for each workout.", "Velg standardklokke ved øktstart. Du kan velge en annen tilgjengelig klokke for hver økt."))
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                    .padding(16)
                    SettingsDivider()
                    PremiumSettingsRow(icon: "clock", iconTint: ATHLTHTheme.accentDeep,
                        iconBackground: ATHLTHTheme.premiumGoldSoft,
                        title: tr("Default start time", "Standard starttid"),
                        subtitle: tr("New planned workouts", "Nye planlagte økter")) {
                        DatePicker(tr("Start time", "Starttid"), selection: $settings.defaultPlannedWorkoutTime,
                                   displayedComponents: .hourAndMinute)
                            .labelsHidden().datePickerStyle(.compact).fixedSize()
                    }
                }
            }
            ATHLTHSettingsGroup(title: tr("Running & walking", "Løping og gåing")) {
                PremiumSettingsCard {
                    NavigationLink {
                        ATHLTHPremiumSettingsChoices(title: tr("Default running environment", "Standard løpemiljø"),
                            subtitle: tr("Applies only to new free runs; planned workouts and routes keep their own setup.", "Gjelder bare nye friløp. Planlagte økter og ruter beholder eget oppsett."),
                            options: RunEnvironment.allCases, selection: $settings.defaultFreeRunEnvironment,
                            optionTitle: { $0.title }, optionDetail: { $0.subtitle })
                    } label: {
                        row("figure.run", tr("Default running environment", "Standard løpemiljø"), settings.defaultFreeRunEnvironment.title)
                    }.buttonStyle(.plain)
                    SettingsDivider()
                    NavigationLink {
                        ATHLTHPremiumSettingsChoices(title: tr("Quick Run countdown", "Nedtelling ved hurtigløp"),
                            subtitle: tr("The 30-second Watch countdown runs on the watch. Other countdowns require the phone app to remain active.", "30 sekunders Watch-nedtelling kjører på klokken. Andre nedtellinger krever at telefonappen er aktiv."),
                            options: ATHLTHQuickRunCountdownPreference.allCases, selection: $settings.quickRunStartCountdown,
                            optionTitle: { $0.title }, optionDetail: { _ in "" })
                    } label: {
                        row("timer", tr("Quick Run countdown", "Nedtelling ved hurtigløp"), settings.quickRunStartCountdown.title)
                    }.buttonStyle(.plain)
                    SettingsDivider()
                    toggle("pause.circle", tr("Auto-pause outdoors", "Automatisk pause ute"),
                           tr("Default for outdoor running and walking", "Standard for løping og gåing utendørs"),
                           $settings.autoPauseOutdoorWorkouts)
                }
            }
            ATHLTHSettingsGroup(title: tr("Strength", "Styrke")) {
                PremiumSettingsCard {
                    NavigationLink { ATHLTHStrengthBarMassSettingsView() } label: {
                        row("scalemass", tr("Default bar weight", "Standard stangvekt"),
                            tr("Default and per-exercise overrides", "Standard og tilpasning per øvelse"))
                    }.buttonStyle(.plain)
                }
            }
            ATHLTHSettingsGroup(title: tr("Feedback", "Tilbakemelding")) {
                PremiumSettingsCard {
                    toggle("waveform", tr("Sound cues", "Lydsignaler"), tr("Feedback during training", "Tilbakemelding under trening"), $settings.audioCuesEnabled)
                    SettingsDivider()
                    toggle("waveform.path", tr("Haptic cues", "Vibrasjon"), tr("Haptic feedback during training", "Haptisk tilbakemelding under trening"), $settings.hapticCuesEnabled)
                    SettingsDivider()
                    toggle("sun.max", tr("Keep screen awake", "Hold skjermen på"), tr("While an active workout requests the screen", "Under aktive økter som bruker skjermen"), $settings.keepWorkoutScreenAwake)
                }
            }
            ATHLTHSettingsGroup(title: tr("Sharing", "Deling")) {
                PremiumSettingsCard {
                    NavigationLink { ATHLTHPrivacyCenterView() } label: {
                        row("person.2.shield.checkmark", tr("Workout sharing", "Øktdeling"),
                            tr("Automatic publishing and visibility", "Automatisk publisering og synlighet"))
                    }.buttonStyle(.plain)
                }
            }
        }
    }
    private func row(_ icon: String, _ title: String, _ subtitle: String) -> some View {
        PremiumSettingsRow(icon: icon, iconTint: ATHLTHTheme.accentDeep,
                           iconBackground: ATHLTHTheme.premiumGoldSoft, title: title, subtitle: subtitle) {
            Image(systemName: "chevron.right").foregroundStyle(ATHLTHTheme.mutedText)
        }
    }
    private func toggle(_ icon: String, _ title: String, _ subtitle: String, _ binding: Binding<Bool>) -> some View {
        PremiumSettingsRow(icon: icon, iconTint: ATHLTHTheme.accentDeep,
                           iconBackground: ATHLTHTheme.premiumGoldSoft, title: title, subtitle: subtitle) {
            Toggle(title, isOn: binding).labelsHidden().tint(ATHLTHTheme.premiumGold).fixedSize()
        }
    }
}

private struct ATHLTHAchievementSettingsView: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        ATHLTHSettingsScreen(title: tr("Achievements", "Prestasjoner"),
                             subtitle: tr("Celebrate your progress your way.", "Feir fremgangen på din måte.")) {
            ATHLTHSettingsGroup(title: tr("Visual effects", "Visuelle effekter")) {
                PremiumSettingsCard {
                    NavigationLink {
                        ATHLTHPremiumSettingsChoices(title: tr("Visual effects", "Visuelle effekter"),
                            subtitle: tr("Choose your celebration style.", "Velg hvordan prestasjoner feires."),
                            options: AchievementEffectPreference.allCases, selection: $settings.achievementEffects,
                            optionTitle: { $0.title }, optionDetail: { $0.subtitle })
                    } label: {
                        PremiumSettingsRow(icon: "sparkles", iconTint: ATHLTHTheme.accentDeep,
                            iconBackground: ATHLTHTheme.premiumGoldSoft,
                            title: tr("Effects", "Effekter"), subtitle: settings.achievementEffects.title) {
                            Image(systemName: "chevron.right").foregroundStyle(ATHLTHTheme.mutedText)
                        }
                    }.buttonStyle(.plain)
                }
            }
            ATHLTHSettingsGroup(title: tr("Feedback", "Tilbakemelding")) {
                PremiumSettingsCard {
                    feedback("speaker.wave.2", tr("Celebration sounds", "Lyd ved prestasjoner"),
                             $settings.achievementUnlockSoundsEnabled)
                    SettingsDivider()
                    feedback("waveform.path", tr("Celebration haptics", "Vibrasjon ved prestasjoner"),
                             $settings.achievementUnlockHapticsEnabled)
                }
            }
            ATHLTHSettingsGroup(title: tr("Accessibility", "Tilgjengelighet")) {
                PremiumSettingsCard {
                    Text(tr("iOS Reduce Motion and Reduce Transparency take priority.", "iOS-innstillingene Reduser bevegelse og Reduser gjennomsiktighet har alltid prioritet."))
                        .font(.caption).foregroundStyle(ATHLTHTheme.mutedText).padding(16)
                    if reduceMotion {
                        PremiumSettingsRow(icon: "figure.walk.motion", title: tr("Reduce Motion is active", "Reduser bevegelse er aktivert")) { EmptyView() }
                    }
                    if reduceTransparency {
                        PremiumSettingsRow(icon: "circle.lefthalf.filled", title: tr("Reduce Transparency is active", "Reduser gjennomsiktighet er aktivert")) { EmptyView() }
                    }
                }
            }
        }
    }

    private func feedback(_ icon: String, _ title: String, _ value: Binding<Bool>) -> some View {
        PremiumSettingsRow(icon: icon, iconTint: ATHLTHTheme.accentDeep,
            iconBackground: ATHLTHTheme.premiumGoldSoft, title: title) {
            Toggle(title, isOn: value).labelsHidden().tint(ATHLTHTheme.premiumGold).fixedSize()
        }
    }
}

private struct ATHLTHNotificationSettingsView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var notifications: ATHLTHNotificationStore
    @ObservedObject private var push = APNsPushManager.shared

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("Notifications", "Varsler"))
                        .font(.system(size: 32, weight: .regular, design: .serif))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                    Text(tr("Choose what ATHLTH notifies you about.", "Velg hva ATHLTH skal varsle deg om."))
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }

                notificationSection(tr("Reminders", "Påminnelser")) {
                    PremiumSettingsCard {
                        notificationToggle(
                            icon: "checkmark.circle",
                            title: tr("Daily check-in", "Daglig innsjekk"),
                            subtitle: tr("Reminder if you have not checked in", "Påminnelse hvis du ikke har sjekket inn"),
                            isOn: $settings.dailyCheckInRemindersEnabled
                        )
                        if settings.dailyCheckInRemindersEnabled {
                            SettingsDivider()
                            PremiumSettingsRow(
                                icon: "clock",
                                iconTint: ATHLTHTheme.accentDeep,
                                iconBackground: ATHLTHTheme.premiumGoldSoft,
                                title: tr("Reminder time", "Klokkeslett"),
                                subtitle: tr("Your daily reminder", "Din daglige påminnelse")
                            ) {
                                DatePicker(
                                    tr("Reminder time", "Klokkeslett"),
                                    selection: $settings.dailyCheckInReminderTime,
                                    displayedComponents: .hourAndMinute
                                )
                                .labelsHidden()
                                .datePickerStyle(.compact)
                                .tint(ATHLTHTheme.premiumGold)
                                .fixedSize()
                            }
                        }
                    }
                    if hasEnabledAlerts {
                        if notifications.authorizationStatus == .notDetermined {
                            permissionButton(
                                title: tr("Enable iPhone notifications", "Aktiver iPhone-varsler"),
                                subtitle: tr("Allow notifications from ATHLTH", "Tillat varsler fra ATHLTH")
                            ) {
                                Task { await notifications.requestSystemNotificationPermission() }
                            }
                        } else if notifications.authorizationStatus == .denied {
                            permissionButton(
                                title: tr("Enable notifications in iOS Settings", "Aktiver varsler i iOS-innstillinger"),
                                subtitle: tr("Notifications are disabled in iOS", "Varsler er deaktivert i iOS")
                            ) {
                                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                    openURL(url)
                                }
                            }
                        }
                    }
                }

                notificationSection(tr("Training", "Trening")) {
                    PremiumSettingsCard {
                        notificationToggle(
                            icon: "figure.run",
                            title: tr("Workout updates", "Øktoppdateringer"),
                            subtitle: tr("Notifications related to your workouts", "Varsler knyttet til treningsøktene dine"),
                            isOn: $settings.workoutRemindersEnabled
                        )
                    }
                }

                notificationSection(tr("Community", "Fellesskap")) {
                    PremiumSettingsCard {
                        notificationToggle(
                            icon: "person.2",
                            title: tr("Friend activity", "Venneaktivitet"),
                            subtitle: tr("Activity from your friends", "Aktivitet fra vennene dine"),
                            isOn: $settings.friendActivityNotificationsEnabled
                        )
                        SettingsDivider()
                        notificationToggle(
                            icon: "trophy",
                            title: tr("Challenges", "Utfordringer"),
                            subtitle: tr("Updates about challenges", "Oppdateringer om utfordringer"),
                            isOn: $settings.challengeNotificationsEnabled
                        )
                        SettingsDivider()
                        notificationToggle(
                            icon: "bubble.left.and.bubble.right",
                            title: tr("Messages", "Meldinger"),
                            subtitle: tr("New messages in your inbox", "Nye meldinger i innboksen"),
                            isOn: $settings.messageNotificationsEnabled
                        )
                        SettingsDivider()
                        notificationToggle(
                            icon: "at",
                            title: tr("Mentions", "Omtaler"),
                            subtitle: tr("When someone mentions you", "Når noen omtaler deg"),
                            isOn: $settings.mentionNotificationsEnabled
                        )
                    }
                }

                Label(
                    tr("Choose which alerts appear on your iPhone. Activity remains available in ATHLTH.", "Velg hvilke varsler du får på iPhone. Aktiviteten er fortsatt tilgjengelig i ATHLTH."),
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .padding(.horizontal, 8)
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 32)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background {
            ZStack {
                LinearGradient(
                    colors: [ATHLTHTheme.canvasTop, .white, ATHLTHTheme.canvasBottom],
                    startPoint: .top, endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [ATHLTHTheme.premiumGold.opacity(0.055), .clear],
                    center: .topTrailing, startRadius: 20, endRadius: 420
                )
            }
            .ignoresSafeArea()
        }
        .navigationTitle(
            ATHLTHLocalization.choose(
                english: "Notifications",
                norwegian: "Varsler"
            )
        )
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: notifications.authorizationStatus) { _, _ in
            reconcileDailyReminder()
        }
        .onChange(of: settings.dailyCheckInRemindersEnabled) { _, _ in
            reconcileDailyReminder()
        }
        .onChange(of: settings.dailyCheckInReminderMinuteOfDay) { _, _ in
            reconcileDailyReminder()
        }
        .task {
            await notifications.refreshAuthorizationStatus()
            reconcileDailyReminder()
            await notifications.reconcileSystemPreferences()
            await push.repairRegistrationIfAuthorized()
            await push.refreshBackendRegistrationStatus()
        }
        .onChange(of: settings.challengeNotificationsEnabled) { _, _ in
            Task {
                await notifications.reconcileSystemPreferences()
            }
        }
    }

    private func notificationSection<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(2.8)
                .foregroundStyle(ATHLTHTheme.accentDeep.opacity(0.82))
                .padding(.leading, 16)
            content()
        }
    }

    private func notificationToggle(
        icon: String, title: String, subtitle: String, isOn: Binding<Bool>
    ) -> some View {
        PremiumSettingsRow(
            icon: icon,
            iconTint: ATHLTHTheme.accentDeep,
            iconBackground: ATHLTHTheme.premiumGoldSoft,
            title: title, subtitle: subtitle
        ) {
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .tint(ATHLTHTheme.premiumGold)
                .fixedSize()
                .accessibilityLabel(Text(title))
        }
    }

    private func permissionButton(
        title: String, subtitle: String, action: @escaping () -> Void
    ) -> some View {
        PremiumSettingsCard {
            Button(action: action) {
                PremiumSettingsRow(
                    icon: "bell.badge",
                    iconTint: ATHLTHTheme.accentDeep,
                    iconBackground: ATHLTHTheme.premiumGoldSoft,
                    title: title, subtitle: subtitle
                ) {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func reconcileDailyReminder() {
        notifications.reconcileDailyCheckIn(
            enabled: settings.dailyCheckInRemindersEnabled,
            accountID: session.profile.userID,
            completed: RecoverySorenessStore().hasTodayCheckIn
        )
    }

    private var hasEnabledAlerts: Bool {
        settings.dailyCheckInRemindersEnabled ||
        settings.workoutRemindersEnabled ||
        settings.friendActivityNotificationsEnabled ||
        settings.challengeNotificationsEnabled ||
        settings.messageNotificationsEnabled ||
        settings.mentionNotificationsEnabled
    }
}

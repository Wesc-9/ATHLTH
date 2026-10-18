import SwiftUI

/// A focused, readable privacy hub. The switches deliberately reuse the
/// existing saved SocialPrivacySettings fields and Supabase RLS audiences.
struct SocialPrivacySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var goalStore: GoalStore
    @EnvironmentObject private var realtime: ATHLTHRealtimeSocialStore

    @State private var draft: SocialPrivacySettings?
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var activityExpanded = true
    @State private var achievementsExpanded = false
    @State private var profileExtrasExpanded = false
    @State private var liveExpanded = false

    private func loc(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    var body: some View {
        ZStack {
            ATHLTHPremiumCanvas(accent: ATHLTHTheme.premiumGold.opacity(0.23))

            ScrollView {
                if let binding = draftBinding {
                    VStack(alignment: .leading, spacing: 22) {
                        introduction
                        profileSection(binding)
                        messagingSection(binding)
                        sharingSection(binding)
                        challengesSection(binding)
                        saveButton
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 120)
                    .frame(maxWidth: 660)
                    .frame(maxWidth: .infinity)
                } else {
                    ProgressView(loc("Loading privacy settings…", "Laster personvern…"))
                        .frame(maxWidth: .infinity, minHeight: 220)
                }
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(loc("Social privacy", "Sosialt personvern"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if draft != nil {
                    Button {
                        Task { await save() }
                    } label: {
                        if saving {
                            ProgressView()
                                .tint(.white)
                                .frame(width: 52, height: 20)
                        } else {
                            Text(loc("Save", "Lagre"))
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(ATHLTHTheme.accentDeep, in: Capsule())
                    .disabled(saving)
                }
            }
        }
        .alert(
            loc("Could not save", "Kunne ikke lagre"),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            if social.privacy == nil {
                await social.refresh()
            }
            // Never overwrite unsaved changes on scene reactivation.
            if draft == nil { draft = social.privacy }
        }
    }

    private var introduction: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "hand.raised.shield.lefthalf.filled")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(width: 48, height: 48)
                .background(ATHLTHTheme.premiumGoldSoft, in:
                    RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(loc("Your profile. Your choice.", "Din profil. Dine valg."))
                    .font(.system(size: 25, weight: .regular, design: .serif))
                    .foregroundStyle(ATHLTHTheme.primaryText)

                Text(loc(
                    "Choose who can reach you and what others can see. Sharing is off until you enable it.",
                    "Velg hvem som kan kontakte deg og hva andre kan se. Deling er av til du slår den på."
                ))
                .font(.subheadline)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func profileSection(_ data: Binding<SocialPrivacySettings>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("person.crop.circle", loc("Profile", "Profil"))
            premiumCard {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        rowIcon("globe.europe.africa")
                        VStack(alignment: .leading, spacing: 3) {
                            Text(loc("Profile visibility", "Profilsynlighet"))
                                .font(.subheadline.weight(.semibold))
                            Text(loc("Who can open your profile", "Hvem som kan åpne profilen"))
                                .font(.caption)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                        }
                        Spacer(minLength: 3)
                        Picker("", selection: data.profileVisibility) {
                            Text(loc("Private", "Privat")).tag("private")
                            Text(loc("Followers", "Følgere")).tag("friends")
                            Text(loc("Public", "Offentlig")).tag("public")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .tint(ATHLTHTheme.accentDeep)
                    }
                    .frame(minHeight: 51)
                    thinDivider

                    privacyToggle(
                        "person.badge.plus",
                        loc("Allow follow requests", "Tillat følgeforespørsler"),
                        detail: "",
                        binding: data.allowFriendRequests
                    )
                    thinDivider

                    privacyToggle(
                        "circle.fill",
                        loc("Show when I'm online", "Vis når jeg er pålogget"),
                        detail: "",
                        binding: data.showOnlineStatus,
                        presenceIcon: true
                    )

                    privacyHint(
                        loc(
                            "Only mutual follows can see your online status. It expires automatically when you leave the app.",
                            "Kun personer dere følger gjensidig kan se pålogget-status. Den utløper automatisk når du forlater appen."
                        )
                    )
                    .padding(.top, 6)
                }
            }
        }
    }

    private func messagingSection(_ data: Binding<SocialPrivacySettings>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("bubble.left.and.bubble.right",
                         loc("Messages", "Meldinger"))
            premiumCard {
                VStack(alignment: .leading, spacing: 11) {
                    HStack(spacing: 11) {
                        rowIcon("paperplane")
                        VStack(alignment: .leading, spacing: 3) {
                            Text(loc("Who can message me", "Hvem kan sende meg meldinger"))
                                .font(.subheadline.weight(.semibold))
                            Text(loc("Choose who may contact you", "Bestem hvem som kan ta kontakt"))
                                .font(.caption)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                        }
                        Spacer()
                    }
                    Picker("", selection: data.allowDirectMessages) {
                        // 'requests' is the existing secure all-users request mode:
                        // one introductory message until the recipient approves.
                        Text(loc("Everyone", "Alle")).tag("requests")
                        Text(loc("Mutual follows only", "Kun gjensidige")).tag("friends")
                        Text(loc("No new requests", "Ingen nye forespørsler")).tag("nobody")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .accessibilityLabel(loc("Who can message me", "Hvem kan sende meg meldinger"))

                    privacyHint(messageExplanation(for: data.wrappedValue.allowDirectMessages))
                }
            }
        }
    }

    private func messageExplanation(for value: String) -> String {
        switch value {
        case "requests":
            return loc(
                "Anyone can send one message request. You must accept it before they can send more. Blocking always prevents contact.",
                "Alle kan sende én meldingsforespørsel. Du må godkjenne før de kan sende mer. Blokkering stopper alltid kontakt."
            )
        case "friends":
            return loc(
                "Only people you follow who also follow you can start a conversation.",
                "Bare personer dere følger gjensidig kan starte en samtale."
            )
        default:
            return loc(
                "New message requests are closed. Existing accepted conversations may remain available.",
                "Nye meldingsforespørsler er stengt. Allerede godkjente samtaler kan fortsatt være tilgjengelige."
            )
        }
    }

    private func sharingSection(_ data: Binding<SocialPrivacySettings>) -> some View {
        let value = data.wrappedValue
        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle("square.on.square",
                         loc("What you share", "Hva du deler"))

            Text(loc(
                "Open a category to choose what others can see. Off always means private. Audience is shown for each item.",
                "Åpne en kategori og velg hva andre kan se. Av betyr alltid privat. Publikum vises for hvert valg."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHTheme.mutedText)
            .padding(.horizontal, 5)

            shareGroup(
                title: loc("Training activity", "Treningsaktivitet"),
                icon: "figure.run",
                enabled: [value.shareTrainingPresence, value.shareRecentActivity]
                    .filter { $0 }.count,
                total: 2,
                expanded: $activityExpanded
            ) {
                privacyToggle(
                    "figure.run",
                    loc("Training now", "Trener nå"),
                    detail: audience(
                        enabled: value.shareTrainingPresence,
                        visibility: value.trainingPresenceVisibility,
                        profile: value.profileVisibility
                    ),
                    binding: data.shareTrainingPresence
                )
                thinDivider
                privacyToggle(
                    "clock.arrow.circlepath",
                    loc("Recent activity", "Siste aktivitet"),
                    detail: audience(
                        enabled: value.shareRecentActivity,
                        visibility: value.recentActivityVisibility,
                        profile: value.profileVisibility
                    ),
                    binding: data.shareRecentActivity
                )
            }

            shareGroup(
                title: loc("Performance", "Prestasjoner"),
                icon: "chart.bar",
                enabled: [
                    value.sharePerformanceStats, value.shareRunningPRs,
                    value.shareStrengthPRs, value.shareWorkoutTotals
                ].filter { $0 }.count,
                total: 4,
                expanded: $achievementsExpanded
            ) {
                privacyToggle(
                    "chart.bar",
                    loc("Performance statistics", "Prestasjonstall"),
                    detail: audience(
                        enabled: value.sharePerformanceStats,
                        visibility: value.performanceStatsVisibility,
                        profile: value.profileVisibility
                    ),
                    binding: data.sharePerformanceStats
                )
                thinDivider
                privacyToggle(
                    "figure.run.circle",
                    loc("Running records", "Løperekorder"),
                    detail: audience(
                        enabled: value.shareRunningPRs,
                        visibility: value.runningPRsVisibility,
                        profile: value.profileVisibility
                    ),
                    binding: data.shareRunningPRs
                )
                thinDivider
                privacyToggle(
                    "dumbbell",
                    loc("Strength records", "Styrkerekorder"),
                    detail: audience(
                        enabled: value.shareStrengthPRs,
                        visibility: value.strengthPRsVisibility,
                        profile: value.profileVisibility
                    ),
                    binding: data.shareStrengthPRs
                )
                thinDivider
                privacyToggle(
                    "sum",
                    loc("Workout totals", "Treningssummer"),
                    detail: audience(
                        enabled: value.shareWorkoutTotals,
                        visibility: value.performanceStatsVisibility,
                        profile: value.profileVisibility
                    ),
                    binding: data.shareWorkoutTotals
                )
                privacyHint(loc(
                    "Strength records are marked manual; running records use qualifying Apple Health data.",
                    "Styrkerekorder merkes som manuelle. Løperekorder bruker godkjente Apple Health-data."
                ))
            }

            shareGroup(
                title: loc("Profile content", "Profilinnhold"),
                icon: "person.text.rectangle",
                enabled: [
                    value.shareTrophyCabinet, value.shareGoals, value.shareGear
                ].filter { $0 }.count,
                total: 3,
                expanded: $profileExtrasExpanded
            ) {
                privacyToggle(
                    "trophy",
                    loc("Trophy cabinet", "Troféskap"),
                    detail: audience(
                        enabled: value.shareTrophyCabinet,
                        visibility: value.trophyCabinetVisibility,
                        profile: value.profileVisibility
                    ),
                    binding: data.shareTrophyCabinet
                )
                thinDivider
                privacyToggle(
                    "scope",
                    loc("Goals", "Mål"),
                    detail: audience(
                        enabled: value.shareGoals,
                        visibility: value.goalsVisibility,
                        profile: value.profileVisibility
                    ),
                    binding: data.shareGoals
                )
                thinDivider
                privacyToggle(
                    "backpack",
                    loc("Equipment", "Utstyr"),
                    detail: audience(
                        enabled: value.shareGear,
                        visibility: value.gearVisibility,
                        profile: value.profileVisibility
                    ),
                    binding: data.shareGear
                )
            }

            shareGroup(
                title: loc("Live location", "Live-posisjon"),
                icon: "location",
                enabled: value.shareLiveWorkoutLocation ? 1 : 0,
                total: 1,
                expanded: $liveExpanded,
                sensitive: true
            ) {
                privacyToggle(
                    "location",
                    loc("Share location during workouts", "Del posisjon under økt"),
                    detail: loc("Only while supported outdoor workouts are active",
                                "Kun under støttede utendørsøkter"),
                    binding: data.shareLiveWorkoutLocation
                )
                .onChange(of: value.shareLiveWorkoutLocation) { _, enabled in
                    if !enabled { draft?.shareLiveWorkoutHeartRate = false }
                }

                if value.shareLiveWorkoutLocation {
                    thinDivider
                    HStack {
                        Text(loc("Who can see the live map?", "Hvem kan se live-kartet?"))
                            .font(.subheadline.weight(.medium))
                        Spacer(minLength: 8)
                        Picker("", selection: data.liveLocationVisibility) {
                            Text(loc("Followers", "Følgere")).tag("followers")
                            Text(loc("Mutual follows", "Gjensidige")).tag("mutuals")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .tint(ATHLTHTheme.accentDeep)
                    }
                    .padding(.vertical, 10)

                    thinDivider
                    privacyToggle(
                        "heart",
                        loc("Include heart rate", "Del også puls"),
                        detail: loc("Only with the live-map audience", "Kun med de som kan se live-kartet"),
                        binding: data.shareLiveWorkoutHeartRate
                    )
                }

                privacyHint(loc(
                    "Live position is sensitive. The app stores only the latest point, which expires after about 90 seconds. Heart rate is off unless enabled.",
                    "Live-posisjon er sensitivt. Kun siste punkt lagres og utløper etter omtrent 90 sekunder. Puls deles ikke med mindre du slår det på."
                ))
                .padding(.top, 6)
            }
        }
    }

    private func challengesSection(_ data: Binding<SocialPrivacySettings>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("flag.checkered", loc("Challenges", "Utfordringer"))
            premiumCard {
                HStack(spacing: 10) {
                    rowIcon("flag.checkered")
                    Text(loc("Who can challenge me", "Hvem kan utfordre meg"))
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 6)
                    Picker("", selection: data.allowChallengeInvites) {
                        Text(loc("Mutual follows", "Gjensidige")).tag("friends")
                        Text(loc("Everyone", "Alle")).tag("everyone")
                        Text(loc("Nobody", "Ingen")).tag("nobody")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(ATHLTHTheme.accentDeep)
                }
            }
        }
    }

    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            HStack(spacing: 10) {
                Spacer()
                if saving { ProgressView().tint(.white) }
                Text(loc("Save preferences", "Lagre innstillinger"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .frame(height: 52)
            .foregroundStyle(.white)
            .background(ATHLTHTheme.accentDeep, in: Capsule())
        }
        .disabled(saving)
        .padding(.top, 3)
    }

    private func audience(enabled: Bool, visibility: String, profile: String) -> String {
        let scope = PrivacyVisibilityRules.scope(
            enabled: enabled, current: visibility, profile: profile
        )
        switch scope {
        case "public": return loc("Visible to everyone", "Synlig for alle")
        case "friends": return loc("Visible to followers", "Synlig for følgere")
        default: return loc("Private", "Privat")
        }
    }

    private func sectionTitle(_ icon: String, _ title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(width: 39, height: 39)
                .background(ATHLTHTheme.premiumGoldSoft, in: Circle())
            Text(title)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .foregroundStyle(ATHLTHTheme.primaryText)
        }
        .padding(.leading, 5)
    }

    private func rowIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(ATHLTHTheme.accentDeep)
            .frame(width: 37, height: 37)
            .background(ATHLTHTheme.champagneSoft.opacity(0.8), in: Circle())
            .accessibilityHidden(true)
    }

    private var thinDivider: some View {
        Rectangle()
            .fill(ATHLTHTheme.border.opacity(0.63))
            .frame(height: 0.7)
            .padding(.vertical, 8)
    }

    private func premiumCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(17)
            .background(
                LinearGradient(
                    colors: [.white, ATHLTHTheme.champagneSoft.opacity(0.32)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 25, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .stroke(ATHLTHTheme.border.opacity(0.72), lineWidth: 0.8)
            }
            .shadow(color: ATHLTHTheme.accentDeep.opacity(0.045), radius: 16, y: 6)
    }

    private func privacyToggle(
        _ icon: String,
        _ title: String,
        detail: String,
        binding: Binding<Bool>,
        presenceIcon: Bool = false
    ) -> some View {
        Toggle(isOn: binding) {
            HStack(spacing: 12) {
                if presenceIcon {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.green)
                        .frame(width: 37, height: 37)
                        .background(ATHLTHTheme.champagneSoft.opacity(0.8), in: Circle())
                        .accessibilityHidden(true)
                } else {
                    rowIcon(icon)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                            .lineLimit(2)
                    }
                }
            }
        }
        .tint(ATHLTHTheme.accentDeep)
        .padding(.vertical, 5)
    }

    private func privacyHint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "info.circle")
                .font(.system(size: 14))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .padding(.top, 1)
            Text(text)
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ATHLTHTheme.champagneSoft.opacity(0.54),
                    in: RoundedRectangle(cornerRadius: 14))
    }

    private func shareGroup<Content: View>(
        title: String,
        icon: String,
        enabled: Int,
        total: Int,
        expanded: Binding<Bool>,
        sensitive: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        premiumCard {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expanded.wrappedValue.toggle()
                    }
                } label: {
                    HStack(spacing: 11) {
                        rowIcon(icon)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ATHLTHTheme.primaryText)
                            Text(loc(
                                "\(enabled) of \(total) shared",
                                "\(enabled) av \(total) delt"
                            ))
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                        }
                        Spacer()
                        if sensitive {
                            Image(systemName: "lock.shield")
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                                .accessibilityHidden(true)
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .rotationEffect(.degrees(expanded.wrappedValue ? 180 : 0))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(loc(
                    "Double tap to expand or collapse sharing options.",
                    "Dobbelttrykk for å vise eller skjule delingsvalg."
                ))

                if expanded.wrappedValue {
                    thinDivider
                    content()
                }
            }
        }
    }

    private var draftBinding: Binding<SocialPrivacySettings>? {
        guard draft != nil else { return nil }
        return Binding(get: { draft! }, set: { draft = $0 })
    }

    @MainActor
    private func save() async {
        guard let draft, !saving else { return }
        saving = true
        defer { saving = false }

        let result = await social.updatePrivacy(draft)
        switch result {
        case .success:
            await social.syncOwnGoals(goalStore.goals, enabled: draft.shareGoals)
            await realtime.configureOnlinePresence(
                appIsActive: true,
                enabled: draft.showOnlineStatus
            )

            if !draft.shareLiveWorkoutLocation {
                if realtime.currentSession?.ghostChallengeID != nil {
                    await realtime.setCurrentLiveLocationSharing(false)
                } else {
                    await realtime.leaveCurrentLiveWorkout()
                }
            }

            if let visibility = ProfileVisibility(rawValue: draft.profileVisibility) {
                settings.profileVisibility = visibility
            }
            settings.shareTrainingPresence = draft.shareTrainingPresence
            dismiss()

        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}

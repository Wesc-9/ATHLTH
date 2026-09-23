import PhotosUI
import SwiftUI
import UIKit

struct ATHLTHEditProfileView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var accountService: SupabaseAccountService

    @State private var displayName = ""
    @State private var username = ""
    @State private var bio = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedAvatarData: Data?
    @State private var usernameAvailable: Bool?
    @State private var checkingUsername = false
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var saved = false

    var body: some View {
        Form {
            Section {
                VStack(spacing: 14) {
                    avatarPreview

                    PhotosPicker(
                        selection: $selectedPhoto,
                        matching: .images
                    ) {
                        Label(
                            selectedAvatarData == nil ? "Choose Profile Photo" : "Change Photo",
                            systemImage: "photo"
                        )
                    }
                    .buttonStyle(.bordered)
                    .tint(ATHLTHTheme.accent)

                    Text("Your photo is shown only where your profile visibility allows it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section("Public profile") {
                TextField("Display name", text: $displayName)
                    .textContentType(.name)

                VStack(alignment: .leading, spacing: 6) {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)

                    usernameStatus
                }

                VStack(alignment: .trailing, spacing: 6) {
                    TextEditor(text: $bio)
                        .frame(minHeight: 92)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(
                            Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 12)
                        )

                    Text("\(bio.count)/160")
                        .font(.caption2)
                        .foregroundStyle(bio.count > 160 ? .red : .secondary)
                }
            }

            Section {
                Button {
                    Task { await saveProfile() }
                } label: {
                    HStack {
                        Text("Save Profile")
                        Spacer()
                        if saving {
                            ProgressView()
                        }
                    }
                }
                .disabled(!canSave || saving)
            } footer: {
                Text("Display name, username, bio and profile photo are social profile data. Health details remain private and are managed separately.")
            }
        }
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadCurrentProfile)
        .onChange(of: selectedPhoto) { _, newItem in
            guard let newItem else { return }
            Task {
                do {
                    guard let data = try await newItem.loadTransferable(type: Data.self),
                          let image = UIImage(data: data),
                          let jpeg = image.jpegData(compressionQuality: 0.82)
                    else {
                        throw ProfileEditingError.invalidImage
                    }
                    await MainActor.run {
                        selectedAvatarData = jpeg
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
        .task(id: username) {
            await checkUsername()
        }
        .alert(
            "ATHLTH",
            isPresented: Binding(
                get: { errorMessage != nil || saved },
                set: {
                    if !$0 {
                        errorMessage = nil
                        saved = false
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Profile updated.")
        }
    }

    @ViewBuilder
    private var avatarPreview: some View {
        if let selectedAvatarData,
           let image = UIImage(data: selectedAvatarData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 112, height: 112)
                .clipShape(Circle())
                .overlay {
                    Circle().stroke(ATHLTHTheme.border, lineWidth: 1)
                }
        } else if let avatarURL = session.profile.avatarURL {
            AsyncImage(url: avatarURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    avatarFallback
                }
            }
            .frame(width: 112, height: 112)
            .clipShape(Circle())
            .overlay {
                Circle().stroke(ATHLTHTheme.border, lineWidth: 1)
            }
        } else {
            avatarFallback
                .frame(width: 112, height: 112)
        }
    }

    private var avatarFallback: some View {
        Circle()
            .fill(ATHLTHTheme.accentSoft)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(ATHLTHTheme.accent)
            }
    }

    @ViewBuilder
    private var usernameStatus: some View {
        let clean = cleanedUsername

        if clean == session.profile.username.lowercased() {
            Label("Current username", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if clean.count < 3 {
            Text("Use at least 3 characters.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if checkingUsername {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text("Checking availability…")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if usernameAvailable == true {
            Label("Username available", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.accent)
        } else if usernameAvailable == false {
            Label("Username unavailable or invalid", systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private var cleanedUsername: String {
        username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private var canSave: Bool {
        let cleanName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentUsername = session.profile.username.lowercased()
        let usernameOK =
            cleanedUsername == currentUsername ||
            usernameAvailable == true

        return !cleanName.isEmpty &&
            cleanedUsername.count >= 3 &&
            bio.count <= 160 &&
            usernameOK
    }

    private func loadCurrentProfile() {
        displayName = session.profile.displayName
        username = session.profile.username
        bio = session.profile.bio
        usernameAvailable = nil
    }

    private func checkUsername() async {
        let clean = cleanedUsername

        guard clean != session.profile.username.lowercased(),
              clean.count >= 3
        else {
            usernameAvailable = nil
            checkingUsername = false
            return
        }

        checkingUsername = true
        usernameAvailable = nil

        try? await Task.sleep(nanoseconds: 450_000_000)
        guard !Task.isCancelled else { return }

        do {
            let available = try await accountService.isUsernameAvailable(clean)
            guard !Task.isCancelled else { return }
            usernameAvailable = available
        } catch {
            guard !Task.isCancelled else { return }
            usernameAvailable = false
        }

        checkingUsername = false
    }

    private func saveProfile() async {
        guard canSave else { return }

        saving = true
        errorMessage = nil
        defer { saving = false }

        do {
            var avatarURL = session.profile.avatarURL

            if let selectedAvatarData {
                avatarURL = try await accountService.uploadProfileAvatar(
                    jpegData: selectedAvatarData
                )
            }

            let bootstrap = try await accountService.updateProfile(
                displayName: displayName,
                username: cleanedUsername,
                bio: bio,
                avatarURL: avatarURL
            )

            session.applyBackendBootstrap(bootstrap)
            selectedAvatarData = nil
            saved = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum ProfileEditingError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        "ATHLTH could not prepare that image. Try another photo."
    }
}

struct PersonalHealthProfileView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var settings: AppSettingsStore

    @State private var includeDateOfBirth = false
    @State private var dateOfBirth =
        Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    @State private var includeSex = false
    @State private var healthSex: HealthSex = .preferNotToSay
    @State private var includeWeight = false
    @State private var weightKilograms = 75.0
    @State private var includeHeight = false
    @State private var heightCentimeters = 180.0

    var body: some View {
        Form {
            Section("Source") {
                LabeledContent("Current source", value: sourceTitle)

                Button {
                    Task {
                        await health.requestAuthorization()
                        await health.configureBackgroundSync(
                            allowed:
                                session.canAccess(.backgroundHealthSync) &&
                                settings.backgroundHealthSyncEnabled
                        )
                        await health.refreshPersonalDetails()
                        session.updatePersonalDetails(
                            health.personalDetails,
                            source: health.personalDetails.hasAnyValue
                                ? .appleHealth
                                : .none
                        )
                        loadFromSession()
                    }
                } label: {
                    Label("Use Apple Health", systemImage: "heart.fill")
                }

                Text("ATHLTH uses only profile values Apple Health makes available. Missing values can be entered manually below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Manual health details") {
                Toggle("Date of birth", isOn: $includeDateOfBirth)

                if includeDateOfBirth {
                    DatePicker(
                        "Date",
                        selection: $dateOfBirth,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                }

                Toggle("Sex for health calculations", isOn: $includeSex)

                if includeSex {
                    Picker("Sex", selection: $healthSex) {
                        ForEach(HealthSex.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                }

                Toggle("Weight", isOn: $includeWeight)

                if includeWeight {
                    HStack {
                        Text("Weight")
                        Spacer()
                        Text(weightDisplay)
                            .monospacedDigit()
                    }

                    Slider(
                        value: weightBinding,
                        in: weightRange,
                        step: settings.measurementPreference == .metric ? 0.5 : 1
                    )
                }

                Toggle("Height", isOn: $includeHeight)

                if includeHeight {
                    HStack {
                        Text("Height")
                        Spacer()
                        Text(heightDisplay)
                            .monospacedDigit()
                    }

                    Slider(
                        value: heightBinding,
                        in: heightRange,
                        step: 1
                    )
                }

                Button("Save Health Profile") {
                    session.updatePersonalDetails(
                        HealthProfileBasics(
                            dateOfBirth: includeDateOfBirth ? dateOfBirth : nil,
                            healthSex: includeSex ? healthSex : nil,
                            weightKilograms: includeWeight ? weightKilograms : nil,
                            heightCentimeters: includeHeight ? heightCentimeters : nil
                        ),
                        source: .manual
                    )
                }
                .disabled(
                    !includeDateOfBirth &&
                    !includeSex &&
                    !includeWeight &&
                    !includeHeight
                )
            }

            Section("Privacy") {
                Label("Private health profile", systemImage: "lock.shield.fill")
                    .foregroundStyle(ATHLTHTheme.accent)

                Text("Date of birth, sex, weight and height are never placed on your public profile. Sharing health metrics requires a separate explicit action.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Health Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadFromSession)
    }

    private var sourceTitle: String {
        switch session.onboardingProfile?.personalDetailsSource ?? .none {
        case .appleHealth: return "Apple Health"
        case .manual: return "Manual"
        case .none: return "Not set"
        }
    }

    private var weightBinding: Binding<Double> {
        Binding(
            get: {
                settings.measurementPreference == .metric
                    ? weightKilograms
                    : weightKilograms * 2.2046226218
            },
            set: { newValue in
                weightKilograms =
                    settings.measurementPreference == .metric
                    ? newValue
                    : newValue / 2.2046226218
            }
        )
    }

    private var weightRange: ClosedRange<Double> {
        settings.measurementPreference == .metric
            ? 30...250
            : 66...551
    }

    private var weightDisplay: String {
        settings.measurementPreference.weight(
            fromKilograms: weightKilograms
        )
    }

    private var heightBinding: Binding<Double> {
        Binding(
            get: {
                settings.measurementPreference == .metric
                    ? heightCentimeters
                    : heightCentimeters / 2.54
            },
            set: { newValue in
                heightCentimeters =
                    settings.measurementPreference == .metric
                    ? newValue
                    : newValue * 2.54
            }
        )
    }

    private var heightRange: ClosedRange<Double> {
        settings.measurementPreference == .metric
            ? 120...230
            : 47...91
    }

    private var heightDisplay: String {
        if settings.measurementPreference == .metric {
            return "\(Int(heightCentimeters.rounded())) cm"
        }

        let totalInches = Int((heightCentimeters / 2.54).rounded())
        return "\(totalInches / 12) ft \(totalInches % 12) in"
    }

    private func loadFromSession() {
        guard let profile = session.onboardingProfile else { return }

        if let value = profile.dateOfBirth {
            includeDateOfBirth = true
            dateOfBirth = value
        } else {
            includeDateOfBirth = false
        }

        if let value = profile.healthSex {
            includeSex = true
            healthSex = value
        } else {
            includeSex = false
        }

        if let value = profile.weightKilograms {
            includeWeight = true
            weightKilograms = value
        } else {
            includeWeight = false
        }

        if let value = profile.heightCentimeters {
            includeHeight = true
            heightCentimeters = value
        } else {
            includeHeight = false
        }
    }
}

struct ATHLTHPrivacyCenterView: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var social: SocialStore

    var body: some View {
        Form {
            Section("Profile & Messages") {
                NavigationLink {
                    SocialPrivacySettingsView()
                } label: {
                    LabeledContent("Social profile", value: profileVisibilityTitle)
                }

                NavigationLink {
                    SocialPrivacySettingsView()
                } label: {
                    LabeledContent("Message requests", value: messagePrivacyTitle)
                }

                Text("Profile visibility, discoverability, friend requests, message requests and “Training now” presence are synced to your ATHLTH account.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Activities") {
                Picker(
                    "Default activity visibility",
                    selection: $settings.defaultActivityVisibility
                ) {
                    ForEach(ProfileVisibility.allCases) { visibility in
                        Text(visibility.title).tag(visibility)
                    }
                }

                Text("You can still change visibility during post-workout review before an activity is shared.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Routes") {
                Toggle(
                    "Hide route start & end",
                    isOn: $settings.hideRouteStartAndEnd
                )

                Text(
                    settings.hideRouteStartAndEnd
                        ? "ATHLTH removes roughly 250 m from both ends before a route is shared in Messages."
                        : "Shared routes include their full start and end points."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Label("Routes are shared only when you explicitly choose to share them.", systemImage: "hand.raised.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Health") {
                Label("Health data is private by default", systemImage: "heart.text.square.fill")
                    .foregroundStyle(ATHLTHTheme.accent)

                Text("Heart rate, sleep, weight and other Apple Health values are never attached automatically when you share a workout, route or plan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Personalization") {
                Toggle(
                    "Personalized ATHLTH offers",
                    isOn: Binding(
                        get: {
                            session.onboardingProfile?.personalizedOfferConsent == .granted
                        },
                        set: { enabled in
                            session.setPersonalizedOfferConsent(
                                enabled ? .granted : .declined
                            )
                        }
                    )
                )

                Text("Uses only goals and interests you choose in ATHLTH. Apple Health / HealthKit data is excluded from offer targeting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Safety") {
                NavigationLink {
                    BlockedUsersView()
                } label: {
                    Label("Blocked users", systemImage: "person.crop.circle.badge.xmark")
                }
            }
        }
        .navigationTitle("Privacy Center")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await social.refresh()
        }
    }

    private var profileVisibilityTitle: String {
        guard let raw = social.privacy?.profileVisibility,
              let value = ProfileVisibility(rawValue: raw)
        else {
            return settings.profileVisibility.title
        }
        return value.title
    }

    private var messagePrivacyTitle: String {
        switch social.privacy?.allowDirectMessages {
        case "requests": return "Friends + requests"
        case "friends": return "Friends only"
        case "nobody": return "Nobody"
        default: return "Review"
        }
    }
}

struct ATHLTHAccountSecurityView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var accountService: SupabaseAccountService
    @EnvironmentObject private var messaging: MessagingStore

    @State private var showingSignOutConfirmation = false
    @State private var signOutInProgress = false
    @State private var sendingReset = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    var body: some View {
        Form {
            Section("Account") {
                LabeledContent("Email", value: accountEmail)
                LabeledContent("Sign-in method", value: signInMethodTitle)
                LabeledContent(
                    "Member since",
                    value: session.accountCreatedAt.formatted(
                        date: .abbreviated,
                        time: .omitted
                    )
                )
            }

            if session.signInMethod == .email {
                Section("Security") {
                    Button {
                        Task { await sendPasswordReset() }
                    } label: {
                        HStack {
                            Label("Change Password", systemImage: "key.fill")
                            Spacer()
                            if sendingReset {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(sendingReset)

                    Text("ATHLTH sends a secure password-reset link to your account email.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if session.signInMethod == .apple {
                Section("Security") {
                    Label("Secured with Sign in with Apple", systemImage: "apple.logo")
                    Text("Your Apple ID controls authentication for this ATHLTH account.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Your data") {
                NavigationLink {
                    ATHLTHDataExportView()
                } label: {
                    Label("Export ATHLTH Data", systemImage: "square.and.arrow.up")
                }
            }

            Section {
                Button(role: .destructive) {
                    showingSignOutConfirmation = true
                } label: {
                    HStack {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        Spacer()
                        if signOutInProgress {
                            ProgressView()
                        }
                    }
                }
                .disabled(signOutInProgress)

                NavigationLink {
                    DeleteAccountView()
                } label: {
                    Label("Delete Account", systemImage: "trash")
                        .foregroundStyle(.red)
                }
            } footer: {
                Text("Deleting your account is permanent. Signing out keeps your account and clears account-specific cached data from this device.")
            }
        }
        .navigationTitle("Account & Security")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Sign out of ATHLTH?",
            isPresented: $showingSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                Task { await signOut() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            statusIsError ? "ATHLTH" : "Check Your Email",
            isPresented: Binding(
                get: { statusMessage != nil },
                set: { if !$0 { statusMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(statusMessage ?? "")
        }
    }

    private var accountEmail: String {
        if let email = accountService.currentEmail, !email.isEmpty {
            return email
        }

        return session.signInMethod == .apple
            ? "Managed by Apple"
            : "Unavailable"
    }

    private var signInMethodTitle: String {
        switch session.signInMethod {
        case .apple: return "Sign in with Apple"
        case .email: return "Email & password"
        case .none: return "ATHLTH account"
        }
    }

    private func sendPasswordReset() async {
        sendingReset = true
        statusMessage = nil
        defer { sendingReset = false }

        do {
            try await accountService.sendPasswordResetForCurrentAccount()
            statusIsError = false
            statusMessage = "We sent a secure password-reset link to \(accountEmail)."
        } catch {
            statusIsError = true
            statusMessage = error.localizedDescription
        }
    }

    private func signOut() async {
        signOutInProgress = true
        statusMessage = nil
        defer { signOutInProgress = false }

        do {
            try await accountService.signOut()
            messaging.reset()
            session.clearAfterSignOut()
        } catch {
            statusIsError = true
            statusMessage = error.localizedDescription
        }
    }
}


struct SpotifySettingsView: View {
    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "music.note")
                        .font(.title2)
                        .foregroundStyle(ATHLTHTheme.accent)
                        .frame(width: 44, height: 44)
                        .background(
                            ATHLTHTheme.accentSoft,
                            in: RoundedRectangle(cornerRadius: 14)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Spotify")
                            .font(.headline)
                        Text("Integration planned")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Planned integration") {
                Text("Spotify authorization and training-plan playlist playback are not enabled yet. ATHLTH will add the real connection flow before this setting becomes interactive.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Spotify")
        .navigationBarTitleDisplayMode(.inline)
    }
}

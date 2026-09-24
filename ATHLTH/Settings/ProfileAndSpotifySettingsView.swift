import PhotosUI
import SwiftUI
import UIKit

struct ATHLTHEditProfileView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var accountService: SupabaseAccountService
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var gear: ProfileGearStore

    @State private var displayName = ""
    @State private var username = ""
    @State private var bio = ""
    @State private var selectedTrainingFocus: TrainingFocus?
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

                    HStack(spacing: 10) {
                        PhotosPicker(
                            selection: $selectedPhoto,
                            matching: .images
                        ) {
                            Label(
                                selectedAvatarData == nil ? "Choose Photo" : "Change Photo",
                                systemImage: "photo"
                            )
                        }
                        .buttonStyle(.bordered)
                        .tint(ATHLTHTheme.accent)

                        if session.profile.avatarURL != nil || selectedAvatarData != nil {
                            Button(role: .destructive) {
                                Task { await removePhoto() }
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                            .disabled(saving)
                        }
                    }

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

            Section("Training Identity") {
                Picker("Training focus", selection: $selectedTrainingFocus) {
                    Text("Not set").tag(TrainingFocus?.none)
                    ForEach(TrainingFocus.allCases) { focus in
                        Label(focus.title, systemImage: focus.systemImage)
                            .tag(Optional(focus))
                    }
                }

                Text(
                    selectedTrainingFocus?.subtitle
                        ?? "Choose the training identity that best describes how you train."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("My Gear") {
                NavigationLink {
                    ProfileGearManagerView()
                } label: {
                    LabeledContent {
                        Text("\(gear.items.count) saved")
                            .foregroundStyle(.secondary)
                    } label: {
                        Label("Manage gear", systemImage: "backpack.fill")
                    }
                }

                Text("Save multiple watches, shoes, headphones and other gear. Pick one item in each category to show on your profile.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .task {
            await gear.refresh()
        }
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
        selectedTrainingFocus = session.onboardingProfile?.trainingFocus
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

    private func removePhoto() async {
        if selectedAvatarData != nil {
            selectedAvatarData = nil
            selectedPhoto = nil
            return
        }

        guard session.profile.avatarURL != nil else { return }

        saving = true
        errorMessage = nil
        defer { saving = false }

        do {
            let bootstrap = try await accountService.removeProfileAvatar()
            session.applyBackendBootstrap(bootstrap)
        } catch {
            errorMessage = error.localizedDescription
        }
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

            if let selectedTrainingFocus {
                session.setTrainingFocus(selectedTrainingFocus)
                await social.syncOwnTrainingFocus(selectedTrainingFocus)
            }

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

private enum HealthProfileField: String, Identifiable {
    case dateOfBirth
    case healthSex
    case weight
    case height

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dateOfBirth: return "Date of birth"
        case .healthSex: return "Sex for health calculations"
        case .weight: return "Weight"
        case .height: return "Height"
        }
    }

    var systemImage: String {
        switch self {
        case .dateOfBirth: return "calendar"
        case .healthSex: return "person.fill"
        case .weight: return "scalemass.fill"
        case .height: return "ruler.fill"
        }
    }
}

struct PersonalHealthProfileView: View {
    @Environment(\.dismiss) private var dismiss
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

    @State private var editingField: HealthProfileField?
    @State private var refreshingAppleHealth = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                sourceSection
                detailsSection
                privacySection
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 120)
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
        .navigationTitle("Health Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadFromSession)
        .sheet(item: $editingField) { field in
            healthEditor(for: field)
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("APPLE HEALTH SOURCE")

            ATHLTHCard {
                HStack(spacing: 14) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.pink)
                        .frame(width: 46, height: 46)
                        .background(
                            Color.pink.opacity(0.10),
                            in: RoundedRectangle(
                                cornerRadius: 14,
                                style: .continuous
                            )
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Apple Health")
                            .font(.headline)
                            .foregroundStyle(ATHLTHTheme.primaryText)

                        Text(sourceTitle)
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }

                    Spacer()

                    if refreshingAppleHealth {
                        ProgressView()
                            .tint(ATHLTHTheme.accent)
                    } else {
                        Image(
                            systemName: health.hasRequestedAuthorization
                                ? "checkmark.circle.fill"
                                : "circle"
                        )
                        .font(.title3)
                        .foregroundStyle(
                            health.hasRequestedAuthorization
                                ? ATHLTHTheme.accentDeep
                                : Color.secondary.opacity(0.5)
                        )
                    }
                }

                Divider()
                    .padding(.vertical, 12)

                Button {
                    refreshFromAppleHealth()
                } label: {
                    HStack {
                        Label(
                            health.hasRequestedAuthorization
                                ? "Refresh Apple Health"
                                : "Connect Apple Health",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                        .font(.subheadline.weight(.semibold))

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                }
                .buttonStyle(.plain)
                .disabled(refreshingAppleHealth)

                Text(
                    "ATHLTH uses only profile values Apple Health makes available. You can add or edit missing values below."
                )
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            }
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("HEALTH DETAILS")

            ATHLTHCard {
                healthDetailRow(
                    .dateOfBirth,
                    value: dateOfBirthDisplay,
                    isSet: includeDateOfBirth
                )

                Divider().padding(.leading, 48)

                healthDetailRow(
                    .healthSex,
                    value: includeSex ? healthSex.title : "Add",
                    isSet: includeSex
                )

                Divider().padding(.leading, 48)

                healthDetailRow(
                    .weight,
                    value: includeWeight ? weightDisplay : "Add",
                    isSet: includeWeight
                )

                Divider().padding(.leading, 48)

                healthDetailRow(
                    .height,
                    value: includeHeight ? heightDisplay : "Add",
                    isSet: includeHeight
                )
            }

            Text(
                "These values are used only for ATHLTH health and training calculations. They are not shown on your public profile."
            )
            .font(.caption)
            .foregroundStyle(ATHLTHTheme.mutedText)
            .padding(.horizontal, 6)
        }
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("PRIVACY")

            ATHLTHCard {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                        .frame(width: 44, height: 44)
                        .background(
                            ATHLTHTheme.accentSoft,
                            in: RoundedRectangle(
                                cornerRadius: 14,
                                style: .continuous
                            )
                        )

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Private health profile")
                            .font(.headline)
                            .foregroundStyle(ATHLTHTheme.primaryText)

                        Text(
                            "Date of birth, sex, weight and height stay private. Sharing health metrics always requires a separate explicit action."
                        )
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .tracking(2.4)
            .foregroundStyle(ATHLTHTheme.accentDeep.opacity(0.82))
            .padding(.leading, 16)
    }

    private func healthDetailRow(
        _ field: HealthProfileField,
        value: String,
        isSet: Bool
    ) -> some View {
        Button {
            editingField = field
        } label: {
            HStack(spacing: 12) {
                Image(systemName: field.systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .frame(width: 34)

                Text(field.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ATHLTHTheme.primaryText)

                Spacer(minLength: 10)

                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(
                        isSet
                            ? ATHLTHTheme.primaryText
                            : ATHLTHTheme.accentDeep
                    )
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func healthEditor(
        for field: HealthProfileField
    ) -> some View {
        NavigationStack {
            Form {
                Section {
                    switch field {
                    case .dateOfBirth:
                        DatePicker(
                            "Date of birth",
                            selection: $dateOfBirth,
                            in: ...Date(),
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)

                    case .healthSex:
                        Picker(
                            "Sex for health calculations",
                            selection: $healthSex
                        ) {
                            ForEach(HealthSex.allCases) { value in
                                Text(value.title).tag(value)
                            }
                        }
                        .pickerStyle(.inline)

                    case .weight:
                        VStack(spacing: 18) {
                            Text(weightDisplay)
                                .font(.system(size: 34, weight: .bold))
                                .monospacedDigit()
                                .frame(maxWidth: .infinity)

                            Stepper(
                                settings.measurementPreference == .metric
                                    ? "Adjust by 0.5 kg"
                                    : "Adjust by 1 lb",
                                value: weightBinding,
                                in: weightRange,
                                step: settings.measurementPreference == .metric
                                    ? 0.5
                                    : 1
                            )
                        }
                        .padding(.vertical, 8)

                    case .height:
                        VStack(spacing: 18) {
                            Text(heightDisplay)
                                .font(.system(size: 34, weight: .bold))
                                .monospacedDigit()
                                .frame(maxWidth: .infinity)

                            Stepper(
                                settings.measurementPreference == .metric
                                    ? "Adjust by 1 cm"
                                    : "Adjust by 1 in",
                                value: heightBinding,
                                in: heightRange,
                                step: 1
                            )
                        }
                        .padding(.vertical, 8)
                    }
                }

                if isFieldSet(field) {
                    Section {
                        Button("Remove value", role: .destructive) {
                            remove(field)
                        }
                    }
                }
            }
            .navigationTitle(field.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        loadFromSession()
                        editingField = nil
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        setFieldIncluded(field)
                        persistManualDetails()
                        editingField = nil
                    }
                    .fontWeight(.semibold)
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var sourceTitle: String {
        switch session.onboardingProfile?.personalDetailsSource ?? .none {
        case .appleHealth: return "Connected"
        case .mixed: return "Apple Health + manual details"
        case .manual: return "Manual details"
        case .none: return "Not connected"
        }
    }

    private var dateOfBirthDisplay: String {
        guard includeDateOfBirth else { return "Add" }
        return dateOfBirth.formatted(
            .dateTime
                .day()
                .month(.abbreviated)
                .year()
        )
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

    private func refreshFromAppleHealth() {
        guard !refreshingAppleHealth else { return }

        Task {
            refreshingAppleHealth = true
            defer { refreshingAppleHealth = false }

            await health.requestAuthorization()
            await health.completeAuthorizationSetup()
            await health.configureBackgroundSync(
                allowed: settings.backgroundHealthSyncEnabled
            )
            await health.refreshAll()
            await health.refreshPersonalDetails()

            if health.personalDetails.hasAnyValue {
                session.mergePersonalDetailsFromAppleHealth(
                    health.personalDetails
                )
            }

            loadFromSession()
        }
    }

    private func persistManualDetails() {
        let manualDetails = HealthProfileBasics(
            dateOfBirth: includeDateOfBirth ? dateOfBirth : nil,
            healthSex: includeSex ? healthSex : nil,
            weightKilograms: includeWeight ? weightKilograms : nil,
            heightCentimeters: includeHeight ? heightCentimeters : nil
        )

        let existingSource =
            session.onboardingProfile?.personalDetailsSource ?? .none
        let keepsAppleHealthLinked =
            existingSource == .appleHealth ||
            existingSource == .mixed

        session.updatePersonalDetails(
            manualDetails,
            source: keepsAppleHealthLinked ? .mixed : .manual
        )
    }

    private func isFieldSet(_ field: HealthProfileField) -> Bool {
        switch field {
        case .dateOfBirth: return includeDateOfBirth
        case .healthSex: return includeSex
        case .weight: return includeWeight
        case .height: return includeHeight
        }
    }

    private func setFieldIncluded(_ field: HealthProfileField) {
        switch field {
        case .dateOfBirth:
            includeDateOfBirth = true
        case .healthSex:
            includeSex = true
        case .weight:
            includeWeight = true
        case .height:
            includeHeight = true
        }
    }

    private func remove(_ field: HealthProfileField) {
        switch field {
        case .dateOfBirth:
            includeDateOfBirth = false
        case .healthSex:
            includeSex = false
        case .weight:
            includeWeight = false
        case .height:
            includeHeight = false
        }

        persistManualDetails()
        editingField = nil
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
                    VStack(alignment: .leading, spacing: 4) {
                        Label(
                            "Social & Messages",
                            systemImage: "person.2.badge.gearshape"
                        )
                        .font(.subheadline.weight(.semibold))

                        Text(
                            "\(profileVisibilityTitle) profile · \(messagePrivacyTitle)"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                }

                Text("Profile visibility, discoverability, friend requests, message requests and “Training now” presence are managed together and synced to your ATHLTH account.")
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

                Label(
                    "Leaderboards only use activity that is already visible to the viewer.",
                    systemImage: "trophy.fill"
                )
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
                        ? "Recommended · On by default. ATHLTH removes roughly 250 m from both ends before a route is shared in Messages."
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
        .navigationTitle("Privacy & Visibility")
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

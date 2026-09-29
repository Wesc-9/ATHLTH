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

    @FocusState private var focusedField: ProfileEditField?

    @AppStorage("hasEditedATHLTHProfile")
    private var hasEditedATHLTHProfile = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                profileHero
                publicIdentitySection
                trainingIdentitySection
                gearSection

                if let errorMessage {
                    errorBanner(errorMessage)
                }

                privacyFootnote
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 36)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(
            ATHLTHPremiumCanvas(
                accent: ATHLTHTheme.champagne.opacity(0.26)
            )
        )
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                saveToolbarControl
            }

            ToolbarItemGroup(placement: .keyboard) {
                Spacer()

                Button("Done") {
                    focusedField = nil
                }
            }
        }
        .onAppear(perform: loadCurrentProfile)
        .task {
            await gear.refresh()
        }
        .onChange(of: selectedPhoto) { _, newItem in
            guard let newItem else { return }

            Task {
                await prepareSelectedPhoto(newItem)
            }
        }
        .task(id: username) {
            await checkUsername()
        }
        .onChange(of: displayName) { _, _ in
            saved = false
        }
        .onChange(of: bio) { _, _ in
            saved = false
        }
        .onChange(of: selectedTrainingFocus) { _, _ in
            saved = false
        }
    }

    private var profileHero: some View {
        ATHLTHCard {
            VStack(spacing: 17) {
                ZStack(alignment: .bottomTrailing) {
                    avatarPreview
                        .frame(width: 122, height: 122)

                    PhotosPicker(
                        selection: $selectedPhoto,
                        matching: .images
                    ) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(
                                ATHLTHTheme.accentDeep,
                                in: Circle()
                            )
                            .overlay {
                                Circle()
                                    .stroke(
                                        Color.white,
                                        lineWidth: 3
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Change profile photo")
                }

                VStack(spacing: 4) {
                    Text(
                        displayName.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                            ? "Your profile"
                            : displayName
                    )
                    .font(
                        .system(
                            size: 23,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .multilineTextAlignment(.center)

                    if !cleanedUsername.isEmpty {
                        Text("@\(cleanedUsername)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                }

                HStack(spacing: 10) {
                    PhotosPicker(
                        selection: $selectedPhoto,
                        matching: .images
                    ) {
                        Label(
                            hasProfilePhoto
                                ? "Change photo"
                                : "Add photo",
                            systemImage: "photo.on.rectangle"
                        )
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 13)
                        .frame(height: 38)
                    }
                    .buttonStyle(.bordered)
                    .tint(ATHLTHTheme.accentDeep)

                    if hasProfilePhoto {
                        Button(role: .destructive) {
                            Task {
                                await removePhoto()
                            }
                        } label: {
                            Label(
                                "Remove",
                                systemImage: "trash"
                            )
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .frame(height: 38)
                        }
                        .buttonStyle(.bordered)
                        .disabled(saving)
                    }
                }

                HStack(spacing: 7) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Photo visibility follows your profile privacy settings.")
                }
                .font(.caption2)
                .foregroundStyle(ATHLTHTheme.mutedText)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var publicIdentitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(
                "Public identity",
                subtitle: "What people see when they open your profile."
            )

            ATHLTHCard {
                VStack(spacing: 0) {
                    profileTextField(
                        title: "Display name",
                        icon: "person.text.rectangle",
                        placeholder: "Your name",
                        text: $displayName,
                        contentType: .name,
                        field: .displayName
                    )

                    Divider()
                        .padding(.leading, 46)

                    VStack(alignment: .leading, spacing: 7) {
                        profileTextField(
                            title: "Username",
                            icon: "at",
                            placeholder: "username",
                            text: $username,
                            contentType: .username,
                            field: .username,
                            lowercase: true
                        )

                        usernameStatus
                            .padding(.leading, 46)
                            .padding(.bottom, 10)
                    }

                    Divider()
                        .padding(.leading, 46)

                    bioEditor
                }
            }
        }
    }

    private var bioEditor: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 12) {
                Image(systemName: "text.quote")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .frame(width: 34, height: 34)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: RoundedRectangle(
                            cornerRadius: 10,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Bio")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.mutedText)

                    Text("A short line about you or your training.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Text("\(bio.count)/160")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(
                        bio.count > 160
                            ? Color.red
                            : ATHLTHTheme.mutedText
                    )
            }

            ZStack(alignment: .topLeading) {
                if bio.isEmpty {
                    Text("Tell people what you're working toward…")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 13)
                }

                TextEditor(text: $bio)
                    .focused($focusedField, equals: .bio)
                    .font(.subheadline)
                    .frame(minHeight: 104)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
            }
            .background(
                ATHLTHTheme.surfaceStone.opacity(0.60),
                in: RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
                .stroke(
                    bio.count > 160
                        ? Color.red.opacity(0.35)
                        : Color.primary.opacity(0.045),
                    lineWidth: 1
                )
            }
        }
        .padding(.top, 13)
    }

    private var trainingIdentitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(
                "Training identity",
                subtitle: "Choose the focus that best reflects how you train."
            )

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(TrainingFocus.allCases) { focus in
                    trainingFocusCard(focus)
                }
            }

            if let selectedTrainingFocus {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.premiumGold)

                    Text(selectedTrainingFocus.subtitle)
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private var gearSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(
                "My gear",
                subtitle: "Equipment linked to your training and profile."
            )

            NavigationLink {
                ProfileGearManagerView()
            } label: {
                ATHLTHCard {
                    HStack(spacing: 13) {
                        Image(systemName: "backpack.fill")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .frame(width: 46, height: 46)
                            .background(
                                ATHLTHTheme.champagneSoft,
                                in: RoundedRectangle(
                                    cornerRadius: 14,
                                    style: .continuous
                                )
                            )

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Manage gear")
                                .font(.headline)
                                .foregroundStyle(
                                    ATHLTHTheme.primaryText
                                )

                            Text(
                                gear.items.isEmpty
                                    ? "Add shoes, watches and other equipment."
                                    : "\(gear.items.count) item\(gear.items.count == 1 ? "" : "s") saved"
                            )
                            .font(.caption)
                            .foregroundStyle(
                                ATHLTHTheme.mutedText
                            )
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var privacyFootnote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)

            Text(
                "Profile identity and health data stay separate. Visibility is controlled from your profile privacy settings."
            )
            .font(.caption)
            .foregroundStyle(ATHLTHTheme.mutedText)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    @ViewBuilder
    private var saveToolbarControl: some View {
        if saving {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Saving profile")
        } else if saved {
            Label("Saved", systemImage: "checkmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.vitality)
                .transition(.opacity)
        } else {
            Button {
                focusedField = nil
                Task {
                    await saveProfile()
                }
            } label: {
                Text("Save")
                    .fontWeight(.semibold)
            }
            .disabled(
                !canSave ||
                !hasUnsavedChanges
            )
            .accessibilityLabel("Save profile")
        }
    }

    private func sectionLabel(
        _ title: String,
        subtitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(1.65)
                .foregroundStyle(ATHLTHTheme.mutedText)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 3)
    }

    private func profileTextField(
        title: String,
        icon: String,
        placeholder: String,
        text: Binding<String>,
        contentType: UITextContentType?,
        field: ProfileEditField,
        lowercase: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(width: 34, height: 34)
                .background(
                    ATHLTHTheme.accentSoft,
                    in: RoundedRectangle(
                        cornerRadius: 10,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.mutedText)

                TextField(placeholder, text: text)
                    .focused($focusedField, equals: field)
                    .font(.body.weight(.medium))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .textContentType(contentType)
                    .textInputAutocapitalization(
                        lowercase ? .never : .words
                    )
                    .autocorrectionDisabled(lowercase)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }

    private func trainingFocusCard(
        _ focus: TrainingFocus
    ) -> some View {
        let selected = selectedTrainingFocus == focus

        return Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                selectedTrainingFocus = focus
                saved = false
            }

            UIImpactFeedbackGenerator(
                style: .light
            )
            .impactOccurred()
        } label: {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Image(systemName: focus.systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(
                            selected
                                ? ATHLTHTheme.vitality
                                : ATHLTHTheme.accentDeep
                        )
                        .frame(width: 40, height: 40)
                        .background(
                            selected
                                ? ATHLTHTheme.vitalitySoft
                                : ATHLTHTheme.accentSoft,
                            in: RoundedRectangle(
                                cornerRadius: 12,
                                style: .continuous
                            )
                        )

                    Spacer()

                    Image(
                        systemName:
                            selected
                                ? "checkmark.circle.fill"
                                : "circle"
                    )
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(
                        selected
                            ? ATHLTHTheme.vitality
                            : Color.secondary.opacity(0.55)
                    )
                }

                Text(focus.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .padding(13)
            .frame(
                maxWidth: .infinity,
                minHeight: 102,
                alignment: .topLeading
            )
            .background(
                selected
                    ? ATHLTHTheme.surfaceSage
                    : ATHLTHTheme.card,
                in: RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
                .stroke(
                    selected
                        ? ATHLTHTheme.vitality.opacity(0.28)
                        : Color.primary.opacity(0.05),
                    lineWidth: selected ? 1.4 : 1
                )
            }
            .shadow(
                color: Color.black.opacity(
                    selected ? 0.035 : 0.018
                ),
                radius: 8,
                y: 4
            )
        }
        .buttonStyle(.plain)
    }

    private func errorBanner(
        _ message: String
    ) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(
                systemName:
                    "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 3) {
                Text("Couldn’t save profile")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )

                Text(message)
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
            }

            Spacer()

            Button {
                errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            Color.orange.opacity(0.08),
            in: RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
            .stroke(
                Color.orange.opacity(0.18),
                lineWidth: 1
            )
        }
    }

    @ViewBuilder
    private var avatarPreview: some View {
        if let selectedAvatarData,
           let image = UIImage(
                data: selectedAvatarData
           ) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(
                            Color.white,
                            lineWidth: 3
                        )
                }
                .shadow(
                    color: ATHLTHTheme.accentDeep.opacity(0.14),
                    radius: 12,
                    y: 5
                )
        } else if let avatarURL =
                    session.profile.avatarURL {
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
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(
                        Color.white,
                        lineWidth: 3
                    )
            }
            .shadow(
                color: ATHLTHTheme.accentDeep.opacity(0.14),
                radius: 12,
                y: 5
            )
        } else {
            avatarFallback
        }
    }

    private var avatarFallback: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        ATHLTHTheme.accentSoft,
                        ATHLTHTheme.champagneSoft
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(
                        ATHLTHTheme.accent
                    )
            }
            .overlay {
                Circle()
                    .stroke(
                        Color.white,
                        lineWidth: 3
                    )
            }
    }

    @ViewBuilder
    private var usernameStatus: some View {
        let clean = cleanedUsername

        if clean ==
            session.profile.username.lowercased() {
            Label(
                "Current username",
                systemImage: "checkmark.circle.fill"
            )
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
            Label(
                "Username available",
                systemImage: "checkmark.circle.fill"
            )
            .font(.caption)
            .foregroundStyle(ATHLTHTheme.vitality)
        } else if usernameAvailable == false {
            Label(
                "Username unavailable or invalid",
                systemImage: "xmark.circle.fill"
            )
            .font(.caption)
            .foregroundStyle(.red)
        }
    }

    private var cleanedUsername: String {
        username
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .lowercased()
    }

    private var hasProfilePhoto: Bool {
        selectedAvatarData != nil ||
        session.profile.avatarURL != nil
    }

    private var hasUnsavedChanges: Bool {
        let cleanName =
            displayName.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        return cleanName != session.profile.displayName ||
            cleanedUsername != session.profile.username.lowercased() ||
            bio != session.profile.bio ||
            selectedTrainingFocus !=
                session.onboardingProfile?.trainingFocus ||
            selectedAvatarData != nil
    }

    private var canSave: Bool {
        let cleanName =
            displayName.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        let currentUsername =
            session.profile.username.lowercased()
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
        selectedTrainingFocus =
            session.onboardingProfile?.trainingFocus
        usernameAvailable = nil
        errorMessage = nil
        saved = false
    }

    private func prepareSelectedPhoto(
        _ item: PhotosPickerItem
    ) async {
        do {
            guard let data =
                    try await item.loadTransferable(
                        type: Data.self
                    ),
                  let image = UIImage(data: data),
                  let jpeg =
                    image.jpegData(
                        compressionQuality: 0.82
                    )
            else {
                throw ProfileEditingError.invalidImage
            }

            await MainActor.run {
                selectedAvatarData = jpeg
                errorMessage = nil
                saved = false
            }
        } catch {
            await MainActor.run {
                errorMessage =
                    error.localizedDescription
            }
        }
    }

    private func checkUsername() async {
        let clean = cleanedUsername

        guard clean !=
                session.profile.username.lowercased(),
              clean.count >= 3
        else {
            usernameAvailable = nil
            checkingUsername = false
            return
        }

        checkingUsername = true
        usernameAvailable = nil

        try? await Task.sleep(
            nanoseconds: 450_000_000
        )
        guard !Task.isCancelled else { return }

        do {
            let available =
                try await accountService
                    .isUsernameAvailable(clean)

            guard !Task.isCancelled else {
                return
            }

            usernameAvailable = available
        } catch {
            guard !Task.isCancelled else {
                return
            }

            usernameAvailable = false
        }

        checkingUsername = false
    }

    @MainActor
    private func removePhoto() async {
        if selectedAvatarData != nil {
            selectedAvatarData = nil
            selectedPhoto = nil
            saved = false
            return
        }

        guard session.profile.avatarURL != nil else {
            return
        }

        saving = true
        errorMessage = nil
        defer { saving = false }

        do {
            let bootstrap =
                try await accountService
                    .removeProfileAvatar()

            session.applyBackendBootstrap(bootstrap)

            UINotificationFeedbackGenerator()
                .notificationOccurred(.success)
        } catch {
            errorMessage =
                error.localizedDescription
        }
    }

    @MainActor
    private func saveProfile() async {
        guard canSave,
              hasUnsavedChanges
        else {
            return
        }

        saving = true
        saved = false
        errorMessage = nil
        defer { saving = false }

        do {
            var avatarURL =
                session.profile.avatarURL

            if let selectedAvatarData {
                avatarURL =
                    try await accountService
                        .uploadProfileAvatar(
                            jpegData:
                                selectedAvatarData
                        )
            }

            let bootstrap =
                try await accountService
                    .updateProfile(
                        displayName: displayName,
                        username: cleanedUsername,
                        bio: bio,
                        avatarURL: avatarURL
                    )

            session.applyBackendBootstrap(bootstrap)

            if let selectedTrainingFocus {
                session.setTrainingFocus(
                    selectedTrainingFocus
                )

                await social.syncOwnTrainingFocus(
                    selectedTrainingFocus
                )
            }

            selectedAvatarData = nil
            selectedPhoto = nil
            hasEditedATHLTHProfile = true
            saved = true

            UINotificationFeedbackGenerator()
                .notificationOccurred(.success)

            Task { @MainActor in
                try? await Task.sleep(
                    nanoseconds: 1_600_000_000
                )

                saved = false
            }
        } catch {
            errorMessage =
                error.localizedDescription

            UINotificationFeedbackGenerator()
                .notificationOccurred(.error)
        }
    }
}

private enum ProfileEditField: Hashable {
    case displayName
    case username
    case bio
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
    case maximumHeartRate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dateOfBirth: return "Date of birth"
        case .healthSex: return "Sex for health calculations"
        case .weight: return "Weight"
        case .height: return "Height"
        case .maximumHeartRate: return "Maximum heart rate"
        }
    }

    var systemImage: String {
        switch self {
        case .dateOfBirth: return "calendar"
        case .healthSex: return "person.fill"
        case .weight: return "scalemass.fill"
        case .height: return "ruler.fill"
        case .maximumHeartRate: return "heart.circle.fill"
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
    @State private var includeMaximumHeartRate = false
    @State private var maximumHeartRateBPM = 190

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

                Divider().padding(.leading, 48)

                healthDetailRow(
                    .maximumHeartRate,
                    value:
                        includeMaximumHeartRate
                            ? "\(maximumHeartRateBPM) bpm"
                            : "Add",
                    isSet: includeMaximumHeartRate
                )
            }

            Text(
                "These values are used only for ATHLTH health and training calculations. A known maximum heart rate becomes the source of truth for heart-rate zones and workout alerts. They are not shown on your public profile."
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
                            "Date of birth, sex, weight, height and maximum heart rate stay private. Sharing health metrics always requires a separate explicit action."
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

                    case .maximumHeartRate:
                        VStack(spacing: 18) {
                            Text("\(maximumHeartRateBPM) bpm")
                                .font(.system(size: 34, weight: .bold))
                                .monospacedDigit()
                                .frame(maxWidth: .infinity)

                            Stepper(
                                "Adjust by 1 bpm",
                                value: $maximumHeartRateBPM,
                                in: 100...240,
                                step: 1
                            )

                            Text(
                                "If you know your tested or measured maximum heart rate, enter it here. ATHLTH will use this value instead of an estimated max when calculating heart-rate zones."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(
                                horizontal: false,
                                vertical: true
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
            heightCentimeters: includeHeight ? heightCentimeters : nil,
            maximumHeartRateBPM:
                includeMaximumHeartRate
                    ? maximumHeartRateBPM
                    : nil
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
        case .maximumHeartRate:
            return includeMaximumHeartRate
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
        case .maximumHeartRate:
            includeMaximumHeartRate = true
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
        case .maximumHeartRate:
            includeMaximumHeartRate = false
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

        if let value = profile.maximumHeartRateBPM {
            includeMaximumHeartRate = true
            maximumHeartRateBPM = value
        } else {
            includeMaximumHeartRate = false
        }
    }
}

struct ATHLTHPrivacyCenterView: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var social: SocialStore

    @State private var draft: SocialPrivacySettings?
    @State private var saving = false
    @State private var saved = false
    @State private var saveError: String?

    var body: some View {
        Form {
            if let binding = draftBinding {
                Section("Social & Messages") {
                    Picker(
                        "Profile visibility",
                        selection: binding.profileVisibility
                    ) {
                        Text("Private").tag("private")
                        Text("Friends").tag("friends")
                        Text("Public").tag("public")
                    }

                    Toggle(
                        "Allow friend requests",
                        isOn: binding.allowFriendRequests
                    )

                    Picker(
                        "Who can message me",
                        selection: binding.allowDirectMessages
                    ) {
                        Text("Friends + requests").tag("requests")
                        Text("Friends only").tag("friends")
                        Text("Nobody").tag("nobody")
                    }

                    Text(
                        "Message requests allow one initial message from people who are not yet your friends. Blocking always stops messaging."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section("What Others Can See") {
                    Toggle(
                        "Show when I'm online",
                        isOn: Binding(
                            get: {
                                social
                                    .shareOnlineStatus
                            },
                            set: { enabled in
                                Task {
                                    await social
                                        .setShareOnlineStatus(
                                            enabled
                                        )
                                }
                            }
                        )
                    )

                    Text(
                        "Online status is visible to followers only and is off by default."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Toggle(
                        "Training now",
                        isOn: binding.shareTrainingPresence
                    )
                    Toggle(
                        "Performance stats",
                        isOn: binding.sharePerformanceStats
                    )
                    Toggle(
                        "Trophy cabinet",
                        isOn: binding.shareTrophyCabinet
                    )
                    Toggle(
                        "Recent activity",
                        isOn: binding.shareRecentActivity
                    )
                    Toggle(
                        "Running PRs",
                        isOn: binding.shareRunningPRs
                    )
                    Toggle(
                        "Strength PRs",
                        isOn: binding.shareStrengthPRs
                    )
                    Toggle(
                        "Completed goals",
                        isOn: binding.shareGoals
                    )
                    Toggle(
                        "Workout totals",
                        isOn: binding.shareWorkoutTotals
                    )

                    Text(
                        "These controls decide which profile sections are shared with viewers allowed by your profile visibility."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section("Challenges") {
                    Picker(
                        "Challenge invites",
                        selection: binding.allowChallengeInvites
                    ) {
                        Text("Friends").tag("friends")
                        Text("Everyone").tag("everyone")
                        Text("Nobody").tag("nobody")
                    }
                }

                Section {
                    if saving {
                        ProgressView("Saving…")
                    } else if let saveError {
                        Label("Changes could not be saved", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                        Text(saveError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Retry") {
                            schedulePrivacySave()
                        }
                    } else if saved {
                        Label("Saved", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Changes save automatically")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Section("Social & Messages") {
                    HStack {
                        Spacer()
                        ProgressView("Loading privacy settings…")
                        Spacer()
                    }
                }
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

                Text(
                    "You can still change visibility during post-workout review before an activity is shared."
                )
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
                        ? "Recommended · ATHLTH removes roughly 250 m from both ends before a route is shared."
                        : "Shared routes include their full start and end points."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Label(
                    "Routes are shared only when you explicitly choose to share them.",
                    systemImage: "hand.raised.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Health Data") {
                Label(
                    "Health data is private by default",
                    systemImage: "heart.text.square.fill"
                )
                .foregroundStyle(ATHLTHTheme.accent)

                Text(
                    "Heart rate, sleep, weight and other Apple Health values are never attached automatically when you share a workout, route or plan."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("ATHLTH Coach & AI") {
                Toggle(
                    "Allow Coach to use health data",
                    isOn: Binding(
                        get: {
                            session.aiHealthDataSharingEnabled
                        },
                        set: { enabled in
                            session.setAIHealthDataSharingEnabled(
                                enabled
                            )
                        }
                    )
                )

                Text(
                    session.aiHealthDataSharingEnabled
                        ? "ATHLTH Coach may send the minimum relevant health context, such as sleep, HRV, heart rate and workout metrics, through ATHLTH's backend to the configured AI provider. You can turn this off at any time."
                        : "Off by default. Recovery and workout insights stay local and deterministic until you explicitly allow health data to be used by ATHLTH Coach."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Label(
                    "This is separate from Apple Health permission, cloud backup and personalized offers.",
                    systemImage: "lock.shield.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Personalization") {
                Toggle(
                    "Personalized ATHLTH offers",
                    isOn: Binding(
                        get: {
                            session.onboardingProfile?
                                .personalizedOfferConsent == .granted
                        },
                        set: { enabled in
                            session.setPersonalizedOfferConsent(
                                enabled ? .granted : .declined
                            )
                        }
                    )
                )

                Text(
                    "Uses only goals and interests you choose in ATHLTH. Apple Health / HealthKit data is excluded from offer targeting."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Safety") {
                NavigationLink {
                    BlockedUsersView()
                } label: {
                    Label(
                        "Blocked users",
                        systemImage: "person.crop.circle.badge.xmark"
                    )
                }
            }
        }
        .navigationTitle("Privacy & Data")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard draft == nil else { return }
            if social.privacy == nil {
                await social.refresh()
            }

            draft = social.privacy
        }
    }

    private var draftBinding: Binding<SocialPrivacySettings>? {
        guard draft != nil else {
            return nil
        }

        return Binding(
            get: { draft! },
            set: { updated in
                guard updated != draft else { return }
                draft = updated
                schedulePrivacySave()
            }
        )
    }

    @MainActor
    private func schedulePrivacySave() {
        saved = false
        saveError = nil
        guard !saving, draft != nil else { return }
        saving = true

        // Keep one writer alive when navigating away. Edits made during a
        // request are coalesced into the next write, never sent concurrently.
        Task { @MainActor in
            defer { saving = false }
            while let snapshot = draft {
                let result = await social.updatePrivacy(snapshot)
                if case .failure(let error) = result {
                    saveError = error.localizedDescription
                    return
                }
                guard draft == snapshot else { continue }

                // Only mirror the final confirmed values locally. This also
                // avoids triggering core-privacy observers with stale values.
                if let visibility = ProfileVisibility(rawValue: snapshot.profileVisibility) {
                    settings.profileVisibility = visibility
                }
                settings.shareTrainingPresence = snapshot.shareTrainingPresence
                draft = social.privacy ?? snapshot
                saved = true
                return
            }
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
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var spotify: SpotifyPlaybackStore

    @State private var showingPlaylistPreview = false
    @State private var previewSelection: SpotifyPlaylistReference?

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
                        Text(spotify.connectionState.title)
                            .font(.caption)
                            .foregroundStyle(
                                spotify.isConnected
                                    ? ATHLTHTheme.accentDeep
                                    : .secondary
                            )
                    }

                    Spacer()

                    if spotify.connectionState == .connecting ||
                        spotify.isRefreshingPlaylists {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }

            if !spotify.isConfigured {
                Section("Developer Setup") {
                    Label(
                        "Spotify client ID is not configured for this build.",
                        systemImage: "wrench.and.screwdriver"
                    )
                    .font(.subheadline)

                    Text(
                        spotify.setupMessage
                            ?? "Configure Spotify before connecting an account."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Text("Redirect URI: athlth-spotify-login://callback")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            } else if spotify.isConnected {
                Section("Workout Playback") {
                    Toggle(
                        "Start linked playlist with workout",
                        isOn: $settings.spotifyAutoplayLinkedPlaylists
                    )

                    Button {
                        previewSelection = spotify.playlists.first
                        showingPlaylistPreview = true
                    } label: {
                        HStack {
                            Label(
                                "Browse Spotify playlists",
                                systemImage: "music.note.list"
                            )
                            Spacer()
                            Text("\(spotify.playlists.count)")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(
                        "A program can link one Spotify playlist. On iPhone, ATHLTH can wake Spotify and start that playlist when the workout begins. Apple Watch workouts never wait for Spotify."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        Task {
                            await spotify.refreshPlaylists()
                        }
                    } label: {
                        Label(
                            "Refresh Playlists",
                            systemImage: "arrow.clockwise"
                        )
                    }

                    Button(role: .destructive) {
                        spotify.disconnect()
                        settings.spotifyConnected = false
                    } label: {
                        Label(
                            "Disconnect Spotify",
                            systemImage: "link.badge.minus"
                        )
                    }
                }
            } else {
                Section("Connect") {
                    Button {
                        spotify.connect()
                    } label: {
                        Label(
                            "Connect Spotify",
                            systemImage: "link"
                        )
                    }
                    .disabled(spotify.connectionState == .connecting)

                    Text(
                        "ATHLTH requests only the Spotify access needed to read your playlists and control playback you start from a workout."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if let error = spotify.lastErrorMessage,
               !error.isEmpty {
                Section("Status") {
                    Label(
                        error,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }

            Section("Apple Watch") {
                Text(
                    "Watch-only training stays independent. ATHLTH will not show an “open Spotify first” prompt and will never block Start Workout because Spotify is unavailable."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Spotify")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPlaylistPreview) {
            SpotifyPlaylistPickerView(
                title: "Spotify Playlists",
                selection: $previewSelection
            )
        }
        .task {
            settings.spotifyConnected = spotify.isConnected

            if spotify.isConnected &&
                spotify.playlists.isEmpty {
                await spotify.refreshPlaylists()
            }
        }
        .onChange(of: spotify.connectionState) { _, _ in
            settings.spotifyConnected = spotify.isConnected
        }
    }
}

import PhotosUI
import SwiftUI
import UIKit

struct ATHLTHEditProfileView: View {
    @EnvironmentObject private var session: AppSessionStore
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountService: SupabaseAccountService
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var gear: ProfileGearStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var realtime: ATHLTHRealtimeSocialStore

    // Allows the same header picker and upload/cropping flow to be
    // reused from the profile hero instead of creating a second editor.
    var onEditHeader: (() -> Void)? = nil

    @State private var displayName = ""
    @State private var username = ""
    @State private var bio = ""
    @State private var selectedTrainingFocuses: Set<ProfileTrainingFocus> = []
    @State private var trainingFocusExpanded = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedAvatarData: Data?
    @State private var pendingAvatarCropImage: UIImage?
    @State private var showingAvatarCrop = false
    @State private var usernameAvailable: Bool?
    @State private var checkingUsername = false
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var showingRemoveAvatarConfirmation = false
    @State private var showingRemoveHeaderConfirmation = false
    @State private var removingHeader = false
    @State private var editingPublicField: PublicProfileField?
    @State private var loadedProfile = false
    @State private var showOnlineStatus = false
    @State private var showTrainingStatus = false
    @State private var presenceChoicesLoaded = false
    @State private var presenceChoicesError: String?

    private enum PublicProfileField: String, Identifiable {
        case name, username, bio

        var id: String { rawValue }

        var title: String {
            switch self {
            case .name:
                return ATHLTHLocalization.choose(english: "Display name", norwegian: "Visningsnavn")
            case .username:
                return ATHLTHLocalization.choose(english: "Username", norwegian: "Brukernavn")
            case .bio:
                return "Bio"
            }
        }
    }

    @AppStorage("hasEditedATHLTHProfile")
    private var hasEditedATHLTHProfile = false

    var body: some View {
        ZStack {
            ATHLTHPremiumCanvas(
                accent: ATHLTHTheme.premiumGold.opacity(0.34)
            )

            ScrollView {
                LazyVStack(spacing: 18) {
                    profileIdentityCard

                    VStack(spacing: 12) {
                        ATHLTHSectionHeader(title: ATHLTHLocalization.choose(
                            english: "Public profile",
                            norwegian: "Offentlig profil"
                        ))
                            .padding(.horizontal, 2)

                        publicProfileCard
                    }

                    VStack(spacing: 12) {
                        ATHLTHSectionHeader(title: "Training identity")
                            .padding(.horizontal, 2)

                        trainingIdentityCard
                    }

                    activityStatusCard

                    VStack(spacing: 12) {
                        ATHLTHSectionHeader(
                            title:
                                ATHLTHLocalization.choose(
                                    english: "My gear",
                                    norwegian: "Mitt utstyr"
                                )
                        )
                            .padding(.horizontal, 2)

                        gearCard
                    }

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .frame(width: 30, height: 30)
                            .background(
                                ATHLTHTheme.accentSoft,
                                in: RoundedRectangle(
                                    cornerRadius: 10,
                                    style: .continuous
                                )
                            )

                        Text(
                            "Display name, username, bio and profile photo are social profile data. Health details remain private and are managed separately."
                        )
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 12)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 120)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(
            ATHLTHLocalization.choose(
                english: "Edit profile",
                norwegian: "Rediger profil"
            )
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await saveProfile() }
                } label: {
                    Group {
                        if saving {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                                .frame(width: 48)
                        } else {
                            Text(ATHLTHLocalization.choose(
                                english: "Save", norwegian: "Lagre"
                            ))
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 48)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 8)
                    .background(
                        canSave && !saving
                            ? ATHLTHTheme.accentDeep
                            : ATHLTHTheme.mutedText.opacity(0.45),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canSave || saving)
                .accessibilityLabel(
                    saving ? "Saving profile" : "Save profile"
                )
            }
        }
        .onAppear(perform: loadCurrentProfile)
        .sheet(item: $editingPublicField) { field in
            publicFieldEditor(for: field)
        }
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english: "Remove profile picture?",
                norwegian: "Fjerne profilbildet?"
            ),
            isPresented: $showingRemoveAvatarConfirmation,
            titleVisibility: .visible
        ) {
            Button(ATHLTHLocalization.choose(
                english: "Remove picture", norwegian: "Fjern bilde"
            ), role: .destructive) {
                Task { await removePhoto() }
            }
            Button(ATHLTHLocalization.choose(
                english: "Cancel", norwegian: "Avbryt"
            ), role: .cancel) {}
        } message: {
            Text(ATHLTHLocalization.choose(
                english: "The profile will show a default avatar.",
                norwegian: "Profilen viser standardikonet når bildet fjernes."
            ))
        }
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english: "Remove profile header?",
                norwegian: "Fjerne headerbildet?"
            ),
            isPresented: $showingRemoveHeaderConfirmation,
            titleVisibility: .visible
        ) {
            Button(ATHLTHLocalization.choose(
                english: "Remove header picture", norwegian: "Fjern headerbilde"
            ), role: .destructive) {
                Task { await resetHeaderPicture() }
            }
            Button(ATHLTHLocalization.choose(
                english: "Cancel", norwegian: "Avbryt"
            ), role: .cancel) {}
        } message: {
            Text(ATHLTHLocalization.choose(
                english: "Your profile header will return to ATHLTH's default image.",
                norwegian: "Profilheaderen går tilbake til standardbildet fra ATHLTH."
            ))
        }
        .task {
            await gear.refresh()
            await loadActivityStatus()
        }
        .onChange(of: selectedPhoto) { _, newItem in
            guard let newItem else { return }
            Task {
                do {
                    guard
                        let data = try await newItem.loadTransferable(
                            type: Data.self
                        ),
                        let image = UIImage(data: data),
                        let preparedImage =
                            ATHLTHAvatarCropper.prepare(image)
                    else {
                        throw ProfileEditingError.invalidImage
                    }

                    await MainActor.run {
                        pendingAvatarCropImage = preparedImage
                        showingAvatarCrop = true
                        errorMessage = nil
                    }
                } catch {
                    await MainActor.run {
                        selectedPhoto = nil
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
        .fullScreenCover(
            isPresented: $showingAvatarCrop
        ) {
            if let pendingAvatarCropImage {
                ATHLTHAvatarCropView(
                    image: pendingAvatarCropImage,
                    onCancel: {
                        selectedPhoto = nil
                        self.pendingAvatarCropImage = nil
                        showingAvatarCrop = false
                    },
                    onUse: { jpegData in
                        selectedAvatarData = jpegData
                        selectedPhoto = nil
                        self.pendingAvatarCropImage = nil
                        showingAvatarCrop = false
                    }
                )
            }
        }
        .task(id: username) {
            await checkUsername()
        }
        .alert(
            "ATHLTH",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: {
                    if !$0 {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var profileIdentityCard: some View {
        ATHLTHCard {
            VStack(spacing: 10) {
                ZStack(alignment: .bottom) {
                    headerPicturePreview
                        .overlay(alignment: .topTrailing) {
                            if hasCustomHeader {
                                removePictureButton(
                                    label: ATHLTHLocalization.choose(
                                        english: "Remove header picture",
                                        norwegian: "Fjern headerbilde"
                                    ),
                                    disabled: saving || removingHeader
                                ) {
                                    showingRemoveHeaderConfirmation = true
                                }
                                .padding(9)
                            }
                        }

                    avatarPreview
                        .overlay(alignment: .topTrailing) {
                            if session.profile.avatarURL != nil ||
                                selectedAvatarData != nil {
                                removePictureButton(
                                    label: ATHLTHLocalization.choose(
                                        english: "Remove profile picture",
                                        norwegian: "Fjern profilbilde"
                                    ),
                                    disabled: saving
                                ) {
                                    showingRemoveAvatarConfirmation = true
                                }
                                .offset(x: 5, y: -2)
                            }
                        }
                        .overlay(alignment: .bottomTrailing) {
                            PhotosPicker(
                                selection: $selectedPhoto,
                                matching: .images
                            ) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 34, height: 34)
                                    .background(ATHLTHTheme.accentDeep, in: Circle())
                                    .overlay {
                                        Circle().stroke(.white, lineWidth: 2)
                                    }
                            }
                            .buttonStyle(.plain)
                            .disabled(saving)
                            .accessibilityLabel(ATHLTHLocalization.choose(
                                english: "Change profile picture",
                                norwegian: "Bytt profilbilde"
                            ))
                            .offset(x: 2, y: 2)
                        }
                        .offset(y: 58)
                }
                .padding(.bottom, 58)

                VStack(spacing: 5) {
                    Text(displayName.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                        ? ATHLTHLocalization.choose(
                            english: "Your profile", norwegian: "Din profil"
                        )
                        : displayName)
                        .font(.system(size: 28, weight: .regular, design: .serif))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    if !cleanedUsername.isEmpty {
                        Text("@\(cleanedUsername)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(ATHLTHTheme.mutedText)
                            .lineLimit(1)
                    }

                    Label(
                        visibilityLabel,
                        systemImage: "globe"
                    )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(ATHLTHTheme.champagneSoft, in: Capsule())
                    .padding(.top, 3)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 9)

                Rectangle()
                    .fill(ATHLTHTheme.divider)
                    .frame(height: 0.7)

                HStack(spacing: 10) {
                    PhotosPicker(
                        selection: $selectedPhoto,
                        matching: .images
                    ) {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Change picture",
                                norwegian: "Bytt bilde"
                            ),
                            systemImage: "photo.on.rectangle"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(
                            ATHLTHTheme.accentSoft,
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(saving)

                    if let onEditHeader {
                        Button(action: onEditHeader) {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Change header picture",
                                    norwegian: "Endre headerbilde"
                                ),
                                systemImage: "photo.on.rectangle.angled"
                            )
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .lineLimit(1)
                            .minimumScaleFactor(0.80)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(
                                ATHLTHTheme.champagneSoft,
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(removingHeader || saving)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var hasCustomHeader: Bool {
        session.profile.headerImageURL != nil ||
            (session.profile.headerArtworkName != nil &&
             session.profile.headerArtworkName != "ProfileHero")
    }

    private var visibilityLabel: String {
        switch social.privacy?.profileVisibility {
        case "private":
            return ATHLTHLocalization.choose(
                english: "Private profile", norwegian: "Privat profil"
            )
        case "friends":
            return ATHLTHLocalization.choose(
                english: "Followers", norwegian: "Følgere"
            )
        case "public":
            return ATHLTHLocalization.choose(
                english: "Public identity", norwegian: "Offentlig identitet"
            )
        default:
            return ATHLTHLocalization.choose(
                english: "Visibility not loaded", norwegian: "Synlighet ikke lastet"
            )
        }
    }

    private var headerPicturePreview: some View {
        GeometryReader { viewport in
            Group {
                if let url = session.profile.headerImageURL {
                    ATHLTHStorageImage(url: url, maxPixelSize: 900) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            Image(session.profile.headerArtworkName ?? "ProfileHero")
                                .resizable().scaledToFill()
                        }
                    }
                } else {
                    Image(session.profile.headerArtworkName ?? "ProfileHero")
                        .resizable().scaledToFill()
                }
            }
            .frame(width: viewport.size.width, height: viewport.size.height)
            .clipped()
        }
        .frame(height: 158)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityHidden(true)
    }

    private func removePictureButton(
        label: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(ATHLTHTheme.accentDeep.opacity(0.88), in: Circle())
                .overlay {
                    Circle().stroke(.white.opacity(0.96), lineWidth: 1.5)
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(label)
    }

    private var publicProfileCard: some View {
        ATHLTHCard {
            VStack(spacing: 0) {
                publicProfileRow(
                    title: ATHLTHLocalization.choose(
                        english: "Display name", norwegian: "Visningsnavn"
                    ),
                    subtitle: ATHLTHLocalization.choose(
                        english: "Shown on your ATHLTH profile.",
                        norwegian: "Vises på profilen din."
                    ),
                    value: displayName,
                    icon: "person.fill"
                ) {
                    editingPublicField = .name
                }

                profileDivider

                publicProfileRow(
                    title: ATHLTHLocalization.choose(
                        english: "Username", norwegian: "Brukernavn"
                    ),
                    subtitle: ATHLTHLocalization.choose(
                        english: "Your unique ATHLTH identity.",
                        norwegian: "Din unike identitet på ATHLTH."
                    ),
                    value: "@\(cleanedUsername)",
                    icon: "at"
                ) {
                    editingPublicField = .username
                }

                profileDivider

                publicProfileRow(
                    title: "Bio",
                    subtitle: ATHLTHLocalization.choose(
                        english: "Tell people a little about yourself.",
                        norwegian: "Fortell litt om deg selv."
                    ),
                    value: bio.isEmpty
                        ? ATHLTHLocalization.choose(
                            english: "Add bio", norwegian: "Legg til bio"
                        )
                        : bio,
                    icon: "text.alignleft"
                ) {
                    editingPublicField = .bio
                }

                profileDivider

                NavigationLink {
                    SocialPrivacySettingsView()
                } label: {
                    publicProfileRowContent(
                        title: ATHLTHLocalization.choose(
                            english: "Visibility", norwegian: "Synlighet"
                        ),
                        subtitle: ATHLTHLocalization.choose(
                            english: "Choose who can see your profile.",
                            norwegian: "Velg hvem som kan se profilen."
                        ),
                        value: visibilityLabel,
                        icon: "eye"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func publicProfileRow(
        title: String,
        subtitle: String,
        value: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            publicProfileRowContent(
                title: title, subtitle: subtitle, value: value, icon: icon
            )
        }
        .buttonStyle(.plain)
    }

    private func publicProfileRowContent(
        title: String,
        subtitle: String,
        value: String,
        icon: String
    ) -> some View {
        HStack(spacing: 11) {
            profileFieldIcon(icon)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 6)

            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ATHLTHTheme.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 116, alignment: .trailing)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.mutedText)
        }
        .frame(minHeight: 72)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func publicFieldEditor(
        for field: PublicProfileField
    ) -> some View {
        NavigationStack {
            Form {
                Section {
                    switch field {
                    case .name:
                        TextField(
                            ATHLTHLocalization.choose(
                                english: "Display name", norwegian: "Visningsnavn"
                            ),
                            text: $displayName
                        )
                        .textContentType(.name)
                    case .username:
                        TextField(
                            ATHLTHLocalization.choose(
                                english: "Username", norwegian: "Brukernavn"
                            ),
                            text: $username
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)

                        usernameStatus
                    case .bio:
                        TextField(
                            ATHLTHLocalization.choose(
                                english: "Tell people about yourself",
                                norwegian: "Fortell litt om deg selv"
                            ),
                            text: $bio,
                            axis: .vertical
                        )
                        .lineLimit(3...7)
                        Text("\(bio.count)/160")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(
                                bio.count > 160 ? Color.red : ATHLTHTheme.mutedText
                            )
                    }
                } footer: {
                    Text(ATHLTHLocalization.choose(
                        english: "Your changes will be saved when you tap Save on the profile screen.",
                        norwegian: "Endringene lagres når du trykker Lagre på profilsiden."
                    ))
                }
            }
            .navigationTitle(field.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Done", norwegian: "Ferdig"
                    )) {
                        editingPublicField = nil
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }


    private var trainingIdentityCard: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 13) {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        trainingFocusExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 12) {
                        profileFieldIcon("bolt.heart.fill")
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ATHLTHLocalization.choose(
                                english: "Training focus",
                                norwegian: "Treningsfokus"
                            ))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.primaryText)
                            Text(selectedTrainingFocuses.isEmpty
                                ? ATHLTHLocalization.choose(
                                    english: "Choose how you train",
                                    norwegian: "Velg hvordan du trener"
                                )
                                : ATHLTHLocalization.choose(
                                    english: "\(selectedTrainingFocuses.count) selected · Tap to edit",
                                    norwegian: "\(selectedTrainingFocuses.count) valgt · Trykk for å endre"
                                ))
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                        }
                        Spacer(minLength: 6)
                        Image(systemName: trainingFocusExpanded ? "chevron.up" : "chevron.down")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(ATHLTHLocalization.choose(
                    english: "Expand or collapse training focus choices",
                    norwegian: "Vis eller skjul valg for treningsfokus"
                ))

                if !selectedTrainingFocuses.isEmpty {
                    // Compact when collapsed, while retaining all selected labels.
                    ViewThatFits(in: .vertical) {
                        trainingFocusChips
                    }
                }

                if trainingFocusExpanded {
                    profileDivider
                    Text(ATHLTHLocalization.choose(
                        english: "Select as many as you like",
                        norwegian: "Velg så mange du ønsker"
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)

                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)],
                        spacing: 9
                    ) {
                        ForEach(ProfileTrainingFocus.allCases) { focus in
                            trainingFocusChoice(focus)
                        }
                    }
                }
            }
        }
    }

    private var trainingFocusChips: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 112), spacing: 7)],
            alignment: .leading,
            spacing: 7
        ) {
            ForEach(ProfileTrainingFocus.allCases.filter {
                selectedTrainingFocuses.contains($0)
            }) { focus in
                Label(focus.title, systemImage: focus.systemImage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ATHLTHTheme.accentSoft, in: Capsule())
            }
        }
    }

    private func trainingFocusChoice(_ focus: ProfileTrainingFocus) -> some View {
        let selected = selectedTrainingFocuses.contains(focus)
        return Button {
            if selected {
                selectedTrainingFocuses.remove(focus)
            } else {
                selectedTrainingFocuses.insert(focus)
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: focus.systemImage)
                        .font(.system(size: 18, weight: .medium))
                    Spacer(minLength: 2)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15))
                }
                Text(focus.title)
                    .font(.system(size: 12, weight: .semibold))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(selected ? ATHLTHTheme.accentDeep : ATHLTHTheme.primaryText)
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 83, alignment: .topLeading)
            .background(
                selected ? ATHLTHTheme.accentSoft : Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(
                        selected ? ATHLTHTheme.accentDeep.opacity(0.25) : Color.primary.opacity(0.07),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var activityStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ATHLTHSectionHeader(title: ATHLTHLocalization.choose(
                english: "Activity status",
                norwegian: "Aktivitetsstatus"
            ))
            .padding(.horizontal, 2)

            ATHLTHCard {
                VStack(alignment: .leading, spacing: 14) {
                    if presenceChoicesLoaded {
                        Toggle(isOn: $showOnlineStatus) {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Show when I'm online",
                                    norwegian: "Vis når jeg er pålogget"
                                ),
                                systemImage: "circle.fill"
                            )
                        }

                        profileDivider

                        Toggle(isOn: $showTrainingStatus) {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Show when I'm training",
                                    norwegian: "Vis når jeg trener"
                                ),
                                systemImage: "figure.run"
                            )
                        }

                        Text(ATHLTHLocalization.choose(
                            english: "Only mutual follows can see these status indicators. Both can be changed at any time.",
                            norwegian: "Kun personer dere følger gjensidig kan se disse statusene. Du kan endre valgene når som helst."
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    } else {
                        HStack(spacing: 10) {
                            if presenceChoicesError == nil {
                                ProgressView()
                            }
                            Text(presenceChoicesError ?? ATHLTHLocalization.choose(
                                english: "Loading status sharing…",
                                norwegian: "Henter statusdeling…"
                            ))
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                        }
                    }
                }
                .tint(ATHLTHTheme.accentDeep)
            }
        }
    }

    @MainActor
    private func loadActivityStatus() async {
        do {
            let privacy = try await SupabaseSocialService().loadPrivacySettings()
            showOnlineStatus = privacy.showOnlineStatus
            showTrainingStatus = privacy.shareTrainingPresence
            presenceChoicesLoaded = true
            presenceChoicesError = nil
        } catch {
            presenceChoicesError = ATHLTHLocalization.choose(
                english: "Unable to load status sharing. You can still edit other profile details.",
                norwegian: "Kunne ikke hente statusdeling. Du kan fortsatt redigere resten av profilen."
            )
        }
    }

    @MainActor
    private func saveActivityStatus() async throws {
        guard presenceChoicesLoaded else { return }
        var privacy = try await SupabaseSocialService().loadPrivacySettings()
        guard privacy.showOnlineStatus != showOnlineStatus ||
                privacy.shareTrainingPresence != showTrainingStatus
        else { return }

        privacy.showOnlineStatus = showOnlineStatus
        privacy.shareTrainingPresence = showTrainingStatus
        privacy.trainingPresenceVisibility = showTrainingStatus ? "friends" : "private"
        switch await social.updatePrivacy(privacy) {
        case .success:
            settings.shareTrainingPresence = showTrainingStatus
            await realtime.configureOnlinePresence(
                appIsActive: true,
                enabled: showOnlineStatus
            )
        case .failure(let error):
            throw error
        }
    }

    private var gearCard: some View {
        NavigationLink {
            ProfileGearManagerView()
        } label: {
            ATHLTHCard {
                HStack(spacing: 13) {
                    Image(systemName: "backpack.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.vitality)
                        .frame(width: 42, height: 42)
                        .background(
                            ATHLTHTheme.vitalitySoft,
                            in: RoundedRectangle(
                                cornerRadius: 13,
                                style: .continuous
                            )
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(
                            ATHLTHLocalization.choose(
                                english: "Manage gear",
                                norwegian: "Administrer utstyr"
                            )
                        )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.primaryText)

                        Text(
                            gear.items.isEmpty
                                ? ATHLTHLocalization.choose(
                                    english: "Add watches, shoes, headphones and more.",
                                    norwegian: "Legg til klokker, sko, hodetelefoner og mer."
                                )
                                : ATHLTHLocalization.counted(
                                    gear.items.count,
                                    englishSingular: "saved item",
                                    englishPlural: "saved items",
                                    norwegianSingular: "lagret element",
                                    norwegianPlural: "lagrede elementer"
                                )
                        )
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func profileField<Field: View>(
        title: String,
        icon: String,
        @ViewBuilder field: () -> Field
    ) -> some View {
        HStack(spacing: 12) {
            profileFieldIcon(icon)

            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ATHLTHTheme.mutedText)

            Spacer(minLength: 12)

            field()
                .foregroundStyle(ATHLTHTheme.primaryText)
        }
        .padding(.vertical, 15)
    }

    private func profileFieldIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(ATHLTHTheme.accentDeep)
            .frame(width: 30, height: 30)
            .background(
                ATHLTHTheme.accentSoft,
                in: RoundedRectangle(
                    cornerRadius: 10,
                    style: .continuous
                )
            )
    }

    private var profileDivider: some View {
        Rectangle()
            .fill(ATHLTHTheme.divider)
            .frame(height: 1)
            .padding(.leading, 42)
    }

    @ViewBuilder
    private var avatarPreview: some View {
        if let selectedAvatarData,
           let image = UIImage(data: selectedAvatarData) {
            SwiftUI.Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 118, height: 118)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white,
                                    ATHLTHTheme.champagne,
                                    ATHLTHTheme.accent.opacity(0.24)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 3
                        )
                }
                .shadow(
                    color: ATHLTHTheme.accentDeep.opacity(0.16),
                    radius: 14,
                    y: 7
                )
        } else if let avatarURL = session.profile.avatarURL {
            ATHLTHStorageImage(
                url: avatarURL,
                maxPixelSize: 360
            ) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    avatarFallback
                }
            }
            .frame(width: 118, height: 118)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white,
                                ATHLTHTheme.champagne,
                                ATHLTHTheme.accent.opacity(0.24)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 3
                    )
            }
            .shadow(
                color: ATHLTHTheme.accentDeep.opacity(0.16),
                radius: 14,
                y: 7
            )
        } else {
            avatarFallback
                .frame(width: 118, height: 118)
                .overlay {
                    Circle()
                        .stroke(
                            Color.white.opacity(0.88),
                            lineWidth: 3
                        )
                }
                .shadow(
                    color: ATHLTHTheme.accentDeep.opacity(0.12),
                    radius: 12,
                    y: 6
                )
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
        guard !loadedProfile else { return }
        loadedProfile = true
        displayName = session.profile.displayName
        username = session.profile.username
        bio = session.profile.bio
        selectedTrainingFocuses = ProfileTrainingFocus.selections(
            ids: session.onboardingProfile?.trainingFocusIDs,
            fallback: session.onboardingProfile?.trainingFocus
        )
        trainingFocusExpanded = selectedTrainingFocuses.isEmpty
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
        // A removal from the photo's X always removes the displayed avatar.
        // Discard any pending replacement as well, so Save cannot restore it.
        selectedAvatarData = nil
        selectedPhoto = nil
        guard session.profile.avatarURL != nil else { return }

        saving = true
        errorMessage = nil
        defer { saving = false }

        do {
            let bootstrap = try await accountService.removeProfileAvatar()
            session.applyBackendBootstrap(bootstrap)
            await social.refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetHeaderPicture() async {
        guard !saving && !removingHeader && hasCustomHeader else { return }
        removingHeader = true
        errorMessage = nil
        defer { removingHeader = false }

        do {
            // A missing image uses the built-in default header rather than
            // leaving an invalid remote image reference behind.
            let bootstrap = try await accountService.updateProfileHeader(
                artworkName: "ProfileHero",
                imageURL: nil
            )
            session.applyBackendBootstrap(bootstrap)
            await social.refresh()
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

            await social.syncOwnProfileTrainingFocuses(
                selectedTrainingFocuses
            )
            if let message = social.errorMessage, !message.isEmpty {
                errorMessage = message
                return
            }
            session.setProfileTrainingFocuses(selectedTrainingFocuses)

            try await saveActivityStatus()
            selectedAvatarData = nil
            hasEditedATHLTHProfile = true
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ATHLTHAvatarCropView: View {
    let image: UIImage
    let onCancel: () -> Void
    let onUse: (Data) -> Void

    @State private var committedScale: CGFloat = 1
    @State private var committedOffset: CGSize = .zero
    @State private var cropSide: CGFloat = 1
    @State private var exportFailed = false
    @GestureState private var gestureScale: CGFloat = 1
    @GestureState private var gestureTranslation: CGSize = .zero

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer(minLength: 20)

                    GeometryReader { proxy in
                        let side = max(
                            1,
                            min(
                                proxy.size.width - 32,
                                proxy.size.height,
                                430
                            )
                        )

                        cropCanvas(side: side)
                            .frame(
                                width: side,
                                height: side
                            )
                            .position(
                                x: proxy.size.width / 2,
                                y: proxy.size.height / 2
                            )
                            .onAppear {
                                cropSide = side
                                committedOffset =
                                    clampedOffset(
                                        committedOffset,
                                        scale:
                                            committedScale,
                                        cropSide: side
                                    )
                            }
                            .onChange(
                                of: proxy.size
                            ) { _, _ in
                                cropSide = side
                                committedOffset =
                                    clampedOffset(
                                        committedOffset,
                                        scale:
                                            committedScale,
                                        cropSide: side
                                    )
                            }
                    }
                    .frame(maxHeight: 500)

                    VStack(spacing: 8) {
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Move and scale the photo",
                                norwegian:
                                    "Flytt og skaler bildet"
                            )
                        )
                        .font(.headline)
                        .foregroundStyle(.white)

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Drag to position. Pinch to zoom. The circle shows exactly how your profile photo will appear.",
                                norwegian:
                                    "Dra for å plassere bildet. Knip for å zoome. Sirkelen viser nøyaktig hvordan profilbildet vil se ut."
                            )
                        )
                        .font(.subheadline)
                        .foregroundStyle(
                            .white.opacity(0.68)
                        )
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 26)
                    }

                    Button {
                        committedScale = 1
                        committedOffset = .zero
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Reset crop",
                                norwegian:
                                    "Tilbakestill utsnitt"
                            ),
                            systemImage:
                                "arrow.counterclockwise"
                        )
                        .font(
                            .subheadline.weight(
                                .semibold
                            )
                        )
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 42)
                        .background(
                            .white.opacity(0.12),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 18)
                }
            }
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english: "Crop profile photo",
                    norwegian: "Velg utsnitt"
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(
                Color.black,
                for: .navigationBar
            )
            .toolbarColorScheme(
                .dark,
                for: .navigationBar
            )
            .toolbar {
                ToolbarItem(
                    placement: .cancellationAction
                ) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Cancel",
                            norwegian: "Avbryt"
                        )
                    ) {
                        onCancel()
                    }
                }

                ToolbarItem(
                    placement:
                        .confirmationAction
                ) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Continue",
                            norwegian: "Fortsett"
                        )
                    ) {
                        useCurrentCrop()
                    }
                    .fontWeight(.semibold)
                }
            }
            .alert(
                ATHLTHLocalization.choose(
                    english:
                        "Could not crop photo",
                    norwegian:
                        "Kunne ikke beskjære bildet"
                ),
                isPresented: $exportFailed
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Try a different crop or choose another photo.",
                        norwegian:
                            "Prøv et annet utsnitt eller velg et annet bilde."
                    )
                )
            }
        }
    }

    private func cropCanvas(
        side: CGFloat
    ) -> some View {
        let liveScale =
            ATHLTHAvatarCropper.clampedScale(
                committedScale *
                    gestureScale
            )
        let proposedOffset = CGSize(
            width:
                committedOffset.width +
                gestureTranslation.width,
            height:
                committedOffset.height +
                gestureTranslation.height
        )
        let liveOffset =
            clampedOffset(
                proposedOffset,
                scale: liveScale,
                cropSide: side
            )
        let baseSize =
            ATHLTHAvatarCropper.baseDisplaySize(
                image: image,
                cropSide: side
            )

        return ZStack {
            Color.black.opacity(0.92)

            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .frame(
                    width: baseSize.width,
                    height: baseSize.height
                )
                .scaleEffect(liveScale)
                .offset(liveOffset)
        }
        .frame(width: side, height: side)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(
                    Color.white.opacity(0.96),
                    lineWidth: 2
                )
        }
        .overlay {
            Circle()
                .stroke(
                    Color.white.opacity(0.22),
                    lineWidth: 8
                )
                .padding(4)
        }
        .contentShape(Circle())
        .simultaneousGesture(
            DragGesture(
                minimumDistance: 0
            )
            .updating(
                $gestureTranslation
            ) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                let proposed = CGSize(
                    width:
                        committedOffset.width +
                        value.translation.width,
                    height:
                        committedOffset.height +
                        value.translation.height
                )

                committedOffset =
                    clampedOffset(
                        proposed,
                        scale:
                            committedScale,
                        cropSide: side
                    )
            }
        )
        .simultaneousGesture(
            MagnificationGesture()
                .updating(
                    $gestureScale
                ) { value, state, _ in
                    state = value
                }
                .onEnded { value in
                    committedScale =
                        ATHLTHAvatarCropper
                            .clampedScale(
                                committedScale *
                                    value
                            )
                    committedOffset =
                        clampedOffset(
                            committedOffset,
                            scale:
                                committedScale,
                            cropSide: side
                        )
                }
        )
        .accessibilityLabel(
            ATHLTHLocalization.choose(
                english:
                    "Profile photo crop",
                norwegian:
                    "Utsnitt for profilbilde"
            )
        )
    }

    private func clampedOffset(
        _ value: CGSize,
        scale: CGFloat,
        cropSide: CGFloat
    ) -> CGSize {
        ATHLTHAvatarCropper.clampedOffset(
            value,
            image: image,
            scale: scale,
            cropSide: cropSide
        )
    }

    private func useCurrentCrop() {
        guard cropSide > 1,
              let data =
                ATHLTHAvatarCropper.jpegData(
                    from: image,
                    cropSide: cropSide,
                    scale:
                        ATHLTHAvatarCropper
                            .clampedScale(
                                committedScale
                            ),
                    offset:
                        clampedOffset(
                            committedOffset,
                            scale:
                                ATHLTHAvatarCropper
                                    .clampedScale(
                                        committedScale
                                    ),
                            cropSide: cropSide
                        )
                )
        else {
            exportFailed = true
            return
        }

        onUse(data)
    }
}

enum ATHLTHAvatarCropper {
    static let maximumZoom: CGFloat = 5
    static let maximumSourceDimension:
        CGFloat = 4_096
    static let outputDimension:
        CGFloat = 1_200

    static func prepare(
        _ image: UIImage
    ) -> UIImage? {
        let sourceWidth =
            image.size.width * image.scale
        let sourceHeight =
            image.size.height * image.scale

        guard sourceWidth > 0,
              sourceHeight > 0
        else {
            return nil
        }

        let longest =
            max(sourceWidth, sourceHeight)
        let reduction =
            min(
                1,
                maximumSourceDimension /
                    longest
            )
        let targetSize = CGSize(
            width:
                max(
                    1,
                    floor(
                        sourceWidth *
                            reduction
                    )
                ),
            height:
                max(
                    1,
                    floor(
                        sourceHeight *
                            reduction
                    )
                )
        )

        let format =
            UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer =
            UIGraphicsImageRenderer(
                size: targetSize,
                format: format
            )

        return renderer.image { _ in
            image.draw(
                in: CGRect(
                    origin: .zero,
                    size: targetSize
                )
            )
        }
    }

    static func clampedScale(
        _ value: CGFloat
    ) -> CGFloat {
        min(
            max(value, 1),
            maximumZoom
        )
    }

    static func baseDisplaySize(
        image: UIImage,
        cropSide: CGFloat
    ) -> CGSize {
        let width = max(image.size.width, 1)
        let height =
            max(image.size.height, 1)
        let aspect = width / height

        if aspect >= 1 {
            return CGSize(
                width: cropSide * aspect,
                height: cropSide
            )
        }

        return CGSize(
            width: cropSide,
            height: cropSide / aspect
        )
    }

    static func clampedOffset(
        _ value: CGSize,
        image: UIImage,
        scale: CGFloat,
        cropSide: CGFloat
    ) -> CGSize {
        let resolvedScale =
            clampedScale(scale)
        let base =
            baseDisplaySize(
                image: image,
                cropSide: cropSide
            )
        let maxX =
            max(
                0,
                (
                    base.width *
                    resolvedScale -
                    cropSide
                ) / 2
            )
        let maxY =
            max(
                0,
                (
                    base.height *
                    resolvedScale -
                    cropSide
                ) / 2
            )

        return CGSize(
            width:
                min(
                    max(value.width, -maxX),
                    maxX
                ),
            height:
                min(
                    max(value.height, -maxY),
                    maxY
                )
        )
    }

    static func jpegData(
        from image: UIImage,
        cropSide: CGFloat,
        scale: CGFloat,
        offset: CGSize
    ) -> Data? {
        guard let source = image.cgImage,
              cropSide > 1
        else {
            return nil
        }

        let sourceWidth =
            CGFloat(source.width)
        let sourceHeight =
            CGFloat(source.height)
        let baseScale =
            max(
                cropSide / sourceWidth,
                cropSide / sourceHeight
            )
        let finalScale =
            baseScale *
            clampedScale(scale)
        let visibleSide =
            min(
                floor(
                    cropSide /
                    finalScale
                ),
                min(
                    sourceWidth,
                    sourceHeight
                )
            )

        guard visibleSide >= 1 else {
            return nil
        }

        let sourceCenterX =
            sourceWidth / 2 -
            offset.width /
            finalScale
        let sourceCenterY =
            sourceHeight / 2 -
            offset.height /
            finalScale
        let maxOriginX =
            max(
                0,
                sourceWidth -
                    visibleSide
            )
        let maxOriginY =
            max(
                0,
                sourceHeight -
                    visibleSide
            )
        let originX =
            min(
                max(
                    floor(
                        sourceCenterX -
                        visibleSide / 2
                    ),
                    0
                ),
                maxOriginX
            )
        let originY =
            min(
                max(
                    floor(
                        sourceCenterY -
                        visibleSide / 2
                    ),
                    0
                ),
                maxOriginY
            )
        let cropRect = CGRect(
            x: originX,
            y: originY,
            width: visibleSide,
            height: visibleSide
        )

        guard let cropped =
                source.cropping(
                    to: cropRect
                )
        else {
            return nil
        }

        let outputSide =
            min(
                outputDimension,
                visibleSide
            )
        let outputSize = CGSize(
            width: outputSide,
            height: outputSide
        )
        let format =
            UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let rendered =
            UIGraphicsImageRenderer(
                size: outputSize,
                format: format
            )
            .image { _ in
                UIImage(
                    cgImage: cropped,
                    scale: 1,
                    orientation: .up
                )
                .draw(
                    in: CGRect(
                        origin: .zero,
                        size: outputSize
                    )
                )
            }

        return rendered.jpegData(
            compressionQuality: 0.86
        )
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
    @State private var maximumHeartRateIsEstimated = false

    @State private var editingField: HealthProfileField?
    @State private var refreshingAppleHealth = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                sourceSection
                detailsSection
                ATHLTHPrivateProfileDetailsView()
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
        .navigationTitle(ATHLTHLocalization.choose(
            english: "Health & training profile", norwegian: "Helse- og treningsprofil"
        ))
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
                            ? "\(maximumHeartRateBPM) bpm" +
                              (maximumHeartRateIsEstimated
                                  ? ATHLTHLocalization.choose(
                                      english: " · Est.", norwegian: " · Est."
                                    )
                                  : "")
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
                        VStack(alignment: .leading, spacing: 18) {
                            VStack(spacing: 5) {
                                Text("\(maximumHeartRateBPM) bpm")
                                    .font(.system(size: 34, weight: .bold))
                                    .monospacedDigit()

                                Text(maximumHeartRateIsEstimated
                                    ? ATHLTHLocalization.choose(
                                        english: "Estimated maximum heart rate",
                                        norwegian: "Estimert makspuls"
                                      )
                                    : includeMaximumHeartRate
                                        ? ATHLTHLocalization.choose(
                                            english: "Manually entered value",
                                            norwegian: "Manuelt oppgitt verdi"
                                          )
                                        : ATHLTHLocalization.choose(
                                            english: "Not saved yet",
                                            norwegian: "Ikke lagret ennå"
                                          ))
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                            }
                            .frame(maxWidth: .infinity)

                            Stepper(
                                ATHLTHLocalization.choose(
                                    english: "Adjust by 1 bpm",
                                    norwegian: "Juster med 1 slag/min"
                                ),
                                value: manualMaximumHeartRateBinding,
                                in: 100...240,
                                step: 1
                            )

                            if let estimate = maximumHeartRateEstimate {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Label(
                                            ATHLTHLocalization.choose(
                                                english: "Don't know your max?",
                                                norwegian: "Vet du ikke makspulsen?"
                                            ),
                                            systemImage: "heart.text.square"
                                        )
                                        .font(.subheadline.weight(.semibold))
                                        Spacer()
                                        Text("\(estimate.beatsPerMinute) bpm")
                                            .font(.headline.monospacedDigit())
                                    }

                                    Text(ATHLTHLocalization.choose(
                                        english: "Calculated for age \(estimate.ageYears) based on your health profile. This is a population estimate, not a measurement.",
                                        norwegian: "Beregnet for alder \(estimate.ageYears) år ut fra helseprofilen din. Dette er et befolkningsestimat, ikke en måling."
                                    ))
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                                    .fixedSize(horizontal: false, vertical: true)

                                    Text(estimate.usesFemaleEquation
                                        ? ATHLTHLocalization.choose(
                                            english: "Formula for women: 206 − 0.88 × age.",
                                            norwegian: "Formel for kvinner: 206 − 0,88 × alder."
                                          )
                                        : ATHLTHLocalization.choose(
                                            english: "General adult formula: 208 − 0.7 × age.",
                                            norwegian: "Generell voksenformel: 208 − 0,7 × alder."
                                          ))
                                        .font(.caption2)
                                        .foregroundStyle(ATHLTHTheme.mutedText)

                                    Button {
                                        maximumHeartRateBPM = estimate.beatsPerMinute
                                        maximumHeartRateIsEstimated = true
                                    } label: {
                                        Label(
                                            ATHLTHLocalization.choose(
                                                english: "Use estimated max heart rate",
                                                norwegian: "Bruk estimert makspuls"
                                            ),
                                            systemImage: "wand.and.stars"
                                        )
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity, minHeight: 42)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(ATHLTHTheme.accentDeep)
                                }
                                .padding(14)
                                .background(
                                    ATHLTHTheme.accentSoft.opacity(0.65),
                                    in: RoundedRectangle(cornerRadius: 16)
                                )
                            } else {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english: "Add your date of birth to calculate an estimate (adults 18+).",
                                        norwegian: "Legg inn fødselsdato for å beregne et estimat (18 år eller eldre)."
                                    ),
                                    systemImage: "info.circle"
                                )
                                .font(.caption)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                                .fixedSize(horizontal: false, vertical: true)
                            }

                            Text(ATHLTHLocalization.choose(
                                english: "A measured or tested maximum heart rate is more reliable. If you adjust the number manually, it is saved as a manually entered value. ATHLTH uses the saved value for heart-rate zones.",
                                norwegian: "En målt eller testet makspuls er mer pålitelig. Endrer du tallet manuelt, lagres det som manuelt oppgitt. ATHLTH bruker den lagrede verdien til pulssonene."
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
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

    private var maximumHeartRateEstimate: ATHLTHMaximumHeartRateEstimator.Result? {
        guard includeDateOfBirth else { return nil }
        return ATHLTHMaximumHeartRateEstimator.estimate(
            dateOfBirth: dateOfBirth,
            healthSex: includeSex ? healthSex : nil
        )
    }

    /// Any adjustment makes the value user-specified, not automatically estimated.
    private var manualMaximumHeartRateBinding: Binding<Int> {
        Binding(
            get: { maximumHeartRateBPM },
            set: {
                maximumHeartRateBPM = $0
                maximumHeartRateIsEstimated = false
            }
        )
    }

    private var sourceTitle: String {
        switch session.onboardingProfile?.personalDetailsSource ?? .none {
        case .appleHealth:
            return ATHLTHLocalization.choose(
                english: "Connected",
                norwegian: "Tilkoblet"
            )
        case .mixed:
            return ATHLTHLocalization.choose(
                english: "Apple Health + manual details",
                norwegian: "Apple Health + manuelle opplysninger"
            )
        case .manual:
            return ATHLTHLocalization.choose(
                english: "Manual details",
                norwegian: "Manuelle opplysninger"
            )
        case .none:
            return ATHLTHLocalization.choose(
                english: "Not connected",
                norwegian: "Ikke tilkoblet"
            )
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
        // If the user chose a population estimate, refresh it when their
        // birth date or health-sex preference changes. Never change manual HRmax.
        if includeMaximumHeartRate,
           maximumHeartRateIsEstimated,
           let estimate = maximumHeartRateEstimate {
            maximumHeartRateBPM = estimate.beatsPerMinute
        }

        let manualDetails = HealthProfileBasics(
            dateOfBirth: includeDateOfBirth ? dateOfBirth : nil,
            healthSex: includeSex ? healthSex : nil,
            weightKilograms: includeWeight ? weightKilograms : nil,
            heightCentimeters: includeHeight ? heightCentimeters : nil,
            maximumHeartRateBPM:
                includeMaximumHeartRate
                    ? maximumHeartRateBPM
                    : nil,
            maximumHeartRateIsEstimated:
                includeMaximumHeartRate
                    ? maximumHeartRateIsEstimated
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
            maximumHeartRateIsEstimated = false
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
            maximumHeartRateIsEstimated =
                profile.maximumHeartRateIsEstimated == true
        } else {
            includeMaximumHeartRate = false
            maximumHeartRateIsEstimated = false
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

                Section {
                    Label(
                        ATHLTHLocalization.choose(
                            english:
                                "Visible by default",
                            norwegian:
                                "Synlig som standard"
                        ),
                        systemImage:
                            "lock.fill"
                    )
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Profile sections are visible by default. Turn off anything you do not want to share.",
                            norwegian:
                                "Profilseksjonene er synlige som standard. Skru av det du ikke ønsker å dele."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } header: {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Profile privacy",
                            norwegian:
                                "Personvern på profil"
                        )
                    )
                }

                Section("What Others Can See") {
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
                        ATHLTHLocalization.choose(
                            english: "Gear",
                            norwegian: "Utstyr"
                        ),
                        isOn: binding.shareGear
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
                        ? ATHLTHLocalization.choose(
                            english: "Recommended · ATHLTH removes roughly 250 m from both ends before a route is shared.",
                            norwegian: "Anbefalt · ATHLTH fjerner omtrent 250 m fra begge ender før en rute deles."
                        )
                        : ATHLTHLocalization.choose(
                            english: "Shared routes include their full start and end points.",
                            norwegian: "Delte ruter inkluderer hele start- og sluttpunktet."
                        )
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
                        ? ATHLTHLocalization.choose(
                            english: "ATHLTH Coach may send the minimum relevant health context, such as sleep, HRV, heart rate and workout metrics, through ATHLTH's backend to the configured AI provider. You can turn this off at any time.",
                            norwegian: "ATHLTH Coach kan sende et minimum av relevant helsekontekst, som søvn, HRV, puls og treningsmålinger, gjennom ATHLTHs backend til den konfigurerte AI-leverandøren. Du kan slå dette av når som helst."
                        )
                        : ATHLTHLocalization.choose(
                            english: "Off by default. Recovery and workout insights stay local and deterministic until you explicitly allow health data to be used by ATHLTH Coach.",
                            norwegian: "Av som standard. Restitusjons- og treningsinnsikt forblir lokal og deterministisk til du uttrykkelig tillater at helsedata brukes av ATHLTH Coach."
                        )
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

            Section {
                NavigationLink {
                    ATHLTHPrivacyCenterView()
                } label: {
                    Label(
                        accountText(
                            english: "Privacy & AI",
                            norwegian: "Personvern og AI"
                        ),
                        systemImage: "shield.lefthalf.filled"
                    )
                }

                NavigationLink {
                    TrainingDataSettingsView()
                } label: {
                    Label(
                        accountText(
                            english: "Training data & Coach",
                            norwegian: "Treningsdata og Coach"
                        ),
                        systemImage: "icloud"
                    )
                }

                NavigationLink {
                    ATHLTHDataExportView()
                } label: {
                    Label(
                        accountText(
                            english: "Export ATHLTH Data",
                            norwegian: "Eksporter ATHLTH-data"
                        ),
                        systemImage: "square.and.arrow.up"
                    )
                }
            } header: {
                Text(
                    accountText(
                        english: "Privacy & data",
                        norwegian: "Personvern og data"
                    )
                )
            } footer: {
                Text(
                    accountText(
                        english:
                            "Manage privacy, AI access, cloud training data, backup and export from one place.",
                        norwegian:
                            "Administrer personvern, AI-tilgang, treningsdata i skyen, sikkerhetskopi og eksport på ett sted."
                    )
                )
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
        .navigationTitle(
            accountText(
                english: "Account & Security",
                norwegian: "Konto og sikkerhet"
            )
        )
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

    private func accountText(
        english: String,
        norwegian: String
    ) -> String {
        ATHLTHLocalization.choose(
            english: english,
            norwegian: norwegian
        )
    }

    private var accountEmail: String {
        if let email = accountService.currentEmail, !email.isEmpty {
            return email
        }

        return session.signInMethod == .apple
            ? accountText(
                english: "Managed by Apple",
                norwegian: "Administreres av Apple"
            )
            : accountText(
                english: "Unavailable",
                norwegian: "Ikke tilgjengelig"
            )
    }

    private var signInMethodTitle: String {
        switch session.signInMethod {
        case .apple:
            return accountText(
                english: "Sign in with Apple",
                norwegian: "Logg på med Apple"
            )
        case .email:
            return accountText(
                english: "Email & password",
                norwegian: "E-post og passord"
            )
        case .none:
            return accountText(
                english: "ATHLTH account",
                norwegian: "ATHLTH-konto"
            )
        }
    }

    private func sendPasswordReset() async {
        sendingReset = true
        statusMessage = nil
        defer { sendingReset = false }

        do {
            try await accountService.sendPasswordResetForCurrentAccount()
            statusIsError = false
            statusMessage = ATHLTHLocalization.format(
                english: "We sent a secure password-reset link to %@.",
                norwegian: "Vi sendte en sikker lenke for å tilbakestille passordet til %@.",
                accountEmail
            )
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

    @State private var showingPlaylistPicker = false

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

                    Text(
                        "Redirect URI: \(spotify.redirectURIForDiagnostics)"
                    )
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
                        showingPlaylistPicker = true
                    } label: {
                        HStack {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Default workout playlist",
                                    norwegian: "Standardspilleliste for økter"
                                ),
                                systemImage: "music.note.list"
                            )
                            Spacer()
                            Text(
                                settings
                                    .spotifyDefaultPlaylist?
                                    .name ??
                                ATHLTHLocalization.choose(
                                    english: "None",
                                    norwegian: "Ingen"
                                )
                            )
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        }
                    }

                    Text(
                        ATHLTHLocalization.choose(
                            english: "Choose a default playlist for new quick workouts. Planned workouts and programs can still use their own playlist or turn Spotify off.",
                            norwegian: "Velg en standardspilleliste for nye quick-økter. Planlagte økter og programmer kan fortsatt velge en egen spilleliste eller slå av Spotify."
                        )
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
                        "ATHLTH signs in with Spotify using Authorization Code + PKCE, then keeps the refresh token securely in Keychain. App Remote is used only when playback control is needed."
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

                    VStack(
                        alignment: .leading,
                        spacing: 4
                    ) {
                        Text(
                            "Spotify redirect URI"
                        )
                        .font(
                            .caption2.weight(
                                .semibold
                            )
                        )
                        .foregroundStyle(
                            .secondary
                        )

                        Text(
                            spotify
                                .redirectURIForDiagnostics
                        )
                        .font(
                            .caption
                                .monospaced()
                        )
                        .textSelection(.enabled)
                    }

                    Text(
                        "If Spotify reports a redirect or authorization error, this value must match the Redirect URI in Spotify Developer Dashboard exactly."
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
        .sheet(isPresented: $showingPlaylistPicker) {
            SpotifyPlaylistPickerView(
                title:
                    ATHLTHLocalization.choose(
                        english: "Default Spotify Playlist",
                        norwegian: "Standardspilleliste"
                    ),
                selection:
                    $settings.spotifyDefaultPlaylist
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
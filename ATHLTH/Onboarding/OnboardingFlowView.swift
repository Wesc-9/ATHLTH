import AuthenticationServices
import SwiftUI

struct OnboardingFlowView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @EnvironmentObject private var accountService: SupabaseAccountService

    @State private var step: OnboardingStep = .account
    @State private var username = ""
    @State private var selectedGoal: AchievementGoal?
    @State private var interests: Set<ATHLTHInterest> = []
    @State private var allowPersonalizedOffers = false
    @State private var importedHealthDetails: HealthProfileBasics = .empty
    @State private var healthRequestInProgress = false
    @State private var showingEmailAuth = false
    @State private var legalDocument: LegalDocumentKind?
    @State private var usernameSuggestions: [String] = []
    @State private var usernameValidation: UsernameValidationState = .idle
    @State private var usernameClaimError: String?
    @State private var showPaidPlansBeforeHome = false
    @State private var showingSubscriptionOffer = false
    @State private var authenticationError: String?
    @State private var appleSignInInProgress = false
    @State private var onboardingCompletionError: String?

    private let usernameService = SupabaseUsernameAvailabilityService()

    var body: some View {
        VStack(spacing: 0) {
            progressHeader

            ScrollView {
                VStack(spacing: 22) {
                    content
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 28)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }

            footer
        }
        .background(OnboardingBackground().ignoresSafeArea())
        .task {
            if session.signedIn, !session.onboardingCompleted {
                if let bootstrap = try? await accountService.loadCurrentUser() {
                    routeAuthenticatedUser(bootstrap)
                } else if session.profile.username.isEmpty {
                    step = .username
                } else {
                    step = .goals
                }
            }

            guard health.hasRequestedAuthorization else { return }
            await health.refreshPersonalDetails()
            importedHealthDetails = health.personalDetails
        }
        .sheet(isPresented: $showingEmailAuth) {
            EmailAuthView { bootstrap in
                session.applyBackendBootstrap(bootstrap, method: .email)
                routeAuthenticatedUser(bootstrap)
            }
        }
        .task(id: step) {
            switch step {
            case .username:
                await loadUsernameSuggestions()
            case .connections:
                watchConnection.refreshStatus()
            default:
                break
            }
        }
        .task(id: username) {
            guard step == .username else { return }
            await validateUsernameAfterTyping()
        }
        .sheet(item: $legalDocument) { document in
            NavigationStack {
                LegalDocumentView(kind: document)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                legalDocument = nil
                            }
                        }
                    }
            }
        }
        .sheet(
            isPresented: $showingSubscriptionOffer,
            onDismiss: {
                Task {
                    await finishOnboarding()
                }
            }
        ) {
            SubscriptionOfferView {
                session.applyStoreKitEntitlement(
                    subscriptionStore.activeEntitlement
                )
                showingSubscriptionOffer = false
            }
            .environmentObject(subscriptionStore)
        }
    }

    private var progressHeader: some View {
        VStack(spacing: 13) {
            HStack(alignment: .center) {
                if step != .account {
                    Button {
                        goBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(OnboardingTheme.ink)
                            .frame(width: 42, height: 42)
                            .background(.white.opacity(0.84), in: Circle())
                            .overlay {
                                Circle()
                                    .stroke(Color.white.opacity(0.95), lineWidth: 1)
                            }
                            .shadow(color: Color.black.opacity(0.045), radius: 10, y: 5)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 42, height: 42)
                }

                Spacer()

                ATHLTHBrandMark(size: .compact, showTagline: true)

                Spacer()

                Menu {
                    ForEach(AppLanguage.selectableCases) { language in
                        Button {
                            settings.language = language
                        } label: {
                            HStack {
                                Label(language.title, systemImage: language.systemImage)
                                if settings.language == language {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "globe")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(OnboardingTheme.deepGreen)
                        .frame(width: 42, height: 42)
                        .background(.white.opacity(0.84), in: Circle())
                        .overlay {
                            Circle()
                                .stroke(Color.white.opacity(0.95), lineWidth: 1)
                        }
                        .shadow(color: Color.black.opacity(0.045), radius: 10, y: 5)
                }
                .accessibilityLabel("Language")
            }

            HStack(spacing: 7) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule()
                        .fill(
                            index <= step.rawValue
                                ? LinearGradient(
                                    colors: [
                                        OnboardingTheme.brightGreen,
                                        OnboardingTheme.deepGreen
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                : LinearGradient(
                                    colors: [
                                        Color.black.opacity(0.075),
                                        Color.black.opacity(0.055)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                        )
                        .frame(height: 5)
                }
            }

            Text(
                settings.language == .norwegian
                    ? "\(step.rawValue + 1) av 5"
                    : "\(step.rawValue + 1) of 5"
            )
            .font(.caption2.weight(.semibold))
            .foregroundStyle(OnboardingTheme.mutedInk)
        }
        .padding(.horizontal, OnboardingTheme.screenHorizontalPadding)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .account:
            accountStep
        case .username:
            usernameStep
        case .goals:
            goalsStep
        case .connections:
            connectionsStep
        case .ready:
            readyStep
        }
    }

    private var accountStep: some View {
        VStack(spacing: 20) {
            OnboardingHeroArtwork()
                .padding(.top, 8)

            VStack(spacing: 9) {
                Text("Welcome to ATHLTH")
                    .font(.system(size: 35, weight: .bold, design: .rounded))
                    .foregroundStyle(OnboardingTheme.ink)
                    .multilineTextAlignment(.center)

                Text("Move better. Train smarter. Build a complete picture of your training, recovery and progress.")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(OnboardingTheme.mutedInk)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 6)
            }

            OnboardingCard {
                VStack(spacing: 12) {
                    SignInWithAppleButton(.continue) { request in
                        authenticationError = nil
                        accountService.prepareAppleSignIn(request)
                    } onCompletion: { result in
                        handleAppleAuthorization(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: OnboardingTheme.buttonRadius,
                            style: .continuous
                        )
                    )
                    .disabled(appleSignInInProgress)

                    Button {
                        showingEmailAuth = true
                    } label: {
                        Label("Continue with Email", systemImage: "envelope.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(OnboardingTheme.ink)
                    .background(
                        Color.white.opacity(0.78),
                        in: RoundedRectangle(
                            cornerRadius: OnboardingTheme.buttonRadius,
                            style: .continuous
                        )
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: OnboardingTheme.buttonRadius,
                            style: .continuous
                        )
                        .stroke(OnboardingTheme.border, lineWidth: 1)
                    }
                }
            }

            if let authenticationError {
                Label(authenticationError, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(spacing: 7) {
                Text("By continuing, you agree to ATHLTH’s")
                    .font(.caption2)
                    .foregroundStyle(OnboardingTheme.mutedInk)

                HStack(spacing: 14) {
                    Button("Terms of Service") {
                        legalDocument = .terms
                    }

                    Text("·")
                        .foregroundStyle(.tertiary)

                    Button("Privacy Policy") {
                        legalDocument = .privacy
                    }
                }
                .font(.caption2.weight(.semibold))
                .tint(OnboardingTheme.deepGreen)
            }
            .multilineTextAlignment(.center)
            .padding(.bottom, 8)
        }
    }

    private var usernameStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            onboardingTitle(
                "Choose your username",
                subtitle: "This is how friends will find you. Every ATHLTH username is unique."
            )

            VStack(alignment: .leading, spacing: 10) {
                Text("Username")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("@username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.title2.weight(.semibold))
                    .padding(16)
                    .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 18))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(OnboardingTheme.border, lineWidth: 1)
                    }
                    .shadow(color: Color.black.opacity(0.035), radius: 10, x: 0, y: 5)
                    .onChange(of: username) {
                        username = UsernameGenerator.normalizedTypedUsername(username)
                    }

                if let title = usernameValidation.title, !username.isEmpty {
                    Label {
                        Text(LocalizedStringKey(title))
                    } icon: {
                        Image(systemName: usernameValidation.systemImage)
                    }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(
                            usernameValidation == .available
                                ? Color.green
                                : usernameValidation == .checking
                                    ? Color.secondary
                                    : Color.red
                        )
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            usernameValidation == .available
                                ? Color.green.opacity(0.10)
                                : Color.secondary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                validationRule(
                    "3–20 characters",
                    passed: (3...20).contains(username.count)
                )
                validationRule(
                    "Only a–z, 0–9 and _",
                    passed: username.isEmpty ? false : UsernameGenerator.hasValidCharacters(username)
                )

                Text("Can be changed later")
                    .font(.caption.italic())
                    .foregroundStyle(.secondary)
                    .padding(.leading, 36)
            }
            .font(.caption)

            if !usernameSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Suggestions for you")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 9) {
                        ForEach(usernameSuggestions, id: \.self) { suggestion in
                            Button {
                                username = suggestion
                            } label: {
                                HStack {
                                    Text("@\(suggestion)")
                                        .font(.callout.weight(.medium))

                                    Spacer()

                                    Image(systemName: username == suggestion ? "checkmark.circle.fill" : "plus")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 34, height: 34)
                                        .background(.ultraThinMaterial, in: Circle())
                                }
                                .padding(.horizontal, 14)
                                .frame(height: 46)
                                .background(.white.opacity(0.90), in: RoundedRectangle(cornerRadius: 14))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(OnboardingTheme.border, lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 2)
            }

            if let usernameClaimError {
                Label(usernameClaimError, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var goalsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            onboardingTitle(
                "What do you want to achieve?",
                subtitle: "Choose the goal that matters most right now. You can change it later."
            )

            VStack(spacing: 10) {
                ForEach(AchievementGoal.allCases) { goal in
                    Button {
                        selectedGoal = goal
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: goal.systemImage)
                                .font(.title2)
                                .foregroundStyle(OnboardingTheme.green)
                                .frame(width: 38)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(LocalizedStringKey(goal.title))
                                    .font(.headline)
                                    .foregroundStyle(.primary)

                                Text(LocalizedStringKey(goal.subtitle))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }

                            Spacer()

                            Image(systemName: selectedGoal == goal ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedGoal == goal ? OnboardingTheme.green : Color.secondary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            selectedGoal == goal
                                ? Color.green.opacity(0.10)
                                : Color.secondary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 18)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(
                                    selectedGoal == goal ? OnboardingTheme.green.opacity(0.42) : OnboardingTheme.border,
                                    lineWidth: 1
                                )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 10) {
                Text("Anything else you're interested in?")
                    .font(.title3.weight(.bold))

                Text("Choose all that apply. These help ATHLTH prioritize features, content and future plans for you.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 140), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(ATHLTHInterest.allCases) { interest in
                        Button {
                            toggleInterest(interest)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: interest.systemImage)
                                Text(LocalizedStringKey(interest.title))
                                    .font(.subheadline.weight(.semibold))
                                Spacer(minLength: 0)
                                if interests.contains(interest) {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.bold))
                                }
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .foregroundStyle(interests.contains(interest) ? OnboardingTheme.green : Color.primary)
                            .background(
                                interests.contains(interest)
                                    ? OnboardingTheme.green.opacity(0.10)
                                    : Color.white.opacity(0.90),
                                in: RoundedRectangle(cornerRadius: 14)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            OnboardingCard {
                Toggle(isOn: $allowPersonalizedOffers) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Allow ATHLTH to use the goals and interests you choose to personalize ATHLTH offers.")
                            .font(.subheadline.weight(.semibold))

                        Text("Optional. You can continue without enabling this and change it later in Settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text("This applies only to goals and interests you choose in ATHLTH. Apple Health / HealthKit data is not used for offer targeting.")
                .font(.caption.italic())
                .foregroundStyle(.secondary)
        }
    }

    private var connectionsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            onboardingTitle(
                "Connect your health",
                subtitle: "Bring your health and training data into ATHLTH."
            )

            OnboardingCard {
                connectionRow(
                    title: "Apple Health",
                    subtitle: health.hasRequestedAuthorization
                        ? "Connected"
                        : "Workouts, heart rate, sleep, activity and recovery",
                    icon: "heart.fill",
                    connected: health.hasRequestedAuthorization
                ) {
                    Task {
                        healthRequestInProgress = true
                        await health.requestAuthorization()

                        await health.configureBackgroundSync(
                            allowed: session.canAccess(.backgroundHealthSync)
                        )

                        await health.refreshPersonalDetails()
                        importedHealthDetails = health.personalDetails
                        healthRequestInProgress = false
                    }
                }
            }

            OnboardingCard {
                connectionRow(
                    title: "Apple Watch",
                    subtitle: watchConnection.isReady
                        ? "Connected"
                        : watchConnection.state.subtitle,
                    icon: "applewatch",
                    connected: watchConnection.isReady
                ) {
                    watchConnection.connect()
                }
            }

            if importedHealthDetails.hasAnyValue {
                OnboardingCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Imported from Apple Health")
                            .font(.headline)

                        if let birthDate = importedHealthDetails.dateOfBirth {
                            LabeledContent(
                                "Date of birth",
                                value: birthDate.formatted(date: .abbreviated, time: .omitted)
                            )
                        }

                        if let sex = importedHealthDetails.healthSex {
                            LabeledContent {
                                Text(LocalizedStringKey(sex.title))
                            } label: {
                                Text("Sex")
                            }
                        }

                        if let weight = importedHealthDetails.weightKilograms {
                            LabeledContent(
                                "Weight",
                                value: String(format: "%.1f kg", weight)
                            )
                        }

                        if let height = importedHealthDetails.heightCentimeters {
                            LabeledContent("Height", value: "\(Int(height)) cm")
                        }
                    }
                    .font(.subheadline)
                }
            }

            if session.subscriptionAccess.state == .trial,
               session.subscriptionAccess.trialIsActive {
                OnboardingCard {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(OnboardingTheme.green)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("7-day ATHLTH+ trial active")
                                .font(.subheadline.weight(.semibold))

                            Text("Background Health sync is included during your trial.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            OnboardingCard {
                Label("Private by default", systemImage: "lock.shield.fill")
                    .font(.headline)
                    .foregroundStyle(OnboardingTheme.green)

                Text("Connecting Apple Health does not publish health data. Social sharing is controlled separately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
        }
    }

    private var readyStep: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 36)

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 76))
                .foregroundStyle(OnboardingTheme.green)

            Text("You’re ready")
                .font(.largeTitle.weight(.bold))
                .padding(.top, 16)

            Text("ATHLTH is ready around your goal.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            if let selectedGoal {
                HStack(spacing: 9) {
                    Image(systemName: selectedGoal.systemImage)
                        .foregroundStyle(OnboardingTheme.green)

                    Text(LocalizedStringKey(selectedGoal.title))
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(OnboardingTheme.green.opacity(0.09), in: Capsule())
                .padding(.top, 18)
            }

            Spacer(minLength: 48)

            Button {
                if showPaidPlansBeforeHome {
                    showingSubscriptionOffer = true
                } else {
                    Task {
                        await finishOnboarding()
                    }
                }
            } label: {
                HStack {
                    Spacer()
                    Text("Start ATHLTH")
                        .font(.headline)
                    Image(systemName: "arrow.right")
                    Spacer()
                }
                .padding(.vertical, 5)
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())

            if let onboardingCompletionError {
                Label(onboardingCompletionError, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 10)
            }

            Spacer(minLength: 110)

            if session.subscriptionAccess.trialIsActive {
                VStack(spacing: 5) {
                    Text("7-day ATHLTH+ trial active")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if let trialEndsAt = session.subscriptionAccess.trialEndsAt {
                        Text("Paid access until \(trialEndsAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Button {
                        showPaidPlansBeforeHome.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Image(
                                systemName: showPaidPlansBeforeHome
                                    ? "checkmark.square.fill"
                                    : "square"
                            )
                            .foregroundStyle(
                                showPaidPlansBeforeHome
                                    ? Color.green
                                    : Color.secondary
                            )

                            Text("Keep my ATHLTH+ benefits after the trial")
                                .font(.caption2.weight(.semibold))
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 5)

                    Text("See Monthly and Yearly plans before entering ATHLTH.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 600)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            switch step {
            case .account:
                EmptyView()

            case .username:
                footerButton(
                    title: "Continue",
                    disabled: usernameValidation != .available
                ) {
                    claimUsernameAndContinue()
                }

            case .goals:
                footerButton(title: "Continue", disabled: selectedGoal == nil) {
                    saveProfileData()
                    step = .connections
                }

            case .connections:
                footerButton(title: "Continue") {
                    saveProfileData()
                    step = .ready
                }

            case .ready:
                EmptyView()
            }
        }
        .padding(.horizontal, OnboardingTheme.screenHorizontalPadding)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.78))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func validationRule(_ title: String, passed: Bool) -> some View {
        Label {
            Text(LocalizedStringKey(title))
        } icon: {
            Image(
                systemName: passed
                    ? "checkmark.circle.fill"
                    : "circle"
            )
        }
        .foregroundStyle(passed ? Color.green : Color.secondary)
    }

    private func loadUsernameSuggestions() async {
        usernameSuggestions = await usernameService.suggestions(
            for: session.usernameSeed
        )
    }

    private func validateUsernameAfterTyping() async {
        usernameClaimError = nil

        guard !username.isEmpty else {
            usernameValidation = .idle
            return
        }

        guard UsernameGenerator.isValid(username) else {
            usernameValidation = .invalid
            return
        }

        usernameValidation = .checking

        do {
            try await Task.sleep(for: .milliseconds(350))
        } catch {
            return
        }

        guard !Task.isCancelled else { return }

        let available = await usernameService.isAvailable(username)
        usernameValidation = available ? .available : .taken
    }

    private func claimUsernameAndContinue() {
        Task {
            do {
                try await usernameService.claim(username)
                session.setPendingUsername(username)
                step = .goals
            } catch {
                usernameValidation = .taken
                usernameClaimError = error.localizedDescription
                await loadUsernameSuggestions()
            }
        }
    }

    @ViewBuilder
    private func footerButton(
        title: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)

                HStack {
                    Spacer()

                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .bold))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 20)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .contentShape(
                RoundedRectangle(
                    cornerRadius: OnboardingTheme.buttonRadius,
                    style: .continuous
                )
            )
        }
        .buttonStyle(OnboardingPrimaryButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.58 : 1)
        .accessibilityHint(disabled ? "Complete the required field to continue." : "")
    }

    @ViewBuilder
    private func onboardingTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 32, weight: .bold))
            Text(LocalizedStringKey(subtitle))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func connectionRow(
        title: String,
        subtitle: String,
        icon: String,
        connected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(connected ? OnboardingTheme.green : Color.secondary)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title))
                    .font(.headline)
                Text(LocalizedStringKey(subtitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                action()
            } label: {
                Text(LocalizedStringKey(connected ? "Connected" : "Connect"))
            }
            .buttonStyle(.bordered)
            .disabled(healthRequestInProgress && title == "Apple Health")
        }
        .frame(minHeight: 72)
    }

    private func routeAuthenticatedUser(_ bootstrap: BackendUserBootstrap) {
        if bootstrap.profile.onboardingCompleted {
            return
        }

        if let existingUsername = bootstrap.profile.username,
           !existingUsername.isEmpty {
            username = existingUsername
            step = .goals
        } else {
            let seed = bootstrap.profile.displayName ?? "athlete"
            session.setUsernameSeed(seed)
            step = .username
        }
    }

    private func handleAppleAuthorization(
        _ result: Result<ASAuthorization, Error>
    ) {
        Task {
            authenticationError = nil
            appleSignInInProgress = true
            defer { appleSignInInProgress = false }

            do {
                guard let credential = try result.get().credential
                    as? ASAuthorizationAppleIDCredential
                else {
                    throw SupabaseAccountError.invalidAppleCredential
                }

                let bootstrap = try await accountService.signInWithApple(
                    credential: credential
                )
                session.applyBackendBootstrap(bootstrap, method: .apple)

                if bootstrap.profile.username == nil,
                   bootstrap.profile.displayName == nil,
                   let emailSeed = credential.email?
                    .split(separator: "@")
                    .first
                    .map(String.init) {
                    session.setUsernameSeed(emailSeed)
                }

                routeAuthenticatedUser(bootstrap)
            } catch {
                authenticationError = error.localizedDescription
            }
        }
    }

    private func finishOnboarding() async {
        onboardingCompletionError = nil

        do {
            if accountService.currentUserID != nil {
                try await accountService.markOnboardingComplete()
            }
            session.completeOnboarding()
        } catch {
            onboardingCompletionError = error.localizedDescription
        }
    }

    private func toggleInterest(_ interest: ATHLTHInterest) {
        if interests.contains(interest) {
            interests.remove(interest)
        } else {
            interests.insert(interest)
        }
    }

    private func goBack() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    private func saveProfileData() {
        session.saveOnboardingProfile(
            OnboardingProfileData(
                dateOfBirth: importedHealthDetails.dateOfBirth,
                healthSex: importedHealthDetails.healthSex,
                weightKilograms: importedHealthDetails.weightKilograms,
                heightCentimeters: importedHealthDetails.heightCentimeters,
                personalDetailsSource: importedHealthDetails.hasAnyValue ? .appleHealth : .none,
                currentGoal: selectedGoal.map { UserGoalRecord(type: $0) },
                interests: interests,
                personalizedOfferConsent: allowPersonalizedOffers ? .granted : .declined
            )
        )
    }
}

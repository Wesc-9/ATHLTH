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
        ZStack {
            OnboardingBackground()
                .ignoresSafeArea()

            if step == .account {
                accountStep
            } else {
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
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
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
        VStack(spacing: 12) {
            HStack(alignment: .center) {
                if step != .account {
                    Button {
                        goBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay {
                                Circle()
                                    .stroke(OnboardingTheme.border, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 40, height: 40)
                }

                Spacer()

                ATHLTHBrandMark(size: .compact, showTagline: false)

                Spacer()

                Menu {
                    ForEach(AppLanguage.allCases) { language in
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
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay {
                            Circle()
                                .stroke(OnboardingTheme.border, lineWidth: 1)
                        }
                }
                .accessibilityLabel("Language")
            }

            HStack(spacing: 6) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule()
                        .fill(
                            index <= step.rawValue
                                ? OnboardingTheme.accent
                                : Color.white.opacity(0.12)
                        )
                        .frame(height: 5)
                }
            }

            Text("\(step.rawValue + 1) of 5")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(OnboardingTheme.mutedText)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
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
        GeometryReader { proxy in
            ZStack {
                OnboardingHeroPhoto()
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height
                    )
                    .clipped()
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.42),
                        Color.black.opacity(0.10),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.38)
                )
                .ignoresSafeArea()

                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.black.opacity(0.08),
                        Color.black.opacity(0.72)
                    ],
                    startPoint: UnitPoint(x: 0.5, y: 0.52),
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    accountBrand
                        .padding(.top, 26)

                    Spacer(minLength: 220)

                    accountSignInPanel

                    if let authenticationError {
                        Label(
                            authenticationError,
                            systemImage: "exclamationmark.circle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 6)
                        .padding(.top, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    accountLegal
                        .padding(.top, 18)
                        .padding(.bottom, max(10, proxy.safeAreaInsets.bottom + 6))
                }
                .padding(.horizontal, 24)
                .padding(.top, max(8, proxy.safeAreaInsets.top))
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    private var accountBrand: some View {
        VStack(spacing: 9) {
            ATHLTHMarkShape()
                .fill(.white)
                .frame(width: 58, height: 40)
                .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)

            Text("ATHLTH")
                .font(.system(size: 31, weight: .medium, design: .default))
                .tracking(9.5)
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()

            Text("YOUR BODY. YOUR DATA. YOUR PROGRESS.")
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(2.2)
                .foregroundStyle(.white.opacity(0.86))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ATHLTH. Your body. Your data. Your progress.")
    }

    private var accountSignInPanel: some View {
        VStack(spacing: 12) {
            SignInWithAppleButton(.continue) { request in
                authenticationError = nil
                accountService.prepareAppleSignIn(request)
            } onCompletion: { result in
                handleAppleAuthorization(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .clipShape(Capsule())
            .disabled(appleSignInInProgress)

            Button {
                showingEmailAuth = true
            } label: {
                Label("Continue with Email", systemImage: "envelope")
                    .font(.system(size: 18, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(
                Color.white.opacity(0.10),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.82), lineWidth: 1.25)
            }
        }
        .padding(16)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 30, style: .continuous)
        )
        .background(
            Color.white.opacity(0.20),
            in: RoundedRectangle(cornerRadius: 30, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.42), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 24, x: 0, y: 14)
    }

    private var accountLegal: some View {
        VStack(spacing: 8) {
            Text("By continuing, you agree to ATHLTH’s")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.66))

            HStack(spacing: 12) {
                Button("Terms of Service") {
                    legalDocument = .terms
                }

                Text("·")
                    .foregroundStyle(.white.opacity(0.48))

                Button("Privacy Policy") {
                    legalDocument = .privacy
                }
            }
            .font(.caption.weight(.semibold))
            .tint(.white)
        }
        .multilineTextAlignment(.center)
    }

    private var usernameStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            usernameIdentityHeader

            onboardingTitle(
                "Choose your username",
                subtitle: "This is how friends will find you across ATHLTH."
            )

            OnboardingCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Username")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)

                        Spacer()

                        Text("UNIQUE TO YOU")
                            .font(.caption2.weight(.bold))
                            .tracking(1.2)
                            .foregroundStyle(OnboardingTheme.accent)
                    }

                    TextField("@username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.title2.weight(.semibold))
                        .padding(.horizontal, 16)
                        .frame(height: 58)
                        .background(
                            Color.black.opacity(0.20),
                            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 17, style: .continuous)
                                .stroke(
                                    usernameValidation == .available
                                        ? OnboardingTheme.success.opacity(0.62)
                                        : OnboardingTheme.border,
                                    lineWidth: 1
                                )
                        }
                        .onChange(of: username) {
                            username = UsernameGenerator.normalizedTypedUsername(username)
                        }

                    if let title = usernameValidation.title, !username.isEmpty {
                        Label(title, systemImage: usernameValidation.systemImage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(
                                usernameValidation == .available
                                    ? OnboardingTheme.success
                                    : usernameValidation == .checking
                                        ? OnboardingTheme.mutedText
                                        : Color.red
                            )
                            .padding(.horizontal, 13)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                usernameValidation == .available
                                    ? OnboardingTheme.success.opacity(0.11)
                                    : Color.white.opacity(0.055),
                                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                            )
                    }

                    HStack(spacing: 18) {
                        validationRule(
                            "3–20 characters",
                            passed: (3...20).contains(username.count)
                        )
                        validationRule(
                            "a–z, 0–9, _",
                            passed: username.isEmpty ? false : UsernameGenerator.hasValidCharacters(username)
                        )
                    }
                    .font(.caption)

                }
            }

            if !usernameSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 11) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Suggestions for you")
                            .font(.headline)

                        Spacer()

                        Text("BASED ON YOUR NAME")
                            .font(.caption2.weight(.bold))
                            .tracking(1.0)
                            .foregroundStyle(OnboardingTheme.mutedText)
                    }

                    VStack(spacing: 10) {
                        ForEach(usernameSuggestions, id: \.self) { suggestion in
                            Button {
                                username = suggestion
                            } label: {
                                HStack(spacing: 13) {
                                    Text("@")
                                        .font(.headline.weight(.bold))
                                        .foregroundStyle(OnboardingTheme.accent)
                                        .frame(width: 38, height: 38)
                                        .background(
                                            OnboardingTheme.accent.opacity(0.12),
                                            in: Circle()
                                        )

                                    Text(suggestion)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.white)

                                    Spacer()

                                    Image(
                                        systemName: username == suggestion
                                            ? "checkmark.circle.fill"
                                            : "plus"
                                    )
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(
                                        username == suggestion
                                            ? OnboardingTheme.accent
                                            : OnboardingTheme.mutedText
                                    )
                                }
                                .padding(.horizontal, 14)
                                .frame(height: 58)
                                .background(
                                    username == suggestion
                                        ? OnboardingTheme.accent.opacity(0.10)
                                        : Color.white.opacity(0.075),
                                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(
                                            username == suggestion
                                                ? OnboardingTheme.accent.opacity(0.48)
                                                : OnboardingTheme.border,
                                            lineWidth: 1
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if let usernameClaimError {
                Label(usernameClaimError, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var usernameIdentityHeader: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.12),
                            OnboardingTheme.accent.opacity(0.12),
                            OnboardingTheme.warmHighlight.opacity(0.08),
                            Color.black.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(OnboardingTheme.accent.opacity(0.12))
                .frame(width: 150, height: 150)
                .offset(x: 150, y: -44)
                .blur(radius: 6)

            HStack(spacing: 17) {
                ATHLTHMarkShape()
                    .fill(.white)
                    .frame(width: 48, height: 33)
                    .padding(14)
                    .background(
                        Color.white.opacity(0.09),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.13), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 5) {
                    Text("YOUR ATHLTH IDENTITY")
                        .font(.caption2.weight(.bold))
                        .tracking(1.7)
                        .foregroundStyle(OnboardingTheme.accent)

                    Text("Make it yours.")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)

                    Text("One username across training, friends and challenges.")
                        .font(.caption)
                        .foregroundStyle(OnboardingTheme.mutedText)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .padding(18)
        }
        .frame(height: 118)
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.20), radius: 20, x: 0, y: 10)
    }

    private var goalsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingSceneCard(kind: .goals)

            onboardingTitle(
                "What do you want to achieve?",
                subtitle: "Choose the goal that matters most right now."
            )

            VStack(spacing: 10) {
                ForEach(AchievementGoal.allCases) { goal in
                    Button {
                        selectedGoal = goal
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: goal.systemImage)
                                .font(.title2)
                                .foregroundStyle(OnboardingTheme.accent)
                                .frame(width: 38)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(goal.title)
                                    .font(.headline)
                                    .foregroundStyle(.white)

                                Text(goal.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(OnboardingTheme.mutedText)
                                    .multilineTextAlignment(.leading)
                            }

                            Spacer()

                            Image(systemName: selectedGoal == goal ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedGoal == goal ? OnboardingTheme.accent : Color.secondary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            selectedGoal == goal
                                ? OnboardingTheme.accent.opacity(0.10)
                                : Color.white.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: 18)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(
                                    selectedGoal == goal ? OnboardingTheme.accent.opacity(0.42) : OnboardingTheme.border,
                                    lineWidth: 1
                                )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Anything else you're interested in?")
                    .font(.title3.weight(.bold))

                Text("Choose what you’re interested in to personalize your ATHLTH experience.")
                    .font(.subheadline)
                    .foregroundStyle(OnboardingTheme.mutedText)

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
                                Text(interest.title)
                                    .font(.subheadline.weight(.semibold))
                                Spacer(minLength: 0)
                                if interests.contains(interest) {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.bold))
                                }
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .foregroundStyle(interests.contains(interest) ? OnboardingTheme.accent : Color.primary)
                            .background(
                                interests.contains(interest)
                                    ? OnboardingTheme.accent.opacity(0.10)
                                    : Color.white.opacity(0.10),
                                in: RoundedRectangle(cornerRadius: 14)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

        }
    }

    private var connectionsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingSceneCard(kind: .connections)

            onboardingTitle(
                "Connect your health",
                subtitle: "Bring your health and training data into ATHLTH."
            )

            OnboardingCard {
                connectionRow(
                    title: "Apple Health",
                    subtitle: health.hasRequestedAuthorization
                        ? "Health access requested"
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

            if let healthError = health.authorizationError {
                Label(healthError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 4)
            } else if let backgroundError = health.backgroundSyncError {
                Label(
                    "Health access is active, but background sync needs attention: \(backgroundError)",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.horizontal, 4)
            }

            OnboardingCard {
                connectionRow(
                    title: "Apple Watch",
                    subtitle: watchConnection.statusText,
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
                            LabeledContent("Sex", value: sex.title)
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
                            .foregroundStyle(OnboardingTheme.accent)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("7-day ATHLTH+ trial active")
                                .font(.subheadline.weight(.semibold))

                            Text("Background Health sync is included during your trial.")
                                .font(.caption)
                                .foregroundStyle(OnboardingTheme.mutedText)
                        }
                    }
                }
            }

            OnboardingCard {
                Label("Private by default", systemImage: "lock.shield.fill")
                    .font(.headline)
                    .foregroundStyle(OnboardingTheme.accent)

                Text("Connecting Apple Health does not publish health data. Social sharing is controlled separately.")
                    .font(.caption)
                    .foregroundStyle(OnboardingTheme.mutedText)
                    .padding(.top, 6)
            }
        }
    }

    private var readyStep: some View {
        VStack(spacing: 0) {
            OnboardingSceneCard(kind: .ready)
                .padding(.bottom, 28)

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 76))
                .foregroundStyle(OnboardingTheme.success)

            Text("You’re ready")
                .font(.largeTitle.weight(.bold))
                .padding(.top, 16)

            Text("ATHLTH is ready around your goal.")
                .font(.subheadline)
                .foregroundStyle(OnboardingTheme.mutedText)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            if let selectedGoal {
                HStack(spacing: 9) {
                    Image(systemName: selectedGoal.systemImage)
                        .foregroundStyle(OnboardingTheme.accent)

                    Text(selectedGoal.title)
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(OnboardingTheme.accent.opacity(0.09), in: Capsule())
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
                        .foregroundStyle(OnboardingTheme.mutedText)

                    if let trialEndsAt = session.subscriptionAccess.trialEndsAt {
                        Text("Paid access until \(trialEndsAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption2)
                            .foregroundStyle(OnboardingTheme.faintText)
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
                        .foregroundStyle(OnboardingTheme.faintText)
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

                personalizedOffersFooter

            case .connections:
                footerButton(title: "Continue") {
                    saveProfileData()
                    step = .ready
                }

            case .ready:
                EmptyView()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 18)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: 1)
        }
    }

    private var personalizedOffersFooter: some View {
        Toggle(isOn: $allowPersonalizedOffers) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.accent)
                    .frame(width: 34, height: 34)
                    .background(
                        OnboardingTheme.accent.opacity(0.12),
                        in: Circle()
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("Make offers more relevant")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)

                    Text("Use your selected goals and interests to personalize ATHLTH offers.")
                        .font(.caption)
                        .foregroundStyle(OnboardingTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Optional · Never uses Apple Health data.")
                        .font(.caption2)
                        .foregroundStyle(OnboardingTheme.faintText)
                        .padding(.top, 1)
                }
            }
        }
        .tint(OnboardingTheme.accent)
        .padding(14)
        .background(
            Color.white.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(OnboardingTheme.border, lineWidth: 1)
        }
    }

    @ViewBuilder
    private func validationRule(_ title: String, passed: Bool) -> some View {
        Label(
            title,
            systemImage: passed ? "checkmark.circle.fill" : "circle"
        )
        .foregroundStyle(passed ? OnboardingTheme.success : Color.secondary)
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
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(OnboardingPrimaryButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }

    @ViewBuilder
    private func onboardingTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(OnboardingTheme.mutedText)
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
                .foregroundStyle(connected ? OnboardingTheme.success : Color.secondary)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(OnboardingTheme.mutedText)
            }

            Spacer()

            Button(connected ? "Connected" : "Connect") {
                action()
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

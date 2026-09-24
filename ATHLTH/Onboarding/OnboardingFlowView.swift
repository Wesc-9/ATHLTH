import AuthenticationServices
import SwiftUI
import UIKit

private enum ConnectionStage {
    case device
    case appleHealth
}

struct OnboardingFlowView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var accountService: SupabaseAccountService
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var step: OnboardingStep = .account
    @State private var username = ""
    @State private var selectedGoal: AchievementGoal?
    @State private var selectedGoalFocus: GoalFocusArea?
    @State private var selectedTrainingFocus: TrainingFocus?
    @State private var interests: Set<ATHLTHInterest> = []
    @State private var allowPersonalizedOffers = false
    @State private var importedHealthDetails: HealthProfileBasics = .empty
    @State private var healthRequestInProgress = false
    @State private var showingEmailAuth = false
    @State private var legalDocument: LegalDocumentKind?
    @State private var usernameSuggestions: [String] = []
    @State private var usernameValidation: UsernameValidationState = .idle
    @State private var usernameClaimError: String?
    @State private var authenticationError: String?
    @State private var appleSignInInProgress = false
    @State private var onboardingCompletionError: String?
    @State private var showingWatchInstallHelp = false
    @State private var showingGarminSetup = false
    @State private var connectionStage: ConnectionStage = .device
    @FocusState private var usernameFieldFocused: Bool

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
                    .scrollDismissesKeyboard(.interactively)

                    footer
                }
            }
        }
        .foregroundStyle(step == .account ? Color.white : OnboardingTheme.primaryText)
        .preferredColorScheme(step == .account ? .dark : .light)
        .task {
            if session.signedIn, !session.onboardingCompleted {
                if let bootstrap = try? await accountService.loadCurrentUser() {
                    let restoredNameSeed = await accountService.currentUserNameSeed()
                    routeAuthenticatedUser(
                        bootstrap,
                        usernameSeedFallback: restoredNameSeed
                    )
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
            EmailAuthView { bootstrap, usernameSeedFallback in
                session.applyBackendBootstrap(bootstrap, method: .email)
                routeAuthenticatedUser(
                    bootstrap,
                    usernameSeedFallback: usernameSeedFallback
                )
            }
        }
        .task(id: step) {
            switch step {
            case .username:
                await loadUsernameSuggestions()
            case .connections:
                usernameFieldFocused = false
                // The connection screen is also a device check. Refresh Watch
                // status even when the user has not selected Apple Watch yet.
                watchConnection.refreshStatus()
            case .goals, .ready:
                usernameFieldFocused = false
            default:
                break
            }
        }
        .task(id: username) {
            guard step == .username else { return }
            await validateUsernameAfterTyping()
        }
        .onChange(of: scenePhase) {
            guard scenePhase == .active,
                  step == .connections
            else {
                return
            }
            watchConnection.refreshStatus()
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
        .sheet(isPresented: $showingWatchInstallHelp) {
            WatchInstallHelpView(state: watchConnection.state) {
                showingWatchInstallHelp = false
                watchConnection.refreshStatus()
            }
        }
        .sheet(isPresented: $showingGarminSetup) {
            GarminOnboardingSetupView()
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
                            .foregroundStyle(OnboardingTheme.primaryText)
                            .frame(width: 40, height: 40)
                            .background(OnboardingTheme.card, in: Circle())
                            .overlay {
                                Circle()
                                    .stroke(OnboardingTheme.border, lineWidth: 1)
                            }
                            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 40, height: 40)
                }

                Spacer()

                ATHLTHBrandMark(size: .compact, showTagline: false)

                Spacer()

                Color.clear
                    .frame(width: 40, height: 40)
            }

            HStack(spacing: 6) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule()
                        .fill(
                            index <= step.rawValue
                                ? OnboardingTheme.accent
                                : Color.black.opacity(0.08)
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
            let usesTabletWidth = proxy.size.width >= 700
            let foregroundWidth: CGFloat = usesTabletWidth ? 500 : 560
            let spacerMinimum: CGFloat = usesTabletWidth ? 56 : 170

            ZStack {
                OnboardingHeroPhoto()
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height
                    )
                    .scaleEffect(1.025)
                    .offset(y: 8)
                    .clipped()
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.44),
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
                        Color.black.opacity(0.06),
                        Color.black.opacity(0.76)
                    ],
                    startPoint: UnitPoint(x: 0.5, y: 0.50),
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    accountBrand
                        .padding(.top, usesTabletWidth ? 24 : 18)

                    Spacer(minLength: spacerMinimum)

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
                        .padding(.bottom, 12)
                }
                .frame(maxWidth: foregroundWidth)
                .padding(.horizontal, 24)
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height
                )
            }
        }
        .background(Color.black.ignoresSafeArea())
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
        VStack(spacing: 13) {
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
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.24), radius: 12, x: 0, y: 7)
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
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.13),
                        Color.white.opacity(0.065)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.62),
                                OnboardingTheme.accent.opacity(0.28),
                                Color.white.opacity(0.22)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.1
                    )
            }
        }
        .padding(15)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.10),
                                    OnboardingTheme.accent.opacity(0.045),
                                    Color.black.opacity(0.16)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.46),
                            OnboardingTheme.accent.opacity(0.18),
                            Color.white.opacity(0.16)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.30), radius: 28, x: 0, y: 16)
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
        VStack(alignment: .leading, spacing: 26) {
            onboardingTitle(
                "Choose your username",
                subtitle: "This is how friends will find you across ATHLTH."
            )

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("USERNAME")
                        .font(.caption2.weight(.bold))
                        .tracking(1.35)
                        .foregroundStyle(OnboardingTheme.mutedText)

                    Spacer()

                    Text("ATHLTH ID")
                        .font(.caption2.weight(.bold))
                        .tracking(1.15)
                        .foregroundStyle(OnboardingTheme.accent)
                }
                .padding(.horizontal, 2)

                HStack(spacing: 12) {
                    TextField("@username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($usernameFieldFocused)
                        .onSubmit {
                            usernameFieldFocused = false
                        }
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(OnboardingTheme.primaryText)
                        .onChange(of: username) {
                            username = UsernameGenerator.normalizedTypedUsername(username)
                        }

                    if !username.isEmpty {
                        Group {
                            switch usernameValidation {
                            case .checking:
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(OnboardingTheme.accent)

                            case .available:
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(OnboardingTheme.success)
                                    .frame(width: 30, height: 30)
                                    .background(
                                        OnboardingTheme.success.opacity(0.11),
                                        in: Circle()
                                    )

                            case .taken, .invalid:
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.red)
                                    .frame(width: 30, height: 30)
                                    .background(
                                        Color.red.opacity(0.08),
                                        in: Circle()
                                    )

                            case .idle:
                                EmptyView()
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .frame(height: 66)
                .background(
                    OnboardingTheme.card,
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            usernameFieldFocused
                                ? OnboardingTheme.accent.opacity(0.52)
                                : usernameValidation == .available
                                    ? OnboardingTheme.success.opacity(0.34)
                                    : OnboardingTheme.border,
                            lineWidth: usernameFieldFocused ? 1.25 : 1
                        )
                }
                .shadow(
                    color: usernameFieldFocused
                        ? OnboardingTheme.accent.opacity(0.09)
                        : Color.black.opacity(0.045),
                    radius: usernameFieldFocused ? 18 : 12,
                    x: 0,
                    y: 7
                )

                HStack(spacing: 8) {
                    Text("3–20 characters · letters, numbers & _")
                        .font(.caption)
                        .foregroundStyle(OnboardingTheme.faintText)

                    Spacer()

                    if let title = usernameValidation.title, !username.isEmpty {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(
                                    usernameValidation == .available
                                        ? OnboardingTheme.success
                                        : usernameValidation == .checking
                                            ? OnboardingTheme.accent
                                            : Color.red
                                )
                                .frame(width: 5, height: 5)

                            Text(title)
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(
                            usernameValidation == .available
                                ? OnboardingTheme.success
                                : usernameValidation == .checking
                                    ? OnboardingTheme.mutedText
                                    : Color.red
                        )
                    }
                }
                .padding(.horizontal, 3)
            }

            if !usernameSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Suggestions for you")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(OnboardingTheme.primaryText)

                        Spacer()

                        Text("BASED ON YOUR NAME")
                            .font(.caption2.weight(.bold))
                            .tracking(0.9)
                            .foregroundStyle(OnboardingTheme.faintText)
                    }

                    LazyVGrid(
                        columns: [
                            GridItem(.adaptive(minimum: 145), spacing: 10)
                        ],
                        spacing: 10
                    ) {
                        ForEach(Array(usernameSuggestions.prefix(4)), id: \.self) { suggestion in
                            Button {
                                username = suggestion
                            } label: {
                                HStack(spacing: 8) {
                                    Text("@")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(OnboardingTheme.accent)

                                    Text(suggestion)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(OnboardingTheme.primaryText)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.78)

                                    Spacer(minLength: 4)

                                    Image(
                                        systemName: username == suggestion
                                            ? "checkmark"
                                            : "plus"
                                    )
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(
                                        username == suggestion
                                            ? OnboardingTheme.accent
                                            : OnboardingTheme.mutedText
                                    )
                                }
                                .padding(.horizontal, 13)
                                .frame(minHeight: 46)
                                .background(
                                    username == suggestion
                                        ? OnboardingTheme.selectedFill
                                        : OnboardingTheme.card,
                                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                                        .stroke(
                                            username == suggestion
                                                ? OnboardingTheme.accent.opacity(0.38)
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

    private var goalsStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            onboardingTitle(
                "How do you train?",
                subtitle: "Choose the training identity that fits you best. You can change it later."
            )

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                ForEach(TrainingFocus.allCases) { focus in
                    let selected = selectedTrainingFocus == focus

                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedTrainingFocus = focus
                            applyTrainingFocusToInterests(focus)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: focus.systemImage)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(
                                        selected
                                            ? OnboardingTheme.accent
                                            : OnboardingTheme.primaryText
                                    )

                                Spacer()

                                Image(
                                    systemName: selected
                                        ? "checkmark.circle.fill"
                                        : "circle"
                                )
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(
                                    selected
                                        ? OnboardingTheme.accent
                                        : OnboardingTheme.faintText
                                )
                            }

                            Text(focus.title)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(OnboardingTheme.primaryText)

                            Text(focus.subtitle)
                                .font(.caption)
                                .foregroundStyle(OnboardingTheme.mutedText)
                                .multilineTextAlignment(.leading)
                                .lineLimit(3)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
                        .background(
                            selected
                                ? OnboardingTheme.selectedFill
                                : OnboardingTheme.card,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(
                                    selected
                                        ? OnboardingTheme.accent.opacity(0.40)
                                        : OnboardingTheme.border,
                                    lineWidth: 1
                                )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            onboardingTitle(
                "What matters most right now?",
                subtitle: "Choose one primary goal. This personalizes ATHLTH, but does not make it public."
            )

            VStack(alignment: .leading, spacing: 12) {
                Text("CHOOSE A FOCUS")
                    .font(.caption2.weight(.bold))
                    .tracking(1.25)
                    .foregroundStyle(OnboardingTheme.faintText)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    ForEach(GoalFocusArea.allCases) { focus in
                        let selected = selectedGoalFocus == focus

                        Button {
                            withAnimation(.easeInOut(duration: 0.20)) {
                                if selectedGoalFocus != focus {
                                    selectedGoal = nil
                                }
                                selectedGoalFocus = focus
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: focus.systemImage)
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(
                                            selected
                                                ? OnboardingTheme.accent
                                                : OnboardingTheme.primaryText
                                        )
                                        .frame(width: 38, height: 38)
                                        .background(
                                            selected
                                                ? OnboardingTheme.accent.opacity(0.12)
                                                : OnboardingTheme.subtleFill,
                                            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        )

                                    Spacer()

                                    if selected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundStyle(OnboardingTheme.accent)
                                    }
                                }

                                Text(focus.title)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(OnboardingTheme.primaryText)
                                    .multilineTextAlignment(.leading)

                                Text(focus.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(OnboardingTheme.mutedText)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                            }
                            .padding(15)
                            .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
                            .background(
                                selected
                                    ? OnboardingTheme.selectedFill
                                    : OnboardingTheme.card,
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(
                                        selected
                                            ? OnboardingTheme.accent.opacity(0.42)
                                            : OnboardingTheme.border,
                                        lineWidth: selected ? 1.2 : 1
                                    )
                            }
                            .shadow(
                                color: selected
                                    ? OnboardingTheme.accent.opacity(0.06)
                                    : Color.black.opacity(0.035),
                                radius: 12,
                                x: 0,
                                y: 6
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let selectedGoalFocus {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(goalDetailPrompt(for: selectedGoalFocus))
                            .font(.title3.weight(.bold))
                            .foregroundStyle(OnboardingTheme.primaryText)

                        Spacer()

                        Text("ONE GOAL")
                            .font(.caption2.weight(.bold))
                            .tracking(1.0)
                            .foregroundStyle(OnboardingTheme.faintText)
                    }

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 150), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(selectedGoalFocus.goals) { goal in
                            let selected = selectedGoal == goal

                            Button {
                                withAnimation(.easeInOut(duration: 0.16)) {
                                    selectedGoal = goal
                                }
                            } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: goal.systemImage)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(
                                            selected
                                                ? OnboardingTheme.accent
                                                : OnboardingTheme.mutedText
                                        )

                                    Text(goal.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(OnboardingTheme.primaryText)
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(2)

                                    Spacer(minLength: 4)

                                    Image(
                                        systemName: selected
                                            ? "checkmark.circle.fill"
                                            : "circle"
                                    )
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(
                                        selected
                                            ? OnboardingTheme.accent
                                            : OnboardingTheme.faintText
                                    )
                                }
                                .padding(.horizontal, 13)
                                .frame(minHeight: 50)
                                .background(
                                    selected
                                        ? OnboardingTheme.selectedFill
                                        : OnboardingTheme.card,
                                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                                        .stroke(
                                            selected
                                                ? OnboardingTheme.accent.opacity(0.36)
                                                : OnboardingTheme.border,
                                            lineWidth: 1
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .transition(
                    .opacity.combined(
                        with: .move(edge: .top)
                    )
                )
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Also interested in")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(OnboardingTheme.primaryText)

                    Text("Optional")
                        .font(.caption)
                        .foregroundStyle(OnboardingTheme.faintText)

                    Spacer()
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 120), spacing: 9)],
                    spacing: 9
                ) {
                    ForEach(ATHLTHInterest.allCases) { interest in
                        let selected = interests.contains(interest)

                        Button {
                            toggleInterest(interest)
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: interest.systemImage)
                                    .font(.system(size: 13, weight: .semibold))

                                Text(interest.title)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.82)

                                if selected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                }
                            }
                            .foregroundStyle(
                                selected
                                    ? OnboardingTheme.accent
                                    : OnboardingTheme.primaryText
                            )
                            .padding(.horizontal, 12)
                            .frame(minHeight: 40)
                            .frame(maxWidth: .infinity)
                            .background(
                                selected
                                    ? OnboardingTheme.selectedFill
                                    : OnboardingTheme.card,
                                in: Capsule()
                            )
                            .overlay {
                                Capsule()
                                    .stroke(
                                        selected
                                            ? OnboardingTheme.accent.opacity(0.34)
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
    }

    private func applyTrainingFocusToInterests(_ focus: TrainingFocus) {
        switch focus {
        case .running:
            interests.insert(.running)
        case .strength:
            interests.insert(.strength)
        case .hybrid:
            interests.insert(.running)
            interests.insert(.strength)
        case .walking:
            interests.insert(.walking)
        case .generalFitness:
            interests.insert(.healthTracking)
            interests.insert(.trainingPlans)
        case .recovery:
            interests.insert(.recovery)
        }
    }

    private func goalDetailPrompt(for focus: GoalFocusArea) -> String {
        switch focus {
        case .strengthBody:
            return "What would you like to change?"
        case .performance:
            return "What would you like to improve?"
        case .healthMovement:
            return "What would feel better day to day?"
        case .recovery:
            return "What would you like to recover?"
        }
    }

    @ViewBuilder
    private var connectionsStep: some View {
        switch connectionStage {
        case .device:
            deviceConnectionStep
        case .appleHealth:
            appleHealthConnectionStep
        }
    }

    private var deviceConnectionStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                onboardingTitle(
                    "Check your connections",
                    subtitle: "Make sure the devices you want to use with ATHLTH are ready."
                )

                HStack(spacing: 7) {
                    Text("DEVICES")
                    Text("1 OF 2")
                }
                .font(.caption2.weight(.bold))
                .tracking(1.15)
                .foregroundStyle(OnboardingTheme.faintText)
            }

            VStack(spacing: 12) {
                deviceChoiceCard(
                    provider: .appleWatch,
                    title: "Apple Watch",
                    subtitle: "Track workouts, heart rate, recovery and more.",
                    icon: "applewatch",
                    status: appleWatchConnectionLabel,
                    statusTint: appleWatchConnectionTint,
                    infoAction: {
                        showingWatchInstallHelp = true
                    }
                )

                if settings.trainingDeviceProvider == .appleWatch,
                   watchConnection.state == .appNotInstalled {
                    Button {
                        openAppleWatchApp()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "applewatch")
                            Text("Open Watch app to install ATHLTH")
                                .fontWeight(.semibold)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.bold))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                }

                deviceChoiceCard(
                    provider: .garmin,
                    title: "Garmin",
                    subtitle: "Garmin Connect integration is coming soon.",
                    icon: "watch.analog",
                    isAvailable: false,
                    badge: "COMING SOON",
                    status: "Setup will be required",
                    statusTint: OnboardingTheme.faintText,
                    infoAction: {
                        showingGarminSetup = true
                    }
                )

                deviceChoiceCard(
                    provider: .none,
                    title: "No watch",
                    subtitle: "Use ATHLTH with your iPhone and Apple Health when available.",
                    icon: "iphone",
                    status: settings.trainingDeviceProvider == .none
                        ? "iPhone / manual mode"
                        : nil,
                    statusTint: OnboardingTheme.accent
                )
            }

            if settings.trainingDeviceProvider == .none {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "rectangle.3.group.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(OnboardingTheme.accent)
                        .padding(.top, 1)

                    Text(
                        "ATHLTH adapts to your setup. Apple Health can still power workouts, activity and compatible health insights. Watch-only sections stay hidden when they have no data, and if you skip Apple Health too, ATHLTH keeps the experience focused on features you can use without a wearable."
                    )
                    .font(.caption)
                    .foregroundStyle(OnboardingTheme.mutedText)
                    .lineSpacing(2)
                }
                .padding(14)
                .background(
                    OnboardingTheme.accent.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
            }

            Text("You can change your training device anytime in Settings.")
                .font(.caption)
                .foregroundStyle(OnboardingTheme.faintText)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 2)
        }
    }

    private func deviceChoiceCard(
        provider: TrainingDeviceProvider,
        title: String,
        subtitle: String,
        icon: String,
        isAvailable: Bool = true,
        badge: String? = nil,
        status: String? = nil,
        statusTint: Color = OnboardingTheme.accent,
        infoAction: (() -> Void)? = nil
    ) -> some View {
        let selected = isAvailable && settings.trainingDeviceProvider == provider

        return HStack(spacing: 12) {
            Button {
                guard isAvailable else { return }

                withAnimation(.easeInOut(duration: 0.18)) {
                    settings.trainingDeviceProvider = provider
                }

                if provider != .appleWatch,
                   settings.preferredWorkoutCapture == .appleWatch {
                    settings.preferredWorkoutCapture = .iPhone
                }

                if provider == .appleWatch {
                    watchConnection.refreshStatus()
                }
            } label: {
                HStack(spacing: 17) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                !isAvailable
                                    ? Color.black.opacity(0.025)
                                    : selected
                                        ? OnboardingTheme.accent.opacity(0.11)
                                        : Color.black.opacity(0.035)
                            )
                            .frame(width: 72, height: 72)

                        Image(systemName: icon)
                            .font(.system(size: provider == .appleWatch ? 31 : 28, weight: .medium))
                            .foregroundStyle(
                                !isAvailable
                                    ? OnboardingTheme.faintText.opacity(0.55)
                                    : selected
                                        ? OnboardingTheme.accent
                                        : OnboardingTheme.primaryText.opacity(0.78)
                            )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(title)
                                .font(.system(size: 19, weight: .bold))
                                .foregroundStyle(
                                    isAvailable
                                        ? OnboardingTheme.primaryText
                                        : OnboardingTheme.mutedText
                                )

                            if let badge {
                                Text(badge)
                                    .font(.system(size: 9, weight: .bold))
                                    .tracking(0.7)
                                    .foregroundStyle(OnboardingTheme.faintText)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(
                                        Color.black.opacity(0.045),
                                        in: Capsule()
                                    )
                            }
                        }

                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(
                                isAvailable
                                    ? OnboardingTheme.mutedText
                                    : OnboardingTheme.faintText
                            )
                            .multilineTextAlignment(.leading)
                            .lineSpacing(2)

                        if let status {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(statusTint)
                                    .frame(width: 7, height: 7)

                                Text(status)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(statusTint)
                                    .lineLimit(2)
                            }
                            .padding(.top, 1)
                        }
                    }

                    Spacer(minLength: 2)

                    Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(
                            selected
                                ? OnboardingTheme.accent
                                : OnboardingTheme.faintText.opacity(0.72)
                        )
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isAvailable)

            if let infoAction {
                Button(action: infoAction) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(OnboardingTheme.mutedText)
                        .frame(width: 38, height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title) setup details")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background(
            !isAvailable
                ? Color.black.opacity(0.025)
                : selected
                    ? OnboardingTheme.accent.opacity(0.045)
                    : OnboardingTheme.card,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    !isAvailable
                        ? OnboardingTheme.border.opacity(0.55)
                        : selected
                            ? OnboardingTheme.accent.opacity(0.52)
                            : OnboardingTheme.border,
                    lineWidth: selected ? 1.4 : 1
                )
        }
        .shadow(
            color: !isAvailable
                ? Color.clear
                : selected
                    ? OnboardingTheme.accent.opacity(0.09)
                    : Color.black.opacity(0.035),
            radius: selected ? 18 : 12,
            x: 0,
            y: 8
        )
        .accessibilityElement(children: .contain)
    }

    private var appleWatchConnectionLabel: String {
        switch watchConnection.state {
        case .checking:
            return "Checking connection…"
        case .unsupported:
            return "Apple Watch unavailable"
        case .notPaired:
            return "Watch not connected"
        case .appNotInstalled:
            return "Paired · ATHLTH app not installed"
        case .ready:
            return "Connected"
        }
    }

    private var appleWatchConnectionTint: Color {
        switch watchConnection.state {
        case .ready:
            return OnboardingTheme.success
        case .appNotInstalled, .notPaired:
            return .orange
        case .checking, .unsupported:
            return OnboardingTheme.faintText
        }
    }

    private func openAppleWatchApp() {
        guard let url = URL(string: "itms-watch://") else { return }
        openURL(url)
    }

    private var appleHealthConnectionStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                onboardingTitle(
                    "Connect Apple Health",
                    subtitle: "Bring your health and workout data into ATHLTH."
                )

                HStack(spacing: 7) {
                    Text("APPLE HEALTH")
                    Text("2 OF 2")
                }
                .font(.caption2.weight(.bold))
                .tracking(1.15)
                .foregroundStyle(OnboardingTheme.faintText)
            }

            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color(red: 0.90, green: 0.25, blue: 0.34).opacity(0.09))
                            .frame(width: 78, height: 78)

                        Image(systemName: "heart.fill")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(Color(red: 0.90, green: 0.25, blue: 0.34))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(
                            health.hasRequestedAuthorization
                                ? "Apple Health setup finished"
                                : "Your health. In one place."
                        )
                        .font(.title3.weight(.bold))
                        .foregroundStyle(OnboardingTheme.primaryText)

                        Text(
                            health.hasRequestedAuthorization
                                ? "You can change Health access anytime in iPhone Settings."
                                : "Choose exactly what ATHLTH is allowed to read."
                        )
                        .font(.subheadline)
                        .foregroundStyle(OnboardingTheme.mutedText)
                        .lineSpacing(2)
                    }
                }

                VStack(spacing: 0) {
                    healthBenefitRow(
                        icon: "figure.run",
                        title: "Workouts",
                        detail: "Training history, duration, distance and routes"
                    )

                    Divider().padding(.leading, 42)

                    healthBenefitRow(
                        icon: "heart.text.square",
                        title: "Heart & recovery",
                        detail: "Heart rate, resting heart rate and recovery signals"
                    )

                    Divider().padding(.leading, 42)

                    healthBenefitRow(
                        icon: "bed.double.fill",
                        title: "Sleep & activity",
                        detail: "Sleep and activity data that helps complete the picture"
                    )
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(OnboardingTheme.accent)
                        .padding(.top, 2)

                    Text("ATHLTH only requests the Health data needed for the features you use. Apple Health access is optional.")
                        .font(.caption)
                        .foregroundStyle(OnboardingTheme.faintText)
                        .lineSpacing(2)
                }
                .padding(14)
                .background(
                    OnboardingTheme.accent.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
            }
            .padding(20)
            .background(
                OnboardingTheme.card,
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(OnboardingTheme.border, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.05), radius: 20, x: 0, y: 10)

            if let healthError = health.authorizationError {
                Label(healthError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 4)
            } else if let backgroundError = health.backgroundSyncError {
                Label(
                    "Background Health sync needs attention: \(backgroundError)",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.horizontal, 4)
            }

            if importedHealthDetails.hasAnyValue {
                Text(importedHealthSummary)
                    .font(.caption2)
                    .foregroundStyle(OnboardingTheme.faintText)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func healthBenefitRow(
        icon: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(OnboardingTheme.accent)
                .frame(width: 30, height: 30)
                .background(
                    OnboardingTheme.accent.opacity(0.08),
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(OnboardingTheme.mutedText)
                    .lineSpacing(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
    }

    private var readyStep: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(OnboardingTheme.success.opacity(0.10))
                        .frame(width: 82, height: 82)

                    Circle()
                        .stroke(OnboardingTheme.success.opacity(0.16), lineWidth: 1)
                        .frame(width: 82, height: 82)

                    Image(systemName: "checkmark")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(OnboardingTheme.success)
                }

                Text("SETUP COMPLETE")
                    .font(.caption2.weight(.bold))
                    .tracking(1.8)
                    .foregroundStyle(OnboardingTheme.success)
                    .padding(.top, 4)

                Text("You’re ready")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(OnboardingTheme.primaryText)

                Text(readyGoalMessage)
                    .font(.subheadline)
                    .foregroundStyle(OnboardingTheme.mutedText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 330)
            }
            .padding(.top, 14)

            VStack(alignment: .leading, spacing: 0) {
                Text("YOUR SETUP")
                    .font(.caption2.weight(.bold))
                    .tracking(1.25)
                    .foregroundStyle(OnboardingTheme.faintText)
                    .padding(.bottom, 12)

                if let selectedGoal {
                    readySetupRow(
                        title: "Primary goal",
                        value: selectedGoal.title,
                        icon: selectedGoal.systemImage,
                        tint: OnboardingTheme.accent,
                        complete: true
                    )
                }

                if healthReadyForSummary {
                    Divider()
                        .padding(.leading, 44)

                    readySetupRow(
                        title: "Apple Health",
                        value: "Health data connected",
                        icon: "heart.fill",
                        tint: Color(red: 0.90, green: 0.25, blue: 0.34),
                        complete: true
                    )
                }

                Divider()
                    .padding(.leading, 44)

                readySetupRow(
                    title: "Training device",
                    value: readyDeviceSummary,
                    icon: settings.trainingDeviceProvider.systemImage,
                    tint: OnboardingTheme.accent,
                    complete:
                        settings.trainingDeviceProvider != .appleWatch ||
                        watchConnection.isReady
                )
            }
            .padding(18)
            .background(
                OnboardingTheme.card,
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(OnboardingTheme.border, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.045), radius: 18, x: 0, y: 9)
            .padding(.top, 30)

            Text("You can update your goals and connections anytime in ATHLTH.")
                .font(.caption2)
                .foregroundStyle(OnboardingTheme.faintText)
                .multilineTextAlignment(.center)
                .padding(.top, 14)

            Spacer(minLength: 54)

            Button {
                Task {
                    await finishOnboarding()
                }
            } label: {
                HStack {
                    Spacer()
                    Text("Continue")
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

            Spacer(minLength: 34)
        }
        .frame(maxWidth: .infinity, minHeight: 600)
    }

    private var readyDeviceSummary: String {
        switch settings.trainingDeviceProvider {
        case .appleWatch:
            return watchConnection.isReady
                ? "Apple Watch connected"
                : "Apple Watch selected · finish setup in Settings"
        case .garmin:
            return "Garmin selected · authorization pending"
        case .none:
            return "No watch · iPhone/manual mode"
        }
    }

    private var readyGoalMessage: String {
        guard let selectedGoal else {
            return "Your ATHLTH setup is complete."
        }

        switch selectedGoal {
        case .loseWeight:
            return "ATHLTH is ready to help you build consistent habits around your body-weight goal."
        case .buildMuscle:
            return "ATHLTH is ready to help you train with more structure and track your progress."
        case .getStronger:
            return "ATHLTH is ready to help you build strength and see your progress over time."
        case .improveEndurance:
            return "ATHLTH is ready to help you build fitness, stamina and consistency."
        case .runBetter:
            return "ATHLTH is ready to help you run farther, faster and with better insight."
        case .moveMore:
            return "ATHLTH is ready to help you move more and build a more active routine."
        case .recoverySleep:
            return "ATHLTH is ready to help you understand recovery, sleep and readiness."
        case .mobility:
            return "ATHLTH is ready to help you move better and build lasting mobility."
        case .event:
            return "ATHLTH is ready to help you prepare with purpose for what’s ahead."
        case .maintainHealth:
            return "ATHLTH is ready to help you stay active and maintain your fitness."
        }
    }

    private func readySetupRow(
        title: String,
        value: String,
        icon: String,
        tint: Color,
        complete: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(
                    tint.opacity(0.09),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(OnboardingTheme.faintText)

                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if complete {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(OnboardingTheme.success)
                    .frame(width: 24, height: 24)
                    .background(
                        OnboardingTheme.success.opacity(0.10),
                        in: Circle()
                    )
            }
        }
        .padding(.vertical, 9)
    }

    private var healthReadyForSummary: Bool {
        importedHealthDetails.hasAnyValue ||
        !health.workouts.isEmpty ||
        health.sleep.totalAsleep > 0 ||
        health.heart.latestHeartRate != nil ||
        health.heart.restingHeartRate != nil ||
        health.heart.hrvMilliseconds != nil
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
                footerButton(
                    title: "Continue",
                    disabled: selectedGoal == nil || selectedTrainingFocus == nil
                ) {
                    saveProfileData()
                    step = .connections
                }

                personalizedOffersFooter

            case .connections:
                switch connectionStage {
                case .device:
                    footerButton(title: "Continue") {
                        if settings.trainingDeviceProvider == .appleWatch {
                            watchConnection.refreshStatus()
                        }
                        connectionStage = .appleHealth
                    }

                case .appleHealth:
                    connectionsPrivacyFooter

                    if health.hasRequestedAuthorization {
                        footerButton(title: "Continue") {
                            saveProfileData()
                            step = .ready
                        }
                    } else {
                        footerButton(
                            title: healthRequestInProgress
                                ? "Connecting…"
                                : "Connect Apple Health",
                            disabled: healthRequestInProgress
                        ) {
                            connectAppleHealth()
                        }

                        Button("Not now") {
                            saveProfileData()
                            step = .ready
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(OnboardingTheme.mutedText)
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                }

            case .ready:
                EmptyView()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 18)
        .background(OnboardingTheme.card.opacity(0.97))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(OnboardingTheme.border)
                .frame(height: 1)
        }
    }

    private var personalizedOffersFooter: some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.accent)
                    .frame(width: 28, height: 28)
                    .background(
                        OnboardingTheme.accent.opacity(0.10),
                        in: Circle()
                    )

                Text("Personalize offers from my selections")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)

                Spacer()

                Toggle("", isOn: $allowPersonalizedOffers)
                    .labelsHidden()
                    .tint(OnboardingTheme.accent)
                    .scaleEffect(0.88)
            }

            Text("Optional · Uses only the goals and interests you choose here. Never Apple Health data.")
                .font(.caption2)
                .foregroundStyle(OnboardingTheme.faintText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 38)
        }
        .padding(.horizontal, 2)
        .padding(.top, 2)
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
                .foregroundStyle(OnboardingTheme.primaryText)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(OnboardingTheme.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var watchSetupActionTitle: String {
        switch watchConnection.state {
        case .ready:
            return "Verified"
        case .appNotInstalled:
            return "Install"
        case .checking:
            return "Checking…"
        case .notPaired:
            return "Not paired"
        case .unsupported:
            return "Unavailable"
        }
    }

    private var watchSetupActionDisabled: Bool {
        switch watchConnection.state {
        case .ready, .checking, .notPaired, .unsupported:
            return true
        case .appNotInstalled:
            return false
        }
    }

    private func handleWatchSetupAction() {
        switch watchConnection.state {
        case .appNotInstalled:
            showingWatchInstallHelp = true
        case .ready, .checking, .unsupported, .notPaired:
            break
        }
    }

    private var connectionsPrivacyFooter: some View {
        HStack(alignment: .center, spacing: 11) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(OnboardingTheme.accent)
                .frame(width: 32, height: 32)
                .background(
                    OnboardingTheme.accent.opacity(0.09),
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Your health data stays private")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)

                Text("Never published to your profile or shared with friends.")
                    .font(.caption2)
                    .foregroundStyle(OnboardingTheme.faintText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }

    private var importedHealthSummary: String {
        var parts: [String] = []

        if let birthDate = importedHealthDetails.dateOfBirth {
            parts.append("Born \(birthDate.formatted(date: .abbreviated, time: .omitted))")
        }

        if let weight = importedHealthDetails.weightKilograms {
            parts.append(String(format: "%.1f kg", weight))
        }

        if let height = importedHealthDetails.heightCentimeters {
            parts.append("\(Int(height)) cm")
        }

        if let sex = importedHealthDetails.healthSex {
            parts.append(sex.title)
        }

        return parts.isEmpty ? "Apple Health data is available to ATHLTH." : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func connectionRow(
        title: String,
        subtitle: String,
        detail: String? = nil,
        icon: String,
        iconTint: Color,
        complete: Bool,
        actionTitle: String,
        actionDisabled: Bool = false,
        actionLoading: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 15) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(iconTint)
                .frame(width: 48, height: 48)
                .background(
                    iconTint.opacity(0.09),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(iconTint.opacity(0.12), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(OnboardingTheme.primaryText)

                    if complete {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(OnboardingTheme.success)
                    }
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(OnboardingTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(complete ? OnboardingTheme.success : OnboardingTheme.accent)
                            .frame(width: 5, height: 5)

                        Text(detail)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(OnboardingTheme.faintText)
                            .lineLimit(1)
                    }
                    .padding(.top, 1)
                }
            }

            Spacer(minLength: 8)

            Button {
                action()
            } label: {
                HStack(spacing: 6) {
                    if actionLoading {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Text(actionTitle)
                        .lineLimit(1)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    complete
                        ? OnboardingTheme.success
                        : OnboardingTheme.primaryText
                )
                .padding(.horizontal, 13)
                .frame(minHeight: 36)
                .background(
                    complete
                        ? OnboardingTheme.success.opacity(0.09)
                        : OnboardingTheme.subtleFill,
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(
                            complete
                                ? OnboardingTheme.success.opacity(0.18)
                                : OnboardingTheme.border,
                            lineWidth: 1
                        )
                }
            }
            .buttonStyle(.plain)
            .disabled(actionDisabled)
            .opacity(actionDisabled && !actionLoading ? 0.68 : 1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 17)
        .frame(minHeight: 92)
    }

    private func routeAuthenticatedUser(
        _ bootstrap: BackendUserBootstrap,
        usernameSeedFallback: String? = nil
    ) {
        if bootstrap.profile.onboardingCompleted {
            return
        }

        if let existingUsername = bootstrap.profile.username,
           !existingUsername.isEmpty {
            username = existingUsername
            step = .goals
        } else {
            let seed = bootstrap.profile.displayName
                ?? usernameSeedFallback
                ?? "athlete"
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

                let appleGivenName = credential.fullName?.givenName?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let storedAppleNameSeed = await accountService.currentUserNameSeed()
                let appleEmailSeed = credential.email?
                    .split(separator: "@")
                    .first
                    .map(String.init)
                let appleUsernameSeed =
                    (appleGivenName?.isEmpty == false ? appleGivenName : nil)
                    ?? storedAppleNameSeed
                    ?? appleEmailSeed

                routeAuthenticatedUser(
                    bootstrap,
                    usernameSeedFallback: appleUsernameSeed
                )
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
        if step == .connections, connectionStage == .appleHealth {
            connectionStage = .device
            return
        }

        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    private func connectAppleHealth() {
        guard !healthRequestInProgress else { return }

        Task {
            healthRequestInProgress = true

            await health.requestAuthorization()
            await health.completeAuthorizationSetup()

            await health.configureBackgroundSync(
                allowed: settings.backgroundHealthSyncEnabled
            )

            await health.refreshAll()
            await health.refreshPersonalDetails()
            importedHealthDetails = health.personalDetails
            healthRequestInProgress = false
        }
    }

    private func saveProfileData() {
        session.saveOnboardingProfile(
            OnboardingProfileData(
                dateOfBirth: importedHealthDetails.dateOfBirth,
                healthSex: importedHealthDetails.healthSex,
                weightKilograms: importedHealthDetails.weightKilograms,
                heightCentimeters: importedHealthDetails.heightCentimeters,
                personalDetailsSource: importedHealthDetails.hasAnyValue ? .appleHealth : .none,
                trainingFocus: selectedTrainingFocus,
                currentGoal: selectedGoal.map { UserGoalRecord(type: $0) },
                interests: interests,
                personalizedOfferConsent: allowPersonalizedOffers ? .granted : .declined
            )
        )
    }
}

private struct WatchInstallHelpView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let state: AppleWatchConnectionState
    let onCheckAgain: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: watchHeaderIcon)
                        .font(.system(size: 42, weight: .medium))
                        .foregroundStyle(watchHeaderTint)

                    Text(watchHeaderTitle)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(OnboardingTheme.primaryText)

                    Text(watchHeaderDetail)
                        .font(.subheadline)
                        .foregroundStyle(OnboardingTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if state == .appNotInstalled {
                    VStack(alignment: .leading, spacing: 16) {
                        watchInstallStep(
                            number: "1",
                            title: "Open the Watch app",
                            detail: "ATHLTH can take you directly to Apple’s Watch app on this iPhone."
                        )

                        watchInstallStep(
                            number: "2",
                            title: "Find ATHLTH",
                            detail: "Scroll to Available Apps and tap Install next to ATHLTH."
                        )

                        watchInstallStep(
                            number: "3",
                            title: "Return to ATHLTH",
                            detail: "When installation finishes, come back and check the connection again."
                        )
                    }
                    .padding(18)
                    .background(
                        OnboardingTheme.card,
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(OnboardingTheme.border, lineWidth: 1)
                    }
                } else if state == .notPaired {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(
                            "Pair an Apple Watch in Apple’s Watch app first.",
                            systemImage: "link.badge.plus"
                        )
                        Label(
                            "Then return to ATHLTH and check again.",
                            systemImage: "arrow.clockwise"
                        )
                    }
                    .font(.subheadline)
                    .foregroundStyle(OnboardingTheme.mutedText)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        OnboardingTheme.card,
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(OnboardingTheme.border, lineWidth: 1)
                    }
                }

                Spacer()

                if state == .appNotInstalled || state == .notPaired {
                    Button {
                        if let url = URL(string: "itms-watch://") {
                            openURL(url)
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Text("Open Watch app")
                                .font(.headline)
                            Image(systemName: "arrow.up.right")
                            Spacer()
                        }
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                }

                if state != .unsupported {
                    Button {
                        onCheckAgain()
                    } label: {
                        HStack {
                            Spacer()
                            Text(state == .ready ? "Refresh connection" : "Check again")
                                .font(.headline)
                            Image(systemName: "arrow.clockwise")
                            Spacer()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                Button("Done") {
                    dismiss()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OnboardingTheme.mutedText)
                .frame(maxWidth: .infinity)
            }
            .padding(24)
            .background(OnboardingBackground().ignoresSafeArea())
            .navigationTitle("Apple Watch")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.light)
    }

    private var watchHeaderIcon: String {
        switch state {
        case .ready:
            return "checkmark.circle.fill"
        case .appNotInstalled:
            return "applewatch"
        case .notPaired:
            return "applewatch.slash"
        case .checking:
            return "arrow.clockwise"
        case .unsupported:
            return "exclamationmark.triangle.fill"
        }
    }

    private var watchHeaderTint: Color {
        switch state {
        case .ready:
            return OnboardingTheme.success
        case .appNotInstalled, .notPaired:
            return .orange
        case .checking, .unsupported:
            return OnboardingTheme.accent
        }
    }

    private var watchHeaderTitle: String {
        switch state {
        case .ready:
            return "Apple Watch connected"
        case .appNotInstalled:
            return "Install ATHLTH on Apple Watch"
        case .notPaired:
            return "Apple Watch isn’t connected"
        case .checking:
            return "Checking Apple Watch"
        case .unsupported:
            return "Apple Watch unavailable"
        }
    }

    private var watchHeaderDetail: String {
        switch state {
        case .ready:
            return "Your paired Apple Watch has the ATHLTH companion app installed and is ready to use."
        case .appNotInstalled:
            return "Your Apple Watch is paired, but the ATHLTH Watch app still needs to be installed."
        case .notPaired:
            return "ATHLTH can’t find a paired Apple Watch on this iPhone."
        case .checking:
            return "ATHLTH is checking the paired Watch and companion-app installation."
        case .unsupported:
            return "Apple Watch connectivity is not available on this device."
        }
    }

    private func watchInstallStep(
        number: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundStyle(.black)
                .frame(width: 28, height: 28)
                .background(OnboardingTheme.accent, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(OnboardingTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct GarminOnboardingSetupView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: "watch.analog")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(OnboardingTheme.accent)

                Text("Garmin setup")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(OnboardingTheme.primaryText)

                Text(
                    "Garmin Connect support is not enabled yet. When it is released, this is where you’ll sign in, authorize ATHLTH and confirm the Garmin data you want to sync."
                )
                .font(.subheadline)
                .foregroundStyle(OnboardingTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 13) {
                    Label("Connect Garmin account", systemImage: "person.crop.circle.badge.checkmark")
                    Label("Choose permitted health and workout data", systemImage: "checklist")
                    Label("Confirm sync status before continuing", systemImage: "arrow.triangle.2.circlepath")
                }
                .font(.subheadline)
                .foregroundStyle(OnboardingTheme.mutedText)
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    OnboardingTheme.card,
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(OnboardingTheme.border, lineWidth: 1)
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
            }
            .padding(24)
            .background(OnboardingBackground().ignoresSafeArea())
            .navigationTitle("Garmin")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.light)
    }
}

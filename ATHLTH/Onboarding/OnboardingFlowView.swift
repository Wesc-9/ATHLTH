import SwiftUI

struct OnboardingFlowView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var settings: AppSettingsStore

    @State private var step: OnboardingStep = .account
    @State private var username = ""
    @State private var goals: Set<ATHLTHGoal> = []
    @State private var primaryGoal: ATHLTHGoal?
    @State private var importedHealthDetails: HealthProfileBasics = .empty
    @State private var healthRequestInProgress = false
    @State private var showingEmailAuth = false
    @State private var legalDocument: LegalDocumentKind?
    @State private var usernameSuggestions: [String] = []
    @State private var usernameValidation: UsernameValidationState = .idle
    @State private var usernameClaimError: String?

    private let usernameService = MockUsernameAvailabilityService()

    var body: some View {
        VStack(spacing: 0) {
            progressHeader

            ScrollView {
                VStack(spacing: 22) {
                    content
                }
                .padding(24)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }

            footer
        }
        .background(
            LinearGradient(
                colors: [.green.opacity(0.08), .blue.opacity(0.05), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .task {
            guard health.hasRequestedAuthorization else { return }
            await health.refreshPersonalDetails()
            importedHealthDetails = health.personalDetails
        }
        .sheet(isPresented: $showingEmailAuth) {
            EmailAuthView { result in
                session.beginMockSignIn(method: .email)

                switch result {
                case .newUser(let email):
                    let seed = email.split(separator: "@").first.map(String.init) ?? "athlete"
                    session.setUsernameSeed(seed)
                    step = .username
                case .existingUser:
                    session.completeOnboarding()
                }
            }
        }
        .task(id: step) {
            guard step == .username else { return }
            await loadUsernameSuggestions()
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
    }

    private var progressHeader: some View {
        VStack(spacing: 12) {
            HStack {
                if step != .account {
                    Button {
                        goBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 38, height: 38)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 38, height: 38)
                }

                Spacer()

                Text("ATHLTH")
                    .font(.headline.weight(.black))
                    .tracking(5)

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
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .background(.thinMaterial, in: Circle())
                }
                .accessibilityLabel("Language")
            }

            ProgressView(value: step.progress)
                .tint(.green)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 10)
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
            Spacer().frame(height: 28)

            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 82))
                .foregroundStyle(.green)

            Text("Welcome to ATHLTH")
                .font(.largeTitle.weight(.bold))

            Text("Move better. Train smarter. Build a complete picture of your training, recovery and progress.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                Button {
                    session.beginMockSignIn(method: .apple)
                    session.setUsernameSeed(session.profile.displayName)
                    step = .username
                } label: {
                    Label("Continue with Apple", systemImage: "apple.logo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.black)

                Button {
                    showingEmailAuth = true
                } label: {
                    Label("Continue with Email", systemImage: "envelope.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            VStack(spacing: 7) {
                Text("By continuing, you agree to ATHLTH’s")
                    .font(.caption)
                    .foregroundStyle(.secondary)

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
                .font(.caption.weight(.semibold))
            }
            .multilineTextAlignment(.center)
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
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .onChange(of: username) {
                        username = UsernameGenerator.normalizedTypedUsername(username)
                    }

                if let title = usernameValidation.title, !username.isEmpty {
                    Label(title, systemImage: usernameValidation.systemImage)
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
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
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
                "What do you want from ATHLTH?",
                subtitle: "Choose the areas that matter to you, then select one main goal."
            )

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(ATHLTHGoal.allCases) { goal in
                    Button {
                        toggleGoal(goal)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: goal.systemImage)
                                    .foregroundStyle(.green)
                                Spacer()
                                Image(systemName: goals.contains(goal) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(goals.contains(goal) ? Color.green : Color.secondary)
                            }

                            Text(goal.title)
                                .font(.headline)
                                .multilineTextAlignment(.leading)

                            Text(goal.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                }
            }

            if !goals.isEmpty {
                ATHLTHCard {
                    Picker("Main goal", selection: Binding(
                        get: { primaryGoal ?? goals.first! },
                        set: { primaryGoal = $0 }
                    )) {
                        ForEach(Array(goals).sorted(by: { $0.title < $1.title })) { goal in
                            Text(goal.title).tag(goal)
                        }
                    }
                }
            }
        }
    }

    private var connectionsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            onboardingTitle(
                "Connect your health",
                subtitle: "Apple Health can fill in available profile basics and add workouts, heart rate, sleep, recovery and activity data. Everything here is optional."
            )

            ATHLTHCard {
                connectionRow(
                    title: "Apple Health",
                    subtitle: health.hasRequestedAuthorization
                        ? "Connected — use available Health data"
                        : "Import available health and profile data",
                    icon: "heart.fill",
                    connected: health.hasRequestedAuthorization
                ) {
                    Task {
                        healthRequestInProgress = true
                        await health.requestAuthorization()
                        await health.refreshPersonalDetails()
                        importedHealthDetails = health.personalDetails
                        healthRequestInProgress = false
                    }
                }

                if importedHealthDetails.hasAnyValue {
                    Divider()
                        .padding(.vertical, 10)

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Available from Apple Health")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        if let birthDate = importedHealthDetails.dateOfBirth {
                            LabeledContent("Date of birth", value: birthDate.formatted(date: .abbreviated, time: .omitted))
                        }

                        if let sex = importedHealthDetails.healthSex {
                            LabeledContent("Sex", value: sex.title)
                        }

                        if let weight = importedHealthDetails.weightKilograms {
                            LabeledContent("Weight", value: String(format: "%.1f kg", weight))
                        }

                        if let height = importedHealthDetails.heightCentimeters {
                            LabeledContent("Height", value: "\(Int(height)) cm")
                        }
                    }
                    .font(.subheadline)
                }

                Text("Missing profile details can be added later in Settings. ATHLTH never requires them to finish onboarding.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }

            ATHLTHCard {
                connectionRow(
                    title: "Apple Watch",
                    subtitle: settings.watchConnected
                        ? "Connected"
                        : "Optional — ATHLTH works fully from iPhone",
                    icon: "applewatch",
                    connected: settings.watchConnected
                ) {
                    settings.watchConnected.toggle()
                }

                Text("Watch setup can be changed later in Profile → Settings → Connections.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }

            ATHLTHCard {
                Label("Private by default", systemImage: "lock.shield.fill")
                    .font(.headline)
                    .foregroundStyle(.green)

                Text("Connecting Apple Health does not publish health data. Social sharing is controlled separately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
        }
    }

    private var readyStep: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 26)

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 78))
                .foregroundStyle(.green)

            Text("You’re ready")
                .font(.largeTitle.weight(.bold))

            Text("ATHLTH is set up around your goals. Health connections, personal details, privacy, Spotify and other integrations can be changed later in Settings.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let primaryGoal {
                ATHLTHCard {
                    Label(primaryGoal.title, systemImage: primaryGoal.systemImage)
                        .font(.headline)
                        .foregroundStyle(.green)
                    Text("Your main goal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }

            HStack(spacing: 12) {
                readinessChip(
                    title: "Apple Health",
                    connected: health.hasRequestedAuthorization,
                    icon: "heart.fill"
                )
                readinessChip(
                    title: "Apple Watch",
                    connected: settings.watchConnected,
                    icon: "applewatch"
                )
            }

            Text("Spotify and Home Assistant are configured later in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func readinessChip(title: String, connected: Bool, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(connected ? Color.green : Color.secondary)
            Text(title)
                .font(.caption.weight(.semibold))
            Text(connected ? "Connected" : "Add later")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
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
                footerButton(title: "Continue", disabled: goals.isEmpty) {
                    step = .connections
                }

            case .connections:
                footerButton(title: "Continue") {
                    saveProfileData()
                    step = .ready
                }

                Button("Skip for now") {
                    importedHealthDetails = .empty
                    saveProfileData()
                    step = .ready
                }
                .font(.subheadline)

            case .ready:
                footerButton(title: "Enter ATHLTH") {
                    session.completeOnboarding()
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func validationRule(_ title: String, passed: Bool) -> some View {
        Label(
            title,
            systemImage: passed ? "checkmark.circle.fill" : "circle"
        )
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
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.green)
        .disabled(disabled)
    }

    @ViewBuilder
    private func onboardingTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.largeTitle.weight(.bold))
            Text(subtitle)
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
                .foregroundStyle(connected ? Color.green : Color.secondary)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(connected ? "Connected" : "Connect") {
                action()
            }
            .buttonStyle(.bordered)
            .disabled(healthRequestInProgress && title == "Apple Health")
        }
    }

    private func toggleGoal(_ goal: ATHLTHGoal) {
        if goals.contains(goal) {
            goals.remove(goal)
            if primaryGoal == goal {
                primaryGoal = goals.first
            }
        } else {
            goals.insert(goal)
            if primaryGoal == nil {
                primaryGoal = goal
            }
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
                goals: goals,
                primaryGoal: primaryGoal
            )
        )
    }
}

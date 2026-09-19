import SwiftUI

struct OnboardingFlowView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var settings: AppSettingsStore

    @State private var step: OnboardingStep = .account
    @State private var username = ""
    @State private var dateOfBirth = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    @State private var healthSex: HealthSex = .preferNotToSay
    @State private var weightKilograms = 75.0
    @State private var heightCentimeters = 180.0
    @State private var goals: Set<ATHLTHGoal> = []
    @State private var primaryGoal: ATHLTHGoal?
    @State private var healthRequestInProgress = false
    @State private var healthRequestError: String?

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
        .alert("Apple Health", isPresented: Binding(
            get: { healthRequestError != nil },
            set: { if !$0 { healthRequestError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(healthRequestError ?? "")
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
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Text("ATHLTH")
                    .font(.headline.weight(.black))
                    .tracking(5)

                Spacer()

                if step != .account {
                    Color.clear.frame(width: 16, height: 16)
                }
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
        case .personal:
            personalStep
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
                    step = .username
                } label: {
                    Label("Continue with Apple", systemImage: "apple.logo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.black)

                Button {
                    session.beginMockSignIn(method: .email)
                    step = .username
                } label: {
                    Label("Continue with Email", systemImage: "envelope.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Text("By continuing, you agree to ATHLTH’s Terms and Privacy Policy.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var usernameStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            onboardingTitle(
                "Choose your username",
                subtitle: "This is how friends will find you. Every ATHLTH username is unique."
            )

            TextField("@username", text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.title2.weight(.semibold))
                .padding(16)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))

            Text("You can change your display name later. Your username is your unique ATHLTH identity.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var personalStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            onboardingTitle(
                "About you",
                subtitle: "These details help ATHLTH present training and health data in a useful way. They stay private unless you explicitly share them."
            )

            ATHLTHCard {
                DatePicker(
                    "Date of birth",
                    selection: $dateOfBirth,
                    in: ...Date(),
                    displayedComponents: .date
                )

                Divider()

                Picker("Sex for health calculations", selection: $healthSex) {
                    ForEach(HealthSex.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
            }

            ATHLTHCard {
                VStack(spacing: 14) {
                    HStack {
                        Text("Weight")
                        Spacer()
                        Text(String(format: "%.1f kg", weightKilograms))
                            .font(.headline.monospacedDigit())
                    }

                    Slider(value: $weightKilograms, in: 30...250, step: 0.5)

                    Divider()

                    HStack {
                        Text("Height")
                        Spacer()
                        Text("\(Int(heightCentimeters)) cm")
                            .font(.headline.monospacedDigit())
                    }

                    Slider(value: $heightCentimeters, in: 120...230, step: 1)
                }
            }

            Text("Later, Apple Health can be used as the source for weight and height instead of manual values.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var goalsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            onboardingTitle(
                "What do you want from ATHLTH?",
                subtitle: "Choose as many as you like, then mark one as your main goal."
            )

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(ATHLTHGoal.allCases) { goal in
                    Button {
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
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: goal.systemImage)
                                    .foregroundStyle(.green)
                                Spacer()
                                Image(systemName: goals.contains(goal) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(goals.contains(goal) ? .green : .secondary)
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
                subtitle: "Apple Health improves ATHLTH with workouts, heart rate, sleep, recovery and activity data. Apple Watch is optional."
            )

            ATHLTHCard {
                connectionRow(
                    title: "Apple Health",
                    subtitle: health.hasRequestedAuthorization
                        ? "Authorization requested"
                        : "Connect health and workout data",
                    icon: "heart.fill",
                    connected: health.hasRequestedAuthorization
                ) {
                    Task {
                        healthRequestInProgress = true
                        defer { healthRequestInProgress = false }

                        do {
                            try await health.requestAuthorization()
                            await health.configureBackgroundSync()
                            await health.refreshAll()
                        } catch {
                            healthRequestError = error.localizedDescription
                        }
                    }
                }
            }

            ATHLTHCard {
                connectionRow(
                    title: "Apple Watch",
                    subtitle: settings.watchConnected
                        ? "Connected"
                        : "Optional — you can use ATHLTH fully without a Watch",
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
                Label("Your health data stays private by default", systemImage: "lock.shield.fill")
                    .font(.headline)
                    .foregroundStyle(.green)

                Text("Connecting Apple Health does not make health metrics public. Social sharing is controlled separately.")
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

            Text("ATHLTH is set up around your goals. You can change profile details, privacy, Apple Health, Apple Watch and integrations later in Settings.")
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
        }
    }

    @ViewBuilder
    private func footerButton(title: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
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

    private var footer: some View {
        VStack(spacing: 10) {
            switch step {
            case .account:
                EmptyView()

            case .username:
                footerButton(
                    title: "Continue",
                    disabled: username.trimmingCharacters(in: .whitespacesAndNewlines).count < 3
                ) {
                    session.setPendingUsername(username)
                    step = .personal
                }

            case .personal:
                footerButton(title: "Continue") {
                    step = .goals
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

    private func goBack() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    private func saveProfileData() {
        session.saveOnboardingProfile(
            OnboardingProfileData(
                dateOfBirth: dateOfBirth,
                healthSex: healthSex,
                weightKilograms: weightKilograms,
                heightCentimeters: heightCentimeters,
                goals: goals,
                primaryGoal: primaryGoal
            )
        )
    }
}

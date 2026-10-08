import SwiftUI

struct ATHLTHTrainingPlanBuilderFlow: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var goalStore: GoalStore

    let startsAtSourceChoice: Bool
    let initialAdvanced: Bool

    @State private var step: BuilderStep
    @State private var mode: TrainingPlanBuilderMode

    @State private var title = ""
    @State private var weekCount = 8
    @State private var startDate =
        ATHLTHTrainingPlanBuilderFlow.defaultStartDate()

    @State private var focus: TrainingPlanFocus = .generalFitness
    @State private var secondaryFocus: TrainingPlanFocus?
    @State private var focusWeight = 70
    @State private var goal: TrainingPlanGoalType = .improveFitness
    @State private var goalDetail = ""
    @State private var planSummary = ""

    @State private var injuryFree = true
    @State private var injuriesOrLimitations = ""
    @State private var selectedMuscles: Set<String> = []
    @State private var primaryMuscle: String?

    @State private var sessionsPerWeek = 3
    @State private var selectedDays: Set<Int> = [1, 3, 5]
    @State private var workoutKindOverridesByDay:
        [Int: WorkoutKind] = [:]

    @State private var equipment: EquipmentContext = .gym
    @State private var weeklyTimeBudgetMinutes = 240
    @State private var hasCompetitionDate = false
    @State private var competitionDate =
        Calendar.current.date(
            byAdding: .weekOfYear,
            value: 12,
            to: Date()
        ) ?? Date()
    @State private var visibility: ProfileVisibility = .privateOnly

    @State private var selectedGoalIDs: Set<UUID> = []
    @State private var creationError: String?
    @State private var createdPlanID: UUID?
    @State private var showingCreatedPlan = false
    @State private var showingAIBuilder = false
    @State private var dismissAfterAI = false
    @State private var didApplySuggestedStartDate = false

    init(
        startsAtSourceChoice: Bool,
        initialAdvanced: Bool
    ) {
        self.startsAtSourceChoice =
            startsAtSourceChoice
        self.initialAdvanced =
            initialAdvanced
        // Name and duration come first for every entry path.
        _step = State(initialValue: .basics)
        _mode = State(
            initialValue:
                initialAdvanced
                    ? .advanced
                    : .basic
        )
    }

    private enum BuilderStep: Int, CaseIterable {
        case source
        case basics
        case profile
        case week
        case review

        var number: Int {
            switch self {
            case .source:
                return 0
            case .basics:
                return 1
            case .profile:
                return 2
            case .week:
                return 3
            case .review:
                return 4
            }
        }
    }

    private enum EquipmentContext: String, CaseIterable, Identifiable {
        case gym
        case home
        case both

        var id: String { rawValue }

        var title: String {
            switch self {
            case .gym:
                return ATHLTHLocalization.choose(
                    english: "Gym",
                    norwegian: "Treningssenter"
                )
            case .home:
                return ATHLTHLocalization.choose(
                    english: "Home",
                    norwegian: "Hjemme"
                )
            case .both:
                return ATHLTHLocalization.choose(
                    english: "Both",
                    norwegian: "Begge"
                )
            }
        }

        var icon: String {
            switch self {
            case .gym:
                return "dumbbell.fill"
            case .home:
                return "house.fill"
            case .both:
                return "arrow.left.arrow.right"
            }
        }
    }

    private struct MuscleOption: Identifiable {
        let id: String
        let english: String
        let norwegian: String

        var title: String {
            ATHLTHLocalization.choose(
                english: english,
                norwegian: norwegian
            )
        }
    }

    private static let muscleOptions: [MuscleOption] = [
        .init(
            id: "chest",
            english: "Chest",
            norwegian: "Bryst"
        ),
        .init(
            id: "back",
            english: "Back",
            norwegian: "Rygg"
        ),
        .init(
            id: "shoulders",
            english: "Shoulders",
            norwegian: "Skuldre"
        ),
        .init(
            id: "biceps",
            english: "Biceps",
            norwegian: "Biceps"
        ),
        .init(
            id: "triceps",
            english: "Triceps",
            norwegian: "Triceps"
        ),
        .init(
            id: "forearms",
            english: "Forearms",
            norwegian: "Underarmer"
        ),
        .init(
            id: "quads",
            english: "Quadriceps",
            norwegian: "Forside lår"
        ),
        .init(
            id: "hamstrings",
            english: "Hamstrings",
            norwegian: "Bakside lår"
        ),
        .init(
            id: "glutes",
            english: "Glutes",
            norwegian: "Sete"
        ),
        .init(
            id: "calves",
            english: "Calves",
            norwegian: "Legger"
        ),
        .init(
            id: "core",
            english: "Core",
            norwegian: "Kjerne"
        )
    ]

    private static func defaultStartDate() -> Date {
        let calendar = Calendar.current
        let today =
            calendar.startOfDay(for: Date())

        return calendar.nextDate(
            after: today,
            matching:
                DateComponents(weekday: 2),
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ) ?? today
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ATHLTHPremiumCanvas(
                    accent:
                        mode == .advanced
                            ? ATHLTHTheme.premiumGold
                                .opacity(0.34)
                            : ATHLTHTheme.accent
                                .opacity(0.28)
                )

                content
            }
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english: "New training plan",
                    norwegian: "Ny treningsplan"
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .cancellationAction
                ) {
                    Button(
                        backButtonTitle
                    ) {
                        goBack()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if step != .source {
                    bottomActionBar
                }
            }
            .navigationDestination(
                for: ExistingPlanDestination.self
            ) { destination in
                switch destination {
                case .library:
                    TrainingPlanLibraryView {
                        dismiss()
                    }
                case .mine:
                    MyTrainingPlansLibraryView()
                }
            }
            .navigationDestination(
                isPresented: $showingCreatedPlan
            ) {
                if let createdPlanID {
                    ScrollView {
                        AdvancedPlannerView(planID: createdPlanID)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                    }
                    .background(
                        ATHLTHPremiumCanvas(
                            accent: ATHLTHTheme.accent.opacity(0.30)
                        )
                    )
                    .navigationTitle(
                        ATHLTHLocalization.choose(
                            english: "Build your workouts",
                            norwegian: "Bygg treningsøktene"
                        )
                    )
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(
                                ATHLTHLocalization.choose(
                                    english: "Done",
                                    norwegian: "Ferdig"
                                )
                            ) {
                                dismiss()
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            guard !didApplySuggestedStartDate
            else {
                return
            }

            didApplySuggestedStartDate = true

            let suggested =
                session
                    .suggestedTrainingPlanStartDate
            let defaultDate =
                Self.defaultStartDate()

            startDate =
                max(
                    defaultDate,
                    Calendar.current
                        .startOfDay(
                            for: suggested
                        )
                )
        }
        .onChange(
            of: sessionsPerWeek
        ) { _, newValue in
            let suggested =
                balancedDays(
                    count: newValue
                )
            if selectedDays.count !=
                newValue {
                selectedDays = suggested
            }
        }
        .alert(
            ATHLTHLocalization.choose(
                english: "Could not create plan",
                norwegian: "Kunne ikke opprette planen"
            ),
            isPresented:
                Binding(
                    get: {
                        creationError != nil
                    },
                    set: { shown in
                        if !shown {
                            creationError = nil
                        }
                    }
                )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(creationError ?? "")
        }
        .sheet(
            isPresented: $showingAIBuilder,
            onDismiss: {
                if dismissAfterAI {
                    dismiss()
                }
            }
        ) {
            AIProgramBuilderView(
                mode: .generate,
                seed: aiBuilderSeed,
                onProgramCreated: {
                    dismissAfterAI = true
                }
            )
        }
    }

    private enum ExistingPlanDestination: Hashable {
        case library
        case mine
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .source:
            sourceChoice
        case .basics:
            wizardScroll {
                basicsStep
            }
        case .profile:
            wizardScroll {
                profileStep
            }
        case .week:
            wizardScroll {
                weekStep
            }
        case .review:
            wizardScroll {
                reviewStep
            }
        }
    }

    private func wizardScroll<Content: View>(
        @ViewBuilder content:
            () -> Content
    ) -> some View {
        ScrollView {
            LazyVStack(
                alignment: .leading,
                spacing: 16
            ) {
                progressHeader
                modeControl
                content()
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 118)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private var sourceChoice: some View {
        ScrollView {
            LazyVStack(
                alignment: .leading,
                spacing: 18
            ) {
                VStack(
                    alignment: .leading,
                    spacing: 8
                ) {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "TRAINING PLAN",
                            norwegian: "TRENINGSPLAN"
                        )
                    )
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2.0)
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english: "How do you want to start?",
                            norwegian: "Hvordan vil du starte?"
                        )
                    )
                    .font(
                        .system(
                            size: 33,
                            weight: .semibold,
                            design: .serif
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Build a plan around you, or start from something that already works and make it yours.",
                            norwegian:
                                "Bygg en plan rundt deg, eller start fra noe som allerede fungerer og gjør det til ditt."
                        )
                    )
                    .font(.subheadline)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                    .lineSpacing(2)
                }

                Button {
                    withAnimation(
                        .easeInOut(duration: 0.18)
                    ) {
                        step = .profile
                    }
                } label: {
                    sourceCard(
                        eyebrow:
                            ATHLTHLocalization.choose(
                                english: "NEW PLAN",
                                norwegian: "NY PLAN"
                            ),
                        title:
                            ATHLTHLocalization.choose(
                                english: "Build from scratch",
                                norwegian: "Bygg fra scratch"
                            ),
                        subtitle:
                            ATHLTHLocalization.choose(
                                english:
                                    "Name it, choose the length, tell ATHLTH what you want and build the week.",
                                norwegian:
                                    "Gi planen navn, velg lengde, fortell hva du ønsker og bygg treningsuken."
                            ),
                        footnote:
                            ATHLTHLocalization.choose(
                                english:
                                    "Basic or Advanced · change anytime",
                                norwegian:
                                    "Basic eller Avansert · bytt når du vil"
                            ),
                        icon: "wand.and.stars",
                        prominent: true
                    )
                }
                .buttonStyle(.plain)

                NavigationLink(
                    value:
                        ExistingPlanDestination.library
                ) {
                    sourceCard(
                        eyebrow:
                            ATHLTHLocalization.choose(
                                english: "EXISTING PLAN",
                                norwegian: "EKSISTERENDE PLAN"
                            ),
                        title:
                            ATHLTHLocalization.choose(
                                english: "Use an existing plan",
                                norwegian: "Bruk eksisterende plan"
                            ),
                        subtitle:
                            ATHLTHLocalization.choose(
                                english:
                                    "Choose a finished plan from the Library and adapt it to your dates and needs.",
                                norwegian:
                                    "Velg en ferdig plan fra biblioteket og tilpass den til dine datoer og behov."
                            ),
                        footnote:
                            ATHLTHLocalization.choose(
                                english:
                                    "Curated plans · preview before use",
                                norwegian:
                                    "Ferdige planer · forhåndsvis før bruk"
                            ),
                        icon:
                            "square.stack.3d.up.fill",
                        prominent: false
                    )
                }
                .buttonStyle(.plain)

                NavigationLink(
                    value:
                        ExistingPlanDestination.mine
                ) {
                    compactSourceRow(
                        title:
                            ATHLTHLocalization.choose(
                                english: "My plans & templates",
                                norwegian: "Mine planer og maler"
                            ),
                        subtitle:
                            ATHLTHLocalization.choose(
                                english:
                                    "Reuse a saved, previous or scheduled plan.",
                                norwegian:
                                    "Bruk en lagret, tidligere eller planlagt plan på nytt."
                            ),
                        icon: "calendar.badge.clock"
                    )
                }
                .buttonStyle(.plain)

                HStack(
                    alignment: .top,
                    spacing: 10
                ) {
                    Image(
                        systemName:
                            "checkmark.shield.fill"
                    )
                    .foregroundStyle(
                        ATHLTHTheme.vitality
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "The original is never changed when you start from an existing plan.",
                            norwegian:
                                "Originalen endres aldri når du starter fra en eksisterende plan."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 36)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private func sourceCard(
        eyebrow: String,
        title: String,
        subtitle: String,
        footnote: String,
        icon: String,
        prominent: Bool
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 18
        ) {
            HStack {
                Image(systemName: icon)
                    .font(
                        .system(
                            size: 22,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        prominent
                            ? Color.white
                            : ATHLTHTheme.accentDeep
                    )
                    .frame(width: 54, height: 54)
                    .background(
                        prominent
                            ? Color.white.opacity(0.13)
                            : ATHLTHTheme.accentSoft,
                        in: RoundedRectangle(
                            cornerRadius: 17,
                            style: .continuous
                        )
                    )

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.subheadline.bold())
                    .foregroundStyle(
                        prominent
                            ? Color.white
                            : ATHLTHTheme.accentDeep
                    )
            }

            VStack(
                alignment: .leading,
                spacing: 6
            ) {
                Text(eyebrow)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.55)
                    .foregroundStyle(
                        prominent
                            ? Color.white.opacity(0.62)
                            : ATHLTHTheme.mutedText
                    )

                Text(title)
                    .font(
                        .system(
                            size: 24,
                            weight: .bold,
                            design: .serif
                        )
                    )
                    .foregroundStyle(
                        prominent
                            ? Color.white
                            : ATHLTHTheme.primaryText
                    )

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(
                        prominent
                            ? Color.white.opacity(0.76)
                            : ATHLTHTheme.mutedText
                    )
                    .lineSpacing(2)
            }

            Text(footnote)
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    prominent
                        ? Color.white.opacity(0.72)
                        : ATHLTHTheme.accentDeep
                )
        }
        .padding(20)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background(
            LinearGradient(
                colors:
                    prominent
                    ? [
                        ATHLTHTheme.accentDeep,
                        Color(
                            red: 0.15,
                            green: 0.18,
                            blue: 0.24
                        )
                    ]
                    : [
                        Color.white.opacity(0.96),
                        ATHLTHTheme.cardWarm
                            .opacity(0.48)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(
                    prominent ? 0.10 : 0.92
                ),
                lineWidth: 0.9
            )
        }
        .shadow(
            color:
                ATHLTHTheme.accentDeep
                    .opacity(
                        prominent ? 0.17 : 0.06
                    ),
            radius: 18,
            y: 9
        )
    }

    private func compactSourceRow(
        title: String,
        subtitle: String,
        icon: String
    ) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(
                    .system(
                        size: 18,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )
                .frame(width: 44, height: 44)
                .background(
                    ATHLTHTheme.accentSoft,
                    in: RoundedRectangle(
                        cornerRadius: 13,
                        style: .continuous
                    )
                )

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                    .multilineTextAlignment(.leading)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(15)
        .background(
            Color.white.opacity(0.72),
            in: RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.88),
                lineWidth: 0.8
            )
        }
    }

    private var progressHeader: some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            HStack {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "STEP \(step.number) OF 4",
                        norwegian:
                            "STEG \(step.number) AV 4"
                    )
                )
                .font(.system(size: 9, weight: .bold))
                .tracking(1.55)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )

                Spacer()

                Text(stepTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )
            }

            HStack(spacing: 6) {
                ForEach(1...4, id: \.self) {
                    index in
                    Capsule()
                        .fill(
                            index <= step.number
                                ? ATHLTHTheme.accentDeep
                                : ATHLTHTheme.accent
                                    .opacity(0.10)
                        )
                        .frame(height: 5)
                }
            }
        }
    }

    private var stepTitle: String {
        switch step {
        case .source:
            return ""
        case .basics:
            return ATHLTHLocalization.choose(
                english: "Plan basics",
                norwegian: "Grunninfo"
            )
        case .profile:
            return ATHLTHLocalization.choose(
                english: "Goal & needs",
                norwegian: "Mål og behov"
            )
        case .week:
            return ATHLTHLocalization.choose(
                english: "Training week",
                norwegian: "Treningsuken"
            )
        case .review:
            return ATHLTHLocalization.choose(
                english: "Review",
                norwegian: "Oppsummering"
            )
        }
    }

    private var modeControl: some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            ATHLTHPremiumSegmentedControl(
                titles: [
                    "Basic",
                    ATHLTHLocalization.choose(
                        english: "Advanced",
                        norwegian: "Avansert"
                    )
                ],
                selection: modeSelection
            )

            HStack(
                alignment: .top,
                spacing: 8
            ) {
                Image(
                    systemName:
                        mode == .basic
                            ? "sparkles"
                            : "slider.horizontal.3"
                )
                .font(.caption.weight(.bold))
                .foregroundStyle(
                    mode == .basic
                        ? ATHLTHTheme.vitality
                        : ATHLTHTheme.premiumGold
                )
                .padding(.top, 1)

                Text(modeExplanation)
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
            }
            .padding(.horizontal, 4)
        }
    }

    private var modeSelection: Binding<Int> {
        Binding(
            get: {
                mode == .basic ? 0 : 1
            },
            set: { newValue in
                mode =
                    newValue == 0
                        ? .basic
                        : .advanced
            }
        )
    }

    private var modeExplanation: String {
        switch mode {
        case .basic:
            return ATHLTHLocalization.choose(
                english:
                    "Simple language and only the choices you need. ATHLTH fills in the structure for you.",
                norwegian:
                    "Enkelt språk og bare valgene du trenger. ATHLTH hjelper deg med strukturen."
            )
        case .advanced:
            return ATHLTHLocalization.choose(
                english:
                    "More control for athletes and coaches: secondary focus, targets, time budget and competition date.",
                norwegian:
                    "Mer kontroll for utøvere og trenere: sekundærfokus, måltall, tidsbudsjett og konkurransedato."
            )
        }
    }

    private var basicsStep: some View {
        VStack(
            alignment: .leading,
            spacing: 16
        ) {
            stepIntro(
                eyebrow:
                    ATHLTHLocalization.choose(
                        english: "01 · PLAN BASICS",
                        norwegian: "01 · GRUNNINFO"
                    ),
                title:
                    ATHLTHLocalization.choose(
                        english: "Give the plan a frame",
                        norwegian: "Gi planen en ramme"
                    ),
                subtitle:
                    ATHLTHLocalization.choose(
                        english:
                            "A clear name, a start date and how long you want the plan to run.",
                        norwegian:
                            "Et tydelig navn, startdato og hvor lenge du vil følge planen."
                    ),
                icon: "calendar"
            )

            builderPanel {
                VStack(spacing: 14) {
                    fieldLabel(
                        ATHLTHLocalization.choose(
                            english: "Plan name",
                            norwegian: "Navn på planen"
                        )
                    )

                    TextField(
                        ATHLTHLocalization.choose(
                            english:
                                "e.g. Stronger this autumn",
                            norwegian:
                                "f.eks. Sterkere i høst"
                        ),
                        text: $title
                    )
                    .textFieldStyle(.plain)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 13)
                    .frame(height: 48)
                    .background(
                        Color.black.opacity(0.026),
                        in: RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                    )
                    .onChange(of: title) {
                        _, newValue in
                        if newValue.count > 40 {
                            title =
                                String(
                                    newValue
                                        .prefix(40)
                                )
                        }
                    }

                    HStack {
                        Spacer()

                        Text("\(title.count)/40")
                            .font(.caption2)
                            .foregroundStyle(
                                ATHLTHTheme.mutedText
                            )
                    }

                    Divider()

                    DatePicker(
                        ATHLTHLocalization.choose(
                            english: "Starts",
                            norwegian: "Starter"
                        ),
                        selection: $startDate,
                        in:
                            Calendar.current
                                .startOfDay(
                                    for: Date()
                                )...,
                        displayedComponents: .date
                    )
                    .font(.subheadline.weight(.semibold))

                    Divider()

                    VStack(
                        alignment: .leading,
                        spacing: 10
                    ) {
                        fieldLabel(
                            ATHLTHLocalization.choose(
                                english: "Duration",
                                norwegian: "Varighet"
                            )
                        )

                        durationOptions
                    }

                    HStack {
                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Text(
                                ATHLTHLocalization.choose(
                                    english: "PLAN WINDOW",
                                    norwegian: "PLANPERIODE"
                                )
                            )
                            .font(.system(size: 8.5, weight: .bold))
                            .tracking(1.1)
                            .foregroundStyle(
                                ATHLTHTheme.mutedText
                            )

                            Text(
                                ATHLTHLocalization.choose(
                                    english:
                                        "\(weekCount) weeks",
                                    norwegian:
                                        "\(weekCount) uker"
                                )
                            )
                            .font(.headline)
                        }

                        Spacer()

                        Text(
                            "\(startDate.formatted(date: .abbreviated, time: .omitted))\n– \(resolvedEndDate.formatted(date: .abbreviated, time: .omitted))"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                        .multilineTextAlignment(
                            .trailing
                        )
                    }
                    .padding(12)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                    )
                }
            }

            if let conflict = conflictingPlan {
                conflictCard(conflict)
            }

            if mode == .advanced {
                builderPanel {
                    VStack(spacing: 12) {
                        HStack {
                            VStack(
                                alignment: .leading,
                                spacing: 3
                            ) {
                                Text(
                                    ATHLTHLocalization.choose(
                                        english: "Visibility",
                                        norwegian: "Synlighet"
                                    )
                                )
                                .font(.subheadline.weight(.semibold))

                                Text(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Who can see the plan",
                                        norwegian:
                                            "Hvem kan se planen"
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    ATHLTHTheme.mutedText
                                )
                            }

                            Spacer()

                            Picker(
                                "Visibility",
                                selection: $visibility
                            ) {
                                ForEach(
                                    ProfileVisibility
                                        .allCases
                                ) { item in
                                    Text(item.title)
                                        .tag(item)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }

                        Divider()

                        VStack(
                            alignment: .leading,
                            spacing: 7
                        ) {
                            fieldLabel(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Plan note",
                                    norwegian:
                                        "Kort planbeskrivelse"
                                )
                            )

                            TextField(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Optional context for the season or block",
                                    norwegian:
                                        "Valgfri beskrivelse av perioden"
                                ),
                                text: $planSummary,
                                axis: .vertical
                            )
                            .lineLimit(2...4)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(
                                Color.black
                                    .opacity(0.026),
                                in:
                                    RoundedRectangle(
                                        cornerRadius: 13,
                                        style: .continuous
                                    )
                            )
                        }
                    }
                }
            }
        }
    }

    private var durationOptions: some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 64), spacing: 8)
            ],
            spacing: 8
        ) {
            ForEach(
                [4, 6, 8, 12, 16],
                id: \.self
            ) { value in
                Button {
                    weekCount = value
                } label: {
                    VStack(spacing: 2) {
                        Text("\(value)")
                            .font(.headline)
                        Text(
                            ATHLTHLocalization.choose(
                                english: "weeks",
                                norwegian: "uker"
                            )
                        )
                        .font(.caption2)
                    }
                    .foregroundStyle(
                        weekCount == value
                            ? Color.white
                            : ATHLTHTheme.primaryText
                    )
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 52
                    )
                    .background(
                        weekCount == value
                            ? ATHLTHTheme.accentDeep
                            : Color.white.opacity(0.72),
                        in: RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                    )
                }
                .buttonStyle(.plain)
            }

            Menu {
                ForEach(1...52, id: \.self) {
                    value in
                    Button(
                        ATHLTHLocalization.choose(
                            english:
                                "\(value) weeks",
                            norwegian:
                                "\(value) uker"
                        )
                    ) {
                        weekCount = value
                    }
                }
            } label: {
                VStack(spacing: 2) {
                    Image(
                        systemName:
                            "ellipsis"
                    )
                    .font(.headline)

                    Text(
                        ATHLTHLocalization.choose(
                            english: "Custom",
                            norwegian: "Annet"
                        )
                    )
                    .font(.caption2)
                }
                .foregroundStyle(
                    [4, 6, 8, 12, 16]
                        .contains(weekCount)
                        ? ATHLTHTheme.mutedText
                        : ATHLTHTheme.accentDeep
                )
                .frame(
                    maxWidth: .infinity,
                    minHeight: 52
                )
                .background(
                    Color.white.opacity(0.72),
                    in: RoundedRectangle(
                        cornerRadius: 14,
                        style: .continuous
                    )
                )
            }
        }
    }

    private var profileStep: some View {
        VStack(
            alignment: .leading,
            spacing: 16
        ) {
            stepIntro(
                eyebrow:
                    ATHLTHLocalization.choose(
                        english: "02 · GOAL & NEEDS",
                        norwegian: "02 · MÅL OG BEHOV"
                    ),
                title:
                    ATHLTHLocalization.choose(
                        english: "What should this plan do for you?",
                        norwegian: "Hva skal planen gjøre for deg?"
                    ),
                subtitle:
                    ATHLTHLocalization.choose(
                        english:
                            "These answers shape the week. You can change them later.",
                        norwegian:
                            "Svarene former treningsuken. Alt kan endres senere."
                    ),
                icon: "scope"
            )

            builderPanel {
                VStack(
                    alignment: .leading,
                    spacing: 12
                ) {
                    fieldLabel(
                        ATHLTHLocalization.choose(
                            english: "Main focus",
                            norwegian: "Hovedfokus"
                        )
                    )

                    focusGrid

                    if mode == .advanced {
                        Divider()

                        advancedFocusControls
                    }
                }
            }

            builderPanel {
                VStack(
                    alignment: .leading,
                    spacing: 12
                ) {
                    fieldLabel(
                        ATHLTHLocalization.choose(
                            english: "Main goal",
                            norwegian: "Hva ønsker du å oppnå?"
                        )
                    )

                    goalGrid

                    if mode == .advanced {
                        Divider()

                        TextField(
                            ATHLTHLocalization.choose(
                                english:
                                    "Concrete target, e.g. 5K in 20:00 or squat 150 kg",
                                norwegian:
                                    "Konkret mål, f.eks. 5 km på 20:00 eller 150 kg i knebøy"
                            ),
                            text: $goalDetail,
                            axis: .vertical
                        )
                        .lineLimit(2...4)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(
                            Color.black.opacity(0.026),
                            in: RoundedRectangle(
                                cornerRadius: 13,
                                style: .continuous
                            )
                        )
                    }
                }
            }

            if showMusclePriorities {
                builderPanel {
                    VStack(
                        alignment: .leading,
                        spacing: 10
                    ) {
                        fieldLabel(
                            ATHLTHLocalization.choose(
                                english:
                                    "Muscles you want to prioritise",
                                norwegian:
                                    "Muskler du vil prioritere"
                            )
                        )

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Optional. Choose one or more areas you want the plan to emphasise.",
                                norwegian:
                                    "Valgfritt. Velg ett eller flere områder planen skal prioritere."
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )

                        muscleGrid

                        if selectedMuscles.count > 1 {
                            HStack {
                                Text(
                                    ATHLTHLocalization.choose(
                                        english: "Primary muscle",
                                        norwegian: "Hovedmuskel"
                                    )
                                )
                                .font(.subheadline.weight(.semibold))

                                Spacer()

                                Picker(
                                    ATHLTHLocalization.choose(
                                        english: "Primary muscle",
                                        norwegian: "Hovedmuskel"
                                    ),
                                    selection: Binding(
                                        get: {
                                            primaryMuscle ??
                                                selectedMuscles.sorted().first ??
                                                ""
                                        },
                                        set: { primaryMuscle = $0 }
                                    )
                                ) {
                                    ForEach(
                                        Self.muscleOptions.filter {
                                            selectedMuscles.contains($0.id)
                                        }
                                    ) { muscle in
                                        Text(muscle.title).tag(muscle.id)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                            }
                        }

                        if !selectedMuscles.isEmpty {
                            Text(
                                ATHLTHLocalization.choose(
                                    english: "Editable exercise suggestions can be included in the proposed strength days. You choose the final programme.",
                                    norwegian: "Redigerbare øvelsesforslag kan legges i styrkeøktene. Du bestemmer det endelige programmet."
                                )
                            )
                            .font(.caption2)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                        }
                    }
                }
            }

            builderPanel {
                VStack(
                    alignment: .leading,
                    spacing: 12
                ) {
                    fieldLabel(
                        ATHLTHLocalization.choose(
                            english:
                                "Injuries or limitations",
                            norwegian:
                                "Skader eller begrensninger"
                        )
                    )

                    HStack(spacing: 8) {
                        choicePill(
                            title:
                                ATHLTHLocalization.choose(
                                    english:
                                        "No known issues",
                                    norwegian:
                                        "Ingen kjente"
                                ),
                            icon:
                                "checkmark.circle.fill",
                            selected: injuryFree
                        ) {
                            injuryFree = true
                        }

                        choicePill(
                            title:
                                ATHLTHLocalization.choose(
                                    english:
                                        "I have something to consider",
                                    norwegian:
                                        "Har skade / hensyn"
                                ),
                            icon:
                                "cross.case.fill",
                            selected: !injuryFree
                        ) {
                            injuryFree = false
                        }
                    }

                    if !injuryFree {
                        TextField(
                            ATHLTHLocalization.choose(
                                english:
                                    "Describe what the plan should account for",
                                norwegian:
                                    "Beskriv hva planen skal ta hensyn til"
                            ),
                            text:
                                $injuriesOrLimitations,
                            axis: .vertical
                        )
                        .lineLimit(2...5)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(
                            ATHLTHTheme
                                .premiumGoldSoft
                                .opacity(0.50),
                            in: RoundedRectangle(
                                cornerRadius: 13,
                                style: .continuous
                            )
                        )

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "ATHLTH treats this as planning context, not medical advice.",
                                norwegian:
                                    "ATHLTH bruker dette som planleggingsinformasjon, ikke som medisinsk rådgivning."
                            )
                        )
                        .font(.caption2)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                    }
                }
            }

            if mode == .advanced {
                builderPanel {
                    VStack(spacing: 12) {
                        Toggle(
                            ATHLTHLocalization.choose(
                                english:
                                    "Competition / target date",
                                norwegian:
                                    "Konkurranse / måldato"
                            ),
                            isOn:
                                $hasCompetitionDate
                        )

                        if hasCompetitionDate {
                            DatePicker(
                                ATHLTHLocalization.choose(
                                    english: "Target date",
                                    norwegian: "Måldato"
                                ),
                                selection:
                                    $competitionDate,
                                in: startDate...,
                                displayedComponents:
                                    .date
                            )
                        }
                    }
                }
            }
        }
    }

    private var focusGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ],
            spacing: 8
        ) {
            ForEach(
                TrainingPlanFocus.allCases
            ) { item in
                Button {
                    focus = item

                    if secondaryFocus == item {
                        secondaryFocus = nil
                    }
                } label: {
                    HStack(spacing: 9) {
                        Image(
                            systemName:
                                item.systemImage
                        )
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 28)

                        Text(item.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(
                        focus == item
                            ? Color.white
                            : ATHLTHTheme.primaryText
                    )
                    .padding(.horizontal, 11)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 48
                    )
                    .background(
                        focus == item
                            ? ATHLTHTheme.accentDeep
                            : Color.white.opacity(0.72),
                        in: RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var advancedFocusControls: some View {
        VStack(
            alignment: .leading,
            spacing: 11
        ) {
            HStack {
                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Secondary focus",
                            norwegian:
                                "Sekundærfokus"
                        )
                    )
                    .font(.subheadline.weight(.semibold))

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Optional for hybrid goals",
                            norwegian:
                                "Valgfritt ved kombinerte mål"
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }

                Spacer()

                Menu {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "None",
                            norwegian: "Ingen"
                        )
                    ) {
                        secondaryFocus = nil
                    }

                    ForEach(
                        TrainingPlanFocus.allCases
                            .filter {
                                $0 != focus
                            }
                    ) { item in
                        Button(item.title) {
                            secondaryFocus = item
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(
                            secondaryFocus?.title ??
                            ATHLTHLocalization.choose(
                                english: "None",
                                norwegian: "Ingen"
                            )
                        )
                        .lineLimit(1)

                        Image(
                            systemName:
                                "chevron.down"
                        )
                        .font(.caption2.bold())
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: Capsule()
                    )
                }
            }

            if let secondaryFocus {
                HStack {
                    Text(focus.title)
                        .font(.caption.weight(.semibold))

                    Spacer()

                    Text(
                        "\(focusWeight) / \(100 - focusWeight)"
                    )
                    .font(
                        .caption.monospacedDigit()
                            .weight(.bold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )

                    Spacer()

                    Text(secondaryFocus.title)
                        .font(.caption.weight(.semibold))
                }

                Slider(
                    value:
                        Binding(
                            get: {
                                Double(focusWeight)
                            },
                            set: {
                                focusWeight =
                                    Int($0)
                            }
                        ),
                    in: 50...90,
                    step: 5
                )
                .tint(ATHLTHTheme.accentDeep)
            }
        }
    }

    private var goalGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ],
            spacing: 8
        ) {
            ForEach(
                TrainingPlanGoalType.allCases
            ) { item in
                Button {
                    goal = item
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(
                                goal == item
                                    ? Color.white
                                    : ATHLTHTheme
                                        .accent
                                        .opacity(0.12)
                            )
                            .frame(width: 23, height: 23)
                            .overlay {
                                if goal == item {
                                    Image(
                                        systemName:
                                            "checkmark"
                                    )
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(
                                        ATHLTHTheme.accentDeep
                                    )
                                }
                            }

                        Text(item.title)
                            .font(.caption.weight(.semibold))
                            .multilineTextAlignment(.leading)

                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(
                        goal == item
                            ? Color.white
                            : ATHLTHTheme.primaryText
                    )
                    .padding(.horizontal, 10)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 48
                    )
                    .background(
                        goal == item
                            ? ATHLTHTheme.accentDeep
                            : Color.white.opacity(0.72),
                        in: RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var showMusclePriorities: Bool {
        focus == .hypertrophy ||
        focus == .strength ||
        goal == .buildMuscle ||
        goal == .getStronger
    }

    private var muscleGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 86), spacing: 8)
            ],
            spacing: 8
        ) {
            ForEach(
                Self.muscleOptions
            ) { muscle in
                let selected =
                    selectedMuscles
                        .contains(muscle.id)

                Button {
                    if selected {
                        selectedMuscles.remove(muscle.id)
                        if primaryMuscle == muscle.id {
                            primaryMuscle = selectedMuscles.sorted().first
                        }
                    } else {
                        selectedMuscles.insert(muscle.id)
                        if primaryMuscle == nil {
                            primaryMuscle = muscle.id
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        if selected {
                            Image(
                                systemName: primaryMuscle == muscle.id
                                    ? "star.fill"
                                    : "checkmark"
                            )
                            .font(.system(size: 10, weight: .bold))
                        }
                        Text(muscle.title)
                            .font(.caption.weight(.semibold))
                    }
                        .foregroundStyle(
                            selected
                                ? Color.white
                                : ATHLTHTheme.primaryText
                        )
                        .frame(
                            maxWidth: .infinity,
                            minHeight: 39
                        )
                        .background(
                            selected
                                ? ATHLTHTheme.accentDeep
                                : ATHLTHTheme.accentSoft,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if selected && primaryMuscle != muscle.id {
                        Button {
                            primaryMuscle = muscle.id
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Set as primary focus",
                                    norwegian: "Velg som hovedfokus"
                                ),
                                systemImage: "star.fill"
                            )
                        }
                    }
                }
            }
        }
    }

    private func choicePill(
        title: String,
        icon: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))

                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
            }
            .foregroundStyle(
                selected
                    ? Color.white
                    : ATHLTHTheme.primaryText
            )
            .padding(.horizontal, 10)
            .frame(
                maxWidth: .infinity,
                minHeight: 44
            )
            .background(
                selected
                    ? ATHLTHTheme.accentDeep
                    : Color.white.opacity(0.72),
                in: RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
    }

    private var weekStep: some View {
        VStack(
            alignment: .leading,
            spacing: 16
        ) {
            stepIntro(
                eyebrow:
                    ATHLTHLocalization.choose(
                        english: "03 · TRAINING WEEK",
                        norwegian: "03 · TRENINGSUKEN"
                    ),
                title:
                    ATHLTHLocalization.choose(
                        english: "Choose when you train",
                        norwegian: "Velg når du vil trene"
                    ),
                subtitle:
                    mode == .basic
                    ? ATHLTHLocalization.choose(
                        english:
                            "Pick the number of sessions. ATHLTH spreads them across the week and keeps the other days as rest.",
                        norwegian:
                            "Velg antall økter. ATHLTH fordeler dem gjennom uken og lar resten være hviledager."
                    )
                    : ATHLTHLocalization.choose(
                        english:
                            "Choose the exact training days and define the practical limits around the week.",
                        norwegian:
                            "Velg eksakte treningsdager og legg inn rammene rundt treningsuken."
                    ),
                icon:
                    "calendar.day.timeline.left"
            )

            builderPanel {
                VStack(
                    alignment: .leading,
                    spacing: 14
                ) {
                    HStack {
                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            fieldLabel(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Sessions per week",
                                    norwegian:
                                        "Økter per uke"
                                )
                            )

                            Text(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Rest days stay visible in the plan.",
                                    norwegian:
                                        "Hviledager vises tydelig i planen."
                                )
                            )
                            .font(.caption2)
                            .foregroundStyle(
                                ATHLTHTheme.mutedText
                            )
                        }

                        Spacer()

                        HStack(spacing: 8) {
                            Button {
                                sessionsPerWeek =
                                    max(
                                        sessionsPerWeek - 1,
                                        1
                                    )
                            } label: {
                                Image(
                                    systemName:
                                        "minus"
                                )
                                .font(.caption.bold())
                                .frame(
                                    width: 34,
                                    height: 34
                                )
                                .background(
                                    ATHLTHTheme.accentSoft,
                                    in: Circle()
                                )
                            }
                            .buttonStyle(.plain)

                            Text(
                                "\(sessionsPerWeek)"
                            )
                            .font(
                                .system(
                                    size: 22,
                                    weight: .bold,
                                    design: .rounded
                                )
                            )
                            .frame(width: 30)

                            Button {
                                sessionsPerWeek =
                                    min(
                                        sessionsPerWeek + 1,
                                        7
                                    )
                            } label: {
                                Image(
                                    systemName:
                                        "plus"
                                )
                                .font(.caption.bold())
                                .frame(
                                    width: 34,
                                    height: 34
                                )
                                .background(
                                    ATHLTHTheme.accentDeep,
                                    in: Circle()
                                )
                                .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Divider()

                    fieldLabel(
                        ATHLTHLocalization.choose(
                            english: "Training days",
                            norwegian: "Treningsdager"
                        )
                    )

                    dayPicker

                    HStack(spacing: 8) {
                        Image(
                            systemName:
                                "moon.stars.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme.recoveryBlue
                        )

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "\(7 - selectedDays.count) rest day\(7 - selectedDays.count == 1 ? "" : "s") in the week",
                                norwegian:
                                    "\(7 - selectedDays.count) hviledag\(7 - selectedDays.count == 1 ? "" : "er") i uken"
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                    }
                }
            }

            builderPanel {
                VStack(
                    alignment: .leading,
                    spacing: 11
                ) {
                    fieldLabel(
                        ATHLTHLocalization.choose(
                            english: "Week setup",
                            norwegian: "Ukeoppsett"
                        )
                    )

                    weeklyPreview

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Tap a workout type to change it. This is only the starting structure and every session remains editable.",
                            norwegian:
                                "Trykk på økttypen for å endre den. Dette er bare startstrukturen, og alle økter kan redigeres senere."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }
            }

            if mode == .advanced {
                builderPanel {
                    VStack(spacing: 13) {
                        HStack {
                            VStack(
                                alignment: .leading,
                                spacing: 2
                            ) {
                                Text(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Training environment",
                                        norwegian:
                                            "Hvor trener du?"
                                    )
                                )
                                .font(.subheadline.weight(.semibold))

                                Text(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Used for exercise choices later",
                                        norwegian:
                                            "Brukes til øvelsesvalg senere"
                                    )
                                )
                                .font(.caption2)
                                .foregroundStyle(
                                    ATHLTHTheme.mutedText
                                )
                            }

                            Spacer()
                        }

                        HStack(spacing: 7) {
                            ForEach(
                                EquipmentContext.allCases
                            ) { item in
                                Button {
                                    equipment = item
                                } label: {
                                    VStack(spacing: 5) {
                                        Image(
                                            systemName:
                                                item.icon
                                        )
                                        .font(.system(size: 14, weight: .semibold))

                                        Text(item.title)
                                            .font(.system(size: 9.5, weight: .semibold))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.75)
                                    }
                                    .foregroundStyle(
                                        equipment == item
                                            ? Color.white
                                            : ATHLTHTheme.primaryText
                                    )
                                    .frame(
                                        maxWidth: .infinity,
                                        minHeight: 54
                                    )
                                    .background(
                                        equipment == item
                                            ? ATHLTHTheme.accentDeep
                                            : ATHLTHTheme.accentSoft,
                                        in:
                                            RoundedRectangle(
                                                cornerRadius: 13,
                                                style: .continuous
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Divider()

                        Stepper(
                            value:
                                $weeklyTimeBudgetMinutes,
                            in: 60...1_200,
                            step: 30
                        ) {
                            VStack(
                                alignment: .leading,
                                spacing: 2
                            ) {
                                Text(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Weekly time budget",
                                        norwegian:
                                            "Tidsbudsjett per uke"
                                    )
                                )
                                .font(.subheadline.weight(.semibold))

                                Text(
                                    durationText(
                                        weeklyTimeBudgetMinutes
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    ATHLTHTheme.mutedText
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private var dayPicker: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) {
                dayIndex in
                let selected =
                    selectedDays
                        .contains(dayIndex)

                Button {
                    toggleDay(dayIndex)
                } label: {
                    VStack(spacing: 5) {
                        Text(
                            shortDayName(
                                dayIndex
                            )
                        )
                        .font(.system(size: 9, weight: .bold))

                        Image(
                            systemName:
                                selected
                                    ? "checkmark"
                                    : "moon.fill"
                        )
                        .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(
                        selected
                            ? Color.white
                            : ATHLTHTheme.mutedText
                    )
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 50
                    )
                    .background(
                        selected
                            ? ATHLTHTheme.accentDeep
                            : ATHLTHTheme.recoveryBlueSoft,
                        in: RoundedRectangle(
                            cornerRadius: 13,
                            style: .continuous
                        )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var weeklyPreview: some View {
        VStack(spacing: 7) {
            if !workoutKindOverridesByDay.isEmpty {
                HStack {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "Customised week",
                            norwegian: "Tilpasset uke"
                        )
                    )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )

                    Spacer()

                    Button {
                        withAnimation(
                            .easeOut(duration: 0.16)
                        ) {
                            workoutKindOverridesByDay
                                .removeAll()
                        }
                    } label: {
                        Text(
                            ATHLTHLocalization.choose(
                                english: "Use suggestions",
                                norwegian: "Bruk forslag"
                            )
                        )
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(
                            ATHLTHTheme.accentDeep
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 2)
            }

            ForEach(1...7, id: \.self) {
                dayIndex in
                let isTraining =
                    selectedDays.contains(
                        dayIndex
                    )
                let kind =
                    isTraining
                        ? resolvedWorkoutKind(
                            for: dayIndex
                        )
                        : nil

                HStack(spacing: 10) {
                    Text(
                        fullDayName(dayIndex)
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .frame(
                        width: 73,
                        alignment: .leading
                    )

                    if let kind,
                       isTraining {
                        Image(
                            systemName:
                                kind.systemImage
                        )
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(
                            ATHLTHTheme.accentDeep
                        )
                        .frame(width: 30, height: 30)
                        .background(
                            ATHLTHTheme.accentSoft,
                            in: RoundedRectangle(
                                cornerRadius: 9,
                                style: .continuous
                            )
                        )

                        Menu {
                            ForEach(
                                selectableWorkoutKinds,
                                id: \.self
                            ) { option in
                                Button {
                                    workoutKindOverridesByDay[
                                        dayIndex
                                    ] = option
                                } label: {
                                    Label(
                                        option.title,
                                        systemImage:
                                            option.systemImage
                                    )
                                }
                            }

                            if workoutKindOverridesByDay[
                                dayIndex
                            ] != nil {
                                Divider()

                                Button {
                                    workoutKindOverridesByDay[
                                        dayIndex
                                    ] = nil
                                } label: {
                                    Label(
                                        ATHLTHLocalization.choose(
                                            english:
                                                "Use suggested type",
                                            norwegian:
                                                "Bruk foreslått type"
                                        ),
                                        systemImage:
                                            "arrow.uturn.backward"
                                    )
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                VStack(
                                    alignment: .leading,
                                    spacing: 2
                                ) {
                                    Text(
                                        suggestedWorkoutTitle(
                                            kind: kind,
                                            slot:
                                                trainingSlot(
                                                    for: dayIndex
                                                )
                                        )
                                    )
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(
                                        ATHLTHTheme.primaryText
                                    )
                                    .lineLimit(1)

                                    HStack(spacing: 4) {
                                        Text(kind.title)
                                            .font(.caption2)
                                            .foregroundStyle(
                                                ATHLTHTheme.mutedText
                                            )

                                        if workoutKindOverridesByDay[
                                            dayIndex
                                        ] != nil {
                                            Text("·")
                                                .foregroundStyle(
                                                    ATHLTHTheme.mutedText
                                                )

                                            Text(
                                                ATHLTHLocalization.choose(
                                                    english: "Changed",
                                                    norwegian: "Endret"
                                                )
                                            )
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(
                                                ATHLTHTheme.premiumGold
                                            )
                                        }
                                    }
                                }

                                Spacer(minLength: 4)

                                Image(
                                    systemName:
                                        "chevron.up.chevron.down"
                                )
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(
                                    ATHLTHTheme.mutedText
                                )
                            }
                            .contentShape(Rectangle())
                        }

                        Text(
                            ATHLTHLocalization.choose(
                                english: "Planned",
                                norwegian: "Planlagt"
                            )
                        )
                        .font(.caption2)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                    } else {
                        Image(
                            systemName:
                                "moon.stars.fill"
                        )
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(
                            ATHLTHTheme.recoveryBlue
                        )
                        .frame(width: 30, height: 30)
                        .background(
                            ATHLTHTheme.recoveryBlueSoft,
                            in: RoundedRectangle(
                                cornerRadius: 9,
                                style: .continuous
                            )
                        )

                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Text(
                                ATHLTHLocalization.choose(
                                    english: "Rest day",
                                    norwegian: "Hviledag"
                                )
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(
                                ATHLTHTheme.mutedText
                            )

                            Text(
                                ATHLTHLocalization.choose(
                                    english:
                                        "No workout planned",
                                    norwegian:
                                        "Ingen økt planlagt"
                                )
                            )
                            .font(.caption2)
                            .foregroundStyle(
                                ATHLTHTheme.mutedText
                                    .opacity(0.78)
                            )
                        }

                        Spacer()
                    }
                }
                .padding(.horizontal, 10)
                .frame(minHeight: 52)
                .background(
                    Color.white.opacity(0.56),
                    in: RoundedRectangle(
                        cornerRadius: 13,
                        style: .continuous
                    )
                )
            }
        }
    }

    private var selectableWorkoutKinds:
        [WorkoutKind] {
        if mode == .basic {
            return [
                .strength,
                .running,
                .walking,
                .mobility
            ]
        }

        return [
            .strength,
            .running,
            .walking,
            .mobility,
            .recovery,
            .custom
        ]
    }

    private func trainingSlot(
        for dayIndex: Int
    ) -> Int {
        selectedDays
            .sorted()
            .firstIndex(
                of: dayIndex
            ) ?? 0
    }

    private func resolvedWorkoutKind(
        for dayIndex: Int
    ) -> WorkoutKind {
        if let override =
            workoutKindOverridesByDay[
                dayIndex
            ] {
            return override
        }

        return suggestedKind(
            slot:
                trainingSlot(
                    for: dayIndex
                )
        )
    }

    private var reviewStep: some View {
        VStack(
            alignment: .leading,
            spacing: 16
        ) {
            stepIntro(
                eyebrow:
                    ATHLTHLocalization.choose(
                        english: "04 · REVIEW",
                        norwegian: "04 · OPPSUMMERING"
                    ),
                title:
                    ATHLTHLocalization.choose(
                        english: "Ready to build",
                        norwegian: "Klar til å bygge"
                    ),
                subtitle:
                    ATHLTHLocalization.choose(
                        english:
                            "Check the foundation. You can edit every detail after the plan is created.",
                        norwegian:
                            "Sjekk grunnlaget. Alle detaljer kan redigeres etter at planen er opprettet."
                    ),
                icon: "checkmark.seal.fill"
            )

            builderPanel {
                VStack(spacing: 0) {
                    reviewRow(
                        icon: "textformat",
                        title:
                            ATHLTHLocalization.choose(
                                english: "Plan",
                                norwegian: "Plan"
                            ),
                        value:
                            title.isEmpty
                            ? "—"
                            : title
                    )

                    reviewDivider

                    reviewRow(
                        icon: "calendar",
                        title:
                            ATHLTHLocalization.choose(
                                english: "Period",
                                norwegian: "Periode"
                            ),
                        value:
                            ATHLTHLocalization.choose(
                                english:
                                    "\(weekCount) weeks · \(startDate.formatted(date: .abbreviated, time: .omitted))",
                                norwegian:
                                    "\(weekCount) uker · \(startDate.formatted(date: .abbreviated, time: .omitted))"
                            )
                    )

                    reviewDivider

                    reviewRow(
                        icon:
                            focus.systemImage,
                        title:
                            ATHLTHLocalization.choose(
                                english: "Focus",
                                norwegian: "Fokus"
                            ),
                        value:
                            focusSummary
                    )

                    reviewDivider

                    reviewRow(
                        icon: "scope",
                        title:
                            ATHLTHLocalization.choose(
                                english: "Goal",
                                norwegian: "Mål"
                            ),
                        value: goal.title
                    )

                    reviewDivider

                    reviewRow(
                        icon:
                            "calendar.day.timeline.left",
                        title:
                            ATHLTHLocalization.choose(
                                english: "Week",
                                norwegian: "Uke"
                            ),
                        value:
                            trainingWeekSummary
                    )

                    reviewDivider

                    reviewRow(
                        icon:
                            injuryFree
                                ? "checkmark.shield.fill"
                                : "cross.case.fill",
                        title:
                            ATHLTHLocalization.choose(
                                english: "Limitations",
                                norwegian: "Hensyn"
                            ),
                        value:
                            injuryFree
                                ? ATHLTHLocalization.choose(
                                    english:
                                        "No known issues",
                                    norwegian:
                                        "Ingen kjente"
                                )
                                : injuriesOrLimitations
                                    .trimmingCharacters(
                                        in:
                                            .whitespacesAndNewlines
                                    )
                                    .isEmpty
                                    ? ATHLTHLocalization.choose(
                                        english:
                                            "Marked for consideration",
                                        norwegian:
                                            "Markert for hensyn"
                                    )
                                    : injuriesOrLimitations
                    )

                    if !selectedMuscles.isEmpty {
                        reviewDivider

                        reviewRow(
                            icon:
                                "figure.strengthtraining.traditional",
                            title:
                                ATHLTHLocalization.choose(
                                    english:
                                        "Muscle priority",
                                    norwegian:
                                        "Muskelprioritet"
                                ),
                            value:
                                selectedMuscleTitles
                        )
                    }
                }
            }

            if !goalStore.goals.isEmpty {
                builderPanel {
                    VStack(
                        alignment: .leading,
                        spacing: 9
                    ) {
                        fieldLabel(
                            ATHLTHLocalization.choose(
                                english:
                                    "Connect to goals in Progress",
                                norwegian:
                                    "Koble til mål i Progress"
                            )
                        )

                        ForEach(
                            goalStore.goals.prefix(5)
                        ) { appGoal in
                            Toggle(
                                isOn:
                                    Binding(
                                        get: {
                                            selectedGoalIDs
                                                .contains(
                                                    appGoal.id
                                                )
                                        },
                                        set: {
                                            enabled in
                                            if enabled {
                                                selectedGoalIDs
                                                    .insert(
                                                        appGoal.id
                                                    )
                                            } else {
                                                selectedGoalIDs
                                                    .remove(
                                                        appGoal.id
                                                    )
                                            }
                                        }
                                    )
                            ) {
                                Text(appGoal.title)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
            }

            if let conflict = conflictingPlan {
                conflictCard(conflict)
            }

            VStack(
                alignment: .leading,
                spacing: 10
            ) {
                Text(
                    ATHLTHLocalization.choose(
                        english: "HOW TO START THE WEEK",
                        norwegian: "HVORDAN VIL DU STARTE?"
                    )
                )
                .font(.caption2.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )

                Button {
                    showingAIBuilder = true
                } label: {
                    creationChoiceCard(
                        title:
                            ATHLTHLocalization.choose(
                                english:
                                    "Get an AI proposal",
                                norwegian:
                                    "Få forslag fra AI"
                            ),
                        subtitle:
                            ATHLTHLocalization.choose(
                                english:
                                    "ATHLTH Coach starts with your focus, goal, training days, limitations and available time.",
                                norwegian:
                                    "ATHLTH Coach starter med fokus, mål, treningsdager, hensyn og tiden du har tilgjengelig."
                            ),
                        icon: "sparkles",
                        prominent: true
                    )
                }
                .buttonStyle(.plain)
                .disabled(
                    !canCreatePlan
                )
                .opacity(
                    canCreatePlan ? 1 : 0.42
                )

                Button {
                    createPlan(
                        seedSuggestedWeek: true
                    )
                } label: {
                    creationChoiceCard(
                        title:
                            ATHLTHLocalization.choose(
                                english:
                                    "Use a simple starting structure",
                                norwegian:
                                    "Bruk enkel startstruktur"
                            ),
                        subtitle:
                            ATHLTHLocalization.choose(
                                english:
                                    "Create the chosen training days immediately, without AI, and edit every workout yourself.",
                                norwegian:
                                    "Opprett de valgte treningsdagene med en gang, uten AI, og rediger øktene selv."
                            ),
                        icon:
                            "calendar.day.timeline.left",
                        prominent: false
                    )
                }
                .buttonStyle(.plain)
                .disabled(
                    !canCreatePlan
                )
                .opacity(
                    canCreatePlan ? 1 : 0.42
                )

                Button {
                    createPlan(
                        seedSuggestedWeek: false
                    )
                } label: {
                    creationChoiceCard(
                        title:
                            ATHLTHLocalization.choose(
                                english:
                                    "Start with empty weeks",
                                norwegian:
                                    "Start med tomme uker"
                            ),
                        subtitle:
                            ATHLTHLocalization.choose(
                                english:
                                    "Keep the dates and profile, but add every workout yourself.",
                                norwegian:
                                    "Behold datoer og profil, men legg inn alle økter selv."
                            ),
                        icon:
                            "calendar.badge.plus",
                        prominent: false
                    )
                }
                .buttonStyle(.plain)
                .disabled(
                    !canCreatePlan
                )
                .opacity(
                    canCreatePlan ? 1 : 0.42
                )
            }
        }
    }

    private func reviewRow(
        icon: String,
        title: String,
        value: String
    ) -> some View {
        HStack(
            alignment: .top,
            spacing: 11
        ) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )
                .frame(width: 30, height: 30)
                .background(
                    ATHLTHTheme.accentSoft,
                    in: RoundedRectangle(
                        cornerRadius: 9,
                        style: .continuous
                    )
                )

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )

                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }

    private var reviewDivider: some View {
        Divider()
            .padding(.leading, 41)
    }

    private func creationChoiceCard(
        title: String,
        subtitle: String,
        icon: String,
        prominent: Bool
    ) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(
                    prominent
                        ? ATHLTHTheme.accentDeep
                        : ATHLTHTheme.premiumGold
                )
                .frame(width: 43, height: 43)
                .background(
                    prominent
                        ? Color.white.opacity(0.92)
                        : ATHLTHTheme.premiumGoldSoft,
                    in: RoundedRectangle(
                        cornerRadius: 13,
                        style: .continuous
                    )
                )

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(title)
                    .font(.subheadline.weight(.bold))

                Text(subtitle)
                    .font(.caption)
                    .opacity(0.74)
                    .multilineTextAlignment(.leading)
            }

            Spacer()

            Image(systemName: "arrow.right")
                .font(.caption.bold())
        }
        .foregroundStyle(
            prominent
                ? Color.white
                : ATHLTHTheme.primaryText
        )
        .padding(14)
        .frame(
            maxWidth: .infinity,
            minHeight: 72
        )
        .background(
            prominent
                ? AnyShapeStyle(
                    LinearGradient(
                        colors: [
                            ATHLTHTheme.accentDeep,
                            ATHLTHTheme.accent
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                : AnyShapeStyle(
                    Color.white.opacity(0.72)
                ),
            in: RoundedRectangle(
                cornerRadius: 19,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 19,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(
                    prominent ? 0.12 : 0.90
                ),
                lineWidth: 0.8
            )
        }
    }

    private func stepIntro(
        eyebrow: String,
        title: String,
        subtitle: String,
        icon: String
    ) -> some View {
        HStack(
            alignment: .top,
            spacing: 14
        ) {
            Image(systemName: icon)
                .font(
                    .system(
                        size: 20,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )
                .frame(width: 50, height: 50)
                .background(
                    LinearGradient(
                        colors: [
                            ATHLTHTheme.champagneSoft,
                            ATHLTHTheme.accentSoft
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(
                        cornerRadius: 16,
                        style: .continuous
                    )
                )

            VStack(
                alignment: .leading,
                spacing: 5
            ) {
                Text(eyebrow)
                    .font(.system(size: 8.5, weight: .bold))
                    .tracking(1.45)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )

                Text(title)
                    .font(
                        .system(
                            size: 24,
                            weight: .bold,
                            design: .serif
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                    .lineSpacing(2)
            }

            Spacer(minLength: 0)
        }
        .padding(17)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.94),
                    ATHLTHTheme.cardWarm
                        .opacity(0.44)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.92),
                lineWidth: 0.8
            )
        }
    }

    private func builderPanel<Content: View>(
        @ViewBuilder content:
            () -> Content
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 0
        ) {
            content()
        }
        .padding(16)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.92),
                    ATHLTHTheme.cardWarm
                        .opacity(0.28)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.92),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                ATHLTHTheme.accentDeep
                    .opacity(0.04),
            radius: 10,
            y: 5
        )
    }

    private func fieldLabel(
        _ title: String
    ) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(
                ATHLTHTheme.primaryText
            )
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
    }

    private var bottomActionBar: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.35)

            HStack(spacing: 10) {
                if step != .basics {
                    Button {
                        goBack()
                    } label: {
                        Image(
                            systemName:
                                "chevron.left"
                        )
                        .font(.subheadline.bold())
                        .foregroundStyle(
                            ATHLTHTheme.accentDeep
                        )
                        .frame(width: 48, height: 48)
                        .background(
                            ATHLTHTheme.accentSoft,
                            in: RoundedRectangle(
                                cornerRadius: 15,
                                style: .continuous
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }

                if step != .review {
                    Button {
                        goForward()
                    } label: {
                        HStack {
                            Text(
                                ATHLTHLocalization.choose(
                                    english: "Next",
                                    norwegian: "Neste"
                                )
                            )
                            .font(.subheadline.weight(.bold))

                            Spacer()

                            Image(
                                systemName:
                                    "arrow.right"
                            )
                            .font(.subheadline.bold())
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(
                            maxWidth: .infinity
                        )
                        .frame(height: 48)
                        .background(
                            ATHLTHTheme.accentDeep,
                            in: RoundedRectangle(
                                cornerRadius: 15,
                                style: .continuous
                            )
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canContinue)
                    .opacity(
                        canContinue ? 1 : 0.38
                    )
                } else {
                    HStack(spacing: 8) {
                        Image(
                            systemName:
                                "checkmark.circle.fill"
                        )
                        .foregroundStyle(
                            ATHLTHTheme.vitality
                        )

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Choose how to start the plan above",
                                norwegian:
                                    "Velg hvordan planen skal starte over"
                            )
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )

                        Spacer()
                    }
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 48
                    )
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(
                .ultraThinMaterial
            )
        }
    }

    private var backButtonTitle: String {
        if step == .basics {
            return ATHLTHLocalization.choose(
                english: "Cancel",
                norwegian: "Avbryt"
            )
        }

        return ATHLTHLocalization.choose(
            english: "Back",
            norwegian: "Tilbake"
        )
    }

    private var canContinue: Bool {
        switch step {
        case .source:
            return true
        case .basics:
            return
                !title
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .isEmpty &&
                conflictingPlan == nil
        case .profile:
            return
                injuryFree ||
                !injuriesOrLimitations
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .isEmpty
        case .week:
            return !selectedDays.isEmpty
        case .review:
            return false
        }
    }

    private var canCreatePlan: Bool {
        !title
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .isEmpty &&
        !selectedDays.isEmpty &&
        conflictingPlan == nil &&
        (
            injuryFree ||
            !injuriesOrLimitations
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .isEmpty
        )
    }

    private var resolvedEndDate: Date {
        Calendar.current.date(
            byAdding: .day,
            value:
                max(
                    weekCount * 7 - 1,
                    0
                ),
            to:
                Calendar.current
                    .startOfDay(
                        for: startDate
                    )
        ) ?? startDate
    }

    private var conflictingPlan: TrainingPlan? {
        session.trainingPlanConflict(
            startDate: startDate,
            endDate: resolvedEndDate
        )
    }

    private var focusSummary: String {
        guard
            mode == .advanced,
            let secondaryFocus
        else {
            return focus.title
        }

        return
            "\(focusWeight)% \(focus.title) · " +
            "\(100 - focusWeight)% \(secondaryFocus.title)"
    }

    private var orderedPriorityMuscles: [String] {
        let others = selectedMuscles.sorted()
        guard let primaryMuscle,
              selectedMuscles.contains(primaryMuscle)
        else {
            return others
        }
        return [primaryMuscle] + others.filter { $0 != primaryMuscle }
    }

    private var selectedMuscleTitles: String {
        orderedPriorityMuscles.compactMap { id in
            Self.muscleOptions.first { $0.id == id }?.title
        }
        .joined(separator: ", ")
    }

    private func goForward() {
        withAnimation(
            .easeInOut(duration: 0.18)
        ) {
            switch step {
            case .source:
                step = .profile
            case .basics:
                step = startsAtSourceChoice ? .source : .profile
            case .profile:
                step = .week
            case .week:
                step = .review
            case .review:
                break
            }
        }
    }

    private func goBack() {
        withAnimation(
            .easeInOut(duration: 0.18)
        ) {
            switch step {
            case .source:
                step = .basics

            case .basics:
                dismiss()

            case .profile:
                step = startsAtSourceChoice ? .source : .basics

            case .week:
                step = .profile

            case .review:
                step = .week
            }
        }
    }

    private func toggleDay(
        _ dayIndex: Int
    ) {
        if selectedDays.contains(dayIndex) {
            guard selectedDays.count > 1
            else {
                return
            }

            selectedDays.remove(dayIndex)
        } else {
            selectedDays.insert(dayIndex)
        }

        sessionsPerWeek =
            selectedDays.count
    }

    private func balancedDays(
        count: Int
    ) -> Set<Int> {
        switch count {
        case 1:
            return [3]
        case 2:
            return [2, 5]
        case 3:
            return [1, 3, 5]
        case 4:
            return [1, 2, 4, 6]
        case 5:
            return [1, 2, 3, 5, 6]
        case 6:
            return [1, 2, 3, 4, 5, 6]
        default:
            return [1, 2, 3, 4, 5, 6, 7]
        }
    }

    private func suggestedKind(
        slot: Int
    ) -> WorkoutKind {
        let pattern =
            focus.suggestedWorkoutPattern

        guard !pattern.isEmpty else {
            return .custom
        }

        return pattern[
            slot % pattern.count
        ]
    }

    private func suggestedWorkoutTitle(
        kind: WorkoutKind,
        slot: Int
    ) -> String {
        switch kind {
        case .strength:
            if focus == .hypertrophy {
                let titles = [
                    ATHLTHLocalization.choose(
                        english: "Upper body",
                        norwegian: "Overkropp"
                    ),
                    ATHLTHLocalization.choose(
                        english: "Lower body",
                        norwegian: "Underkropp"
                    ),
                    ATHLTHLocalization.choose(
                        english: "Full body",
                        norwegian: "Helkropp"
                    )
                ]
                return titles[
                    slot % titles.count
                ]
            }

            return ATHLTHLocalization.choose(
                english: "Strength",
                norwegian: "Styrke"
            )

        case .running:
            let titles = [
                ATHLTHLocalization.choose(
                    english: "Easy run",
                    norwegian: "Rolig løp"
                ),
                ATHLTHLocalization.choose(
                    english: "Intervals",
                    norwegian: "Intervaller"
                ),
                ATHLTHLocalization.choose(
                    english: "Long run",
                    norwegian: "Langtur"
                )
            ]
            return titles[
                slot % titles.count
            ]

        case .walking:
            return ATHLTHLocalization.choose(
                english: "Walk",
                norwegian: "Gåtur"
            )

        case .mobility:
            return ATHLTHLocalization.choose(
                english: "Mobility",
                norwegian: "Mobilitet"
            )

        case .recovery:
            return ATHLTHLocalization.choose(
                english: "Recovery",
                norwegian: "Restitusjon"
            )

        case .custom:
            return ATHLTHLocalization.choose(
                english: "Workout",
                norwegian: "Økt"
            )
        }
    }

    private func shortDayName(
        _ dayIndex: Int
    ) -> String {
        let norwegian = [
            "M", "T", "O", "T", "F", "L", "S"
        ]
        let english = [
            "M", "T", "W", "T", "F", "S", "S"
        ]
        let index =
            min(
                max(dayIndex - 1, 0),
                6
            )

        return ATHLTHLocalization.choose(
            english: english[index],
            norwegian: norwegian[index]
        )
    }

    private func fullDayName(
        _ dayIndex: Int
    ) -> String {
        let norwegian = [
            "Mandag",
            "Tirsdag",
            "Onsdag",
            "Torsdag",
            "Fredag",
            "Lørdag",
            "Søndag"
        ]
        let english = [
            "Monday",
            "Tuesday",
            "Wednesday",
            "Thursday",
            "Friday",
            "Saturday",
            "Sunday"
        ]
        let index =
            min(
                max(dayIndex - 1, 0),
                6
            )

        return ATHLTHLocalization.choose(
            english: english[index],
            norwegian: norwegian[index]
        )
    }

    private var trainingWeekSummary:
        String {
        selectedDays
            .sorted()
            .map { dayIndex in
                let kind =
                    resolvedWorkoutKind(
                        for: dayIndex
                    )

                return
                    "\(fullDayName(dayIndex)): \(kind.title)"
            }
            .joined(separator: " · ")
    }

    private func durationText(
        _ minutes: Int
    ) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60

        if hours == 0 {
            return "\(minutes) min"
        }

        if remainder == 0 {
            return ATHLTHLocalization.choose(
                english:
                    "\(hours) h",
                norwegian:
                    "\(hours) t"
            )
        }

        return ATHLTHLocalization.choose(
            english:
                "\(hours) h \(remainder) min",
            norwegian:
                "\(hours) t \(remainder) min"
        )
    }

    private func conflictCard(
        _ conflict: TrainingPlan
    ) -> some View {
        HStack(
            alignment: .top,
            spacing: 11
        ) {
            Image(
                systemName:
                    "calendar.badge.exclamationmark"
            )
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(
                ATHLTHTheme.premiumGold
            )
            .frame(width: 38, height: 38)
            .background(
                ATHLTHTheme.premiumGoldSoft,
                in: RoundedRectangle(
                    cornerRadius: 11,
                    style: .continuous
                )
            )

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Overlaps with \(conflict.title)",
                        norwegian:
                            "Overlapper med \(conflict.title)"
                    )
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Move the start date or change the duration before creating the plan.",
                        norwegian:
                            "Flytt startdatoen eller endre varigheten før planen opprettes."
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            }

            Spacer()
        }
        .padding(14)
        .background(
            ATHLTHTheme.premiumGoldSoft
                .opacity(0.54),
            in: RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
    }

    private var aiBuilderSeed:
        AIProgramBuilderSeed {
        let cleanLimitations =
            injuryFree
                ? ""
                : injuriesOrLimitations
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
        let detail =
            goalDetail
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        var focusNotes: [String] = [
            ATHLTHLocalization.choose(
                english:
                    "Primary goal: \(goal.title).",
                norwegian:
                    "Hovedmål: \(goal.title)."
            )
        ]

        if !detail.isEmpty {
            focusNotes.append(
                ATHLTHLocalization.choose(
                    english:
                        "Concrete target: \(detail).",
                    norwegian:
                        "Konkret mål: \(detail)."
                )
            )
        }

        if !selectedMuscles.isEmpty {
            focusNotes.append(
                ATHLTHLocalization.choose(
                    english:
                        "Prioritise these muscle groups: \(selectedMuscleTitles).",
                    norwegian:
                        "Prioriter disse muskelgruppene: \(selectedMuscleTitles)."
                )
            )
        }

        focusNotes.append(
            ATHLTHLocalization.choose(
                english:
                    "Preferred week: \(trainingWeekSummary).",
                norwegian:
                    "Ønsket treningsuke: \(trainingWeekSummary)."
            )
        )

        if mode == .advanced,
           let secondaryFocus {
            focusNotes.append(
                ATHLTHLocalization.choose(
                    english:
                        "Focus split: \(focusWeight)% \(focus.title), \(100 - focusWeight)% \(secondaryFocus.title).",
                    norwegian:
                        "Fokusfordeling: \(focusWeight)% \(focus.title), \(100 - focusWeight)% \(secondaryFocus.title)."
                )
            )
        }

        if hasCompetitionDate &&
            mode == .advanced {
            focusNotes.append(
                ATHLTHLocalization.choose(
                    english:
                        "Target date: \(competitionDate.formatted(date: .abbreviated, time: .omitted)).",
                    norwegian:
                        "Måldato: \(competitionDate.formatted(date: .abbreviated, time: .omitted))."
                )
            )
        }

        let sessionMinutes: Int
        if mode == .advanced {
            sessionMinutes =
                max(
                    weeklyTimeBudgetMinutes /
                    max(selectedDays.count, 1),
                    20
                )
        } else {
            sessionMinutes = 60
        }

        let seededGymAccess: String?
        if mode == .advanced {
            switch equipment {
            case .gym, .both:
                seededGymAccess = "Yes"
            case .home:
                seededGymAccess = "No"
            }
        } else {
            seededGymAccess = nil
        }

        return AIProgramBuilderSeed(
            preferredTitle:
                title.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
            startDate: startDate,
            weekCount: weekCount,
            sessionsPerWeek:
                selectedDays.count,
            sessionDurationMinutes:
                min(sessionMinutes, 180),
            availableDays:
                selectedDays,
            trainingFocus:
                aiTrainingFocus,
            gymAccess:
                seededGymAccess,
            limitations:
                cleanLimitations,
            coachFocusNotes:
                focusNotes.joined(
                    separator: " "
                ),
            selectedGoalIDs:
                selectedGoalIDs
        )
    }

    private var aiTrainingFocus:
        TrainingFocus {
        switch focus {
        case .generalFitness:
            return .generalFitness
        case .strength,
             .hypertrophy:
            return .strength
        case .running,
             .endurance:
            return .running
        case .hybrid:
            return .hybrid
        case .mobilityRehab:
            return .recovery
        }
    }

    private func createPlan(
        seedSuggestedWeek: Bool
    ) {
        guard canCreatePlan else {
            return
        }

        let cleanLimitations =
            injuriesOrLimitations
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
        let cleanGoalDetail =
            goalDetail
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        let profile =
            TrainingPlanBuilderProfile(
                mode: mode,
                primaryFocus: focus,
                secondaryFocus: secondaryFocus,
                primaryFocusWeightPercent:
                    secondaryFocus != nil ? focusWeight : nil,
                goal: goal,
                goalDetail:
                    cleanGoalDetail.isEmpty
                        ? nil
                        : cleanGoalDetail,
                competitionDate:
                    hasCompetitionDate ? competitionDate : nil,
                sessionsPerWeek:
                    selectedDays.count,
                preferredDayIndexes:
                    selectedDays.sorted(),
                injuriesOrLimitations:
                    injuryFree ||
                    cleanLimitations.isEmpty
                        ? nil
                        : cleanLimitations,
                priorityMuscles:
                    orderedPriorityMuscles,
                equipmentContext: equipment.rawValue,
                weeklyTimeBudgetMinutes:
                    weeklyTimeBudgetMinutes,
                preferredWorkoutKindsByDay:
                    Dictionary(
                        uniqueKeysWithValues:
                            selectedDays
                                .sorted()
                                .map {
                                    (
                                        $0,
                                        resolvedWorkoutKind(
                                            for: $0
                                        )
                                    )
                                }
                    )
            )

        let created =
            session
                .createConfiguredTrainingPlan(
                    title: title,
                    summary: planSummary,
                    weekCount: weekCount,
                    startDate: startDate,
                    endDate: resolvedEndDate,
                    visibility: visibility,
                    builderProfile: profile,
                    seedSuggestedWeek:
                        seedSuggestedWeek
                )

        guard let created else {
            if let conflict =
                conflictingPlan {
                creationError =
                    ATHLTHLocalization.choose(
                        english:
                            "This period overlaps with \(conflict.title). Adjust the dates and try again.",
                        norwegian:
                            "Perioden overlapper med \(conflict.title). Endre datoene og prøv igjen."
                    )
            } else {
                creationError =
                    ATHLTHLocalization.choose(
                        english:
                            "ATHLTH could not create the plan. Check the details and try again.",
                        norwegian:
                            "ATHLTH kunne ikke opprette planen. Kontroller oppsettet og prøv igjen."
                    )
            }
            return
        }

        if !selectedGoalIDs.isEmpty {
            goalStore.setLinkedPlan(
                created.id,
                goalIDs: selectedGoalIDs
            )
        }

        // Open the real day-by-day planner directly after saving so the
        // user can immediately add exercises, edit days and review the week.
        createdPlanID = created.id
        showingCreatedPlan = true
    }
}

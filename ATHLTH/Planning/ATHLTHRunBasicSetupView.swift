import SwiftUI

/// One compact Basic layout for Quick Train and scratch planning.
/// The presentation owns no workout data and starts no workout itself.
struct ATHLTHRunBasicSetupView: View {
    @Binding var workoutName: String
    @Binding var mode: RunQuickStartMode
    @Binding var environment: RunEnvironment
    @Binding var date: Date

    var scheduleEditable = false
    var selectedRouteTitle: String? = nil
    var selectedWorkoutTitle: String? = nil
    var onChooseRoute: (() -> Void)? = nil
    var onChooseWorkout: (() -> Void)? = nil
    var onChooseGoal: (() -> Void)? = nil
    var onChooseGhost: (() -> Void)? = nil
    var onChooseStandardMode: (() -> Void)? = nil
    var isGoalSelected = false
    var isGhostSelected = false
    /// Basic offers one simple coach toggle; Advanced owns the full rules.
    var audioCoachEnabled: Binding<Bool>? = nil

    @State private var showsWorkoutDetails = false

    private let ink = ATHLTHTrainDesign.ink
    private let bronze = ATHLTHTrainDesign.bronze

    private var suggestedName: String {
        switch mode {
        case .free:
            return ATHLTHLocalization.choose(
                english: "Free run", norwegian: "Fri løping"
            )
        case .route:
            return selectedRouteTitle ?? ATHLTHLocalization.choose(
                english: "Route run", norwegian: "Løping med rute"
            )
        case .structured:
            return selectedWorkoutTitle ?? ATHLTHLocalization.choose(
                english: "Running workout", norwegian: "Løpeøkt"
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            sectionHeading(ATHLTHLocalization.choose(
                english: "Running", norwegian: "Løping"
            ))

            ATHLTHBasicActivityHero(
                title: ATHLTHLocalization.choose(
                    english: "Free running", norwegian: "Fri løping"
                ),
                subtitle: ATHLTHLocalization.choose(
                    english: "Start without a plan. Add goals and coaching if you want.",
                    norwegian: "Start uten plan. Legg til mål og veiledning hvis du ønsker."
                ),
                symbol: "figure.run",
                isSelected: mode == .free && !isGoalSelected && !isGhostSelected
            ) {
                onChooseStandardMode?()
                mode = .free
            }

            sectionHeading(ATHLTHLocalization.choose(
                english: "Other ways to run", norwegian: "Andre måter å løpe på"
            ))
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10),
                          GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                runTiles
            }

            DisclosureGroup(isExpanded: $showsWorkoutDetails) {
                detailsCard
                    .padding(.top, 10)
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(bronze)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ATHLTHLocalization.choose(
                            english: "Workout details", norwegian: "Øktdetaljer"
                        ))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ink)
                        Text(environment.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 44)
            }
            .tint(bronze)
            .padding(14)
            .athlthTrainPaper()
        }
        .onChange(of: environment) { _, value in
            if value != .outdoor && mode == .route {
                onChooseStandardMode?()
                mode = .free
            }
        }
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                Image(systemName: "figure.run")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(bronze)
                    .frame(width: 44, height: 44)
                    .background(ATHLTHTrainDesign.paleGold.opacity(0.45),
                                in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 2) {
                    Text(ATHLTHLocalization.choose(
                        english: "WORKOUT DETAILS", norwegian: "ØKTDETALJER"
                    ))
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(bronze)
                    Text(ATHLTHLocalization.choose(
                        english: "Running", norwegian: "Løping"
                    ))
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundStyle(ink)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                TextField(
                    "", text: $workoutName,
                    prompt: Text(suggestedName)
                        .foregroundStyle(.secondary.opacity(0.55))
                )
                .font(.subheadline.weight(.medium))
                .tint(bronze)
                .textInputAutocapitalization(.sentences)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Workout name (optional)", norwegian: "Navn på økt (valgfritt)"
                ))
                if !workoutName.isEmpty {
                    Button {
                        workoutName = ""
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "Clear name", norwegian: "Fjern navn"
                        ), systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                }
            }
            .frame(minHeight: 43)
            .padding(.horizontal, 13)
            .background(ATHLTHPlanDesign.canvas,
                        in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 8) {
                if scheduleEditable {
                    DatePicker(
                        ATHLTHLocalization.choose(english: "Date", norwegian: "Dato"),
                        selection: $date,
                        displayedComponents: .date
                    )
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    DatePicker(
                        ATHLTHLocalization.choose(english: "Time", norwegian: "Tid"),
                        selection: $date,
                        displayedComponents: .hourAndMinute
                    )
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                } else {
                    Label(date.formatted(date: .abbreviated, time: .omitted),
                          systemImage: "calendar")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Label(date.formatted(date: .omitted, time: .shortened),
                          systemImage: "clock")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(ink)
            .frame(minHeight: 42)
            .padding(.horizontal, scheduleEditable ? 0 : 12)
            .background(ATHLTHPlanDesign.canvas,
                        in: RoundedRectangle(cornerRadius: 12))

            ATHLTHRunEnvironmentDetailRow(environment: $environment)

            if let audioCoachEnabled {
                Toggle(isOn: audioCoachEnabled) {
                    Label("Audio Coach", systemImage: "waveform")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ink)
                }
                .tint(bronze)
                .frame(minHeight: 44)
                .accessibilityIdentifier("athlth-basic-audio-coach")
            }
        }
        .padding(15)
        .athlthTrainPaper()
    }

    private func sectionHeading(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 17, weight: .semibold, design: .serif))
            .foregroundStyle(ink)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var runTiles: some View {
        ForEach(RunQuickStartMode.allCases.filter { $0 != .free }) { option in
            ATHLTHBasicActivityModeTile(
                title: option.title,
                subtitle: option == .route
                    ? ATHLTHLocalization.choose(
                        english: "Map and guidance", norwegian: "Kart og navigasjon"
                    )
                    : ATHLTHLocalization.choose(
                        english: "Intervals and plans", norwegian: "Intervaller og økter"
                    ),
                symbol: option.icon,
                selected: mode == option && !isGoalSelected && !isGhostSelected
            ) {
                onChooseStandardMode?()
                if option == .route {
                    environment = .outdoor
                    onChooseRoute?()
                } else if option == .structured {
                    onChooseWorkout?()
                }
                mode = option
            }
        }
        if let onChooseGoal {
            ATHLTHBasicActivityModeTile(
                title: ATHLTHLocalization.choose(
                    english: "Goal-based", norwegian: "Målstyrt"
                ),
                subtitle: ATHLTHLocalization.choose(
                    english: "Time, pace or pulse", norwegian: "Tid, tempo eller puls"
                ),
                symbol: "target", selected: isGoalSelected,
                action: onChooseGoal
            )
        }
        if let onChooseGhost {
            ATHLTHBasicActivityModeTile(
                title: "Ghost Race",
                subtitle: ATHLTHLocalization.choose(
                    english: "Race your past self", norwegian: "Utfordre deg selv"
                ),
                symbol: "figure.run.circle", selected: isGhostSelected,
                action: onChooseGhost
            )
        }
    }

}

 
/// Compact run-environment choice for the Workout Details card.
/// Keeps the three existing recording environments rather than creating
/// a competing GPS/Watch workout mode.
struct ATHLTHRunEnvironmentDetailRow: View {
    @Binding var environment: RunEnvironment

    var body: some View {
        HStack(spacing: 10) {
            Label(
                ATHLTHLocalization.choose(
                    english: "Running environment", norwegian: "Løpemiljø"
                ),
                systemImage: "figure.run"
            )
            .font(.subheadline.weight(.medium))
            .foregroundStyle(ATHLTHTrainDesign.ink)

            Spacer(minLength: 8)

            Picker(
                ATHLTHLocalization.choose(
                    english: "Running environment", norwegian: "Løpemiljø"
                ),
                selection: $environment
            ) {
                ForEach(RunEnvironment.allCases) { option in
                    Label(option.title, systemImage: option.systemImage)
                        .tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(ATHLTHTrainDesign.bronze)
            .accessibilityIdentifier("athlth-run-environment-detail-picker")
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 12)
        .background(
            ATHLTHPlanDesign.canvas,
            in: RoundedRectangle(cornerRadius: 12)
        )
    }
}

/// Shared, activity-independent hierarchy for the second Quick Train screen.
/// Activity selection happens before this view. A prominent free session is
/// always followed by smaller alternative mode tiles; no business logic lives
/// inside these reusable presentation components.
struct ATHLTHBasicActivityHero: View {
    let title: String
    let subtitle: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: symbol)
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                        .frame(width: 52, height: 52)
                        .background(.white.opacity(0.85),
                                    in: RoundedRectangle(cornerRadius: 15))
                    Spacer(minLength: 0)
                    Image(systemName: isSelected
                          ? "checkmark.circle.fill" : "arrow.up.right")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 23, weight: .semibold, design: .serif))
                        .foregroundStyle(ATHLTHTrainDesign.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHTrainDesign.ink.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Image(systemName: "play.fill")
                        .font(.caption.weight(.bold))
                    Text(ATHLTHLocalization.choose(
                        english: "Choose free training",
                        norwegian: "Velg fri trening"
                    ))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 15)
                .frame(minHeight: 46)
                .background(
                    ATHLTHTrainDesign.bronze,
                    in: RoundedRectangle(cornerRadius: 13)
                )
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ATHLTHTrainDesign.paleGold.opacity(isSelected ? 0.55 : 0.27),
                in: RoundedRectangle(cornerRadius: 23, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 23, style: .continuous)
                    .strokeBorder(
                        ATHLTHTrainDesign.bronze.opacity(isSelected ? 0.7 : 0.22),
                        lineWidth: isSelected ? 1.2 : 0.8
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 23))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("athlth-basic-free-hero")
    }
}

struct ATHLTHBasicActivityModeTile: View {
    let title: String
    let subtitle: String
    let symbol: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Image(systemName: symbol)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(ATHLTHTrainDesign.bronze)
                    }
                }
                Spacer(minLength: 0)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTrainDesign.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(ATHLTHTrainDesign.ink.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 122, alignment: .topLeading)
            .background(
                selected ? ATHLTHTrainDesign.paleGold.opacity(0.45) : .white,
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(
                        ATHLTHTrainDesign.bronze.opacity(selected ? 0.6 : 0.2),
                        lineWidth: selected ? 1 : 0.8
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 17))
        }
        .buttonStyle(.plain)
    }
}


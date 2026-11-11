import SwiftUI

/// One compact Basic layout for Quick Train and scratch planning.
/// The presentation owns no workout data and starts no workout itself.
struct ATHLTHRunBasicSetupView: View {
    @Binding var workoutName: String
    @Binding var mode: RunQuickStartMode
    @Binding var environment: RunEnvironment
    @Binding var date: Date

    var scheduleEditable = false
    /// For a planned scratch run, edit the date and structured workout here,
    /// not through the legacy scheduling sheet behind this builder.
    var workoutStepCount = 0
    var onEditWorkout: (() -> Void)? = nil
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

    @State private var showsBasicCoachSettings = false

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

            if scheduleEditable {
                plannedRunSummary
            }

            ATHLTHBasicActivityHero(
                title: ATHLTHLocalization.choose(
                    english: "Free running", norwegian: "Fri løping"
                ),
                subtitle: ATHLTHLocalization.choose(
                    english: "Start without a plan. Add goals and coaching if you want.",
                    norwegian: "Start uten plan. Legg til mål og veiledning hvis du ønsker."
                ),
                symbol: "figure.run",
                isSelected: mode == .free && !isGoalSelected && !isGhostSelected,
                showsAction: false
            ) {
                onChooseStandardMode?()
                mode = .free
            }

            sectionHeading(ATHLTHLocalization.choose(
                english: "Choose running mode", norwegian: "Velg løpemodus"
            ))
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10),
                          GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                runTiles
            }

            // Basic has one visible run choice, not a second generic
            // Workout Details editor that duplicates the schedule screen.
            ATHLTHRunEnvironmentDetailRow(environment: $environment)
                .padding(12)
                .athlthTrainPaper()

            if let audioCoachEnabled {
                DisclosureGroup(isExpanded: $showsBasicCoachSettings) {
                    Toggle(isOn: audioCoachEnabled) {
                        Label("Audio Coach", systemImage: "waveform")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(ink)
                    }
                    .tint(bronze)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("athlth-basic-audio-coach")
                    .padding(.top, 10)
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Audio Coach settings",
                        norwegian: "Audio Coach-innstillinger"
                    ), systemImage: "waveform")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ink)
                }
                .tint(bronze)
                .padding(14)
                .athlthTrainPaper()
            }
        }
        .onChange(of: environment) { _, value in
            if value != .outdoor && mode == .route {
                onChooseStandardMode?()
                mode = .free
            }
        }
    }

    /// The scheduling summary used to live in the *parent* editor after
    /// Save and continue. Keep it here so a free run uses one cohesive sheet.
    private var plannedRunSummary: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "figure.run")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(bronze)
                    .frame(width: 35, height: 39)
                    .accessibilityHidden(true)
                Text(workoutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                     ? suggestedName : workoutName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(ink)
                    .lineLimit(2)
                Spacer(minLength: 4)
                Text(ATHLTHLocalization.format(
                    english: "%d steps", norwegian: "%d deløkter",
                    workoutStepCount
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(minHeight: 49)

            Divider()

            HStack(spacing: 10) {
                Text(ATHLTHLocalization.choose(
                    english: "Date and time", norwegian: "Dato og tid"
                ))
                .font(.subheadline)
                .foregroundStyle(ink)
                .layoutPriority(1)

                Spacer(minLength: 3)

                DatePicker(
                    ATHLTHLocalization.choose(english: "Date", norwegian: "Dato"),
                    selection: $date,
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .accessibilityIdentifier("athlth-basic-run-planned-date")

                DatePicker(
                    ATHLTHLocalization.choose(english: "Time", norwegian: "Tid"),
                    selection: $date,
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .accessibilityIdentifier("athlth-basic-run-planned-time")
            }
            .frame(minHeight: 55)

            if let onEditWorkout {
                Divider()
                Button(action: onEditWorkout) {
                    HStack(spacing: 12) {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(bronze)
                            .frame(width: 30)
                        Text(ATHLTHLocalization.choose(
                            english: "Edit workout",
                            norwegian: "Rediger økten"
                        ))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(bronze)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(bronze.opacity(0.75))
                    }
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("athlth-basic-run-edit-workout")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(ATHLTHPlanDesign.outline, lineWidth: 0.7)
        }
        .accessibilityIdentifier("athlth-basic-run-summary")
    }

    private func sectionHeading(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .semibold, design: .rounded))
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
                    english: "Combine distance, time, pace and pulse", norwegian: "Kombiner distanse, tid, tempo og puls"
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
    var actionTitle: String? = nil
    var showsAction = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: symbol)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                        .frame(width: 43, height: 43)
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
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                        .foregroundStyle(ATHLTHTrainDesign.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHTrainDesign.ink.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if showsAction {
                    HStack {
                        Image(systemName: "play.fill")
                            .font(.caption.weight(.bold))
                        Text(actionTitle ?? ATHLTHLocalization.choose(
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
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ATHLTHTrainDesign.paleGold.opacity(isSelected ? 0.38 : 0.12),
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
    var asNavigationLabel = false
    let action: () -> Void

    @ViewBuilder
    var body: some View {
        if asNavigationLabel {
            tileContent
        } else {
            Button(action: action) { tileContent }
                .buttonStyle(.plain)
        }
    }

    private var tileContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                    .frame(width: 36, height: 36)
                    .background(
                        ATHLTHTrainDesign.paleGold.opacity(0.55),
                        in: RoundedRectangle(cornerRadius: 13)
                    )
                Spacer(minLength: 0)
                Image(systemName: selected
                      ? "checkmark.circle.fill" : "arrow.up.right")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(ATHLTHTrainDesign.bronze.opacity(
                        selected ? 1 : 0.65))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(ATHLTHTrainDesign.ink)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(ATHLTHTrainDesign.ink.opacity(0.68))
                    .lineLimit(2)
                    .frame(minHeight: 32, alignment: .topLeading)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .background(
            selected ? ATHLTHTrainDesign.paleGold.opacity(0.48) : .white,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    ATHLTHTrainDesign.bronze.opacity(selected ? 0.6 : 0.16),
                    lineWidth: selected ? 1.2 : 0.7)
        }
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

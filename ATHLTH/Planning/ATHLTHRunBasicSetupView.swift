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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let ink = ATHLTHTrainDesign.ink
    private let bronze = ATHLTHTrainDesign.bronze
    private let gold = ATHLTHTrainDesign.gold

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
        VStack(alignment: .leading, spacing: 13) {
            detailsCard

            VStack(alignment: .leading, spacing: 8) {
                sectionHeading(
                    ATHLTHLocalization.choose(english: "Run type", norwegian: "Løpetype")
                )
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 9) { runTiles }
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(spacing: 8) { runTiles }
                    } else {
                        HStack(spacing: 5) { runTiles }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionHeading(
                    ATHLTHLocalization.choose(english: "Where are you running?",
                                              norwegian: "Hvor trener du?")
                )
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 9) { environmentTiles }
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(spacing: 8) { environmentTiles }
                    } else {
                        HStack(spacing: 5) { environmentTiles }
                    }
                }
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
        ForEach(RunQuickStartMode.allCases) { option in
            choiceTile(
                title: option.title,
                symbol: option.icon,
                selected: mode == option
            ) {
                if option == .route {
                    environment = .outdoor
                    onChooseRoute?()
                } else if option == .structured {
                    onChooseWorkout?()
                }
                mode = option
            }
        }
    }

    @ViewBuilder
    private var environmentTiles: some View {
        ForEach(RunEnvironment.allCases) { option in
            choiceTile(
                title: option.title,
                symbol: option.systemImage,
                selected: environment == option
            ) {
                environment = option
                if option != .outdoor && mode == .route {
                    mode = .free
                }
            }
        }
    }

    private func choiceTile(
        title: String,
        symbol: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Image(systemName: symbol)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(selected ? .white : bronze)
                        .frame(width: 34, height: 34)
                        .background(
                            selected ? bronze : ATHLTHTrainDesign.paleGold.opacity(0.48),
                            in: RoundedRectangle(cornerRadius: 11)
                        )
                    Spacer(minLength: 0)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(bronze)
                    }
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 83 : 68,
                   alignment: .topLeading)
            .padding(.horizontal, 9)
            .padding(.vertical, 10)
            .background(
                selected
                    ? ATHLTHTrainDesign.paleGold.opacity(0.37)
                    : ATHLTHTrainDesign.paper,
                in: RoundedRectangle(cornerRadius: 17)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 17)
                    .strokeBorder(
                        selected ? gold.opacity(0.8)
                            : ATHLTHTrainDesign.rule.opacity(0.42),
                        lineWidth: selected ? 1.2 : 0.8
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 17))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .frame(maxWidth: .infinity)
    }
}

import SwiftUI

/// Photo-led goal selector shown after the user chooses Simple or Advanced.
/// It writes to the existing plan focus and goal; no parallel plan model.
enum ATHLTHPlanGoalArea: String, CaseIterable, Identifiable {
    case running, strength, general, specific

    var id: Self { self }

    var title: String {
        switch self {
        case .running: return ATHLTHLocalization.choose(english: "Running", norwegian: "Løping")
        case .strength: return ATHLTHLocalization.choose(english: "Strength", norwegian: "Styrke")
        case .general: return ATHLTHLocalization.choose(english: "General", norwegian: "Generelt")
        case .specific: return ATHLTHLocalization.choose(english: "Specific goal", norwegian: "Spesifikt mål")
        }
    }

    var subtitle: String {
        switch self {
        case .running:
            return ATHLTHLocalization.choose(
                english: "Run faster, farther or build endurance.",
                norwegian: "Bli raskere, løp lenger eller bygg utholdenhet."
            )
        case .strength:
            return ATHLTHLocalization.choose(
                english: "Build muscle and become stronger.",
                norwegian: "Bygg muskler, bli sterkere og mer robust."
            )
        case .general:
            return ATHLTHLocalization.choose(
                english: "A balanced plan with different activities.",
                norwegian: "En balansert plan med ulike treningsformer."
            )
        case .specific:
            return ATHLTHLocalization.choose(
                english: "Prepare for an event or a concrete target.",
                norwegian: "Forbered deg til et spesifikt løp, event eller test."
            )
        }
    }

    var imageName: String {
        switch self {
        case .running: return "GoalRunning"
        case .strength: return "GoalStrength"
        case .general: return "GoalRecovery"
        case .specific: return "GoalAdventure"
        }
    }

    var icon: String {
        switch self {
        case .running: return "figure.run"
        case .strength: return "dumbbell"
        case .general: return "chart.bar.fill"
        case .specific: return "trophy"
        }
    }
}

/// One item in the compact radio-list. Each is backed by a real saved
/// TrainingPlanFocus and TrainingPlanGoalType, not illustrative fake data.
struct ATHLTHPlanGoalOption: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let focus: TrainingPlanFocus
    let goal: TrainingPlanGoalType

    static func options(for area: ATHLTHPlanGoalArea) -> [Self] {
        func option(
            _ id: String, _ norwegian: String, _ english: String,
            _ noDetail: String, _ enDetail: String,
            _ icon: String, _ focus: TrainingPlanFocus,
            _ goal: TrainingPlanGoalType
        ) -> Self {
            Self(
                id: id,
                title: ATHLTHLocalization.choose(english: english, norwegian: norwegian),
                subtitle: ATHLTHLocalization.choose(english: enDetail, norwegian: noDetail),
                icon: icon, focus: focus, goal: goal
            )
        }

        switch area {
        case .running:
            return [
                option("fitness", "Bedre kondisjon", "Better fitness",
                       "Øk utholdenhet og generell form.", "Improve endurance and fitness.",
                       "target", .running, .improveFitness),
                option("speed", "Raskere tider", "Faster times",
                       "Forbedre tempo og løpsøkonomi.", "Improve pace and running efficiency.",
                       "stopwatch", .running, .runFaster),
                option("distance", "Løpe lenger", "Run farther",
                       "Bygg opp distanse og utholdenhet.", "Build running distance and endurance.",
                       "mountain.2", .endurance, .improveFitness),
                option("power", "Bygge styrke", "Build strength",
                       "Bli sterkere og mer robust.", "Become stronger and more resilient.",
                       "figure.strengthtraining.traditional", .strength, .getStronger),
                option("wellness", "Bedre helse og velvære", "Health and wellness",
                       "Mer energi i hverdagen.", "More energy in everyday life.",
                       "leaf", .generalFitness, .improveFitness)
            ]
        case .strength:
            return [
                option("power", "Bli sterkere", "Get stronger",
                       "Utvikle styrken i hovedøvelsene.", "Get stronger in main lifts.",
                       "dumbbell", .strength, .getStronger),
                option("muscle", "Bygge muskler", "Build muscle",
                       "Øk muskelmasse med progresjon.", "Build muscle with progression.",
                       "figure.strengthtraining.traditional", .hypertrophy, .buildMuscle),
                option("fitness", "Bedre arbeidskapasitet", "Improve capacity",
                       "Mer overskudd mellom øktene.", "Build better training capacity.",
                       "chart.bar.fill", .hybrid, .improveFitness),
                option("maintain", "Beholde styrken", "Maintain strength",
                       "Ta vare på nivået du har.", "Maintain the strength you have.",
                       "checkmark.shield", .strength, .maintain),
                option("return", "Tilbake etter pause", "Return after a break",
                       "Kom gradvis og trygt i gang.", "Build up gradually again.",
                       "arrow.counterclockwise", .strength, .returnAfterBreak)
            ]
        case .general:
            return [
                option("fitness", "Bedre kondisjon", "Better fitness",
                       "Få mer overskudd i hverdagen.", "Feel fitter in everyday life.",
                       "target", .generalFitness, .improveFitness),
                option("balance", "Variert trening", "Balanced training",
                       "Kombiner styrke og kondisjon.", "Combine strength and cardio.",
                       "figure.mixed.cardio", .hybrid, .improveFitness),
                option("wellness", "Helse og velvære", "Health and wellness",
                       "Bygg gode og varige vaner.", "Build sustainable habits.",
                       "leaf", .generalFitness, .improveFitness),
                option("maintain", "Holde meg i form", "Stay in shape",
                       "Vedlikehold formen over tid.", "Maintain your fitness.",
                       "heart", .generalFitness, .maintain),
                option("return", "Komme i gang igjen", "Get back into it",
                       "Finn tilbake til treningsrutinen.", "Get back into your routine.",
                       "arrow.counterclockwise", .generalFitness, .returnAfterBreak)
            ]
        case .specific:
            return [
                option("event", "Gjennomføre et løp", "Complete an event",
                       "Bygg formen mot et bestemt løp.", "Train towards a specific event.",
                       "trophy", .running, .raceReady),
                option("speed", "Sette ny personlig rekord", "Set a new record",
                       "Jobb målrettet mot raskere tid.", "Aim for a faster time.",
                       "stopwatch", .running, .runFaster),
                option("distance", "Mestre en ny distanse", "Reach a new distance",
                       "Øk utholdenheten steg for steg.", "Build distance step by step.",
                       "mountain.2", .endurance, .raceReady),
                option("power", "Nå et styrkemål", "Reach a strength target",
                       "Utvikle deg mot et bestemt løft.", "Build towards a strength target.",
                       "dumbbell", .strength, .getStronger),
                option("fitness", "Klar for en fysisk test", "Prepare for a fitness test",
                       "Tren mot et konkret resultat.", "Train for a clear result.",
                       "target", .hybrid, .improveFitness)
            ]
        }
    }
}

/// The live Plan creation goal screen. All selections are driven by the
/// wizard's existing bindings and persist as TrainingPlanFocus/GoalType.
/// This is presentation only: it introduces no alternate creation path.
struct ATHLTHPlanGoalEntryView: View {
    let area: ATHLTHPlanGoalArea
    let selectedChoice: String
    let onChooseArea: (ATHLTHPlanGoalArea) -> Void
    let onChooseGoal: (ATHLTHPlanGoalOption) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let canvas = ATHLTHTrainDesign.canvas
    private let ink = ATHLTHTrainDesign.ink
    private let muted = ATHLTHTrainDesign.secondary
    private let gold = ATHLTHTrainDesign.gold
    private let bronze = ATHLTHTrainDesign.bronze
    private let divider = ATHLTHTrainDesign.rule

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            referenceHero
            categoryGrid
            mainGoalList
        }
        .frame(maxWidth: ATHLTHPlanDesign.maxContentWidth)
    }

    // Full-width scenic cover, with the editorial copy remaining entirely
    // legible on top of the left-to-right warm-paper fade.
    private var referenceHero: some View {
        ZStack(alignment: .leading) {
            GeometryReader { geometry in
                Image("PlanGoalHero")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .accessibilityHidden(true)
            }

            LinearGradient(
                stops: [
                    .init(color: canvas, location: 0),
                    .init(color: canvas.opacity(0.99), location: 0.29),
                    .init(color: canvas.opacity(0.90), location: 0.48),
                    .init(color: canvas.opacity(0.31), location: 0.78),
                    .init(color: canvas.opacity(0.04), location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            VStack(alignment: .leading, spacing: 9) {
                Text(ATHLTHLocalization.choose(
                    english: "BUILD YOUR PLAN",
                    norwegian: "BYGG DIN PLAN"
                ))
                .font(.system(size: 10, weight: .semibold))
                .tracking(2.6)
                .foregroundStyle(muted)

                Text(ATHLTHLocalization.choose(
                    english: "What is your goal?",
                    norwegian: "Hva er målet ditt?"
                ))
                .font(.system(
                    size: dynamicTypeSize.isAccessibilitySize ? 32 : 36,
                    weight: .regular, design: .serif
                ))
                .foregroundStyle(ink)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

                Text(ATHLTHLocalization.choose(
                    english: "Choose the main focus for your plan.",
                    norwegian: "Velg hovedfokus for planen din."
                ))
                .font(.system(size: 13))
                .foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: dynamicTypeSize.isAccessibilitySize ? 205 : 145)
        .clipped()
        .padding(.horizontal, -18)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var categoryGrid: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 10) {
                ForEach(ATHLTHPlanGoalArea.allCases) { item in
                    categoryCard(item)
                }
            }
        } else {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(ATHLTHPlanGoalArea.allCases) { item in
                    categoryCard(item)
                }
            }
        }
    }

    private func categoryCard(_ item: ATHLTHPlanGoalArea) -> some View {
        let isSelected = area == item
        return Button {
            onChooseArea(item)
        } label: {
            ZStack(alignment: .topLeading) {
                GeometryReader { bounds in
                    Image(item.imageName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: bounds.size.width, height: bounds.size.height)
                        .clipped()
                        .accessibilityHidden(true)
                }

                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.99), location: 0),
                        .init(color: .white.opacity(0.95), location: 0.27),
                        .init(color: .white.opacity(0.68), location: 0.58),
                        .init(color: .white.opacity(0.04), location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                VStack(alignment: .leading, spacing: 5) {
                    Image(systemName: item.icon)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(isSelected ? .white : bronze)
                        .frame(width: 39, height: 39)
                        .background(
                            isSelected ? gold : ATHLTHTrainDesign.paleGold.opacity(0.72),
                            in: Circle()
                        )
                        .accessibilityHidden(true)

                    Spacer(minLength: 4)

                    Text(item.title)
                        .font(.system(size: 21, weight: .semibold, design: .serif))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text(item.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(muted)
                        .multilineTextAlignment(.leading)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 3)
                        .frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(12)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(gold, in: Circle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: .topTrailing)
                        .padding(10)
                        .accessibilityHidden(true)
                }
            }
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 160 : 128)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isSelected ? bronze.opacity(0.88) : divider.opacity(0.35),
                        lineWidth: isSelected ? 1.3 : 0.65
                    )
                    .allowsHitTesting(false)
            }
            .shadow(color: bronze.opacity(0.07), radius: 12, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title + ". " + item.subtitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(ATHLTHLocalization.choose(
            english: "Select this training focus.",
            norwegian: "Velg dette treningsfokuset."
        ))
    }

    private var mainGoalList: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(ATHLTHLocalization.choose(
                english: "WHAT'S YOUR MAIN GOAL?",
                norwegian: "HVA ER DITT HOVEDMÅL?"
            ))
            .font(.system(size: 10, weight: .semibold))
            .tracking(2.2)
            .foregroundStyle(muted)
            .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                let options = ATHLTHPlanGoalOption.options(for: area)
                ForEach(options.indices, id: \.self) { index in
                    mainGoalRow(options[index])
                    if index < options.count - 1 {
                        Rectangle()
                            .fill(divider.opacity(0.32))
                            .frame(height: 0.6)
                            .padding(.horizontal, 12)
                    }
                }
            }
            .background(
                .white.opacity(0.93),
                in: RoundedRectangle(cornerRadius: 19, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .strokeBorder(divider.opacity(0.32), lineWidth: 0.65)
                    .allowsHitTesting(false)
            }
            .shadow(color: bronze.opacity(0.045), radius: 13, y: 5)
        }
    }

    private func mainGoalRow(_ option: ATHLTHPlanGoalOption) -> some View {
        let isSelected = option.id == selectedChoice
        return Button {
            onChooseGoal(option)
        } label: {
            HStack(spacing: 11) {
                Image(systemName: option.icon)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(bronze)
                    .frame(width: 43, height: 43)
                    .background(
                        ATHLTHTrainDesign.paleGold.opacity(0.34),
                        in: Circle()
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(option.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ink)
                        .multilineTextAlignment(.leading)
                    Text(option.subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(muted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                ZStack {
                    Circle()
                        .strokeBorder(
                            isSelected ? bronze : divider.opacity(0.70),
                            lineWidth: isSelected ? 1.6 : 1.25
                        )
                        .frame(width: 21, height: 21)
                    if isSelected {
                        Circle()
                            .fill(bronze)
                            .frame(width: 13, height: 13)
                    }
                }
                .frame(width: 29, height: 40)
                .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 57)
            .padding(.horizontal, 13)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(option.title + ". " + option.subtitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(ATHLTHLocalization.choose(
            english: "Select as your main goal.",
            norwegian: "Velg som hovedmål."
        ))
    }
}

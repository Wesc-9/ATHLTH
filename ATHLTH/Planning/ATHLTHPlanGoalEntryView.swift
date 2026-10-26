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

struct ATHLTHPlanGoalEntryView: View {
    let area: ATHLTHPlanGoalArea
    let selectedChoice: String
    let onChooseArea: (ATHLTHPlanGoalArea) -> Void
    let onChooseGoal: (ATHLTHPlanGoalOption) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let ink = ATHLTHTrainDesign.ink
    private let secondary = ATHLTHTrainDesign.secondary
    private let bronze = ATHLTHTrainDesign.bronze
    private let gold = ATHLTHTrainDesign.gold
    private let rule = ATHLTHTrainDesign.rule

    var body: some View {
        VStack(alignment: .leading, spacing: 21) {
            hero
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) {
                    ForEach(ATHLTHPlanGoalArea.allCases) { item in areaCard(item) }
                }
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                    GridItem(.flexible(), spacing: 10)],
                          spacing: 10) {
                    ForEach(ATHLTHPlanGoalArea.allCases) { item in areaCard(item) }
                }
            }

            VStack(alignment: .leading, spacing: 11) {
                Text(ATHLTHLocalization.choose(
                    english: "WHAT'S YOUR MAIN GOAL?",
                    norwegian: "HVA ER DITT HOVEDMÅL?"
                ))
                .font(.system(size: 10, weight: .semibold))
                .tracking(2.1)
                .foregroundStyle(secondary)

                VStack(spacing: 0) {
                    let options = ATHLTHPlanGoalOption.options(for: area)
                    ForEach(options.indices, id: \.self) { index in
                        goalRow(options[index])
                        if index < options.count - 1 {
                            Rectangle()
                                .fill(rule.opacity(0.4))
                                .frame(height: 0.6)
                                .padding(.horizontal, 15)
                        }
                    }
                }
                .background(.white.opacity(0.93),
                            in: RoundedRectangle(cornerRadius: 17))
                .overlay {
                    RoundedRectangle(cornerRadius: 17)
                        .stroke(rule.opacity(0.36), lineWidth: 0.6)
                }
            }
        }
        .frame(maxWidth: ATHLTHPlanDesign.maxContentWidth)
    }

    private var hero: some View {
        ZStack(alignment: .leading) {
            GeometryReader { bounds in
                Image("GoalAdventure")
                    .resizable()
                    .scaledToFill()
                    .frame(width: bounds.size.width, height: bounds.size.height)
                    .clipped()
            }
            LinearGradient(
                stops: [
                    .init(color: ATHLTHTrainDesign.canvas, location: 0),
                    .init(color: ATHLTHTrainDesign.canvas.opacity(0.96), location: 0.40),
                    .init(color: ATHLTHTrainDesign.canvas.opacity(0.30), location: 1)
                ],
                startPoint: .leading, endPoint: .trailing
            )
            VStack(alignment: .leading, spacing: 9) {
                Text(ATHLTHLocalization.choose(english: "BUILD YOUR PLAN",
                                                norwegian: "BYGG DIN PLAN"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2.5)
                    .foregroundStyle(secondary)
                Text(ATHLTHLocalization.choose(english: "What is your goal?",
                                                norwegian: "Hva er målet ditt?"))
                    .font(.system(size: 35, weight: .regular, design: .serif))
                    .foregroundStyle(ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)
                Text(ATHLTHLocalization.choose(
                    english: "Choose the main focus for your plan.",
                    norwegian: "Velg hovedfokus for planen din."
                ))
                .font(.system(size: 13))
                .foregroundStyle(secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 3)
        }
        .frame(height: 157)
        .clipped()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func areaCard(_ item: ATHLTHPlanGoalArea) -> some View {
        let chosen = area == item
        return Button {
            onChooseArea(item)
        } label: {
            ZStack(alignment: .leading) {
                GeometryReader { bounds in
                    Image(item.imageName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: bounds.size.width, height: bounds.size.height)
                        .clipped()
                }
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.98), location: 0),
                        .init(color: .white.opacity(0.89), location: 0.45),
                        .init(color: .white.opacity(0.03), location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                VStack(alignment: .leading, spacing: 7) {
                    Image(systemName: item.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(chosen ? .white : bronze)
                        .frame(width: 37, height: 37)
                        .background(chosen ? gold : ATHLTHTrainDesign.paleGold.opacity(0.73),
                                    in: Circle())
                        .padding(.bottom, 2)

                    Spacer(minLength: 0)

                    Text(item.title)
                        .font(.system(size: 21, weight: .medium, design: .serif))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Text(item.subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 38, alignment: .top)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                if chosen {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 27, height: 27)
                                .background(gold, in: Circle())
                        }
                        Spacer()
                    }
                    .padding(10)
                    .accessibilityHidden(true)
                }
            }
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 190 : 162)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(chosen ? gold : rule.opacity(0.4),
                                  lineWidth: chosen ? 1.4 : 0.65)
            }
            .shadow(color: ink.opacity(0.04), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title + ". " + item.subtitle)
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
    }

    private func goalRow(_ item: ATHLTHPlanGoalOption) -> some View {
        let chosen = selectedChoice == item.id
        return Button {
            onChooseGoal(item)
        } label: {
            HStack(spacing: 11) {
                Image(systemName: item.icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(bronze)
                    .frame(width: 43, height: 43)
                    .background(ATHLTHTrainDesign.paleGold.opacity(0.34),
                                in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ink)
                    Text(item.subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: chosen ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(chosen ? bronze : secondary.opacity(0.30))
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 62)
            .padding(.horizontal, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title + ". " + item.subtitle)
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
    }
}

import SwiftUI

/// Choice is available only to Advanced plan builders.
/// Manual options use the existing week and guided-day editors; AI uses
/// ATHLTH's existing AIProgramBuilderView. No parallel plan is created here.
enum ATHLTHPlanBuildMethod: String, CaseIterable, Identifiable {
    case dayByDay
    case weekByWeek
    case ai

    var id: String { rawValue }
}

struct ATHLTHPlanBuildMethodEntryView: View {
    let selected: ATHLTHPlanBuildMethod
    let onSelect: (ATHLTHPlanBuildMethod) -> Void
    let onOpenLibrary: () -> Void
    let onOpenMyPlans: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private let ink = ATHLTHTrainDesign.ink
    private let bronze = ATHLTHTrainDesign.bronze
    private let secondary = ATHLTHTrainDesign.secondary
    private let canvas = ATHLTHTrainDesign.canvas
    private let rule = ATHLTHTrainDesign.rule

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            introduction
            methodCard(
                .dayByDay,
                name: tr("Day by day", "Dag for dag"),
                description: tr(
                    "Plan each training day separately. Once a week is complete, copy it to the remaining weeks.",
                    "Gå gjennom hver treningsdag enkeltvis. Når en uke er ferdig, kan du kopiere den videre i planen."
                ),
                photo: "PlanScheduleHero",
                symbol: "calendar.badge.checkmark",
                qualities: [
                    ("target", tr("Detailed", "Detaljert")),
                    ("square.on.square", tr("Copy week", "Kopier uke")),
                    ("dumbbell", tr("Each day", "Daglige valg"))
                ]
            )
            methodCard(
                .weekByWeek,
                name: tr("Week by week", "Uke for uke"),
                description: tr(
                    "Build complete weeks together, then adjust workouts, workload and progression from week to week.",
                    "Bygg hele uker samlet og juster økter, belastning og progresjon fra uke til uke."
                ),
                photo: "PlanEntryAdvanced",
                symbol: "chart.bar.fill",
                qualities: [
                    ("calendar", tr("Week structure", "Ukestruktur")),
                    ("slider.horizontal.3", tr("Manual", "Manuell")),
                    ("chart.line.uptrend.xyaxis", tr("Progression", "Progresjon"))
                ]
            )
            HStack(spacing: 9) {
                shortcut(
                    tr("Plan library", "Planbibliotek"),
                    subtitle: tr("Ready-made plans", "Utforsk ferdige planer"),
                    symbol: "book.closed",
                    action: onOpenLibrary
                )
                shortcut(
                    tr("My plans", "Mine planer"),
                    subtitle: tr("Manage saved plans", "Se og rediger planer"),
                    symbol: "doc.text",
                    action: onOpenMyPlans
                )
            }
            .padding(.top, 3)
        }
        .frame(maxWidth: ATHLTHPlanDesign.maxContentWidth)
    }

    private var introduction: some View {
        ZStack(alignment: .leading) {
            GeometryReader { bounds in
                Image("PlanGoalHero")
                    .resizable()
                    .scaledToFill()
                    .frame(width: bounds.size.width, height: bounds.size.height)
                    .clipped()
                    .accessibilityHidden(true)
            }
            LinearGradient(
                stops: [
                    .init(color: canvas, location: 0),
                    .init(color: canvas.opacity(0.98), location: 0.30),
                    .init(color: canvas.opacity(0.83), location: 0.51),
                    .init(color: canvas.opacity(0.04), location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            VStack(alignment: .leading, spacing: 7) {
                Text(tr("BUILD YOUR PLAN", "BYGG DIN PLAN"))
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(2.5)
                    .foregroundStyle(secondary)
                Text(tr("How will you\nbuild your plan?",
                        "Hvordan vil du\nbygge opp planen?"))
                    .font(.system(
                        size: typeSize.isAccessibilitySize ? 29 : 35,
                        weight: .regular, design: .serif
                    ))
                    .foregroundStyle(ink)
                    .lineSpacing(-2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(tr(
                    "Choose whether to plan one day at a time or build entire weeks.",
                    "Velg om du vil planlegge dag for dag eller bygge ukene samlet."
                ))
                .font(.system(size: 12))
                .foregroundStyle(secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
            .padding(.trailing, typeSize.isAccessibilitySize ? 36 : 103)
        }
        .frame(height: typeSize.isAccessibilitySize ? 215 : 178)
        .clipped()
    }

    private func methodCard(
        _ method: ATHLTHPlanBuildMethod,
        name: String,
        description: String,
        photo: String,
        symbol: String,
        qualities: [(String, String)]
    ) -> some View {
        let chosen = selected == method
        return Button { onSelect(method) } label: {
            VStack(spacing: 0) {
                ZStack(alignment: .leading) {
                    GeometryReader { bounds in
                        Image(photo)
                            .resizable()
                            .scaledToFill()
                            .frame(width: bounds.size.width, height: bounds.size.height)
                            .clipped()
                            .accessibilityHidden(true)
                    }
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.99), location: 0),
                            .init(color: .white.opacity(0.96), location: 0.30),
                            .init(color: .white.opacity(0.70), location: 0.59),
                            .init(color: .white.opacity(0.05), location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: symbol)
                                .font(.system(size: 19, weight: .medium))
                                .foregroundStyle(bronze)
                                .frame(width: 38, height: 38)
                                .background(ATHLTHTrainDesign.paleGold.opacity(0.60),
                                            in: Circle())
                            Text(name)
                                .font(.system(size: 24, weight: .semibold, design: .serif))
                                .foregroundStyle(ink)
                                .minimumScaleFactor(0.78)
                                .lineLimit(1)
                                .padding(.top, 3)
                            Spacer(minLength: 32)
                        }
                        Text(description)
                            .font(.system(size: 11))
                            .foregroundStyle(secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(typeSize.isAccessibilitySize ? 7 : 3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 48)
                            .padding(.trailing, 78)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(13)

                    Image(systemName: chosen ? "checkmark" : "circle")
                        .font(.system(size: chosen ? 13 : 27, weight: .semibold))
                        .foregroundStyle(chosen ? .white : ink.opacity(0.30))
                        .frame(width: 31, height: 31)
                        .background {
                            if chosen { Circle().fill(bronze.gradient) }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: .topTrailing)
                        .padding(11)
                        .accessibilityHidden(true)
                }
                .frame(height: typeSize.isAccessibilitySize ? 177 : 124)
                .clipped()

                HStack(spacing: 6) {
                    ForEach(qualities.indices, id: \.self) { i in
                        Label(qualities[i].1, systemImage: qualities[i].0)
                            .font(.system(size: 9.5))
                            .foregroundStyle(secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.67)
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                }
                .padding(.horizontal, 6)
                .background(.white.opacity(0.86))
            }
            .background(.white, in: RoundedRectangle(cornerRadius: 18))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(chosen ? bronze : rule.opacity(0.43),
                                  lineWidth: chosen ? 1.5 : 0.7)
                    .allowsHitTesting(false)
            }
            .shadow(color: ink.opacity(chosen ? 0.07 : 0.035), radius: 10, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name + ". " + description)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func shortcut(
        _ title: String,
        subtitle: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 19))
                    .foregroundStyle(bronze)
                    .frame(width: 40, height: 40)
                    .background(ATHLTHTrainDesign.paleGold.opacity(0.52),
                                in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(bronze)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 61, alignment: .leading)
            .background(.white.opacity(0.89),
                        in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(rule.opacity(0.32), lineWidth: 0.7)
            }
        }
        .buttonStyle(.plain)
    }
}

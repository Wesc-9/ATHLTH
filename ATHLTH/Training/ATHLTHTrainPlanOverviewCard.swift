import SwiftUI

/// The compact, accessible entry point to Train → Plan.
/// It reflects persisted plan progress and never starts a workout.
struct ATHLTHTrainPlanOverviewCard<Actions: View>: View {
    let title: String
    let status: String
    let currentWeek: Int
    let weekCount: Int
    let startDate: Date?
    let completionFraction: Double
    let workoutCount: Int
    let completedCount: Int
    let remainingCount: Int
    let restDays: Int
    let onOpenMyPlans: () -> Void
    @ViewBuilder let actions: Actions

    private var gold: Color { ATHLTHTrainDesign.gold }
    private var ink: Color { ATHLTHTrainDesign.ink }
    private var secondary: Color { ATHLTHTrainDesign.secondary }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 9) {
                Button(action: onOpenMyPlans) {
                    HStack(alignment: .top, spacing: 13) {
                        Image(systemName: "calendar")
                            .font(.system(size: 21, weight: .medium))
                            .foregroundStyle(ATHLTHTrainDesign.bronze)
                            .frame(width: 48, height: 48)
                            .background(ATHLTHTrainDesign.paleGold.opacity(0.55),
                                        in: RoundedRectangle(cornerRadius: 15))

                        VStack(alignment: .leading, spacing: 5) {
                            Text(status.uppercased())
                                .font(.caption2.weight(.semibold))
                                .tracking(1.6)
                                .foregroundStyle(ATHLTHTrainDesign.bronze)
                            Text(title)
                                .font(.system(.title3, design: .serif).weight(.semibold))
                                .foregroundStyle(ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                            Text(weekCount == 0
                                ? tr("No training weeks yet", "Ingen treningsuker ennå")
                                : tr("Week \(currentWeek) of \(weekCount)",
                                     "Uke \(currentWeek) av \(weekCount)"))
                                .font(.subheadline)
                                .foregroundStyle(secondary)
                            if let startDate {
                                Text(startDate.formatted(.dateTime.day().month(.abbreviated).year()))
                                    .font(.caption)
                                    .foregroundStyle(secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(secondary)
                            .padding(.top, 8)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    tr("Open My plans", "Åpne Mine planer") + ": " + title
                )

                Menu {
                    actions
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .foregroundStyle(ink)
                        .frame(width: 44, height: 44)
                        .background(ATHLTHTrainDesign.paper, in: Circle())
                        .overlay {
                            Circle().strokeBorder(ATHLTHTrainDesign.rule.opacity(0.6))
                        }
                }
                .accessibilityLabel(tr("Plan options", "Planvalg"))
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(tr("Program completion", "Gjennomført av planen"))
                        .font(.caption)
                        .foregroundStyle(secondary)
                    Spacer()
                    Text("\(Int((min(max(completionFraction, 0), 1) * 100).rounded())) %")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(ink)
                }
                ProgressView(value: min(max(completionFraction, 0), 1))
                    .tint(gold)
                    .accessibilityLabel(tr("Program completion", "Gjennomført av planen"))
            }

            HStack(spacing: 9) {
                Label(tr("\(completedCount) completed", "\(completedCount) fullført"),
                      systemImage: "checkmark.circle")
                Spacer(minLength: 0)
                Label(tr("\(remainingCount) remaining", "\(remainingCount) gjenstår"),
                      systemImage: "clock")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(secondary)
            .lineLimit(2)
            .minimumScaleFactor(0.85)

            Text(tr(
                "\(workoutCount) workouts · \(restDays) days without workouts this week",
                "\(workoutCount) økter · \(restDays) dager uten økter denne uken"
            ))
            .font(.caption)
            .foregroundStyle(secondary)
        }
        .padding(16)
        .background(
            ATHLTHTrainDesign.paper,
            in: RoundedRectangle(cornerRadius: ATHLTHTrainDesign.radius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ATHLTHTrainDesign.radius)
                .strokeBorder(ATHLTHTrainDesign.rule.opacity(0.7), lineWidth: 0.8)
                .allowsHitTesting(false)
        }
    }

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }
}

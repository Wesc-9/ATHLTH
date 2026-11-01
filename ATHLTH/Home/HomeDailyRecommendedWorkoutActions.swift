import SwiftUI

/// Compact, accessible actions. Both start buttons still call the exact
/// existing iPhone and Apple Watch workout launch handlers.
struct HomeDailyRecommendedWorkoutActions: View {
    let isPlanWorkout: Bool
    let canStartWithWatch: Bool
    let onOpenPlannedWorkout: () -> Void
    let onStartOnPhone: () -> Void
    let onStartOnWatch: () -> Void

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    var body: some View {
        VStack(spacing: 9) {
            if isPlanWorkout {
                Button(action: onOpenPlannedWorkout) {
                    Label(
                        tr("Open workout and start", "Åpne økten og start"),
                        systemImage: "play.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(.white)
                    .background(
                        ATHLTHTrainDesign.bronze,
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                }
                .buttonStyle(.plain)
            } else {
                Button(action: onStartOnPhone) {
                    Label(
                        tr("Start with iPhone", "Start med iPhone"),
                        systemImage: "iphone"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(.white)
                    .background(
                        ATHLTHTrainDesign.bronze,
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                }
                .buttonStyle(.plain)

                if canStartWithWatch {
                    Button(action: onStartOnWatch) {
                        Label(
                            tr("Start with Apple Watch", "Start med Apple Watch"),
                            systemImage: "applewatch"
                        )
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .foregroundStyle(ATHLTHTrainDesign.ink)
                        .background(
                            Color.white.opacity(0.94),
                            in: RoundedRectangle(cornerRadius: 16)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(
                                    ATHLTHTrainDesign.bronze.opacity(0.32),
                                    lineWidth: 1
                                )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

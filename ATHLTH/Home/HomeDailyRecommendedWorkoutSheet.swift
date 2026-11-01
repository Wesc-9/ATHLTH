import SwiftUI

/// Shows the exact Home recommendation without changing its workout or
/// start-flow semantics. The execution actions remain in the pinned footer.
struct HomeDailyRecommendedWorkoutSheet: View {
    let workout: PlannedSession
    let isPlanWorkout: Bool
    let canStartWithWatch: Bool
    let onOpenPlannedWorkout: () -> Void
    let onStartOnPhone: () -> Void
    let onStartOnWatch: () -> Void

    @Environment(\.dismiss) private var dismiss

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ATHLTHTrainDesign.ink)
                            .frame(width: 42, height: 42)
                            .background(
                                ATHLTHPlanDesign.selectedSurface,
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tr("Close", "Lukk"))

                    Spacer(minLength: 0)

                    Text(tr("Recommended workout", "Anbefalt treningsøkt"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHTrainDesign.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer(minLength: 0)
                    // Balance the leading close control to keep the title centered.
                    Color.clear
                        .frame(width: 42, height: 42)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 7)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HomeDailyRecommendedWorkoutHero(workout: workout)

                        if !workout.resolvedWorkoutBlocks.isEmpty {
                            ATHLTHWorkoutContentsPreview(
                                workout: workout,
                                maximumVisibleBlocks: nil
                            )
                            .padding(17)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                Color.white,
                                in: RoundedRectangle(cornerRadius: 19)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 19)
                                    .strokeBorder(
                                        ATHLTHPlanDesign.outline.opacity(0.75),
                                        lineWidth: 0.8
                                    )
                            }
                        }

                        if isPlanWorkout {
                            Label {
                                Text(tr(
                                    "This is the workout in your plan. Open it to use the plan's existing tracking and completion rules.",
                                    "Dette er økten i treningsplanen. Åpne den for å bruke planens registrering og fullføringsregler."
                                ))
                            } icon: {
                                Image(systemName: "checkmark.seal")
                            }
                            .font(.caption)
                            .foregroundStyle(ATHLTHTrainDesign.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 6)
                        }
                    }
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 18)
                }
                .scrollIndicators(.hidden)
            }
            .background {
                LinearGradient(
                    colors: [
                        ATHLTHTrainDesign.paper,
                        ATHLTHPlanDesign.canvas
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HomeDailyRecommendedWorkoutActions(
                    isPlanWorkout: isPlanWorkout,
                    canStartWithWatch: canStartWithWatch,
                    onOpenPlannedWorkout: onOpenPlannedWorkout,
                    onStartOnPhone: onStartOnPhone,
                    onStartOnWatch: onStartOnWatch
                )
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 12)
                .frame(maxWidth: 660)
                .frame(maxWidth: .infinity)
                .background {
                    ATHLTHPlanDesign.canvas
                        .ignoresSafeArea(edges: .bottom)
                }
                .overlay(alignment: .top) {
                    ATHLTHPlanDesign.outline.opacity(0.55)
                        .frame(height: 0.75)
                }
            }
        }
    }
}

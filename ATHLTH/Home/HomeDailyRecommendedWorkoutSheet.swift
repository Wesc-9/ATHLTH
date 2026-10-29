import SwiftUI

/// A single confirmation surface for the *exact* workout described by the
/// Home recommendation. Uses the existing planner/recorder after selection.
struct HomeDailyRecommendedWorkoutSheet: View {
    let workout: PlannedSession
    let isPlanWorkout: Bool
    let canStartWithWatch: Bool
    let onOpenPlannedWorkout: () -> Void
    let onStartOnPhone: () -> Void
    let onStartOnWatch: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 13) {
                        Image(systemName: workout.kind.systemImage)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                            .frame(width: 56, height: 56)
                            .background(
                                ATHLTHPlanDesign.selectedSurface,
                                in: RoundedRectangle(cornerRadius: 16)
                            )
                        VStack(alignment: .leading, spacing: 5) {
                            Text(workout.title)
                                .font(.title2.bold())
                                .foregroundStyle(ATHLTHPlanDesign.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            if let minutes = workout.durationMinutes {
                                Label("\(minutes) min", systemImage: "clock")
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            }
                        }
                    }

                    if let notes = workout.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.subheadline)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }

                    if !workout.resolvedWorkoutBlocks.isEmpty {
                        ATHLTHWorkoutContentsPreview(
                            workout: workout, maximumVisibleBlocks: nil
                        )
                        .padding(14)
                        .background(
                            .white, in: RoundedRectangle(cornerRadius: 18)
                        )
                    }

                    if isPlanWorkout {
                        Text(ATHLTHLocalization.choose(
                            english: "This is the actual workout in your plan. Open it to start using the plan's existing tracking and completion rules.",
                            norwegian: "Dette er den faktiske økten i treningsplanen. Åpne den for å starte med planens eksisterende registrering og fullføringsregler."
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                }
                .padding(18)
            }
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(ATHLTHLocalization.choose(
                english: "Recommended workout", norwegian: "Anbefalt treningsøkt"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Close", norwegian: "Lukk"
                    )) {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 9) {
                    if isPlanWorkout {
                        Button {
                            onOpenPlannedWorkout()
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Open workout and start",
                                    norwegian: "Åpne økten og start"
                                ),
                                systemImage: "play.fill"
                            )
                            .frame(maxWidth: .infinity, minHeight: 49)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ATHLTHTheme.accentDeep)
                    } else {
                        Button(action: onStartOnPhone) {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Start with iPhone",
                                    norwegian: "Start med iPhone"
                                ),
                                systemImage: "iphone"
                            )
                            .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ATHLTHTheme.accentDeep)

                        if canStartWithWatch {
                            Button(action: onStartOnWatch) {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english: "Start with Apple Watch",
                                        norwegian: "Start med Apple Watch"
                                    ),
                                    systemImage: "applewatch"
                                )
                                .frame(maxWidth: .infinity, minHeight: 45)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(.horizontal, 17)
                .padding(.vertical, 12)
                .background(.regularMaterial)
            }
        }
    }
}

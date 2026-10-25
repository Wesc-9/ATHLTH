import SwiftUI

/// Creates a dated plan from a saved template only after explicit approval.
/// Active and historical plans are preserved; overlapping dates are blocked.
struct ATHLTHPlanTemplateStartSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore

    let template: TrainingPlan

    @State private var startDate =
        Calendar.current.startOfDay(for: Date())
    @State private var message: String?

    private var overlappingPlan: TrainingPlan? {
        session.trainingPlanConflict(
            startDate: startDate,
            weekCount: max(template.weeks.count, 1)
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(ATHLTHLocalization.choose(
                            english: "SAVED PLAN",
                            norwegian: "LAGRET PLAN"
                        ))
                        .font(.caption2.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(ATHLTHTheme.accentDeep)

                        Text(template.title)
                            .font(.system(size: 27, weight: .medium, design: .serif))
                            .foregroundStyle(ATHLTHTheme.primaryText)

                        Text(ATHLTHLocalization.choose(
                            english: "Choose when to start. The template remains unchanged.",
                            norwegian: "Velg oppstart. Den lagrede planen forblir uendret."
                        ))
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    }

                    VStack(alignment: .leading, spacing: 13) {
                        DatePicker(
                            ATHLTHLocalization.choose(
                                english: "Start date", norwegian: "Startdato"
                            ),
                            selection: $startDate,
                            in: Calendar.current.startOfDay(for: Date())...,
                            displayedComponents: .date
                        )

                        HStack {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Duration", norwegian: "Varighet"
                                ),
                                systemImage: "calendar"
                            )
                            Spacer()
                            Text("\(template.weeks.count) uker")
                        }
                        .font(.subheadline)

                        if let overlappingPlan {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Conflicts with \(overlappingPlan.title). Choose another start date.",
                                    norwegian: "Overlapper med \(overlappingPlan.title). Velg en annen startdato."
                                ),
                                systemImage: "exclamationmark.circle"
                            )
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                        }
                    }
                    .padding(17)
                    .background(
                        Color.white,
                        in: RoundedRectangle(cornerRadius: 21)
                    )

                    if let message {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                    }

                    Button {
                        guard overlappingPlan == nil else { return }
                        if session.usePlanTemplate(
                            template.id,
                            startDate: startDate
                        ) != nil {
                            dismiss()
                        } else {
                            message = ATHLTHLocalization.choose(
                                english: "The plan could not be created. Check for conflicting dates.",
                                norwegian: "Planen kunne ikke opprettes. Kontroller datoene."
                            )
                        }
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Create planned program",
                                norwegian: "Opprett plan"
                            ),
                            systemImage: "calendar.badge.plus"
                        )
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 49)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.white)
                    .background(
                        ATHLTHTheme.accentDeep,
                        in: RoundedRectangle(cornerRadius: 15)
                    )
                    .disabled(overlappingPlan != nil)
                    .opacity(overlappingPlan == nil ? 1 : 0.48)
                }
                .padding(20)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .background(ATHLTHTheme.canvasTop.ignoresSafeArea())
            .navigationTitle(ATHLTHLocalization.choose(
                english: "Use saved plan", norwegian: "Bruk lagret plan"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Cancel", norwegian: "Avbryt"
                    )) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}

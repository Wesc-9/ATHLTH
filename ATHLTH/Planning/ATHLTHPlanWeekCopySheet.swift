import SwiftUI

/// The confirmation is intentionally separate from the week timeline so
/// copying cannot happen by an accidental tap on a date or workout card.
struct ATHLTHPlanWeekCopySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore

    let planID: UUID
    let sourceWeekID: UUID
    @State private var destinationWeekID: UUID
    @State private var copyFailed = false

    init(plan: TrainingPlan, sourceWeekID: UUID) {
        planID = plan.id
        self.sourceWeekID = sourceWeekID
        let sourceNumber = plan.weeks.first {
            $0.id == sourceWeekID
        }?.weekNumber ?? 1
        let target = plan.weeks.first { $0.weekNumber > sourceNumber }
            ?? plan.weeks.first { $0.id != sourceWeekID }
        _destinationWeekID = State(
            initialValue: target?.id ?? sourceWeekID
        )
    }

    private var plan: TrainingPlan? {
        session.trainingPlan(withID: planID)
    }

    private var sourceWeek: TrainingPlanWeek? {
        plan?.weeks.first { $0.id == sourceWeekID }
    }

    private var targetWeeks: [TrainingPlanWeek] {
        guard let plan else { return [] }
        return plan.weeks.filter { week in
            guard week.id != sourceWeekID else { return false }
            return week.days.contains { day in
                guard let date = TrainingPlanSchedule.dayDate(
                    in: plan, week: week, day: day
                ) else { return false }
                return Calendar.current.startOfDay(for: date) >=
                    Calendar.current.startOfDay(for: Date())
            }
        }.sorted { $0.weekNumber < $1.weekNumber }
    }

    private var preview: ATHLTHPlanWeekCopy? {
        guard let plan else { return nil }
        return ATHLTHPlanWeekCopy(
            plan: plan,
            sourceWeekID: sourceWeekID,
            destinationWeekID: destinationWeekID,
            standaloneSessions: session.standalonePlannedSessions
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(ATHLTHLocalization.choose(
                            english: "COPY WEEK SAFELY",
                            norwegian: "KOPIER UKEN TRYGT"
                        ))
                        .font(.caption2.bold())
                        .tracking(1.4)
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                        Text(ATHLTHLocalization.choose(
                            english: "Only fill free days",
                            norwegian: "Fyll bare ledige dager"
                        ))
                        .font(.system(
                            size: 26, weight: .medium, design: .serif
                        ))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        Text(ATHLTHLocalization.choose(
                            english: "Your existing workouts, rest days and completed training stay unchanged.",
                            norwegian: "Eksisterende økter, hviledager og gjennomført trening beholdes uendret."
                        ))
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if targetWeeks.isEmpty {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "There are no future weeks to copy into. Add another week in the plan editor first.",
                                norwegian: "Det finnes ingen kommende uker å kopiere til. Legg til en uke i planredigeringen først."
                            ),
                            systemImage: "calendar.badge.exclamationmark"
                        )
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(ATHLTHLocalization.choose(
                                    english: "From",
                                    norwegian: "Fra"
                                ))
                                Spacer()
                                Text(ATHLTHLocalization.choose(
                                    english: "Week",
                                    norwegian: "Uke"
                                ) + " \(sourceWeek?.weekNumber ?? 1)")
                                .fontWeight(.semibold)
                            }
                            Picker(
                                ATHLTHLocalization.choose(
                                    english: "Copy into",
                                    norwegian: "Kopier til"
                                ),
                                selection: $destinationWeekID
                            ) {
                                ForEach(targetWeeks) { week in
                                    Text(ATHLTHLocalization.choose(
                                        english: "Week",
                                        norwegian: "Uke"
                                    ) + " \(week.weekNumber)")
                                    .tag(week.id)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        .padding(16)
                        .background(Color.white, in:
                            RoundedRectangle(cornerRadius: 20))

                        if let preview {
                            previewCard(preview)
                        }

                        if copyFailed {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "The plan changed or no free days remain. Review the preview again.",
                                    norwegian: "Planen er endret, eller ingen ledige dager gjenstår. Kontroller forhåndsvisningen igjen."
                                ),
                                systemImage: "exclamationmark.circle"
                            )
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                        }
                    }
                }
                .padding(18)
            }
            .background(ATHLTHTheme.canvasTop.ignoresSafeArea())
            .navigationTitle(ATHLTHLocalization.choose(
                english: "Copy week", norwegian: "Kopier uke"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if let preview, preview.copyCount > 0 {
                    Button {
                        let count = session.copyPlanWeekIntoFreeDays(
                            planID: planID,
                            sourceWeekID: sourceWeekID,
                            destinationWeekID: destinationWeekID,
                            expectedVersion: preview.expectedVersion
                        )
                        if count > 0 {
                            dismiss()
                        } else {
                            copyFailed = true
                        }
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Copy \(preview.copyCount) workouts",
                                norwegian: "Kopier \(preview.copyCount) økter"
                            ),
                            systemImage: "doc.on.doc"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(15)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.white)
                    .background(ATHLTHTheme.accentDeep, in:
                        RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(ATHLTHTheme.canvasTop)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Close", norwegian: "Lukk"
                    )) { dismiss() }
                }
            }
        }
    }

    private func previewCard(_ preview: ATHLTHPlanWeekCopy) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(ATHLTHLocalization.choose(
                    english: "PREVIEW", norwegian: "FORHÅNDSVISNING"
                ))
                .font(.caption2.bold())
                .tracking(1)
                Spacer()
                Text("\(preview.copyCount) " + ATHLTHLocalization.choose(
                    english: "workouts to copy",
                    norwegian: "økter å kopiere"
                ))
                .font(.caption.weight(.semibold))
            }
            .foregroundStyle(ATHLTHTheme.accentDeep)

            ForEach(preview.days) { day in
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: day.canCopy
                        ? "plus.circle.fill"
                        : day.reason == .sourceEmpty
                            ? "minus.circle"
                            : "lock.shield")
                    .foregroundStyle(day.canCopy
                        ? ATHLTHTheme.accentDeep
                        : ATHLTHTheme.mutedText)
                    .frame(width: 22)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(day.date.formatted(
                            .dateTime.weekday(.abbreviated).day()
                                .month(.abbreviated)
                        ))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.primaryText)

                        Text(day.canCopy
                            ? day.titles.joined(separator: " · ")
                            : reasonText(day.reason))
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                    Spacer(minLength: 0)
                }
                if day.id != preview.days.last?.id {
                    Divider()
                }
            }

            Text(ATHLTHLocalization.choose(
                english: "Copying creates new planned sessions with independent IDs. It never records a completed workout.",
                norwegian: "Kopiering oppretter nye planlagte økter med egne ID-er. Ingen trening blir registrert som gjennomført."
            ))
            .font(.caption2)
            .foregroundStyle(ATHLTHTheme.mutedText)
        }
        .padding(16)
        .background(Color.white, in:
            RoundedRectangle(cornerRadius: 20))
    }

    private func reasonText(_ reason: ATHLTHPlanWeekCopy.BlockReason?) -> String {
        switch reason {
        case .sourceEmpty:
            return ATHLTHLocalization.choose(
                english: "No workout in the source week",
                norwegian: "Ingen økt i uken det kopieres fra"
            )
        case .pastDate:
            return ATHLTHLocalization.choose(
                english: "Past date is protected",
                norwegian: "Tidligere dato beskyttes"
            )
        case .plannedRest:
            return ATHLTHLocalization.choose(
                english: "Planned rest day is protected",
                norwegian: "Planlagt hviledag beskyttes"
            )
        case .existingWorkout:
            return ATHLTHLocalization.choose(
                english: "Existing workout is protected",
                norwegian: "Eksisterende økt beskyttes"
            )
        case .standaloneWorkout:
            return ATHLTHLocalization.choose(
                english: "Standalone workout is protected",
                norwegian: "Frittstående økt beskyttes"
            )
        case nil:
            return ""
        }
    }
}

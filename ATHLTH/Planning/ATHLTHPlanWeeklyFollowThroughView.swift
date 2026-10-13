import SwiftUI

/// Transparently separates completed, skipped, upcoming and unreviewed past
/// workouts, without guessing completion or changing saved workouts.
struct ATHLTHPlanWeeklyFollowThroughView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore

    let plan: TrainingPlan
    let onSelect: (UUID, UUID?) -> Void
    @State private var showsAll = false
    @State private var showsSuggestionPreview = false

    var body: some View {
        let report = ATHLTHPlanWeeklyFollowThrough.inspect(
            plan: plan,
            store: session,
            healthWorkouts: health.workouts,
            strengthHistory: strength.workoutHistory
        )
        let relevant = report.relevantWeeks

        ATHLTHPlanSurface {
            VStack(alignment: .leading, spacing: 5) {
                Text("ATHLTH / WEEKLY REVIEW")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.8)
                    .foregroundStyle(ATHLTHPlanDesign.accent)

                Text(ATHLTHLocalization.choose(
                    english: "What happened this week?",
                    norwegian: "Hva har skjedd i treningsuken?"
                ))
                .font(.system(size: 23, weight: .semibold, design: .serif))
                .foregroundStyle(ATHLTHPlanDesign.ink)

                Text(ATHLTHLocalization.choose(
                    english: "Confirmed activity, skipped workouts and future sessions are separated. Past sessions without a recorded result are shown for review, not marked as failures.",
                    norwegian: "Fullførte økter, økter du har hoppet over og kommende økter holdes adskilt. Tidligere økter uten registrert resultat vises for gjennomgang, ikke som mislykkede."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            }

            if report.total == 0 {
                Label(
                    ATHLTHLocalization.choose(
                        english: "No planned workouts to review yet.",
                        norwegian: "Ingen planlagte økter å gjennomgå ennå."
                    ),
                    systemImage: "calendar"
                )
                .font(.subheadline)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            } else {
                VStack(alignment: .leading, spacing: 11) {
                    HStack(spacing: 13) {
                        metric(
                            report.completed,
                            label: ATHLTHLocalization.choose(
                                english: "Completed", norwegian: "Fullført"
                            )
                        )
                        metric(
                            report.upcoming,
                            label: ATHLTHLocalization.choose(
                                english: "Upcoming", norwegian: "Kommende"
                            )
                        )
                        metric(
                            report.needsReview,
                            label: ATHLTHLocalization.choose(
                                english: "Review", norwegian: "Gjennomgå"
                            )
                        )
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(
                        ATHLTHPlanDesign.selectedSurface,
                        in: RoundedRectangle(
                            cornerRadius: ATHLTHPlanDesign.fieldRadius
                        )
                    )

                    if let completedPercent = report.completionPercent,
                       let accountedPercent = report.accountedPercent {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(ATHLTHLocalization.choose(
                                english: "Completion: \(completedPercent)% · \(report.pastCompleted) of \(report.pastDated) past workouts",
                                norwegian: "Gjennomført: \(completedPercent) % · \(report.pastCompleted) av \(report.pastDated) tidligere økter"
                            ))
                            Text(ATHLTHLocalization.choose(
                                english: "Accounted for: \(accountedPercent)% · includes skipped workouts",
                                norwegian: "Avklart: \(accountedPercent) % · inkluderer økter hoppet over"
                            ))
                            Text(ATHLTHLocalization.choose(
                                english: "Unreviewed sessions are not assumed to be missed.",
                                norwegian: "Uavklarte økter regnes ikke automatisk som uteblitte."
                            ))
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        .fixedSize(horizontal: false, vertical: true)


                    }

                    if report.pastDated > 0 {
                        Text(ATHLTHLocalization.choose(
                            english: "Past workout breakdown: \(report.pastCompleted) completed · \(report.pastSkipped) skipped · \(report.pastUnreviewed) awaiting review. Skipped and unreviewed are different outcomes.",
                            norwegian: "Tidligere økter fordelt: \(report.pastCompleted) fullført · \(report.pastSkipped) hoppet over · \(report.pastUnreviewed) til gjennomgang. Hoppet over og uavklart er forskjellige resultater."
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    if let suggestion = report.reviewSuggestion {
                        VStack(alignment: .leading, spacing: 5) {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Suggested next step",
                                    norwegian: "Forslag til neste steg"
                                ),
                                systemImage: "lightbulb"
                            )
                            .font(.caption.weight(.semibold))
                            switch suggestion {
                            case .reviewUnresolved(let count):
                                Text(ATHLTHLocalization.choose(
                                    english: "\(count) past workouts have no recorded outcome. Review these sessions before adjusting your plan.",
                                    norwegian: "\(count) tidligere økter mangler registrert resultat. Gå gjennom øktene før du endrer planen."
                                ))
                            case .reviewSkipped(let count):
                                Text(ATHLTHLocalization.choose(
                                    english: "\(count) past workouts were marked skipped. Consider whether your schedule needs adjustment.",
                                    norwegian: "\(count) tidligere økter er markert som hoppet over. Vurder om treningsplanen bør tilpasses."
                                ))
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ATHLTHLocalization.choose(
                                    english: "Before → after review",
                                    norwegian: "Før → etter gjennomgang"
                                ))
                                .font(.caption.weight(.semibold))
                                Text(ATHLTHLocalization.choose(
                                    english: "Before: \(report.pastCompleted) completed · \(report.pastSkipped) skipped · \(report.pastUnreviewed) unresolved.",
                                    norwegian: "Før: \(report.pastCompleted) fullført · \(report.pastSkipped) hoppet over · \(report.pastUnreviewed) uavklart."
                                ))
                                Text(ATHLTHLocalization.choose(
                                    english: "After opening: unchanged until you explicitly edit a session.",
                                    norwegian: "Etter åpning: uendret til du selv redigerer en økt."
                                ))
                            }
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.ink)

                            Text(ATHLTHLocalization.choose(
                                english: "Only you can decide to change the plan. No changes are made automatically.",
                                norwegian: "Du bestemmer selv om planen skal endres. Ingenting endres automatisk."
                            ))
                            .font(.caption2)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

                            Button {
                                showsSuggestionPreview = true
                            } label: {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english: "Review suggestion",
                                        norwegian: "Se gjennom forslaget"
                                    ),
                                    systemImage: "arrow.up.right"
                                )
                            }
                            .buttonStyle(.bordered)
                            .confirmationDialog(
                                ATHLTHLocalization.choose(
                                    english: "Preview only — your plan will not change",
                                    norwegian: "Kun forhåndsvisning – planen endres ikke"
                                ),
                                isPresented: $showsSuggestionPreview,
                                titleVisibility: .visible
                            ) {
                                Button(ATHLTHLocalization.choose(
                                    english: "Open relevant week",
                                    norwegian: "Åpne aktuell uke"
                                )) {
                                    let matching = report.relevantWeeks.first {
                                        switch suggestion {
                                        case .reviewUnresolved: return $0.needsReview > 0
                                        case .reviewSkipped: return $0.pastSkipped > 0
                                        }
                                    }
                                    if let matching {
                                        onSelect(matching.id, matching.firstReviewDayID)
                                    }
                                }
                                Button(ATHLTHLocalization.choose(
                                    english: "Cancel", norwegian: "Avbryt"
                                ), role: .cancel) { }
                            } message: {
                                Text(ATHLTHLocalization.choose(
                                    english: "You can inspect the recorded sessions in the existing plan editor. No workout will be moved, skipped or overwritten.",
                                    norwegian: "Du kan kontrollere de registrerte øktene i den eksisterende planredigeringen. Ingen økter flyttes, hoppes over eller overskrives."
                                ))
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    if let trend = report.completedWeekTrend {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Completed weeks W\(trend.previous.number) → W\(trend.latest.number): \(trend.delta > 0 ? "+" : "")\(trend.delta) percentage points in completion. This describes recorded outcomes, not fitness progress.",
                                norwegian: "Avsluttede uker U\(trend.previous.number) → U\(trend.latest.number): \(trend.delta > 0 ? "+" : "")\(trend.delta) prosentpoeng i gjennomføring. Dette viser registrerte resultater, ikke formutvikling."
                            ),
                            systemImage: "chart.line.uptrend.xyaxis"
                        )
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        .fixedSize(horizontal: false, vertical: true)

                        Text(ATHLTHLocalization.choose(
                            english: "Recorded change: completed \(trend.latest.pastCompleted - trend.previous.pastCompleted >= 0 ? "+" : "")\(trend.latest.pastCompleted - trend.previous.pastCompleted), skipped \(trend.latest.pastSkipped - trend.previous.pastSkipped >= 0 ? "+" : "")\(trend.latest.pastSkipped - trend.previous.pastSkipped), unreviewed \(trend.latest.pastUnreviewed - trend.previous.pastUnreviewed >= 0 ? "+" : "")\(trend.latest.pastUnreviewed - trend.previous.pastUnreviewed). Counts are not normalized for weekly plan size.",
                            norwegian: "Registrert endring: fullført \(trend.latest.pastCompleted - trend.previous.pastCompleted >= 0 ? "+" : "")\(trend.latest.pastCompleted - trend.previous.pastCompleted), hoppet over \(trend.latest.pastSkipped - trend.previous.pastSkipped >= 0 ? "+" : "")\(trend.latest.pastSkipped - trend.previous.pastSkipped), uavklart \(trend.latest.pastUnreviewed - trend.previous.pastUnreviewed >= 0 ? "+" : "")\(trend.latest.pastUnreviewed - trend.previous.pastUnreviewed). Antall er ikke justert for ulikt antall planlagte økter."
                        ))
                        .font(.caption2)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    if report.pastDated > 0 {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Past workouts accounted for: \(report.pastConfirmed) of \(report.pastDated) · includes completed and skipped.",
                                norwegian: "Tidligere økter avklart: \(report.pastConfirmed) av \(report.pastDated) · inkluderer fullførte og hoppet over."
                            ),
                            systemImage: "checkmark.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(ATHLTHLocalization.choose(
                        english: "\(report.skipped) skipped · \(report.unknownDate) without plan dates. Today's unfinished sessions are still upcoming.",
                        norwegian: "\(report.skipped) hoppet over · \(report.unknownDate) uten plandato. Dagens ufullførte økter regnes fortsatt som kommende."
                    ))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)

                    if report.needsReview > 0 {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "\(report.needsReview) past sessions have no confirmed result. Review these days to decide whether a recording needs linking or the plan needs updating.",
                                norwegian: "\(report.needsReview) tidligere økter mangler bekreftet resultat. Gå gjennom dagene for å se om en registrering må kobles eller planen bør oppdateres."
                            ),
                            systemImage: "info.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    ForEach(Array(relevant.prefix(
                        showsAll ? relevant.count : 4
                    ))) { week in
                        Button {
                            onSelect(week.id, week.firstReviewDayID)
                        } label: {
                            HStack(spacing: 12) {
                                Text(ATHLTHLocalization.choose(
                                    english: "W\(week.number)",
                                    norwegian: "U\(week.number)"
                                ))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(ATHLTHPlanDesign.ink)
                                .frame(width: 40, alignment: .leading)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(ATHLTHLocalization.choose(
                                        english: "\(week.completed) completed · \(week.upcoming) upcoming",
                                        norwegian: "\(week.completed) fullført · \(week.upcoming) kommende"
                                    ))
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(ATHLTHPlanDesign.ink)

                                    if week.needsReview > 0 {
                                        Text(ATHLTHLocalization.choose(
                                            english: "\(week.needsReview) to review · open related day",
                                            norwegian: "\(week.needsReview) til gjennomgang · åpne dagen"
                                        ))
                                        .font(.caption)
                                        .foregroundStyle(ATHLTHTheme.accentDeep)
                                    } else {
                                        Text(ATHLTHLocalization.choose(
                                            english: "\(week.skipped) skipped · \(week.unknownDate) undated",
                                            norwegian: "\(week.skipped) hoppet over · \(week.unknownDate) uten dato"
                                        ))
                                        .font(.caption2)
                                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                    }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                    .accessibilityHidden(true)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(ATHLTHLocalization.choose(
                            english: "Open this week or a past workout day to review, without changing the plan.",
                            norwegian: "Åpne uken eller en tidligere økt til gjennomgang, uten å endre planen."
                        ))
                    }

                    if relevant.count > 4 {
                        Button {
                            showsAll.toggle()
                        } label: {
                            Label(
                                showsAll
                                    ? ATHLTHLocalization.choose(
                                        english: "Show fewer weeks",
                                        norwegian: "Vis færre uker"
                                    )
                                    : ATHLTHLocalization.choose(
                                        english: "Show all \(relevant.count) weeks",
                                        norwegian: "Vis alle \(relevant.count) uker"
                                    ),
                                systemImage: showsAll
                                    ? "chevron.up" : "chevron.down"
                            )
                        }
                        .font(.subheadline.weight(.medium))
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private func metric(_ number: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(number)")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ATHLTHPlanDesign.ink)
            Text(label)
                .font(.caption2)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
        }
        .accessibilityElement(children: .combine)
    }
}

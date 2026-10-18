import SwiftUI

/// Two presentations of the same dated training-plan model, not two engines.
enum ATHLTHPlanWeekPlanningApproach: String, Codable {
    case quick
    case guided
}

struct ATHLTHPlanWeekApproachCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                    .frame(width: 48, height: 48)
                    .background(ATHLTHPlanDesign.selectedSurface,
                                in: RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 19, weight: .semibold, design: .serif))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 2)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
            .athlthPlanCard(radius: 22)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title + ". " + subtitle)
    }
}

/// Pick a whole workout recipe, never a lone exercise.
struct ATHLTHPlanWorkoutLibraryPicker: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var runningLibrary: RunningWorkoutLibraryStore
    @StateObject private var catalog = WorkoutTemplateCatalogStore()
    @State private var query = ""
    let onSelect: (PlannedSession) -> Void

    private var hasMatchingWorkouts: Bool {
        session.savedWorkoutTemplates.contains { matches($0.title) }
            || runningLibrary.allTemplates.contains { matches($0.title) }
            || catalog.entries.contains { matches($0.title) }
    }

    private func matches(_ title: String) -> Bool {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty || title.localizedCaseInsensitiveContains(clean)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ATHLTHPlanSectionIntro(
                        eyebrow: ATHLTHLocalization.choose(
                            english: "YOUR WORKOUT LIBRARY", norwegian: "DITT ØKTBIBLIOTEK"
                        ),
                        title: ATHLTHLocalization.choose(
                            english: "Choose a complete workout",
                            norwegian: "Velg en komplett treningsøkt"
                        ),
                        subtitle: ATHLTHLocalization.choose(
                            english: "Copy all exercises, sets, intervals and recovery into the selected date.",
                            norwegian: "Kopier alle øvelser, sett, intervaller og pauser til den valgte dagen."
                        ),
                        icon: "books.vertical"
                    )

                    TextField(ATHLTHLocalization.choose(
                        english: "Search workouts", norwegian: "Søk etter treningsøkter"
                    ), text: $query)
                        .textFieldStyle(.roundedBorder)

                    if !session.savedWorkoutTemplates.isEmpty {
                        sectionHeading(ATHLTHLocalization.choose(
                            english: "Your saved workouts", norwegian: "Dine lagrede treningsøkter"
                        ))
                        ForEach(session.savedWorkoutTemplates.filter { matches($0.title) }) { workout in
                            workoutButton(workout, subtitle:
                                "\(ATHLTHUnifiedWorkout.editorBlocks(from: workout).count) " +
                                ATHLTHLocalization.choose(english: "steps", norwegian: "deler"))
                        }
                    }

                    let builtInRuns = runningLibrary.allTemplates.filter {
                        $0.isBuiltIn && matches($0.title)
                    }
                    if !builtInRuns.isEmpty {
                        sectionHeading(ATHLTHLocalization.choose(
                            english: "Ready-made running workouts",
                            norwegian: "Ferdige løpeøkter"
                        ))
                        ForEach(builtInRuns) { run in
                            workoutButton(run.plannedSession(), subtitle: run.summary)
                        }
                    }

                    let customRuns = runningLibrary.customTemplates.filter { matches($0.title) }
                    if !customRuns.isEmpty {
                        sectionHeading(ATHLTHLocalization.choose(
                            english: "Saved runs", norwegian: "Lagrede løpeøkter"
                        ))
                        ForEach(customRuns) { run in
                            workoutButton(run.plannedSession(), subtitle: run.summary)
                        }
                    }

                    let catalogItems = catalog.entries.filter { matches($0.title) }
                    if !catalogItems.isEmpty {
                        sectionHeading(ATHLTHLocalization.choose(
                            english: "Workout library", norwegian: "Treningsbibliotek"
                        ))
                        ForEach(catalogItems) { item in
                            workoutButton(item.plannedSession(), subtitle: item.summary)
                        }
                    }

                    if !hasMatchingWorkouts {
                        VStack(spacing: 9) {
                            Image(systemName: "rectangle.stack")
                                .font(.system(size: 27, weight: .medium))
                                .foregroundStyle(ATHLTHPlanDesign.ink)
                            Text(ATHLTHLocalization.choose(
                                english: "No workouts found", norwegian: "Ingen treningsøkter funnet"
                            ))
                            .font(.headline)
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                            Text(ATHLTHLocalization.choose(
                                english: "Try a different search, or build a workout on the selected day.",
                                norwegian: "Prøv et annet søk, eller bygg en økt på den valgte dagen."
                            ))
                            .font(.subheadline)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 170)
                        .padding(18)
                        .athlthPlanCard(radius: 22)
                    }
                }
                .padding(18)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(ATHLTHLocalization.choose(
                english: "Workout library", norwegian: "Øktbibliotek"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(english: "Cancel", norwegian: "Avbryt")) {
                        dismiss()
                    }
                }
            }
            .task { await catalog.refresh() }
        }
    }

    private func sectionHeading(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(1.2)
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            .padding(.top, 8)
    }

    private func workoutButton(_ workout: PlannedSession, subtitle: String) -> some View {
        Button {
            onSelect(workout)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: workout.kind.systemImage)
                    .font(.title3)
                    .frame(width: 42, height: 42)
                    .background(ATHLTHPlanDesign.selectedSurface,
                                in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text(workout.title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .lineLimit(2)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
                Spacer()
                Image(systemName: "plus.circle")
            }
            .foregroundStyle(ATHLTHPlanDesign.ink)
            .padding(14)
            .frame(minHeight: ATHLTHPlanDesign.minTapHeight)
            .athlthPlanCard(radius: 18)
        }
        .buttonStyle(.plain)
    }


}

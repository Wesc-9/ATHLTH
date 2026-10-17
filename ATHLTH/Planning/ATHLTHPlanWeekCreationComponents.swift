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

    private func matches(_ title: String) -> Bool {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty || title.localizedCaseInsensitiveContains(clean)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    Text(ATHLTHLocalization.choose(
                        english: "Choose a complete workout",
                        norwegian: "Velg en komplett treningsøkt"
                    ))
                    .font(.system(size: 28, weight: .semibold, design: .serif))
                    .foregroundStyle(ATHLTHPlanDesign.ink)

                    Text(ATHLTHLocalization.choose(
                        english: "All exercises, sets, running intervals and rests are copied into your planned day.",
                        norwegian: "Alle øvelser, sett, løpeintervaller og pauser kopieres inn i dagen."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

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

                    if !runningLibrary.customTemplates.isEmpty {
                        sectionHeading(ATHLTHLocalization.choose(
                            english: "Saved runs", norwegian: "Lagrede løpeøkter"
                        ))
                        ForEach(runningLibrary.customTemplates.filter { matches($0.title) }) { run in
                            let workout = makeRunningWorkout(run)
                            workoutButton(workout, subtitle:
                                "\(run.blocks.count) " +
                                ATHLTHLocalization.choose(english: "interval blocks", norwegian: "intervallblokker"))
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

    private func makeRunningWorkout(_ run: RunningWorkoutTemplate) -> PlannedSession {
        var workout = PlannedSession(
            id: UUID(), title: run.title, kind: .running, scheduledStart: nil,
            durationMinutes: run.estimatedDurationSeconds.map { Int(ceil($0 / 60)) },
            targetDistanceKilometers: nil, targetPaceSecondsPerKilometer: nil,
            routeID: run.routeID, exercises: [], notes: nil
        )
        workout.runningWorkout = run
        return workout
    }
}

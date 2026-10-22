import SwiftUI

/// Appends an entire saved workout or running interval program into the
/// existing strength recording. A different HealthKit session is never started.
struct ActiveHybridWorkoutPicker: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var runningLibrary: RunningWorkoutLibraryStore

    var runningOnly = false
    let onAppend: (PlannedSession, Bool) -> Bool

    @State private var unsupportedMessage: String?

    private var plannedWorkouts: [PlannedSession] {
        let all = session.trainingPlans.flatMap { plan in
            plan.weeks.flatMap { week in
                week.days.flatMap(\.sessions)
            }
        }
        var seen = Set<UUID>()
        return all.filter {
            seen.insert($0.id).inserted &&
            (!runningOnly || $0.runningWorkout != nil) &&
            !$0.isExplicitRestDay &&
            (!$0.exercises.isEmpty ||
             !$0.resolvedWorkoutBlocks.isEmpty ||
             !$0.resolvedRunningWorkouts.isEmpty ||
             $0.kind == .running)
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private var treadmillTemplates: [RunningWorkoutTemplate] {
        runningLibrary.allTemplates.filter { template in
            let runSteps = ATHLTHUnifiedWorkout
                .editorBlocks(from: makeRunningSession(template))
                .filter { $0.kind == .run || $0.kind == .rest }
            return runSteps.contains(where: { $0.kind == .run }) &&
                runSteps.allSatisfy {
                    $0.durationSeconds.map {
                        $0.isFinite && (15...7_200).contains($0)
                    } == true
                }
        }
    }

    private func makeRunningSession(
        _ template: RunningWorkoutTemplate
    ) -> PlannedSession {
        PlannedSession(
            id: UUID(),
            title: template.title,
            kind: .running,
            scheduledStart: nil,
            durationMinutes: nil,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes: template.summary,
            runningWorkout: template
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "figure.run.square.stack.fill")
                            .font(.title2)
                            .foregroundStyle(ATHLTHTheme.premiumGold)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ATHLTHLocalization.choose(
                                english: runningOnly
                                    ? "Add intervals, keep your recording"
                                    : "One recording, multiple workout parts",
                                norwegian: runningOnly
                                    ? "Legg til intervaller i samme økt"
                                    : "Én registrering, flere treningsdeler"
                            ))
                            .font(.subheadline.weight(.semibold))
                            Text(ATHLTHLocalization.choose(
                                english: runningOnly
                                    ? "Append a running interval program without stopping your current Apple Watch or iPhone recording."
                                    : "Add a saved session or a treadmill interval. Existing sets and Apple Watch measurements are preserved.",
                                norwegian: runningOnly
                                    ? "Legg til en intervalløkt uten å stoppe det pågående opptaket fra Apple Watch eller iPhone."
                                    : "Legg til en lagret økt eller mølleintervaller. Settene og Apple Watch-målingene beholdes."
                            ))
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            Text(ATHLTHLocalization.choose(
                                english: runningOnly
                                    ? "If intervals are in progress, queue the next program rather than restarting the current one."
                                    : "Starting another part saves elapsed time in any active timed set. Existing completed sets and the Watch recording stay intact.",
                                norwegian: runningOnly
                                    ? "Hvis intervaller allerede pågår, legger du neste program i kø i stedet for å avbryte det aktive."
                                    : "Starter du en annen del, lagres faktisk tid i et pågående tidssett. Ferdige sett og klokkeopptaket beholdes."
                            ))
                            .font(.caption2)
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 7)
                }

                Section(ATHLTHLocalization.choose(
                    english: "Treadmill intervals", norwegian: "Intervaller på mølle"
                )) {
                    ForEach(treadmillTemplates) { template in
                        workoutRow(
                            title: template.title,
                            subtitle: template.summary,
                            symbol: "figure.run",
                            duration: nil
                        ) { startNow in
                            append(
                                makeRunningSession(template),
                                startNow: startNow
                            )
                        }
                    }
                }

                if !plannedWorkouts.isEmpty {
                    Section(ATHLTHLocalization.choose(
                        english: "Saved training sessions",
                        norwegian: "Lagrede treningsøkter"
                    )) {
                        ForEach(plannedWorkouts) { workout in
                            workoutRow(
                                title: workout.title,
                                subtitle: workout.kind.title,
                                symbol: workout.exercises.isEmpty
                                    ? "figure.run" : "dumbbell.fill",
                                duration: workout.durationMinutes
                            ) { startNow in
                                append(workout, startNow: startNow)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(ATHLTHLocalization.choose(
                english: "Add workout", norwegian: "Legg til treningsøkt"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(ATHLTHLocalization.choose(
                        english: "Done", norwegian: "Ferdig"
                    )) { dismiss() }
                }
            }
            .alert(
                ATHLTHLocalization.choose(
                    english: "Workout could not be added",
                    norwegian: "Kunne ikke legge til økten"
                ),
                isPresented: Binding(
                    get: { unsupportedMessage != nil },
                    set: { if !$0 { unsupportedMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { unsupportedMessage = nil }
            } message: {
                Text(unsupportedMessage ?? "")
            }
        }
    }

    private func append(_ planned: PlannedSession, startNow: Bool) {
        if onAppend(planned, startNow) {
            dismiss()
        } else {
            unsupportedMessage = ATHLTHLocalization.choose(
                english: runningOnly
                    ? "This interval could not be added right now. If another interval is running, choose Queue. If no interval is running, choose Start this part. Strength additions require the hybrid strength session."
                    : "This workout has no supported exercises or time-based running phases. Distance-only GPS workouts need a separate outdoor recording.",
                norwegian: runningOnly
                    ? "Intervalløkten kunne ikke legges til nå. Hvis et intervall pågår, velg Legg til senere. Ellers velger du Start denne delen. Styrkedeler må legges til fra hybrid styrkeøkt."
                    : "Økten har ingen støttede øvelser eller tidsstyrte løpefaser. Distansebasert GPS-løping må fortsatt registreres separat."
            )
        }
    }

    private func workoutRow(
        title: String,
        subtitle: String,
        symbol: String,
        duration: Int?,
        action: @escaping (Bool) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(ATHLTHTheme.premiumGold)
                    .frame(width: 43, height: 43)
                    .background(ATHLTHTheme.champagneSoft, in:
                        RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        .lineLimit(2)
                    if let duration {
                        Label("\(duration) min", systemImage: "clock")
                            .font(.caption2)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Button {
                    action(true)
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Start this part", norwegian: "Start denne delen"
                    ), systemImage: "play.fill")
                        .frame(maxWidth: .infinity, minHeight: 41)
                }
                .buttonStyle(.plain)
                .foregroundStyle(ATHLTHTheme.primaryText)
                .background(ATHLTHTheme.champagne, in: Capsule())

                Button {
                    action(false)
                } label: {
                    Text(ATHLTHLocalization.choose(
                        english: "Queue", norwegian: "Legg til senere"
                    ))
                    .frame(maxWidth: .infinity, minHeight: 41)
                }
                .buttonStyle(.plain)
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                .background(ATHLTHPlanDesign.warmSurface, in: Capsule())
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.vertical, 6)
    }
}

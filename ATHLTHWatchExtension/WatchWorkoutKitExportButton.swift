import SwiftUI
import HealthKit
import WorkoutKit

/// Opening the system Workout app is a deliberate external handoff,
/// not an ATHLTH start, receipt or completed calendar session.
struct WatchWorkoutKitExportButton: View {
    let recipe: WatchPreparedWorkoutTransfer
    let canOpen: () -> Bool
    @State private var confirming = false
    @State private var opening = false
    @State private var failed = false

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        Button {
            confirming = true
        } label: {
            Label(tr("Open in Apple Workout", "Åpne i Apple Trening"), systemImage: "figure.run.circle")
                .font(.caption2)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(opening || !canOpen())
        .confirmationDialog(tr("Use Apple Workout?", "Bruke Apple Trening?"), isPresented: $confirming, titleVisibility: .visible) {
            Button(tr("Open workout", "Åpne økt")) {
                guard canOpen(), !opening, let plan = makePlan() else { failed = true; return }
                opening = true
                Task { @MainActor in
                    defer { opening = false }
                    guard canOpen() else { failed = true; return }
                    do { try await plan.openInWorkoutApp() }
                    catch { failed = true }
                }
            }
            Button(tr("Cancel", "Avbryt"), role: .cancel) {}
        } message: {
            Text(tr("Apple records a separate workout. ATHLTH Coach, live sharing and app-specific guidance are not included. Import the result through your normal Apple Health inbox; your ATHLTH plan is not marked complete automatically.", "Apple registrerer en separat økt. ATHLTH Coach, live-deling og appens egne veiledninger følger ikke med. Importer resultatet via vanlig Apple Helse-innboks. ATHLTH-planen markeres ikke automatisk som fullført."))
        }
        .alert(tr("Could not open Apple Workout", "Kunne ikke åpne Apple Trening"), isPresented: $failed) {
            Button("OK", role: .cancel) {}
        }
    }

    private func makePlan() -> WorkoutPlan? {
        guard ATHLTHWorkoutKitExportPolicy.canExport(recipe),
              let source = recipe.runningWorkout else { return nil }
        var warmup: WorkoutStep?
        var cooldown: WorkoutStep?
        var main: [IntervalStep] = []
        for step in source.steps {
            let goal: WorkoutGoal
            switch step.measure {
            case .open: goal = .open
            case .time:
                guard let seconds = step.durationSeconds else { return nil }
                goal = .time(seconds, .seconds)
            case .distance:
                guard let meters = step.distanceMeters else { return nil }
                goal = .distance(meters, .meters)
            }
            let item = WorkoutStep(goal: goal, alert: nil, displayName: String(step.title.prefix(80)))
            switch step.phase?.lowercased() {
            case "warmup": warmup = item
            case "cooldown": cooldown = item
            case "recovery", "rest", "activerecovery": main.append(IntervalStep(.recovery, step: item))
            default: main.append(IntervalStep(.work, step: item))
            }
        }
        guard !main.isEmpty else { return nil }
        let activity: HKWorkoutActivityType = recipe.kind == .walking ? .walking : .running
        let location: HKWorkoutSessionLocationType = recipe.indoor == true ? .indoor : .outdoor
        let workout = CustomWorkout(activity: activity, location: location,
            displayName: String(recipe.title.prefix(80)), warmup: warmup,
            blocks: [IntervalBlock(steps: main, iterations: 1)], cooldown: cooldown)
        // Independent export identity; do not fabricate original completion
        // evidence or pass an ATHLTH planned session identifier to Apple.
        return WorkoutPlan(.custom(workout), id: UUID())
    }
}

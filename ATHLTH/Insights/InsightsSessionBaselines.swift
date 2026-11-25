import SwiftUI
import UIKit

/// Immutable O(n) session averages. Recomputed on published Health workouts,
/// not on scroll/layout passes of the simulator card.
struct InsightsSessionBaselines: Equatable {
    let allSessionMinutes: Double?
    let runningSessionMinutes: Double?
    let strengthSessionMinutes: Double?
    let walkingSessionMinutes: Double?
    let allWeeklyMinutes: Double?
    let runningWeeklyMinutes: Double?
    let strengthWeeklyMinutes: Double?
    let walkingWeeklyMinutes: Double?
    let allWeeklySessions: Double?
    let runningWeeklySessions: Double?
    let strengthWeeklySessions: Double?
    let walkingWeeklySessions: Double?

    static let empty = InsightsSessionBaselines(
        allSessionMinutes: nil,
        runningSessionMinutes: nil,
        strengthSessionMinutes: nil,
        walkingSessionMinutes: nil,
        allWeeklyMinutes: nil,
        runningWeeklyMinutes: nil,
        strengthWeeklyMinutes: nil,
        walkingWeeklyMinutes: nil,
        allWeeklySessions: nil,
        runningWeeklySessions: nil,
        strengthWeeklySessions: nil,
        walkingWeeklySessions: nil
    )

    static func calculate(
        workouts: [WorkoutSummary],
        at date: Date,
        calendar: Calendar = .current
    ) -> InsightsSessionBaselines {
        let cutoff = calendar.date(byAdding: .day, value: -28, to: date)
            ?? date.addingTimeInterval(-2_419_200)

        var allTotal = 0.0
        var allCount = 0
        var runningTotal = 0.0
        var runningCount = 0
        var strengthTotal = 0.0
        var strengthCount = 0
        var walkingTotal = 0.0
        var walkingCount = 0

        for workout in workouts {
            guard workout.startDate >= cutoff,
                  workout.startDate <= date,
                  workout.duration.isFinite,
                  workout.duration > 0 else {
                continue
            }

            let minutes = workout.duration / 60
            allCount += 1
            allTotal += minutes
            if workout.activity == .running {
                runningCount += 1
                runningTotal += minutes
            } else if workout.activity == .strength {
                strengthCount += 1
                strengthTotal += minutes
            } else if workout.activity == .walking {
                walkingCount += 1
                walkingTotal += minutes
            }
        }

        // Four complete weeks of history, not the current calendar week.
        // Keep unavailable history nil: never invent a 45-minute baseline.
        return InsightsSessionBaselines(
            allSessionMinutes: allCount > 0
                ? allTotal / Double(allCount) : nil,
            runningSessionMinutes: runningCount > 0
                ? runningTotal / Double(runningCount) : nil,
            strengthSessionMinutes: strengthCount > 0
                ? strengthTotal / Double(strengthCount) : nil,
            walkingSessionMinutes: walkingCount > 0
                ? walkingTotal / Double(walkingCount) : nil,
            allWeeklyMinutes: allCount > 0 ? allTotal / 4 : nil,
            runningWeeklyMinutes: runningCount > 0 ? runningTotal / 4 : nil,
            strengthWeeklyMinutes: strengthCount > 0 ? strengthTotal / 4 : nil,
            walkingWeeklyMinutes: walkingCount > 0 ? walkingTotal / 4 : nil,
            allWeeklySessions: allCount > 0 ? Double(allCount) / 4 : nil,
            runningWeeklySessions: runningCount > 0
                ? Double(runningCount) / 4 : nil,
            strengthWeeklySessions: strengthCount > 0
                ? Double(strengthCount) / 4 : nil,
            walkingWeeklySessions: walkingCount > 0
                ? Double(walkingCount) / 4 : nil
        )
    }
}

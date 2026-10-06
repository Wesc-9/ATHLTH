import Foundation

struct AthleteRace: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var date: Date
    var distanceKM: Double
    var goal: String

    func phase(at now: Date, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        if days > 14 { return "Preparation" }
        if days > 0 { return "Taper" }
        if days == 0 { return "Race day" }
        return days >= -7 ? "Recovery" : "Completed"
    }
    var adaptationNotes: String {
        "Prepare my plan for \(name) on \(date.formatted(date: .complete, time: .omitted)), \(distanceKM) km. Goal: \(goal). Include a suitable taper and recovery, and preserve unrelated sessions."
    }
}

struct AthleteFuelPlan: Codable, Hashable {
    var durationMinutes = 120
    var intervalMinutes = 20
    var carbohydrateGramsPerHour = 45
    var fluidMLPerHour = 500

    var valid: Bool {
        (30...480).contains(durationMinutes) && (10...60).contains(intervalMinutes)
            && (0...120).contains(carbohydrateGramsPerHour) && (0...1500).contains(fluidMLPerHour)
    }
    var reminderOffsets: [Int] {
        guard valid else { return [] }
        return Array(stride(from: intervalMinutes, to: durationMinutes, by: intervalMinutes))
    }
    var gramsPerReminder: Double { Double(carbohydrateGramsPerHour * intervalMinutes) / 60 }
    var fluidPerReminder: Double { Double(fluidMLPerHour * intervalMinutes) / 60 }
}

struct AthleteCycleEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    var energy: Int
    var symptoms: String
    var notes: String
}

struct AthleteGearService: Identifiable, Codable, Hashable {
    var id = UUID()
    var gearID: UUID
    var date: Date
    var odometerKM: Double
    var note: String
}
struct AthleteGearRule: Codable, Hashable {
    var intervalKM: Double
    var baselineKM: Double = 0
    var notifications = false
    var notified = false
    func remaining(at totalKM: Double) -> Double { intervalKM - max(0, totalKM - baselineKM) }
}
struct AthleteToolsData: Codable {
    var races: [AthleteRace] = []
    var fuel = AthleteFuelPlan()
    var gearRules: [UUID: AthleteGearRule] = [:]
    var services: [AthleteGearService] = []
    var loadNotifications = false
    var lastLoadWarning: Date?
    var fuelEndsAt: Date? = nil
}

struct AthleteLoadSample: Hashable {
    var date: Date
    var minutes: Double
    var effort: Double
    var load: Double { max(0, minutes) * min(10, max(1, effort)) }
}
struct AthleteLoadAssessment: Hashable {
    var current: Double
    var baseline: Double
    var hasBaseline: Bool
    var lowRecovery: Bool
    var ratio: Double? { hasBaseline && baseline > 0 ? current / baseline : nil }
    var shouldWarn: Bool { (ratio ?? 0) >= 1.3 || (lowRecovery && current > baseline && hasBaseline) }
}
enum AthleteLoadEngine {
    static func assess(_ samples: [AthleteLoadSample], recoveryScore: Int?, now: Date = Date()) -> AthleteLoadAssessment {
        let cutoff = now.addingTimeInterval(-28 * 86_400)
        let week = now.addingTimeInterval(-7 * 86_400)
        let relevant = samples.filter { $0.date > cutoff && $0.date <= now && $0.minutes.isFinite && $0.effort.isFinite }
        let current = relevant.filter { $0.date > week }.reduce(0) { $0 + $1.load }
        let older = relevant.filter { $0.date <= week }
        // Require observations in each of the previous three weeks.
        let hasBaseline = (1...3).allSatisfy { index in
            let lower = now.addingTimeInterval(-Double((index + 1) * 7) * 86_400)
            let upper = now.addingTimeInterval(-Double(index * 7) * 86_400)
            return older.contains { $0.date > lower && $0.date <= upper }
        }
        return AthleteLoadAssessment(current: current, baseline: older.reduce(0) { $0 + $1.load } / 3,
                                     hasBaseline: hasBaseline, lowRecovery: (recoveryScore ?? 100) < 45)
    }
}

enum AthleteStrengthProgression {
    static func suggestion(
        sets: [StrengthSetLog],
        targetReps: Int
    ) -> StrengthProgressionSuggestion? {
        let working =
            sets.compactMap {
                set -> StrengthSetLog? in

                guard
                    set.countsTowardTrainingLoad,
                    set.resolvedTargetKind != .time,
                    set.resolvedLoadKind ==
                        .weightKilograms
                else {
                    return nil
                }

                var result = set

                if let segments =
                        set.effortSegments,
                   !segments.isEmpty {
                    // A lighter drop-set segment cannot complete the rep
                    // target at the heavier load. Use the strongest segment.
                    let valid =
                        segments.filter {
                            ($0.reps ?? 0) > 0 &&
                            ($0.weightKilograms ?? 0) >
                                0
                        }

                    guard let strongest =
                            valid.max(
                                by: {
                                    lhs,
                                    rhs in

                                    if lhs
                                        .weightKilograms ==
                                        rhs
                                        .weightKilograms {
                                        return
                                            (lhs.reps ??
                                                0) <
                                            (rhs.reps ??
                                                0)
                                    }

                                    return
                                        (lhs
                                            .weightKilograms ??
                                            0) <
                                        (rhs
                                            .weightKilograms ??
                                            0)
                                }
                            )
                    else {
                        return nil
                    }

                    result.completedReps =
                        strongest.reps
                    result
                        .completedWeightKilograms =
                        strongest
                            .weightKilograms
                }

                guard
                    (result.completedReps ?? 0) >
                        0,
                    (result
                        .completedWeightKilograms ??
                        0) > 0
                else {
                    return nil
                }

                return result
            }

        guard
            targetReps > 0,
            let last = working.last,
            let weight =
                last.completedWeightKilograms,
            weight.isFinite,
            let reps = last.completedReps
        else {
            return nil
        }

        let metTarget =
            working.allSatisfy {
                ($0.completedReps ?? 0) >=
                    targetReps
            }
        let excessive =
            working.contains {
                ($0.rpe ?? 0) >= 9.5 ||
                ($0.rir ?? 10) <= 0
            }
        let missingEffort =
            working.contains {
                $0.rpe == nil &&
                $0.rir == nil
            }
        let ready =
            working.allSatisfy {
                ($0.rpe ?? 0) <= 8 &&
                ($0.rir ?? 10) >= 2
            }

        let increment =
            weight >= 100
                ? 5.0
                : 2.5
        let suggested: Double
        let reason: String

        if excessive && !metTarget {
            suggested =
                max(
                    0.5,
                    (
                        weight *
                        0.95 *
                        2
                    )
                    .rounded() /
                    2
                )
            reason =
                ATHLTHLocalization.choose(
                    english:
                        "The target was missed at very high effort. A small reduction may be smarter today.",
                    norwegian:
                        "Målet ble bommet med svært høy innsats. En liten reduksjon kan være smartere i dag."
                )
        } else if metTarget &&
                    ready &&
                    !missingEffort {
            suggested =
                weight + increment
            reason =
                ATHLTHLocalization.choose(
                    english:
                        "All working sets hit the target with effort in reserve.",
                    norwegian:
                        "Alle arbeidssettene traff målet med litt kapasitet igjen."
                )
        } else {
            suggested = weight
            reason =
                missingEffort
                    ? ATHLTHLocalization.choose(
                        english:
                            "Add RPE or RIR for a safer progression signal. Keep this load for now.",
                        norwegian:
                            "Legg inn RPE eller RIR for et sikrere progresjonssignal. Behold belastningen foreløpig."
                    )
                    : ATHLTHLocalization.choose(
                        english:
                            "Repeat this load until the target feels controlled with effort in reserve.",
                        norwegian:
                            "Gjenta denne belastningen til målet kjennes kontrollert med litt kapasitet igjen."
                    )
        }

        return StrengthProgressionSuggestion(
            previousWeightKilograms:
                weight,
            previousReps: reps,
            suggestedWeightKilograms:
                suggested,
            suggestedReps: targetReps,
            reason: reason
        )
    }

    /// Classifies a small recent window. Suggestions must be newest first.
    /// The latest session remains authoritative; older sessions only add
    /// confidence/context and never force a larger jump.
    static func recentTrend(
        suggestions:
            [StrengthProgressionSuggestion]
    ) -> StrengthProgressionRecentTrend? {
        guard suggestions.count >= 2,
              let latest =
                suggestions.first
        else {
            return nil
        }

        let total =
            suggestions.count
        let delta =
            latest
                .suggestedWeightKilograms -
            latest
                .previousWeightKilograms

        if delta < -0.01 {
            return .heavy(
                totalSessions: total
            )
        }

        if delta > 0.01 {
            let readyCount =
                suggestions.filter {
                    $0.suggestedWeightKilograms >
                        $0.previousWeightKilograms +
                        0.01
                }
                .count

            if readyCount >= 2 {
                return .readyRepeated(
                    readySessions:
                        readyCount,
                    totalSessions: total
                )
            }

            return .readyLatest(
                totalSessions: total
            )
        }

        if let oldest =
                suggestions.last,
           latest.previousWeightKilograms >
                oldest
                    .previousWeightKilograms +
                0.01 {
            return .improving(
                totalSessions: total
            )
        }

        return .stable(
            totalSessions: total
        )
    }
}

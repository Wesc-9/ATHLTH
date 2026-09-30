import Foundation

enum RecoveryReadinessEngine {
    static func evaluate(
        currentSleep: SleepSummary,
        currentHeart: HeartSummary,
        sleepDays: [Date: Double],
        hrvDays: [Date: Double],
        restingHeartRateDays: [Date: Double],
        now: Date = Date()
    ) -> RecoveryReadinessSummary {
        let commonDays =
            Set(sleepDays.keys)
                .intersection(hrvDays.keys)
                .intersection(
                    restingHeartRateDays.keys
                )
                .filter { day in
                    guard let sleep =
                            sleepDays[day],
                          let hrv =
                            hrvDays[day],
                          let resting =
                            restingHeartRateDays[day]
                    else {
                        return false
                    }

                    return sleep.isFinite &&
                        sleep > 0 &&
                        hrv.isFinite &&
                        hrv > 0 &&
                        resting.isFinite &&
                        resting > 0
                }
        let baselineDays =
            commonDays.count

        let averageSleep =
            average(
                commonDays.compactMap {
                    sleepDays[$0]
                }
            )
        let averageHRV =
            average(
                commonDays.compactMap {
                    hrvDays[$0]
                }
            )
        let averageRestingHeartRate =
            average(
                commonDays.compactMap {
                    restingHeartRateDays[$0]
                }
            )

        let recentWindow:
            TimeInterval = 48 * 3_600

        guard baselineDays >= 5,
              currentSleep.totalAsleep > 0,
              let currentHRV =
                currentHeart.hrvMilliseconds,
              currentHRV > 0,
              let hrvDate = currentHeart.hrvDate,
              abs(
                now.timeIntervalSince(
                    hrvDate
                )
              ) <= recentWindow,
              let currentRestingHeartRate =
                currentHeart.restingHeartRate,
              currentRestingHeartRate > 0,
              let restingDate =
                currentHeart.restingHeartRateDate,
              abs(
                now.timeIntervalSince(
                    restingDate
                )
              ) <= recentWindow,
              let averageSleep,
              averageSleep > 0,
              let averageHRV,
              averageHRV > 0,
              let averageRestingHeartRate,
              averageRestingHeartRate > 0
        else {
            return RecoveryReadinessSummary(
                score: nil,
                state: .buildingBaseline,
                detail:
                    baselineDays > 0
                        ? "ATHLTH has \(baselineDays) usable baseline day\(baselineDays == 1 ? "" : "s"). At least 5 days with sleep, HRV and resting heart rate are needed."
                        : "ATHLTH is learning your recent sleep, HRV and resting heart-rate baseline.",
                baselineDays: baselineDays,
                averageSleepDuration:
                    averageSleep,
                baselineHRVMilliseconds:
                    averageHRV,
                baselineRestingHeartRate:
                    averageRestingHeartRate
            )
        }

        let sleepReference =
            max(
                averageSleep,
                7.5 * 3_600
            )
        let sleepScore =
            clamp(
                currentSleep.totalAsleep /
                    sleepReference,
                lower: 0.45,
                upper: 1.0
            ) * 100

        let hrvScore =
            clamp(
                currentHRV / averageHRV,
                lower: 0.55,
                upper: 1.0
            ) * 100

        let restingHeartRateScore =
            clamp(
                averageRestingHeartRate /
                    currentRestingHeartRate,
                lower: 0.60,
                upper: 1.0
            ) * 100

        let rawScore =
            sleepScore * 0.45 +
            hrvScore * 0.35 +
            restingHeartRateScore * 0.20

        let score =
            Int(
                clamp(
                    rawScore,
                    lower: 0,
                    upper: 100
                ).rounded()
            )

        let state:
            RecoveryReadinessState
        switch score {
        case 80...:
            state = .ready
        case 65..<80:
            state = .balanced
        case 50..<65:
            state = .takeItEasy
        default:
            state = .recover
        }

        return RecoveryReadinessSummary(
            score: score,
            state: state,
            detail:
                "Based on last night's sleep and today's HRV/resting heart rate compared with your recent baseline.",
            baselineDays: baselineDays,
            averageSleepDuration:
                averageSleep,
            baselineHRVMilliseconds:
                averageHRV,
            baselineRestingHeartRate:
                averageRestingHeartRate
        )
    }

    private static func average(
        _ values: [Double]
    ) -> Double? {
        guard !values.isEmpty else {
            return nil
        }

        return values.reduce(0, +) /
            Double(values.count)
    }

    private static func clamp(
        _ value: Double,
        lower: Double,
        upper: Double
    ) -> Double {
        min(
            max(value, lower),
            upper
        )
    }
}

import Foundation

enum RecoveryReadinessEngine {
    static func evaluate(
        currentSleep: SleepSummary,
        currentHeart: HeartSummary,
        sleepDays: [Date: Double],
        hrvDays: [Date: Double],
        restingHeartRateDays: [Date: Double],
        now: Date = Date(),
        lookbackDays: Int = 28,
        failedSignals: [RecoveryReadinessSignal] = []
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

        func usableCount(_ values: [Date: Double]) -> Int {
            values.values.filter { $0.isFinite && $0 > 0 }.count
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let days: [RecoveryReadinessDayCoverage] = (1...7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today)
            else { return nil }
            var available: [RecoveryReadinessSignal] = []
            if let value = sleepDays[day], value.isFinite, value > 0 {
                available.append(.sleep)
            }
            if let value = hrvDays[day], value.isFinite, value > 0 {
                available.append(.hrv)
            }
            if let value = restingHeartRateDays[day], value.isFinite, value > 0 {
                available.append(.restingHeartRate)
            }
            return RecoveryReadinessDayCoverage(
                date: day, availableSignals: available
            )
        }

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
        let sleepAge =
            currentSleep.sleepEnd.map {
                now.timeIntervalSince($0)
            }
        let hrvAge =
            currentHeart.hrvDate.map {
                now.timeIntervalSince($0)
            }
        let restingAge =
            currentHeart
                .restingHeartRateDate
                .map {
                    now.timeIntervalSince($0)
                }

        let diagnostics = RecoveryReadinessDiagnostics(
            lookbackDays: lookbackDays,
            requiredDays: 5,
            sleepDays: usableCount(sleepDays),
            hrvDays: usableCount(hrvDays),
            restingHeartRateDays: usableCount(restingHeartRateDays),
            completeDays: baselineDays,
            recentSleep: currentSleep.totalAsleep.isFinite &&
                currentSleep.totalAsleep > 0 &&
                sleepAge.map { $0 >= 0 && $0 <= recentWindow } == true,
            recentHRV: currentHeart.hrvMilliseconds.map {
                $0.isFinite && $0 > 0
            } == true && hrvAge.map {
                $0 >= 0 && $0 <= recentWindow
            } == true,
            recentRestingHeartRate: currentHeart.restingHeartRate.map {
                $0.isFinite && $0 > 0
            } == true && restingAge.map {
                $0 >= 0 && $0 <= recentWindow
            } == true,
            failedSignals: failedSignals,
            lastSevenDays: days
        )

        guard failedSignals.isEmpty,
              baselineDays >= 5,
              currentSleep.totalAsleep.isFinite,
              currentSleep.totalAsleep > 0,
              let sleepAge,
              sleepAge >= 0,
              sleepAge <= recentWindow,
              let currentHRV =
                currentHeart.hrvMilliseconds,
              currentHRV.isFinite,
              currentHRV > 0,
              let hrvAge,
              hrvAge >= 0,
              hrvAge <= recentWindow,
              let currentRestingHeartRate =
                currentHeart.restingHeartRate,
              currentRestingHeartRate.isFinite,
              currentRestingHeartRate > 0,
              let restingAge,
              restingAge >= 0,
              restingAge <= recentWindow,
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
                detail: missingDataDetail(diagnostics),
                baselineDays: baselineDays,
                averageSleepDuration:
                    averageSleep,
                baselineHRVMilliseconds:
                    averageHRV,
                baselineRestingHeartRate:
                    averageRestingHeartRate,
                diagnostics: diagnostics
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
                lower: 0.0,
                upper: 1.0
            ) * 100

        let hrvScore =
            clamp(
                currentHRV / averageHRV,
                lower: 0.0,
                upper: 1.0
            ) * 100

        let restingHeartRateScore =
            clamp(
                averageRestingHeartRate /
                    currentRestingHeartRate,
                lower: 0.0,
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
            detail: ATHLTHLocalization.choose(
                english: "Based on your recent sleep, HRV and resting heart rate compared with your personal baseline.",
                norwegian: "Basert på søvn, HRV og hvilepuls sammenlignet med din personlige normal."
            ),
            baselineDays: baselineDays,
            averageSleepDuration:
                averageSleep,
            baselineHRVMilliseconds:
                averageHRV,
            baselineRestingHeartRate:
                averageRestingHeartRate,
            diagnostics: diagnostics
        )
    }

    private static func missingDataDetail(
        _ diagnostic: RecoveryReadinessDiagnostics
    ) -> String {
        if !diagnostic.failedSignals.isEmpty {
            let names = diagnostic.failedSignals.map(\.title).joined(separator: ", ")
            return ATHLTHLocalization.choose(
                english: "Could not read Apple Health history for: \(names). Refresh or check Health access.",
                norwegian: "Kunne ikke lese historikk fra Apple Helse for: \(names). Oppdater eller kontroller Helse-tilgangen."
            )
        }
        if diagnostic.completeDays < diagnostic.requiredDays {
            return ATHLTHLocalization.choose(
                english: "\(diagnostic.completeDays) of \(diagnostic.requiredDays) complete days in the last \(diagnostic.lookbackDays) days. Sleep, HRV and resting heart rate must be recorded on the same days.",
                norwegian: "\(diagnostic.completeDays) av \(diagnostic.requiredDays) komplette dager de siste \(diagnostic.lookbackDays) dagene. Søvn, HRV og hvilepuls må være registrert på de samme dagene."
            )
        }
        let names = diagnostic.missingRecentSignals.map(\.title).joined(separator: ", ")
        return ATHLTHLocalization.choose(
            english: "Needs a valid recent measurement (within 48 hours): \(names).",
            norwegian: "Trenger gyldige målinger fra de siste 48 timene: \(names)."
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

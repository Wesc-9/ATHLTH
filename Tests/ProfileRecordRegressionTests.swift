import XCTest
@testable import ATHLTH

final class ProfileRecordRegressionTests:
    XCTestCase {
    func testExpandedRunningRecordDistances() {
        XCTAssertEqual(
            HealthPersonalRecordKind
                .fastest400M
                .targetDistanceMeters ?? 0,
            400
        )
        XCTAssertEqual(
            HealthPersonalRecordKind
                .fastest800M
                .targetDistanceMeters ?? 0,
            800
        )
        XCTAssertEqual(
            HealthPersonalRecordKind
                .fastest3K
                .targetDistanceMeters ?? 0,
            3_000
        )
        XCTAssertEqual(
            HealthPersonalRecordKind
                .fastest15K
                .targetDistanceMeters ?? 0,
            15_000
        )
        XCTAssertEqual(
            HealthPersonalRecordKind
                .fastest10Mile
                .targetDistanceMeters ?? 0,
            16_093.44,
            accuracy: 0.01
        )
    }

    func testExpandedRunningRecordsStayInRunningGroup() {
        let kinds: [ProfileFeaturedRecordKind] = [
            .fastest400M,
            .fastest800M,
            .fastest3K,
            .fastest15K,
            .fastest10Mile
        ]

        XCTAssertTrue(
            kinds.allSatisfy {
                $0.group == .running
            }
        )
    }

    func testProfileShowcaseStillUsesFourSlots() {
        XCTAssertEqual(
            ProfileFeaturedRecordKind
                .showcaseLimit,
            4
        )
    }

    func testAllHealthBackedProfileRecordsMapToHealthKind() {
        let derivedRunningRecords:
            Set<ProfileFeaturedRecordKind> = [
                .bestWeeklyRunningDistance,
                .mostRunsInWeek,
                .bestRunningMonth
            ]

        let healthBacked =
            ProfileFeaturedRecordKind
                .allCases
                .filter {
                    (
                        $0.group == .running &&
                        !derivedRunningRecords
                            .contains($0)
                    ) ||
                    $0.group == .appleHealth ||
                    $0 ==
                        .longestStrengthWorkout
                }

        XCTAssertTrue(
            healthBacked.allSatisfy {
                $0.healthKind != nil
            }
        )

        XCTAssertTrue(
            derivedRunningRecords
                .allSatisfy {
                    $0.healthKind == nil
                }
        )
    }

    private func weightedExerciseRecord(
        _ title: String,
        kilograms: Double,
        kind: StrengthPersonalRecordKind = .heaviestSet
    ) -> StrengthPersonalRecord {
        StrengthPersonalRecord(
            id: "heaviest-set-\(title.lowercased())",
            kind: kind,
            title: title,
            value: "\(kilograms) kg × 5",
            date: Date(timeIntervalSince1970: 1_000),
            score: kilograms
        )
    }

    func testExerciseWeightRecordsDefaultToThreeMeasuredExerciseBests() {
        let records = [
            weightedExerciseRecord("Benkpress", kilograms: 100),
            weightedExerciseRecord("Knebøy", kilograms: 150),
            weightedExerciseRecord("Markløft", kilograms: 180),
            weightedExerciseRecord("Skulderpress", kilograms: 65)
        ]
        XCTAssertEqual(
            ProfileStrengthExerciseRecordSelection.selectedIDs(
                from: "",
                availableRecords: records
            ),
            records.prefix(3).map(\.id)
        )
    }

    func testExerciseWeightRecordSelectionsPersistAndExcludeUnknownOrDuplicateIDs() {
        let bench = weightedExerciseRecord("Benkpress", kilograms: 100)
        let squat = weightedExerciseRecord("Knebøy", kilograms: 150)
        let stored = ProfileStrengthExerciseRecordSelection.encoded([
            squat.id, bench.id, bench.id, "missing-exercise"
        ])
        XCTAssertEqual(
            ProfileStrengthExerciseRecordSelection.selectedIDs(
                from: stored,
                availableRecords: [bench, squat]
            ),
            [squat.id, bench.id]
        )
    }

    func testExerciseWeightRecordsIgnoreUnweightedAndNonHeaviestEntries() {
        let zero = weightedExerciseRecord("Nedtrekk", kilograms: 0)
        let rep = weightedExerciseRecord(
            "Benkpress",
            kilograms: 90,
            kind: .estimatedOneRepMax
        )
        let valid = weightedExerciseRecord("Knebøy", kilograms: 110)
        XCTAssertEqual(
            ProfileStrengthExerciseRecordSelection.selectedIDs(
                from: "",
                availableRecords: [zero, rep, valid]
            ),
            [valid.id]
        )
    }

    func testExerciseWeightRecordProfileSelectionCanBeExplicitlyEmpty() {
        let bench = weightedExerciseRecord("Benkpress", kilograms: 100)
        XCTAssertEqual(
            ProfileStrengthExerciseRecordSelection.selectedIDs(
                from: ProfileStrengthExerciseRecordSelection.encoded([]),
                availableRecords: [bench]
            ),
            []
        )
        XCTAssertEqual(
            ProfileStrengthExerciseRecordSelection.showcaseLimit,
            4
        )
    }

    func testNewPaceAndDurationRecordsHaveHealthSources() {
        let running: [ProfileFeaturedRecordKind] = [
            .bestRunningAveragePace,
            .fastestFiveMinutePace,
            .fastestTenMinutePace,
            .longestRunningDuration,
            .mostRunningElevationGain
        ]
        XCTAssertTrue(running.allSatisfy { $0.group == .running })
        XCTAssertTrue(running.allSatisfy { $0.healthKind != nil })
        XCTAssertEqual(
            ProfileFeaturedRecordKind.bestWalkingAveragePace.group,
            .appleHealth
        )
        XCTAssertEqual(
            ProfileFeaturedRecordKind.bestWalkingAveragePace.healthKind,
            .bestWalkingAveragePace
        )
    }

    func testNewRecordValuesAreFormattedInMeaningfulUnits() {
        let date = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(
            HealthPersonalRecord(
                kind: .bestRunningAveragePace,
                value: 246,
                date: date
            ).formattedValue,
            "4:06 /km"
        )
        XCTAssertEqual(
            HealthPersonalRecord(
                kind: .fastestFiveMinutePace,
                value: 255,
                date: date
            ).formattedValue,
            "4:15 /km"
        )
        XCTAssertEqual(
            HealthPersonalRecord(
                kind: .longestRunningDuration,
                value: 5_220,
                date: date
            ).formattedValue,
            "1h 27m"
        )
        XCTAssertEqual(
            HealthPersonalRecord(
                kind: .mostRunningElevationGain,
                value: 287.3,
                date: date
            ).formattedValue,
            "287 hm"
        )
    }

    func testNewStrengthRecordsUseLoggedWorkouts() {
        let kinds: [ProfileFeaturedRecordKind] = [
            .strengthBestSingleSetVolume,
            .strengthBestExerciseVolume,
            .strengthMostRepsInSet,
            .strengthLongestTimedSet,
            .strengthMostWorkoutsInWeek
        ]
        XCTAssertTrue(kinds.allSatisfy { $0.group == .strength })
        XCTAssertTrue(kinds.allSatisfy { $0.healthKind == nil })
        XCTAssertTrue(
            kinds.allSatisfy {
                $0.displayValue(healthRecords: [], stats: nil) == "—"
            }
        )
    }


    func testFeaturedRecordCanBeRemovedWithoutDeletingOtherSelections() {
        let selection: [ProfileFeaturedRecordKind] = [
            .fastest1K, .longestRun, .strengthHeaviestSet
        ]
        let result = ProfileFeaturedRecordKind.removing(
            .longestRun,
            from: selection
        )
        XCTAssertEqual(result, [.fastest1K, .strengthHeaviestSet])
        XCTAssertEqual(
            ProfileFeaturedRecordKind.decodedSelection(
                from: ProfileFeaturedRecordKind.encodedSelection(result)
            ),
            result
        )
        XCTAssertEqual(
            ProfileFeaturedRecordKind.encodedSelection(
                ProfileFeaturedRecordKind.removing(.fastest1K, from: [.fastest1K])
            ),
            "-"
        )
    }

    func testReplacingFeaturedRecordKeepsPositionAndOtherRecords() {
        let before: [ProfileFeaturedRecordKind] = [
            .fastest1K, .longestRun, .strengthHeaviestSet
        ]
        XCTAssertEqual(
            ProfileFeaturedRecordKind.replacing(
                in: before, at: 1, with: .fastestFiveMinutePace
            ),
            [.fastest1K, .fastestFiveMinutePace, .strengthHeaviestSet]
        )
        // Already featured records exchange positions instead of duplicating.
        XCTAssertEqual(
            ProfileFeaturedRecordKind.replacing(
                in: before, at: 0, with: .strengthHeaviestSet
            ),
            [.strengthHeaviestSet, .longestRun, .fastest1K]
        )
    }

    func testReplacingInvalidSlotPreservesPreviousSelection() {
        let before: [ProfileFeaturedRecordKind] = [.fastest1K, .longestRun]
        XCTAssertEqual(
            ProfileFeaturedRecordKind.replacing(
                in: before, at: 4, with: .fastest5K
            ),
            before
        )
    }
}

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

}

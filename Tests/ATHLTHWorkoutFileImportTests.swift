import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHWorkoutFileImportTests: XCTestCase {
    func testTCXPlannedIntervalsImportAsEditableBlocksWithZone() throws {
        let tcx = """
        <?xml version="1.0" encoding="utf-8"?>
        <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
          <Workouts><Workout Sport="Running">
            <Name>One minute Z5</Name>
            <Step><Name>Warmup</Name><Duration xsi:type="Time_t" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><Seconds>600</Seconds></Duration><Intensity>Active</Intensity></Step>
            <Repeat><Repetitions>2</Repetitions>
              <Step><Name>Z5 effort</Name><Duration><Seconds>60</Seconds></Duration><Intensity>Active</Intensity><Target><HeartRateZone>5</HeartRateZone></Target></Step>
              <Step><Name>Easy rest</Name><Duration><Seconds>60</Seconds></Duration><Intensity>Resting</Intensity></Step>
            </Repeat>
          </Workout></Workouts>
        </TrainingCenterDatabase>
        """
        let result = try ATHLTHWorkoutFileImport.parse(
            data: Data(tcx.utf8), filename: "intervals.tcx",
            selectedActivity: .running
        )
        XCTAssertEqual(result.title, "One minute Z5")
        XCTAssertEqual(result.activity, .running)
        XCTAssertEqual(result.blocks.count, 5)
        XCTAssertEqual(result.blocks.map(\.durationSeconds), [600, 60, 60, 60, 60])
        XCTAssertEqual(result.blocks[1].targetHeartRateZone, 5)
        XCTAssertEqual(result.blocks[2].kind, .rest)
        XCTAssertNil(result.blocks[2].targetHeartRateZone)
        XCTAssertEqual(result.blocks[0].resolvedPhase, .warmup)
        XCTAssertEqual(result.durationSeconds, 840)
    }

    func testZWOImportKeepsFTPAsNotesNotInventedHeartRateZone() throws {
        let zwo = """
        <workout_file>
          <name>Indoor intervals</name>
          <workout>
            <Warmup Duration="300" PowerLow="0.45" PowerHigh="0.65"/>
            <IntervalsT Repeat="2" OnDuration="60" OffDuration="60"
                OnPower="1.20" OffPower="0.50"/>
            <Cooldown Duration="180" PowerLow="0.55" PowerHigh="0.35"/>
          </workout>
        </workout_file>
        """
        let result = try ATHLTHWorkoutFileImport.parse(
            data: Data(zwo.utf8), filename: "session.zwo",
            selectedActivity: .cycling
        )
        XCTAssertEqual(result.blocks.count, 6)
        XCTAssertEqual(result.blocks[1].notes, "Zwift: 120% FTP")
        XCTAssertEqual(result.blocks[1].activityTag, "cycling")
        XCTAssertNil(result.blocks[1].targetHeartRateZone)
        XCTAssertEqual(result.blocks[2].resolvedPhase, .recovery)
    }

    func testZwiftRunningFileUsesRunningStepsAndNeverInventsPace() throws {
        let zwo = """
        <workout_file><sportType>run</sportType><name>Run workout</name>
        <workout><IntervalsT Repeat="2" OnDuration="60" OffDuration="60"
                 OnPower="1.20" OffPower="0.50"/></workout></workout_file>
        """
        let result = try ATHLTHWorkoutFileImport.parse(
            data: Data(zwo.utf8), filename: "run.zwo",
            selectedActivity: .running
        )
        XCTAssertEqual(result.activity, .running)
        XCTAssertEqual(result.blocks.count, 4)
        XCTAssertEqual(result.blocks[0].kind, .run)
        XCTAssertEqual(result.blocks[1].kind, .rest)
        XCTAssertEqual(result.blocks[0].notes, "Zwift: 120% prescribed intensity")
        XCTAssertNil(result.blocks[0].targetPaceSecondsPerKilometer)
        XCTAssertNil(result.blocks[0].targetHeartRateZone)
    }

    func testJSONEditableBlocksImportWithoutExternalRouteIdentity() throws {
        let block = WorkoutTemplateBlock(
            sequence: 1, kind: .run, title: "Interval Z4",
            exerciseSlug: nil, distanceMeters: nil,
            repetitions: nil, durationSeconds: 240,
            targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: .main,
            targetHeartRateZone: 4
        )
        let raw = try JSONEncoder().encode([block])
        let result = try ATHLTHWorkoutFileImport.parse(
            data: raw, filename: "athlth.json", selectedActivity: .running
        )
        XCTAssertEqual(result.blocks.count, 1)
        XCTAssertEqual(result.blocks[0].targetHeartRateZone, 4)
        XCTAssertEqual(result.blocks[0].durationSeconds, 240)
        XCTAssertEqual(result.blocks[0].kind, .run)
    }

    func testRecordedTCXActivityIsNotMisidentifiedAsTrainingPlan() {
        let tcx = """
        <TrainingCenterDatabase><Activities><Activity Sport="Running">
          <Lap><Track><Trackpoint><DistanceMeters>100</DistanceMeters></Trackpoint></Track></Lap>
        </Activity></Activities></TrainingCenterDatabase>
        """
        XCTAssertThrowsError(try ATHLTHWorkoutFileImport.parse(
            data: Data(tcx.utf8), filename: "recorded.tcx",
            selectedActivity: .running
        )) { error in
            guard case ATHLTHWorkoutFileImport.ImportFailure.noPlannedWorkout = error
            else { return XCTFail("Should reject recorded activities") }
        }
    }

    func testCyclingWorkoutCannotSilentlyOverwriteRunningPlan() {
        let zwo = """
        <workout_file><name>Cycling</name><workout>
          <SteadyState Duration="600" Power="0.75"/>
        </workout></workout_file>
        """
        XCTAssertThrowsError(try ATHLTHWorkoutFileImport.parse(
            data: Data(zwo.utf8), filename: "cycling.zwo",
            selectedActivity: .running
        )) { error in
            guard case ATHLTHWorkoutFileImport.ImportFailure.incompatibleActivity = error
            else { return XCTFail("Should require a matching workout type") }
        }
    }

    func testInvalidExtensionsRejectedWithoutSideEffects() {
        XCTAssertThrowsError(try ATHLTHWorkoutFileImport.parse(
            data: Data("not a workout".utf8),
            filename: "recorded.fit", selectedActivity: .running
        )) { error in
            guard case ATHLTHWorkoutFileImport.ImportFailure.unsupported = error
            else { return XCTFail("Expected explicit unsupported format") }
        }
    }
}

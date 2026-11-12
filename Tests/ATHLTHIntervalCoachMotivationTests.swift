import XCTest
@testable import ATHLTH

final class ATHLTHIntervalCoachMotivationTests: XCTestCase {
    func testHalfwayFollowsEachEffortLength() {
        let settings = ATHLTHIntervalMotivationSettings(halfway: true, finalSeconds: nil)
        for duration in [30.0, 240.0] {
            let midpoint = duration / 2
            XCTAssertNil(ATHLTHIntervalCoachCue.motivation(
                settings, phase: "work", elapsed: midpoint - 1, remaining: midpoint + 1,
                norwegian: true
            ))
            XCTAssertEqual(ATHLTHIntervalCoachCue.motivation(
                settings, phase: "work", elapsed: midpoint, remaining: midpoint,
                norwegian: true
            )?.key, "halfway")
        }
    }

    func testFinalPushAppliesOnlyDuringWorkAndForAValidLeadTime() {
        let settings = ATHLTHIntervalMotivationSettings(halfway: false, finalSeconds: 15)
        XCTAssertEqual(ATHLTHIntervalCoachCue.motivation(
            settings, phase: "work", elapsed: 225, remaining: 15, norwegian: true
        )?.key, "finish")
        XCTAssertNil(ATHLTHIntervalCoachCue.motivation(
            settings, phase: "recovery", elapsed: 225, remaining: 15, norwegian: true
        ))
        XCTAssertNil(ATHLTHIntervalCoachCue.motivation(
            settings, phase: "work", elapsed: 0, remaining: 15, norwegian: true
        ))
    }

    func testGroupReportCountsEffortsAndExcludesBothRecoveryTypes() throws {
        let groupID = UUID()
        let report = ATHLTHIntervalSpokenReport(effortPace: true, groupDistance: true)
        let phases = ["work", "recovery", "work", "recovery"]
        let steps = phases.enumerated().map { index, phase in
            WatchRunningWorkoutStep(
                id: UUID(), title: phase, measure: .time,
                distanceMeters: nil, durationSeconds: 60, intensityText: nil,
                phase: phase,
                recoveryStyle: index == 1 ? .activeJog : index == 3 ? .passive : nil,
                coachGroupID: groupID, spokenReport: report
            )
        }
        let distances = [200.0, 150.0, 240.0, 10.0]
        let recorded = phases.enumerated().map { index, phase in
            ATHLTHRecordedRunningStep(index: index, title: phase, phase: phase,
                                      activeSeconds: 60, distanceMeters: distances[index])
        }
        let effort = try XCTUnwrap(ATHLTHRunningCoachReport.make(
            steps: steps, finishedIndex: 2, recorded: recorded
        ))
        XCTAssertEqual(effort.paceSecondsPerKilometer, 250)
        XCTAssertNil(effort.groupDistanceMeters)
        let completed = try XCTUnwrap(ATHLTHRunningCoachReport.make(
            steps: steps, finishedIndex: 3, recorded: recorded
        ))
        XCTAssertNil(completed.paceSecondsPerKilometer)
        XCTAssertEqual(completed.groupDistanceMeters, 440)
    }

    func testHalfwayPulseUsesMeasuredZoneOnly() throws {
        let settings = ATHLTHIntervalMotivationSettings(
            halfway: true, finalSeconds: nil, halfwayMessage: .heartRateZone
        )
        let measured = ATHLTHIntervalCoachCue.motivation(
            settings, phase: "work", elapsed: 60, remaining: 60, norwegian: true, measuredZone: 3
        )
        XCTAssertTrue(try XCTUnwrap(measured?.text).contains("pulssone 3"))
        let unavailable = ATHLTHIntervalCoachCue.motivation(
            settings, phase: "work", elapsed: 60, remaining: 60, norwegian: true
        )
        XCTAssertTrue(try XCTUnwrap(unavailable?.text).contains("ikke tilgjengelig"))
    }
}

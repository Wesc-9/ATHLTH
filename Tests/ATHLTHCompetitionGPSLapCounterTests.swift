import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHCompetitionGPSLapCounterTests: XCTestCase {
    private let start = Date().addingTimeInterval(-130)

    private func fix(
        lon: Double,
        time: TimeInterval,
        accuracy: Double = 4,
        course: Double? = 0
    ) -> ATHLTHCompetitionGPSFix {
        ATHLTHCompetitionGPSFix(
            latitude: 0, longitude: lon,
            accuracyMeters: accuracy,
            timestamp: start.addingTimeInterval(time),
            courseDegrees: course
        )
    }

    func testTwoAccurateOutboundAndInboundSamplesCountOnePhysicalLap() {
        var state = ATHLTHCompetitionGPSLapState()
        let measurements: [(Double,Double)] = [
            (0.0, 2), (0.00062, 16), (0.00063, 20),
            (0.00016, 37), (0.00015, 42)
        ]
        for (lon, time) in measurements {
            state = ATHLTHCompetitionGPSLapCounter.update(
                state, fix: fix(lon: lon, time: time),
                startLatitude: 0, startLongitude: 0,
                startSignalAt: start, limit: 3
            )
        }
        XCTAssertEqual(state.laps, 1)
        // Remaining at the finish line never causes a repeat lap.
        state = ATHLTHCompetitionGPSLapCounter.update(
            state, fix: fix(lon: 0.0001, time: 45),
            startLatitude: 0, startLongitude: 0,
            startSignalAt: start, limit: 3
        )
        XCTAssertEqual(state.laps, 1)
    }

    func testBadGpsAndPreSignalLocationNeverUnlockFinish() {
        var state = ATHLTHCompetitionGPSLapState()
        for (time, acc) in [(5.0, 3.0), (30.0, 38.0), (40.0, 40.0)] {
            state = ATHLTHCompetitionGPSLapCounter.update(
                state,
                fix: fix(lon: 0.00064,time: time,accuracy: acc),
                startLatitude: 0,startLongitude: 0,
                startSignalAt: start.addingTimeInterval(20),limit: 3
            )
        }
        XCTAssertEqual(state.laps, 0)
        XCTAssertEqual(state.outsideSamples, 0)
    }

    func testReverseCourseCannotQualifySecondLap() {
        var state = ATHLTHCompetitionGPSLapState()
        let first: [(Double, Double)] = [
            (0,2),(0.00062,16),(0.00063,20),(0.00016,37),(0.00015,42)
        ]
        for (lon, time) in first {
            state = ATHLTHCompetitionGPSLapCounter.update(
                state,fix: fix(lon: lon,time: time,course: 0),
                startLatitude: 0,startLongitude: 0,
                startSignalAt: start,limit: 3
            )
        }
        XCTAssertEqual(state.laps, 1)
        for (lon,time) in [(0.00062,58.0),(0.00062,62.0),
                           (0.00016,77.0),(0.00015,82.0)] {
            state = ATHLTHCompetitionGPSLapCounter.update(
                state,fix: fix(lon: lon,time: time,course: 180),
                startLatitude: 0,startLongitude: 0,
                startSignalAt: start,limit: 3
            )
        }
        XCTAssertEqual(state.laps, 1)
    }

    func testRaceOverlayRoundTripPreservesOriginalWorkoutIdentity() throws {
        let raceID = UUID()
        var race = ATHLTHCompetitionRaceRules()
        race.discipline = .laps
        race.lapCount = 5
        race.lapCourseName = "Rundt bygningen"
        race.lapVerification = .gps
        var record = ATHLTHCompetitionCaptureContext(
            tournamentID: raceID,
            startSignalAt: start,
            raceRules: race
        )
        record.lapState.laps = 2
        let recovered = try JSONDecoder().decode(
            ATHLTHCompetitionCaptureContext.self,
            from: JSONEncoder().encode(record)
        )
        XCTAssertEqual(recovered.tournamentID,raceID)
        XCTAssertEqual(recovered.lapSummary,"2/5 runder")
    }
}

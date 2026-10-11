import Foundation
import XCTest
@testable import ATHLTH

final class PlannedWorkoutInviteTests: XCTestCase {
    private func makeWorkout() -> PlannedSession {
        PlannedSession(
            id: UUID(),
            title: "Sunday run",
            kind: .running,
            scheduledStart: Date(timeIntervalSince1970: 1_800_000_000),
            durationMinutes: nil,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes: nil
        )
    }

    func testTrainTogetherModeIsPreservedAcrossInvitations() throws {
        var session = makeWorkout()
        session.trainTogetherMode = .sameWorkout
        let decoded = try JSONDecoder().decode(
            PlannedSession.self,
            from: JSONEncoder().encode(session)
        )
        XCTAssertEqual(decoded.trainTogetherMode, .sameWorkout)
        XCTAssertNil(decoded.meetingPoint)
        var physical = makeWorkout()
        physical.trainTogetherMode = .physical
        let decodedPhysical = try JSONDecoder().decode(
            PlannedSession.self,
            from: JSONEncoder().encode(physical)
        )
        XCTAssertEqual(decodedPhysical.trainTogetherMode, .physical)
    }

    func testMeetingPointAndReminderSurviveRoundTrip() throws {
        var workout = makeWorkout()
        workout.meetingPoint = PlannedWorkoutMeetingPoint(
            name: "Start", address: "Tromsø",
            latitude: 69.65, longitude: 18.95
        )
        workout.reminderMinutesBefore = 30

        let decoded = try JSONDecoder().decode(
            PlannedSession.self,
            from: JSONEncoder().encode(workout)
        )
        XCTAssertEqual(decoded.meetingPoint, workout.meetingPoint)
        XCTAssertEqual(decoded.reminderMinutesBefore, 30)
        XCTAssertNil(decoded.durationMinutes)
    }

    func testOldWorkoutWithoutLogisticsFieldsStillDecodes() throws {
        let workout = makeWorkout()
        var payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(workout))
            as? [String: Any]
        )
        payload.removeValue(forKey: "meetingPoint")
        payload.removeValue(forKey: "reminderMinutesBefore")
        let data = try JSONSerialization.data(withJSONObject: payload)
        let restored = try JSONDecoder().decode(PlannedSession.self, from: data)
        XCTAssertNil(restored.meetingPoint)
        XCTAssertNil(restored.reminderMinutesBefore)
    }

    func testInvitationResponseIsPreserved() throws {
        let id = UUID()
        let answer = PlannedWorkoutInviteResponse(
            sourceWorkoutID: id, decision: .accepted
        )
        let restored = try JSONDecoder().decode(
            PlannedWorkoutInviteResponse.self,
            from: JSONEncoder().encode(answer)
        )
        XCTAssertEqual(restored.sourceWorkoutID, id)
        XCTAssertEqual(restored.decision, .accepted)
    }
}

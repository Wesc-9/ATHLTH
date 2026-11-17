import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHAudioCoachGroupMoveTests: XCTestCase {
    func testCannotRemoveCommandFromItsTriggerGroup() {
        var draft = AudioCoachDraft()
        let rule = ATHLTHAudioCoachRule(
            trigger: .distance, metric: .heartRate, interval: 1_000
        )
        var group = ATHLTHAudioCoachGroup(name: "Per kilometer")
        group.trigger = .distance
        group.interval = 1_000
        group.ruleIDs = [rule.id]
        draft.customRules = [rule]
        draft.coachGroups = [group]

        let payload = "metric:" + rule.id.uuidString + ":heartRate"
        XCTAssertFalse(ATHLTHAudioCoachCommandMoves.move(payload, to: nil, draft: &draft))
        XCTAssertEqual(draft.customRules.count, 1)
        XCTAssertEqual(draft.coachGroups[0].ruleIDs, [rule.id])
    }

    func testMovingBetweenGroupsAdoptsNewTriggerAndInterval() {
        var draft = AudioCoachDraft()
        let rule = ATHLTHAudioCoachRule(
            trigger: .distance, metric: .distance, interval: 1_000
        )
        var source = ATHLTHAudioCoachGroup(name: "Distance")
        source.trigger = .distance
        source.interval = 1_000
        source.ruleIDs = [rule.id]
        var destination = ATHLTHAudioCoachGroup(name: "Time")
        destination.trigger = .time
        destination.interval = 60
        draft.customRules = [rule]
        draft.coachGroups = [source, destination]

        let payload = "metric:" + rule.id.uuidString + ":distance"
        XCTAssertTrue(ATHLTHAudioCoachCommandMoves.move(
            payload, to: destination.id, draft: &draft
        ))

        XCTAssertTrue(draft.coachGroups[0].ruleIDs.isEmpty)
        XCTAssertEqual(draft.coachGroups[1].ruleIDs.count, 1)
        let newID = try? XCTUnwrap(draft.coachGroups[1].ruleIDs.first)
        let moved = draft.customRules.first(where: { $0.id == newID })
        XCTAssertEqual(moved?.trigger, .time)
        XCTAssertEqual(moved?.validatedInterval, 60)
        XCTAssertEqual(moved?.selectedMetrics, [.distance])
    }

    func testMuteMusicSettingSurvivesWorkoutConfigurationRoundTrip() throws {
        var draft = AudioCoachDraft()
        draft.muteOtherAudio = true
        draft.duckOtherAudio = false

        let encoded = try JSONEncoder().encode(draft.configuration())
        let restored = try JSONDecoder().decode(
            WatchAudioCoachConfiguration.self, from: encoded
        )

        XCTAssertTrue(restored.shouldMuteOtherAudio)
        XCTAssertFalse(restored.shouldDuckOtherAudio)

        var nextDraft = AudioCoachDraft()
        nextDraft.load(configuration: restored)
        XCTAssertTrue(nextDraft.muteOtherAudio)
        XCTAssertFalse(nextDraft.duckOtherAudio)
    }
}

import XCTest
@testable import ATHLTH

final class ATHLTHAudioCoachRuleDeliveryTests: XCTestCase {
    func testIndependentDistanceAndTimeAnnouncementsDoNotRepeat() {
        let pace = ATHLTHAudioCoachRule(
            trigger: .distance, metric: .pace, interval: 1_000
        )
        let time = ATHLTHAudioCoachRule(
            trigger: .time, metric: .elapsedTime, interval: 30
        )
        let rules = [pace, time]
        var last = ATHLTHAudioCoachRuleDelivery.initialSlots(
            rules: rules, distanceMeters: 0, elapsedSeconds: 0
        )

        let first = ATHLTHAudioCoachRuleDelivery.dueMessages(
            rules: rules, distanceMeters: 400, elapsedSeconds: 30,
            paceSecondsPerKilometer: 315, heartRateBPM: 140,
            norwegian: true, lastSlots: &last
        )
        XCTAssertEqual(first.count, 1)
        XCTAssertTrue(first[0].contains("Tid"))
        XCTAssertEqual(last[time.id], 1)
        XCTAssertEqual(last[pace.id], 0)

        let repeated = ATHLTHAudioCoachRuleDelivery.dueMessages(
            rules: rules, distanceMeters: 400, elapsedSeconds: 30.8,
            paceSecondsPerKilometer: 315, heartRateBPM: 140,
            norwegian: true, lastSlots: &last
        )
        XCTAssertTrue(repeated.isEmpty)

        let both = ATHLTHAudioCoachRuleDelivery.dueMessages(
            rules: rules, distanceMeters: 1_025, elapsedSeconds: 60,
            paceSecondsPerKilometer: 315, heartRateBPM: 140,
            norwegian: true, lastSlots: &last
        )
        XCTAssertEqual(both.count, 2)
        XCTAssertTrue(both[0].contains("Tempo"))
        XCTAssertTrue(both[1].contains("Tid"))
    }

    func testLateHandoffDoesNotReplayPassedAnnouncements() {
        let rule = ATHLTHAudioCoachRule(
            trigger: .distance, metric: .pace, interval: 1_000
        )
        var last = ATHLTHAudioCoachRuleDelivery.initialSlots(
            rules: [rule], distanceMeters: 2_250, elapsedSeconds: 740
        )
        XCTAssertEqual(last[rule.id], 2)

        let noReplay = ATHLTHAudioCoachRuleDelivery.dueMessages(
            rules: [rule], distanceMeters: 2_255, elapsedSeconds: 741,
            paceSecondsPerKilometer: 330, heartRateBPM: nil,
            norwegian: true, lastSlots: &last
        )
        XCTAssertTrue(noReplay.isEmpty)

        let next = ATHLTHAudioCoachRuleDelivery.dueMessages(
            rules: [rule], distanceMeters: 3_020, elapsedSeconds: 1_020,
            paceSecondsPerKilometer: 330, heartRateBPM: nil,
            norwegian: true, lastSlots: &last
        )
        XCTAssertEqual(next.count, 1)
    }

    func testMissingPaceDoesNotReadOldMilestoneLate() {
        let rule = ATHLTHAudioCoachRule(
            trigger: .time, metric: .pace, interval: 30
        )
        var last: [UUID: Int] = [:]
        let unavailable = ATHLTHAudioCoachRuleDelivery.dueMessages(
            rules: [rule], distanceMeters: 100, elapsedSeconds: 30,
            paceSecondsPerKilometer: nil, heartRateBPM: nil,
            norwegian: false, lastSlots: &last
        )
        XCTAssertTrue(unavailable.isEmpty)
        XCTAssertEqual(last[rule.id], 1)

        let stale = ATHLTHAudioCoachRuleDelivery.dueMessages(
            rules: [rule], distanceMeters: 120, elapsedSeconds: 35,
            paceSecondsPerKilometer: 360, heartRateBPM: nil,
            norwegian: false, lastSlots: &last
        )
        XCTAssertTrue(stale.isEmpty)
    }

    func testSavedRuleListPreservesIndividualIntervals() throws {
        let saved = ATHLTHAudioCoachRuleSet(
            title: "Løp og tempo",
            rules: [
                ATHLTHAudioCoachRule(
                    trigger: .distance, metric: .pace, interval: 1_000
                ),
                ATHLTHAudioCoachRule(
                    trigger: .time, metric: .elapsedTime, interval: 30
                )
            ]
        )
        let restored = try JSONDecoder().decode(
            ATHLTHAudioCoachRuleSet.self,
            from: JSONEncoder().encode(saved)
        )
        XCTAssertEqual(restored, saved)
        XCTAssertEqual(restored.rules.map(\.validatedInterval), [1_000, 30])
    }
}

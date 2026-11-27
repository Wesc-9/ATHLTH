import XCTest
@testable import ATHLTH

final class ATHLTHAudioCoachRuleDeliveryTests: XCTestCase {

    func testNamedCoachGroupsSurviveProfileAndWatchConfigurationRoundTrip() throws {
        let rule = ATHLTHAudioCoachRule(
            trigger: .time, metric: .heartRate, interval: 300
        )
        let group = ATHLTHAudioCoachGroup(
            name: "Mine motivasjonsbeskjeder",
            ruleIDs: [rule.id], optionIDs: ["targetZoneCoach"]
        )
        var config = WatchAudioCoachConfiguration.disabled
        config.enabled = true
        config.customRules = [rule]
        config.coachGroups = [group]

        let profile = ATHLTHAudioCoachProfile(
            name: "Min mal", configuration: config
        )
        let restored = try JSONDecoder().decode(
            ATHLTHAudioCoachProfile.self,
            from: JSONEncoder().encode(profile)
        )
        var draft = AudioCoachDraft()
        draft.load(profile: restored)

        XCTAssertEqual(draft.coachGroups, [group])
        XCTAssertEqual(draft.configuration().coachGroups, [group])
        XCTAssertEqual(draft.configuration().customRules?.first?.id, rule.id)
    }

    func testStandardBuiltInMessagesRemainActiveWithoutStoredGroups() {
        var draft = AudioCoachDraft()
        draft.applySimpleAudioCoach()

        let active = ATHLTHAudioCoachOption.allCases.filter {
            $0 != .customAnnouncements &&
            $0.isVisible(route: false, structured: false) &&
            $0.isActive(in: draft)
        }

        // Older standard settings are virtual presentation groups only.
        // The Watch engine must not receive duplicate triggers.
        XCTAssertEqual(active.count, 8)
        XCTAssertTrue(draft.coachGroups.isEmpty)
        XCTAssertTrue(draft.customRules.isEmpty)
    }

    func testCoachGroupWithMultipleReadoutsSpeaksOneCombinedCue() throws {
        let rule = ATHLTHAudioCoachRule(
            trigger: .time,
            metric: .distance,
            interval: 300,
            additionalMetrics: [.elapsedTime, .heartRate],
            scope: .workout
        )
        let group = ATHLTHAudioCoachGroup(
            name: "Fem minutter",
            ruleIDs: [rule.id]
        )
        var config = WatchAudioCoachConfiguration.disabled
        config.enabled = true
        config.customRules = [rule]
        config.coachGroups = [group]

        let restored = try JSONDecoder().decode(
            WatchAudioCoachConfiguration.self,
            from: JSONEncoder().encode(config)
        )
        XCTAssertEqual(restored.coachGroups?.first?.ruleIDs, [rule.id])
        XCTAssertEqual(restored.customRules?.first?.selectedMetrics,
                       [.distance, .elapsedTime, .heartRate])

        var slots = ATHLTHAudioCoachRuleDelivery.initialSlots(
            rules: [rule],
            distanceMeters: 0,
            elapsedSeconds: 0
        )
        let spoken = ATHLTHAudioCoachRuleDelivery.dueMessages(
            rules: [rule],
            distanceMeters: 1_000,
            elapsedSeconds: 300,
            paceSecondsPerKilometer: 300,
            heartRateBPM: 150,
            norwegian: true,
            lastSlots: &slots
        )
        XCTAssertEqual(spoken.count, 1)
        XCTAssertTrue(spoken[0].contains("Distanse"))
        XCTAssertTrue(spoken[0].contains("Tid"))
        XCTAssertTrue(spoken[0].contains("Puls"))
    }

    func testGroupTriggerAndCommandsSurviveWatchAndProfileRoundTrip() throws {
        let rule = ATHLTHAudioCoachRule(
            trigger: .distance, metric: .distance, interval: 1_000,
            additionalMetrics: [.heartRate, .pace]
        )
        var group = ATHLTHAudioCoachGroup(
            name: "Kilometerstatus", ruleIDs: [rule.id]
        )
        group.trigger = .distance
        group.interval = 1_000
        var config = WatchAudioCoachConfiguration.disabled
        config.enabled = true
        config.customRules = [rule]
        config.coachGroups = [group]

        let profile = ATHLTHAudioCoachProfile(
            name: "Egen mal", configuration: config
        )
        let decoded = try JSONDecoder().decode(
            ATHLTHAudioCoachProfile.self,
            from: JSONEncoder().encode(profile)
        )
        var draft = AudioCoachDraft()
        draft.load(profile: decoded)
        XCTAssertEqual(draft.coachGroups.first?.trigger, .distance)
        XCTAssertEqual(draft.coachGroups.first?.interval, 1_000)
        XCTAssertEqual(draft.customRules.first?.selectedMetrics,
                       [.distance, .heartRate, .pace])
    }

    func testDraggingIndividualCommandsIntoAndOutOfGroupDoesNotDuplicate() {
        var draft = AudioCoachDraft()
        draft.customRules = [
            ATHLTHAudioCoachRule(
                trigger: .time, metric: .distance, interval: 60,
                additionalMetrics: [.heartRate]
            )
        ]
        var group = ATHLTHAudioCoachGroup(name: "Tre minutter")
        group.trigger = .time
        group.interval = 180
        draft.coachGroups = [group]

        let source = draft.customRules[0]
        XCTAssertTrue(ATHLTHAudioCoachCommandMoves.move(
            "metric:\(source.id.uuidString):heartRate",
            to: group.id, draft: &draft
        ))
        XCTAssertEqual(draft.customRules.count, 2)
        XCTAssertEqual(draft.customRules.first?.selectedMetrics, [.distance])
        let moved = draft.customRules.first(where: {
            group.id == draft.coachGroups.first?.id &&
                draft.coachGroups[0].ruleIDs.contains($0.id)
        })
        XCTAssertEqual(moved?.selectedMetrics, [.heartRate])
        XCTAssertEqual(moved?.validatedInterval, 180)

        // Commands require a trigger-bearing group. Dropping outside a
        // group must leave the scheduled metric and its ownership intact.
        XCTAssertFalse(ATHLTHAudioCoachCommandMoves.move(
            "metric:\(moved!.id.uuidString):heartRate",
            to: nil, draft: &draft
        ))
        XCTAssertEqual(draft.coachGroups[0].ruleIDs, [moved!.id])
        XCTAssertEqual(
            draft.customRules.flatMap(\.selectedMetrics)
                .filter { $0 == .heartRate }.count,
            1
        )
        XCTAssertFalse(ATHLTHAudioCoachCommandMoves.move(
            "metric:00000000-0000-0000-0000-000000000000:pace",
            to: group.id, draft: &draft
        ))
    }

    func testDraggingBuiltInOptionsOnlyMovesPresentationOwnership() {
        var draft = AudioCoachDraft()
        draft.applySimpleAudioCoach()
        let group = ATHLTHAudioCoachGroup(name: "Mine varsler")
        draft.coachGroups = [group]

        XCTAssertTrue(ATHLTHAudioCoachCommandMoves.move(
            "option:workoutStart", to: group.id, draft: &draft
        ))
        XCTAssertTrue(draft.announceWorkoutStart)
        XCTAssertEqual(draft.coachGroups[0].optionIDs, ["workoutStart"])
        XCTAssertTrue(draft.customRules.isEmpty)

        // Built-in options cannot be moved to an ungrouped destination.
        XCTAssertFalse(ATHLTHAudioCoachCommandMoves.move(
            "option:workoutStart", to: nil, draft: &draft
        ))
        XCTAssertEqual(draft.coachGroups[0].optionIDs, ["workoutStart"])
        XCTAssertTrue(draft.announceWorkoutStart)
    }

    func testPersonalMotivationTextIsSpokenWithGroupMetrics() {
        var rule = ATHLTHAudioCoachRule(
            trigger: .time,
            metric: .motivation,
            interval: 300,
            additionalMetrics: [.distance]
        )
        rule.customPhrase = "Nå gir du alt!"
        let phrase = rule.phrase(
            distanceMeters: 1_500,
            elapsedSeconds: 300,
            paceSecondsPerKilometer: 305,
            heartRateBPM: nil,
            norwegian: true
        )
        XCTAssertTrue(phrase?.contains("Nå gir du alt!") == true)
        XCTAssertTrue(phrase?.contains("Distanse") == true)
    }

    func testBeforeFinishMotivationIsSpokenOnceOnlyWhenFinishIsKnown() {
        var rule = ATHLTHAudioCoachRule(
            trigger: .time, metric: .motivation, interval: 60
        )
        rule.beforeEndSeconds = 900
        rule.customPhrase = "Nå gir du alt!"
        XCTAssertTrue(ATHLTHCoachReadoutContext.needsSegmentData([rule]))
        var slots = ATHLTHAudioCoachRuleDelivery.initialSlots(
            rules: [rule], distanceMeters: 0, elapsedSeconds: 0
        )

        func messages(remaining: Double?) -> [String] {
            ATHLTHAudioCoachRuleDelivery.dueMessages(
                rules: [rule], distanceMeters: 1_000, elapsedSeconds: 300,
                paceSecondsPerKilometer: 300, heartRateBPM: 150,
                norwegian: true,
                context: ATHLTHCoachReadoutContext(
                    workoutRemainingSeconds: remaining
                ),
                lastSlots: &slots
            )
        }

        XCTAssertTrue(messages(remaining: nil).isEmpty)
        XCTAssertTrue(messages(remaining: 901).isEmpty)
        XCTAssertEqual(messages(remaining: 900), ["Nå gir du alt!"])
        XCTAssertTrue(messages(remaining: 899).isEmpty)
        XCTAssertEqual(slots[rule.id], 1)
    }

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

    func testCompetitionCoachProfileCanBeLoadedBeforeRunWithoutLosingRuleCadences() throws {
        let distanceEveryMinute = ATHLTHAudioCoachRule(
            trigger: .time, metric: .distance, interval: 60
        )
        let timeEvery800Metres = ATHLTHAudioCoachRule(
            trigger: .distance, metric: .elapsedTime, interval: 800
        )

        var config = WatchAudioCoachConfiguration.disabled
        config.enabled = true
        config.language = .norwegian
        config.customRules = [distanceEveryMinute, timeEvery800Metres]
        config.smartPrompts = ATHLTHAudioCoachSmartSettings(
            motivationEnabled: true,
            motivationIntervalSeconds: 60,
            randomEncouragementEnabled: true,
            randomIntervalSeconds: 180
        )
        config.announceDistance = true
        config.announceElapsedTime = true
        config.speechStyle = .motivating

        let profile = ATHLTHAudioCoachProfile(
            name: "Konkurranse", configuration: config
        )
        let restored = try JSONDecoder().decode(
            ATHLTHAudioCoachProfile.self,
            from: JSONEncoder().encode(profile)
        )

        var preStart = AudioCoachDraft()
        preStart.load(profile: restored)
        let transfer = preStart.configuration()
        XCTAssertTrue(transfer.enabled)
        XCTAssertEqual(transfer.customRules?.map(\.validatedInterval),
                       [60, 800])
        XCTAssertNil(transfer.distanceIntervalMeters)
        XCTAssertNil(transfer.timeIntervalSeconds)
        XCTAssertEqual(transfer.speechStyle, .motivating)
        XCTAssertEqual(transfer.smartPrompts?.motivationIntervalSeconds, 60)
        XCTAssertEqual(transfer.smartPrompts?.randomIntervalSeconds, 180)
    }

    func testDistanceEachMinuteAndTimeEach800MetresBothFireOnce() {
        let distanceUpdate = ATHLTHAudioCoachRule(
            trigger: .time, metric: .distance, interval: 60
        )
        let elapsedUpdate = ATHLTHAudioCoachRule(
            trigger: .distance, metric: .elapsedTime, interval: 800
        )
        var slots: [UUID: Int] = [:]
        let atMinute = ATHLTHAudioCoachRuleDelivery.dueMessages(
            rules: [distanceUpdate, elapsedUpdate],
            distanceMeters: 400,
            elapsedSeconds: 60,
            paceSecondsPerKilometer: 300,
            heartRateBPM: nil,
            norwegian: true,
            lastSlots: &slots
        )
        XCTAssertEqual(atMinute.count, 1)
        XCTAssertTrue(atMinute[0].contains("Distanse"))

        let at800m = ATHLTHAudioCoachRuleDelivery.dueMessages(
            rules: [distanceUpdate, elapsedUpdate],
            distanceMeters: 800,
            elapsedSeconds: 100,
            paceSecondsPerKilometer: 300,
            heartRateBPM: nil,
            norwegian: true,
            lastSlots: &slots
        )
        XCTAssertEqual(at800m.count, 1)
        XCTAssertTrue(at800m[0].contains("Tid"))

        let repeats = ATHLTHAudioCoachRuleDelivery.dueMessages(
            rules: [distanceUpdate, elapsedUpdate],
            distanceMeters: 810,
            elapsedSeconds: 101,
            paceSecondsPerKilometer: 300,
            heartRateBPM: nil,
            norwegian: true,
            lastSlots: &slots
        )
        XCTAssertTrue(repeats.isEmpty)
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

    func testOneKilometreBundleIncludesDistanceTimePacePulseAndZone() {
        let rule = ATHLTHAudioCoachRule(
            trigger: .distance, metric: .distance, interval: 1_000,
            additionalMetrics: [.elapsedTime, .pace, .heartRate, .heartRateZone]
        )
        var slot = ATHLTHAudioCoachRuleDelivery.initialSlots(
            rules: [rule], distanceMeters: 0, elapsedSeconds: 0
        )
        let message = ATHLTHAudioCoachRuleDelivery.dueMessages(
            rules: [rule], distanceMeters: 1_010, elapsedSeconds: 360,
            paceSecondsPerKilometer: 355, heartRateBPM: 151,
            norwegian: true, maximumHeartRateBPM: 185, lastSlots: &slot
        )
        XCTAssertEqual(message.count, 1)
        XCTAssertTrue(message[0].contains("Distanse"))
        XCTAssertTrue(message[0].contains("Tid"))
        XCTAssertTrue(message[0].contains("Tempo"))
        XCTAssertTrue(message[0].contains("Puls 151"))
        XCTAssertTrue(message[0].contains("Pulssone"))
        XCTAssertTrue(ATHLTHAudioCoachRuleDelivery.dueMessages(
            rules: [rule], distanceMeters: 1_050, elapsedSeconds: 362,
            paceSecondsPerKilometer: 355, heartRateBPM: 151,
            norwegian: true, maximumHeartRateBPM: 185, lastSlots: &slot
        ).isEmpty)
    }

    func testLegacyRuleAndNewBundleEncodeDecodeWithoutLosingMetrics() throws {
        let original = ATHLTHAudioCoachRule(
            trigger: .time, metric: .heartRateZone, interval: 60,
            additionalMetrics: [.heartRate]
        )
        let encoded = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(
            ATHLTHAudioCoachRule.self, from: encoded
        )
        XCTAssertEqual(restored.selectedMetrics, [.heartRateZone, .heartRate])
        let legacy = """
        {"id":"A519D13E-2792-49DF-AB57-F69705011EB5",
         "trigger":"distance","metric":"heartRate","interval":1000}
        """
        let old = try JSONDecoder().decode(
            ATHLTHAudioCoachRule.self, from: Data(legacy.utf8)
        )
        XCTAssertEqual(old.selectedMetrics, [.heartRate])
    }

    func testDueAnnouncementsIdentifyOnlyMetricsWithSensorData() {
        let rule = ATHLTHAudioCoachRule(
            trigger: .distance, metric: .distance, interval: 1_000,
            additionalMetrics: [.elapsedTime, .heartRate, .heartRateZone]
        )
        var slots = ATHLTHAudioCoachRuleDelivery.initialSlots(
            rules: [rule], distanceMeters: 0, elapsedSeconds: 0
        )
        let due = ATHLTHAudioCoachRuleDelivery.dueAnnouncements(
            rules: [rule], distanceMeters: 1_004, elapsedSeconds: 380,
            paceSecondsPerKilometer: 380, heartRateBPM: nil, norwegian: true,
            maximumHeartRateBPM: 190, lastSlots: &slots
        )
        XCTAssertEqual(due.count, 1)
        XCTAssertTrue(due[0].metrics.contains(.distance))
        XCTAssertTrue(due[0].metrics.contains(.elapsedTime))
        XCTAssertFalse(due[0].metrics.contains(.heartRate))
        XCTAssertFalse(due[0].metrics.contains(.heartRateZone))
    }

    func testCollidingCustomRulesSpeakEachMetricAtMostOnce() {
        let first = ATHLTHAudioCoachRule(
            trigger: .distance, metric: .distance, interval: 1_000,
            additionalMetrics: [.elapsedTime, .heartRate]
        )
        let second = ATHLTHAudioCoachRule(
            trigger: .time, metric: .heartRate, interval: 60,
            additionalMetrics: [.heartRateZone]
        )
        var slots = ATHLTHAudioCoachRuleDelivery.initialSlots(
            rules: [first, second], distanceMeters: 0, elapsedSeconds: 0
        )
        let cues = ATHLTHAudioCoachRuleDelivery.dueAnnouncements(
            rules: [first, second], distanceMeters: 1_001, elapsedSeconds: 360,
            paceSecondsPerKilometer: 360, heartRateBPM: 150,
            norwegian: true, maximumHeartRateBPM: 185, lastSlots: &slots
        )
        XCTAssertEqual(cues.count, 2)
        let spoken = cues.map(\.text).joined(separator: ". ")
        XCTAssertEqual(spoken.components(separatedBy: "Puls 150").count - 1, 1)
        XCTAssertTrue(spoken.contains("Pulssone"))
        XCTAssertTrue(spoken.contains("Distanse"))
    }

    func testDeliveryKeysAreStableAcrossSnapshotTimingAndOrder() {
        let custom = ATHLTHAudioCoachRule(
            trigger: .distance, metric: .heartRate, interval: 1_000
        )
        var watchSlots = ATHLTHAudioCoachRuleDelivery.initialSlots(
            rules: [custom], distanceMeters: 0, elapsedSeconds: 0
        )
        var phoneSlots = watchSlots
        let watch = ATHLTHAudioCoachRuleDelivery.dueAnnouncements(
            rules: [custom], distanceMeters: 1_001, elapsedSeconds: 355,
            paceSecondsPerKilometer: 350, heartRateBPM: 150,
            norwegian: true, lastSlots: &watchSlots
        )
        let phone = ATHLTHAudioCoachRuleDelivery.dueAnnouncements(
            rules: [custom], distanceMeters: 1_010, elapsedSeconds: 357,
            paceSecondsPerKilometer: 355, heartRateBPM: 149,
            norwegian: true, lastSlots: &phoneSlots
        )
        let watchKey = ATHLTHAudioCoachRuleDelivery.stableDeliveryKey(
            standardMilestones: ["d1000", "t300"], customAnnouncements: watch
        )
        let phoneKey = ATHLTHAudioCoachRuleDelivery.stableDeliveryKey(
            standardMilestones: ["t300", "d1000"], customAnnouncements: phone
        )
        XCTAssertEqual(watchKey, phoneKey)
        XCTAssertTrue(watchKey.count < 110)
        let later = ATHLTHAudioCoachRuleDelivery.stableDeliveryKey(
            standardMilestones: ["d2000", "t300"], customAnnouncements: watch
        )
        XCTAssertNotEqual(watchKey, later)
    }
    func testMinuteMotivationAndKilometreMetricsAreSeparateGroups() {
        let kilometres = ATHLTHAudioCoachRule(
            trigger: .distance, metric: .distance, interval: 1_000,
            additionalMetrics: [.elapsedTime, .heartRateZone]
        )
        var motivation = ATHLTHAudioCoachRule(
            trigger: .time, metric: .motivation, interval: 60
        )
        motivation.encouragementStyle = .push
        let rules = [kilometres, motivation]
        var last = ATHLTHAudioCoachRuleDelivery.initialSlots(
            rules: rules, distanceMeters: 0, elapsedSeconds: 0
        )

        let atMinute = ATHLTHAudioCoachRuleDelivery.dueAnnouncements(
            rules: rules, distanceMeters: 180, elapsedSeconds: 60,
            paceSecondsPerKilometer: 335, heartRateBPM: 145,
            norwegian: true, maximumHeartRateBPM: 185, lastSlots: &last
        )
        XCTAssertEqual(atMinute.count, 1)
        XCTAssertTrue(atMinute[0].metrics.contains(.motivation))
        XCTAssertFalse(atMinute[0].text.contains("Pulssone"))

        let repeatSnapshot = ATHLTHAudioCoachRuleDelivery.dueMessages(
            rules: rules, distanceMeters: 185, elapsedSeconds: 60.8,
            paceSecondsPerKilometer: 335, heartRateBPM: 146,
            norwegian: true, maximumHeartRateBPM: 185, lastSlots: &last
        )
        XCTAssertTrue(repeatSnapshot.isEmpty)

        let atKilometreAndMinute = ATHLTHAudioCoachRuleDelivery.dueAnnouncements(
            rules: rules, distanceMeters: 1_010, elapsedSeconds: 120,
            paceSecondsPerKilometer: 330, heartRateBPM: 149,
            norwegian: true, maximumHeartRateBPM: 185, lastSlots: &last
        )
        XCTAssertEqual(atKilometreAndMinute.count, 2)
        XCTAssertTrue(atKilometreAndMinute[0].text.contains("Distanse"))
        XCTAssertTrue(atKilometreAndMinute[0].text.contains("Tid"))
        XCTAssertTrue(atKilometreAndMinute[0].text.contains("Pulssone"))
        XCTAssertEqual(atKilometreAndMinute[1].metrics, [.motivation])
    }

    func testPausedMotivationGroupDoesNotSpeakAndSurvivesStorage() throws {
        var motivation = ATHLTHAudioCoachRule(
            trigger: .time, metric: .motivation, interval: 60
        )
        motivation.enabled = false
        motivation.encouragementStyle = .praise
        let restored = try JSONDecoder().decode(
            ATHLTHAudioCoachRule.self, from: JSONEncoder().encode(motivation)
        )
        XCTAssertFalse(restored.isEnabled)
        XCTAssertEqual(restored.encouragementStyle, .praise)
        var last: [UUID: Int] = [:]
        let skipped = ATHLTHAudioCoachRuleDelivery.dueMessages(
            rules: [restored], distanceMeters: 200, elapsedSeconds: 60,
            paceSecondsPerKilometer: nil, heartRateBPM: nil,
            norwegian: true, lastSlots: &last
        )
        XCTAssertTrue(skipped.isEmpty)
        XCTAssertEqual(last[restored.id], 1)
    }

    func testNativeZoneReadoutUsesRecorderBoundariesWithoutHRMax() {
        let rule = ATHLTHAudioCoachRule(trigger: .distance, metric: .heartRateZone, interval: 1_000)
        var context = ATHLTHCoachReadoutContext()
        context.appleLiveHeartRateZones = [
            ATHLTHRecordedHeartRateZone(index: 0, minimumBPM: nil, maximumBPM: 130, durationSeconds: 0),
            ATHLTHRecordedHeartRateZone(index: 1, minimumBPM: 130, maximumBPM: 170, durationSeconds: 0),
            ATHLTHRecordedHeartRateZone(index: 2, minimumBPM: 170, maximumBPM: nil, durationSeconds: 0)
        ]
        var slots: [UUID: Int] = [:]
        let messages = ATHLTHAudioCoachRuleDelivery.dueMessages(
            rules: [rule], distanceMeters: 1_020, elapsedSeconds: 300,
            paceSecondsPerKilometer: nil, heartRateBPM: 125,
            norwegian: true, maximumHeartRateBPM: nil, context: context, lastSlots: &slots
        )
        XCTAssertEqual(messages, ["Pulssone 1"])
        XCTAssertTrue(ATHLTHAudioCoachRule.Trigger.zoneEnter.requiresAuthoredZoneScale)
        XCTAssertFalse(ATHLTHAudioCoachRule.Trigger.distance.requiresAuthoredZoneScale)
    }

    func testMissingHeartRateZoneDoesNotSuppressDistanceOrMotivation() {
        let distance = ATHLTHAudioCoachRule(
            trigger: .distance, metric: .distance, interval: 1_000,
            additionalMetrics: [.heartRateZone]
        )
        let motivation = ATHLTHAudioCoachRule(
            trigger: .time, metric: .motivation, interval: 60
        )
        var slots: [UUID: Int] = [:]
        let cues = ATHLTHAudioCoachRuleDelivery.dueMessages(
            rules: [distance, motivation], distanceMeters: 1_020,
            elapsedSeconds: 60, paceSecondsPerKilometer: nil,
            heartRateBPM: nil, norwegian: true, lastSlots: &slots
        )
        XCTAssertEqual(cues.count, 2)
        XCTAssertTrue(cues[0].contains("Distanse"))
        XCTAssertFalse(cues[0].contains("Pulssone"))
        XCTAssertFalse(cues[1].contains("Distanse"))
    }

    func testPlannedWorkoutCoachSnapshotRetainsGroupEditsWithoutGlobalChanges() throws {
        var original = WatchAudioCoachConfiguration.disabled
        original.enabled = true
        original.distanceIntervalMeters = 1_000
        original.timeIntervalSeconds = 60
        original.customRules = [
            ATHLTHAudioCoachRule(
                trigger: .distance, metric: .distance, interval: 1_000,
                additionalMetrics: [.elapsedTime, .heartRateZone]
            ),
            ATHLTHAudioCoachRule(
                trigger: .time, metric: .motivation, interval: 60
            )
        ]
        original.language = .norwegian
        original.duckOtherAudio = true

        var draft = AudioCoachDraft()
        draft.load(configuration: original)
        let prepared = draft.configuration()

        XCTAssertEqual(prepared.customRules?.count, 2)
        // Adding independent groups must preserve configured standard cadences.
        XCTAssertEqual(prepared.distanceIntervalMeters, 1_000)
        XCTAssertEqual(prepared.timeIntervalSeconds, 60)
        XCTAssertEqual(prepared.language, .norwegian)
        XCTAssertEqual(prepared.duckOtherAudio, true)
        XCTAssertTrue(prepared.customRules?[1].selectedMetrics.contains(.motivation) == true)

        let copied = try JSONDecoder().decode(
            WatchAudioCoachConfiguration.self,
            from: JSONEncoder().encode(prepared)
        )
        XCTAssertEqual(copied.customRules, prepared.customRules)
    }

    func testAddingOneMinuteMotivationDoesNotDisableExistingKilometreCoach() {
        var draft = AudioCoachDraft()
        draft.enabled = true
        draft.distanceTriggerEnabled = true
        draft.distanceIntervalKilometers = 1
        draft.timeTriggerEnabled = false
        draft.announceDistance = true
        draft.announceElapsedTime = true
        draft.customRules = [
            ATHLTHAudioCoachRule(
                trigger: .time, metric: .motivation, interval: 60
            )
        ]
        let config = draft.configuration()
        XCTAssertEqual(config.distanceIntervalMeters, 1_000)
        XCTAssertNil(config.timeIntervalSeconds)
        XCTAssertEqual(config.customRules?.count, 1)

        var slots = ATHLTHAudioCoachRuleDelivery.initialSlots(
            rules: config.customRules ?? [],
            distanceMeters: 0, elapsedSeconds: 0
        )
        let minute = ATHLTHAudioCoachRuleDelivery.dueAnnouncements(
            rules: config.customRules ?? [],
            distanceMeters: 150, elapsedSeconds: 60,
            paceSecondsPerKilometer: nil, heartRateBPM: nil,
            norwegian: true, lastSlots: &slots
        )
        XCTAssertEqual(minute.count, 1)
        XCTAssertEqual(minute.first?.metrics, [.motivation])
        let kilometre = ATHLTHAudioCoachRuleDelivery.dueAnnouncements(
            rules: config.customRules ?? [],
            distanceMeters: 1_005, elapsedSeconds: 95,
            paceSecondsPerKilometer: nil, heartRateBPM: nil,
            norwegian: true, lastSlots: &slots
        )
        XCTAssertTrue(kilometre.isEmpty,
            "Custom time motivation does not replace the standard 1km cadence")
    }

    func testCustomMetricsAndStandardCadencesSurviveSavedProfile() throws {
        var config = WatchAudioCoachConfiguration.disabled
        config.enabled = true
        config.distanceIntervalMeters = 1_000
        config.timeIntervalSeconds = 90
        config.customRules = [
            ATHLTHAudioCoachRule(
                trigger: .distance, metric: .heartRateZone, interval: 1_000
            )
        ]
        let restored = try JSONDecoder().decode(
            WatchAudioCoachConfiguration.self,
            from: JSONEncoder().encode(config)
        )
        var draft = AudioCoachDraft()
        draft.load(configuration: restored)
        let launch = draft.configuration()
        XCTAssertEqual(launch.distanceIntervalMeters, 1_000)
        XCTAssertEqual(launch.timeIntervalSeconds, 90)
        XCTAssertEqual(launch.customRules, restored.customRules)
    }


    func testPerEffortRuleRestartsAndStaysSilentDuringRecovery() {
        let rule = ATHLTHAudioCoachRule(
            trigger: .time, metric: .elapsedTime, interval: 30, scope: .effort
        )
        var slots: [UUID: Int] = [:]
        func count(index: Int, elapsed: Double, isEffort: Bool) -> Int {
            ATHLTHAudioCoachRuleDelivery.dueAnnouncements(
                rules: [rule], distanceMeters: 1000, elapsedSeconds: 500,
                paceSecondsPerKilometer: nil, heartRateBPM: nil, norwegian: true,
                context: .init(stepIndex: index, isEffort: isEffort, stepElapsedSeconds: elapsed),
                lastSlots: &slots
            ).count
        }
        XCTAssertEqual(count(index: 0, elapsed: 30, isEffort: true), 1)
        XCTAssertEqual(count(index: 0, elapsed: 31, isEffort: true), 0)
        XCTAssertEqual(count(index: 1, elapsed: 30, isEffort: false), 0)
        XCTAssertEqual(count(index: 2, elapsed: 29, isEffort: true), 0)
        XCTAssertEqual(count(index: 2, elapsed: 30, isEffort: true), 1)
    }

    func testHydrationReminderEveryFifteenMinutesOnPhoneAndWatch() throws {
        let reminder = ATHLTHAudioCoachRule(
            trigger: .time, metric: .hydrationReminder,
            interval: 15 * 60, scope: .workout
        )
        var config = WatchAudioCoachConfiguration.disabled
        config.enabled = true
        config.customRules = [reminder]
        // The rule is saved in the same payload that is sent to Apple Watch.
        let restored = try JSONDecoder().decode(
            WatchAudioCoachConfiguration.self,
            from: JSONEncoder().encode(config)
        )
        XCTAssertEqual(restored.customRules, [reminder])
        var slots = ATHLTHAudioCoachRuleDelivery.initialSlots(
            rules: restored.customRules ?? [], distanceMeters: 0, elapsedSeconds: 0
        )
        func due(_ seconds: TimeInterval, norwegian: Bool) -> [ATHLTHAudioCoachDueAnnouncement] {
            ATHLTHAudioCoachRuleDelivery.dueAnnouncements(
                rules: restored.customRules ?? [], distanceMeters: 0,
                elapsedSeconds: seconds, paceSecondsPerKilometer: nil,
                heartRateBPM: nil, norwegian: norwegian, lastSlots: &slots
            )
        }
        XCTAssertTrue(due(899, norwegian: true).isEmpty)
        let first = due(900, norwegian: true)
        XCTAssertEqual(first.count, 1)
        XCTAssertTrue(first[0].text.contains("vann"))
        XCTAssertEqual(first[0].metrics, [.hydrationReminder])
        XCTAssertTrue(due(901, norwegian: true).isEmpty)
        XCTAssertTrue(due(1_799, norwegian: true).isEmpty)
        let second = due(1_800, norwegian: false)
        XCTAssertEqual(second.count, 1)
        XCTAssertTrue(second[0].text.contains("water"))
        XCTAssertNotEqual(first[0].milestoneKey, second[0].milestoneKey)
    }

    func testMutedGroupSurvivesTemplateAndWatchRoundTripWithoutSpeaking() throws {
        let hidden = ATHLTHAudioCoachRule(
            trigger: .time, metric: .heartRate, interval: 60
        )
        let visible = ATHLTHAudioCoachRule(
            trigger: .distance, metric: .distance, interval: 1_000
        )
        var group = ATHLTHAudioCoachGroup(
            name: "Min gruppe", ruleIDs: [hidden.id]
        )
        group.enabled = false
        var config = WatchAudioCoachConfiguration.disabled
        config.enabled = true
        config.customRules = [hidden, visible]
        config.coachGroups = [group]

        let decoded = try JSONDecoder().decode(
            WatchAudioCoachConfiguration.self, from: JSONEncoder().encode(config)
        )
        XCTAssertEqual(decoded.coachGroups?.first?.isEnabled, false)
        XCTAssertEqual(decoded.customRules?.count, 2)
        XCTAssertEqual(decoded.activeCustomRules.map(\.id), [visible.id])

        var draft = AudioCoachDraft()
        draft.load(configuration: decoded)
        XCTAssertFalse(draft.coachGroups[0].isEnabled)
        draft.coachGroups[0].enabled = true
        XCTAssertEqual(draft.configuration().activeCustomRules.count, 2)
    }

    func testStructuredNextExerciseAndMeasuredSummaries() {
        let steps = [
            WatchRunningWorkoutStep(
                id: UUID(), title: "Oppvarming", measure: .time,
                distanceMeters: nil, durationSeconds: 120,
                intensityText: nil, phase: "warmup"
            ),
            WatchRunningWorkoutStep(
                id: UUID(), title: "Drag", measure: .time,
                distanceMeters: nil, durationSeconds: 120,
                intensityText: nil, phase: "work"
            ),
            WatchRunningWorkoutStep(
                id: UUID(), title: "Pause", measure: .time,
                distanceMeters: nil, durationSeconds: 30,
                intensityText: nil, phase: "recovery"
            ),
            WatchRunningWorkoutStep(
                id: UUID(), title: "Nedjogging", measure: .open,
                distanceMeters: nil, durationSeconds: nil,
                intensityText: nil, phase: "cooldown"
            )
        ]
        let plan = WatchRunningWorkoutTransfer(title: "Intervall", steps: steps)
        let records = [
            ATHLTHRecordedRunningStep(
                index: 0, title: "Oppvarming", phase: "warmup",
                activeSeconds: 120, distanceMeters: 280
            ),
            ATHLTHRecordedRunningStep(
                index: 1, title: "Drag", phase: "work",
                activeSeconds: 120, distanceMeters: 400
            ),
            ATHLTHRecordedRunningStep(
                index: 2, title: "Pause", phase: "recovery",
                activeSeconds: 30, distanceMeters: 70
            )
        ]

        let effort = ATHLTHCoachReadoutContext.make(
            plan: plan, index: 1, elapsed: 0,
            distance: 0, recorded: Array(records.prefix(1)),
            routeRemainingMeters: nil
        )
        XCTAssertEqual(effort.remainingExerciseCount, 1)
        XCTAssertEqual(effort.nextExerciseName, "Nedjogging")
        XCTAssertNil(effort.previousMainSectionSeconds)

        let cooldown = ATHLTHCoachReadoutContext.make(
            plan: plan, index: 3, elapsed: 0,
            distance: 0, recorded: records, routeRemainingMeters: nil
        )
        XCTAssertEqual(cooldown.previousExerciseName, "Drag")
        XCTAssertEqual(cooldown.previousMainSectionExerciseCount, 1)
        XCTAssertEqual(cooldown.previousMainSectionSeconds, 150)
        XCTAssertEqual(cooldown.previousMainSectionDistanceMeters, 470)

        let remaining = ATHLTHAudioCoachRule(
            trigger: .stepStart, metric: .remainingExercises, interval: 1
        )
        XCTAssertTrue(remaining.phrase(
            distanceMeters: 0, elapsedSeconds: 0,
            paceSecondsPerKilometer: nil, heartRateBPM: nil,
            norwegian: true, context: effort
        )?.contains("1 øvelse") == true)

        let next = ATHLTHAudioCoachRule(
            trigger: .stepStart, metric: .nextExercise, interval: 1
        )
        XCTAssertTrue(next.phrase(
            distanceMeters: 0, elapsedSeconds: 0,
            paceSecondsPerKilometer: nil, heartRateBPM: nil,
            norwegian: true, context: effort
        )?.contains("Neste øvelse: Nedjogging") == true)

        let previous = ATHLTHAudioCoachRule(
            trigger: .stepStart, metric: .previousExerciseSummary, interval: 1
        )
        XCTAssertTrue(previous.phrase(
            distanceMeters: 0, elapsedSeconds: 0,
            paceSecondsPerKilometer: nil, heartRateBPM: nil,
            norwegian: true, context: cooldown
        )?.contains("Drag") == true)

        let main = ATHLTHAudioCoachRule(
            trigger: .stepStart, metric: .previousMainSectionSummary, interval: 1
        )
        XCTAssertNil(main.phrase(
            distanceMeters: 0, elapsedSeconds: 0,
            paceSecondsPerKilometer: nil, heartRateBPM: nil,
            norwegian: true, context: effort
        ))
        XCTAssertTrue(main.phrase(
            distanceMeters: 0, elapsedSeconds: 0,
            paceSecondsPerKilometer: nil, heartRateBPM: nil,
            norwegian: true, context: cooldown
        )?.contains("470 meter") == true)
    }

    func testInactiveGroupPreservesAuthoredBuiltInOptionsButSuppressesPlayback() throws {
        var group = ATHLTHAudioCoachGroup(name: "Muted values")
        group.enabled = false
        group.optionIDs = ["distanceUpdates", "motivation", "scopedCountdowns", "customPhrases"]
        var config = WatchAudioCoachConfiguration.disabled
        config.enabled = true
        config.distanceIntervalMeters = 1_000
        var smart = ATHLTHAudioCoachSmartSettings()
        smart.motivationEnabled = true
        smart.customEncouragements = ["My original motivation"]
        smart.boundaryCountdownRules = [ATHLTHCoachBoundaryCountdownRule()]
        config.smartPrompts = smart
        config.coachGroups = [group]

        let spoken = config.deliveryConfiguration
        XCTAssertNil(spoken.distanceIntervalMeters)
        XCTAssertFalse(spoken.smartPrompts?.motivationEnabled ?? true)
        XCTAssertTrue(spoken.smartPrompts?.customEncouragements.isEmpty ?? false)
        XCTAssertNil(spoken.smartPrompts?.boundaryCountdownRules)
        // The same payload must survive a template/Watch round trip verbatim.
        let stored = try JSONDecoder().decode(
            WatchAudioCoachConfiguration.self, from: JSONEncoder().encode(config)
        )
        XCTAssertEqual(stored.distanceIntervalMeters, 1_000)
        XCTAssertEqual(stored.smartPrompts?.customEncouragements, ["My original motivation"])
        XCTAssertEqual(stored.coachGroups?.first?.isEnabled, false)
        var enabled = stored
        enabled.coachGroups?[0].enabled = true
        XCTAssertNotNil(enabled.deliveryConfiguration.distanceIntervalMeters)
    }

    func testCoachGroupPhaseFilterConsumesEarlierMilestonesWithoutLateReplay() {
        let rule = ATHLTHAudioCoachRule(
            trigger: .time, metric: .distance, interval: 60
        )
        var group = ATHLTHAudioCoachGroup(name: "Hoveddel", ruleIDs: [rule.id])
        group.phases = [.main]
        var config = WatchAudioCoachConfiguration.disabled
        config.enabled = true
        config.coachGroups = [group]
        config.customRules = [rule]
        let active = config.activeCustomRules
        XCTAssertEqual(active.first?.allowedPhases, [.main])
        var slots: [UUID: Int] = [:]

        var warmup = ATHLTHCoachReadoutContext()
        warmup.stepPhase = "warmup"
        let first = ATHLTHAudioCoachRuleDelivery.dueMessages(
            rules: active, distanceMeters: 250, elapsedSeconds: 60,
            paceSecondsPerKilometer: 350, heartRateBPM: nil,
            norwegian: true, context: warmup,
            lastSlots: &slots
        )
        XCTAssertTrue(first.isEmpty)
        XCTAssertEqual(slots[rule.id], 1)
        var main = warmup
        main.stepPhase = "work"
        let second = ATHLTHAudioCoachRuleDelivery.dueMessages(
            rules: active, distanceMeters: 500, elapsedSeconds: 120,
            paceSecondsPerKilometer: 350, heartRateBPM: nil,
            norwegian: true, context: main,
            lastSlots: &slots
        )
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(slots[rule.id], 2)
    }

    func testPriorityComposerLimitsSimultaneousMessages() {
        let due: [ATHLTHAudioCoachDueAnnouncement] = [
            .init(text: "Motivasjon", metrics: [.motivation], milestoneKey: "a"),
            .init(text: "Distanse", metrics: [.distance], milestoneKey: "b"),
            .init(text: "Puls", metrics: [.heartRate], milestoneKey: "c"),
            .init(text: "Neste øvelse", metrics: [.nextExercise], milestoneKey: "d")
        ]
        let message = ATHLTHCoachRoutineComposition.compose(
            regular: "Vanlig status", customDue: due
        )
        XCTAssertTrue(message.contains("Neste øvelse"))
        XCTAssertTrue(message.contains("Puls"))
        XCTAssertTrue(message.contains("Distanse"))
        XCTAssertFalse(message.contains("Motivasjon"))
        XCTAssertFalse(message.contains("Vanlig status"))
    }

    func testGroupPreviewUsesExampleDataNotHealthKitWorkout() {
        let rule = ATHLTHAudioCoachRule(
            trigger: .stepStart, metric: .nextExercise, interval: 1
        )
        let group = ATHLTHAudioCoachGroup(name: "Preview", ruleIDs: [rule.id])
        let text = ATHLTHAudioCoachGroupPreview.text(
            group: group, rules: [rule], norwegian: true
        )
        XCTAssertTrue(text.contains("Knebøy"))
    }

    func testOpenCooldownDoesNotInventAnEstimatedFinishTime() throws {
        let groupID = UUID()
        let steps = [
            WatchRunningWorkoutStep(id: UUID(), title: "Effort", measure: .time,
                                    distanceMeters: nil, durationSeconds: 120, intensityText: nil,
                                    phase: "work", coachGroupID: groupID),
            WatchRunningWorkoutStep(id: UUID(), title: "Recovery", measure: .time,
                                    distanceMeters: nil, durationSeconds: 30, intensityText: nil,
                                    phase: "recovery", coachGroupID: groupID),
            WatchRunningWorkoutStep(id: UUID(), title: "Cooldown", measure: .open,
                                    distanceMeters: nil, durationSeconds: nil, intensityText: nil,
                                    phase: "cooldown")
        ]
        let context = ATHLTHCoachReadoutContext.make(
            plan: .init(title: "Intervals", steps: steps), index: 0,
            elapsed: 60, distance: 150, recorded: [], routeRemainingMeters: nil
        )
        XCTAssertEqual(context.stepRemainingSeconds, 60)
        XCTAssertEqual(context.groupRemainingSeconds, 90)
        XCTAssertNil(context.workoutRemainingSeconds)
        let rule = ATHLTHAudioCoachRule(trigger: .time, metric: .workoutRemainingTime, interval: 60)
        XCTAssertNil(rule.phrase(distanceMeters: 150, elapsedSeconds: 60,
                                 paceSecondsPerKilometer: nil, heartRateBPM: nil,
                                 norwegian: true, context: context))
    }

    func testUniversalAudioRulesKeepGenericCommandsButRejectWrongSport() {
        let time = ATHLTHAudioCoachRule(
            trigger: .time, metric: .elapsedTime, interval: 60
        )
        let heart = ATHLTHAudioCoachRule(
            trigger: .time, metric: .heartRate, interval: 60
        )
        let distance = ATHLTHAudioCoachRule(
            trigger: .distance, metric: .distance, interval: 1000
        )
        let pace = ATHLTHAudioCoachRule(
            trigger: .paceFasterOverall, metric: .pace, interval: 300
        )
        let step = ATHLTHAudioCoachRule(
            trigger: .effortStart, metric: .stepName, interval: 1
        )
        let record = ATHLTHAudioCoachRule(
            trigger: .personalRecordConfirmed, metric: .personalRecord, interval: 1
        )
        let mixed = ATHLTHAudioCoachRule(
            trigger: .time, metric: .elapsedTime, interval: 60,
            additionalMetrics: [.averagePace]
        )
        let rules = [time, heart, distance, pace, step, record, mixed]
        let cycle = ATHLTHAudioCoachSportPolicy.eligibleRules(
            rules, sport: "cycling"
        )
        XCTAssertEqual(cycle.map(\.id), [time.id, heart.id, distance.id])
        let hiit = ATHLTHAudioCoachSportPolicy.eligibleRules(
            rules, sport: "hiit"
        )
        XCTAssertEqual(hiit.map(\.id), [time.id, heart.id])
        XCTAssertEqual(ATHLTHAudioCoachSportPolicy.eligibleRules(
            rules, sport: "running"
        ).map(\.id), rules.map(\.id))
        XCTAssertTrue(ATHLTHAudioCoachSportPolicy.supportsDistance("rowing"))
        XCTAssertFalse(ATHLTHAudioCoachSportPolicy.supportsRunningPace("cycling"))
        XCTAssertFalse(ATHLTHAudioCoachSportPolicy.supportsDistance("yoga"))
    }


    func testWatchAndMirrorUseSameNonRunningRuleFilter() {
        let time = ATHLTHAudioCoachRule(
            trigger: .time, metric: .elapsedTime, interval: 60
        )
        let heart = ATHLTHAudioCoachRule(
            trigger: .time, metric: .heartRate, interval: 60
        )
        let distance = ATHLTHAudioCoachRule(
            trigger: .distance, metric: .distance, interval: 500
        )
        let pace = ATHLTHAudioCoachRule(
            trigger: .paceFasterOverall, metric: .pace, interval: 300
        )
        let step = ATHLTHAudioCoachRule(
            trigger: .stepStart, metric: .stepName, interval: 1
        )
        let all = [time, heart, distance, pace, step]
        for sport in ["cycling", "rowing"] {
            XCTAssertEqual(
                ATHLTHAudioCoachSportPolicy.eligibleRules(all, sport: sport)
                    .map(\.id),
                [time.id, heart.id, distance.id]
            )
        }
        for sport in ["hiit", "functional", "yoga", "meditation", "other"] {
            XCTAssertEqual(
                ATHLTHAudioCoachSportPolicy.eligibleRules(all, sport: sport)
                    .map(\.id),
                [time.id, heart.id]
            )
        }
    }

    func testWatchStrengthCoachDoesNotMixRunningMeasurements() {
        let valid = ATHLTHAudioCoachRule(
            trigger: .time, metric: .elapsedTime, interval: 60,
            additionalMetrics: [.remainingExercises]
        )
        let invalid = ATHLTHAudioCoachRule(
            trigger: .time, metric: .elapsedTime, interval: 60,
            additionalMetrics: [.pace]
        )
        let runOnly = ATHLTHAudioCoachRule(
            trigger: .paceFasterOverall, metric: .pace, interval: 300
        )
        XCTAssertEqual(
            ATHLTHAudioCoachSportPolicy.eligibleStrengthRules(
                [valid, invalid, runOnly]
            ).map(\.id),
            [valid.id]
        )
    }


    func testVoiceOwnersNeverTreatUnmeasuredRowingDistanceAsRecorded() {
        let time = ATHLTHAudioCoachRule(
            trigger: .time, metric: .elapsedTime, interval: 60
        )
        let distanceTrigger = ATHLTHAudioCoachRule(
            trigger: .distance, metric: .distance, interval: 500
        )
        let distanceReadout = ATHLTHAudioCoachRule(
            trigger: .time, metric: .distance, interval: 60
        )
        let mixed = ATHLTHAudioCoachRule(
            trigger: .time, metric: .elapsedTime, interval: 60,
            additionalMetrics: [.distance]
        )
        let rules = [time, distanceTrigger, distanceReadout, mixed]
        XCTAssertFalse(WatchWorkoutKind.rowing.supportsDistanceMetric)
        XCTAssertTrue(WatchWorkoutKind.cycling.supportsDistanceMetric)
        XCTAssertEqual(
            ATHLTHAudioCoachSportPolicy.eligibleRules(
                rules, sport: "rowing",
                measuredDistanceSupported:
                    WatchWorkoutKind.rowing.supportsDistanceMetric
            ).map(\.id),
            [time.id]
        )
        XCTAssertEqual(
            ATHLTHAudioCoachSportPolicy.eligibleRules(
                rules, sport: "cycling", measuredDistanceSupported: true
            ).map(\.id),
            rules.map(\.id)
        )
        XCTAssertEqual(
            ATHLTHAudioCoachSportPolicy.eligibleRules(
                rules, sport: "cycling", measuredDistanceSupported: false
            ).map(\.id),
            [time.id]
        )
        // The original persisted configuration is never changed.
        XCTAssertEqual(rules.count, 4)
    }

}

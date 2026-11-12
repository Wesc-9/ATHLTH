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
}

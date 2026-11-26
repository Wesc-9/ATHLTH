import XCTest
@testable import ATHLTH

final class ATHLTHUnifiedQuickStartPresentationTests: XCTestCase {
    @MainActor
    func testStudioTrainFeaturedActivitiesMatchApprovedOrder() {
        let featured = ATHLTHStudioTrainLandingView.featuredActivities
        XCTAssertEqual(featured.map(\.rawValue), ["walking", "running", "strength"])
        XCTAssertTrue(featured.allSatisfy(\.isAvailable))
    }

    func testActivityTypeChoicesAreSharedAcrossBasicAndAdvanced() {
        XCTAssertEqual(ATHLTHQuickStartActivity.running.types,
                       [.free, .route, .workout])
        XCTAssertEqual(ATHLTHQuickStartActivity.walking.types,
                       [.free, .route])
        XCTAssertEqual(ATHLTHQuickStartActivity.strength.types,
                       [.free, .workout, .exercises])
    }

    func testStrengthNeverOffersWalkingCompanion() {
        for iPad in [false, true] {
            let tools = ATHLTHQuickStartActivity.strength.availableTools(
                registeredIPad: iPad
            )
            XCTAssertFalse(tools.contains(.companion))
            XCTAssertTrue(tools.contains(.partner))
            XCTAssertTrue(tools.contains(.guidance))
            XCTAssertTrue(tools.contains(.equipment))
            XCTAssertTrue(tools.contains(.spotify))
        }
        XCTAssertTrue(
            ATHLTHQuickStartActivity.running.availableTools(
                registeredIPad: false
            ).contains(.companion)
        )
        XCTAssertTrue(
            ATHLTHQuickStartActivity.walking.availableTools(
                registeredIPad: false
            ).contains(.companion)
        )
    }

    func testIPadControlIsHiddenWithoutConfirmedRegistration() {
        for activity in [
            ATHLTHQuickStartActivity.running, .walking, .strength
        ] {
            XCTAssertFalse(activity.availableTools(
                registeredIPad: false
            ).contains(.iPad))
            XCTAssertTrue(activity.availableTools(
                registeredIPad: true
            ).contains(.iPad))
        }
    }

    func testCoachGuidanceIsNotRunSpecific() {
        XCTAssertEqual(
            ATHLTHQuickStartTool.guidance.title,
            ATHLTHLocalization.choose(
                english: "Coach & guidance",
                norwegian: "Coach og veiledning"
            )
        )
    }

    func testAllWorkoutTypesHaveAnAccessibleTitleAndSymbol() {
        for activity in [
            ATHLTHQuickStartActivity.running, .walking, .strength
        ] {
            for type in activity.types {
                XCTAssertFalse(type.title(for: activity).isEmpty)
                XCTAssertFalse(type.subtitle(for: activity).isEmpty)
                XCTAssertFalse(type.symbol.isEmpty)
            }
        }
    }
}

final class ATHLTHSportsQuickStartTests: XCTestCase {
    func testSportsUsesAnOpenWorkoutAndIsAvailableInCatalogue() {
        let category = ATHLTHTrainAllWorkoutCategoriesSheet.Category.sports
        XCTAssertTrue(category.isAvailable)
        XCTAssertEqual(category.icon, "sportscourt.fill")
        let configuration = CustomQuickWorkoutConfiguration.openTimed(activity: .sports)
        XCTAssertEqual(configuration.activity, .sports)
        XCTAssertEqual(configuration.method, .open)
        XCTAssertEqual(configuration.title, CustomQuickWorkoutActivity.sports.localizedTitle)
        XCTAssertFalse(configuration.audioCoach.enabled)
        XCTAssertFalse(configuration.activity.watchKind.supportsDistanceMetric)
        XCTAssertEqual(ATHLTHOtherSportLiveResolver.resolve(
            kind: configuration.activity.watchKind, distanceMeters: 1_000), .elapsed)
    }

    func testFreeTrainingRemainsOpenAndSeparate() {
        let configuration = CustomQuickWorkoutConfiguration.openTimed()
        XCTAssertEqual(configuration.activity, .other)
        XCTAssertEqual(configuration.method, .open)
        XCTAssertNotEqual(configuration.title, CustomQuickWorkoutConfiguration.openTimed(activity: .sports).title)
    }
}


final class ATHLTHCompletedSportsReviewTests: XCTestCase {
    func testWatchSportsIdentityAndRenameKeepOriginalMetrics() {
        let id = UUID()
        let start = Date()
        var result = WatchWorkoutResult(id: UUID(), kind: .other, healthKitWorkoutUUID: id,
            startedAt: start, endedAt: start.addingTimeInterval(60), duration: 60,
            activeCalories: 50, distanceMeters: 100, averageHeartRate: 150,
            maxHeartRate: 175, routePointCount: 0)
        XCTAssertFalse(SocialPublishableWorkout(watchResult: result).isSports)
        result.isSports = true
        let original = SocialPublishableWorkout(watchResult: result)
        let named = original.renamed("Cageball")
        XCTAssertTrue(named.isSports)
        XCTAssertEqual(named.presentationIcon, "sportscourt.fill")
        XCTAssertEqual(named.title, "Cageball")
        XCTAssertEqual(named.id, id)
        XCTAssertEqual(named.distanceMeters, 100)
        XCTAssertEqual(named.recordedAverageHeartRate, 150)
        XCTAssertEqual(named.recordedMaximumHeartRate, 175)
        XCTAssertNotEqual(original.title, named.title)
    }

    func testNameRejectsWhitespaceAndLimitsLength() {
        XCTAssertNil(ATHLTHCompletedWorkoutNames.clean("   "))
        XCTAssertEqual(ATHLTHCompletedWorkoutNames.clean("  Cageball  "), "Cageball")
        XCTAssertEqual(ATHLTHCompletedWorkoutNames.clean(String(repeating: "a", count: 200))?.count, 100)
    }
}


final class ATHLTHWatchHomeSentQueueTests: XCTestCase {
    private func workout(_ title: String, date: Date, owner: UUID, session: UUID? = nil,
                         mode: WatchWorkoutStartMode = .onWatch) -> WatchPreparedWorkoutTransfer {
        WatchPreparedWorkoutTransfer(id: UUID(), title: title, summary: "", kind: .walking,
            routeID: nil, runningWorkout: nil, audioCoach: nil, startMode: mode,
            plannedPlanID: session == nil ? nil : UUID(), plannedSessionID: session,
            updatedAt: date, ownerID: owner)
    }

    func testTwoManualTransfersAndDuplicateDelivery() {
        let owner = UUID(), now = Date()
        let one = workout("First", date: now.addingTimeInterval(-10), owner: owner)
        let two = workout("Second", date: now, owner: owner)
        let queue = WatchHomeSentQueue.inserting(two, into: [one], consumed: [], owner: owner, now: now)
        XCTAssertEqual(queue.map(\.id), [two.id, one.id])
        XCTAssertEqual(WatchHomeSentQueue.inserting(one, into: queue, consumed: [], owner: owner, now: now), queue)
        XCTAssertEqual(WatchHomeSentQueue.inserting(one, into: [two], consumed: [one.id], owner: owner, now: now), [two])
    }

    func testNewerSameSessionReplacesAndWrongAccountIsRejected() {
        let owner = UUID(), session = UUID(), now = Date()
        let old = workout("Old", date: now.addingTimeInterval(-10), owner: owner, session: session)
        let new = workout("New", date: now, owner: owner, session: session)
        XCTAssertEqual(WatchHomeSentQueue.inserting(new, into: [old], consumed: [], owner: owner, now: now), [new])
        XCTAssertTrue(WatchHomeSentQueue.visible([old], owner: UUID(), now: now).isEmpty)
    }
}


final class ATHLTHWatchDailyFormTransferTests: XCTestCase {
    func testDailyFormScoreAndFreshness() throws {
        let now = Date()
        let form = WatchDailyFormTransfer(score: 76, measuredScore: 80, state: "balanced",
            advice: nil, explanation: nil, sleepSeconds: 25000, hrvMilliseconds: 45,
            restingHeartRate: 53, trainingLoadRatio: 1.1, baselineDays: 10, updatedAt: now)
        XCTAssertEqual(form.validScore, 76)
        XCTAssertTrue(form.isCurrent(now: now))
        var expired = form
        expired.updatedAt = now.addingTimeInterval(-25 * 3600)
        XCTAssertFalse(expired.isCurrent(now: now))
        expired.score = 101
        XCTAssertNil(expired.validScore)
        expired.score = nil
        XCTAssertNil(expired.validScore)
        let decoded = try JSONDecoder().decode(WatchDailyFormTransfer.self, from: JSONEncoder().encode(form))
        XCTAssertEqual(decoded, form)
    }
}

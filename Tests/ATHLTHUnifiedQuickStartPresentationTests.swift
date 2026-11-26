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

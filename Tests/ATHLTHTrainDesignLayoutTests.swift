import SwiftUI
import XCTest
@testable import ATHLTH

final class ATHLTHTrainDesignLayoutTests: XCTestCase {
    @MainActor
    func testProgressPaceChartUsesStableIDsAndFitsCompactScreens() {
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        // Multiple HealthKit workouts can share a displayed timestamp. The
        // original chart used the date as its SwiftUI row identifier.
        let first = ATHLTHTrainProgressPaceChartView.Sample(
            id: UUID(), date: day, minutesPerKilometer: 5.2
        )
        let second = ATHLTHTrainProgressPaceChartView.Sample(
            id: UUID(), date: day, minutesPerKilometer: 5.0
        )
        XCTAssertNotEqual(first.id, second.id)
        for width in [320.0, 390.0, 768.0] {
            let chart = ATHLTHTrainProgressPaceChartView(samples: [first, second])
            let host = UIHostingController(rootView: chart)
            host.loadViewIfNeeded()
            let measured = host.sizeThatFits(
                in: CGSize(width: width, height: 600)
            )
            XCTAssertLessThanOrEqual(measured.width, width + 1)
            XCTAssertGreaterThan(measured.height, 0)
        }
    }

    @MainActor
    func testExtractedTodayCoverFitsNarrowAndLargeText() {
        for width in [320.0, 390.0, 768.0] {
            for size in [DynamicTypeSize.large, .accessibility3] {
                let cover = ATHLTHTrainTodayCoverView(
                    day: .now, selection: .constant(.today)
                )
                .environment(\.dynamicTypeSize, size)
                let host = UIHostingController(rootView: cover)
                host.loadViewIfNeeded()
                let measured = host.sizeThatFits(
                    in: CGSize(width: width, height: 1_000)
                )
                XCTAssertLessThanOrEqual(measured.width, width + 1)
                XCTAssertGreaterThan(measured.height, 0)
            }
        }
    }

    @MainActor
    func testCompactTodayNavigationFitsPhonesAndAccessibilityText() {
        for width in [320.0, 390.0, 768.0] {
            for textSize in [DynamicTypeSize.large, .accessibility3] {
                let navigation = ATHLTHTrainNavigation(
                    selection: .constant(.today),
                    compact: true
                )
                .environment(\.dynamicTypeSize, textSize)
                let host = UIHostingController(rootView: navigation)
                host.loadViewIfNeeded()
                let measured = host.sizeThatFits(
                    in: CGSize(width: width, height: 300)
                )
                XCTAssertLessThanOrEqual(
                    measured.width, width + 1,
                    "Compact Today navigation exceeds a \(Int(width))-point viewport"
                )
            }
        }
    }

    @MainActor
    func testSharedChromeAndActivityTilesFitCompactAndWideLayoutsWithLargeText() {
        for width in [320.0, 390.0, 768.0] {
            for size in [DynamicTypeSize.large, .accessibility3] {
                for section in [ATHLTHTrainSection.today, .plan, .progress] {
                    let content = VStack(alignment: .leading, spacing: 24) {
                        ATHLTHTrainMasthead(
                            title: "En gjennomtenkt treningsuke",
                            subtitle: "Alle planlagte økter og faktisk gjennomført trening",
                            onLibrary: {})
                        ATHLTHTrainNavigation(selection: .constant(section))
                        ATHLTHTrainActivityTile(title: "Styrketrening", symbol: "dumbbell")
                        ATHLTHTrainMetricTile(title: "Registrerte økter", value: "124", symbol: "calendar")
                    }
                    .padding(17)
                    .environment(\.dynamicTypeSize, size)
                    let host = UIHostingController(rootView: content)
                    host.loadViewIfNeeded()
                    let measured = host.sizeThatFits(in: CGSize(width: width, height: 5_000))
                    XCTAssertLessThanOrEqual(measured.width, width + 1)
                    XCTAssertGreaterThan(measured.height, 0)
                }
            }
        }
    }
    @MainActor
    func testSharedTrainHeaderKeepsSameDimensionsAcrossAllThreeSelections() {
        // The exact same navigation/eyebrow component is used in all
        // three scrollable sections, including the Today cover.
        for width in [320.0, 390.0, 768.0] {
            for typeSize in [DynamicTypeSize.large, .accessibility3] {
                var heights: [CGFloat] = []
                for section in [ATHLTHTrainSection.today, .plan, .progress] {
                    let row = ATHLTHTrainHeaderRow(selection: .constant(section))
                        .environment(\.dynamicTypeSize, typeSize)
                    let host = UIHostingController(rootView: row)
                    host.loadViewIfNeeded()
                    let measured = host.sizeThatFits(
                        in: CGSize(width: width - 40, height: 240))
                    XCTAssertGreaterThan(measured.height, 0)
                    XCTAssertLessThanOrEqual(measured.width, width - 39)
                    heights.append(measured.height)
                }
                XCTAssertLessThanOrEqual(
                    (heights.max() ?? 0) - (heights.min() ?? 0), 1.5,
                    "Switching Train tabs must not resize the shared masthead")
            }
        }
    }



    @MainActor
    func testPlanWeekRowsAndWorkoutCardsFitPhoneAndTabletWidths() throws {
        let suite = "ATHLTHTrainPlanLayout.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = AppSessionStore(defaults: defaults)
        let created = try XCTUnwrap(store.createTrainingPlan(
            title: "Løping og styrke med lang beskrivelse av treningsmålene",
            summary: "Detailed schedule", weekCount: 2,
            startDate: Calendar.current.startOfDay(for: .now)
        ))
        let workout = PlannedSession(
            id: UUID(),
            title: "Lang intervalløkt med oppvarming, hoveddel og nedjogging",
            kind: .running, scheduledStart: nil, durationMinutes: 60,
            targetDistanceKilometers: nil, targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: nil
        )
        store.addSession(
            workout, toDay: created.weeks[0].days[0].id, inPlan: created.id
        )
        let plan = try XCTUnwrap(store.trainingPlan(withID: created.id))
        let week = try XCTUnwrap(plan.weeks.first)

        for viewport in [320.0, 375.0, 393.0, 430.0, 768.0] {
            for textSize in [DynamicTypeSize.large, .accessibility3] {
                let weekView = ATHLTHPlanWeekOverview(
                    week: week, plan: plan,
                    weekday: { _ in "Onsdag" },
                    planDayDate: { _ in .now },
                    isCompleted: { _ in false },
                    onSelectDay: { _ in }
                )
                .padding(.horizontal, 17)
                .environment(\.dynamicTypeSize, textSize)
                let weekHost = UIHostingController(rootView: weekView)
                weekHost.loadViewIfNeeded()
                let weekSize = weekHost.sizeThatFits(
                    in: CGSize(width: viewport, height: 5_000)
                )
                XCTAssertLessThanOrEqual(
                    weekSize.width, viewport + 1,
                    "Plan week rows overflow \(Int(viewport))pt in \(textSize)"
                )
                XCTAssertGreaterThan(weekSize.height, 0)

                let workoutCard = ATHLTHPlanWorkoutExpandableCard(
                    workout: workout, completed: false, skipped: false,
                    onEditBlock: { _, _ in }
                )
                .padding(.horizontal, 17)
                .environment(\.dynamicTypeSize, textSize)
                let workoutHost = UIHostingController(rootView: workoutCard)
                workoutHost.loadViewIfNeeded()
                let workoutSize = workoutHost.sizeThatFits(
                    in: CGSize(width: viewport, height: 2_000)
                )
                XCTAssertLessThanOrEqual(
                    workoutSize.width, viewport + 1,
                    "Workout cards overflow \(Int(viewport))pt in \(textSize)"
                )
                XCTAssertGreaterThan(workoutSize.height, 0)
            }
        }
    }

}

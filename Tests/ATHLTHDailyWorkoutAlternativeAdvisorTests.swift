import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHDailyWorkoutAlternativeAdvisorTests: XCTestCase {
    private func runningSession() -> PlannedSession {
        PlannedSession(
            id: UUID(), title: "Langtur 15 km", kind: .running,
            scheduledStart: Date(),
            durationMinutes: 90, targetDistanceKilometers: 15,
            targetPaceSecondsPerKilometer: 360,
            routeID: UUID(), exercises: [],
            notes: "Build endurance safely"
        )
    }

    private func signals(
        energy: Int? = nil,
        feet: RecoverySorenessLevel? = nil,
        stress: Int? = nil
    ) -> ATHLTHDailyWorkoutAlternativeAdvisor.Signals {
        var muscles: [String: RecoverySorenessLevel] = [:]
        if let feet { muscles["Feet"] = feet }
        return .init(
            energy: energy, stress: stress, overallSoreness: nil,
            muscleRatings: muscles, readiness: nil
        )
    }

    func testExplicitFootSorenessSuggestsAnotherModalityFirst() {
        let recommendations = ATHLTHDailyWorkoutAlternativeAdvisor.suggestions(
            for: runningSession(), signals: signals(feet: .moderate))
        XCTAssertEqual(recommendations.first?.choice, .mobility)
        XCTAssertTrue(recommendations.contains(where: { $0.choice == .rest }))
        XCTAssertFalse(recommendations.contains(where: {
            $0.choice == .shorterRun
        }), "Do not prescribe more impact to relieve reported sore feet")
    }

    func testNoSignalsDoesNotInventNeedToSwap() {
        let suggestions = ATHLTHDailyWorkoutAlternativeAdvisor.suggestions(
            for: runningSession(), signals: signals())
        XCTAssertTrue(suggestions.isEmpty)
    }

    func testLowEnergyMakesCrossTrainingVisibleBeforeShorterRun() {
        let suggestions = ATHLTHDailyWorkoutAlternativeAdvisor.suggestions(
            for: runningSession(), signals: signals(energy: 2))
        XCTAssertEqual(suggestions.first?.choice, .gentleWalk)
        XCTAssertTrue(suggestions.contains(where: { $0.choice == .mobility }))
        XCTAssertTrue(suggestions.contains(where: { $0.choice == .rest }))
        XCTAssertTrue(suggestions.contains(where: { $0.choice == .shorterRun }))
        XCTAssertEqual(suggestions.first(where: {
            $0.choice == .shorterRun
        })?.distanceKilometers, 5)
    }

    func testApprovedMobilitySwapCanBeUndoneWithoutLosingIntervalsOrRoute() throws {
        let original = runningSession()
        let suggestion = try XCTUnwrap(
            ATHLTHDailyWorkoutAlternativeAdvisor.suggestions(
                for: original, signals: signals(feet: .high)).first
        )
        let swapped = ATHLTHDailyWorkoutAlternativeAdvisor.replacing(
            original, with: suggestion
        )
        XCTAssertEqual(swapped.id, original.id)
        XCTAssertEqual(swapped.kind, .mobility)
        XCTAssertNil(swapped.targetDistanceKilometers)
        XCTAssertNil(swapped.routeID)
        XCTAssertEqual(swapped.workoutBlocks?.first?.wellnessKind, .mobility)
        XCTAssertNotNil(swapped.dailyAlternativeOriginal)

        let restored = try XCTUnwrap(
            swapped.dailyAlternativeOriginal?.restoring(swapped))
        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.title, original.title)
        XCTAssertEqual(restored.targetDistanceKilometers, 15)
        XCTAssertEqual(restored.routeID, original.routeID)
        XCTAssertEqual(restored.targetPaceSecondsPerKilometer, 360)
        XCTAssertEqual(restored.notes, original.notes)
        XCTAssertNil(restored.dailyAlternativeOriginal)
    }

    func testRecoveryDayIsDeliberateAndReversible() throws {
        let original = runningSession()
        let choice = try XCTUnwrap(
            ATHLTHDailyWorkoutAlternativeAdvisor.suggestions(
                for: original, signals: signals(feet: .high))
                .first(where: { $0.choice == .rest })
        )
        let swapped = ATHLTHDailyWorkoutAlternativeAdvisor.replacing(
            original, with: choice)
        XCTAssertTrue(swapped.isExplicitRestDay)
        XCTAssertNil(swapped.durationMinutes)
        XCTAssertEqual(swapped.dailyAlternativeOriginal?.kind, .running)
    }

    func testReplacingAlreadySwappedOrRestDayIsNotOffered() throws {
        let original = runningSession()
        let fat = signals(feet: .moderate)
        let choice = try XCTUnwrap(
            ATHLTHDailyWorkoutAlternativeAdvisor.suggestions(
                for: original, signals: fat).first)
        let swapped = ATHLTHDailyWorkoutAlternativeAdvisor.replacing(
            original, with: choice)
        XCTAssertTrue(ATHLTHDailyWorkoutAlternativeAdvisor.suggestions(
            for: swapped, signals: fat).isEmpty)
    }
}

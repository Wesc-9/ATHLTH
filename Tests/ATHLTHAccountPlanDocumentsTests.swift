import Foundation
import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHAccountPlanDocumentsTests: XCTestCase {
    private func plan(owner: UUID) -> TrainingPlan {
        let today = Calendar.current.startOfDay(for: Date())
        return TrainingPlan(id: UUID(), ownerID: owner, title: "My plan", summary: "",
            visibility: .privateOnly, version: 1,
            weeks: [TrainingPlanWeek(id: UUID(), weekNumber: 1, title: "Week 1",
                days: (1...7).map { TrainingPlanDay(id: UUID(), dayIndex: $0, title: "", sessions: []) })],
            tags: [], createdAt: today, updatedAt: today, startDate: today)
    }

    func testNewPlanSavesReusableCopyUnlessOptedOut() throws {
        let suite = "AccountPlanDocuments.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = AppSessionStore(defaults: defaults)
        let source = plan(owner: session.profile.userID)
        XCTAssertTrue(session.addTrainingPlan(source))
        XCTAssertEqual(session.planTemplates.count, 1)
        session.savePlanToLibrary(source)
        XCTAssertEqual(session.planTemplates.count, 1)
        XCTAssertNil(session.planTemplates.first?.startDate)
        XCTAssertTrue(session.deactivateTrainingPlan(source.id))
        XCTAssertTrue(session.addTrainingPlan(plan(owner: session.profile.userID), saveToLibrary: false))
        XCTAssertEqual(session.planTemplates.count, 1)
    }

    func testLibraryDocumentImportsWithoutBecomingActiveOrDuplicating() throws {
        let suite = "AccountPlanDocuments.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = AppSessionStore(defaults: defaults)
        var document = plan(owner: session.profile.userID)
        document.tags = ["sync:template"]
        document.startDate = nil
        XCTAssertTrue(session.importAccountPlanDocument(document))
        XCTAssertTrue(session.importAccountPlanDocument(document))
        XCTAssertNil(session.activePlan)
        XCTAssertTrue(session.trainingPlans.isEmpty)
        XCTAssertEqual(session.planTemplates.count, 1)
        XCTAssertFalse(session.planTemplates[0].tags.contains("sync:template"))
        XCTAssertEqual(session.accountPlanDocument(withID: document.id), document)
    }

    func testDisabledRemotePlanCannotReplaceAnActivePlan() throws {
        let suite = "AccountPlanDocuments.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = AppSessionStore(defaults: defaults)
        let active = plan(owner: session.profile.userID)
        XCTAssertTrue(session.addTrainingPlan(active, saveToLibrary: false))
        var remote = plan(owner: session.profile.userID)
        remote.tags = ["sync:inactive"]
        XCTAssertTrue(session.importAccountPlanDocument(remote))
        XCTAssertEqual(session.activePlan?.id, active.id)
        XCTAssertTrue(session.isTrainingPlanDeactivated(remote.id))
        XCTAssertEqual(session.trainingPlans.count, 2)
        XCTAssertTrue(session.planTemplates.isEmpty)
    }

    func testDifferentAccountDocumentIsRejected() throws {
        let suite = "AccountPlanDocuments.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = AppSessionStore(defaults: defaults)
        XCTAssertFalse(session.importAccountPlanDocument(plan(owner: UUID())))
        XCTAssertTrue(session.trainingPlans.isEmpty)
        XCTAssertTrue(session.planTemplates.isEmpty)
    }
}

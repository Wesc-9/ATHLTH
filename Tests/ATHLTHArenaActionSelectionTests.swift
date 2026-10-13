import Foundation
import XCTest
@testable import ATHLTH

/// The home digest must never let expiring active races crowd out all
/// invitations. It is a bounded preview, not the authoritative series list.
final class ATHLTHArenaActionSelectionTests: XCTestCase {
    private func series(
        _ status: String,
        deadline: Date?,
        id: UUID = UUID()
    ) throws -> ATHLTHArenaRemoteSeries {
        var fields: [String: Any] = [
            "id": id.uuidString,
            "title": "Arena action test",
            "scope": "duel",
            "scoring": "winner",
            "duration_days": 14,
            "status": status
        ]
        if let deadline {
            fields["ends_at"] = ISO8601DateFormatter().string(from: deadline)
        }
        let data = try JSONSerialization.data(withJSONObject: fields)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ATHLTHArenaRemoteSeries.self, from: data)
    }

    func testDraftInvitationsNotStarvedByActiveCompetitions() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let drafts = try (0..<10).map { i in
            try series("draft", deadline: now.addingTimeInterval(Double(500 + i)))
        }
        let active = try (0..<30).map { i in
            try series("active", deadline: now.addingTimeInterval(Double(i)))
        }
        let selected = ATHLTHArenaActionSelection.candidates(
            from: active + drafts
        )
        XCTAssertEqual(selected.count, ATHLTHArenaActionSelection.maxChecked)
        XCTAssertGreaterThanOrEqual(
            selected.filter { $0.status == "draft" }.count, 6
        )
        XCTAssertGreaterThanOrEqual(
            selected.filter { $0.status == "active" }.count, 6
        )
    }

    func testCompletedSeriesNeverConsumesActionScanCapacity() throws {
        let completed = try (0..<30).map { _ in
            try series("completed", deadline: nil)
        }
        let invited = try series("draft", deadline: nil)
        let selected = ATHLTHArenaActionSelection.candidates(
            from: completed + [invited]
        )
        XCTAssertEqual(selected.map(\.id), [invited.id])
    }

    func testUnusedDraftSlotsGoToActiveCompetitions() throws {
        let oneDraft = try series("draft", deadline: nil)
        let active = try (0..<20).map { _ in
            try series("active", deadline: nil)
        }
        let selected = ATHLTHArenaActionSelection.candidates(
            from: active + [oneDraft]
        )
        XCTAssertEqual(selected.count, ATHLTHArenaActionSelection.maxChecked)
        XCTAssertTrue(selected.contains { $0.id == oneDraft.id })
        XCTAssertEqual(Set(selected.map(\.id)).count, selected.count)
    }

    func testStableOrderIgnoresBackendArrayOrder() throws {
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let values = try (0..<18).map { i in
            try series(
                i.isMultiple(of: 2) ? "active" : "draft",
                deadline: timestamp.addingTimeInterval(Double(i / 3) * 60)
            )
        }
        XCTAssertEqual(
            ATHLTHArenaActionSelection.candidates(from: values).map(\.id),
            ATHLTHArenaActionSelection.candidates(from: values.reversed()).map(\.id)
        )
    }
}

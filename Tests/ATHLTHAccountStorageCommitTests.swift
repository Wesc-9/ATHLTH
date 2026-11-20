import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHAccountStorageCommitTests: XCTestCase {
    private struct Unencodable: Encodable {
        enum Failure: Error { case deliberate }
        func encode(to encoder: Encoder) throws {
            throw Failure.deliberate
        }
    }

    func testFailedTrainingWritePreservesLastGoodValueAndDoesNotNotify() throws {
        let name = "ATHLTHStorageCommit.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let owner = UUID()
        var notifications = 0

        try ATHLTHAccountTrainingCommit.save(
            ["existing plan"], userID: owner, defaults: defaults
        ) { notifications += 1 }
        XCTAssertEqual(notifications, 1)
        let baseline = defaults.data(forKey: AccountLocalStorage.key(
            "training", userID: owner
        ))
        XCTAssertNotNil(baseline)

        XCTAssertThrowsError(
            try ATHLTHAccountTrainingCommit.save(
                Unencodable(), userID: owner, defaults: defaults
            ) { notifications += 1 }
        )
        XCTAssertEqual(notifications, 1)
        XCTAssertEqual(defaults.data(forKey: AccountLocalStorage.key(
            "training", userID: owner
        )), baseline)
    }

    func testLegacyMigrationReceiptRequiresCommittedSnapshot() throws {
        let name = "ATHLTHMigrationReceipt.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let owner = UUID()
        let marker = AccountLocalStorage.key("legacyMigrated", userID: owner)

        XCTAssertThrowsError(try ATHLTHAccountTrainingCommit.save(
            Unencodable(), userID: owner, defaults: defaults
        ) {
            defaults.set(true, forKey: marker)
        })
        XCTAssertFalse(defaults.bool(forKey: marker))
        XCTAssertNil(defaults.data(forKey: AccountLocalStorage.key(
            "training", userID: owner
        )))

        try ATHLTHAccountTrainingCommit.save(
            ["kept legacy session"], userID: owner, defaults: defaults
        ) {
            defaults.set(true, forKey: marker)
        }
        XCTAssertTrue(defaults.bool(forKey: marker))
    }

    func testAccountScopedTrainingWriteCannotChangeAnotherAccount() throws {
        let name = "ATHLTHStorageIsolation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let first = UUID(), second = UUID()
        try ATHLTHAccountTrainingCommit.save(
            ["A"], userID: first, defaults: defaults
        ) {}
        try ATHLTHAccountTrainingCommit.save(
            ["B"], userID: second, defaults: defaults
        ) {}
        XCTAssertEqual(AccountLocalStorage.read(
            [String].self, name: "training", userID: first, defaults: defaults
        ), ["A"])
        XCTAssertEqual(AccountLocalStorage.read(
            [String].self, name: "training", userID: second, defaults: defaults
        ), ["B"])
        XCTAssertThrowsError(try ATHLTHAccountTrainingCommit.save(
            Unencodable(), userID: first, defaults: defaults
        ) {})
        XCTAssertEqual(AccountLocalStorage.read(
            [String].self, name: "training", userID: second, defaults: defaults
        ), ["B"])
    }
}

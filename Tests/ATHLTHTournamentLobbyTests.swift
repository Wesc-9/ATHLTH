import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHTournamentLobbyTests: XCTestCase {
    private func sampleDraft(
        exerciseMode: ATHLTHTournamentExerciseMode = .vote
    ) -> ATHLTHTournamentDraft {
        let now = Date(timeIntervalSince1970: 1_795_000_000)
        return ATHLTHTournamentDraft(
            ownerID: UUID(),
            clubID: nil,
            title: "November Cup",
            format: .cup,
            groupSize: 4,
            qualifiersPerGroup: 2,
            participants: [
                .init(id: UUID(),username: "athlete1"),
                .init(id: UUID(),username: "athlete2")
            ],
            warmupRounds: [
                .init(title: "Oppvarming uten poeng")
            ],
            exerciseMode: exerciseMode,
            exerciseCount: 4,
            proposalsCloseAt: now,
            votesCloseAt: now.addingTimeInterval(86_400),
            approvePlayerChanges: true
        )
    }

    func testSportPermissionsAndTimingPersist() throws {
        let base = sampleDraft()
        var changed = base
        changed.allowedActivities = [.running,.strength,.cycling]
        changed.rulesAuthority = .group
        changed.cadenceDays = 2
        changed.completionHours = 48
        let data = try JSONEncoder().encode(changed)
        let decoded = try JSONDecoder().decode(
            ATHLTHTournamentDraft.self, from: data
        )
        XCTAssertEqual(Set(decoded.allowedActivities),
                       Set([.running,.strength,.cycling]))
        XCTAssertEqual(decoded.rulesAuthority,.group)
        XCTAssertEqual(decoded.cadenceDays,2)
        XCTAssertEqual(decoded.completionHours,48)
        XCTAssertEqual(ATHLTHTournamentCadence.title(for: 1),"Hver dag")
        XCTAssertEqual(ATHLTHTournamentCadence.title(for: 14),"Annenhver uke")
        XCTAssertEqual(ATHLTHTournamentCadence.window(48),"2 dager")
    }

    func testOldDraftGetsConservativeSportAndScheduleDefaults() throws {
        let draft = sampleDraft()
        let data = try JSONEncoder().encode(draft)
        var legacy = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        for field in ["allowedActivities","rulesAuthority",
                      "cadenceDays","completionHours"] {
            legacy.removeValue(forKey: field)
        }
        let encoded = try JSONSerialization.data(withJSONObject: legacy)
        let decoded = try JSONDecoder().decode(
            ATHLTHTournamentDraft.self, from: encoded
        )
        XCTAssertEqual(decoded.allowedActivities,[.strength])
        XCTAssertEqual(decoded.rulesAuthority,.owner)
        XCTAssertEqual(decoded.cadenceDays,7)
        XCTAssertEqual(decoded.completionHours,48)
    }

    func testPresetExerciseUsesTypedIDInsteadOfAbsentCatalogID() throws {
        let preset = UUID()
        let row: [String: Any] = [
            "id": UUID().uuidString,
            "tournament_id": UUID().uuidString,
            "exercise_id": NSNull(),
            "activity_template_id": preset.uuidString,
            "suggested_by": UUID().uuidString,
            "created_at": "2026-11-03T10:00:00Z",
            "selected_position": NSNull()
        ]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(
            ATHLTHTournamentExerciseCandidateRemote.self,
            from: JSONSerialization.data(withJSONObject: row)
        )
        XCTAssertNil(decoded.exerciseID)
        XCTAssertEqual(decoded.lookupID,preset)
    }

    func testVotedExerciseRulesPersistAcrossAppRestart() throws {
        let original = sampleDraft()
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(
            ATHLTHTournamentDraft.self,from: data
        )
        XCTAssertEqual(restored.exerciseMode,.vote)
        XCTAssertEqual(restored.exerciseCount,4)
        XCTAssertEqual(restored.votesCloseAt,original.votesCloseAt)
        XCTAssertEqual(restored.proposalsCloseAt,original.proposalsCloseAt)
        XCTAssertTrue(restored.approvePlayerChanges)
        XCTAssertEqual(restored.warmupRounds.count,1)
        XCTAssertFalse(restored.warmupRounds[0].countsForPoints)
        XCTAssertFalse(restored.warmupRounds[0].mayEliminate)
    }

    func testOldTournamentDraftsDecodeWithoutNewLobbyFields() throws {
        let original=sampleDraft()
        let data=try JSONEncoder().encode(original)
        var dictionary=try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        for field in [
            "exerciseMode","exerciseCount","proposalsCloseAt",
            "votesCloseAt","approvePlayerChanges"
        ] {
            dictionary.removeValue(forKey: field)
        }
        let legacy=try JSONSerialization.data(withJSONObject: dictionary)
        let restored=try JSONDecoder().decode(
            ATHLTHTournamentDraft.self,from: legacy
        )
        XCTAssertEqual(restored.exerciseMode,.owner)
        XCTAssertEqual(restored.exerciseCount,4)
        XCTAssertFalse(restored.approvePlayerChanges)
        XCTAssertNil(restored.votesCloseAt)
        XCTAssertEqual(restored.warmupRounds.count,1)
    }

    func testReadyAndRemovalDecodeFromDatabase() throws {
        let owner=UUID()
        let tournament=UUID()
        let response: [String: Any] = [
            "tournament_id":tournament.uuidString,
            "user_id":owner.uuidString,
            "seed":1,
            "response":"accepted",
            "responded_at":"2026-11-03T08:00:00Z",
            "group_index":0,
            "is_ready":true,
            "ready_at":"2026-11-03T08:00:00Z",
            "removed_at":NSNull(),
            "replaced_by":NSNull()
        ]
        let data=try JSONSerialization.data(withJSONObject: response)
        let decoder=JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let row=try decoder.decode(ATHLTHTournamentRemoteEntry.self,from:data)
        XCTAssertEqual(row.userID,owner)
        XCTAssertTrue(row.isReady)
        XCTAssertNil(row.removedAt)
    }

    func testLobbyServerModelsDecodeExerciseAndVoteStatus() throws {
        let id=UUID()
        let candidate=UUID()
        let voter=UUID()
        let exerciseJSON: [String: Any] = [
            "id":id.uuidString,
            "tournament_id":UUID().uuidString,
            "exercise_id":UUID().uuidString,
            "suggested_by":voter.uuidString,
            "created_at":"2026-11-03T10:00:00Z",
            "selected_position":2
        ]
        let decoder=JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let row=try decoder.decode(
            ATHLTHTournamentExerciseCandidateRemote.self,
            from: JSONSerialization.data(withJSONObject:exerciseJSON)
        )
        XCTAssertEqual(row.selectedPosition,2)

        let voteJSON: [String: String] = [
            "candidate_id":candidate.uuidString,
            "voter_id":voter.uuidString
        ]
        let vote=try decoder.decode(
            ATHLTHTournamentExerciseVoteRemote.self,
            from: JSONSerialization.data(withJSONObject:voteJSON)
        )
        XCTAssertEqual(vote.voterID,voter)

        let proofJSON: [String: Any] = [
            "match_exercise_id":UUID().uuidString,
            "user_id":voter.uuidString,
            "submitted_at":"2026-11-03T10:00:00Z",
            "review_status":"submitted"
        ]
        let proof=try decoder.decode(
            ATHLTHTournamentExerciseCompletionRemote.self,
            from: JSONSerialization.data(withJSONObject:proofJSON)
        )
        XCTAssertEqual(proof.reviewStatus,"submitted")
    }
}

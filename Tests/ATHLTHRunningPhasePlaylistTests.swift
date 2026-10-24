import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHRunningPhasePlaylistTests: XCTestCase {
    func testPerPhasePlaylistSurvivesTemplateRoundTrip() throws {
        let playlist = SpotifyPlaylistReference(
            id: "abc123",
            name: "Intervals",
            uri: "spotify:playlist:abc123",
            artworkURL: nil,
            ownerName: "Test"
        )
        let interval = RunningWorkoutBlock(
            kind: .work,
            title: "4 x 4",
            repetitions: 4,
            work: .time(240),
            recovery: .time(120),
            spotifyPlaylist: playlist
        )
        let warmup = RunningWorkoutBlock(
            kind: .warmup,
            title: "Warm up",
            work: .time(600)
        )
        let now = Date()
        let workout = RunningWorkoutTemplate(
            id: UUID(),
            title: "Interval day",
            type: .intervals,
            summary: "",
            blocks: [warmup, interval],
            routeID: nil,
            isBuiltIn: false,
            createdAt: now,
            updatedAt: now
        )

        let restored = try JSONDecoder().decode(
            RunningWorkoutTemplate.self,
            from: JSONEncoder().encode(workout)
        )
        XCTAssertNil(restored.blocks[0].spotifyPlaylist)
        XCTAssertEqual(restored.blocks[1].spotifyPlaylist?.uri, playlist.uri)
        XCTAssertEqual(restored.blocks[1].spotifyPlaylist?.name, "Intervals")
    }

    func testExistingIntervalWithoutPlaylistStillDecodes() throws {
        let legacy = RunningWorkoutBlock(
            kind: .work,
            title: "Intervals",
            repetitions: 5,
            work: .time(180),
            recovery: .time(90)
        )
        let data = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(RunningWorkoutBlock.self, from: data)
        XCTAssertNil(decoded.spotifyPlaylist)
        XCTAssertEqual(decoded.repetitions, 5)
        XCTAssertEqual(decoded.work.durationSeconds, 180)
    }
}

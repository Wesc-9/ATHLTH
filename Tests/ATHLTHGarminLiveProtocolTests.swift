import XCTest
@testable import ATHLTH

final class ATHLTHGarminLiveProtocolTests: XCTestCase {
    func testPreparedDoesNotMeanRecording() throws {
        let request = ATHLTHGarminLiveRequest(sport: .running)
        let device = UUID()
        var handshake = ATHLTHGarminLiveHandshake(request: request, deviceID: device)
        func event(_ seq: Int, _ phase: String) throws -> ATHLTHGarminLiveEvent {
            try XCTUnwrap(ATHLTHGarminLiveEvent(message: [
                "v": 1, "kind": "event", "id": request.id.uuidString,
                "seq": seq, "state": phase
            ]))
        }
        XCTAssertTrue(handshake.receive(try event(1, "ready"), from: device))
        XCTAssertFalse(handshake.confirmedRecording)
        XCTAssertTrue(handshake.receive(try event(2, "recording"), from: device))
        XCTAssertTrue(handshake.confirmedRecording)
        XCTAssertTrue(handshake.needsReconciliation)
        XCTAssertFalse(handshake.receive(try event(2, "saved"), from: device))
        XCTAssertFalse(handshake.receive(try event(3, "saved"), from: UUID()))
        XCTAssertTrue(handshake.receive(try event(4, "saved"), from: device))
        XCTAssertFalse(handshake.needsReconciliation)
        XCTAssertFalse(handshake.receive(try event(5, "recording"), from: device))
    }

    func testOptionalDeviceMetadataDoesNotConfirmRecording() throws {
        let request = ATHLTHGarminLiveRequest(sport: .running)
        let device = UUID()
        var handshake = ATHLTHGarminLiveHandshake(request: request, deviceID: device)
        let ready = try XCTUnwrap(ATHLTHGarminLiveEvent(message: [
            "v": 1, "kind": "event", "id": request.id.uuidString,
            "seq": 1, "state": "ready", "firmwareVersion": "27.1", "partNumber": "test-part"
        ]))
        XCTAssertEqual(ready.firmwareVersion, "27.1")
        XCTAssertEqual(ready.partNumber, "test-part")
        XCTAssertTrue(handshake.receive(ready, from: device))
        XCTAssertFalse(handshake.confirmedRecording)
    }

    func testInvalidPayloadAndMissingMeasurements() throws {
        XCTAssertNil(ATHLTHGarminLiveEvent(message: ["v": 2]))
        let request = ATHLTHGarminLiveRequest(sport: .strength)
        let event = try XCTUnwrap(ATHLTHGarminLiveEvent(message: [
            "v": 1, "kind": "event", "id": request.id.uuidString,
            "seq": 1, "state": "recording", "bpm": -1, "meters": Double.infinity
        ]))
        XCTAssertNil(event.bpm)
        XCTAssertNil(event.meters)
        XCTAssertNil(event.seconds)
    }
}

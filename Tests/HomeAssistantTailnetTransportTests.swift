import Foundation
import XCTest
@testable import ATHLTH

@MainActor
final class HomeAssistantTailnetTransportTests: XCTestCase {
    func testTailscaleIPv4HTTPClassification() {
        XCTAssertTrue(HomeAssistantConnectionStore.isTailnetHTTPAddress(
            "100.102.222.20:8123"
        ))
        XCTAssertTrue(HomeAssistantConnectionStore.isTailnetHTTPAddress(
            "http://100.64.0.1:8123"
        ))
        XCTAssertTrue(HomeAssistantConnectionStore.isTailnetHTTPAddress(
            "http://100.127.255.254:8123"
        ))
        XCTAssertFalse(HomeAssistantConnectionStore.isTailnetHTTPAddress(
            "http://100.63.255.255:8123"
        ))
        XCTAssertFalse(HomeAssistantConnectionStore.isTailnetHTTPAddress(
            "http://100.128.0.1:8123"
        ))
        XCTAssertFalse(HomeAssistantConnectionStore.isTailnetHTTPAddress(
            "http://8.8.8.8:8123"
        ))
        XCTAssertFalse(HomeAssistantConnectionStore.isTailnetHTTPAddress(
            "https://device.tailnet.ts.net"
        ))
        XCTAssertFalse(HomeAssistantConnectionStore.isTailnetHTTPAddress(
            "http://100.102.222.999:8123"
        ))
    }

    func testScopedATSExceptionDoesNotDisableGlobalATS() {
        let ats = Bundle.main.object(
            forInfoDictionaryKey: "NSAppTransportSecurity"
        ) as? [String: Any]
        let exceptionDomains = ats?["NSExceptionDomains"] as? [String: Any]
        let cidr = exceptionDomains?["100.64.0.0/10"] as? [String: Any]
        XCTAssertEqual(ats?["NSAllowsLocalNetworking"] as? Bool, true)
        XCTAssertEqual(cidr?["NSExceptionAllowsInsecureHTTPLoads"] as? Bool, true)
        XCTAssertNil(ats?["NSAllowsArbitraryLoads"])
        XCTAssertEqual(exceptionDomains?.count, 1)
    }
}

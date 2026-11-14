import XCTest
@testable import ATHLTH

final class PublicRouteBrowseRegressionTests: XCTestCase {
    func testRouteLibrarySeparatesPublicAndSavedCollections() {
        XCTAssertEqual(
            RouteLibraryCollection.allCases,
            [.publicRoutes, .savedRoutes]
        )
        XCTAssertNotEqual(
            RouteLibraryCollection.publicRoutes.id,
            RouteLibraryCollection.savedRoutes.id
        )
        XCTAssertFalse(RouteLibraryCollection.publicRoutes.title.isEmpty)
        XCTAssertFalse(RouteLibraryCollection.savedRoutes.title.isEmpty)
    }

    func testPublicFiltersOnlyOfferAllFavoritesAndMutualFriends() {
        XCTAssertEqual(
            PublicRouteBrowseFilter.allCases,
            [.all, .favorites, .friends]
        )
        XCTAssertEqual(PublicRouteBrowseFilter.friends.rawValue, "friends")
    }

    func testPublicCataloguePassesMutualFriendFilterToServerBeforePaging() throws {
        let params = RouteCatalogSearchParameters(
            p_query: "Fauske",
            p_sort: "Newest",
            p_length: 0,
            p_latitude: nil,
            p_longitude: nil,
            p_offset: 50,
            p_friends_only: true,
            p_min_length: 0,
            p_max_length: 20
        )
        let data = try JSONEncoder().encode(params)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(object["p_friends_only"] as? Bool, true)
        XCTAssertEqual(object["p_offset"] as? Int, 50)
        XCTAssertEqual(object["p_query"] as? String, "Fauske")
    }

    func testPublicRouteCatalogueDecodesOwnerAndDistanceForFriendCards() throws {
        let json = """
        {
          "id": "9E7D4D84-2021-42EE-85C7-59BFB85320EA",
          "owner_id": "03A07816-BAF7-4DA0-99D6-252BDA4590B3",
          "title": "Skogsløypa",
          "distance_kilometers": 7.5,
          "elevation_gain_meters": 110.0,
          "start_name": "Start",
          "end_name": "Mål",
          "center_latitude": 67.25,
          "center_longitude": 15.4,
          "created_at": "2026-10-21T12:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try decoder.decode(RouteLibraryEntry.self, from: Data(json.utf8))
        XCTAssertEqual(entry.title, "Skogsløypa")
        XCTAssertEqual(entry.distanceKilometers, 7.5, accuracy: 0.001)
        XCTAssertEqual(entry.ownerID.uuidString.lowercased(),
                       "03a07816-baf7-4da0-99d6-252bda4590b3")
    }

    func testUnifiedPublicTrailsDecodeAsLightweightEntries() throws {
        let json = """
        {
          "id": "B33A4A12-EB92-4122-9CD0-198D103A6235",
          "owner_id": "00000000-0000-0000-0000-000000000001",
          "title": "Havsteinrunden",
          "distance_kilometers": 6.8,
          "elevation_gain_meters": null,
          "start_name": null,
          "end_name": null,
          "center_latitude": 63.41,
          "center_longitude": 10.36,
          "created_at": "2026-11-14T10:00:00Z",
          "source_type": "public_trail",
          "visibility": "public",
          "source_label": "openstreetmap"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try decoder.decode(RouteLibraryEntry.self, from: Data(json.utf8))
        XCTAssertTrue(entry.isPublicTrail)
        XCTAssertFalse(entry.isFriendsOnly)
        XCTAssertEqual(entry.distanceKilometers, 6.8, accuracy: 0.001)
        XCTAssertEqual(entry.sourceType, "public_trail")
        XCTAssertEqual(entry.sourceLabel, "openstreetmap")
    }

    func testFriendsOnlyRouteRequiresItsOwnVisibilityMarker() throws {
        let json = """
        {
          "id": "9E7D4D84-2021-42EE-85C7-59BFB85320EA",
          "owner_id": "03A07816-BAF7-4DA0-99D6-252BDA4590B3",
          "title": "Venneløypa",
          "distance_kilometers": 7.5,
          "elevation_gain_meters": 110,
          "start_name": "Start",
          "end_name": "Mål",
          "center_latitude": 67.25,
          "center_longitude": 15.4,
          "created_at": "2026-10-21T12:00:00Z",
          "source_type": "community",
          "visibility": "friends",
          "source_label": null
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try decoder.decode(RouteLibraryEntry.self, from: Data(json.utf8))
        XCTAssertTrue(entry.isFriendsOnly)
        XCTAssertFalse(entry.isPublicTrail)
        XCTAssertEqual(entry.visibility, "friends")
    }

    func testCustomLengthRangeIsSentToServer() throws {
        let params = RouteCatalogSearchParameters(
            p_query: "",
            p_sort: "Shortest",
            p_length: 6,
            p_latitude: nil,
            p_longitude: nil,
            p_offset: 0,
            p_friends_only: false,
            p_min_length: 3,
            p_max_length: 12
        )
        let data = try JSONEncoder().encode(params)
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(payload["p_min_length"] as? Double, 3)
        XCTAssertEqual(payload["p_max_length"] as? Double, 12)
        XCTAssertEqual(payload["p_length"] as? Int, 6)
    }
}

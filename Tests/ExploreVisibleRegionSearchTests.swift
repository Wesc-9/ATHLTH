import CoreLocation
import MapKit
import XCTest
@testable import ATHLTH

final class ExploreVisibleRegionSearchTests: XCTestCase {
    private let trondheim = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 63.4305, longitude: 10.3951),
        span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
    )

    func testViewportBoundsIncludeOnlyRoutesInDisplayedArea() throws {
        let bounds = try XCTUnwrap(RouteDiscoveryRegionBounds(region: trondheim))
        XCTAssertTrue(bounds.contains(latitude: 63.4305, longitude: 10.3951))
        XCTAssertTrue(bounds.contains(latitude: 63.45, longitude: 10.40))
        XCTAssertFalse(bounds.contains(latitude: 59.91, longitude: 10.75))
        XCTAssertFalse(bounds.contains(latitude: 63.60, longitude: 10.40))
    }

    func testZoomOrPanRequiresManualSearch() {
        XCTAssertFalse(ExploreVisibleRegionSearchPolicy.needsSearch(
            current: trondheim, lastSearched: trondheim
        ))
        var zoom = trondheim
        zoom.span.latitudeDelta *= 2
        zoom.span.longitudeDelta *= 2
        XCTAssertTrue(ExploreVisibleRegionSearchPolicy.needsSearch(
            current: zoom, lastSearched: trondheim
        ))
        var pan = trondheim
        pan.center.longitude += 0.08
        XCTAssertTrue(ExploreVisibleRegionSearchPolicy.needsSearch(
            current: pan, lastSearched: trondheim
        ))
    }

    func testTinyCameraJitterDoesNotRepeatedlyPromptSearch() {
        var jitter = trondheim
        jitter.center.latitude += 0.00001
        jitter.span.longitudeDelta += 0.00001
        XCTAssertFalse(ExploreVisibleRegionSearchPolicy.needsSearch(
            current: jitter, lastSearched: trondheim
        ))
    }

    func testDatelineAndInvalidRegions() throws {
        let dateline = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 60, longitude: 179.9),
            span: MKCoordinateSpan(latitudeDelta: 0.4, longitudeDelta: 1)
        )
        let bounds = try XCTUnwrap(RouteDiscoveryRegionBounds(region: dateline))
        XCTAssertNil(bounds.west)
        XCTAssertNil(bounds.east)
        XCTAssertTrue(bounds.contains(latitude: 60, longitude: -179.9))
        XCTAssertFalse(bounds.contains(latitude: 60, longitude: 10))

        let invalid = MKCoordinateRegion(
            center: trondheim.center,
            span: MKCoordinateSpan(latitudeDelta: 0, longitudeDelta: 0.1)
        )
        XCTAssertNil(RouteDiscoveryRegionBounds(region: invalid))
    }
    func testAreaSearchUsesOnePillForIdleAndActiveRequest() {
        XCTAssertTrue(ExploreVisibleRegionSearchPolicy.showsSearchControl(
            hasVisibleRegion: true, needsSearch: true, isSearching: false
        ))
        // During the query the search button becomes the loading indicator;
        // the legacy secondary status capsule must not be shown too.
        XCTAssertTrue(ExploreVisibleRegionSearchPolicy.showsSearchControl(
            hasVisibleRegion: true, needsSearch: true, isSearching: true
        ))
        XCTAssertTrue(ExploreVisibleRegionSearchPolicy.showsSearchControl(
            hasVisibleRegion: true, needsSearch: false, isSearching: true
        ))
        XCTAssertFalse(ExploreVisibleRegionSearchPolicy.showsSearchControl(
            hasVisibleRegion: true, needsSearch: false, isSearching: false
        ))
        XCTAssertFalse(ExploreVisibleRegionSearchPolicy.showsSearchControl(
            hasVisibleRegion: false, needsSearch: true, isSearching: false
        ))
    }

}

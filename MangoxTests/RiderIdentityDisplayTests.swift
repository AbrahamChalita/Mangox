import XCTest
@testable import Mangox

final class RiderIdentityDisplayTests: XCTestCase {

    override func tearDown() {
        RidePreferences.shared.riderDisplayName = ""
        super.tearDown()
    }

    func testResolvedTitlePrefersLocalOverStrava() {
        RidePreferences.shared.riderDisplayName = "Alex"
        XCTAssertEqual(RiderIdentityDisplay.resolvedTitle(stravaDisplayName: "Strava Person"), "Alex")
    }

    func testResolvedTitleFallsBackToStravaThenMangox() {
        RidePreferences.shared.riderDisplayName = "   "
        XCTAssertEqual(RiderIdentityDisplay.resolvedTitle(stravaDisplayName: "Sam Rider"), "Sam Rider")
        XCTAssertEqual(RiderIdentityDisplay.resolvedTitle(stravaDisplayName: nil), "Mangox")
        XCTAssertEqual(RiderIdentityDisplay.resolvedTitle(stravaDisplayName: "  "), "Mangox")
    }

    func testPersonalizationNameNilWhenUnset() {
        RidePreferences.shared.riderDisplayName = ""
        XCTAssertNil(RiderIdentityDisplay.personalizationName(stravaDisplayName: nil))
        XCTAssertNil(RiderIdentityDisplay.personalizationName(stravaDisplayName: "  "))
    }

    func testPersonalizationNameUsesLocal() {
        RidePreferences.shared.riderDisplayName = "Jordan"
        XCTAssertEqual(RiderIdentityDisplay.personalizationName(stravaDisplayName: "Other"), "Jordan")
    }
}

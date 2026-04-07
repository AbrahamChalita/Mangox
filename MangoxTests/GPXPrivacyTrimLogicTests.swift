import Mangox
import Testing

struct GPXPrivacyTrimLogicTests {

    @Test func trimStartDropsEarlyPoints() {
        #expect(
            GPXPrivacyTrimLogic.isExcluded(
                cumulativeDistanceAlongRoute: 100,
                trimStartMeters: 500,
                trimEndMeters: 0,
                routeLengthMeters: 10_000
            ))
    }

    @Test func trimEndDropsLatePoints() {
        #expect(
            GPXPrivacyTrimLogic.isExcluded(
                cumulativeDistanceAlongRoute: 9_900,
                trimStartMeters: 0,
                trimEndMeters: 500,
                routeLengthMeters: 10_000
            ))
    }

    @Test func midRoutePointNotExcludedWithSymmetricTrim() {
        #expect(
            !GPXPrivacyTrimLogic.isExcluded(
                cumulativeDistanceAlongRoute: 5_000,
                trimStartMeters: 500,
                trimEndMeters: 500,
                routeLengthMeters: 10_000
            ))
    }

    @Test func noTrimNeverExcludes() {
        #expect(
            !GPXPrivacyTrimLogic.isExcluded(
                cumulativeDistanceAlongRoute: 0,
                trimStartMeters: 0,
                trimEndMeters: 0,
                routeLengthMeters: 10_000
            ))
    }
}

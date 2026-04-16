import Foundation
import Testing
@testable import Mangox

struct InstagramStoryCardSessionKindTests {

    @Test func outdoorWhenRouteNamePassed() {
        let w = Workout(startDate: Date())
        w.duration = 3600
        w.elevationGain = 0
        #expect(
            InstagramStoryCardSessionKind.resolve(workout: w, routeName: "Alpe", totalElevationGain: 0) == .outdoor
        )
    }

    @Test func outdoorWhenElevationHigh() {
        let w = Workout(startDate: Date())
        w.duration = 3600
        w.elevationGain = 0
        #expect(
            InstagramStoryCardSessionKind.resolve(workout: w, routeName: nil, totalElevationGain: 120) == .outdoor
        )
    }

    @Test func indoorTrainerWhenNoRouteAndLowElevation() {
        let w = Workout(startDate: Date())
        w.duration = 3600
        w.elevationGain = 10
        #expect(
            InstagramStoryCardSessionKind.resolve(workout: w, routeName: nil, totalElevationGain: 10) == .indoorTrainer
        )
    }

    @Test func unknownWhenElevationInGrayZone() {
        let w = Workout(startDate: Date())
        w.duration = 3600
        w.elevationGain = 40
        #expect(
            InstagramStoryCardSessionKind.resolve(workout: w, routeName: nil, totalElevationGain: 0) == .unknown
        )
    }

    @Test func outdoorWhenSavedRouteIsGpxWithoutName() {
        let w = Workout(startDate: Date())
        w.duration = 3600
        w.elevationGain = 5
        w.savedRouteKind = .gpx
        w.savedRouteName = nil
        #expect(
            InstagramStoryCardSessionKind.resolve(workout: w, routeName: nil, totalElevationGain: 0) == .outdoor
        )
    }

    @Test func outdoorWhenGrayElevationButRoadLikeDistance() {
        let w = Workout(startDate: Date())
        w.duration = 7200
        w.distance = 40_000
        w.elevationGain = 35
        #expect(
            InstagramStoryCardSessionKind.resolve(workout: w, routeName: nil, totalElevationGain: 0) == .outdoor
        )
    }
}

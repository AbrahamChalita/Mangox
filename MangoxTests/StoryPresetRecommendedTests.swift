import Foundation
import Testing
@testable import Mangox

@MainActor
struct StoryPresetRecommendedTests {

    @Test func nightRideBeforeSix() {
        #expect(InstagramStoryCardOptions.StoryPreset.recommended(hour: 5, elevationMeters: 0) == .nightRide)
    }

    @Test func nightRideAtOrAfterEightPM() {
        #expect(InstagramStoryCardOptions.StoryPreset.recommended(hour: 20, elevationMeters: 0) == .nightRide)
        #expect(InstagramStoryCardOptions.StoryPreset.recommended(hour: 23, elevationMeters: 0) == .nightRide)
    }

    @Test func dawnGradientInEarlyMorning() {
        #expect(InstagramStoryCardOptions.StoryPreset.recommended(hour: 6, elevationMeters: 0) == .dawnGradient)
        #expect(InstagramStoryCardOptions.StoryPreset.recommended(hour: 7, elevationMeters: 0) == .dawnGradient)
    }

    @Test func sunsetMangoInEvening() {
        #expect(InstagramStoryCardOptions.StoryPreset.recommended(hour: 18, elevationMeters: 0) == .sunsetMango)
        #expect(InstagramStoryCardOptions.StoryPreset.recommended(hour: 19, elevationMeters: 0) == .sunsetMango)
    }

    @Test func mountainSilhouetteWhenHighElevationDuringDay() {
        #expect(InstagramStoryCardOptions.StoryPreset.recommended(hour: 10, elevationMeters: 600) == .mountainSilhouette)
    }

    @Test func atmosphericFallbackForLowElevationDaytime() {
        #expect(InstagramStoryCardOptions.StoryPreset.recommended(hour: 10, elevationMeters: 120) == .darkAtmospheric)
    }

    @Test func timeOfDayWinsOverElevation() {
        #expect(InstagramStoryCardOptions.StoryPreset.recommended(hour: 22, elevationMeters: 1200) == .nightRide)
    }
}

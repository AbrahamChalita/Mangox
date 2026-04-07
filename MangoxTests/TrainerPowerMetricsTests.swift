import Foundation
import Testing
@testable import Mangox

struct TrainerPowerMetricsTests {

    @Test func meanInt_matchesArithmeticMean() {
        #expect(TrainerPowerMetrics.meanInt(samples: [100, 200, 300]) == 200)
        #expect(TrainerPowerMetrics.meanInt(samples: [400]) == 400)
        #expect(TrainerPowerMetrics.meanInt(samples: []) == 0)
    }

    @Test func peakInt_isMaximumSample() {
        #expect(TrainerPowerMetrics.peakInt(samples: [100, 400, 300]) == 400)
        #expect(TrainerPowerMetrics.peakInt(samples: [50]) == 50)
        #expect(TrainerPowerMetrics.peakInt(samples: []) == 0)
    }

    @Test func indoorPowerHeroPreference_roundTripThroughUserDefaults() {
        let prefs = RidePreferences.shared
        let saved = prefs.indoorPowerHeroMode
        defer { prefs.indoorPowerHeroMode = saved }

        prefs.indoorPowerHeroMode = .threeSecond
        #expect(prefs.indoorPowerHeroMode == .threeSecond)
        #expect(UserDefaults.standard.string(forKey: "ride_pref_indoor_power_hero_v1") == IndoorPowerHeroMode.threeSecond.rawValue) // matches RidePreferences.Key

        prefs.indoorPowerHeroMode = .oneSecond
        #expect(prefs.indoorPowerHeroMode == .oneSecond)
    }
}

import Testing
@testable import Mangox

@MainActor
struct AerobicDecouplingAnalyticsTests {
    @Test func steadyRideWithFlatHeartRate_isStable() {
        let samples = (0..<2400).map {
            AerobicDecouplingAnalytics.Sample(elapsedSeconds: $0, power: 180, heartRate: 135)
        }

        let result = AerobicDecouplingAnalytics.compute(samples: samples)

        #expect(result?.status == .stable)
        #expect(abs(result?.decouplingPercent ?? 999) < 0.1)
    }

    @Test func risingHeartRateAtSamePower_isHighDrift() {
        let samples = (0..<2400).map { second in
            AerobicDecouplingAnalytics.Sample(
                elapsedSeconds: second,
                power: 180,
                heartRate: second < 1200 ? 130 : 146
            )
        }

        let result = AerobicDecouplingAnalytics.compute(samples: samples)

        #expect(result?.status == .highDrift)
        #expect((result?.decouplingPercent ?? 0) > 10)
    }

    @Test func shortRide_returnsNil() {
        let samples = (0..<300).map {
            AerobicDecouplingAnalytics.Sample(elapsedSeconds: $0, power: 180, heartRate: 135)
        }

        #expect(AerobicDecouplingAnalytics.compute(samples: samples) == nil)
    }
}

import Testing
@testable import Mangox

struct CriticalPowerModelTests {
    @Test func fit_requiresAtLeastThreeLongEfforts() {
        let points = [
            PowerCurveAnalytics.Point(durationSeconds: 300, watts: 320),
            PowerCurveAnalytics.Point(durationSeconds: 1200, watts: 280),
        ]

        #expect(CriticalPowerModel.fit(from: points) == nil)
    }

    @Test func fit_recoversReasonableCPAndWPrime() {
        let cp = 260.0
        let wPrime = 20000.0
        let durations = [180, 300, 480, 720, 1200]
        let points = durations.map { duration in
            let power = cp + wPrime / Double(duration)
            return PowerCurveAnalytics.Point(durationSeconds: duration, watts: Int(power.rounded()))
        }

        let fit = CriticalPowerModel.fit(from: points)

        #expect(fit != nil)
        #expect(abs(Double(fit!.criticalPowerWatts) - cp) < 15)
        #expect(abs(Double(fit!.wPrimeJoules) - wPrime) < 5000)
        #expect(fit!.rSquared > 0.95)
    }

    @Test func predictedPower_matchesModel() {
        let fit = CriticalPowerModel.Fit(
            criticalPowerWatts: 250,
            wPrimeJoules: 18000,
            rSquared: 0.98,
            sampleCount: 4
        )

        let p = CriticalPowerModel.predictedPower(durationSeconds: 600, fit: fit)

        #expect(p == 280)
    }
}

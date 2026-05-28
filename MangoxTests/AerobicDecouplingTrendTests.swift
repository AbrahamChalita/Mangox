import Foundation
import Testing
@testable import Mangox

struct AerobicDecouplingTrendTests {
    @Test func insufficientRides_returnsInsufficientData() {
        let rides = [
            AerobicDecouplingTrend.RideSample(
                date: .now,
                decouplingPercent: 4.0,
                status: .stable
            ),
        ]

        let result = AerobicDecouplingTrend.analyze(rides: rides)

        #expect(result.direction == AerobicDecouplingTrend.Direction.insufficientData)
        #expect(result.isSignificant == false)
    }

    @Test func worseningSlope_isSignificant() {
        let base = Date(timeIntervalSince1970: 0)
        let rides = (0..<4).map { index in
            AerobicDecouplingTrend.RideSample(
                date: base.addingTimeInterval(Double(index) * 86_400),
                decouplingPercent: 3.0 + Double(index) * 1.5,
                status: index >= 2 ? .moderateDrift : .stable
            )
        }

        let result = AerobicDecouplingTrend.analyze(rides: rides)

        #expect(result.direction == AerobicDecouplingTrend.Direction.worsening)
        #expect(result.isSignificant)
        #expect(result.slopePercentPerRide > 0)
    }

    @Test func improvingSlope_isDetected() {
        let base = Date(timeIntervalSince1970: 0)
        let rides = (0..<4).map { index in
            AerobicDecouplingTrend.RideSample(
                date: base.addingTimeInterval(Double(index) * 86_400),
                decouplingPercent: 12.0 - Double(index) * 1.2,
                status: .moderateDrift
            )
        }

        let result = AerobicDecouplingTrend.analyze(rides: rides)

        #expect(result.direction == AerobicDecouplingTrend.Direction.improving)
        #expect(result.slopePercentPerRide < 0)
    }

    @Test func flatValues_areStable() {
        let rides = (0..<5).map { index in
            AerobicDecouplingTrend.RideSample(
                date: Date(timeIntervalSince1970: Double(index) * 86_400),
                decouplingPercent: 4.2,
                status: .stable
            )
        }

        let result = AerobicDecouplingTrend.analyze(rides: rides)

        #expect(result.direction == AerobicDecouplingTrend.Direction.stable)
        #expect(abs(result.slopePercentPerRide) < 0.01)
    }
}

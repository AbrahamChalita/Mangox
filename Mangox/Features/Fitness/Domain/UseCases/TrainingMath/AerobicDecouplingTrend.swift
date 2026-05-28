// Features/Fitness/Domain/UseCases/TrainingMath/AerobicDecouplingTrend.swift
import Foundation

/// Multi-ride aerobic decoupling trend (slope + significance) for coach snapshots and tools.
/// Wraps per-ride `AerobicDecouplingAnalytics` results — pure, testable, no SwiftData.
nonisolated enum AerobicDecouplingTrend {

    struct RideSample: Sendable, Equatable {
        let date: Date
        let decouplingPercent: Double
        let status: AerobicDecouplingAnalytics.Status
    }

    enum Direction: String, Sendable, Codable {
        case improving
        case stable
        case worsening
        case insufficientData
    }

    struct Result: Sendable, Equatable {
        let analyzedRideCount: Int
        /// Linear slope of decoupling % vs ride order (positive = drift worsening over time).
        let slopePercentPerRide: Double
        let direction: Direction
        /// True when enough rides and |slope| exceeds the significance threshold.
        let isSignificant: Bool
        let latestDecouplingPercent: Double?
        let averageDecouplingPercent: Double?
        let latestStatus: AerobicDecouplingAnalytics.Status?

        var plainLanguageSummary: String {
            switch direction {
            case .insufficientData:
                return "Not enough steady endurance rides with power and HR for a decoupling trend."
            case .improving:
                if isSignificant {
                    return String(
                        format: "Aerobic drift is improving across %d rides (slope %+.2f%%/ride, avg %.1f%%).",
                        analyzedRideCount,
                        slopePercentPerRide,
                        averageDecouplingPercent ?? 0
                    )
                }
                return String(
                    format: "Aerobic drift is slightly improving (avg %.1f%% over %d rides).",
                    averageDecouplingPercent ?? 0,
                    analyzedRideCount
                )
            case .stable:
                return String(
                    format: "Aerobic drift is stable (avg %.1f%% over %d rides).",
                    averageDecouplingPercent ?? 0,
                    analyzedRideCount
                )
            case .worsening:
                if isSignificant {
                    return String(
                        format: "Aerobic drift is worsening across %d rides (slope %+.2f%%/ride); keep endurance progression conservative.",
                        analyzedRideCount,
                        slopePercentPerRide
                    )
                }
                return String(
                    format: "Aerobic drift may be creeping up (avg %.1f%% over %d rides).",
                    averageDecouplingPercent ?? 0,
                    analyzedRideCount
                )
            }
        }
    }

    /// Minimum rides with valid decoupling to compute a trend.
    nonisolated static let minimumRides = 3

    /// |slope| above this (percent per ride) counts as a meaningful trend.
    nonisolated static let significanceSlopeThreshold = 0.35

    /// Rides should be oldest-first for a chronological slope.
    nonisolated static func analyze(rides: [RideSample]) -> Result {
        let valid = rides.filter { $0.status != .insufficientData }
        guard valid.count >= minimumRides else {
            return Result(
                analyzedRideCount: valid.count,
                slopePercentPerRide: 0,
                direction: .insufficientData,
                isSignificant: false,
                latestDecouplingPercent: valid.last?.decouplingPercent,
                averageDecouplingPercent: average(valid.map(\.decouplingPercent)),
                latestStatus: valid.last?.status
            )
        }

        let slope = linearSlope(y: valid.map(\.decouplingPercent))
        let direction = classify(slope: slope)
        let significant = abs(slope) >= significanceSlopeThreshold

        return Result(
            analyzedRideCount: valid.count,
            slopePercentPerRide: slope,
            direction: direction,
            isSignificant: significant,
            latestDecouplingPercent: valid.last?.decouplingPercent,
            averageDecouplingPercent: average(valid.map(\.decouplingPercent)),
            latestStatus: valid.last?.status
        )
    }

    private nonisolated static func linearSlope(y: [Double]) -> Double {
        guard y.count >= 2 else { return 0 }
        let n = Double(y.count)
        let xMean = (n - 1) / 2
        let yMean = y.reduce(0, +) / n
        var numerator = 0.0
        var denominator = 0.0
        for (index, value) in y.enumerated() {
            let x = Double(index)
            numerator += (x - xMean) * (value - yMean)
            denominator += (x - xMean) * (x - xMean)
        }
        guard denominator > 0 else { return 0 }
        return numerator / denominator
    }

    private nonisolated static func classify(slope: Double) -> Direction {
        if slope <= -significanceSlopeThreshold { return .improving }
        if slope >= significanceSlopeThreshold { return .worsening }
        return .stable
    }

    private nonisolated static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

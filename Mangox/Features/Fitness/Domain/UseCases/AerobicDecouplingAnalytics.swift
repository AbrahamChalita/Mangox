// Features/Fitness/Domain/UseCases/AerobicDecouplingAnalytics.swift
import Foundation

/// Estimates Pw:HR aerobic decoupling for steady endurance-style rides.
/// Positive values mean heart rate rose relative to power in the second half.
enum AerobicDecouplingAnalytics {
    struct Sample: Sendable {
        let elapsedSeconds: Int
        let power: Int
        let heartRate: Int
    }

    enum Status: String, Codable, Sendable {
        case stable
        case moderateDrift
        case highDrift
        case insufficientData
    }

    struct Result: Codable, Sendable {
        let decouplingPercent: Double
        let firstHalfEfficiency: Double
        let secondHalfEfficiency: Double
        let validSeconds: Int
        let status: Status

        var plainLanguageSummary: String {
            switch status {
            case .stable:
                return String(format: "Aerobic drift stayed low at %.1f%%.", decouplingPercent)
            case .moderateDrift:
                return String(format: "Aerobic drift was moderate at %.1f%%.", decouplingPercent)
            case .highDrift:
                return String(format: "Aerobic drift was high at %.1f%%; keep endurance progression conservative.", decouplingPercent)
            case .insufficientData:
                return "Not enough steady power and heart-rate data for aerobic drift."
            }
        }
    }

    static let minimumValidSeconds = 20 * 60

    static func compute(samples: [Sample]) -> Result? {
        let clean = samples
            .filter { $0.power >= 80 && $0.heartRate >= 80 }
            .sorted { $0.elapsedSeconds < $1.elapsedSeconds }
        guard clean.count >= minimumValidSeconds else { return nil }

        let midpoint = clean.count / 2
        guard midpoint > 0 else { return nil }

        let first = Array(clean[..<midpoint])
        let second = Array(clean[midpoint...])
        guard
            let firstEfficiency = efficiency(for: first),
            let secondEfficiency = efficiency(for: second),
            firstEfficiency > 0
        else { return nil }

        let decoupling = ((firstEfficiency - secondEfficiency) / firstEfficiency) * 100
        return Result(
            decouplingPercent: decoupling,
            firstHalfEfficiency: firstEfficiency,
            secondHalfEfficiency: secondEfficiency,
            validSeconds: clean.count,
            status: status(for: decoupling)
        )
    }

    static func compute(from workout: Workout) -> Result? {
        let samples = workout.samples.map {
            Sample(
                elapsedSeconds: $0.elapsedSeconds,
                power: $0.power,
                heartRate: $0.heartRate
            )
        }
        return compute(samples: samples)
    }

    private static func efficiency(for samples: [Sample]) -> Double? {
        guard !samples.isEmpty else { return nil }
        let sumPower = samples.reduce(0.0) { $0 + Double($1.power) }
        let sumHR = samples.reduce(0.0) { $0 + Double($1.heartRate) }
        guard sumPower > 0, sumHR > 0 else { return nil }
        return sumPower / sumHR
    }

    private static func status(for decoupling: Double) -> Status {
        if decoupling < 5 { return .stable }
        if decoupling < 10 { return .moderateDrift }
        return .highDrift
    }
}

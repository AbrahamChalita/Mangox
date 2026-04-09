// Features/Indoor/Domain/Entities/TrainerPowerMetrics.swift
import Foundation

/// Pure helpers for aggregating high-rate trainer power samples within one second.
/// Used by `WorkoutManager` and tests so mean vs peak logic stays consistent.
enum TrainerPowerMetrics {
    static func meanInt(samples: [Int]) -> Int {
        guard !samples.isEmpty else { return 0 }
        return samples.reduce(0, +) / samples.count
    }

    static func peakInt(samples: [Int]) -> Int {
        samples.max() ?? 0
    }
}

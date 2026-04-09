// Features/Workout/Domain/UseCases/SummaryZoneAggregation.swift
import Foundation

/// Pure zone bucketing for background aggregation. Lives in a SwiftUI-free file so these
/// helpers are not MainActor-isolated (unlike `PowerZone` / `HeartRateZone`, which use `Color`).
enum SummaryZoneAggregation {
    /// Matches `PowerZone.zone(for:)` thresholds using a captured FTP.
    nonisolated static func powerZoneId(forWatts watts: Int, ftp: Int) -> Int {
        let pct = Double(watts) / Double(max(ftp, 1))
        if pct < 0.55 { return 1 }
        if pct < 0.75 { return 2 }
        if pct < 0.87 { return 3 }
        if pct < 1.05 { return 4 }
        if pct < 1.50 { return 5 }
        return 5
    }

    /// Matches `HeartRateZone.zone(for:)` using captured HR settings.
    nonisolated static func heartRateZoneId(forBpm bpm: Int, maxHR: Int, restingHR: Int, usesKarvonen: Bool) -> Int {
        let maxHRd = Double(maxHR)
        guard maxHRd > 0, bpm > 0 else { return 1 }

        if usesKarvonen {
            let reserve = maxHRd - Double(restingHR)
            guard reserve > 0 else { return 1 }
            let intensity = (Double(bpm) - Double(restingHR)) / reserve
            if intensity < 0.60 { return 1 }
            if intensity < 0.70 { return 2 }
            if intensity < 0.80 { return 3 }
            if intensity < 0.90 { return 4 }
            return 5
        } else {
            let pct = Double(bpm) / maxHRd
            if pct < 0.60 { return 1 }
            if pct < 0.70 { return 2 }
            if pct < 0.80 { return 3 }
            if pct < 0.90 { return 4 }
            return 5
        }
    }
}

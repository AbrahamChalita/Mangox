// Features/Outdoor/Domain/UseCases/GPXPrivacyTrimLogic.swift
import Foundation

/// Shared rules for GPX start/end privacy trimming (used by export and unit tests).
public enum GPXPrivacyTrimLogic {
    /// Whether a trackpoint at `cumulativeDistanceAlongRoute` should be dropped by trim settings.
    public static func isExcluded(
        cumulativeDistanceAlongRoute: Double,
        trimStartMeters: Double,
        trimEndMeters: Double,
        routeLengthMeters: Double
    ) -> Bool {
        guard trimStartMeters > 0 || trimEndMeters > 0 else { return false }
        let routeLen = max(routeLengthMeters, 1)
        if cumulativeDistanceAlongRoute < trimStartMeters { return true }
        if cumulativeDistanceAlongRoute > max(0, routeLen - trimEndMeters) { return true }
        return false
    }
}

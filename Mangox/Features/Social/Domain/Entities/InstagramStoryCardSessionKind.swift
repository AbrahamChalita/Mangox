// Features/Social/Domain/Entities/InstagramStoryCardSessionKind.swift
import Foundation

/// Inferred session context for story copy and sensible defaults (not persisted).
enum InstagramStoryCardSessionKind: String, Sendable, Equatable {
    case outdoor
    case indoorTrainer
    case unknown

    /// Best-effort classification: route, GPX/directions ride, meaningful elevation, or long moving outdoor-like stats → outdoor; otherwise indoor-style.
    static func resolve(workout: Workout, routeName: String?, totalElevationGain: Double) -> InstagramStoryCardSessionKind {
        let saved = workout.savedRouteName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let passed = (routeName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let hasRoute = !saved.isEmpty || !passed.isEmpty
        let elevMeters = max(workout.elevationGain, totalElevationGain)

        if hasRoute || elevMeters > 50 {
            return .outdoor
        }

        if let kind = workout.savedRouteKind {
            switch kind {
            case .gpx, .directions:
                return .outdoor
            case .free:
                break
            }
        }

        if elevMeters <= 25, workout.duration >= 60 {
            return .indoorTrainer
        }

        if elevMeters <= 50,
           workout.distance >= 15_000,
           workout.displayAverageSpeedKmh >= 16
        {
            return .outdoor
        }

        return .unknown
    }
}

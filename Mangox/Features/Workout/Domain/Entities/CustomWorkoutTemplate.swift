// Features/Workout/Domain/Entities/CustomWorkoutTemplate.swift
import Foundation
import SwiftData

/// User-saved structured workout (e.g. from ZWO import or built in-app) for indoor guided sessions.
@Model
final class CustomWorkoutTemplate {
    @Attribute(.unique) var id: UUID
    var name: String
    /// Encoded `[IntervalSegment]` via JSON.
    var intervalsPayload: Data
    var createdAt: Date

    init(id: UUID = UUID(), name: String, intervals: [IntervalSegment], createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.intervalsPayload = (try? JSONEncoder().encode(intervals)) ?? Data()
        self.createdAt = createdAt
    }

    var intervals: [IntervalSegment] {
        get {
            (try? JSONDecoder().decode([IntervalSegment].self, from: intervalsPayload)) ?? []
        }
        set {
            intervalsPayload = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    /// Builds a `PlanDay` compatible with `GuidedSessionManager`.
    func asPlanDay() -> PlanDay {
        let segs = intervals
        let totalSec = segs.isEmpty ? 45 * 60 : segs.reduce(0) { $0 + $1.totalSeconds }
        let minutes = max(1, totalSec / 60)
        return PlanDay(
            id: "custom-\(id.uuidString)",
            weekNumber: 0,
            dayOfWeek: 1,
            dayType: .workout,
            title: name,
            durationMinutes: minutes,
            zone: .mixed,
            notes: "",
            intervals: segs,
            isKeyWorkout: true,
            requiresFTPTest: false
        )
    }
}

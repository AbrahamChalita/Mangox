// Features/Training/Domain/UseCases/ExternalActivityPlanMatcher.swift
import Foundation

/// Matches an imported external cycling ride to an open training-plan day on the same calendar date.
enum ExternalActivityPlanMatcher {
    private static let cyclingDayTypes: Set<PlanDayType> = [
        .workout, .ftpTest, .optionalWorkout, .commute,
    ]

    /// Returns the best plan day to auto-complete for the given ride, or nil when no eligible day exists.
    static func matchPlanDay(
        workoutStart: Date,
        workoutDurationSeconds: Int,
        progress: TrainingPlanProgress,
        plan: TrainingPlan,
        occupiedDayIDs: Set<String>
    ) -> PlanDay? {
        let calendar = Calendar.current
        let workoutDay = calendar.startOfDay(for: workoutStart)

        let candidates = plan.allDays.filter { day in
            cyclingDayTypes.contains(day.dayType)
                && !progress.isCompleted(day.id)
                && !progress.isSkipped(day.id)
                && !occupiedDayIDs.contains(day.id)
                && calendar.startOfDay(for: progress.calendarDate(for: day)) == workoutDay
        }

        return candidates.max { lhs, rhs in
            score(day: lhs, workoutDurationSeconds: workoutDurationSeconds)
                < score(day: rhs, workoutDurationSeconds: workoutDurationSeconds)
        }
    }

    /// Picks the most recently started plan that has an eligible day for this ride.
    static func matchAcrossPlans(
        workoutStart: Date,
        workoutDurationSeconds: Int,
        allProgress: [TrainingPlanProgress],
        resolvePlan: (String) -> TrainingPlan?,
        occupiedDayIDsForPlan: (String) -> Set<String>
    ) -> (progress: TrainingPlanProgress, plan: TrainingPlan, day: PlanDay)? {
        let sorted = allProgress.sorted { $0.startDate > $1.startDate }
        for progress in sorted {
            guard let plan = resolvePlan(progress.planID) else { continue }
            let occupied = occupiedDayIDsForPlan(progress.planID)
            if let day = matchPlanDay(
                workoutStart: workoutStart,
                workoutDurationSeconds: workoutDurationSeconds,
                progress: progress,
                plan: plan,
                occupiedDayIDs: occupied
            ) {
                return (progress, plan, day)
            }
        }
        return nil
    }

    private static func score(day: PlanDay, workoutDurationSeconds: Int) -> Int {
        var value = 0
        switch day.dayType {
        case .ftpTest: value += 100
        case .workout: value += 80
        case .commute: value += 40
        case .optionalWorkout: value += 30
        default: value += 10
        }
        if day.isKeyWorkout { value += 25 }

        let plannedSeconds = max(day.durationMinutes * 60, 1)
        let deltaMinutes = abs(plannedSeconds - workoutDurationSeconds) / 60
        value -= min(deltaMinutes, 120)
        return value
    }
}

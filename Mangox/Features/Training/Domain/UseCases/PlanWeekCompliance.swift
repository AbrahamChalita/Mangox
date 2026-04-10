// Features/Training/Domain/UseCases/PlanWeekCompliance.swift
import Foundation

/// Plan adherence for the current calendar week (Mon–Sun).
enum PlanWeekCompliance {
    struct Snapshot: Sendable {
        let planName: String
        let scheduledWorkouts: Int
        let completedWorkouts: Int
        let plannedWeekTSS: Int
        let actualWeekTSS: Int
        let keySessionsPlanned: Int
        let keySessionsCompleted: Int

        var fraction: Double {
            guard scheduledWorkouts > 0 else { return 0 }
            return Double(completedWorkouts) / Double(scheduledWorkouts)
        }

        var percentLabel: String {
            guard scheduledWorkouts > 0 else { return "—" }
            return "\(Int((fraction * 100).rounded()))%"
        }

        var tssPercentLabel: String {
            guard plannedWeekTSS > 0 else { return "—" }
            return "\(Int(min(199, (Double(actualWeekTSS) / Double(plannedWeekTSS) * 100).rounded())))%"
        }
    }

    /// Uses the most recently started plan progress, matching plan, and recent rides for week TSS.
    @MainActor
    static func snapshot(
        progress: TrainingPlanProgress?,
        plan: TrainingPlan?,
        recentWorkouts: [Workout]
    ) -> Snapshot? {
        let snapshots = recentWorkouts.map(WorkoutMetricsSnapshot.init(from:))
        return snapshot(
            progress: progress,
            plan: plan,
            recentWorkouts: snapshots
        )
    }

    @MainActor
    static func snapshot(
        progress: TrainingPlanProgress?,
        plan: TrainingPlan?,
        recentWorkouts: [WorkoutMetricsSnapshot]
    ) -> Snapshot? {
        guard let progress, let plan else { return nil }

        let cal = Calendar.current
        let weekRange = TrainingPlanCompliance.currentWeekRange()
        let weekStart = weekRange.start
        let weekEnd = weekRange.end

        var scheduled = 0
        var completed = 0

        for day in plan.allDays {
            switch day.dayType {
            case .workout, .ftpTest, .optionalWorkout, .commute:
                break
            default:
                continue
            }

            let dayDate = progress.calendarDate(for: day)
            let start = cal.startOfDay(for: dayDate)
            guard start >= weekStart && start < weekEnd else { continue }

            scheduled += 1
            if progress.isCompleted(day.id) {
                completed += 1
            }
        }

        guard scheduled > 0 else { return nil }

        let ftp = max(1, max(progress.currentFTP, PowerZone.ftp))
        let actualWeekTSS = recentWorkouts.reduce(0.0) { partial, workout in
            guard workout.startDate >= weekStart && workout.startDate < weekEnd else { return partial }
            return partial + workout.tss
        }
        let compliance = TrainingPlanCompliance.compute(
            plan: plan,
            progress: progress,
            ftp: ftp,
            actualWeekTSS: actualWeekTSS
        )

        return Snapshot(
            planName: plan.name,
            scheduledWorkouts: scheduled,
            completedWorkouts: completed,
            plannedWeekTSS: Int(compliance.plannedWeekTSS.rounded()),
            actualWeekTSS: Int(compliance.actualWeekTSS.rounded()),
            keySessionsPlanned: compliance.keySessionsPlanned,
            keySessionsCompleted: compliance.keySessionsCompleted
        )
    }
}

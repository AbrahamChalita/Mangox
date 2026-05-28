// Features/Training/Domain/UseCases/PlanTSSVectorBuilder.swift
import Foundation

/// Plain progress fields for pure plan TSS vector math (no SwiftData).
struct PlanProgressFields: Sendable, Equatable {
    let startDate: Date
    let currentFTP: Int
    let adaptiveLoadMultiplier: Double

    init(startDate: Date, currentFTP: Int, adaptiveLoadMultiplier: Double = 1.0) {
        self.startDate = startDate
        self.currentFTP = max(1, currentFTP)
        self.adaptiveLoadMultiplier = adaptiveLoadMultiplier
    }

    init(from progress: TrainingPlanProgress) {
        self.startDate = progress.startDate
        self.currentFTP = max(1, progress.currentFTP)
        self.adaptiveLoadMultiplier = progress.adaptiveLoadMultiplier
    }

    func calendarDate(for day: PlanDay) -> Date {
        let dayOffset = (day.weekNumber - 1) * 7 + (day.dayOfWeek - 1)
        return Calendar.current.date(byAdding: .day, value: dayOffset, to: startDate) ?? startDate
    }
}

/// Builds daily TSS sequences from a training plan for PMC forward simulation.
enum PlanTSSVectorBuilder {

    struct ScheduledDay: Sendable, Equatable {
        let date: Date
        let dayID: String
        let title: String
        let tss: Double
    }

    /// Maps each calendar day in `[referenceDate+1 … +horizonDays]` to planned TSS (0 on rest/no-plan days).
    static func forwardDailyTSS(
        plan: TrainingPlan,
        progress: PlanProgressFields,
        referenceDate: Date = .now,
        horizonDays: Int,
        includeAdaptiveMultiplier: Bool = true
    ) -> [Double] {
        let scheduled = forwardSchedule(
            plan: plan,
            progress: progress,
            referenceDate: referenceDate,
            horizonDays: horizonDays,
            includeAdaptiveMultiplier: includeAdaptiveMultiplier
        )
        return scheduled.map(\.tss)
    }

    static func forwardSchedule(
        plan: TrainingPlan,
        progress: PlanProgressFields,
        referenceDate: Date = .now,
        horizonDays: Int,
        includeAdaptiveMultiplier: Bool = true
    ) -> [ScheduledDay] {
        guard horizonDays > 0 else { return [] }

        let cal = Calendar.current
        let today = cal.startOfDay(for: referenceDate)
        let multiplier = includeAdaptiveMultiplier ? max(0.5, min(1.2, progress.adaptiveLoadMultiplier)) : 1.0
        let ftp = progress.currentFTP

        var dayByDate: [Date: PlanDay] = [:]
        for day in plan.allDays {
            let d = cal.startOfDay(for: progress.calendarDate(for: day))
            dayByDate[d] = day
        }

        return (1...horizonDays).map { offset in
            let date = cal.date(byAdding: .day, value: offset, to: today) ?? today
            let key = cal.startOfDay(for: date)

            guard let planDay = dayByDate[key] else {
                return ScheduledDay(date: key, dayID: "", title: "No plan", tss: 0)
            }

            let raw = planDay.estimatedPlannedTSS(ftp: ftp)
            let scaled = (raw * multiplier * 10).rounded() / 10

            return ScheduledDay(
                date: key,
                dayID: planDay.id,
                title: planDay.title,
                tss: max(0, scaled)
            )
        }
    }
}

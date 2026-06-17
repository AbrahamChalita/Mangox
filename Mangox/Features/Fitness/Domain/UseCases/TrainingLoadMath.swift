// Features/Fitness/Domain/UseCases/TrainingLoadMath.swift
import Foundation

nonisolated struct TrainingLoadInput: Sendable, Equatable {
    let startDate: Date
    let tss: Double
}

nonisolated struct TrainingLoadPoint: Sendable, Equatable {
    let date: Date
    let ctl: Double
    let atl: Double
    let tsb: Double
}

/// Source-agnostic CTL / ATL / TSB math for cycling workouts plus logged activities.
///
/// TSB ("form") is a load balance signal: chronic load minus acute load. It is
/// intentionally separate from morning recovery/readiness signals such as WHOOP.
nonisolated enum TrainingLoadMath {
    static let ctlDays = 42
    static let atlDays = 7
    static let defaultWarmBackDays = 180

    static var ctlAlpha: Double { 2.0 / Double(ctlDays + 1) }
    static var atlAlpha: Double { 2.0 / Double(atlDays + 1) }

    static func buildPoints(
        inputs: [TrainingLoadInput],
        rangeDays: Int,
        now: Date = Date(),
        calendar: Calendar = .current,
        warmBackDays: Int = defaultWarmBackDays
    ) -> [TrainingLoadPoint] {
        guard rangeDays > 0 else { return [] }

        let today = calendar.startOfDay(for: now)
        guard let startDate = calendar.date(byAdding: .day, value: -rangeDays, to: today),
              let warmStart = calendar.date(byAdding: .day, value: -warmBackDays, to: startDate)
        else { return [] }

        var tssByDay: [Date: Double] = [:]
        for input in inputs where input.tss.isFinite && input.tss > 0 {
            let day = calendar.startOfDay(for: input.startDate)
            guard day >= warmStart && day <= today else { continue }
            tssByDay[day, default: 0] += input.tss
        }

        return buildPoints(
            tssByDay: tssByDay,
            visibleStart: startDate,
            warmStart: warmStart,
            today: today,
            calendar: calendar
        )
    }

    private static func buildPoints(
        tssByDay: [Date: Double],
        visibleStart: Date,
        warmStart: Date,
        today: Date,
        calendar: Calendar
    ) -> [TrainingLoadPoint] {
        var ctl = 0.0
        var atl = 0.0
        var points: [TrainingLoadPoint] = []
        var currentDate = warmStart

        while currentDate <= today {
            let dayTSS = tssByDay[currentDate] ?? 0
            ctl += ctlAlpha * (dayTSS - ctl)
            atl += atlAlpha * (dayTSS - atl)

            if currentDate >= visibleStart {
                points.append(
                    TrainingLoadPoint(
                        date: currentDate,
                        ctl: ctl,
                        atl: atl,
                        tsb: ctl - atl
                    )
                )
            }

            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)
                ?? today.addingTimeInterval(86_400)
        }

        return points
    }
}

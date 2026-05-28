import Testing
@testable import Mangox

@MainActor
struct PlanForwardImpactSummaryTests {
    @Test func compute_returnsSummaryForMultiWeekPlan() {
        let plan = TrainingPlan(
            id: "impact-test",
            name: "Impact",
            eventName: "Gran Fondo",
            eventDate: "2026-08-01",
            distance: "100 km",
            elevation: "1000 m",
            location: "Test",
            description: "",
            weeks: [
                PlanWeek(
                    weekNumber: 1,
                    phase: "base",
                    title: "Base",
                    totalHoursLow: 6,
                    totalHoursHigh: 8,
                    tssTarget: 200...300,
                    focus: "endurance",
                    days: easyWeekDays(week: 1)
                ),
                PlanWeek(
                    weekNumber: 2,
                    phase: "build",
                    title: "Build",
                    totalHoursLow: 7,
                    totalHoursHigh: 9,
                    tssTarget: 250...350,
                    focus: "threshold",
                    days: easyWeekDays(week: 2)
                ),
            ]
        )

        let summary = PlanForwardImpactSummary.compute(
            plan: plan,
            eventDateString: "2026-08-01",
            ftp: 250
        )

        #expect(summary != nil)
        #expect(summary?.contains("Projected over") == true)
    }

    private func easyWeekDays(week: Int) -> [PlanDay] {
        (1...7).map { dayOfWeek in
            PlanDay(
                id: "w\(week)d\(dayOfWeek)",
                weekNumber: week,
                dayOfWeek: dayOfWeek,
                dayType: dayOfWeek == 7 ? .rest : .workout,
                title: dayOfWeek == 7 ? "Rest" : "Endurance",
                durationMinutes: dayOfWeek == 7 ? 0 : 60,
                zone: .z2,
                notes: "",
                intervals: [],
                isKeyWorkout: dayOfWeek == 3,
                requiresFTPTest: false
            )
        }
    }
}

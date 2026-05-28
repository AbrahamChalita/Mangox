import Testing
@testable import Mangox

@MainActor
struct PlanCriticTests {
    @Test func backToBackKeySessions_flagsWarning() {
        let plan = makePlan(
            weeks: [
                makeWeek(
                    weekNumber: 1,
                    days: [
                        makeDay(id: "k1", dayOfWeek: 2, key: true, title: "Threshold"),
                        makeDay(id: "k2", dayOfWeek: 3, key: true, title: "VO2"),
                    ]
                ),
            ]
        )

        let verdict = PlanCritic.validate(plan: plan, ftp: 250)

        #expect(verdict.warnings.contains { $0.code == "back_to_back_key" })
    }

    @Test func stableLoad_passesWithoutErrors() {
        let plan = makePlan(
            weeks: [
                makeWeek(weekNumber: 1, days: easyWeekDays(week: 1, duration: 60)),
                makeWeek(weekNumber: 2, days: easyWeekDays(week: 2, duration: 65)),
            ]
        )

        let verdict = PlanCritic.validate(plan: plan, ftp: 250)

        #expect(verdict.passed)
        #expect(verdict.errors.isEmpty)
    }

    private func makePlan(weeks: [PlanWeek]) -> TrainingPlan {
        TrainingPlan(
            id: "critic-test",
            name: "Critic",
            eventName: "Event",
            eventDate: "2026-06-01",
            distance: "100 km",
            elevation: "500 m",
            location: "Test",
            description: "",
            weeks: weeks
        )
    }

    private func makeWeek(weekNumber: Int, days: [PlanDay]) -> PlanWeek {
        PlanWeek(
            weekNumber: weekNumber,
            phase: "base",
            title: "Week \(weekNumber)",
            totalHoursLow: 5,
            totalHoursHigh: 8,
            tssTarget: 200...300,
            focus: "endurance",
            days: days
        )
    }

    private func makeDay(id: String, dayOfWeek: Int, key: Bool, title: String) -> PlanDay {
        PlanDay(
            id: id,
            weekNumber: 1,
            dayOfWeek: dayOfWeek,
            dayType: .workout,
            title: title,
            durationMinutes: 75,
            zone: .z3,
            notes: "",
            intervals: [],
            isKeyWorkout: key,
            requiresFTPTest: false
        )
    }

    private func easyWeekDays(week: Int, duration: Int) -> [PlanDay] {
        (1...7).map { day in
            if day == 7 {
                return PlanDay(
                    id: "w\(week)d\(day)",
                    weekNumber: week,
                    dayOfWeek: day,
                    dayType: .rest,
                    title: "Rest",
                    durationMinutes: 0,
                    zone: .rest,
                    notes: "",
                    intervals: [],
                    isKeyWorkout: false,
                    requiresFTPTest: false
                )
            }
            return PlanDay(
                id: "w\(week)d\(day)",
                weekNumber: week,
                dayOfWeek: day,
                dayType: .workout,
                title: "Easy",
                durationMinutes: duration,
                zone: .z2,
                notes: "",
                intervals: [],
                isKeyWorkout: false,
                requiresFTPTest: false
            )
        }
    }
}

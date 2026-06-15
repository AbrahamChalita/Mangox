import Foundation
import Testing
@testable import Mangox

@MainActor
struct ExternalActivityPlanMatcherTests {

    @Test func matchesOpenWorkoutDayOnSameCalendarDate() {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 8
        let startDate = Calendar.current.date(from: components)!
        let progress = TrainingPlanProgress(planID: "plan-a", startDate: startDate, ftp: 250)

        let day = PlanDay(
            id: "w1d1",
            weekNumber: 1,
            dayOfWeek: 1,
            dayType: .workout,
            title: "Endurance",
            durationMinutes: 60,
            zone: .z2,
            notes: "",
            intervals: [],
            isKeyWorkout: false,
            requiresFTPTest: false
        )
        let plan = makePlan(id: "plan-a", days: [day])

        let rideStart = Calendar.current.date(byAdding: .hour, value: 9, to: startDate)!
        let match = ExternalActivityPlanMatcher.matchPlanDay(
            workoutStart: rideStart,
            workoutDurationSeconds: 3_600,
            progress: progress,
            plan: plan,
            occupiedDayIDs: []
        )

        #expect(match?.id == "w1d1")
    }

    @Test func skipsCompletedAndOccupiedDays() {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 8
        let startDate = Calendar.current.date(from: components)!
        let progress = TrainingPlanProgress(planID: "plan-a", startDate: startDate, ftp: 250)
        progress.markCompleted("w1d1")

        let day = PlanDay(
            id: "w1d1",
            weekNumber: 1,
            dayOfWeek: 1,
            dayType: .workout,
            title: "Endurance",
            durationMinutes: 60,
            zone: .z2,
            notes: "",
            intervals: [],
            isKeyWorkout: false,
            requiresFTPTest: false
        )
        let plan = makePlan(id: "plan-a", days: [day])

        let rideStart = Calendar.current.date(byAdding: .hour, value: 9, to: startDate)!
        let match = ExternalActivityPlanMatcher.matchPlanDay(
            workoutStart: rideStart,
            workoutDurationSeconds: 3_600,
            progress: progress,
            plan: plan,
            occupiedDayIDs: []
        )

        #expect(match == nil)
    }

    @Test func prefersFtpTestOverOptionalWorkoutOnSameDay() {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 8
        let startDate = Calendar.current.date(from: components)!
        let progress = TrainingPlanProgress(planID: "plan-a", startDate: startDate, ftp: 250)

        let optional = PlanDay(
            id: "opt",
            weekNumber: 1,
            dayOfWeek: 1,
            dayType: .optionalWorkout,
            title: "Spin",
            durationMinutes: 45,
            zone: .z1,
            notes: "",
            intervals: [],
            isKeyWorkout: false,
            requiresFTPTest: false
        )
        let ftpTest = PlanDay(
            id: "ftp",
            weekNumber: 1,
            dayOfWeek: 1,
            dayType: .ftpTest,
            title: "FTP Test",
            durationMinutes: 60,
            zone: .z4,
            notes: "",
            intervals: [],
            isKeyWorkout: true,
            requiresFTPTest: true
        )
        let plan = makePlan(id: "plan-a", days: [optional, ftpTest])

        let rideStart = Calendar.current.date(byAdding: .hour, value: 9, to: startDate)!
        let match = ExternalActivityPlanMatcher.matchPlanDay(
            workoutStart: rideStart,
            workoutDurationSeconds: 3_600,
            progress: progress,
            plan: plan,
            occupiedDayIDs: []
        )

        #expect(match?.id == "ftp")
    }

    private func makePlan(id: String, days: [PlanDay]) -> TrainingPlan {
        let week = PlanWeek(
            weekNumber: 1,
            phase: "Base",
            title: "Week 1",
            totalHoursLow: 0,
            totalHoursHigh: 0,
            tssTarget: 0...0,
            focus: "",
            days: days
        )
        return TrainingPlan(
            id: id,
            name: "Test",
            eventName: "",
            eventDate: "",
            distance: "",
            elevation: "",
            location: "",
            description: "",
            weeks: [week]
        )
    }
}

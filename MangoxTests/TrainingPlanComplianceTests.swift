import Foundation
import Testing
@testable import Mangox

struct TrainingPlanComplianceTests {

    @Test func optionalKeyWorkoutDoesNotCountTowardMandatoryKeySessions() {
        var components = DateComponents()
        components.year = 2026
        components.month = 4
        components.day = 8
        let ref = Calendar.current.date(from: components)!
        let weekStart = TrainingPlanCompliance.currentWeekRange(referenceDate: ref).start

        let optionalKey = PlanDay(
            id: "ok",
            weekNumber: 1,
            dayOfWeek: 1,
            dayType: .optionalWorkout,
            title: "Optional endurance",
            durationMinutes: 60,
            zone: .z2,
            notes: "",
            intervals: [],
            isKeyWorkout: true,
            requiresFTPTest: false
        )
        let week = PlanWeek(
            weekNumber: 1,
            phase: "Test",
            title: "T",
            totalHoursLow: 0,
            totalHoursHigh: 0,
            tssTarget: 0...0,
            focus: "",
            days: [optionalKey]
        )
        let plan = TrainingPlan(
            id: "test-plan",
            name: "Test",
            eventName: "",
            eventDate: "",
            distance: "",
            elevation: "",
            location: "",
            description: "",
            weeks: [week]
        )
        let progress = TrainingPlanProgress(planID: "test-plan", startDate: weekStart, ftp: 250)

        let c = TrainingPlanCompliance.compute(
            plan: plan, progress: progress, ftp: 250, actualWeekTSS: 0, referenceDate: ref)
        #expect(c.keySessionsPlanned == 0)
    }

    @Test func starredWorkoutDayCountsAsMandatoryKeyWhenIncomplete() {
        var components = DateComponents()
        components.year = 2026
        components.month = 4
        components.day = 8
        let ref = Calendar.current.date(from: components)!
        let weekStart = TrainingPlanCompliance.currentWeekRange(referenceDate: ref).start

        let key = PlanDay(
            id: "mk",
            weekNumber: 1,
            dayOfWeek: 1,
            dayType: .workout,
            title: "Threshold",
            durationMinutes: 60,
            zone: .z4,
            notes: "",
            intervals: [],
            isKeyWorkout: true,
            requiresFTPTest: false
        )
        let week = PlanWeek(
            weekNumber: 1,
            phase: "Test",
            title: "T",
            totalHoursLow: 0,
            totalHoursHigh: 0,
            tssTarget: 0...0,
            focus: "",
            days: [key]
        )
        let plan = TrainingPlan(
            id: "test-plan-2",
            name: "Test",
            eventName: "",
            eventDate: "",
            distance: "",
            elevation: "",
            location: "",
            description: "",
            weeks: [week]
        )
        let progress = TrainingPlanProgress(planID: "test-plan-2", startDate: weekStart, ftp: 250)

        let c = TrainingPlanCompliance.compute(
            plan: plan, progress: progress, ftp: 250, actualWeekTSS: 0, referenceDate: ref)
        #expect(c.keySessionsPlanned == 1)
        #expect(c.keySessionsCompleted == 0)
    }
}

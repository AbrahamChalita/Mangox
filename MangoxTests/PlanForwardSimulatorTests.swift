import XCTest
@testable import Mangox

@MainActor
final class PlanForwardSimulatorTests: XCTestCase {

    func testSimulateVector_projectsEndingTSB() {
        let result = PlanForwardSimulator.simulate(
            currentCTL: 45,
            currentATL: 38,
            dailyTSS: [50, 55, 60, 40, 0, 70, 65]
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.horizonDays, 7)
        XCTAssertGreaterThan(result!.endingCTL, result!.startingCTL)
        XCTAssertNotEqual(result!.deltaTSB, 0)
    }

    func testSimulateFromPlan_usesScheduledTSS() {
        let plan = samplePlan()
        let progress = PlanProgressFields(
            startDate: Calendar.current.startOfDay(for: Date()),
            currentFTP: 250,
            adaptiveLoadMultiplier: 1.0
        )

        let vector = PlanTSSVectorBuilder.forwardDailyTSS(
            plan: plan,
            progress: progress,
            horizonDays: 7
        )

        let result = PlanForwardSimulator.simulate(
            currentCTL: 40,
            currentATL: 35,
            dailyTSS: vector
        )

        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result!.totalPlannedTSS, 0)
    }

    private func samplePlan() -> TrainingPlan {
        let week = PlanWeek(
            weekNumber: 1,
            phase: "base",
            title: "Base",
            totalHoursLow: 6,
            totalHoursHigh: 8,
            tssTarget: 200...280,
            focus: "endurance",
            days: (1...7).map { offset in
                offset == 7
                    ? PlanDay(
                        id: "rest",
                        weekNumber: 1,
                        dayOfWeek: 7,
                        dayType: .rest,
                        title: "Rest",
                        durationMinutes: 0,
                        zone: .rest,
                        notes: "",
                        intervals: [],
                        isKeyWorkout: false,
                        requiresFTPTest: false
                    )
                    : PlanDay(
                        id: "d\(offset)",
                        weekNumber: 1,
                        dayOfWeek: offset,
                        dayType: .workout,
                        title: "Ride \(offset)",
                        durationMinutes: 60,
                        zone: .z2,
                        notes: "",
                        intervals: [],
                        isKeyWorkout: false,
                        requiresFTPTest: false
                    )
            }
        )
        return TrainingPlan(
            id: "test-plan",
            name: "Test",
            eventName: "Test Event",
            eventDate: "2026-06-01",
            distance: "100 km",
            elevation: "1000 m",
            location: "Test",
            description: "",
            weeks: [week]
        )
    }
}

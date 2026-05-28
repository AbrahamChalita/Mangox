import Testing
@testable import Mangox

@MainActor
struct WorkoutCriticTests {
    @Test func durationMismatch_flagsWarning() {
        let workout = makeWorkout(durationMinutes: 90, intervals: longIntervals())
        let inputs = WorkoutGenerationInputs(
            goal: "threshold",
            durationMinutes: 45,
            experience: nil,
            preferredIntensity: nil,
            environment: "indoor",
            plannedDate: nil,
            currentFTP: 250,
            planContext: nil
        )

        let verdict = WorkoutCritic.validate(workout: workout, inputs: inputs, ftp: 250)

        #expect(verdict.warnings.contains { $0.code == "duration_mismatch" })
    }

    @Test func recoveryGoalWithHighTSS_flagsWarning() {
        let workout = makeWorkout(
            durationMinutes: 60,
            intervals: [
                IntervalSegment(
                    order: 1,
                    name: "Main",
                    durationSeconds: 3600,
                    zone: .z3,
                    repeats: 1,
                    recoverySeconds: 0,
                    recoveryZone: .z1,
                    notes: "",
                    suggestedTrainerMode: .erg
                ),
            ]
        )
        let inputs = WorkoutGenerationInputs(
            goal: "easy recovery spin",
            durationMinutes: 60,
            experience: nil,
            preferredIntensity: nil,
            environment: "indoor",
            plannedDate: nil,
            currentFTP: 250,
            planContext: nil
        )

        let verdict = WorkoutCritic.validate(workout: workout, inputs: inputs, ftp: 250)

        #expect(verdict.warnings.contains { $0.code == "recovery_too_hard" })
    }

    private func makeWorkout(durationMinutes: Int, intervals: [IntervalSegment]) -> GeneratedWorkout {
        GeneratedWorkout(
            title: "Test",
            purpose: "Test workout",
            rationale: nil,
            day: PlanDay(
                id: "w1",
                weekNumber: 0,
                dayOfWeek: 1,
                dayType: .workout,
                title: "Test",
                durationMinutes: durationMinutes,
                zone: .z3,
                notes: "",
                intervals: intervals,
                isKeyWorkout: false,
                requiresFTPTest: false
            )
        )
    }

    private func longIntervals() -> [IntervalSegment] {
        [
            IntervalSegment(
                order: 1,
                name: "Warm-up",
                durationSeconds: 600,
                zone: .z2,
                repeats: 1,
                recoverySeconds: 0,
                recoveryZone: .z1,
                notes: "",
                suggestedTrainerMode: .erg
            ),
            IntervalSegment(
                order: 2,
                name: "Main",
                durationSeconds: 4200,
                zone: .z4,
                repeats: 1,
                recoverySeconds: 0,
                recoveryZone: .z1,
                notes: "",
                suggestedTrainerMode: .erg
            ),
        ]
    }
}

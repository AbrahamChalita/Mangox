import Foundation
import SwiftData

/// Builds a `CustomWorkoutTemplate` from a completed ride (laps → segments, or one steady block).
enum WorkoutCustomTemplateBuilder {

    @MainActor
    static func makeTemplate(from workout: Workout, name: String? = nil) -> CustomWorkoutTemplate? {
        guard workout.status == .completed, workout.isValid else { return nil }

        let title = (name?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? defaultTitle(for: workout)

        let laps = workout.laps.sorted { $0.lapNumber < $1.lapNumber }
        let usableLaps = laps.filter { $0.duration >= 5 }

        let intervals: [IntervalSegment]
        if usableLaps.count >= 2 {
            intervals = usableLaps.enumerated().map { index, lap in
                let sec = max(1, Int(lap.duration.rounded()))
                let w = Int(lap.avgPower.rounded())
                return IntervalSegment(
                    order: index + 1,
                    name: "Lap \(lap.lapNumber)",
                    durationSeconds: sec,
                    zone: trainingZoneTarget(forWatts: w),
                    repeats: 1,
                    cadenceLow: lap.avgCadence > 0 ? max(0, Int(lap.avgCadence.rounded()) - 5) : nil,
                    cadenceHigh: lap.avgCadence > 0 ? Int(lap.avgCadence.rounded()) + 5 : nil,
                    recoverySeconds: 0,
                    recoveryZone: .z1,
                    notes: "",
                    suggestedTrainerMode: .erg,
                    simulationGrade: nil
                )
            }
        } else {
            let sec = max(60, Int(workout.duration.rounded()))
            let w = Int(workout.avgPower.rounded())
            intervals = [
                IntervalSegment(
                    order: 1,
                    name: "Steady",
                    durationSeconds: sec,
                    zone: trainingZoneTarget(forWatts: w),
                    repeats: 1,
                    cadenceLow: workout.avgCadence > 0
                        ? max(0, Int(workout.avgCadence.rounded()) - 5) : nil,
                    cadenceHigh: workout.avgCadence > 0
                        ? Int(workout.avgCadence.rounded()) + 5 : nil,
                    recoverySeconds: 0,
                    recoveryZone: .z1,
                    notes: "From free ride",
                    suggestedTrainerMode: .erg,
                    simulationGrade: nil
                )
            ]
        }

        return CustomWorkoutTemplate(name: title, intervals: intervals)
    }

    private static func defaultTitle(for workout: Workout) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return "Custom · \(df.string(from: workout.startDate))"
    }

    private static func trainingZoneTarget(forWatts watts: Int) -> TrainingZoneTarget {
        guard watts > 0 else { return .z2 }
        let z = PowerZone.zone(for: watts)
        switch z.id {
        case 1: return .z1
        case 2: return .z2
        case 3: return .z3
        case 4: return .z4
        default: return .z5
        }
    }
}

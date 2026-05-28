// Features/Training/Domain/UseCases/WorkoutCritic.swift
import Foundation

/// Client-side workout critic — validates generated workouts before save (Phase 2).
enum WorkoutCritic {

    enum Severity: String, Sendable, Codable {
        case warning
        case error
    }

    struct Issue: Sendable, Equatable {
        let code: String
        let message: String
        let severity: Severity
    }

    struct Verdict: Sendable, Equatable {
        let issues: [Issue]
        var warnings: [Issue] { issues.filter { $0.severity == .warning } }
        var errors: [Issue] { issues.filter { $0.severity == .error } }
        var passed: Bool { errors.isEmpty }
    }

    static func validate(
        workout: GeneratedWorkout,
        inputs: WorkoutGenerationInputs,
        ftp: Int
    ) -> Verdict {
        var issues: [Issue] = []
        let safeFTP = max(1, inputs.currentFTP ?? ftp)

        let plannedSeconds = workout.day.intervals.reduce(0) { partial, segment in
            let work = segment.durationSeconds * max(1, segment.repeats)
            let recovery = max(0, segment.recoverySeconds) * max(0, segment.repeats - 1)
            return partial + work + recovery
        }
        let fallbackSeconds = workout.day.durationMinutes * 60
        let totalSeconds = plannedSeconds > 0 ? plannedSeconds : fallbackSeconds
        let requestedSeconds = inputs.durationMinutes * 60

        if totalSeconds > 0 {
            let ratio = Double(totalSeconds) / Double(max(1, requestedSeconds))
            if ratio < 0.75 || ratio > 1.35 {
                issues.append(
                    Issue(
                        code: "duration_mismatch",
                        message: String(
                            format: "Workout structure is ~%d min but you asked for %d min.",
                            totalSeconds / 60,
                            inputs.durationMinutes
                        ),
                        severity: .warning
                    )
                )
            }
        }

        let estimatedTSS = workout.day.estimatedPlannedTSS(ftp: safeFTP)
        let tssPerHour = estimatedTSS / max(1, Double(totalSeconds) / 3600)
        if tssPerHour > 120 {
            issues.append(
                Issue(
                    code: "high_tss_density",
                    message: String(format: "Estimated TSS %.0f looks very dense for this duration.", estimatedTSS),
                    severity: .warning
                )
            )
        }

        if workout.day.intervals.isEmpty && workout.day.durationMinutes <= 0 {
            issues.append(
                Issue(
                    code: "empty_structure",
                    message: "Workout has no intervals or duration.",
                    severity: .error
                )
            )
        }

        let goal = inputs.goal.lowercased()
        if goal.contains("recovery") || goal.contains("easy") {
            if estimatedTSS > 45 {
                issues.append(
                    Issue(
                        code: "recovery_too_hard",
                        message: "Recovery-focused request but estimated TSS is high.",
                        severity: .warning
                    )
                )
            }
        }

        return Verdict(issues: issues)
    }
}

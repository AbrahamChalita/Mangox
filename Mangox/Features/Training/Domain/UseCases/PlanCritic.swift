// Features/Training/Domain/UseCases/PlanCritic.swift
import Foundation

/// Client-side plan critic — validates proposed training plans before save (Phase 1).
enum PlanCritic {

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

    static let maxWeekToWeekTSSIncrease = 0.15
    static let minRestDaysPerWeek = 1

    static func validate(plan: TrainingPlan, ftp: Int) -> Verdict {
        var issues: [Issue] = []
        let safeFTP = max(1, ftp)

        issues.append(contentsOf: weekToWeekLoadIssues(plan: plan, ftp: safeFTP))
        issues.append(contentsOf: restDayIssues(plan: plan))
        issues.append(contentsOf: keySessionSpacingIssues(plan: plan))
        issues.append(contentsOf: weeklyTargetAlignmentIssues(plan: plan, ftp: safeFTP))

        return Verdict(issues: issues)
    }

    private static func weekToWeekLoadIssues(plan: TrainingPlan, ftp: Int) -> [Issue] {
        let weeklyTSS = plan.weeks.map { week in
            week.days.reduce(0.0) { $0 + $1.estimatedPlannedTSS(ftp: ftp) }
        }
        guard weeklyTSS.count >= 2 else { return [] }

        var issues: [Issue] = []
        for index in 1..<weeklyTSS.count {
            let prev = weeklyTSS[index - 1]
            let curr = weeklyTSS[index]
            guard prev > 0 else { continue }
            let jump = (curr - prev) / prev
            if jump > maxWeekToWeekTSSIncrease {
                issues.append(
                    Issue(
                        code: "week_tss_spike",
                        message: String(
                            format: "Week %d planned TSS jumps %.0f%% vs week %d — keep increases under %.0f%%.",
                            index + 1,
                            jump * 100,
                            index,
                            maxWeekToWeekTSSIncrease * 100
                        ),
                        severity: .warning
                    )
                )
            }
        }
        return issues
    }

    private static func restDayIssues(plan: TrainingPlan) -> [Issue] {
        var issues: [Issue] = []
        for week in plan.weeks {
            let workoutDays = week.days.filter {
                switch $0.dayType {
                case .workout, .ftpTest, .optionalWorkout, .commute: return true
                default: return false
                }
            }.count
            let restDays = max(0, 7 - workoutDays)
            if restDays < minRestDaysPerWeek {
                issues.append(
                    Issue(
                        code: "insufficient_rest",
                        message: "Week \(week.weekNumber) has fewer than \(minRestDaysPerWeek) rest/easy day(s).",
                        severity: .warning
                    )
                )
            }
        }
        return issues
    }

    private static func keySessionSpacingIssues(plan: TrainingPlan) -> [Issue] {
        var issues: [Issue] = []
        for week in plan.weeks {
            let keyDays = week.days
                .filter { $0.isKeyWorkout && $0.dayType != .optionalWorkout && $0.dayType != .rest }
                .sorted { $0.dayOfWeek < $1.dayOfWeek }

            for pair in zip(keyDays, keyDays.dropFirst()) {
                if pair.1.dayOfWeek - pair.0.dayOfWeek == 1 {
                    issues.append(
                        Issue(
                            code: "back_to_back_key",
                            message: "Week \(week.weekNumber): key sessions \"\(pair.0.title)\" and \"\(pair.1.title)\" are on consecutive days.",
                            severity: .warning
                        )
                    )
                }
            }
        }
        return issues
    }

    private static func weeklyTargetAlignmentIssues(plan: TrainingPlan, ftp: Int) -> [Issue] {
        var issues: [Issue] = []
        for week in plan.weeks {
            let computed = week.days.reduce(0.0) { $0 + $1.estimatedPlannedTSS(ftp: ftp) }
            let targetMid = Double(week.tssTarget.lowerBound + week.tssTarget.upperBound) / 2
            guard targetMid > 0, computed > 0 else { continue }

            let deviation = abs(computed - targetMid) / targetMid
            if deviation > 0.25 {
                issues.append(
                    Issue(
                        code: "tss_target_mismatch",
                        message: String(
                            format: "Week %d computed TSS %.0f differs from target mid %.0f by %.0f%%.",
                            week.weekNumber,
                            computed,
                            targetMid,
                            deviation * 100
                        ),
                        severity: .warning
                    )
                )
            }
        }
        return issues
    }
}

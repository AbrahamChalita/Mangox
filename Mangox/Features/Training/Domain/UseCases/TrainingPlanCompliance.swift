// Features/Training/Domain/UseCases/TrainingPlanCompliance.swift
import Foundation

// MARK: - Zone → approximate intensity factor (fraction of FTP) for TSS estimation

extension TrainingZoneTarget {
    /// Midpoint IF used for steady-state TSS estimates (planning).
    var approximateIntensityFactor: Double {
        switch self {
        case .z1: return 0.50
        case .z2: return 0.65
        case .z3: return 0.80
        case .z4: return 0.95
        case .z5: return 1.12
        case .z1z2: return 0.60
        case .z2z3: return 0.72
        case .z3z4: return 0.88
        case .z3z5: return 0.95
        case .z4z5: return 1.02
        case .mixed: return 0.85
        case .all: return 0.85
        case .rest, .none: return 0.40
        }
    }
}

extension IntervalSegment {
    /// TSS contribution: work + recovery intervals at recovery zone IF.
    func estimatedTSSContribution(ftp: Int) -> Double {
        guard ftp > 0 else { return 0 }
        let ftpD = Double(ftp)
        let workIF = zone.approximateIntensityFactor
        let workTSS = tssForSeconds(durationSeconds * repeats, intensityFactor: workIF, ftp: ftpD)
        guard repeats > 1, recoverySeconds > 0 else { return workTSS }
        let recIF = recoveryZone.approximateIntensityFactor
        let recTSS = tssForSeconds(recoverySeconds * (repeats - 1), intensityFactor: recIF, ftp: ftpD)
        return workTSS + recTSS
    }

    private func tssForSeconds(_ seconds: Int, intensityFactor: Double, ftp: Double) -> Double {
        guard seconds > 0 else { return 0 }
        return Double(seconds) * intensityFactor * intensityFactor / 36.0
    }
}

extension PlanDay {
    /// Rough planned TSS for calendar / compliance (not identical to completed workout NP).
    func estimatedPlannedTSS(ftp: Int) -> Double {
        guard ftp > 0 else { return 0 }
        switch dayType {
        case .rest, .event, .race:
            return 0
        case .workout, .ftpTest, .optionalWorkout, .commute:
            break
        }
        if !intervals.isEmpty {
            return intervals.reduce(0) { $0 + $1.estimatedTSSContribution(ftp: ftp) }
        }
        let sec = durationMinutes * 60
        let ifac: Double =
            dayType == .commute ? TrainingZoneTarget.z2.approximateIntensityFactor : zone.approximateIntensityFactor
        return Double(sec) * ifac * ifac / 36.0
    }
}

// MARK: - Weekly compliance (planned vs actual)

struct TrainingPlanCompliance {
    let plannedWeekTSS: Double
    let actualWeekTSS: Double
    let completionRatio: Double
    let keySessionsPlanned: Int
    let keySessionsCompleted: Int

    var percentOfPlanned: Double {
        guard plannedWeekTSS > 0 else { return 0 }
        return min(1.5, actualWeekTSS / plannedWeekTSS)
    }

    /// Calendar week (Mon–Sun) containing `referenceDate`, aligned with `FitnessTracker` week logic.
    static func currentWeekRange(referenceDate: Date = .now) -> (start: Date, end: Date) {
        let cal = Calendar.current
        guard let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: referenceDate)) else {
            let d = cal.startOfDay(for: referenceDate)
            return (d, d)
        }
        let start = cal.startOfDay(for: weekStart)
        let end = cal.date(byAdding: .day, value: 7, to: start) ?? start
        return (start, end)
    }

    /// Planned TSS from the active training plan for days mapped into this calendar week.
    static func compute(
        plan: TrainingPlan,
        progress: TrainingPlanProgress,
        ftp: Int,
        actualWeekTSS: Double,
        referenceDate: Date = .now
    ) -> TrainingPlanCompliance {
        let range = currentWeekRange(referenceDate: referenceDate)
        var planned: Double = 0
        var keyPlanned = 0
        var keyDone = 0

        for day in plan.allDays {
            let d = progress.calendarDate(for: day)
            guard d >= range.start, d < range.end else { continue }
            let countsTowardVolume =
                day.dayType == .workout || day.dayType == .ftpTest || day.dayType == .optionalWorkout
                || day.dayType == .commute
            guard countsTowardVolume else { continue }
            planned += day.estimatedPlannedTSS(ftp: ftp)
            let mandatoryKey = day.isKeyWorkout && day.dayType != .optionalWorkout
            if mandatoryKey {
                keyPlanned += 1
                if progress.isCompleted(day.id) { keyDone += 1 }
            }
        }

        let ratio = planned > 0 ? actualWeekTSS / planned : 0
        return TrainingPlanCompliance(
            plannedWeekTSS: planned,
            actualWeekTSS: actualWeekTSS,
            completionRatio: ratio,
            keySessionsPlanned: keyPlanned,
            keySessionsCompleted: keyDone
        )
    }
}

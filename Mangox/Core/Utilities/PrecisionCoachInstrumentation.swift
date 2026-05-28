// Core/Utilities/PrecisionCoachInstrumentation.swift
import Foundation
import OSLog

/// Privacy-preserving OSLog hooks + local outcome persistence for precision coach tracking.
nonisolated enum PrecisionCoachInstrumentation {
    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Mangox",
        category: "PrecisionCoach"
    )

    static func planGenerated(planID: String, criticWarnings: Int, criticErrors: Int) {
        log.info(
            "plan_generated id=\(planID, privacy: .public) warnings=\(criticWarnings) errors=\(criticErrors)"
        )
        PrecisionCoachOutcomeStore.record(
            .init(
                kind: .planGenerated,
                planID: planID,
                numericValue: Double(criticWarnings),
                numericValue2: Double(criticErrors)
            )
        )
    }

    static func planStarted(planID: String) {
        log.info("plan_started id=\(planID, privacy: .public)")
        PrecisionCoachOutcomeStore.record(.init(kind: .planStarted, planID: planID))
    }

    static func planDayCompleted(planID: String, dayID: String, source: String) {
        log.info(
            "plan_day_completed plan=\(planID, privacy: .public) day=\(dayID, privacy: .public) source=\(source, privacy: .public)"
        )
        PrecisionCoachOutcomeStore.record(
            .init(kind: .planDayCompleted, planID: planID, dayID: dayID, source: source)
        )
    }

    static func adaptiveLoadAdjusted(planID: String, oldMultiplier: Double, newMultiplier: Double, tsb: Double?) {
        let tsbText = tsb.map { String(format: "%.1f", $0) } ?? "n/a"
        log.info(
            "adaptive_load plan=\(planID, privacy: .public) \(oldMultiplier, privacy: .public)→\(newMultiplier, privacy: .public) tsb=\(tsbText, privacy: .public)"
        )
        PrecisionCoachOutcomeStore.record(
            .init(
                kind: .adaptiveLoadAdjusted,
                planID: planID,
                numericValue: oldMultiplier,
                numericValue2: newMultiplier,
                note: tsbText
            )
        )
    }

    static func ftpApplied(oldFTP: Int, newFTP: Int, source: String) {
        log.info(
            "ftp_applied \(oldFTP)→\(newFTP, privacy: .public) source=\(source, privacy: .public)"
        )
        PrecisionCoachOutcomeStore.record(
            .init(
                kind: .ftpApplied,
                source: source,
                numericValue: Double(oldFTP),
                numericValue2: Double(newFTP)
            )
        )
    }

    static func planForwardSimulated(horizonDays: Int, deltaTSB: Double) {
        log.debug(
            "plan_forward_sim days=\(horizonDays) delta_tsb=\(deltaTSB, privacy: .public)"
        )
        PrecisionCoachOutcomeStore.record(
            .init(
                kind: .planForwardSimulated,
                numericValue: Double(horizonDays),
                numericValue2: deltaTSB
            )
        )
    }

    static func criticalPowerFit(cpWatts: Int, wPrimeKJ: Int, rSquared: Double) {
        log.debug(
            "cp_fit cp=\(cpWatts)W wprime=\(wPrimeKJ)kJ r2=\(rSquared, privacy: .public)"
        )
    }

    static func workoutGenerated(title: String, warningCount: Int) {
        log.info("workout_generated title=\(title, privacy: .public) warnings=\(warningCount)")
        PrecisionCoachOutcomeStore.record(
            .init(
                kind: .workoutGenerated,
                numericValue: Double(warningCount),
                note: title
            )
        )
    }
}

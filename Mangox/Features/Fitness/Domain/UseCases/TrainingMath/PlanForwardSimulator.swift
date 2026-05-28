// Features/Fitness/Domain/UseCases/TrainingMath/PlanForwardSimulator.swift
import Foundation

/// Forward PMC simulation for an exact proposed plan TSS vector (Phase 1 precision coach).
nonisolated enum PlanForwardSimulator {

    struct Result: Sendable, Equatable {
        let horizonDays: Int
        let startingCTL: Double
        let startingATL: Double
        let startingTSB: Double
        let endingCTL: Double
        let endingATL: Double
        let endingTSB: Double
        let totalPlannedTSS: Double
        let projection: [PMCProjection.ProjectedDay]

        var deltaTSB: Double { endingTSB - startingTSB }

        var plainLanguageSummary: String {
            String(
                format: "After %d plan days: CTL %.1f→%.1f, ATL %.1f→%.1f, TSB %+.1f→%+.1f (Δ%+.1f, %d TSS total)",
                horizonDays,
                startingCTL, endingCTL,
                startingATL, endingATL,
                startingTSB, endingTSB,
                deltaTSB,
                Int(totalPlannedTSS.rounded())
            )
        }
    }

    nonisolated static func simulate(
        currentCTL: Double,
        currentATL: Double,
        dailyTSS: [Double]
    ) -> Result? {
        guard !dailyTSS.isEmpty else { return nil }

        let projection = PMCProjection.project(
            currentCTL: max(0, currentCTL),
            currentATL: max(0, currentATL),
            dailyTSS: dailyTSS
        )
        guard let last = projection.last else { return nil }

        let startTSB = currentCTL - currentATL
        return Result(
            horizonDays: dailyTSS.count,
            startingCTL: currentCTL,
            startingATL: currentATL,
            startingTSB: startTSB,
            endingCTL: last.ctl,
            endingATL: last.atl,
            endingTSB: last.tsb,
            totalPlannedTSS: dailyTSS.reduce(0, +),
            projection: projection
        )
    }
}

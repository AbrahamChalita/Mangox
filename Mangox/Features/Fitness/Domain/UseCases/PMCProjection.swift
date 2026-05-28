// Features/Fitness/Domain/UseCases/PMCProjection.swift
import Foundation

/// Pure forward simulation of Performance Management Chart (CTL/ATL/TSB) using the same
/// exponential moving average rules as FitnessTracker.
///
/// This is the foundation for the precision AI coach: the model can call this to answer
/// "what will my fitness/form look like if I follow this plan?" instead of guessing.
///
/// All functions are non-isolated (explicitly opt out of the app-wide @MainActor default),
/// pure, and fully testable with no side effects.
nonisolated enum PMCProjection {

    /// Matches FitnessTracker.ctlDays / atlDays
    nonisolated static let defaultCTLDays = 42
    nonisolated static let defaultATLDays = 7

    private nonisolated static var defaultCTLAlpha: Double {
        2.0 / Double(defaultCTLDays + 1)
    }

    private nonisolated static var defaultATLAlpha: Double {
        2.0 / Double(defaultATLDays + 1)
    }

    /// One projected day in a forward simulation.
    struct ProjectedDay: Identifiable, Sendable, Equatable {
        public var id: Int { dateOffset }
        /// 0 = today (starting point), 1 = tomorrow, etc.
        let dateOffset: Int
        let ctl: Double
        let atl: Double
        let tsb: Double
        /// The daily TSS that was applied for this step (for explainability)
        let appliedTSS: Double
    }

    /// Projects forward from current state using an explicit daily TSS sequence.
    ///
    /// - Parameters:
    ///   - currentCTL: Starting chronic load (from FitnessTracker or snapshot).
    ///   - currentATL: Starting acute load.
    ///   - dailyTSS: TSS planned for each future day (index 0 = tomorrow).
    ///   - ctlAlpha / atlAlpha: Pass explicit values to stay in sync with FitnessTracker.
    /// - Returns: Array of projected days (does not include the starting "today" state).
    nonisolated static func project(
        currentCTL: Double,
        currentATL: Double,
        dailyTSS: [Double],
        ctlAlpha: Double? = nil,
        atlAlpha: Double? = nil
    ) -> [ProjectedDay] {
        let cAlpha = ctlAlpha ?? defaultCTLAlpha
        let aAlpha = atlAlpha ?? defaultATLAlpha

        var ctl = currentCTL
        var atl = currentATL
        var results: [ProjectedDay] = []

        for (offset, tss) in dailyTSS.enumerated() {
            let safeTSS = max(0, tss)
            ctl = ctl + cAlpha * (safeTSS - ctl)
            atl = atl + aAlpha * (safeTSS - atl)
            let tsb = ctl - atl

            results.append(
                ProjectedDay(
                    dateOffset: offset + 1,
                    ctl: ctl,
                    atl: atl,
                    tsb: tsb,
                    appliedTSS: safeTSS
                )
            )
        }
        return results
    }

    /// Convenience: project a constant weekly TSS load, evenly distributed across days.
    ///
    /// Useful for quick "what if I average X TSS per week for the next N weeks?" questions.
    nonisolated static func projectConstantWeeklyLoad(
        currentCTL: Double,
        currentATL: Double,
        weeklyTSS: Double,
        numberOfWeeks: Int,
        daysPerWeek: Int = 7
    ) -> [ProjectedDay] {
        let daily = weeklyTSS / Double(daysPerWeek)
        let totalDays = numberOfWeeks * daysPerWeek
        let plan = Array(repeating: daily, count: totalDays)
        return project(currentCTL: currentCTL, currentATL: currentATL, dailyTSS: plan)
    }

    /// Summarizes the end state of a projection (handy for coach context / tool output).
    nonisolated static func summary(from projection: [ProjectedDay]) -> String {
        guard let last = projection.last else { return "No projection." }
        return String(
            format: "After %d days: CTL %.1f, ATL %.1f, TSB %+.1f (from last applied %.0f TSS)",
            last.dateOffset,
            last.ctl,
            last.atl,
            last.tsb,
            last.appliedTSS
        )
    }
}

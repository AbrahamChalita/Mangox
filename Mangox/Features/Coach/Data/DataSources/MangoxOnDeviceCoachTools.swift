import Foundation
import FoundationModels

// MARK: - Shared tool arguments (parallel “weather-style” fetches)

@Generable
struct MangoxOnDeviceToolFilter: Equatable {
    @Guide(
        description:
            "Optional lowercase substring to narrow lines (notes, route, FTP row). Use an empty string for the full tool output."
    )
    var filterSubstring: String
}

private enum MangoxOnDeviceLineFilter {
    /// Callable from `@concurrent` `Tool.call` implementations (not MainActor-isolated).
    nonisolated static func apply(_ raw: String, to digest: String) -> String {
        let f = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if f.isEmpty { return digest }
        let lines = digest.split(separator: "\n", omittingEmptySubsequences: false)
        let hit = lines.filter { $0.lowercased().contains(f) }
        if hit.isEmpty {
            return "No lines matched filter \"\(f)\".\n\n\(digest)"
        }
        return hit.joined(separator: "\n")
    }
}

/// Last ~20 completed rides: date, TSS, duration, notes, route (on-device retrieval).
struct MangoxOnDeviceRecentWorkoutsTool: Tool {
    let digest: String

    var name: String { "mangox_recent_workouts" }

    var description: String {
        "Recent completed rides with dates, TSS, duration, optional notes and route labels. Use for history beyond the baseline snapshot."
    }

    @concurrent func call(arguments: MangoxOnDeviceToolFilter) async throws -> String {
        MangoxOnDeviceLineFilter.apply(arguments.filterSubstring, to: digest)
    }
}

/// Weight, age, season goal, plan semantics hint (on-device).
struct MangoxOnDeviceRiderExtendedTool: Tool {
    let digest: String

    var name: String { "mangox_rider_extended_profile" }

    var description: String {
        "Extended rider fields: weight, age, season goal summary, and active-plan semantics hints when present."
    }

    @concurrent func call(arguments: MangoxOnDeviceToolFilter) async throws -> String {
        MangoxOnDeviceLineFilter.apply(arguments.filterSubstring, to: digest)
    }
}

/// FTP test history rows (on-device UserDefaults store).
struct MangoxOnDeviceFTPHistoryTool: Tool {
    let digest: String

    var name: String { "mangox_ftp_test_history" }

    var description: String {
        "Historical FTP test results with dates and estimated FTP. Use for progression or test-specific questions."
    }

    @concurrent func call(arguments: MangoxOnDeviceToolFilter) async throws -> String {
        MangoxOnDeviceLineFilter.apply(arguments.filterSubstring, to: digest)
    }
}

/// Latest WHOOP recovery/profile values when connected.
struct MangoxOnDeviceWhoopRecoveryTool: Tool {
    let digest: String

    var name: String { "mangox_whoop_recovery" }

    var description: String {
        "Latest WHOOP recovery and profile values such as recovery score, resting HR, HRV, and max heart rate when available."
    }

    @concurrent func call(arguments: MangoxOnDeviceToolFilter) async throws -> String {
        MangoxOnDeviceLineFilter.apply(arguments.filterSubstring, to: digest)
    }
}

/// Active plan and current load/scheduling context.
struct MangoxOnDeviceActivePlanTool: Tool {
    let digest: String

    var name: String { "mangox_active_plan_context" }

    var description: String {
        "Current active plan summary, progress, adaptive ERG scaling, weekly TSS, season goal, and related scheduling notes."
    }

    @concurrent func call(arguments: MangoxOnDeviceToolFilter) async throws -> String {
        MangoxOnDeviceLineFilter.apply(arguments.filterSubstring, to: digest)
    }
}

// MARK: - PMC forward projection tool (precision coach foundation)

@Generable
struct MangoxPMCProjectionArgs: Equatable {
    @Guide(description: "Current CTL (chronic/fitness). Use latest known value or ~40 if unknown.")
    var currentCTL: Double

    @Guide(description: "Current ATL (acute/fatigue). Use latest known value or ~30 if unknown.")
    var currentATL: Double

    @Guide(description: "Target average weekly TSS to simulate (e.g. 350, 420).")
    var weeklyTSS: Double

    @Guide(description: "Projection horizon in whole weeks (1 to 12).")
    var weeks: Int
}

/// Allows the on-device narrow coach to run "what if I hold X TSS per week?" simulations
/// using the exact same EMA math as the app's PMC chart. Pure and private.
struct MangoxOnDevicePMCProjectionTool: Tool {
    var name: String { "mangox_pmc_projection" }

    var description: String {
        "Forward-simulate Performance Management Chart (CTL, ATL, TSB) for a proposed constant weekly TSS load. Returns projected fitness, fatigue, and form at the end of the horizon plus a short trend summary. Use this before giving any advice about future load, periodization, or race readiness."
    }

    @concurrent func call(arguments: MangoxPMCProjectionArgs) async throws -> String {
        let safeWeeks = max(1, min(arguments.weeks, 12))
        let safeCTL = max(0, arguments.currentCTL)
        let safeATL = max(0, arguments.currentATL)
        let safeWeekly = max(0, arguments.weeklyTSS)

        let projection = PMCProjection.projectConstantWeeklyLoad(
            currentCTL: safeCTL,
            currentATL: safeATL,
            weeklyTSS: safeWeekly,
            numberOfWeeks: safeWeeks
        )

        guard !projection.isEmpty else {
            return "Unable to project with the given inputs."
        }

        let last = projection.last!
        let startTSB = safeCTL - safeATL
        let endTSB = last.tsb

        var lines: [String] = [
            "Projection horizon: \(safeWeeks) weeks at \(Int(safeWeekly)) TSS/week",
            String(format: "Starting: CTL %.1f, ATL %.1f, TSB %+.1f", safeCTL, safeATL, startTSB),
            String(format: "Ending:   CTL %.1f, ATL %.1f, TSB %+.1f", last.ctl, last.atl, endTSB),
            "Delta TSB: \(String(format: "%+.1f", endTSB - startTSB))"
        ]

        // Simple qualitative note the model can use
        if endTSB > startTSB + 5 {
            lines.append("Form is expected to improve meaningfully.")
        } else if endTSB < startTSB - 8 {
            lines.append("Form is expected to drop — higher injury/fatigue risk if sustained.")
        }

        lines.append(PMCProjection.summary(from: projection))
        return lines.joined(separator: "\n")
    }
}

// MARK: - Aerobic decoupling trend (precision coach)

/// Multi-ride Pw:HR drift trend from precomputed digest (oldest → newest rides).
struct MangoxOnDeviceDecouplingTrendTool: Tool {
    let digest: String

    var name: String { "mangox_decoupling_trend" }

    var description: String {
        "Aerobic decoupling (Pw:HR drift) trend across recent steady endurance rides: slope, direction, and per-ride values. Use before advising on endurance progression or base training."
    }

    @concurrent func call(arguments: MangoxOnDeviceToolFilter) async throws -> String {
        MangoxOnDeviceLineFilter.apply(arguments.filterSubstring, to: digest)
    }
}

// MARK: - Power curve summary (precision coach)

/// Best rolling-average power at standard durations from recent rides.
struct MangoxOnDevicePowerCurveSummaryTool: Tool {
    let digest: String

    var name: String { "mangox_power_curve_summary" }

    var description: String {
        "Best power curve (5s through 1h rolling averages) from recent rides, with watts and FTP multiples when FTP is known. Use for sprint/VO2/threshold capability questions."
    }

    @concurrent func call(arguments: MangoxOnDeviceToolFilter) async throws -> String {
        MangoxOnDeviceLineFilter.apply(arguments.filterSubstring, to: digest)
    }
}

// MARK: - Critical power model (Phase 1)

struct MangoxOnDeviceCriticalPowerTool: Tool {
    let digest: String

    var name: String { "mangox_critical_power" }

    var description: String {
        "Two-parameter critical power (CP) and W′ estimate from recent mean-maximal power durations. Use for pacing, fatigue, and interval feasibility — not for inventing CP/W′."
    }

    @concurrent func call(arguments: MangoxOnDeviceToolFilter) async throws -> String {
        MangoxOnDeviceLineFilter.apply(arguments.filterSubstring, to: digest)
    }
}

// MARK: - Plan forward PMC simulation (Phase 1)

@Generable
struct MangoxPlanForwardSimArgs: Equatable {
    @Guide(description: "Current CTL (chronic/fitness).")
    var currentCTL: Double

    @Guide(description: "Current ATL (acute/fatigue).")
    var currentATL: Double

    @Guide(description: "Forward horizon in days (1–42), using the active plan's daily TSS from tomorrow.")
    var horizonDays: Int
}

/// Simulates CTL/ATL/TSB following the active plan's daily TSS vector (not constant weekly load).
struct MangoxOnDevicePlanForwardSimTool: Tool {
    let dailyTSSFromPlan: [Double]

    var name: String { "mangox_plan_forward_sim" }

    var description: String {
        "Forward-simulate PMC (CTL, ATL, TSB) using the active training plan's daily TSS from tomorrow. Returns ending form and load vs starting values. Use before advising on plan changes, race taper, or block progression."
    }

    @concurrent func call(arguments: MangoxPlanForwardSimArgs) async throws -> String {
        guard !dailyTSSFromPlan.isEmpty else {
            return "No active plan daily TSS vector available. Ask the rider to start a plan or use mangox_pmc_projection for a constant weekly load scenario."
        }

        let safeDays = max(1, min(arguments.horizonDays, min(42, dailyTSSFromPlan.count)))
        let vector = Array(dailyTSSFromPlan.prefix(safeDays))
        let safeCTL = max(0, arguments.currentCTL)
        let safeATL = max(0, arguments.currentATL)

        guard let result = PlanForwardSimulator.simulate(
            currentCTL: safeCTL,
            currentATL: safeATL,
            dailyTSS: vector
        ) else {
            return "Unable to simulate with the given inputs."
        }

        PrecisionCoachInstrumentation.planForwardSimulated(
            horizonDays: safeDays,
            deltaTSB: result.deltaTSB
        )

        var lines = [
            "Active plan forward sim (\(safeDays) days from tomorrow):",
            result.plainLanguageSummary,
        ]

        if result.deltaTSB > 5 {
            lines.append("Form is expected to improve over this block.")
        } else if result.deltaTSB < -10 {
            lines.append("Form is expected to fall — watch fatigue and recovery.")
        }

        if let last = result.projection.last {
            lines.append(
                String(format: "Final day applied TSS: %.0f", last.appliedTSS)
            )
        }

        return lines.joined(separator: "\n")
    }
}

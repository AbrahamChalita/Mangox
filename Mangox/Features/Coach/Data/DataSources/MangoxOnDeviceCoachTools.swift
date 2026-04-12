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

import Foundation

/// Golden fixtures and output validators for AFM prompt regression (Evaluations-framework-style harness).
enum FoundationModelsCoachEvaluation {

    // MARK: - Fixtures

    struct RoutingFixture: Sendable {
        let name: String
        let message: String
        let expectOnDevice: Bool
        let expectPCC: Bool
        let expectCloudBackend: Bool
    }

    static let routingFixtures: [RoutingFixture] = [
        RoutingFixture(
            name: "stats_tss",
            message: "What's my TSS this week?",
            expectOnDevice: true,
            expectPCC: false,
            expectCloudBackend: false
        ),
        RoutingFixture(
            name: "plan_build",
            message: "Build me a training plan for my event",
            expectOnDevice: false,
            expectPCC: true,
            expectCloudBackend: false
        ),
        RoutingFixture(
            name: "web_search",
            message: "Search the web for latest polarized training study",
            expectOnDevice: false,
            expectPCC: false,
            expectCloudBackend: true
        ),
        RoutingFixture(
            name: "local_spotlight",
            message: "Find my notes about Leadville training",
            expectOnDevice: true,
            expectPCC: false,
            expectCloudBackend: false
        ),
        RoutingFixture(
            name: "intervals_today",
            message: "Should I do intervals today?",
            expectOnDevice: false,
            expectPCC: true,
            expectCloudBackend: false
        ),
        RoutingFixture(
            name: "sweet_spot_vs_threshold",
            message: "Compare sweet spot vs threshold for me",
            expectOnDevice: false,
            expectPCC: true,
            expectCloudBackend: false
        ),
        RoutingFixture(
            name: "short_greeting",
            message: "Hi",
            expectOnDevice: true,
            expectPCC: false,
            expectCloudBackend: false
        ),
        RoutingFixture(
            name: "long_context_plan",
            message: String(repeating: "detail ", count: 120) + "build a race plan",
            expectOnDevice: false,
            expectPCC: true,
            expectCloudBackend: false
        ),
    ]

    static let sampleFactSheet = """
        Rider: FTP 245W, max HR 188, resting HR 52.
        Week TSS: 312. Recovery: moderate.
        Last ride (Jun 1): TSS 68, 52min, 198W avg.
        Active plan: Base Build. Progress: week 3/12.
        """

    // MARK: - Validators

    /// Returns nil when valid, or a failure reason.
    nonisolated static func validateNarrowReply(_ reply: NarrowCoachReply) -> String? {
        let body = reply.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty { return "empty body" }
        if body.contains("\n"), !bodyHasOnlyBulletNewlines(body) {
            return "body contains invalid newline"
        }
        if body.count > 1300 { return "body exceeds narrow limit (\(body.count))" }
        if reply.tags.count > 4 { return "too many tags" }
        if !reply.category.isEmpty,
            !CoachReplyMetadataSupport.allowedCategories.contains(reply.category.lowercased())
        {
            return "invalid category"
        }
        for action in reply.suggestedActions {
            if action.label.count > 48 { return "suggested action too long" }
        }
        return nil
    }

    nonisolated private static func bodyHasOnlyBulletNewlines(_ body: String) -> Bool {
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 1 else { return true }
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("• ") { continue }
            return false
        }
        return true
    }

    nonisolated static func validateWorkoutInsight(
        headline: String,
        bullets: [String],
        narrative: String?
    ) -> String? {
        if headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "empty headline"
        }
        if bullets.isEmpty { return "no bullets" }
        if bullets.count > 5 { return "too many bullets" }
        if let narrative, narrative.count > 320 { return "narrative too long" }
        return nil
    }

    // MARK: - Routing simulation (no FM calls)

    nonisolated static func simulatedDeliveryPath(
        userMessage: String,
        planIntake: Bool,
        pccAvailable: Bool
    ) -> CoachDeliveryPath {
        if !planIntake, OnDeviceCoachEngine.heuristicPrefersPCCWebSearch(for: userMessage) {
            if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *),
                MangoxPrivateCloudComputeModelFactory.isLiveWebSearchAvailable,
                pccAvailable
            {
                return .privateCloudCompute
            }
            return .mangoxCloudBackend
        }
        if !planIntake, OnDeviceCoachEngine.passesOnDeviceNarrowHeuristics(for: userMessage) {
            return .onDeviceNarrow
        }
        if pccAvailable {
            return .privateCloudCompute
        }
        return .mangoxCloudBackend
    }
}

/// Coach message delivery tier (on-device → PCC → Mangox cloud).
enum CoachDeliveryPath: String, Equatable, Sendable {
    case onDeviceNarrow
    case privateCloudCompute
    case mangoxCloudBackend

    /// Maps a persisted assistant `category` back to a delivery path for telemetry.
    nonisolated static func fromMessageCategory(_ category: String?) -> CoachDeliveryPath {
        switch category?.lowercased() ?? "" {
        case "on_device", "on_device_coach":
            return .onDeviceNarrow
        case "pcc_coach", "plan_intake", "plan_analysis", "pcc_web_search":
            return .privateCloudCompute
        default:
            return .mangoxCloudBackend
        }
    }

    var instrumentationLabel: String { rawValue }
}

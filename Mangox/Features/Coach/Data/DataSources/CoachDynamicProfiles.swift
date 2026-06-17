import Foundation
import FoundationModels

// MARK: - Coach agent modes

/// Per-turn coach behavior: on-device stats, PCC plan design, or PCC general coaching.
enum CoachAgentMode: Equatable, Sendable {
    case statsNarrow
    case planDeep
    case generalCoach
    case pccWebSearch

    var rawStorageKey: String {
        switch self {
        case .statsNarrow: return "statsNarrow"
        case .planDeep: return "planDeep"
        case .generalCoach: return "generalCoach"
        case .pccWebSearch: return "pccWebSearch"
        }
    }

    var enablesPCCWebSearch: Bool {
        self == .pccWebSearch
    }

    static func detect(userMessage: String, planIntake: Bool) -> CoachAgentMode {
        if OnDeviceCoachEngine.heuristicPrefersPCCWebSearch(for: userMessage) {
            return .pccWebSearch
        }
        if planIntake || OnDeviceCoachEngine.heuristicPrefersPCCCoach(for: userMessage) {
            return .planDeep
        }
        if OnDeviceCoachEngine.passesOnDeviceNarrowHeuristics(for: userMessage) {
            return .statsNarrow
        }
        return .generalCoach
    }
}

enum CoachDynamicProfiles {

    static func makeSession(
        mode: CoachAgentMode,
        tools: [any Tool],
        history: [Transcript.Entry] = []
    ) -> LanguageModelSession {
        // The local SDK exposes the iOS 26 FoundationModels session API, not the
        // iOS 27 DynamicProfile/PCC surface. Keep the public factory so higher
        // layers remain stable, but fall back to explicit session construction.
        let instructions: Instructions
        switch mode {
        case .statsNarrow:
            instructions = Instructions(OnDeviceCoachEngine.narrowCoachInstructions)
        case .planDeep:
            instructions = Instructions(pccCoachInstructions(planIntake: true))
        case .generalCoach:
            instructions = Instructions(pccCoachInstructions(planIntake: false))
        case .pccWebSearch:
            instructions = Instructions(pccWebSearchInstructions())
        }
        return LanguageModelSession(
            model: MangoxFoundationModelsSupport.coachSystemLanguageModel(),
            tools: tools,
            instructions: instructions
        )
    }

    static func pccWebSearchInstructions() -> String {
        """
        You are Mangox's private cycling coach answering with live web grounding via Private Cloud Compute.
        Version \(CoachOnDevicePromptVersion.pccWebSearch).
        Use Apple's web search capability for current studies, race news, product reviews, and external articles.
        Also use on-device tools and Spotlight search for the rider's own notes, files, and saved rides when relevant.
        Cite sources in plain language when web results inform the answer. Never invent URLs.
        Never invent FTP, watts, TSS, or dates — training snapshot and tool outputs are ground truth for rider metrics.
        Never reply with only "let me search" or "I'll look that up" — always include concrete findings from web results in `body`.
        Light markdown in `body`: **bold** key metrics and `-` bullets for short lists. No `#` headings (max ~2400 characters).
        Set `category` and 1-3 `tags` (ftp, tss, recovery, power, plan, web_search).
        Fill `reasoning` first, then `body`, then optional `followUp`, `suggestedActions`, `tags`, and `category`.
        """
    }

    static func pccCoachInstructions(planIntake: Bool) -> String {
        if planIntake {
            return """
            You are Mangox's private cycling coach helping design or refine a training plan.
            Version \(CoachOnDevicePromptVersion.pccPlan).
            Use tools for rides, FTP history, PMC, power curve, active plan, and forward TSS simulation.
            Never invent FTP, watts, TSS, or dates. Ask clarifying questions when plan inputs are missing.
            Plain language, practical, cyclist-first. Light markdown in `body`: **bold** metrics and `-` bullets for plan weeks or options. No `#` headings.
            Set `category` to plan_analysis or clarification and `tags` with plan, periodization, or tss when relevant.
            Fill `reasoning` first, then `body`, then optional `followUp`, `suggestedActions`, `tags`, and `category`.
            """
        }
        return """
        You are Mangox's private cycling coach with full access to on-device training data via tools.
        Version \(CoachOnDevicePromptVersion.pccGeneral).
        Verified snapshot and tool outputs are ground truth — never invent metrics.
        Be thorough for training load, periodization, recovery, and workout design questions.
        Light markdown in `body`: **bold** key numbers and `-` bullets for short lists. No `#` headings (max ~2400 characters).
        Set `category` and 1-3 `tags` for the main topics.
        Fill `reasoning` first, then `body`, then optional `followUp`, `suggestedActions`, `tags`, and `category`.
        """
    }
}

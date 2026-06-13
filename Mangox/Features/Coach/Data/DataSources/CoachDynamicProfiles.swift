import Foundation
import FoundationModels

// MARK: - Coach agent modes (iOS 27 Dynamic Profiles)

/// Per-turn coach behavior: on-device stats, PCC plan design, or PCC general coaching.
@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
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

@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
enum CoachDynamicProfiles {

    static func makeSession(
        mode: CoachAgentMode,
        tools: [any Tool],
        history: [Transcript.Entry] = []
    ) -> LanguageModelSession {
        let profile = MangoxCoachAgentProfile(mode: mode, tools: tools)
        return LanguageModelSession(profile: profile, history: history)
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

@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
private struct MangoxCoachAgentProfile: LanguageModelSession.DynamicProfile {
    let mode: CoachAgentMode
    let tools: [any Tool]

    @LanguageModelSession.DynamicProfileBuilder
    var body: some LanguageModelSession.DynamicProfile {
        switch mode {
        case .statsNarrow:
            statsNarrowProfile
        case .planDeep:
            planDeepProfile
        case .generalCoach:
            generalCoachProfile
        case .pccWebSearch:
            pccWebSearchProfile
        }
    }

    private var statsNarrowProfile: some LanguageModelSession.DynamicProfile {
        LanguageModelSession.Profile {
            Instructions(OnDeviceCoachEngine.narrowCoachInstructions)
            tools
        }
        .model(MangoxFoundationModelsSupport.coachSystemLanguageModel())
        .samplingMode(.greedy)
        .toolCallingMode(.allowed)
        .mangoxCoachInstrumentation(mode: .statsNarrow)
    }

    private var planDeepProfile: some LanguageModelSession.DynamicProfile {
        LanguageModelSession.Profile {
            Instructions(CoachDynamicProfiles.pccCoachInstructions(planIntake: true))
            tools
        }
        .model(MangoxPrivateCloudComputeModelFactory.coachModel(enableWebSearch: false))
        .samplingMode(.greedy)
        .reasoningLevel(.deep)
        .toolCallingMode(.allowed)
        .historyTransform(MangoxFoundationModelsSupport.coachHistoryTransform)
        .mangoxCoachInstrumentation(mode: .planDeep)
    }

    private var generalCoachProfile: some LanguageModelSession.DynamicProfile {
        LanguageModelSession.Profile {
            Instructions(CoachDynamicProfiles.pccCoachInstructions(planIntake: false))
            tools
        }
        .model(MangoxPrivateCloudComputeModelFactory.coachModel(enableWebSearch: false))
        .samplingMode(.greedy)
        .reasoningLevel(.moderate)
        .toolCallingMode(.allowed)
        .historyTransform(MangoxFoundationModelsSupport.coachHistoryTransform)
        .mangoxCoachInstrumentation(mode: .generalCoach)
    }

    private var pccWebSearchProfile: some LanguageModelSession.DynamicProfile {
        LanguageModelSession.Profile {
            Instructions(CoachDynamicProfiles.pccWebSearchInstructions())
            tools
        }
        .model(MangoxPrivateCloudComputeModelFactory.coachModel(enableWebSearch: true))
        .samplingMode(.greedy)
        .reasoningLevel(.deep)
        .toolCallingMode(.allowed)
        .historyTransform(MangoxFoundationModelsSupport.coachHistoryTransform)
        .mangoxCoachInstrumentation(mode: .pccWebSearch)
    }
}

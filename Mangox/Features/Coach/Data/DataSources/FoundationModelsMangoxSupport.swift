import Foundation
import FoundationModels
import os.log

// MARK: - Errors

enum MangoxFoundationModelsError: Error, LocalizedError {
    case unsupportedLocale

    var errorDescription: String? {
        switch self {
        case .unsupportedLocale:
            return "Apple Intelligence language/locale is not supported for this model."
        }
    }
}

// MARK: - Diagnostics (Console)

/// Centralized Foundation Models helpers: locale, guardrails model, token estimates, transcript logging, generation errors.
enum MangoxFoundationModelsSupport {
    /// Log each `Transcript.Entry` after sessions when `true`.
    nonisolated static let coachTranscriptDebugKey = "MangoxCoachFMTranscriptDebug"
    /// Log instruction + prompt + tool token estimates when `true`. In DEBUG, defaults to on unless explicitly set false.
    nonisolated static let tokenBudgetLogKey = "MangoxCoachFMTokenLog"

    nonisolated private static let logger = Logger(subsystem: "com.abchalita.Mangox", category: "FoundationModels")

    static var transcriptDebugEnabled: Bool {
        UserDefaults.standard.bool(forKey: coachTranscriptDebugKey)
    }

    nonisolated static var tokenBudgetLoggingEnabled: Bool {
        #if DEBUG
        if UserDefaults.standard.object(forKey: tokenBudgetLogKey) == nil { return true }
        #endif
        return UserDefaults.standard.bool(forKey: tokenBudgetLogKey)
    }

    /// On-device context window for token-budget logging (falls back when `contextSize` is unavailable).
    static func contextWindowTokens(for model: SystemLanguageModel) -> Int {
        if #available(iOS 26.4, macOS 26.4, visionOS 26.4, *) {
            return model.contextSize
        }
        return 4096
    }

    /// Deterministic token sampling for coach and insight generation.
    static var greedyGenerationOptions: GenerationOptions {
        GenerationOptions(samplingMode: .greedy)
    }

    /// Moderate temperature for short creative copy (captions, headlines, session titles).
    static var creativeGenerationOptions: GenerationOptions {
        GenerationOptions(samplingMode: .greedy, temperature: 0.75)
    }

    /// Narrow coach guided generation; enforces tool calls on iOS 27+ when `requireTools` on first turn.
    static func narrowGenerationOptions(requireTools: Bool, isFollowUp: Bool) -> GenerationOptions {
        if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) {
            let mode: GenerationOptions.ToolCallingMode =
                isFollowUp ? .allowed : (requireTools ? .required : .allowed)
            return GenerationOptions(samplingMode: .greedy, toolCallingMode: mode)
        }
        return greedyGenerationOptions
    }

    // MARK: - Private Cloud Compute (scaffold — no entitlement required to compile)

    /// True when Apple's PCC coach tier is available on this device (typically requires entitlement).
    static var isPrivateCloudComputeCoachAvailable: Bool {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return false }
        switch PrivateCloudComputeLanguageModel().availability {
        case .available: return true
        default: return false
        }
    }

    /// Whether PCC supports the active locale (iOS 27+).
    static func privateCloudComputeSupportsCurrentLocale() -> Bool {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return false }
        return PrivateCloudComputeLanguageModel().supportsLocale(Locale.current)
    }

    /// Returns a PCC model when available; otherwise `nil` (caller should use Mangox cloud API).
    @available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
    static func privateCloudComputeCoachModel() -> PrivateCloudComputeLanguageModel? {
        let model = PrivateCloudComputeLanguageModel()
        guard case .available = model.availability else { return nil }
        return model
    }

    /// Keeps the last 24 transcript entries for PCC sessions (roughly 12 turns).
    @available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
    static func coachHistoryTransform(_ entries: [Transcript.Entry]) -> [Transcript.Entry] {
        let maxEntries = 24
        guard entries.count > maxEntries else { return entries }
        return Array(entries.suffix(maxEntries))
    }

    /// Default on-device coach model with Apple’s default guardrails.
    static func coachSystemLanguageModel() -> SystemLanguageModel {
        SystemLanguageModel(useCase: .general, guardrails: .default)
    }

    static func throwIfLocaleUnsupported() throws {
        guard SystemLanguageModel.default.supportsLocale(Locale.current) else {
            throw MangoxFoundationModelsError.unsupportedLocale
        }
    }

    static func logTranscriptEntries(_ session: LanguageModelSession, label: String) {
        guard transcriptDebugEnabled else { return }
        for entry in session.transcript {
            logger.info(
                "FM entry [\(label, privacy: .public)]: \(String(describing: entry), privacy: .public)")
        }
    }

    static func logPromptFootprint(
        model: SystemLanguageModel,
        label: String,
        instructions: Instructions,
        prompt: String,
        tools: [any Tool]
    ) async {
        guard tokenBudgetLoggingEnabled else { return }
        guard #available(iOS 26.4, macOS 26.4, visionOS 26.4, *) else { return }
        do {
            let iTok = try await model.tokenCount(for: instructions)
            let pTok = try await model.tokenCount(for: prompt)
            let tTok = tools.isEmpty ? 0 : (try await model.tokenCount(for: tools))
            logger.info(
                "FM tokens [\(label, privacy: .public)] instructions=\(iTok) prompt=\(pTok) tools=\(tTok) totalEst=\(iTok + pTok + tTok) windowLimit=\(contextWindowTokens(for: model))"
            )
        } catch {
            logger.debug("FM tokenCount failed: \(error.localizedDescription)")
        }
    }

    /// Logs actual token usage from a completed FM response (iOS 27).
    /// Cached tokens are relevant for third-party providers billing on prompt tokens;
    /// reasoning tokens indicate PCC deep-reasoning spend.
    static func logResponseUsage(
        inputTotal: Int, inputCached: Int, outputTotal: Int, outputReasoning: Int, label: String
    ) {
        guard tokenBudgetLoggingEnabled else { return }
        logger.info(
            """
            FM usage [\(label, privacy: .public)] \
            in=\(inputTotal) cached=\(inputCached) \
            out=\(outputTotal) reasoning=\(outputReasoning)
            """
        )
    }

    /// `true` once `LanguageModelSession.Response.usage` ships in the public SDK.
    /// Absent from Xcode 27.0 beta-1 — re-check each Xcode beta and flip when available.
    nonisolated static let sdkExposesResponseUsage = false

    /// Wraps `session.respond` and logs `response.usage` when `sdkExposesResponseUsage` is true.
    /// Call this everywhere instead of `session.respond` directly so usage logging is enabled by
    /// flipping one flag once the property ships in the SDK.
    static func respond<T: Generable & Sendable>(
        session: LanguageModelSession,
        to prompt: String,
        generating type: T.Type,
        options: GenerationOptions,
        label: String
    ) async throws -> LanguageModelSession.Response<T> {
        let response = try await session.respond(to: prompt, generating: type, options: options)
        // When sdkExposesResponseUsage is true, add:
        // logResponseUsage(inputTotal: response.usage.input.totalTokenCount,
        //                  inputCached: response.usage.input.cachedTokenCount,
        //                  outputTotal: response.usage.output.totalTokenCount,
        //                  outputReasoning: response.usage.output.reasoningTokenCount,
        //                  label: label)
        return response
    }

    nonisolated static func logSnapshotSelection(fullChosen: Bool, tokenEstimate: Int) {
        guard tokenBudgetLoggingEnabled else { return }
        logger.info(
            "FM coach snapshot \(fullChosen ? "full" : "compact", privacy: .public) ~tokens=\(tokenEstimate)"
        )
    }

    /// Maps Apple generation errors for logging / user messaging.
    static func logGenerationFailure(_ error: Error, label: String) {
        if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) {
            if let pcc = error as? PrivateCloudComputeLanguageModel.Error {
                logger.warning("FM PCC error [\(label, privacy: .public)]: \(pcc.localizedDescription, privacy: .public)")
                return
            }
            if let modelErr = error as? LanguageModelError {
                logger.warning("FM LanguageModelError [\(label)]: \(String(describing: modelErr), privacy: .public)")
                return
            }
            if let sessionErr = error as? LanguageModelSession.Error {
                logger.warning("FM session error [\(label)]: \(String(describing: sessionErr), privacy: .public)")
                return
            }
        }
        if let toolErr = error as? LanguageModelSession.ToolCallError {
            logger.warning(
                "FM ToolCallError [\(label, privacy: .public)] tool=\(toolErr.tool.name, privacy: .public) underlying=\(String(describing: toolErr.underlyingError), privacy: .public)"
            )
            return
        }
        if let gen = error as? LanguageModelSession.GenerationError {
            switch gen {
            case .exceededContextWindowSize(let ctx):
                logger.warning("FM exceededContextWindow [\(label)]: \(ctx.debugDescription, privacy: .public)")
            case .unsupportedLanguageOrLocale(let ctx):
                logger.warning("FM unsupportedLocale [\(label)]: \(ctx.debugDescription, privacy: .public)")
            case .guardrailViolation(let ctx):
                logger.warning("FM guardrailViolation [\(label)]: \(ctx.debugDescription, privacy: .public)")
            case .refusal(_, let ctx):
                logger.warning("FM refusal [\(label)]: \(ctx.debugDescription, privacy: .public)")
            default:
                logger.warning("FM GenerationError [\(label)]: \(String(describing: gen), privacy: .public)")
            }
            return
        }
        logger.warning("FM error [\(label, privacy: .public)]: \(error.localizedDescription, privacy: .public)")
    }

    // MARK: - Feedback Assistant (evaluation harness)

    /// When `true`, successful sessions may call `LanguageModelSession.logFeedbackAttachment` so bad runs are easy to file from Feedback Assistant.
    static let feedbackAttachmentLogKey = "MangoxCoachFMFeedbackAttachment"

    static var feedbackAttachmentLoggingEnabled: Bool {
        UserDefaults.standard.bool(forKey: feedbackAttachmentLogKey)
    }

    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    static func logFeedbackAttachmentIfEnabled(
        session: LanguageModelSession,
        sentiment: LanguageModelFeedback.Sentiment?,
        issues: [LanguageModelFeedback.Issue] = [],
        desiredResponseText: String? = nil
    ) {
        guard feedbackAttachmentLoggingEnabled else { return }
        _ = session.logFeedbackAttachment(
            sentiment: sentiment,
            issues: issues,
            desiredResponseText: desiredResponseText
        )
    }

    // MARK: - Dynamic Profile hooks (iOS 27)

    @available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
    static func recordDynamicProfilePrompt(mode: CoachAgentMode, prompt: Transcript.Prompt) {
        guard tokenBudgetLoggingEnabled || coachFlowLoggingEnabled else { return }
        logger.info(
            "FM dynamicProfile prompt mode=\(mode.rawStorageKey, privacy: .public) segments=\(prompt.segments.count)"
        )
        PrecisionCoachInstrumentation.coachDynamicProfileEvent(
            phase: "prompt",
            mode: mode.rawStorageKey,
            detail: "segments=\(prompt.segments.count)"
        )
    }

    @available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
    static func recordDynamicProfileResponse(mode: CoachAgentMode, response: Transcript.Response) {
        guard tokenBudgetLoggingEnabled || coachFlowLoggingEnabled else { return }
        logger.info("FM dynamicProfile response mode=\(mode.rawStorageKey, privacy: .public)")
        PrecisionCoachInstrumentation.coachDynamicProfileEvent(
            phase: "response",
            mode: mode.rawStorageKey,
            detail: nil
        )
    }

    @available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
    static func recordDynamicProfileToolCall(mode: CoachAgentMode, toolCall: Transcript.ToolCall) {
        guard tokenBudgetLoggingEnabled || coachFlowLoggingEnabled else { return }
        logger.info(
            "FM dynamicProfile toolCall mode=\(mode.rawStorageKey, privacy: .public) tool=\(toolCall.toolName, privacy: .public)"
        )
        PrecisionCoachInstrumentation.coachDynamicProfileEvent(
            phase: "toolCall",
            mode: mode.rawStorageKey,
            detail: toolCall.toolName
        )
    }

    private static var coachFlowLoggingEnabled: Bool {
        #if DEBUG
        return UserDefaults.standard.object(forKey: "MangoxCoachChatFlowLog") as? Bool ?? true
        #else
        return UserDefaults.standard.bool(forKey: "MangoxCoachChatFlowLog")
        #endif
    }
}

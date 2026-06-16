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
        model.contextSize
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
        let mode: GenerationOptions.ToolCallingMode =
            isFollowUp ? .allowed : (requireTools ? .required : .allowed)
        return GenerationOptions(samplingMode: .greedy, toolCallingMode: mode)
    }

    // MARK: - Private Cloud Compute (scaffold — no entitlement required to compile)

    /// True when Apple's PCC coach tier is available on this device (typically requires entitlement).
    static var isPrivateCloudComputeCoachAvailable: Bool {
        switch PrivateCloudComputeLanguageModel().availability {
        case .available: return true
        default: return false
        }
    }

    /// Whether PCC supports the active locale (iOS 27+).
    static func privateCloudComputeSupportsCurrentLocale() -> Bool {
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

    /// Wraps `session.respond` and logs actual token usage from the completed response.
    static func respond<T: Generable & Sendable>(
        session: LanguageModelSession,
        to prompt: String,
        generating type: T.Type,
        options: GenerationOptions,
        label: String
    ) async throws -> LanguageModelSession.Response<T> {
        let response = try await session.respond(to: prompt, generating: type, options: options)
        logResponseUsage(
            inputTotal: response.usage.input.totalTokenCount,
            inputCached: response.usage.input.cachedTokenCount,
            outputTotal: response.usage.output.totalTokenCount,
            outputReasoning: response.usage.output.reasoningTokenCount,
            label: label
        )
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
        if let pcc = error as? PrivateCloudComputeLanguageModel.Error {
            logger.warning("FM PCC error [\(label, privacy: .public)]: \(pcc.localizedDescription, privacy: .public)")
            return
        }
        if let modelErr = error as? LanguageModelError {
            logLanguageModelError(modelErr, label: label)
            return
        }
        if let sessionErr = error as? LanguageModelSession.Error {
            logger.warning("FM session error [\(label)]: \(String(describing: sessionErr), privacy: .public)")
            return
        }
        if let toolErr = error as? LanguageModelSession.ToolCallError {
            logger.warning(
                "FM ToolCallError [\(label, privacy: .public)] tool=\(toolErr.tool.name, privacy: .public) underlying=\(String(describing: toolErr.underlyingError), privacy: .public)"
            )
            return
        }
        logger.warning("FM error [\(label, privacy: .public)]: \(error.localizedDescription, privacy: .public)")
    }

    private static func logLanguageModelError(_ error: LanguageModelError, label: String) {
        switch error {
        case .contextSizeExceeded(let context):
            logger.warning(
                "FM contextSizeExceeded [\(label, privacy: .public)]: tokens=\(context.tokenCount) contextSize=\(context.contextSize) \(context.debugDescription, privacy: .public)"
            )
        case .rateLimited(let context):
            logger.warning(
                "FM rateLimited [\(label, privacy: .public)]: reset=\(String(describing: context.resetDate), privacy: .public) \(context.debugDescription, privacy: .public)"
            )
        case .guardrailViolation(let context):
            logger.warning("FM guardrailViolation [\(label, privacy: .public)]: \(context.debugDescription, privacy: .public)")
        case .refusal(let context):
            logger.warning("FM refusal [\(label, privacy: .public)]: \(context.debugDescription, privacy: .public)")
        case .unsupportedCapability(let context):
            logger.warning(
                "FM unsupportedCapability [\(label, privacy: .public)]: \(String(describing: context.capability), privacy: .public) \(context.debugDescription, privacy: .public)"
            )
        case .unsupportedTranscriptContent(let context):
            logger.warning("FM unsupportedTranscriptContent [\(label, privacy: .public)]: \(context.debugDescription, privacy: .public)")
        case .unsupportedGenerationGuide(let context):
            logger.warning(
                "FM unsupportedGenerationGuide [\(label, privacy: .public)]: schema=\(String(describing: context.schemaName), privacy: .public) \(context.debugDescription, privacy: .public)"
            )
        case .unsupportedLanguageOrLocale(let context):
            logger.warning(
                "FM unsupportedLanguageOrLocale [\(label, privacy: .public)]: language=\(String(describing: context.languageCode), privacy: .public) \(context.debugDescription, privacy: .public)"
            )
        case .timeout(let context):
            logger.warning("FM timeout [\(label, privacy: .public)]: \(context.debugDescription, privacy: .public)")
        @unknown default:
            logger.warning("FM LanguageModelError [\(label, privacy: .public)]: \(String(describing: error), privacy: .public)")
        }
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

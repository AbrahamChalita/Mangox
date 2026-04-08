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
    static let coachTranscriptDebugKey = "MangoxCoachFMTranscriptDebug"
    /// Log instruction + prompt + tool token estimates when `true`. In DEBUG, defaults to on unless explicitly set false.
    static let tokenBudgetLogKey = "MangoxCoachFMTokenLog"

    private static let logger = Logger(subsystem: "com.abchalita.Mangox", category: "FoundationModels")

    static var transcriptDebugEnabled: Bool {
        UserDefaults.standard.bool(forKey: coachTranscriptDebugKey)
    }

    static var tokenBudgetLoggingEnabled: Bool {
        #if DEBUG
        if UserDefaults.standard.object(forKey: tokenBudgetLogKey) == nil { return true }
        #endif
        return UserDefaults.standard.bool(forKey: tokenBudgetLogKey)
    }

    /// Apple documents ~4096 tokens per `LanguageModelSession`.
    static let documentedContextWindowTokens = 4096

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
                "FM tokens [\(label, privacy: .public)] instructions=\(iTok) prompt=\(pTok) tools=\(tTok) totalEst=\(iTok + pTok + tTok) windowLimit=\(documentedContextWindowTokens)"
            )
        } catch {
            logger.debug("FM tokenCount failed: \(error.localizedDescription)")
        }
    }

    static func logSnapshotSelection(fullChosen: Bool, tokenEstimate: Int) {
        guard tokenBudgetLoggingEnabled else { return }
        logger.info(
            "FM coach snapshot \(fullChosen ? "full" : "compact", privacy: .public) ~tokens=\(tokenEstimate)"
        )
    }

    /// Maps Apple generation errors for logging / user messaging.
    static func logGenerationFailure(_ error: Error, label: String) {
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
}

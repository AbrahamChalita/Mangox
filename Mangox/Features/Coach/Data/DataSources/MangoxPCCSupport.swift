import Foundation
import FoundationModels

/// Private Cloud Compute helpers aligned with Apple's PCC documentation:
/// availability, quota, network/on-device fallback, and context sizing.
enum MangoxPCCSupport {

    // MARK: - Availability

    struct AvailabilityDetail: Sendable, Equatable {
        let isReady: Bool
        let settingsMessage: String?
    }

    @available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
    static func availabilityDetail() -> AvailabilityDetail {
        let model = PrivateCloudComputeLanguageModel()
        switch model.availability {
        case .available:
            return AvailabilityDetail(isReady: true, settingsMessage: nil)
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return AvailabilityDetail(
                    isReady: false,
                    settingsMessage: "This device does not support Apple Intelligence or Private Cloud Compute."
                )
            case .systemNotReady:
                return AvailabilityDetail(
                    isReady: false,
                    settingsMessage: "Turn on Apple Intelligence in Settings and connect to the internet to use Private Cloud."
                )
            @unknown default:
                return AvailabilityDetail(
                    isReady: false,
                    settingsMessage: "Private Cloud Compute is not available on this device."
                )
            }
        }
    }

    static var settingsAvailabilityLine: String {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else {
            return "Private Cloud Compute requires iOS 27 or later."
        }
        let detail = availabilityDetail()
        if detail.isReady {
            return "Private Cloud Compute is available on this device."
        }
        return detail.settingsMessage ?? "Private Cloud Compute is not available on this device."
    }

    // MARK: - Quota

    struct QuotaSnapshot: Sendable, Equatable {
        let isLimitReached: Bool
        let isApproachingLimit: Bool
        let resetDate: Date?
        let settingsSummary: String
    }

    @available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
    static func quotaSnapshot() -> QuotaSnapshot? {
        guard MangoxFoundationModelsSupport.isPrivateCloudComputeCoachAvailable else { return nil }
        let usage = PrivateCloudComputeLanguageModel().quotaUsage
        let approaching: Bool = {
            if case .belowLimit(let below) = usage.status { return below.isApproachingLimit }
            return false
        }()
        let summary: String
        if usage.isLimitReached {
            if let reset = usage.resetDate {
                summary = "Private Cloud daily limit reached — resets \(Self.shortResetLabel(reset))."
            } else {
                summary = "Private Cloud daily limit reached for today."
            }
        } else if approaching {
            summary = "Private Cloud usage is high today; heavy tasks like plan generation may hit the limit."
        } else {
            summary = "Private Cloud quota available."
        }
        return QuotaSnapshot(
            isLimitReached: usage.isLimitReached,
            isApproachingLimit: approaching,
            resetDate: usage.resetDate,
            settingsSummary: summary
        )
    }

    /// Blocks coach PCC turns when quota is exhausted.
    static func coachTurnQuotaBlockMessage() -> String? {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return nil }
        guard let snap = quotaSnapshot(), snap.isLimitReached else { return nil }
        return coachQuotaUserMessage(resetDate: snap.resetDate)
    }

    /// Plan generation uses skeleton + one call per week on PCC.
    static func throwIfPlanGenerationQuotaBlocked(estimatedPCCCalls: Int) throws {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }
        guard MangoxFoundationModelsSupport.isPrivateCloudComputeCoachAvailable else { return }
        guard let snap = quotaSnapshot(), snap.isLimitReached else { return }
        throw OnDevicePlanGeneratorError.quotaLimitReached(
            coachQuotaUserMessage(resetDate: snap.resetDate)
        )
    }

    @available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
    static func presentQuotaLimitIncreaseIfAvailable(from error: Error) {
        guard case .quotaLimitReached(let detail) = error as? PrivateCloudComputeLanguageModel.Error else {
            if let snap = quotaSnapshot(), snap.isLimitReached {
                PrivateCloudComputeLanguageModel().quotaUsage.limitIncreaseSuggestion?.show()
            }
            return
        }
        detail.limitIncreaseSuggestion?.show()
    }

    // MARK: - Errors

    static func isNetworkFailure(_ error: Error) -> Bool {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return false }
        if case .networkFailure = error as? PrivateCloudComputeLanguageModel.Error { return true }
        if let urlErr = error as? URLError {
            switch urlErr.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
                .cannotConnectToHost, .dnsLookupFailed:
                return true
            default:
                return false
            }
        }
        return false
    }

    /// PCC session could not be created (concurrency, entitlement, or system restriction) — safe to retry on-device.
    static func isSessionEstablishmentFailure(_ error: Error) -> Bool {
        if isQuotaLimitReached(error) { return false }

        let message = error.localizedDescription.lowercased()
        let failureMarkers = [
            "operation not permitted",
            "establishment of session failed",
            "sending cancel session failed",
            "sending deletion session failed",
            "create session",
            "modelmanagererror",
        ]
        if failureMarkers.contains(where: { message.contains($0) }) { return true }

        if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) {
            if error is LanguageModelError { return true }
            if error is LanguageModelSession.Error { return true }
            if let pcc = error as? PrivateCloudComputeLanguageModel.Error {
                switch pcc {
                case .networkFailure, .quotaLimitReached:
                    return false
                default:
                    return true
                }
            }
        }

        let ns = error as NSError
        if ns.domain.localizedCaseInsensitiveContains("foundationmodels")
            || ns.domain.localizedCaseInsensitiveContains("generativemodels")
        {
            return true
        }
        return false
    }

    /// When true, plan generation should retry with on-device FM instead of failing immediately.
    static func shouldFallbackToOnDeviceAfterPCCFailure(_ error: Error) -> Bool {
        isNetworkFailure(error) || isSessionEstablishmentFailure(error)
    }

    static func isQuotaLimitReached(_ error: Error) -> Bool {
        if let planErr = error as? OnDevicePlanGeneratorError, case .quotaLimitReached = planErr { return true }
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return false }
        if case .quotaLimitReached = error as? PrivateCloudComputeLanguageModel.Error { return true }
        return false
    }

    static func userFacingMessage(for error: Error) -> String? {
        if isQuotaLimitReached(error) {
            if let planErr = error as? OnDevicePlanGeneratorError { return planErr.localizedDescription }
            if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) {
                if case .quotaLimitReached(let detail) = error as? PrivateCloudComputeLanguageModel.Error {
                    return coachQuotaUserMessage(resetDate: detail.resetDate)
                }
                return coachQuotaUserMessage(resetDate: quotaSnapshot()?.resetDate)
            }
            return "Private Cloud daily limit reached for today."
        }
        if isNetworkFailure(error) {
            return "Private Cloud needs a network connection. Replied using on-device Apple Intelligence instead."
        }
        if isSessionEstablishmentFailure(error) {
            return "Private Cloud couldn't start a session. Mangox will try on-device or cloud generation instead."
        }
        return nil
    }

    // MARK: - Context size (32K on PCC)

    /// Token budget for inlined training snapshot text (not the full context window).
    static func snapshotTokenBudget(usePrivateCloudCompute: Bool) -> Int {
        usePrivateCloudCompute ? 8_000 : 1_900
    }

    @available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
    static func contextWindowTokens() async -> Int {
        let model = PrivateCloudComputeLanguageModel()
        do {
            return try await model.contextSize
        } catch {
            return 32_768
        }
    }

    // MARK: - Private

    private static func coachQuotaUserMessage(resetDate: Date?) -> String {
        if let resetDate {
            return "Private Cloud daily limit reached. Try again \(shortResetLabel(resetDate)), upgrade iCloud+ for more, or use on-device stats questions."
        }
        return "Private Cloud daily limit reached for today. Upgrade iCloud+ for more capacity, or try again later."
    }

    private static func shortResetLabel(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .none
        fmt.timeStyle = .short
        fmt.doesRelativeDateFormatting = true
        return fmt.string(from: date)
    }
}

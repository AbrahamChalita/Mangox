import Foundation
import os
import Supabase

/// Email + OTP sign-in flow.
///
/// Stage 1: `sendCode(to:)` posts the email; Supabase mails the code.
/// Stage 2: `verify(email:code:)` exchanges the code for a session. AuthState's
/// own `authStateChanges` listener picks up the new session automatically.
@MainActor
final class EmailSignInController {
    nonisolated static let otpCodeLength = 8
    nonisolated static let resendCooldownSeconds: UInt64 = 60
    private static let logger = Logger(subsystem: "abchalita.Mangox", category: "SupabaseAuth")

    enum EmailSignInError: LocalizedError {
        case notConfigured
        case invalidEmail
        case codeTooShort
        case underlying(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:  "Cloud sync isn't configured in this build."
            case .invalidEmail:   "Enter a valid email address."
            case .codeTooShort:   "Enter the \(EmailSignInController.otpCodeLength)-digit code from your email."
            case .underlying(let m): m
            }
        }
    }

    /// Stage 1 — request a one-time code.
    func sendCode(to email: String) async throws {
        guard let client = MangoxSupabase.shared else { throw EmailSignInError.notConfigured }
        let trimmed = Self.normalizedEmail(email)
        guard Self.isLikelyEmail(trimmed) else { throw EmailSignInError.invalidEmail }
        let startedAt = ContinuousClock.now
        Self.logAuthAttempt(action: "sendCode", email: trimmed)
        do {
            try await client.auth.signInWithOTP(email: trimmed, shouldCreateUser: true)
            Self.logAuthSuccess(action: "sendCode", email: trimmed, startedAt: startedAt)
        } catch {
            Self.logAuthError(error, action: "sendCode", email: trimmed, startedAt: startedAt)
            throw EmailSignInError.underlying(Self.userFacingMessage(for: error))
        }
    }

    /// Stage 2 — verify the code and obtain a Supabase session.
    @discardableResult
    func verify(email: String, code: String) async throws -> Session {
        guard let client = MangoxSupabase.shared else { throw EmailSignInError.notConfigured }
        let trimmedEmail = Self.normalizedEmail(email)
        let trimmedCode  = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedCode.count == Self.otpCodeLength else { throw EmailSignInError.codeTooShort }
        let startedAt = ContinuousClock.now
        Self.logAuthAttempt(action: "verifyCode", email: trimmedEmail)
        do {
            let response = try await client.auth.verifyOTP(
                email: trimmedEmail,
                token: trimmedCode,
                type: .email
            )
            guard let session = response.session else {
                throw EmailSignInError.underlying("Server didn't return a session.")
            }
            Self.logAuthSuccess(action: "verifyCode", email: trimmedEmail, startedAt: startedAt)
            return session
        } catch let signInError as EmailSignInError {
            throw signInError
        } catch {
            Self.logAuthError(error, action: "verifyCode", email: trimmedEmail, startedAt: startedAt)
            throw EmailSignInError.underlying(Self.userFacingMessage(for: error))
        }
    }

    static func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func isLikelyEmail(_ s: String) -> Bool {
        // Loose pre-check; Supabase does the real validation server-side.
        s.contains("@") && s.contains(".") && !s.contains(" ")
    }

    private static func userFacingMessage(for error: Error) -> String {
        let message = detailedMessage(for: error)
        let lowercased = message.lowercased()

        if lowercased.contains("email address not authorized") {
            return "This Supabase project is still using the demo email sender. Enable custom SMTP with Resend to send codes to any address."
        }

        if lowercased.contains("rate limit") || lowercased.contains("too many") || lowercased.contains("429") {
            return "Please wait a minute before requesting another sign-in code."
        }

        if lowercased.contains("otp_expired")
            || lowercased.contains("token has expired")
            || lowercased.contains("token is invalid")
        {
            return "That code expired or doesn't match. Request a new code and enter the latest \(Self.otpCodeLength)-digit code."
        }

        return message
    }

    private static func detailedMessage(for error: Error) -> String {
        if case let AuthError.api(message, errorCode, underlyingData, underlyingResponse) = error {
            let requestID = underlyingResponse.value(forHTTPHeaderField: "sb-request-id") ?? "unknown"
            let gatewayErrorCode = underlyingResponse.value(forHTTPHeaderField: "x-sb-error-code") ?? "none"
            let body = String(data: underlyingData, encoding: .utf8) ?? "<\(underlyingData.count) bytes>"
            return """
            \(message) [code: \(errorCode.rawValue), gatewayCode: \(gatewayErrorCode), status: \(underlyingResponse.statusCode), request: \(requestID), body: \(body)]
            """
        }

        let localized = error.localizedDescription
        let reflected = String(reflecting: error)

        if reflected != localized,
           !localized.isEmpty,
           localized != "The operation couldn't be completed." {
            return "\(localized) (\(reflected))"
        }

        return reflected
    }

    private static func logAuthAttempt(action: String, email: String) {
        let domain = email.split(separator: "@").last.map(String.init) ?? "unknown"
        logger.info("""
        Supabase auth \(action, privacy: .public) starting \
        [project: \(MangoxSupabase.projectHostForDiagnostics, privacy: .public), \
        emailDomain: \(domain, privacy: .public)]
        """)
    }

    private static func logAuthSuccess(action: String, email: String, startedAt: ContinuousClock.Instant) {
        let domain = email.split(separator: "@").last.map(String.init) ?? "unknown"
        logger.info("""
        Supabase auth \(action, privacy: .public) succeeded \
        [emailDomain: \(domain, privacy: .public), elapsedMs: \(elapsedMilliseconds(since: startedAt), privacy: .public)]
        """)
    }

    private static func logAuthError(
        _ error: Error,
        action: String,
        email: String,
        startedAt: ContinuousClock.Instant
    ) {
        let domain = email.split(separator: "@").last.map(String.init) ?? "unknown"
        logger.error("""
        Supabase auth \(action, privacy: .public) failed \
        [project: \(MangoxSupabase.projectHostForDiagnostics, privacy: .public), \
        emailDomain: \(domain, privacy: .public), \
        elapsedMs: \(elapsedMilliseconds(since: startedAt), privacy: .public)] \
        \(detailedMessage(for: error), privacy: .public)
        """)

        logTroubleshootingHint(for: error)
    }

    private static func logTroubleshootingHint(for error: Error) {
        guard case let AuthError.api(_, errorCode, _, response) = error,
              response.statusCode >= 500 || errorCode == .unexpectedFailure
        else { return }

        let requestID = response.value(forHTTPHeaderField: "sb-request-id") ?? "unknown"
        logger.notice("""
        Supabase Auth returned a server-side email send failure. \
        Search Supabase Auth logs for request id \(requestID, privacy: .public). \
        If Resend has no matching log, re-check Supabase SMTP password, port, and sender domain.
        """)
    }

    private static func elapsedMilliseconds(since startedAt: ContinuousClock.Instant) -> Int {
        let duration = startedAt.duration(to: ContinuousClock.now)
        return Int(Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15)
    }
}

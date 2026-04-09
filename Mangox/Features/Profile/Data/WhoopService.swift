import AuthenticationServices
import Foundation
import os.log
import Security
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

private let whoopLogger = Logger(subsystem: "com.abchalita.Mangox", category: "WhoopService")

/// OAuth + read-only access to WHOOP member data ([developer.whoop.com](https://developer.whoop.com/)).
/// WHOOP does not expose public APIs to upload workouts; Mangox can still save rides to Apple Health so members may import them in the WHOOP app when that integration is enabled.
@Observable
@MainActor
final class WhoopService: WhoopServiceProtocol {
    enum WhoopError: LocalizedError {
        case notConfigured
        case invalidAuthURL
        case userCancelled
        case authPresentationFailed
        case missingAuthorizationCode
        case oauthReturnedError(String)
        case stateMismatch
        case networkUnavailable
        case requestTimedOut(String)
        case tokenExchangeFailed(String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "WHOOP is not configured. Add WHOOP_CLIENT_ID and WHOOP_CLIENT_SECRET in build settings and register the redirect URL in the WHOOP Developer Dashboard."
            case .invalidAuthURL:
                return "Unable to build WHOOP authorization URL."
            case .userCancelled:
                return "WHOOP authorization was canceled."
            case .authPresentationFailed:
                return "Unable to open WHOOP login. Keep the app in foreground and try again."
            case .missingAuthorizationCode:
                return "WHOOP did not return an authorization code."
            case .oauthReturnedError(let message):
                return "WHOOP authorization failed: \(message)"
            case .stateMismatch:
                return "WHOOP sign-in could not be verified. Try connecting again."
            case .networkUnavailable:
                return "You appear to be offline. Check your connection and try again."
            case .requestTimedOut(let context):
                return "\(context) timed out. Try again on a stronger connection."
            case .tokenExchangeFailed(let message):
                return "WHOOP token exchange failed: \(message)"
            case .invalidResponse:
                return "Invalid response from WHOOP."
            }
        }
    }

    private struct Session: Codable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Int
        var memberFirstName: String?
        var memberLastName: String?

        var displayName: String {
            let full = [memberFirstName, memberLastName]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return full.isEmpty ? "WHOOP member" : full
        }
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int
        let token_type: String?
        let scope: String?
    }

    private struct ProfileDTO: Decodable {
        let firstName: String
        let lastName: String
    }

    private struct CycleCollectionDTO: Decodable {
        struct Record: Decodable {
            let id: Int
        }

        let records: [Record]?
    }

    /// Recovery for a cycle ([WHOOP tutorial](https://developer.whoop.com/docs/tutorials/get-current-recovery-score/)).
    private struct RecoveryDTO: Decodable {
        struct Score: Decodable {
            let recoveryScore: Double?
            let restingHeartRate: Int?
            let hrvRmssdMilli: Double?
        }

        let scoreState: String?
        let score: Score?
    }

    /// `GET /v2/user/measurement/body` — includes WHOOP-estimated max HR ([API docs](https://developer.whoop.com/api/)).
    private struct BodyMeasurementDTO: Decodable {
        let heightMeter: Double?
        let weightKilogram: Double?
        let maxHeartRate: Int?
    }

    /// UserDefaults key — when true (default), WHOOP max & resting HR update `HeartRateZone` after each refresh (unless manual overrides are set).
    static let syncHeartBaselinesDefaultsKey = "whoop_sync_hr_baselines"

    var isConnected = false
    var memberDisplayName: String?
    /// Most recent recovery score from WHOOP (0–100), when available.
    var latestRecoveryScore: Double?
    var latestRecoveryRestingHR: Int?
    var latestRecoveryHRV: Int?
    var isBusy = false
    var lastError: String?
    /// Set after a successful `refreshLinkedData()` (profile + recovery fetch).
    private(set) var lastSuccessfulRefreshAt: Date?
    /// Max HR from WHOOP body-measurement endpoint (not workout peak).
    private(set) var latestMaxHeartRateFromProfile: Int?

    var isConfigured: Bool {
        !clientID.isEmpty && !clientSecret.isEmpty && !redirectURIString.isEmpty
    }

    private static let authorizeURL = URL(string: "https://api.prod.whoop.com/oauth/oauth2/auth")!
    private static let tokenURL = URL(string: "https://api.prod.whoop.com/oauth/oauth2/token")!
    /// REST resources live under `/developer` (OAuth endpoints do not).
    private static let apiBase = URL(string: "https://api.prod.whoop.com/developer")!
    private static let keychainAccount = "whoop.session.v1"
    private static let requestTimeout: TimeInterval = 25
    private static let resourceTimeout: TimeInterval = 60
    /// Space-delimited OAuth scopes ([WHOOP API docs](https://developer.whoop.com/api/)).
    private static let oauthScopes =
        "offline read:profile read:recovery read:workout read:sleep read:cycles read:body_measurement"

    private let clientID: String
    private let clientSecret: String
    private let redirectURIString: String
    private let presentationContextProvider = WhoopWebAuthPresentationContextProvider()
    private let urlSession: URLSession
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private var session: Session?
    private var authSession: ASWebAuthenticationSession?
    private var pendingOAuthState: String?
    private var refreshTask: Task<String, Error>?

    init() {
        self.clientID = Self.infoValue(for: "WHOOP_CLIENT_ID")
        self.clientSecret = Self.infoValue(for: "WHOOP_CLIENT_SECRET")
        self.redirectURIString = Self.infoValue(
            for: "WHOOP_REDIRECT_URI",
            fallback: "mangox://localhost/whoop-auth"
        )
        self.urlSession = Self.makeSession()
        restoreSession()
    }

    /// When true, Mangox writes WHOOP max HR (body API) and resting HR (recovery) into `HeartRateZone` if the user has not set manual overrides.
    var syncHeartBaselinesFromWhoop: Bool {
        get {
            if UserDefaults.standard.object(forKey: Self.syncHeartBaselinesDefaultsKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Self.syncHeartBaselinesDefaultsKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.syncHeartBaselinesDefaultsKey) }
    }

    /// Applies latest cached WHOOP values to `HeartRateZone` when sync is enabled and connected.
    func applyHeartBaselinesFromLatestWhoopData() {
        guard syncHeartBaselinesFromWhoop, isConnected else { return }
        if let maxHR = latestMaxHeartRateFromProfile, (100...240).contains(maxHR),
            !HeartRateZone.hasManualMaxHROverride
        {
            HeartRateZone.maxHR = maxHR
        }
        if let rhr = latestRecoveryRestingHR, (30...120).contains(rhr),
            !HeartRateZone.hasManualRestingHROverride
        {
            HeartRateZone.restingHR = rhr
        }
    }

    func connect() async throws {
        guard isConfigured else { throw WhoopError.notConfigured }

        whoopLogger.info("WHOOP connect started — redirectURI: \(self.redirectURIString)")

        isBusy = true
        defer { isBusy = false }

        do {
            let code = try await authorizeAndGetCode()
            whoopLogger.info("WHOOP authorization code received, exchanging for token…")
            let tokenResponse = try await requestToken(grantType: "authorization_code", code: code)
            guard let refresh = tokenResponse.refresh_token, !refresh.isEmpty else {
                throw WhoopError.tokenExchangeFailed("No refresh token. Ensure the offline scope is granted.")
            }
            let newSession = mapSession(tokenResponse, refreshToken: refresh, previous: nil)
            try persistSession(newSession)
            applySession(newSession)
            lastError = nil
            await refreshLinkedDataIgnoringErrors()
            whoopLogger.info("WHOOP connected successfully as \(newSession.displayName)")
        } catch {
            whoopLogger.error("WHOOP connect failed: \(error.localizedDescription)")
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            throw error
        }
    }

    /// Refetches profile, latest recovery, and recent workouts from WHOOP (read-only API).
    func refreshLinkedData() async throws {
        guard isConfigured else { throw WhoopError.notConfigured }
        _ = try await validAccessToken()
        try await performDataRefresh()
    }

    private func refreshLinkedDataIgnoringErrors() async {
        do {
            try await refreshLinkedData()
        } catch {
            whoopLogger.warning("WHOOP post-connect refresh failed: \(error.localizedDescription)")
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func performDataRefresh() async throws {
        let token = try await validAccessToken()

        let profileURL = Self.apiBase.appendingPathComponent("v2/user/profile/basic")
        let profile: ProfileDTO = try await getJSON(url: profileURL, token: token, context: "WHOOP profile")
        if var current = session {
            current.memberFirstName = profile.firstName
            current.memberLastName = profile.lastName
            try persistSession(current)
            applySession(current)
        }

        await loadLatestRecoveryMetrics(accessToken: token)
        await loadBodyMeasurements(accessToken: token)

        applyHeartBaselinesFromLatestWhoopData()

        lastError = nil
        lastSuccessfulRefreshAt = Date()
    }

    private func loadBodyMeasurements(accessToken: String) async {
        let url = Self.apiBase.appendingPathComponent("v2/user/measurement/body")
        do {
            let body: BodyMeasurementDTO = try await getJSON(
                url: url,
                token: accessToken,
                context: "WHOOP body measurements"
            )
            if let m = body.maxHeartRate, (100...240).contains(m) {
                latestMaxHeartRateFromProfile = m
            } else {
                latestMaxHeartRateFromProfile = nil
            }
        } catch {
            whoopLogger.warning("WHOOP body measurements failed (non-fatal): \(error.localizedDescription)")
            latestMaxHeartRateFromProfile = nil
        }
    }

    /// Refreshes from WHOOP when connected and cached data is older than `maximumAge`, or never refreshed.
    func refreshLinkedDataIfStale(maximumAge: TimeInterval = 4 * 60 * 60) async {
        guard isConnected, isConfigured else { return }
        if isBusy { return }
        if let last = lastSuccessfulRefreshAt, Date().timeIntervalSince(last) < maximumAge {
            return
        }
        do {
            try await refreshLinkedData()
        } catch {
            whoopLogger.warning("WHOOP stale refresh failed: \(error.localizedDescription)")
        }
    }

    private func loadLatestRecoveryMetrics(accessToken: String) async {
        var cycleComponents = URLComponents(
            url: Self.apiBase.appendingPathComponent("v2/cycle"),
            resolvingAgainstBaseURL: true
        )
        cycleComponents?.queryItems = [URLQueryItem(name: "limit", value: "1")]
        guard let cycleURL = cycleComponents?.url else {
            clearRecoveryMetrics()
            return
        }

        do {
            let cycles: CycleCollectionDTO = try await getJSON(
                url: cycleURL,
                token: accessToken,
                context: "WHOOP cycles"
            )
            guard let cycleId = cycles.records?.first?.id else {
                clearRecoveryMetrics()
                return
            }

            let recoveryURL = Self.apiBase.appendingPathComponent("v2/cycle/\(cycleId)/recovery")
            guard let recovery: RecoveryDTO = try await getJSONIfOK(
                url: recoveryURL,
                token: accessToken,
                context: "WHOOP recovery"
            ) else {
                clearRecoveryMetrics()
                return
            }

            guard recovery.scoreState == "SCORED", let score = recovery.score?.recoveryScore else {
                clearRecoveryMetrics()
                return
            }

            latestRecoveryScore = score
            latestRecoveryRestingHR = recovery.score?.restingHeartRate
            if let hrv = recovery.score?.hrvRmssdMilli {
                latestRecoveryHRV = Int(hrv.rounded())
            } else {
                latestRecoveryHRV = nil
            }
        } catch {
            whoopLogger.warning("WHOOP recovery path failed (non-fatal): \(error.localizedDescription)")
            clearRecoveryMetrics()
        }
    }

    private func clearRecoveryMetrics() {
        latestRecoveryScore = nil
        latestRecoveryRestingHR = nil
        latestRecoveryHRV = nil
    }

    func disconnect() async {
        if session != nil {
            do {
                let token = try await validAccessToken()
                try await revokeRemote(accessToken: token)
            } catch {
                whoopLogger.warning("WHOOP revoke failed (continuing local disconnect): \(error.localizedDescription)")
            }
        }
        clearLocalSession()
    }

    private func clearLocalSession() {
        session = nil
        memberDisplayName = nil
        clearRecoveryMetrics()
        latestMaxHeartRateFromProfile = nil
        isConnected = false
        lastError = nil
        lastSuccessfulRefreshAt = nil
        _ = try? WhoopKeychainStorage.delete(account: Self.keychainAccount)
    }

    // MARK: - OAuth

    private func authorizeAndGetCode() async throws -> String {
        guard let redirectURI = URL(string: redirectURIString) else {
            whoopLogger.error("Invalid WHOOP redirect URI string: \(self.redirectURIString)")
            throw WhoopError.invalidAuthURL
        }

        let state = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16).lowercased()
        let stateString = String(state)
        pendingOAuthState = stateString

        var components = URLComponents(url: Self.authorizeURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.oauthScopes),
            URLQueryItem(name: "state", value: stateString),
        ]

        guard let url = components?.url else {
            throw WhoopError.invalidAuthURL
        }

        let callbackScheme = redirectURI.scheme
        whoopLogger.info("Starting WHOOP ASWebAuthenticationSession — callbackScheme: \(callbackScheme ?? "nil")")

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { [self] callbackURL, error in
                self.authSession = nil
                defer { self.pendingOAuthState = nil }

                if let error = error as? ASWebAuthenticationSessionError {
                    switch error.code {
                    case .canceledLogin:
                        continuation.resume(throwing: WhoopError.userCancelled)
                    case .presentationContextInvalid, .presentationContextNotProvided:
                        continuation.resume(throwing: WhoopError.authPresentationFailed)
                    default:
                        continuation.resume(throwing: error)
                    }
                    return
                }

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let callbackURL else {
                    continuation.resume(throwing: WhoopError.missingAuthorizationCode)
                    return
                }

                let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []

                if let errorCode = items.first(where: { $0.name == "error" })?.value {
                    let desc = items.first(where: { $0.name == "error_description" })?.value?
                        .replacingOccurrences(of: "+", with: " ")
                        .removingPercentEncoding ?? errorCode
                    continuation.resume(throwing: WhoopError.oauthReturnedError(desc))
                    return
                }

                guard let returnedState = items.first(where: { $0.name == "state" })?.value,
                      returnedState == stateString
                else {
                    continuation.resume(throwing: WhoopError.stateMismatch)
                    return
                }

                guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
                    continuation.resume(throwing: WhoopError.missingAuthorizationCode)
                    return
                }

                continuation.resume(returning: code)
            }

            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = presentationContextProvider
            authSession = session
            _ = session.start()
        }
    }

    private func requestToken(
        grantType: String,
        code: String? = nil,
        refreshToken: String? = nil
    ) async throws -> TokenResponse {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = Self.requestTimeout

        var items: [URLQueryItem] = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "grant_type", value: grantType),
        ]
        if let code {
            items.append(URLQueryItem(name: "code", value: code))
            items.append(URLQueryItem(name: "redirect_uri", value: redirectURIString))
        }
        if let refreshToken {
            items.append(URLQueryItem(name: "refresh_token", value: refreshToken))
            items.append(URLQueryItem(name: "scope", value: "offline"))
        }
        var body = URLComponents()
        body.queryItems = items
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await send(request, context: "WHOOP sign-in")
        guard let http = response as? HTTPURLResponse else {
            throw WhoopError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw WhoopError.tokenExchangeFailed(message)
        }

        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw WhoopError.tokenExchangeFailed("Unable to decode token response.")
        }
    }

    private func validAccessToken() async throws -> String {
        guard let current = session else {
            throw WhoopError.tokenExchangeFailed("No WHOOP session. Connect your account first.")
        }

        let now = Int(Date().timeIntervalSince1970)
        if current.expiresAt - now > 90 {
            return current.accessToken
        }

        if let existing = refreshTask {
            return try await existing.value
        }

        let task = Task<String, Error> { [weak self] in
            guard let self, var current = self.session else {
                throw WhoopError.tokenExchangeFailed("Session lost during refresh.")
            }
            let refreshed = try await self.requestToken(
                grantType: "refresh_token",
                refreshToken: current.refreshToken
            )
            guard let newRefresh = refreshed.refresh_token, !newRefresh.isEmpty else {
                throw WhoopError.tokenExchangeFailed("Refresh response missing refresh_token.")
            }
            current = self.mapSession(refreshed, refreshToken: newRefresh, previous: current)
            try self.persistSession(current)
            self.applySession(current)
            return current.accessToken
        }

        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func mapSession(
        _ response: TokenResponse,
        refreshToken: String,
        previous: Session?
    ) -> Session {
        let now = Int(Date().timeIntervalSince1970)
        let expiresAt = now + max(response.expires_in, 60)
        return Session(
            accessToken: response.access_token,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            memberFirstName: previous?.memberFirstName,
            memberLastName: previous?.memberLastName
        )
    }

    private func revokeRemote(accessToken: String) async throws {
        let url = Self.apiBase.appendingPathComponent("v2/user/access")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = Self.requestTimeout

        let (data, response) = try await send(request, context: "WHOOP revoke")
        guard let http = response as? HTTPURLResponse else {
            throw WhoopError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw WhoopError.tokenExchangeFailed(message)
        }
    }

    // MARK: - HTTP helpers

    private func getJSON<T: Decodable>(url: URL, token: String, context: String) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = Self.requestTimeout

        let (data, response) = try await send(request, context: context)
        guard let http = response as? HTTPURLResponse else {
            throw WhoopError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw WhoopError.tokenExchangeFailed(message)
        }
        return try decoder.decode(T.self, from: data)
    }

    /// `nil` when the server responds **404** (e.g. no recovery yet for the current cycle).
    private func getJSONIfOK<T: Decodable>(
        url: URL,
        token: String,
        context: String
    ) async throws -> T? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = Self.requestTimeout

        let (data, response) = try await send(request, context: context)
        guard let http = response as? HTTPURLResponse else {
            throw WhoopError.invalidResponse
        }
        if http.statusCode == 404 {
            return nil
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw WhoopError.tokenExchangeFailed(message)
        }
        return try decoder.decode(T.self, from: data)
    }

    private func send(_ request: URLRequest, context: String) async throws -> (Data, URLResponse) {
        do {
            return try await urlSession.data(for: request)
        } catch let error as URLError {
            whoopLogger.warning("\(context, privacy: .public) URLError \(error.code.rawValue)")
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
                 .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed:
                throw WhoopError.networkUnavailable
            case .timedOut:
                throw WhoopError.requestTimedOut(context)
            default:
                throw WhoopError.tokenExchangeFailed(error.localizedDescription)
            }
        }
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.requestCachePolicy = .useProtocolCachePolicy
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1"
        configuration.httpAdditionalHeaders = [
            "Accept": "application/json",
            "User-Agent": "Mangox/\(version) (WHOOP; iOS)",
        ]
        return URLSession(configuration: configuration)
    }

    private func persistSession(_ session: Session) throws {
        let data = try JSONEncoder().encode(session)
        try WhoopKeychainStorage.save(data: data, account: Self.keychainAccount)
    }

    private func restoreSession() {
        do {
            guard let data = try WhoopKeychainStorage.read(account: Self.keychainAccount) else {
                return
            }
            let restored = try JSONDecoder().decode(Session.self, from: data)
            applySession(restored)
        } catch {
            whoopLogger.error("Failed to restore WHOOP session: \(error.localizedDescription)")
            _ = try? WhoopKeychainStorage.delete(account: Self.keychainAccount)
        }
    }

    private func applySession(_ session: Session) {
        self.session = session
        isConnected = true
        memberDisplayName = session.displayName
    }

    private static func infoValue(for key: String, fallback: String = "") -> String {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) else {
            return fallback
        }
        if let value = raw as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return fallback }
            if trimmed.hasPrefix("$("), trimmed.hasSuffix(")") {
                return fallback
            }
            return trimmed
        }
        if let value = raw as? NSNumber {
            return value.stringValue
        }
        return fallback
    }
}

// MARK: - Readiness (UI + coach)

extension WhoopService {
    /// Approximate WHOOP-style recovery bands for copy and tinting.
    enum ReadinessBand: Sendable {
        case strong, moderate, low, unknown

        static func from(recoveryPercent: Double?) -> ReadinessBand {
            guard let p = recoveryPercent else { return .unknown }
            if p >= 67 { return .strong }
            if p >= 34 { return .moderate }
            return .low
        }
    }

    var readinessBand: ReadinessBand {
        ReadinessBand.from(recoveryPercent: latestRecoveryScore)
    }

    var readinessAccentColor: Color {
        switch readinessBand {
        case .strong: return AppColor.success
        case .moderate: return AppColor.yellow
        case .low: return AppColor.orange
        case .unknown: return AppColor.whoop.opacity(0.85)
        }
    }

    /// Short coaching hint from latest recovery, when scored.
    var readinessTrainingHint: String {
        guard let p = latestRecoveryScore else {
            return "WHOOP is linked — recovery will appear after your next sync."
        }
        switch readinessBand {
        case .strong:
            return "Recovery looks strong — suitable for quality or higher load if the plan calls for it."
        case .moderate:
            return "Moderate recovery — prioritize plan adherence but avoid extra hard stacking today."
        case .low:
            return "Low recovery — bias easy endurance, sleep, and fueling; skip optional intensity."
        case .unknown:
            return String(format: "Latest WHOOP recovery: %.0f%%.", p)
        }
    }
}

// MARK: - Presentation anchor (same pattern as Strava)

@MainActor
private final class WhoopWebAuthPresentationContextProvider: NSObject,
    ASWebAuthenticationPresentationContextProviding
{
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
        let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = windowScenes.first(where: { $0.activationState == .foregroundActive }) ?? windowScenes.first

        if let scene {
            if let keyWindow = scene.keyWindow {
                return keyWindow
            }
            if let keyWindow = scene.windows.first(where: { $0.isKeyWindow }) {
                return keyWindow
            }
            if let anyWindow = scene.windows.first {
                return anyWindow
            }
            return UIWindow(windowScene: scene)
        }

        if let w = UIApplication.shared.delegate.flatMap({ $0.window }) {
            return w!
        }
        fatalError("No presentation anchor for WHOOP OAuth — no UIWindowScene or delegate window")
        #elseif canImport(AppKit)
        return NSApplication.shared.keyWindow ?? NSWindow()
        #else
        fatalError("Unsupported platform for WHOOP OAuth")
        #endif
    }
}

// MARK: - Keychain

private enum WhoopKeychainStorage {
    enum KeychainError: Error {
        case operationFailed(OSStatus)
    }

    static func save(data: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus != errSecItemNotFound {
            throw KeychainError.operationFailed(updateStatus)
        }
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.operationFailed(addStatus)
        }
    }

    static func read(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.operationFailed(status)
        }
        return item as? Data
    }

    static func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.operationFailed(status)
        }
    }
}

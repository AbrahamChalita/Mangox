// Features/Social/Data/DataSources/StravaService.swift
import Foundation
import AuthenticationServices
import os.log
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

private let stravaLogger = Logger(subsystem: "com.abchalita.Mangox", category: "StravaService")

@Observable
@MainActor
final class StravaService: StravaServiceProtocol {
    typealias UploadResult = StravaUploadResult

    /// Values for Strava’s `sport_type` upload field (case-sensitive). See upload API docs.
    enum SportType {
        static let virtualRide = "VirtualRide"
        static let outdoorRide = "Ride"
    }

    struct PhotoUploadResult {
        let activityID: Int
        let success: Bool
    }

    /// A bike from the athlete profile (`gear_id` on activities). See `GET /athlete`.
    typealias AthleteBike = StravaAthleteBike

    private struct Session: Codable, OAuthSessionPayload {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Int
        var athleteID: Int?
        var athleteFirstName: String?
        var athleteLastName: String?
        var athleteUsername: String?
        var athleteProfileURL: String?

        var displayName: String {
            let fullName = [athleteFirstName, athleteLastName]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if !fullName.isEmpty {
                return fullName
            }
            if let athleteUsername, !athleteUsername.isEmpty {
                return athleteUsername
            }
            return "Strava Athlete"
        }
    }

    private struct Athlete: Codable {
        let id: Int?
        let username: String?
        let firstname: String?
        let lastname: String?
        let profile: String?
        let profile_medium: String?
    }

    struct SummaryActivity: Codable {
        let id: Int
        let name: String?
        let sportType: String?
        let startDate: Date?
        let elapsedTime: Int?
        let movingTime: Int?
        let distance: Double?
        let totalElevationGain: Double?
        let averageHeartrate: Double?
        let maxHeartrate: Double?
        let calories: Double?
        let kilojoules: Double?
        let averageSpeed: Double?
        let maxSpeed: Double?
        let averageCadence: Double?
        let averageWatts: Double?
        let averageTemp: Double?
        let sufferScore: Int?
        let achievementCount: Int?
        let prCount: Int?
        let totalPhotoCount: Int?
        let map: ActivityMap?

        struct ActivityMap: Codable {
            let id: String?
            let summaryPolyline: String?

            enum CodingKeys: String, CodingKey {
                case id
                case summaryPolyline = "summary_polyline"
            }
        }

        enum CodingKeys: String, CodingKey {
            case id, name
            case sportType = "sport_type"
            case startDate = "start_date"
            case elapsedTime = "elapsed_time"
            case movingTime = "moving_time"
            case distance
            case totalElevationGain = "total_elevation_gain"
            case averageHeartrate = "average_heartrate"
            case maxHeartrate = "max_heartrate"
            case calories
            case kilojoules
            case averageSpeed = "average_speed"
            case maxSpeed = "max_speed"
            case averageCadence = "average_cadence"
            case averageWatts = "average_watts"
            case averageTemp = "average_temp"
            case sufferScore = "suffer_score"
            case achievementCount = "achievement_count"
            case prCount = "pr_count"
            case totalPhotoCount = "total_photo_count"
            case map
        }

        private static let iso8601: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }()

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(Int.self, forKey: .id)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            sportType = try container.decodeIfPresent(String.self, forKey: .sportType)
            elapsedTime = try container.decodeIfPresent(Int.self, forKey: .elapsedTime)
            movingTime = try container.decodeIfPresent(Int.self, forKey: .movingTime)
            distance = try container.decodeIfPresent(Double.self, forKey: .distance)
            totalElevationGain = try container.decodeIfPresent(Double.self, forKey: .totalElevationGain)
            averageHeartrate = try container.decodeIfPresent(Double.self, forKey: .averageHeartrate)
            maxHeartrate = try container.decodeIfPresent(Double.self, forKey: .maxHeartrate)
            calories = try container.decodeIfPresent(Double.self, forKey: .calories)
            kilojoules = try container.decodeIfPresent(Double.self, forKey: .kilojoules)
            averageSpeed = try container.decodeIfPresent(Double.self, forKey: .averageSpeed)
            maxSpeed = try container.decodeIfPresent(Double.self, forKey: .maxSpeed)
            averageCadence = try container.decodeIfPresent(Double.self, forKey: .averageCadence)
            averageWatts = try container.decodeIfPresent(Double.self, forKey: .averageWatts)
            averageTemp = try container.decodeIfPresent(Double.self, forKey: .averageTemp)
            sufferScore = try container.decodeIfPresent(Int.self, forKey: .sufferScore)
            achievementCount = try container.decodeIfPresent(Int.self, forKey: .achievementCount)
            prCount = try container.decodeIfPresent(Int.self, forKey: .prCount)
            totalPhotoCount = try container.decodeIfPresent(Int.self, forKey: .totalPhotoCount)
            map = try container.decodeIfPresent(ActivityMap.self, forKey: .map)

            if let dateString = try container.decodeIfPresent(String.self, forKey: .startDate) {
                startDate = Self.iso8601.date(from: dateString)
                    ?? ISO8601DateFormatter().date(from: dateString)
            } else {
                startDate = nil
            }
        }
    }

    private struct TokenResponse: Codable {
        let token_type: String?
        let access_token: String
        let refresh_token: String
        let expires_at: Int
        let athlete: Athlete?
    }

    private struct UploadResponse: Decodable {
        let id: Int
        /// Present on newer responses; prefer when IDs exceed 32-bit.
        let id_str: String?
        let status: String?
        let error: String?
        let activity_id: Int?

        enum CodingKeys: String, CodingKey {
            case id, id_str, status, error, activity_id
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(Int.self, forKey: .id)
            id_str = try c.decodeIfPresent(String.self, forKey: .id_str)
            status = try c.decodeIfPresent(String.self, forKey: .status)
            error = try c.decodeIfPresent(String.self, forKey: .error)
            activity_id = Self.decodeActivityID(from: c)
        }

        /// Strava may return `activity_id` as int, string, or double in JSON.
        private static func decodeActivityID(from c: KeyedDecodingContainer<CodingKeys>) -> Int? {
            if let v = try? c.decode(Int.self, forKey: .activity_id) { return v }
            if let s = try? c.decode(String.self, forKey: .activity_id) {
                return Int(s.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            if let d = try? c.decode(Double.self, forKey: .activity_id) {
                return Int(d)
            }
            return nil
        }
    }

    enum StravaError: LocalizedError {
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
        case uploadFailed(String)
        case uploadTimedOut
        case invalidFileType
        case invalidResponse
        case activityFetchFailed(String)
        case photoUploadFailed(String)
        /// Strava returns 404 for `POST /activities/{id}/photos` for most OAuth apps — attaching photos is not a documented/supported public API flow.
        case photoUploadNotSupportedByAPI

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Strava linking requires Mangox cloud backup (Supabase) and the oauth-token-exchange edge function with Strava secrets deployed."
            case .invalidAuthURL:
                return "Unable to build Strava authorization URL."
            case .userCancelled:
                return "Strava authorization was canceled."
            case .authPresentationFailed:
                return "Unable to open Strava login. Keep the app in foreground and try again."
            case .missingAuthorizationCode:
                return "Strava did not return an authorization code."
            case .oauthReturnedError(let message):
                return "Strava authorization failed: \(message)"
            case .stateMismatch:
                return "Strava sign-in could not be verified. Try connecting again."
            case .networkUnavailable:
                return "You appear to be offline. Check your connection and try again."
            case .requestTimedOut(let context):
                return "\(context) timed out. Try again on a stronger connection."
            case .tokenExchangeFailed(let message):
                return "Strava token exchange failed: \(message)"
            case .uploadFailed(let message):
                return "Strava upload failed: \(message)"
            case .uploadTimedOut:
                return "Strava upload timed out while processing."
            case .invalidFileType:
                return "Strava supports FIT, GPX, and TCX files."
            case .invalidResponse:
                return "Invalid response from Strava."
            case .activityFetchFailed(let message):
                return "Strava activity import failed: \(message)"
            case .photoUploadFailed(let message):
                return "Strava photo upload failed: \(message)"
            case .photoUploadNotSupportedByAPI:
                return "Strava does not allow this app to attach activity photos automatically (API limitation)."
            }
        }
    }

    var isConnected = false
    var athleteDisplayName: String?
    var athleteProfileImageURL: URL?
    var isBusy = false
    var lastError: String?

    var isConfigured: Bool {
        !clientID.isEmpty && !redirectURIString.isEmpty && OAuthTokenExchangeClient.isAvailable
    }

    private static let authorizeURL = URL(string: "https://www.strava.com/oauth/authorize")!
    /// Strava API v3 base (migrated host per Strava 2027 deadline). OAuth stays on www.strava.com.
    static let apiBase = URL(string: "https://www.api-v3.strava.com")!
    private static let uploadURL = apiBase.appending(path: "uploads")
    private static let athleteURL = apiBase.appending(path: "athlete")
    static let athleteActivitiesURL = apiBase.appending(path: "athlete/activities")
    private static let keychainAccount = "strava.session.v1"
    private static let localSavedAtKey = "mangox.linked_oauth.strava.saved_at"

    weak var linkedOAuthBridge: LinkedOAuthSessionBridge?

    var linkedAccountLocalSavedAt: Date? {
        sessionStore.linkedAccountLocalSavedAt
    }

    var linkedOAuthProviderUserID: String? {
        session?.athleteID.map(String.init)
    }
    private static let requestTimeout: TimeInterval = 20
    private static let uploadTimeout: TimeInterval = 45
    private static let resourceTimeout: TimeInterval = 90
    private static let decoder: JSONDecoder = JSONDecoder()

    private let clientID: String
    private let clientSecret: String
    private let redirectURIString: String
    private let presentationContextProvider = WebAuthenticationPresentationContextProvider()
    let urlSession: URLSession

    private let sessionStore: OAuthSessionStore<Session>
    private var session: Session? {
        get { sessionStore.session }
        set { sessionStore.setSession(newValue) }
    }
    private var authSession: ASWebAuthenticationSession?
    private var pendingOAuthState: String?

    /// Latest seen 15-minute rate-limit usage. Updated lazily from `X-RateLimit-Usage` headers
    /// on Activities API responses; nil until any call has completed.
    /// Format: (usage, limit) for the rolling 15-min window.
    private(set) var rateLimitShortWindow: (usage: Int, limit: Int)?

    /// Module-internal setter so request helpers in extensions can record usage. Don't expose to UI.
    func updateRateLimitShortWindow(usage: Int, limit: Int) {
        rateLimitShortWindow = (usage: usage, limit: limit)
    }

    /// Heuristic guard for non-essential calls (streams, lap details). Returns true when we've
    /// seen recent traffic close to the 15-min cap, so callers can opt-out instead of getting 429s.
    var isRateLimitTight: Bool {
        guard let r = rateLimitShortWindow, r.limit > 0 else { return false }
        return Double(r.usage) / Double(r.limit) >= 0.80
    }

    init() {
        self.clientID = Self.infoValue(for: "STRAVA_CLIENT_ID")
        self.clientSecret = ""
        self.redirectURIString = Self.infoValue(for: "STRAVA_REDIRECT_URI", fallback: "mangox://localhost/strava-auth")
        self.sessionStore = OAuthSessionStore(
            keychainAccount: Self.keychainAccount,
            localSavedAtKey: Self.localSavedAtKey
        )
        self.urlSession = Self.makeSession()
        sessionStore.restore(decoder: Self.decoder, onRestored: { [weak self] restored in
            self?.applySession(restored)
        }, onFailure: { error in
            stravaLogger.error("Failed to restore Strava session: \(error.localizedDescription)")
        })
    }

    /// Builds a stable `external_id` for Strava (unique per Mangox workout). Helps dedupe and support.
    static func externalIDForWorkout(workoutID: UUID) -> String {
        "mangox-\(workoutID.uuidString.lowercased())"
    }

    func connect() async throws {
        guard isConfigured else { throw StravaError.notConfigured }

        stravaLogger.info("Strava connect started — clientID present: \(!self.clientID.isEmpty), redirectURI: \(self.redirectURIString)")

        isBusy = true
        defer { isBusy = false }

        do {
            let code = try await authorizeAndGetCode()
            stravaLogger.info("Authorization code received, exchanging for token…")
            let tokenResponse = try await requestToken(grantType: "authorization_code", code: code)
            let newSession = mapSession(tokenResponse, previous: nil)
            try persistSession(newSession)
            applySession(newSession)
            lastError = nil
            stravaLogger.info("Strava connected successfully as \(newSession.displayName)")
        } catch {
            stravaLogger.error("Strava connect failed: \(error.localizedDescription)")
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            throw error
        }
    }

    /// Uploads a JPEG image as a photo on an already-created Strava activity.
    ///
    /// **Note:** `POST /activities/{id}/photos` is not documented for third-party apps. Strava typically responds with **404**
    /// (`Record Not Found`) even when the activity exists and `PUT` succeeds — we map that to ``StravaError/photoUploadNotSupportedByAPI``
    /// instead of retrying (retries only wasted time and log noise).
    func uploadActivityPhoto(
        activityID: Int,
        image: PlatformImage
    ) async throws -> PhotoUploadResult {
        guard isConfigured else { throw StravaError.notConfigured }

        #if canImport(UIKit)
        guard let jpegData = image.jpegData(compressionQuality: 0.88) else {
            throw StravaError.photoUploadFailed("Could not encode image as JPEG.")
        }

        // Brief pause so Strava can finish processing a newly created activity before photo POST.
        try await Task.sleep(nanoseconds: 1_200_000_000)

        do {
            try await uploadActivityPhoto(activityID: activityID, jpegData: jpegData)
            return PhotoUploadResult(activityID: activityID, success: true)
        } catch StravaError.photoUploadNotSupportedByAPI {
            throw StravaError.photoUploadNotSupportedByAPI
        } catch StravaError.photoUploadFailed(let message) {
            // One retry for possible transient server errors (not 404 — handled inside `postActivityPhotoOnce`).
            let looksTransient = message.localizedCaseInsensitiveContains("500")
                || message.localizedCaseInsensitiveContains("502")
                || message.localizedCaseInsensitiveContains("503")
                || message.localizedCaseInsensitiveContains("429")
            if looksTransient {
                stravaLogger.warning("Strava photo upload retry after transient error")
                try await Task.sleep(nanoseconds: 2_000_000_000)
                return try await postActivityPhotoOnce(activityID: activityID, jpegData: jpegData)
            }
            throw StravaError.photoUploadFailed(message)
        }
        #else
        throw StravaError.photoUploadFailed("Photo upload requires iOS/iPadOS.")
        #endif
    }

    func uploadActivityPhoto(activityID: Int, jpegData: Data) async throws {
        guard isConfigured else { throw StravaError.notConfigured }

        try await Task.sleep(nanoseconds: 1_200_000_000)

        do {
            _ = try await postActivityPhotoOnce(activityID: activityID, jpegData: jpegData)
        } catch StravaError.photoUploadNotSupportedByAPI {
            throw StravaError.photoUploadNotSupportedByAPI
        } catch StravaError.photoUploadFailed(let message) {
            let looksTransient = message.localizedCaseInsensitiveContains("500")
                || message.localizedCaseInsensitiveContains("502")
                || message.localizedCaseInsensitiveContains("503")
                || message.localizedCaseInsensitiveContains("429")
            if looksTransient {
                stravaLogger.warning("Strava photo upload retry after transient error")
                try await Task.sleep(nanoseconds: 2_000_000_000)
                _ = try await postActivityPhotoOnce(activityID: activityID, jpegData: jpegData)
                return
            }
            throw StravaError.photoUploadFailed(message)
        }
    }

    #if canImport(UIKit)
    private func postActivityPhotoOnce(activityID: Int, jpegData: Data) async throws -> PhotoUploadResult {
        let token = try await validAccessToken()

        let boundary = "Boundary-\(UUID().uuidString)"
        let url = Self.apiBase.appending(path: "activities/\(activityID)/photos")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = Self.uploadTimeout

        var body = Data()
        let nl = "\r\n"
        body.append("--\(boundary)\(nl)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"photo[source]\"\(nl)\(nl)".data(using: .utf8)!)
        body.append("2\(nl)".data(using: .utf8)!)
        body.append("--\(boundary)\(nl)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"photo[file]\"; filename=\"summary.jpg\"\(nl)".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\(nl)\(nl)".data(using: .utf8)!)
        body.append(jpegData)
        body.append("\(nl)--\(boundary)--\(nl)".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await send(request, context: "Photo upload")
        guard let http = response as? HTTPURLResponse else {
            throw StravaError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            if http.statusCode == 404 {
                stravaLogger.info("Strava photo POST returned 404 — API does not expose photo upload for this app (activity \(activityID) exists for PUT).")
                throw StravaError.photoUploadNotSupportedByAPI
            }
            stravaLogger.warning("Photo upload failed with status \(http.statusCode): \(message)")
            throw StravaError.photoUploadFailed(message)
        }
        stravaLogger.info("Photo uploaded successfully to activity \(activityID)")
        return PhotoUploadResult(activityID: activityID, success: true)
    }
    #endif

    func disconnect() {
        session = nil
        athleteDisplayName = nil
        athleteProfileImageURL = nil
        isConnected = false
        lastError = nil
        sessionStore.deleteKeychain()
        sessionStore.clearLocalSavedAt()
        let bridge = linkedOAuthBridge
        Task { await bridge?.deleteCloudSession(provider: .strava) }
    }

    func exportSessionJSONForCloudBackup() -> Data? {
        sessionStore.exportJSON()
    }

    func restoreSessionFromCloudIfNeeded(sessionJSON: Data, remoteUpdatedAt: Date) {
        if isConnected, let localAt = linkedAccountLocalSavedAt, localAt >= remoteUpdatedAt {
            return
        }
        do {
            let restored = try JSONDecoder().decode(Session.self, from: sessionJSON)
            try persistSession(restored, notifyCloud: false)
            applySession(restored)
            sessionStore.markLinkedAccountSaved(at: remoteUpdatedAt)
            lastError = nil
            stravaLogger.info("Strava session restored from cloud backup")
            let now = Int(Date().timeIntervalSince1970)
            if restored.expiresAt - now <= 90 {
                stravaLogger.info("Strava cloud-restored token is expired/near-expiry — refreshing in background")
                Task { [weak self] in try? await self?.validAccessToken() }
            }
        } catch {
            stravaLogger.error("Strava cloud restore failed: \(error.localizedDescription)")
        }
    }

    /// Updates an existing Strava activity with custom metadata.
    ///
    /// Even when multipart upload includes `name`, `description`, and `sport_type`, Strava may still
    /// prefer file-derived titles until processing finishes. Calling `PUT` after `activity_id` exists
    /// is the reliable way to apply Mangox copy, sport type, and trainer flags.
    func updateActivity(
        activityID: Int,
        name: String? = nil,
        description: String? = nil,
        sportType: String? = nil,
        trainer: Bool? = nil,
        commute: Bool? = nil,
        gearID: String? = nil
    ) async throws {
        guard isConfigured else { throw StravaError.notConfigured }

        let token = try await validAccessToken()
        let url = Self.apiBase.appending(path: "activities/\(activityID)")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = Self.requestTimeout

        var body: [String: Any] = [:]
        if let name { body["name"] = StravaPostBuilder.clampActivityName(name) }
        if let description { body["description"] = description }
        if let sportType { body["sport_type"] = sportType }
        if let trainer { body["trainer"] = trainer }
        if let commute { body["commute"] = commute }
        if let gearID { body["gear_id"] = gearID }

        guard !body.isEmpty else { return }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await send(request, context: "Update activity")
        guard let http = response as? HTTPURLResponse else {
            throw StravaError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            stravaLogger.warning("Activity update failed with status \(http.statusCode): \(message)")
            throw StravaError.uploadFailed(message)
        }
        stravaLogger.info("Activity \(activityID) updated successfully")
    }

    /// Loads bikes from the authenticated athlete profile for `gear_id` on uploads.
    /// Requires `profile:read_all` scope (re-authorize if bikes fail to load).
    func fetchAthleteBikes() async throws -> [AthleteBike] {
        guard isConfigured else { throw StravaError.notConfigured }
        let token = try await validAccessToken()
        var request = URLRequest(url: Self.athleteURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = Self.requestTimeout

        let (data, response) = try await send(request, context: "Athlete profile")
        guard let http = response as? HTTPURLResponse else {
            throw StravaError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            stravaLogger.warning("Athlete fetch failed: \(message, privacy: .public)")
            throw StravaError.uploadFailed(message)
        }

        let decoded = try Self.decoder.decode(StravaDetailedAthleteDTO.self, from: data)
        return (decoded.bikes ?? []).map { bike in
            AthleteBike(id: bike.id, name: (bike.name?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "Bike")
        }
    }

    /// Checks whether a workout with the same start time (±5 min) and similar
    /// duration already exists in the athlete's recent Strava activities.
    ///
    /// Returns the existing activity ID if a match is found, nil otherwise.
    func checkForDuplicate(
        startDate: Date,
        elapsedSeconds: Int
    ) async -> Int? {
        guard let current = session else { return nil }
        let now = Int(Date().timeIntervalSince1970)
        if current.expiresAt - now <= 90 {
            _ = try? await validAccessToken()
        }
        guard let token = try? await validAccessToken() else { return nil }

        let before = Int(startDate.addingTimeInterval(300).timeIntervalSince1970)
        let after = Int(startDate.addingTimeInterval(-300).timeIntervalSince1970)

        var components = URLComponents(url: Self.athleteActivitiesURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "before", value: "\(before)"),
            URLQueryItem(name: "after", value: "\(after)"),
            URLQueryItem(name: "per_page", value: "30"),
        ]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = Self.requestTimeout

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }

            let activities = try JSONDecoder().decode([SummaryActivity].self, from: data)
            for activity in activities {
                if let activityStart = activity.startDate,
                   abs(activityStart.timeIntervalSince(startDate)) < 300,
                   let activityElapsed = activity.elapsedTime,
                   abs(activityElapsed - elapsedSeconds) < 120 {
                    return activity.id
                }
            }
        } catch {
            stravaLogger.warning("Duplicate check failed: \(error.localizedDescription)")
        }
        return nil
    }

    /// Uploads a FIT/GPX/TCX file. Pass a stable `externalID` (e.g. `externalIDForWorkout`) and Strava `sport_type`
    /// (`VirtualRide` vs `Ride`) so the initial multipart matches what you apply with `updateActivity`.
    func uploadWorkoutFile(
        fileURL: URL,
        name: String,
        description: String?,
        trainer: Bool,
        externalID: String,
        sportType: String
    ) async throws -> UploadResult {
        guard isConfigured else { throw StravaError.notConfigured }
        let dataType = fileURL.pathExtension.lowercased()
        guard ["fit", "gpx", "tcx"].contains(dataType) else {
            throw StravaError.invalidFileType
        }

        isBusy = true
        defer { isBusy = false }

        do {
            let token = try await validAccessToken()
            let upload = try await createUpload(
                accessToken: token,
                fileURL: fileURL,
                dataType: dataType,
                name: name,
                description: description,
                trainer: trainer,
                externalID: externalID,
                sportType: sportType
            )

            if let uploadError = upload.error, !uploadError.isEmpty {
                if let dupId = Self.parseDuplicateActivityID(from: uploadError) {
                    stravaLogger.info("Upload reported duplicate; using activity \(dupId)")
                    lastError = nil
                    return UploadResult(
                        uploadID: upload.id,
                        activityID: dupId,
                        status: upload.status ?? "Duplicate file — linked to existing activity",
                        isDuplicateRecovery: true
                    )
                }
                throw StravaError.uploadFailed(uploadError)
            }

            let result = try await pollUpload(accessToken: token, uploadID: upload.id, initialStatus: upload.status)
            lastError = nil
            return result
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            throw error
        }
    }

    private func authorizeAndGetCode() async throws -> String {
        guard let redirectURI = URL(string: redirectURIString) else {
            stravaLogger.error("Invalid redirect URI string: \(self.redirectURIString)")
            throw StravaError.invalidAuthURL
        }

        guard presentationContextProvider.hasPresentationAnchor else {
            throw StravaError.authPresentationFailed
        }

        let stateString = Self.makeOAuthState()
        pendingOAuthState = stateString

        var components = URLComponents(url: Self.authorizeURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope", value: "activity:write,activity:read,profile:read_all"),
            URLQueryItem(name: "state", value: stateString),
        ]

        guard let url = components?.url else {
            throw StravaError.invalidAuthURL
        }

        let callbackScheme = redirectURI.scheme
        stravaLogger.info("Starting ASWebAuthenticationSession — authURL: \(url.absoluteString), callbackScheme: \(callbackScheme ?? "nil")")

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { [self] callbackURL, error in
                // Hold strong self so authSession stays alive through the redirect round-trip.
                self.authSession = nil
                defer { self.pendingOAuthState = nil }

                if let error = error as? ASWebAuthenticationSessionError {
                    stravaLogger.error("ASWebAuthenticationSession error — code: \(error.code.rawValue), desc: \(error.localizedDescription)")
                    switch error.code {
                    case .canceledLogin:
                        continuation.resume(throwing: StravaError.userCancelled)
                    case .presentationContextInvalid, .presentationContextNotProvided:
                        continuation.resume(throwing: StravaError.authPresentationFailed)
                    default:
                        continuation.resume(throwing: error)
                    }
                    return
                }

                if let error {
                    stravaLogger.error("Auth session returned unexpected error: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                    return
                }

                guard let callbackURL else {
                    stravaLogger.error("Auth callback missing URL")
                    continuation.resume(throwing: StravaError.missingAuthorizationCode)
                    return
                }

                let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []

                if let errorCode = items.first(where: { $0.name == "error" })?.value {
                    let desc = items.first(where: { $0.name == "error_description" })?.value?
                        .replacingOccurrences(of: "+", with: " ")
                        .removingPercentEncoding ?? errorCode
                    continuation.resume(throwing: StravaError.oauthReturnedError(desc))
                    return
                }

                guard let returnedState = items.first(where: { $0.name == "state" })?.value,
                      returnedState == stateString
                else {
                    continuation.resume(throwing: StravaError.stateMismatch)
                    return
                }

                stravaLogger.info("Auth callback received and state verified.")

                guard let code = items.first(where: { $0.name == "code" })?.value,
                      !code.isEmpty else {
                    stravaLogger.error("Callback URL missing authorization code.")
                    continuation.resume(throwing: StravaError.missingAuthorizationCode)
                    return
                }

                stravaLogger.info("Authorization code extracted successfully.")
                continuation.resume(returning: code)
            }

            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = self.presentationContextProvider
            self.authSession = session

            let started = session.start()
            stravaLogger.info("ASWebAuthenticationSession.start() returned: \(started)")
            if !started {
                self.authSession = nil
                self.pendingOAuthState = nil
                continuation.resume(throwing: StravaError.authPresentationFailed)
            }
        }
    }

    private func requestToken(
        grantType: String,
        code: String? = nil,
        refreshToken: String? = nil
    ) async throws -> TokenResponse {
        let data: Data
        do {
            data = try await OAuthTokenExchangeClient.exchange(
                provider: .strava,
                grantType: grantType,
                code: code,
                refreshToken: refreshToken,
                redirectURI: code != nil ? redirectURIString : nil
            )
        } catch let error as OAuthTokenExchangeClient.ExchangeError {
            switch error {
            case .notConfigured:
                throw StravaError.notConfigured
            case .invalidResponse:
                throw StravaError.tokenExchangeFailed("Invalid response from OAuth proxy.")
            case .serverError(let message):
                throw StravaError.tokenExchangeFailed(message)
            }
        } catch {
            throw StravaError.tokenExchangeFailed(error.localizedDescription)
        }

        do {
            return try Self.decoder.decode(TokenResponse.self, from: data)
        } catch {
            throw StravaError.tokenExchangeFailed("Unable to decode token response.")
        }
    }

    func validAccessToken() async throws -> String {
        let bridge = linkedOAuthBridge
        return try await sessionStore.validAccessToken(
            noSessionError: StravaError.tokenExchangeFailed("No Strava session. Connect your account first."),
            sessionLostError: StravaError.tokenExchangeFailed("Session lost during refresh."),
            refresh: { [weak self] refreshToken in
                guard let self else {
                    throw StravaError.tokenExchangeFailed("Session lost during refresh.")
                }
                let refreshed = try await self.requestToken(
                    grantType: "refresh_token",
                    refreshToken: refreshToken
                )
                return self.mapSession(refreshed, previous: self.session)
            },
            onRefreshed: { [weak self] session in
                self?.applySession(session)
            },
            onCloudNotify: {
                Task { await bridge?.pushProviderToCloud(.strava) }
            }
        )
    }

    private func createUpload(
        accessToken: String,
        fileURL: URL,
        dataType: String,
        name: String,
        description: String?,
        trainer: Bool,
        externalID: String,
        sportType: String
    ) async throws -> UploadResponse {
        let fileData = try Data(contentsOf: fileURL)
        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: Self.uploadURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = Self.uploadTimeout
        request.httpBody = makeUploadBody(
            boundary: boundary,
            fileName: fileURL.lastPathComponent,
            fileData: fileData,
            dataType: dataType,
            name: name,
            description: description,
            trainer: trainer,
            externalID: externalID,
            sportType: sportType
        )

        stravaLogger.info("Strava upload POST: sport_type=\(sportType, privacy: .public) external_id=\(externalID, privacy: .public) file=\(fileURL.lastPathComponent, privacy: .public)")

        let (data, response) = try await send(request, context: "Workout upload")
        guard let http = response as? HTTPURLResponse else {
            throw StravaError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw StravaError.uploadFailed(message)
        }

        do {
            return try Self.decoder.decode(UploadResponse.self, from: data)
        } catch {
            throw StravaError.uploadFailed("Unable to decode Strava upload response.")
        }
    }

    private func pollUpload(
        accessToken: String,
        uploadID: Int,
        initialStatus: String?
    ) async throws -> UploadResult {
        var lastSeenStatus = initialStatus ?? "Upload queued"
        var sleepNanoseconds: UInt64 = 1_000_000_000 // start at 1s

        // Strava can take a long time to attach activity_id for large uploads; keep polling longer than 30s.
        for _ in 0..<60 {
            let upload = try await fetchUpload(accessToken: accessToken, uploadID: uploadID)

            if let activityID = upload.activity_id {
                return UploadResult(
                    uploadID: uploadID,
                    activityID: activityID,
                    status: upload.status ?? "Ready",
                    isDuplicateRecovery: false
                )
            }

            if let error = upload.error, !error.isEmpty {
                if let dupId = Self.parseDuplicateActivityID(from: error) {
                    stravaLogger.info("Poll reported duplicate; using activity \(dupId)")
                    return UploadResult(
                        uploadID: uploadID,
                        activityID: dupId,
                        status: upload.status ?? error,
                        isDuplicateRecovery: true
                    )
                }
                throw StravaError.uploadFailed(error)
            }

            if let status = upload.status, !status.isEmpty {
                lastSeenStatus = status
            }

            try await Task.sleep(nanoseconds: sleepNanoseconds)
            sleepNanoseconds = min(sleepNanoseconds * 2, 8_000_000_000) // cap at 8s
        }

        stravaLogger.warning("Upload poll timed out for id=\(uploadID)")
        if !lastSeenStatus.isEmpty {
            stravaLogger.warning("Last upload status before timeout: \(lastSeenStatus, privacy: .public)")
        }
        throw StravaError.uploadTimedOut
    }

    private func fetchUpload(accessToken: String, uploadID: Int) async throws -> UploadResponse {
        var request = URLRequest(url: Self.apiBase.appending(path: "uploads/\(uploadID)"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = Self.requestTimeout

        let (data, response) = try await send(request, context: "Upload status check")
        guard let http = response as? HTTPURLResponse else {
            throw StravaError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw StravaError.uploadFailed(message)
        }

        do {
            return try Self.decoder.decode(UploadResponse.self, from: data)
        } catch {
            throw StravaError.uploadFailed("Unable to decode Strava upload status.")
        }
    }

    private func makeUploadBody(
        boundary: String,
        fileName: String,
        fileData: Data,
        dataType: String,
        name: String,
        description: String?,
        trainer: Bool,
        externalID: String,
        sportType: String
    ) -> Data {
        var body = Data()

        func appendField(_ key: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        appendField("data_type", dataType)
        appendField("external_id", externalID)
        appendField("name", StravaPostBuilder.clampActivityName(name))
        if let description, !description.isEmpty {
            appendField("description", description)
        }
        appendField("trainer", trainer ? "1" : "0")
        // `sport_type` overrides file-derived type; preferred over deprecated `activity_type`.
        appendField("sport_type", sportType)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        return body
    }

    /// Strava’s English error strings sometimes include `duplicate of activity 123456789`.
    private static func parseDuplicateActivityID(from message: String) -> Int? {
        guard let regex = try? NSRegularExpression(
            pattern: #"duplicate of activity\s+(\d+)"#,
            options: .caseInsensitive
        ) else { return nil }
        let ns = message as NSString
        guard let match = regex.firstMatch(in: message, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1 else { return nil }
        let r = match.range(at: 1)
        guard r.location != NSNotFound else { return nil }
        return Int(ns.substring(with: r))
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
            "User-Agent": "Mangox/\(version) (CFNetwork; iOS)"
        ]
        return URLSession(configuration: configuration)
    }

    private func send(_ request: URLRequest, context: String) async throws -> (Data, URLResponse) {
        do {
            return try await urlSession.data(for: request)
        } catch let error as URLError {
            let mapped = mapNetworkError(error, context: context)
            stravaLogger.warning("\(context, privacy: .public) failed with URLError \(error.code.rawValue): \(error.localizedDescription, privacy: .public)")
            throw mapped
        } catch {
            stravaLogger.error("\(context, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func mapNetworkError(_ error: URLError, context: String) -> StravaError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed:
            return .networkUnavailable
        case .timedOut:
            return .requestTimedOut(context)
        default:
            return fallbackError(for: context, message: error.localizedDescription)
        }
    }

    private func fallbackError(for context: String, message: String) -> StravaError {
        if context == "Strava sign-in" {
            return .tokenExchangeFailed(message)
        }
        if context == "Photo upload" {
            return .photoUploadFailed(message)
        }
        return .uploadFailed(message)
    }

    private func mapSession(_ response: TokenResponse, previous: Session?) -> Session {
        Session(
            accessToken: response.access_token,
            refreshToken: response.refresh_token,
            expiresAt: response.expires_at,
            athleteID: response.athlete?.id ?? previous?.athleteID,
            athleteFirstName: response.athlete?.firstname ?? previous?.athleteFirstName,
            athleteLastName: response.athlete?.lastname ?? previous?.athleteLastName,
            athleteUsername: response.athlete?.username ?? previous?.athleteUsername,
            athleteProfileURL: response.athlete?.profile ?? response.athlete?.profile_medium ?? previous?.athleteProfileURL
        )
    }

    private func persistSession(_ session: Session, notifyCloud: Bool = true) throws {
        let bridge = linkedOAuthBridge
        try sessionStore.persist(session, notifyCloud: notifyCloud) {
            Task { await bridge?.pushProviderToCloud(.strava) }
        }
    }

    private func applySession(_ session: Session) {
        self.session = session
        self.isConnected = true
        self.athleteDisplayName = session.displayName
        if let urlString = session.athleteProfileURL,
           let url = URL(string: urlString),
           url.scheme == "https" {
            self.athleteProfileImageURL = url
        } else {
            self.athleteProfileImageURL = nil
        }
    }

    private static func infoValue(for key: String, fallback: String = "") -> String {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) else {
            return fallback
        }
        if let value = raw as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return fallback }
            // Unexpanded build setting placeholders should be treated as missing values.
            if trimmed.hasPrefix("$(") && trimmed.hasSuffix(")") {
                return fallback
            }
            return trimmed
        }
        if let value = raw as? NSNumber {
            return value.stringValue
        }
        return fallback
    }

    private static func makeOAuthState() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16).lowercased()
    }
}

private struct StravaGearDTO: Codable {
    let id: String
    let name: String?
}

private struct StravaDetailedAthleteDTO: Codable {
    let bikes: [StravaGearDTO]?
}

@MainActor
private final class WebAuthenticationPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    var hasPresentationAnchor: Bool {
        Self.currentPresentationAnchor() != nil
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let anchor = Self.currentPresentationAnchor() {
            return anchor
        }
        stravaLogger.error("No presentation anchor for Strava OAuth")
        #if canImport(AppKit)
        return ASPresentationAnchor()
        #else
        preconditionFailure("Missing presentation anchor for Strava OAuth")
        #endif
    }

    private static func currentPresentationAnchor() -> ASPresentationAnchor? {
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
            // iOS 26+: `UIWindow()` / `init(frame:)` are deprecated — use `init(windowScene:)`.
            return UIWindow(windowScene: scene)
        }

        // No `UIWindowScene` in `connectedScenes` yet (rare): legacy `UIApplicationDelegate.window`.
        // Avoid `UIApplication.shared.windows` (deprecated iOS 15) and `UIWindow()` without a scene (deprecated iOS 26).
        if let w = UIApplication.shared.delegate.flatMap({ $0.window }) {
            return w!
        }
        return nil
        #elseif canImport(AppKit)
        return NSApplication.shared.keyWindow
        #else
        return nil
        #endif
    }
}


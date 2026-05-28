import Foundation
import Supabase

/// Server-side WHOOP / Strava token exchange via Supabase Edge Function `oauth-token-exchange`.
/// Client secrets live in Supabase project secrets, not in the iOS binary.
enum OAuthTokenExchangeClient {
    enum Provider: String, Encodable, Sendable {
        case whoop
        case strava
    }

    enum ExchangeError: LocalizedError {
        case notConfigured
        case invalidResponse
        case serverError(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                "OAuth linking requires Mangox cloud backup (Supabase) to be configured in this build."
            case .invalidResponse:
                "Invalid response from OAuth proxy."
            case .serverError(let message):
                message
            }
        }
    }

    private struct ExchangeRequest: Encodable {
        let provider: String
        let grant_type: String
        let code: String?
        let refresh_token: String?
        let redirect_uri: String?
    }

    private struct ErrorPayload: Decodable {
        let error: String?
        let detail: String?
    }

    static var isAvailable: Bool { MangoxSupabase.isConfigured }

    private static let rawResponseData: @Sendable (Data, HTTPURLResponse) throws -> Data = { data, _ in
        data
    }

    static func exchange(
        provider: Provider,
        grantType: String,
        code: String? = nil,
        refreshToken: String? = nil,
        redirectURI: String? = nil
    ) async throws -> Data {
        guard let client = MangoxSupabase.shared else {
            throw ExchangeError.notConfigured
        }

        let body = ExchangeRequest(
            provider: provider.rawValue,
            grant_type: grantType,
            code: code,
            refresh_token: refreshToken,
            redirect_uri: redirectURI
        )

        do {
            // Must use the raw-bytes decode closure. `invoke` as `Data` would use
            // `Data`'s Decodable conformance (base64 in JSON), not the HTTP body.
            return try await client.functions.invoke(
                "oauth-token-exchange",
                options: FunctionInvokeOptions(body: body),
                decode: Self.rawResponseData
            )
        } catch let error as FunctionsError {
            throw ExchangeError.serverError(userFacingMessage(for: error))
        } catch {
            throw ExchangeError.serverError(error.localizedDescription)
        }
    }

    private static func userFacingMessage(for error: FunctionsError) -> String {
        switch error {
        case .httpError(let code, let data):
            if let payload = try? JSONDecoder().decode(ErrorPayload.self, from: data) {
                if payload.error == "missing_server_secret:WHOOP_CLIENT_SECRET"
                    || payload.error == "missing_server_secret:STRAVA_CLIENT_SECRET"
                    || payload.error?.hasPrefix("missing_server_secret:") == true
                {
                    return "OAuth proxy is not fully configured on the server. Deploy oauth-token-exchange secrets in Supabase."
                }
                if let detail = payload.detail, !detail.isEmpty {
                    return "OAuth exchange failed (HTTP \(code)): \(detail)"
                }
                if let err = payload.error, !err.isEmpty {
                    return "OAuth exchange failed (HTTP \(code)): \(err)"
                }
            }
            let raw = String(data: data, encoding: .utf8) ?? ""
            return raw.isEmpty ? "OAuth exchange failed (HTTP \(code))." : "OAuth exchange failed (HTTP \(code)): \(raw)"
        case .relayError:
            return "OAuth proxy relay error."
        @unknown default:
            return "OAuth exchange failed."
        }
    }
}

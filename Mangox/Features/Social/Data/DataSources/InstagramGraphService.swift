// Features/Social/Data/DataSources/InstagramGraphService.swift
import AuthenticationServices
import Foundation
import Supabase
import UIKit

/// Instagram Graph API client for Business/Creator accounts.
///
/// This is **scaffolding** for programmatic Story/Reel publishing and is gated behind Meta App Review.
/// Unlike ``InstagramStoryShare`` (the no-login pasteboard flow), the Graph API lets Mangox publish a
/// Story/Reel directly on behalf of a linked Instagram Business/Creator account —unlocked once:
///
/// 1. The Meta App (``FacebookAppID``) has App Review approval for:
///    `instagram_basic`, `instagram_content_publishing`, `pages_show_list`.
/// 2. The Supabase edge function `instagram-graph` is deployed with secrets:
///    `META_APP_ID`, `META_APP_SECRET`, `META_REDIRECT_URI` (see `supabase/functions/instagram-graph/`).
/// 3. The user connects an Instagram Business/Creator account via the OAuth flow below.
///
/// **Token custody:** the edge function returns the long-lived token to the caller. For production,
/// store it server-side (Supabase table keyed by user id) and expose publish as authenticated edge
/// endpoints so the token never resides on the device. The skeleton here performs publishing from the
/// device to keep the integration surface small; migrate to server-side custody before shipping.
///
/// **Story/Reel media constraint:** the Graph API requires a **publicly reachable** `image_url` /
/// `video_url` — it cannot accept raw bytes. Upload the rendered card to a public Supabase Storage
/// bucket first, then pass that URL to ``publishStory(imageURL:caption:)``.
enum InstagramGraphService {

    enum GraphError: LocalizedError {
        case notConfigured
        case noCodeInCallback
        case invalidResponse
        case noInstagramAccount
        case graphError(String)
        case serverError(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                "Instagram Graph publishing requires a Facebook App ID and Mangox cloud (Supabase) configured."
            case .noCodeInCallback:
                "Instagram linking was canceled or did not return an authorization code."
            case .invalidResponse:
                "Invalid response from the Instagram Graph proxy."
            case .noInstagramAccount:
                "No Instagram Business/Creator account is linked to this Facebook Page."
            case .graphError(let detail):
                "Instagram Graph API error: \(detail)"
            case .serverError(let message):
                message
            }
        }
    }

    /// Linked Instagram Business/Creator account resolved from the Graph API.
    struct InstagramAccount: Decodable, Sendable {
        let ig_user_id: String
        let username: String
        let page_id: String
    }

    /// Response from the `instagram-graph` edge function `exchange`/`resolve_account` actions.
    struct ExchangeResponse: Decodable, Sendable {
        let long_lived_token: String
        let expires_at: Int?
        let instagram: InstagramAccount?
    }

    // MARK: - Configuration

    /// Meta App ID read from `FacebookAppID` in Info.plist (same key used for Stories `source_application`).
    static var metaAppID: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "FacebookAppID") as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !(trimmed.hasPrefix("$(") && trimmed.hasSuffix(")")) else { return nil }
        return trimmed
    }

    /// Whether both the Meta App ID and Supabase are configured (prerequisite for the OAuth flow).
    static var isConfigured: Bool {
        metaAppID != nil && MangoxSupabase.isConfigured
    }

    /// OAuth scopes required for Story/Reel publishing (must be approved via Meta App Review).
    static let oauthScopes = "instagram_basic instagram_content_publishing pages_show_list"

    /// Default OAuth callback scheme (register `mangox` in `CFBundleURLSchemes`; the host is virtual).
    static let defaultRedirectURI = "mangox://localhost/instagram-auth"

    /// Raw-bytes decode closure (must be `@Sendable` for `FunctionInvokeOptions`).
    private static let rawResponseData: @Sendable (Data, HTTPURLResponse) throws -> Data = { data, _ in data }

    // MARK: - OAuth

    /// Builds the Meta OAuth authorization URL to open in `ASWebAuthenticationSession`.
    static func authorizationURL(redirectURI: String = defaultRedirectURI, state: String) -> URL? {
        guard let appID = metaAppID else { return nil }
        var components = URLComponents(string: "https://www.facebook.com/v21.0/dialog/oauth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: appID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: oauthScopes),
            URLQueryItem(name: "state", value: state),
        ]
        return components?.url
    }

    /// Extracts the `code` query parameter from an `ASWebAuthenticationSession` callback URL.
    static func code(fromCallback url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "code" })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Exchanges an OAuth `code` for a long-lived token + linked Instagram account via the
    /// `instagram-graph` Supabase edge function (keeps `META_APP_SECRET` server-side).
    static func exchangeCode(code: String, redirectURI: String = defaultRedirectURI) async throws -> ExchangeResponse {
        guard let client = MangoxSupabase.shared else {
            throw GraphError.notConfigured
        }
        let body: [String: String] = [
            "action": "exchange",
            "code": code,
            "redirect_uri": redirectURI,
        ]
        let data: Data
        do {
            data = try await client.functions.invoke(
                "instagram-graph",
                options: FunctionInvokeOptions(body: body),
                decode: Self.rawResponseData
            )
        } catch let error as FunctionsError {
            throw GraphError.serverError(message(for: error))
        } catch {
            throw GraphError.serverError(error.localizedDescription)
        }
        do {
            return try JSONDecoder().decode(ExchangeResponse.self, from: data)
        } catch {
            throw GraphError.invalidResponse
        }
    }

    // MARK: - Publishing

    /// Publishes a Story image to the linked Instagram account via the Graph API two-step flow:
    /// 1. Create a media container (`POST /{ig-user-id}/media` with `media_type=STORY`).
    /// 2. Publish it (`POST /{ig-user-id}/media_publish`).
    ///
    /// `imageURL` must be publicly reachable — the Graph API fetches the media itself; it cannot accept
    /// raw bytes. Upload the rendered card to a public Supabase Storage bucket first.
    static func publishStory(
        igUserID: String,
        longLivedToken: String,
        imageURL: URL,
        caption: String? = nil
    ) async throws -> String {
        let containerID = try await createStoryContainer(
            igUserID: igUserID,
            longLivedToken: longLivedToken,
            imageURL: imageURL,
            caption: caption
        )
        return try await publishContainer(
            igUserID: igUserID,
            longLivedToken: longLivedToken,
            containerID: containerID
        )
    }

    private static func createStoryContainer(
        igUserID: String,
        longLivedToken: String,
        imageURL: URL,
        caption: String?
    ) async throws -> String {
        var components = URLComponents(string: "https://graph.facebook.com/v21.0/\(igUserID)/media")
        var queryItems = [
            URLQueryItem(name: "media_type", value: "STORY"),
            URLQueryItem(name: "image_url", value: imageURL.absoluteString),
            URLQueryItem(name: "access_token", value: longLivedToken),
        ]
        if let caption, !caption.isEmpty {
            queryItems.append(URLQueryItem(name: "caption", value: caption))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else { throw GraphError.invalidResponse }

        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GraphError.graphError(String(data: data, encoding: .utf8) ?? "unknown")
        }
        guard let containerID = (try? JSONDecoder().decode(ContainerResponse.self, from: data))?.id else {
            throw GraphError.invalidResponse
        }
        return containerID
    }

    private static func publishContainer(
        igUserID: String,
        longLivedToken: String,
        containerID: String
    ) async throws -> String {
        var components = URLComponents(string: "https://graph.facebook.com/v21.0/\(igUserID)/media_publish")
        components?.queryItems = [
            URLQueryItem(name: "creation_id", value: containerID),
            URLQueryItem(name: "access_token", value: longLivedToken),
        ]
        guard let url = components?.url else { throw GraphError.invalidResponse }

        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GraphError.graphError(String(data: data, encoding: .utf8) ?? "unknown")
        }
        guard let mediaID = (try? JSONDecoder().decode(ContainerResponse.self, from: data))?.id else {
            throw GraphError.invalidResponse
        }
        return mediaID
    }

    private struct ContainerResponse: Decodable { let id: String }

    private static func message(for error: FunctionsError) -> String {
        switch error {
        case .httpError(let code, let data):
            let raw = String(data: data, encoding: .utf8) ?? ""
            if raw.contains("missing_server_secret:") {
                return "Instagram Graph proxy is not fully configured. Deploy instagram-graph secrets in Supabase."
            }
            return raw.isEmpty ? "Instagram Graph exchange failed (HTTP \(code))." : "Instagram Graph exchange failed (HTTP \(code)): \(raw)"
        case .relayError:
            return "Instagram Graph proxy relay error."
        @unknown default:
            return "Instagram Graph exchange failed."
        }
    }
}

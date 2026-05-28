import Foundation

extension URLRequest {
    /// Applies headers required for our Mangox cloud backend.
    ///
    /// - Always sets an honest `User-Agent` (unless already overridden) so the backend can identify the client.
    /// - Adds ngrok-specific headers only when the base URL indicates a tunnel (dev convenience).
    mutating func mangox_applyDevTunnelHeadersIfNeeded(mangoxBaseURL: String) {
        // Honest identification for all Mangox backend calls (chat, plan gen, workout gen, etc.)
        if value(forHTTPHeaderField: "User-Agent") == nil {
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
            setValue("Mangox/\(version) (iOS)", forHTTPHeaderField: "User-Agent")
        }

        let s = mangoxBaseURL.lowercased()
        guard s.contains("ngrok") else { return }

        setValue("true", forHTTPHeaderField: "ngrok-skip-browser-warning")
    }
}

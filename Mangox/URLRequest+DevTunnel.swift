import Foundation

extension URLRequest {
    /// Free ngrok (`*.ngrok-free.app` / `*.ngrok-free.dev`) may return an HTML interstitial or edge error page
    /// unless clients send a skip header and a non-empty User-Agent (URLSession defaults are sometimes treated as “browserless”).
    mutating func mangox_applyDevTunnelHeadersIfNeeded(mangoxBaseURL: String) {
        let s = mangoxBaseURL.lowercased()
        guard s.contains("ngrok") else { return }
        setValue("true", forHTTPHeaderField: "ngrok-skip-browser-warning")
        if value(forHTTPHeaderField: "User-Agent") == nil {
            setValue("MangoxCoach/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        }
    }
}

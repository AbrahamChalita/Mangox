import Foundation

/// Clearer errors when a dev tunnel (e.g. ngrok free) returns HTML instead of the JSON API.
enum CoachHTTPError: LocalizedError {
    case tunnelReturnedHTML(status: Int)

    var errorDescription: String? {
        switch self {
        case .tunnelReturnedHTML(let status):
            return """
            Tunnel returned a web page instead of the API (HTTP \(status)). On your Mac keep `npm run dev` running, start ngrok with `ngrok http 127.0.0.1:3000`, and set Coach Base URL to `https://…ngrok-free.dev` only (no `/api`). \
            If this persists, open ngrok’s inspector at http://127.0.0.1:4040 for the exact edge error.
            """
        }
    }
}

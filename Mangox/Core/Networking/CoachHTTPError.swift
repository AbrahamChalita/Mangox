import Foundation

/// Clearer errors when a dev tunnel (e.g. ngrok free) returns HTML instead of the JSON API.
enum CoachHTTPError: LocalizedError {
    case tunnelReturnedHTML(status: Int)

    var errorDescription: String? {
        switch self {
        case .tunnelReturnedHTML(let status):
            return """
            Tunnel returned a web page instead of the API (HTTP \(status)). Use the **host only** for Mangox Cloud base URL (e.g. `https://….ngrok-free.dev`) — **no** `/api` suffix (that becomes `/api/api/chat` and 404). \
            Keep `npm run dev` running on the Mac, forward `ngrok http 127.0.0.1:3000`, and check http://127.0.0.1:4040 if the tunnel still fails.
            """
        }
    }
}

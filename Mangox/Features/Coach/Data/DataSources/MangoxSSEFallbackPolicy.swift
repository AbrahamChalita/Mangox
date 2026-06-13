import Foundation

/// Guards against duplicate LLM runs when an SSE stream fails mid-flight.
enum MangoxSSEFallbackPolicy {
    /// `true` only when the stream never delivered model output (safe to retry via blocking POST).
    nonisolated static func shouldFallbackToNonStreaming(receivedStreamPayload: Bool) -> Bool {
        !receivedStreamPayload
    }
}

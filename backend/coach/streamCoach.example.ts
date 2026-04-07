/**
 * Example: wire `parseCoachModelJson` + SSE `final` event into your existing `/api/chat/stream` handler.
 *
 * Pseudocode flow:
 * 1. Call the LLM with stream: true.
 * 2. For each text delta, append to a buffer and `yield` SSE `{ type: "delta", delta: chunk }` if you mirror raw tokens to the client.
 * 3. When the stream ends, run `parseCoachModelJson(buffer)`.
 * 4. If `ok`, emit `{ type: "final", message }` where `message` matches iOS `ChatAPIResponse`.
 * 5. If `!ok`, log `[coach/stream] stream_json_parse_failed` with head/tail, then emit
 *    `{ type: "final", message: clarificationFallbackFromRaw(buffer, result.reason) }`
 *    so follow-ups still appear (aligns with iOS recovery).
 *
 * Gemma-specific tips:
 * - Prefer `max_tokens` high enough to finish the JSON object, OR switch this route to non-streaming for Gemma only.
 * - Add `response_format: { type: "json_object" }` on OpenAI-compatible APIs that support it.
 * - On Google AI Gemini API, use `generationConfig.responseMimeType = "application/json"` and a response schema when available.
 */

import type { CoachChatMessage } from "./types.js";
import {
  clarificationFallbackFromRaw,
  parseCoachModelJson,
  type ParseCoachReplyResult,
} from "./parseCoachReply.js";

export type SseLine = string;

export function formatSse(obj: Record<string, unknown>): SseLine {
  return `data: ${JSON.stringify(obj)}\n\n`;
}

/**
 * @param accumulatedAssistantText - full model output for this turn (JSON or mixed).
 * @param log - optional logger (e.g. console or pino)
 */
export function finalizeCoachStreamMessage(
  accumulatedAssistantText: string,
  log?: { info: (o: object) => void; warn: (o: object) => void }
): { message: CoachChatMessage; parse: ParseCoachReplyResult } {
  const parsed = parseCoachModelJson(accumulatedAssistantText);

  if (parsed.ok) {
    return { message: parsed.message, parse: parsed };
  }

  log?.warn({
    event: "coach_stream_json_parse_failed",
    reason: parsed.reason,
    rawLen: parsed.rawLen,
    head: parsed.head,
    tail: parsed.tail,
  });

  const message = clarificationFallbackFromRaw(accumulatedAssistantText);
  return {
    message,
    parse: parsed,
  };
}

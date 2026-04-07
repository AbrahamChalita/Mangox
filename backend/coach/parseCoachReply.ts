import { jsonrepair } from "jsonrepair";
import {
  coachChatMessageSchema,
  normalizeCoachKeys,
  type CoachChatMessageParsed,
} from "./schema.js";
import type { CoachChatMessage, SuggestedAction } from "./types.js";
import { extractFirstBalancedJsonObject, stripMarkdownJsonFence } from "./extractJson.js";

export type ParseCoachReplyResult =
  | { ok: true; message: CoachChatMessage }
  | { ok: false; reason: string; rawLen: number; head: string; tail: string };

function toWireMessage(parsed: CoachChatMessageParsed): CoachChatMessage {
  return {
    category: parsed.category,
    content: parsed.content,
    suggestedActions: parsed.suggestedActions,
    followUpQuestion: parsed.followUpQuestion ?? null,
    followUpBlocks: parsed.followUpBlocks.map((b) => ({
      question: b.question,
      suggestedActions: b.suggestedActions.slice(0, 6),
    })),
    confidence: parsed.confidence,
    thinkingSteps: parsed.thinkingSteps,
    tags: parsed.tags,
    references: parsed.references,
    toolCalls: parsed.toolCalls,
    used_web_search: parsed.used_web_search,
  };
}

/** Remove obvious hallucinated key spam before JSON repair (Gemma). */
function scrubSuspiciousSuggestedActionKeys(jsonText: string): string {
  let t = jsonText.replace(/^\s*"suggested_action_\d+"\s*:\s*"[^"]*"\s*,?\s*$/gm, "");
  t = t.replace(/"suggested_action_\d+"\s*:\s*"[^"]*"\s*,?/g, "");
  return t;
}

function firstQuestionFromProse(content: string): string | null {
  const trimmed = content.trim();
  const q = trimmed.indexOf("?");
  if (q < 0) return null;
  const head = trimmed.slice(0, q);
  let start = 0;
  const lb = head.lastIndexOf("\n");
  const dot = head.lastIndexOf(".");
  start = Math.max(lb >= 0 ? lb + 1 : 0, dot >= 0 ? dot + 1 : 0);
  const sentence = trimmed.slice(start, q + 1).trim();
  if (sentence.length >= 8 && sentence.length <= 500) return sentence;
  return null;
}

function planIntakeClarificationChips(): SuggestedAction[] {
  return [
    { label: "Target event & date", type: "ask_followup" },
    { label: "Distance & elevation", type: "ask_followup" },
    { label: "FTP & hours per week", type: "ask_followup" },
    { label: "I'm new — guide me step by step", type: "ask_followup" },
  ];
}

/**
 * When JSON is hopeless, still return a valid coach message so the app shows follow-ups.
 */
export function clarificationFallbackFromRaw(rawAssistantText: string): CoachChatMessage {
  const stripped = stripMarkdownJsonFence(rawAssistantText);
  const prose =
    stripped.length > 0 && !stripped.trimStart().startsWith("{")
      ? stripped
      : "I need a bit more information to help. What’s your main goal or event?";

  let follow = firstQuestionFromProse(prose);
  if (
    follow &&
    (prose.toLowerCase().startsWith(follow.toLowerCase()) ||
      (prose.toLowerCase().includes(follow.toLowerCase()) && follow.length >= 48))
  ) {
    follow = null;
  }
  return {
    category: "clarification",
    content: prose.slice(0, 12000),
    suggestedActions: planIntakeClarificationChips(),
    followUpQuestion: follow,
    followUpBlocks: [],
    confidence: 0.85,
    thinkingSteps: [],
    tags: [],
    references: [],
    toolCalls: [],
    used_web_search: false,
  };
}

/**
 * Parse model output (full accumulated string) into `CoachChatMessage`.
 * Order: balanced extract → jsonrepair → Zod (+ key normalization).
 */
export function parseCoachModelJson(rawAssistantText: string): ParseCoachReplyResult {
  const rawLen = rawAssistantText.length;
  const head = rawAssistantText.slice(0, 180);
  const tail = rawAssistantText.slice(Math.max(0, rawLen - 180));

  let candidate = stripMarkdownJsonFence(rawAssistantText);
  let balanced = extractFirstBalancedJsonObject(candidate);
  if (!balanced) {
    candidate = scrubSuspiciousSuggestedActionKeys(candidate);
    balanced = extractFirstBalancedJsonObject(candidate);
  }

  if (!balanced) {
    try {
      const repaired = jsonrepair(candidate.trim());
      balanced = extractFirstBalancedJsonObject(repaired) ?? repaired;
    } catch {
      return {
        ok: false,
        reason: "no_balanced_object",
        rawLen,
        head,
        tail,
      };
    }
  }

  let obj: unknown;
  try {
    obj = JSON.parse(balanced);
  } catch (e) {
    try {
      obj = JSON.parse(jsonrepair(balanced));
    } catch {
      return {
        ok: false,
        reason: `json_parse_failed: ${e instanceof Error ? e.message : String(e)}`,
        rawLen,
        head,
        tail,
      };
    }
  }

  if (!obj || typeof obj !== "object") {
    return { ok: false, reason: "not_object", rawLen, head, tail };
  }

  const normalized = normalizeCoachKeys(obj as Record<string, unknown>);
  const parsed = coachChatMessageSchema.safeParse(normalized);
  if (!parsed.success) {
    return {
      ok: false,
      reason: `schema: ${parsed.error.message}`,
      rawLen,
      head,
      tail,
    };
  }

  return { ok: true, message: toWireMessage(parsed.data) };
}

export type { CoachChatMessage, CoachFollowUpBlock, SuggestedAction } from "./types.js";
export { COACH_JSON_OUTPUT_RULES } from "./systemPrompt.js";
export {
  extractFirstBalancedJsonObject,
  stripMarkdownJsonFence,
} from "./extractJson.js";
export {
  parseCoachModelJson,
  clarificationFallbackFromRaw,
  type ParseCoachReplyResult,
} from "./parseCoachReply.js";
export { coachChatMessageSchema, normalizeCoachKeys } from "./schema.js";
export {
  finalizeCoachStreamMessage,
  formatSse,
  type SseLine,
} from "./streamCoach.example.js";

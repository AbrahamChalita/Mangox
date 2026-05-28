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
  MANGOX_FITNESS_TOOL_NAMES,
  mangoxCriticalPowerArgsSchema,
  mangoxDecouplingTrendArgsSchema,
  mangoxFitnessToolCallSchema,
  mangoxOnDeviceToolFilterSchema,
  mangoxPlanForwardSimArgsSchema,
  mangoxPMCProjectionArgsSchema,
  mangoxPowerCurveSummaryArgsSchema,
  parseMangoxFitnessToolCall,
  parseMangoxFitnessToolCalls,
  type MangoxDecouplingTrendArgs,
  type MangoxCriticalPowerArgs,
  type MangoxPlanForwardSimArgs,
  type MangoxFitnessToolCall,
  type MangoxPMCProjectionArgs,
  type MangoxPowerCurveSummaryArgs,
} from "./fitnessTools.js";
export {
  criticWarningsFromVerdict,
  planCriticIssueSchema,
  planCriticPlanSchema,
  planCriticVerdictSchema,
  validatePlanForCritic,
  type PlanCriticIssue,
  type PlanCriticPlanInput,
  type PlanCriticVerdict,
} from "./planCritic.js";
export {
  criticWarningsFromWorkoutVerdict,
  validateWorkoutForCritic,
  workoutCriticIssueSchema,
  workoutCriticVerdictSchema,
  type WorkoutCriticInputs,
  type WorkoutCriticIssue,
  type WorkoutCriticVerdict,
} from "./workoutCritic.js";
export {
  finalizeCoachStreamMessage,
  formatSse,
  type SseLine,
} from "./streamCoach.example.js";

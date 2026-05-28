import { z } from "zod";

/**
 * Cloud coach fitness tool contracts — keep in sync with iOS on-device tools in
 * `MangoxOnDeviceCoachTools.swift` and precision math in `Features/Fitness/Domain/UseCases/TrainingMath/`.
 *
 * The deployed worker executes these tools server-side when the model requests them.
 * Shapes mirror what the iOS narrow path already exposes on-device.
 */

export const mangoxPMCProjectionArgsSchema = z.object({
  currentCTL: z.number().min(0),
  currentATL: z.number().min(0),
  weeklyTSS: z.number().min(0),
  weeks: z.number().int().min(1).max(12),
});

export const mangoxOnDeviceToolFilterSchema = z.object({
  filterSubstring: z.string().max(200).default(""),
});

export const mangoxDecouplingTrendArgsSchema = mangoxOnDeviceToolFilterSchema;

export const mangoxPowerCurveSummaryArgsSchema = z.object({
  filterSubstring: z.string().max(200).default(""),
  /** Optional duration label filter, e.g. "5m", "1h". */
  durationLabel: z.string().max(16).optional(),
});

export const mangoxCriticalPowerArgsSchema = mangoxOnDeviceToolFilterSchema;

export const mangoxPlanForwardSimArgsSchema = z.object({
  currentCTL: z.number().min(0),
  currentATL: z.number().min(0),
  horizonDays: z.number().int().min(1).max(42),
});

export const mangoxFitnessToolCallSchema = z.discriminatedUnion("name", [
  z.object({
    name: z.literal("mangox_pmc_projection"),
    arguments: mangoxPMCProjectionArgsSchema,
  }),
  z.object({
    name: z.literal("mangox_decoupling_trend"),
    arguments: mangoxDecouplingTrendArgsSchema,
  }),
  z.object({
    name: z.literal("mangox_power_curve_summary"),
    arguments: mangoxPowerCurveSummaryArgsSchema,
  }),
  z.object({
    name: z.literal("mangox_critical_power"),
    arguments: mangoxCriticalPowerArgsSchema,
  }),
  z.object({
    name: z.literal("mangox_plan_forward_sim"),
    arguments: mangoxPlanForwardSimArgsSchema,
  }),
]);

export type MangoxPMCProjectionArgs = z.infer<typeof mangoxPMCProjectionArgsSchema>;
export type MangoxDecouplingTrendArgs = z.infer<typeof mangoxDecouplingTrendArgsSchema>;
export type MangoxPowerCurveSummaryArgs = z.infer<typeof mangoxPowerCurveSummaryArgsSchema>;
export type MangoxCriticalPowerArgs = z.infer<typeof mangoxCriticalPowerArgsSchema>;
export type MangoxPlanForwardSimArgs = z.infer<typeof mangoxPlanForwardSimArgsSchema>;
export type MangoxFitnessToolCall = z.infer<typeof mangoxFitnessToolCallSchema>;

/** Parse a single fitness tool call from model output (throws ZodError on mismatch). */
export function parseMangoxFitnessToolCall(raw: unknown): MangoxFitnessToolCall {
  return mangoxFitnessToolCallSchema.parse(raw);
}

/** Lenient parse for mixed tool arrays in chat replies. */
export function parseMangoxFitnessToolCalls(raw: unknown): MangoxFitnessToolCall[] {
  if (!Array.isArray(raw)) return [];
  const parsed: MangoxFitnessToolCall[] = [];
  for (const item of raw) {
    const result = mangoxFitnessToolCallSchema.safeParse(item);
    if (result.success) parsed.push(result.data);
  }
  return parsed;
}

export const MANGOX_FITNESS_TOOL_NAMES = [
  "mangox_pmc_projection",
  "mangox_decoupling_trend",
  "mangox_power_curve_summary",
  "mangox_critical_power",
  "mangox_plan_forward_sim",
] as const;

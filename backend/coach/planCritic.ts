import { z } from "zod";

/**
 * Server-side plan critic — mirrors iOS `PlanCritic.swift` for worker validation after LLM plan generation.
 * Operates on decoded plan JSON before returning to the client.
 */

export const planCriticIssueSchema = z.object({
  code: z.string().max(64),
  message: z.string().max(500),
  severity: z.enum(["warning", "error"]),
});

export const planCriticVerdictSchema = z.object({
  issues: z.array(planCriticIssueSchema).max(32),
});

export type PlanCriticIssue = z.infer<typeof planCriticIssueSchema>;
export type PlanCriticVerdict = z.infer<typeof planCriticVerdictSchema>;

/** Minimal plan shape for critic checks (matches iOS TrainingPlan JSON). */
export const planCriticPlanSchema = z.object({
  weeks: z.array(
    z.object({
      weekNumber: z.number().int(),
      tssTarget: z
        .object({ lowerBound: z.number(), upperBound: z.number() })
        .optional(),
      tssTargetLower: z.number().optional(),
      tssTargetUpper: z.number().optional(),
      days: z.array(
        z.object({
          id: z.string(),
          weekNumber: z.number().int(),
          dayOfWeek: z.number().int().min(1).max(7),
          dayType: z.string(),
          title: z.string(),
          isKeyWorkout: z.boolean().optional(),
          durationMinutes: z.number().optional(),
          zone: z.string().optional(),
          intervals: z.array(z.unknown()).optional(),
        })
      ),
    })
  ),
});

export type PlanCriticPlanInput = z.infer<typeof planCriticPlanSchema>;

const MAX_WEEK_TO_WEEK_INCREASE = 0.15;
const MIN_REST_DAYS_PER_WEEK = 1;

const WORKOUT_TYPES = new Set([
  "workout",
  "ftpTest",
  "optionalWorkout",
  "commute",
]);

/** Lightweight week TSS estimate for critic (server may use richer math later). */
function estimateDayTSS(day: PlanCriticPlanInput["weeks"][number]["days"][number], ftp: number): number {
  if (!WORKOUT_TYPES.has(day.dayType)) return 0;
  const minutes = day.durationMinutes ?? 60;
  return (minutes * 60 * 0.65 * 0.65) / 36; // ~Z2 IF midpoint, same formula family as iOS
}

function weekTSS(week: PlanCriticPlanInput["weeks"][number], ftp: number): number {
  return week.days.reduce((sum, day) => sum + estimateDayTSS(day, ftp), 0);
}

/** Run critic rules aligned with iOS PlanCritic. */
export function validatePlanForCritic(plan: PlanCriticPlanInput, ftp = 250): PlanCriticVerdict {
  const issues: PlanCriticIssue[] = [];
  const weekly = plan.weeks.map((w) => weekTSS(w, ftp));

  for (let i = 1; i < weekly.length; i++) {
    const prev = weekly[i - 1]!;
    const curr = weekly[i]!;
    if (prev > 0 && (curr - prev) / prev > MAX_WEEK_TO_WEEK_INCREASE) {
      issues.push({
        code: "week_tss_spike",
        message: `Week ${i + 1} planned TSS jumps more than ${MAX_WEEK_TO_WEEK_INCREASE * 100}% vs week ${i}.`,
        severity: "warning",
      });
    }
  }

  for (const week of plan.weeks) {
    const workoutDays = week.days.filter((d) => WORKOUT_TYPES.has(d.dayType)).length;
    const restDays = Math.max(0, 7 - workoutDays);
    if (restDays < MIN_REST_DAYS_PER_WEEK) {
      issues.push({
        code: "insufficient_rest",
        message: `Week ${week.weekNumber} has fewer than ${MIN_REST_DAYS_PER_WEEK} rest/easy day(s).`,
        severity: "warning",
      });
    }

    const keyDays = week.days
      .filter((d) => d.isKeyWorkout && d.dayType !== "optionalWorkout" && d.dayType !== "rest")
      .sort((a, b) => a.dayOfWeek - b.dayOfWeek);

    for (let j = 1; j < keyDays.length; j++) {
      const prev = keyDays[j - 1]!;
      const curr = keyDays[j]!;
      if (curr.dayOfWeek - prev.dayOfWeek === 1) {
        issues.push({
          code: "back_to_back_key",
          message: `Week ${week.weekNumber}: key sessions "${prev.title}" and "${curr.title}" are on consecutive days.`,
          severity: "warning",
        });
      }
    }
  }

  return { issues };
}

export function criticWarningsFromVerdict(verdict: PlanCriticVerdict): string[] {
  return verdict.issues.filter((i) => i.severity === "warning").map((i) => i.message);
}

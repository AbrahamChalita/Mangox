import { z } from "zod";

/**
 * Server-side workout critic — mirrors iOS `WorkoutCritic.swift` for worker validation
 * after LLM workout generation.
 */

export const workoutCriticIssueSchema = z.object({
  code: z.string().max(64),
  message: z.string().max(500),
  severity: z.enum(["warning", "error"]),
});

export const workoutCriticVerdictSchema = z.object({
  issues: z.array(workoutCriticIssueSchema).max(32),
});

export type WorkoutCriticIssue = z.infer<typeof workoutCriticIssueSchema>;
export type WorkoutCriticVerdict = z.infer<typeof workoutCriticVerdictSchema>;

export type WorkoutCriticInputs = {
  goal: string;
  duration_minutes: number;
  current_ftp?: number;
};

export type WorkoutCriticDay = {
  durationMinutes?: number;
  zone?: string;
  intervals?: Array<{
    durationSeconds?: number;
    zone?: string;
    repeats?: number;
    recoverySeconds?: number;
    recoveryZone?: string;
  }>;
};

const ZONE_IF: Record<string, number> = {
  Z1: 0.5,
  Z2: 0.65,
  Z3: 0.8,
  Z4: 0.95,
  Z5: 1.12,
  Z1Z2: 0.6,
  Z2Z3: 0.72,
  Z3Z4: 0.88,
  Z3Z5: 0.95,
  Z4Z5: 1.02,
  MIXED: 0.85,
  ALL: 0.85,
  REST: 0.4,
  NONE: 0.4,
};

function zoneIF(raw: string | undefined, fallback = 0.65): number {
  if (!raw) return fallback;
  return ZONE_IF[raw.trim().toUpperCase()] ?? fallback;
}

function tssForSeconds(seconds: number, intensityFactor: number): number {
  if (seconds <= 0) return 0;
  return (seconds * intensityFactor * intensityFactor) / 36;
}

function intervalTSS(seg: NonNullable<WorkoutCriticDay["intervals"]>[number]): number {
  const repeats = Math.max(1, seg.repeats ?? 1);
  const workSeconds = Math.max(0, seg.durationSeconds ?? 0) * repeats;
  const workTSS = tssForSeconds(workSeconds, zoneIF(seg.zone));
  const recoverySeconds = Math.max(0, seg.recoverySeconds ?? 0);
  if (repeats <= 1 || recoverySeconds <= 0) return workTSS;
  const recTSS = tssForSeconds(recoverySeconds * (repeats - 1), zoneIF(seg.recoveryZone, 0.4));
  return workTSS + recTSS;
}

function estimateDayTSS(day: WorkoutCriticDay, ftp: number): number {
  const safeFTP = Math.max(1, ftp);
  void safeFTP;
  const intervals = day.intervals ?? [];
  if (intervals.length > 0) {
    return intervals.reduce((sum, seg) => sum + intervalTSS(seg), 0);
  }
  const minutes = day.durationMinutes ?? 0;
  return tssForSeconds(minutes * 60, zoneIF(day.zone));
}

function plannedSeconds(day: WorkoutCriticDay): number {
  const intervals = day.intervals ?? [];
  if (intervals.length === 0) {
    return Math.max(0, (day.durationMinutes ?? 0) * 60);
  }
  return intervals.reduce((partial, seg) => {
    const repeats = Math.max(1, seg.repeats ?? 1);
    const work = Math.max(0, seg.durationSeconds ?? 0) * repeats;
    const recovery = Math.max(0, seg.recoverySeconds ?? 0) * Math.max(0, repeats - 1);
    return partial + work + recovery;
  }, 0);
}

/** Run critic rules aligned with iOS WorkoutCritic. */
export function validateWorkoutForCritic(
  workout: { day: WorkoutCriticDay },
  inputs: WorkoutCriticInputs,
  ftp = 250,
): WorkoutCriticVerdict {
  const issues: WorkoutCriticIssue[] = [];
  const safeFTP = Math.max(1, inputs.current_ftp ?? ftp);
  const day = workout.day;

  const totalSeconds = plannedSeconds(day);
  const fallbackSeconds = Math.max(0, (day.durationMinutes ?? 0) * 60);
  const effectiveSeconds = totalSeconds > 0 ? totalSeconds : fallbackSeconds;
  const requestedSeconds = inputs.duration_minutes * 60;

  if (effectiveSeconds > 0) {
    const ratio = effectiveSeconds / Math.max(1, requestedSeconds);
    if (ratio < 0.75 || ratio > 1.35) {
      issues.push({
        code: "duration_mismatch",
        message: `Workout structure is ~${Math.round(effectiveSeconds / 60)} min but you asked for ${inputs.duration_minutes} min.`,
        severity: "warning",
      });
    }
  }

  const estimatedTSS = estimateDayTSS(day, safeFTP);
  const tssPerHour = estimatedTSS / Math.max(1, effectiveSeconds / 3600);
  if (tssPerHour > 120) {
    issues.push({
      code: "high_tss_density",
      message: `Estimated TSS ${Math.round(estimatedTSS)} looks very dense for this duration.`,
      severity: "warning",
    });
  }

  if ((day.intervals?.length ?? 0) === 0 && (day.durationMinutes ?? 0) <= 0) {
    issues.push({
      code: "empty_structure",
      message: "Workout has no intervals or duration.",
      severity: "error",
    });
  }

  const goal = inputs.goal.toLowerCase();
  if (goal.includes("recovery") || goal.includes("easy")) {
    if (estimatedTSS > 45) {
      issues.push({
        code: "recovery_too_hard",
        message: "Recovery-focused request but estimated TSS is high.",
        severity: "warning",
      });
    }
  }

  return { issues };
}

export function criticWarningsFromWorkoutVerdict(verdict: WorkoutCriticVerdict): string[] {
  return verdict.issues.filter((i) => i.severity === "warning").map((i) => i.message);
}

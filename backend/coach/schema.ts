import { z } from "zod";

/** Keep in sync with iOS `SuggestedAction` / `CoachFollowUpBlock`. */
const suggestedActionSchema = z.object({
  label: z.string(),
  type: z.string(),
});

const followUpBlockSchema = z.preprocess((val) => {
  if (val && typeof val === "object" && !Array.isArray(val)) {
    const o = val as Record<string, unknown>;
    if (o.suggested_actions && !o.suggestedActions) {
      return { ...o, suggestedActions: o.suggested_actions };
    }
  }
  return val;
}, z.object({
  question: z.string(),
  suggestedActions: z.array(suggestedActionSchema).max(6).default([]),
}));

/**
 * Hard limits reduce Gemma-style runaway keys (`suggested_action_126`, …) and oversize strings.
 */
export const coachChatMessageSchema = z.object({
  category: z.string().max(64).default("training_advice"),
  content: z.string().max(12000),
  suggestedActions: z.array(suggestedActionSchema).max(6).default([]),
  followUpQuestion: z.string().max(500).nullable().optional(),
  followUpBlocks: z.array(followUpBlockSchema).max(3).default([]),
  confidence: z.number().min(0).max(1).default(1),
  thinkingSteps: z.array(z.string().max(2000)).max(8).default([]),
  tags: z.array(z.string().max(64)).max(16).default([]),
  references: z
    .array(
      z.object({
        title: z.string().max(200),
        url: z.string().max(2000).optional(),
        snippet: z.string().max(2000).optional(),
      })
    )
    .max(12)
    .default([]),
  toolCalls: z.array(z.unknown()).max(8).default([]),
  used_web_search: z.boolean().default(false),
});

export type CoachChatMessageParsed = z.infer<typeof coachChatMessageSchema>;

/** Accept snake_case from sloppy model output before Zod. */
export function normalizeCoachKeys(raw: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = { ...raw };
  if (out.suggested_actions && !out.suggestedActions) {
    out.suggestedActions = out.suggested_actions;
  }
  if (out.follow_up_question != null && out.followUpQuestion == null) {
    out.followUpQuestion = out.follow_up_question;
  }
  if (out.follow_up_blocks && !out.followUpBlocks) {
    out.followUpBlocks = out.follow_up_blocks;
  }
  if (out.usedWebSearch != null && out.used_web_search == null) {
    out.used_web_search = out.usedWebSearch;
  }
  if (Array.isArray(out.followUpBlocks)) {
    out.followUpBlocks = out.followUpBlocks.map((b: unknown) => {
      if (!b || typeof b !== "object") return b;
      const x = b as Record<string, unknown>;
      if (x.suggested_actions && !x.suggestedActions) {
        return { ...x, suggestedActions: x.suggested_actions };
      }
      return x;
    });
  }
  return out;
}

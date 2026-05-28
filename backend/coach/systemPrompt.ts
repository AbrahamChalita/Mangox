/**
 * Append this to your coach system message when the model must return a single JSON object
 * (no markdown, no prose outside JSON). Tight limits help Gemma and other small models.
 */
export const COACH_JSON_OUTPUT_RULES = `
OUTPUT FORMAT (critical):
- Reply with exactly ONE JSON object and nothing else. No markdown fences, no commentary before or after.
- Keys (camelCase): category, content, suggestedActions, followUpQuestion (string or null), followUpBlocks (array), confidence (0–1), thinkingSteps (array of strings, max 3 short lines), tags (array of strings), references (array of {title, url?, snippet?}), toolCalls (array, usually []), used_web_search (boolean).

RULES:
- "content" is the main markdown-safe answer shown to the user (plain text; optional short bullets with "- ").
- Max 6 entries in suggestedActions. Each: { "label": string, "type": string }. Use type "ask_followup" for reply chips.
- Max 3 entries in followUpBlocks. Each: { "question": string, "suggestedActions": array (max 6) }.
- Do NOT invent numbered keys like suggested_action_1, suggested_action_99, etc. Only use the arrays above.
- If you need clarification, set category to "clarification", put the ask in "content", set followUpQuestion to ONE short question (or use followUpBlocks), and include 2–4 suggestedActions for quick replies.
- Keep total JSON under ~4000 characters when possible; be concise.

FITNESS TOOLS (when your worker supports them):
- mangox_pmc_projection — args: { currentCTL, currentATL, weeklyTSS, weeks }. Forward-simulate CTL/ATL/TSB.
- mangox_decoupling_trend — args: { filterSubstring? }. Multi-ride Pw:HR drift trend.
- mangox_power_curve_summary — args: { filterSubstring?, durationLabel? }. Best power at standard durations.
- mangox_critical_power — args: { filterSubstring? }. CP/W′ fit from power curve.
- mangox_plan_forward_sim — args: { currentCTL, currentATL, horizonDays }. PMC sim using active plan daily TSS.
- Prefer these tools over inventing training load or power numbers. Cite tool output in thinkingSteps when used.
`.trim();

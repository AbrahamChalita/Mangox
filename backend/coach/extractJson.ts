/**
 * Extract the first syntactically balanced `{ ... }` from text, respecting strings and escapes.
 * Returns null if the object never closes (truncated stream).
 */
export function extractFirstBalancedJsonObject(text: string): string | null {
  const start = text.indexOf("{");
  if (start < 0) return null;

  let depth = 0;
  let inString = false;
  let escape = false;

  for (let i = start; i < text.length; i++) {
    const c = text[i]!;

    if (escape) {
      escape = false;
      continue;
    }

    if (inString) {
      if (c === "\\") {
        escape = true;
        continue;
      }
      if (c === '"') {
        inString = false;
      }
      continue;
    }

    if (c === '"') {
      inString = true;
      continue;
    }

    if (c === "{") depth++;
    else if (c === "}") {
      depth--;
      if (depth === 0) return text.slice(start, i + 1);
    }
  }

  return null;
}

/** Strip ```json ... ``` fences some models wrap around JSON. */
export function stripMarkdownJsonFence(text: string): string {
  let t = text.trim();
  if (t.startsWith("```")) {
    const firstNl = t.indexOf("\n");
    if (firstNl >= 0) t = t.slice(firstNl + 1);
    const end = t.lastIndexOf("```");
    if (end >= 0) t = t.slice(0, end);
  }
  return t.trim();
}

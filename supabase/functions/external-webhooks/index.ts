type Provider = "strava" | "whoop";

type LinkedAccountRow = {
  user_id: string;
};

type WebhookEventRow = {
  user_id: string;
  provider: Provider;
  provider_user_id: string;
  provider_object_id: string;
  event_type: string;
  aspect_type?: string;
  object_type?: string;
  updates: Record<string, unknown>;
  trace_id?: string;
  payload: Record<string, unknown>;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-mangox-webhook-secret",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const url = new URL(req.url);
  if (req.method === "GET" && url.searchParams.has("hub.challenge")) {
    return handleStravaVerification(url);
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const secretError = validateSharedSecret(req, url);
  if (secretError) return secretError;

  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Expected JSON body" }, 400);
  }

  const provider = detectProvider(url, payload);
  if (!provider) {
    return json({ error: "Missing or unknown provider" }, 400);
  }

  const parsed = parseEvent(provider, payload);
  if (!parsed) {
    return json({ error: "Webhook payload is missing required ids" }, 400);
  }

  const users = await findLinkedUsers(provider, parsed.providerUserId);
  if (users instanceof Response) return users;

  if (users.length > 0) {
    const insertResult = await insertEvents(users.map((user) => ({
      user_id: user.user_id,
      provider,
      provider_user_id: parsed.providerUserId,
      provider_object_id: parsed.providerObjectId,
      event_type: parsed.eventType,
      aspect_type: parsed.aspectType,
      object_type: parsed.objectType,
      updates: parsed.updates,
      trace_id: parsed.traceId,
      payload,
    })));
    if (insertResult instanceof Response) return insertResult;
  }

  return json({ ok: true, provider, matched: users.length }, 202);
});

function handleStravaVerification(url: URL): Response {
  const challenge = url.searchParams.get("hub.challenge");
  const expectedToken = Deno.env.get("STRAVA_WEBHOOK_VERIFY_TOKEN");
  const suppliedToken = url.searchParams.get("hub.verify_token");

  if (expectedToken && suppliedToken !== expectedToken) {
    return json({ error: "Invalid Strava verify token" }, 401);
  }
  return json({ "hub.challenge": challenge ?? "" });
}

function validateSharedSecret(req: Request, url: URL): Response | null {
  const expected = Deno.env.get("MANGOX_WEBHOOK_SECRET");
  if (!expected) return null;

  const supplied = req.headers.get("x-mangox-webhook-secret") ?? url.searchParams.get("secret");
  if (supplied !== expected) {
    return json({ error: "Invalid webhook secret" }, 401);
  }
  return null;
}

function detectProvider(url: URL, payload: Record<string, unknown>): Provider | null {
  const raw = url.searchParams.get("provider")?.toLowerCase();
  if (raw === "strava" || raw === "whoop") return raw;
  if (typeof payload.object_type === "string" && typeof payload.aspect_type === "string") return "strava";
  if (typeof payload.type === "string" && typeof payload.user_id !== "undefined") return "whoop";
  return null;
}

function parseEvent(provider: Provider, payload: Record<string, unknown>) {
  if (provider === "strava") {
    const ownerId = stringify(payload.owner_id);
    const objectId = stringify(payload.object_id);
    const objectType = stringify(payload.object_type);
    const aspectType = stringify(payload.aspect_type);
    if (!ownerId || !objectId || !objectType || !aspectType) return null;
    return {
      providerUserId: ownerId,
      providerObjectId: objectId,
      eventType: `${objectType}.${aspectType}`,
      objectType,
      aspectType,
      traceId: undefined,
      updates: objectRecord(payload.updates),
    };
  }

  const userId = stringify(payload.user_id);
  const objectId = stringify(payload.id);
  const type = stringify(payload.type);
  if (!userId || !objectId || !type) return null;
  return {
    providerUserId: userId,
    providerObjectId: objectId,
    eventType: type,
    objectType: type.split(".")[0] || undefined,
    aspectType: type.split(".")[1] || undefined,
    traceId: stringify(payload.trace_id),
    updates: {},
  };
}

async function findLinkedUsers(provider: Provider, providerUserId: string): Promise<LinkedAccountRow[] | Response> {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: "Supabase service role is not configured" }, 500);
  }

  const params = new URLSearchParams({
    provider: `eq.${provider}`,
    provider_user_id: `eq.${providerUserId}`,
    select: "user_id",
  });
  const response = await fetch(`${supabaseUrl}/rest/v1/linked_oauth_accounts?${params}`, {
    headers: serviceHeaders(serviceRoleKey),
  });

  if (!response.ok) {
    return json({ error: "Could not route webhook", detail: await response.text() }, 502);
  }
  return await response.json();
}

async function insertEvents(rows: WebhookEventRow[]): Promise<true | Response> {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: "Supabase service role is not configured" }, 500);
  }

  const response = await fetch(`${supabaseUrl}/rest/v1/external_webhook_events`, {
    method: "POST",
    headers: {
      ...serviceHeaders(serviceRoleKey),
      "Content-Type": "application/json",
      "Prefer": "return=minimal",
    },
    body: JSON.stringify(rows),
  });

  if (!response.ok) {
    return json({ error: "Could not store webhook event", detail: await response.text() }, 502);
  }
  return true;
}

function serviceHeaders(serviceRoleKey: string): HeadersInit {
  return {
    apikey: serviceRoleKey,
    Authorization: `Bearer ${serviceRoleKey}`,
  };
}

function stringify(value: unknown): string | undefined {
  if (typeof value === "string") return value.trim() || undefined;
  if (typeof value === "number" && Number.isFinite(value)) return String(value);
  return undefined;
}

function objectRecord(value: unknown): Record<string, unknown> {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return {};
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

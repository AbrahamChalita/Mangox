// Proxies WHOOP / Strava OAuth token exchange so client secrets never ship in the iOS app.
// Secrets (set via `supabase secrets set`): WHOOP_CLIENT_ID, WHOOP_CLIENT_SECRET,
// STRAVA_CLIENT_ID, STRAVA_CLIENT_SECRET.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const WHOOP_TOKEN_URL = "https://api.prod.whoop.com/oauth/oauth2/token";
const STRAVA_TOKEN_URL = "https://www.strava.com/oauth/token";

const DEFAULT_REDIRECTS = [
  "mangox://localhost/whoop-auth",
  "mangox://localhost/strava-auth",
] as const;

type Provider = "whoop" | "strava";
type GrantType = "authorization_code" | "refresh_token";

interface ExchangeRequest {
  provider?: Provider;
  grant_type?: GrantType;
  code?: string;
  refresh_token?: string;
  redirect_uri?: string;
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function allowedRedirectURIs(): Set<string> {
  const extra = Deno.env.get("OAUTH_ALLOWED_REDIRECT_URIS")?.trim();
  const fromEnv = extra
    ? extra.split(",").map((s) => s.trim()).filter(Boolean)
    : [];
  return new Set([...DEFAULT_REDIRECTS, ...fromEnv]);
}

function requireEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) {
    throw new Error(`missing_server_secret:${name}`);
  }
  return value;
}

function parseRequest(body: unknown): ExchangeRequest {
  if (!body || typeof body !== "object") {
    throw new Error("invalid_body");
  }
  return body as ExchangeRequest;
}

function validateRequest(req: ExchangeRequest): void {
  if (req.provider !== "whoop" && req.provider !== "strava") {
    throw new Error("invalid_provider");
  }
  if (req.grant_type !== "authorization_code" && req.grant_type !== "refresh_token") {
    throw new Error("invalid_grant_type");
  }
  if (req.grant_type === "authorization_code") {
    if (!req.code?.trim()) throw new Error("missing_code");
    if (!req.redirect_uri?.trim()) throw new Error("missing_redirect_uri");
    if (!allowedRedirectURIs().has(req.redirect_uri.trim())) {
      throw new Error("invalid_redirect_uri");
    }
  }
  if (req.grant_type === "refresh_token" && !req.refresh_token?.trim()) {
    throw new Error("missing_refresh_token");
  }
}

function buildUpstreamBody(req: ExchangeRequest): URLSearchParams {
  const params = new URLSearchParams();

  if (req.provider === "whoop") {
    params.set("client_id", requireEnv("WHOOP_CLIENT_ID"));
    params.set("client_secret", requireEnv("WHOOP_CLIENT_SECRET"));
    params.set("grant_type", req.grant_type!);
    if (req.grant_type === "authorization_code") {
      params.set("code", req.code!.trim());
      params.set("redirect_uri", req.redirect_uri!.trim());
    } else {
      params.set("refresh_token", req.refresh_token!.trim());
      params.set("scope", "offline");
    }
    return params;
  }

  params.set("client_id", requireEnv("STRAVA_CLIENT_ID"));
  params.set("client_secret", requireEnv("STRAVA_CLIENT_SECRET"));
  params.set("grant_type", req.grant_type!);
  if (req.grant_type === "authorization_code") {
    params.set("code", req.code!.trim());
  } else {
    params.set("refresh_token", req.refresh_token!.trim());
  }
  return params;
}

function tokenURL(provider: Provider): string {
  return provider === "whoop" ? WHOOP_TOKEN_URL : STRAVA_TOKEN_URL;
}

function mapError(status: number, raw: string): { error: string; detail?: string } {
  if (status === 401 || status === 403) {
    return { error: "upstream_unauthorized", detail: raw };
  }
  return { error: "upstream_token_exchange_failed", detail: raw };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers":
          "authorization, x-client-info, apikey, content-type",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
      },
    });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  let payload: ExchangeRequest;
  try {
    payload = parseRequest(await req.json());
    validateRequest(payload);
  } catch (e) {
    const message = e instanceof Error ? e.message : "invalid_request";
    const status = message.startsWith("missing_server_secret:") ? 503 : 400;
    return jsonResponse({ error: message }, status);
  }

  const upstreamBody = buildUpstreamBody(payload);
  let upstreamResponse: Response;
  try {
    upstreamResponse = await fetch(tokenURL(payload.provider!), {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        Accept: "application/json",
      },
      body: upstreamBody.toString(),
    });
  } catch {
    return jsonResponse({ error: "upstream_unreachable" }, 502);
  }

  const raw = await upstreamResponse.text();
  if (!upstreamResponse.ok) {
    return jsonResponse(
      mapError(upstreamResponse.status, raw),
      upstreamResponse.status >= 500 ? 502 : 400,
    );
  }

  try {
    const parsed = JSON.parse(raw);
    return jsonResponse(parsed, 200);
  } catch {
    return jsonResponse({ error: "invalid_upstream_response" }, 502);
  }
});

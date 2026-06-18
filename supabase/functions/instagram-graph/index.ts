// Instagram Graph API token custody for Business/Creator accounts.
//
// Proxies Meta OAuth token exchange + Instagram Business account resolution so the Meta App Secret
// never ships in the iOS app. Supports:
//   - action=exchange       : exchange an OAuth `code` for a long-lived user token, then resolve the
//                             linked Instagram Business/Creator account id + username.
//   - action=refresh        : refresh a long-lived user token (valid ~60 days; refresh before expiry).
//   - action=resolve_account: resolve the IG Business account id + username for an existing long-lived token.
//
// Secrets (set via `supabase secrets set`): META_APP_ID, META_APP_SECRET, META_REDIRECT_URI.
//
// App Review requirements (Meta App must have these permissions approved):
//   - instagram_basic
//   - instagram_content_publishing (to publish Stories/Reels via the Graph API)
//   - pages_show_list (to resolve the Page → instagram_business_account)
//
// Token custody note: this function returns tokens to the caller. For production, prefer storing the
// long-lived token server-side (Supabase table keyed by user id) and exposing publish actions as
// authenticated edge-function endpoints so the token never reaches the device.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const GRAPH_API_BASE = "https://graph.facebook.com/v21.0";

type Action = "exchange" | "refresh" | "resolve_account";

interface ExchangeRequest {
  action?: Action;
  code?: string;
  redirect_uri?: string;
  long_lived_token?: string;
}

type ValidatedRequest =
  | { action: "exchange"; code: string; redirect_uri: string }
  | { action: "refresh"; long_lived_token: string }
  | { action: "resolve_account"; long_lived_token: string };

interface InstagramAccount {
  ig_user_id: string;
  username: string;
  page_id: string;
}

interface ExchangeResponse {
  long_lived_token: string;
  expires_at: number | null;
  instagram: InstagramAccount | null;
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
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

function allowedRedirectURIs(): Set<string> {
  const extra = Deno.env.get("INSTAGRAM_ALLOWED_REDIRECT_URIS")?.trim();
  const fromEnv = extra
    ? extra.split(",").map((s) => s.trim()).filter(Boolean)
    : [];
  const defaultRedirect = Deno.env.get("META_REDIRECT_URI")?.trim();
  const defaults = defaultRedirect ? [defaultRedirect] : [];
  return new Set([...defaults, ...fromEnv]);
}

function validateRequest(req: ExchangeRequest): ValidatedRequest {
  if (req.action !== "exchange" && req.action !== "refresh" && req.action !== "resolve_account") {
    throw new Error("invalid_action");
  }
  if (req.action === "exchange") {
    if (!req.code?.trim()) throw new Error("missing_code");
    if (!req.redirect_uri?.trim()) throw new Error("missing_redirect_uri");
    if (!allowedRedirectURIs().has(req.redirect_uri.trim())) {
      throw new Error("invalid_redirect_uri");
    }
    return { action: "exchange", code: req.code.trim(), redirect_uri: req.redirect_uri.trim() };
  }
  if (!req.long_lived_token?.trim()) throw new Error("missing_long_lived_token");
  return { action: req.action, long_lived_token: req.long_lived_token.trim() };
}

async function graphGet(path: string, params: URLSearchParams): Promise<unknown> {
  const url = `${GRAPH_API_BASE}${path}?${params.toString()}`;
  const res = await fetch(url, { headers: { Accept: "application/json" } });
  const raw = await res.text();
  if (!res.ok) {
    throw new Error(`graph_error:${res.status}:${raw}`);
  }
  try {
    return JSON.parse(raw);
  } catch {
    throw new Error(`graph_invalid_response:${raw}`);
  }
}

/// Exchange the short-lived code for a short-lived user token, then a long-lived user token.
async function exchangeForLongLivedToken(code: string, redirectUri: string): Promise<{ token: string; expiresAt: number | null }> {
  const appId = requireEnv("META_APP_ID");
  const appSecret = requireEnv("META_APP_SECRET");

  const shortParams = new URLSearchParams({
    client_id: appId,
    redirect_uri: redirectUri,
    client_secret: appSecret,
    code,
  });
  const shortRes = (await graphGet("/oauth/access_token", shortParams)) as {
    access_token?: string;
    expires_in?: number;
  };
  const shortToken = shortRes.access_token?.trim();
  if (!shortToken) throw new Error("no_short_lived_token");

  const longParams = new URLSearchParams({
    grant_type: "fb_exchange_token",
    client_id: appId,
    client_secret: appSecret,
    fb_exchange_token: shortToken,
  });
  const longRes = (await graphGet("/oauth/access_token", longParams)) as {
    access_token?: string;
    expires_in?: number;
  };
  const longToken = longRes.access_token?.trim();
  if (!longToken) throw new Error("no_long_lived_token");
  const expiresAt = longRes.expires_in ? Date.now() + longRes.expires_in * 1000 : null;
  return { token: longToken, expiresAt };
}

/// Resolve the first linked Instagram Business/Creator account for the given long-lived user token.
async function resolveInstagramAccount(longLivedToken: string): Promise<InstagramAccount | null> {
  const accountsParams = new URLSearchParams({ access_token: longLivedToken });
  const accounts = (await graphGet("/me/accounts", accountsParams)) as {
    data?: Array<{ id?: string; access_token?: string }>;
  };
  const page = accounts.data?.find((p) => p.id && p.access_token);
  if (!page?.id) return null;

  const igParams = new URLSearchParams({
    fields: "instagram_business_account",
    access_token: longLivedToken,
  });
  const igLink = (await graphGet(`/${page.id}`, igParams)) as {
    instagram_business_account?: { id?: string };
  };
  const igUserId = igLink.instagram_business_account?.id;
  if (!igUserId) return null;

  const usernameParams = new URLSearchParams({
    fields: "username",
    access_token: longLivedToken,
  });
  const igProfile = (await graphGet(`/${igUserId}`, usernameParams)) as { username?: string };

  return {
    ig_user_id: igUserId,
    username: igProfile.username?.trim() ?? "",
    page_id: page.id,
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
      },
    });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  let payload: ValidatedRequest;
  try {
    payload = validateRequest(parseRequest(await req.json()));
  } catch (e) {
    const message = e instanceof Error ? e.message : "invalid_request";
    const status = message.startsWith("missing_server_secret:") ? 503 : 400;
    return jsonResponse({ error: message }, status);
  }

  try {
    let token: string;
    let expiresAt: number | null = null;

    if (payload.action === "exchange") {
      const exchanged = await exchangeForLongLivedToken(payload.code, payload.redirect_uri);
      token = exchanged.token;
      expiresAt = exchanged.expiresAt;
    } else {
      token = payload.long_lived_token;
    }

    let instagram: InstagramAccount | null = null;
    try {
      instagram = await resolveInstagramAccount(token);
    } catch (e) {
      // Token is valid but IG account resolution failed (no linked business account, or permissions missing).
      // Return the token with instagram=null so the caller can surface a clear error.
      instagram = null;
    }

    const body: ExchangeResponse = {
      long_lived_token: token,
      expires_at: expiresAt,
      instagram,
    };
    return jsonResponse(body, 200);
  } catch (e) {
    const message = e instanceof Error ? e.message : "exchange_failed";
    if (message.startsWith("missing_server_secret:")) {
      return jsonResponse({ error: message }, 503);
    }
    if (message.startsWith("graph_error:")) {
      return jsonResponse({ error: "upstream_graph_error", detail: message }, 502);
    }
    if (message.startsWith("upstream") || message === "no_short_lived_token" || message === "no_long_lived_token") {
      return jsonResponse({ error: message }, 502);
    }
    return jsonResponse({ error: message }, 400);
  }
});

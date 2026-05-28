#!/usr/bin/env bash
# Deploy oauth-token-exchange and required Supabase secrets for WHOOP / Strava linking.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

require_var() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "Missing $name. Export WHOOP_CLIENT_ID, WHOOP_CLIENT_SECRET, STRAVA_CLIENT_ID, STRAVA_CLIENT_SECRET." >&2
    exit 1
  fi
}

require_var WHOOP_CLIENT_ID
require_var WHOOP_CLIENT_SECRET
require_var STRAVA_CLIENT_ID
require_var STRAVA_CLIENT_SECRET

if ! command -v supabase >/dev/null 2>&1; then
  echo "Install the Supabase CLI: https://supabase.com/docs/guides/cli" >&2
  exit 1
fi

echo "Setting Supabase secrets for OAuth proxy…"
supabase secrets set \
  "WHOOP_CLIENT_ID=${WHOOP_CLIENT_ID}" \
  "WHOOP_CLIENT_SECRET=${WHOOP_CLIENT_SECRET}" \
  "STRAVA_CLIENT_ID=${STRAVA_CLIENT_ID}" \
  "STRAVA_CLIENT_SECRET=${STRAVA_CLIENT_SECRET}"

echo "Deploying oauth-token-exchange…"
supabase functions deploy oauth-token-exchange

echo "Done. Test WHOOP/Strava connect from the app Settings screen."

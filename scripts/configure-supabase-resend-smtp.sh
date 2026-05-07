#!/usr/bin/env bash
set -euo pipefail

PROJECT_REF="${SUPABASE_PROJECT_REF:-jvhkplgacbeuksiphgyk}"
SENDER_NAME="${SUPABASE_SMTP_SENDER_NAME:-Mangox}"
SMTP_PORT="${SUPABASE_SMTP_PORT:-465}"

if [[ -z "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
  echo "Missing SUPABASE_ACCESS_TOKEN. Create one at https://supabase.com/dashboard/account/tokens" >&2
  exit 1
fi

if [[ -z "${RESEND_API_KEY:-}" ]]; then
  echo "Missing RESEND_API_KEY. Use the Resend API key as the SMTP password." >&2
  exit 1
fi

if [[ -z "${SUPABASE_SMTP_FROM:-}" ]]; then
  echo "Missing SUPABASE_SMTP_FROM, for example no-reply@auth.example.com." >&2
  exit 1
fi

body="$(mktemp)"
trap 'rm -f "$body"' EXIT

jq -n \
  --arg from "$SUPABASE_SMTP_FROM" \
  --arg host "smtp.resend.com" \
  --arg user "resend" \
  --arg pass "$RESEND_API_KEY" \
  --arg sender "$SENDER_NAME" \
  --argjson port "$SMTP_PORT" \
  '{
    external_email_enabled: true,
    mailer_secure_email_change_enabled: true,
    mailer_autoconfirm: false,
    smtp_admin_email: $from,
    smtp_host: $host,
    smtp_port: $port,
    smtp_user: $user,
    smtp_pass: $pass,
    smtp_sender_name: $sender
  }' > "$body"

curl --fail-with-body \
  -X PATCH "https://api.supabase.com/v1/projects/${PROJECT_REF}/config/auth" \
  -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  --data-binary "@${body}"

echo
echo "Supabase Auth SMTP is configured to send through Resend for ${PROJECT_REF}."

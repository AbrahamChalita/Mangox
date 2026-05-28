#!/usr/bin/env bash
# Reconcile Supabase migration history when the remote DB was built via MCP/dashboard
# but this repo only tracks new migrations under supabase/migrations/.
#
# This does NOT roll back schema — it only fixes the supabase_migrations.schema_migrations table
# so `supabase db push` can apply 20260527120000_linked_oauth_accounts.sql.
#
# Prereq: supabase link --project-ref jvhkplgacbeuksiphgyk
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v supabase >/dev/null 2>&1; then
  echo "Install Supabase CLI: https://supabase.com/docs/guides/cli" >&2
  exit 1
fi

echo "Marking remote-only MCP migration versions as reverted (history bookkeeping only)…"
supabase migration repair --status reverted \
  20260506211213 \
  20260506211236 \
  20260506211305 \
  20260506211336 \
  20260506211414 \
  20260506211426 \
  20260506211450 \
  20260506211514 \
  20260506211548 \
  20260506211745 \
  20260507022847

echo ""
echo "Pushing local migrations (linked_oauth_accounts)…"
supabase db push

echo ""
echo "Done. Verify in Dashboard → Database → Tables → linked_oauth_accounts"

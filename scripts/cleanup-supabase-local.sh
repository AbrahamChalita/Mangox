#!/usr/bin/env bash
# Remove local Supabase CLI artifacts only (safe — does not touch remote DB).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -d supabase/.temp ]]; then
  rm -rf supabase/.temp
  echo "Removed supabase/.temp/"
else
  echo "No supabase/.temp/ to remove."
fi

if command -v supabase >/dev/null 2>&1; then
  if supabase unlink 2>/dev/null; then
    echo "Unlinked local Supabase project (run supabase link to reconnect)."
  fi
fi

echo "Done. Remote database unchanged."

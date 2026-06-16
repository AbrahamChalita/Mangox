# Supabase Setup — Mangox

Backend-of-record for Mangox cloud sync, AI coaching context, and (optional) account-bound user data.

## Project

| Field | Value |
| --- | --- |
| Project ref | `jvhkplgacbeuksiphgyk` |
| URL | `https://jvhkplgacbeuksiphgyk.supabase.co` |
| Region | `us-east-1` |
| Postgres | 17.6 |
| Publishable key | `sb_publishable_m2mgjTsNA9Gi2wPMwewwgg_oS8-aerC` (already wired into `Config/App.xcconfig`) |

The `service_role` key is **server-only** — never ship it in the iOS app. Use it from edge functions or trusted backends.

## Local-first, sync-optional

The product rule:

> Sign-in is optional. Until the user creates an account or signs in, **nothing is sent to the cloud**. Settings appears a "Sync to cloud" / "Create account" entry that opts them in later.

Onboarding copy must say this explicitly. Suggested wording:

> "You can use Mangox without an account. Your rides, settings, and coach chats stay on this device. To back them up to your account or use cloud features, sign in or create an account in Settings."

Implementation contract:

1. SwiftData remains the source of truth on device. Existing models keep working.
2. A `SupabaseSyncCoordinator` singleton starts disabled. It only initializes the Supabase client and begins reconciling once the user authenticates.
3. On first sign-in, all local rows are uploaded under the new `user_id`. Every row has a `client_id UUID` for idempotent upsert.
4. Sign-out clears the in-memory session but keeps local data. The next sign-in (same account) merges by `client_id`; a different account creates a fresh cloud namespace and the user is asked whether to upload local data, keep it local, or replace cloud data.

## Auth providers

Enable in Dashboard → Authentication → Providers:

- **Email OTP** (no password) — primary.
- **Sign in with Apple** — recommended for iOS; required by App Store guidelines if other social providers are offered.
- **Google** (optional).

Add the deep-link callback in iOS scheme handler: `mangox://auth-callback`.
Add the same URL to Authentication → URL Configuration → Redirect URLs.

## Auth email delivery with Resend

Supabase's built-in email sender is only for demos: it sends only to project team
addresses and currently has a very low project-level limit. Keep the iOS app on
Supabase OTP auth, but configure Supabase Auth to deliver those OTP emails through
Resend custom SMTP.

Resend SMTP settings:

| Field | Value |
| --- | --- |
| Host | `smtp.resend.com` |
| Port | `465` (implicit SSL/TLS; `587` STARTTLS also works) |
| Username | `resend` |
| Password | Resend API key |
| From address | A verified Resend sender, preferably `no-reply@auth.<domain>` |

Apply with the helper script:

```bash
export SUPABASE_ACCESS_TOKEN="sbp_..."
export RESEND_API_KEY="re_..."
export SUPABASE_SMTP_FROM="no-reply@auth.example.com"
export SUPABASE_SMTP_SENDER_NAME="Mangox"

scripts/configure-supabase-resend-smtp.sh
```

Do not put the Resend API key in `Config/App.xcconfig`, `Config/Secrets.xcconfig`,
or the iOS target. It belongs only in Supabase Auth's server-side SMTP settings.

After saving SMTP settings, send a fresh OTP from the app and check Supabase Auth
logs plus Resend logs if delivery fails. Then tune Authentication → Rate Limits:
custom SMTP lifts the demo sender restriction, but Supabase still defaults to a
60-second resend window for the same user and a modest project-level OTP limit.
Keep the same-user delay in place to protect the sender reputation.

## Schema (public)

| Table | Purpose |
| --- | --- |
| `profiles` | One row per user. Identity, physical metrics, current FTP/HR zones, units, locale. Auto-created on signup. |
| `user_settings` | All ride preferences (mirrors iOS `RidePreferences` UserDefaults). Typed columns for stable settings + `extra` jsonb for forward compat. |
| `zone_snapshots` | Audit trail of FTP / max HR / resting HR changes over time. |
| `workouts` | Completed rides (indoor / outdoor / virtual). Includes summary metrics, route GeoJSON, plan link, full-text `search_tsv`. |
| `workout_samples` | Per-second telemetry stream. Cascade-deleted with parent workout. |
| `workout_laps` | Lap / split summaries. |
| `workout_rag_chunks` | `vector(1536)` embeddings + chunk text for AI coach retrieval. |
| `custom_workout_templates` | User-authored interval workouts. |
| `ai_generated_plans` | AI-generated multi-week training plans. |
| `training_plan_progress` | Per-plan completed/skipped days, FTP delta, adaptive load multiplier. |
| `goals` | Distance / duration / TSS / streak goals (period-scoped). |
| `chat_sessions` | AI coach conversation threads. |
| `chat_messages` | Messages within a session. |
| `linked_oauth_accounts` | Encrypted Strava/WHOOP OAuth sessions (AES-256-GCM with `USER_DATA_KEY`). Restored on sign-in after reinstall. |

### AI-friendly views & RPCs

- `v_workout_overview` — flat summary of completed workouts. Use for "show recent rides".
- `v_daily_training_load` — per-day rollup (workouts, TSS, duration, distance, elevation).
- `match_workouts(query_embedding vector, match_count int, min_similarity float)` — cosine similarity search scoped to caller.
- `get_user_context()` — one-shot bundle (profile + settings + active plan + last 10 workouts + 30d load + active goals) for the coach.

All views use `security_invoker = true`; all RPCs use `security invoker`. RLS applies as if the user ran the SQL themselves.

### RLS

Every user-scoped table has RLS enabled and forced. Per-table policies:

- `select`, `insert`, `update`, `delete` to `authenticated` where `user_id = (select auth.uid())`.

Anonymous users (no JWT) cannot read or write anything. This is what enforces the "nothing leaves the device unless you sign in" guarantee.

### pgvector

Extension installed in `extensions` schema (out of public per linter best practice). The `workout_rag_chunks.embedding` column is `vector(1536)` to match OpenAI `text-embedding-3-small` / `ada-002`. If you swap models with a different dim, run a follow-up migration to alter the column and rebuild the IVFFlat index.

The IVFFlat index uses `lists = 100` — fine to start. Once you have ≥10k chunks, rebuild with `lists ≈ sqrt(rows)` for better recall.

## iOS integration plan

### Dependencies

Add to `Mangox.xcodeproj` via Swift Package Manager:

- `https://github.com/supabase/supabase-swift` (latest, `Supabase` library).

### Config plumbing

`Config/App.xcconfig` already exposes `SUPABASE_URL_HOST` and `SUPABASE_PUBLISHABLE_KEY`. Surface them to runtime via `Info.plist`:

```xml
<key>SUPABASE_URL_HOST</key>
<string>$(SUPABASE_URL_HOST)</string>
<key>SUPABASE_PUBLISHABLE_KEY</key>
<string>$(SUPABASE_PUBLISHABLE_KEY)</string>
```

### Suggested module layout

```
Mangox/Core/Networking/Supabase/
  SupabaseClient+Mangox.swift     // singleton, lazy init from Info.plist
  SupabaseSyncCoordinator.swift   // entry point: enable/disable, push, pull, resolve
  Mappers/
    Workout+Supabase.swift
    UserSettings+Supabase.swift
    ChatSession+Supabase.swift
    ...
```

### Sync model

- **Push**: on sign-in, upsert all SwiftData rows by `client_id`. Subsequent edits are queued and flushed on app foreground / network availability.
- **Pull**: follow-up work. The current iOS implementation is cloud backup first; true multi-device restore/sync should fetch rows newer than `local.updated_at`, merge by `client_id`, and let remote `updated_at` win on conflicts.
- **Realtime** (later): subscribe to `workouts`, `chat_messages`, `user_settings` for cross-device live updates.

### Idempotency

Every table that maps to an iOS SwiftData model has `client_id UUID` (or a natural unique key). Upsert with `onConflict: "user_id,client_id"`.

## Settings UI changes needed

Add to `Features/Profile/Presentation`:

1. **Account section** (top of Settings):
   - When signed out: "Sync to cloud — Sign in or create account" with a subtitle "Your data stays on this device until you sign in."
   - When signed in: shows email, "Last backed up …", "Sign out", "Delete cloud data".
2. **Onboarding final step**: a clear screen explaining cloud-optional behavior with two CTAs — `Skip — keep on device` (primary) and `Create account` (secondary).

## Updating the schema

Use the Supabase MCP `apply_migration` tool with snake_case names. Migrations applied so far (in order):

1. `01_extensions_and_profiles`
2. `02_settings_and_zone_snapshots`
3. `03_workouts_samples_laps`
4. `04_rag_chunks`
5. `05_training_plans_and_goals`
6. `06_coach_chat`
7. `07_rls_policies`
8. `08_views_and_rpc_for_ai`
9. `09_harden_functions_and_indexes`
10. `20260527120000_linked_oauth_accounts` (in-repo SQL under `supabase/migrations/`)

After any DDL change, run `get_advisors` (security + performance) and address WARN-level findings before shipping.

### Migration history mismatch (`db pull` / `db push` errors)

The core schema (`profiles`, `workouts`, etc.) was applied remotely via MCP with version IDs that are **not** checked into this repo. Only newer migrations live under `supabase/migrations/`. The CLI then reports:

> Remote migration versions not found in local migrations directory

**Do not use `supabase db pull` to fix this** unless you intend to replace repo migrations with a full remote dump (and you have `SUPABASE_DB_PASSWORD` set for the linked project).

**Recommended fix** (history bookkeeping only — does not drop existing tables):

```bash
supabase link --project-ref jvhkplgacbeuksiphgyk
./scripts/repair-supabase-migration-history.sh
```

Or manually:

```bash
supabase migration repair --status reverted \
  20260506211213 20260506211236 20260506211305 20260506211336 \
  20260506211414 20260506211426 20260506211450 20260506211514 \
  20260506211548 20260506211745 20260507022847

supabase db push
```

If you already ran the `linked_oauth_accounts` SQL in the dashboard:

```bash
supabase migration repair --status applied 20260527120000
```

**Alternative:** paste `supabase/migrations/20260527120000_linked_oauth_accounts.sql` into the Supabase SQL editor and run it, then mark applied as above.

### Cleanup

| Goal | What to do |
| --- | --- |
| **Fix CLI migration history (one-time)** | `./scripts/repair-supabase-migration-history.sh` — does not delete data |
| **Local CLI cache** | Delete `supabase/.temp/` (ignored by git; recreated on `supabase link`) |
| **Unlink project on this machine** | `supabase unlink` |
| **Remove encrypted Strava/WHOOP backups** | Disconnect each service in Settings, or sign in and use “Delete all my data” (also wipes local + cloud OAuth rows) |
| **Remove cloud account data, keep local rides** | Settings → Account → Sign out (OAuth backups stay until you disconnect integrations) |
| **Drop `linked_oauth_accounts` table** | Dashboard SQL: `drop table if exists public.linked_oauth_accounts cascade;` then `supabase migration repair --status reverted 20260527120000` |

**Do not** run `supabase db reset` on the hosted project — that targets local Docker, not production. Never `drop schema public` on `jvhkplgacbeuksiphgyk` unless you intend to destroy all user data.

**Steady state after repair:** only `supabase/migrations/*.sql` in git drives new changes; use `supabase db push` for future migrations. Skip `db pull` unless you are intentionally rebaselining the migrations folder.

### Linked OAuth (Strava / WHOOP)

Apply migration `supabase/migrations/20260527120000_linked_oauth_accounts.sql` to the project (via `db push` after repair, or SQL editor).
Apply migration `supabase/migrations/20260616113000_external_webhook_events.sql` when enabling Strava/WHOOP webhooks.

When the user is signed in to cloud backup:

1. Connecting Strava or WHOOP encrypts the session JSON and upserts `linked_oauth_accounts`.
2. The app stores the provider account id in `provider_user_id` so Strava/WHOOP webhooks can be routed without decrypting OAuth tokens server-side.
3. Sign-in / sync **pull** restores tokens into Keychain if the device has no newer local copy.
4. Disconnect or “Delete all my data” removes the cloud row.

Requires `USER_DATA_KEY` in the build (same key as coach context encryption). App Store builds share one key per release; custom `Secrets.xcconfig` overrides break cross-device restore for that dev build.

## WHOOP / Strava OAuth (server-side token exchange)

[WHOOP](https://developer.whoop.com/docs/developing/oauth/) and [Strava](https://developers.strava.com/docs/authentication/) both require a **client secret** when exchanging authorization codes or refresh tokens. The secret must not ship in the iOS app. Mangox proxies token exchange through the Supabase Edge Function `oauth-token-exchange` (`supabase/functions/oauth-token-exchange/`).

The app still embeds **client IDs** and redirect URIs in `Config/App.xcconfig` (for the browser OAuth step). Only the secrets live on Supabase.

### Deploy

```bash
# One-time: link the Supabase CLI to project jvhkplgacbeuksiphgyk
supabase link --project-ref jvhkplgacbeuksiphgyk

# Set secrets (values from WHOOP Developer Dashboard / Strava API settings)
supabase secrets set \
  WHOOP_CLIENT_ID='your-whoop-client-id' \
  WHOOP_CLIENT_SECRET='your-whoop-client-secret' \
  STRAVA_CLIENT_ID='your-strava-client-id' \
  STRAVA_CLIENT_SECRET='your-strava-client-secret'

# Deploy the function
supabase functions deploy oauth-token-exchange
```

Or run `scripts/deploy-oauth-edge-function.sh` after exporting the four env vars above.

`verify_jwt` is **false** for this function so users can link WHOOP/Strava before signing in to cloud backup. The publishable anon key is still required on each request.

## WHOOP / Strava Webhooks

Mangox receives provider webhook callbacks through the Supabase Edge Function `external-webhooks` (`supabase/functions/external-webhooks/`). The function routes provider events to a signed-in Mangox user by matching `linked_oauth_accounts.provider_user_id`; the encrypted OAuth payload is never decrypted in the function.

Deploy after applying `20260616113000_external_webhook_events.sql`:

```bash
supabase secrets set \
  SUPABASE_SERVICE_ROLE_KEY='your-service-role-key' \
  STRAVA_WEBHOOK_VERIFY_TOKEN='your-random-strava-verify-token' \
  MANGOX_WEBHOOK_SECRET='your-random-shared-webhook-secret'

supabase functions deploy external-webhooks
```

Register callback URLs:

- Strava: `https://<project-ref>.supabase.co/functions/v1/external-webhooks?provider=strava&secret=<MANGOX_WEBHOOK_SECRET>`
- WHOOP: `https://<project-ref>.supabase.co/functions/v1/external-webhooks?provider=whoop&secret=<MANGOX_WEBHOOK_SECRET>`

Strava's subscription verification uses `STRAVA_WEBHOOK_VERIFY_TOKEN` and returns the required `hub.challenge`. Runtime event callbacks write to `external_webhook_events` for app-side refresh/processing.

### Redirect URIs

Allowed by default:

- `mangox://localhost/whoop-auth`
- `mangox://localhost/strava-auth`

Register the same URLs in the WHOOP and Strava developer consoles. Optional extra URIs: set `OAUTH_ALLOWED_REDIRECT_URIS` (comma-separated) in Supabase secrets.

### iOS behavior

- `WhoopService` / `StravaService` call `OAuthTokenExchangeClient`, which invokes `oauth-token-exchange` via `supabase-swift`.
- `isConfigured` is true when the app has a client ID, redirect URI, and Supabase URL/key in the build — not when xcconfig contains a client secret.
- If secrets are missing on the server, connect fails with a clear proxy error in Settings.

## Things still to do (manual)

- [ ] Enable Apple / Email providers in Auth dashboard and configure redirect URL `mangox://auth-callback`.
- [ ] Configure Resend custom SMTP for Auth OTP delivery and verify the sending domain's SPF, DKIM, and DMARC records.
- [ ] Decide on email template branding.
- [ ] Add `supabase-swift` SPM dependency to `Mangox.xcodeproj`.
- [ ] Implement `SupabaseSyncCoordinator` and SwiftData ↔ Postgres mappers.
- [ ] Add the Account section + onboarding cloud-optional screen.
- [ ] Once embedding model is finalized in `Features/Coach/`, confirm dim is 1536 (or migrate the column).

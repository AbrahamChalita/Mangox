# Mangox — Complete Functional Specification

> Extracted from the v1 codebase (June 2026) as the reference for the Mangox 2.0 rebuild.
> Covers every screen, feature, integration, quirk, and hard-coded constant.
> File references point at the v1 repo for archaeology.

---

## 1. What Mangox Is

A local-first SwiftUI iOS **cycling training app** with:
- Indoor smart-trainer rides (BLE FTMS control: ERG / simulation / resistance / free)
- Outdoor GPS rides with maps, GPX following, and turn-by-turn navigation
- A 4-tier AI coach (on-device Foundation Models → Private Cloud Compute → third-party LLM → Mangox Cloud)
- AI-generated multi-week training plans + built-in plan library
- Training analytics (PMC: CTL/ATL/TSB, power curves, critical power, aerobic decoupling)
- Cross-sport activity logging (manual + WHOOP + Strava imports) — *the seed of "more sports" in 2.0*
- Social sharing (Instagram story cards, Strava upload)
- Supabase cloud backup/sync (opt-in), RevenueCat subscriptions

**Architecture:** single Swift module, feature folders with `Domain/Data/Presentation` layering, `DIContainer` for services/ViewModels, SwiftData persistence, dark-mode-only design system ("mango" #FFB31A brand). Tabs: Home · Workouts · Coach · Stats · Settings, plus a floating Ride FAB (Indoor/Outdoor).

---

## 2. App Shell & Navigation

- **Entry** (`MangoxApp.swift`): onboarding gate via `hasCompletedOnboarding` UserDefault; in-app launch splash (wordmark + dots, dismissed after 900ms); forced dark scheme; global UITabBar styling.
- **ContentView**: 5-tab TabView, each tab with its own NavigationStack. Coach/Stats/Settings are **lazy-loaded** (only on first tap, or prewarmed 650ms after splash fades).
- **Routing** (`AppRoute.swift`): enum routes — connection/ride setup, dashboards (indoor/outdoor/plan/custom-workout), FTP setup/test, workout summary, paywall, calendar, PMC, AI plan detail, logged activities (list/form/detail), day summary studio, plus a temp `.storyCardDebug` route marked for removal.
- **Deep links**: `mangox://auth-callback` (Supabase), `mangox://ride/indoor/live` and `/outdoor/live` (Live Activity tap — deliberately never clears the nav stack so the active ride isn't restarted).
- **Lifecycle hooks**: on active — settings backfill, plan progress cleanup migration, missed-key-workout notification check, cloud sync; on background — ride checkpoint persistence, reschedule evening preview notification.
- **Quirks**: indoor ViewModel is retained across deep links to avoid restarting WorkoutManager; map prewarm behind feature flags (`allowsAppShellMapPrewarm` default off, `allowsOutdoorMapPrewarm` default on/one-shot).

---

## 3. Onboarding

9-page TabView flow: Welcome → Bluetooth → HealthKit → Notifications → Location → Strava (optional) → Rider profile → Cloud backup (optional email+OTP) → Done.

- Permission pages poll for grant (BLE 30×250ms, Location 40×250ms) then auto-advance regardless.
- Rider profile: name (50-char cap), weight slider with metric/imperial toggle (×2.20462), birth-year wheel (1940 → currentYear−16), optional photo (`RiderProfileAvatarStore`, local-only).
- Strava pre-fills display name if field empty and connected.
- Cloud page: passwordless email OTP (auto-submit at full code length, resend cooldown), immediate sync after sign-in.
- Reduce Motion: all animations skip/instant.
- Ambient gradient accent changes per page.

---

## 4. Home

Dashboard (`HomeView`): time-based greeting + rider name, **Training Status Card** (CTL, weekly TSS, ACWR, 7-day TSS bars, optional WHOOP strip with recovery/RHR/HRV), next scheduled plan workout card, recent activity list (workouts + logged activities merged, top 5), AI-generated training insight line (on-device coach, deferred 350ms past launch overlay).

Quirks & constants:
- FTP prompt card if FTP unset or **>42 days** old.
- ACWR bands: <0.8 Fresh, 0.8–1.0 Building, 1.0–1.3 Optimal, 1.3–1.5 High, >1.5 Overreaching.
- TSS bar colors: <50 green, <100 yellow, <150 orange, ≥150 red; 4px min bar height.
- Training math (`HomeTrainingAggregateMath`) runs off-main on lightweight metric slices; refresh debounced 120ms.
- WHOOP refresh throttled to 4h staleness.
- Dead code: `Workout.zoneDistribution` returns hard-coded `[0.1,0.25,0.35,0.2,0.1]`, never used.

---

## 5. Indoor Rides

### Pre-ride
- `ConnectionView`: BLE discovery/pairing for trainer (FTMS), HR strap, CSC sensor; RSSI display; WiFi-trainer fallback; simulator mock devices in DEBUG; `GuidedSessionCard` plan-day preview with adaptive load scale.
- First-time **ride tips onboarding prompt** ("Enable Essentials" = fueling+cadence, rare spacing / Decline).

### Recording (`WorkoutManager`, 1Hz tick)
State machine: `idle → recording ↔ paused/autoPaused → finished`.
- Auto-pause after 3s of zero power; 8s grace after manual resume.
- Per-second: displayPower/cadence/speed (1s mean; optional 3s smoothing UI-only), rolling 3/5/30s averages, lap accumulators, peak-power rings (5s/15s/30s/1m/5m/20m), live NP/IF/TSS/VI/EF/kJ, zone-seconds, goal checks, low-cadence detection (>30s under threshold, default 60rpm).
- Samples flushed to SwiftData in batches of 5.

### Trainer control (FTMS)
- Parses 0x2AD2 Indoor Bike Data, 0x2A63 Cycling Power (with crank-rev cadence derivation + uint16 rollover), 0x2A37 HR. Sanity caps: power ≤3000W, cadence ≤250, speed ≤120km/h, HR ≤250.
- Control point 0x2AD9: requestControl/reset/setTargetPower/setIndoorBikeSimulation/spinDown.
- Modes: ERG, Simulation (grade scaled by `routeDifficultyScale` default 0.5), Resistance, Free.
- 5s engage delay after start; grade updates max every 5s and only on meaningful change.
- Indoor speed: trainer-reported or computed from power (physics model; rider 75kg / bike 8kg / CdA 0.32 defaults, capped 80km/h).
- WiFi trainer: pauses ride on app background (can't survive backgrounding).

### Guided sessions (`GuidedSessionManager`)
Flattens plan-day intervals (incl. repeats/recoveries) into a timeline; per-step target watt range (scaled by adaptive ERG multiplier), compliance tracking (in/below/above zone, % in-zone), automatic trainer mode switching per step, 10s countdown audio cue, motivational messages, AI pre-ride briefing toast.

### Dashboard UX
Two pages: RIDE (power hero + zone strip + HR mini + goals) and DETAILS (charts, NP/IF/TSS grid, laps, trainer control). Milestone celebrations (every 5km; 25/50/75/100% of distance goal) with confetti + optional sound; goal-completion toasts; low-cadence banner; end-confirmation dialog.

---

## 6. Outdoor Rides

- **Setup**: free ride, GPX follow (file import), or turn-by-turn navigate (MKLocalSearchCompleter destination search, NavigationService routing).
- **Live**: full-screen map (two-column on iPad) with breadcrumb trail (frozen chunks + live tail, speed-colored), route polylines (completed/remaining/lookahead), nav HUD (instruction, distance, icon), compact stat card (speed hero, distance, duration, HR, power, cadence).
- **Map render budget** scales with zoom: 320→90 route points, 220→80 breadcrumb points.
- Auto-pause on sustained low speed; auto-lap every N meters (default 1000m, 0=off); elevation gain filtered (only +ΔZ above threshold) to kill GPS jitter.
- **Crash resilience**: `PersistedRideCheckpoint` JSON (breadcrumbs, laps, metadata) restored on relaunch; failed saves stash an `OutdoorRideDraft` in UserDefaults and retry on next foreground.
- CSC sensor optional (wheel circumference default 2.096m); GPX privacy trim (start/end meters).

### In-ride smart tips (`RideNudgeEngine`)
Curated, pre-written nudges (no free-form AI claims). 6 tips across categories (recovery, fueling, cadence, posture, heat/fluids) with eligibility predicates + layered cooldowns: global 240s × spacing multiplier (rare 1.45 / normal 1.0 / more 0.72), per-category 20min, per-tip 9–32min, max-per-session caps, 5.5s suppression after milestone toasts. Defaults: enabled, rare spacing, essentials categories (fueling+cadence); audio off.

### Live Activity / Dynamic Island (`MangoxLiveActivityExtension`)
ContentState: speed, distance, duration, startedAt, HR/power/cadence (+zone IDs), next turn, units, isPaused, mode label (Indoor/Outdoor/Route/Navigate). Lock screen with zone strip + gradient accent bar; expanded/compact/minimal island variants (priority HR > power > speed). Publish every 5s recording / 15s idle, min 1s between updates, 30s stale window. Zone colors hard-coded in the extension (no live theming).

---

## 7. Post-Ride: Workout & Summary

- **Workout** SwiftData model: full metrics (NP/IF/TSS, kJ, elevation), 1Hz `WorkoutSample`s + `LapSplit`s (cascade delete), plan linkage (`planDayID`/`planID`), route metadata, origin (recorded/imported with .fit/.tcx/.zwo), RPE (0 sentinel = unrated), notes, smart title.
- **SummaryView**: hero stats, zone breakdown (power + HR; Karvonen or %max), laps, power graph, PR celebration toast, on-device AI ride title/insight (skeleton while generating; nil on failure — no placeholder), photo, Strava upload (configurable description), HealthKit save, privacy flags (hide route/power/HR).
- **NP algorithm**: O(1) ring buffer over rolling 30s window; <30 samples falls back to simple average; tested against O(n²) reference ±0.01W.
- **Personal records**: MMP at 5s/30s/1m/5m/10m/20m/30m/60m, W/kg, cross-workout PRs.
- Minimum valid workout: **60s**. Duration = active time only (pauses excluded). Outdoor rides without power show NP/TSS = 0 (no estimation).
- Export: FIT/TCX/GPX. Import: .fit/.tcx/.zwo (extension-based detection). `WorkoutRAGChunk` stores embeddings of notes/insights for coach RAG.
- Deleting a plan-linked workout un-marks the plan day.

---

## 8. Training Plans & FTP

- **Screens**: TrainingPlanView (active plan, weekly compliance, ICS export, reset/delete), CalendarView (month/list, 5-year window, 12k row cap, origin filters, day-summary share), FTPTestView, FTPHistoryView.
- **Model**: `TrainingPlan → PlanWeek (phase, TSS range, hours) → PlanDay (type, zone, intervals, isKeyWorkout, requiresFTPTest) → IntervalSegment (repeats, cadence range, trainer mode, sim grade)`. Resilient decoding for LLM output (snake_case enums, alternate TSS-range shapes).
- **Compliance** (`PlanWeekCompliance`): planned vs actual TSS, key-session completion (optional-day key workouts don't count as mandatory), Mon–Sun weeks (firstWeekday=2).
- **PlanCritic** (mirrored client + server): ≤15% week-over-week TSS jump, ≥1 rest day/week, key-session spacing, taper sanity. Zone IF table: Z1 .50, Z2 .65, Z3 ~.80, Z4 .95, Z5 1.12.
- **Adaptive load**: ERG multiplier 0.88–1.08, 4% decay per ride, driven by actual/planned TSS ratio + TSB + decoupling; indoor plan-linked rides only.
- **FTP test**: warm-up (50→65→80% ERG) → 5-min clear → 20-min free-ride test → cooldown; result → `PowerZone.setFTP()` → `FTPRefreshTrigger` invalidates PMC. FTP default 265W, floor 100W. Zones Z1–Z5: 0–55/55–75/75–87/87–105/105%+ FTP.
- Plan reminders via local notifications; evening preview notification rescheduled on background.
- Known issue: plan start date stored as calendar date — timezone drift unhandled.

---

## 9. Fitness Analytics (Stats tab)

- **PMChartView**: interactive PMC (CTL/ATL/TSB toggle lines, date scrubber, sticky TSB pill), range 30/60/90/180/365d, power curve (log-scaled, tap-inspect), FTP timeline.
- PMC includes **logged-activity TSS** (multi-sport contribution) alongside rides; 180-day warm-back before visible window for CTL stability; rebuild debounced 64ms; off-main-actor on Sendable snapshots; power curve capped at 600 workouts (footnote when hit).
- **TrainingMath** (also exposed as coach tools): PMC trend (14/28d deltas), PMC projection, plan forward simulation, aerobic decoupling trend (last 12 rides), power curve summary, critical power CP/W′ fit, health readiness (WHOOP + HK sleep/RHR).
- HealthKit: resting/max HR, DOB, VO2 max; one auth attempt per launch, then cached UserDefaults (graceful degrade). Max-HR fallback 220−age (clamped 100–185). HR zone methods: %max or Karvonen.

---

## 10. AI Coach

### Chat routing — 4-tier fallback (`AIService.sendMessage`)
1. **On-device narrow** (Foundation Models): short factual/stats turns (~400-char heuristic), ~1200-char fact-sheet replies, full local tool access, no photos. Prompt version `narrow = 8`.
2. **Private Cloud Compute** (iOS 27 dynamic profiles): agent modes statsNarrow / planDeep / generalCoach / pccWebSearch; photos supported; suggested actions, follow-up blocks, thinking steps, tags. Locale + quota gated.
3. **Third-party LLM fallback** (Anthropic/Google via SPM): keys in Keychain (`mangox_coach_anthropic_api_key` / `..._google_...`), Settings-selectable.
4. **Mangox Cloud backend** (`/api/chat/stream`, SSE): last resort; the only path that counts against the **5 free messages/day** (Pro unlimited; staff bypass via Info.plist `MangoxCoachStaffTier`); handles web search until PCC's `Extension.webSearch` ships (absent from iOS 27 beta-1 SDK — the blocker for backend retirement).

Pipeline details: 50ms stream-display throttle; `<think>` tag parsing → "Thinking…" status; store-before-display commit to SwiftData; caps of 4 suggested actions / 3 follow-up blocks / 3 thinking steps; user context (FTP, HR, PMC, WHOOP, power curve, plan progress, ride digests…) encrypted AES-256-GCM with `USER_DATA_KEY` — RELEASE refuses plaintext, DEBUG allows fallback. Photos never reach Mangox Cloud.

### On-device tools (digests cached per session)
Recent workouts, rider profile, FTP history, WHOOP recovery, active plan, decoupling trend, power curve, critical power, plan forward sim, PMC projection, Spotlight local search.

### Plan generation
Entry: chat tool-call confirmation banner (inline, not a sheet — avoids SwiftUI multi-sheet conflicts; normalizes user dates via ISO/US/EU/DataDetector), plan-builder quick start, or regenerate-from-saved (inputs persisted in `AIGeneratedPlan.regenerationInputsJSON`).
Path: on-device/PCC skeleton→parallel weeks (prompt `pccPlan = 2`) → cloud streaming fallback (`/api/generate-plan/stream` SSE: skeleton/weeks/validating/assembling/complete) → non-streaming POST as final fallback. PlanCritic validates; celebration UI shows warnings + forward PMC impact + which weeks used fallback. Pro limit: **8 AI plans/month** (hard-coded in paywall copy).
Also: single-workout generation tool with confirm-then-save-to-templates flow.

### UX & persistence
`CoachConversationView` (streaming chat, delivery-tier badge, contextual quick prompts, photo attach, plan intake banner), `CoachSessionsSheet` (list 400, search, bulk delete), Coach hub (recent sessions, plan/workout libraries). SwiftData: `ChatSession` (auto 5-word title), `CoachChatMessage` (JSON-blob fields for actions/blocks/steps/tags/references, image data, feedback score), `AIGeneratedPlan`.

### Backend package (`backend/coach`, TypeScript)
JSON-only output contract, fitness-tool Zod schemas mirroring iOS tools, server PlanCritic, JSON extraction/fence-stripping, SSE helpers, stats-fallback copy. Runs on Cloudflare Workers (KV for rate limit + usage; OPENAI/ANTHROPIC/REVENUECAT secrets). **Slated for deletion** once PCC web search ships.

---

## 11. Activity Log (multi-sport — the 2.0 expansion seed)

- **21 activity types**: run, walk, hike, swim, rowing, climbing; 4 strength variants; yoga/pilates/mobility; soccer/basketball/tennis/padel/boxing/martial arts; HIIT/crossfit/other (custom label).
- **Sources**: manual form (type, date, duration ≥60s, intensity band, RPE, type-conditional metrics, notes), **WHOOP import** (sport-id map; cycling ids {1,63,64,65,126} skipped; strain, kJ, 6-bucket HR-zone millis), **Strava import** (sport-type map; all cycling types skipped; optional streams enrichment → HR-zone distribution at 60–100% max-HR breakpoints + best-km split).
- Import cursors: most recent imported date per source, else 30 days back; 4-hour stale cooldown (single shared key); pull-to-refresh runs both imports in parallel; dedup via `(source, externalID)`.
- Imported entries: notes + RPE editable, source metrics frozen, deep link back to WHOOP/Strava.
- **TSS estimation** (`LoggedActivityTSSEstimator`): strength via RPE curve, cardio via HR zones + duration, else intensity band — feeds PMC and Home load.
- Persistence quirk: SwiftData record uses sentinels (−1 for Double-nil, 0 for Int-nil).
- v1 out-of-scope (2.0 candidates): coach reading logged activities, Apple Health import source, unified cross-sport fatigue model, pull-sync.

---

## 12. Social

- **Instagram Story Studio**: 9 templates × 7 visual styles, 1080×1920 Core Graphics export with direct low-resolution template thumbnails, pick-4 metric slots, accent from dominant power zone or mango, preset/custom-photo/clean atmospheric backgrounds, optional WHOOP recovery stripe; custom photos remain recognizable under a restrained editorial wash and are session-only (the source resets to a preset when reopened); session-kind auto-detection (outdoor if route/elevation >50m; indoor if ≥60min and ≤25m elevation); 220ms debounced preview re-render; editable on-device AI caption/title with stats-only fallback; direct Instagram sharing restores the caption to the clipboard after Instagram consumes the image payload, while system-share fallbacks include the caption as a share item; optional movable-card Instagram share, 3-image share set, and 3-second MP4 export (Facebook App ID `986008587288900` for source attribution).
- **Strava**: OAuth via Supabase edge function (secrets server-side), token in Keychain, upload as Ride/VirtualRide with `StravaPostBuilder` captions + photos, 15-min rate-limit header tracking, stream fetching (both array and keyed formats).
- **Day Summary Studio** (`.daySummaryStudio(date:)`): day recap card combining rides + logged activities, with the same session-only photo handling, orientation correction, save feedback, and Instagram/system-share fallback behavior as Workout Stories (multi-image export remains planned, post-v1).

---

## 13. Design System (`Core/UIComponents`)

- **Theme**: dark-only; bg0–bg4 canvas, fg0–fg4 text tiers, hair/hair2/hair3 hairlines; mango #FFB31A (+dim/glow); semantic colors incl. brand strava/whoop/discord; zone color mapping on `TrainingZoneTarget`; `tint()` 12% / `wash()` 8% helpers.
- **Motion tokens** (`MangoxMotion`): press 120ms → pulse repeatForever, named springs for entrance/exit/sheet/bouncy; Reduce Motion respected app-wide.
- **Surfaces** (`MangoxSurface`): frosted (ultraThinMaterial + bg4@72%, falls back flat under Reduce Transparency), frosted-interactive, flat, flat-subtle, map-overlay.
- **Buttons**: hero/primary/secondary/icon/map-icon/end (red)/destructive/plain.
- **Components**: MetricCard, SectionLabel, StatusPill, ConfirmOverlay, Skeleton, ErrorBanner, EmptyState.
- **A11yL10n**: centralized VoiceOver strings (`feature.a11y.key`); migration from hard-coded strings unfinished.
- **Liquid Glass** (iOS 26+): reserved for control/nav layers only; rollout Home → Connection → Dashboard → Summary; keep numeric data opaque/high-contrast.

---

## 14. Persistence, Sync & Backend

### SwiftData schema
`Workout`, `WorkoutSample`, `LapSplit`, `WorkoutRAGChunk`, `CustomWorkoutTemplate`, `ChatSession`, `CoachChatMessage`, `AIGeneratedPlan`, `FitnessSettingsSnapshot`, `TrainingPlanProgress`, `LoggedActivityRecord`. Single container; in-memory for tests/previews. Simulator demo seeder (DEBUG+simulator, `debug.seedSimulatorData`/`resetSimulatorData`, versioned `2026-04-19-v1`).

### Local-first sync (Supabase)
- Optional sign-in (email OTP primary; Apple required; Google optional). Nothing leaves device until signed in.
- `SyncCoordinator`: domain protocol (push + optional pull), per-domain cursors, 1.5s debounced push on local change, full push-then-pull on `syncNow()` (linked-OAuth pull first to restore tokens). Sign-out keeps local data, clears cursors; re-sign-in merges via `client_id` idempotent upsert.
- Domains: workouts, chat, AI plans, zone snapshots, custom templates, logged activities (push-only v1), linked OAuth.

### Supabase schema (project `jvhkplgacbeuksiphgyk`, Postgres 17.6)
Tables: profiles, user_settings, zone_snapshots, workouts (+samples +laps), workout_rag_chunks (`vector(1536)`, OpenAI text-embedding-3-small, IVFFlat lists=100), custom_workout_templates, ai_generated_plans, training_plan_progress, goals, chat_sessions, chat_messages, linked_oauth_accounts (AES-256-GCM payloads). Views/RPCs: `v_workout_overview`, `v_daily_training_load`, `match_workouts()`, `get_user_context()`. RLS everywhere (`user_id = auth.uid()`). Migration-history mismatch workaround script exists.

### OAuth edge function
`oauth-token-exchange` proxies Strava/WHOOP code↔token (secrets server-side, redirect-URI allow-list, both grant types). Client IDs in `Config/App.xcconfig`: Strava `207587`, WHOOP `8c9a9d3d-...`. ⚠️ `USER_DATA_KEY` is **checked into App.xcconfig** (shared across builds for cross-device restore) — revisit for 2.0.

### Monetization
RevenueCat + StoreKit 2: monthly $4.99 / yearly $29.99 ("Save 50%", pre-selected). Paywall sells: structured training, AI coaching, AI plan building (8/mo), PMC, priority features. DEBUG Pro override `MangoxDevForcePro`.

---

## 15. Settings (Profile tab)

Hierarchical: Account & Cloud (backup status, sign-out) · Training (rider profile, FTP/power zones, heart rate with manual overrides) · Connections (Strava, WHOOP with sync-recovery-to-zones toggle) · Ride settings (trainer, outdoor, BLE sensors, gear labels, audio & haptics) · AI & Analytics (provider, third-party fallback model + API key, daily limit status, encryption key status, Pro upsell) · Data & privacy (notifications, ICS calendar export, full data export ZIP, wipe-everything with cascade + disconnects).

Quirks: manual HR overrides block HealthKit/WHOOP auto-sync; WHOOP lacks VO2 max (UI points to Apple Health); weight masking eye-toggle in identity card.

---

## 16. Quirk Compendium (don't-lose-these list)

| Constant / behavior | Value |
|---|---|
| FTP default / floor / re-test prompt | 265W / 100W / 42 days |
| Free coach messages (cloud only) / AI plans (Pro) | 5/day / 8/month |
| Auto-pause / resume grace (indoor) | 3s zero power / 8s |
| Trainer engage delay / grade update interval | 5s / 5s |
| Computed indoor speed cap | 80 km/h |
| Low-cadence warning | <60rpm default, >30s sustained |
| Min valid workout | 60s |
| Peak power windows | 5s/15s/30s/1m/5m/20m (records add 10m/30m/60m) |
| PMC warm-back / power-curve cap | 180 days / 600 workouts |
| Adaptive ERG multiplier | 0.88–1.08, 4% decay per ride |
| PlanCritic | ≤15% weekly TSS jump, ≥1 rest day |
| Nudge cooldowns | 240s global × spacing, 20min/category, 9–32min/tip |
| Live Activity cadence | 5s publish / 1s min / 30s stale / 15s idle |
| Import cooldown / first-run window | 4h / 30 days |
| Calendar window | 5 years, 12k rows |
| Streaming UI throttle / training refresh debounce | 50ms / 120ms |
| Demo seeder version | `2026-04-19-v1` |
| Prompt versions | narrow=8, pccPlan=2, pccGeneral=2, pccWebSearch=2 |
| WHOOP cycling sport-ids (skip on import) | 1, 63, 64, 65, 126 |
| Weeks | always Mon–Sun (firstWeekday=2) |

Sentinels: RPE 0 = unrated; logged-activity metrics −1 (Double) / 0 (Int) = nil.

---

## 17. Notes for 2.0

1. **More sports**: ActivityLog already has 21 types, source mappers, and a cross-sport TSS estimator — promote it from "log" to first-class recording (HR-based sessions for run/strength/etc.), unified fatigue model, coach awareness of non-cycling load (all explicitly out-of-scope in v1).
2. **Backend retirement**: the only remaining Mangox Cloud dependency is web search + free-tier chat; PCC web search blocked on Apple SDK. 2.0 can be designed cloud-coach-free from day one.
3. **Security**: move `USER_DATA_KEY` out of the repo/xcconfig; per-user key derivation.
4. **Module boundaries**: v1's Domain/Data/Presentation convention is unenforced — use SPM packages from the start.
5. **Known debt to not replicate**: timezone-drifting plan dates, dead `zoneDistribution`, `.storyCardDebug` route, single shared import-cooldown key, hard-coded Live Activity zone palette, unfinished A11yL10n migration.

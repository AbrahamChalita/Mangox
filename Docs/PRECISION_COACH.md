# Precision AI Coach

Phase 0 turns coach math into **first-class, callable tools**. Phase 1 adds a **closed-loop controller**: CP/W′ model, plan forward simulation, client/server critic, smarter adaptive load, and outcome instrumentation.

## Architecture

```
Coach turn
  ├─ On-device narrow path (Foundation Models + tools)
  └─ Cloud path (encrypted UserContext + worker-side tools + plan critic)

Shared pure math:
  Features/Fitness/Domain/UseCases/TrainingMath/
  Features/Training/Domain/UseCases/PlanTSSVectorBuilder.swift
  Features/Training/Domain/UseCases/PlanCritic.swift
  backend/coach/fitnessTools.ts + planCritic.ts
```

## Phase 0 — Math as tools (shipped)

| Module | Role |
|--------|------|
| `PMCProjection.swift` | Forward CTL/ATL/TSB from daily TSS or constant weekly load |
| `TrainingMath/PMCTrend.swift` | 14/28-day PMC deltas |
| `TrainingMath/AerobicDecouplingTrend.swift` | Multi-ride Pw:HR drift slope |
| `TrainingMath/PowerCurveSummary.swift` | Format best power at standard durations |

### On-device tools (Phase 0)

| Tool | Purpose |
|------|---------|
| `mangox_pmc_projection` | Constant weekly TSS simulation |
| `mangox_decoupling_trend` | Multi-ride aerobic drift |
| `mangox_power_curve_summary` | Best power 5s–1h |

## Phase 1 — Closed-loop controller (shipped in repo)

| Module | Role |
|--------|------|
| `TrainingMath/CriticalPowerModel.swift` | 2-parameter CP/W′ fit from power curve |
| `TrainingMath/PlanForwardSimulator.swift` | PMC sim for exact daily TSS vectors |
| `PlanTSSVectorBuilder.swift` | Active plan → daily TSS from tomorrow |
| `PlanCritic.swift` | Client-side plan validation before save |
| `AdaptiveTrainingAdjuster` | ERG nudges using TSB + decoupling + compliance |
| `PrecisionCoachInstrumentation.swift` | OSLog outcome hooks |

### On-device tools (Phase 1)

| Tool | Purpose |
|------|---------|
| `mangox_critical_power` | CP/W′ digest from recent MMP data |
| `mangox_plan_forward_sim` | PMC sim using active plan daily TSS |

### Encrypted cloud `UserContext` (additive fields)

- Phase 0: `currentCtl/Atl/Tsb`, `pmcTrendSummary`, `aerobicDecouplingTrend`, `powerCurveSummary`
- Phase 1: `criticalPowerSummary`

### Plan critic

- **Client:** `PlanCritic.validate` runs after `/api/generate-plan` decode; warnings merge into `PlanSaveCelebration`.
- **Server:** `backend/coach/planCritic.ts` — mirror rules for worker-side validation.

### Adaptive load (Phase 1)

`AdaptiveTrainingAdjuster` now accepts `AdaptiveLoadSignals`:

- Skips upward ERG nudges when TSB < −20 or weekly compliance < 70%
- Caps multiplier when TSB < −30 or decoupling trend is worsening + significant

### Instrumentation events (OSLog, category `PrecisionCoach`)

| Event | Hook |
|-------|------|
| `plan_generated` | After plan save + critic |
| `plan_started` | `TrainingPlanPersistenceRepository.startPlan` |
| `plan_day_completed` | Indoor auto plan completion |
| `adaptive_load` | After ERG multiplier change |
| `ftp_applied` | `FTPTestManager.applyEstimatedFTP` |
| `plan_forward_sim` | On-device plan forward tool |
| `cp_fit` | Critical power digest build |

North-star metric (6 mo): **plan compliance × FTP delta at block ends**, conditioned on decoupling trend.

## Phase 2 — Workout critic, persistence, outdoor completion (shipped in repo)

| Module | Role |
|--------|------|
| `PrecisionCoachOutcomeStore.swift` | UserDefaults-backed outcome log (500 events) |
| `WorkoutCritic.swift` | Client-side workout validation before save |
| `PlanForwardImpactSummary.swift` | PMC impact line for plan save UI |
| `PlanWorkoutCompletion.swift` | Shared indoor/outdoor plan-day completion + adaptive load |
| `backend/coach/workoutCritic.ts` | Server-side workout critic mirror |
| `mangox-backend/src/workoutCritic.ts` | Worker workout critic wired into `/api/generate-workout` |

### Outcome persistence

`PrecisionCoachInstrumentation` now writes to `PrecisionCoachOutcomeStore` in addition to OSLog. Event kinds: `planGenerated`, `planStarted`, `planDayCompleted`, `adaptiveLoadAdjusted`, `ftpApplied`, `planForwardSimulated`, `workoutGenerated`.

### Workout critic

- **Client:** `WorkoutCritic.validate` after `/api/generate-workout`; warnings shown on workout confirm banner.
- **Server:** returns `validation_warnings` on success; hard `error` severity issues return 422.

### Plan forward impact UI

`PlanSaveCelebration.forwardImpactSummary` shows projected PMC / race-day form trend after plan generation.

### Outdoor plan completion

- Route: `AppRoute.outdoorPlanRide(planID:dayID:)`
- Training plan: **Ride Outside** on commute/optional days
- `PlanWorkoutCompletion.completePlanLinkedRide` runs after outdoor ride save (source: `outdoor_auto`)

### Instrumentation hooks (updated)

| Event | Hook |
|-------|------|
| `plan_day_completed` | Indoor + outdoor auto plan completion |
| `workout_generated` | After generate_workout + critic |

## Backend helpers

`backend/coach/fitnessTools.ts` — Zod schemas for all fitness tools including Phase 1.

`backend/coach/planCritic.ts` — server-side plan validation scaffold.

`backend/coach/workoutCritic.ts` — server-side workout validation scaffold.

Run `npm run check` in `backend/` after schema changes.

## Tests

| Test file | Covers |
|-----------|--------|
| `CriticalPowerModelTests.swift` | CP/W′ fit + prediction |
| `PlanForwardSimulatorTests.swift` | Vector + plan-based sim |
| `PlanCriticTests.swift` | Key session spacing, stable load |
| `WorkoutCriticTests.swift` | Duration mismatch, recovery goal |
| `PrecisionCoachOutcomeStoreTests.swift` | Outcome event persistence |
| `PlanForwardImpactSummaryTests.swift` | Plan save impact summary |
| `PMCProjectionTests.swift` | Forward PMC |
| `AerobicDecouplingTrendTests.swift` | Decoupling trend |
| `mangox-backend/src/__tests__/workoutCritic.test.ts` | Server workout critic |

## OpenRouter (mangox-backend)

Adding `OPENROUTER_API_KEY` alone does **not** force Owl Alpha. Set:

```bash
LLM_PROVIDER=openrouter
OPENROUTER_API_KEY=...
OPENROUTER_CHAT_MODEL=openrouter/owl-alpha
OPENROUTER_PLAN_MODEL=openrouter/owl-alpha
```

Ensure `USER_DATA_KEY` matches the iOS app for encrypted `user_context`.

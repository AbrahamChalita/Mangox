# Indoor Weight Loss + General Fitness Spec

Status: Proposal (implementation-ready)
Owner: Product + iOS
Last updated: 2026-04-12

## 1) Product goal

Expand Mangox from performance-only indoor cycling into a dual-purpose experience:

1. Weight-loss users can track progress safely and consistently.
2. General fitness users can improve cardio, consistency, and recovery without race-focused complexity.

This spec keeps current strengths (FTP/TSS/plan compliance) and adds a practical body-composition layer.

## 2) Current gaps in app

Current app is strong on in-ride and performance signals, but missing key loops for fat loss and broad fitness:

- No explicit body-composition goal model (target weight, weekly target change).
- No trend-based weight tracking (daily noise smoothing, on-track detection).
- No energy-balance view connecting rides to weekly deficit/surplus.
- Ride goals are session-level (distance, duration, kJ, TSS) but not habit-level (weekly minutes, rides, strength sessions).
- No integrated strength or mobility companion layer.
- No weekly check-in loop that auto-adjusts plan load based on trend + fatigue + adherence.

## 3) Success criteria

Primary outcomes (8-12 weeks):

- More users complete at least 3 indoor sessions/week.
- Weight-goal users see stable weekly trend movement (not day-to-day swings).
- Fewer users overreach from aggressive deficits or intensity stacking.
- Improved retention via weekly check-in completion.

Guardrails:

- No medical claims.
- No unsafe deficit recommendations.
- No "perfect precision" calorie messaging.

## 4) Scope by release

### MVP (v1)

- Weight goal setup and trend graph.
- Weekly energy estimate and on-track status.
- Weekly adherence dashboard (rides, minutes, zone 2 minutes).
- Two indoor plan templates for weight-loss and general fitness.
- Weekly check-in with simple auto-adjust rules.

### V2

- Strength/mobility templates and completion tracking.
- Smarter adaptation with fatigue/recovery context.
- Goal-based coach prompts and nudges.
- Better projection windows and confidence ranges.

### V3

- Optional wearable-aware readiness weighting.
- Personalization by preferred training days and available session time.
- Meal timing suggestions (non-prescriptive, educational only).

## 5) Data model changes

## 5.1 New entities (SwiftData)

### WeightGoalProfile

- `id: UUID`
- `isEnabled: Bool`
- `goalType: String` (`fat_loss`, `recomposition`, `fitness`)
- `startWeightKg: Double`
- `targetWeightKg: Double?`
- `targetWeeklyChangeKg: Double` (negative for loss; clamp safe range)
- `dailyEnergyTargetDeltaKcal: Int` (derived recommendation, not strict prescription)
- `createdAt: Date`
- `updatedAt: Date`

### BodyWeightEntry

- `id: UUID`
- `date: Date` (start of day)
- `weightKg: Double`
- `source: String` (`manual`, `healthkit`)
- `note: String?`

### WeeklyFitnessCheckIn

- `id: UUID`
- `weekStartDate: Date`
- `weightTrendDeltaKg: Double`
- `estimatedWeeklyEnergyDeficitKcal: Int`
- `completedRides: Int`
- `completedZone2Minutes: Int`
- `completedStrengthSessions: Int`
- `fatigueScore: Int` (1-5 self-report)
- `sleepQualityScore: Int` (1-5 self-report)
- `adjustmentApplied: String?`
- `createdAt: Date`

### WeeklyHabitTargets

- `id: UUID`
- `weekStartDate: Date`
- `targetRideCount: Int`
- `targetZone2Minutes: Int`
- `targetStrengthSessions: Int`
- `targetMobilitySessions: Int`
- `targetActiveDays: Int`

## 5.2 Existing model extensions

### Workout

No schema change required for MVP. Reuse existing:

- `duration`
- `tss`
- `avgPower`
- `normalizedPower`
- indoor `kilojoules` from `WorkoutManager` for summary aggregation logic.

Optional later:

- `estimatedCaloriesBurned` denormalized for query speed.

### RidePreferences

Add preference keys for:

- `weightGoalNotificationsEnabled`
- `weeklyCheckInReminderDay`
- `weeklyCheckInReminderTime`
- `showWeightTrendOnHome`

## 5.3 Persistence and migration

- Add schema migration with safe defaults (`isEnabled = false`).
- Keep feature dormant until user opts in.
- Backfill weekly aggregates from recent workouts on first launch after migration.

## 6) Metrics and algorithm rules

## 6.1 Weight trend (noise reduction)

Use smoothed trend, not raw daily delta:

- Rolling 7-day average (or EWMA equivalent).
- Compare week-over-week trend average.
- Mark `insufficient_data` if fewer than 4 entries in 14 days.

## 6.2 Energy estimate (practical, not clinical)

Estimated weekly deficit:

`weeklyDeficit = estimatedExerciseEnergy - estimatedCompensation`

MVP assumptions:

- Exercise energy from workout kJ (cycling conversion approximation).
- Conservative compensation factor to avoid over-crediting exercise.
- Display as range, not exact single-value certainty.

UI language:

- "Estimated range"
- "Use trend + consistency over day-to-day changes"

## 6.3 Safety bounds

Clamp recommended target weekly change:

- Fat loss: `-0.75 ... -0.20 kg/week`
- Recomposition: `-0.25 ... +0.10 kg/week`
- Fitness: no weight-change target required

If trend exceeds pace (too fast loss), suggest recovery and intake normalization.

## 6.4 Weekly adaptation rules (MVP deterministic)

Inputs:

- Trend status (`ahead`, `on_track`, `behind`, `insufficient_data`)
- Adherence status (habit targets met or not)
- Fatigue and sleep self-report

Outputs (single weekly adjustment):

- `hold`
- `add_zone2_15_to_30_min`
- `remove_intensity_session`
- `add_recovery_day`

Example rules:

- If `behind` + low fatigue + high adherence: add 20 min zone 2 to 2 sessions.
- If `ahead` + high fatigue: reduce intensity by 1 session and hold volume.
- If low adherence: no load increase; simplify plan first.

## 7) UI and UX changes

## 7.1 New/updated screens

### Goal setup flow

Add a "Body goals" setup card in Settings -> Rider Profile and optional first-run prompt:

- Goal type picker (fat loss, recomposition, fitness).
- Current weight and optional target weight.
- Preferred weekly pace.
- Habit baseline (days available/week, strength yes/no).

### Home cards

New cards:

- `Weight Trend`: 4-week trend sparkline + status chip.
- `Weekly Energy`: estimated range and confidence.
- `Adherence`: rides, zone 2 minutes, strength sessions.

### Fitness tab enhancements

Keep PM chart, add parallel "Body + Habits" section:

- Trend line (weight avg).
- Weekly adherence bars.
- Check-in history list.

### Weekly check-in sheet

Simple modal every 7 days (dismissible):

- Current trend summary.
- Fatigue (1-5), sleep quality (1-5), confidence (1-5).
- One recommended adjustment + apply button.

## 7.2 In-ride integration

Keep current ride goals, add optional habit-oriented target hints pre-ride:

- "This week: 2/4 rides"
- "Zone 2 minutes remaining: 48"

Do not show weight-loss pressure messaging during hard intervals.

## 7.3 Copy and trust tone

Use language like:

- "estimated"
- "trend"
- "on track this week"

Avoid:

- "guaranteed fat loss"
- strict calorie prescriptions
- medical directives

## 8) Plan templates (MVP)

Add template family under Training:

1. `Indoor Fat-Loss Base (3x/week)`
   - 2x zone 2 steady sessions
   - 1x short tempo/interval session
2. `Indoor Fitness Builder (4x/week)`
   - 2x zone 2
   - 1x threshold-lite
   - 1x optional skills/cadence ride

Each plan includes:

- weekly habit targets
- optional strength placeholders (off-bike)
- clear progression and deload weeks

## 9) Technical integration map

Likely touchpoints:

- `Mangox/Features/Profile/Presentation/View/SettingsDetailViews.swift`
- `Mangox/Features/Profile/Presentation/View/SettingsView.swift`
- `Mangox/Features/Fitness/Presentation/View/PMChartView.swift`
- `Mangox/Features/Fitness/Presentation/ViewModel/FitnessViewModel.swift`
- `Mangox/Features/Indoor/Presentation/View/ConnectionView.swift`
- `Mangox/Features/Workout/Data/PersistenceModels/Workout.swift`
- `Mangox/Core/Persistence/PersistenceContainer.swift`

New files (proposed):

- `Mangox/Features/Fitness/Data/PersistenceModels/WeightGoalProfile.swift`
- `Mangox/Features/Fitness/Data/PersistenceModels/BodyWeightEntry.swift`
- `Mangox/Features/Fitness/Data/PersistenceModels/WeeklyFitnessCheckIn.swift`
- `Mangox/Features/Fitness/Domain/UseCases/WeightTrendAnalytics.swift`
- `Mangox/Features/Fitness/Domain/UseCases/WeeklyAdjustmentEngine.swift`

## 10) Analytics events

Track (privacy-safe, no raw health payloads):

- `weight_goal_enabled`
- `weight_entry_logged`
- `weekly_checkin_completed`
- `weekly_adjustment_applied`
- `habit_target_met`

## 11) QA acceptance criteria

- Weight trend shows stable values with sparse input (no extreme jump visuals).
- Weekly adjustment never applies contradictory actions.
- Safety clamps enforce valid weekly pace bounds.
- Feature remains hidden/neutral when user has not enabled body goals.
- Existing indoor workout flow and PM chart remain unaffected.

## 12) MVP implementation sequence

1. Add SwiftData entities + migration.
2. Add analytics/use-case layer (`WeightTrendAnalytics`, `WeeklyAdjustmentEngine`).
3. Add settings flow for body goals and manual weight entry.
4. Add home + fitness cards for trend/adherence.
5. Add weekly check-in sheet and recommendation apply action.
6. Add two template plans and habit targets.
7. QA + tuning pass.

## 13) What this does not do (yet)

- No meal logging system.
- No macro tracker.
- No advanced metabolic adaptation model.
- No clinical guidance.

This keeps MVP focused, safer to ship, and aligned with Mangox's current training-first architecture.

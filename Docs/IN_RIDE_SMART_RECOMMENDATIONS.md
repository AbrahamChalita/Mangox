# In-ride smart recommendations — design doc

**Status:** Draft for implementation  
**Owner:** Product + iOS  
**Last updated:** 2026-04-08  

## 1. Summary

Add **optional, sparse, context-aware nudges** during indoor (and optionally outdoor) rides: short text ± optional audio, triggered by **measurable ride state** and a **small curated library** of copy. “Smart” means **prioritization and timing**, not free-form AI claims about physiology.

**Non-goal:** Real-time LLM-generated “science” explanations during the ride (hallucination and App Store / trust risk).

---

## 2. Goals

1. **Usefulness:** Help riders with timing and habits that are broadly aligned with endurance training practice (cadence, fueling reminders, recovery cues, heat/fluid awareness).
2. **Trust:** Every shown tip is **pre-written**, **versioned**, and optionally linked to **static** “why we say this” references (general sources, not personalized medical advice).
3. **Respect attention:** Defaults are **quiet**; aggressive modes are opt-in; strong **cooldowns** prevent nagging.
4. **Fit the codebase:** Reuse **1 Hz** session state (`WorkoutManager`), **audio** (`AudioCueManager`), **prefs** (`RidePreferences`), and existing patterns (e.g. low-cadence banner).

## 3. Non-goals

- Diagnosing injury, prescribing hydration for medical conditions, or replacing a coach.
- Using live model output to assert “studies show …” without human-curated backing text.
- Guaranteeing performance outcomes.

## 4. Design principles

| Principle | Implication |
|-----------|-------------|
| **Signal-first** | A nudge fires only when defined thresholds on real signals are met (or time-based with session context). |
| **Curated copy** | All user-visible strings live in a **Tip Library** (Swift structs or localized strings + IDs). |
| **Cooldowns** | Global and per-category minimum gaps between nudges (e.g. 3–8 minutes depending on severity). |
| **One channel default** | Prefer **in-UI banner or compact toast**; audio only if “Ride tips audio” is enabled (separate from step/navigation cues where helpful). |
| **Transparency** | Settings screen lists categories and what triggers them (plain language). |
| **Science posture** | UI copy: “General training tip” / “Many riders find …”; detailed citations in **Learn more** sheet, not in a 2-second toast. |

---

## 5. Personas & scenarios

- **Free indoor ride, distance goal:** Mid-ride fueling reminder after ~60–90 min steady work (if no pause).
- **Guided workout:** Avoid duplicating `GuidedSessionManager` motivational strings; only add tips when **not** covered (e.g. fueling, posture) or when **explicitly** in “free ride after plan” segment.
- **Low cadence habit:** Complement existing **Low Cadence Warning** (30 s below threshold) with a **one-time** softer hint earlier or a spoken line if audio enabled — **coordinate** so we do not double-fire the same second.
- **Long Z2 / steady endurance:** Occasional “check in” (breathing, upper body relaxation) — low frequency.

---

## 6. Signal inventory (what we can know today)

Relevant existing or easily derived signals (indoor unless noted):

| Signal | Source (today) | Notes |
|--------|----------------|--------|
| Recording / paused / auto-paused | `WorkoutManager.state` | Suppress nudges when not `.recording` (or allow “resume”-only class — TBD). |
| Elapsed active time | `elapsedSeconds` | For time-based fueling / duration cues. |
| Distance | `activeDistance` | Milestone system already exists; avoid collision with milestone toasts (cooldown or shared coordinator). |
| Power, zone | `displayPower`, `PowerZone` | Zone-aware templates (e.g. Z1–Z2 vs threshold). |
| Cadence (1 s avg) | `WorkoutManager` tick / formatted cadence | Align with `lowCadenceWarning` logic. |
| Heart rate | From metrics when available | Optional: HR present vs missing; future: drift vs session average (needs spec + validation). |
| Guided session | `GuidedSessionManager` | `isActive`, current step zone, recovery vs work, `motivationalMessage` — **de-duplicate**. |
| Goals | `RidePreferences.activeGoals` | e.g. long duration + distance goal → slightly more fueling emphasis (optional v2). |

**Gaps (v2+):** indoor temperature, sweat rate, user-reported “easy indoor fan” flag, outdoor heat index — could add simple prefs later.

---

## 7. Tip Library (content model)

### 7.1 Data shape (conceptual)

Each **TipDefinition** includes:

- **`id`:** Stable string, e.g. `fueling_60min_steady`.
- **`category`:** `Fueling` | `Cadence` | `Posture` | `Recovery` | `HeatFluids` | `General` (extensible enum).
- **`priority`:** Int — higher wins when multiple eligible same tick (only one fires).
- **`trigger`:** Declarative rule (see §8).
- **`copy`:** Title (optional) + body (1–2 short sentences max for on-screen).
- **`audioScript`:** Optional shorter phrase for TTS (may differ from on-screen).
- **`learnMoreURL` or `learnMoreMarkdownResource`:** Optional; opens sheet or Safari.
- **`audience`:** `.indoorOnly` | `.outdoorOnly` | `.any` (phase 1: `.indoorOnly` acceptable).

### 7.2 Example entries (draft copy — edit before ship)

| ID | Category | Rough trigger | On-screen (example) |
|----|----------|---------------|---------------------|
| `fueling_steady_75m` | Fueling | ≥75 min active, Z2–Z3-ish average recent zone, not fired this session | “Long steady block — if you’re going 90+ minutes total, consider a sip of fuel on schedule.” |
| `cadence_torque_soft` | Cadence | Cadence &lt; user threshold − margin for &gt;20 s while power &gt; X W (below existing 30 s hard warning) | “If the legs feel heavy, a slightly quicker spin can ease torque — find what feels sustainable.” |
| `posture_relax_grip` | Posture | Every 45–60 min, random jitter, max N times per session | “Light grip on the bars, soft elbows, weight through the core.” |
| `recovery_spin` | Recovery | Guided recovery step or free ride Z1 + cadence available | “Recovery: easy spin, nasal breathing if comfortable.” |
| `fluids_indoor_long` | HeatFluids | ≥45 min indoor, optional “indoor heat” user pref | “Indoor heat adds up — small sips beat chugging later.” |

**Legal / medical:** Run final strings past App Store / compliance comfort; avoid disease claims.

---

## 8. Trigger language (implementation-facing)

Define triggers as **composable predicates** evaluated on a **NudgeContext** snapshot each second (or every K seconds to save CPU — start with 1 Hz aligned with `WorkoutManager` tick).

Examples:

- `elapsedActive >= duration(75 * 60)` AND `rollingAvgZone in [.z2, .z3]` AND `not fired(fueling_steady_75m)`.
- `cadenceBelow(rpm: threshold - 5, minSeconds: 20)` AND `powerAbove(watts: 120)` AND `not showLowCadenceWarning` (avoid overlap) — **requires careful ordering**.
- `sessionOnce(maxCount: 2)` with random offset window for posture tips.

**Session state machine:**

- `firedTipIDs: Set<String>` for current workout session.
- `lastNudgeAt: Date?` and `lastNudgeCategory: Category?` for cooldowns.
- Reset on `idle → recording` (match milestone reset pattern in `DashboardView`).

**Cooldown policy (defaults — tune in QA):**

- **Global:** Minimum **180 s** between any two nudges (except critical safety class — we may have none in v1).
- **Per category:** e.g. Posture **≥ 20 min** since last posture tip.
- **Same tip ID:** Once per session unless explicitly “repeat allowed” (probably never in v1).

---

## 9. UX specification

### 9.1 Surface

- **Primary:** Compact **banner** below header or above controls (similar visual weight to `cadenceWarningBanner` in `DashboardView` — distinct color token, e.g. blue/slate not orange warning).
- **Secondary:** Optional **toast** style (reuse milestone chrome pattern only if it does not clash with distance milestones — prefer **separate** styling to avoid confusion).
- **Audio:** Optional; setting **“Spoken ride tips”** (new pref). Shorter script; respect `AudioCueManager` debouncing and ducking.

### 9.2 Actions

- **Dismiss** (tap or auto-dismiss 6–10 s).
- **“?” or “Why”** opens **Learn more** (static content only).

### 9.3 Conflicts

- **Milestone toasts / goal % toasts:** Global nudge coordinator **or** shared minimum spacing (e.g. if milestone visible in last 5 s, defer nudge).
- **Guided step countdown / audio:** Defer non-critical nudges if `GuidedSessionManager` is about to play 10 s cue (optional v1.1).

---

## 10. Settings

Add a **Ride tips** subsection (e.g. under existing ride / audio settings in `SettingsDetailViews`):

| Control | Type | Default |
|---------|------|---------|
| Enable ride tips | Toggle | **Off** (conservative) or **On** — product call |
| Categories | Multi-toggle or “Essentials / All” | Essentials = Fueling + Cadence-related only |
| Spacing | Segmented: “Rare / Normal / More” | Maps to global cooldown multipliers |
| Spoken ride tips | Toggle | Off |
| Indoor heat awareness | Toggle | Off — gates `HeatFluids` tips |

**Accessibility:** Respect Reduce Motion (no extra animation); VoiceOver labels on dismiss and “Learn more”.

---

## 11. Architecture (proposed)

1. **`RideNudgeEngine`** (new, `@MainActor`, or methods on existing manager):  
   - Input: `NudgeContext` built from `WorkoutManager` + `RidePreferences` + `GuidedSessionManager?`.  
   - Output: `RideNudgeEvent?` (tip ID + presentation payload).

2. **`TipLibrary`:** Static array or generated from a plist/JSON bundled in app (easier for copy edits without recompiling logic).

3. **Wiring:**  
   - From `WorkoutManager`’s 1 Hz path **or** `DashboardView.onChange(of: elapsedSeconds)` — prefer **one** place to avoid double evaluation.  
   - Publish `currentNudge: RideNudgeEvent?` via `@Observable` on `WorkoutManager` or small `@Observable` holder injected in environment.

4. **Analytics (optional):** `tip_shown`, `tip_dismissed`, `learn_more_opened` with `tip_id` — privacy policy update if added.

**Module placement:** `Services/RideNudgeEngine.swift` + `Core/Models/RideNudge*.swift` per `Docs/MODULES.md` (services use Core, not Features).

---

## 12. Phased rollout

| Phase | Scope |
|-------|--------|
| **P0** | Data model + engine + 3–5 tips + banner UI + prefs master toggle + cooldowns; indoor only. |
| **P1** | Learn more sheet + category toggles + spoken tips setting. |
| **P2** | Outdoor bike computer (if signals sufficient) + HR-aware rules (if validated). |
| **P3** | Optional: ML **ranking** only (chooses among curated tips; does not author text). |

---

## 13. Open questions

1. Default **on vs off** for first-time users? (Recommend **off** until quality bar proven, or **on “Essentials”** with very rare spacing — product decision.)
2. Should **low cadence** stay solely the existing warning, or should ride tips **subsume** part of it with one unified UX?
3. **Localization:** All strings in `Localizable.xcstrings` from day one?
4. **Testing:** Unit tests for trigger evaluation with fixed `NudgeContext` sequences.

---

## 14. References (for authors of `learnMore` sheets — not exhaustive)

Authors should attach **specific** links or short bibliographies per tip when shipping. General domains to draw from: sports nutrition timing for endurance sessions, cadence and joint loading (individual variation), indoor thermal stress and fluid intake behavior. Final wording must be **non-medical** and **non-absolute**.

---

## 15. Acceptance criteria (P0)

- [ ] No nudge fires when tips disabled or when not recording.  
- [ ] Cooldowns enforced; no more than one nudge in default global window.  
- [ ] No duplicate tip ID in one session unless spec says otherwise.  
- [ ] Milestone / goal toasts and nudges do not stack unreadably (manual QA script).  
- [ ] Guided workout: no contradictory duplicate message in same 15 s window (spot-check).  
- [ ] Settings changes apply without restart.  

---

*End of doc.*

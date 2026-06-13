# Foundation Models migration (iOS 27)

Mangox coach routing is now **on-device → Private Cloud Compute → third-party `LanguageModel` → Mangox Cloud**. This doc tracks what is shipped in-app vs what remains operational or SDK-blocked.

## Migration checklist

| Step | Status | Action |
|------|--------|--------|
| 1. Free PCC tier | Operational | Enroll via **App Store Connect → Small Business Program** (<2M first-time downloads). No code change; unlocks zero-cost PCC turns. |
| 1b. PCC entitlement | Shipped | `com.apple.developer.private-cloud-compute` in `Mangox.entitlements`. Request the capability in [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list) for your App ID before App Store submission. |
| 2. Plan generation on PCC | Shipped | `OnDevicePlanGenerator` uses `CoachDynamicProfiles.planDeep`. Cloud fallback is **off by default** while PCC is available (Settings → AI Coach). |
| 3. Third-party fallback | Scaffolded | Settings → AI Coach → **Fallback model**. Link Anthropic or Google Foundation Models SPM packages, enter API key (Keychain). Replaces `/api/chat/stream` when configured. |
| 4. PCC live web search | Blocked on SDK | Flip `MangoxPrivateCloudComputeModelFactory.sdkExposesWebSearchExtension` when `Extension.webSearch` appears in the Xcode beta swiftinterface. |
| 5. Delete `backend/` helpers | Pending | Safe after step 3 is live in production **and** step 4 ships (web search is the last hard Mangox Cloud dependency). |

## Routing (chat)

```
User message (+ optional photo)
  → on-device narrow (stats heuristics, no photo)
  → Mangox Cloud (live web search until PCC webSearch extension ships)
  → Private Cloud Compute (Dynamic Profiles)
  → third-party LanguageModel (Anthropic / Google, if SPM + API key)
  → Mangox Cloud fallback
```

Photos require PCC or a configured fallback model (`Transcript.ImageAttachment` / `Attachment`).

## Daily limit

`AIService.freeDailyLimit` (5/day) applies to **Mangox Cloud billable turns only**. On-device stats, PCC, and third-party replies do not increment the counter.

Apple also enforces a **Private Cloud daily quota** per user. Mangox surfaces quota status in Settings → AI Coach, blocks PCC turns when the limit is reached, and offers Apple's limit-increase sheet when available. Plan generation checks quota before starting (skeleton + one call per week).

## Network fallback

When PCC returns `networkFailure`, coach turns retry on-device Apple Intelligence before third-party or Mangox Cloud. Plan generation retries with an on-device `LanguageModelSession` for the same skeleton/week loop.

## Evaluations

- **In Xcode:** `FoundationModelsCoachEvaluationTests` (routing fixtures + narrow reply validators).
- **CI script:** `./Scripts/run-coach-evals.sh` runs those tests on a booted simulator.
- **Apple `fm` CLI (optional):** when the Foundation Models utilities package is installed, point `fm` at exported fixtures under `backend/scripts/coach-eval-fixtures.json` for prompt regression between OS releases.

## Backend deletion criteria

Remove Mangox Cloud calls (and eventually the in-repo `backend/` helper package) when:

1. Free PCC tier is enrolled and stable in production.
2. Third-party or PCC covers all non-web-search fallback turns.
3. `sdkExposesWebSearchExtension = true` and web-search routing no longer hits `/api/chat/stream`.
4. Plan/week regeneration no longer needs `/api/generate-plan` or `/api/regenerate-plan-week` (toggle remains for emergency fallback).

## SDK verification notes (June 2026, iOS 27.0 beta-1)

- `LanguageModel` / `LanguageModelExecutor` — present; third-party SPM providers plug into Dynamic Profiles via `.model(...)`.
- `onPrompt` / `onResponse` / `onToolCall` — wired on all coach Dynamic Profiles (`CoachDynamicProfileInstrumentation.swift`).
- `Transcript.ImageAttachment`, `Attachment.image` — used for coach photo turns.
- `PrivateCloudComputeLanguageModel.Extension.webSearch` — **absent** from public swiftinterface; Mangox Cloud remains required for live web search.

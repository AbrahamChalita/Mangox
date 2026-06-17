# Mangox Code Polish Audit - 2026-06-17

Scope: full repo pass across the iOS app, shared Core, SwiftUI feature views, domain algorithms, Supabase Edge Functions, tests, and existing docs. This is a code-first audit from the local workspace, not a runtime UX pass on device.

## Executive Summary

Current quality is high for a fast-moving app: feature folders follow the documented Domain/Data/Presentation split, shared UI/design tokens exist, core training math has meaningful unit coverage, Strava's new API host has already been migrated, and BLE hot-path debug logging is gated behind a compile flag.

Update after fixes: the app now builds on this machine by routing the unavailable FoundationModels/PCC/iOS 27 surface through local SDK-compatible fallbacks. This restores day-to-day compile/test ability, but it does not mean PCC, dynamic FoundationModels profiles, quota prompts, or image attachments are available in the installed SDK. Those remain product/runtime follow-ups for a matching iOS 27 SDK.

Issue count by severity:

| Severity | Count | Theme |
| --- | ---: | --- |
| Critical | 1 | Build is red on the available SDK/toolchain |
| High | 5 | FoundationModels API drift, giant files, actor/thread hops, debug logging, SDK target mismatch |
| Medium | 8 | SwiftUI invalidation, formatter churn, localization/a11y debt, design token drift, backend auth shape |
| Low | 6 | Docs drift, preview force-unwraps, minor algorithm cleanup, ops/tooling gaps |

Recommended order:

1. Keep the compatibility fallback build green while deciding the long-term iOS 27 SDK/PCC requirement.
2. Split the largest SwiftUI/service files enough to improve compile time and reviewability.
3. Profile the live ride dashboards and coach transcript after build is green.
4. Tighten localization/accessibility and debug logging.
5. Add Supabase typecheck tooling to the dev environment.

## Verification Performed

| Check | Result |
| --- | --- |
| `xcodebuild ... build` | Passes after compatibility fallback patches |
| `deno task check` | Not run: `deno` is not installed on PATH |
| Static scan | Completed with `rg`, file size scan, targeted source reads |
| `MangoxTests/PMCProjectionTests` | Passes |
| `MangoxTests/FTMSControlServiceTests` | Passes |
| `MangoxTests/CoachChatImprovementsTests/incrementalParser_matchesFullParser` | Passes |
| `MangoxTests/WorkoutManagerTests/stateTransitionsAndAutoPause` | Passes |
| Full `MangoxTests` target | Interrupted after Xcode simulator test-session finalization wedged; no assertion failure was surfaced before the hang |
| `git diff --check` | Passes |

Build command used:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Mangox.xcodeproj -scheme Mangox -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/MangoxDerived build
```

Original build diagnostics that triggered the compatibility work:

- `CoachDynamicProfiles.swift`: `LanguageModelSession.DynamicProfile`, `LanguageModelSession.Profile`, and `LanguageModelSession(profile:history:)` are not present in the available FoundationModels module.
- `FoundationModelsMangoxSupport.swift`: `GenerationOptions(samplingMode:)`, `GenerationOptions.ToolCallingMode`, `PrivateCloudComputeLanguageModel`, `LanguageModelError`, and `response.usage` are unavailable or renamed in the local SDK.
- `OnDeviceCoachEngine.swift`: `CoachRouteKind` no longer satisfies the current `Generable` requirements under the available SDK.
- Project warning still present: `IPHONEOS_DEPLOYMENT_TARGET = 27.0`, but the installed simulator SDK supports up to `26.5.99`.

## Positive Findings

- Module boundaries are clear and documented in `Docs/MODULES.md`.
- Training math has unusually good unit coverage for a consumer app: PMC, critical power, aerobic decoupling, plan simulation, compliance, GPX trimming, RAG, FTMS parsing, and sync all have tests.
- Shared UI primitives exist in `Core/UIComponents`, including `A11yL10n`, `MangoxMotion`, `MangoxSpacing`, `MangoxRadius`, `MangoxSurface`, and `MangoxButton`.
- Strava API host migration appears complete in source: `StravaService.swift` now has `static let apiBase = URL(string: "https://www.api-v3.strava.com")!`.
- BLE raw packet logging is behind `#if BLE_VERBOSE`, avoiding the worst ride-time logging overhead by default.
- Supabase Edge Functions validate provider, grant type, redirect URI, webhook secret, and required IDs explicitly.

## Critical Findings

### 1. Build fails on the available SDK/toolchain

Location:

- `Mangox/Features/Coach/Data/DataSources/CoachDynamicProfiles.swift:41`
- `Mangox/Features/Coach/Data/DataSources/FoundationModelsMangoxSupport.swift:46`
- `Mangox/Features/Coach/Data/DataSources/MangoxPCCSupport.swift:17`
- `Mangox/Features/Coach/Data/DataSources/OnDeviceCoachEngine.swift:41`

Status: mitigated for this workspace. The app builds by using local FoundationModels APIs and treating PCC/dynamic-profile/image-attachment features as unavailable when the SDK symbols are missing.

Impact if left as only a fallback: CI and release validation can proceed locally, but any product requirement that depends on PCC, FoundationModels dynamic profiles, quota UI, response usage metrics, or image attachments still needs validation on the intended iOS 27 SDK.

Recommendation: choose one of two long-term paths:

1. Require the iOS 27 SDK in CI and developer setup, then update `Docs/` and fail fast with clear tooling instructions.
2. Keep strengthening the compatibility boundaries so the iOS 26.5 SDK can compile, with explicit no-op/cloud fallback behavior when the symbols are absent.

Suggested fix shape:

```swift
// Before
GenerationOptions(samplingMode: .greedy)

// Current local SDK expects
GenerationOptions(sampling: .greedy)
```

```swift
// Before
return LanguageModelSession(profile: profile, history: history)

// Compatibility direction
return LanguageModelSession(
    model: MangoxFoundationModelsSupport.coachSystemLanguageModel(),
    tools: tools,
    instructions: Instructions(...)
)
```

## High-Severity Findings

### 2. FoundationModels surface is mixed between old, beta, and future APIs

Location:

- `FoundationModelsMangoxSupport.swift:46-59`
- `FoundationModelsMangoxSupport.swift:65-83`
- `FoundationModelsMangoxSupport.swift:148-165`
- `CoachDynamicProfiles.swift:92-160`

Impact: even if an iOS 27 SDK is intended, the code has no protective layer around experimental framework churn. One Apple beta change can break a large part of the coach pipeline.

Recommendation: create a narrow `CoachLanguageModelRuntime` abstraction in the Coach data layer. Keep raw FoundationModels symbols out of `AIService.swift` and most coach files. One file should own the SDK-specific conditional compilation and availability checks.

Suggested command: use `/harden` or the Swift concurrency/FoundationModels-specific skills before implementing.

### 3. Large files are now an engineering velocity risk

Largest app files:

| File | Lines |
| --- | ---: |
| `AIService.swift` | 3669 |
| `OutdoorDashboardView.swift` | 3479 |
| `SummaryView.swift` | 2642 |
| `ConnectionView.swift` | 2470 |
| `SettingsDetailViews.swift` | 2466 |
| `DashboardView.swift` | 2432 |
| `LocationManager.swift` | 2077 |
| `OnDeviceCoachEngine.swift` | 1806 |

Impact: giant SwiftUI views and service classes slow type-checking, make previews brittle, and make regressions harder to isolate. They also hide natural testing seams.

Recommendation:

- Split `AIService` by responsibilities: session persistence, routing, plan generation, cloud streaming, FoundationModels runtime, and draft/save operations.
- Split dashboards into stable leaf views with small value inputs. Start with state-heavy sections that update during rides.
- Move preview/test doubles out of production view files where practical.

Suggested command: use `/extract` for reusable components, then `/polish` after behavior is stable.

### 4. Actor/thread hop pattern in BLE callbacks deserves a focused review

Location:

- `BLEManager.swift:964-1028`
- `BLEManager.swift:1031-1045`
- `BLEManager.swift:1468-1475`

Status: improved. The repeated `DispatchQueue.main.async` + `MainActor.assumeIsolated` wrapper has been centralized in `hopToMainActorFromCoreBluetooth(_:)`, so the CoreBluetooth threading invariant is documented once and the delegate bodies stay focused on BLE state handling.

Impact: `DispatchQueue.main.async` plus `MainActor.assumeIsolated` is intentionally avoiding concurrency warnings, but it centralizes safety on the assumption that every callback lands exactly as expected. This is a good candidate for a targeted Swift concurrency review, especially because it sits on a high-rate BLE data path.

Recommendation: keep the current performance intent, but wrap this pattern in one helper such as `hopToMainActorFromCoreBluetooth(_:)`, document the invariant once, and add tests around subscriber notification/coalescing where possible.

### 5. Debug diagnostics still leak through production-ish paths

Location:

- `SyncCoordinator.swift:92-114`
- `SupabaseClient+Mangox.swift:17`

Status: fixed for the cited Supabase sync paths by replacing `print` with `Logger`.

Impact: `print` calls are gated in sync failures, but the app would benefit from consistent `Logger` categories with privacy annotations. This matters for customer support builds and for avoiding accidental sensitive payload logging later.

Recommendation: replace `print` with `Logger`, using domain names as public and error descriptions as private unless reviewed.

### 6. Deployment target currently exceeds installed SDK

Location:

- Xcode build settings in `Mangox.xcodeproj`

Impact: every local build emits target-range warnings and then fails on missing framework symbols. This is either a tooling setup issue or an accidental project setting drift.

Recommendation: either lower the simulator deployment target while keeping iOS 27-only code gated, or make the iOS 27 SDK an explicit prerequisite in setup docs and CI.

## Medium-Severity Findings

### 7. SwiftUI hot paths need runtime profiling after compile is green

Locations:

- `DashboardView.swift`
- `OutdoorDashboardView.swift`
- `SummaryView.swift`
- `CoachConversationView.swift`

Risk patterns observed: many `GeometryReader`s, multiple animations on large trees, high-frequency ride metrics, and broad observable manager dependencies in large root views.

Recommendation: once build is green, capture Instruments SwiftUI + Time Profiler traces for:

- indoor ride recording for 2 minutes with BLE packets
- outdoor ride screen with GPS + map + sensors
- coach streaming a long response
- workout summary opening and expanding sections

Likely fixes: split high-frequency metric labels into `Equatable` leaf views, keep manager reads out of broad parent views, and localize animations to small subtrees.

### 8. Some formatter allocations remain in repeatable paths

Examples:

- `LoggedActivitiesViewModel.swift:290`
- `TrainingPlanView.swift:36`
- `WorkoutHistoryKeywordRetriever.swift:24`
- `CoachContextBuilder.swift:142`
- `OnDeviceCoachEngine.swift:1335, 1385, 1480`

Status: partially fixed. Repeated medium-date formatter allocation was removed from `LoggedActivitiesViewModel`, `CoachContextBuilder`, `WorkoutHistoryKeywordRetriever`, and the cited `OnDeviceCoachEngine` coach tool payloads.

Impact: most are not catastrophic, but formatters are still expensive and easy to centralize. This matters during context building and list refreshes.

Recommendation: extend `AppFormat` with the missing date styles and replace ad hoc `DateFormatter()` / `ISO8601DateFormatter()` allocations in code that can run repeatedly.

### 9. Force unwraps are mostly preview/test-only, but a few production ones are avoidable

Examples:

- `OutdoorDashboardView.swift:754` opens Settings via a force-unwrapped URL.
- `CalendarView.swift:293` force unwraps dictionary lookup after deriving keys from the dictionary.
- Several `Data(... .utf8)!` form-body appends exist in service upload code.

Status: partially fixed. The cited `OutdoorDashboardView` Settings URL force unwrap and `CalendarView` dictionary lookup force unwrap were removed.

Impact: low crash likelihood, but this is cheap polish and keeps strict code hygiene consistent.

Recommendation: replace production force unwraps with `guard let`, optional chaining, or local helper APIs.

### 10. Localization and accessibility are partially centralized but not complete

Examples:

- `OutdoorDashboardView.swift` contains many literal `Text("...")` strings and a few literal accessibility labels such as `"Elapsed time"`.
- `A11yL10n` exists and should keep absorbing shared VoiceOver copy.

Impact: future localization and VoiceOver consistency will drift in the most important in-ride screens.

Recommendation: finish migrating in-ride controls, route banners, dialogs, and metric labels to localized keys and `A11yL10n`.

### 11. Visual design is cohesive, but the palette is very one-mode

Location:

- `Theme.swift:12-24`

Impact: the app is intentionally dark and mango-accented, which fits the product, but the use of pure black and white opacity tokens limits contrast/theming flexibility and makes light-mode or high-contrast variants harder.

Recommendation: keep the identity, but introduce semantic foreground/background roles that can map to high-contrast and future light variants. Avoid expanding ad hoc `.white.opacity(...)` usage outside shared tokens.

### 12. Supabase webhooks use shared-secret auth, not provider signatures

Location:

- `supabase/functions/external-webhooks/index.ts:76-91`

Impact: shared-secret headers/query params are workable for internal callbacks and providers that support custom secrets, but provider-native signature verification is stronger where available.

Recommendation: document provider security assumptions. If WHOOP/Strava support signature verification for the active webhook setup, validate signatures before inserting events.

### 13. Edge function typecheck is missing from this environment

Location:

- local tooling, `deno.json`

Impact: `deno task check` is the documented verification step but cannot run here.

Recommendation: add Deno installation/version instructions to setup docs or provide a devcontainer/bootstrap script.

### 14. Existing audit doc has drifted

Location:

- `Docs/AUDIT_2026-06.md`

Impact: it says the tree was verified against iOS 27 SDK and flags Strava base URL as unfixed. In this workspace, the Strava code is migrated but the local SDK build is red.

Recommendation: either update the old doc with a superseded note or keep this dated report as the active follow-up.

## Low-Severity Findings

### 15. Calendar grouping can remove a force unwrap

Location:

- `CalendarView.swift:293`

Status: fixed by compact-mapping the grouped day lookup.

Suggested change:

```swift
// Before
workoutsGroupedByDay = byDay.keys.sorted(by: >).map { day in (day, byDay[day]!) }

// After
workoutsGroupedByDay = byDay.keys
    .sorted(by: >)
    .compactMap { day in byDay[day].map { (day, $0) } }
```

### 16. Week label formatter can be cached

Location:

- `LoggedActivitiesViewModel.swift:281-294`

Status: fixed with a cached week-range formatter.

Suggested change: move the `DateFormatter` into a static cached property or `AppFormat`.

### 17. Preview-only `try!` can stay, but should be visually separated

Examples:

- `ContentView.swift:268`
- `TrainingPlanView.swift:1485`
- `DashboardSubviews.swift:1351, 1388`

Impact: acceptable in previews, but static scans keep surfacing them. A `PreviewPersistence.makeInMemoryContainer()` helper would make intent obvious.

### 18. Repeated `.white.opacity(...)` remains common

Impact: not a blocker, but it dilutes the token system. Continue moving shared components toward `AppColor` and `AppOpacity`.

### 19. `Docs/MODULES.md` still says tests have about 84 methods

Impact: this is likely stale given current test file count. Refresh the numbers or avoid exact counts.

### 20. Full runtime UX audit remains outstanding

Impact: this pass did not launch the app, inspect simulator screenshots, or test Dynamic Type/VoiceOver. Those should happen after the build is green.

## Suggested Work Plan

Immediate:

1. Decide iOS 27 SDK requirement vs keeping the iOS 26.5 compile fallback as a supported path.
2. Validate PCC/dynamic-profile/image-attachment behavior on the intended iOS 27 SDK.
3. Stabilize the full `MangoxTests` simulator run; the focused failures from the first pass now pass.

Short term:

1. Extract `AIService` runtime boundaries.
2. Split `OutdoorDashboardView`, `DashboardView`, and `SummaryView` by update frequency.
3. Replace production force unwraps and prints.
4. Install Deno and run `deno task check`.

Medium term:

1. Instruments pass for ride dashboards and coach streaming.
2. Finish `A11yL10n` and localization migration in the in-ride screens.
3. Add provider-signature verification if webhook providers support it.
4. Refresh or supersede the older June audit doc.

Long term:

1. Consider package boundaries for `Core`, `TrainingMath`, BLE, and Coach runtime.
2. Add architecture checks that prevent `Core` from importing feature code.
3. Build a small benchmark suite for power curve, RAG indexing, FIT/TCX import, and workout aggregation.

## Suggested Commands For Follow-Up

- `/harden`: SDK compatibility, force unwraps, logging, backend auth assumptions.
- `/optimize`: SwiftUI runtime profiling, dashboard invalidation, formatter churn.
- `/extract`: large file decomposition and reusable UI/service boundaries.
- `/polish`: final localization, accessibility labels, color token consistency, and preview cleanup.

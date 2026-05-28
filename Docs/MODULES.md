# Mangox module layout

The app target remains a **single Swift module** (`Mangox`) so nothing breaks at compile time. Source is **physically grouped** by feature with a clean `Domain/Data/Presentation` layering inside each feature.

## Directory map

| Folder | Role |
|--------|------|
| **`App/`** | App entry, root navigation, dependency injection: `MangoxApp.swift`, `ContentView.swift`, `AppRoute.swift`, `AppRouter.swift`, `DIContainer.swift`. |
| **`Core/`** | Feature-agnostic infrastructure, design tokens, and reusable UI. No feature-specific services. |
| **`Core/UIComponents/`** | Shared design system: `Theme.swift`, `MangoxFont.swift`, `MangoxMotion.swift`, `MangoxSpacing.swift`, `MangoxRadius.swift`, `MangoxSurface.swift`, `MangoxButton.swift`, `A11yL10n.swift`. |
| **`Core/UIComponents/Components/`** | Reusable UI components: `MangoxMetricCard`, `MangoxSectionLabel`, `MangoxStatusPill`, `MangoxConfirmOverlay`, `MangoxSkeletonView`, `MangoxErrorBanner`, `MangoxEmptyState`. |
| **`Core/UIComponents/DesignSystem/`** | Design tokens and modifiers for fonts, motion, spacing, radius, surfaces. |
| **`Core/UIComponents/Zones/`** | Heart rate and power zone chart components. |
| **`Core/Networking/`** | HTTP client, dev tunnel, Supabase auth, sync coordinator, and domain mappers. |
| **`Core/Persistence/`** | SwiftData container setup and demo data seeder. |
| **`Core/Utilities/`** | Audio cues, haptics, image processing, feature flags, legal URLs, avatar store. |
| **`Core/Extensions/`** | Shared extensions (e.g. `MapPolylineSanitize`). |
| **`Features/ActivityLog/`** | Cross-source activity logging (manual, Whoop, Strava import) with `Domain/Data/Presentation` layers. |
| **`Features/Coach/`** | AI coaching chat, plan generation, on-device coach with `Domain/Data/Presentation` layers. |
| **`Features/Fitness/`** | Fitness analytics: power curves, HR zones, FTP timeline, aerobic decoupling, health readiness, **TrainingMath** (PMC projection/trends for precision coach). |
| **`Features/Home/`** | Home dashboard with training status, recent rides, and workout suggestions. |
| **`Features/Indoor/`** | BLE/Wi-Fi trainer stack, indoor dashboard, guided sessions, workout controls. |
| **`Features/Onboarding/`** | First-launch flow, launch screen, cloud setup page. |
| **`Features/Outdoor/`** | GPS, MapKit navigation, outdoor dashboard, elevation, route management, live activities. |
| **`Features/Paywall/`** | RevenueCat subscription paywall. |
| **`Features/Profile/`** | Settings, account, rider profile, Strava/Whoop integrations, data export. |
| **`Features/Social/`** | Instagram story cards, day summary studio, Strava post builder. |
| **`Features/Training/`** | Training plans, FTP testing, calendar view, plan compliance, **PlanCritic**, **PlanTSSVectorBuilder**. |
| **`Features/Workout/`** | Workout recording, summary, FIT/TCX/GPX export, workout insights, RAG indexing. |
| **`MangoxTests/`** | Unit and integration tests (~84 test methods). |
| **`MangoxUITests/`** | UI tests (~34 test methods). |
| **`Docs/`** | Product and engineering notes (see `PRECISION_COACH.md` for coach math tools). |
| **`backend/`** | TypeScript helper package for coach parsing and schema utilities. |

**Assets**, **Info.plist**, **PrivacyInfo**, **entitlements** stay at `Mangox/` root.

## Feature layer convention

Each feature follows a `Domain/Data/Presentation` structure:

- **`Domain/`** — Entities, repository protocols, use cases. No framework imports beyond Foundation.
- **`Data/`** — Concrete repository implementations, data sources, persistence models, mappers.
- **`Presentation/`** — SwiftUI views, view models, and view-specific helpers.

## Dependency guidelines (social contract)

1. **`Core/`** must not import from `Features/*` (models, theme, and UI components stay portable).
2. **`Features/*`** may depend on `Core/` and other features only through protocols or shared services.
3. **`Features/Indoor/`** and **`Features/Outdoor/`** may use `Core/` and shared services; avoid referencing each other directly.
4. **ViewModels** are created by `DIContainer` and injected via `@Environment` or init parameters.
5. **Shared service logic** (Strava, Whoop, HealthKit, AI) lives in feature `Data/` layers with protocol-typed interfaces exposed for cross-feature use.

These rules are **not** enforced by the compiler yet; follow them in code review until (optional) SPM targets are introduced.

## Build and test

Use the shared `Mangox` scheme:

- **Build:** `xcodebuild -project Mangox.xcodeproj -scheme Mangox -configuration Debug -destination 'generic/platform=iOS Simulator' build`
- **Test:** `xcodebuild -project Mangox.xcodeproj -scheme Mangox -destination 'id=<simulator-id>' test`

## Next steps (optional)

- Extract **`MangoxCore`** as a local Swift package (models + theme + preferences) and link it from the app target.
- Split **`Features/Indoor`** and **`Features/Outdoor`** into package targets with explicit `import`s and `public` APIs.
- Finish migrating remaining hardcoded VoiceOver strings to **`A11yL10n`**.

# Mangox module layout

The app target remains a **single Swift module** (`Mangox`) so nothing breaks at compile time. Source is **physically grouped** so outdoor, indoor, shared services, and core data are easy to find and evolve independently.

## Directory map

| Folder | Role |
|--------|------|
| **`App/`** | App entry and root navigation: `MangoxApp.swift`, `ContentView.swift`, `AppRoute`. |
| **`Core/`** | Domain + design tokens: `Models/`, `Theme.swift`, `MapPolylineSanitize.swift`. No feature-specific services. |
| **`Features/Outdoor/`** | GPS, MapKit navigation, outdoor dashboard UI, elevation strip, mini map helpers. |
| **`Features/Indoor/`** | BLE stack (`BLE/`), trainer + dashboard session (`WorkoutManager`, `Dashboard*`, `WorkoutControlBar`), Wi‑Fi trainer, `DataSourceCoordinator`, `RingBuffer`, `GuidedSessionManager`. |
| **`Services/`** | Cross-cutting integrations: routes/GPX (`RouteManager`), export, Strava, HealthKit, fitness analytics, audio/haptics, FTP test utilities, personal records. |
| **`Views/`** | Screens that combine multiple domains (home, calendar, summary, settings, connection, training plan, charts, onboarding, etc.). |

**Assets**, **Info.plist**, **PrivacyInfo**, **entitlements** stay at `Mangox/` root next to these folders.

## Dependency guidelines (social contract)

1. **`Core/`** must not import from `Features/*` or `Services/` (models & theme stay portable).
2. **`Features/Outdoor/`** may use `Core/`, `Services/` (e.g. `RouteManager`), and `Views/`-level types only through the app or shared APIs—prefer depending on **`Services/`** and **`Core/`** first.
3. **`Features/Indoor/`** may use `Core/` and `Services/`; avoid referencing outdoor-only types from indoor code paths.
4. **`Services/`** may use **`Core/`**; avoid referencing `Features/Outdoor` or `Features/Indoor` directly—pass data or use protocols if a service ever needs feature-specific behavior.

These rules are **not** enforced by the compiler yet; follow them in code review until (optional) SPM targets are introduced.

## Next steps (optional)

- Extract **`MangoxCore`** as a local Swift package (models + theme + preferences) and link it from the app target.
- Split **`Features/Outdoor`** and **`Features/Indoor`** into package targets with explicit `import`s and `public` APIs.
- Move **`Views/`** into smaller feature groups or a `SharedUI` package as screens stabilize.

**Note:** Indoor trainer data paths already converge on **`DataSourceCoordinator`** (BLE + Wi‑Fi); SPM splits above are organizational only and do not change that wiring.

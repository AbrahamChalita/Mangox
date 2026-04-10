# Mangox Enterprise Refactor Register

Last updated: 2026-04-10 (Domain extraction and closeout audit complete)

## Baseline

Every feature should converge on this shape:

1. Domain owns app-facing models and contracts.
2. Data owns infrastructure and concrete implementations.
3. Presentation uses a feature-owned `@Observable` view model or store.
4. `App/DIContainer.swift` is the composition root.
5. Large views are split only after data flow and dependency boundaries are clean.

## Future LLM Handoff

Read this file first in any new session. Treat it as the source of truth for what has already been refactored, what is still in flight, and what order to continue in.

### Primary objective

Finish turning Mangox into a feature-first SwiftUI app with:

1. Feature-owned presentation models.
2. Cleaner Presentation -> Domain -> Data boundaries.
3. Fewer giant root views acting like controllers.
4. Better profiling surfaces for SwiftUI performance and UI polish.

### Non-negotiable architecture rules

1. Do not let Presentation depend directly on concrete infrastructure when a feature-owned seam can own the orchestration.
2. Do not move SwiftUI, SwiftData, persistence models, or service-specific types into Domain.
3. Keep `App/DIContainer.swift` as the composition root.
4. Prefer moving state flow and orchestration first; split giant views into smaller sections after the data flow is cleaner.
5. Never revert unrelated user changes in the worktree.

### What has already been done

1. `Home` has a real feature-owned `HomeViewModel`, with aggregation and refresh logic moved out of the root view.
2. `Coach` has a shared `CoachViewModel`, no direct `@Environment(AIService.self)` usage in presentation, and several coach-facing models moved out of `AIService` into Domain.
3. `Indoor`, `Outdoor`, and `Workout Summary` all now use route-level injected feature view models.
4. `Indoor` owns ride feedback, milestone state, and end/discard/finish navigation flow in the feature model.
5. `Outdoor` owns route/setup presentation state, ride exit confirmation state, and completed-ride persistence drafting/finalization in the feature model.
6. `Workout Summary` owns prepared summary data, export/delete state, Strava/story draft state, and repeat/delete/export navigation decisions in the feature model.
7. `ConnectionView` is already protocol-injected via init (`BLEServiceProtocol`, `DataSourceServiceProtocol`, `RouteServiceProtocol`, `LocationServiceProtocol`) and no longer reads concrete services from `@Environment`.
8. `InstagramStoryCardOptions.Accent` no longer imports SwiftUI or stores `Color` in Domain; Presentation resolves the accent color in `InstagramStoryAccent+Color.swift`.

### Exact files to inspect first in a new session

1. `Docs/enterprise-refactor-register.md`
2. `Mangox/App/DIContainer.swift`
3. `Mangox/App/AppRouter.swift`
4. `Mangox/Features/Indoor/Presentation/ViewModel/IndoorViewModel.swift`
5. `Mangox/Features/Outdoor/Presentation/ViewModel/OutdoorViewModel.swift`
6. `Mangox/Features/Workout/Presentation/ViewModel/WorkoutViewModel.swift`
7. `Mangox/Features/Coach/Presentation/ViewModel/CoachViewModel.swift`
8. `Mangox/Features/Home/Presentation/ViewModel/HomeViewModel.swift`

### Recommended next order of work

1. **Optional cleanup only**: If desired, follow up on low-priority app-level `ModelContext` helpers such as `WorkoutRAGIndex.scheduleBackgroundSync(modelContext:)` and preview-only `ModelContext(...)` scaffolding.
2. **DTO split only if needed**: The architectural extraction is complete because no SwiftData `@Model` types remain in Domain. Only add parallel plain-domain mapper types later if a real isolation benefit appears.
3. **UI polish/perf**: Future work is no longer architecture-blocking; focus can shift to feature polish, performance, and release readiness.

### Per-feature workflow

1. Inspect the route/root injection path first.
2. Identify root-view local state that is really orchestration or screen-state, and move it into the feature view model.
3. Move completion, delete, repeat, export, or navigation decisions into the feature model before touching visual composition.
4. Only after the state flow is cleaner, split large views into smaller rendering sections.
5. Rebuild after each meaningful pass.

### Build / verification command

Use this after each pass:

```bash
xcodebuild -project Mangox.xcodeproj -scheme Mangox -destination 'generic/platform=iOS' build
```

### How to update this file after each session

1. Update `Last updated`.
2. Update the relevant row in `Progress`.
3. Update `Latest wave notes` with the concrete seam that moved.
4. If the recommended order changed, update `Recommended next order of work`.
5. Do not leave vague notes like "did some cleanup"; name the actual orchestration/state boundary that changed.

## Progress

| Feature | Status | What is done | What remains |
| --- | --- | --- | --- |
| Home | Complete | `HomeViewModel` owns `BLEServiceProtocol`, `DataSourceServiceProtocol`, `LocationPermissionService`, `WhoopServiceProtocol`, `AIServiceProtocol`, and `TrainingPlanLookupServiceProtocol`. All 5 concrete @Environment reads removed from `HomeView`. BLE pre-warm, location setup, Whoop refresh, AI insight generation, FTP display, and next-workout plan lookup all resolve through feature-owned seams. `AIServiceProtocol` and `TrainingPlanLookupServiceProtocol` now own their persistence context internally, so `HomeViewModel` no longer imports `SwiftData` or accepts `ModelContext`. | Residual app-wide audit only. |
| Coach | Complete | `CoachViewModel` owns `PurchasesServiceProtocol`; `isPro` is feature-owned. `CoachConversationView` and `PlanGenerationSheets` no longer read `PurchasesManager` from @Environment. Coach session loading, starter content, send/switch/delete flows, and plan regeneration now resolve through service APIs that own persistence internally, so `CoachViewModel` no longer imports `SwiftData` or threads `ModelContext`. `stagePlanRegeneration` now takes a plain `AIGeneratedPlanDraft` instead of the SwiftData model directly. | Residual app-wide audit only. |
| Indoor | Complete | `IndoorViewModel` owns `BLEServiceProtocol`, `DataSourceServiceProtocol`, `RouteServiceProtocol`, `HealthKitServiceProtocol`, `LiveActivityServiceProtocol`, `WorkoutPersistenceRepositoryProtocol`, and `TrainingPlanPersistenceRepositoryProtocol`. All 5 concrete @Environment reads removed from `DashboardView`. Live metrics, trainer control state, route state, HealthKit save, live-activity sync, custom-template lookup, and plan-day completion persistence all resolve through the feature model. `ConnectionView` is already init-injected with protocol dependencies. Plan lookup in `DashboardView` now uses `TrainingPlanLookupServiceProtocol` instead of `PlanLibrary` directly. `WorkoutManager` and `GuidedSessionManager` now live in `IndoorViewModel`, `HapticManager` usage is consolidated to `HapticManager.shared`, and `bootstrapDashboard` no longer downcasts concrete service types or thread `ModelContext`. | Residual app-wide audit only. |
| Outdoor | Complete | `OutdoorViewModel` owns `BLEServiceProtocol`, `RouteServiceProtocol`, `HealthKitServiceProtocol`, `LiveActivityServiceProtocol`, `LocationServiceProtocol`, and `WorkoutPersistenceRepositoryProtocol`. BLE/Route/HealthKit/LiveActivity concrete environment reads are gone from `OutdoorDashboardView`. `ElevationProfileView` and `RouteMiniMapView` take `RouteServiceProtocol` via init. Live GPS reads already flow through `viewModel.locationService`. `NavigationService` moved from `@State` in the view into `OutdoorViewModel` as an owned stored property; all 7 VM methods that previously accepted `navigationService:` as a parameter now access `self.navigationService` instead. `_bleManager: BLEManager` backing field and protocol-façade computed property replaced with a single `let bleService: BLEServiceProtocol` stored dependency; init updated accordingly. `DIContainer.makeOutdoorViewModel()` updated to pass `bleService: bleManager`. `completeRide` now persists completed outdoor workouts and lap splits through `WorkoutPersistenceRepository`. `LocationServiceProtocol` no longer carries map-camera state; `OutdoorDashboardView` now reads camera/search-bias concerns through `MapCameraServiceProtocol`. | Residual app-wide audit only. |
| Workout Summary | Complete | `WorkoutViewModel` owns `RouteServiceProtocol`, `PersonalRecordsServiceProtocol`, `HealthKitServiceProtocol`, `StravaServiceProtocol`, `TrainingPlanLookupServiceProtocol`, and `WorkoutPersistenceRepositoryProtocol`. `RouteManager` and `PersonalRecords` @Environment reads removed from `SummaryView`. `WorkoutExportService` now uses `RouteServiceProtocol`. `StravaUploadRequest` uses protocol-typed route service. Plan/day lookup for `SummaryView` and `WorkoutRowView` now goes through the lookup service seam instead of `PlanLibrary` directly. `WorkoutPersistenceRepositoryProtocol` now handles delete, custom-template save, outdoor-ride save, and sorted sample loading for summary preparation, and `SummaryOnDeviceInsightCard` no longer threads `ModelContext` for smart-title generation. | Residual app-wide audit only. |
| Fitness | Complete | `FitnessViewModel` owns PMC data, range selection, legend toggles, rebuild scheduling, plan compliance, power curve, and uses `TrainingPlanLookupServiceProtocol` for plan resolution. `PMCPoint` is a shared model. `HeartRateBarView` dead @Environment removed. `FitnessViewModel` now consumes `WorkoutMetricsSnapshot` instead of live SwiftData `Workout` models, and no longer imports `SwiftData`. | Residual app-wide audit only. |
| Onboarding | Complete | `OnboardingViewModel` owns `HealthKitServiceProtocol`, `LocationPermissionService`, `StravaServiceProtocol`. All OS permission requests, Strava connection, notification checks, onboarding completion resolve through the VM. `OnboardingView` reads zero concrete services from @Environment. | Display-only view state audit. |
| Paywall | Complete | `PaywallViewModel` owns all purchase orchestration via `PurchasesServiceProtocol`: offerings loading, package selection (`PaywallOption`), purchase execution, restore, sync, subscriber display. View no longer imports RevenueCat. Protocol extended with `purchase(optionWithID:)`, `availablePaywallOptions`, `hasStoreSubscription`, `storeProPlanKind`, `storeProRenewalDescription`. | Display-only view state audit. |
| Profile | Complete | `ProfileViewModel` owns `WhoopServiceProtocol`, `PurchasesServiceProtocol`, `StravaServiceProtocol`, `FTPRefreshTrigger`, `HealthKitServiceProtocol`. `SettingsView`, `ProfileView`, and 6 sub-views in `SettingsDetailViews` no longer read concrete services from @Environment — all go through the VM. Settings snapshot recording, notification rescheduling, and export bundle generation now go through data-layer helpers that own persistence internally instead of view-level `ModelContext` calls. | Residual app-wide audit only. |
| Social | Complete | `SocialViewModel` owns AI caption/title generation state and rendering state. `previewImage: UIImage?`, `isRendering: Bool`, `renderPreview(workout:dominantZone:routeName:totalElevationGain:personalRecordNames:) async`, and `shareToInstagram(workout:dominantZone:routeName:totalElevationGain:personalRecordNames:onError:onDismiss:) async` all moved from the view into `SocialViewModel`. `shareFallbackItems` retyped from `[Any]` to `[UIImage]`. `InstagramStoryStudioView` no longer owns any render or share logic. | Display-only view state audit. |
| Training | Complete | `TrainingViewModel` owns `WhoopServiceProtocol`, `PurchasesServiceProtocol`, and `TrainingPlanPersistenceRepositoryProtocol`. `FTPTestView` now uses `FTPTestViewModel` with `BLEServiceProtocol` and `DataSourceServiceProtocol` instead of 3 concrete @Environment reads. Training plan start/reset/delete and day completion/skip/unmark mutations now persist through the repository seam, the adaptive-load reset action no longer saves SwiftData directly from `TrainingPlanView`, and `TrainingPlanProgress` has been extracted out of the Domain plan file into Data-layer persistence models. | Residual app-wide audit only. |

## Current Wave

### Wave 1

- Indoor dashboard
- Outdoor dashboard
- Workout summary

### Extraction order

1. Inject the feature view model at the route/root level.
2. Move root screen orchestration and transient UI state into the feature view model.
3. Move derived calculations into Domain use cases when they are not presentation-specific.
4. Replace direct concrete environment/service reads with protocol-backed dependencies where practical.
5. Split the giant root view into stable rendering sections once the state flow is settled.

## Known app-wide architecture gaps

### Protocol / injection gaps
- Wave 2 and Wave 4 protocol / injection gaps are closed. The remaining structural gaps are Domain-purity focused rather than concrete service-injection issues.

### SwiftData mutation gaps (Presentation ViewModels still calling ModelContext directly)
- `IndoorViewModel`: migrated behind `WorkoutPersistenceRepositoryProtocol` and `TrainingPlanPersistenceRepositoryProtocol`. ✅
- `WorkoutViewModel.prepareSummaryData`: migrated behind `WorkoutPersistenceRepositoryProtocol.fetchSortedSamples(forWorkoutID:)`. ✅
- `TrainingViewModel`: migrated behind `TrainingPlanPersistenceRepository`. ✅
- `OutdoorViewModel.completeRide`: migrated behind `WorkoutPersistenceRepository.saveOutdoorRide(...)`. ✅

### Presentation rendering still in views
- No known high-value rendering/orchestration gaps remain from Waves 2 through 4. Remaining work is Domain purity and final audit.

### Domain purity gaps
- No SwiftData `@Model` types remain under `Features/*/Domain`.
- Targeted presentation `ModelContext` seams from the final audit are closed: `SettingsDetailViews`, `SummaryOnDeviceInsightCard`, `FTPHistoryView`, and the `DashboardView` bootstrap path now call data-layer helpers that own persistence internally.
- Low-priority residuals are app-level only: `WorkoutRAGIndex.scheduleBackgroundSync(modelContext:)` in `MangoxApp` and preview/test-only `ModelContext(...)` construction.

## Remaining to 100% checklist

### Protocol / injection
- [x] Update `LiveActivityServiceProtocol.syncRecording` and `syncIndoorRecording` to take `bleService: BLEServiceProtocol` instead of `bleManager: BLEManager`. Update `RideLiveActivityManager` implementation. ✅
- [x] Replace `OutdoorViewModel._bleManager: BLEManager` with `bleService: BLEServiceProtocol`. Update init and `DIContainer.makeOutdoorViewModel()`. ✅
- [x] Remove `IndoorViewModel.syncLiveActivity` downcasts (`as? RideLiveActivityManager`, `as? BLEManager`) — call `liveActivityService.syncIndoorRecording` directly once the protocol uses `BLEServiceProtocol`. ✅
- [x] Remove `IndoorViewModel.bootstrapDashboard` downcasts (`as? BLEManager`, `as? DataSourceCoordinator`, `as? RouteManager`) by updating `WorkoutManager.configure` to accept protocol types. ✅
- [x] Move `NavigationService` out of `OutdoorDashboardView` @State into `OutdoorViewModel` as a stored property. Remove `navigationService:` parameter from all affected VM methods. ✅
- [x] Move `WorkoutManager`, `HapticManager`, and `GuidedSessionManager` out of `DashboardView` @State. `WorkoutManager` → `IndoorViewModel` owned property (or DI). `HapticManager` → `HapticManager.shared`. `GuidedSessionManager` → `IndoorViewModel`. ✅
- [x] Replace `ContentView`'s `@Environment(LocationManager.self)` with `di.locationService`. Add `warmUpLocationIfAuthorized()` to `LocationServiceProtocol`. Expose `var locationService: LocationServiceProtocol { locationManager }` on `DIContainer`. ✅
- [x] Fix `WorkoutPersistenceRepository.deleteWorkout` inverted dependency: inline the `FetchDescriptor<TrainingPlanProgress>` + `removeAll` + `save` logic directly in the repository instead of calling `DashboardView.unmarkPlanDay(...)`. ✅

### SwiftData mutation extraction (repository seams)
- [x] `OutdoorViewModel.completeRide`: extend `WorkoutPersistenceRepositoryProtocol` with an outdoor-ride save method; migrate `insert(workout)` + per-lap `insert(split)` + `save()` behind the repository. ✅
- [x] `TrainingViewModel`: create `TrainingPlanPersistenceRepositoryProtocol` + `TrainingPlanPersistenceRepository`. Migrate all 6 saves + 2 inserts + 3 deletes. Register in `DIContainer`. ✅
- [x] `IndoorViewModel`: custom template lookup now uses `WorkoutPersistenceRepositoryProtocol.fetchCustomWorkoutTemplate(id:)`, and plan-day completion persistence now goes through `TrainingPlanPersistenceRepositoryProtocol`. Direct `modelContext.fetch` and `modelContext.save` calls removed from the VM. ✅
- [x] `WorkoutViewModel.prepareSummaryData`: background sample loading now runs through `WorkoutPersistenceRepositoryProtocol.fetchSortedSamples(forWorkoutID:)`. Direct `ModelContext(modelContainer)` construction removed from the VM. ✅
- [x] `WorkoutViewModel` delete + custom-template save: fully migrated to `WorkoutPersistenceRepositoryProtocol`. ✅

### Presentation rendering
- [x] Move `SocialViewModel`: add `var previewImage: UIImage?`, `var isRendering: Bool`, `func renderPreview(workout:dominantZone:routeName:totalElevationGain:personalRecordNames:) async`, and `func shareToInstagram(workout:dominantZone:routeName:totalElevationGain:personalRecordNames:onError:onDismiss:) async`. Remove these from `InstagramStoryStudioView`. Retype `shareFallbackItems` from `[Any]` to `[UIImage]`. ✅

### Domain purity
- [x] Extract all 10 `@Model` entities from Domain into Data-layer `@Model` persistence classes. No SwiftData models remain under `Features/*/Domain`. ✅
- [x] Move `FitnessSettingsSnapshotRecorder/Backfill` and `PlanLibrary` out of Domain into Data repositories. ✅
- [x] Remove direct `PlanLibrary` access from Presentation via `TrainingPlanLookupServiceProtocol`. ✅
- [x] Split `LocationServiceProtocol` camera state: `LocationServiceProtocol` no longer imports `SwiftUI`/`MapKit` or exposes camera-following state. `MapCameraServiceProtocol` now owns map camera and search-bias concerns for `OutdoorDashboardView`. ✅
- [x] `CoachViewModel` purity: removed `SwiftData` from `CoachViewModel`, stopped threading `ModelContext` through its presentation APIs, and replaced the direct `AIGeneratedPlan` argument in `stagePlanRegeneration(from:)` with plain `AIGeneratedPlanDraft`. The existing `AIServiceProtocol` seam now owns persistence internally. ✅
- [x] `HomeViewModel` purity: `AIServiceProtocol.coachFactSheetText` and `TrainingPlanLookupServiceProtocol` no longer surface `ModelContext`, and `HomeViewModel` no longer imports `SwiftData` or accepts `ModelContext`. ✅
- [x] `FitnessViewModel` purity: `WorkoutMetricsSnapshot` is now the plain input for PMC, power-curve, and plan-compliance work. `FitnessViewModel` no longer imports `SwiftData` or accepts `Workout` directly. ✅

### Final audit
- [x] Run a final sweep for any remaining concrete `@Environment` reads, `ModelContext` parameters in Presentation, stale register entries, and display-only state still acting like orchestration. Remaining `ModelContext` uses are app-level or preview-only. ✅

## Todos

### Wave 2 — Concrete seam and injection fixes (immediate, self-contained)

- [x] **TODO-01** `LiveActivityServiceProtocol` BLE type: change `bleManager: BLEManager` → `bleService: BLEServiceProtocol` in `syncRecording` and `syncIndoorRecording`. Updated `RideLiveActivityManager` to match. ✅
- [x] **TODO-02** `OutdoorViewModel` BLE init: replaced `private let _bleManager: BLEManager` + façade with a single `let bleService: BLEServiceProtocol`. Updated init and `DIContainer.makeOutdoorViewModel()`. ✅
- [x] **TODO-03** `IndoorViewModel.syncLiveActivity` downcasts: removed `liveActivityService as? RideLiveActivityManager` and `bleService as? BLEManager`. Now calls `liveActivityService.syncIndoorRecording(isRecording:prefs:workoutManager:bleService:)` directly through the protocol. ✅
- [x] **TODO-04** `NavigationService` ownership: `let navigationService = NavigationService()` added to `OutdoorViewModel`. `navigationService:` parameter removed from all 7 affected VM methods. `OutdoorDashboardView` `@State var navigationService` removed; all reads go through `viewModel.navigationService` (shorthand `ns`). ✅
- [x] **TODO-05** `ContentView` location seam: `warmUpLocationIfAuthorized()` added to `LocationServiceProtocol` with a no-op default extension. `var locationService: LocationServiceProtocol { locationManager }` exposed on `DIContainer`. `@Environment(LocationManager.self)` removed from `ContentView`; both call sites now use `di.locationService`. ✅
- [x] **TODO-06** `SocialViewModel` rendering migration: `previewImage`, `isRendering`, `renderPreview(...)`, `shareToInstagram(...)` moved into `SocialViewModel`. `shareFallbackItems` retyped `[Any]` → `[UIImage]`. `InstagramStoryStudioView` now contains no render or share logic. ✅
- [x] **TODO-07** `WorkoutPersistenceRepository` view dependency: `DashboardView.unmarkPlanDay(...)` call removed. `FetchDescriptor<TrainingPlanProgress>` fetch + `completedDayIDs.removeAll` + save inlined as a private `unmarkPlanDay` helper in the repository. ✅

### Wave 3 — SwiftData mutation extraction

- [x] **TODO-08** `OutdoorViewModel.completeRide` persistence: completed via `WorkoutPersistenceRepository.saveOutdoorRide(workout:splits:)`. `OutdoorViewModel.completeRide` no longer inserts `Workout` or `LapSplit` directly. ✅
- [x] **TODO-09** `TrainingViewModel` persistence: added `TrainingPlanPersistenceRepositoryProtocol` + `TrainingPlanPersistenceRepository` in `Training/Data/Repositories/`. `startPlan`, `resetPlan`, `deleteAIPlan`, `markCompleted`, `markSkipped`, `unmark`, and adaptive-load reset actions now persist through the repository seam. Injected via `DIContainer`. ✅
- [x] **TODO-10** `IndoorViewModel` plan-progress persistence: custom template lookup now uses `WorkoutPersistenceRepositoryProtocol.fetchCustomWorkoutTemplate(id:)`, and plan-day completion persistence now runs through `TrainingPlanPersistenceRepositoryProtocol.markCompleted(...)` plus `save(progress:)`. Direct `modelContext.fetch` and `modelContext.save` calls removed from `IndoorViewModel`. ✅
- [x] **TODO-11** `WorkoutViewModel.prepareSummaryData` background context: `WorkoutPersistenceRepositoryProtocol.fetchSortedSamples(forWorkoutID:)` now owns the background sample read. `WorkoutViewModel` no longer constructs `ModelContext(modelContainer)` directly. ✅

### Wave 4 — Indoor session object ownership

- [x] **TODO-12** `WorkoutManager.configure` protocol types: `WorkoutManager.configure(...)` now accepts `BLEServiceProtocol` and `DataSourceServiceProtocol`, and `configureRoute(_:)` now accepts `RouteServiceProtocol`. `BLEServiceProtocol` gained `setSimulationGrade(_:)` so route simulation no longer relies on concrete trainer internals. ✅
- [x] **TODO-13** `IndoorViewModel.bootstrapDashboard` downcasts: removed `bleService as? BLEManager`, `dataSourceService as? DataSourceCoordinator`, and `routeService as? RouteManager`. `IndoorViewModel` now passes protocol values directly. ✅
- [x] **TODO-14** `WorkoutManager` ownership: `WorkoutManager` moved out of `DashboardView` `@State` and into `IndoorViewModel` as an owned session object. View and child call sites now read it from the view model. ✅
- [x] **TODO-15** `HapticManager` consolidation: `DashboardView` no longer owns a per-view `HapticManager`. Calls now use `HapticManager.shared`. ✅
- [x] **TODO-16** `GuidedSessionManager` ownership: `GuidedSessionManager` moved out of `DashboardView` `@State` and into `IndoorViewModel` as an owned session object. ✅

### Wave 5 — Domain purity

- [x] **TODO-17** `LocationServiceProtocol` SwiftUI split: `LocationServiceProtocol` no longer imports `SwiftUI` or `MapKit`, and `MapCameraServiceProtocol` now owns map camera / search bias state for `OutdoorDashboardView`. ✅
- [x] **TODO-18** `CoachViewModel` purity: `CoachViewModel` no longer threads `ModelContext`, and plan regeneration now uses plain `AIGeneratedPlanDraft`. The existing AI service seam owns persistence internally. ✅
- [x] **TODO-19** `HomeViewModel` purity: `AIServiceProtocol.coachFactSheetText` and `TrainingPlanLookupServiceProtocol` no longer accept `ModelContext`, and `HomeViewModel` no longer imports `SwiftData`. ✅
- [x] **TODO-20** `FitnessViewModel` purity: `WorkoutMetricsSnapshot` now backs PMC, power curve, and plan compliance; `FitnessViewModel` no longer takes `Workout` directly or imports `SwiftData`. ✅
- [x] **TODO-21** Full Domain `@Model` extraction: all 10 SwiftData models now live under feature `Data/PersistenceModels/`, and `TrainingPlanProgress` was split out of `TrainingPlan.swift`. No `@Model` types remain in Domain. ✅

### Wave 6 — Final audit

- [x] **TODO-22** Final sweep: completed targeted audit for concrete `@Environment` reads and presentation `ModelContext` usage. Residual low-priority call sites are now documented under `Domain purity gaps`. ✅
- [x] **TODO-23** Update register after each wave: completed for Wave 5 and the final audit log. ✅

## New protocols created this session

- `BLEServiceProtocol` — Indoor/Domain/Repositories/
- `DataSourceServiceProtocol` — Indoor/Domain/Repositories/
- `RouteServiceProtocol` — Outdoor/Domain/Repositories/
- `PersonalRecordsServiceProtocol` — Workout/Domain/Repositories/
- `LiveActivityServiceProtocol` — Indoor/Domain/Repositories/
- `LocationPermissionService` — Onboarding/Domain/Repositories/
- `WorkoutPersistenceRepositoryProtocol` — Workout/Data/Repositories/
- `TrainingPlanPersistenceRepositoryProtocol` — Training/Data/Repositories/

## Extended protocols this session

- `PurchasesServiceProtocol` — added `purchase(optionWithID:)`, `availablePaywallOptions`, `hasStoreSubscription`, `storeProPlanKind`, `storeProRenewalDescription`
- `HealthKitServiceProtocol` — added `saveCyclingWorkoutToHealthIfEnabled(_:)`
- `WhoopServiceProtocol` — added `lastSuccessfulRefreshAt`
- `AIServiceProtocol` — added `coachFactSheetText(modelContext:)`
- `BLEServiceProtocol` — added `setSimulationGrade(_:)`

## Latest wave notes

- `Home`: All 5 concrete @Environment reads removed. `HomeViewModel` owns `BLEServiceProtocol`, `DataSourceServiceProtocol`, `LocationPermissionService`, `WhoopServiceProtocol`, `AIServiceProtocol`. BLE pre-warm, location setup, Whoop refresh, AI insight generation all run through the feature model.
- `Training lookup seam`: added `TrainingPlanLookupServiceProtocol` + `TrainingPlanLookupService` in Data and injected it through DI. Direct `PlanLibrary` usage is now gone from Presentation and App-route composition.
- `ConnectionView`: verified complete on the service-injection seam. It already receives protocol dependencies through init and no longer reads concrete services from `@Environment`.
- `Indoor`: All 5 concrete @Environment reads removed from DashboardView. `IndoorViewModel` owns `BLEServiceProtocol`, `DataSourceServiceProtocol`, `RouteServiceProtocol`, `HealthKitServiceProtocol`, `LiveActivityServiceProtocol`. Live metrics, trainer control state, route state, HealthKit save, live-activity sync all resolve through the VM. `syncLiveActivity` downcast to `RideLiveActivityManager` + `BLEManager` eliminated — `liveActivityService.syncIndoorRecording(bleService:)` called directly via the protocol.
- `Indoor` Wave 3 and 4 finish: `IndoorViewModel` now injects `WorkoutPersistenceRepositoryProtocol` and `TrainingPlanPersistenceRepositoryProtocol`, so custom-template lookup and plan-day completion persistence no longer touch `ModelContext` directly. `WorkoutManager.configure(...)` and route simulation are protocol-backed, `bootstrapDashboard` no longer downcasts concrete services, `WorkoutManager` and `GuidedSessionManager` moved into `IndoorViewModel`, and `DashboardView` now uses `HapticManager.shared`.
- `Outdoor`: `NavigationService` moved from `@State` in `OutdoorDashboardView` into `OutdoorViewModel` as a stored property (`let navigationService = NavigationService()`). All 7 VM methods that previously took `navigationService:` as a parameter now use `self.navigationService`. View replaced the `@State` with a `private var ns: NavigationService { viewModel.navigationService }` shorthand. `_bleManager: BLEManager` concrete backing field + protocol-façade computed property eliminated; `OutdoorViewModel` now stores `let bleService: BLEServiceProtocol` directly. `LiveActivityServiceProtocol.syncRecording` updated to take `bleService: BLEServiceProtocol`. `DIContainer.makeOutdoorViewModel()` updated to pass `bleService: bleManager`.
- `Workout Summary`: `RouteManager` and `PersonalRecords` @Environment reads removed. `WorkoutViewModel` owns `RouteServiceProtocol`, `PersonalRecordsServiceProtocol`, `HealthKitServiceProtocol`, and `WorkoutPersistenceRepositoryProtocol`. `WorkoutExportService` and `StravaUploadRequest` use protocol-typed route service, and `prepareSummaryData(...)` now fetches sorted samples through the workout persistence repository instead of constructing a background `ModelContext` in Presentation.
- `Workout SwiftData mutation seam`: added `WorkoutPersistenceRepositoryProtocol` and `WorkoutPersistenceRepository` to centralize workout-related SwiftData writes (custom-template save and workout delete side effects), preparing `WorkoutViewModel` to stop mutating `ModelContext` directly.
- `Training SwiftData mutation seam`: added `TrainingPlanPersistenceRepositoryProtocol` and `TrainingPlanPersistenceRepository`. `TrainingViewModel` no longer imports `SwiftData` or accepts `ModelContext`; start/reset/delete/complete/skip/unmark flows now persist through DI-injected repository calls, and `TrainingPlanView` no longer saves adaptive-load resets directly.
- `Domain purity audit`: verified that `InstagramStoryCardOptions.Accent` is already clean, while the real remaining domain work is the 10 SwiftData-backed Domain entities plus `LocationServiceProtocol` carrying UI-facing camera types.
- `ContentView` location seam: `@Environment(LocationManager.self)` removed. `warmUpLocationIfAuthorized()` added to `LocationServiceProtocol` (with a no-op default extension). `DIContainer` now exposes `var locationService: LocationServiceProtocol { locationManager }`. `ContentView` reads location exclusively via `di.locationService`.
- `Social` rendering migration: `previewImage: UIImage?`, `isRendering: Bool`, `renderPreview(workout:dominantZone:routeName:totalElevationGain:personalRecordNames:) async`, and `shareToInstagram(workout:dominantZone:routeName:totalElevationGain:personalRecordNames:onError:onDismiss:) async` moved from `InstagramStoryStudioView` into `SocialViewModel`. `shareFallbackItems` retyped `[Any]` → `[UIImage]`. View now owns zero render or share logic.
- `WorkoutPersistenceRepository` inversion fix: `DashboardView.unmarkPlanDay(...)` static call removed from the Data-layer repository. Logic inlined as a private `unmarkPlanDay(_:planID:)` helper directly in `WorkoutPersistenceRepository`, eliminating the Data → Presentation dependency.
- `SummaryView preview` fix: added `_SummaryPreviewPersistenceRepository` private stub to satisfy the `workoutPersistenceRepository:` parameter in the `#Preview` macro. Added `import SwiftData` to `DIContainer` to resolve `PersistenceContainer.shared.mainContext` availability.
- `Wave 5 domain purity`: `LocationServiceProtocol` is now CoreLocation-only while `MapCameraServiceProtocol` owns map camera/search-bias state for the outdoor dashboard. `AIServiceProtocol` and `TrainingPlanLookupServiceProtocol` now own persistence internally, so `CoachViewModel` and `HomeViewModel` no longer thread `ModelContext`. `FitnessViewModel` now consumes `WorkoutMetricsSnapshot` instead of live `Workout` models.
- `Domain extraction closeout`: all remaining SwiftData models were moved out of `Features/*/Domain` into feature `Data/PersistenceModels/` folders, and `TrainingPlanProgress` was split out of `TrainingPlan.swift`.
- `Final audit`: completed a targeted sweep for presentation `ModelContext` usage and concrete service injection. `SettingsDetailViews`, `FTPHistoryView`, `SummaryOnDeviceInsightCard`, and the `DashboardView` bootstrap path no longer thread `ModelContext` from Presentation. Remaining low-priority residuals are app-level or preview-only.
- `Coach`: `PurchasesManager` @Environment reads removed from `CoachConversationView` and `PlanGenerationSheets`. `CoachViewModel` owns `PurchasesServiceProtocol` and exposes `isPro`.
- `Profile`: All concrete @Environment reads removed from `SettingsView`, `ProfileView`, and 6 sub-views in `SettingsDetailViews`. `ProfileViewModel` now owns `HealthKitServiceProtocol` in addition to existing deps. Sub-views take `viewModel: ProfileViewModel` parameter.
- `Fitness`: `HeartRateBarView` dead @Environment(HealthKitManager) removed. All PMC/chart state is feature-owned.
- `Social`: AI caption/title generation state and methods moved into `SocialViewModel`. Share fallback state is feature-owned.
- `Training/FTPTestView`: `FTPTestViewModel` created owning `BLEServiceProtocol` and `DataSourceServiceProtocol`. 3 concrete @Environment reads removed.
- **App-wide**: Waves 2 through 6 are complete and verified with a clean build. Architecture-blocking refactor work is closed out; remaining cleanup is optional and low-priority.

## Definition of done per feature

- Root screen uses a feature-owned presentation model.
- Presentation no longer depends directly on concrete infrastructure services.
- Domain models are framework-light and do not own persistence or UI concerns.
- DI creates the feature graph explicitly.
- Large-screen side effects are isolated enough to profile and test.

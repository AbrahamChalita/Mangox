# Logged Workouts + Day Share — Implementation Plan

Two related features in one plan:

1. **Cross-source non-cycling activity log.** Lets users record off-bike workouts (strength, run, yoga, etc.) by **manual entry**, **Whoop import**, or **Strava import**. Stored locally (SwiftData) + synced to Supabase. Not fed into Coach in v1.
2. **Day Summary share card.** A single shareable Instagram-story card that aggregates *all* of a calendar day's activities — cycling workouts **plus** the new logged activities — into one cohesive 1080×1920 image. Reuses the existing renderer + share pipeline.

---

## 1. Decisions (locked)

| # | Decision | Choice |
|---|----------|--------|
| 1 | Entry point | Header pill in Workouts (Calendar) tab → pushes `LoggedActivitiesView` |
| 2 | Edit imported entries | Notes + RPE editable; source metrics frozen; "View on source" link out |
| 3 | Sync trigger | Auto-on-stale (≥4h, mirrors `refreshLinkedDataIfStale`) **+** manual pull-to-refresh / "Import" button |
| 4 | Import window | First run: last 30 days. Subsequent: "since most recent imported `externalID`" cursor per source |
| 5 | Cycling dedup | Exclude all cycling-shaped activities (Strava `Ride`/`VirtualRide`/`EBikeRide`/`MountainBikeRide`/`GravelRide`/`Handcycle`; Whoop sport-ids 1, 63, 64, 65) — already covered by the `Workout` lane |
| 6 | Coach access | Out of scope for v1 |
| 7 | Supabase | New `logged_activities` table; migration applied via Supabase MCP |
| 8 | Whoop endpoint | `GET /developer/v2/activity/workout` verified — `{records, next_token}` envelope, `limit ≤ 25`, scope `read:workout` |
| 9 | Home dashboard tile | Out of scope for v1 |

---

## 2. Whoop v2 endpoint reference (verified)

```
GET https://api.prod.whoop.com/developer/v2/activity/workout
  ?start=<ISO8601>     // inclusive
  &end=<ISO8601>       // exclusive
  &limit=25            // max 25
  &nextToken=<token>   // pagination

Response:
{
  "records": [
    {
      "id": "<uuid>",
      "v1_id": <int>,
      "user_id": <int>,
      "created_at": "<ts>",
      "updated_at": "<ts>",
      "start": "<ts>",
      "end": "<ts>",
      "timezone_offset": "+02:00",
      "sport_name": "Running",
      "sport_id": 0,
      "score_state": "SCORED",
      "score": {
        "strain": 12.4,
        "average_heart_rate": 142,
        "max_heart_rate": 178,
        "kilojoule": 1820,
        "distance_meter": 9320,
        "zone_durations": { ... }
      }
    }
  ],
  "next_token": "<string|null>"
}
```

Scope: `read:workout` (already requested in `WhoopService` OAuth setup).

---

## 3. Data model

### 3.1 Domain entity (`LoggedActivity`)

Pure-Swift value type used by use cases / view models. Persistence model maps to/from this.

```swift
struct LoggedActivity: Identifiable, Sendable, Hashable {
    let id: UUID
    let source: LoggedActivitySource          // .manual | .whoop | .strava
    let externalID: String?                   // Whoop activity uuid / Strava activity id ("123456789")
    let type: LoggedActivityType              // enum, see below
    let customLabel: String?                  // populated when type == .other
    let startDate: Date
    let durationSeconds: Int
    let intensity: LoggedActivityIntensity?
    let rpe: Int?                             // 1...10
    let notes: String
    let metrics: LoggedActivityMetrics
    let createdAt: Date
    let updatedAt: Date
}

enum LoggedActivitySource: String, Codable, Sendable, CaseIterable {
    case manual, whoop, strava
}

enum LoggedActivityType: String, Codable, Sendable, CaseIterable {
    case run, walk, hike
    case strengthDumbbells, strengthBarbell, strengthBodyweight, strengthMachine
    case yoga, pilates, mobility
    case swim, rowing, climbing
    case hiit, crossfit, boxing, martialArts
    case soccer, basketball, tennis, padel
    case other
}

enum LoggedActivityIntensity: String, Codable, Sendable, CaseIterable {
    case easy, moderate, hard, max
}

struct LoggedActivityMetrics: Codable, Sendable, Hashable {
    var distanceMeters: Double?
    var elevationGainMeters: Double?
    var avgHeartRate: Int?
    var maxHeartRate: Int?
    var calories: Int?
    var sets: Int?
    var reps: Int?
    var weightKg: Double?
    var strain: Double?       // Whoop only
    var kilojoules: Double?   // Strava + Whoop
}
```

### 3.2 SwiftData persistence model (`LoggedActivityRecord`)

Mirrors `Workout` conventions: raw-string enums, `Double`/`Int` sentinels for optionals, single `@Attribute(.unique) id`. Compound dedup `(source, externalID)` enforced at the repository.

```swift
@Model final class LoggedActivityRecord {
    @Attribute(.unique) var id: UUID
    var sourceRaw: String
    var externalID: String?
    var typeRaw: String
    var customLabel: String?
    var startDate: Date
    var durationSeconds: Int
    var intensityRaw: String?
    var rpe: Int               // 0 = nil
    var notes: String

    // Metrics (0 / -1 sentinels — keeps queries cheap, matches Workout)
    var distanceMeters: Double      // -1 = nil
    var elevationGainMeters: Double // -1 = nil
    var avgHeartRate: Int           // 0 = nil
    var maxHeartRate: Int           // 0 = nil
    var calories: Int               // 0 = nil
    var sets: Int                   // 0 = nil
    var reps: Int                   // 0 = nil
    var weightKg: Double            // -1 = nil
    var strain: Double              // -1 = nil
    var kilojoules: Double          // -1 = nil

    var createdAt: Date
    var updatedAt: Date
}
```

### 3.3 Supabase table (migration name: `add_logged_activities`)

```sql
create table public.logged_activities (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    client_id uuid not null,                         -- iOS local UUID (idempotency)
    source text not null check (source in ('manual','whoop','strava')),
    external_id text,                                -- nullable for manual
    activity_type text not null,
    custom_label text,
    start_date timestamptz not null,
    duration_seconds integer not null check (duration_seconds > 0),
    intensity text check (intensity in ('easy','moderate','hard','max')),
    rpe smallint check (rpe between 1 and 10),
    notes text default '',

    -- typed metric columns (nullable)
    distance_meters numeric,
    elevation_gain_meters numeric,
    avg_heart_rate integer,
    max_heart_rate integer,
    calories integer,
    sets integer,
    reps integer,
    weight_kg numeric,
    strain numeric,
    kilojoules numeric,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    unique (user_id, client_id),
    -- Dedup at the database layer for imported rows
    unique (user_id, source, external_id)
);

comment on table public.logged_activities is
  'Non-cycling logged workouts (manual / Whoop / Strava). Cycling lives in workouts.';
comment on column public.logged_activities.client_id is
  'iOS local UUID. Idempotency key for sync upsert.';
comment on column public.logged_activities.external_id is
  'Whoop activity uuid or Strava activity id. NULL for manual entries.';

create index logged_activities_user_start_idx
    on public.logged_activities (user_id, start_date desc);

-- RLS: matches profiles / workouts pattern
alter table public.logged_activities enable row level security;

create policy "logged_activities_select_own"
    on public.logged_activities for select
    using (auth.uid() = user_id);

create policy "logged_activities_insert_own"
    on public.logged_activities for insert
    with check (auth.uid() = user_id);

create policy "logged_activities_update_own"
    on public.logged_activities for update
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

create policy "logged_activities_delete_own"
    on public.logged_activities for delete
    using (auth.uid() = user_id);

-- updated_at trigger (matches existing tables)
create trigger logged_activities_set_updated_at
    before update on public.logged_activities
    for each row execute function public.set_updated_at();
```

> If `set_updated_at()` doesn't exist yet (verify in `list_functions`), inline the `new.updated_at = now()` body or reuse whichever helper the existing tables use.

---

## 4. Architecture / file layout

New feature folder: **`Mangox/Features/ActivityLog/`** with strict three-layer split.

```
Mangox/Features/ActivityLog/
├── Domain/
│   ├── Entities/
│   │   ├── LoggedActivity.swift
│   │   ├── LoggedActivitySource.swift
│   │   ├── LoggedActivityType.swift
│   │   ├── LoggedActivityIntensity.swift
│   │   ├── LoggedActivityMetrics.swift
│   │   └── LoggedActivityDraft.swift
│   ├── Repositories/
│   │   └── LoggedActivityRepository.swift          (protocol)
│   └── UseCases/
│       ├── ImportWhoopWorkoutsUseCase.swift
│       └── ImportStravaActivitiesUseCase.swift
├── Data/
│   ├── PersistenceModels/
│   │   └── LoggedActivityRecord.swift              (@Model)
│   ├── Repositories/
│   │   └── LoggedActivityRepositoryImpl.swift
│   └── Mappers/
│       ├── WhoopWorkoutMapper.swift                (DTO → Draft)
│       └── StravaActivityMapper.swift              (DTO → Draft)
└── Presentation/
    ├── ViewModel/
    │   ├── LoggedActivitiesViewModel.swift
    │   └── LoggedActivityFormViewModel.swift
    └── View/
        ├── LoggedActivitiesView.swift
        ├── LoggedActivityRow.swift
        ├── LoggedActivityFormView.swift
        ├── LoggedActivityDetailView.swift
        └── LoggedActivityIcon.swift
```

### Cross-feature additions

| Path | Purpose |
|---|---|
| `Mangox/Features/Profile/Data/DataSources/WhoopService+Workouts.swift` | Adds `fetchRecentWorkouts(since:until:)` |
| `Mangox/Features/Social/Data/DataSources/StravaService+Activities.swift` | Adds `fetchRecentActivities(since:perPage:)` returning full `SummaryActivity` |
| `Mangox/Core/Networking/Supabase/Mappers/LoggedActivitySyncDomain.swift` | Push/pull sync domain |

---

## 5. Layer-by-layer detail

### 5.1 Domain

**`LoggedActivityRepository` protocol** (`@MainActor`):

```swift
@MainActor protocol LoggedActivityRepository {
    func create(_ draft: LoggedActivityDraft) throws -> LoggedActivity
    func update(_ activity: LoggedActivity) throws
    func delete(id: UUID) throws

    func fetchAll(limit: Int?, source: LoggedActivitySource?) throws -> [LoggedActivity]
    func fetch(id: UUID) throws -> LoggedActivity?

    func existsExternal(source: LoggedActivitySource, externalID: String) throws -> Bool
    func mostRecentExternalDate(source: LoggedActivitySource) throws -> Date?
    func upsertImported(_ batch: [LoggedActivityDraft]) throws -> Int  // returns inserted count
}
```

**Use case shape** (both imports follow the same pattern):

```swift
struct ImportWhoopWorkoutsUseCase {
    let whoop: WhoopServiceProtocol
    let repository: LoggedActivityRepository
    let now: () -> Date

    struct Result { let imported: Int; let skipped: Int }

    func callAsFunction(window: Calendar.Component = .day, count: Int = 30) async throws -> Result {
        let cursor = try repository.mostRecentExternalDate(source: .whoop)
        let since = cursor ?? Calendar.current.date(byAdding: window, value: -count, to: now())!
        let dtos = try await whoop.fetchRecentWorkouts(since: since, until: now())
        let drafts = dtos.compactMap(WhoopWorkoutMapper.draft(from:))   // filters cycling sport-ids
        let inserted = try repository.upsertImported(drafts)
        return .init(imported: inserted, skipped: drafts.count - inserted)
    }
}
```

Strava equivalent uses `StravaActivityMapper` which filters cycling `sport_type` values.

### 5.2 Data

**`LoggedActivityRepositoryImpl`** mirrors `WorkoutPersistenceRepository`:

- Holds a `ModelContext`.
- Domain ↔ persistence mappers in same file (private).
- After every mutation: post `Notification.Name.mangoxLoggedActivitiesAggregatesMayHaveChanged` (mirrors the existing `mangoxWorkoutAggregatesMayHaveChanged` defined in `MangoxModelNotifications.swift`) and invoke an injected `onLocalChange: () -> Void` closure (DIContainer wires this to `syncCoordinator.notifyLocalChange()`).
- `existsExternal(source:externalID:)` issues a single `FetchDescriptor` with predicate on raw enum + externalID.
- `upsertImported`: batch insert with per-item dedup check.

**Whoop service extension** (`WhoopService+Workouts.swift`):

```swift
extension WhoopService {
    public func fetchRecentWorkouts(since: Date, until: Date) async throws -> [WhoopWorkoutDTO] {
        var all: [WhoopWorkoutDTO] = []
        var token: String? = nil
        repeat {
            let page: WhoopWorkoutPage = try await getJSON(
                path: "/developer/v2/activity/workout",
                query: [
                    "start": ISO8601DateFormatter().string(from: since),
                    "end": ISO8601DateFormatter().string(from: until),
                    "limit": "25",
                    "nextToken": token,
                ].compactMapValues { $0 }
            )
            all.append(contentsOf: page.records)
            token = page.next_token
        } while token != nil && all.count < 200   // safety cap
        return all
    }
}

struct WhoopWorkoutPage: Decodable { let records: [WhoopWorkoutDTO]; let next_token: String? }
struct WhoopWorkoutDTO: Decodable { /* fields per §2 */ }
```

Add `fetchRecentWorkouts` to `WhoopServiceProtocol`.

**Strava service extension** (`StravaService+Activities.swift`):

- Promote private `SummaryActivity` to internal and extend with: `name, type, sport_type, distance, moving_time, elapsed_time, total_elevation_gain, average_heartrate, max_heartrate, calories, kilojoules, start_date`.
- Add `fetchRecentActivities(since: Date, perPage: Int = 30) async throws -> [SummaryActivity]` — paginate with `page` param until empty page or `before` cursor. Reuses `athleteActivitiesURL` (verified at `StravaService.swift:211` — currently `private static let`, **bump access to `internal`** so the cross-file extension can read it).
- Update `StravaServiceProtocol`.

**Mappers** (filtering rules):

- `WhoopWorkoutMapper`: skip when `sport_id` ∈ `{1, 63, 64, 65}` (cycling family). Map sport-id → `LoggedActivityType` via static dictionary; unknown → `.other` with `customLabel = sport_name`.
- `StravaActivityMapper`: skip when `sport_type` ∈ `{Ride, VirtualRide, EBikeRide, MountainBikeRide, GravelRide, Handcycle}`. Map remaining `sport_type` strings → `LoggedActivityType`.
- Both mappers populate `externalID` from the source id (Whoop uuid string / Strava activity id stringified).

**Sync domain** (`LoggedActivitySyncDomain.swift`):

- Cursor key `"mangox.sync.logged_activities.cursor"` — append to `SyncCoordinator.cursorKeys`.
- Push: query `LoggedActivityRecord` rows changed since cursor → upsert into Supabase keyed on `(user_id, client_id)`.
- Pull: v1 = no-op (matches `WorkoutSyncDomain`). Add later when multi-device sync ships for cycling.
- Codable `LoggedActivityRow` struct mirrors the Postgres column names (snake_case), maps to/from the SwiftData record.

### 5.3 Presentation

**Routes** (`AppRoute.swift` additions):

```swift
case loggedActivities
case loggedActivityDetail(id: UUID)
case loggedActivityForm(editing: UUID?)
```

Wire destinations in `AppRouter.swift`.

**`LoggedActivitiesViewModel`** (`@Observable @MainActor`):

```swift
@Observable @MainActor
final class LoggedActivitiesViewModel {
    private(set) var activities: [LoggedActivity] = []
    var sourceFilter: LoggedActivitySource? = nil
    private(set) var isImporting = false
    private(set) var lastImportSummary: String? = nil

    let repository: LoggedActivityRepository
    let importWhoop: ImportWhoopWorkoutsUseCase
    let importStrava: ImportStravaActivitiesUseCase
    let whoopConnected: () -> Bool
    let stravaConnected: () -> Bool

    func load() { ... }
    func runWhoopImport() async { ... }
    func runStravaImport() async { ... }
    func refreshIfStale() async { ... }     // 4h cooldown via UserDefaults
    func delete(_ id: UUID) { ... }
}
```

**`LoggedActivityFormViewModel`** — fields bound to `LoggedActivityDraft`. Validates `durationSeconds > 0` and `type != nil`. Save calls `repository.create` (or `update` when editing).

**Views**:

- `LoggedActivitiesView` — `List` grouped by week (use `Dictionary(grouping:by:)` on ISO week, mirrors `CalendarView` density). Toolbar: `+` (manual entry) and "Import" `Menu` ("From Whoop" / "From Strava" — disabled when not connected, with footnote linking to Settings). Pull-to-refresh runs both imports in parallel via `async let`. Empty state with two CTAs ("Add manually", "Connect in Settings").
- `LoggedActivityRow` — `AppColor.bg1` card, type SF Symbol + tint from `LoggedActivityIcon`, source badge ("WHOOP"/"Strava"/"Manual"), date, duration, primary metric (distance for run/walk/hike, sets×reps for strength, etc.).
- `LoggedActivityFormView` — `Form` sections:
  - **Basics**: type `Picker`, custom label (when `.other`), start date, duration (`hours:minutes` `Stepper`s).
  - **Intensity**: band `Picker` + RPE `Slider` (1–10).
  - **Metrics**: type-conditional fields.
    - Strength (`strength*`): sets, reps, weightKg.
    - Run/walk/hike: distance, elevationGain, avgHR, maxHR.
    - Swim/rowing: distance, calories.
    - Yoga/pilates/mobility: just intensity + notes.
  - **Notes**: free text.
- `LoggedActivityDetailView` — readonly card. Manual: edit + delete. Imported: notes + RPE editable inline; "View on Whoop" / "View on Strava" link.
- `LoggedActivityIcon` — single source-of-truth `(LoggedActivityType) -> (String, Color)` mapping for SF Symbol + tint (e.g. `.run → "figure.run"` mango, `.strengthDumbbells → "figure.strengthtraining.traditional"`, `.yoga → "figure.yoga"`).

**`CalendarView` change** — add a header chip:

```swift
HStack {
    Image(systemName: "figure.mixed.cardio")
    Text("Other activities")
    Spacer()
    Text("\(otherActivityCount)").font(.caption).foregroundStyle(.secondary)
    Image(systemName: "chevron.right").font(.caption)
}
.onTapGesture { calendarPath.append(.loggedActivities) }
```

Use a lightweight `@Query` of `LoggedActivityRecord` for the count (cheap; does not load full rows).

---

## 6. DI wiring (`DIContainer.swift`)

> ⚠️ **Verified during sanity check:** `SyncCoordinator.domains` is a **private immutable** stored property and `SyncCoordinator.cursorKeys` is a **`static let`**. Neither can be mutated post-init at runtime — both must be edited at construction / source level.

The domain must be passed in the existing `SyncCoordinator(auth:context:domains:)` initializer call site, alongside the other domains. The cursor key is added by editing the literal in `SyncCoordinator.cursorKeys`'s declaration.

```swift
let loggedActivityRepository: LoggedActivityRepository

init() {
    // ... existing setup ...
    let repo = LoggedActivityRepositoryImpl(
        modelContext: PersistenceContainer.shared.mainContext,
        onLocalChange: { [weak self] in self?.syncCoordinator?.notifyLocalChange() }
    )
    self.loggedActivityRepository = repo

    // SyncCoordinator: pass the new domain through the existing constructor — DO NOT
    // attempt to mutate `domains` afterward (it's private/immutable).
    self.syncCoordinator = SyncCoordinator(
        auth: ...,
        context: PersistenceContainer.shared.mainContext,
        domains: [
            // existing domains, in their existing order...
            LoggedActivitySyncDomain(/* deps */),
        ]
    )
}

@MainActor func makeLoggedActivitiesViewModel() -> LoggedActivitiesViewModel {
    LoggedActivitiesViewModel(
        repository: loggedActivityRepository,
        importWhoop: ImportWhoopWorkoutsUseCase(
            whoop: whoopService,
            repository: loggedActivityRepository,
            now: { Date() }
        ),
        importStrava: ImportStravaActivitiesUseCase(
            strava: stravaService,
            repository: loggedActivityRepository,
            now: { Date() }
        ),
        whoopConnected: { [whoopService] in whoopService.isConnected },
        stravaConnected: { [stravaService] in stravaService.isConnected }
    )
}

@MainActor func makeLoggedActivityFormViewModel(editing: UUID?) -> LoggedActivityFormViewModel {
    LoggedActivityFormViewModel(
        repository: loggedActivityRepository,
        editing: editing
    )
}
```

`PersistenceContainer.swift` — register `LoggedActivityRecord.self` in the `Schema([...])` array.

`SyncCoordinator.cursorKeys` — append the new cursor key.

---

## 7. Stale-data refresh logic

Mirrors `refreshLinkedDataIfStale` already used for Whoop recovery / Strava bikes.

```swift
func refreshIfStale() async {
    let key = "mangox.activityLog.lastImport"
    let last = UserDefaults.standard.object(forKey: key) as? Date ?? .distantPast
    guard Date().timeIntervalSince(last) > 4 * 3600 else { return }
    async let w = runWhoopImport()
    async let s = runStravaImport()
    _ = await (w, s)
    UserDefaults.standard.set(Date(), forKey: key)
}
```

Called from `LoggedActivitiesView.task { await viewModel.refreshIfStale() }`.

---

## 8. Files

### Create (19)

```
Mangox/Features/ActivityLog/Domain/Entities/LoggedActivity.swift
Mangox/Features/ActivityLog/Domain/Entities/LoggedActivitySource.swift
Mangox/Features/ActivityLog/Domain/Entities/LoggedActivityType.swift
Mangox/Features/ActivityLog/Domain/Entities/LoggedActivityIntensity.swift
Mangox/Features/ActivityLog/Domain/Entities/LoggedActivityMetrics.swift
Mangox/Features/ActivityLog/Domain/Entities/LoggedActivityDraft.swift
Mangox/Features/ActivityLog/Domain/Repositories/LoggedActivityRepository.swift
Mangox/Features/ActivityLog/Domain/UseCases/ImportWhoopWorkoutsUseCase.swift
Mangox/Features/ActivityLog/Domain/UseCases/ImportStravaActivitiesUseCase.swift
Mangox/Features/ActivityLog/Data/PersistenceModels/LoggedActivityRecord.swift
Mangox/Features/ActivityLog/Data/Repositories/LoggedActivityRepositoryImpl.swift
Mangox/Features/ActivityLog/Data/Mappers/WhoopWorkoutMapper.swift
Mangox/Features/ActivityLog/Data/Mappers/StravaActivityMapper.swift
Mangox/Features/Profile/Data/DataSources/WhoopService+Workouts.swift
Mangox/Features/Social/Data/DataSources/StravaService+Activities.swift
Mangox/Core/Networking/Supabase/Mappers/LoggedActivitySyncDomain.swift
Mangox/Features/ActivityLog/Presentation/ViewModel/LoggedActivitiesViewModel.swift
Mangox/Features/ActivityLog/Presentation/ViewModel/LoggedActivityFormViewModel.swift
Mangox/Features/ActivityLog/Presentation/View/LoggedActivitiesView.swift
Mangox/Features/ActivityLog/Presentation/View/LoggedActivityRow.swift
Mangox/Features/ActivityLog/Presentation/View/LoggedActivityFormView.swift
Mangox/Features/ActivityLog/Presentation/View/LoggedActivityDetailView.swift
Mangox/Features/ActivityLog/Presentation/View/LoggedActivityIcon.swift
```

### Modify (9)

```
Mangox/Core/Persistence/PersistenceContainer.swift           (register @Model)
Mangox/App/AppRoute.swift                                    (3 cases)
Mangox/App/AppRouter.swift                                   (destinations)
Mangox/App/DIContainer.swift                                 (repo + factories + sync domain)
Mangox/Features/Profile/Domain/Repositories/WhoopServiceProtocol.swift
Mangox/Features/Social/Domain/Repositories/StravaServiceProtocol.swift
Mangox/Features/Training/Presentation/View/CalendarView.swift   (header chip)
Mangox/Core/Networking/Supabase/SyncCoordinator.swift        (cursor key)
Mangox/en.lproj/Localizable.strings                          (UI strings)
```

---

## 9. Test plan

- **Unit**: `LoggedActivityRepositoryImplTests` — CRUD, dedup via `existsExternal`, `upsertImported` returns correct insert count, cycling sport-id filter in `WhoopWorkoutMapper` and `StravaActivityMapper`.
- **Unit**: `ImportWhoopWorkoutsUseCaseTests` / `ImportStravaActivitiesUseCaseTests` with mock services — first-run window of 30 days, cursor advancement on subsequent runs.
- **UI smoke** (manual on device): manual entry round-trip, edit notes on imported entry (other fields locked), import with no Whoop connection (button disabled, footnote visible), pull-to-refresh, week grouping, empty state CTAs.
- **Sync**: insert manual entry → kill app → reopen on second device with same account → row appears (gates on whether pull is implemented in v1; for v1 we ship push-only and confirm the row lands in Supabase via dashboard).

---

## 10. Day Summary share card

A new card type rendered by the existing `InstagramStoryCardRenderer` pipeline that aggregates every activity on a given calendar day into one shareable image.

### 10.1 What's reused vs. new

| Existing (reuse) | New (build) |
|---|---|
| `InstagramStoryCardRenderer` 1080×1920 `UIGraphicsImageRenderer` core (`Mangox/Features/Social/Data/DataSources/InstagramStoryCardRenderer.swift`) | `DaySummary` aggregator entity |
| `StoryCardDrawing` primitives (panels, zone bars, stat tiles, gradients) | `DaySummaryCardOptions` (parallel to `InstagramStoryCardOptions`) |
| `InstagramStoryShare` Meta Stories API + pasteboard + URL scheme (`InstagramStoryShare.swift`) | 4 new day-card templates (`StoryCardDrawing.drawDay…`) |
| `InstagramStoryStudioView` customize sheet, render debounce, save-to-photos, carousel export | `DaySummaryStudioView` (forked, accepts the aggregate not a single `Workout`) |
| `privacyHideRoute / privacyHidePower / privacyHideHeartRate` toggles | Calendar day-cell tap → "Share day" entry point |

### 10.2 `DaySummary` entity

New file `Mangox/Features/Social/Domain/Entities/DaySummary.swift`:

```swift
struct DaySummary: Sendable, Hashable {
    let date: Date                                  // start-of-day in user's calendar
    let cyclingWorkouts: [Workout]                  // existing entity
    let loggedActivities: [LoggedActivity]          // from §3.1
    // Aggregate roll-ups (computed at construction)
    let totalDurationSeconds: Int
    let totalDistanceMeters: Double                 // cycling + run + walk + hike + swim + rowing
    let totalElevationGainMeters: Double
    let totalKilojoules: Double                     // cycling + Whoop/Strava-provided kJ
    let totalTSS: Double?                           // cycling only — nil if no cycling workouts
    let combinedAvgHeartRate: Int?                  // duration-weighted across all activities
    let activityCount: Int                          // cyclingWorkouts.count + loggedActivities.count
    let dominantZone: PowerZone?                    // cycling only
    let primaryEnvironment: WorkoutEnvironment?     // .indoor/.outdoor/.virtual/.mixed
    let prHighlights: [WorkoutPR]                   // surfaced on the card
}
```

Builder lives in `Mangox/Features/Social/Domain/UseCases/BuildDaySummaryUseCase.swift` — pulls from `WorkoutRepository` + `LoggedActivityRepository`, scoped to `[startOfDay, startOfNextDay)`.

### 10.3 New card templates

Add to `InstagramStoryCardOptions.Template`:

```swift
case dayHeroStack          // big date headline, vertical stack of activity tiles
case dayMosaic             // 2-up grid of activity tiles, hero stat at top
case dayTimelineRibbon     // horizontal timeline ribbon (sunrise→sunset) with activity beads
case dayMinimalist         // single big number (total duration), tiny activity icons row
```

Each renders a row/tile per activity: type icon (from `LoggedActivityIcon`), label, duration, headline metric (distance for run/walk; sets×reps×weight for strength; power/TSS for cycling). Cycling rows use the existing tile style; logged activities use a parallel style with mango accent.

**Layout sketch (`dayHeroStack`)**:

```
┌──────────────────────────────────┐
│  TUESDAY · MAR 12                │  ← eyebrow
│                                  │
│  3 activities · 2h 14m           │  ← hero
│  41 km · 612 m · 1,820 kJ        │  ← roll-up stats row
│                                  │
│  ┌──────────────────────────┐    │
│  │ 🚴 Outdoor ride · 1h 22m │    │
│  │ 32 km · 240 W · 78 TSS   │    │
│  └──────────────────────────┘    │
│  ┌──────────────────────────┐    │
│  │ 🏃 Run · 32 m            │    │
│  │ 5.2 km · 156 bpm         │    │
│  └──────────────────────────┘    │
│  ┌──────────────────────────┐    │
│  │ 🏋️ Dumbbells · 20 m      │    │
│  │ RPE 7 · 5×8 @ 22 kg      │    │
│  └──────────────────────────┘    │
│                                  │
│           MANGOX · @user         │  ← footer
└──────────────────────────────────┘
```

### 10.4 Privacy

`DaySummaryCardOptions` carries the same three toggles as `InstagramStoryCardOptions` plus a new `hideStrengthLoad: Bool` (some users don't want to broadcast lifting numbers). When toggled on, strength activities show only duration + RPE.

If *any* per-activity privacy flag was set when the originals were saved (e.g. a particular workout was marked `privacyHideRoute`), the day card respects the union — i.e. hides that field globally on the day card. Implemented in `BuildDaySummaryUseCase`.

### 10.5 Entry points

1. **Calendar day cell** — verified `dayCell(date:)` at `CalendarView.swift:655` returns a SwiftUI `some View`, so attaching a `.contextMenu { Button("Share day") { router.push(.daySummaryStudio(date: date)) } }` modifier works directly. Hide the menu item when the day has zero activities.
2. **Day detail screen** (if you have one — verify in `CalendarView`'s detail destination; otherwise add a small "Share this day" button at the top of the day's activity list).
3. **Logged Activities list** — when the list is filtered to a single day, show a "Share day" toolbar item.

### 10.6 New routes

```swift
case daySummaryStudio(date: Date)
```

Wire in `AppRouter.swift`. Destination instantiates `DaySummaryStudioView` via `DIContainer.makeDaySummaryStudioViewModel(date:)`.

### 10.7 `DaySummaryStudioView` + ViewModel

Fork `InstagramStoryStudioView` (1015 lines — large; keep it as a parallel file to avoid destabilizing the working per-workout flow). Differences:

- Header reads "Share day" with the date.
- Template carousel offers only the four `day*` templates.
- Customize sheet:
  - **Stat slots**: pick which roll-up stats appear in the hero row (max 3 of: total time, total distance, total elevation, total kJ, total TSS, activity count).
  - **Activity ordering**: chronological / by duration / manual (drag).
  - **Privacy**: hideRoute / hidePower / hideHeartRate / hideStrengthLoad.
  - **Background**: same options as per-workout (gradient presets, photo, dominant-zone tint).
- Reuses `schedulePreviewRenderDebounced` (220 ms coalesce).
- Reuses `InstagramStoryShare.presentStories` + carousel save-to-photos (3 slides could be: the day card + the two highest-effort activities' individual cards — out of scope for v1, but the option flag should exist so we can light it up later).

Lives at `Mangox/Features/Social/Presentation/View/DaySummaryStudioView.swift` + `Mangox/Features/Social/Presentation/ViewModel/DaySummaryStudioViewModel.swift`.

### 10.8 Renderer additions

> ⚠️ **Verified during sanity check:** `StoryCardDrawing` is currently `private` to `InstagramStoryCardRenderer.swift`. A cross-file extension (`+Day.swift`) cannot see it. **Promote `StoryCardDrawing` to `internal`** as a one-line access-level change so the day-rendering extension can reuse the primitives without duplicating them. (Alternative: keep day rendering inline in the renderer file — viable but bloats an already-1622-line file. Promotion is the cleaner choice.)

Then in `InstagramStoryCardRenderer+Day.swift`, add the overload:

```swift
func renderDaySummary(
    summary: DaySummary,
    options: DaySummaryCardOptions,
    background: UIImage?
) -> UIImage
```

It dispatches to a new `StoryCardDrawing.drawDay…` family — one method per day template. Drawing primitives (`drawPanel`, `drawZoneBar`, `drawStatTile`, font ramps, gradient backgrounds) are reused as-is.

### 10.9 Files

**Create (8):**
```
Mangox/Features/Social/Domain/Entities/DaySummary.swift
Mangox/Features/Social/Domain/Entities/DaySummaryCardOptions.swift
Mangox/Features/Social/Domain/UseCases/BuildDaySummaryUseCase.swift
Mangox/Features/Social/Presentation/ViewModel/DaySummaryStudioViewModel.swift
Mangox/Features/Social/Presentation/View/DaySummaryStudioView.swift
Mangox/Features/Social/Presentation/View/DaySummaryActivityTile.swift   (shared row used by templates)
Mangox/Features/Social/Data/DataSources/InstagramStoryCardRenderer+Day.swift   (extension with drawDay… funcs)
MangoxTests/DaySummaryBuilderTests.swift
```

**Modify (4):**
```
Mangox/Features/Social/Domain/Entities/InstagramStoryCardOptions.swift   (add 4 day templates to enum)
Mangox/Features/Training/Presentation/View/CalendarView.swift            (long-press menu + button)
Mangox/App/AppRoute.swift                                                 (daySummaryStudio case)
Mangox/App/AppRouter.swift                                                (destination)
Mangox/App/DIContainer.swift                                              (factory)
```

### 10.10 Open questions for the day-share feature

1. **Mixed cycling+strength rendering** — do strength activities show RPE on the public card, or treat RPE as private by default? (Recommend public; it's a normal training metric.)
2. **Empty day** — should "Share day" be available on a day with zero activities? (Recommend no — hide the menu item.)
3. **Future Apple Health activities** — when Apple Health import lands as a fourth source, the day summary picks them up automatically because it queries the repositories, not a specific source.
4. **Carousel export** — v1 day card is single image. Carousel mode (day card + top-N individual workout cards) is the obvious follow-up; add the option toggle but stub the export until v1.1.

---

## 11. Rollout sequence

1. Apply Supabase migration `add_logged_activities`.
2. **Logged Workouts** — domain → data → sync → presentation (entities, repo protocol, use cases, SwiftData model, repo impl, service extensions, mappers, sync domain, DI, views, calendar header chip).
3. **Day Summary share** — `DaySummary` entity + builder, renderer extension + day templates, `DaySummaryStudioView`, calendar entry point.
4. Tests (logged-activity repo + day-summary builder).
5. Manual device verification: manual entry, Whoop import, Strava import, day card share for a day with mixed cycling + logged activities.

---

## 12. Sanity-check log (pre-implementation)

Verified against the live codebase + Supabase project on 2026-05-06:

| Check | Result |
|---|---|
| `public.set_updated_at()` exists in Supabase | ✅ confirmed via `pg_proc` query |
| Deployment target supports `@Observable` / `@Model` | ✅ iOS 26.2 (year-versioned) — well above iOS 17 minimum |
| `WhoopService.getJSON` helper exists | ✅ |
| `WhoopServiceProtocol` exists at planned path | ✅ |
| Whoop v2 endpoint shape | ✅ `GET /developer/v2/activity/workout`, `{records, next_token}` envelope, `limit ≤ 25`, scope `read:workout` |
| `StravaService.SummaryActivity` private | ✅ — plan promotes to `internal` |
| `StravaService.athleteActivitiesURL` exists | ✅ at line 211; **must be bumped from `private` to `internal`** for cross-file extension access |
| `CalendarView.dayCell(date:)` is a `some View` func | ✅ at line 655 — `.contextMenu` modifier works |
| `AppRoute` / `AppRouter` switch-dispatch pattern | ✅ matches plan |
| `SyncCoordinator.notifyLocalChange()` exists | ✅ at line 110 |
| `SyncCoordinator.domains` mutability | ⚠️ **private immutable** — must be passed via `init(domains:)`, not appended afterward. Plan §6 updated. |
| `SyncCoordinator.cursorKeys` mutability | ⚠️ **`static let`** — addition is a source-code edit to the literal array, not a runtime append |
| `StoryCardDrawing` reachable from extension | ⚠️ currently **`private`** to file — plan §10.8 updated to require bumping to `internal` |
| Existing notification name pattern | ⚠️ existing convention is `mangoxWorkoutAggregatesMayHaveChanged` (defined in `MangoxModelNotifications.swift`); plan updated to use `mangoxLoggedActivitiesAggregatesMayHaveChanged` to mirror it |
| `PersistenceContainer` schema array | ✅ exists; plan adds `LoggedActivityRecord.self` |
| `refreshLinkedDataIfStale` 4h-cooldown pattern | ✅ exists in WhoopService — reused for the activity-log auto-refresh |

No remaining open blockers.

---

## 13. Out of scope (explicit, for future tickets)

- Coach reading logged activities for recommendations.
- Home dashboard summary tile ("this week: 2 runs, 1 yoga").
- Apple Health import (separate source — would slot in as `.appleHealth` on `LoggedActivitySource`).
- Strain / training-load modeling combining cycling + non-cycling.
- Multi-device pull-sync of logged activities (v1 push-only, mirrors `WorkoutSyncDomain`).

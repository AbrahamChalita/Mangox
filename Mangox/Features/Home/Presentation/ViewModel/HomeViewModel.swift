import CoreBluetooth
import Foundation

// Features/Home/Presentation/ViewModel/HomeViewModel.swift

@MainActor
@Observable
final class HomeViewModel {
    // MARK: - Dependencies
    private let bleService: BLEServiceProtocol
    private let dataSourceService: DataSourceServiceProtocol
    private let locationService: LocationServiceProtocol
    private let whoopService: WhoopServiceProtocol
    private let aiService: AIServiceProtocol
    let trainingPlanLookupService: TrainingPlanLookupServiceProtocol
    private let syncExternalCyclingWorkouts: SyncExternalCyclingWorkoutsUseCase

    private let trainingAggregator:
        @Sendable ([HomeWorkoutMetricSlice], Date, TimeZone, Locale) -> HomeTrainingCacheDTO

    // MARK: - View state
    var weeklyTSS: Double = 0
    var chronicLoad: Double = 0
    var acwr: Double = 0
    var weekRides: Int = 0
    var weekBars: [HomeWeekBarDTO] = []
    var homeTrainingStatusLabel: String?
    var hasComputedTrainingState = false
    var trainingStatusRequestID: UInt64 = 0

    private var trainingCacheRecomputeTask: Task<Void, Never>?
    private var trainingCacheGeneration: UInt64 = 0
    private var trainingCacheHasSeenData = false

    // MARK: - Whoop computed properties

    var whoopConnected: Bool { whoopService.isConnected }
    var whoopConfigured: Bool { whoopService.isConfigured }
    var whoopRecoveryScore: Double? { whoopService.latestRecoveryScore }
    var whoopRestingHR: Int? { whoopService.latestRecoveryRestingHR }
    var whoopHRV: Int? { whoopService.latestRecoveryHRV }
    var whoopLastRefreshAt: Date? { whoopService.lastSuccessfulRefreshAt }

    // MARK: - BLE / connectivity computed properties

    var bleBluetoothState: CBManagerState { bleService.bluetoothState }
    var isTrainerConnected: Bool { bleService.trainerConnectionState.isConnected }
    var isWifiConnected: Bool { dataSourceService.wifiConnectionState.isConnected }

    // MARK: - FTP computed properties

    var ftp: Int { PowerZone.ftp }
    var hasSetFTP: Bool { PowerZone.hasSetFTP }
    var lastFTPUpdate: Date? { PowerZone.lastFTPUpdate }

    // MARK: - Init

    init(
        bleService: BLEServiceProtocol,
        dataSourceService: DataSourceServiceProtocol,
        locationService: LocationServiceProtocol,
        whoopService: WhoopServiceProtocol,
        aiService: AIServiceProtocol,
        trainingPlanLookupService: TrainingPlanLookupServiceProtocol,
        syncExternalCyclingWorkouts: SyncExternalCyclingWorkoutsUseCase,
        trainingAggregator: @escaping @Sendable (
            [HomeWorkoutMetricSlice], Date, TimeZone, Locale
        ) -> HomeTrainingCacheDTO = HomeTrainingAggregateMath.compute
    ) {
        self.bleService = bleService
        self.dataSourceService = dataSourceService
        self.locationService = locationService
        self.whoopService = whoopService
        self.aiService = aiService
        self.trainingPlanLookupService = trainingPlanLookupService
        self.syncExternalCyclingWorkouts = syncExternalCyclingWorkouts
        self.trainingAggregator = trainingAggregator
    }

    // MARK: - Lifecycle methods

    /// Prepares location services for Home. Trainer/Wi‑Fi reconnect is **not** started here — only after opening
    /// Indoor Ride, Outdoor Ride, or related connection screens (see `ConnectionView` / `OutdoorViewModel`).
    func prewarmLocationServices() {
        locationService.setup()
    }

    /// Refreshes WHOOP data if stale (4-hour threshold matching the concrete default).
    func refreshWhoopIfStale() async {
        await whoopService.refreshLinkedDataIfStale(maximumAge: 4 * 60 * 60)
    }

    /// Pulls Strava/WHOOP cycling rides into the calendar and auto-completes matching plan days.
    func refreshExternalCyclingIfStale() async {
        await syncExternalCyclingWorkouts.refreshIfStale()
    }

    /// Generates an on-device AI training insight label using the fact sheet from aiService.
    func generateAITrainingInsight() async {
        guard hasComputedTrainingState, OnDeviceCoachEngine.isSystemModelAvailable else {
            updateHomeTrainingStatusLabel(nil)
            return
        }
        let factSheet = aiService.coachFactSheetText()
        let label = try? await OnDeviceCoachEngine.generateHomeTrainingInsight(factSheet: factSheet)
        guard !Task.isCancelled else { return }
        updateHomeTrainingStatusLabel(label)
    }

    // MARK: - Training cache

    func scheduleTrainingRefresh(workouts: [Workout], activities: [LoggedActivityRecord]) {
        if workouts.isEmpty && activities.isEmpty {
            trainingCacheRecomputeTask?.cancel()
            trainingCacheGeneration += 1
            trainingCacheHasSeenData = false
            let dto = trainingAggregator([], Date(), .current, .current)
            apply(dto)
            return
        }

        if !trainingCacheHasSeenData {
            trainingCacheHasSeenData = true
            trainingCacheRecomputeTask?.cancel()
            Task { @MainActor [weak self] in
                await self?.runTrainingCacheGeneration(workouts: workouts, activities: activities)
            }
            return
        }

        trainingCacheRecomputeTask?.cancel()
        if !hasComputedTrainingState {
            Task { @MainActor [weak self] in
                await self?.runTrainingCacheGeneration(workouts: workouts, activities: activities)
            }
            return
        }

        trainingCacheRecomputeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            await self?.runTrainingCacheGeneration(workouts: workouts, activities: activities)
        }
    }

    func updateHomeTrainingStatusLabel(_ label: String?) {
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        homeTrainingStatusLabel = (trimmed?.isEmpty == false) ? trimmed : nil
    }

    func nextScheduledWorkout(allProgress: [TrainingPlanProgress]) -> ScheduledTrainingDay? {
        trainingPlanLookupService.nextScheduledWorkout(allProgress: allProgress)
    }

    private func runTrainingCacheGeneration(
        workouts: [Workout],
        activities: [LoggedActivityRecord]
    ) async {
        trainingCacheGeneration += 1
        let generation = trainingCacheGeneration
        let profile = LoggedActivityTSSEstimator.Profile.current()
        var slices = workouts.map { HomeWorkoutMetricSlice(startDate: $0.startDate, tss: $0.tss) }
        slices.reserveCapacity(slices.count + activities.count)
        for record in activities {
            let domain = record.toDomain()
            let tss = LoggedActivityTSSEstimator.estimate(domain, profile: profile)
            slices.append(HomeWorkoutMetricSlice(startDate: domain.startDate, tss: tss))
        }
        let now = Date()
        let timeZone = TimeZone.current
        let locale = Locale.current
        let aggregator = trainingAggregator
        let dto = await Self.computeTrainingCacheDTO(
            slices: slices,
            now: now,
            timeZone: timeZone,
            locale: locale,
            aggregator: aggregator
        )
        guard let dto else { return }
        guard !Task.isCancelled else { return }
        guard generation == trainingCacheGeneration else { return }
        apply(dto)
    }

    private nonisolated static func computeTrainingCacheDTO(
        slices: [HomeWorkoutMetricSlice],
        now: Date,
        timeZone: TimeZone,
        locale: Locale,
        aggregator: @escaping @Sendable ([HomeWorkoutMetricSlice], Date, TimeZone, Locale) -> HomeTrainingCacheDTO
    ) async -> HomeTrainingCacheDTO? {
        await Task.detached(priority: .utility) {
            guard !Task.isCancelled else { return nil }
            return aggregator(slices, now, timeZone, locale)
        }.value
    }

    private func apply(_ dto: HomeTrainingCacheDTO) {
        weeklyTSS = dto.weeklyTSS
        chronicLoad = dto.chronicLoad
        acwr = dto.acwr
        weekRides = dto.weekRides
        weekBars = dto.weekBars
        hasComputedTrainingState = true
        trainingStatusRequestID &+= 1
    }
}

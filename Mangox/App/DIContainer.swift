// App/DIContainer.swift
import Foundation
import SwiftData

/// Assembles and owns all app-level dependencies.
///
/// Concrete implementations are created here. Protocol-typed properties are exposed
/// so ViewModels depend on contracts rather than concrete classes.
/// Inject as `@Environment(DIContainer.self)` in views that create ViewModels.
/// Individual concrete services are also injected separately for legacy @Environment usage.
@MainActor
@Observable
final class DIContainer {

    // MARK: - Indoor / BLE infrastructure (concrete — used by DashboardView directly)

    let bleManager: BLEManager
    let wifiTrainerService: WiFiTrainerService
    let dataSourceCoordinator: DataSourceCoordinator

    // MARK: - Navigation (concrete)

    let routeManager: RouteManager
    let locationManager: LocationManager

    // MARK: - Fitness & Health (protocol-typed for ViewModel injection)

    let healthKitManager: HealthKitManager
    var healthKitService: HealthKitServiceProtocol { healthKitManager }
    var locationService: LocationServiceProtocol { locationManager }
    var mapCameraService: MapCameraServiceProtocol { locationManager }

    let fitnessTracker: FitnessTracker
    var fitnessTrackerService: FitnessTrackerProtocol { fitnessTracker }

    // MARK: - Workout utilities

    let personalRecords: PersonalRecords
    let liveActivityManager: RideLiveActivityManager

    // MARK: - External services (protocol-typed for ViewModel injection)

    let stravaService: StravaService

    let whoopService: WhoopService
    var whoopServiceProtocol: WhoopServiceProtocol { whoopService }

    let purchasesManager: PurchasesManager
    var purchasesServiceProtocol: PurchasesServiceProtocol { purchasesManager }

    let aiService: AIService
    var coachRepository: CoachRepository { aiService }

    let ftpRefreshTrigger: FTPRefreshTrigger
    let trainingPlanLookupService: TrainingPlanLookupServiceProtocol
    let workoutPersistenceRepository: WorkoutPersistenceRepositoryProtocol
    let trainingPlanPersistenceRepository: TrainingPlanPersistenceRepositoryProtocol
    let loggedActivityRepository: LoggedActivityRepository
    let syncExternalCyclingWorkouts: SyncExternalCyclingWorkoutsUseCase

    // MARK: - Cloud sync (Supabase)

    let authState: AuthState
    let linkedOAuthBridge: LinkedOAuthSessionBridge
    let syncCoordinator: SyncCoordinator

    // MARK: - ViewModels (lazily vended; each VM owns its own lifecycle)

    /// Reused while an indoor workout is recording or paused so Live Activity / Dynamic Island deep links
    /// that recreate `DashboardView` do not start a new `WorkoutManager` session.
    private var retainedIndoorViewModel: IndoorViewModel?

    func makeCoachViewModel() -> CoachViewModel {
        CoachViewModel(coach: aiService, purchasesService: purchasesServiceProtocol)
    }

    func makeHomeViewModel() -> HomeViewModel {
        HomeViewModel(
            bleService: bleManager,
            dataSourceService: dataSourceCoordinator,
            locationService: locationManager,
            whoopService: whoopServiceProtocol,
            aiService: aiService,
            trainingPlanLookupService: trainingPlanLookupService,
            syncExternalCyclingWorkouts: syncExternalCyclingWorkouts
        )
    }

    func makeFitnessViewModel() -> FitnessViewModel {
        FitnessViewModel(
            fitnessTracker: fitnessTrackerService,
            healthKit: healthKitService,
            trainingPlanLookupService: trainingPlanLookupService
        )
    }

    func makeProfileViewModel() -> ProfileViewModel {
        ProfileViewModel(
            whoopService: whoopServiceProtocol,
            purchasesService: purchasesServiceProtocol,
            stravaService: stravaService,
            ftpRefreshTrigger: ftpRefreshTrigger,
            healthKitService: healthKitService,
            aiService: aiService
        )
    }

    func makePaywallViewModel() -> PaywallViewModel {
        PaywallViewModel(purchasesService: purchasesServiceProtocol)
    }

    func makeIndoorViewModel() -> IndoorViewModel {
        if let vm = retainedIndoorViewModel, vm.workoutManager.state.isLiveSessionActive {
            return vm
        }
        let vm = IndoorViewModel(
            bleService: bleManager,
            dataSourceService: dataSourceCoordinator,
            routeService: routeManager,
            healthKitService: healthKitService,
            liveActivityService: liveActivityManager,
            workoutPersistenceRepository: workoutPersistenceRepository,
            trainingPlanPersistenceRepository: trainingPlanPersistenceRepository
        )
        retainedIndoorViewModel = vm
        return vm
    }

    func persistIndoorRecordingCheckpointNow() {
        retainedIndoorViewModel?.persistRecordingCheckpointNow()
    }
    func makeOutdoorViewModel() -> OutdoorViewModel {
        OutdoorViewModel(
            locationService: locationManager,
            bleService: bleManager,
            routeService: routeManager,
            healthKitService: healthKitManager,
            liveActivityService: liveActivityManager,
            workoutPersistenceRepository: workoutPersistenceRepository,
            trainingPlanPersistenceRepository: trainingPlanPersistenceRepository
        )
    }
    func makeSocialViewModel() -> SocialViewModel {
        SocialViewModel(whoopService: whoopServiceProtocol)
    }
    func makeTrainingViewModel() -> TrainingViewModel {
        TrainingViewModel(
            whoopService: whoopServiceProtocol,
            purchasesService: purchasesServiceProtocol,
            persistenceRepository: trainingPlanPersistenceRepository
        )
    }
    func makeLoggedActivitiesViewModel(lockedDate: Date? = nil) -> LoggedActivitiesViewModel {
        LoggedActivitiesViewModel(
            repository: loggedActivityRepository,
            importWhoop: ImportWhoopWorkoutsUseCase(
                whoopService: whoopServiceProtocol,
                repository: loggedActivityRepository
            ),
            importStrava: ImportStravaActivitiesUseCase(
                stravaService: stravaService,
                repository: loggedActivityRepository
            ),
            syncExternalCycling: syncExternalCyclingWorkouts,
            whoopConnected: { [weak self] in self?.whoopService.isConnected ?? false },
            stravaConnected: { [weak self] in self?.stravaService.isConnected ?? false },
            lockedDate: lockedDate
        )
    }

    func makeLoggedActivityFormViewModel(editing id: UUID? = nil) -> LoggedActivityFormViewModel {
        LoggedActivityFormViewModel(repository: loggedActivityRepository, editingID: id)
    }

    func makeDaySummaryStudioViewModel(for date: Date) -> DaySummaryStudioViewModel {
        DaySummaryStudioViewModel(
            date: date,
            modelContext: PersistenceContainer.shared.mainContext,
            repository: loggedActivityRepository,
            enrichStravaStreams: EnrichStravaStreamsUseCase(
                stravaService: stravaService,
                repository: loggedActivityRepository
            )
        )
    }

    func makeWorkoutViewModel() -> WorkoutViewModel {
        WorkoutViewModel(
            stravaService: stravaService,
            routeService: routeManager,
            personalRecordsService: personalRecords,
            healthKitService: healthKitManager,
            trainingPlanLookupService: trainingPlanLookupService,
            workoutPersistenceRepository: workoutPersistenceRepository
        )
    }
    func makeFTPTestViewModel() -> FTPTestViewModel {
        FTPTestViewModel(
            bleService: bleManager,
            dataSourceService: dataSourceCoordinator
        )
    }
    func makeOnboardingViewModel() -> OnboardingViewModel {
        OnboardingViewModel(
            healthKitService: healthKitService,
            locationService: locationManager,
            stravaService: stravaService
        )
    }

    // MARK: - Init

    init() {
        let ble = BLEManager()
        let wifi = WiFiTrainerService()
        bleManager = ble
        wifiTrainerService = wifi
        dataSourceCoordinator = DataSourceCoordinator(bleManager: ble, wifiService: wifi)
        routeManager = RouteManager()
        locationManager = LocationManager()
        healthKitManager = HealthKitManager()
        fitnessTracker = FitnessTracker.shared
        personalRecords = PersonalRecords.shared
        liveActivityManager = RideLiveActivityManager.shared
        let strava = StravaService()
        let whoop = WhoopService()
        stravaService = strava
        whoopService = whoop
        purchasesManager = PurchasesManager.shared
        ftpRefreshTrigger = FTPRefreshTrigger.shared
        trainingPlanLookupService = TrainingPlanLookupService()
        workoutPersistenceRepository = WorkoutPersistenceRepository(
            modelContext: PersistenceContainer.shared.mainContext,
            modelContainer: PersistenceContainer.shared
        )
        aiService = AIService(workoutPersistence: workoutPersistenceRepository)
        trainingPlanPersistenceRepository = TrainingPlanPersistenceRepository(
            modelContext: PersistenceContainer.shared.mainContext
        )

        let auth = AuthState()
        authState = auth

        linkedOAuthBridge = LinkedOAuthSessionBridge(
            strava: strava,
            whoop: whoop,
            userId: { [weak auth] in auth?.userId }
        )
        strava.linkedOAuthBridge = linkedOAuthBridge
        whoop.linkedOAuthBridge = linkedOAuthBridge

        let activityRepo = LoggedActivityRepositoryImpl(
            modelContext: PersistenceContainer.shared.mainContext
        )
        loggedActivityRepository = activityRepo

        syncCoordinator = SyncCoordinator(
            auth: auth,
            context: PersistenceContainer.shared.mainContext,
            domains: [
                ProfileSyncDomain(),
                UserSettingsSyncDomain(),
                WorkoutSyncDomain(),
                ChatSyncDomain(),
                AIGeneratedPlanSyncDomain(),
                TrainingPlanProgressSyncDomain(),
                ZoneSnapshotSyncDomain(),
                CustomWorkoutTemplateSyncDomain(),
                LoggedActivitySyncDomain(),
                LinkedOAuthSyncDomain(bridge: linkedOAuthBridge),
            ],
            linkedOAuthBridge: linkedOAuthBridge
        )

        // Wire local-change notifications from the repo to the sync coordinator.
        // Done after syncCoordinator is initialized so the capture is valid.
        activityRepo.setOnLocalChange { [weak syncCoordinator] in
            syncCoordinator?.notifyLocalChange()
        }

        if let workoutRepo = workoutPersistenceRepository as? WorkoutPersistenceRepository {
            workoutRepo.setOnLocalChange { [weak syncCoordinator] in
                syncCoordinator?.notifyLocalChange()
            }
        }

        syncExternalCyclingWorkouts = SyncExternalCyclingWorkoutsUseCase(
            stravaService: strava,
            whoopService: whoop,
            workoutRepository: workoutPersistenceRepository,
            trainingPlanLookupService: trainingPlanLookupService,
            trainingPlanPersistenceRepository: trainingPlanPersistenceRepository,
            modelContext: PersistenceContainer.shared.mainContext
        )
    }
}

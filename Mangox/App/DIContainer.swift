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
            trainingPlanLookupService: trainingPlanLookupService
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
            healthKitService: healthKitService
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
    func makeOutdoorViewModel() -> OutdoorViewModel {
        OutdoorViewModel(
            locationService: locationManager,
            bleService: bleManager,
            routeService: routeManager,
            healthKitService: healthKitManager,
            liveActivityService: liveActivityManager,
            workoutPersistenceRepository: workoutPersistenceRepository
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
        stravaService = StravaService()
        whoopService = WhoopService()
        purchasesManager = PurchasesManager.shared
        aiService = AIService()
        ftpRefreshTrigger = FTPRefreshTrigger.shared
        trainingPlanLookupService = TrainingPlanLookupService()
        workoutPersistenceRepository = WorkoutPersistenceRepository(
            modelContext: PersistenceContainer.shared.mainContext,
            modelContainer: PersistenceContainer.shared
        )
        trainingPlanPersistenceRepository = TrainingPlanPersistenceRepository(
            modelContext: PersistenceContainer.shared.mainContext
        )
    }
}

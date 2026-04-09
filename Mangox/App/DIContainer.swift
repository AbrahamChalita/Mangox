// App/DIContainer.swift
import Foundation

/// Assembles and owns all app-level dependencies.
///
/// Concrete implementations are created here. Protocol-typed properties are exposed
/// so ViewModels depend on contracts rather than concrete classes.
/// Views that still use @Environment(ConcreteType.self) can access the concrete
/// properties below; new ViewModels should consume the protocol-typed versions.
@MainActor
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

    // MARK: - ViewModels (lazily vended; each VM owns its own lifecycle)

    func makeCoachViewModel() -> CoachViewModel {
        CoachViewModel(coach: coachRepository)
    }

    func makeHomeViewModel() -> HomeViewModel {
        HomeViewModel()
    }

    func makeFitnessViewModel() -> FitnessViewModel {
        FitnessViewModel(fitnessTracker: fitnessTrackerService, healthKit: healthKitService)
    }

    func makeProfileViewModel() -> ProfileViewModel {
        ProfileViewModel(whoopService: whoopServiceProtocol, purchasesService: purchasesServiceProtocol)
    }

    func makePaywallViewModel() -> PaywallViewModel {
        PaywallViewModel(purchasesService: purchasesServiceProtocol)
    }

    func makeIndoorViewModel() -> IndoorViewModel { IndoorViewModel() }
    func makeOutdoorViewModel() -> OutdoorViewModel { OutdoorViewModel() }
    func makeSocialViewModel() -> SocialViewModel { SocialViewModel() }
    func makeTrainingViewModel() -> TrainingViewModel { TrainingViewModel() }
    func makeWorkoutViewModel() -> WorkoutViewModel { WorkoutViewModel() }
    func makeOnboardingViewModel() -> OnboardingViewModel { OnboardingViewModel() }

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
    }
}

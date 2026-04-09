import Foundation

/// Assembles and owns all app-level dependencies.
///
/// Concrete implementations are created here and exposed as protocol types
/// so future ViewModels can depend on contracts rather than concrete classes.
/// Views continue using `@Environment(ConcreteType.self)` as before; this container
/// centralises construction and makes the wiring explicit.
@MainActor
final class DIContainer {

    // MARK: - Indoor / BLE infrastructure

    let bleManager: BLEManager
    let wifiTrainerService: WiFiTrainerService
    let dataSourceCoordinator: DataSourceCoordinator

    // MARK: - Navigation

    let routeManager: RouteManager
    let locationManager: LocationManager

    // MARK: - Fitness & Health

    let healthKitManager: HealthKitManager
    let fitnessTracker: FitnessTracker

    // MARK: - Workout utilities

    let personalRecords: PersonalRecords
    let liveActivityManager: RideLiveActivityManager

    // MARK: - External services

    let stravaService: StravaService
    let whoopService: WhoopService
    let purchasesManager: PurchasesManager
    let aiService: AIService
    let ftpRefreshTrigger: FTPRefreshTrigger

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

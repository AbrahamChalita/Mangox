import SwiftUI
import SwiftData

@main
struct MangoxApp: App {
    @State private var bleManager: BLEManager
    @State private var wifiTrainerService: WiFiTrainerService
    @State private var dataSourceCoordinator: DataSourceCoordinator
    @State private var routeManager = RouteManager()
    @State private var locationManager = LocationManager()
    @State private var healthKitManager = HealthKitManager()
    @State private var stravaService = StravaService()
    @State private var whoopService = WhoopService()
    @State private var purchasesManager = PurchasesManager.shared
    @State private var aiService = AIService()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    /// Controls the in-app launch screen visibility.
    /// Stays true until SwiftData has had one runloop cycle to populate
    /// @Query results, then fades out smoothly into HomeView.
    @State private var showLaunch = true

    init() {
        let ble = BLEManager()
        let wifi = WiFiTrainerService()
        let coordinator = DataSourceCoordinator(bleManager: ble, wifiService: wifi)
        _bleManager = State(initialValue: ble)
        _wifiTrainerService = State(initialValue: wifi)
        _dataSourceCoordinator = State(initialValue: coordinator)
        // Warm up the training plan at launch so the first access from
        // HomeView / TrainingPlanView costs nothing on the main thread.
        // CachedPlan.shared is a lazy static let — touching it once here
        // pre-builds the full 8-week struct before any view renders.
        // Plain Task (not detached) inherits the MainActor context of App.init,
        // which is what Swift 6 requires for accessing a MainActor-visible static.
        Task(priority: .utility) {
            _ = CachedPlan.shared
        }

        if let apiKey = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String {
            PurchasesManager.shared.configure(apiKey: apiKey)
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if hasCompletedOnboarding {
                    ContentView()
                        .environment(bleManager)
                        .environment(wifiTrainerService)
                        .environment(dataSourceCoordinator)
                        .environment(routeManager)
                        .environment(locationManager)
                        .environment(healthKitManager)
                        .environment(stravaService)
                        .environment(whoopService)
                        .environment(FTPRefreshTrigger.shared)
                        .environment(purchasesManager)
                        .environment(FitnessTracker.shared)
                        .environment(aiService)
                        .environment(\.launchOverlayVisible, showLaunch)
                        .preferredColorScheme(.dark)
                        .overlay {
                            NotificationLifecycleHook()
                                .allowsHitTesting(false)
                        }
                } else {
                    OnboardingView()
                        .environment(locationManager)
                        .environment(healthKitManager)
                        .environment(stravaService)
                        .environment(whoopService)
                        .preferredColorScheme(.dark)
                }

                // Launch screen sits on top and fades out once the app is ready.
                // ZStack layering means ContentView renders immediately underneath,
                // so by the time the launch screen fades there is fully loaded UI.
                LaunchScreenView(isVisible: showLaunch)
            }
            .task {
                aiService.whoopDataSource = whoopService
                // Wait for SwiftData @Query population + BLE manager init.
                // 900ms covers cold launch on older devices and gives the entry
                // animation time to fully play before we trigger the exit.
                // If Coach/Calendar/Stats still hitch on first open on a device, use Instruments
                // (Time Profiler + SwiftUI) to confirm whether the bottleneck is fetch vs layout.
                try? await Task.sleep(for: .milliseconds(900))
                showLaunch = false
            }
        }
        .modelContainer(
            for: [
                Workout.self, WorkoutSample.self, LapSplit.self, TrainingPlanProgress.self,
                AIGeneratedPlan.self, ChatSession.self, CoachChatMessage.self,
                CustomWorkoutTemplate.self, FitnessSettingsSnapshot.self,
                WorkoutRAGChunk.self,
            ])
    }
}

// MARK: - Local notification refresh (evening preview, missed key, FTP nudge)

private struct NotificationLifecycleHook: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    FitnessSettingsSnapshotBackfill.runIfNeeded(modelContext: modelContext)
                    TrainingNotificationsScheduler.evaluateMissedKeyIfNeeded(modelContext: modelContext)
                    TrainingNotificationsScheduler.rescheduleFTPReminder()
                    WorkoutRAGIndex.scheduleBackgroundSync(modelContext: modelContext)
                case .background:
                    TrainingNotificationsScheduler.rescheduleEveningPreview(modelContext: modelContext)
                default:
                    break
                }
            }
    }
}

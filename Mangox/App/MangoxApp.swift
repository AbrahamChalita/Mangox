import SwiftUI
import SwiftData

@main
struct MangoxApp: App {
    @State private var di = DIContainer()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    /// Controls the in-app launch screen visibility.
    /// Stays true until SwiftData has had one runloop cycle to populate
    /// @Query results, then fades out smoothly into HomeView.
    @State private var showLaunch = true

    init() {
        if let apiKey = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String {
            PurchasesManager.shared.configure(apiKey: apiKey)
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if hasCompletedOnboarding {
                    ContentView(di: di)
                        .environment(di.bleManager)
                        .environment(di.wifiTrainerService)
                        .environment(di.dataSourceCoordinator)
                        .environment(di.routeManager)
                        .environment(di.locationManager)
                        .environment(di.healthKitManager)
                        .environment(di.stravaService)
                        .environment(di.whoopService)
                        .environment(di.ftpRefreshTrigger)
                        .environment(di.purchasesManager)
                        .environment(di.fitnessTracker)
                        .environment(di.personalRecords)
                        .environment(di.liveActivityManager)
                        .environment(di.aiService)
                        .environment(\.launchOverlayVisible, showLaunch)
                        .preferredColorScheme(.dark)
                        .overlay {
                            NotificationLifecycleHook(di: di)
                                .allowsHitTesting(false)
                        }
                } else {
                    OnboardingView(viewModel: di.makeOnboardingViewModel())
                        .environment(di)
                        .environment(di.locationManager)
                        .environment(di.healthKitManager)
                        .environment(di.stravaService)
                        .environment(di.whoopService)
                        .preferredColorScheme(.dark)
                }

                LaunchScreenView(isVisible: showLaunch)
            }
            .task {
                di.aiService.whoopDataSource = di.whoopService
                try? await Task.sleep(for: .milliseconds(900))
                showLaunch = false
            }
        }
        .modelContainer(PersistenceContainer.shared)
    }
}

// MARK: - Local notification refresh (evening preview, missed key, FTP nudge)

private struct NotificationLifecycleHook: View {
    @Environment(\.scenePhase) private var scenePhase
    let di: DIContainer

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    FitnessSettingsSnapshotBackfill.runIfNeeded()
                    TrainingPlanProgressCleanupMigration.runIfNeeded()
                    TrainingNotificationsScheduler.evaluateMissedKeyIfNeeded()
                    TrainingNotificationsScheduler.rescheduleFTPReminder()
                    WorkoutRAGIndex.scheduleBackgroundSync()
                case .background:
                    di.locationService.persistRecordingCheckpointNow()
                    TrainingNotificationsScheduler.rescheduleEveningPreview()
                default:
                    break
                }
            }
    }
}

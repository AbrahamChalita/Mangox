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
        // Warm up the training plan at launch so the first access from
        // HomeView / TrainingPlanView costs nothing on the main thread.
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
                            NotificationLifecycleHook()
                                .allowsHitTesting(false)
                        }
                } else {
                    OnboardingView()
                        .environment(di.locationManager)
                        .environment(di.healthKitManager)
                        .environment(di.stravaService)
                        .environment(di.whoopService)
                        .preferredColorScheme(.dark)
                }

                // Launch screen sits on top and fades out once the app is ready.
                LaunchScreenView(isVisible: showLaunch)
            }
            .task {
                di.aiService.whoopDataSource = di.whoopService
                // Wait for SwiftData @Query population + BLE manager init.
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

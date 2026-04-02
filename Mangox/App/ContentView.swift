import SwiftUI
import SwiftData
import CoreLocation

enum AppRoute: Hashable {
    case connection
    case indoorRideSetup
    case connectionForPlan(planID: String, dayID: String)
    case ftpSetup
    case dashboard
    case outdoorDashboard
    case planDashboard(planID: String, dayID: String)
    case ftpTest
    case summary(workoutID: UUID)
    case trainingPlan
    case profile
    case settings
    case outdoorSensorsSetup
    case calendar
    case pmc
    case paywall
    case aiPlan(planID: String)
}

struct ContentView: View {
    @Environment(LocationManager.self) private var locationManager

    @State private var selectedTab = 0
    @State private var homePath = NavigationPath()
    @State private var calendarPath = NavigationPath()
    @State private var coachPath = NavigationPath()
    @State private var statsPath = NavigationPath()
    @State private var settingsPath = NavigationPath()

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house.fill", value: 0) {
                NavigationStack(path: $homePath) {
                    HomeView(navigationPath: $homePath, selectedTab: $selectedTab)
                        .toolbar(.hidden, for: .navigationBar)
                        .navigationDestination(for: AppRoute.self) { route in
                            routeDestination(route, path: $homePath)
                        }
                }
            }

            Tab("Calendar", systemImage: "calendar", value: 1) {
                LazyTabRootContent(tabIndex: 1, selectedTab: selectedTab) {
                    NavigationStack(path: $calendarPath) {
                        CalendarView(navigationPath: $calendarPath)
                            .toolbar(.hidden, for: .navigationBar)
                            .navigationDestination(for: AppRoute.self) { route in
                                routeDestination(route, path: $calendarPath)
                            }
                    }
                }
            }

            Tab("Coach", systemImage: "sparkles", value: 2) {
                LazyTabRootContent(tabIndex: 2, selectedTab: selectedTab) {
                    NavigationStack(path: $coachPath) {
                        CoachHubView(navigationPath: $coachPath)
                            .navigationDestination(for: AppRoute.self) { route in
                                routeDestination(route, path: $coachPath)
                            }
                    }
                }
            }

            Tab("Stats", systemImage: "chart.line.uptrend.xyaxis", value: 3) {
                LazyTabRootContent(tabIndex: 3, selectedTab: selectedTab) {
                    NavigationStack(path: $statsPath) {
                        PMChartView(navigationPath: $statsPath)
                            .toolbar(.hidden, for: .navigationBar)
                            .navigationDestination(for: AppRoute.self) { route in
                                routeDestination(route, path: $statsPath)
                            }
                    }
                }
            }

            Tab("Settings", systemImage: "gearshape.fill", value: 4) {
                LazyTabRootContent(tabIndex: 4, selectedTab: selectedTab) {
                    NavigationStack(path: $settingsPath) {
                        SettingsView()
                            .toolbar(.hidden, for: .navigationBar)
                            .navigationDestination(for: AppRoute.self) { route in
                                routeDestination(route, path: $settingsPath)
                            }
                    }
                }
            }
        }
        .tint(AppColor.mango)
        .tabBarMinimizeBehavior(.onScrollDown)
        .task {
            locationManager.warmUpLocationIfAuthorized()
        }
        .onChange(of: locationManager.authorizationStatus) { _, newStatus in
            if newStatus == .authorizedWhenInUse || newStatus == .authorizedAlways {
                locationManager.warmUpLocationIfAuthorized()
            }
        }
    }

    @ViewBuilder
    private func routeDestination(_ route: AppRoute, path: Binding<NavigationPath>) -> some View {
        switch route {
        case .connection:
            ConnectionView(navigationPath: path)
                .toolbar(.hidden, for: .tabBar)
        case .indoorRideSetup:
            ConnectionView(navigationPath: path, indoorRideLocked: true)
                .toolbar(.hidden, for: .tabBar)
        case .connectionForPlan(let planID, let dayID):
            ConnectionView(navigationPath: path, startMode: .ride, planID: planID, planDayID: dayID)
                .toolbar(.hidden, for: .tabBar)
        case .ftpSetup:
            ConnectionView(navigationPath: path, startMode: .ftpTest)
                .toolbar(.hidden, for: .tabBar)
        case .dashboard:
            DashboardView(navigationPath: path)
                .toolbar(.hidden, for: .navigationBar)
                .toolbar(.hidden, for: .tabBar)
        case .outdoorDashboard:
            OutdoorDashboardView(navigationPath: path)
                .toolbar(.hidden, for: .navigationBar)
                .toolbar(.hidden, for: .tabBar)
        case .planDashboard(let planID, let dayID):
            DashboardView(navigationPath: path, planID: planID, planDayID: dayID)
                .toolbar(.hidden, for: .navigationBar)
                .toolbar(.hidden, for: .tabBar)
        case .ftpTest:
            FTPTestView(navigationPath: path)
                .toolbar(.hidden, for: .tabBar)
        case .summary(let workoutID):
            SummaryView(workoutID: workoutID, navigationPath: path)
        case .trainingPlan:
            TrainingPlanView(navigationPath: path)
                .toolbar(.hidden, for: .navigationBar)
        case .paywall:
            PaywallView()
        case .profile:
            SettingsView()
                .toolbar(.hidden, for: .navigationBar)
        case .settings:
            SettingsView()
        case .outdoorSensorsSetup:
            ConnectionView(navigationPath: path, outdoorSensorsOnly: true)
                .toolbar(.hidden, for: .tabBar)
        case .calendar:
            CalendarView(navigationPath: path)
                .toolbar(.hidden, for: .navigationBar)
        case .pmc:
            PMChartView(navigationPath: path)
                .toolbar(.hidden, for: .navigationBar)
        case .aiPlan(let planID):
            AITrainingPlanView(planID: planID, navigationPath: path)
                .toolbar(.hidden, for: .navigationBar)
        }
    }
}

// MARK: - AI Training Plan Wrapper

struct AITrainingPlanView: View {
    let planID: String
    @Binding var navigationPath: NavigationPath
    @Query private var aiPlans: [AIGeneratedPlan]

    private var resolvedPlan: TrainingPlan? {
        aiPlans.first { $0.id == planID }?.plan
    }

    var body: some View {
        if let plan = resolvedPlan {
            TrainingPlanView(navigationPath: $navigationPath, plan: plan)
        } else {
            ContentUnavailableView(
                "Plan not found",
                systemImage: "exclamationmark.triangle",
                description: Text("This plan may have been deleted.")
            )
        }
    }
}

#Preview {
    let ble = BLEManager()
    let wifi = WiFiTrainerService()
    return ContentView()
        .environment(ble)
        .environment(wifi)
        .environment(DataSourceCoordinator(bleManager: ble, wifiService: wifi))
        .environment(RouteManager())
        .environment(LocationManager())
        .environment(HealthKitManager())
        .environment(StravaService())
        .environment(FTPRefreshTrigger.shared)
        .modelContainer(for: [Workout.self, WorkoutSample.self, LapSplit.self, TrainingPlanProgress.self], inMemory: true)
}

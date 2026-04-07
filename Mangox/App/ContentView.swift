import CoreLocation
import MapKit
import SwiftData
import SwiftUI

// MARK: - Launch overlay (prewarm timing)

private enum LaunchOverlayEnvironment {
    struct Key: EnvironmentKey {
        static let defaultValue = false
    }
}

extension EnvironmentValues {
    /// True while `LaunchScreenView` covers the root UI (`MangoxApp`).
    var launchOverlayVisible: Bool {
        get { self[LaunchOverlayEnvironment.Key.self] }
        set { self[LaunchOverlayEnvironment.Key.self] = newValue }
    }
}

enum AppRoute: Hashable {
    case connection
    case indoorRideSetup
    case connectionForPlan(planID: String, dayID: String)
    case ftpSetup
    case dashboard
    case outdoorDashboard
    case planDashboard(planID: String, dayID: String)
    /// Indoor guided ride from an imported or saved `CustomWorkoutTemplate` (e.g. ZWO).
    case customWorkoutRide(templateID: UUID)
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
    @Environment(\.launchOverlayVisible) private var launchOverlayVisible

    @State private var selectedTab = 0
    @State private var homePath = NavigationPath()
    @State private var calendarPath = NavigationPath()
    @State private var coachPath = NavigationPath()
    @State private var statsPath = NavigationPath()
    @State private var settingsPath = NavigationPath()
    @State private var showRideMenu = false
    /// Off-screen build of **Coach + Settings** only under the launch overlay (cheap vs Calendar/PMC).
    @State private var prewarmSecondaryTabRoots = false

    @Namespace private var rideGlassNamespace

    private var isInSubview: Bool {
        !homePath.isEmpty || !calendarPath.isEmpty || !coachPath.isEmpty || !statsPath.isEmpty
    }

    private var showFloatingButton: Bool {
        (selectedTab == 0 || selectedTab == 1) && !isInSubview
    }

    var body: some View {
        ZStack {
            if prewarmSecondaryTabRoots {
                SecondaryTabRootsPrewarm()
                    .frame(width: 1, height: 1)
                    .opacity(0.02)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

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
                    LazyTabRootContent(
                        tabIndex: 1, selectedTab: selectedTab, placeholderStyle: .calendar
                    ) {
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
                    LazyTabRootContent(
                        tabIndex: 2, selectedTab: selectedTab, placeholderStyle: .coach
                    ) {
                        NavigationStack(path: $coachPath) {
                            CoachTabRootView(navigationPath: $coachPath)
                                .navigationDestination(for: AppRoute.self) { route in
                                    routeDestination(route, path: $coachPath)
                                }
                        }
                    }
                }

                Tab("Stats", systemImage: "chart.line.uptrend.xyaxis", value: 3) {
                    LazyTabRootContent(
                        tabIndex: 3, selectedTab: selectedTab, placeholderStyle: .stats
                    ) {
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
                    LazyTabRootContent(
                        tabIndex: 4, selectedTab: selectedTab, placeholderStyle: .settings
                    ) {
                        NavigationStack(path: $settingsPath) {
                            SettingsView(navigationPath: $settingsPath)
                                .navigationDestination(for: AppRoute.self) { route in
                                    routeDestination(route, path: $settingsPath)
                                }
                        }
                    }
                }
            }

        }
        .overlay(alignment: .bottomTrailing) {
            ZStack(alignment: .bottomTrailing) {
                if showRideMenu {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(duration: 0.2)) { showRideMenu = false }
                        }
                        .transition(.opacity)
                }
                if showFloatingButton {
                    GlassEffectContainer {
                        if showRideMenu {
                            rideExpandedMorphCard
                        } else {
                            rideCollapsedMorphFab
                        }
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 70)
                    .transition(.opacity)
                }
            }
        }
        .animation(.spring(duration: 0.35), value: showFloatingButton)
        .background {
            // Pre-warm Apple Maps Metal renderer invisibly
            Map()
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .allowsHitTesting(false)
        }
        .task {
            locationManager.warmUpLocationIfAuthorized()
        }
        .task(id: launchOverlayVisible) {
            await MangoxDebugPerformance.runInterval("Content.tabPrewarm") {
                await runSecondaryTabPrewarmTask()
            }
        }
        .onChange(of: locationManager.authorizationStatus) { _, newStatus in
            if newStatus == .authorizedWhenInUse || newStatus == .authorizedAlways {
                locationManager.warmUpLocationIfAuthorized()
            }
        }
    }

    private func runSecondaryTabPrewarmTask() async {
        if launchOverlayVisible {
            try? await Task.sleep(for: .milliseconds(80))
            prewarmSecondaryTabRoots = true
        } else if prewarmSecondaryTabRoots {
            try? await Task.sleep(for: .milliseconds(400))
            prewarmSecondaryTabRoots = false
        } else {
            // Previews (no overlay): discretionary prewarm without tying to launch timing.
            try? await Task.sleep(for: .milliseconds(150))
            prewarmSecondaryTabRoots = true
            try? await Task.sleep(for: .milliseconds(500))
            prewarmSecondaryTabRoots = false
        }
    }

    private func handleRideSelection(_ route: AppRoute) {
        withAnimation(.spring(duration: 0.3)) {
            showRideMenu = false
        }
        selectedTab = 0
        homePath.append(route)
    }

    // MARK: - Ride Menu (Liquid Glass morph)

    private static let rideGlassMorphID = "rideGlassFAB"

    private var rideMenuPanelContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            rideMenuRow(
                icon: "figure.indoor.cycle",
                iconColor: AppColor.mango,
                title: "Indoor Ride",
                subtitle: "Smart trainer & power meter"
            ) {
                handleRideSelection(.indoorRideSetup)
            }

            Divider()

            rideMenuRow(
                icon: "bicycle",
                iconColor: AppColor.blue,
                title: "Outdoor Ride",
                subtitle: "GPS, maps & optional sensors"
            ) {
                handleRideSelection(.outdoorDashboard)
            }
        }
    }

    private var rideCollapsedMorphFab: some View {
        Button {
            withAnimation(.spring(duration: 0.22, bounce: 0.1)) {
                showRideMenu = true
            }
        } label: {
            Image(systemName: "plus")
                .font(.title2.bold())
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .contentShape(Circle())
        }
        .buttonStyle(MangoxPressStyle())
        .glassEffect(.regular.tint(AppColor.mango), in: .circle)
        .glassEffectID(Self.rideGlassMorphID, in: rideGlassNamespace)
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
    }

    private var rideExpandedMorphCard: some View {
        rideMenuPanelContent
            .frame(width: 260)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .glassEffectID(Self.rideGlassMorphID, in: rideGlassNamespace)
            .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
    }

    private func rideMenuRow(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(iconColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(MangoxPressStyle())
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
        case .customWorkoutRide(let templateID):
            DashboardView(navigationPath: path, customWorkoutTemplateID: templateID)
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
            SettingsView(navigationPath: path)
                .toolbar(.hidden, for: .navigationBar)
        case .settings:
            SettingsView(navigationPath: path)
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

// MARK: - Secondary tab prewarm

/// Prewarms only Coach + Settings (SwiftData + heavy UI) under the launch screen.
/// Calendar and Stats stay cold until first open so launch doesn’t pay Charts + large workout queries twice.
private struct SecondaryTabRootsPrewarm: View {
    @State private var coachPath = NavigationPath()
    @State private var settingsPath = NavigationPath()

    var body: some View {
        ZStack {
            NavigationStack(path: $coachPath) {
                CoachTabRootView(navigationPath: $coachPath)
            }
            NavigationStack(path: $settingsPath) {
                SettingsView(navigationPath: $settingsPath)
            }
        }
    }
}

// MARK: - AI Training Plan Wrapper

struct AITrainingPlanView: View {
    let planID: String
    @Binding var navigationPath: NavigationPath
    @Query private var aiPlans: [AIGeneratedPlan]

    init(planID: String, navigationPath: Binding<NavigationPath>) {
        self.planID = planID
        _navigationPath = navigationPath
        let pid = planID
        var d = FetchDescriptor<AIGeneratedPlan>(
            predicate: #Predicate<AIGeneratedPlan> { $0.id == pid }
        )
        d.fetchLimit = 1
        _aiPlans = Query(d)
    }

    private var resolvedPlan: TrainingPlan? {
        aiPlans.first?.plan
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
        .modelContainer(
            for: [
                Workout.self, WorkoutSample.self, LapSplit.self, TrainingPlanProgress.self,
                CustomWorkoutTemplate.self, FitnessSettingsSnapshot.self,
            ],
            inMemory: true)
}

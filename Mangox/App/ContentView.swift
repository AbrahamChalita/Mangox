// App/ContentView.swift
import CoreLocation
import MapKit
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.launchOverlayVisible) private var launchOverlayVisible

    let di: DIContainer
    @State private var selectedTab = 0
    @State private var homePath = NavigationPath()
    @State private var calendarPath = NavigationPath()
    @State private var coachPath = NavigationPath()
    @State private var statsPath = NavigationPath()
    @State private var settingsPath = NavigationPath()
    @State private var loadedSecondaryTabs: Set<Int> = []
    @State private var prewarmSecondaryTabRoots = false

    private var isInSubview: Bool {
        !homePath.isEmpty || !calendarPath.isEmpty || !coachPath.isEmpty || !statsPath.isEmpty
    }

    private var showFloatingButton: Bool {
        (selectedTab == 0 || selectedTab == 1) && !isInSubview
    }

    var body: some View {
        ZStack {
            if prewarmSecondaryTabRoots {
                SecondaryTabRootsPrewarm(di: di)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .opacity(0.001)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            TabView(selection: $selectedTab) {
                    Tab("Home", systemImage: "house.fill", value: 0) {
                    NavigationStack(path: $homePath) {
                        HomeView(
                            navigationPath: $homePath,
                            selectedTab: $selectedTab,
                            viewModel: di.makeHomeViewModel()
                        )
                        .toolbar(Visibility.hidden, for: ToolbarPlacement.navigationBar)
                        .navigationDestination(for: AppRoute.self) { route in
                            appRouteDestination(route, path: $homePath, di: di)
                        }
                    }
                }

                Tab("Workouts", systemImage: "figure.outdoor.cycle", value: 1) {
                    NavigationStack(path: $calendarPath) {
                        CalendarView(di: di, navigationPath: $calendarPath)
                            .navigationDestination(for: AppRoute.self) { route in
                                appRouteDestination(route, path: $calendarPath, di: di)
                            }
                    }
                    .toolbar(.hidden, for: .navigationBar)
                }

                Tab("Coach", systemImage: "sparkles", value: 2) {
                    LazyTabRootContent(
                        tabIndex: 2,
                        selectedTab: selectedTab,
                        loadedTabs: $loadedSecondaryTabs,
                        placeholderStyle: .coach
                    ) {
                        NavigationStack(path: $coachPath) {
                            CoachTabRootView(
                                navigationPath: $coachPath,
                                viewModel: di.makeCoachViewModel()
                            )
                            .navigationDestination(for: AppRoute.self) { route in
                                appRouteDestination(route, path: $coachPath, di: di)
                            }
                        }
                    }
                }

                Tab("Stats", systemImage: "chart.line.uptrend.xyaxis", value: 3) {
                    LazyTabRootContent(
                        tabIndex: 3,
                        selectedTab: selectedTab,
                        loadedTabs: $loadedSecondaryTabs,
                        placeholderStyle: .stats
                    ) {
                        NavigationStack(path: $statsPath) {
                            PMChartView(
                                navigationPath: $statsPath, viewModel: di.makeFitnessViewModel()
                            )
                            .toolbar(Visibility.hidden, for: ToolbarPlacement.navigationBar)
                            .navigationDestination(for: AppRoute.self) { route in
                                appRouteDestination(route, path: $statsPath, di: di)
                            }
                        }
                    }
                }

                Tab("Settings", systemImage: "gearshape.fill", value: 4) {
                    LazyTabRootContent(
                        tabIndex: 4,
                        selectedTab: selectedTab,
                        loadedTabs: $loadedSecondaryTabs,
                        placeholderStyle: .settings
                    ) {
                        NavigationStack(path: $settingsPath) {
                            SettingsView(
                                navigationPath: $settingsPath, viewModel: di.makeProfileViewModel()
                            )
                            .navigationDestination(for: AppRoute.self) { route in
                                appRouteDestination(route, path: $settingsPath, di: di)
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            RideFABView(showFloatingButton: showFloatingButton) { route in
                selectedTab = 0
                homePath.append(route)
            }
        }
        .background {
            if MangoxFeatureFlags.allowsAppShellMapPrewarm {
                Map()
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .allowsHitTesting(false)
            }
        }
        .task {
            di.locationService.warmUpLocationIfAuthorized()
            di.locationService.restoreRecordingIfNeeded()
        }
        .task(id: launchOverlayVisible) {
            await MangoxDebugPerformance.runInterval("Content.tabPrewarm") {
                await runSecondaryTabPrewarmTask()
            }
        }
        .onChange(of: di.locationService.authorizationStatus) { _, newStatus in
            if shouldWarmLocation(for: newStatus) {
                di.locationService.warmUpLocationIfAuthorized()
            }
        }
        .onOpenURL { url in
            guard isRideLiveActivityURL(url) else { return }
            selectedTab = 0
            // Never clear `homePath` here: that pops the in-memory indoor stack and builds a new
            // `DashboardView`, which used to vend a fresh `IndoorViewModel` and restart the ride.
            if isIndoorLiveActivityURL(url) {
                if homePath.isEmpty {
                    homePath.append(AppRoute.dashboard)
                }
            } else if homePath.isEmpty {
                homePath.append(AppRoute.outdoorDashboard)
            }
        }
    }

    private func shouldWarmLocation(for status: CLAuthorizationStatus) -> Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }

    private func runSecondaryTabPrewarmTask() async {
        if launchOverlayVisible {
            try? await Task.sleep(for: .milliseconds(80))
            prewarmSecondaryTabRoots = true
        } else if prewarmSecondaryTabRoots {
            try? await Task.sleep(for: .milliseconds(400))
            prewarmSecondaryTabRoots = false
        } else {
            try? await Task.sleep(for: .milliseconds(150))
            prewarmSecondaryTabRoots = true
            try? await Task.sleep(for: .milliseconds(500))
            prewarmSecondaryTabRoots = false
        }
    }

    private func isRideLiveActivityURL(_ url: URL) -> Bool {
        isOutdoorLiveActivityURL(url) || isIndoorLiveActivityURL(url)
    }

    private func isOutdoorLiveActivityURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "mangox" else { return false }
        guard url.host?.lowercased() == "ride" else { return false }
        let path = url.path.lowercased()
        return path == "/outdoor/live" || path == "/outdoor"
    }

    private func isIndoorLiveActivityURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "mangox" else { return false }
        guard url.host?.lowercased() == "ride" else { return false }
        let path = url.path.lowercased()
        return path == "/indoor/live" || path == "/indoor"
    }
}

#Preview {
    let di = DIContainer()
    let ble = BLEManager()
    let wifi = WiFiTrainerService()
    return ContentView(di: di)
        .environment(ble)
        .environment(wifi)
        .environment(DataSourceCoordinator(bleManager: ble, wifiService: wifi))
        .environment(RouteManager())
        .environment(LocationManager())
        .environment(HealthKitManager())
        .environment(StravaService())
        .environment(WhoopService())
        .environment(FTPRefreshTrigger.shared)
        .modelContainer(try! PersistenceContainer.makeContainer(inMemory: true))
}

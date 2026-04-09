// App/ContentView.swift
import CoreLocation
import MapKit
import SwiftUI

struct ContentView: View {
    @Environment(LocationManager.self) private var locationManager
    @Environment(\.launchOverlayVisible) private var launchOverlayVisible

    @State private var selectedTab = 0
    @State private var homePath = NavigationPath()
    @State private var calendarPath = NavigationPath()
    @State private var coachPath = NavigationPath()
    @State private var statsPath = NavigationPath()
    @State private var settingsPath = NavigationPath()
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
                                appRouteDestination(route, path: $homePath)
                            }
                    }
                }

                Tab("Calendar", systemImage: "calendar", value: 1) {
                    LazyTabRootContent(tabIndex: 1, selectedTab: selectedTab, placeholderStyle: .calendar) {
                        NavigationStack(path: $calendarPath) {
                            CalendarView(navigationPath: $calendarPath)
                                .toolbar(.hidden, for: .navigationBar)
                                .navigationDestination(for: AppRoute.self) { route in
                                    appRouteDestination(route, path: $calendarPath)
                                }
                        }
                    }
                }

                Tab("Coach", systemImage: "sparkles", value: 2) {
                    LazyTabRootContent(tabIndex: 2, selectedTab: selectedTab, placeholderStyle: .coach) {
                        NavigationStack(path: $coachPath) {
                            CoachTabRootView(navigationPath: $coachPath)
                                .navigationDestination(for: AppRoute.self) { route in
                                    appRouteDestination(route, path: $coachPath)
                                }
                        }
                    }
                }

                Tab("Stats", systemImage: "chart.line.uptrend.xyaxis", value: 3) {
                    LazyTabRootContent(tabIndex: 3, selectedTab: selectedTab, placeholderStyle: .stats) {
                        NavigationStack(path: $statsPath) {
                            PMChartView(navigationPath: $statsPath)
                                .toolbar(.hidden, for: .navigationBar)
                                .navigationDestination(for: AppRoute.self) { route in
                                    appRouteDestination(route, path: $statsPath)
                                }
                        }
                    }
                }

                Tab("Settings", systemImage: "gearshape.fill", value: 4) {
                    LazyTabRootContent(tabIndex: 4, selectedTab: selectedTab, placeholderStyle: .settings) {
                        NavigationStack(path: $settingsPath) {
                            SettingsView(navigationPath: $settingsPath)
                                .navigationDestination(for: AppRoute.self) { route in
                                    appRouteDestination(route, path: $settingsPath)
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
            try? await Task.sleep(for: .milliseconds(150))
            prewarmSecondaryTabRoots = true
            try? await Task.sleep(for: .milliseconds(500))
            prewarmSecondaryTabRoots = false
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
        .environment(WhoopService())
        .environment(FTPRefreshTrigger.shared)
        .modelContainer(
            for: [
                Workout.self, WorkoutSample.self, LapSplit.self, TrainingPlanProgress.self,
                CustomWorkoutTemplate.self, FitnessSettingsSnapshot.self, WorkoutRAGChunk.self,
            ],
            inMemory: true)
}

// App/AppRouter.swift
import SwiftUI
import SwiftData

/// Maps every `AppRoute` case to its destination view.
/// Used as the single `navigationDestination(for: AppRoute.self)` handler
/// across all tab NavigationStacks in ContentView.
@ViewBuilder
func appRouteDestination(_ route: AppRoute, path: Binding<NavigationPath>, di: DIContainer) -> some View {
    switch route {
    case .connection:
        ConnectionView(navigationPath: path, bleService: di.bleManager, dataSourceService: di.dataSourceCoordinator, routeService: di.routeManager, locationService: di.locationManager)
            .toolbar(.hidden, for: .tabBar)
    case .indoorRideSetup:
        ConnectionView(navigationPath: path, indoorRideLocked: true, bleService: di.bleManager, dataSourceService: di.dataSourceCoordinator, routeService: di.routeManager, locationService: di.locationManager)
            .toolbar(.hidden, for: .tabBar)
    case .connectionForPlan(let planID, let dayID):
        ConnectionView(navigationPath: path, startMode: .ride, planID: planID, planDayID: dayID, bleService: di.bleManager, dataSourceService: di.dataSourceCoordinator, routeService: di.routeManager, locationService: di.locationManager)
            .toolbar(.hidden, for: .tabBar)
    case .ftpSetup:
        ConnectionView(navigationPath: path, startMode: .ftpTest, bleService: di.bleManager, dataSourceService: di.dataSourceCoordinator, routeService: di.routeManager, locationService: di.locationManager)
            .toolbar(.hidden, for: .tabBar)
    case .dashboard:
        DashboardView(
            navigationPath: path,
            trainingPlanLookupService: di.trainingPlanLookupService,
            viewModel: di.makeIndoorViewModel()
        )
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
    case .outdoorDashboard:
        OutdoorDashboardView(navigationPath: path, di: di, viewModel: di.makeOutdoorViewModel())
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
    case .planDashboard(let planID, let dayID):
        DashboardView(
            navigationPath: path,
            planID: planID,
            planDayID: dayID,
            trainingPlanLookupService: di.trainingPlanLookupService,
            viewModel: di.makeIndoorViewModel()
        )
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
    case .customWorkoutRide(let templateID):
        DashboardView(
            navigationPath: path,
            customWorkoutTemplateID: templateID,
            trainingPlanLookupService: di.trainingPlanLookupService,
            viewModel: di.makeIndoorViewModel()
        )
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
    case .ftpTest:
        FTPTestView(viewModel: di.makeFTPTestViewModel(), navigationPath: path)
            .toolbar(.hidden, for: .tabBar)
    case .summary(let workoutID):
        SummaryView(
            workoutID: workoutID,
            navigationPath: path,
            viewModel: di.makeWorkoutViewModel()
        )
    case .paywall:
        PaywallView(viewModel: di.makePaywallViewModel())
    case .profile:
        SettingsView(navigationPath: path, viewModel: di.makeProfileViewModel())
            .toolbar(.hidden, for: .navigationBar)
    case .settings:
        SettingsView(navigationPath: path, viewModel: di.makeProfileViewModel())
    case .outdoorSensorsSetup:
        ConnectionView(navigationPath: path, outdoorSensorsOnly: true, bleService: di.bleManager, dataSourceService: di.dataSourceCoordinator, routeService: di.routeManager, locationService: di.locationManager)
            .toolbar(.hidden, for: .tabBar)
    case .calendar:
        CalendarView(di: di, navigationPath: path)
            .toolbar(.hidden, for: .navigationBar)
    case .pmc:
        PMChartView(navigationPath: path, viewModel: di.makeFitnessViewModel())
            .toolbar(.hidden, for: .navigationBar)
    case .aiPlan(let planID):
        AITrainingPlanView(planID: planID, navigationPath: path, viewModel: di.makeTrainingViewModel())
            .toolbar(.hidden, for: .navigationBar)
    }
}

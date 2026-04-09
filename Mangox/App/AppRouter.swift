// App/AppRouter.swift
import SwiftUI
import SwiftData

/// Maps every `AppRoute` case to its destination view.
/// Used as the single `navigationDestination(for: AppRoute.self)` handler
/// across all tab NavigationStacks in ContentView.
@ViewBuilder
func appRouteDestination(_ route: AppRoute, path: Binding<NavigationPath>) -> some View {
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

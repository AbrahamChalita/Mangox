import Foundation

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

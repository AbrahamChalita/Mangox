import Foundation

/// Contract for Live Activity synchronization during indoor and outdoor rides.
/// Concrete implementation: `RideLiveActivityManager` in Outdoor/Data/DataSources/RideLiveActivity/.
@MainActor
protocol LiveActivityServiceProtocol: AnyObject {
    func syncRecording(
        isRecording: Bool,
        prefs: RidePreferences,
        navigationService: NavigationService,
        locationManager: LocationServiceProtocol,
        bleService: BLEServiceProtocol
    ) async

    func syncIndoorRecording(
        isRecording: Bool,
        prefs: RidePreferences,
        workoutManager: WorkoutManager,
        dataSourceService: DataSourceServiceProtocol,
        bleService: BLEServiceProtocol
    ) async

    func endLiveActivity() async
}

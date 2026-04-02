import ActivityKit
import Foundation
import os.log

private let liveActivityLogger = Logger(subsystem: "com.abchalita.Mangox", category: "RideLiveActivity")

/// Starts and updates a Live Activity while recording. Requires a Widget Extension target that declares
/// `ActivityConfiguration(for: MangoxRideAttributes.self)` and embeds the `.appex` in the Mangox app.
@MainActor
final class RideLiveActivityManager {
    static let shared = RideLiveActivityManager()

    private var activity: Activity<MangoxRideAttributes>?
    private var lastUpdate: Date = .distantPast
    private let minUpdateInterval: TimeInterval = 5

    // MARK: - Outdoor

    func syncRecording(
        isRecording: Bool,
        prefs: RidePreferences,
        navigationService: NavigationService,
        locationManager: LocationManager,
        bleManager: BLEManager
    ) async {
        guard prefs.outdoorLiveActivityEnabled else {
            await endIfNeeded()
            return
        }
        guard isRecording else {
            await endIfNeeded()
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let nextTurn: String?
        if navigationService.mode == .turnByTurn, let turn = navigationService.nextTurn {
            nextTurn = turn.instruction
        } else if navigationService.mode == .followRoute, let hint = navigationService.followRouteHint {
            nextTurn = hint.instruction
        } else {
            nextTurn = nil
        }

        let hr = max(0, bleManager.metrics.heartRate)
        let power = max(0, bleManager.smoothedPower)
        let cadence = bleManager.metrics.cadence
        let hrZoneId: Int = hr > 0 ? HeartRateZone.zone(for: hr).id : 0
        let powerZoneId: Int = power > 0 ? PowerZone.zone(for: power).id : 0

        let state = MangoxRideAttributes.ContentState(
            speedKmh: locationManager.speed,
            distanceM: locationManager.totalDistance,
            durationSeconds: locationManager.rideDuration,
            nextTurnShort: nextTurn,
            heartRateBpm: hr,
            powerWatts: power,
            cadenceRpm: cadence,
            hrZoneId: hrZoneId,
            powerZoneId: powerZoneId,
            useImperial: prefs.isImperial
        )

        let modeLabel: String
        switch navigationService.mode {
        case .freeRide: modeLabel = "Outdoor"
        case .followRoute: modeLabel = "Route"
        case .turnByTurn: modeLabel = "Navigate"
        }

        if let activity {
            let elapsed = Date().timeIntervalSince(lastUpdate)
            if elapsed >= minUpdateInterval {
                await activity.update(ActivityContent(state: state, staleDate: nil))
                lastUpdate = Date()
            }
        } else {
            let attrs = MangoxRideAttributes(rideModeLabel: modeLabel)
            do {
                activity = try Activity.request(
                    attributes: attrs,
                    content: ActivityContent(state: state, staleDate: nil),
                    pushType: nil
                )
                lastUpdate = Date()
            } catch {
                #if DEBUG
                liveActivityLogger.debug("Activity.request failed: \(error.localizedDescription, privacy: .public)")
                #endif
            }
        }
    }

    // MARK: - Indoor

    func syncIndoorRecording(
        isRecording: Bool,
        prefs: RidePreferences,
        workoutManager: WorkoutManager,
        bleManager: BLEManager
    ) async {
        guard prefs.indoorLiveActivityEnabled else {
            await endIfNeeded()
            return
        }
        guard isRecording else {
            await endIfNeeded()
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let hr = max(0, bleManager.metrics.heartRate)
        let power = workoutManager.displayPower
        let cadence = bleManager.metrics.cadence
        let speed = workoutManager.metricsSpeed
        let distanceM = workoutManager.activeDistance
        let duration = Double(workoutManager.elapsedSeconds)
        let hrZoneId: Int = hr > 0 ? HeartRateZone.zone(for: hr).id : 0
        let powerZoneId: Int = power > 0 ? PowerZone.zone(for: power).id : 0

        let state = MangoxRideAttributes.ContentState(
            speedKmh: speed,
            distanceM: distanceM,
            durationSeconds: duration,
            nextTurnShort: nil,
            heartRateBpm: hr,
            powerWatts: power,
            cadenceRpm: cadence,
            hrZoneId: hrZoneId,
            powerZoneId: powerZoneId,
            useImperial: prefs.isImperial
        )

        if let activity {
            let elapsed = Date().timeIntervalSince(lastUpdate)
            if elapsed >= minUpdateInterval {
                await activity.update(ActivityContent(state: state, staleDate: nil))
                lastUpdate = Date()
            }
        } else {
            let attrs = MangoxRideAttributes(rideModeLabel: "Indoor")
            do {
                activity = try Activity.request(
                    attributes: attrs,
                    content: ActivityContent(state: state, staleDate: nil),
                    pushType: nil
                )
                lastUpdate = Date()
            } catch {
                #if DEBUG
                liveActivityLogger.debug("Activity.request failed: \(error.localizedDescription, privacy: .public)")
                #endif
            }
        }
    }

    private func endIfNeeded() async {
        guard let activity else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        self.activity = nil
        lastUpdate = .distantPast
    }
}

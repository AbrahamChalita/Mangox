import ActivityKit
import Foundation
import os.log

private let liveActivityLogger = Logger(
    subsystem: "com.abchalita.Mangox", category: "RideLiveActivity")

/// Starts and updates a Live Activity while recording. Requires a Widget Extension target that declares
/// `ActivityConfiguration(for: MangoxRideAttributes.self)` and embeds the `.appex` in the Mangox app.
@MainActor
@Observable
final class RideLiveActivityManager: LiveActivityServiceProtocol {
    static let shared = RideLiveActivityManager()

    private var activity: Activity<MangoxRideAttributes>?
    private var lastUpdate: Date = .distantPast

    // MARK: - Outdoor

    func syncRecording(
        isRecording: Bool,
        prefs: RidePreferences,
        navigationService: NavigationService,
        locationManager: LocationServiceProtocol,
        bleService: BLEServiceProtocol
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
        } else if navigationService.mode == .followRoute,
            let hint = navigationService.followRouteHint
        {
            nextTurn = hint.instruction
        } else {
            nextTurn = nil
        }

        let hr = max(0, bleService.metrics.heartRate)
        let power = max(0, bleService.smoothedPower)
        let cadence = bleService.metrics.cadence
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

        await publishState(state, modeLabel: modeLabel)
    }

    // MARK: - Indoor

    func syncIndoorRecording(
        isRecording: Bool,
        prefs: RidePreferences,
        workoutManager: WorkoutManager,
        dataSourceService: DataSourceServiceProtocol,
        bleService: BLEServiceProtocol
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

        let unified = dataSourceService.snapshotUnifiedMetrics()
        let hr = max(0, unified.heartRate)
        let power = workoutManager.displayPower
        let cadence = unified.cadence
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

        await publishState(state, modeLabel: "Indoor")
    }

    private func publishState(
        _ state: MangoxRideAttributes.ContentState,
        modeLabel: String
    ) async {
        let now = Date()
        if let activeActivity = resolveExistingActivityIfNeeded() {
            let elapsed = now.timeIntervalSince(lastUpdate)
            guard elapsed >= RideLiveActivityConfiguration.minUpdateInterval else {
                #if DEBUG
                    liveActivityLogger.debug(
                        "skip update (\(modeLabel, privacy: .public)) throttle=\(Int(RideLiveActivityConfiguration.minUpdateInterval - elapsed), privacy: .public)s duration=\(Int(state.durationSeconds), privacy: .public) power=\(state.powerWatts, privacy: .public) speed=\(state.speedKmh, privacy: .public)"
                    )
                #endif
                return
            }
            await activeActivity.update(
                ActivityContent(
                    state: state,
                    staleDate: now.addingTimeInterval(RideLiveActivityConfiguration.staleWindow)))
            lastUpdate = now
            #if DEBUG
                liveActivityLogger.debug(
                    "updated (\(modeLabel, privacy: .public)) duration=\(Int(state.durationSeconds), privacy: .public) power=\(state.powerWatts, privacy: .public) speed=\(state.speedKmh, privacy: .public)"
                )
            #endif
            return
        }

        let attrs = MangoxRideAttributes(rideModeLabel: modeLabel)
        do {
            activity = try Activity.request(
                attributes: attrs,
                content: ActivityContent(
                    state: state,
                    staleDate: now.addingTimeInterval(RideLiveActivityConfiguration.staleWindow)),
                pushType: nil
            )
            lastUpdate = now
            #if DEBUG
                liveActivityLogger.debug(
                    "requested (\(modeLabel, privacy: .public)) duration=\(Int(state.durationSeconds), privacy: .public) power=\(state.powerWatts, privacy: .public) speed=\(state.speedKmh, privacy: .public)"
                )
            #endif
        } catch {
            #if DEBUG
                liveActivityLogger.debug(
                    "Activity.request failed: \(error.localizedDescription, privacy: .public)")
            #endif
        }
    }

    private func resolveExistingActivityIfNeeded() -> Activity<MangoxRideAttributes>? {
        if let activity {
            return activity
        }

        if let existing = Activity<MangoxRideAttributes>.activities.first {
            activity = existing
            return existing
        }

        return nil
    }

    private func endIfNeeded() async {
        var activityIDs = Set<String>()
        var activitiesToEnd: [Activity<MangoxRideAttributes>] = []

        if let activity {
            activityIDs.insert(activity.id)
            activitiesToEnd.append(activity)
        }

        for existing in Activity<MangoxRideAttributes>.activities where activityIDs.insert(existing.id).inserted {
            activitiesToEnd.append(existing)
        }

        guard !activitiesToEnd.isEmpty else {
            self.activity = nil
            lastUpdate = .distantPast
            return
        }

        for existing in activitiesToEnd {
            await existing.end(nil, dismissalPolicy: .immediate)
        }

        self.activity = nil
        lastUpdate = .distantPast
    }

    /// Ends the Live Activity on the Lock Screen and Dynamic Island. Call when a ride stops (finished, discarded,
    /// or prefs turn Live Activities off) — `sync*` only runs on timer ticks, so workout end must invoke this explicitly.
    func endLiveActivity() async {
        await endIfNeeded()
    }
}

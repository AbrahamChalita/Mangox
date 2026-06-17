import ActivityKit
import Foundation
import os.log

private let liveActivityLogger = Logger(
    subsystem: "com.abchalita.Mangox", category: "RideLiveActivity")

private struct SendableRideActivity: @unchecked Sendable {
    nonisolated(unsafe) let value: Activity<MangoxRideAttributes>
    nonisolated init(_ value: Activity<MangoxRideAttributes>) {
        self.value = value
    }
}

/// Starts and updates a Live Activity while recording. Requires a Widget Extension target that declares
/// `ActivityConfiguration(for: MangoxRideAttributes.self)` and embeds the `.appex` in the Mangox app.
@MainActor
@Observable
final class RideLiveActivityManager: LiveActivityServiceProtocol {
    static let shared = RideLiveActivityManager()

    private var activity: Activity<MangoxRideAttributes>?
    private var lastUpdate: Date = .distantPast

    // MARK: - Outdoor

    func syncOutdoorRecording(snapshot: OutdoorLiveActivitySnapshot) async {
        guard snapshot.isEnabled else {
            await endIfNeeded()
            return
        }
        guard snapshot.isRecording else {
            await endIfNeeded()
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let hrZoneId: Int = snapshot.heartRateBpm > 0 ? HeartRateZone.zone(for: snapshot.heartRateBpm).id : 0
        let powerZoneId: Int = snapshot.powerWatts > 0 ? PowerZone.zone(for: snapshot.powerWatts).id : 0

        let state = MangoxRideAttributes.ContentState(
            speedKmh: snapshot.speedKmh,
            distanceM: snapshot.distanceM,
            durationSeconds: snapshot.durationSeconds,
            startedAt: Date().addingTimeInterval(-snapshot.durationSeconds),
            nextTurnShort: snapshot.nextTurnShort,
            heartRateBpm: snapshot.heartRateBpm,
            powerWatts: snapshot.powerWatts,
            cadenceRpm: snapshot.cadenceRpm,
            hrZoneId: hrZoneId,
            powerZoneId: powerZoneId,
            useImperial: snapshot.useImperial,
            isAutoPaused: snapshot.isAutoPaused,
            isManuallyPaused: snapshot.isManuallyPaused
        )

        await publishState(state, modeLabel: snapshot.modeLabel)
    }

    // MARK: - Indoor

    func syncIndoorRecording(snapshot: IndoorLiveActivitySnapshot) async {
        guard snapshot.isEnabled else {
            await endIfNeeded()
            return
        }
        guard snapshot.isRecording else {
            await endIfNeeded()
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let hrZoneId: Int = snapshot.heartRateBpm > 0 ? HeartRateZone.zone(for: snapshot.heartRateBpm).id : 0
        let powerZoneId: Int = snapshot.powerWatts > 0 ? PowerZone.zone(for: snapshot.powerWatts).id : 0

        let state = MangoxRideAttributes.ContentState(
            speedKmh: snapshot.speedKmh,
            distanceM: snapshot.distanceM,
            durationSeconds: snapshot.durationSeconds,
            startedAt: Date().addingTimeInterval(-snapshot.durationSeconds),
            nextTurnShort: nil,
            heartRateBpm: snapshot.heartRateBpm,
            powerWatts: snapshot.powerWatts,
            cadenceRpm: snapshot.cadenceRpm,
            hrZoneId: hrZoneId,
            powerZoneId: powerZoneId,
            useImperial: snapshot.useImperial,
            isAutoPaused: snapshot.isAutoPaused,
            isManuallyPaused: snapshot.isManuallyPaused
        )

        await publishState(state, modeLabel: "Indoor")
    }

    private func publishState(
        _ state: MangoxRideAttributes.ContentState,
        modeLabel: String
    ) async {
        let now = Date()
        if let activeActivity = resolveExistingActivityIfNeeded() {
            let activityBox = SendableRideActivity(activeActivity)
            let elapsed = now.timeIntervalSince(lastUpdate)
            guard elapsed >= RideLiveActivityConfiguration.minUpdateInterval else {
                #if DEBUG
                    liveActivityLogger.debug(
                        "skip update (\(modeLabel, privacy: .public)) throttle=\(Int(RideLiveActivityConfiguration.minUpdateInterval - elapsed), privacy: .public)s duration=\(Int(state.durationSeconds), privacy: .public) power=\(state.powerWatts, privacy: .public) speed=\(state.speedKmh, privacy: .public)"
                    )
                #endif
                return
            }
            await activityBox.value.update(
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
        var activitiesToEnd: [SendableRideActivity] = []

        if let activity {
            activityIDs.insert(activity.id)
            activitiesToEnd.append(SendableRideActivity(activity))
        }

        for existing in Activity<MangoxRideAttributes>.activities where activityIDs.insert(existing.id).inserted {
            activitiesToEnd.append(SendableRideActivity(existing))
        }

        guard !activitiesToEnd.isEmpty else {
            self.activity = nil
            lastUpdate = .distantPast
            return
        }

        for existing in activitiesToEnd {
            await existing.value.end(nil, dismissalPolicy: .immediate)
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

import Foundation
import Testing
@testable import Mangox

struct RideNudgeEngineTests {

    private struct PrefSnapshot {
        let rideTipsEnabled: Bool
        let rideTipsSpacing: RideNudgeSpacing
        let rideTipsIndoorHeatAwareness: Bool
        let lowCadenceWarningEnabled: Bool
        let rideTipsEnabledCategories: Set<RideNudgeCategory>
    }

    @MainActor
    private func capturePrefs() -> PrefSnapshot {
        let prefs = RidePreferences.shared
        return PrefSnapshot(
            rideTipsEnabled: prefs.rideTipsEnabled,
            rideTipsSpacing: prefs.rideTipsSpacing,
            rideTipsIndoorHeatAwareness: prefs.rideTipsIndoorHeatAwareness,
            lowCadenceWarningEnabled: prefs.lowCadenceWarningEnabled,
            rideTipsEnabledCategories: prefs.rideTipsEnabledCategories
        )
    }

    @MainActor
    private func restorePrefs(_ snapshot: PrefSnapshot) {
        let prefs = RidePreferences.shared
        prefs.rideTipsEnabled = snapshot.rideTipsEnabled
        prefs.rideTipsSpacing = snapshot.rideTipsSpacing
        prefs.rideTipsIndoorHeatAwareness = snapshot.rideTipsIndoorHeatAwareness
        prefs.lowCadenceWarningEnabled = snapshot.lowCadenceWarningEnabled
        prefs.rideTipsEnabledCategories = snapshot.rideTipsEnabledCategories
    }

    private func makeContext(
        now: Date,
        elapsedSeconds: Int,
        distanceGoalProgress: Double? = nil,
        cadence: Double = 90
    ) -> RideNudgeContext {
        RideNudgeContext(
            now: now,
            isRecording: true,
            elapsedSeconds: elapsedSeconds,
            displayPower: 180,
            displayCadenceRpm: cadence,
            zoneId: 2,
            lowCadenceThreshold: 60,
            lowCadenceStreakSeconds: 0,
            showLowCadenceHardWarning: false,
            activeDistanceMeters: 45_000,
            distanceGoalKm: distanceGoalProgress == nil ? nil : 100,
            distanceGoalProgress: distanceGoalProgress,
            guidedIsActive: false,
            guidedStepIsRecovery: false,
            guidedSecondsIntoStep: nil,
            guidedStepIsHardIntensity: false,
            suppressUntil: nil
        )
    }

    @MainActor
    @Test func fuelingTipRepeatsAfterConfiguredInterval() {
        let prefs = RidePreferences.shared
        let snapshot = capturePrefs()
        defer { restorePrefs(snapshot) }

        prefs.rideTipsEnabled = true
        prefs.rideTipsSpacing = .more
        prefs.rideTipsIndoorHeatAwareness = false
        prefs.rideTipsEnabledCategories = [.fueling]

        var session = RideNudgeSessionState()
        let start = Date(timeIntervalSince1970: 1_000)
        let firstContext = makeContext(now: start, elapsedSeconds: 40 * 60)
        let firstTip = RideNudgeEngine.nextTip(
            context: firstContext,
            prefs: prefs,
            guidedStepIndex: -1,
            session: &session
        )

        #expect(firstTip?.id == "fueling_steady_long")

        let blockedContext = makeContext(
            now: start.addingTimeInterval(8 * 60),
            elapsedSeconds: 48 * 60
        )
        let blockedTip = RideNudgeEngine.nextTip(
            context: blockedContext,
            prefs: prefs,
            guidedStepIndex: -1,
            session: &session
        )
        #expect(blockedTip == nil)

        let repeatContext = makeContext(
            now: start.addingTimeInterval(27 * 60),
            elapsedSeconds: 67 * 60
        )
        let repeatTip = RideNudgeEngine.nextTip(
            context: repeatContext,
            prefs: prefs,
            guidedStepIndex: -1,
            session: &session
        )
        #expect(repeatTip?.id == "fueling_steady_long")
    }

    @MainActor
    @Test func fuelingTipRequiresDistanceWindowWhenGoalProgressExists() {
        let prefs = RidePreferences.shared
        let snapshot = capturePrefs()
        defer { restorePrefs(snapshot) }

        prefs.rideTipsEnabled = true
        prefs.rideTipsSpacing = .more
        prefs.rideTipsEnabledCategories = [.fueling]

        var earlySession = RideNudgeSessionState()
        let now = Date(timeIntervalSince1970: 2_000)
        let earlyContext = makeContext(
            now: now,
            elapsedSeconds: 45 * 60,
            distanceGoalProgress: 0.20
        )
        let earlyTip = RideNudgeEngine.nextTip(
            context: earlyContext,
            prefs: prefs,
            guidedStepIndex: -1,
            session: &earlySession
        )
        #expect(earlyTip == nil)

        var windowSession = RideNudgeSessionState()
        let windowContext = makeContext(
            now: now,
            elapsedSeconds: 45 * 60,
            distanceGoalProgress: 0.40
        )
        let windowTip = RideNudgeEngine.nextTip(
            context: windowContext,
            prefs: prefs,
            guidedStepIndex: -1,
            session: &windowSession
        )
        #expect(windowTip?.id == "fueling_steady_long")
    }
}

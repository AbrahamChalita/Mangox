// Features/Outdoor/Presentation/ViewModel/OutdoorViewModel.swift
import Foundation

@MainActor
@Observable
final class OutdoorViewModel {
    // MARK: - View state
    var currentMetrics: CyclingMetrics = CyclingMetrics()
    var isRecording: Bool = false
    var elapsedSeconds: Int = 0
    var currentNudge: RideNudgeDisplay? = nil
    var rideGoals: [RideGoal] = []

    // MARK: - Nudge engine state
    private var nudgeSession: RideNudgeSessionState = RideNudgeSessionState()

    func evaluateNudge(context: RideNudgeContext, prefs: RidePreferences, guidedStepIndex: Int) {
        if let nudge = RideNudgeEngine.nextTip(
            context: context,
            prefs: prefs,
            guidedStepIndex: guidedStepIndex,
            session: &nudgeSession
        ) {
            currentNudge = nudge
        }
    }

    func dismissNudge() {
        currentNudge = nil
    }

    func resetNudgeSession() {
        nudgeSession.reset()
        currentNudge = nil
    }
}

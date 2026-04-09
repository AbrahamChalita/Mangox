import UIKit

@Observable
final class HapticManager {
    static let shared = HapticManager()

    private var lastZoneID: Int?

    // MARK: - Zone Changes

    func zoneChanged(to newZoneID: Int) {
        guard let last = lastZoneID, last != newZoneID else {
            lastZoneID = newZoneID
            return
        }

        if newZoneID > last {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        } else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        lastZoneID = newZoneID
    }

    // MARK: - Workout Lifecycle

    /// Fired when the user starts recording.
    func workoutStarted() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Fired when the workout ends and data is saved.
    func workoutEnded() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Fired when a lap is manually marked.
    func lapCompleted() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    // MARK: - Auto-Pause / Resume

    /// Soft alert: power dropped, auto-pause triggered.
    func autoPaused() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// Soft confirmation: power returned, recording resumed.
    func autoResumed() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    // MARK: - Milestones & Goals

    /// Double-tap for distance milestones (every N km on the indoor dashboard).
    func milestone() {
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            gen.impactOccurred(intensity: 0.55)
        }
    }

    /// Single success tap when a ride goal is completed.
    func goalCompleted() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Subtle tap for optional in-ride training tips.
    func rideTipNudge() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.85)
    }

    // MARK: - Outdoor Navigation

    /// Strong cue for a newly announced turn or off-course event.
    func navigationPrimary() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    /// Lighter cue for an upcoming turn reminder.
    func navigationAdvance() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Immediate cue for a near-immediate turn.
    func navigationImmediate() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    // MARK: - Coach

    /// Light confirmation when the user sends a coach message.
    func coachMessageSent() {
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.prepare()
        gen.impactOccurred()
    }

    /// Tapping an inline suggested-reply chip under a coach message.
    func coachQuickReplyTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Onboarding

    /// Permission or integration step completed during first-launch onboarding.
    func onboardingStepCompleted() {
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.prepare()
        gen.impactOccurred()
    }

    /// Strava connected or final “Get Started” — slightly stronger than a single impact.
    func onboardingCelebration() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: - FTP Test

    /// Fired when the FTP test protocol finishes.
    func ftpTestCompleted() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: - Reset

    func reset() {
        lastZoneID = nil
    }
}

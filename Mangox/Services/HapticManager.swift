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

    /// Double-tap for distance milestones (every 10 km).
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

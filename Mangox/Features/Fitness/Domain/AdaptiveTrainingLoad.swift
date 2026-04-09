import Foundation

/// Nudges ERG targets for guided plan sessions based on how completed plan rides compare to rough planned load.
enum AdaptiveTrainingAdjuster {
    private static let minMultiplier = 0.88
    private static let maxMultiplier = 1.08
    private static let decayPerRide = 0.96
    private static let minTSSForRatioAdjust = 5.0
    private static let highPlannedTSSNoPower = 30.0

    /// Call after a **valid** plan-linked workout is saved (indoor with power / TSS preferred).
    @MainActor
    static func adjustAfterCompletedPlanWorkout(
        workout: Workout,
        planDay: PlanDay,
        progress: TrainingPlanProgress
    ) {
        guard workout.isValid else { return }
        guard planDay.dayType == .workout || planDay.dayType == .ftpTest else { return }

        let ftp = max(1, max(progress.currentFTP, PowerZone.ftp))
        let planned = planDay.estimatedPlannedTSS(ftp: ftp)
        guard planned >= 15 else { return }

        let actual = workout.tss
        guard actual.isFinite, actual >= 0 else { return }

        // Always drift slightly back toward 1.0 so load doesn’t sit pinned forever.
        var m = 1.0 + (progress.adaptiveLoadMultiplier - 1.0) * decayPerRide

        let skipRatioAdjust =
            actual < minTSSForRatioAdjust
            || (workout.maxPower <= 0 && planned >= highPlannedTSSNoPower)

        if skipRatioAdjust {
            progress.adaptiveLoadMultiplier = m
            return
        }

        let ratio = actual / planned

        if ratio < 0.82 {
            m = max(minMultiplier, m * 0.985)
        } else if ratio > 1.18 {
            m = min(maxMultiplier, m * 1.012)
        }

        progress.adaptiveLoadMultiplier = m
    }
}

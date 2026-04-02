import Foundation
import os.log

private let guidedLogger = Logger(subsystem: "com.abchalita.Mangox", category: "GuidedSession")

// MARK: - Flattened Timeline Step

/// A single step in the flattened interval timeline.
/// Repeats and recovery periods are expanded into individual steps so the UI
/// can show a simple linear progress bar and countdown.
struct TimelineStep: Identifiable, Sendable {
    let id: Int                          // sequential index (0-based)
    let segment: IntervalSegment         // original segment reference
    let isRecovery: Bool                 // true = recovery between repeats
    let repeatIndex: Int                 // which repeat (0-based); 0 for non-repeating
    let durationSeconds: Int
    let zone: TrainingZoneTarget
    let suggestedTrainerMode: SuggestedTrainerMode
    let simulationGrade: Double?
    let cadenceLow: Int?
    let cadenceHigh: Int?

    /// Cumulative start time in seconds from the beginning of the workout
    let startOffset: Int

    var endOffset: Int { startOffset + durationSeconds }

    var label: String {
        if isRecovery {
            return "\(segment.name) — Recovery"
        }
        if segment.repeats > 1 {
            return "\(segment.name) (\(repeatIndex + 1)/\(segment.repeats))"
        }
        return segment.name
    }

    /// Target watt range for this step based on its zone.
    var targetWattRange: ClosedRange<Int>? {
        let ftp = Double(PowerZone.ftp)
        guard ftp > 0 else { return nil }
        switch zone {
        case .z1:       return Int(ftp * 0.0)...Int(ftp * 0.55)
        case .z2:       return Int(ftp * 0.55)...Int(ftp * 0.75)
        case .z3:       return Int(ftp * 0.75)...Int(ftp * 0.87)
        case .z4:       return Int(ftp * 0.87)...Int(ftp * 1.05)
        case .z5:       return Int(ftp * 1.05)...Int(ftp * 1.50)
        case .z1z2:     return Int(ftp * 0.0)...Int(ftp * 0.75)
        case .z2z3:     return Int(ftp * 0.55)...Int(ftp * 0.87)
        case .z3z4:     return Int(ftp * 0.75)...Int(ftp * 1.05)
        case .z3z5:     return Int(ftp * 0.75)...Int(ftp * 1.50)
        case .z4z5:     return Int(ftp * 0.87)...Int(ftp * 1.50)
        case .mixed, .all: return Int(ftp * 0.55)...Int(ftp * 1.20)
        case .rest, .none: return nil
        }
    }

    /// Mid-point ERG target watts.
    var ergTargetWatts: Int? {
        guard let range = targetWattRange else { return nil }
        return (range.lowerBound + range.upperBound) / 2
    }
}

// MARK: - Zone Compliance

enum ZoneCompliance: Sendable {
    case inZone
    case belowZone
    case aboveZone

    var icon: String {
        switch self {
        case .inZone: return "checkmark.circle.fill"
        case .belowZone: return "arrow.up.circle.fill"
        case .aboveZone: return "arrow.down.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .inZone: return "In Zone"
        case .belowZone: return "Push Harder!"
        case .aboveZone: return "Ease Up"
        }
    }
}

// MARK: - Guided Session Manager

/// Manages a guided training plan session during a workout.
///
/// Responsibilities:
/// - Flattens `IntervalSegment` repeats/recoveries into a linear `TimelineStep` array
/// - Tracks elapsed time against the timeline to determine the active step
/// - Exposes current step, countdown, progress, and upcoming steps for the dashboard UI
/// - Signals the `WorkoutManager` when the trainer mode should change (ERG/SIM/Free)
/// - Tracks zone compliance (is the rider in the target zone?)
@Observable
@MainActor
final class GuidedSessionManager {

    // MARK: - Configuration (set once before workout starts)

    /// The plan day being executed.
    private(set) var planDay: PlanDay?

    /// The plan day's title for UI display.
    var dayTitle: String { planDay?.title ?? "" }

    /// The plan day's notes.
    var dayNotes: String { planDay?.notes ?? "" }

    /// Whether a guided session is active.
    var isActive: Bool { planDay != nil }

    /// Whether the session has structured intervals (vs. steady-state).
    var hasIntervals: Bool { !timeline.isEmpty }

    // MARK: - Timeline

    /// Flattened, ordered steps derived from the plan day's intervals.
    private(set) var timeline: [TimelineStep] = []

    /// Total planned duration in seconds.
    var totalPlannedSeconds: Int {
        timeline.last?.endOffset ?? planDay.map { $0.durationMinutes * 60 } ?? 0
    }

    // MARK: - Live State (updated every second by WorkoutManager)

    /// Current elapsed seconds in the workout (mirrors WorkoutManager.elapsedSeconds).
    private(set) var elapsedSeconds: Int = 0

    /// Index of the current step in the timeline.
    private(set) var currentStepIndex: Int = 0

    /// The currently active timeline step (nil if past end or no intervals).
    var currentStep: TimelineStep? {
        guard currentStepIndex < timeline.count else { return nil }
        return timeline[currentStepIndex]
    }

    /// Seconds remaining in the current step.
    var stepSecondsRemaining: Int {
        guard let step = currentStep else { return 0 }
        return max(0, step.endOffset - elapsedSeconds)
    }

    /// Progress fraction (0–1) through the current step.
    var stepProgress: Double {
        guard let step = currentStep, step.durationSeconds > 0 else { return 0 }
        let elapsed = elapsedSeconds - step.startOffset
        return min(1, max(0, Double(elapsed) / Double(step.durationSeconds)))
    }

    /// Overall progress fraction (0–1) through the entire workout.
    var overallProgress: Double {
        guard totalPlannedSeconds > 0 else { return 0 }
        return min(1, Double(elapsedSeconds) / Double(totalPlannedSeconds))
    }

    /// Whether the rider has exceeded the planned duration (free riding after plan ends).
    var isPastPlan: Bool {
        totalPlannedSeconds > 0 && elapsedSeconds >= totalPlannedSeconds
    }

    /// The next upcoming step (for "up next" display).
    var nextStep: TimelineStep? {
        let nextIdx = currentStepIndex + 1
        guard nextIdx < timeline.count else { return nil }
        return timeline[nextIdx]
    }

    /// Current zone compliance based on current power.
    private(set) var compliance: ZoneCompliance = .inZone

    /// Seconds spent in-zone during the current step.
    private(set) var stepInZoneSeconds: Int = 0

    /// Total seconds spent in-zone across all steps.
    private(set) var totalInZoneSeconds: Int = 0

    /// In-zone percentage for the current step.
    var stepInZonePercent: Double {
        guard let step = currentStep else { return 0 }
        let stepElapsed = elapsedSeconds - step.startOffset
        guard stepElapsed > 0 else { return 0 }
        return Double(stepInZoneSeconds) / Double(stepElapsed) * 100
    }

    /// In-zone percentage across the entire session.
    var totalInZonePercent: Double {
        guard elapsedSeconds > 0 else { return 0 }
        return Double(totalInZoneSeconds) / Double(elapsedSeconds) * 100
    }

    /// Callback invoked when the active step changes and the trainer mode should be updated.
    /// Parameters: (suggestedMode, ergWatts?, simulationGrade?)
    var onTrainerModeChange: ((SuggestedTrainerMode, Int?, Double?) -> Void)?

    /// The last trainer mode that was applied (to avoid redundant commands).
    /// The last step index for which a trainer mode command was successfully dispatched.
    /// Stays at -1 (or the previous step) when a command is skipped due to missing
    /// parameters, so it will be retried on the next tick.
    private var lastAppliedStep: Int = -1

    // MARK: - Motivational Messages

    /// A contextual motivational message based on the current state.
    var motivationalMessage: String {
        if isPastPlan {
            return "Plan complete! 🎉 Free riding now."
        }
        guard let step = currentStep else {
            return dayNotes.isEmpty ? "Let's go! 🚴" : dayNotes
        }

        let remaining = stepSecondsRemaining

        // Last 10 seconds of a hard interval
        if remaining <= 10 && remaining > 0 && (step.zone == .z4 || step.zone == .z5 || step.zone == .z4z5) {
            return remaining <= 5 ? "Almost there! \(remaining)s!" : "Final push! \(remaining)s left!"
        }

        // Transitioning to recovery
        if remaining <= 3 && remaining > 0, let next = nextStep, next.isRecovery {
            return "Recovery coming up — ease off 🧊"
        }

        // Starting a hard interval
        if stepProgress < 0.05 && !step.isRecovery {
            switch step.zone {
            case .z5: return "VO2max — give it everything! 🔥"
            case .z4: return "Threshold — hold steady! 💪"
            case .z3: return step.segment.cadenceLow != nil ? "Tempo — find your climbing rhythm 🏔️" : "Tempo — settle in 🎯"
            default: break
            }
        }

        // Climbing simulation
        if step.suggestedTrainerMode == .simulation, let grade = step.simulationGrade {
            if grade >= 7 {
                return "Steep climb! Stay seated, grind it out 🏔️"
            } else if grade >= 4 {
                return "Climbing — steady power, low cadence ⛰️"
            }
        }

        // In recovery
        if step.isRecovery {
            return "Recover — spin easy, breathe deep 🧘"
        }

        // Cadence cue
        if let low = step.cadenceLow, let high = step.cadenceHigh {
            return "Target cadence: \(low)–\(high) RPM"
        }

        // Generic mid-interval
        if !step.segment.notes.isEmpty {
            return step.segment.notes
        }

        return "Stay focused! 💪"
    }

    // MARK: - Setup

    /// Configure the guided session for a specific plan day.
    /// Call before the workout starts.
    func configure(planDay: PlanDay) {
        self.planDay = planDay
        self.timeline = Self.buildTimeline(from: planDay.intervals)
        self.elapsedSeconds = 0
        self.currentStepIndex = 0
        self.stepInZoneSeconds = 0
        self.totalInZoneSeconds = 0
        self.compliance = .inZone
        self.lastAppliedStep = -1

        guidedLogger.info("Guided session configured: \(planDay.title) — \(self.timeline.count) steps, \(self.totalPlannedSeconds)s total")
    }

    /// Tear down the guided session.
    func tearDown() {
        planDay = nil
        timeline = []
        elapsedSeconds = 0
        currentStepIndex = 0
        stepInZoneSeconds = 0
        totalInZoneSeconds = 0
        compliance = .inZone
        lastAppliedStep = -1
        onTrainerModeChange = nil
    }

    // MARK: - Tick (called every second by WorkoutManager)

    /// Advance the session clock and update the active step.
    /// - Parameters:
    ///   - elapsed: Current workout elapsed seconds.
    ///   - currentPower: The rider's current smoothed power (3s avg).
    func tick(elapsed: Int, currentPower: Int) {
        elapsedSeconds = elapsed

        // Find current step
        let previousIndex = currentStepIndex
        updateCurrentStep()

        // Zone compliance
        updateCompliance(currentPower: currentPower)

        // Trigger trainer mode change if step changed.
        // Guards:
        // 1. Only fire when we have an actual current step (not past plan end).
        // 2. For ERG steps, skip if ergTargetWatts is nil (FTP not set yet) so
        //    lastAppliedStep isn't consumed — it will be retried on the next tick
        //    once FTP becomes available.
        // 3. For simulation steps, skip if simulationGrade is nil.
        if currentStepIndex != lastAppliedStep, let step = currentStep {
            let ergWatts = step.suggestedTrainerMode == .erg ? step.ergTargetWatts : nil
            let grade = step.suggestedTrainerMode == .simulation ? step.simulationGrade : nil

            // Don't consume lastAppliedStep if the required parameter is missing
            let canApply: Bool
            switch step.suggestedTrainerMode {
            case .erg:        canApply = ergWatts != nil
            case .simulation: canApply = grade != nil
            case .freeRide:   canApply = true
            }

            if canApply {
                lastAppliedStep = currentStepIndex
                onTrainerModeChange?(step.suggestedTrainerMode, ergWatts, grade)

                if currentStepIndex != previousIndex {
                    guidedLogger.info("Step \(self.currentStepIndex): \(step.label) — \(step.zone.label) — \(step.suggestedTrainerMode.label)")
                }
            } else {
                guidedLogger.warning("Step \(self.currentStepIndex): skipping trainer command — required parameter missing (FTP set?)")
            }
        }
    }

    // MARK: - Private

    private func updateCurrentStep() {
        guard !timeline.isEmpty else { return }

        // If we're past the last step, clamp to timeline end
        if elapsedSeconds >= (timeline.last?.endOffset ?? 0) {
            currentStepIndex = timeline.count
            return
        }

        // Fast path: still in current step
        if currentStepIndex < timeline.count {
            let step = timeline[currentStepIndex]
            if elapsedSeconds >= step.startOffset && elapsedSeconds < step.endOffset {
                return
            }
        }

        // Search for the correct step (usually the next one)
        for (index, step) in timeline.enumerated() {
            if elapsedSeconds >= step.startOffset && elapsedSeconds < step.endOffset {
                if currentStepIndex != index {
                    // Step changed — reset step-level in-zone counter
                    stepInZoneSeconds = 0
                }
                currentStepIndex = index
                return
            }
        }
    }

    private func updateCompliance(currentPower: Int) {
        guard let step = currentStep, let range = step.targetWattRange else {
            compliance = .inZone
            return
        }

        if currentPower < range.lowerBound {
            compliance = .belowZone
        } else if currentPower > range.upperBound {
            compliance = .aboveZone
        } else {
            compliance = .inZone
            stepInZoneSeconds += 1
            totalInZoneSeconds += 1
        }
    }

    // MARK: - Timeline Builder

    /// Flatten interval segments (with repeats and recoveries) into a linear array of steps.
    static func buildTimeline(from intervals: [IntervalSegment]) -> [TimelineStep] {
        var steps: [TimelineStep] = []
        var offset = 0
        var index = 0

        for segment in intervals.sorted(by: { $0.order < $1.order }) {
            for rep in 0..<max(1, segment.repeats) {
                // Work step
                let workStep = TimelineStep(
                    id: index,
                    segment: segment,
                    isRecovery: false,
                    repeatIndex: rep,
                    durationSeconds: segment.durationSeconds,
                    zone: segment.zone,
                    suggestedTrainerMode: segment.suggestedTrainerMode,
                    simulationGrade: segment.simulationGrade,
                    cadenceLow: segment.cadenceLow,
                    cadenceHigh: segment.cadenceHigh,
                    startOffset: offset
                )
                steps.append(workStep)
                offset += segment.durationSeconds
                index += 1

                // Recovery step between repeats (not after the last repeat)
                if segment.recoverySeconds > 0 && rep < segment.repeats - 1 {
                    let recoveryStep = TimelineStep(
                        id: index,
                        segment: segment,
                        isRecovery: true,
                        repeatIndex: rep,
                        durationSeconds: segment.recoverySeconds,
                        zone: segment.recoveryZone,
                        suggestedTrainerMode: .erg,
                        simulationGrade: nil,
                        cadenceLow: nil,
                        cadenceHigh: nil,
                        startOffset: offset
                    )
                    steps.append(recoveryStep)
                    offset += segment.recoverySeconds
                    index += 1
                }
            }
        }

        return steps
    }

    // MARK: - Formatting Helpers

    /// Format seconds as "M:SS" or "H:MM:SS".
    static func formatCountdown(_ seconds: Int) -> String {
        let s = max(0, seconds)
        if s >= 3600 {
            return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
        }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

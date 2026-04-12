// Features/Outdoor/Domain/UseCases/RideNudgeEngine.swift
import Foundation

// MARK: - Session state (reset each recording)

struct RideNudgeSessionState: Equatable {
    var lastAnyNudgeAt: Date?
    var lastCategoryAt: [RideNudgeCategory: Date] = [:]
    var postureTipCount: Int = 0
    var lastPostureElapsed: Int = -1
    var tipShowCounts: [String: Int] = [:]
    var lastTipShownAt: [String: Date] = [:]
    /// Guided step indices that already received the recovery tip.
    var recoveryTipStepIndices: Set<Int> = []

    mutating func reset() {
        lastAnyNudgeAt = nil
        lastCategoryAt = [:]
        postureTipCount = 0
        lastPostureElapsed = -1
        tipShowCounts = [:]
        lastTipShownAt = [:]
        recoveryTipStepIndices = []
    }
}

// MARK: - Engine

enum RideNudgeEngine {

    private static let baseGlobalCooldown: TimeInterval = 240
    private static let categoryCooldown: TimeInterval = 1200

    private struct TipSpec {
        let id: String
        let category: RideNudgeCategory
        let priority: Int
        let headline: String
        let body: String
        let audioScript: String
        let minRepeatInterval: TimeInterval
        let maxSessionCount: Int
        let isEligible: (RideNudgeContext, RidePreferences, RideNudgeSessionState) -> Bool
    }

    /// Returns a tip to show this tick, or nil. Mutates `session` when a tip is returned (caller should commit).
    static func nextTip(
        context: RideNudgeContext,
        prefs: RidePreferences,
        guidedStepIndex: Int,
        session: inout RideNudgeSessionState
    ) -> RideNudgeDisplay? {
        guard prefs.rideTipsEnabled else { return nil }
        guard context.isRecording else { return nil }
        if let until = context.suppressUntil, context.now < until { return nil }

        let globalMin = baseGlobalCooldown * prefs.rideTipsSpacing.globalCooldownMultiplier
        if let last = session.lastAnyNudgeAt, context.now.timeIntervalSince(last) < globalMin {
            return nil
        }

        let ftp = max(PowerZone.ftp, 1)
        let tipWeightBoostForDistanceGoals: [RideNudgeCategory: Int] = [
            .fueling: 12,
            .heatFluids: 8,
            .posture: 4,
        ]

        let tips: [TipSpec] = [
            TipSpec(
                id: "recovery_easy_spin",
                category: .recovery,
                priority: 88,
                headline: "Recovery",
                body: "Easy spin — relax the shoulders and let cadence float up if it feels good.",
                audioScript: "Recovery: easy spin and relaxed shoulders.",
                minRepeatInterval: 9 * 60,
                maxSessionCount: 4
            ) { ctx, _, sess in
                guard ctx.guidedIsActive, ctx.guidedStepIsRecovery else { return false }
                guard let t = ctx.guidedSecondsIntoStep, (8...28).contains(t) else { return false }
                guard guidedStepIndex >= 0 else { return false }
                if sess.recoveryTipStepIndices.contains(guidedStepIndex) { return false }
                return true
            },
            TipSpec(
                id: "fueling_steady_long",
                category: .fueling,
                priority: 70,
                headline: "Training tip",
                body:
                    "Long steady block — if you’re out for 90+ minutes total, small sips of fuel on a schedule beat playing catch-up later.",
                audioScript: "Steady ride — remember fuel on a schedule for long efforts.",
                minRepeatInterval: 26 * 60,
                maxSessionCount: 4
            ) { ctx, _, _ in
                guard ctx.elapsedSeconds >= 38 * 60 else { return false }
                guard ctx.displayPower >= 70 else { return false }
                guard [2, 3].contains(ctx.zoneId) else { return false }
                if ctx.guidedIsActive && ctx.guidedStepIsHardIntensity { return false }
                if let progress = ctx.distanceGoalProgress {
                    let windows = [(0.35, 0.45), (0.60, 0.75), (0.82, 0.98)]
                    guard windows.contains(where: { progress >= $0.0 && progress <= $0.1 }) else {
                        return false
                    }
                }
                return true
            },
            TipSpec(
                id: "cadence_ease_torque",
                category: .cadence,
                priority: 65,
                headline: "Cadence",
                body:
                    "If the legs feel heavy, a slightly quicker spin can ease torque — find a cadence you can hold.",
                audioScript: "If your legs feel heavy, try spinning a little quicker.",
                minRepeatInterval: 18 * 60,
                maxSessionCount: 3
            ) { ctx, prefs, _ in
                guard !ctx.showLowCadenceHardWarning else { return false }
                guard ctx.displayPower >= min(120, Int(Double(ftp) * 0.35)) else { return false }
                guard ctx.displayCadenceRpm >= 25 else { return false }
                let margin = 8
                let softBelow = Double(ctx.lowCadenceThreshold - margin)
                guard ctx.displayCadenceRpm < softBelow else { return false }
                guard ctx.lowCadenceStreakSeconds >= 15 && ctx.lowCadenceStreakSeconds < 28 else { return false }
                guard prefs.lowCadenceWarningEnabled else { return false }
                return true
            },
            TipSpec(
                id: "posture_light_grip",
                category: .posture,
                priority: 40,
                headline: "Training tip",
                body: "Light grip on the bars, soft elbows, neutral neck — let the bike support itself.",
                audioScript: "Light grip, soft elbows, easy neck.",
                minRepeatInterval: 32 * 60,
                maxSessionCount: 4
            ) { ctx, _, sess in
                guard ctx.elapsedSeconds >= 42 * 60 else { return false }
                guard sess.postureTipCount < 4 else { return false }
                if sess.lastPostureElapsed >= 0 {
                    guard ctx.elapsedSeconds - sess.lastPostureElapsed >= 28 * 60 else { return false }
                }
                return true
            },
            TipSpec(
                id: "fluids_indoor_warm",
                category: .heatFluids,
                priority: 35,
                headline: "Indoor riding",
                body: "Heat builds indoors — small sips through the ride beat chugging when you’re already behind.",
                audioScript: "Indoor heat adds up — sip fluids regularly.",
                minRepeatInterval: 24 * 60,
                maxSessionCount: 5
            ) { ctx, prefs, _ in
                guard prefs.rideTipsIndoorHeatAwareness else { return false }
                guard ctx.elapsedSeconds >= 40 * 60 else { return false }
                guard ctx.displayPower >= 55 else { return false }
                return true
            },
        ]

        var candidates: [TipSpec] = []
        for tip in tips {
            guard prefs.rideTipsEnabledCategories.contains(tip.category) else { continue }
            let shownCount = session.tipShowCounts[tip.id, default: 0]
            guard shownCount < tip.maxSessionCount else { continue }
            if let lastTipAt = session.lastTipShownAt[tip.id],
               context.now.timeIntervalSince(lastTipAt) < tip.minRepeatInterval {
                continue
            }
            guard tip.isEligible(context, prefs, session) else { continue }
            if let catLast = session.lastCategoryAt[tip.category],
                context.now.timeIntervalSince(catLast) < categoryCooldown
            {
                continue
            }
            candidates.append(tip)
        }

        let hasDistanceGoal = (context.distanceGoalProgress ?? 0) > 0
        guard let best = candidates.max(by: {
            let lhs = $0.priority + (hasDistanceGoal ? tipWeightBoostForDistanceGoals[$0.category, default: 0] : 0)
            let rhs = $1.priority + (hasDistanceGoal ? tipWeightBoostForDistanceGoals[$1.category, default: 0] : 0)
            return lhs < rhs
        }) else { return nil }

        session.tipShowCounts[best.id, default: 0] += 1
        session.lastTipShownAt[best.id] = context.now
        session.lastAnyNudgeAt = context.now
        session.lastCategoryAt[best.category] = context.now

        switch best.id {
        case "recovery_easy_spin":
            session.recoveryTipStepIndices.insert(guidedStepIndex)
        case "posture_light_grip":
            session.postureTipCount += 1
            session.lastPostureElapsed = context.elapsedSeconds
        default:
            break
        }

        return RideNudgeDisplay(
            id: best.id,
            category: best.category,
            headline: best.headline,
            body: best.body,
            audioScript: best.audioScript
        )
    }
}

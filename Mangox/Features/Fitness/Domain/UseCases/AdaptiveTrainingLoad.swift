// Features/Fitness/Domain/UseCases/AdaptiveTrainingLoad.swift
import Foundation
import SwiftData

/// Signals that inform adaptive ERG scaling beyond simple actual/planned TSS ratio.
struct AdaptiveLoadSignals: Sendable {
    let currentTSB: Double?
    let decouplingDirection: AerobicDecouplingTrend.Direction?
    let decouplingSignificant: Bool
    /// Week actual TSS / planned TSS (0…1.5+). Nil when unknown.
    let weekComplianceRatio: Double?

    static let neutral = AdaptiveLoadSignals(
        currentTSB: nil,
        decouplingDirection: nil,
        decouplingSignificant: false,
        weekComplianceRatio: nil
    )
}

/// Nudges ERG targets for guided plan sessions based on completed plan rides, PMC form,
/// aerobic decoupling trend, and weekly compliance (Phase 1 precision coach).
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
        progress: TrainingPlanProgress,
        signals: AdaptiveLoadSignals = .neutral
    ) {
        guard workout.isValid else { return }
        guard planDay.dayType == .workout || planDay.dayType == .ftpTest else { return }

        let ftp = max(1, max(progress.currentFTP, PowerZone.ftp))
        let planned = planDay.estimatedPlannedTSS(ftp: ftp)
        guard planned >= 15 else { return }

        let actual = workout.tss
        guard actual.isFinite, actual >= 0 else { return }

        let oldMultiplier = progress.adaptiveLoadMultiplier

        // Always drift slightly back toward 1.0 so load doesn’t sit pinned forever.
        var m = 1.0 + (progress.adaptiveLoadMultiplier - 1.0) * decayPerRide

        let skipRatioAdjust =
            actual < minTSSForRatioAdjust
            || (workout.maxPower <= 0 && planned >= highPlannedTSSNoPower)

        if !skipRatioAdjust {
            let ratio = actual / planned

            if ratio < 0.82 {
                m = max(minMultiplier, m * 0.985)
            } else if ratio > 1.18 {
                m = applyUpwardAdjustment(current: m, signals: signals)
            }
        }

        m = applyFormAndTrendCaps(to: m, signals: signals)
        progress.adaptiveLoadMultiplier = m

        if abs(m - oldMultiplier) > 0.001 {
            PrecisionCoachInstrumentation.adaptiveLoadAdjusted(
                planID: progress.planID,
                oldMultiplier: oldMultiplier,
                newMultiplier: m,
                tsb: signals.currentTSB
            )
        }
    }

    @MainActor
    static func signals(
        modelContext: ModelContext,
        plan: TrainingPlan?,
        progress: TrainingPlanProgress
    ) -> AdaptiveLoadSignals {
        let ft = FitnessTracker.shared
        let tsb = ft.isLoaded ? ft.currentTSB : nil

        let rideDescriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { $0.statusRaw == "completed" },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let rides = ((try? modelContext.fetch(rideDescriptor)) ?? []).filter(\.isValid)
        let decouplingSamples: [AerobicDecouplingTrend.RideSample] = rides
            .prefix(12)
            .reversed()
            .compactMap { ride in
                guard let result = AerobicDecouplingAnalytics.compute(from: ride),
                      result.status != .insufficientData
                else { return nil }
                return AerobicDecouplingTrend.RideSample(
                    date: ride.startDate,
                    decouplingPercent: result.decouplingPercent,
                    status: result.status
                )
            }
        let decoupling = AerobicDecouplingTrend.analyze(rides: decouplingSamples)

        var complianceRatio: Double?
        if let plan {
            let weekRange = TrainingPlanCompliance.currentWeekRange()
            let weekWorkouts = rides.filter { $0.startDate >= weekRange.start && $0.startDate < weekRange.end }
            let actualWeekTSS = weekWorkouts.reduce(0.0) { $0 + $1.tss }
            let compliance = TrainingPlanCompliance.compute(
                plan: plan,
                progress: progress,
                ftp: max(1, progress.currentFTP),
                actualWeekTSS: actualWeekTSS
            )
            complianceRatio = compliance.completionRatio
        }

        return AdaptiveLoadSignals(
            currentTSB: tsb,
            decouplingDirection: decoupling.direction == .insufficientData ? nil : decoupling.direction,
            decouplingSignificant: decoupling.isSignificant,
            weekComplianceRatio: complianceRatio
        )
    }

    private static func applyUpwardAdjustment(current: Double, signals: AdaptiveLoadSignals) -> Double {
        // Don’t increase load when compliance is poor or form is deeply negative.
        if let ratio = signals.weekComplianceRatio, ratio < 0.70 {
            return current
        }
        if let tsb = signals.currentTSB, tsb < -20 {
            return current
        }
        return min(maxMultiplier, current * 1.012)
    }

    private static func applyFormAndTrendCaps(to multiplier: Double, signals: AdaptiveLoadSignals) -> Double {
        var m = multiplier

        if let tsb = signals.currentTSB {
            if tsb < -30 {
                m = min(m, 0.95)
            } else if tsb < -15, m > 1.0 {
                m = min(m, 1.0)
            }
        }

        if signals.decouplingSignificant,
           signals.decouplingDirection == .worsening,
           m > 1.0
        {
            m = min(m, 1.0)
        }

        return min(maxMultiplier, max(minMultiplier, m))
    }
}

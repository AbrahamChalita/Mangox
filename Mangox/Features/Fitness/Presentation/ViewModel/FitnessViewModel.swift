// Features/Fitness/Presentation/ViewModel/FitnessViewModel.swift
import Foundation

@MainActor
@Observable
final class FitnessViewModel {
    // MARK: - Dependencies
    private let fitnessTracker: FitnessTrackerProtocol
    private let healthKit: HealthKitServiceProtocol
    private let trainingPlanLookupService: TrainingPlanLookupServiceProtocol

    // MARK: - PMC chart state
    var pmcData: [PMCPoint] = []
    var rangeDays: Int = 90
    var showCTL = true
    var showATL = true
    var showTSB = true

    /// Warm-back days before the visible window start.
    static let pmcWarmBackDays = 180

    var pmcRebuildTask: Task<Void, Never>?

    // MARK: - Power curve state
    var powerCurve: [PowerCurveAnalytics.Point] = []
    var isLoading: Bool = false
    var error: String? = nil

    // MARK: - Plan compliance
    var planCompliance: PlanWeekCompliance.Snapshot?

    let rangeOptions = [30, 60, 90, 180, 365]

    init(
        fitnessTracker: FitnessTrackerProtocol,
        healthKit: HealthKitServiceProtocol,
        trainingPlanLookupService: TrainingPlanLookupServiceProtocol
    ) {
        self.fitnessTracker = fitnessTracker
        self.healthKit = healthKit
        self.trainingPlanLookupService = trainingPlanLookupService
    }

    // MARK: - Range selection

    func setRange(_ days: Int) {
        rangeDays = days
    }

    // MARK: - PMC rebuild

    func schedulePMCRebuild(with workouts: [WorkoutMetricsSnapshot]) {
        if workouts.isEmpty || pmcData.isEmpty {
            pmcRebuildTask?.cancel()
            rebuildPMC(from: workouts)
            return
        }
        pmcRebuildTask?.cancel()
        pmcRebuildTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(64))
            guard !Task.isCancelled else { return }
            rebuildPMC(from: workouts)
        }
    }

    func rebuildPMC(from workouts: [WorkoutMetricsSnapshot]) {
        rebuildPowerCurve(from: workouts)

        guard !workouts.isEmpty else {
            pmcData = []
            return
        }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let startDate = cal.date(byAdding: .day, value: -rangeDays, to: today)
        else { return }
        guard let warmStart = cal.date(byAdding: .day, value: -Self.pmcWarmBackDays, to: startDate)
        else { return }

        var tssByDay: [Date: Double] = [:]
        for workout in workouts {
            let day = cal.startOfDay(for: workout.startDate)
            if day < warmStart || day > today { continue }
            tssByDay[day, default: 0] += workout.tss
        }

        let ctlConstant = 42.0
        let atlConstant = 7.0
        var ctl = 0.0
        var atl = 0.0

        var points: [PMCPoint] = []
        var currentDate = warmStart

        while currentDate <= today {
            let dayTSS = tssByDay[currentDate] ?? 0
            ctl = ctl + (dayTSS - ctl) / ctlConstant
            atl = atl + (dayTSS - atl) / atlConstant

            if currentDate >= startDate {
                points.append(
                    PMCPoint(
                        date: currentDate,
                        ctl: ctl,
                        atl: atl,
                        tsb: ctl - atl
                    ))
            }

            currentDate = cal.date(byAdding: .day, value: 1, to: currentDate)!
        }

        pmcData = points
    }

    // MARK: - Power curve

    func loadPowerCurve(from powerStreams: [[Int]]) {
        powerCurve = PowerCurveAnalytics.compute(from: powerStreams)
    }

    func rebuildPowerCurve(from workouts: [WorkoutMetricsSnapshot], rangeDays: Int? = nil) {
        let days = rangeDays ?? self.rangeDays
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let cutoff = cal.date(byAdding: .day, value: -days, to: today) ?? .distantPast

        var streams: [[Int]] = []
        var used = 0
        for workout in workouts {
            guard used < 80 else { break }
            guard workout.startDate >= cutoff else { continue }
            guard workout.sampleCount >= 5, workout.maxPower > 0 else { continue }
            let powers = workout.sortedPowers
            guard powers.count >= 5 else { continue }
            streams.append(powers)
            used += 1
        }

        loadPowerCurve(from: streams)
    }

    // MARK: - Plan compliance

    func updatePlanCompliance(
        progress: [TrainingPlanProgress],
        workouts: [WorkoutMetricsSnapshot]
    ) {
        guard let p = progress.first else {
            planCompliance = nil
            return
        }
        let plan = trainingPlanLookupService.resolvePlan(planID: p.planID)
        planCompliance = PlanWeekCompliance.snapshot(progress: p, plan: plan, recentWorkouts: workouts)
    }
}

// MARK: - PMC Point

struct PMCPoint: Identifiable {
    let date: Date
    let ctl: Double
    let atl: Double
    let tsb: Double

    var id: Date { date }
}

import Foundation
import Observation

// MARK: - Lightweight inputs (Sendable — safe for background PMC math)

/// Scalar snapshot of a workout for CTL/ATL math without passing SwiftData models across actors.
struct WorkoutLoadSnapshot: Sendable {
    let startDate: Date
    let tss: Double
    let distance: Double
    let duration: TimeInterval
    let isValid: Bool
}

// MARK: - Daily Fitness Entry

/// One day's fitness snapshot used for the PMC chart.
struct FitnessDayEntry: Identifiable {
    let date: Date
    let ctl: Double   // Chronic Training Load (42-day EMA of TSS) — "fitness"
    let atl: Double   // Acute Training Load  (7-day  EMA of TSS) — "fatigue"
    let tsb: Double   // Training Stress Balance = CTL − ATL       — "form"
    let tss: Double   // Actual TSS recorded on this day (0 if rest day)

    var id: TimeInterval { date.timeIntervalSince1970 }

    /// Colour-coded form state based on TSB value.
    var formState: FormState {
        if tsb > 25  { return .fresh }
        if tsb > 5   { return .optimal }
        if tsb > -10 { return .neutral }
        if tsb > -30 { return .fatigued }
        return .overreached
    }
}

// MARK: - Form State

enum FormState: String {
    case fresh      = "Fresh"
    case optimal    = "Optimal"
    case neutral    = "Neutral"
    case fatigued   = "Fatigued"
    case overreached = "Overreached"

    var emoji: String {
        switch self {
        case .fresh:       return "😎"
        case .optimal:     return "✅"
        case .neutral:     return "😐"
        case .fatigued:    return "😓"
        case .overreached: return "🥵"
        }
    }

    var color: String {
        // Returned as a semantic name; views resolve to AppColor themselves.
        switch self {
        case .fresh:       return "blue"
        case .optimal:     return "success"
        case .neutral:     return "yellow"
        case .fatigued:    return "orange"
        case .overreached: return "red"
        }
    }
}

// MARK: - Weekly Summary

struct WeekSummary: Identifiable {
    let weekStart: Date    // Monday of the week
    let totalTSS: Double
    let totalDistance: Double   // meters
    let totalDuration: Double   // seconds
    let rideCount: Int

    var id: TimeInterval { weekStart.timeIntervalSince1970 }
}

// MARK: - FitnessTracker

/// Computes the Performance Management Chart (PMC) metrics from saved workout history.
///
/// - CTL (Chronic Training Load) = 42-day exponential moving average of daily TSS
/// - ATL (Acute Training Load)   = 7-day  exponential moving average of daily TSS
/// - TSB (Training Stress Balance) = CTL − ATL
///
/// All heavy work runs off the main actor via Task.detached.
@Observable
@MainActor
final class FitnessTracker: FitnessTrackerProtocol {

    // MARK: - Singleton

    static let shared = FitnessTracker()

    // MARK: - Constants

    /// Number of days used for CTL (chronic / fitness).
    private static let ctlDays = 42
    /// Number of days used for ATL (acute / fatigue).
    private static let atlDays = 7

    // Exponential smoothing factors
    private static let ctlAlpha: Double = 2.0 / Double(ctlDays + 1)
    private static let atlAlpha: Double = 2.0 / Double(atlDays + 1)

    // MARK: - Published State

    /// Full PMC history — one entry per calendar day, sorted ascending.
    private(set) var history: [FitnessDayEntry] = []

    /// Weekly summaries for the bar chart — sorted ascending.
    private(set) var weeklyHistory: [WeekSummary] = []

    /// Today's snapshot (last entry in history).
    var today: FitnessDayEntry? { history.last }

    /// Current CTL (fitness).
    var currentCTL: Double { today?.ctl ?? 0 }

    /// Current ATL (fatigue).
    var currentATL: Double { today?.atl ?? 0 }

    /// Current TSB (form).
    var currentTSB: Double { today?.tsb ?? 0 }

    /// Current form state.
    var currentFormState: FormState { today?.formState ?? .neutral }

    /// Whether data has been computed at least once.
    private(set) var isLoaded = false

    // MARK: - Weekly TSS Goal (persisted)

    private static let weeklyTSSGoalKey = "fitness_weekly_tss_goal"

    var weeklyTSSGoal: Double {
        didSet {
            UserDefaults.standard.set(weeklyTSSGoal, forKey: Self.weeklyTSSGoalKey)
        }
    }

    /// TSS accumulated in the current calendar week (Mon–Sun).
    var currentWeekTSS: Double {
        let cal = Calendar.current
        let now = Date()
        guard let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) else {
            return 0
        }
        return history
            .filter { $0.date >= weekStart && $0.date <= now }
            .reduce(0) { $0 + $1.tss }
    }

    var currentWeekProgress: Double {
        guard weeklyTSSGoal > 0 else { return 0 }
        return min(1.0, currentWeekTSS / weeklyTSSGoal)
    }

    // MARK: - Init

    private init() {
        let stored = UserDefaults.standard.double(forKey: Self.weeklyTSSGoalKey)
        self.weeklyTSSGoal = stored > 0 ? stored : 400
    }

    // MARK: - Public API

    /// Recompute all metrics from the given list of workouts.
    /// Safe to call repeatedly; each call replaces the previous result.
    func compute(from workouts: [Workout]) async {
        isLoaded = false

        let snapshots = workouts.map {
            WorkoutLoadSnapshot(
                startDate: $0.startDate,
                tss: $0.tss,
                distance: $0.distance,
                duration: $0.duration,
                isValid: $0.isValid
            )
        }

        let result = await Task.detached(priority: .utility) { [ctlAlpha = Self.ctlAlpha,
                                                                  atlAlpha = Self.atlAlpha,
                                                                  ctlDays = Self.ctlDays] in
            Self.buildHistory(workouts: snapshots, ctlAlpha: ctlAlpha, atlAlpha: atlAlpha, ctlDays: ctlDays)
        }.value

        history = result.days
        weeklyHistory = result.weeks
        isLoaded = true
    }

    // MARK: - Private Computation

    private struct ComputeResult {
        var days: [FitnessDayEntry]
        var weeks: [WeekSummary]
    }

    nonisolated private static func buildHistory(
        workouts: [WorkoutLoadSnapshot],
        ctlAlpha: Double,
        atlAlpha: Double,
        ctlDays: Int
    ) -> ComputeResult {

        guard !workouts.isEmpty else {
            return ComputeResult(days: [], weeks: [])
        }

        let cal = Calendar(identifier: .gregorian)

        // Build a dictionary: normalized-date → TSS for all valid workouts
        var tssByDay: [Date: Double] = [:]
        var distanceByDay: [Date: Double] = [:]
        var durationByDay: [Date: Double] = [:]
        var countByDay: [Date: Int] = [:]

        for workout in workouts where workout.isValid {
            let day = cal.startOfDay(for: workout.startDate)
            tssByDay[day, default: 0] += workout.tss
            distanceByDay[day, default: 0] += workout.distance
            durationByDay[day, default: 0] += workout.duration
            countByDay[day, default: 0] += 1
        }

        guard let earliestDay = tssByDay.keys.min() else {
            return ComputeResult(days: [], weeks: [])
        }

        // Build a contiguous day range from the first workout to today
        let today = cal.startOfDay(for: Date())
        // Start slightly before earliest workout so CTL has a warm-up period
        let warmupStart = cal.date(byAdding: .day, value: -(ctlDays), to: earliestDay) ?? earliestDay
        let start = min(warmupStart, earliestDay)

        var days: [FitnessDayEntry] = []
        var ctl: Double = 0
        var atl: Double = 0

        var current = start
        while current <= today {
            let tss = tssByDay[current] ?? 0

            // EMA update
            ctl = ctl + ctlAlpha * (tss - ctl)
            atl = atl + atlAlpha * (tss - atl)
            let tsb = ctl - atl

            // Only include days from the earliest actual workout onwards
            if current >= earliestDay {
                days.append(FitnessDayEntry(
                    date: current,
                    ctl: ctl,
                    atl: atl,
                    tsb: tsb,
                    tss: tss
                ))
            }

            current = cal.date(byAdding: .day, value: 1, to: current) ?? today.addingTimeInterval(86400)
        }

        // --- Weekly summaries ---
        var weeks: [WeekSummary] = []
        var weekBuckets: [Date: (tss: Double, dist: Double, dur: Double, count: Int)] = [:]

        for (day, tss) in tssByDay {
            // Find Monday of this day's week
            var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: day)
            comps.weekday = 2 // Monday
            guard let weekStart = cal.date(from: comps) else { continue }

            weekBuckets[weekStart, default: (0, 0, 0, 0)].tss   += tss
            weekBuckets[weekStart, default: (0, 0, 0, 0)].dist  += distanceByDay[day] ?? 0
            weekBuckets[weekStart, default: (0, 0, 0, 0)].dur   += durationByDay[day] ?? 0
            weekBuckets[weekStart, default: (0, 0, 0, 0)].count += countByDay[day] ?? 0
        }

        weeks = weekBuckets.map { weekStart, bucket in
            WeekSummary(
                weekStart: weekStart,
                totalTSS: bucket.tss,
                totalDistance: bucket.dist,
                totalDuration: bucket.dur,
                rideCount: bucket.count
            )
        }.sorted { $0.weekStart < $1.weekStart }

        return ComputeResult(days: days, weeks: weeks)
    }
}

// Features/Fitness/Data/DataSources/PersonalRecords.swift
import Foundation
import SwiftData

// MARK: - MMP Duration Buckets

/// The canonical durations (in seconds) used for Mean Maximal Power tracking.
enum MMPDuration: Int, CaseIterable, Identifiable {
    case five        = 5
    case thirty      = 30
    case sixty       = 60
    case fiveMin     = 300
    case tenMin      = 600
    case twentyMin   = 1200
    case thirtyMin   = 1800
    case sixtyMin    = 3600

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .five:      return "5s"
        case .thirty:    return "30s"
        case .sixty:     return "1m"
        case .fiveMin:   return "5m"
        case .tenMin:    return "10m"
        case .twentyMin: return "20m"
        case .thirtyMin: return "30m"
        case .sixtyMin:  return "60m"
        }
    }
}

// MARK: - MMP Result

/// Best average power held for a given duration within a single workout.
struct MMPResult: Identifiable {
    let duration: MMPDuration
    let watts: Int
    let workoutID: UUID
    let date: Date

    var id: Int { duration.rawValue }

    var wattsPerKg: Double? {
        let weight = RidePreferences.shared.riderWeightKg
        guard weight > 0 else { return nil }
        return Double(watts) / weight
    }
}

// MARK: - PR Entry

/// A confirmed personal record: the best MMP across all workouts for a duration.
struct PREntry: Identifiable {
    let duration: MMPDuration
    let watts: Int
    let workoutID: UUID
    let date: Date

    var id: Int { duration.rawValue }
}

// MARK: - Workout MMP

/// All MMP results for a single workout.
struct WorkoutMMP {
    let workoutID: UUID
    let results: [MMPResult]

    func watts(for duration: MMPDuration) -> Int? {
        results.first { $0.duration == duration }?.watts
    }
}

// MARK: - New PR Flag

/// Marks that a specific duration is a new PR in the context of the just-completed workout.
struct NewPRFlag: Identifiable {
    let duration: MMPDuration
    let watts: Int
    var id: Int { duration.rawValue }
}

// MARK: - PersonalRecords Service

/// Computes Mean Maximal Power curves and detects personal records across all saved workouts.
///
/// Designed to be called lazily from SummaryView after a ride — not running continuously.
/// All heavy computation is done off the main actor and results are published back.
@Observable
@MainActor
final class PersonalRecords: PersonalRecordsServiceProtocol {

    // MARK: - Singleton

    static let shared = PersonalRecords()

    // MARK: - Published State

    /// All-time best power for each MMP duration bucket.
    private(set) var allTimePRs: [PREntry] = []

    /// Whether the service has finished computing.
    private(set) var isLoaded = false

    // MARK: - Incremental State

    /// Per-workout MMP results cached in memory (keyed by workout ID).
    /// Persisted across load() calls so new workouts only need their own MMP computed.
    private var cachedMMPs: [UUID: WorkoutMMP] = [:]

    // MARK: - Init

    private init() {}

    // MARK: - Public API

    /// Compute (or refresh) all-time PRs from all workouts in the given context.
    /// Incremental: only recomputes MMP for workouts not yet cached.
    func load(from workouts: [Workout]) async {
        isLoaded = false
        let cached = self.cachedMMPs
        let prs = await Task.detached(priority: .utility) {
            Self.computeAllTimePRsIncremental(from: workouts, cachedMMPs: cached)
        }.value
        allTimePRs = prs.entries
        cachedMMPs = prs.updatedCache
        isLoaded = true
    }

    /// Compute the MMP curve for a single workout's samples.
    /// This is the per-workout curve displayed in SummaryView.
    nonisolated static func computeMMP(for samples: [WorkoutSampleData], workoutID: UUID) -> WorkoutMMP? {
        guard !samples.isEmpty, let first = samples.first else { return nil }
        // workoutID is passed

        let sorted = samples.sorted { $0.elapsedSeconds < $1.elapsedSeconds }
        let powers = sorted.map { $0.power }

        var results: [MMPResult] = []

        for bucket in MMPDuration.allCases {
            let windowSize = bucket.rawValue
            guard powers.count >= windowSize else { continue }

            var bestAvg = 0
            var windowSum = 0

            // Seed the first window
            for i in 0..<windowSize {
                windowSum += powers[i]
            }
            bestAvg = windowSum / windowSize

            // Slide
            for i in windowSize..<powers.count {
                windowSum += powers[i]
                windowSum -= powers[i - windowSize]
                let avg = windowSum / windowSize
                if avg > bestAvg {
                    bestAvg = avg
                }
            }

            if bestAvg > 0 {
                results.append(MMPResult(
                    duration: bucket,
                    watts: bestAvg,
                    workoutID: workoutID,
                    date: first.timestamp
                ))
            }
        }

        guard !results.isEmpty else { return nil }
        return WorkoutMMP(workoutID: workoutID, results: results)
    }

    /// Instance-method wrapper that satisfies `PersonalRecordsServiceProtocol`.
    /// Delegates to the static implementation.
    func computeMMP(for samples: [WorkoutSampleData], workoutID: UUID) -> WorkoutMMP? {
        Self.computeMMP(for: samples, workoutID: workoutID)
    }

    /// Compare a freshly-computed WorkoutMMP against stored all-time PRs and
    /// return which durations represent new personal records.
    func newPRs(for mmp: WorkoutMMP) -> [NewPRFlag] {
        var flags: [NewPRFlag] = []

        for result in mmp.results {
            let existing = allTimePRs.first { $0.duration == result.duration }
            if existing == nil || result.watts > existing!.watts {
                flags.append(NewPRFlag(duration: result.duration, watts: result.watts))
            }
        }

        return flags
    }

    /// Return all-time PRs as WorkoutMMP-compatible lookup for profile / training views.
    func allTimePRResult(for duration: MMPDuration) -> PREntry? {
        allTimePRs.first { $0.duration == duration }
    }

    // MARK: - Private Computation

    /// Incremental: only compute MMP for new workouts, merge with cached results.
    nonisolated private static func computeAllTimePRsIncremental(
        from workouts: [Workout],
        cachedMMPs: [UUID: WorkoutMMP]
    ) -> (entries: [PREntry], updatedCache: [UUID: WorkoutMMP]) {
        var mmpCache = cachedMMPs
        var best: [MMPDuration: (watts: Int, workoutID: UUID, date: Date)] = [:]

        // Seed best from cached MMPs first
        for (_, mmp) in mmpCache {
            for result in mmp.results {
                if let existing = best[result.duration] {
                    if result.watts > existing.watts {
                        best[result.duration] = (result.watts, mmp.workoutID, result.date)
                    }
                } else {
                    best[result.duration] = (result.watts, mmp.workoutID, result.date)
                }
            }
        }

        // Only compute MMP for workouts not in cache
        for workout in workouts {
            guard workout.isValid else { continue }

            if let cached = mmpCache[workout.id] {
                // Already computed — merge into best
                for result in cached.results {
                    if let existing = best[result.duration] {
                        if result.watts > existing.watts {
                            best[result.duration] = (result.watts, cached.workoutID, result.date)
                        }
                    } else {
                        best[result.duration] = (result.watts, cached.workoutID, result.date)
                    }
                }
                continue
            }

            // New workout — compute MMP
            let sorted = workout.samples.sorted { $0.elapsedSeconds < $1.elapsedSeconds }
            let powers = sorted.map { $0.power }
            guard !powers.isEmpty else { continue }
            let date = workout.startDate

            var workoutResults: [MMPResult] = []
            for bucket in MMPDuration.allCases {
                let windowSize = bucket.rawValue
                guard powers.count >= windowSize else { continue }

                var windowSum = 0
                for i in 0..<windowSize { windowSum += powers[i] }
                var bestAvg = windowSum / windowSize

                for i in windowSize..<powers.count {
                    windowSum += powers[i]
                    windowSum -= powers[i - windowSize]
                    let avg = windowSum / windowSize
                    if avg > bestAvg { bestAvg = avg }
                }

                if bestAvg > 0 {
                    workoutResults.append(MMPResult(
                        duration: bucket, watts: bestAvg,
                        workoutID: workout.id, date: date
                    ))
                    if let existing = best[bucket] {
                        if bestAvg > existing.watts {
                            best[bucket] = (bestAvg, workout.id, date)
                        }
                    } else {
                        best[bucket] = (bestAvg, workout.id, date)
                    }
                }
            }

            if !workoutResults.isEmpty {
                mmpCache[workout.id] = WorkoutMMP(workoutID: workout.id, results: workoutResults)
            }
        }

        let entries = best.map { duration, entry in
            PREntry(duration: duration, watts: entry.watts, workoutID: entry.workoutID, date: entry.date)
        }.sorted { $0.duration.rawValue < $1.duration.rawValue }

        return (entries, mmpCache)
    }
}

// Features/Fitness/Data/DataSources/FitnessSettingsSnapshotOperations.swift
import Foundation
import SwiftData

enum FitnessSettingsSnapshotRecorder {
    private static let dedupeSeconds: TimeInterval = 45

    @MainActor
    static func recordFromCurrentSettings(source: String) {
        recordFromCurrentSettings(
            source: source,
            modelContext: PersistenceContainer.shared.mainContext
        )
    }

    @MainActor
    static func recordFromCurrentSettings(source: String, modelContext: ModelContext) {
        let ftp = PowerZone.ftp
        let maxHR = HeartRateZone.maxHR
        let resting = HeartRateZone.restingHR
        if shouldSkipDedupe(
            ftp: ftp, maxHR: maxHR, resting: resting, modelContext: modelContext
        ) {
            return
        }
        let row = FitnessSettingsSnapshot(
            ftpWatts: ftp,
            maxHR: maxHR,
            restingHR: resting,
            sourceRaw: source
        )
        modelContext.insert(row)
        try? modelContext.save()
    }

    @MainActor
    private static func shouldSkipDedupe(
        ftp: Int, maxHR: Int, resting: Int, modelContext: ModelContext
    ) -> Bool {
        var d = FetchDescriptor<FitnessSettingsSnapshot>(
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        d.fetchLimit = 1
        guard let last = try? modelContext.fetch(d).first else { return false }
        guard Date().timeIntervalSince(last.recordedAt) < dedupeSeconds else { return false }
        return last.ftpWatts == ftp && last.maxHR == maxHR && last.restingHR == resting
    }
}

// MARK: - One-time backfill (pre-timeline users)

enum FitnessSettingsSnapshotBackfill {
    private static let doneKey = "mangox.fitness_snapshot_backfill_v1"

    /// Inserts a single snapshot from current settings when the store has none (e.g. before the timeline shipped).
    @MainActor
    static func runIfNeeded() {
        runIfNeeded(modelContext: PersistenceContainer.shared.mainContext)
    }

    /// Inserts a single snapshot from current settings when the store has none (e.g. before the timeline shipped).
    @MainActor
    static func runIfNeeded(modelContext: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return }

        var descriptor = FetchDescriptor<FitnessSettingsSnapshot>()
        descriptor.fetchLimit = 1
        let existing = (try? modelContext.fetch(descriptor))?.isEmpty == false
        if existing {
            UserDefaults.standard.set(true, forKey: doneKey)
            return
        }

        let recordedAt = PowerZone.lastFTPUpdate ?? Date()
        let row = FitnessSettingsSnapshot(
            recordedAt: recordedAt,
            ftpWatts: PowerZone.ftp,
            maxHR: HeartRateZone.maxHR,
            restingHR: HeartRateZone.restingHR,
            sourceRaw: "backfill_migration"
        )
        modelContext.insert(row)
        try? modelContext.save()
        UserDefaults.standard.set(true, forKey: doneKey)
    }
}

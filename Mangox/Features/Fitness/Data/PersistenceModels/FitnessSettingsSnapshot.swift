// Features/Fitness/Data/PersistenceModels/FitnessSettingsSnapshot.swift
import Foundation
import SwiftData

/// Point-in-time record of FTP and HR settings (manual changes and applied tests).
@Model
final class FitnessSettingsSnapshot {
    @Attribute(.unique) var id: UUID
    var recordedAt: Date
    var ftpWatts: Int
    var maxHR: Int
    var restingHR: Int
    /// e.g. `ftp_settings`, `hr_settings`, `ftp_test`
    var sourceRaw: String

    init(
        id: UUID = UUID(),
        recordedAt: Date = .now,
        ftpWatts: Int,
        maxHR: Int,
        restingHR: Int,
        sourceRaw: String
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.ftpWatts = ftpWatts
        self.maxHR = maxHR
        self.restingHR = restingHR
        self.sourceRaw = sourceRaw
    }
}

// NOTE: FitnessSettingsSnapshotRecorder and FitnessSettingsSnapshotBackfill have been
// moved to the Data layer (FitnessSettingsSnapshotOperations.swift) to preserve
// Domain purity — they depend on SwiftData ModelContext / FetchDescriptor.

import Foundation
import SwiftData

/// Exports ride metadata and fitness snapshots as JSON for user data portability.
enum UserDataExportService {

    /// `standard` — compact ride summaries. `extended` — adds sample counts, max power, elevation, and status.
    enum ExportTier: String, Codable {
        case standard
        case extended
    }

    struct WorkoutExportRow: Codable {
        let id: String
        let startDate: Date
        let endDate: Date?
        let durationSeconds: Double
        let distanceMeters: Double
        let avgPower: Double
        let normalizedPower: Double
        let tss: Double
        let planDayID: String?
        let planID: String?
        let savedRouteName: String?
        let sampleCount: Int?
        let maxPowerWatts: Int?
        let elevationGainMeters: Double?
        let completionStatus: String?
    }

    struct SnapshotExportRow: Codable {
        let recordedAt: Date
        let ftpWatts: Int
        let maxHR: Int
        let restingHR: Int
        let source: String
    }

    struct Bundle: Codable {
        let exportedAt: Date
        let app: String
        let exportTier: String
        let workouts: [WorkoutExportRow]
        let fitnessSnapshots: [SnapshotExportRow]
    }

    @MainActor
    static func buildExportBundle(
        modelContext: ModelContext,
        tier: ExportTier = .standard
    ) throws -> URL {
        var wd = FetchDescriptor<Workout>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        wd.fetchLimit = 5000
        let workouts = (try? modelContext.fetch(wd)) ?? []

        let rows = workouts.map { w in
            WorkoutExportRow(
                id: w.id.uuidString,
                startDate: w.startDate,
                endDate: w.endDate,
                durationSeconds: w.duration,
                distanceMeters: w.distance,
                avgPower: w.avgPower,
                normalizedPower: w.normalizedPower,
                tss: w.tss,
                planDayID: w.planDayID,
                planID: w.planID,
                savedRouteName: w.savedRouteName,
                sampleCount: tier == .extended ? w.sampleCount : nil,
                maxPowerWatts: tier == .extended ? w.maxPower : nil,
                elevationGainMeters: tier == .extended ? w.elevationGain : nil,
                completionStatus: tier == .extended ? w.statusRaw : nil
            )
        }

        var sd = FetchDescriptor<FitnessSettingsSnapshot>(
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        sd.fetchLimit = 500
        let snaps = (try? modelContext.fetch(sd)) ?? []
        let snapRows = snaps.map {
            SnapshotExportRow(
                recordedAt: $0.recordedAt,
                ftpWatts: $0.ftpWatts,
                maxHR: $0.maxHR,
                restingHR: $0.restingHR,
                source: $0.sourceRaw
            )
        }

        let bundle = Bundle(
            exportedAt: Date(),
            app: "Mangox",
            exportTier: tier.rawValue,
            workouts: rows,
            fitnessSnapshots: snapRows
        )

        let data = try JSONEncoder().encode(bundle)
        let suffix = tier == .extended ? "-extended" : ""
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mangox-export\(suffix)-\(Int(Date().timeIntervalSince1970)).json")
        try data.write(to: url, options: .atomic)
        return url
    }
}

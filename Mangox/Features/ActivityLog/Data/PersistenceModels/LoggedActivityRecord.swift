// Features/ActivityLog/Data/PersistenceModels/LoggedActivityRecord.swift
import Foundation
import SwiftData

@Model
final class LoggedActivityRecord {
    @Attribute(.unique) var id: UUID

    var sourceRaw: String
    var externalID: String?
    var typeRaw: String
    var customLabel: String?
    var startDate: Date
    var durationSeconds: Int
    var intensityRaw: String?
    /// 0 means nil (sentinel, same convention as Workout.rpe).
    var rpe: Int

    var notes: String

    // Metrics — -1 means nil for Double fields, 0 means nil for Int fields.
    var distanceMeters: Double
    var elevationGainMeters: Double
    var avgHeartRate: Int
    var maxHeartRate: Int
    var calories: Int
    var sets: Int
    var reps: Int
    var weightKg: Double
    var strain: Double
    var kilojoules: Double
    var avgSpeedMetersPerSecond: Double = -1
    var maxSpeedMetersPerSecond: Double = -1
    var relativeEffort: Int = 0
    var achievementCount: Int = 0
    var prCount: Int = 0
    var mapSummaryPolyline: String?
    var percentRecorded: Double = -1
    var altitudeChangeMeters: Double = -1
    var hrZoneZeroMillis: Int = 0
    var hrZoneOneMillis: Int = 0
    var hrZoneTwoMillis: Int = 0
    var hrZoneThreeMillis: Int = 0
    var hrZoneFourMillis: Int = 0
    var hrZoneFiveMillis: Int = 0

    var createdAt: Date
    var updatedAt: Date

    init(draft: LoggedActivityDraft) {
        self.id = draft.id
        self.sourceRaw = draft.source.rawValue
        self.externalID = draft.externalID
        self.typeRaw = draft.type.rawValue
        self.customLabel = draft.customLabel
        self.startDate = draft.startDate
        self.durationSeconds = draft.durationSeconds
        self.intensityRaw = draft.intensity?.rawValue
        self.rpe = draft.rpe ?? 0
        self.notes = draft.notes
        let m = draft.metrics
        self.distanceMeters = m.distanceMeters ?? -1
        self.elevationGainMeters = m.elevationGainMeters ?? -1
        self.avgHeartRate = m.avgHeartRate ?? 0
        self.maxHeartRate = m.maxHeartRate ?? 0
        self.calories = m.calories ?? 0
        self.sets = m.sets ?? 0
        self.reps = m.reps ?? 0
        self.weightKg = m.weightKg ?? -1
        self.strain = m.strain ?? -1
        self.kilojoules = m.kilojoules ?? -1
        self.createdAt = Date()
        self.updatedAt = Date()
        self.applyExtendedMetrics(m)
    }

    func apply(_ draft: LoggedActivityDraft) {
        typeRaw = draft.type.rawValue
        customLabel = draft.customLabel
        startDate = draft.startDate
        durationSeconds = draft.durationSeconds
        intensityRaw = draft.intensity?.rawValue
        rpe = draft.rpe ?? 0
        notes = draft.notes
        let m = draft.metrics
        distanceMeters = m.distanceMeters ?? -1
        elevationGainMeters = m.elevationGainMeters ?? -1
        avgHeartRate = m.avgHeartRate ?? 0
        maxHeartRate = m.maxHeartRate ?? 0
        calories = m.calories ?? 0
        sets = m.sets ?? 0
        reps = m.reps ?? 0
        weightKg = m.weightKg ?? -1
        strain = m.strain ?? -1
        kilojoules = m.kilojoules ?? -1
        applyExtendedMetrics(m)
        updatedAt = Date()
    }

    func toDomain() -> LoggedActivity {
        LoggedActivity(
            id: id,
            source: LoggedActivitySource(rawValue: sourceRaw) ?? .manual,
            externalID: externalID,
            type: LoggedActivityType(rawValue: typeRaw) ?? .other,
            customLabel: customLabel,
            startDate: startDate,
            durationSeconds: durationSeconds,
            intensity: intensityRaw.flatMap { LoggedActivityIntensity(rawValue: $0) },
            rpe: rpe > 0 ? rpe : nil,
            notes: notes,
            metrics: LoggedActivityMetrics(
                distanceMeters: distanceMeters >= 0 ? distanceMeters : nil,
                elevationGainMeters: elevationGainMeters >= 0 ? elevationGainMeters : nil,
                avgHeartRate: avgHeartRate > 0 ? avgHeartRate : nil,
                maxHeartRate: maxHeartRate > 0 ? maxHeartRate : nil,
                calories: calories > 0 ? calories : nil,
                sets: sets > 0 ? sets : nil,
                reps: reps > 0 ? reps : nil,
                weightKg: weightKg >= 0 ? weightKg : nil,
                strain: strain >= 0 ? strain : nil,
                kilojoules: kilojoules >= 0 ? kilojoules : nil,
                avgSpeedMetersPerSecond: avgSpeedMetersPerSecond >= 0 ? avgSpeedMetersPerSecond : nil,
                maxSpeedMetersPerSecond: maxSpeedMetersPerSecond >= 0 ? maxSpeedMetersPerSecond : nil,
                relativeEffort: relativeEffort > 0 ? relativeEffort : nil,
                achievementCount: achievementCount > 0 ? achievementCount : nil,
                prCount: prCount > 0 ? prCount : nil,
                mapSummaryPolyline: mapSummaryPolyline,
                percentRecorded: percentRecorded >= 0 ? percentRecorded : nil,
                altitudeChangeMeters: altitudeChangeMeters >= 0 ? altitudeChangeMeters : nil,
                heartRateZoneMillis: heartRateZoneMillis
            ),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private var heartRateZoneMillis: [Int]? {
        let values = [
            hrZoneZeroMillis,
            hrZoneOneMillis,
            hrZoneTwoMillis,
            hrZoneThreeMillis,
            hrZoneFourMillis,
            hrZoneFiveMillis,
        ]
        return values.contains { $0 > 0 } ? values : nil
    }

    private func applyExtendedMetrics(_ metrics: LoggedActivityMetrics) {
        avgSpeedMetersPerSecond = metrics.avgSpeedMetersPerSecond ?? -1
        maxSpeedMetersPerSecond = metrics.maxSpeedMetersPerSecond ?? -1
        relativeEffort = metrics.relativeEffort ?? 0
        achievementCount = metrics.achievementCount ?? 0
        prCount = metrics.prCount ?? 0
        mapSummaryPolyline = metrics.mapSummaryPolyline
        percentRecorded = metrics.percentRecorded ?? -1
        altitudeChangeMeters = metrics.altitudeChangeMeters ?? -1

        var zones = Array(repeating: 0, count: 6)
        if let sourceZones = metrics.heartRateZoneMillis {
            for (index, value) in sourceZones.prefix(6).enumerated() {
                zones[index] = max(0, value)
            }
        }
        hrZoneZeroMillis = zones[0]
        hrZoneOneMillis = zones[1]
        hrZoneTwoMillis = zones[2]
        hrZoneThreeMillis = zones[3]
        hrZoneFourMillis = zones[4]
        hrZoneFiveMillis = zones[5]
    }
}

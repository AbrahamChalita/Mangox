// Features/ActivityLog/Data/Mappers/WhoopWorkoutMapper.swift
import Foundation

enum WhoopWorkoutMapper {
    /// Sport IDs to exclude — cycling family. Whoop's catalogue has no official public
    /// list; these IDs cover road, mountain, indoor, track, and virtual cycling.
    private static let cyclingIDs: Set<Int> = [1, 63, 64, 65, 126]

    static func draft(from dto: WhoopWorkoutDTO) -> LoggedActivityDraft? {
        guard !cyclingIDs.contains(dto.sportId) else { return nil }

        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let start = fmt.date(from: dto.start) ?? ISO8601DateFormatter().date(from: dto.start) else { return nil }

        let end = dto.end.flatMap { fmt.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
        let duration = end.map { Int($0.timeIntervalSince(start)) } ?? 0
        guard duration > 0 else { return nil }

        let type = activityType(for: dto.sportId, name: dto.sportName)
        let customLabel: String? = type == .other ? dto.sportName : nil

        var metrics = LoggedActivityMetrics()
        if let score = dto.score {
            metrics.avgHeartRate = score.averageHeartRate
            metrics.maxHeartRate = score.maxHeartRate
            metrics.strain = score.strain
            metrics.kilojoules = score.kilojoule
            if let dist = score.distanceMeter, dist > 0 { metrics.distanceMeters = dist }
            if let gain = score.altitudeGainMeter, gain > 0 { metrics.elevationGainMeters = gain }
            metrics.altitudeChangeMeters = score.altitudeChangeMeter
            metrics.percentRecorded = score.percentRecorded
            if let zones = score.zoneDurations {
                metrics.heartRateZoneMillis = [
                    zones.zoneZeroMilli ?? 0,
                    zones.zoneOneMilli ?? 0,
                    zones.zoneTwoMilli ?? 0,
                    zones.zoneThreeMilli ?? 0,
                    zones.zoneFourMilli ?? 0,
                    zones.zoneFiveMilli ?? 0,
                ]
            }
        }

        return LoggedActivityDraft(
            id: UUID(),
            source: .whoop,
            externalID: dto.id,
            type: type,
            customLabel: customLabel,
            startDate: start,
            durationSeconds: duration,
            intensity: nil,
            rpe: nil,
            notes: "",
            metrics: metrics
        )
    }

    private static func activityType(for sportID: Int, name: String) -> LoggedActivityType {
        switch sportID {
        case 0: return .run
        case 16: return .swim
        case 44: return .yoga
        case 45: return .pilates
        case 50: return .hiit
        case 52: return .strengthBarbell
        case 53, 54: return .strengthDumbbells
        case 55: return .strengthBodyweight
        case 56: return .rowing
        case 57: return .boxing
        case 70: return .tennis
        case 71: return .basketball
        case 72: return .soccer
        case 73: return .martialArts
        case 74: return .climbing
        case 92: return .hike
        case 93: return .walk
        case 131: return .crossfit
        default: return .other
        }
    }
}

// Features/Workout/Data/Mappers/WhoopCyclingWorkoutMapper.swift
import Foundation

enum WhoopCyclingWorkoutMapper {
    /// Sport IDs for the cycling family (road, MTB, indoor, track, virtual).
    static let cyclingSportIDs: Set<Int> = [1, 63, 64, 65, 126]

    static func isCycling(_ dto: WhoopWorkoutDTO) -> Bool {
        cyclingSportIDs.contains(dto.sport_id)
    }

    static func payload(from dto: WhoopWorkoutDTO) -> ExternalWorkoutPayload? {
        guard isCycling(dto) else { return nil }

        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let start = fmt.date(from: dto.start) ?? ISO8601DateFormatter().date(from: dto.start) else {
            return nil
        }

        let end = dto.end.flatMap { fmt.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
        let duration = end.map { Int($0.timeIntervalSince(start)) } ?? 0
        guard duration >= minimumValidWorkoutSeconds else { return nil }

        let score = dto.score
        let avgHR = Double(score?.average_heart_rate ?? 0)
        let maxHR = score?.max_heart_rate ?? 0
        let distance = score?.distance_meter ?? 0
        let elevation = score?.altitude_gain_meter ?? 0
        let tss = estimateTSS(durationSeconds: duration, score: score)

        return ExternalWorkoutPayload(
            source: .whoop,
            externalID: dto.id,
            title: dto.sport_name.nilIfEmpty,
            format: .whoop,
            startDate: start,
            durationSeconds: duration,
            distanceMeters: distance,
            elevationGainMeters: elevation,
            avgPower: 0,
            maxPower: 0,
            avgHR: avgHR,
            maxHR: maxHR,
            avgCadence: 0,
            normalizedPower: 0,
            intensityFactor: 0,
            tss: tss,
            samples: []
        )
    }

    private static func estimateTSS(durationSeconds: Int, score: WhoopWorkoutDTO.Score?) -> Double {
        let hours = Double(durationSeconds) / 3600
        guard hours > 0 else { return 0 }

        if let avg = score?.average_heart_rate, avg > 0 {
            let profile = LoggedActivityTSSEstimator.Profile.current()
            if let maxHR = profile.maxHR, maxHR > 0 {
                var metrics = LoggedActivityMetrics()
                metrics.avgHeartRate = avg
                metrics.maxHeartRate = score?.max_heart_rate
                metrics.strain = score?.strain
                let synthetic = LoggedActivity(
                    id: UUID(),
                    source: .whoop,
                    externalID: nil,
                    type: .other,
                    customLabel: nil,
                    startDate: .distantPast,
                    durationSeconds: durationSeconds,
                    intensity: nil,
                    rpe: nil,
                    notes: "",
                    metrics: metrics,
                    createdAt: .distantPast,
                    updatedAt: .distantPast
                )
                return LoggedActivityTSSEstimator.estimate(synthetic, profile: profile)
            }
        }

        if let strain = score?.strain, strain > 0 {
            return strain * 7
        }

        return hours * 0.65 * 0.65 * 100
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

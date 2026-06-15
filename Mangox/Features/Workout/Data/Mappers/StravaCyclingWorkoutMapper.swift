// Features/Workout/Data/Mappers/StravaCyclingWorkoutMapper.swift
import Foundation

enum StravaCyclingWorkoutMapper {
    static func payload(
        from activity: StravaService.SummaryActivity,
        streams: StravaService.ActivityStreams?
    ) -> ExternalWorkoutPayload? {
        guard StravaActivityMapper.isCycling(activity) else { return nil }
        guard let start = activity.startDate else { return nil }

        let duration = activity.movingTime ?? activity.elapsedTime ?? 0
        guard duration >= minimumValidWorkoutSeconds else { return nil }

        let samples = buildSamples(startDate: start, streams: streams)
        let powerSamples = samples.map(\.power).filter { $0 > 0 }
        let ftp = Double(PowerZone.ftp)

        let metrics: (np: Double, intensityFactor: Double, tss: Double, avgPower: Double, maxPower: Int)
        if !powerSamples.isEmpty {
            let aggregated = WorkoutMetricsAggregator.normalizedPowerIntensityAndTSS(
                powerSamples: powerSamples,
                durationSeconds: duration,
                ftp: ftp
            )
            let avg = Double(powerSamples.reduce(0, +)) / Double(powerSamples.count)
            metrics = (
                aggregated.np,
                aggregated.intensityFactor,
                aggregated.tss,
                avg,
                powerSamples.max() ?? 0
            )
        } else if let avgWatts = activity.averageWatts, avgWatts > 0, ftp > 0 {
            let ifac = avgWatts / ftp
            let tss = (Double(duration) * avgWatts * ifac) / (ftp * 3600) * 100
            metrics = (avgWatts, ifac, tss, avgWatts, Int(avgWatts.rounded()))
        } else if let kj = activity.kilojoules, kj > 0, duration > 0 {
            let avgWatts = (kj * 1000) / Double(duration)
            let ifac = ftp > 0 ? avgWatts / ftp : 0
            let tss = ftp > 0 ? (Double(duration) * avgWatts * ifac) / (ftp * 3600) * 100 : 0
            metrics = (avgWatts, ifac, tss, avgWatts, Int(avgWatts.rounded()))
        } else {
            metrics = (0, 0, 0, 0, 0)
        }

        let avgHR = activity.averageHeartrate ?? 0
        let maxHR = Int(activity.maxHeartrate ?? 0)
        let avgCadence = activity.averageCadence ?? averageCadence(from: samples)

        return ExternalWorkoutPayload(
            source: .strava,
            externalID: "\(activity.id)",
            title: activity.name,
            format: .strava,
            startDate: start,
            durationSeconds: duration,
            distanceMeters: activity.distance ?? 0,
            elevationGainMeters: activity.totalElevationGain ?? 0,
            avgPower: metrics.avgPower,
            maxPower: metrics.maxPower,
            avgHR: avgHR,
            maxHR: maxHR,
            avgCadence: avgCadence,
            normalizedPower: metrics.np,
            intensityFactor: metrics.intensityFactor,
            tss: metrics.tss,
            samples: samples
        )
    }

    private static func buildSamples(
        startDate: Date,
        streams: StravaService.ActivityStreams?
    ) -> [ImportedWorkoutSamplePayload] {
        guard let streams, !streams.time.isEmpty else { return [] }

        let count = streams.time.count
        var samples: [ImportedWorkoutSamplePayload] = []
        samples.reserveCapacity(count)

        for index in 0..<count {
            let elapsed = streams.time[index]
            let power = index < streams.watts.count ? streams.watts[index] : 0
            let hr = index < streams.heartrate.count ? streams.heartrate[index] : 0
            let cadence = index < streams.cadence.count ? Double(streams.cadence[index]) : 0
            let speedMps = index < streams.velocitySmooth.count ? streams.velocitySmooth[index] : 0
            let speedKmh = speedMps * 3.6

            samples.append(
                ImportedWorkoutSamplePayload(
                    timestamp: startDate.addingTimeInterval(TimeInterval(elapsed)),
                    elapsedSeconds: elapsed,
                    power: power,
                    cadence: cadence,
                    speed: speedKmh,
                    heartRate: hr
                )
            )
        }
        return samples
    }

    private static func averageCadence(from samples: [ImportedWorkoutSamplePayload]) -> Double {
        let values = samples.map(\.cadence).filter { $0 > 0 }
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}

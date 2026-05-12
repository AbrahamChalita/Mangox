// Features/ActivityLog/Data/Mappers/StravaActivityMapper.swift
import Foundation

enum StravaActivityMapper {
    private static let cyclingSportTypes: Set<String> = [
        "Ride", "VirtualRide", "EBikeRide", "MountainBikeRide",
        "GravelRide", "Handcycle", "Velomobile",
    ]

    static func isCycling(_ activity: StravaService.SummaryActivity) -> Bool {
        cyclingSportTypes.contains(activity.sportType ?? "")
    }

    static func draft(
        from activity: StravaService.SummaryActivity,
        streams: StravaService.ActivityStreams? = nil
    ) -> LoggedActivityDraft? {
        guard let start = activity.startDate else { return nil }
        let sportType = activity.sportType ?? ""
        guard !isCycling(activity) else { return nil }

        let duration = activity.movingTime ?? activity.elapsedTime ?? 0
        guard duration > 0 else { return nil }

        let type = activityType(for: sportType)
        let customLabel: String? = type == .other ? (activity.name ?? sportType) : nil

        var metrics = LoggedActivityMetrics()
        if let d = activity.distance, d > 0 { metrics.distanceMeters = d }
        if let e = activity.totalElevationGain, e > 0 { metrics.elevationGainMeters = e }
        if let hr = activity.averageHeartrate { metrics.avgHeartRate = Int(hr) }
        if let mhr = activity.maxHeartrate { metrics.maxHeartRate = Int(mhr) }
        if let cal = activity.calories { metrics.calories = Int(cal) }
        if let kj = activity.kilojoules { metrics.kilojoules = kj }
        metrics.avgSpeedMetersPerSecond = activity.averageSpeed
        metrics.maxSpeedMetersPerSecond = activity.maxSpeed
        metrics.relativeEffort = activity.sufferScore
        metrics.achievementCount = activity.achievementCount
        metrics.prCount = activity.prCount
        metrics.mapSummaryPolyline = activity.map?.summaryPolyline

        // New rich fields off the summary
        if let cad = activity.averageCadence, cad > 0 { metrics.avgCadence = cad }
        if let watts = activity.averageWatts, watts > 0 { metrics.avgPowerWatts = watts }
        if let temp = activity.averageTemp { metrics.avgTempCelsius = temp }

        // Streams-derived enrichments (best-effort)
        if let streams {
            if type.isCardioDistance, let bestKm = bestKmSplitSeconds(streams: streams) {
                metrics.bestKmSplitSeconds = bestKm
            }
            // Prefer the user's configured max HR (manual override or HealthKit-derived) over the
            // single activity max — gives consistent zones across activities and accuracy when the
            // activity peak under-represents the user's actual ceiling.
            let cap = Double(HeartRateZone.maxHR)
            if let zones = heartRateZoneMillis(streams: streams, maxHR: cap) {
                metrics.heartRateZoneMillis = zones
            }
        }

        return LoggedActivityDraft(
            id: UUID(),
            source: .strava,
            externalID: "\(activity.id)",
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

    /// Sliding-window scan for the fastest 1km segment in a `time`/`distance` stream pair.
    /// Returns seconds for the best km, or nil if streams don't cover 1km.
    static func bestKmSplitSeconds(streams: StravaService.ActivityStreams) -> Int? {
        let dist = streams.distance
        let time = streams.time
        guard dist.count == time.count, dist.count > 1 else { return nil }
        guard let totalDist = dist.last, totalDist >= 1000 else { return nil }

        var best = Int.max
        var lo = 0
        for hi in 1..<dist.count {
            while lo < hi && dist[hi] - dist[lo] >= 1000 {
                let elapsed = time[hi] - time[lo]
                if elapsed > 0, elapsed < best { best = elapsed }
                lo += 1
            }
        }
        return best == Int.max ? nil : best
    }

    /// Distributes time spent in each HR zone (5 zones) using % of the supplied max-HR cap.
    /// Returns 6-element array (zone 0 = below z1, zones 1...5) for compatibility with existing renderer.
    static func heartRateZoneMillis(
        streams: StravaService.ActivityStreams,
        maxHR: Double?
    ) -> [Int]? {
        let hr = streams.heartrate
        guard hr.count > 1 else { return nil }
        let cap = (maxHR ?? Double(hr.max() ?? 200)).rounded()
        guard cap > 0 else { return nil }

        // Zone breakpoints as % of max HR: <60, 60-70, 70-80, 80-90, 90-100, >100
        let breakpoints: [Double] = [0.60, 0.70, 0.80, 0.90, 1.00].map { $0 * cap }
        var zones = [Int](repeating: 0, count: 6)

        // Each sample is ~1s of activity (Strava streams are 1Hz). Use time-stream deltas if available.
        let times = streams.time
        for i in 0..<hr.count {
            let bpm = Double(hr[i])
            var zone = 0
            for (z, threshold) in breakpoints.enumerated() {
                if bpm >= threshold { zone = z + 1 }
            }
            let dt: Int
            if i + 1 < times.count {
                dt = max(0, times[i + 1] - times[i])
            } else if i > 0 && times.count == hr.count {
                dt = max(0, times[i] - times[i - 1])
            } else {
                dt = 1
            }
            zones[zone] += dt * 1000
        }
        return zones.reduce(0, +) > 0 ? zones : nil
    }

    private static func activityType(for sportType: String) -> LoggedActivityType {
        switch sportType {
        case "Run": return .run
        case "Walk": return .walk
        case "Hike": return .hike
        case "Swim": return .swim
        case "Rowing", "Canoeing", "Kayaking", "StandUpPaddling": return .rowing
        case "WeightTraining": return .strengthDumbbells
        case "Crossfit": return .crossfit
        case "Workout", "HIIT": return .hiit
        case "Yoga": return .yoga
        case "Pilates": return .pilates
        case "Boxing", "MartialArts": return .boxing
        case "Soccer": return .soccer
        case "Tennis": return .tennis
        case "Basketball", "Basketball ": return .basketball
        case "Climbing", "RockClimbing": return .climbing
        default: return .other
        }
    }
}

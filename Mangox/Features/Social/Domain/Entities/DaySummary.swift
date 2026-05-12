// Features/Social/Domain/Entities/DaySummary.swift
import Foundation

struct DaySummary: Sendable, Hashable {
    let date: Date
    let cyclingWorkouts: [Workout]
    let loggedActivities: [LoggedActivity]

    // Duration-weighted roll-ups
    let totalDurationSeconds: Int
    let totalDistanceMeters: Double
    let totalElevationGainMeters: Double
    let totalKilojoules: Double
    let totalTSS: Double?
    let combinedAvgHeartRate: Int?

    var activityCount: Int { cyclingWorkouts.count + loggedActivities.count }
    var isEmpty: Bool { activityCount == 0 }

    init(date: Date, cyclingWorkouts: [Workout], loggedActivities: [LoggedActivity]) {
        self.date = date
        self.cyclingWorkouts = cyclingWorkouts
        self.loggedActivities = loggedActivities

        var duration = cyclingWorkouts.reduce(0) { $0 + Int($1.duration) }
        duration += loggedActivities.reduce(0) { $0 + $1.durationSeconds }
        totalDurationSeconds = duration

        var distance = cyclingWorkouts.reduce(0.0) { $0 + $1.distance }
        distance += loggedActivities.compactMap(\.metrics.distanceMeters).reduce(0, +)
        totalDistanceMeters = distance

        var elevation = cyclingWorkouts.reduce(0.0) { $0 + $1.elevationGain }
        elevation += loggedActivities.compactMap(\.metrics.elevationGainMeters).reduce(0, +)
        totalElevationGainMeters = elevation

        var kj = cyclingWorkouts.reduce(0.0) { acc, w in
            let power = w.avgPower > 0 ? w.avgPower : 0
            return acc + (power * w.duration / 1000)
        }
        kj += loggedActivities.compactMap(\.metrics.kilojoules).reduce(0, +)
        totalKilojoules = kj

        let workoutTSS = cyclingWorkouts.filter { $0.tss > 0 }.map { $0.tss }.reduce(0, +)
        let profile = LoggedActivityTSSEstimator.Profile.current()
        let activityTSS = loggedActivities
            .map { LoggedActivityTSSEstimator.estimate($0, profile: profile) }
            .reduce(0, +)
        let combinedTSS = workoutTSS + activityTSS
        totalTSS = combinedTSS > 0 ? combinedTSS : nil

        // Duration-weighted avg HR across all activities that have HR
        var weightedHR = 0.0
        var totalHRDuration = 0
        for w in cyclingWorkouts where w.avgHR > 0 {
            let dur = Int(w.duration)
            weightedHR += w.avgHR * Double(dur)
            totalHRDuration += dur
        }
        for a in loggedActivities {
            if let hr = a.metrics.avgHeartRate, hr > 0 {
                weightedHR += Double(hr) * Double(a.durationSeconds)
                totalHRDuration += a.durationSeconds
            }
        }
        combinedAvgHeartRate = totalHRDuration > 0 ? Int(weightedHR / Double(totalHRDuration)) : nil
    }

    var totalDurationFormatted: String {
        let h = totalDurationSeconds / 3600
        let m = (totalDurationSeconds % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    var totalDistanceFormatted: String {
        totalDistanceMeters >= 1000
            ? String(format: "%.1f km", totalDistanceMeters / 1000)
            : String(format: "%.0f m", totalDistanceMeters)
    }
}

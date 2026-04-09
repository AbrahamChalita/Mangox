import SwiftUI

/// Celebration card shown on the summary screen when new personal records are achieved.
/// Displays confetti animation and highlights the new PRs.
struct PRCelebrationView: View {
    let newPRs: [PRBadge]

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColor.yellow)
                Text("PERSONAL RECORDS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppColor.yellow)
                    .tracking(1.5)
                Spacer()
            }

            ForEach(newPRs) { pr in
                HStack(spacing: 10) {
                    Image(systemName: pr.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(pr.color)
                        .frame(width: 28, height: 28)
                        .background(pr.color.opacity(0.1))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 1) {
                        Text(pr.label)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                        Text(pr.detail)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.35))
                    }

                    Spacer()

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(pr.value)
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundStyle(pr.color)
                        Text(pr.unit)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.25))
                    }
                }
                .padding(.vertical, 4)

                if pr.id != newPRs.last?.id {
                    Divider().background(Color.white.opacity(0.06))
                }
            }
        }
        .padding(14)
        .background(AppColor.yellow.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(AppColor.yellow.opacity(0.2), lineWidth: 1)
        )
        .scaleEffect(appeared ? 1 : 0.9)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                appeared = true
            }
        }
    }
}

// MARK: - PR Badge

struct PRBadge: Identifiable {
    let id: String
    let label: String
    let detail: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
}

// MARK: - PR Detector

/// Checks workout data against stored personal records and returns new PRs.
enum PRDetector {

    /// Compute new PRs for a given workout against all-time bests.
    static func detectNewPRs(
        for workout: Workout,
        allWorkouts: [Workout]
    ) -> [PRBadge] {
        var badges: [PRBadge] = []

        let duration = Int(workout.duration)
        let maxPower = workout.maxPower
        let avgPower = workout.avgPower
        let np = workout.normalizedPower
        let distance = workout.distance
        let tss = workout.tss

        // Best avg power
        let bestAvgPower = allWorkouts.filter { $0.id != workout.id && $0.avgPower > 0 }
            .map(\.avgPower).max() ?? 0
        if avgPower > bestAvgPower, avgPower > 0 {
            badges.append(PRBadge(
                id: "best_avg_power",
                label: "Best Average Power",
                detail: "Previous best: \(Int(bestAvgPower))W",
                value: "\(Int(avgPower))",
                unit: "W",
                icon: "bolt.fill",
                color: AppColor.orange
            ))
        }

        // Best NP
        let bestNP = allWorkouts.filter { $0.id != workout.id && $0.normalizedPower > 0 }
            .map(\.normalizedPower).max() ?? 0
        if np > bestNP, np > 0 {
            badges.append(PRBadge(
                id: "best_np",
                label: "Best Normalized Power",
                detail: "Previous best: \(Int(bestNP))W",
                value: "\(Int(np))",
                unit: "W",
                icon: "waveform.path.ecg",
                color: AppColor.yellow
            ))
        }

        // Best max power
        let bestMax = allWorkouts.filter { $0.id != workout.id }
            .map(\.maxPower).max() ?? 0
        if maxPower > bestMax, maxPower > 0 {
            badges.append(PRBadge(
                id: "best_max_power",
                label: "Peak Power",
                detail: "Previous best: \(bestMax)W",
                value: "\(maxPower)",
                unit: "W",
                icon: "arrow.up.circle.fill",
                color: AppColor.red
            ))
        }

        // Longest distance
        let bestDistance = allWorkouts.filter { $0.id != workout.id }
            .map(\.distance).max() ?? 0
        if distance > bestDistance, distance > 0 {
            badges.append(PRBadge(
                id: "longest_distance",
                label: "Longest Distance",
                detail: String(format: "Previous best: %.1f km", bestDistance / 1000),
                value: String(format: "%.1f", distance / 1000),
                unit: "km",
                icon: "road.lanes",
                color: AppColor.blue
            ))
        }

        // Longest duration
        let bestDuration = allWorkouts.filter { $0.id != workout.id }
            .map(\.duration).max() ?? 0
        if duration > Int(bestDuration), duration > 0 {
            badges.append(PRBadge(
                id: "longest_duration",
                label: "Longest Ride",
                detail: "Previous best: \(AppFormat.duration(bestDuration))",
                value: AppFormat.duration(Double(duration)),
                unit: "",
                icon: "timer",
                color: AppColor.success
            ))
        }

        // Highest TSS
        let bestTSS = allWorkouts.filter { $0.id != workout.id }
            .map(\.tss).max() ?? 0
        if tss > bestTSS, tss > 0 {
            badges.append(PRBadge(
                id: "highest_tss",
                label: "Highest TSS",
                detail: String(format: "Previous best: %.0f TSS", bestTSS),
                value: String(format: "%.0f", tss),
                unit: "TSS",
                icon: "flame.fill",
                color: AppColor.mango
            ))
        }

        return badges
    }
}

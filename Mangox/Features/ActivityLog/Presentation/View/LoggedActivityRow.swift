// Features/ActivityLog/Presentation/View/LoggedActivityRow.swift
import SwiftUI

struct LoggedActivityRow: View {
    let activity: LoggedActivity

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LoggedActivityIcon.color(for: activity.type).opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: LoggedActivityIcon.symbol(for: activity.type))
                    .foregroundStyle(LoggedActivityIcon.color(for: activity.type))
                    .font(.system(size: 18, weight: .medium))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(activity.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColor.fg0)

                    let badge = LoggedActivityIcon.sourceBadge(for: activity.source)
                    Text(badge.text)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(badge.color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(badge.color.opacity(0.12))
                        .clipShape(Capsule())
                }

                HStack(spacing: 10) {
                    Text(activity.startDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 13))
                        .foregroundStyle(AppColor.fg3)

                    Text("·")
                        .foregroundStyle(AppColor.fg4)

                    Text(activity.durationFormatted)
                        .font(.system(size: 13))
                        .foregroundStyle(AppColor.fg2)

                    if let primary = primaryMetric {
                        Text("·")
                            .foregroundStyle(AppColor.fg4)
                        Text(primary)
                            .font(.system(size: 13))
                            .foregroundStyle(AppColor.fg2)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColor.fg4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppColor.bg1)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(AppColor.hair, lineWidth: 1)
        )
    }

    private var primaryMetric: String? {
        let m = activity.metrics
        if let d = m.distanceMeters, d > 0 {
            return d >= 1000
                ? String(format: "%.1f km", d / 1000)
                : String(format: "%.0f m", d)
        }
        if let s = m.sets, s > 0, let r = m.reps, r > 0 {
            return "\(s)×\(r)"
        }
        if let hr = m.avgHeartRate, hr > 0 {
            return "\(hr) bpm"
        }
        if let rpe = activity.rpe {
            return "RPE \(rpe)"
        }
        return nil
    }
}

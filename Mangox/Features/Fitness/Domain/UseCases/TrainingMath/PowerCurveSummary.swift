// Features/Fitness/Domain/UseCases/TrainingMath/PowerCurveSummary.swift
import Foundation

/// Human-readable power curve summaries for coach tools and encrypted cloud context.
nonisolated enum PowerCurveSummary {

    nonisolated static let defaultRangeDays = 90

    /// Formats standard-duration bests with optional FTP-relative labels.
    nonisolated static func format(
        points: [PowerCurveAnalytics.Point],
        ftp: Int,
        rangeDays: Int = defaultRangeDays
    ) -> String {
        guard !points.isEmpty else {
            return "No power curve data in the last \(rangeDays) days."
        }

        var lines: [String] = ["Power curve (last \(rangeDays)d, best rolling averages):"]
        for duration in PowerCurveAnalytics.standardDurations {
            guard let point = points.first(where: { $0.durationSeconds == duration }) else { continue }
            var line = "\(label(for: duration)): \(point.watts)W"
            if ftp > 0 {
                let ratio = Double(point.watts) / Double(ftp)
                line += String(format: " (%.2f× FTP)", ratio)
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    nonisolated static func label(for durationSeconds: Int) -> String {
        switch durationSeconds {
        case ..<60: return "\(durationSeconds)s"
        case 60..<3600:
            let minutes = durationSeconds / 60
            return minutes == 1 ? "1m" : "\(minutes)m"
        default:
            return durationSeconds == 3600 ? "1h" : "\(durationSeconds / 3600)h"
        }
    }
}

import SwiftData
import SwiftUI

/// Log of FTP + HR settings over time (manual saves from Settings / applied FTP tests).
struct FitnessThresholdTimelineView: View {
    @Query(sort: \FitnessSettingsSnapshot.recordedAt, order: .reverse)
    private var snapshots: [FitnessSettingsSnapshot]

    var body: some View {
        SettingsSubviewShell(title: "Threshold log") {
            if snapshots.isEmpty {
                settingsSubCard {
                    Text("No entries yet")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                    Text("When you apply FTP in Power & Zones, save heart-rate overrides, or apply an FTP test result, a snapshot is stored here.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.32))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ForEach(snapshots, id: \.id) { s in
                    settingsSubCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(s.recordedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.55))
                                Spacer()
                                Text(sourceLabel(s.sourceRaw))
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(AppColor.mango.opacity(0.85))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(AppColor.mango.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            HStack(spacing: 16) {
                                metric("FTP", "\(s.ftpWatts)", "W")
                                metric("Max HR", "\(s.maxHR)", "bpm")
                                metric("Resting", "\(s.restingHR)", "bpm")
                            }
                        }
                    }
                }
            }
        }
    }

    private func metric(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.25))
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.88))
                Text(unit)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
    }

    private func sourceLabel(_ raw: String) -> String {
        switch raw {
        case "ftp_settings": return "FTP settings"
        case "hr_settings": return "Heart rate"
        case "ftp_test_applied": return "FTP test"
        default: return raw.replacingOccurrences(of: "_", with: " ")
        }
    }
}

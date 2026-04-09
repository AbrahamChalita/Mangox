import SwiftData
import SwiftUI

/// Power zone time shares for the ride insight footer (same order as ``PowerZone.zones``).
struct RideInsightZoneSegment: Identifiable {
    let zone: PowerZone
    let seconds: Int
    let percent: Double
    var id: Int { zone.id }
}

// MARK: - Power zones footer (Mangox card / zone-row language)

private struct InsightPowerZonesFooter: View {
    let segments: [RideInsightZoneSegment]
    /// Dimmed while the AI insight is still generating.
    var subdued: Bool = false

    @Environment(\.isWideSummary) private var isWide

    private var nonzero: [RideInsightZoneSegment] {
        segments.filter { $0.percent > 0.001 }
    }

    private var total: Double {
        max(nonzero.reduce(0) { $0 + $1.percent }, 0.000_001)
    }

    private var barHeight: CGFloat { isWide ? 12 : 10 }

    var body: some View {
        VStack(alignment: .leading, spacing: isWide ? 12 : 10) {
            Rectangle()
                .fill(Color.white.opacity(AppOpacity.divider))
                .frame(height: 1)

            HStack(spacing: isWide ? 8 : 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: isWide ? 12 : 10))
                    .foregroundStyle(.white.opacity(0.3))
                Text("POWER ZONES")
                    .font(.system(size: isWide ? 11 : 10, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.35))
                    .tracking(1.5)
            }

            GeometryReader { geo in
                let innerW = geo.size.width
                let spacing: CGFloat = 1
                let n = nonzero.count
                let totalSpacing = spacing * CGFloat(max(0, n - 1))
                let usable = max(innerW - totalSpacing, 0)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.04))
                    if !nonzero.isEmpty {
                        HStack(spacing: spacing) {
                            ForEach(nonzero) { seg in
                                let w = max(2, usable * CGFloat(seg.percent / total))
                                Rectangle()
                                    .fill(seg.zone.color.opacity(subdued ? 0.55 : 1))
                                    .frame(width: w, height: barHeight)
                            }
                        }
                        .clipShape(Capsule())
                    }
                }
                .frame(height: barHeight)
            }
            .frame(height: barHeight)

            HStack(spacing: 0) {
                ForEach(segments) { seg in
                    VStack(spacing: 3) {
                        Text("Z\(seg.zone.id)")
                            .font(.system(size: isWide ? 10 : 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(seg.zone.color.opacity(subdued ? 0.45 : 1))
                        Text("\(Int((seg.percent * 100).rounded()))%")
                            .font(.system(size: isWide ? 10 : 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(AppOpacity.textTertiary))
                        Text(AppFormat.seconds(seg.seconds))
                            .font(.system(size: isWide ? 9 : 8, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.22))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .opacity(subdued ? 0.65 : 1)
    }
}

/// On-device Apple Intelligence takeaway for the ride summary (Foundation Models).
struct SummaryOnDeviceInsightCard: View {
    let workout: Workout
    let zoneSegments: [RideInsightZoneSegment]
    let powerZoneLine: String
    let planLine: String?
    let ftpWatts: Int
    /// First name when known (e.g. Strava); insights avoid naming the app as the rider.
    var riderCallName: String? = nil
    /// When `true`, the standalone summary power-zones card should appear (insight unavailable).
    @Binding var onDeviceInsightFailed: Bool

    @Environment(\.modelContext) private var modelContext

    @State private var insight: WorkoutSummaryOnDeviceInsight?
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let insight {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "apple.intelligence")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColor.mango)
                        Text("RIDE INSIGHT")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.35))
                            .tracking(1.0)
                        Spacer(minLength: 0)
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.35))
                    }

                    Text(insight.displayHeadline)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(AppOpacity.textPrimary))
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(insight.displayBullets.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                    .foregroundStyle(.white.opacity(0.45))
                                Text(line)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.78))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    if let narrative = insight.displayNarrative {
                        Text(narrative)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }

                    if let caveat = insight.displayCaveat {
                        Text(caveat)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.45))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("Private on this device — not sent to the cloud coach.")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.32))

                    InsightPowerZonesFooter(segments: zoneSegments, subdued: false)
                }
                .padding(14)
                .cardStyle(cornerRadius: 16)
            } else if loadFailed {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(AppColor.mango)
                        Text("Generating on-device insight…")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.45))
                        Spacer(minLength: 0)
                    }

                    InsightPowerZonesFooter(segments: zoneSegments, subdued: true)
                }
                .padding(14)
                .cardStyle(cornerRadius: 16)
            }
        }
        .task(id: workout.id) { @MainActor in
            onDeviceInsightFailed = false
            loadFailed = false

            // Smart title runs in parallel — it writes directly to workout.smartTitle via SwiftData.
            async let titleTask: Void = WorkoutSummaryOnDeviceInsight.generateSmartTitleIfNeeded(
                workout: workout,
                powerZoneLine: powerZoneLine,
                ftpWatts: ftpWatts,
                modelContext: modelContext
            )

            if let hit = WorkoutSummaryOnDeviceInsight.loadCached(
                workout: workout,
                powerZoneLine: powerZoneLine,
                planLine: planLine,
                ftpWatts: ftpWatts,
                riderCallName: riderCallName
            ) {
                insight = hit
                _ = await titleTask
                return
            }
            insight = nil
            async let insightTask = WorkoutSummaryOnDeviceInsight.generate(
                workout: workout,
                powerZoneLine: powerZoneLine,
                planLine: planLine,
                ftpWatts: ftpWatts,
                riderCallName: riderCallName
            )
            let (result, _) = await (insightTask, titleTask)
            if let result {
                insight = result
            } else {
                loadFailed = true
                onDeviceInsightFailed = true
            }
        }
    }
}

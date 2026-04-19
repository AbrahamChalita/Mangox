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

private struct InsightPowerZonesCompactStrip: View {
    let segments: [RideInsightZoneSegment]
    var subdued: Bool = false

    @Environment(\.isWideSummary) private var isWide

    private var nonzero: [RideInsightZoneSegment] {
        segments.filter { $0.percent > 0.001 }
    }

    private var total: Double {
        max(nonzero.reduce(0) { $0 + $1.percent }, 0.000_001)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isWide ? 8 : 7) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: isWide ? 11 : 10))
                    .foregroundStyle(.white.opacity(0.35))
                Text("ZONE MIX")
                    .font(.system(size: isWide ? 10 : 9, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(1.1)
            }

            GeometryReader { geo in
                let spacing: CGFloat = 1
                let count = nonzero.count
                let totalSpacing = spacing * CGFloat(max(0, count - 1))
                let usable = max(geo.size.width - totalSpacing, 0)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.05))
                    if !nonzero.isEmpty {
                        HStack(spacing: spacing) {
                            ForEach(nonzero) { seg in
                                let width = max(2, usable * CGFloat(seg.percent / total))
                                Rectangle()
                                    .fill(seg.zone.color.opacity(subdued ? 0.5 : 0.95))
                                    .frame(width: width, height: 8)
                            }
                        }
                        .clipShape(Capsule())
                    }
                }
                .frame(height: 8)
            }
            .frame(height: 8)

            HStack(spacing: isWide ? 8 : 6) {
                ForEach(segments) { seg in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(seg.zone.color.opacity(subdued ? 0.5 : 1))
                            .frame(width: 6, height: 6)
                        Text("Z\(seg.zone.id)")
                            .font(.system(size: isWide ? 10 : 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.72))
                        Text("\(Int((seg.percent * 100).rounded()))%")
                            .font(.system(size: isWide ? 9 : 8, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.42))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .opacity(subdued ? 0.65 : 1)
    }
}

/// On-device Apple Intelligence takeaway for the ride summary (Foundation Models).
enum SummaryInsightCardDisplayMode {
    case regular
    case compact
}

struct SummaryOnDeviceInsightCard: View {
    let workout: Workout
    let zoneSegments: [RideInsightZoneSegment]
    let powerZoneLine: String
    let planLine: String?
    let ftpWatts: Int
    /// First name when known (e.g. Strava); insights avoid naming the app as the rider.
    var riderCallName: String? = nil
    var displayMode: SummaryInsightCardDisplayMode = .regular
    /// When `true`, the standalone summary power-zones card should appear (insight unavailable).
    @Binding var onDeviceInsightFailed: Bool

    @State private var insight: WorkoutSummaryOnDeviceInsight?
    /// True when ``insight`` was built from ``OnDeviceModelFallbackCopy`` (no on-device language model or model returned nothing).
    @State private var insightIsStatsFallback = false
    private var isCompact: Bool { displayMode == .compact }

    var body: some View {
        Group {
            if let insight {
                VStack(alignment: .leading, spacing: isCompact ? 10 : 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "apple.intelligence")
                            .font(.system(size: isCompact ? 13 : 14, weight: .semibold))
                            .foregroundStyle(AppColor.mango)
                        Text(isCompact ? "COACHING" : "RIDE INSIGHT")
                            .font(.system(size: isCompact ? 11 : 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.35))
                            .tracking(1.0)
                        Spacer(minLength: 0)
                        if !isCompact {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }

                    Text(insight.displayHeadline)
                        .font(.system(size: isCompact ? 15 : 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(AppOpacity.textPrimary))
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: isCompact ? 5 : 6) {
                        ForEach(
                            Array(
                                insight.displayBullets.prefix(isCompact ? 2 : insight.displayBullets.count)
                                    .enumerated()),
                            id: \.offset
                        ) { _, line in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                    .foregroundStyle(.white.opacity(0.45))
                                Text(line)
                                    .font(.system(size: isCompact ? 12 : 13))
                                    .foregroundStyle(.white.opacity(0.78))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    if !isCompact, let narrative = insight.displayNarrative {
                        Text(narrative)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }

                    if !isCompact, let caveat = insight.displayCaveat {
                        Text(caveat)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.45))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if insightIsStatsFallback {
                        Text(
                            "Stats-based summary. Apple Intelligence is not available on this device."
                        )
                        .font(.system(size: isCompact ? 11 : 10))
                            .foregroundStyle(.white.opacity(0.38))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if isCompact {
                        InsightPowerZonesCompactStrip(segments: zoneSegments, subdued: false)
                    }

                    if !isCompact {
                        Text("Private on this device — not sent to the cloud coach.")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.32))
                    }

                    if !isCompact {
                        InsightPowerZonesFooter(segments: zoneSegments, subdued: false)
                    }
                }
                .padding(isCompact ? 12 : 14)
                .cardStyle(cornerRadius: 16)
            } else {
                VStack(alignment: .leading, spacing: isCompact ? 8 : 12) {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(AppColor.mango)
                        Text(isCompact ? "Generating coaching insight…" : "Generating on-device insight…")
                            .font(.system(size: isCompact ? 12 : 13))
                            .foregroundStyle(.white.opacity(0.45))
                        Spacer(minLength: 0)
                    }

                    if isCompact {
                        InsightPowerZonesCompactStrip(segments: zoneSegments, subdued: true)
                    }

                    if !isCompact {
                        InsightPowerZonesFooter(segments: zoneSegments, subdued: true)
                    }
                }
                .padding(isCompact ? 12 : 14)
                .cardStyle(cornerRadius: 16)
            }
        }
        .task(id: workout.id) { @MainActor in
            onDeviceInsightFailed = false
            insightIsStatsFallback = false

            if let hit = WorkoutSummaryOnDeviceInsight.loadCached(
                workout: workout,
                powerZoneLine: powerZoneLine,
                planLine: planLine,
                ftpWatts: ftpWatts,
                riderCallName: riderCallName
            ) {
                insight = hit
                await WorkoutSummaryOnDeviceInsight.generateSmartTitleIfNeeded(
                    workout: workout,
                    powerZoneLine: powerZoneLine,
                    ftpWatts: ftpWatts
                )
                return
            }

            if !OnDeviceCoachEngine.isOnDeviceWritingModelAvailable {
                insight = OnDeviceModelFallbackCopy.rideSummaryInsight(
                    workout: workout,
                    powerZoneLine: powerZoneLine,
                    planLine: planLine,
                    ftpWatts: ftpWatts,
                    riderCallName: riderCallName
                )
                insightIsStatsFallback = true
                await WorkoutSummaryOnDeviceInsight.generateSmartTitleIfNeeded(
                    workout: workout,
                    powerZoneLine: powerZoneLine,
                    ftpWatts: ftpWatts
                )
                return
            }

            insight = nil
            let result = await WorkoutSummaryOnDeviceInsight.generate(
                workout: workout,
                powerZoneLine: powerZoneLine,
                planLine: planLine,
                ftpWatts: ftpWatts,
                riderCallName: riderCallName
            )
            await WorkoutSummaryOnDeviceInsight.generateSmartTitleIfNeeded(
                workout: workout,
                powerZoneLine: powerZoneLine,
                ftpWatts: ftpWatts
            )
            if let result {
                insight = result
                insightIsStatsFallback = false
            } else {
                insight = OnDeviceModelFallbackCopy.rideSummaryInsight(
                    workout: workout,
                    powerZoneLine: powerZoneLine,
                    planLine: planLine,
                    ftpWatts: ftpWatts,
                    riderCallName: riderCallName
                )
                insightIsStatsFallback = true
            }
        }
    }
}

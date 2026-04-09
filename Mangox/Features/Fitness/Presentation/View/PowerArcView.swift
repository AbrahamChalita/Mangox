import SwiftUI

struct PowerArcView: View {
    let watts: Int
    var maxWatts: Int = 500
    var compact: Bool = false
    /// When false, only the arc track is shown (e.g. beside a separate hero watt readout).
    var showCenterText: Bool = true
    /// Extra-small arc for dense phone layouts (e.g. portrait free ride).
    var micro: Bool = false

    private let startAngle: Double = -220
    private let sweepAngle: Double = 260

    private var arcSize: CGFloat {
        if micro { return 155 }
        return compact ? 200 : 260
    }

    private var lineWidth: CGFloat {
        if micro { return 8 }
        return compact ? 11 : 14
    }

    private var pct: Double {
        min(Double(watts) / Double(maxWatts), 1.0)
    }

    private var zone: PowerZone {
        PowerZone.zone(for: watts)
    }

    private var zoneRangeText: String {
        let low = zone.wattRange.lowerBound
        let high = zone.wattRange.upperBound
        if zone.id == PowerZone.zones.last?.id {
            return "\(low)+ W"
        }
        return "\(low)–\(high) W"
    }

    private var zoneSegments: [(zone: PowerZone, segStart: Double, segSweep: Double)] {
        PowerZone.zones.map { z in
            let lowFrac  = min(Double(z.wattRange.lowerBound) / Double(maxWatts), 1.0)
            let highFrac = min(Double(z.wattRange.upperBound) / Double(maxWatts), 1.0)
            return (z, sweepAngle * lowFrac, sweepAngle * (highFrac - lowFrac))
        }
    }

    var body: some View {
        FTPRefreshScope {
        VStack(spacing: compact ? 8 : 12) {
            ZStack {
                // Base track (gray, visible in the gap above Z5)
                ArcShape(startAngle: startAngle, sweepAngle: sweepAngle)
                    .stroke(Color.white.opacity(0.06),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))

                // Zone-colored segments
                ForEach(zoneSegments, id: \.zone.id) { seg in
                    let isActive = seg.zone.id == zone.id
                    ArcShape(
                        startAngle: startAngle + seg.segStart,
                        sweepAngle: seg.segSweep
                    )
                    .stroke(
                        seg.zone.color.opacity(isActive ? 0.5 : 0.15),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
                    )
                }

                // Filled progress arc
                if watts > 0 {
                    ArcShape(startAngle: startAngle, sweepAngle: sweepAngle * pct)
                        .stroke(zone.color,
                                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .shadow(color: zone.color.opacity(0.35), radius: 8)
                }

                // Zone boundary tick marks (geometry must match `arcSize` + ArcShape radius)
                ForEach(zoneSegments, id: \.zone.id) { seg in
                    if seg.zone.id > 1 {
                        TickMark(
                            angleDegrees: startAngle + seg.segStart,
                            arcSize: arcSize,
                            strokeLineWidth: lineWidth
                        )
                    }
                }

                // Center text (optional — e.g. hidden on iPhone when PhonePowerDisplay is the hero)
                if showCenterText {
                    VStack(spacing: compact ? 2 : 4) {
                        Text("\(watts)")
                            .font(.system(size: compact ? 36 : 48, weight: .bold, design: .monospaced))
                            .foregroundStyle(zone.color)

                        Text("WATTS")
                            .font(.system(size: compact ? 10 : 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.35))
                            .tracking(1.5)

                        Text(zone.name.uppercased())
                            .font(.system(size: compact ? 10 : 11, weight: .semibold))
                            .foregroundStyle(zone.color.opacity(0.9))
                            .tracking(1.5)

                        Text(zoneRangeText)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
            }
            .frame(width: arcSize, height: arcSize)
        }
        .animation(.easeInOut(duration: 0.3), value: watts)
        }
    }
}

private struct MiniStatCard: View {
    let label: String
    let value: String
    let unit: String
    var valueColor: Color = .white
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 5) {
            Text(label)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.white.opacity(0.3))
                .tracking(1.5)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: compact ? 17 : 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(valueColor)
                Text(unit)
                    .font(.system(size: compact ? 9 : 11))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, compact ? 10 : 14)
        .padding(.vertical, compact ? 8 : 12)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(AppOpacity.cardBorder), lineWidth: 1)
        )
    }
}

private struct ArcShape: Shape {
    let startAngle: Double
    let sweepAngle: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 - 10
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startAngle),
            endAngle: .degrees(startAngle + sweepAngle),
            clockwise: false
        )
        return path
    }
}

/// Radial ticks on the zone ring — must use the same center and radius as `ArcShape` in a square of side `arcSize`.
private struct TickMark: View {
    let angleDegrees: Double
    let arcSize: CGFloat
    let strokeLineWidth: CGFloat

    var body: some View {
        let center = CGPoint(x: arcSize / 2, y: arcSize / 2)
        // Match `ArcShape.path(in:)` exactly: radius = min(w,h)/2 - 10
        let radius = min(arcSize, arcSize) / 2 - 10
        let rad = angleDegrees * .pi / 180
        // Ticks span from inside the colored stroke to just outside the track
        let inner = max(2, radius - strokeLineWidth - 6)
        let outer = radius + 5

        Path { path in
            path.move(to: CGPoint(
                x: center.x + inner * cos(rad),
                y: center.y + inner * sin(rad)
            ))
            path.addLine(to: CGPoint(
                x: center.x + outer * cos(rad),
                y: center.y + outer * sin(rad)
            ))
        }
        .stroke(Color.white.opacity(0.22), lineWidth: 1.25)
    }
}

#Preview {
    PowerArcView(watts: 210)
        .environment(FTPRefreshTrigger.shared)
        .padding()
        .background(Color(red: 0.03, green: 0.04, blue: 0.06))
}

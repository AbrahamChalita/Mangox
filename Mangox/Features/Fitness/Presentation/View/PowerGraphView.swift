import SwiftUI
import Charts

#if canImport(UIKit)
    import UIKit
#endif

private enum PowerGraphFontToken {
    static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let fontName: String
        switch weight {
        case .light:
            fontName = "GeistMono-Light"
        case .medium, .semibold, .bold, .heavy, .black:
            fontName = "GeistMono-Medium"
        default:
            fontName = "GeistMono-Regular"
        }

        #if canImport(UIKit)
            if UIFont(name: fontName, size: size) != nil {
                return .custom(fontName, size: size)
            }
        #endif
        return .system(size: size, weight: weight, design: .monospaced)
    }
}

struct PoweredSample: Identifiable {
    let elapsed: Int
    let power: Int
    let zoneKey: String

    var id: Int { elapsed }
}

struct PowerGraphView: View {
    let powerHistory: [PowerSample]
    /// Pre-computed by WorkoutManager — avoids scanning the array in body.
    let powerHistoryMax: Int
    /// Shorter chart on iPhone compact layout.
    var compact: Bool = false
    /// Optional height (pt) when `compact` is true — e.g. shorter while riding to reduce vertical scroll.
    var chartHeightCompact: CGFloat? = nil
    /// Line-only strip with no area fill — same data, less vertical weight than the default chart.
    var flatStrip: Bool = false
    /// Shows a trailing “last N seconds” caption (indoor Details / compact strip).
    var showTimeframeHint: Bool = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Canvas-based zone bar strip — colored columns (height ∝ power, color = zone). Much flatter than a chart.
    var zoneBar: Bool = false

    /// Downsample to a fixed cap before passing to Chart — avoids rendering 7200+ marks
    /// during long rides. LTTB-like: keep first/last, evenly subsample the middle.
    private var annotatedSamples: [PoweredSample] {
        let maxPoints = 600
        let source: [PowerSample]
        if powerHistory.count > maxPoints {
            let step = Double(powerHistory.count) / Double(maxPoints - 1)
            var sampled = [PowerSample]()
            sampled.reserveCapacity(maxPoints)
            for i in 0..<maxPoints {
                let idx = min(Int(Double(i) * step), powerHistory.count - 1)
                sampled.append(powerHistory[idx])
            }
            source = sampled
        } else {
            source = powerHistory
        }
        // Use sequential index (not elapsed seconds) as x so pause/resume gaps don't compress old samples.
        return source.enumerated().map { (i, s) in
            PoweredSample(
                elapsed: i,
                power: s.power,
                zoneKey: "Z\(PowerZone.zone(for: s.power).id)"
            )
        }
    }

    private var chartHeight: CGFloat {
        if zoneBar { return compact ? 20 : 26 }
        if flatStrip {
            if compact, let h = chartHeightCompact { return h }
            return compact ? 38 : 48
        }
        if compact, let h = chartHeightCompact { return h }
        return compact ? 88 : 120
    }

    var body: some View {
        VStack(alignment: .leading, spacing: zoneBar ? 6 : (flatStrip ? 4 : 6)) {
            powerGraphHeader

            let samples = annotatedSamples
            if samples.isEmpty {
                powerGraphEmptyPlaceholder
                    .frame(height: chartHeight)
            } else if zoneBar {
                zoneBarCanvas(samples: samples)
                    .frame(height: chartHeight)
            } else {
                let yCeiling = powerHistoryMax + 20
                ZStack(alignment: .topTrailing) {
                    Chart(samples) { sample in
                        if !flatStrip {
                            AreaMark(
                                x: .value("Time", sample.elapsed),
                                y: .value("Power", sample.power)
                            )
                            .foregroundStyle(by: .value("Zone", sample.zoneKey))
                            .opacity(0.22)
                            .interpolationMethod(.catmullRom)
                        }

                        LineMark(
                            x: .value("Time", sample.elapsed),
                            y: .value("Power", sample.power)
                        )
                        .foregroundStyle(by: .value("Zone", sample.zoneKey))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: flatStrip ? 1.1 : 1.5))
                    }
                    .chartForegroundStyleScale(styleScale)
                    .chartXAxis(.hidden)
                    .modifier(PowerGraphYAxisStyle(flatStrip: flatStrip))
                    .chartYScale(domain: 0...yCeiling)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                    Text(String(format: String(localized: "indoor.power_graph.y_max"), locale: .current, yCeiling))
                        .font(PowerGraphFontToken.mono(size: 9))
                        .foregroundStyle(AppColor.fg3)
                        .padding(.trailing, 4)
                        .padding(.top, 1)
                        .accessibilityHidden(true)
                }
                .frame(height: chartHeight)
            }
        }
        .padding(zoneBar ? 10 : (flatStrip ? 10 : 12))
        .background(AppColor.bg2)
        .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue))
        .overlay(
            RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue)
                .strokeBorder(AppColor.hair2, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var powerGraphHeader: some View {
        if showTimeframeHint, dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                Text(IndoorDashboardL10n.powerGraphTitle)
                    .mangoxFont(.micro)
                    .fontWeight(.bold)
                    .foregroundStyle(AppColor.fg3)
                    .tracking(1.5)
                Text(IndoorDashboardL10n.powerGraphTimeframe)
                    .mangoxFont(.micro)
                    .foregroundStyle(AppColor.fg4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(IndoorDashboardL10n.powerGraphTitle), \(IndoorDashboardL10n.powerGraphTimeframe)")
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(IndoorDashboardL10n.powerGraphTitle)
                    .mangoxFont(.micro)
                    .fontWeight(.bold)
                    .foregroundStyle(AppColor.fg3)
                    .tracking(1.5)
                Spacer(minLength: 8)
                if showTimeframeHint {
                    Text(IndoorDashboardL10n.powerGraphTimeframe)
                        .mangoxFont(.micro)
                        .foregroundStyle(AppColor.fg4)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                showTimeframeHint
                    ? "\(IndoorDashboardL10n.powerGraphTitle), \(IndoorDashboardL10n.powerGraphTimeframe)"
                    : IndoorDashboardL10n.powerGraphTitle
            )
        }
    }

    private func zoneBarCanvas(samples: [PoweredSample]) -> some View {
        Canvas { context, size in
            let n = CGFloat(samples.count)
            guard n > 0 else { return }
            let maxP = max(CGFloat(powerHistoryMax), 1)
            let sliceW = size.width / n
            for (i, sample) in samples.enumerated() {
                let zone = PowerZone.zone(for: sample.power)
                let fillH = max(2, size.height * CGFloat(sample.power) / maxP)
                let rect = CGRect(
                    x: CGFloat(i) * sliceW,
                    y: size.height - fillH,
                    width: max(1, sliceW - 0.5),
                    height: fillH
                )
                context.fill(Path(rect), with: .color(zone.color.opacity(0.72)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var styleScale: KeyValuePairs<String, Color> {
        [
            "Z1": PowerZone.zones[0].color,
            "Z2": PowerZone.zones[1].color,
            "Z3": PowerZone.zones[2].color,
            "Z4": PowerZone.zones[3].color,
            "Z5": PowerZone.zones[4].color,
        ]
    }

    private var powerGraphEmptyPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(AppColor.hair)
            VStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .font(MangoxFont.title.value)
                    .foregroundStyle(AppColor.fg3)
                Text(IndoorDashboardL10n.powerGraphEmpty)
                    .mangoxFont(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(AppColor.fg2)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16)
        }
        .accessibilityLabel(IndoorDashboardL10n.powerGraphEmptyA11y)
    }
}

/// Hides Y axis for the flat strip; otherwise shows compact watt labels + light grid.
private struct PowerGraphYAxisStyle: ViewModifier {
    let flatStrip: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if flatStrip {
            content.chartYAxis(.hidden)
        } else {
            content.chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisValueLabel {
                        if let w = value.as(Int.self) {
                            Text("\(w)")
                                .font(PowerGraphFontToken.mono(size: 9))
                                .foregroundStyle(AppColor.fg3)
                        }
                    }
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        .foregroundStyle(AppColor.hair)
                }
            }
        }
    }
}

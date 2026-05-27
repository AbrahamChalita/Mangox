/// DashboardSubviews.swift
/// Extracted subviews from DashboardView.
///
/// Each struct takes only the values it needs as immutable `let` properties.
/// SwiftUI uses value equality to skip re-rendering a subtree whose inputs
/// haven't changed — the key mechanism for reducing 4 Hz BLE re-renders.

import Foundation
import SwiftData
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

enum DashboardNumberFormat {
    private static let percent0Formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter
    }()
    private static let percent1Formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    static func percent0(_ value: Double) -> String {
        "\(percent0Formatter.string(from: NSNumber(value: value)) ?? "\(value)")%"
    }

    static func percent1(_ value: Double) -> String {
        "\(percent1Formatter.string(from: NSNumber(value: value)) ?? "\(value)")%"
    }
}

enum DashboardFontToken {
    static func ui(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let fontName: String
        switch weight {
        case .light:
            fontName = "Manrope-Light"
        case .medium, .semibold, .bold, .heavy, .black:
            fontName = "Manrope-Medium"
        default:
            fontName = "Manrope-Regular"
        }

        #if canImport(UIKit)
            if UIFont(name: fontName, size: size) != nil {
                return .custom(fontName, size: size)
            }
        #endif
        return .system(size: size, weight: weight)
    }

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

// MARK: - Goal Progress Pill

struct GoalProgressPill: View {
    let goal: RideGoal
    let progress: Double
    let currentValue: String
    let targetValue: String
    let elapsedSeconds: Int

    private var isComplete: Bool { progress >= 1.0 }

    /// Estimated time to completion
    private var etaText: String? {
        guard !isComplete, elapsedSeconds > 0, progress > 0 else { return nil }
        switch goal.kind {
        case .duration:
            let targetSeconds = goal.target * 60
            let remaining = max(0, targetSeconds - Double(elapsedSeconds))
            let min = Int(remaining) / 60
            let sec = Int(remaining) % 60
            return "\(min):\(String(format: "%02d", sec)) left"
        case .distance, .kilojoules, .tss:
            // Extrapolate: if we've done X% in T seconds, remaining = T * (1-X)/X
            let rate = progress / Double(elapsedSeconds)
            let remainingSeconds = (1.0 - progress) / rate
            let totalMin = Int(remainingSeconds / 60)
            if totalMin >= 60 {
                return "~\(totalMin / 60)h \(totalMin % 60)m left"
            }
            return "~\(totalMin)m left"
        }
    }

    var body: some View {
        if goal.kind == .distance {
            distanceGoalBody
        } else {
            standardGoalBody
        }
    }

    private var standardGoalBody: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: isComplete ? "checkmark.circle.fill" : goal.kind.icon)
                    .mangoxFont(.callout)
                    .foregroundStyle(isComplete ? AppColor.success : AppColor.fg2)

                Text(goal.kind.label.uppercased())
                    .mangoxFont(.label)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.fg2)
                    .tracking(0.5)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(AppColor.hair)
                        Capsule()
                            .fill(isComplete ? AppColor.success : AppColor.mango)
                            .frame(width: max(4, geo.size.width * min(progress, 1.0)))
                            .animation(MangoxMotion.smooth, value: progress)
                    }
                }

                let unit = isComplete ? "" : " / \(targetValue) \(goal.kind.unit)"
                Text("\(currentValue)\(unit)")
                    .mangoxFont(.caption)
                    .foregroundStyle(isComplete ? AppColor.success : AppColor.fg1)
            }

            if let eta = etaText {
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .mangoxFont(.micro)
                    Text(eta)
                        .mangoxFont(.label)
                        .foregroundStyle(AppColor.fg3)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppColor.hair)
        .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue))
        .overlay(
            RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue)
                .strokeBorder(AppColor.hair, lineWidth: 1)
        )
    }

    /// Distance goals: full-width “beam” track with gradient fill and a bright leading edge.
    private var distanceGoalBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isComplete ? "checkmark.circle.fill" : "road.lanes")
                    .font(MangoxFont.title.value)
                    .foregroundStyle(isComplete ? AppColor.success : AppColor.mango.opacity(0.95))
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(goal.kind.label.uppercased())
                        .mangoxFont(.label)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.fg3)
                        .tracking(1.1)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(currentValue)
                            .font(DashboardFontToken.mono(size: 26, weight: .heavy))
                            .foregroundStyle(isComplete ? AppColor.success : AppColor.fg0)
                            .contentTransition(.numericText())
                            .minimumScaleFactor(0.72)
                            .lineLimit(1)
                        Text("km")
                            .mangoxFont(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(
                                isComplete ? AppColor.success.opacity(0.7) : AppColor.fg2)
                        if !isComplete {
                            Text("/ \(targetValue)")
                                .mangoxFont(.callout)
                                .fontWeight(.semibold)
                                .foregroundStyle(AppColor.fg3)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 0)

                if let eta = etaText, !isComplete {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: "clock.fill")
                            .mangoxFont(.micro)
                        Text(eta)
                            .font(DashboardFontToken.mono(size: 10, weight: .semibold))
                            .multilineTextAlignment(.trailing)
                    }
                    .foregroundStyle(AppColor.fg3)
                    .frame(maxWidth: 140, alignment: .trailing)
                }
            }

            GeometryReader { geo in
                let w = geo.size.width
                let rawFill = w * min(progress, 1.0)
                let fillW: CGFloat = rawFill <= 0 ? 0 : max(12, rawFill)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue, style: .continuous)
                        .fill(AppColor.hair2)
                    RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppColor.mango.opacity(0.45),
                                    AppColor.mango,
                                    AppColor.orange,
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: fillW)
                        .shadow(color: AppColor.mango.opacity(0.55), radius: 8, x: 0, y: 0)
                        .animation(MangoxMotion.smooth, value: progress)
                        .overlay(alignment: .trailing) {
                            if progress > 0.04 && !isComplete {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [.white.opacity(0.95), .white.opacity(0.35)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(width: 4, height: 14)
                                    .shadow(color: .white.opacity(0.8), radius: 4, x: 0, y: 0)
                            }
                        }
                }
            }
            .frame(height: 18)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue, style: .continuous)
                .fill(AppColor.hair)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [AppColor.mango.opacity(0.35), AppColor.hair],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Live Performance Bar

/// Displays NP, IF, TSS, VI, avg power, Pw:HR, and kJ.
/// Inputs change at 1 Hz (timer tick), not at 4 Hz BLE rate.
struct LivePerformanceBar: View {
    enum LayoutMode {
        case stacked
        /// Single horizontal row for dense phone layouts; falls back to stacked at large Dynamic Type.
        case horizontalScroll
        /// Minimal vertical footprint: one horizontal scroller with all metrics (no section header).
        case oneLine
    }

    let formattedNP: String
    let formattedIF: String
    let formattedTSS: String
    let formattedVI: String
    let formattedAvgPower: String
    let formattedEfficiency: String
    let formattedKJ: String
    let showEfficiency: Bool
    /// When false, IF/TSS are de‑emphasized (FTP not yet set by the user).
    let ftpIsSet: Bool
    /// Tighter typography and padding for iPhone compact layout.
    var compact: Bool = false
    var layoutMode: LayoutMode = .stacked
    /// Omits outer card chrome when embedded in `CollapsibleLivePerformanceBar`.
    var embedded: Bool = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var effectiveLayout: LayoutMode {
        if layoutMode == .oneLine, !dynamicTypeSize.isAccessibilitySize {
            return .oneLine
        }
        if layoutMode == .horizontalScroll, !dynamicTypeSize.isAccessibilitySize {
            return .horizontalScroll
        }
        return .stacked
    }

    @ViewBuilder
    private var performanceContent: some View {
        if effectiveLayout == .oneLine {
            oneLineMetrics
        } else {
            VStack(alignment: .leading, spacing: compact ? 6 : 8) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.fill")
                        .font(MangoxFont.caption.value)
                        .foregroundStyle(AppColor.fg3)
                    Text(IndoorDashboardL10n.livePerformanceTitle)
                        .mangoxFont(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.fg3)
                        .tracking(1.0)
                    Spacer()
                }

                if !ftpIsSet {
                    Text(IndoorDashboardL10n.ftpEstimatedHint)
                        .mangoxFont(.caption)
                        .foregroundStyle(AppColor.fg3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                primaryMetricsRow

                if showEfficiency {
                    secondaryMetricsRow
                }
            }
        }
    }

    var body: some View {
        performanceContent
            .padding(embedded ? 0 : (compact ? 10 : 12))
            .background(embedded ? Color.clear : AppColor.hair)
            .clipShape(RoundedRectangle(cornerRadius: embedded ? 0 : MangoxRadius.sharp.rawValue))
            .overlay {
                if !embedded {
                    RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue)
                        .strokeBorder(AppColor.hair2, lineWidth: 1)
                }
            }
    }

    /// Single short block: optional FTP hint + one horizontal row of all metrics.
    private var oneLineMetrics: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !ftpIsSet {
                Text(IndoorDashboardL10n.ftpEstimatedHint)
                    .mangoxFont(.micro)
                    .foregroundStyle(AppColor.fg3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    let npSize = compact ? 13.0 : 15.0
                    let viSize = compact ? 10.0 : 11.0
                    let avgSize = compact ? 12.0 : 14.0
                    liveMetricPill(
                        label: "NP", value: formattedNP, unit: "W", valueSize: npSize,
                        dimmed: false, fixedWidth: true)
                    liveMetricPill(
                        label: "IF", value: formattedIF, unit: "", valueSize: npSize,
                        dimmed: !ftpIsSet, fixedWidth: true)
                    liveMetricPill(
                        label: "TSS", value: formattedTSS, unit: "", valueSize: npSize,
                        dimmed: !ftpIsSet, fixedWidth: true)
                    liveMetricPill(
                        label: "VI", value: formattedVI, unit: "", valueSize: viSize, dimmed: true,
                        fixedWidth: true)
                    if showEfficiency {
                        liveMetricPill(
                            label: "AVG", value: formattedAvgPower, unit: "W", valueSize: avgSize,
                            dimmed: false, fixedWidth: true)
                        liveMetricPill(
                            label: "Pw:HR", value: formattedEfficiency, unit: "W/bpm",
                            valueSize: avgSize, dimmed: false, fixedWidth: true)
                        liveMetricPill(
                            label: "kJ", value: formattedKJ, unit: "", valueSize: avgSize,
                            dimmed: false, fixedWidth: true)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var primaryMetricsRow: some View {
        let npSize = compact ? 15.0 : 18.0
        let viSize = compact ? 11.0 : 13.0
        if effectiveLayout == .horizontalScroll {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    liveMetricPill(
                        label: "NP", value: formattedNP, unit: "W", valueSize: npSize,
                        dimmed: false, fixedWidth: true)
                    liveMetricPill(
                        label: "IF", value: formattedIF, unit: "", valueSize: npSize,
                        dimmed: !ftpIsSet, fixedWidth: true)
                    liveMetricPill(
                        label: "TSS", value: formattedTSS, unit: "", valueSize: npSize,
                        dimmed: !ftpIsSet, fixedWidth: true)
                    liveMetricPill(
                        label: "VI", value: formattedVI, unit: "", valueSize: viSize, dimmed: true,
                        fixedWidth: true)
                }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: compact ? 6 : 10) {
                liveMetricPill(
                    label: "NP", value: formattedNP, unit: "W", valueSize: npSize, dimmed: false,
                    fixedWidth: false)
                liveMetricPill(
                    label: "IF", value: formattedIF, unit: "", valueSize: npSize, dimmed: !ftpIsSet,
                    fixedWidth: false)
                liveMetricPill(
                    label: "TSS", value: formattedTSS, unit: "", valueSize: npSize,
                    dimmed: !ftpIsSet, fixedWidth: false)
                liveMetricPill(
                    label: "VI", value: formattedVI, unit: "", valueSize: viSize, dimmed: true,
                    fixedWidth: false)
            }
        }
    }

    @ViewBuilder
    private var secondaryMetricsRow: some View {
        let avgSize = compact ? 14.0 : 16.0
        if effectiveLayout == .horizontalScroll {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    liveMetricPill(
                        label: "AVG", value: formattedAvgPower, unit: "W", valueSize: avgSize,
                        dimmed: false, fixedWidth: true)
                    liveMetricPill(
                        label: "Pw:HR", value: formattedEfficiency, unit: "W/bpm",
                        valueSize: avgSize, dimmed: false, fixedWidth: true)
                    liveMetricPill(
                        label: "kJ", value: formattedKJ, unit: "", valueSize: avgSize,
                        dimmed: false, fixedWidth: true)
                }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: compact ? 6 : 10) {
                liveMetricPill(
                    label: "AVG", value: formattedAvgPower, unit: "W", valueSize: avgSize,
                    dimmed: false, fixedWidth: false)
                liveMetricPill(
                    label: "Pw:HR", value: formattedEfficiency, unit: "W/bpm", valueSize: avgSize,
                    dimmed: false, fixedWidth: false)
                liveMetricPill(
                    label: "kJ", value: formattedKJ, unit: "", valueSize: avgSize, dimmed: false,
                    fixedWidth: false)
            }
        }
    }

    private func liveMetricPill(
        label: String,
        value: String,
        unit: String,
        valueSize: CGFloat = 15,
        dimmed: Bool = false,
        fixedWidth: Bool
    ) -> some View {
        let baseOpacity = dimmed ? 0.45 : 0.85
        return VStack(spacing: compact ? 2 : 3) {
            Text(label)
                .mangoxFont(.micro)
                .fontWeight(.bold)
                .foregroundStyle(AppColor.fg3)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(DashboardFontToken.mono(size: valueSize, weight: .bold))
                    .foregroundStyle(AppColor.fg0.opacity(baseOpacity))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                if !unit.isEmpty {
                    Text(unit)
                        .mangoxFont(.micro)
                        .foregroundStyle(AppColor.fg3)
                }
            }
        }
        // Horizontal row: min width only so wide values (e.g. TSS) never squish — user scrolls instead.
        // Stacked row: equal-width columns.
        .frame(minWidth: fixedWidth ? 56 : 0, maxWidth: fixedWidth ? nil : .infinity)
        .padding(.horizontal, fixedWidth ? 8 : 0)
        .padding(.vertical, compact ? 5 : 6)
        .background(AppColor.hair)
        .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue))
    }
}

// MARK: - Session stats expanded grid

/// Two-up grid for NP/IF/TSS/VI plus a slim efficiency row — cleaner than a single scrolling strip when expanded.
struct SessionStatsMetricGrid: View {
    let formattedNP: String
    let formattedIF: String
    let formattedTSS: String
    let formattedVI: String
    let formattedAvgPower: String
    let formattedEfficiency: String
    let formattedKJ: String
    let showEfficiency: Bool
    let ftpIsSet: Bool
    var compact: Bool = true

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var gridColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
    }

    private var gridSpacing: CGFloat { dynamicTypeSize.isAccessibilitySize ? 10 : 8 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !ftpIsSet {
                Text(IndoorDashboardL10n.ftpEstimatedHint)
                    .mangoxFont(.caption)
                    .foregroundStyle(AppColor.fg3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: gridSpacing) {
                    statTile(label: "NP", value: formattedNP, unit: "W", dimmed: false)
                    statTile(label: "IF", value: formattedIF, unit: "", dimmed: !ftpIsSet)
                    statTile(label: "TSS", value: formattedTSS, unit: "", dimmed: !ftpIsSet)
                    statTile(label: "VI", value: formattedVI, unit: "", dimmed: true)
                }
            } else {
                LazyVGrid(columns: gridColumns, spacing: gridSpacing) {
                    statTile(label: "NP", value: formattedNP, unit: "W", dimmed: false)
                    statTile(label: "IF", value: formattedIF, unit: "", dimmed: !ftpIsSet)
                    statTile(label: "TSS", value: formattedTSS, unit: "", dimmed: !ftpIsSet)
                    statTile(label: "VI", value: formattedVI, unit: "", dimmed: true)
                }
            }

            if showEfficiency {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: gridSpacing) {
                        statTileFlexible(
                            label: "AVG", value: formattedAvgPower, unit: "W", dimmed: false)
                        statTileFlexible(
                            label: "Pw:HR", value: formattedEfficiency, unit: "W/bpm",
                            dimmed: false)
                        statTileFlexible(label: "kJ", value: formattedKJ, unit: "", dimmed: false)
                    }
                } else {
                    HStack(spacing: 8) {
                        statTileFlexible(
                            label: "AVG", value: formattedAvgPower, unit: "W", dimmed: false)
                        statTileFlexible(
                            label: "Pw:HR", value: formattedEfficiency, unit: "W/bpm",
                            dimmed: false)
                        statTileFlexible(label: "kJ", value: formattedKJ, unit: "", dimmed: false)
                    }
                }
            }
        }
    }

    private func statTile(label: String, value: String, unit: String, dimmed: Bool) -> some View {
        let baseOpacity = dimmed ? 0.45 : 0.88
        return VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .mangoxFont(.label)
                .fontWeight(.bold)
                .foregroundStyle(AppColor.fg3)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(
                        DashboardFontToken.mono(
                            size: compact ? 17 : 19,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(AppColor.fg0.opacity(baseOpacity))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !unit.isEmpty {
                    Text(unit)
                        .mangoxFont(.label)
                        .foregroundStyle(AppColor.fg3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue, style: .continuous)
                .fill(AppColor.hair)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue, style: .continuous)
                .strokeBorder(AppColor.hair2, lineWidth: 1)
        )
    }

    private func statTileFlexible(label: String, value: String, unit: String, dimmed: Bool)
        -> some View
    {
        let baseOpacity = dimmed ? 0.45 : 0.88
        return VStack(alignment: .center, spacing: 4) {
            Text(label)
                .mangoxFont(.micro)
                .fontWeight(.bold)
                .foregroundStyle(AppColor.fg3)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(DashboardFontToken.mono(size: 13, weight: .bold))
                    .foregroundStyle(AppColor.fg0.opacity(baseOpacity))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                if !unit.isEmpty {
                    Text(unit)
                        .mangoxFont(.micro)
                        .foregroundStyle(AppColor.fg3)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue, style: .continuous)
                .fill(AppColor.hair)
        )
    }
}

// MARK: - Collapsible live performance

/// NP / IF / TSS live block, collapsed by default; expand for full detail. Still records in `WorkoutManager` either way.
struct CollapsibleLivePerformanceBar: View {
    @State private var expanded = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let formattedNP: String
    let formattedIF: String
    let formattedTSS: String
    let formattedVI: String
    let formattedAvgPower: String
    let formattedEfficiency: String
    let formattedKJ: String
    let showEfficiency: Bool
    let ftpIsSet: Bool
    var compact: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(MangoxMotion.micro) { expanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.right")
                        .mangoxFont(.callout)
                        .fontWeight(.bold)
                        .foregroundStyle(AppColor.fg2)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Image(systemName: "chart.bar.fill")
                        .mangoxFont(.callout)
                        .foregroundStyle(AppColor.fg3)
                    Text(IndoorDashboardL10n.sessionStatsTitle)
                        .mangoxFont(.callout)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.fg2)
                        .tracking(0.6)
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(formattedAvgPower) W")
                            .mangoxFont(.callout)
                            .fontWeight(.bold)
                            .foregroundStyle(AppColor.fg2)
                        Text("\(formattedKJ) kJ")
                            .mangoxFont(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColor.mango.opacity(0.95))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(IndoorDashboardL10n.sessionStatsTitle)
            .accessibilityValue(
                expanded
                    ? String(localized: "indoor.session_stats.a11y_expanded")
                    : String(localized: "indoor.session_stats.a11y_collapsed")
            )
            .accessibilityHint(IndoorDashboardL10n.sessionStatsExpandHint)

            if expanded {
Rectangle()
                .fill(AppColor.hair2)
                .frame(height: 1)
                    .padding(.horizontal, 10)

                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        LivePerformanceBar(
                            formattedNP: formattedNP,
                            formattedIF: formattedIF,
                            formattedTSS: formattedTSS,
                            formattedVI: formattedVI,
                            formattedAvgPower: formattedAvgPower,
                            formattedEfficiency: formattedEfficiency,
                            formattedKJ: formattedKJ,
                            showEfficiency: showEfficiency,
                            ftpIsSet: ftpIsSet,
                            compact: compact,
                            layoutMode: .stacked,
                            embedded: true
                        )
                    } else {
                        SessionStatsMetricGrid(
                            formattedNP: formattedNP,
                            formattedIF: formattedIF,
                            formattedTSS: formattedTSS,
                            formattedVI: formattedVI,
                            formattedAvgPower: formattedAvgPower,
                            formattedEfficiency: formattedEfficiency,
                            formattedKJ: formattedKJ,
                            showEfficiency: showEfficiency,
                            ftpIsSet: ftpIsSet,
                            compact: compact
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .background(AppColor.hair)
        .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue))
        .overlay(
            RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue)
                .strokeBorder(AppColor.hair2, lineWidth: 1)
        )
        #if canImport(UIKit)
            /// First tap on Session stats often failed: UIScrollView defers touches to see if the user is scrolling.
            .overlay(alignment: .topLeading) {
                ScrollViewImmediateTouchesAnchor()
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
            }
        #endif
    }
}

// MARK: - Live power zone distribution (compact ride)

/// Thin stacked bar of time-in-zone (Z1–Z5), using ``PowerZone`` palette from the design system.
struct IndoorZoneDistributionStrip: View {
    let zoneSecondsByZoneID: [Int: Int]
    var compact: Bool = true

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var total: Int {
        zoneSecondsByZoneID.values.reduce(0, +)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 6) {
            HStack(spacing: 6) {
                Text(String(localized: "indoor.dashboard.zones.title"))
                    .mangoxFont(.micro)
                    .fontWeight(.bold)
                    .foregroundStyle(AppColor.fg3)
                    .tracking(1.0)
                Spacer(minLength: 0)
            }

            if total == 0 {
                VStack(spacing: compact ? 4 : 5) {
                    Text(String(localized: "indoor.dashboard.zones.empty"))
                        .font(DashboardFontToken.mono(size: dynamicTypeSize.isAccessibilitySize ? 15 : 13, weight: .semibold))
                        .foregroundStyle(AppColor.fg4)
                    Text(String(localized: "indoor.dashboard.zones.empty_caption"))
                        .mangoxFont(.micro)
                        .foregroundStyle(AppColor.fg4.opacity(0.9))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            } else {
                GeometryReader { geo in
                    let w = geo.size.width
                    HStack(spacing: 0) {
                        ForEach(PowerZone.zones) { zone in
                            let secs = zoneSecondsByZoneID[zone.id] ?? 0
                            let fw =
                                total > 0 ? w * CGFloat(secs) / CGFloat(total) : 0
                            Rectangle()
                                .fill(zone.color)
                                .frame(width: secs > 0 ? max(fw, 2) : 0)
                        }
                    }
                }
                .frame(height: compact ? 5 : 6)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "indoor.dashboard.zones.a11y"))
                .accessibilityValue(zoneAccessibilitySummary)
            }

            HStack(spacing: 0) {
                ForEach(PowerZone.zones) { zone in
                    Text("Z\(zone.id)")
                        .font(DashboardFontToken.mono(size: 9, weight: .bold))
                        .foregroundStyle(AppColor.fg4)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, compact ? 10 : 12)
        .padding(.vertical, compact ? 8 : 10)
        .background(AppColor.hair.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue))
        .overlay(
            RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue)
                .strokeBorder(AppColor.hair2, lineWidth: 1)
        )
    }

    private var zoneAccessibilitySummary: String {
        PowerZone.zones.map { z in
            let s = zoneSecondsByZoneID[z.id] ?? 0
            return "Z\(z.id) \(s)s"
        }.joined(separator: ", ")
    }
}

// MARK: - Ride heart rate card

/// Full-width card below the power hero — keeps HR scannable without crowding watts.
struct IndoorRideHeartRateCard: View {
    let heartRateBpm: Int

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var zone: HeartRateZone {
        heartRateBpm > 0 ? HeartRateZone.zone(for: heartRateBpm) : HeartRateZone.zones[0]
    }

    private var tint: Color { heartRateBpm > 0 ? zone.color : AppColor.fg4 }

    private var pctMax: Double {
        HeartRateZone.percentOfMax(bpm: heartRateBpm)
    }

    private var zoneLabel: String {
        heartRateBpm > 0
            ? String(format: String(localized: "indoor.dashboard.heart_card.zone_format"), zone.id)
            : String(localized: "indoor.dashboard.heart_card.no_zone")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? 12 : 10) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(heartRateBpm > 0 ? 0.18 : 0.10))
                    Image(systemName: "heart.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(tint)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "indoor.dashboard.heart_card.current_zone"))
                        .mangoxFont(.micro)
                        .fontWeight(.bold)
                        .foregroundStyle(AppColor.fg3)
                        .tracking(1.0)
                    Text(heartRateBpm > 0 ? zone.name.uppercased() : String(localized: "indoor.dashboard.heart_card.waiting"))
                        .mangoxFont(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(heartRateBpm > 0 ? tint.opacity(0.95) : AppColor.fg4)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(zoneLabel)
                        .font(
                            DashboardFontToken.mono(
                                size: dynamicTypeSize.isAccessibilitySize ? 28 : 24,
                                weight: .heavy
                            )
                        )
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(heartRateBpm > 0 ? "\(Int((pctMax * 100).rounded()))% max" : "")
                        .font(DashboardFontToken.mono(size: 9, weight: .semibold))
                        .foregroundStyle(AppColor.fg3)
                        .lineLimit(1)
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(heartRateBpm > 0 ? "\(heartRateBpm)" : "—")
                        .font(
                            DashboardFontToken.mono(
                                size: dynamicTypeSize.isAccessibilitySize ? 34 : 30,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(tint)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text("bpm")
                        .mangoxFont(.micro)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.fg3)
                }

                Spacer(minLength: 0)

                HStack(spacing: 3) {
                    ForEach(HeartRateZone.zones) { z in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(z.color.opacity(heartRateBpm > 0 && z.id == zone.id ? 1.0 : 0.22))
                            .frame(width: 20, height: heartRateBpm > 0 && z.id == zone.id ? 10 : 6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .strokeBorder(
                                        heartRateBpm > 0 && z.id == zone.id ? Color.white.opacity(0.45) : Color.clear,
                                        lineWidth: 1
                                    )
                            )
                    }
                }
                .accessibilityHidden(true)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    HStack(spacing: 2) {
                        ForEach(HeartRateZone.zones) { z in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(z.color.opacity(0.20))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    if heartRateBpm > 0 {
                        Capsule()
                            .fill(tint)
                            .frame(width: max(8, geo.size.width * min(max(pctMax, 0), 1)))
                            .shadow(color: tint.opacity(0.35), radius: 5, x: 0, y: 0)
                            .animation(MangoxMotion.standard, value: heartRateBpm)
                        Circle()
                            .fill(tint)
                            .frame(width: 10, height: 10)
                            .offset(x: max(0, geo.size.width * min(max(pctMax, 0), 1) - 5))
                            .shadow(color: tint.opacity(0.6), radius: 5, x: 0, y: 0)
                            .animation(MangoxMotion.standard, value: heartRateBpm)
                    } else {
                        Text(String(localized: "indoor.dashboard.heart_card.waiting_short"))
                            .mangoxFont(.micro)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColor.fg3)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .frame(height: 12)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 14 : 12)
        .background(
            LinearGradient(
                colors: [
                    tint.opacity(heartRateBpm > 0 ? 0.16 : 0.06),
                    AppColor.bg2,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue))
        .overlay(
            RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue)
                .strokeBorder(heartRateBpm > 0 ? tint.opacity(0.30) : AppColor.hair2, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "indoor.dashboard.hero.hr.a11y"))
        .accessibilityValue(
            heartRateBpm > 0
                ? "\(heartRateBpm) bpm, \(zoneLabel), \(zone.name)" : String(localized: "indoor.dashboard.heart_card.waiting_a11y"))
    }
}

#if canImport(UIKit)
    /// Finds the enclosing `UIScrollView` and sets `delaysContentTouches = false` so buttons respond on the first tap.
    private struct ScrollViewImmediateTouchesAnchor: UIViewRepresentable {
        func makeUIView(context: Context) -> UIView {
            let v = UIView()
            v.isUserInteractionEnabled = false
            v.backgroundColor = .clear
            return v
        }

        func updateUIView(_ uiView: UIView, context: Context) {
            var superview: UIView? = uiView.superview
            while let s = superview {
                if let scroll = s as? UIScrollView {
                    scroll.delaysContentTouches = false
                    return
                }
                superview = s.superview
            }
        }
    }
#endif

// MARK: - Indoor ride mode (free vs route)

/// Explains session mode so a map-free layout still feels intentional.
struct IndoorRideModeContext: View {
    let hasRoute: Bool
    let routeName: String?
    /// Hides the secondary GPX hint line to save vertical space on single-screen layouts.
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 0 : 6) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: hasRoute ? "map.fill" : "figure.indoor.cycle")
                        .mangoxFont(.caption)
                        .fontWeight(.semibold)
                    Text(hasRoute ? IndoorDashboardL10n.route : IndoorDashboardL10n.freeRide)
                        .mangoxFont(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(hasRoute ? AppColor.mango.opacity(0.95) : AppColor.fg1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppColor.hair)
                .clipShape(Capsule())

                if hasRoute, let routeName, !routeName.isEmpty {
                    Text(routeName)
                        .mangoxFont(.callout)
                        .foregroundStyle(AppColor.fg2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer(minLength: 0)
            }

            if !hasRoute && !compact {
                Text(IndoorDashboardL10n.gpxHint)
                    .mangoxFont(.caption)
                    .foregroundStyle(AppColor.fg3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}


// MARK: - Phone Power Display

/// Large power number with zone strip and progress bar — iPhone compact layout.
struct PhonePowerDisplay: View {
    let smoothedWatts: Int
    let zone: PowerZone
    let pctFTP: Int
    let powerZoneRangeText: String
    /// 3s smoothed power shown as a capsule beside the zone name (e.g. next to “Recovery”).
    var avg3s: Double? = nil
    /// Guided ERG band + status, when the active step exposes a watt range.
    var guidedTargetText: String? = nil
    var guidedStatusText: String? = nil
    var guidedStatusColor: Color = AppColor.fg2

    @ScaledMetric(relativeTo: .largeTitle) private var heroFontSize = 56
    @ScaledMetric(relativeTo: .title3) private var secondaryFontSize = 18
    @ScaledMetric(relativeTo: .title2) private var ftpFontSize = 22
    @ScaledMetric(relativeTo: .caption) private var zoneNameFontSize = 12
    @ScaledMetric(relativeTo: .caption) private var pctUnitFontSize = 11
    @ScaledMetric(relativeTo: .caption2) private var rangeFontSize = 10
    @ScaledMetric(relativeTo: .caption) private var progressBarHeight = 4
    /// Keeps zone/FTP column from expanding and stealing space from the hero watts.
    @ScaledMetric(relativeTo: .body) private var zoneColumnWidth = 118
    @ScaledMetric(relativeTo: .body) private var zoneColumnWidthWithPill = 148

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                // Watts + bar: must shrink first — zone column keeps a fixed budget so 4-digit watts don’t clip.
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(smoothedWatts)")
                            .font(DashboardFontToken.mono(size: heroFontSize, weight: .black))
                            .foregroundStyle(zone.color)
                            .contentTransition(.numericText())
                            .lineLimit(1)
                            .minimumScaleFactor(0.42)
                        Text("W")
                            .font(DashboardFontToken.ui(size: secondaryFontSize, weight: .medium))
                            .foregroundStyle(AppColor.fg3)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                // Zone info — capped width so the hero always wins the remaining width budget.
                VStack(alignment: .trailing, spacing: 5) {
                    HStack(alignment: .center, spacing: 6) {
                        Text(zone.name.uppercased())
                            .font(DashboardFontToken.mono(size: zoneNameFontSize, weight: .bold))
                            .foregroundStyle(zone.color)
                            .tracking(1.0)
                            .lineLimit(avg3s != nil ? 1 : 2)
                            .minimumScaleFactor(0.72)
                            .multilineTextAlignment(.trailing)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .trailing)
                        if let s = avg3s {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("3s")
                                    .mangoxFont(.micro)
                                    .fontWeight(.bold)
                                    .foregroundStyle(AppColor.fg3)
                                Text("\(Int(s))")
                                    .font(DashboardFontToken.mono(size: 12, weight: .bold))
                                    .foregroundStyle(PowerZone.zone(for: Int(s)).color)
                                Text("W")
                                    .mangoxFont(.micro)
                                    .foregroundStyle(AppColor.fg3)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppColor.hair2)
                            .clipShape(Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(pctFTP)")
                            .font(DashboardFontToken.mono(size: ftpFontSize, weight: .bold))
                            .foregroundStyle(zone.color.opacity(0.85))
                            .contentTransition(.numericText())
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("%")
                            .font(DashboardFontToken.ui(size: pctUnitFontSize, weight: .medium))
                            .foregroundStyle(AppColor.fg3)
                    }
                    Text(powerZoneRangeText)
                        .font(DashboardFontToken.mono(size: rangeFontSize))
                        .foregroundStyle(AppColor.fg3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .frame(
                    width: avg3s != nil ? zoneColumnWidthWithPill : zoneColumnWidth,
                    alignment: .trailing
                )
                .layoutPriority(0)
            }

            ZoneTickedPowerBar(
                watts: smoothedWatts,
                zone: zone
            )
            .padding(.top, 6)

            if let target = guidedTargetText {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(target)
                        .mangoxFont(.micro)
                        .fontWeight(.medium)
                        .foregroundStyle(AppColor.fg3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                    if let status = guidedStatusText {
                        Text(status)
                            .mangoxFont(.micro)
                            .fontWeight(.semibold)
                            .foregroundStyle(guidedStatusColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
                .padding(.top, 6)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    ([target] + [guidedStatusText].compactMap { $0 }).joined(separator: ", ")
                )
            }
        }
        .padding(.vertical, 8)
        .animation(MangoxMotion.standard, value: zone.id)
    }
}

// MARK: - Zone Ticked Power Bar

/// Compact horizontal bar with zone boundary tick marks.
/// Shows current power as a colored fill against a track marked with
/// zone boundaries for instant spatial context during hard efforts.
struct ZoneTickedPowerBar: View {
    let watts: Int
    let zone: PowerZone

    private var maxWatts: Double {
        max(Double(PowerZone.ftp) * 1.5, 500)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(AppColor.hair2)

                // Zone boundary tick marks
                ForEach(PowerZone.zones) { z in
                    let boundary = Double(z.wattRange.upperBound)
                    let xPos = w * CGFloat(min(boundary / maxWatts, 1.0))

                    Rectangle()
                        .fill(z.color.opacity(0.5))
                        .frame(width: 1.5, height: h - 2)
                        .position(x: xPos, y: h / 2)
                }

                // Power fill
                Capsule()
                    .fill(zone.color)
                    .scaleEffect(
                        x: min(Double(watts) / 500.0, 1.0), y: 1, anchor: .leading
                    )
                    .animation(MangoxMotion.standard, value: watts)
            }
        }
        .frame(height: 5)
    }
}

// MARK: - Peak effort (live best 5s)

/// Best 5s average power so far — compact row for the Details page.
struct IndoorPeakEffortsRow: View {
    let peakPowers: [PeakPowerEntry]

    private var best5s: PeakPowerEntry? {
        peakPowers.first { $0.windowSeconds == 5 && $0.watts > 0 }
    }

    var body: some View {
        if let peak = best5s {
            HStack(spacing: 10) {
                Text(IndoorDashboardL10n.peakEffort5sTitle)
                    .mangoxFont(.micro)
                    .fontWeight(.bold)
                    .foregroundStyle(AppColor.fg3)
                    .tracking(0.8)
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(peak.watts)")
                        .font(DashboardFontToken.mono(size: 15, weight: .bold))
                        .foregroundStyle(AppColor.mango)
                    Text("W")
                        .mangoxFont(.micro)
                        .foregroundStyle(AppColor.fg3)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(AppColor.hair.opacity(0.88))
            .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue))
            .overlay(
                RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue)
                    .strokeBorder(AppColor.hair2, lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                String(format: String(localized: "indoor.peak_effort.5s_a11y"), peak.watts)
            )
        }
    }
}

#Preview("Free Ride") {
    let ble = BLEManager()
    let wifi = WiFiTrainerService()
    let ds = DataSourceCoordinator(bleManager: ble, wifiService: wifi)
    let rm = RouteManager()
    let hk = HealthKitManager()
    let la = RideLiveActivityManager.shared
    let container = try! PersistenceContainer.makeContainer(inMemory: true)
    let workoutRepository = WorkoutPersistenceRepository(modelContainer: container)
    let trainingRepository = TrainingPlanPersistenceRepository(modelContainer: container)
    DashboardView(
        navigationPath: .constant(NavigationPath()),
        trainingPlanLookupService: TrainingPlanLookupService(modelContainer: container),
        viewModel: IndoorViewModel(
            bleService: ble,
            dataSourceService: ds,
            routeService: rm,
            healthKitService: hk,
            liveActivityService: la,
            workoutPersistenceRepository: workoutRepository,
            trainingPlanPersistenceRepository: trainingRepository
        )
    )
    .modelContainer(
        for: [
            Workout.self, WorkoutSample.self, LapSplit.self, TrainingPlanProgress.self,
            CustomWorkoutTemplate.self, WorkoutRAGChunk.self,
        ],
        inMemory: true
    )
    .environment(ble)
    .environment(ds)
    .environment(rm)
    .environment(hk)
    .environment(FTPRefreshTrigger.shared)
}

#Preview("Guided Session") {
    let ble = BLEManager()
    let wifi = WiFiTrainerService()
    let ds = DataSourceCoordinator(bleManager: ble, wifiService: wifi)
    let rm = RouteManager()
    let hk = HealthKitManager()
    let la = RideLiveActivityManager.shared
    let container = try! PersistenceContainer.makeContainer(inMemory: true)
    let workoutRepository = WorkoutPersistenceRepository(modelContainer: container)
    let trainingRepository = TrainingPlanPersistenceRepository(modelContainer: container)
    DashboardView(
        navigationPath: .constant(NavigationPath()),
        planDayID: "w2d2",
        trainingPlanLookupService: TrainingPlanLookupService(modelContainer: container),
        viewModel: IndoorViewModel(
            bleService: ble,
            dataSourceService: ds,
            routeService: rm,
            healthKitService: hk,
            liveActivityService: la,
            workoutPersistenceRepository: workoutRepository,
            trainingPlanPersistenceRepository: trainingRepository
        )
    )
    .modelContainer(
        for: [
            Workout.self, WorkoutSample.self, LapSplit.self, TrainingPlanProgress.self,
            CustomWorkoutTemplate.self, WorkoutRAGChunk.self,
        ],
        inMemory: true
    )
    .environment(ble)
    .environment(ds)
    .environment(rm)
    .environment(hk)
    .environment(FTPRefreshTrigger.shared)
}

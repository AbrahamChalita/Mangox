/// DashboardSubviews.swift
/// Extracted subviews from DashboardView.
///
/// Each struct takes only the values it needs as immutable `let` properties.
/// SwiftUI uses value equality to skip re-rendering a subtree whose inputs
/// haven't changed — the key mechanism for reducing 4 Hz BLE re-renders.

import SwiftData
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

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
                    .font(.system(size: 12))
                    .foregroundStyle(isComplete ? AppColor.success : .white.opacity(0.5))

                Text(goal.kind.label.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .tracking(0.5)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.06))
                        Capsule()
                            .fill(isComplete ? AppColor.success : AppColor.mango)
                            .frame(width: max(4, geo.size.width * min(progress, 1.0)))
                            .animation(.easeInOut(duration: 0.5), value: progress)
                    }
                }

                let unit = isComplete ? "" : " / \(targetValue) \(goal.kind.unit)"
                Text("\(currentValue)\(unit)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(isComplete ? AppColor.success : .white.opacity(0.6))
            }

            if let eta = etaText {
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 8))
                    Text(eta)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    /// Distance goals: full-width “beam” track with gradient fill and a bright leading edge.
    private var distanceGoalBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isComplete ? "checkmark.circle.fill" : "road.lanes")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isComplete ? AppColor.success : AppColor.mango.opacity(0.95))
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(goal.kind.label.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.38))
                        .tracking(1.1)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(currentValue)
                            .font(.system(size: 26, weight: .heavy, design: .monospaced))
                            .foregroundStyle(isComplete ? AppColor.success : .white)
                            .contentTransition(.numericText())
                            .minimumScaleFactor(0.72)
                            .lineLimit(1)
                        Text("km")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(
                                isComplete ? AppColor.success.opacity(0.7) : .white.opacity(0.55))
                        if !isComplete {
                            Text("/ \(targetValue)")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.38))
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 0)

                if let eta = etaText, !isComplete {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 9))
                        Text(eta)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .multilineTextAlignment(.trailing)
                    }
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: 140, alignment: .trailing)
                }
            }

            GeometryReader { geo in
                let w = geo.size.width
                let rawFill = w * min(progress, 1.0)
                let fillW: CGFloat = rawFill <= 0 ? 0 : max(12, rawFill)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppColor.mango.opacity(0.45),
                                    AppColor.mango,
                                    Color(red: 1, green: 0.48, blue: 0.15),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: fillW)
                        .shadow(color: AppColor.mango.opacity(0.55), radius: 8, x: 0, y: 0)
                        .animation(.easeInOut(duration: 0.45), value: progress)
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
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [AppColor.mango.opacity(0.35), Color.white.opacity(0.06)],
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
                        .font(.system(size: compact ? 10 : 11))
                        .foregroundStyle(.white.opacity(0.3))
                    Text(IndoorDashboardL10n.livePerformanceTitle)
                        .font(.system(size: compact ? 10 : 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.3))
                        .tracking(1.0)
                    Spacer()
                }

                if !ftpIsSet {
                    Text(IndoorDashboardL10n.ftpEstimatedHint)
                        .font(.system(size: compact ? 10 : 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.38))
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
            .background(embedded ? Color.clear : Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: embedded ? 0 : 12))
            .overlay {
                if !embedded {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                }
            }
    }

    /// Single short block: optional FTP hint + one horizontal row of all metrics.
    private var oneLineMetrics: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !ftpIsSet {
                Text(IndoorDashboardL10n.ftpEstimatedHint)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.38))
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
                .font(.system(size: compact ? 9 : 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.3))
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: valueSize, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(baseOpacity))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: compact ? 9 : 10))
                        .foregroundStyle(.white.opacity(0.25))
                }
            }
        }
        // Horizontal row: min width only so wide values (e.g. TSS) never squish — user scrolls instead.
        // Stacked row: equal-width columns.
        .frame(minWidth: fixedWidth ? 56 : 0, maxWidth: fixedWidth ? nil : .infinity)
        .padding(.horizontal, fixedWidth ? 8 : 0)
        .padding(.vertical, compact ? 5 : 6)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

    private var gridColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !ftpIsSet {
                Text(IndoorDashboardL10n.ftpEstimatedHint)
                    .font(.system(size: compact ? 10 : 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.38))
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(columns: gridColumns, spacing: 8) {
                statTile(label: "NP", value: formattedNP, unit: "W", dimmed: false)
                statTile(label: "IF", value: formattedIF, unit: "", dimmed: !ftpIsSet)
                statTile(label: "TSS", value: formattedTSS, unit: "", dimmed: !ftpIsSet)
                statTile(label: "VI", value: formattedVI, unit: "", dimmed: true)
            }

            if showEfficiency {
                HStack(spacing: 8) {
                    statTileFlexible(
                        label: "AVG", value: formattedAvgPower, unit: "W", dimmed: false)
                    statTileFlexible(
                        label: "Pw:HR", value: formattedEfficiency, unit: "W/bpm", dimmed: false)
                    statTileFlexible(label: "kJ", value: formattedKJ, unit: "", dimmed: false)
                }
            }
        }
    }

    private func statTile(label: String, value: String, unit: String, dimmed: Bool) -> some View {
        let baseOpacity = dimmed ? 0.45 : 0.88
        return VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.32))
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: compact ? 17 : 19, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(baseOpacity))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.28))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private func statTileFlexible(label: String, value: String, unit: String, dimmed: Bool)
        -> some View
    {
        let baseOpacity = dimmed ? 0.45 : 0.88
        return VStack(alignment: .center, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.3))
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(baseOpacity))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.26))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.04))
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
                withAnimation(.easeInOut(duration: 0.22)) { expanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.45))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.35))
                    Text(IndoorDashboardL10n.sessionStatsTitle)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.45))
                        .tracking(0.6)
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(formattedAvgPower) W")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.55))
                        Text("\(formattedKJ) kJ")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
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
                    .fill(Color.white.opacity(0.08))
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
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
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
            DispatchQueue.main.async {
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
                        .font(.system(size: 11, weight: .semibold))
                    Text(hasRoute ? IndoorDashboardL10n.route : IndoorDashboardL10n.freeRide)
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(hasRoute ? AppColor.mango.opacity(0.95) : .white.opacity(0.88))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())

                if hasRoute, let routeName, !routeName.isEmpty {
                    Text(routeName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer(minLength: 0)
            }

            if !hasRoute && !compact {
                Text(IndoorDashboardL10n.gpxHint)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.32))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Trainer Control Card

struct TrainerControlCard: View {
    let trainerMode: TrainerControlMode
    let supportsSimulation: Bool
    let supportsERG: Bool
    let supportsResistance: Bool
    let hasRoute: Bool
    let isWorkoutActive: Bool
    /// When true, show the “load GPX for simulation” line (e.g. guided session has no mode banner).
    let showRouteSimulationFooterHint: Bool
    /// Tighter chrome for portrait single-screen layouts.
    var condensed: Bool = false

    var intensityMultiplier: Double = 1.0
    var onIntensityChange: ((Double) -> Void)? = nil

    var routeDifficultyScale: Double = 0.5
    var onDifficultyChange: ((Double) -> Void)? = nil

    let onRouteSim: () -> Void
    let onERG: () -> Void
    let onResistance: () -> Void
    let onFreeRide: () -> Void

    private var isRouteSimActive: Bool {
        if case .simulation = trainerMode { return true }
        return false
    }
    private var isERGActive: Bool {
        if case .erg = trainerMode { return true }
        return false
    }
    private var isResistanceActive: Bool {
        if case .resistance = trainerMode { return true }
        return false
    }

    private func gradeColor(for grade: Double) -> Color {
        let abs = Swift.abs(grade)
        if abs < 2 { return AppColor.success }
        if abs < 5 { return AppColor.yellow }
        if abs < 8 { return AppColor.orange }
        return AppColor.red
    }

    var body: some View {
        VStack(spacing: condensed ? 6 : 10) {
            if !condensed {
                // Header row
                HStack(spacing: 6) {
                    Image(systemName: "gearshape.2.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(
                            trainerMode.isActive ? AppColor.success : .white.opacity(0.3))
                    Text("TRAINER CONTROL")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.3))
                        .tracking(1.0)
                    Spacer()

                    Text(trainerMode.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(
                            trainerMode.isActive ? AppColor.success : .white.opacity(0.35)
                        )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            (trainerMode.isActive ? AppColor.success : Color.white).opacity(0.08)
                        )
                        .clipShape(Capsule())
                }
            }

            // Simulation grade display
            if case .simulation(let grade) = trainerMode {
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: grade >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: condensed ? 11 : 12, weight: .bold))
                            .foregroundStyle(gradeColor(for: grade))
                        Text(String(format: "%.1f%%", grade))
                            .font(
                                .system(
                                    size: condensed ? 18 : 22, weight: .bold, design: .monospaced)
                            )
                            .foregroundStyle(gradeColor(for: grade))
                    }
                    Spacer()
                    if let onDifficultyChange = onDifficultyChange {
                        compactStepper(
                            value: routeDifficultyScale,
                            step: 0.1,
                            minVal: 0.1,
                            maxVal: 2.0,
                            action: onDifficultyChange
                        )
                    }
                }
            }

            // ERG display
            if case .erg(let watts) = trainerMode {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(AppColor.orange)
                    Text("TARGET")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.3))
                        .tracking(1)
                    Text("\(watts)W")
                        .font(
                            .system(size: condensed ? 17 : 20, weight: .bold, design: .monospaced)
                        )
                        .foregroundStyle(AppColor.orange)
                    Spacer()
                    if let onIntensityChange = onIntensityChange {
                        compactStepper(
                            value: intensityMultiplier,
                            step: 0.05,
                            minVal: 0.5,
                            maxVal: 1.5,
                            action: onIntensityChange
                        )
                    }
                }
            }

            // Quick buttons
            if isWorkoutActive {
                HStack(spacing: condensed ? 6 : 8) {
                    if supportsSimulation && hasRoute {
                        trainerButton(
                            "Route", icon: "map.fill", isActive: isRouteSimActive,
                            action: onRouteSim, condensed: condensed)
                    }
                    if supportsERG {
                        trainerButton(
                            "ERG", icon: "lock.fill", isActive: isERGActive, action: onERG,
                            condensed: condensed)
                    }
                    if supportsResistance {
                        trainerButton(
                            "Resist", icon: "dial.medium.fill", isActive: isResistanceActive,
                            action: onResistance, condensed: condensed)
                    }
                    if trainerMode.isActive {
                        trainerButton(
                            "Free", icon: "figure.outdoor.cycle", isActive: false,
                            action: onFreeRide, condensed: condensed)
                    }
                }
            }

            if condensed {
                switch trainerMode {
                case .simulation, .erg:
                    EmptyView()
                default:
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape.2.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(
                                trainerMode.isActive ? AppColor.success : .white.opacity(0.25))
                        Text(trainerMode.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(
                                trainerMode.isActive ? AppColor.success : .white.opacity(0.35))
                        Spacer()
                    }
                }
            }

            if supportsSimulation, !hasRoute, isWorkoutActive, showRouteSimulationFooterHint,
                !condensed
            {
                Text(IndoorDashboardL10n.trainerRouteSimFooter)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.28))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, condensed ? 10 : 12)
        .padding(
            .vertical,
            supportsSimulation && !hasRoute && isWorkoutActive && showRouteSimulationFooterHint
                && !condensed ? 10 : (condensed ? 8 : 12)
        )
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    trainerMode.isActive
                        ? AppColor.success.opacity(0.15) : Color.white.opacity(0.06),
                    lineWidth: 1
                )
        )
        .animation(.easeInOut(duration: 0.3), value: trainerMode.label)
    }

    @ViewBuilder
    private func compactStepper(
        value: Double,
        step: Double,
        minVal: Double,
        maxVal: Double,
        action: @escaping (Double) -> Void
    ) -> some View {
        HStack(spacing: 6) {
            Button {
                action(max(minVal, value - step))
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Text("\(Int(round(value * 100)))%")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
                .frame(minWidth: 40)
                .multilineTextAlignment(.center)

            Button {
                action(min(maxVal, value + step))
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private func trainerButton(
        _ label: String,
        icon: String,
        isActive: Bool,
        action: @escaping () -> Void,
        condensed: Bool = false
    ) -> some View {
        Button(action: action) {
            VStack(spacing: condensed ? 2 : 4) {
                Image(systemName: icon)
                    .font(.system(size: condensed ? 10 : 11))
                Text(label)
                    .font(.system(size: condensed ? 9 : 10, weight: .semibold))
                    .tracking(0.5)
            }
            .foregroundStyle(isActive ? AppColor.success : .white.opacity(0.5))
            .frame(maxWidth: .infinity)
            .padding(.vertical, condensed ? 6 : 8)
            .background((isActive ? AppColor.success : Color.white).opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isActive ? AppColor.success.opacity(0.3) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Guided Session Card

struct GuidedSessionCard: View {
    let session: GuidedSessionManager
    /// Shorter layout for portrait single-screen fits (drops up-next and stats bar).
    var condensed: Bool = false

    private func guidedZoneColor(_ zone: TrainingZoneTarget) -> Color { zone.color }

    private var complianceColor: Color {
        switch session.compliance {
        case .inZone: return AppColor.success
        case .belowZone: return AppColor.yellow
        case .aboveZone: return AppColor.red
        }
    }

    private func gradeColor(for grade: Double) -> Color {
        let abs = Swift.abs(grade)
        if abs < 2 { return AppColor.success }
        if abs < 5 { return AppColor.yellow }
        if abs < 8 { return AppColor.orange }
        return AppColor.red
    }

    private var borderColor: Color {
        if let step = session.currentStep {
            return guidedZoneColor(step.zone).opacity(0.2)
        }
        return AppColor.mango.opacity(0.15)
    }

    var body: some View {
        Group {
            if condensed {
                condensedStepContent
            } else {
                VStack(spacing: 0) {
                    currentStepContent
                    upNextPreview
                    sessionStatsBar
                }
            }
        }
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: condensed ? 12 : 14))
        .overlay(
            RoundedRectangle(cornerRadius: condensed ? 12 : 14)
                .strokeBorder(borderColor, lineWidth: condensed ? 1 : 1.5)
        )
        .animation(.easeInOut(duration: 0.3), value: session.currentStepIndex)
    }

    @ViewBuilder
    private var condensedStepContent: some View {
        if let step = session.currentStep {
            activeStepCondensed(step)
        } else if session.isPastPlan {
            pastPlanCondensed
        } else if !session.hasIntervals {
            steadyStateCondensed
        }
    }

    private func activeStepCondensed(_ step: TimelineStep) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(step.label)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                Text(GuidedSessionManager.formatCountdown(session.stepSecondsRemaining))
                    .font(.system(size: 22, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text(step.zone.label)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(guidedZoneColor(step.zone))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(guidedZoneColor(step.zone).opacity(0.15))
                    .clipShape(Capsule())
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.06))
                    Capsule()
                        .fill(guidedZoneColor(step.zone))
                        .frame(width: max(0, geo.size.width * session.stepProgress))
                        .animation(.easeInOut(duration: 0.5), value: session.stepProgress)
                }
            }
            .frame(height: 4)
            .clipShape(Capsule())

            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: session.compliance.icon)
                        .font(.system(size: 10))
                        .foregroundStyle(complianceColor)
                    Text(session.compliance.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(complianceColor)
                }
                if let range = session.scaledTargetWattRange(for: step) {
                    Text("\(range.lowerBound)–\(range.upperBound) W")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(guidedZoneColor(step.zone))
                }
                Spacer(minLength: 0)
            }
        }
        .padding(10)
    }

    private var pastPlanCondensed: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 16))
                .foregroundStyle(AppColor.success)
            VStack(alignment: .leading, spacing: 2) {
                Text("Workout Complete!")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                Text("Free riding — end when ready")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(10)
    }

    private var steadyStateCondensed: some View {
        HStack(spacing: 8) {
            Image(systemName: "figure.indoor.cycle")
                .font(.system(size: 14))
                .foregroundStyle(AppColor.success)
            Text(session.dayTitle)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
        }
        .padding(10)
    }

    @ViewBuilder
    private var currentStepContent: some View {
        if let step = session.currentStep {
            activeStepView(step)
        } else if session.isPastPlan {
            pastPlanView
        } else if !session.hasIntervals {
            steadyStateView
        }
    }

    private func activeStepView(_ step: TimelineStep) -> some View {
        VStack(spacing: 10) {
            // Top row
            HStack(spacing: 8) {
                Text(step.label)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                Text(step.zone.label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(guidedZoneColor(step.zone))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(guidedZoneColor(step.zone).opacity(0.15))
                    .clipShape(Capsule())
                HStack(spacing: 3) {
                    Image(systemName: step.suggestedTrainerMode.icon)
                        .font(.system(size: 10))
                    Text(step.suggestedTrainerMode.label)
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(AppColor.success.opacity(0.8))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(AppColor.success.opacity(0.1))
                .clipShape(Capsule())
            }

            // Countdown + targets
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("REMAINING")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.25))
                    Text(GuidedSessionManager.formatCountdown(session.stepSecondsRemaining))
                        .font(.system(size: 32, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.3), value: session.stepSecondsRemaining)
                }
                Spacer()
                if let range = session.scaledTargetWattRange(for: step) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("TARGET")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.25))
                        Text("\(range.lowerBound)–\(range.upperBound)")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundStyle(guidedZoneColor(step.zone))
                        Text("watts")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.25))
                    }
                }
                if let low = step.cadenceLow, let high = step.cadenceHigh {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("CADENCE")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.25))
                        Text("\(low)–\(high)")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppColor.blue)
                        Text("rpm")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.25))
                    }
                }
            }

            // Step progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.06))
                    Capsule()
                        .fill(guidedZoneColor(step.zone))
                        .frame(width: max(0, geo.size.width * session.stepProgress))
                        .animation(.easeInOut(duration: 0.5), value: session.stepProgress)
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())

            // Compliance row
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: session.compliance.icon)
                        .font(.system(size: 11))
                        .foregroundStyle(complianceColor)
                    Text(session.compliance.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(complianceColor)
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "target")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.3))
                    Text(String(format: "%.0f%% in zone", session.stepInZonePercent))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                }
                if step.suggestedTrainerMode == .simulation, let grade = step.simulationGrade {
                    HStack(spacing: 3) {
                        Image(systemName: "mountain.2.fill")
                            .font(.system(size: 9))
                        Text(String(format: "%.1f%%", grade))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(gradeColor(for: grade))
                }
            }

            // Motivational message
            Text(session.motivationalMessage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.7))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.3), value: session.motivationalMessage)
        }
        .padding(14)
    }

    private var pastPlanView: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 18))
                .foregroundStyle(AppColor.success)
            VStack(alignment: .leading, spacing: 2) {
                Text("Workout Complete!")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                Text("Free riding — keep going or end when ready")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.0f%%", session.totalInZonePercent))
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppColor.success)
                Text("in zone")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .padding(14)
    }

    private var steadyStateView: some View {
        HStack(spacing: 10) {
            Image(systemName: "figure.indoor.cycle")
                .font(.system(size: 16))
                .foregroundStyle(AppColor.success)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.dayTitle)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                Text(session.dayNotes)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(14)
    }

    @ViewBuilder
    private var upNextPreview: some View {
        if let next = session.nextStep {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            HStack(spacing: 8) {
                Text("UP NEXT")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.25))
                    .tracking(1.0)
                Circle()
                    .fill(guidedZoneColor(next.zone))
                    .frame(width: 6, height: 6)
                Text(next.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                Spacer()
                Text(GuidedSessionManager.formatCountdown(next.durationSeconds))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
                Text(next.zone.label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(guidedZoneColor(next.zone).opacity(0.7))
                Text(next.suggestedTrainerMode.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var sessionStatsBar: some View {
        if session.hasIntervals {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            HStack(spacing: 0) {
                guidedStatPill(
                    label: "OVERALL",
                    value: String(format: "%.0f%%", session.overallProgress * 100))
                guidedStatPill(
                    label: "IN ZONE",
                    value: String(format: "%.0f%%", session.totalInZonePercent))
                guidedStatPill(
                    label: "ELAPSED",
                    value: GuidedSessionManager.formatCountdown(session.elapsedSeconds))
                guidedStatPill(
                    label: "REMAINING",
                    value: GuidedSessionManager.formatCountdown(
                        max(0, session.totalPlannedSeconds - session.elapsedSeconds)
                    )
                )
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
        }
    }

    private func guidedStatPill(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.2))
                .tracking(1.0)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
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
                            .font(.system(size: heroFontSize, weight: .black, design: .monospaced))
                            .foregroundStyle(zone.color)
                            .contentTransition(.numericText())
                            .lineLimit(1)
                            .minimumScaleFactor(0.42)
                        Text("W")
                            .font(.system(size: secondaryFontSize, weight: .medium))
                            .foregroundStyle(.white.opacity(0.3))
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(AppOpacity.cardBorder))
                        Capsule()
                            .fill(zone.color)
                            .scaleEffect(
                                x: min(Double(smoothedWatts) / 500.0, 1.0), y: 1, anchor: .leading
                            )
                            .animation(.easeOut(duration: 0.35), value: smoothedWatts)
                    }
                    .frame(height: max(3, progressBarHeight))
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                // Zone info — capped width so the hero always wins the remaining width budget.
                VStack(alignment: .trailing, spacing: 5) {
                    HStack(alignment: .center, spacing: 6) {
                        Text(zone.name.uppercased())
                            .font(.system(size: zoneNameFontSize, weight: .bold))
                            .foregroundStyle(zone.color)
                            .tracking(0.5)
                            .lineLimit(avg3s != nil ? 1 : 2)
                            .minimumScaleFactor(0.72)
                            .multilineTextAlignment(.trailing)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .trailing)
                        if let s = avg3s {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("3s")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.38))
                                Text("\(Int(s))")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundStyle(PowerZone.zone(for: Int(s)).color)
                                Text("W")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.28))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(pctFTP)")
                            .font(.system(size: ftpFontSize, weight: .bold, design: .monospaced))
                            .foregroundStyle(zone.color.opacity(0.85))
                            .contentTransition(.numericText())
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("%")
                            .font(.system(size: pctUnitFontSize, weight: .medium))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    Text(powerZoneRangeText)
                        .font(.system(size: rangeFontSize, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .frame(
                    width: avg3s != nil ? zoneColumnWidthWithPill : zoneColumnWidth,
                    alignment: .trailing
                )
                .layoutPriority(0)
            }
        }
        .padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.25), value: zone.id)
    }
}

// MARK: - Reduce Transparency (header chrome)

struct IndoorHeaderBarChrome: ViewModifier {
    let reduceTransparency: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(red: 0.04, green: 0.05, blue: 0.08))
        } else {
            content.glassEffect(.regular, in: .rect(cornerRadius: 0))
        }
    }
}

struct IndoorGlassOrOpaqueCircle: ViewModifier {
    let useOpaque: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if useOpaque {
            content.background(Circle().fill(Color.white.opacity(0.12)))
        } else {
            content.glassEffect(.regular.interactive(), in: .circle)
        }
    }
}

struct IndoorMilestoneToastChrome: ViewModifier {
    let reduceTransparency: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Capsule().fill(Color(red: 0.08, green: 0.09, blue: 0.12)))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
        } else {
            content.glassEffect(.regular, in: .capsule)
        }
    }
}

#Preview("Free Ride") {
    let ble = BLEManager()
    let wifi = WiFiTrainerService()
    let ds = DataSourceCoordinator(bleManager: ble, wifiService: wifi)
    return DashboardView(
        navigationPath: .constant(NavigationPath())
    )
    .modelContainer(
        for: [
            Workout.self, WorkoutSample.self, LapSplit.self, TrainingPlanProgress.self,
            CustomWorkoutTemplate.self,
        ],
        inMemory: true
    )
    .environment(ble)
    .environment(ds)
    .environment(RouteManager())
    .environment(HealthKitManager())
    .environment(FTPRefreshTrigger.shared)
}

#Preview("Guided Session") {
    let ble = BLEManager()
    let wifi = WiFiTrainerService()
    let ds = DataSourceCoordinator(bleManager: ble, wifiService: wifi)
    return DashboardView(
        navigationPath: .constant(NavigationPath()),
        planDayID: "w2d2"
    )
    .modelContainer(
        for: [
            Workout.self, WorkoutSample.self, LapSplit.self, TrainingPlanProgress.self,
            CustomWorkoutTemplate.self,
        ],
        inMemory: true
    )
    .environment(ble)
    .environment(ds)
    .environment(RouteManager())
    .environment(HealthKitManager())
    .environment(FTPRefreshTrigger.shared)
}

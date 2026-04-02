import SwiftUI
import SwiftData

/// Performance Management Chart (PMC) showing CTL, ATL, and TSB over time.
/// The industry-standard training load visualization.
struct PMChartView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var navigationPath: NavigationPath

    private static let pmcWorkoutsDescriptor: FetchDescriptor<Workout> = {
        var d = FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        d.fetchLimit = 600
        return d
    }()

    @Query(PMChartView.pmcWorkoutsDescriptor) private var allWorkouts: [Workout]

    @State private var pmcData: [PMCPoint] = []
    @State private var rangeDays: Int = 90
    @State private var showCTL = true
    @State private var showATL = true
    @State private var showTSB = true

    private let rangeOptions = [30, 60, 90, 180, 365]

    var body: some View {
        ZStack {
            AppColor.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 16)

                    // Training load hero card — overlaps chart
                    if let latest = pmcData.last {
                        trainingLoadHero(latest)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                    }

                    // Range selector
                    HStack(spacing: 6) {
                        ForEach(rangeOptions, id: \.self) { days in
                            Button("\(days)d") {
                                rangeDays = days
                                rebuild()
                            }
                            .font(.system(size: 12, weight: days == rangeDays ? .bold : .medium))
                            .foregroundStyle(days == rangeDays ? AppColor.mango : .white.opacity(0.4))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(days == rangeDays ? AppColor.mango.opacity(0.12) : Color.clear)
                            .clipShape(Capsule())
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

                    // Legend
                    HStack(spacing: 16) {
                        legendItem(label: "Fitness", color: AppColor.blue, isOn: $showCTL)
                        legendItem(label: "Fatigue", color: AppColor.red, isOn: $showATL)
                        legendItem(label: "Form", color: AppColor.success, isOn: $showTSB)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                    // Chart
                    if pmcData.isEmpty {
                        emptyState
                    } else {
                        pmcChart
                            .padding(.horizontal, 16)
                    }

                    // CTL / ATL / TSB breakdown
                    if let latest = pmcData.last {
                        metricStrip(latest)
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                    }

                    Spacer(minLength: 40)
                }
            }
            .scrollIndicators(.hidden)
        }
        .navigationBarBackButtonHidden()
        .task {
            rebuild()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Text("Training Load")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)

            Spacer()
        }
    }

    // MARK: - Training Load Hero Card

    private func trainingLoadHero(_ latest: PMCPoint) -> some View {
        let tsb = latest.tsb
        let status: String
        let statusColor: Color
        let statusIcon: String
        let advice: String

        if tsb > 25 {
            status = "Very Fresh"
            statusColor = AppColor.blue
            statusIcon = "bolt.fill"
            advice = "High form — ready for a hard session or race."
        } else if tsb > 5 {
            status = "Fresh"
            statusColor = AppColor.success
            statusIcon = "checkmark.seal.fill"
            advice = "Good form — ideal for intensity work."
        } else if tsb > -10 {
            status = "Neutral"
            statusColor = AppColor.yellow
            statusIcon = "equal.circle.fill"
            advice = "Balanced fitness and fatigue."
        } else if tsb > -30 {
            status = "Fatigued"
            statusColor = AppColor.orange
            statusIcon = "flame.fill"
            advice = "Consider an easy day or rest."
        } else {
            status = "Overreached"
            statusColor = AppColor.red
            statusIcon = "exclamationmark.triangle.fill"
            advice = "Recovery needed to avoid overtraining."
        }

        return VStack(spacing: 0) {
            // Top section: big TSB number + status
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: statusIcon)
                            .font(.system(size: 13))
                            .foregroundStyle(statusColor)
                        Text(status.uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(statusColor)
                            .tracking(1.0)
                    }

                    Text(advice)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(2)
                }

                Spacer()

                // Big TSB number
                VStack(alignment: .trailing, spacing: 2) {
                    Text("FORM")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.25))
                        .tracking(1.0)
                    Text(String(format: "%.0f", tsb))
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .foregroundStyle(statusColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            // Mini sparkline showing recent TSB trend
            if pmcData.count > 7 {
                let recentTSB = Array(pmcData.suffix(min(30, pmcData.count)).map(\.tsb))
                miniSparkline(values: recentTSB, color: statusColor)
                    .frame(height: 32)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
        }
        .background(statusColor.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(statusColor.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Mini Sparkline

    private func miniSparkline(values: [Double], color: Color) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let minV = values.min() ?? 0
            let maxV = values.max() ?? 1
            let range = max(maxV - minV, 1)

            // Zero line
            let zeroY = h * (1 - CGFloat((0 - minV) / range))

            Path { p in
                p.move(to: CGPoint(x: 0, y: zeroY))
                p.addLine(to: CGPoint(x: w, y: zeroY))
            }
            .stroke(Color.white.opacity(0.06), lineWidth: 1)

            // Sparkline
            Path { p in
                for (i, val) in values.enumerated() {
                    let x = w * CGFloat(i) / CGFloat(max(values.count - 1, 1))
                    let y = h * (1 - CGFloat((val - minV) / range))
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                    else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(color.opacity(0.6), lineWidth: 1.5)

            // Gradient fill under sparkline
            Path { p in
                for (i, val) in values.enumerated() {
                    let x = w * CGFloat(i) / CGFloat(max(values.count - 1, 1))
                    let y = h * (1 - CGFloat((val - minV) / range))
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                    else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
                p.addLine(to: CGPoint(x: w, y: h))
                p.addLine(to: CGPoint(x: 0, y: h))
                p.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [color.opacity(0.15), color.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    // MARK: - Metric Strip

    private func metricStrip(_ latest: PMCPoint) -> some View {
        let tsb = latest.tsb
        let statusColor: Color = if tsb > 25 {
            AppColor.blue
        } else if tsb > 5 {
            AppColor.success
        } else if tsb > -10 {
            AppColor.yellow
        } else if tsb > -30 {
            AppColor.orange
        } else {
            AppColor.red
        }

        return HStack(spacing: 0) {
            pmcStat(label: "CTL", subtitle: "Fitness", value: String(format: "%.0f", latest.ctl), color: AppColor.blue)
            Divider()
                .frame(height: 28)
                .overlay(Color.white.opacity(0.06))
            pmcStat(label: "ATL", subtitle: "Fatigue", value: String(format: "%.0f", latest.atl), color: AppColor.red)
            Divider()
                .frame(height: 28)
                .overlay(Color.white.opacity(0.06))
            pmcStat(label: "TSB", subtitle: "Form", value: String(format: "%.0f", latest.tsb), color: statusColor)
        }
        .padding(.vertical, 12)
        .cardStyle()
    }

    // MARK: - Legend

    private func legendItem(label: String, color: Color, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(isOn.wrappedValue ? color : Color.white.opacity(0.15))
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isOn.wrappedValue ? .white.opacity(0.5) : .white.opacity(0.2))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.15))
            Text("Not enough data yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
            Text("Complete a few rides to see your training load trends.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.25))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Chart

    private var pmcChart: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let padding: CGFloat = 40 // left axis labels
            let chartWidth = width - padding
            let chartHeight = height

            // Find data range in a single pass — avoids 3× .map() + array concat
            let dataRange = Self.computeDataRange(pmcData)
            let maxVal = dataRange.maxVal
            let tsbMin = dataRange.tsbMin
            let tsbMax = dataRange.tsbMax

            ZStack(alignment: .leading) {
                // Background grid
                ForEach(0..<5) { i in
                    let y = chartHeight * CGFloat(i) / 4
                    Path { p in
                        p.move(to: CGPoint(x: padding, y: y))
                        p.addLine(to: CGPoint(x: width, y: y))
                    }
                    .stroke(Color.white.opacity(0.04), lineWidth: 1)
                }

                // TSB zone shading
                if showTSB {
                    // Green zone (TSB > 0 = fresh)
                    if let zeroY = tsbToY(0, tsbMin: tsbMin, tsbMax: tsbMax, chartHeight: chartHeight) {
                        Path { p in
                            p.addRect(CGRect(x: padding, y: 0, width: chartWidth, height: zeroY))
                        }
                        .fill(AppColor.success.opacity(0.03))

                        // Red zone (TSB < 0 = fatigued)
                        Path { p in
                            p.addRect(CGRect(x: padding, y: zeroY, width: chartWidth, height: chartHeight - zeroY))
                        }
                        .fill(AppColor.red.opacity(0.03))
                    }
                }

                // CTL line
                if showCTL {
                    pmcLine(values: pmcData.map(\.ctl), color: AppColor.blue, maxVal: maxVal, chartWidth: chartWidth, chartHeight: chartHeight, padding: padding)
                }

                // ATL line
                if showATL {
                    pmcLine(values: pmcData.map(\.atl), color: AppColor.red, maxVal: maxVal, chartWidth: chartWidth, chartHeight: chartHeight, padding: padding)
                }

                // TSB line
                if showTSB {
                    pmcLine(values: pmcData.map(\.tsb), color: AppColor.success, maxVal: tsbMax, minVal: tsbMin, chartWidth: chartWidth, chartHeight: chartHeight, padding: padding, isTSB: true)
                }

                // Y-axis labels
                VStack {
                    Text("\(Int(maxVal))")
                    Spacer()
                    Text("0")
                    Spacer()
                    Text("0")
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.2))
                .frame(width: padding - 4, height: chartHeight)
            }
        }
        .frame(height: 220)
    }

    private func pmcLine(values: [Double], color: Color, maxVal: Double, minVal: Double = 0, chartWidth: CGFloat, chartHeight: CGFloat, padding: CGFloat, isTSB: Bool = false) -> some View {
        Path { path in
            guard !values.isEmpty else { return }
            let stepX = chartWidth / CGFloat(max(values.count - 1, 1))

            for (i, value) in values.enumerated() {
                let x = padding + CGFloat(i) * stepX
                let normalized = isTSB
                    ? (value - minVal) / (maxVal - minVal)
                    : value / maxVal
                let y = chartHeight * (1 - CGFloat(normalized))

                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
        .stroke(color, lineWidth: 2)
        .opacity(0.7)
    }

    private func tsbToY(_ tsb: Double, tsbMin: Double, tsbMax: Double, chartHeight: CGFloat) -> CGFloat? {
        let normalized = (tsb - tsbMin) / (tsbMax - tsbMin)
        return chartHeight * (1 - CGFloat(normalized))
    }

    // MARK: - PMC Stat

    private func pmcStat(label: String, subtitle: String, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.25))
                .tracking(0.8)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Computation

    private static func computeDataRange(_ data: [PMCPoint]) -> (maxVal: Double, tsbMin: Double, tsbMax: Double) {
        var ctlMax = -Double.greatestFiniteMagnitude
        var atlMax = -Double.greatestFiniteMagnitude
        var tsbMin = Double.greatestFiniteMagnitude
        var tsbMax = -Double.greatestFiniteMagnitude
        for pt in data {
            if pt.ctl > ctlMax { ctlMax = pt.ctl }
            if pt.atl > atlMax { atlMax = pt.atl }
            if pt.tsb < tsbMin { tsbMin = pt.tsb }
            if pt.tsb > tsbMax { tsbMax = pt.tsb }
        }
        return (
            maxVal: max(max(ctlMax, atlMax) * 1.1, 50),
            tsbMin: min(tsbMin * 1.2, -10),
            tsbMax: max(tsbMax * 1.2, 50)
        )
    }

    private func rebuild() {
        guard !allWorkouts.isEmpty else {
            pmcData = []
            return
        }

        let today = Calendar.current.startOfDay(for: Date())
        guard let startDate = Calendar.current.date(byAdding: .day, value: -rangeDays, to: today) else { return }

        // Build daily TSS map
        var tssByDay: [Date: Double] = [:]
        for workout in allWorkouts {
            let day = Calendar.current.startOfDay(for: workout.startDate)
            tssByDay[day, default: 0] += workout.tss
        }

        // Seed CTL/ATL from 42-day and 7-day decay of known TSS
        // Use exponential moving average approach
        let ctlConstant = 42.0
        let atlConstant = 7.0
        var ctl = 0.0
        var atl = 0.0

        var points: [PMCPoint] = []
        var currentDate = startDate

        while currentDate <= today {
            let dayTSS = tssByDay[currentDate] ?? 0
            ctl = ctl + (dayTSS - ctl) / ctlConstant
            atl = atl + (dayTSS - atl) / atlConstant

            points.append(PMCPoint(
                date: currentDate,
                ctl: ctl,
                atl: atl,
                tsb: ctl - atl
            ))

            currentDate = Calendar.current.date(byAdding: .day, value: 1, to: currentDate)!
        }

        pmcData = points
    }
}

// MARK: - PMC Point

private struct PMCPoint: Identifiable {
    let date: Date
    let ctl: Double
    let atl: Double
    let tsb: Double

    var id: Date { date }
}

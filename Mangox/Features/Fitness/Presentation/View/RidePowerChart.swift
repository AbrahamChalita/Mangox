import SwiftUI

/// Power chart for the post-ride summary.
/// Plots per-second power as a filled area chart with zone-colored segments.
struct RidePowerChart: View {
    let samples: [WorkoutSample]

    @State private var selectedIndex: Int?
    @State private var normalizedSamples: [NormalizedSamplePoint] = []
    @State private var peakPower: Int = 0

    private struct NormalizedSamplePoint {
        let x: CGFloat
        let y: CGFloat
        let power: Int
        let elapsed: Int
        let zoneColor: Color
    }

    private struct ChartCacheKey: Equatable {
        let count: Int
        let firstElapsed: Int
        let lastElapsed: Int
        let lastPower: Int
    }

    private var selectedSample: WorkoutSample? {
        guard let selectedIndex else { return nil }
        return samples[safe: selectedIndex]
    }

    private var selectedPoint: NormalizedSamplePoint? {
        guard let selectedIndex else { return nil }
        return normalizedSamples[safe: selectedIndex]
    }

    private var chartCacheKey: ChartCacheKey {
        ChartCacheKey(
            count: samples.count,
            firstElapsed: samples.first?.elapsedSeconds ?? 0,
            lastElapsed: samples.last?.elapsedSeconds ?? 0,
            lastPower: samples.last?.power ?? 0
        )
    }

    private func rebuildChartData() {
        guard !samples.isEmpty else {
            normalizedSamples = []
            peakPower = 0
            selectedIndex = nil
            return
        }

        let maxPower = max(samples.map(\.power).max() ?? 0, 1)
        peakPower = maxPower
        normalizedSamples = samples.enumerated().map { index, sample in
            let x = CGFloat(index) / CGFloat(max(samples.count - 1, 1))
            let y = 1.0 - CGFloat(sample.power) / CGFloat(maxPower)
            return NormalizedSamplePoint(
                x: x,
                y: y,
                power: sample.power,
                elapsed: sample.elapsedSeconds,
                zoneColor: PowerZone.zone(for: sample.power).color
            )
        }

        if let selectedIndex, !samples.indices.contains(selectedIndex) {
            self.selectedIndex = nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
                Text("POWER")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.35))
                    .tracking(1.5)
                Spacer()

                if let selected = selectedSample {
                    HStack(spacing: 4) {
                        Text("\(selected.power)W")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(selectedPoint?.zoneColor ?? PowerZone.zone(for: selected.power).color)
                        Text(AppFormat.duration(Double(selected.elapsedSeconds)))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                } else {
                    Text("Peak: \(peakPower)W")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }

            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height

                ZStack(alignment: .topLeading) {
                    // Zone-colored area fill — single Canvas pass instead of 3600+ Path views
                    if !normalizedSamples.isEmpty {
                        Canvas { context, size in
                            let rectWidth = max(1, size.width / CGFloat(normalizedSamples.count))
                            for pt in normalizedSamples {
                                let xPos = pt.x * size.width
                                let yPos = pt.y * size.height
                                let rect = CGRect(x: xPos, y: yPos, width: rectWidth, height: size.height - yPos)
                                context.fill(
                                    Path(rect),
                                    with: .color(pt.zoneColor.opacity(0.25))
                                )
                            }
                        }

                        // Smoothed line overlay
                        Path { path in
                            for (i, pt) in normalizedSamples.enumerated() {
                                let x = pt.x * width
                                let y = pt.y * height
                                if i == 0 {
                                    path.move(to: CGPoint(x: x, y: y))
                                } else {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                            }
                        }
                        .stroke(Color.white.opacity(0.6), lineWidth: 1.5)
                    }

                    // Touch interaction
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard !samples.isEmpty, width > 0 else { return }
                                    let clampedX = min(max(value.location.x, 0), width)
                                    let fraction = clampedX / width
                                    let rawIndex = Int(fraction * CGFloat(max(samples.count - 1, 1)))
                                    selectedIndex = min(max(rawIndex, 0), samples.count - 1)
                                }
                                .onEnded { _ in
                                    selectedIndex = nil
                                }
                        )

                    // Selection indicator
                    if let selectedPoint {
                        let x = selectedPoint.x * width
                        let y = selectedPoint.y * height

                        Path { path in
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: height))
                        }
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)

                        Circle()
                            .fill(selectedPoint.zoneColor)
                            .frame(width: 8, height: 8)
                            .position(x: x, y: y)
                    }
                }
            }
            .frame(height: 140)
        }
        .padding(14)
        .cardStyle()
        .onAppear(perform: rebuildChartData)
        .onChange(of: chartCacheKey) { _, _ in
            rebuildChartData()
        }
    }
}

// MARK: - Safe Array Index

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

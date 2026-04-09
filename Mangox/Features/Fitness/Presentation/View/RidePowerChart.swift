import SwiftUI

/// Power chart for the post-ride summary.
/// Plots per-second power as a filled area chart with zone-colored segments.
struct RidePowerChart: View {
    let samples: [WorkoutSample]

    @State private var selectedSample: WorkoutSample?

    private var normalizedSamples: [(x: CGFloat, y: CGFloat, power: Int, elapsed: Int)] {
        guard !samples.isEmpty else { return [] }
        let maxPower = max(samples.map(\.power).max() ?? 1, 1)
        return samples.enumerated().map { index, sample in
            let x = CGFloat(index) / CGFloat(max(samples.count - 1, 1))
            let y = 1.0 - CGFloat(sample.power) / CGFloat(maxPower)
            return (x: x, y: y, power: sample.power, elapsed: sample.elapsedSeconds)
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
                            .foregroundStyle(PowerZone.zone(for: selected.power).color)
                        Text(AppFormat.duration(Double(selected.elapsedSeconds)))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                } else {
                    let maxPower = samples.map(\.power).max() ?? 0
                    Text("Peak: \(maxPower)W")
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
                                let zoneColor = PowerZone.zone(for: pt.power).color
                                let xPos = pt.x * size.width
                                let yPos = pt.y * size.height
                                let rect = CGRect(x: xPos, y: yPos, width: rectWidth, height: size.height - yPos)
                                context.fill(
                                    Path(rect),
                                    with: .color(zoneColor.opacity(0.25))
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
                                    let fraction = value.location.x / width
                                    let index = Int(fraction * CGFloat(max(samples.count - 1, 1)))
                                    selectedSample = samples[safe: index]
                                }
                                .onEnded { _ in
                                    selectedSample = nil
                                }
                        )

                    // Selection indicator
                    if let selected = selectedSample,
                       let index = samples.firstIndex(where: { $0.id == selected.id }) {
                        let fraction = CGFloat(index) / CGFloat(max(samples.count - 1, 1))
                        let x = fraction * width
                        let pt = normalizedSamples[safe: index]
                        let y = (pt?.y ?? 0.5) * height

                        Path { path in
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: height))
                        }
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)

                        Circle()
                            .fill(PowerZone.zone(for: selected.power).color)
                            .frame(width: 8, height: 8)
                            .position(x: x, y: y)
                    }
                }
            }
            .frame(height: 140)
        }
        .padding(14)
        .cardStyle()
    }
}

// MARK: - Safe Array Index

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

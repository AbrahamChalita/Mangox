import SwiftUI

struct HeartRateBarView: View {
    let heartRate: Int
    var compact: Bool = false

    private var maxHR: Int {
        HeartRateZone.maxHR
    }

    private var pct: Double {
        guard maxHR > 0 else { return 0 }
        return Double(heartRate) / Double(maxHR)
    }

    private var zone: HeartRateZone {
        HeartRateZone.zone(for: heartRate)
    }

    private var pctReserve: Double? {
        HeartRateZone.percentOfReserve(bpm: heartRate)
    }

    private var subtitle: String {
        var parts: [String] = []
        if HeartRateZone.hasRestingHR {
            parts.append("Rest \(HeartRateZone.restingHR)")
        }
        parts.append("Max \(maxHR)")
        if let pctR = pctReserve {
            parts.append("\(Int((pctR * 100).rounded()))% HRR")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        if compact {
            compactView
        } else {
            fullView
        }
    }

    // MARK: - Compact (phone single row)

    private var compactView: some View {
        HStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(heartRate)")
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(zone.color)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.3), value: heartRate)
                Text("bpm")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
            }

            Text(zone.name.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(zone.color)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(zone.bgColor)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(zone.color.opacity(0.2), lineWidth: 1))

            Spacer()

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(AppOpacity.cardBorder))
                    Capsule()
                        .fill(zone.color)
                        .frame(width: max(0, geo.size.width * min(pct, 1.0)))
                        .animation(.easeInOut(duration: 0.5), value: heartRate)
                }
            }
            .frame(width: 72, height: 4)

            Text("\(Int((pct * 100).rounded()))%")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .cardStyle(cornerRadius: 12)
    }

    // MARK: - Full (iPad)

    private var fullView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("HEART RATE")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.white.opacity(0.35))
                    .tracking(2)
                Spacer()
                Text("\(Int(pct * 100))% MAX")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(zone.color)
            }

            HStack(spacing: 10) {
                Text("\(heartRate)")
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .foregroundStyle(zone.color)

                Text("bpm")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.25))

                Spacer()

                Text(zone.name.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(zone.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(zone.bgColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(zone.color.opacity(0.3), lineWidth: 1)
                    )
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    HStack(spacing: 1) {
                        ForEach(HeartRateZone.zones) { z in
                            let segmentWidth = segmentFraction(for: z) * geo.size.width
                            RoundedRectangle(cornerRadius: 2)
                                .fill(z.color.opacity(0.15))
                                .frame(width: max(segmentWidth - 1, 0), height: 6)
                        }
                    }
                    RoundedRectangle(cornerRadius: 2)
                        .fill(zone.color)
                        .frame(width: geo.size.width * min(pct, 1.0), height: 6)
                        .animation(.easeInOut(duration: 0.5), value: heartRate)
                    Circle()
                        .fill(zone.color)
                        .frame(width: 10, height: 10)
                        .shadow(color: zone.color.opacity(0.6), radius: 4)
                        .offset(x: max(0, geo.size.width * min(pct, 1.0) - 5))
                        .animation(.easeInOut(duration: 0.5), value: heartRate)
                }
            }
            .frame(height: 10)

            Text(subtitle)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.25))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(AppOpacity.cardBorder), lineWidth: 1)
        )
    }

    private func segmentFraction(for zone: HeartRateZone) -> Double {
        let range = zone.percentMaxRange
        let low = Double(range.lowerBound) / Double(maxHR)
        let high = Double(range.upperBound) / Double(maxHR)
        return max(high - low, 0)
    }
}

#Preview {
    VStack(spacing: 16) {
        HeartRateBarView(heartRate: 152, compact: true)
        HeartRateBarView(heartRate: 152)
        HeartRateBarView(heartRate: 178)
    }
    .padding()
    .background(Color(red: 0.03, green: 0.04, blue: 0.06))
}

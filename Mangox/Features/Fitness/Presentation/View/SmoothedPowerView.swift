import SwiftUI

struct SmoothedPowerView: View {
    let avg3s: Double
    let avg5s: Double
    let avg30s: Double
    var compact: Bool = false

    var body: some View {
        if compact {
            HStack(spacing: 0) {
                compactItem(label: "3s", value: avg3s)
                    .cardStyle(cornerRadius: 10)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 8) {
                smoothedCard(label: "3s", value: avg3s)
                smoothedCard(label: "30s", value: avg30s)
            }
        }
    }

    private func compactItem(label: String, value: Double) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.38))
            Text("\(Int(value))")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(PowerZone.zone(for: Int(value)).color)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text("W")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.28))
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func smoothedCard(label: String, value: Double) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.35))
                .tracking(1)

            Text("\(Int(value))")
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(PowerZone.zone(for: Int(value)).color)

            Text("W")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .cardStyle(cornerRadius: 10)
    }
}

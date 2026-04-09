import SwiftUI

struct MetricCardView: View {
    let label: String
    let value: String
    let unit: String
    var valueColor: Color = .white
    var subtitle: String?

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var isPhone: Bool { sizeClass == .compact }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(1.5)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.system(size: isPhone ? 24 : 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Text(unit)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, isPhone ? 14 : 20)
        .padding(.vertical, isPhone ? 12 : 18)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value) \(unit)")
    }
}

#Preview {
    HStack {
        MetricCardView(label: "SPEED", value: "32.4", unit: "km/h")
        MetricCardView(label: "CADENCE", value: "88", unit: "rpm", valueColor: Color(red: 107/255, green: 127/255, blue: 212/255))
    }
    .padding()
    .background(Color(red: 0.03, green: 0.04, blue: 0.06))
}

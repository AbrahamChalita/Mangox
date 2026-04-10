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
        MangoxMetricCard(
            label: label,
            value: value,
            unit: unit,
            valueColor: valueColor,
            subtitle: subtitle,
            compact: isPhone
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

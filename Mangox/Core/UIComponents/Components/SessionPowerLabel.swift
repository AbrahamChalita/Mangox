import SwiftUI

/// Equatable hot-metric readout for live power values.
struct SessionPowerLabel: View, Equatable {
    let power: Int
    let unit: String
    var valueFont: Font = .body
    var unitFont: Font = .title3
    var unitColor: Color = AppColor.fg3

    static func == (lhs: SessionPowerLabel, rhs: SessionPowerLabel) -> Bool {
        lhs.power == rhs.power && lhs.unit == rhs.unit
    }

    var body: some View {
        let zone = PowerZone.zone(for: power)
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("\(power)")
                .font(valueFont)
                .foregroundStyle(zone.color)
                .contentTransition(.numericText())
            Text(unit)
                .font(unitFont)
                .foregroundStyle(unitColor)
        }
    }
}

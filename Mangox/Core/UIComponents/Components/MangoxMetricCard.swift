import SwiftUI

struct MangoxMetricCard: View {
    let label: String
    let value: String
    let unit: String
    var valueColor: Color = .white
    var subtitle: String?
    var compact: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .mangoxFont(.label)
                .foregroundStyle(AppColor.fg3)
                .tracking(1.4)
                .textCase(.uppercase)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font((compact ? MangoxFont.value : MangoxFont.largeValue).value)
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .monospacedDigit()

                Text(unit)
                    .mangoxFont(.micro)
                    .foregroundStyle(AppColor.fg2)
                    .tracking(0.8)
                    .textCase(.uppercase)
            }

            if let subtitle {
                Text(subtitle)
                    .mangoxFont(.micro)
                    .foregroundStyle(AppColor.fg3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, compact ? MangoxSpacing.lg.rawValue : MangoxSpacing.xl.rawValue)
        .padding(.vertical, compact ? MangoxSpacing.md.rawValue : MangoxSpacing.lg.rawValue)
        .mangoxSurface(.flat, shape: .rounded(MangoxRadius.card.rawValue))
    }
}

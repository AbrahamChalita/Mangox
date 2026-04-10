import SwiftUI

struct MangoxMetricCard: View {
    let label: String
    let value: String
    let unit: String
    var valueColor: Color = .white
    var subtitle: String?
    var compact: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .mangoxFont(.label)
                .foregroundStyle(.white.opacity(AppOpacity.textSecondary))
                .tracking(1.0)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.system(size: compact ? 24 : 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Text(unit)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(AppOpacity.textTertiary))
            }

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(AppOpacity.textQuaternary))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, compact ? 14 : 20)
        .padding(.vertical, compact ? 12 : 18)
        .mangoxSurface(.flat, shape: .rounded(MangoxRadius.card.rawValue))
    }
}

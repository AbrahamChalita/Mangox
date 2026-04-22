import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

private enum LapCardFontToken {
    static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let fontName: String
        switch weight {
        case .light:
            fontName = "GeistMono-Light"
        case .medium, .semibold, .bold, .heavy, .black:
            fontName = "GeistMono-Medium"
        default:
            fontName = "GeistMono-Regular"
        }

        #if canImport(UIKit)
            if UIFont(name: fontName, size: size) != nil {
                return .custom(fontName, size: size)
            }
        #endif
        return .system(size: size, weight: weight, design: .monospaced)
    }
}

struct LapCardView: View {
    let lapNumber: Int
    let currentAvgPower: Double
    let currentDuration: TimeInterval
    let previousAvgPower: Double
    let previousDuration: TimeInterval
    var compact: Bool = false

    var body: some View {
        if compact {
            compactBody
        } else {
            fullBody
        }
    }

    private var fullBody: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "flag.fill")
                        .mangoxFont(.micro)
                        .foregroundStyle(AppColor.blue)
                    Text("LAP \(lapNumber)")
                        .mangoxFont(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(AppColor.fg2)
                        .tracking(1)
                }
                Spacer()
            }

            HStack(spacing: 16) {
                // Current lap
                VStack(alignment: .leading, spacing: 3) {
                    Text("CURRENT")
                        .mangoxFont(.micro)
                        .fontWeight(.bold)
                        .foregroundStyle(AppColor.fg3)
                        .tracking(1)
                    HStack(spacing: 8) {
                        Text("\(Int(currentAvgPower))W")
                            .font(LapCardFontToken.mono(size: 16, weight: .bold))
                            .foregroundStyle(PowerZone.zone(for: Int(currentAvgPower)).color)
                        Text(formatDuration(currentDuration))
                            .font(LapCardFontToken.mono(size: 13))
                            .foregroundStyle(AppColor.fg2)
                    }
                }

                if lapNumber > 1 {
                    Rectangle()
                        .fill(AppColor.hair)
                        .frame(width: 1, height: 30)

                    // Previous lap
                    VStack(alignment: .leading, spacing: 3) {
                        Text("PREVIOUS")
                            .mangoxFont(.micro)
                            .fontWeight(.bold)
                            .foregroundStyle(AppColor.fg3)
                            .tracking(1)
                        HStack(spacing: 8) {
                            Text("\(Int(previousAvgPower))W")
                                .font(LapCardFontToken.mono(size: 16, weight: .bold))
                                .foregroundStyle(AppColor.fg2)
                            Text(formatDuration(previousDuration))
                                .font(LapCardFontToken.mono(size: 13))
                                .foregroundStyle(AppColor.fg3)
                        }
                    }
                }

                Spacer()
            }
        }
        .padding(12)
        .background(AppColor.bg2)
        .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue))
        .overlay(
            RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue)
                .strokeBorder(AppColor.hair2, lineWidth: 1)
        )
    }

    private var compactBody: some View {
        HStack(spacing: 10) {
            Image(systemName: "flag.fill")
                .mangoxFont(.micro)
                .foregroundStyle(AppColor.blue)
            Text("LAP \(lapNumber)")
                .mangoxFont(.label)
                .fontWeight(.bold)
                .foregroundStyle(AppColor.fg2)
                .tracking(0.5)
            Text("\(Int(currentAvgPower))W")
                .font(LapCardFontToken.mono(size: 13, weight: .bold))
                .foregroundStyle(PowerZone.zone(for: Int(currentAvgPower)).color)
            Text(formatDuration(currentDuration))
                .font(LapCardFontToken.mono(size: 12))
                .foregroundStyle(AppColor.fg2)
            if lapNumber > 1 {
                Text("·")
                    .foregroundStyle(AppColor.fg3)
                Text("\(Int(previousAvgPower))W")
                    .font(LapCardFontToken.mono(size: 12, weight: .semibold))
                    .foregroundStyle(AppColor.fg2)
                Text(formatDuration(previousDuration))
                    .font(LapCardFontToken.mono(size: 11))
                    .foregroundStyle(AppColor.fg3)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppColor.bg2)
        .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue))
        .overlay(
            RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue)
                .strokeBorder(AppColor.hair2, lineWidth: 1)
        )
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

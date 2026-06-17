import SwiftUI

struct SessionModeBadge: Equatable {
    let dotColor: Color
    let label: String
}

/// Shared in-ride header row: leading control, elapsed clock, optional trailing chrome.
struct SessionHeaderBar<Leading: View, Trailing: View>: View {
    let timing: SessionElapsedTiming?
    let elapsedPlaceholder: String
    var elapsedStyle: SessionElapsedStyle
    let statusSubtitle: String?
    let modeBadge: SessionModeBadge?
    let sideSlotWidth: CGFloat
    var elapsedAccessibilityLabel: String = "Elapsed time"
    let horizontalPadding: CGFloat
    let topPadding: CGFloat
    let bottomPadding: CGFloat

    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            leading()
                .frame(width: sideSlotWidth, alignment: .leading)

            VStack(alignment: .center, spacing: 2) {
                SessionElapsedLabel(
                    timing: timing,
                    placeholder: elapsedPlaceholder,
                    style: elapsedStyle,
                    accessibilityLabel: elapsedAccessibilityLabel
                )

                if let statusSubtitle {
                    Text(statusSubtitle)
                        .mangoxFont(.micro)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.yellow.opacity(0.95))
                        .tracking(0.8)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }

                if let modeBadge {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(modeBadge.dotColor)
                            .frame(width: 5, height: 5)
                        Text(modeBadge.label)
                            .mangoxFont(.micro)
                            .fontWeight(.bold)
                            .foregroundStyle(AppColor.fg3)
                            .tracking(1.0)
                    }
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity)

            trailing()
                .frame(width: sideSlotWidth, alignment: .trailing)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
    }
}

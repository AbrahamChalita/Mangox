import SwiftUI

struct MangoxConfirmOverlay<Actions: View>: View {
    let title: String
    let message: String
    let onDismiss: () -> Void
    @ViewBuilder let actions: Actions

    var body: some View {
        ZStack {
            AppColor.bg0.opacity(0.64)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(alignment: .leading, spacing: MangoxSpacing.lg.rawValue) {
                Text(title)
                    .mangoxFont(.title)
                    .foregroundStyle(AppColor.fg0)

                Text(message)
                    .mangoxFont(.body)
                    .foregroundStyle(AppColor.fg1)
                    .fixedSize(horizontal: false, vertical: true)

                actions
            }
            .padding(MangoxSpacing.xxl.rawValue)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue, style: .continuous)
                    .fill(AppColor.bg2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue, style: .continuous)
                    .strokeBorder(AppColor.hair2, lineWidth: 1)
            )
            .padding(.horizontal, MangoxSpacing.xxl.rawValue)
        }
        .allowsHitTesting(true)
    }
}

// MARK: - Dual-action row (equal-width buttons)

/// Cancel + confirm row for ``MangoxConfirmOverlay`` — both actions share the **exact** same
/// width (50/50 split) and height. Does not use ``MangoxButtonChrome`` `.hero` so label
/// typography matches secondary (``.hero`` uses title scale and a different radius, which
/// skewed layout next to Cancel).
struct MangoxConfirmDualButtonRow: View {
    enum TrailingStyle {
        case hero
        case destructive
    }

    private static let rowHeight: CGFloat = 50
    private static let spacing: CGFloat = 12

    let cancelTitle: String
    let confirmTitle: String
    var trailingStyle: TrailingStyle = .hero
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        GeometryReader { geo in
            let cellW = max(
                0,
                (geo.size.width - Self.spacing) / 2
            )
            HStack(spacing: Self.spacing) {
                Button(action: onCancel) {
                    Text(cancelTitle)
                        .mangoxFont(.bodyBold)
                        .foregroundStyle(AppColor.fg1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AppColor.bg2, in: roundedButtonShape)
                        .overlay(
                            roundedButtonShape.strokeBorder(AppColor.hair2, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .frame(width: cellW, height: Self.rowHeight)

                Button(action: onConfirm) {
                    Text(confirmTitle)
                        .mangoxFont(.bodyBold)
                        .foregroundStyle(AppColor.bg0)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(trailingFill, in: roundedButtonShape)
                        .overlay(
                            roundedButtonShape.strokeBorder(trailingStroke, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .frame(width: cellW, height: Self.rowHeight)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(height: Self.rowHeight)
    }

    private var roundedButtonShape: some InsettableShape {
        RoundedRectangle(cornerRadius: MangoxRadius.button.rawValue, style: .continuous)
    }

    private var trailingFill: Color {
        switch trailingStyle {
        case .hero: return AppColor.mango
        case .destructive: return AppColor.red
        }
    }

    private var trailingStroke: Color {
        switch trailingStyle {
        case .hero: return AppColor.mango.opacity(0.45)
        case .destructive: return AppColor.red.opacity(0.5)
        }
    }
}

import SwiftUI

// MARK: - Shared prompt row (suggested replies + empty-state starters)

/// Full-width tap target shared by coach suggested replies and conversation starters.
struct CoachTallPromptButton: View {
    let title: String
    var subtitle: String? = nil
    var leadingSystemImage: String? = nil
    var trailingSystemImage: String = "arrow.up.circle.fill"
    var trailingTint: Color = AppColor.mango.opacity(0.95)
    /// Tinted fill + stroke for coach quick-reply chips; starters use `.neutral`.
    var chipPalette: CoachReplyChipPalette = .neutral
    var isEnabled: Bool = true
    var isSent: Bool = false
    /// When nil, a default label is derived from `title`.
    var accessibilityLabelOverride: String? = nil
    let action: () -> Void

    private var titleColor: Color {
        if isSent { return AppColor.mango.opacity(0.95) }
        return isEnabled ? .white.opacity(0.92) : .white.opacity(0.35)
    }

    private var minRowHeight: CGFloat {
        (subtitle == nil || subtitle?.isEmpty == true) ? 52 : 58
    }

    @ViewBuilder
    private var rowBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        if isSent {
            shape.fill(AppColor.mango.opacity(0.12))
        } else {
            shape.fill(chipPalette.gradientFill(isEnabled: isEnabled))
        }
    }

    @ViewBuilder
    private var rowBorder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(
                isSent
                    ? AppColor.mango.opacity(0.45)
                    : chipPalette.strokeColor(isEnabled: isEnabled),
                lineWidth: 1
            )
    }

    var body: some View {
        Button {
            guard isEnabled, !isSent else { return }
            HapticManager.shared.coachQuickReplyTapped()
            action()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                if let leadingSystemImage {
                    Image(systemName: isSent ? "checkmark.circle.fill" : leadingSystemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(
                            isSent
                                ? AppColor.mango.opacity(0.95)
                                : chipPalette.leadingIconTint(isEnabled: isEnabled)
                        )
                        .frame(width: 26, alignment: .center)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: (subtitle == nil || subtitle?.isEmpty == true) ? 0 : 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(titleColor)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(isEnabled ? 0.44 : 0.28))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isSent ? "checkmark" : trailingSystemImage)
                    .font(.system(size: isSent ? 14 : 20, weight: .semibold))
                    .foregroundStyle(
                        isSent
                            ? AppColor.mango.opacity(0.95)
                            : (isEnabled ? trailingTint : .white.opacity(0.2))
                    )
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: minRowHeight, alignment: .center)
            .background { rowBackground }
            .overlay { rowBorder }
        }
        .buttonStyle(MangoxPressStyle())
        .disabled(!isEnabled || isSent)
        .animation(.snappy, value: isSent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            accessibilityLabelOverride
                ?? [title, subtitle].compactMap { $0 }.joined(separator: ", ")
        )
        .accessibilityAddTraits(.isButton)
    }
}

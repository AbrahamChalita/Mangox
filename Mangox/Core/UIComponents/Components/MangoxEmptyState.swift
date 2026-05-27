import SwiftUI

/// Reusable empty state view with icon, title, message, and optional action.
struct MangoxEmptyState: View {
    let icon: String
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(AppOpacity.textQuaternary))

            Text(title)
                .font(MangoxFont.bodyBold.value)
                .foregroundStyle(AppColor.fg2)

            if let message {
                Text(message)
                    .font(MangoxFont.caption.value)
                    .foregroundStyle(AppColor.fg3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(MangoxFont.caption.value)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.mango)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(AppColor.mango.opacity(0.12))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
    }
}

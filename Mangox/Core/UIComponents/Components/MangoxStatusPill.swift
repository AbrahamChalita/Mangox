import SwiftUI

struct MangoxStatusPill: View {
    let text: String
    let color: Color
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
            }
            Text(text)
                .mangoxFont(.caption)
                .tracking(1.0)
                .textCase(.uppercase)
                .lineLimit(1)
        }
        .foregroundStyle(color.opacity(0.95))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(AppColor.bg1, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(color.opacity(0.5), lineWidth: 1)
        )
    }
}

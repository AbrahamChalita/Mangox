import SwiftUI

struct MangoxIconBadge: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 30
    var cornerRadius: CGFloat = MangoxRadius.badge.rawValue

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.46, weight: .medium))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(AppColor.tint(for: color))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

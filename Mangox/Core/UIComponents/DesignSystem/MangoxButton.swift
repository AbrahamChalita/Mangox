import SwiftUI

enum MangoxButtonKind {
    case hero
    case primary
    case secondary
    case icon
    case iconSmall
    case mapIcon
    case mapIconSmall
    case endIcon
    case destructive
    case plain
}

extension View {
    func mangoxButtonChrome(_ kind: MangoxButtonKind, tint: Color = AppColor.mango) -> some View {
        modifier(MangoxButtonChrome(kind: kind, tint: tint))
    }
}

private struct MangoxButtonChrome: ViewModifier {
    let kind: MangoxButtonKind
    let tint: Color

    func body(content: Content) -> some View {
        switch kind {
        case .hero:
            content
                .mangoxFont(.title)
                .foregroundStyle(AppColor.bg)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(tint)
                .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.card.rawValue, style: .continuous))
        case .primary:
            content
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .mangoxSurface(.frostedInteractive, shape: .rounded(MangoxRadius.button.rawValue))
        case .secondary:
            content
                .foregroundStyle(.white.opacity(AppOpacity.textSecondary))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .mangoxSurface(.frostedInteractive, shape: .rounded(MangoxRadius.button.rawValue))
        case .icon:
            content
                .frame(width: 40, height: 40)
                .mangoxSurface(.frostedInteractive, shape: .circle)
        case .iconSmall:
            content
                .frame(width: 32, height: 32)
                .mangoxSurface(.frostedInteractive, shape: .circle)
        case .mapIcon:
            content
                .frame(width: 40, height: 40)
                .mangoxSurface(.mapOverlay, shape: .circle)
        case .mapIconSmall:
            content
                .frame(width: 32, height: 32)
                .mangoxSurface(.mapOverlay, shape: .circle)
        case .endIcon:
            content
                .mangoxFont(.label)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(AppColor.red)
                .clipShape(Circle())
        case .destructive:
            content
                .foregroundStyle(AppColor.bg)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppColor.red)
                .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.button.rawValue, style: .continuous))
        case .plain:
            content
        }
    }
}

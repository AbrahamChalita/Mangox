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
                .foregroundStyle(AppColor.bg0)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(tint, in: RoundedRectangle(cornerRadius: MangoxRadius.card.rawValue, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: MangoxRadius.card.rawValue, style: .continuous)
                        .strokeBorder(tint.opacity(0.45), lineWidth: 1)
                )
        case .primary:
            content
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(AppColor.bg2, in: RoundedRectangle(cornerRadius: MangoxRadius.button.rawValue, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: MangoxRadius.button.rawValue, style: .continuous)
                        .strokeBorder(tint.opacity(0.45), lineWidth: 1)
                )
        case .secondary:
            content
                .foregroundStyle(AppColor.fg1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(AppColor.bg2, in: RoundedRectangle(cornerRadius: MangoxRadius.button.rawValue, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: MangoxRadius.button.rawValue, style: .continuous)
                        .strokeBorder(AppColor.hair2, lineWidth: 1)
                )
        case .icon:
            content
                .frame(width: 40, height: 40)
                .mangoxSurface(.frostedInteractive, shape: .rounded(MangoxRadius.button.rawValue))
        case .iconSmall:
            content
                .frame(width: 32, height: 32)
                .mangoxSurface(.frostedInteractive, shape: .rounded(MangoxRadius.button.rawValue))
        case .mapIcon:
            content
                .frame(width: 40, height: 40)
                .mangoxSurface(.mapOverlay, shape: .rounded(MangoxRadius.button.rawValue))
        case .mapIconSmall:
            content
                .frame(width: 32, height: 32)
                .mangoxSurface(.mapOverlay, shape: .rounded(MangoxRadius.button.rawValue))
        case .endIcon:
            content
                .mangoxFont(.label)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(AppColor.red, in: RoundedRectangle(cornerRadius: MangoxRadius.button.rawValue, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: MangoxRadius.button.rawValue, style: .continuous)
                        .strokeBorder(AppColor.red.opacity(0.5), lineWidth: 1)
                )
        case .destructive:
            content
                .foregroundStyle(AppColor.bg0)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(AppColor.red, in: RoundedRectangle(cornerRadius: MangoxRadius.button.rawValue, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: MangoxRadius.button.rawValue, style: .continuous)
                        .strokeBorder(AppColor.red.opacity(0.5), lineWidth: 1)
                )
        case .plain:
            content
        }
    }
}

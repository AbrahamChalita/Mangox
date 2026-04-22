import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum MangoxFont {
    case heroValue
    case largeValue
    case value
    case compactValue
    case title
    case bodyBold
    case body
    case callout
    case caption
    case label
    case micro

    var value: Font {
        switch self {
        case .heroValue:
            return MangoxFontResolver.mono(size: 52, weight: .light)
        case .largeValue:
            return MangoxFontResolver.mono(size: 28, weight: .light)
        case .value:
            return MangoxFontResolver.mono(size: 22, weight: .regular)
        case .compactValue:
            return MangoxFontResolver.mono(size: 20, weight: .regular)
        case .title:
            return MangoxFontResolver.ui(size: 17, weight: .medium)
        case .bodyBold:
            return MangoxFontResolver.ui(size: 15, weight: .medium)
        case .body:
            return MangoxFontResolver.ui(size: 14, weight: .regular)
        case .callout:
            return MangoxFontResolver.ui(size: 13, weight: .medium)
        case .caption:
            return MangoxFontResolver.mono(size: 11, weight: .regular)
        case .label:
            return MangoxFontResolver.mono(size: 10, weight: .regular)
        case .micro:
            return MangoxFontResolver.mono(size: 9, weight: .regular)
        }
    }
}

private enum MangoxFontResolver {
    static func ui(size: CGFloat, weight: Font.Weight) -> Font {
        // Manrope (variable font bundle); named instances Manrope-Light / Regular / Medium.
        let fontName: String
        switch weight {
        case .light:
            fontName = "Manrope-Light"
        case .medium, .semibold, .bold, .heavy, .black:
            fontName = "Manrope-Medium"
        default:
            fontName = "Manrope-Regular"
        }

        return custom(name: fontName, size: size, fallback: .system(size: size, weight: weight))
    }

    static func mono(size: CGFloat, weight: Font.Weight) -> Font {
        let fontName: String
        switch weight {
        case .light:
            fontName = "GeistMono-Light"
        case .medium, .semibold, .bold, .heavy, .black:
            fontName = "GeistMono-Medium"
        default:
            fontName = "GeistMono-Regular"
        }

        return custom(
            name: fontName,
            size: size,
            fallback: .system(size: size, weight: weight, design: .monospaced)
        )
    }

    private static func custom(name: String, size: CGFloat, fallback: Font) -> Font {
        #if canImport(UIKit)
        if UIFont(name: name, size: size) != nil {
            return .custom(name, size: size)
        }
        #endif
        return fallback
    }
}

extension View {
    func mangoxFont(_ font: MangoxFont) -> some View {
        self.font(font.value)
    }
}

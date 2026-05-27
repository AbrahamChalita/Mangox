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

    /// Returns a Dynamic Type-scaled font while retaining the custom typeface.
    func scaled(relativeTo style: Font.TextStyle? = nil) -> Font {
        let textStyle = style ?? self.textStyle
        let scaledSize = MangoxFontScaler.scaledSize(base: scaledBaseSize, relativeTo: textStyle)
        if usesUIFont {
            return MangoxFontResolver.ui(size: scaledSize, weight: weight)
        }
        return MangoxFontResolver.mono(size: scaledSize, weight: weight)
    }

    private var scaledBaseSize: CGFloat {
        switch self {
        case .heroValue: return 52
        case .largeValue: return 28
        case .value: return 22
        case .compactValue: return 20
        case .title: return 17
        case .bodyBold: return 15
        case .body: return 14
        case .callout: return 13
        case .caption: return 11
        case .label: return 10
        case .micro: return 9
        }
    }

    private var usesUIFont: Bool {
        switch self {
        case .title, .bodyBold, .body, .callout:
            return true
        default:
            return false
        }
    }

    private var weight: Font.Weight {
        switch self {
        case .heroValue, .largeValue: return .light
        case .title, .bodyBold, .callout: return .medium
        default: return .regular
        }
    }

    /// The text style this font maps to for Dynamic Type scaling.
    var textStyle: Font.TextStyle {
        switch self {
        case .heroValue: return .largeTitle
        case .largeValue: return .title
        case .value: return .title2
        case .compactValue: return .title3
        case .title: return .headline
        case .bodyBold: return .subheadline
        case .body: return .body
        case .callout: return .callout
        case .caption: return .caption
        case .label: return .caption2
        case .micro: return .caption2
        }
    }
}

private enum MangoxFontScaler {
    static func scaledSize(base: CGFloat, relativeTo style: Font.TextStyle) -> CGFloat {
        #if canImport(UIKit)
        return UIFontMetrics(forTextStyle: uiKitTextStyle(for: style)).scaledValue(for: base)
        #else
        return base
        #endif
    }

    #if canImport(UIKit)
    private static func uiKitTextStyle(for style: Font.TextStyle) -> UIFont.TextStyle {
        switch style {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .body: return .body
        case .callout: return .callout
        case .caption: return .caption1
        case .caption2: return .caption2
        case .footnote: return .footnote
        @unknown default: return .body
        }
    }
    #endif
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

    /// Applies a Dynamic Type-scaled MangoxFont. The font scales with the user's
    /// preferred text size while retaining the custom typeface.
    func mangoxFontScaled(_ font: MangoxFont) -> some View {
        self.font(font.scaled(relativeTo: font.textStyle))
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }
}

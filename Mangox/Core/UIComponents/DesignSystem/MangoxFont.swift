import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum MangoxFont {
    case heroTitle
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

    private struct Spec {
        let size: CGFloat
        let weight: Font.Weight
        let textStyle: Font.TextStyle
        let usesUI: Bool
    }

    private static let specs: [MangoxFont: Spec] = [
        .heroTitle: Spec(size: 24, weight: .bold, textStyle: .title, usesUI: true),
        .heroValue: Spec(size: 52, weight: .light, textStyle: .largeTitle, usesUI: false),
        .largeValue: Spec(size: 28, weight: .light, textStyle: .title, usesUI: false),
        .value: Spec(size: 22, weight: .regular, textStyle: .title2, usesUI: false),
        .compactValue: Spec(size: 20, weight: .regular, textStyle: .title3, usesUI: false),
        .title: Spec(size: 17, weight: .medium, textStyle: .headline, usesUI: true),
        .bodyBold: Spec(size: 15, weight: .medium, textStyle: .subheadline, usesUI: true),
        .body: Spec(size: 14, weight: .regular, textStyle: .body, usesUI: true),
        .callout: Spec(size: 13, weight: .medium, textStyle: .callout, usesUI: true),
        .caption: Spec(size: 11, weight: .regular, textStyle: .caption, usesUI: false),
        .label: Spec(size: 10, weight: .regular, textStyle: .caption2, usesUI: false),
        .micro: Spec(size: 9, weight: .regular, textStyle: .caption2, usesUI: false),
    ]

    private var spec: Spec {
        Self.specs[self]!
    }

    var value: Font {
        let spec = spec
        if spec.usesUI {
            return MangoxFontResolver.ui(size: spec.size, weight: spec.weight)
        }
        return MangoxFontResolver.mono(size: spec.size, weight: spec.weight)
    }

    /// Returns a Dynamic Type-scaled font while retaining the custom typeface.
    func scaled(relativeTo style: Font.TextStyle? = nil) -> Font {
        let spec = spec
        let textStyle = style ?? spec.textStyle
        let scaledSize = MangoxFontScaler.scaledSize(base: spec.size, relativeTo: textStyle)
        if spec.usesUI {
            return MangoxFontResolver.ui(size: scaledSize, weight: spec.weight)
        }
        return MangoxFontResolver.mono(size: scaledSize, weight: spec.weight)
    }

    /// The text style this font maps to for Dynamic Type scaling.
    var textStyle: Font.TextStyle {
        spec.textStyle
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

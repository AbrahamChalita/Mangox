import SwiftUI

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
            return .system(size: 52, weight: .light, design: .rounded)
        case .largeValue:
            return .system(size: 28, weight: .bold, design: .monospaced)
        case .value:
            return .system(size: 22, weight: .bold, design: .monospaced)
        case .compactValue:
            return .system(size: 20, weight: .bold, design: .monospaced)
        case .title:
            return .system(size: 17, weight: .bold)
        case .bodyBold:
            return .system(size: 15, weight: .semibold)
        case .body:
            return .system(size: 14, weight: .medium)
        case .callout:
            return .system(size: 13, weight: .semibold)
        case .caption:
            return .system(size: 12, weight: .semibold)
        case .label:
            return .system(size: 11, weight: .bold)
        case .micro:
            return .system(size: 9, weight: .heavy)
        }
    }
}

extension View {
    func mangoxFont(_ font: MangoxFont) -> some View {
        self.font(font.value)
    }
}

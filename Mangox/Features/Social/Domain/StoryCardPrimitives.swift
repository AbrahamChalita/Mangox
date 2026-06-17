import UIKit

enum StoryCardPrimitives {
    static func fillRadial(center: CGPoint, radius: CGFloat, color: UIColor, cg: CGContext) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let colors = [
            UIColor(red: red, green: green, blue: blue, alpha: alpha).cgColor,
            UIColor(red: red, green: green, blue: blue, alpha: 0).cgColor,
        ] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
        cg.saveGState()
        cg.setBlendMode(.screen)
        cg.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: radius,
            options: [.drawsAfterEndLocation]
        )
        cg.restoreGState()
    }

    static func fittingFontSize(
        for text: String,
        startingAt start: CGFloat,
        minimum: CGFloat,
        maxWidth: CGFloat
    ) -> CGFloat {
        var size = start
        while size > minimum {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: StoryCardFontToken.mono(size: size, weight: .heavy),
                .kern: -5.0,
            ]
            if text.size(withAttributes: attrs).width <= maxWidth {
                return size
            }
            size -= 4
        }
        return minimum
    }

    static func fittingFontSize(
        for text: String,
        fontProvider: (CGFloat) -> UIFont,
        startingAt start: CGFloat,
        minimum: CGFloat,
        maxWidth: CGFloat,
        kern: CGFloat
    ) -> CGFloat {
        var size = start
        while size > minimum {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: fontProvider(size),
                .kern: kern,
            ]
            if text.size(withAttributes: attrs).width <= maxWidth {
                return size
            }
            size -= 2
        }
        return minimum
    }
}

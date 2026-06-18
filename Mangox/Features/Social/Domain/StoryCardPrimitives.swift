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

    // MARK: - Film grain

    private static var grainTileCache: UIImage?
    private static let grainTileEdge: Int = 256

    /// A cached 256×256 grayscale noise tile (mean ~128) for `.overlay`-blend film grain.
    static func filmGrainTile() -> UIImage {
        if let cached = grainTileCache { return cached }
        let edge = grainTileEdge
        var bytes = [UInt8](repeating: 128, count: edge * edge)
        for i in 0..<bytes.count {
            bytes[i] = UInt8.random(in: 0...255)
        }
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let cgImage = CGImage(
                width: edge,
                height: edge,
                bitsPerComponent: 8,
                bitsPerPixel: 8,
                bytesPerRow: edge,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            return UIImage()
        }
        let image = UIImage(cgImage: cgImage)
        grainTileCache = image
        return image
    }

    /// Tiles the cached grain across `size` using `.overlay` blend at the given alpha (0–1).
    /// Call within the active draw context. Typical alpha: 0.03–0.05.
    static func applyFilmGrain(in size: CGSize, cg: CGContext, alpha: CGFloat) {
        guard alpha > 0 else { return }
        let tile = filmGrainTile()
        let tileW = tile.size.width
        let tileH = tile.size.height
        cg.saveGState()
        cg.setBlendMode(.overlay)
        cg.setAlpha(alpha)
        var y: CGFloat = 0
        while y < size.height {
            var x: CGFloat = 0
            while x < size.width {
                tile.draw(in: CGRect(x: x, y: y, width: tileW, height: tileH))
                x += tileW
            }
            y += tileH
        }
        cg.restoreGState()
    }
}

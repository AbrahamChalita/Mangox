import SwiftUI
import UIKit

// MARK: - Instagram Story Card (dedicated renderer)

/// Renders the workout summary **bitmap for Instagram Stories** only — **full-bleed 1080×1920** (9:16), no letterboxing.
/// Background paints edge-to-edge; **content** is inset from top/bottom for Instagram’s on-screen chrome.
///
/// Design: compact **9:16 story** — top meta line, short hero chart, distance + duration primary row, two stat cards,
/// left-aligned workout title filling remaining space, footer (matches improved HTML layout).
enum InstagramStoryCardRenderer {

    /// Full Instagram Story canvas (matches ``InstagramStoryShare/storySize`` — export fills the frame horizontally and vertically).
    static let cardSize = CGSize(width: 1080, height: 1920)

    @MainActor
    static func render(
        workout: Workout,
        dominantZone: PowerZone,
        routeName: String?,
        totalElevationGain: Double,
        personalRecordNames: [String] = [],
        options: InstagramStoryCardOptions? = nil,
        whoopStrain: Double? = nil,
        whoopRecovery: Double? = nil,
        aiTitle: String? = nil
    ) -> UIImage {
        let opts =
            options
            ?? InstagramStoryCardOptions(
                accent: .dominantZone,
                layeredShare: false,
                showPowerHRChart: true,
                showHeartRateLineOnChart: true,
                showMetaLine: true,
                showFooterBranding: true,
                showElevation: true,
                showNPAndTSS: true
            )
        let renderer = UIGraphicsImageRenderer(size: cardSize)
        return renderer.image { ctx in
            StoryCardDrawing.draw(
                in: ctx.cgContext,
                size: cardSize,
                workout: workout,
                dominantZone: dominantZone,
                routeName: routeName,
                totalElevationGain: totalElevationGain,
                personalRecordNames: personalRecordNames,
                options: opts,
                whoopStrain: whoopStrain,
                whoopRecovery: whoopRecovery,
                aiTitle: aiTitle
            )
        }
    }

    /// Atmospheric gradient only — used as the Instagram **background** layer when ``InstagramStoryCardOptions/layeredShare`` is on.
    @MainActor
    static func renderAtmosphericBackgroundOnly(
        dominantZone: PowerZone,
        options: InstagramStoryCardOptions
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: cardSize)
        return renderer.image { ctx in
            StoryCardDrawing.drawAtmosphericBackground(
                in: cardSize,
                dominantZone: dominantZone,
                accent: options.accent,
                cg: ctx.cgContext
            )
        }
    }

    /// Rounded, scaled copy of the full card for Instagram’s **sticker** layer (transparent outside the card).
    @MainActor
    static func renderStickerLayer(
        fullCard: UIImage,
        scale: CGFloat = 0.84,
        cornerRadius: CGFloat = 52
    ) -> UIImage {
        let W = cardSize.width
        let H = cardSize.height
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: W, height: H), format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.clear(CGRect(x: 0, y: 0, width: W, height: H))
            let tw = W * scale
            let th = H * scale
            let rect = CGRect(x: (W - tw) / 2, y: (H - th) / 2, width: tw, height: th)
            cg.saveGState()
            let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)

            cg.addPath(path.cgPath)
            cg.setFillColor(UIColor.black.withAlphaComponent(0.4).cgColor)
            cg.fillPath()

            cg.addPath(path.cgPath)
            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.1).cgColor)
            cg.setLineWidth(2.0)
            cg.strokePath()

            cg.addPath(path.cgPath)
            cg.clip()
            fullCard.draw(in: rect)
            cg.restoreGState()
        }
    }
}

// MARK: - Drawing

private enum StoryCardDrawing {

    /// Horizontal padding for story **content** (bitmap stays full-bleed; background still fills 1080×1920).
    private static let sidePad: CGFloat = 88
    /// Extra top inset so titles/meta clear Instagram’s profile / progress UI (content only — orbs still full-bleed).
    private static let topSafe: CGFloat = 156
    /// Extra bottom inset so stats/title/footer clear reply / share / sticker strip.
    private static let bottomSafe: CGFloat = 168
    private static let sectionGap: CGFloat = 40

    /// Matches ``AppColor.mango`` — primary brand accent (mango yellow-orange).
    private static let brandMango = UIColor(red: 1, green: 186 / 255, blue: 50 / 255, alpha: 1)
    private static let brandMangoSoft = UIColor(
        red: 1, green: 186 / 255, blue: 50 / 255, alpha: 0.45)
    private static let brandMangoLight = UIColor(
        red: 1, green: 235 / 255, blue: 150 / 255, alpha: 1)
    private static let neonCyan = UIColor(red: 0.31, green: 0.675, blue: 0.996, alpha: 1)
    private static let neonCyanEnd = UIColor(red: 0, green: 0.949, blue: 0.996, alpha: 1)

    static func draw(
        in cgCtx: CGContext,
        size: CGSize,
        workout: Workout,
        dominantZone: PowerZone,
        routeName: String?,
        totalElevationGain: Double,
        personalRecordNames: [String],
        options: InstagramStoryCardOptions,
        whoopStrain: Double? = nil,
        whoopRecovery: Double? = nil,
        aiTitle: String? = nil
    ) {
        let W = size.width
        let H = size.height

        UIGraphicsPushContext(cgCtx)
        defer { UIGraphicsPopContext() }

        // Use AI-generated title if available, otherwise fall back to static builder
        let title = aiTitle ?? StravaPostBuilder.buildTitle(
            workout: workout,
            routeName: routeName,
            dominantPowerZone: dominantZone,
            personalRecordNames: personalRecordNames
        )

        drawAtmosphericBackground(
            in: size, dominantZone: dominantZone, accent: options.accent, cg: cgCtx)

        var y = topSafe

        // === 1. TOP META: "APRIL 7 · RIDE" ===
        drawTopMetaLine(date: workout.startDate, width: W, y: y)
        y += 56

        // === 2. CHART PANEL ===
        let heroH: CGFloat = 340
        if options.showPowerHRChart {
            let heroRect = CGRect(x: sidePad, y: y, width: W - sidePad * 2, height: heroH)
            drawHeroPanel(
                workout: workout,
                in: heroRect,
                cg: cgCtx,
                showHeartRateLine: options.showHeartRateLineOnChart
            )
            y += heroH + sectionGap
        }

        // === 3. TWO METRIC CARDS SIDE BY SIDE (square) ===
        let bentoGap: CGFloat = 20
        let bentoW = W - sidePad * 2
        let halfW = (bentoW - bentoGap) / 2
        let cardH: CGFloat = halfW  // Square aspect ratio

        // Left: Distance
        drawMetricCard(
            label: "Distance",
            value: String(format: "%.1f", workout.distance / 1000),
            unit: "km",
            accent: brandMangoLight,
            in: CGRect(x: sidePad, y: y, width: halfW, height: cardH),
            cg: cgCtx
        )

        // Right: Avg Power
        drawMetricCard(
            label: "Avg Power",
            value: workout.avgPower > 0 ? "\(Int(workout.avgPower))" : "—",
            unit: "W",
            accent: neonCyan,
            in: CGRect(x: sidePad + halfW + bentoGap, y: y, width: halfW, height: cardH),
            cg: cgCtx
        )
        y += cardH + 20

        // === 4. STATS PILL ===
        let pillH: CGFloat = 56
        let pillRect = CGRect(x: sidePad, y: y, width: bentoW, height: pillH)

        var segments: [(value: String, label: String)] = []
        let durationStr = AppFormat.duration(workout.duration)
        segments.append((value: durationStr, label: ""))
        if options.showElevation {
            segments.append((value: "\(Int(totalElevationGain))m", label: "↑"))
        }
        if options.showNPAndTSS && workout.normalizedPower > 0 {
            segments.append((value: "NP \(Int(workout.normalizedPower))W", label: ""))
        }
        if options.showNPAndTSS && workout.tss > 0 {
            segments.append((value: "TSS \(Int(workout.tss))", label: ""))
        }

        drawStatsPill(segments: segments, in: pillRect, cg: cgCtx)
        y += pillH + 20

        // === 5. HERO TITLE ===
        let footerLineY = H - bottomSafe - 48
        let titleRegionTop = y + 10
        drawBottomTitlePoster(
            title: title,
            route: routeName,
            canvasWidth: W,
            cg: cgCtx,
            regionTop: titleRegionTop,
            footerLineY: footerLineY
        )

        // === 6. FOOTER ===
        if options.showFooterBranding {
            drawFooterBranding(width: W, bottomY: H - bottomSafe)
        }
    }

    // MARK: - Metric Card

    private static func drawMetricCard(
        label: String,
        value: String,
        unit: String?,
        accent: UIColor,
        in rect: CGRect,
        cg: CGContext
    ) {
        let corner: CGFloat = 14
        let path = UIBezierPath(roundedRect: rect, cornerRadius: corner)

        // Mangox card style: white @ 4% fill
        UIColor(white: 1, alpha: 0.04).setFill()
        path.fill()

        // Subtle border glow
        UIColor(white: 1, alpha: 0.06).setStroke()
        path.lineWidth = 1
        path.stroke()

        let inset: CGFloat = 28

        // Label: tracked uppercase
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 18, weight: .bold),
            .foregroundColor: UIColor(white: 1, alpha: 0.45),
            .kern: 2.5,
        ]
        label.draw(at: CGPoint(x: rect.minX + inset, y: rect.minY + inset), withAttributes: labelAttrs)

        // Value: large, bold, monospaced, colored with subtle glow
        let valueFont = UIFont.monospacedSystemFont(ofSize: 90, weight: .bold)
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: valueFont,
            .foregroundColor: accent,
        ]
        let valueSize = value.size(withAttributes: valueAttrs)

        let valueY = rect.maxY - inset - valueSize.height
        value.draw(at: CGPoint(x: rect.minX + inset, y: valueY), withAttributes: valueAttrs)

        // Unit: subtle secondary color
        if let unit = unit {
            let unitAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .medium),
                .foregroundColor: UIColor(white: 1, alpha: 0.55),
            ]
            let unitX = rect.minX + inset + valueSize.width + 8
            let unitY = valueY + valueSize.height - 32
            unit.draw(at: CGPoint(x: unitX, y: unitY), withAttributes: unitAttrs)
        }

        // Subtle accent line at bottom
        let accentLine = CGRect(x: rect.minX + inset, y: rect.maxY - inset - 6, width: 48, height: 3)
        accent.setFill()
        UIRectFill(accentLine)
    }

    // MARK: - Stats Pill (compact, inline format)

    private static func drawStatsPill(
        segments: [(value: String, label: String)],
        in rect: CGRect,
        cg: CGContext
    ) {
        let corner: CGFloat = 14  // Mangox standard
        let path = UIBezierPath(roundedRect: rect, cornerRadius: corner)

        // Mangox card style: white @ 4% fill
        UIColor(white: 1, alpha: 0.04).setFill()
        path.fill()

        // Border: white @ 8%
        UIColor(white: 1, alpha: 0.08).setStroke()
        path.lineWidth = 1
        path.stroke()

        // Build combined string with · separators
        var parts: [String] = []
        for seg in segments {
            if seg.label.isEmpty {
                parts.append(seg.value)
            } else {
                parts.append("\(seg.value) \(seg.label)")
            }
        }
        let combined = parts.joined(separator: "  ·  ")

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 26, weight: .semibold),
            .foregroundColor: UIColor(white: 1, alpha: 0.9),
            .kern: 1,
        ]
        let size = combined.size(withAttributes: attrs)
        let x = rect.midX - size.width / 2
        let y = rect.midY - size.height / 2
        combined.draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
    }

    // MARK: Background

    static func drawAtmosphericBackground(
        in size: CGSize,
        dominantZone: PowerZone,
        accent: InstagramStoryCardOptions.Accent,
        cg: CGContext
    ) {
        // Mangox bg: near-black rgb(8, 10, 15)
        UIColor(red: 0.03, green: 0.04, blue: 0.06, alpha: 1).setFill()
        UIRectFill(CGRect(origin: .zero, size: size))

        // Subtle grain texture for depth
        let noiseRect = CGRect(origin: .zero, size: size)
        cg.saveGState()
        cg.setBlendMode(.overlay)
        cg.setAlpha(0.06)
        let step: CGFloat = 4
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        var x: CGFloat = 0
        while x < noiseRect.width {
            var y: CGFloat = 0
            while y < noiseRect.height {
                seed &+= 0xC6BC_2796_92B5_C323
                let g = CGFloat(seed % 1000) / 1000.0 * 0.04 + 0.02
                UIColor(white: g, alpha: 1).setFill()
                cg.fill(CGRect(x: x, y: y, width: step, height: step))
                y += step
            }
            x += step
        }
        cg.restoreGState()

        func orb(
            _ center: CGPoint, radius: CGFloat, color: UIColor, alpha: CGFloat
        ) {
            let cs = CGColorSpaceCreateDeviceRGB()
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            let colors = [
                UIColor(red: r, green: g, blue: b, alpha: alpha).cgColor,
                UIColor(red: r, green: g, blue: b, alpha: 0).cgColor,
            ] as CFArray
            guard let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1]) else {
                return
            }
            cg.drawRadialGradient(
                grad,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: radius,
                options: [.drawsAfterEndLocation]
            )
        }

        cg.saveGState()
        cg.addRect(CGRect(origin: .zero, size: size))
        cg.clip()
        cg.setBlendMode(.screen)

        // Mango glow top-right
        orb(
            CGPoint(x: size.width * 0.85, y: size.height * 0.08), radius: 500,
            color: brandMango, alpha: 0.12)

        // Subtle mango glow bottom-left
        orb(
            CGPoint(x: size.width * 0.15, y: size.height * 0.85), radius: 450,
            color: brandMango, alpha: 0.08)

        cg.restoreGState()
    }

    // MARK: Header

    private static func drawTopMetaLine(date: Date, width: CGFloat, y: CGFloat) {
        let f = DateFormatter()
        f.dateFormat = "MMMM d"
        let dayPart = f.string(from: date).uppercased()
        let line = "\(dayPart) · RIDE"
        // Match reference: text-[10px] text-zinc-400 uppercase tracking-[0.2em]
        let a: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 18, weight: .medium),
            .foregroundColor: UIColor(white: 0.63, alpha: 1),  // zinc-400
            .kern: 3.5,  // tracking-[0.2em]
        ]
        line.draw(at: CGPoint(x: sidePad, y: y), withAttributes: a)
    }

    /// Returns extra vertical space consumed below `y`.
    @discardableResult
    private static func drawZoneFocusBanner(zone: PowerZone, width: CGFloat, y: CGFloat) -> CGFloat
    {
        let zc = UIColor(zone.color)
        let line = "Z\(zone.id) · \(zone.name.uppercased())"
        let a: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 36, weight: .bold),
            .foregroundColor: zc,
            .kern: 2.2,
        ]
        let sz = line.size(withAttributes: a)
        line.draw(at: CGPoint(x: sidePad, y: y), withAttributes: a)
        return sz.height + 8
    }

    /// Returns vertical space used (including bottom gap).
    private static func drawNPAndTSSLine(workout: Workout, width: CGFloat, y: CGFloat) -> CGFloat {
        var parts: [String] = []
        if workout.normalizedPower > 0 {
            parts.append("NP \(Int(workout.normalizedPower.rounded()))W")
        }
        if workout.tss > 0 {
            parts.append(String(format: "TSS %.0f", workout.tss))
        }
        if workout.intensityFactor > 0 {
            parts.append(String(format: "IF %.2f", workout.intensityFactor))
        }
        guard !parts.isEmpty else { return 0 }
        let line = parts.joined(separator: "  ·  ")
        let a: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 30, weight: .medium),
            .foregroundColor: UIColor(white: 1, alpha: 0.78),
            .kern: 0.12,
        ]
        let sz = line.size(withAttributes: a)
        line.draw(at: CGPoint(x: sidePad, y: y), withAttributes: a)
        return sz.height + 12
    }

    /// Story title: neutral **regular** weight, left-aligned (matches improved HTML).
    private static func posterTitleFont(size: CGFloat) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: .regular)
    }

    private static func titleParagraphStyle(fontSize: CGFloat) -> NSParagraphStyle {
        let titlePara = NSMutableParagraphStyle()
        titlePara.alignment = .left
        titlePara.lineBreakMode = .byWordWrapping
        titlePara.lineSpacing = fontSize * 0.05
        titlePara.hyphenationFactor = 0
        return titlePara
    }

    /// Width of the longest whitespace-delimited word at this size (prevents mid-word line breaks).
    private static func widestWordWidth(_ title: String, fontSize: CGFloat) -> CGFloat {
        let font = posterTitleFont(size: fontSize)
        let kern = -0.02 * fontSize
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .kern: kern]
        let words = title.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return 0 }
        return words.map { ($0 as NSString).size(withAttributes: attrs).width }.max() ?? 0
    }

    /// Inserts newlines only at spaces so Core Text never breaks inside a word.
    private static func wordWrappedTitle(_ title: String, maxWidth: CGFloat, fontSize: CGFloat)
        -> String
    {
        let font = posterTitleFont(size: fontSize)
        let kern = -0.02 * fontSize
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .kern: kern]
        let words = title.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return title }
        var lines: [String] = []
        var current = ""
        for word in words {
            let candidate = current.isEmpty ? word : current + " " + word
            let w = (candidate as NSString).size(withAttributes: attrs).width
            if w <= maxWidth {
                current = candidate
            } else {
                if !current.isEmpty { lines.append(current) }
                current = word
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines.joined(separator: "\n")
    }

    private static func measuredTitleHeight(
        _ title: String,
        fontSize: CGFloat,
        maxWidth: CGFloat
    ) -> CGFloat {
        let font = posterTitleFont(size: fontSize)
        let para = titleParagraphStyle(fontSize: fontSize)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: para,
            .kern: -0.02 * fontSize,
        ]
        let s = NSAttributedString(string: title, attributes: attrs)
        let bound = s.boundingRect(
            with: CGSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return ceil(bound.height)
    }

    /// Workout name fills the vertical band between metrics and footer; type scales up to use that space.
    private static func drawBottomTitlePoster(
        title: String,
        route: String?,
        canvasWidth: CGFloat,
        cg: CGContext,
        regionTop: CGFloat,
        footerLineY: CGFloat
    ) {
        let maxW = canvasWidth - sidePad * 2
        let clearanceAboveRule: CGFloat = 32
        let routeGap: CGFloat = 16
        let bottomEdge = footerLineY - clearanceAboveRule
        let availableH = max(0, bottomEdge - regionTop)

        let routeFont = UIFont.systemFont(ofSize: 18, weight: .regular)
        let routePara = NSMutableParagraphStyle()
        routePara.alignment = .left
        let routeAttrsBase: [NSAttributedString.Key: Any] = [
            .font: routeFont,
            .foregroundColor: UIColor(white: 1, alpha: 0.34),
            .paragraphStyle: routePara,
        ]
        var routeH: CGFloat = 0
        if let route, !route.isEmpty {
            let rStr = NSAttributedString(string: route, attributes: routeAttrsBase)
            routeH = ceil(
                rStr.boundingRect(
                    with: CGSize(width: maxW, height: 160),
                    options: [.usesLineFragmentOrigin],
                    context: nil
                ).height)
        }
        let routeBlock = routeH > 0 ? routeGap + routeH : CGFloat(0)

        let titleMaxH = max(48, availableH - routeBlock)
        // Largest point size that still fits — fills the band for short titles, scales down for long ones.
        var lo = 26
        var hi = min(178, Int(titleMaxH * 1.2))
        hi = max(hi, lo + 1)
        var best = lo
        while lo <= hi {
            let mid = (lo + hi) / 2
            let h = measuredTitleHeight(title, fontSize: CGFloat(mid), maxWidth: maxW)
            if h <= titleMaxH {
                best = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        let minTitleFont: CGFloat = 14

        var fontSize = CGFloat(best)
        while fontSize > minTitleFont
            && measuredTitleHeight(title, fontSize: fontSize, maxWidth: maxW) > titleMaxH
        {
            fontSize -= 1
        }

        // Shrink until every word fits the column and the wrapped block fits height (no intra-word breaks).
        while fontSize > minTitleFont {
            let wWord = widestWordWidth(title, fontSize: fontSize)
            let display = wordWrappedTitle(title, maxWidth: maxW, fontSize: fontSize)
            let hBlock = measuredTitleHeight(display, fontSize: fontSize, maxWidth: maxW)
            if wWord <= maxW && hBlock <= titleMaxH { break }
            fontSize -= 1
        }
        let displayTitle = wordWrappedTitle(title, maxWidth: maxW, fontSize: fontSize)

        let titleFont = posterTitleFont(size: fontSize)
        let titlePara = titleParagraphStyle(fontSize: fontSize)
        let titleH = measuredTitleHeight(displayTitle, fontSize: fontSize, maxWidth: maxW)
        let blockH = titleH + routeBlock
        let blockStartY = regionTop + max(0, (availableH - blockH) / 2)

        let isHolo = displayTitle.contains("PR") || displayTitle.contains("🏆")
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: isHolo ? UIColor.black : UIColor(white: 1, alpha: 1),
            .paragraphStyle: titlePara,
            .kern: -0.02 * fontSize,
        ]
        let titleAttrStr = NSAttributedString(string: displayTitle, attributes: titleAttrs)
        let textRect = CGRect(x: sidePad, y: blockStartY, width: maxW, height: titleH)

        if isHolo {
            cg.saveGState()
            cg.beginTransparencyLayer(auxiliaryInfo: nil)

            titleAttrStr.draw(in: textRect)
            cg.setBlendMode(.sourceIn)

            // Gradient: teal-300 → indigo-400 → pink-400 (from reference)
            let holoColors =
                [
                    UIColor(red: 94/255, green: 234/255, blue: 212/255, alpha: 1).cgColor,   // teal-300
                    UIColor(red: 129/255, green: 140/255, blue: 248/255, alpha: 1).cgColor,  // indigo-400
                    UIColor(red: 244/255, green: 114/255, blue: 182/255, alpha: 1).cgColor,  // pink-400
                ] as CFArray
            let holoGrad = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: holoColors,
                locations: [0, 0.5, 1.0])!
            cg.drawLinearGradient(
                holoGrad, start: CGPoint(x: textRect.minX, y: textRect.minY),
                end: CGPoint(x: textRect.maxX, y: textRect.maxY), options: [])

            cg.endTransparencyLayer()
            cg.restoreGState()
        } else {
            titleAttrStr.draw(in: textRect)
        }

        if let route, !route.isEmpty {
            let rStr = NSAttributedString(string: route, attributes: routeAttrsBase)
            let ry = blockStartY + titleH + routeGap
            rStr.draw(in: CGRect(x: sidePad, y: ry, width: maxW, height: routeH))

            cg.saveGState()
            let path = CGMutablePath()
            var px = sidePad
            var py = ry + routeH + 16
            path.move(to: CGPoint(x: px, y: py))
            for i in 1...6 {
                px += 24
                py += (i % 2 == 0) ? -8 : 8
                path.addLine(to: CGPoint(x: px, y: py))
            }
            cg.setStrokeColor(brandMango.cgColor)
            cg.setLineWidth(4)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            cg.setShadow(offset: .zero, blur: 12, color: brandMango.cgColor)
            cg.addPath(path)
            cg.strokePath()
            cg.restoreGState()
        }
    }

    // MARK: Hero chart

    private static func drawHeroPanel(
        workout: Workout,
        in rect: CGRect,
        cg: CGContext,
        showHeartRateLine: Bool = true
    ) {
        let corner: CGFloat = 14  // Mangox standard
        let bgPath = UIBezierPath(roundedRect: rect, cornerRadius: corner)

        // Mangox card style: white @ 4% fill
        UIColor(white: 1, alpha: 0.04).setFill()
        bgPath.fill()

        // Border: white @ 8%
        UIColor(white: 1, alpha: 0.08).setStroke()
        bgPath.lineWidth = 1
        bgPath.stroke()

        // Label: "POWER + HEART RATE" - tracked uppercase style
        let label = showHeartRateLine ? "POWER + HEART RATE" : "POWER"
        let la: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16, weight: .bold),
            .foregroundColor: UIColor(white: 1, alpha: 0.4),
            .kern: 2.5,
        ]
        label.draw(at: CGPoint(x: rect.minX + 24, y: rect.minY + 20), withAttributes: la)

        let chartRect = CGRect(
            x: rect.minX + 16,
            y: rect.minY + 56,
            width: rect.width - 32,
            height: rect.height - 72
        )
        let samples = workout.samples.sorted { $0.elapsedSeconds < $1.elapsedSeconds }
        if samples.count >= 3 {
            drawTelemetryChart(
                samples: samples,
                maxPower: workout.maxPower,
                in: chartRect,
                cg: cg,
                compact: true,
                showHeartRateLine: showHeartRateLine
            )
        } else {
            drawPlaceholderChart(in: chartRect, workout: workout, cg: cg, compact: true)
        }
    }

    private static func downsampleSamples(_ samples: [WorkoutSample], maxPoints: Int)
        -> [WorkoutSample]
    {
        guard samples.count > maxPoints else { return samples }
        let step = max(1, samples.count / maxPoints)
        var out: [WorkoutSample] = []
        var i = 0
        while i < samples.count {
            out.append(samples[i])
            i += step
        }
        if let last = samples.last, out.last?.elapsedSeconds != last.elapsedSeconds {
            out.append(last)
        }
        return out
    }

    private static func drawTelemetryChart(
        samples: [WorkoutSample],
        maxPower: Int,
        in rect: CGRect,
        cg: CGContext,
        compact: Bool = false,
        showHeartRateLine: Bool = true
    ) {
        let lwPower: CGFloat = compact ? 8 : 7
        let lwHR: CGFloat = compact ? 5 : 5
        let areaTopAlpha: CGFloat = compact ? 0.22 : 0.45
        let glowBlur: CGFloat = compact ? 8 : 18

        let picked = downsampleSamples(samples, maxPoints: compact ? 100 : 140)
        let powers = picked.map { Double($0.power) }
        let hrs = picked.map { Double($0.heartRate) }
        let pMin = powers.min() ?? 0
        let pMax = max(powers.max() ?? 1, pMin + 1)
        let hasHR = hrs.contains { $0 > 0 }
        let hVals = hrs.filter { $0 > 0 }
        let hMin = hVals.min() ?? 0
        let hMax = max(hVals.max() ?? 1, hMin + 1)

        let n = max(CGFloat(picked.count - 1), 1)
        let left = rect.minX
        let chartW = rect.width
        let top = rect.minY
        let chartH = rect.height

        func xAt(_ i: Int) -> CGFloat { left + CGFloat(i) / n * chartW }

        func yPower(_ i: Int) -> CGFloat {
            let t = (powers[i] - pMin) / (pMax - pMin)
            return top + chartH * (1 - CGFloat(t) * 0.82 - 0.06)
        }

        func yHR(_ i: Int) -> CGFloat {
            guard hasHR, hrs[i] > 0 else { return top + chartH * 0.5 }
            let t = (hrs[i] - hMin) / (hMax - hMin)
            return top + chartH * (1 - CGFloat(t) * 0.72 - 0.12)
        }

        // Area under power (elevation-style fill)
        let area = CGMutablePath()
        area.move(to: CGPoint(x: xAt(0), y: top + chartH))
        for i in 0..<picked.count {
            area.addLine(to: CGPoint(x: xAt(i), y: yPower(i)))
        }
        area.addLine(to: CGPoint(x: xAt(picked.count - 1), y: top + chartH))
        area.closeSubpath()
        cg.saveGState()
        cg.addPath(area)
        cg.clip()
        let elevGrad = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                brandMango.withAlphaComponent(areaTopAlpha).cgColor,
                brandMango.withAlphaComponent(0).cgColor,
            ] as CFArray,
            locations: [0, 1]
        )!
        cg.drawLinearGradient(
            elevGrad, start: CGPoint(x: left, y: top), end: CGPoint(x: left, y: top + chartH),
            options: [])
        cg.restoreGState()

        // Power stroke (smooth-ish)
        let powerPath = smoothPathThrough(
            points: (0..<picked.count).map { CGPoint(x: xAt($0), y: yPower($0)) })
        cg.saveGState()
        cg.setLineWidth(lwPower)
        cg.setLineCap(.round)
        cg.setLineJoin(.round)
        let powerGrad = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [brandMango.cgColor, brandMangoLight.cgColor] as CFArray,
            locations: [0, 1]
        )!
        cg.addPath(powerPath)
        cg.replacePathWithStrokedPath()
        cg.clip()
        cg.drawLinearGradient(
            powerGrad,
            start: CGPoint(x: left, y: top),
            end: CGPoint(x: left + chartW, y: top),
            options: []
        )
        cg.restoreGState()

        cg.saveGState()
        cg.setShadow(
            offset: CGSize(width: 0, height: 0), blur: glowBlur,
            color: brandMango.withAlphaComponent(0.85).cgColor)
        cg.setStrokeColor(brandMango.cgColor)
        cg.setLineWidth(lwPower)
        cg.setLineCap(.round)
        cg.addPath(powerPath)
        cg.strokePath()
        cg.restoreGState()

        if showHeartRateLine, hasHR {
            let hrPath = smoothPathThrough(
                points: (0..<picked.count).map { CGPoint(x: xAt($0), y: yHR($0)) })
            cg.saveGState()
            cg.setLineWidth(lwHR)
            cg.setLineCap(.round)
            let hrGrad = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [neonCyan.cgColor, neonCyanEnd.cgColor] as CFArray,
                locations: [0, 1]
            )!
            cg.addPath(hrPath)
            cg.replacePathWithStrokedPath()
            cg.clip()
            cg.drawLinearGradient(
                hrGrad,
                start: CGPoint(x: left, y: top),
                end: CGPoint(x: left + chartW, y: top),
                options: []
            )
            cg.restoreGState()

            cg.setStrokeColor(neonCyan.withAlphaComponent(0.92).cgColor)
            cg.setLineWidth(lwHR)
            cg.setLineCap(.round)
            cg.addPath(hrPath)
            cg.strokePath()
        }

        // Peak power marker (omitted in compact strip — chart is decorative only)
        if !compact, let maxIdx = powers.enumerated().max(by: { $0.element < $1.element })?.offset {
            let cx = xAt(maxIdx)
            let cy = yPower(maxIdx)
            let peakW = maxPower > 0 ? maxPower : Int(powers[maxIdx].rounded())
            let label = "\(peakW)W"
            let dotR: CGFloat = 8
            cg.setFillColor(UIColor.white.cgColor)
            cg.fillEllipse(
                in: CGRect(x: cx - dotR, y: cy - dotR, width: dotR * 2, height: dotR * 2))

            let fa: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 22, weight: .bold),
                .foregroundColor: UIColor.white,
            ]
            let fsz = label.size(withAttributes: fa)
            label.draw(at: CGPoint(x: cx - fsz.width / 2, y: cy - 34), withAttributes: fa)
        }
    }

    private static func smoothPathThrough(points: [CGPoint]) -> CGPath {
        guard points.count > 1 else {
            let p = CGMutablePath()
            if let first = points.first { p.move(to: first) }
            return p
        }
        let path = CGMutablePath()
        path.move(to: points[0])
        for i in 1..<points.count {
            path.addLine(to: points[i])
        }
        return path
    }

    private static func drawPlaceholderChart(
        in rect: CGRect, workout: Workout, cg: CGContext, compact: Bool = false
    ) {
        let left = rect.minX
        let chartW = rect.width
        let top = rect.minY
        let chartH = rect.height
        let np = max(workout.normalizedPower, workout.avgPower, 1)
        let amp = CGFloat(min(np / 300.0, 1))

        var pts: [CGPoint] = []
        let steps = 48
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let x = left + t * chartW
            let wave = sin(t * .pi * 4 + 0.5) * 0.18 + sin(t * .pi * 11) * 0.06
            let y = top + chartH * (0.72 - CGFloat(wave) * amp - t * 0.08)
            pts.append(CGPoint(x: x, y: y))
        }

        let area = CGMutablePath()
        area.move(to: CGPoint(x: pts[0].x, y: top + chartH))
        for p in pts { area.addLine(to: p) }
        area.addLine(to: CGPoint(x: pts.last!.x, y: top + chartH))
        area.closeSubpath()
        cg.saveGState()
        cg.addPath(area)
        cg.clip()
        let g = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                UIColor(white: 1, alpha: compact ? 0.1 : 0.18).cgColor,
                UIColor(white: 1, alpha: 0).cgColor,
            ] as CFArray,
            locations: [0, 1]
        )!
        cg.drawLinearGradient(
            g, start: CGPoint(x: left, y: top), end: CGPoint(x: left, y: top + chartH), options: [])
        cg.restoreGState()

        let path = smoothPathThrough(points: pts)
        cg.setStrokeColor(brandMango.withAlphaComponent(0.92).cgColor)
        cg.setLineWidth(compact ? 5 : 6)
        cg.setLineCap(.round)
        cg.addPath(path)
        cg.strokePath()

        if !compact {
            let hint = "ADD RICHER TELEMETRY ON NEXT RIDE"
            let ha: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
                .foregroundColor: UIColor(white: 1, alpha: 0.35),
                .kern: 1.5,
            ]
            hint.draw(
                at: CGPoint(
                    x: rect.midX - hint.size(withAttributes: ha).width / 2, y: rect.midY + 20),
                withAttributes: ha)
        }
    }

    // MARK: Stat cards

    /// Distance + duration in one primary row (`.primary` in improved HTML).
    private static func drawPrimaryDistanceDurationRow(
        distanceValue: String,
        duration: String,
        in rect: CGRect,
        cg: CGContext
    ) {
        let corner: CGFloat = 46
        let path = UIBezierPath(roundedRect: rect, cornerRadius: corner)
        UIColor(white: 1, alpha: 0.04).setFill()
        path.fill()
        neonCyan.withAlphaComponent(0.55).setStroke()
        path.lineWidth = 1.5
        path.stroke()

        let lblAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 30, weight: .regular),
            .foregroundColor: UIColor(white: 1, alpha: 0.7),
        ]
        "DISTANCE".draw(at: CGPoint(x: rect.minX + 38, y: rect.minY + 22), withAttributes: lblAttrs)

        let valFont = UIFont.monospacedDigitSystemFont(ofSize: 88, weight: .bold)
        let valAttrs: [NSAttributedString.Key: Any] = [
            .font: valFont,
            .foregroundColor: UIColor.white,
            .kern: -2,
        ]
        let vs = distanceValue.size(withAttributes: valAttrs)
        distanceValue.draw(
            at: CGPoint(x: rect.minX + 38, y: rect.minY + 50), withAttributes: valAttrs)

        let unitFont = UIFont.monospacedDigitSystemFont(ofSize: 30, weight: .medium)
        let us = " km".size(withAttributes: [.font: unitFont])
        " km".draw(
            at: CGPoint(
                x: rect.minX + 38 + vs.width + 8, y: rect.minY + 50 + (vs.height - us.height) * 0.55
            ),
            withAttributes: [
                .font: unitFont,
                .foregroundColor: UIColor(white: 1, alpha: 0.85),
            ]
        )

        let durAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 30, weight: .medium),
            .foregroundColor: UIColor(white: 1, alpha: 0.75),
        ]
        let dw = duration.size(withAttributes: durAttrs)
        duration.draw(
            at: CGPoint(x: rect.maxX - 38 - dw.width, y: rect.minY + 28),
            withAttributes: durAttrs
        )
    }

    private static func drawSecondaryCard(
        label: String,
        value: String,
        unit: String? = nil,
        accent: UIColor?,
        in rect: CGRect,
        cornerRadius: CGFloat = 52,
        elevated: Bool = false,
        secondaryValue: String? = nil,
        secondaryLabel: String? = nil
    ) {
        let cg = UIGraphicsGetCurrentContext()!

        // Modern glass background with gradient
        let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
        cg.saveGState()
        cg.addPath(path.cgPath)
        cg.clip()

        // Gradient fill for glass effect
        let glassGrad = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                UIColor(white: 1, alpha: elevated ? 0.14 : 0.10).cgColor,
                UIColor(white: 1, alpha: elevated ? 0.06 : 0.03).cgColor,
            ] as CFArray,
            locations: [0, 1]
        )!
        cg.drawLinearGradient(
            glassGrad,
            start: CGPoint(x: rect.minX, y: rect.minY),
            end: CGPoint(x: rect.minX, y: rect.maxY),
            options: []
        )
        cg.restoreGState()

        // Subtle accent glow at top
        if let accent {
            cg.saveGState()
            cg.addPath(path.cgPath)
            cg.clip()
            let glowH: CGFloat = 60
            let glowGrad = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    accent.withAlphaComponent(0.25).cgColor,
                    accent.withAlphaComponent(0).cgColor,
                ] as CFArray,
                locations: [0, 1]
            )!
            cg.drawLinearGradient(
                glowGrad,
                start: CGPoint(x: rect.minX, y: rect.minY),
                end: CGPoint(x: rect.minX, y: rect.minY + glowH),
                options: []
            )
            cg.restoreGState()
        }

        // Border with gradient
        if let accent {
            cg.saveGState()
            cg.setLineWidth(1.5)
            let borderGrad = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    accent.withAlphaComponent(0.5).cgColor,
                    accent.withAlphaComponent(0.15).cgColor,
                ] as CFArray,
                locations: [0, 1]
            )!
            cg.addPath(path.cgPath)
            cg.replacePathWithStrokedPath()
            cg.clip()
            cg.drawLinearGradient(
                borderGrad,
                start: CGPoint(x: rect.minX, y: rect.minY),
                end: CGPoint(x: rect.minX, y: rect.maxY),
                options: []
            )
            cg.restoreGState()
        } else {
            UIColor(white: 1, alpha: 0.12).setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        // Label with icon-style indicator
        let labelFontSize: CGFloat = 13
        let la: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: labelFontSize, weight: .bold),
            .foregroundColor: (accent ?? UIColor.white).withAlphaComponent(0.7),
            .kern: 2.2,
        ]
        let labelPos = CGPoint(x: rect.minX + 28, y: rect.minY + 24)
        label.uppercased().draw(at: labelPos, withAttributes: la)

        // Main value - larger, centered
        let valFontSize: CGFloat = 72
        let valFont = UIFont.systemFont(ofSize: valFontSize, weight: .bold)
        var va: [NSAttributedString.Key: Any] = [
            .font: valFont,
            .foregroundColor: UIColor.white,
            .kern: -3,
        ]
        if let accent {
            va[.foregroundColor] = accent
        }

        let vs = value.size(withAttributes: va)

        // Unit styling
        let unitFontSize: CGFloat = 24
        let uf = UIFont.systemFont(ofSize: unitFontSize, weight: .semibold)
        let ua: [NSAttributedString.Key: Any] = [
            .font: uf,
            .foregroundColor: (accent ?? UIColor.white).withAlphaComponent(0.5),
        ]

        let us = unit?.size(withAttributes: ua) ?? .zero
        let totalWidth = vs.width + (unit != nil ? 4 + us.width : 0)

        // Center the value block
        let valX = rect.minX + (rect.width - totalWidth) / 2
        let valY = rect.minY + rect.height * 0.38 - vs.height / 2

        value.draw(at: CGPoint(x: valX, y: valY), withAttributes: va)

        if let unit {
            let unitY = valY + vs.height - us.height - 8
            unit.draw(at: CGPoint(x: valX + vs.width + 4, y: unitY), withAttributes: ua)
        }

        // Secondary stat line at bottom
        if let secVal = secondaryValue, let secLbl = secondaryLabel {
            let sepY = rect.maxY - 52
            let sepRect = CGRect(x: rect.minX + 28, y: sepY, width: rect.width - 56, height: 1)
            UIColor(white: 1, alpha: 0.1).setFill()
            UIRectFill(sepRect)

            let secAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 18, weight: .semibold),
                .foregroundColor: UIColor(white: 1, alpha: 0.6),
                .kern: 0.5,
            ]
            let secText = "\(secLbl) \(secVal)"
            let secSize = secText.size(withAttributes: secAttrs)
            secText.draw(
                at: CGPoint(x: rect.midX - secSize.width / 2, y: sepY + 10),
                withAttributes: secAttrs
            )
        }
    }

    /// Draws a segmented pill with dividers between stats
    private static func drawSegmentedPill(
        segments: [(value: String, label: String)],
        in rect: CGRect,
        cg: CGContext,
        accent: UIColor
    ) {
        guard !segments.isEmpty else { return }

        let corner = rect.height / 2
        let path = UIBezierPath(roundedRect: rect, cornerRadius: corner)

        // Glass background
        cg.saveGState()
        cg.addPath(path.cgPath)
        cg.clip()

        let glassGrad = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                UIColor(white: 1, alpha: 0.12).cgColor,
                UIColor(white: 1, alpha: 0.05).cgColor,
            ] as CFArray,
            locations: [0, 1]
        )!
        cg.drawLinearGradient(
            glassGrad,
            start: CGPoint(x: rect.minX, y: rect.minY),
            end: CGPoint(x: rect.minX, y: rect.maxY),
            options: []
        )
        cg.restoreGState()

        // Gradient border
        cg.saveGState()
        cg.setLineWidth(1.5)
        let borderGrad = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                accent.withAlphaComponent(0.4).cgColor,
                UIColor(white: 1, alpha: 0.15).cgColor,
            ] as CFArray,
            locations: [0, 1]
        )!
        cg.addPath(path.cgPath)
        cg.replacePathWithStrokedPath()
        cg.clip()
        cg.drawLinearGradient(
            borderGrad,
            start: CGPoint(x: rect.minX, y: rect.minY),
            end: CGPoint(x: rect.maxX, y: rect.minY),
            options: []
        )
        cg.restoreGState()

        // Draw segments
        let segCount = CGFloat(segments.count)
        let segWidth = rect.width / segCount
        let dividerInset: CGFloat = 14

        for (i, seg) in segments.enumerated() {
            let segX = rect.minX + CGFloat(i) * segWidth
            let segRect = CGRect(x: segX, y: rect.minY, width: segWidth, height: rect.height)

            // Value (top, larger)
            let valAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 26, weight: .bold),
                .foregroundColor: UIColor.white,
                .kern: -0.5,
            ]
            let valSize = seg.value.size(withAttributes: valAttrs)
            let valX = segRect.midX - valSize.width / 2
            let valY = segRect.midY - valSize.height / 2 - 6
            seg.value.draw(at: CGPoint(x: valX, y: valY), withAttributes: valAttrs)

            // Label (bottom, smaller)
            let lblAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: UIColor(white: 1, alpha: 0.5),
                .kern: 1.2,
            ]
            let lblSize = seg.label.size(withAttributes: lblAttrs)
            let lblX = segRect.midX - lblSize.width / 2
            let lblY = valY + valSize.height + 2
            seg.label.draw(at: CGPoint(x: lblX, y: lblY), withAttributes: lblAttrs)

            // Divider (except after last)
            if i < segments.count - 1 {
                let divX = segX + segWidth
                let divTop = rect.minY + dividerInset
                let divBottom = rect.maxY - dividerInset
                cg.setStrokeColor(UIColor(white: 1, alpha: 0.15).cgColor)
                cg.setLineWidth(1)
                cg.move(to: CGPoint(x: divX, y: divTop))
                cg.addLine(to: CGPoint(x: divX, y: divBottom))
                cg.strokePath()
            }
        }
    }

    private static func drawFooterBranding(width: CGFloat, bottomY: CGFloat) {
        // Subtle divider line
        let topLine = CGRect(x: sidePad, y: bottomY - 44, width: width - sidePad * 2, height: 1)
        UIColor(white: 1, alpha: 0.15).setFill()
        UIRectFill(topLine)

        // Mangox brand
        let brand = "MANGOX"
        let ba: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 22, weight: .bold),
            .foregroundColor: brandMango,
            .kern: 4,
        ]
        brand.draw(at: CGPoint(x: sidePad, y: bottomY - 32), withAttributes: ba)

        // Cycling icon + version
        let icon = "\u{1F6B2}"  // Bicycle emoji
        let sub = "\u{1F6B2}  TELEMETRY"
        let sa: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium),
            .foregroundColor: UIColor(white: 1, alpha: 0.55),
            .kern: 1.2,
        ]
        let sw = sub.size(withAttributes: sa)
        sub.draw(at: CGPoint(x: width - sidePad - sw.width, y: bottomY - 30), withAttributes: sa)
    }

}

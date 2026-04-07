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
        totalElevationGain: Double
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: cardSize)
        return renderer.image { ctx in
            StoryCardDrawing.draw(
                in: ctx.cgContext,
                size: cardSize,
                workout: workout,
                dominantZone: dominantZone,
                routeName: routeName,
                totalElevationGain: totalElevationGain
            )
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
    private static let brandMangoSoft = UIColor(red: 1, green: 186 / 255, blue: 50 / 255, alpha: 0.45)
    private static let brandMangoLight = UIColor(red: 1, green: 235 / 255, blue: 150 / 255, alpha: 1)
    private static let neonCyan = UIColor(red: 0.31, green: 0.675, blue: 0.996, alpha: 1)
    private static let neonCyanEnd = UIColor(red: 0, green: 0.949, blue: 0.996, alpha: 1)

    static func draw(
        in cgCtx: CGContext,
        size: CGSize,
        workout: Workout,
        dominantZone: PowerZone,
        routeName: String?,
        totalElevationGain: Double
    ) {
        let W = size.width
        let H = size.height

        UIGraphicsPushContext(cgCtx)
        defer { UIGraphicsPopContext() }

        drawAtmosphericBackground(in: size, dominantZone: dominantZone, cg: cgCtx)

        let title = StravaPostBuilder.buildTitle(
            workout: workout,
            routeName: routeName,
            dominantPowerZone: dominantZone,
            personalRecordNames: []
        )
        var y = topSafe

        drawTopMetaLine(date: workout.startDate, width: W, y: y)
        y += 40

        y += sectionGap

        let heroH: CGFloat = 300
        let heroRect = CGRect(x: sidePad, y: y, width: W - sidePad * 2, height: heroH)
        drawHeroPanel(workout: workout, in: heroRect, cg: cgCtx)
        y += heroH + sectionGap

        let distKm = workout.distance / 1000
        let heroValue = String(format: "%.2f", distKm)
        let speed = workout.displayAverageSpeedKmh
        let avgHR = workout.avgHR
        let calories = WorkoutExportService.estimateCalories(
            avgPower: workout.avgPower,
            durationSeconds: workout.duration
        )

        let primaryH: CGFloat = 158
        drawPrimaryDistanceDurationRow(
            distanceValue: heroValue,
            duration: AppFormat.duration(workout.duration),
            in: CGRect(x: sidePad, y: y, width: W - sidePad * 2, height: primaryH),
            cg: cgCtx
        )
        y += primaryH + sectionGap

        let colGap: CGFloat = 24
        let halfW = (W - sidePad * 2 - colGap) / 2
        let rowH: CGFloat = 128
        let hrAccent = avgHR > 0 ? brandMango : nil
        drawSecondaryCard(
            label: avgHR > 0 ? "Avg HR" : "Energy",
            value: avgHR > 0 ? "\(Int(avgHR.rounded()))" : "\(calories)",
            unit: avgHR > 0 ? "bpm" : "kcal",
            accent: hrAccent,
            in: CGRect(x: sidePad, y: y, width: halfW, height: rowH),
            cornerRadius: 36,
            elevated: true
        )
        drawSecondaryCard(
            label: "Speed",
            value: speed > 0 ? String(format: "%.1f", speed) : "—",
            unit: speed > 0 ? "km/h" : nil,
            accent: nil,
            in: CGRect(x: sidePad + halfW + colGap, y: y, width: halfW, height: rowH),
            cornerRadius: 36,
            elevated: true
        )
        y += rowH + sectionGap

        var meta: [String] = []
        if workout.avgHR > 0 { meta.append("HR \(Int(workout.avgHR.rounded())) / \(workout.maxHR)") }
        if workout.avgCadence > 0 { meta.append("\(Int(workout.avgCadence.rounded())) rpm") }
        if let r = routeName, !r.isEmpty { meta.append(r) }
        var metaBottomY = y
        if !meta.isEmpty {
            let metaStr = meta.joined(separator: "  ·  ")
            let a: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 33, weight: .regular),
                .foregroundColor: UIColor(white: 1, alpha: 0.7),
                .kern: 0.1,
            ]
            let metaSz = metaStr.size(withAttributes: a)
            metaStr.draw(at: CGPoint(x: sidePad, y: y), withAttributes: a)
            metaBottomY = y + metaSz.height
        }

        let footerLineY = H - bottomSafe - 48
        let titleRegionTop = metaBottomY + (meta.isEmpty ? 16 : 20)
        drawBottomTitlePoster(
            title: title,
            route: routeName,
            canvasWidth: W,
            cg: cgCtx,
            regionTop: titleRegionTop,
            footerLineY: footerLineY
        )

        drawFooterBranding(width: W, bottomY: H - bottomSafe)
    }

    // MARK: Background

    private static func drawAtmosphericBackground(in size: CGSize, dominantZone: PowerZone, cg: CGContext) {
        UIColor(red: 0.02, green: 0.02, blue: 0.02, alpha: 1).setFill()
        UIRectFill(CGRect(origin: .zero, size: size))

        let zc = UIColor(dominantZone.color)
        let zr = zc.cgColor.components?[0] ?? 0.3
        let zg = zc.cgColor.components?[1] ?? 0.3
        let zb = zc.cgColor.components?[2] ?? 0.4

        func orb(_ center: CGPoint, radius: CGFloat, r: CGFloat, g: CGFloat, b: CGFloat, alpha: CGFloat) {
            let cs = CGColorSpaceCreateDeviceRGB()
            let colors = [
                UIColor(red: r, green: g, blue: b, alpha: alpha).cgColor,
                UIColor(red: r, green: g, blue: b, alpha: 0).cgColor,
            ] as CFArray
            guard let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1]) else { return }
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
        orb(CGPoint(x: size.width * 0.85, y: size.height * 0.08), radius: 520, r: 1, g: 186 / 255, b: 50 / 255, alpha: 0.48)
        orb(CGPoint(x: size.width * 0.1, y: size.height * 0.92), radius: 580, r: zr * 0.9, g: zg * 0.9, b: zb, alpha: 0.45)
        orb(CGPoint(x: size.width * 0.35, y: size.height * 0.42), radius: 380, r: 0.15, g: 0.12, b: 0.22, alpha: 0.55)
        cg.restoreGState()

        let cs2 = CGColorSpaceCreateDeviceRGB()
        let overlay = CGGradient(
            colorsSpace: cs2,
            colors: [
                UIColor(red: zr * 0.25, green: zg * 0.25, blue: zb * 0.35, alpha: 0.35).cgColor,
                UIColor(red: 0.02, green: 0.02, blue: 0.04, alpha: 0.2).cgColor,
            ] as CFArray,
            locations: [0, 1]
        )!
        cg.drawLinearGradient(
            overlay,
            start: .zero,
            end: CGPoint(x: size.width, y: size.height),
            options: []
        )

        drawSubtleNoise(in: CGRect(origin: .zero, size: size), cg: cg)
    }

    private static func drawSubtleNoise(in rect: CGRect, cg: CGContext) {
        cg.saveGState()
        cg.setBlendMode(.overlay)
        cg.setAlpha(0.12)
        let step: CGFloat = 6
        var seed: UInt64 = 0x9E3779B97F4A7C15
        var x: CGFloat = 0
        while x < rect.width {
            var y: CGFloat = 0
            while y < rect.height {
                seed &+= 0xC6BC279692B5C323
                let g = CGFloat(seed % 1000) / 1000.0 * 0.08 + 0.04
                UIColor(white: g, alpha: 1).setFill()
                cg.fill(CGRect(x: x, y: y, width: step, height: step))
                y += step
            }
            x += step
        }
        cg.restoreGState()
    }

    // MARK: Header

    private static func drawTopMetaLine(date: Date, width: CGFloat, y: CGFloat) {
        let f = DateFormatter()
        f.dateFormat = "MMMM d"
        let dayPart = f.string(from: date).uppercased()
        let line = "\(dayPart) · RIDE"
        let a: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 33, weight: .regular),
            .foregroundColor: UIColor(white: 1, alpha: 0.7),
            .kern: 0.15,
        ]
        line.draw(at: CGPoint(x: sidePad, y: y), withAttributes: a)
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
    private static func wordWrappedTitle(_ title: String, maxWidth: CGFloat, fontSize: CGFloat) -> String {
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
            routeH = ceil(rStr.boundingRect(
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
        while fontSize > minTitleFont && measuredTitleHeight(title, fontSize: fontSize, maxWidth: maxW) > titleMaxH {
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

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: UIColor(white: 1, alpha: 1),
            .paragraphStyle: titlePara,
            .kern: -0.02 * fontSize,
        ]
        let titleAttrStr = NSAttributedString(string: displayTitle, attributes: titleAttrs)
        titleAttrStr.draw(in: CGRect(x: sidePad, y: blockStartY, width: maxW, height: titleH))

        if let route, !route.isEmpty {
            let rStr = NSAttributedString(string: route, attributes: routeAttrsBase)
            let ry = blockStartY + titleH + routeGap
            rStr.draw(in: CGRect(x: sidePad, y: ry, width: maxW, height: routeH))
        }
    }

    // MARK: Hero chart

    private static func drawHeroPanel(workout: Workout, in rect: CGRect, cg: CGContext) {
        let corner: CGFloat = 40
        let bgPath = UIBezierPath(roundedRect: rect, cornerRadius: corner)
        cg.saveGState()
        cg.addPath(bgPath.cgPath)
        cg.clip()
        let glassGrad = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                UIColor(white: 1, alpha: 0.12).cgColor,
                UIColor(white: 1, alpha: 0.04).cgColor,
            ] as CFArray,
            locations: [0, 1]
        )!
        cg.drawLinearGradient(glassGrad, start: CGPoint(x: rect.minX, y: rect.minY), end: CGPoint(x: rect.minX, y: rect.maxY), options: [])
        cg.restoreGState()

        UIColor(white: 1, alpha: 0.12).setStroke()
        bgPath.lineWidth = 1
        bgPath.stroke()

        let label = "POWER + HEART RATE"
        let la: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 28, weight: .medium),
            .foregroundColor: UIColor(white: 1, alpha: 0.6),
            .kern: 1.8,
        ]
        label.draw(at: CGPoint(x: rect.minX + 28, y: rect.minY + 24), withAttributes: la)

        let chartRect = rect.insetBy(dx: 28, dy: 56)
        let samples = workout.samples.sorted { $0.elapsedSeconds < $1.elapsedSeconds }
        if samples.count >= 3 {
            drawTelemetryChart(samples: samples, maxPower: workout.maxPower, in: chartRect, cg: cg, compact: true)
        } else {
            drawPlaceholderChart(in: chartRect, workout: workout, cg: cg, compact: true)
        }
    }

    private static func downsampleSamples(_ samples: [WorkoutSample], maxPoints: Int) -> [WorkoutSample] {
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
        compact: Bool = false
    ) {
        let lwPower: CGFloat = compact ? 8 : 7
        let lwHR: CGFloat = compact ? 5 : 5
        let areaTopAlpha: CGFloat = compact ? 0.12 : 0.22
        let glowBlur: CGFloat = compact ? 6 : 14

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
                UIColor(white: 1, alpha: areaTopAlpha).cgColor,
                UIColor(white: 1, alpha: 0).cgColor,
            ] as CFArray,
            locations: [0, 1]
        )!
        cg.drawLinearGradient(elevGrad, start: CGPoint(x: left, y: top), end: CGPoint(x: left, y: top + chartH), options: [])
        cg.restoreGState()

        // Power stroke (smooth-ish)
        let powerPath = smoothPathThrough(points: (0..<picked.count).map { CGPoint(x: xAt($0), y: yPower($0)) })
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
        cg.setShadow(offset: CGSize(width: 0, height: 0), blur: glowBlur, color: brandMango.withAlphaComponent(0.45).cgColor)
        cg.setStrokeColor(brandMango.cgColor)
        cg.setLineWidth(lwPower)
        cg.setLineCap(.round)
        cg.addPath(powerPath)
        cg.strokePath()
        cg.restoreGState()

        if hasHR {
            let hrPath = smoothPathThrough(points: (0..<picked.count).map { CGPoint(x: xAt($0), y: yHR($0)) })
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
            cg.fillEllipse(in: CGRect(x: cx - dotR, y: cy - dotR, width: dotR * 2, height: dotR * 2))

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

    private static func drawPlaceholderChart(in rect: CGRect, workout: Workout, cg: CGContext, compact: Bool = false) {
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
        cg.drawLinearGradient(g, start: CGPoint(x: left, y: top), end: CGPoint(x: left, y: top + chartH), options: [])
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
            hint.draw(at: CGPoint(x: rect.midX - hint.size(withAttributes: ha).width / 2, y: rect.midY + 20), withAttributes: ha)
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
        distanceValue.draw(at: CGPoint(x: rect.minX + 38, y: rect.minY + 50), withAttributes: valAttrs)

        let unitFont = UIFont.monospacedDigitSystemFont(ofSize: 30, weight: .medium)
        let us = " km".size(withAttributes: [.font: unitFont])
        " km".draw(
            at: CGPoint(x: rect.minX + 38 + vs.width + 8, y: rect.minY + 50 + (vs.height - us.height) * 0.55),
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
        cornerRadius: CGFloat = 28,
        elevated: Bool = false
    ) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
        UIColor(white: 1, alpha: elevated ? 0.08 : 0.06).setFill()
        path.fill()

        if let accent {
            accent.withAlphaComponent(0.35).setStroke()
        } else {
            UIColor(white: 1, alpha: 0.1).setStroke()
        }
        path.lineWidth = 1
        path.stroke()

        let la: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: UIColor(white: 1, alpha: 0.52),
            .kern: 1.8,
        ]
        label.draw(at: CGPoint(x: rect.minX + 22, y: rect.minY + 18), withAttributes: la)

        let valFont = UIFont.monospacedDigitSystemFont(ofSize: 48, weight: .bold)
        var va: [NSAttributedString.Key: Any] = [
            .font: valFont,
            .foregroundColor: UIColor.white,
            .kern: -1,
        ]
        if let accent {
            va[.foregroundColor] = accent
        }
        value.draw(at: CGPoint(x: rect.minX + 22, y: rect.minY + 46), withAttributes: va)

        if let unit {
            let uf = UIFont.monospacedDigitSystemFont(ofSize: 20, weight: .medium)
            let ua: [NSAttributedString.Key: Any] = [
                .font: uf,
                .foregroundColor: (accent ?? UIColor.white).withAlphaComponent(0.55),
            ]
            let vs = value.size(withAttributes: va)
            unit.draw(at: CGPoint(x: rect.minX + 22 + vs.width + 6, y: rect.minY + 56), withAttributes: ua)
        }
    }

    private static func drawFooterBranding(width: CGFloat, bottomY: CGFloat) {
        let topLine = CGRect(x: sidePad, y: bottomY - 44, width: width - sidePad * 2, height: 1)
        UIColor(white: 1, alpha: 0.2).setFill()
        UIRectFill(topLine)

        let brand = "MANGOX"
        let ba: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 20, weight: .semibold),
            .foregroundColor: UIColor(white: 1, alpha: 0.85),
            .kern: 3,
        ]
        brand.draw(at: CGPoint(x: sidePad, y: bottomY - 30), withAttributes: ba)

        let sub = "RIDE TELEMETRY"
        let sa: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .regular),
            .foregroundColor: UIColor(white: 1, alpha: 0.8),
            .kern: 1.5,
        ]
        let sw = sub.size(withAttributes: sa)
        sub.draw(at: CGPoint(x: width - sidePad - sw.width, y: bottomY - 28), withAttributes: sa)
    }
}

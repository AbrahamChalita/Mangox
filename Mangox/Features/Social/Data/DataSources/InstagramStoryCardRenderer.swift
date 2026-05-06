import SwiftUI
import UIKit

enum InstagramStoryCardRenderer {
    static let cardSize = CGSize(width: 1080, height: 1920)

    /// Instagram expects ~1080×1920 logical pixels; default `UIGraphicsImageRenderer` uses **device scale** (2–3×),
    /// which multiplies bitmap cost (~9× memory and CPU) without improving Stories output.
    private static func storyRendererFormat(opaque: Bool) -> UIGraphicsImageRendererFormat {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = opaque
        return format
    }

    @MainActor
    static func render(
        workout: Workout,
        dominantZone: PowerZone,
        routeName: String?,
        totalElevationGain: Double,
        personalRecordNames: [String] = [],
        options: InstagramStoryCardOptions? = nil,
        sessionKind: InstagramStoryCardSessionKind? = nil,
        whoopStrain: Double? = nil,
        whoopRecovery: Double? = nil,
        aiTitle: String? = nil,
        backgroundImage: UIImage? = nil
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: cardSize, format: storyRendererFormat(opaque: false))
        let resolvedOptions = options ?? .default
        let resolvedSession = sessionKind ?? InstagramStoryCardSessionKind.resolve(
            workout: workout,
            routeName: routeName,
            totalElevationGain: totalElevationGain
        )
        return renderer.image { ctx in
            StoryCardDrawing.draw(
                in: ctx.cgContext,
                size: cardSize,
                workout: workout,
                dominantZone: dominantZone,
                routeName: routeName,
                totalElevationGain: totalElevationGain,
                personalRecordNames: personalRecordNames,
                options: resolvedOptions,
                sessionKind: resolvedSession,
                whoopStrain: whoopStrain,
                whoopRecovery: whoopRecovery,
                aiTitle: aiTitle,
                backgroundImage: backgroundImage
            )
        }
    }

    @MainActor
    static func renderBackgroundOnly(
        dominantZone: PowerZone,
        options: InstagramStoryCardOptions,
        backgroundImage: UIImage? = nil
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: cardSize, format: storyRendererFormat(opaque: false))
        return renderer.image { ctx in
            StoryCardDrawing.drawBackground(
                in: ctx.cgContext,
                size: cardSize,
                dominantZone: dominantZone,
                options: options,
                backgroundImage: backgroundImage
            )
        }
    }

    @MainActor
    static func renderAtmosphericBackgroundOnly(
        dominantZone: PowerZone,
        options: InstagramStoryCardOptions
    ) -> UIImage {
        renderBackgroundOnly(dominantZone: dominantZone, options: options)
    }

    @MainActor
    static func renderStickerLayer(
        fullCard: UIImage,
        scale: CGFloat = 0.84,
        cornerRadius: CGFloat = 52
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1

        let renderer = UIGraphicsImageRenderer(size: cardSize, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let w = cardSize.width * scale
            let h = cardSize.height * scale
            let rect = CGRect(
                x: (cardSize.width - w) / 2,
                y: (cardSize.height - h) / 2,
                width: w,
                height: h
            )
            let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)

            cg.clear(CGRect(origin: .zero, size: cardSize))
            cg.saveGState()
            cg.setShadow(
                offset: CGSize(width: 0, height: 30),
                blur: 90,
                color: UIColor.black.withAlphaComponent(0.34).cgColor
            )
            cg.addPath(path.cgPath)
            cg.setFillColor(UIColor.black.withAlphaComponent(0.22).cgColor)
            cg.fillPath()
            cg.restoreGState()

            cg.saveGState()
            cg.addPath(path.cgPath)
            cg.clip()
            fullCard.draw(in: rect)
            cg.restoreGState()

            cg.addPath(path.cgPath)
            cg.setStrokeColor(StoryCardDesign.panelBorder.cgColor)
            cg.setLineWidth(2)
            cg.strokePath()
        }
    }
}

private enum StoryCardFontToken {
    static func ui(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let fontName: String
        switch weight {
        case .ultraLight, .thin, .light:
            fontName = "Manrope-Light"
        case .medium, .semibold, .bold, .heavy, .black:
            fontName = "Manrope-Medium"
        default:
            fontName = "Manrope-Regular"
        }

        return UIFont(name: fontName, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    static func mono(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let fontName: String
        switch weight {
        case .ultraLight, .thin, .light:
            fontName = "GeistMono-Light"
        case .medium, .semibold, .bold, .heavy, .black:
            fontName = "GeistMono-Medium"
        default:
            fontName = "GeistMono-Regular"
        }

        return UIFont(name: fontName, size: size) ?? .monospacedSystemFont(ofSize: size, weight: weight)
    }
}

private enum StoryCardDesign {
    static let canvasBackground = UIColor(AppColor.bg0)
    static let canvasSecondary = UIColor(AppColor.bg2)
    static let panelTop = UIColor(AppColor.bg2).withAlphaComponent(0.96)
    static let panelBottom = UIColor(AppColor.bg3).withAlphaComponent(0.94)
    static let panelBorder = UIColor(AppColor.hair2)
    static let divider = UIColor(AppColor.hair2)
    static let textPrimary = UIColor(AppColor.fg0)
    static let textSecondary = UIColor(AppColor.fg1)
    static let textMuted = UIColor(AppColor.fg2)
    static let textQuiet = UIColor(AppColor.fg3)
    static let accentMango = UIColor(AppColor.mango)
    static let accentBlue = UIColor(AppColor.blue)
    static let accentYellow = UIColor(AppColor.yellow)
    static let whoopTeal = UIColor(AppColor.whoop)
    static let panelShadow = UIColor.black.withAlphaComponent(0.28)
    static let panelRadius = MangoxRadius.overlay.rawValue
    static let badgeRadius = MangoxRadius.button.rawValue

    static func accentColor(for accent: InstagramStoryCardOptions.Accent, dominantZone: PowerZone) -> UIColor {
        switch accent {
        case .dominantZone:
            return UIColor(dominantZone.color)
        case .brandMango:
            return accentMango
        }
    }
}

private enum StoryCardDrawing {
    private static let sidePad: CGFloat = 64
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE  •  d MMM"
        return formatter
    }()

    static func draw(
        in cg: CGContext,
        size: CGSize,
        workout: Workout,
        dominantZone: PowerZone,
        routeName: String?,
        totalElevationGain: Double,
        personalRecordNames: [String],
        options: InstagramStoryCardOptions,
        sessionKind: InstagramStoryCardSessionKind,
        whoopStrain: Double?,
        whoopRecovery: Double?,
        aiTitle: String?,
        backgroundImage: UIImage?
    ) {
        UIGraphicsPushContext(cg)
        defer { UIGraphicsPopContext() }

        let accent = StoryCardDesign.accentColor(for: options.accent, dominantZone: dominantZone)
        drawBackground(
            in: cg,
            size: size,
            dominantZone: dominantZone,
            options: options,
            backgroundImage: backgroundImage
        )

        if options.template != .cleanStats {
            drawStudioTemplate(
                in: cg,
                size: size,
                workout: workout,
                dominantZone: dominantZone,
                routeName: routeName,
                totalElevationGain: totalElevationGain,
                personalRecordNames: personalRecordNames,
                options: options,
                sessionKind: sessionKind,
                whoopStrain: whoopStrain,
                whoopRecovery: whoopRecovery,
                aiTitle: aiTitle
            )
            return
        }

        let heroTitle = resolvedHeroTitle(
            from: aiTitle,
            workout: workout,
            routeName: routeName,
            dominantZone: dominantZone,
            personalRecordNames: personalRecordNames
        )
        let heroLines = titleLines(for: heroTitle)
        let topY: CGFloat = 100

        if options.showHeader {
            drawHeader(
                brandTitle: options.showBrandBadge ? "MANGOX SHARE" : "RIDE SHARE",
                dateTitle: dateFormatter.string(from: workout.startDate).uppercased(),
                accent: accent,
                y: topY,
                width: size.width,
                cg: cg
            )
        }

        let heroY: CGFloat = options.showHeader ? 220 : 150
        drawHeroBlock(
            titleLines: heroLines,
            workout: workout,
            routeName: routeName,
            showRouteName: options.showRouteName && !options.privacyHideRoute,
            sessionKind: sessionKind,
            dominantZone: dominantZone,
            accent: accent,
            y: heroY,
            width: size.width,
            showHeroTitle: options.showHeroTitle,
            cg: cg
        )

        let summaryCardH: CGFloat = 220
        let trainingCardH = trainingLoadCardHeight(
            options: options,
            whoopStrain: whoopStrain,
            whoopRecovery: whoopRecovery
        )
        let quickStatsH: CGFloat = 120
        let bottomSafe: CGFloat = 40
        let minSectionGap: CGFloat = 30

        var sectionCount = 0
        var contentH: CGFloat = 0
        if options.showBottomStrip { sectionCount += 1; contentH += quickStatsH }
        if options.showTrainingLoad { sectionCount += 1; contentH += trainingCardH }
        if options.showSummaryCards { sectionCount += 1; contentH += summaryCardH }

        let heroBottom: CGFloat = heroY + 48 + 300 + 190
        let availableH = size.height - heroBottom - bottomSafe
        let gaps = max(1, sectionCount)
        let sectionGap = min(max(minSectionGap, (availableH - contentH) / CGFloat(gaps)), 80)

        var cursor = heroBottom + sectionGap

        if options.showBottomStrip {
            drawQuickStatsRow(
                workout: workout,
                totalElevationGain: totalElevationGain,
                options: options,
                y: cursor,
                width: size.width,
                cg: cg
            )
            cursor += quickStatsH + sectionGap
        }

        if options.showTrainingLoad {
            drawTrainingLoadCard(
                workout: workout,
                dominantZone: dominantZone,
                accent: accent,
                y: cursor,
                width: size.width,
                height: trainingCardH,
                options: options,
                whoopStrain: whoopStrain,
                whoopRecovery: whoopRecovery,
                cg: cg
            )
            cursor += trainingCardH + sectionGap
        }

        if options.showSummaryCards {
            drawBottomSummaryCards(
                workout: workout,
                accent: accent,
                options: options,
                y: cursor,
                width: size.width,
                cg: cg
            )
        }
    }

    static func drawBackground(
        in cg: CGContext,
        size: CGSize,
        dominantZone: PowerZone,
        options: InstagramStoryCardOptions,
        backgroundImage: UIImage?
    ) {
        switch options.backgroundSource {
        case .preset:
            if let image = UIImage(named: options.selectedPreset.assetName) {
                drawPhotoBackground(image, in: size, cg: cg)
            } else {
                drawAtmosphericBackground(in: size, dominantZone: dominantZone, options: options, cg: cg)
            }
        case .custom:
            if let image = backgroundImage {
                drawPhotoBackground(image, in: size, cg: cg)
            } else {
                drawAtmosphericBackground(in: size, dominantZone: dominantZone, options: options, cg: cg)
            }
        case .none:
            drawAtmosphericBackground(in: size, dominantZone: dominantZone, options: options, cg: cg)
        }

        drawForegroundScrim(in: size, cg: cg)
    }

    private static func drawPhotoBackground(_ image: UIImage, in size: CGSize, cg: CGContext) {
        let prepared = ImageProcessing.prepareStoryBackground(from: image)
        prepared.draw(in: CGRect(origin: .zero, size: size))

        cg.saveGState()
        cg.setFillColor(StoryCardDesign.canvasBackground.withAlphaComponent(0.70).cgColor)
        cg.fill(CGRect(origin: .zero, size: size))
        cg.restoreGState()
    }

    private static func drawAtmosphericBackground(
        in size: CGSize,
        dominantZone: PowerZone,
        options: InstagramStoryCardOptions,
        cg: CGContext
    ) {
        StoryCardDesign.canvasBackground.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))

        let accent = StoryCardDesign.accentColor(for: options.accent, dominantZone: dominantZone)
        fillRadial(
            center: CGPoint(x: size.width * 0.82, y: size.height * 0.88),
            radius: 340,
            color: accent.withAlphaComponent(options.visualStyle == .neonNight ? 0.36 : 0.24),
            cg: cg
        )
        fillRadial(
            center: CGPoint(x: size.width * 0.20, y: size.height * 0.15),
            radius: 260,
            color: secondaryAtmosphereColor(for: options.visualStyle).withAlphaComponent(0.16),
            cg: cg
        )
        fillRadial(
            center: CGPoint(x: size.width * 0.50, y: size.height * 0.48),
            radius: 560,
            color: StoryCardDesign.canvasSecondary.withAlphaComponent(0.16),
            cg: cg
        )
    }

    private static func drawForegroundScrim(in size: CGSize, cg: CGContext) {
        let colors = [
            StoryCardDesign.canvasBackground.withAlphaComponent(0.10).cgColor,
            StoryCardDesign.canvasBackground.withAlphaComponent(0.04).cgColor,
            StoryCardDesign.canvasBackground.withAlphaComponent(0.16).cgColor,
            StoryCardDesign.canvasBackground.withAlphaComponent(0.26).cgColor,
        ] as CFArray
        let locations: [CGFloat] = [0, 0.30, 0.68, 1]

        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: locations
        ) else { return }

        cg.drawLinearGradient(
            gradient,
            start: CGPoint(x: size.width / 2, y: 0),
            end: CGPoint(x: size.width / 2, y: size.height),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }

    private static func drawHeader(
        brandTitle: String,
        dateTitle: String,
        accent: UIColor,
        y: CGFloat,
        width: CGFloat,
        cg: CGContext
    ) {
        let dividerY = y + 10
        cg.setStrokeColor(StoryCardDesign.divider.cgColor)
        cg.setLineWidth(1)
        cg.move(to: CGPoint(x: sidePad, y: dividerY))
        cg.addLine(to: CGPoint(x: width - sidePad, y: dividerY))
        cg.strokePath()

        let dotRect = CGRect(x: sidePad + 2, y: dividerY + 22, width: 18, height: 18)
        let dotPath = UIBezierPath(ovalIn: dotRect)
        accent.setFill()
        dotPath.fill()

        brandTitle.draw(
            at: CGPoint(x: sidePad + 34, y: dividerY + 14),
            withAttributes: [
                .font: StoryCardFontToken.ui(size: 34, weight: .medium),
                .foregroundColor: StoryCardDesign.textPrimary,
                .kern: 2.2,
            ]
        )

        let dateAttrs: [NSAttributedString.Key: Any] = [
            .font: StoryCardFontToken.mono(size: 28, weight: .medium),
            .foregroundColor: StoryCardDesign.textQuiet,
            .kern: 1.6,
        ]
        let dateSize = dateTitle.size(withAttributes: dateAttrs)
        dateTitle.draw(
            at: CGPoint(x: width - sidePad - dateSize.width, y: dividerY + 16),
            withAttributes: dateAttrs
        )
    }

    private static func drawHeroBlock(
        titleLines: [String],
        workout: Workout,
        routeName: String?,
        showRouteName: Bool,
        sessionKind: InstagramStoryCardSessionKind,
        dominantZone: PowerZone,
        accent: UIColor,
        y: CGFloat,
        width: CGFloat,
        showHeroTitle: Bool,
        cg: CGContext
    ) {
        let eyebrow = heroEyebrowText(
            routeName: routeName,
            showRouteName: showRouteName,
            sessionKind: sessionKind,
            dominantZone: dominantZone
        )
        eyebrow.draw(
            at: CGPoint(x: sidePad, y: y),
            withAttributes: [
                .font: StoryCardFontToken.mono(size: 24, weight: .medium),
                .foregroundColor: accent.withAlphaComponent(0.94),
                .kern: 2.0,
            ]
        )

        let titleRectY = y + 48
        if showHeroTitle {
            let firstLine = titleLines.first ?? ""
            let secondLine = titleLines.count > 1 ? titleLines[1] : ""

            let firstAttrs: [NSAttributedString.Key: Any] = [
                .font: StoryCardFontToken.ui(size: 112, weight: .heavy),
                .foregroundColor: StoryCardDesign.textPrimary,
                .kern: -4.6,
            ]
            firstLine.draw(
                at: CGPoint(x: sidePad, y: titleRectY),
                withAttributes: firstAttrs
            )

            if !secondLine.isEmpty {
                secondLine.draw(
                    at: CGPoint(x: sidePad, y: titleRectY + 118),
                    withAttributes: [
                        .font: StoryCardFontToken.ui(size: 108, weight: .heavy),
                        .foregroundColor: StoryCardDesign.textQuiet,
                        .kern: -4.6,
                    ]
                )
            }
        }

        let distanceValue = String(format: "%.1f", workout.distance / 1000)
        let metricY = titleRectY + 300

        let distanceAttrs: [NSAttributedString.Key: Any] = [
            .font: StoryCardFontToken.mono(size: 126, weight: .heavy),
            .foregroundColor: StoryCardDesign.textPrimary,
            .kern: -4.6,
        ]
        let unitAttrs: [NSAttributedString.Key: Any] = [
            .font: StoryCardFontToken.ui(size: 46, weight: .medium),
            .foregroundColor: StoryCardDesign.textMuted,
        ]
        let size = distanceValue.size(withAttributes: distanceAttrs)
        distanceValue.draw(at: CGPoint(x: sidePad, y: metricY), withAttributes: distanceAttrs)
        "km".draw(
            at: CGPoint(x: sidePad + size.width + 8, y: metricY + 58),
            withAttributes: unitAttrs
        )

        let movingTime = AppFormat.duration(workout.duration)
        let movingAttrs: [NSAttributedString.Key: Any] = [
            .font: StoryCardFontToken.mono(size: 64, weight: .bold),
            .foregroundColor: StoryCardDesign.textPrimary,
            .kern: -2.0,
        ]
        let movingLabelAttrs: [NSAttributedString.Key: Any] = [
            .font: StoryCardFontToken.mono(size: 18, weight: .medium),
            .foregroundColor: StoryCardDesign.textQuiet,
            .kern: 1.7,
        ]
        let movingX = width - sidePad - 255
        movingTime.draw(
            at: CGPoint(x: movingX, y: metricY + 28),
            withAttributes: movingAttrs
        )
        "MOVING TIME".draw(
            at: CGPoint(x: movingX + 18, y: metricY + 108),
            withAttributes: movingLabelAttrs
        )

        let dividerY = metricY + 190
        cg.setStrokeColor(StoryCardDesign.divider.cgColor)
        cg.setLineWidth(1)
        cg.move(to: CGPoint(x: sidePad, y: dividerY))
        cg.addLine(to: CGPoint(x: width - sidePad, y: dividerY))
        cg.strokePath()
    }

    private static func drawQuickStatsRow(
        workout: Workout,
        totalElevationGain: Double,
        options: InstagramStoryCardOptions,
        y: CGFloat,
        width: CGFloat,
        cg: CGContext
    ) {
        var slots = options.quickStatSlots
            .prefix(4)
            .compactMap { metricSlot($0, workout: workout, totalElevationGain: totalElevationGain, options: options) }
        if slots.isEmpty {
            slots = [
                metricSlot(.distance, workout: workout, totalElevationGain: totalElevationGain, options: options),
                metricSlot(.movingTime, workout: workout, totalElevationGain: totalElevationGain, options: options),
                metricSlot(.elevation, workout: workout, totalElevationGain: totalElevationGain, options: options),
                metricSlot(.speed, workout: workout, totalElevationGain: totalElevationGain, options: options),
            ].compactMap { $0 }
        }

        let gap: CGFloat = 18
        let count = slots.count
        let cardWidth = (width - sidePad * 2 - gap * CGFloat(max(0, count - 1))) / CGFloat(max(count, 1))

        for index in 0..<count {
            let rect = CGRect(
                x: sidePad + CGFloat(index) * (cardWidth + gap),
                y: y,
                width: cardWidth,
                height: 120
            )
            drawPanel(in: rect, cornerRadius: StoryCardDesign.panelRadius, cg: cg)

            let valueAttrs: [NSAttributedString.Key: Any] = [
                .font: StoryCardFontToken.mono(size: 54, weight: .bold),
                .foregroundColor: StoryCardDesign.textPrimary,
                .kern: -1.8,
            ]
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: StoryCardFontToken.mono(size: 15, weight: .medium),
                .foregroundColor: StoryCardDesign.textQuiet,
                .kern: 1.3,
            ]
            let value = slots[index].value
            let label = slots[index].label
            let valueSize = value.size(withAttributes: valueAttrs)
            value.draw(
                at: CGPoint(x: rect.midX - valueSize.width / 2, y: rect.minY + 24),
                withAttributes: valueAttrs
            )

            let labelSize = label.size(withAttributes: labelAttrs)
            label.draw(
                at: CGPoint(x: rect.midX - labelSize.width / 2, y: rect.minY + 78),
                withAttributes: labelAttrs
            )
        }
    }

    private static func trainingLoadCardHeight(
        options: InstagramStoryCardOptions,
        whoopStrain: Double?,
        whoopRecovery: Double?
    ) -> CGFloat {
        guard options.showTrainingLoad else { return 0 }
        return hasWhoopStoryLine(options: options, whoopStrain: whoopStrain, whoopRecovery: whoopRecovery) ? 306 : 270
    }

    private static func hasWhoopStoryLine(
        options: InstagramStoryCardOptions,
        whoopStrain: Double?,
        whoopRecovery: Double?
    ) -> Bool {
        guard options.showWhoopReadiness else { return false }
        if let r = whoopRecovery, r > 0 { return true }
        if let s = whoopStrain, s > 0 { return true }
        return false
    }

    private static func whoopStoryLineText(strain: Double?, recovery: Double?) -> String? {
        var parts: [String] = []
        if let r = recovery, r > 0 {
            parts.append("Recovery \(Int(r.rounded()))%")
        }
        if let s = strain, s > 0 {
            parts.append(String(format: "Strain %.1f", min(s, 21)))
        }
        guard !parts.isEmpty else { return nil }
        return "WHOOP · " + parts.joined(separator: " · ")
    }

    private static func drawTrainingLoadCard(
        workout: Workout,
        dominantZone: PowerZone,
        accent: UIColor,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        options: InstagramStoryCardOptions,
        whoopStrain: Double?,
        whoopRecovery: Double?,
        cg: CGContext
    ) {
        let rect = CGRect(x: sidePad, y: y, width: width - sidePad * 2, height: height)
        drawPanel(in: rect, cornerRadius: StoryCardDesign.panelRadius, cg: cg)

        "TRAINING LOAD".draw(
            at: CGPoint(x: rect.minX + 26, y: rect.minY + 24),
            withAttributes: [
                .font: StoryCardFontToken.mono(size: 18, weight: .medium),
                .foregroundColor: StoryCardDesign.textQuiet,
                .kern: 1.8,
            ]
        )

        let status = trainingStatus(for: workout).uppercased()
        let badgeFont = StoryCardFontToken.mono(size: 22, weight: .medium)
        let badgeKern: CGFloat = 1.8
        let badgeAttrs: [NSAttributedString.Key: Any] = [
            .font: badgeFont,
            .kern: badgeKern,
        ]
        let textWidth = status.size(withAttributes: badgeAttrs).width
        let horizontalPadding: CGFloat = 26
        let rightInsetFromPanel: CGFloat = 28
        let badgeWidth = min(
            max(120, ceil(textWidth + horizontalPadding * 2)),
            rect.width - 52 - 200
        )
        let badgeHeight: CGFloat = 44
        let badgeRect = CGRect(
            x: rect.maxX - rightInsetFromPanel - badgeWidth,
            y: rect.minY + 20,
            width: badgeWidth,
            height: badgeHeight
        )
        let badgeCorner = min(StoryCardDesign.badgeRadius, badgeHeight / 2)
        let badgePath = UIBezierPath(roundedRect: badgeRect, cornerRadius: badgeCorner)
        accent.withAlphaComponent(0.16).setFill()
        badgePath.fill()
        accent.withAlphaComponent(0.28).setStroke()
        badgePath.lineWidth = 1
        badgePath.stroke()
        status.draw(
            at: CGPoint(x: badgeRect.minX + horizontalPadding, y: badgeRect.minY + 10),
            withAttributes: [
                .font: badgeFont,
                .foregroundColor: accent.withAlphaComponent(0.92),
                .kern: badgeKern,
            ]
        )

        let load = trainingLoadValue(for: workout)
        let loadText = "\(load)"
        let loadAttrs: [NSAttributedString.Key: Any] = [
            .font: StoryCardFontToken.mono(size: 88, weight: .heavy),
            .foregroundColor: StoryCardDesign.textPrimary,
            .kern: -3.6,
        ]
        let loadSize = loadText.size(withAttributes: loadAttrs)
        let loadOriginY = rect.minY + 76
        loadText.draw(
            at: CGPoint(x: rect.minX + 26, y: loadOriginY),
            withAttributes: loadAttrs
        )

        let slashText = "/ 100"
        let slashAttrs: [NSAttributedString.Key: Any] = [
            .font: StoryCardFontToken.mono(size: 38, weight: .medium),
            .foregroundColor: StoryCardDesign.textQuiet,
            .kern: -1.0,
        ]
        let slashSize = slashText.size(withAttributes: slashAttrs)
        let slashOriginY = rect.minY + 122
        slashText.draw(
            at: CGPoint(x: rect.minX + 26 + loadSize.width + 8, y: slashOriginY),
            withAttributes: slashAttrs
        )

        let scoreBlockBottom = max(
            loadOriginY + loadSize.height,
            slashOriginY + slashSize.height
        )

        let whoopLine = hasWhoopStoryLine(options: options, whoopStrain: whoopStrain, whoopRecovery: whoopRecovery)
            ? whoopStoryLineText(strain: whoopStrain, recovery: whoopRecovery)
            : nil
        let whoopAttrs: [NSAttributedString.Key: Any] = [
            .font: StoryCardFontToken.mono(size: 17, weight: .medium),
            .foregroundColor: StoryCardDesign.whoopTeal,
            .kern: 1.1,
        ]
        var zoneContentTop = scoreBlockBottom + 18
        if let line = whoopLine {
            let whoopY = scoreBlockBottom + 18
            line.draw(
                at: CGPoint(x: rect.minX + 26, y: whoopY),
                withAttributes: whoopAttrs
            )
            zoneContentTop = whoopY + line.size(withAttributes: whoopAttrs).height + 14
        }

        let segments = zoneDistribution(for: workout, dominantZone: dominantZone)
        let barY = zoneContentTop
        let barX = rect.minX + 26
        let totalBarWidth = rect.width - 52
        let barHeight: CGFloat = 16
        var cursor = barX
        let gap: CGFloat = 8
        let available = totalBarWidth - gap * CGFloat(max(0, segments.count - 1))
        for segment in segments {
            let widthSegment = max(28, available * CGFloat(segment.percentage))
            let barRect = CGRect(x: cursor, y: barY, width: widthSegment, height: barHeight)
            let barPath = UIBezierPath(roundedRect: barRect, cornerRadius: 8)
            segment.color.setFill()
            barPath.fill()
            cursor += widthSegment + gap
        }

        let legendY = barY + 34
        let itemWidth = totalBarWidth / CGFloat(segments.count)
        for (index, segment) in segments.enumerated() {
            let x = barX + CGFloat(index) * itemWidth
            let dotRect = CGRect(x: x, y: legendY + 10, width: 10, height: 10)
            UIBezierPath(ovalIn: dotRect).fill(with: .normal, alpha: 1)
            segment.color.setFill()
            UIBezierPath(ovalIn: dotRect).fill()

            let label = "Z\(segment.zone.id)  \(Int((segment.percentage * 100).rounded()))%"
            label.draw(
                at: CGPoint(x: x + 18, y: legendY),
                withAttributes: [
                    .font: StoryCardFontToken.mono(size: 15, weight: .medium),
                    .foregroundColor: StoryCardDesign.textSecondary,
                    .kern: 0.8,
                ]
            )
        }
    }

    private static func drawBottomSummaryCards(
        workout: Workout,
        accent: UIColor,
        options: InstagramStoryCardOptions,
        y: CGFloat,
        width: CGFloat,
        cg: CGContext
    ) {
        let gap: CGFloat = 20
        let totalWidth = width - sidePad * 2
        let cardWidth = (totalWidth - gap) / 2
        let leftRect = CGRect(x: sidePad, y: y, width: cardWidth, height: 220)
        let rightRect = CGRect(x: sidePad + cardWidth + gap, y: y, width: cardWidth, height: 220)

        drawPanel(in: leftRect, cornerRadius: StoryCardDesign.panelRadius, cg: cg)
        drawPanel(in: rightRect, cornerRadius: StoryCardDesign.panelRadius, cg: cg)

        let leftTitle = options.privacyHidePower ? "MOVING TIME" : "AVG POWER"
        leftTitle.draw(
            at: CGPoint(x: leftRect.minX + 24, y: leftRect.minY + 22),
            withAttributes: [
                .font: StoryCardFontToken.mono(size: 18, weight: .medium),
                .foregroundColor: StoryCardDesign.textQuiet,
                .kern: 1.7,
            ]
        )

        let powerValue = options.privacyHidePower
            ? AppFormat.duration(workout.duration)
            : metricText(Int(workout.avgPower.rounded()), fallback: "—")
        let powerAttrs: [NSAttributedString.Key: Any] = [
            .font: StoryCardFontToken.mono(size: options.privacyHidePower ? 52 : 68, weight: .heavy),
            .foregroundColor: StoryCardDesign.textPrimary,
            .kern: -2.6,
        ]
        let powerSize = powerValue.size(withAttributes: powerAttrs)
        powerValue.draw(at: CGPoint(x: leftRect.minX + 24, y: leftRect.minY + 66), withAttributes: powerAttrs)
        if !options.privacyHidePower {
            "w".draw(
                at: CGPoint(x: leftRect.minX + 24 + powerSize.width + 10, y: leftRect.minY + 109),
                withAttributes: [
                    .font: StoryCardFontToken.ui(size: 28, weight: .medium),
                    .foregroundColor: StoryCardDesign.textMuted,
                ]
            )
        }

        let npText = options.privacyHidePower
            ? String(format: "%.1f km", workout.distance / 1000)
            : "NP \(metricText(Int(workout.normalizedPower.rounded()), fallback: "—"))w"
        let ifText = options.privacyHidePower
            ? "\(estimatedCalories(for: workout)) kcal"
            : "IF \(String(format: "%.2f", max(0, workout.intensityFactor)))"
        "\(npText)  •  \(ifText)".draw(
            at: CGPoint(x: leftRect.minX + 24, y: leftRect.maxY - 44),
            withAttributes: [
                .font: StoryCardFontToken.mono(size: 18, weight: .medium),
                .foregroundColor: StoryCardDesign.textMuted,
            ]
        )

        "TSS • FTP EFFORT".draw(
            at: CGPoint(x: rightRect.minX + 24, y: rightRect.minY + 22),
            withAttributes: [
                .font: StoryCardFontToken.mono(size: 18, weight: .medium),
                .foregroundColor: StoryCardDesign.textQuiet,
                .kern: 1.7,
            ]
        )

        let tssValue = metricText(Int(workout.tss.rounded()), fallback: "—")
        let tssAttrs: [NSAttributedString.Key: Any] = [
            .font: StoryCardFontToken.mono(size: 68, weight: .heavy),
            .foregroundColor: StoryCardDesign.textPrimary,
            .kern: -2.6,
        ]
        let tssSize = tssValue.size(withAttributes: tssAttrs)
        tssValue.draw(at: CGPoint(x: rightRect.minX + 24, y: rightRect.minY + 66), withAttributes: tssAttrs)
        "tss".draw(
            at: CGPoint(x: rightRect.minX + 24 + tssSize.width + 10, y: rightRect.minY + 109),
            withAttributes: [
                .font: StoryCardFontToken.ui(size: 26, weight: .medium),
                .foregroundColor: StoryCardDesign.textMuted,
            ]
        )

        let ftpPercent = ftpPercentValue(for: workout)
        let progressRect = CGRect(x: rightRect.minX + 24, y: rightRect.maxY - 52, width: rightRect.width - 48, height: 14)
        let track = UIBezierPath(roundedRect: progressRect, cornerRadius: 7)
        UIColor(AppColor.hair).setFill()
        track.fill()

        let fillWidth = progressRect.width * min(max(CGFloat(ftpPercent) / 100, 0), 1)
        let fillRect = CGRect(x: progressRect.minX, y: progressRect.minY, width: fillWidth, height: progressRect.height)
        let fillPath = UIBezierPath(roundedRect: fillRect, cornerRadius: 7)
        let gradientColors = [StoryCardDesign.accentYellow.cgColor, accent.cgColor] as CFArray
        cg.saveGState()
        cg.addPath(fillPath.cgPath)
        cg.clip()
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: gradientColors, locations: [0, 1]) {
            cg.drawLinearGradient(
                gradient,
                start: CGPoint(x: fillRect.minX, y: fillRect.midY),
                end: CGPoint(x: fillRect.maxX, y: fillRect.midY),
                options: []
            )
        }
        cg.restoreGState()

        "FTP%".draw(
            at: CGPoint(x: progressRect.minX, y: progressRect.maxY + 8),
            withAttributes: [
                .font: StoryCardFontToken.mono(size: 15, weight: .medium),
                .foregroundColor: StoryCardDesign.textQuiet,
                .kern: 1.1,
            ]
        )
        "\(ftpPercent)".draw(
            at: CGPoint(x: progressRect.maxX - 46, y: progressRect.maxY + 4),
            withAttributes: [
                .font: StoryCardFontToken.mono(size: 22, weight: .bold),
                .foregroundColor: StoryCardDesign.textSecondary,
            ]
        )
    }

    private static func drawPanel(in rect: CGRect, cornerRadius: CGFloat, cg: CGContext) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
        cg.saveGState()
        cg.setShadow(
            offset: CGSize(width: 0, height: 20),
            blur: 50,
            color: StoryCardDesign.panelShadow.cgColor
        )
        cg.addPath(path.cgPath)
        cg.setFillColor(StoryCardDesign.canvasBackground.withAlphaComponent(0.12).cgColor)
        cg.fillPath()
        cg.restoreGState()

        cg.saveGState()
        cg.addPath(path.cgPath)
        cg.clip()
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [StoryCardDesign.panelTop.cgColor, StoryCardDesign.panelBottom.cgColor] as CFArray,
            locations: [0, 1]
        ) {
            cg.drawLinearGradient(
                gradient,
                start: CGPoint(x: rect.midX, y: rect.minY),
                end: CGPoint(x: rect.midX, y: rect.maxY),
                options: []
            )
        }
        cg.restoreGState()

        StoryCardDesign.panelBorder.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private static func fillRadial(center: CGPoint, radius: CGFloat, color: UIColor, cg: CGContext) {
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

    private static func heroEyebrowText(
        routeName: String?,
        showRouteName: Bool,
        sessionKind: InstagramStoryCardSessionKind,
        dominantZone: PowerZone
    ) -> String {
        if showRouteName, let routeName, !routeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return routeName.uppercased()
        }
        switch sessionKind {
        case .outdoor: return "OUTDOOR CYCLING"
        case .indoorTrainer: return "INDOOR CYCLING"
        case .unknown: return dominantZone.name.uppercased()
        }
    }

    private static func resolvedHeroTitle(
        from aiTitle: String?,
        workout: Workout,
        routeName: String?,
        dominantZone: PowerZone,
        personalRecordNames: [String]
    ) -> String {
        let raw = aiTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let raw, !raw.isEmpty {
            return raw.replacingOccurrences(of: ".", with: "")
        }
        let fallback = StravaPostBuilder.buildTitle(
            workout: workout,
            routeName: routeName,
            dominantPowerZone: dominantZone,
            personalRecordNames: personalRecordNames
        )
        return fallback.replacingOccurrences(of: ".", with: "")
    }

    private static func titleLines(for title: String) -> [String] {
        let words = title.uppercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !words.isEmpty else { return ["CLIMB", "DAY."] }
        if words.count == 1 { return [words[0], ""] }
        if words.count == 2 { return [words[0], words[1] + "."] }

        let midpoint = Int(ceil(Double(words.count) / 2.0))
        let first = words.prefix(midpoint).joined(separator: " ")
        let second = words.suffix(words.count - midpoint).joined(separator: " ")
        return [first, second + "."]
    }

    private static func drawStudioTemplate(
        in cg: CGContext,
        size: CGSize,
        workout: Workout,
        dominantZone: PowerZone,
        routeName: String?,
        totalElevationGain: Double,
        personalRecordNames: [String],
        options: InstagramStoryCardOptions,
        sessionKind: InstagramStoryCardSessionKind,
        whoopStrain: Double?,
        whoopRecovery: Double?,
        aiTitle: String?
    ) {
        let accent = StoryCardDesign.accentColor(for: options.accent, dominantZone: dominantZone)
        let title = resolvedTemplateTitle(
            from: aiTitle,
            template: options.template,
            workout: workout,
            routeName: routeName,
            dominantZone: dominantZone,
            personalRecordNames: personalRecordNames
        )
        let eyebrow = heroEyebrowText(
            routeName: routeName,
            showRouteName: options.showRouteName && !options.privacyHideRoute,
            sessionKind: sessionKind,
            dominantZone: dominantZone
        )

        switch options.template {
        case .bigAchievement, .prFlex, .raceEffort:
            drawPosterTemplate(
                title: title,
                eyebrow: eyebrow,
                workout: workout,
                totalElevationGain: totalElevationGain,
                personalRecordNames: personalRecordNames,
                options: options,
                accent: accent,
                size: size,
                cg: cg
            )
        case .photoFirst, .routeDay, .recoveryRide, .minimalDark:
            drawEditorialTemplate(
                title: title,
                eyebrow: eyebrow,
                workout: workout,
                totalElevationGain: totalElevationGain,
                options: options,
                accent: accent,
                size: size,
                cg: cg
            )
        case .indoorPower:
            drawPowerTemplate(
                title: title,
                eyebrow: eyebrow,
                workout: workout,
                dominantZone: dominantZone,
                totalElevationGain: totalElevationGain,
                options: options,
                whoopStrain: whoopStrain,
                whoopRecovery: whoopRecovery,
                accent: accent,
                size: size,
                cg: cg
            )
        case .cleanStats:
            break
        }
    }

    private static func drawPosterTemplate(
        title: String,
        eyebrow: String,
        workout: Workout,
        totalElevationGain: Double,
        personalRecordNames: [String],
        options: InstagramStoryCardOptions,
        accent: UIColor,
        size: CGSize,
        cg: CGContext
    ) {
        drawStyleMotif(options.visualStyle, accent: accent, size: size, date: workout.startDate, cg: cg)
        if options.showHeader {
            drawHeader(
                brandTitle: options.showBrandBadge ? "MANGOX" : "RIDE SHARE",
                dateTitle: dateFormatter.string(from: workout.startDate).uppercased(),
                accent: accent,
                y: 100,
                width: size.width,
                cg: cg
            )
        }

        eyebrow.draw(at: CGPoint(x: sidePad, y: 260), withAttributes: templateEyebrowAttrs(accent: accent))
        drawWrappedTitle(title.uppercased(), in: CGRect(x: sidePad, y: 320, width: size.width - sidePad * 2, height: 440), fontSize: 118)

        let heroMetric = primaryTemplateMetric(workout: workout, template: options.template, personalRecordNames: personalRecordNames)
        drawHugeMetric(label: heroMetric.label, value: heroMetric.value, unit: heroMetric.unit, y: 820, accent: accent, width: size.width)

        if options.showBottomStrip {
            drawQuickStatsRow(workout: workout, totalElevationGain: totalElevationGain, options: options, y: 1220, width: size.width, cg: cg)
        }
        if options.showSummaryCards {
            drawBottomSummaryCards(workout: workout, accent: accent, options: options, y: 1410, width: size.width, cg: cg)
        }
    }

    private static func drawEditorialTemplate(
        title: String,
        eyebrow: String,
        workout: Workout,
        totalElevationGain: Double,
        options: InstagramStoryCardOptions,
        accent: UIColor,
        size: CGSize,
        cg: CGContext
    ) {
        drawStyleMotif(options.visualStyle, accent: accent, size: size, date: workout.startDate, cg: cg)
        let titleY: CGFloat = options.template == .photoFirst ? 1010 : 265
        let panelY: CGFloat = options.template == .photoFirst ? 1320 : 1110

        eyebrow.draw(at: CGPoint(x: sidePad, y: titleY - 66), withAttributes: templateEyebrowAttrs(accent: accent))
        drawWrappedTitle(
            title.uppercased(),
            in: CGRect(x: sidePad, y: titleY, width: size.width - sidePad * 2, height: 330),
            fontSize: options.template == .minimalDark ? 86 : 104
        )

        if options.showBottomStrip {
            drawQuickStatsRow(workout: workout, totalElevationGain: totalElevationGain, options: options, y: panelY, width: size.width, cg: cg)
        }
        if options.showSummaryCards {
            drawBottomSummaryCards(workout: workout, accent: accent, options: options, y: panelY + 170, width: size.width, cg: cg)
        }
    }

    private static func drawPowerTemplate(
        title: String,
        eyebrow: String,
        workout: Workout,
        dominantZone: PowerZone,
        totalElevationGain: Double,
        options: InstagramStoryCardOptions,
        whoopStrain: Double?,
        whoopRecovery: Double?,
        accent: UIColor,
        size: CGSize,
        cg: CGContext
    ) {
        drawStyleMotif(options.visualStyle, accent: accent, size: size, date: workout.startDate, cg: cg)
        eyebrow.draw(at: CGPoint(x: sidePad, y: 190), withAttributes: templateEyebrowAttrs(accent: accent))
        drawWrappedTitle(title.uppercased(), in: CGRect(x: sidePad, y: 250, width: size.width - sidePad * 2, height: 300), fontSize: 96)
        drawHugeMetric(
            label: options.privacyHidePower ? "MOVING TIME" : "NORMALIZED POWER",
            value: options.privacyHidePower ? AppFormat.duration(workout.duration) : metricText(Int(workout.normalizedPower.rounded()), fallback: "—"),
            unit: options.privacyHidePower ? "" : "w",
            y: 640,
            accent: accent,
            width: size.width
        )
        if options.showTrainingLoad {
            drawTrainingLoadCard(
                workout: workout,
                dominantZone: dominantZone,
                accent: accent,
                y: 965,
                width: size.width,
                height: trainingLoadCardHeight(options: options, whoopStrain: whoopStrain, whoopRecovery: whoopRecovery),
                options: options,
                whoopStrain: whoopStrain,
                whoopRecovery: whoopRecovery,
                cg: cg
            )
        }
        if options.showBottomStrip {
            drawQuickStatsRow(workout: workout, totalElevationGain: totalElevationGain, options: options, y: 1335, width: size.width, cg: cg)
        }
        if options.showSummaryCards {
            drawBottomSummaryCards(workout: workout, accent: accent, options: options, y: 1515, width: size.width, cg: cg)
        }
    }

    private static func drawStyleMotif(
        _ style: InstagramStoryCardOptions.VisualStyle,
        accent: UIColor,
        size: CGSize,
        date: Date,
        cg: CGContext
    ) {
        switch style {
        case .raceBib:
            let rect = CGRect(x: sidePad, y: 104, width: size.width - sidePad * 2, height: 126)
            drawPanel(in: rect, cornerRadius: 24, cg: cg)
            "RIDE / \(Calendar.current.component(.day, from: date))".draw(
                at: CGPoint(x: rect.minX + 28, y: rect.minY + 38),
                withAttributes: [
                    .font: StoryCardFontToken.mono(size: 42, weight: .bold),
                    .foregroundColor: StoryCardDesign.textPrimary,
                    .kern: 2.0,
                ]
            )
        case .proBroadcast:
            cg.setFillColor(accent.withAlphaComponent(0.18).cgColor)
            cg.fill(CGRect(x: 0, y: size.height - 360, width: size.width, height: 10))
            cg.fill(CGRect(x: 0, y: size.height - 324, width: size.width, height: 4))
        case .cafeRide:
            cg.setFillColor(UIColor(red: 0.98, green: 0.84, blue: 0.44, alpha: 0.08).cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
        case .neonNight:
            fillRadial(center: CGPoint(x: size.width * 0.5, y: size.height * 0.2), radius: 520, color: UIColor.systemPink.withAlphaComponent(0.18), cg: cg)
        case .topoMap:
            drawTopoLines(size: size, accent: accent, cg: cg)
        case .analyst:
            drawAnalysisGrid(size: size, cg: cg)
        case .mangoEditorial:
            break
        }
    }

    private static func drawTopoLines(size: CGSize, accent: UIColor, cg: CGContext) {
        cg.saveGState()
        cg.setStrokeColor(accent.withAlphaComponent(0.16).cgColor)
        cg.setLineWidth(2)
        for i in 0..<9 {
            let y = CGFloat(240 + i * 150)
            cg.move(to: CGPoint(x: -40, y: y))
            cg.addCurve(
                to: CGPoint(x: size.width + 40, y: y + CGFloat((i % 3) * 18)),
                control1: CGPoint(x: size.width * 0.28, y: y - 68),
                control2: CGPoint(x: size.width * 0.68, y: y + 82)
            )
            cg.strokePath()
        }
        cg.restoreGState()
    }

    private static func drawAnalysisGrid(size: CGSize, cg: CGContext) {
        cg.saveGState()
        cg.setStrokeColor(StoryCardDesign.divider.withAlphaComponent(0.22).cgColor)
        cg.setLineWidth(1)
        for x in stride(from: CGFloat(64), through: size.width - 64, by: 96) {
            cg.move(to: CGPoint(x: x, y: 120))
            cg.addLine(to: CGPoint(x: x, y: size.height - 120))
        }
        for y in stride(from: CGFloat(160), through: size.height - 160, by: 96) {
            cg.move(to: CGPoint(x: 64, y: y))
            cg.addLine(to: CGPoint(x: size.width - 64, y: y))
        }
        cg.strokePath()
        cg.restoreGState()
    }

    private static func drawWrappedTitle(_ title: String, in rect: CGRect, fontSize: CGFloat) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 0.86
        paragraph.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: StoryCardFontToken.ui(size: fontSize, weight: .heavy),
            .foregroundColor: StoryCardDesign.textPrimary,
            .paragraphStyle: paragraph,
        ]
        title.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
    }

    private static func drawHugeMetric(label: String, value: String, unit: String, y: CGFloat, accent: UIColor, width: CGFloat) {
        label.draw(at: CGPoint(x: sidePad, y: y), withAttributes: templateEyebrowAttrs(accent: accent))
        let maxValueWidth = width - sidePad * 2 - (unit.isEmpty ? 0 : 150)
        let fontSize = fittingFontSize(
            for: value,
            startingAt: 150,
            minimum: 88,
            maxWidth: maxValueWidth
        )
        let attrs: [NSAttributedString.Key: Any] = [
            .font: StoryCardFontToken.mono(size: fontSize, weight: .heavy),
            .foregroundColor: StoryCardDesign.textPrimary,
            .kern: -5.0,
        ]
        let valueSize = value.size(withAttributes: attrs)
        value.draw(at: CGPoint(x: sidePad, y: y + 48), withAttributes: attrs)
        if !unit.isEmpty {
            unit.draw(
                at: CGPoint(x: min(width - sidePad - 130, sidePad + valueSize.width + 16), y: y + 48 + fontSize * 0.62),
                withAttributes: [
                    .font: StoryCardFontToken.ui(size: 48, weight: .medium),
                    .foregroundColor: StoryCardDesign.textMuted,
                ]
            )
        }
    }

    private static func fittingFontSize(
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

    private static func templateEyebrowAttrs(accent: UIColor) -> [NSAttributedString.Key: Any] {
        [
            .font: StoryCardFontToken.mono(size: 24, weight: .medium),
            .foregroundColor: accent.withAlphaComponent(0.94),
            .kern: 2.0,
        ]
    }

    private static func resolvedTemplateTitle(
        from aiTitle: String?,
        template: InstagramStoryCardOptions.Template,
        workout: Workout,
        routeName: String?,
        dominantZone: PowerZone,
        personalRecordNames: [String]
    ) -> String {
        if template == .prFlex, let first = personalRecordNames.first {
            return "New \(first)"
        }
        if template == .recoveryRide {
            return "Easy work counts"
        }
        if template == .indoorPower {
            return "Power session"
        }
        return resolvedHeroTitle(from: aiTitle, workout: workout, routeName: routeName, dominantZone: dominantZone, personalRecordNames: personalRecordNames)
    }

    private static func primaryTemplateMetric(
        workout: Workout,
        template: InstagramStoryCardOptions.Template,
        personalRecordNames: [String]
    ) -> (label: String, value: String, unit: String) {
        if template == .prFlex, !personalRecordNames.isEmpty {
            return ("PERSONAL RECORDS", "\(personalRecordNames.count)", "PR")
        }
        if template == .raceEffort {
            return ("TRAINING STRESS", metricText(Int(workout.tss.rounded()), fallback: "—"), "tss")
        }
        return ("DISTANCE", String(format: "%.1f", workout.distance / 1000), "km")
    }

    private static func metricSlot(
        _ slot: InstagramStoryCardOptions.MetricSlot,
        workout: Workout,
        totalElevationGain: Double,
        options: InstagramStoryCardOptions
    ) -> (label: String, value: String)? {
        switch slot {
        case .distance: return ("KM", String(format: "%.1f", workout.distance / 1000))
        case .movingTime: return ("TIME", AppFormat.duration(workout.duration))
        case .avgPower:
            return options.privacyHidePower ? nil : ("AVG W", metricText(Int(workout.avgPower.rounded()), fallback: "—"))
        case .normalizedPower:
            return options.privacyHidePower ? nil : ("NP W", metricText(Int(workout.normalizedPower.rounded()), fallback: "—"))
        case .tss:
            return options.privacyHidePower ? nil : ("TSS", metricText(Int(workout.tss.rounded()), fallback: "—"))
        case .intensityFactor:
            return options.privacyHidePower ? nil : ("IF", String(format: "%.2f", max(0, workout.intensityFactor)))
        case .heartRate:
            return options.privacyHideHeartRate ? nil : ("HR AVG", metricText(averageHeartRate(from: workout), fallback: "—"))
        case .cadence: return ("RPM", metricText(Int(workout.avgCadence.rounded()), fallback: "—"))
        case .elevation:
            return ("ELEV M", metricText(Int(max(workout.elevationGain, totalElevationGain).rounded()), fallback: "—"))
        case .calories: return ("KCAL", "\(estimatedCalories(for: workout))")
        case .speed: return ("KM/H", String(format: "%.1f", max(0, workout.displayAverageSpeedKmh)))
        case .maxPower:
            return options.privacyHidePower ? nil : ("MAX W", metricText(workout.maxPower, fallback: "—"))
        }
    }

    private static func estimatedCalories(for workout: Workout) -> Int {
        WorkoutExportService.estimateCalories(avgPower: workout.avgPower, durationSeconds: workout.duration)
    }

    private static func secondaryAtmosphereColor(for style: InstagramStoryCardOptions.VisualStyle) -> UIColor {
        switch style {
        case .neonNight: return UIColor.systemPink
        case .cafeRide: return UIColor(red: 0.92, green: 0.68, blue: 0.30, alpha: 1)
        case .topoMap: return UIColor.systemGreen
        case .analyst: return UIColor.systemTeal
        case .raceBib: return UIColor.white
        case .proBroadcast: return StoryCardDesign.accentBlue
        case .mangoEditorial: return StoryCardDesign.accentBlue
        }
    }

    private static func metricText(_ value: Int, fallback: String) -> String {
        value > 0 ? "\(value)" : fallback
    }

    private static func averageHeartRate(from workout: Workout) -> Int {
        let samples = workout.samples
        if samples.isEmpty { return Int(workout.avgHR.rounded()) }
        if samples.count > 6_000, workout.avgHR > 0 {
            return Int(workout.avgHR.rounded())
        }
        var sum = 0.0
        var count = 0
        for s in samples where s.heartRate > 0 {
            sum += Double(s.heartRate)
            count += 1
        }
        if count > 0 { return Int((sum / Double(count)).rounded()) }
        return Int(workout.avgHR.rounded())
    }

    private static func ftpPercentValue(for workout: Workout) -> Int {
        if workout.intensityFactor > 0 {
            return Int((workout.intensityFactor * 100).rounded())
        }
        guard PowerZone.ftp > 0, workout.avgPower > 0 else { return 0 }
        return Int(((workout.avgPower / Double(PowerZone.ftp)) * 100).rounded())
    }

    private static func trainingLoadValue(for workout: Workout) -> Int {
        let tss = Int(workout.tss.rounded())
        if tss > 0 { return min(100, tss) }
        let ftp = ftpPercentValue(for: workout)
        return min(100, max(ftp, 0))
    }

    private static func trainingStatus(for workout: Workout) -> String {
        let value = trainingLoadValue(for: workout)
        switch value {
        case 85...: return "productive"
        case 65..<85: return "solid"
        case 40..<65: return "steady"
        case 1..<40: return "easy"
        default: return "ready"
        }
    }

    /// Cap how many power samples we classify so long rides stay fast (distribution converges with subsampling).
    private static let maxZoneDistributionSamples = 4_000

    private static func zoneDistribution(
        for workout: Workout,
        dominantZone: PowerZone
    ) -> [(zone: PowerZone, percentage: Double, color: UIColor)] {
        var counts: [Int: Int] = [:]
        let samples = workout.samples
        var totalWithPower = 0
        for s in samples where s.power > 0 {
            totalWithPower += 1
        }

        if totalWithPower == 0 {
            counts[dominantZone.id] = 1
        } else if totalWithPower <= maxZoneDistributionSamples {
            for s in samples where s.power > 0 {
                let zone = PowerZone.zone(for: s.power)
                counts[zone.id, default: 0] += 1
            }
        } else {
            let step = max(1, (totalWithPower + maxZoneDistributionSamples - 1) / maxZoneDistributionSamples)
            var streamIndex = 0
            for s in samples where s.power > 0 {
                if streamIndex % step == 0 {
                    let zone = PowerZone.zone(for: s.power)
                    counts[zone.id, default: 0] += 1
                }
                streamIndex += 1
            }
        }

        let total = max(1, counts.values.reduce(0, +))
        return PowerZone.zones.map { zone in
            let percentage = Double(counts[zone.id, default: 0]) / Double(total)
            return (zone, percentage, UIColor(zone.color))
        }
    }
}

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
            showRouteName: options.showRouteName,
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
            color: accent.withAlphaComponent(0.24),
            cg: cg
        )
        fillRadial(
            center: CGPoint(x: size.width * 0.20, y: size.height * 0.15),
            radius: 260,
            color: StoryCardDesign.accentBlue.withAlphaComponent(0.14),
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
        let elevDisplayM = max(workout.elevationGain, totalElevationGain)
        var slots: [(label: String, value: String)] = []
        if options.showQuickStatHeartRate {
            slots.append(("HR AVG", metricText(averageHeartRate(from: workout), fallback: "—")))
        }
        if options.showQuickStatCadence {
            slots.append(("RPM", metricText(Int(workout.avgCadence.rounded()), fallback: "—")))
        }
        if options.showQuickStatThird {
            if options.showElevation {
                slots.append(("ELEV M", metricText(Int(elevDisplayM.rounded()), fallback: "—")))
            } else {
                slots.append(("NP W", metricText(Int(workout.normalizedPower.rounded()), fallback: "—")))
            }
        }
        if options.showQuickStatSpeed {
            slots.append(("KM/H", String(format: "%.1f", max(0, workout.displayAverageSpeedKmh))))
        }
        if slots.isEmpty {
            slots = [
                ("HR AVG", metricText(averageHeartRate(from: workout), fallback: "—")),
                ("RPM", metricText(Int(workout.avgCadence.rounded()), fallback: "—")),
                (
                    options.showElevation ? "ELEV M" : "NP W",
                    options.showElevation
                        ? metricText(Int(elevDisplayM.rounded()), fallback: "—")
                        : metricText(Int(workout.normalizedPower.rounded()), fallback: "—")
                ),
                ("KM/H", String(format: "%.1f", max(0, workout.displayAverageSpeedKmh))),
            ]
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

        "AVG POWER".draw(
            at: CGPoint(x: leftRect.minX + 24, y: leftRect.minY + 22),
            withAttributes: [
                .font: StoryCardFontToken.mono(size: 18, weight: .medium),
                .foregroundColor: StoryCardDesign.textQuiet,
                .kern: 1.7,
            ]
        )

        let powerValue = metricText(Int(workout.avgPower.rounded()), fallback: "—")
        let powerAttrs: [NSAttributedString.Key: Any] = [
            .font: StoryCardFontToken.mono(size: 68, weight: .heavy),
            .foregroundColor: StoryCardDesign.textPrimary,
            .kern: -2.6,
        ]
        let powerSize = powerValue.size(withAttributes: powerAttrs)
        powerValue.draw(at: CGPoint(x: leftRect.minX + 24, y: leftRect.minY + 66), withAttributes: powerAttrs)
        "w".draw(
            at: CGPoint(x: leftRect.minX + 24 + powerSize.width + 10, y: leftRect.minY + 109),
            withAttributes: [
                .font: StoryCardFontToken.ui(size: 28, weight: .medium),
                .foregroundColor: StoryCardDesign.textMuted,
            ]
        )

        let npText = "NP \(metricText(Int(workout.normalizedPower.rounded()), fallback: "—"))w"
        let ifText = "IF \(String(format: "%.2f", max(0, workout.intensityFactor)))"
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

// Features/Social/Data/DataSources/InstagramStoryCardRenderer+Day.swift
import SwiftUI
import UIKit

// MARK: - Public Entry Point

extension InstagramStoryCardRenderer {
    @MainActor
    static func renderDaySummary(
        summary: DaySummary,
        options: DaySummaryCardOptions,
        backgroundImage: UIImage? = nil
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: cardSize, format: format)
        return renderer.image { ctx in
            DaySummaryCardDrawing.draw(
                in: ctx.cgContext,
                size: cardSize,
                summary: summary,
                options: options,
                backgroundImage: backgroundImage
            )
        }
    }
}

// MARK: - Drawing Engine

private enum DaySummaryCardDrawing {

    struct TileData {
        let symbol: String
        let accentColor: UIColor
        let typeLabel: String
        let ribbonLabel: String   // 3-char uppercase abbreviation for the timeline ribbon
        let durationText: String
        let metricText: String?
        let detailText: String?
        let mapPolyline: String?
        let hrZoneMillis: [Int]?
        let durationSeconds: Double  // used for sort order
        /// Sport-specific secondary stats in priority order. Adaptive renderers reveal more
        /// of these as the tile gets taller; the ones that don't fit are dropped.
        let secondaryStats: [(label: String, value: String)]
    }

    private static let sidePad: CGFloat = 64

    private static let headerDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        return f
    }()

    private static let dayNameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    private static let fullDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()

    private static let gradientAccents: [UIColor] = [
        UIColor(AppColor.mango),
        UIColor(AppColor.blue),
        UIColor(AppColor.success),
        UIColor(AppColor.form),
        UIColor(AppColor.whoop),
    ]

    static func draw(
        in cg: CGContext,
        size: CGSize,
        summary: DaySummary,
        options: DaySummaryCardOptions,
        backgroundImage: UIImage? = nil
    ) {
        UIGraphicsPushContext(cg)
        defer { UIGraphicsPopContext() }

        if options.backgroundSource == .photo, let backgroundImage {
            drawPhotoBackground(backgroundImage, size: size, cg: cg)
        } else {
            drawBackground(index: options.backgroundGradientIndex, size: size, cg: cg)
        }
        drawTemplateMotif(for: options.template, in: cg, size: size)

        switch options.template {
        case .dayBriefing:       drawBriefing(cg: cg, size: size, summary: summary, options: options)
        case .dayHeroStack:      drawHeroStack(cg: cg, size: size, summary: summary, options: options)
        case .dayMosaic:         drawMosaic(cg: cg, size: size, summary: summary, options: options)
        case .dayTimelineRibbon: drawTimelineRibbon(cg: cg, size: size, summary: summary, options: options)
        case .dayMinimalist:     drawMinimalist(cg: cg, size: size, summary: summary, options: options)
        case .dayPosterGrid:     drawPosterGrid(cg: cg, size: size, summary: summary, options: options)
        case .dayOrbit:          drawOrbit(cg: cg, size: size, summary: summary, options: options)
        case .dayScoreboard:     drawScoreboard(cg: cg, size: size, summary: summary, options: options)
        }
    }

    // MARK: - Background

    private static func drawPhotoBackground(_ image: UIImage, size: CGSize, cg: CGContext) {
        let prepared = ImageProcessing.prepareStoryBackground(from: image)
        prepared.draw(in: CGRect(origin: .zero, size: size))

        // Top fade (for header readability)
        let topColors = [
            UIColor.black.withAlphaComponent(0.62).cgColor,
            UIColor.black.withAlphaComponent(0.10).cgColor,
            UIColor.black.withAlphaComponent(0).cgColor,
        ] as CFArray
        if let topGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: topColors, locations: [0, 0.35, 1]) {
            cg.drawLinearGradient(
                topGradient,
                start: CGPoint(x: size.width / 2, y: 0),
                end: CGPoint(x: size.width / 2, y: size.height * 0.42),
                options: []
            )
        }

        // Bottom fade (for stat row readability)
        let bottomColors = [
            UIColor.black.withAlphaComponent(0).cgColor,
            UIColor.black.withAlphaComponent(0.30).cgColor,
            UIColor.black.withAlphaComponent(0.78).cgColor,
        ] as CFArray
        if let bottomGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bottomColors, locations: [0, 0.55, 1]) {
            cg.drawLinearGradient(
                bottomGradient,
                start: CGPoint(x: size.width / 2, y: size.height * 0.45),
                end: CGPoint(x: size.width / 2, y: size.height),
                options: []
            )
        }

        // Mango wash to maintain brand presence over photo
        cg.saveGState()
        cg.setBlendMode(.softLight)
        cg.setFillColor(UIColor(AppColor.mango).withAlphaComponent(0.08).cgColor)
        cg.fill(CGRect(origin: .zero, size: size))
        cg.restoreGState()
    }

    private static func drawBackground(index: Int, size: CGSize, cg: CGContext) {
        StoryCardDesign.canvasBackground.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))

        let accent    = gradientAccents[min(index, gradientAccents.count - 1)]
        let secondary = gradientAccents[(index + 2) % gradientAccents.count]

        fillRadial(center: CGPoint(x: size.width * 0.78, y: size.height * 0.84), radius: 380, color: accent.withAlphaComponent(0.26), cg: cg)
        fillRadial(center: CGPoint(x: size.width * 0.18, y: size.height * 0.12), radius: 300, color: secondary.withAlphaComponent(0.14), cg: cg)
        fillRadial(center: CGPoint(x: size.width * 0.50, y: size.height * 0.50), radius: 600, color: StoryCardDesign.canvasSecondary.withAlphaComponent(0.12), cg: cg)

        let colors = [
            StoryCardDesign.canvasBackground.withAlphaComponent(0.10).cgColor,
            StoryCardDesign.canvasBackground.withAlphaComponent(0.04).cgColor,
            StoryCardDesign.canvasBackground.withAlphaComponent(0.16).cgColor,
            StoryCardDesign.canvasBackground.withAlphaComponent(0.26).cgColor,
        ] as CFArray
        let locations: [CGFloat] = [0, 0.30, 0.68, 1]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) {
            cg.drawLinearGradient(
                gradient,
                start: CGPoint(x: size.width / 2, y: 0),
                end: CGPoint(x: size.width / 2, y: size.height),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
    }

    private static func fillRadial(center: CGPoint, radius: CGFloat, color: UIColor, cg: CGContext) {
        var r: CGFloat = 0; var g: CGFloat = 0; var b: CGFloat = 0; var a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let colors = [UIColor(red: r, green: g, blue: b, alpha: a).cgColor,
                      UIColor(red: r, green: g, blue: b, alpha: 0).cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
        cg.saveGState()
        cg.setBlendMode(.screen)
        cg.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [.drawsAfterEndLocation])
        cg.restoreGState()
    }

    // MARK: - Template Motifs

    private static func drawTemplateMotif(for template: DaySummaryCardOptions.Template, in cg: CGContext, size: CGSize) {
        switch template {
        case .dayScoreboard:
            cg.saveGState()
            cg.setFillColor(UIColor.white.withAlphaComponent(0.022).cgColor)
            var y: CGFloat = 0
            while y < size.height {
                cg.fill(CGRect(x: 0, y: y, width: size.width, height: 1))
                y += 4
            }
            cg.restoreGState()
        case .dayMosaic:
            cg.saveGState()
            UIColor.white.withAlphaComponent(0.04).setFill()
            let spacing: CGFloat = 48
            var dotY: CGFloat = spacing / 2
            while dotY < size.height {
                var dotX: CGFloat = spacing / 2
                while dotX < size.width {
                    UIBezierPath(ovalIn: CGRect(x: dotX - 1.5, y: dotY - 1.5, width: 3, height: 3)).fill()
                    dotX += spacing
                }
                dotY += spacing
            }
            cg.restoreGState()
        default:
            break
        }
    }

    // MARK: - Shared: Header

    private static func drawHeader(
        summary: DaySummary,
        options: DaySummaryCardOptions,
        accent: UIColor,
        y: CGFloat,
        size: CGSize,
        cg: CGContext
    ) {
        let dividerY = y + 10
        cg.setStrokeColor(StoryCardDesign.divider.cgColor)
        cg.setLineWidth(1)
        cg.move(to: CGPoint(x: sidePad, y: dividerY))
        cg.addLine(to: CGPoint(x: size.width - sidePad, y: dividerY))
        cg.strokePath()

        let dotRect = CGRect(x: sidePad + 2, y: dividerY + 22, width: 18, height: 18)
        accent.setFill()
        UIBezierPath(ovalIn: dotRect).fill()

        let brandText = options.showBrandBadge ? "MANGOX DAY" : "DAY SUMMARY"
        brandText.draw(
            at: CGPoint(x: sidePad + 34, y: dividerY + 14),
            withAttributes: [
                .font: StoryCardFontToken.ui(size: 32, weight: .medium),
                .foregroundColor: StoryCardDesign.textPrimary,
                .kern: 2.0,
            ]
        )

        let dateText = headerDateFormatter.string(from: summary.date).uppercased()
        let dateAttrs: [NSAttributedString.Key: Any] = [
            .font: StoryCardFontToken.mono(size: 26, weight: .medium),
            .foregroundColor: StoryCardDesign.textQuiet,
            .kern: 1.4,
        ]
        let dateSize = dateText.size(withAttributes: dateAttrs)
        dateText.draw(at: CGPoint(x: size.width - sidePad - dateSize.width, y: dividerY + 16), withAttributes: dateAttrs)
    }

    // MARK: - Shared: Stat Row

    private static func drawStatRow(
        summary: DaySummary,
        options: DaySummaryCardOptions,
        accent: UIColor,
        y: CGFloat,
        size: CGSize,
        cg: CGContext
    ) {
        var statData: [(label: String, value: String)] = []
        for slot in options.statSlots.prefix(4) {
            switch slot {
            case .totalTime:
                statData.append(("TIME", summary.totalDurationFormatted.uppercased()))
            case .totalDistance:
                guard summary.totalDistanceMeters > 0 else { continue }
                statData.append(("DISTANCE", summary.totalDistanceFormatted))
            case .totalElevation:
                guard summary.totalElevationGainMeters > 0 else { continue }
                statData.append(("ELEVATION", "\(Int(summary.totalElevationGainMeters.rounded()))m"))
            case .totalKJ:
                guard summary.totalKilojoules > 0, !options.privacyHidePower else { continue }
                statData.append(("ENERGY", "\(Int(summary.totalKilojoules.rounded()))kJ"))
            case .totalTSS:
                guard let tss = summary.totalTSS, tss > 0, !options.privacyHidePower else { continue }
                statData.append(("TSS", "\(Int(tss.rounded()))"))
            case .activityCount:
                statData.append(("ACTIVITIES", "\(summary.activityCount)"))
            }
        }
        guard !statData.isEmpty else { return }

        let count = CGFloat(statData.count)
        let gap: CGFloat = 16
        let tileW = (size.width - sidePad * 2 - gap * (count - 1)) / count
        let tileH: CGFloat = 130

        for (i, stat) in statData.enumerated() {
            let rect = CGRect(x: sidePad + CGFloat(i) * (tileW + gap), y: y, width: tileW, height: tileH)
            StoryCardDrawing.drawPanel(in: rect, cornerRadius: StoryCardDesign.panelRadius, cg: cg)

            let valAttrs: [NSAttributedString.Key: Any] = [
                .font: StoryCardFontToken.mono(size: 48, weight: .bold),
                .foregroundColor: StoryCardDesign.textPrimary,
                .kern: -1.6,
            ]
            let lblAttrs: [NSAttributedString.Key: Any] = [
                .font: StoryCardFontToken.mono(size: 14, weight: .medium),
                .foregroundColor: StoryCardDesign.textQuiet,
                .kern: 1.2,
            ]
            let valSize = stat.value.size(withAttributes: valAttrs)
            stat.value.draw(at: CGPoint(x: rect.midX - valSize.width / 2, y: rect.minY + 22), withAttributes: valAttrs)
            let lblSize = stat.label.size(withAttributes: lblAttrs)
            stat.label.draw(at: CGPoint(x: rect.midX - lblSize.width / 2, y: rect.minY + 84), withAttributes: lblAttrs)
        }
    }

    // MARK: - Shared: Brand Footer

    private static func drawBrandBadge(y: CGFloat, size: CGSize) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: StoryCardFontToken.mono(size: 20, weight: .medium),
            .foregroundColor: StoryCardDesign.textQuiet,
            .kern: 2.4,
        ]
        let text = "MANGOX"
        let sz = text.size(withAttributes: attrs)
        text.draw(at: CGPoint(x: (size.width - sz.width) / 2, y: y), withAttributes: attrs)
    }

    // MARK: - Shared: Icon Circle + SF Symbol

    private static func drawIconCircleAndSymbol(
        symbol: String,
        color: UIColor,
        center: CGPoint,
        radius: CGFloat,
        cg: CGContext
    ) {
        let circleRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        color.withAlphaComponent(0.18).setFill()
        UIBezierPath(ovalIn: circleRect).fill()

        color.withAlphaComponent(0.32).setStroke()
        let borderPath = UIBezierPath(ovalIn: circleRect.insetBy(dx: 0.5, dy: 0.5))
        borderPath.lineWidth = 1.5
        borderPath.stroke()

        let iconPt = radius * 1.1
        let config = UIImage.SymbolConfiguration(pointSize: iconPt, weight: .medium)
        if let img = UIImage(systemName: symbol, withConfiguration: config)?
            .withTintColor(color.withAlphaComponent(0.92), renderingMode: .alwaysOriginal) {
            img.draw(at: CGPoint(x: center.x - img.size.width / 2, y: center.y - img.size.height / 2))
        }
    }

    private static func drawBackdropWord(_ text: String, at point: CGPoint, size: CGFloat, alpha: CGFloat) {
        text.draw(
            at: point,
            withAttributes: [
                .font: StoryCardFontToken.mono(size: size, weight: .heavy),
                .foregroundColor: UIColor.white.withAlphaComponent(alpha),
                .kern: -8.0,
            ]
        )
    }

    private static func drawCapsuleText(
        _ text: String,
        at point: CGPoint,
        color: UIColor,
        fontSize: CGFloat = 22,
        horizontalPadding: CGFloat = 18
    ) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: StoryCardFontToken.mono(size: fontSize, weight: .medium),
            .foregroundColor: color.withAlphaComponent(0.94),
            .kern: 1.2,
        ]
        let textSize = text.size(withAttributes: attrs)
        let rect = CGRect(
            x: point.x,
            y: point.y,
            width: textSize.width + horizontalPadding * 2,
            height: textSize.height + 16
        )
        color.withAlphaComponent(0.14).setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2).fill()
        color.withAlphaComponent(0.28).setStroke()
        UIBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: rect.height / 2).stroke()
        text.draw(at: CGPoint(x: rect.minX + horizontalPadding, y: rect.minY + 8), withAttributes: attrs)
    }

    private static func drawOneLine(
        _ text: String,
        in rect: CGRect,
        fontSize: CGFloat,
        minSize: CGFloat,
        color: UIColor,
        weight: UIFont.Weight = .medium,
        kern: CGFloat = 0
    ) {
        var size = fontSize
        while size > minSize {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: StoryCardFontToken.ui(size: size, weight: weight),
                .foregroundColor: color,
                .kern: kern,
            ]
            if text.size(withAttributes: attrs).width <= rect.width {
                text.draw(at: rect.origin, withAttributes: attrs)
                return
            }
            size -= 2
        }
        text.draw(
            at: rect.origin,
            withAttributes: [
                .font: StoryCardFontToken.ui(size: minSize, weight: weight),
                .foregroundColor: color,
                .kern: kern,
            ]
        )
    }

    private static func drawAngledBand(rect: CGRect, color: UIColor, cg: CGContext) {
        cg.saveGState()
        cg.translateBy(x: rect.midX, y: rect.midY)
        cg.rotate(by: -0.10)
        color.setFill()
        UIBezierPath(roundedRect: CGRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height), cornerRadius: 34).fill()
        cg.restoreGState()
    }

    private static func drawHRZoneStrip(zones: [Int], rect: CGRect, cg: CGContext) {
        let total = zones.reduce(0, +)
        guard total > 0 else { return }
        let colors = [
            UIColor.white.withAlphaComponent(0.22),
            UIColor(AppColor.blue),
            UIColor.systemGreen,
            UIColor(AppColor.yellow),
            UIColor(AppColor.orange),
            UIColor(AppColor.red),
        ]
        let path = UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2)
        StoryCardDesign.panelBorder.withAlphaComponent(0.5).setFill()
        path.fill()

        cg.saveGState()
        cg.addPath(path.cgPath)
        cg.clip()
        var x = rect.minX
        for (index, zone) in zones.enumerated() where zone > 0 {
            let width = max(3, rect.width * CGFloat(zone) / CGFloat(total))
            colors[min(index, colors.count - 1)].withAlphaComponent(0.86).setFill()
            UIRectFill(CGRect(x: x, y: rect.minY, width: width, height: rect.height))
            x += width
        }
        cg.restoreGState()
    }

    private static func drawMiniRoute(polyline: String, in rect: CGRect, color: UIColor, cg: CGContext) {
        let points = decodePolyline(polyline)
        guard points.count > 1 else { return }
        let lats = points.map(\.latitude)
        let lons = points.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(), let minLon = lons.min(), let maxLon = lons.max() else { return }
        let latSpan = max(0.000001, maxLat - minLat)
        let lonSpan = max(0.000001, maxLon - minLon)

        let path = UIBezierPath()
        for (index, point) in points.enumerated() {
            let x = rect.minX + CGFloat((point.longitude - minLon) / lonSpan) * rect.width
            let y = rect.maxY - CGFloat((point.latitude - minLat) / latSpan) * rect.height
            if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }

        cg.saveGState()
        color.withAlphaComponent(0.16).setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 18).fill()
        color.withAlphaComponent(0.78).setStroke()
        path.lineWidth = 4
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
        cg.restoreGState()
    }

    private static func decodePolyline(_ encoded: String) -> [(latitude: Double, longitude: Double)] {
        let scalars = Array(encoded.unicodeScalars).map { Int($0.value) }
        var index = 0
        var latitude = 0
        var longitude = 0
        var points: [(Double, Double)] = []

        while index < scalars.count {
            guard let deltaLat = decodePolylineValue(scalars: scalars, index: &index),
                  let deltaLon = decodePolylineValue(scalars: scalars, index: &index) else {
                break
            }
            latitude += deltaLat
            longitude += deltaLon
            points.append((Double(latitude) / 1e5, Double(longitude) / 1e5))
        }
        return points
    }

    private static func decodePolylineValue(scalars: [Int], index: inout Int) -> Int? {
        var result = 0
        var shift = 0
        var byte = 0
        repeat {
            guard index < scalars.count else { return nil }
            byte = scalars[index] - 63
            index += 1
            result |= (byte & 0x1f) << shift
            shift += 5
        } while byte >= 0x20
        return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
    }

    // MARK: - Shared: Tile Data

    private static func tileData(for summary: DaySummary, options: DaySummaryCardOptions) -> [TileData] {
        var tiles: [TileData] = []

        for w in summary.cyclingWorkouts {
            let dur = w.duration
            let h = Int(dur) / 3600
            let m = (Int(dur) % 3600) / 60
            let durText = h > 0 ? "\(h)h \(m)m" : "\(m)m"
            let dist = w.distance > 0 ? String(format: "%.1f km", w.distance / 1000) : nil
            let hour = Calendar.current.component(.hour, from: w.startDate)
            let timeLabel: String
            switch hour {
            case 5..<12:  timeLabel = "Morning Ride"
            case 12..<17: timeLabel = "Afternoon Ride"
            case 17..<21: timeLabel = "Evening Ride"
            default:      timeLabel = "Night Ride"
            }
            tiles.append(TileData(
                symbol: "bicycle",
                accentColor: StoryCardDesign.accentMango,
                typeLabel: timeLabel,
                ribbonLabel: "CYC",
                durationText: durText,
                metricText: dist,
                detailText: w.tss > 0 && !options.privacyHidePower ? "\(Int(w.tss.rounded())) TSS" : nil,
                mapPolyline: nil,
                hrZoneMillis: nil,
                durationSeconds: dur,
                secondaryStats: cyclingSecondaryStats(workout: w, options: options)
            ))
        }

        for a in summary.loggedActivities {
            let metric = primaryMetric(for: a, options: options)
            let detail = detailMetric(for: a, options: options)
            tiles.append(TileData(
                symbol: a.type.sfSymbol,
                accentColor: accentColor(for: a.type),
                typeLabel: a.displayName,
                ribbonLabel: ribbonAbbreviation(for: a.type),
                durationText: a.durationFormatted,
                metricText: metric,
                detailText: detail,
                mapPolyline: a.metrics.mapSummaryPolyline,
                hrZoneMillis: a.metrics.heartRateZoneMillis,
                durationSeconds: Double(a.durationSeconds),
                secondaryStats: loggedActivitySecondaryStats(activity: a, options: options)
            ))
        }
        return tiles.sorted { $0.durationSeconds > $1.durationSeconds }
    }

    private static func cyclingSecondaryStats(
        workout: Workout,
        options: DaySummaryCardOptions
    ) -> [(label: String, value: String)] {
        var stats: [(String, String)] = []
        if !options.privacyHidePower {
            if workout.avgPower > 0 { stats.append(("AVG W", "\(Int(workout.avgPower.rounded()))")) }
            if workout.normalizedPower > 0 { stats.append(("NP", "\(Int(workout.normalizedPower.rounded()))")) }
            if workout.intensityFactor > 0 {
                stats.append(("IF", String(format: "%.2f", workout.intensityFactor)))
            }
        }
        if !options.privacyHideHeartRate, workout.avgHR > 0 {
            stats.append(("AVG HR", "\(Int(workout.avgHR.rounded())) bpm"))
        }
        if workout.elevationGain > 0 {
            stats.append(("ELEV", "\(Int(workout.elevationGain.rounded())) m"))
        }
        if workout.avgCadence > 0 {
            stats.append(("CAD", "\(Int(workout.avgCadence.rounded())) rpm"))
        }
        if workout.maxPower > 0, !options.privacyHidePower {
            stats.append(("MAX W", "\(workout.maxPower)"))
        }
        return stats
    }

    private static func loggedActivitySecondaryStats(
        activity: LoggedActivity,
        options: DaySummaryCardOptions
    ) -> [(label: String, value: String)] {
        let m = activity.metrics
        var stats: [(String, String)] = []

        if activity.type.isCardioDistance, let bestKm = m.bestKmSplitSeconds, bestKm > 0 {
            stats.append(("BEST KM", "\(bestKm / 60):\(String(format: "%02d", bestKm % 60))"))
        }
        if let speed = m.avgSpeedMetersPerSecond, speed > 0, activity.type.isCardioDistance {
            let pace = Int((1000 / speed).rounded())
            stats.append(("PACE", "\(pace / 60):\(String(format: "%02d", pace % 60))/km"))
        }
        if let watts = m.avgPowerWatts, watts > 0, !options.privacyHidePower {
            stats.append(("AVG W", "\(Int(watts.rounded()))"))
        }
        if let avgHR = m.avgHeartRate, avgHR > 0, !options.privacyHideHeartRate {
            stats.append(("AVG HR", "\(avgHR) bpm"))
        }
        if let maxHR = m.maxHeartRate, maxHR > 0, !options.privacyHideHeartRate {
            stats.append(("MAX HR", "\(maxHR) bpm"))
        }
        if let cad = m.avgCadence, cad > 0 {
            stats.append(("CAD", "\(Int(cad.rounded())) \(cadenceUnit(for: activity.type))"))
        }
        if let elev = m.elevationGainMeters, elev > 0 {
            stats.append(("ELEV", "\(Int(elev.rounded())) m"))
        }
        if activity.type.isStrength, let sets = m.sets, sets > 0, !options.privacyHideStrengthLoad {
            if let reps = m.reps, reps > 0 {
                stats.append(("VOLUME", "\(sets)x\(reps)"))
            } else {
                stats.append(("SETS", "\(sets)"))
            }
        }
        if let kj = m.kilojoules, kj > 0, !options.privacyHidePower {
            stats.append(("ENERGY", "\(Int(kj.rounded())) kJ"))
        }
        if let cal = m.calories, cal > 0 {
            stats.append(("CAL", "\(cal)"))
        }
        if let temp = m.avgTempCelsius, abs(temp) > 0 {
            stats.append(("TEMP", "\(Int(temp.rounded()))°C"))
        }
        if let effort = m.relativeEffort, effort > 0 {
            stats.append(("EFFORT", "\(effort)"))
        }
        return stats
    }

    private static func primaryMetric(for activity: LoggedActivity, options: DaySummaryCardOptions) -> String? {
        let metrics = activity.metrics
        if let strain = metrics.strain, strain > 0 {
            return String(format: "%.1f strain", strain)
        }
        if let distance = metrics.distanceMeters, distance > 0 {
            return distance >= 1000 ? String(format: "%.1f km", distance / 1000) : "\(Int(distance.rounded())) m"
        }
        if let sets = metrics.sets, !options.privacyHideStrengthLoad {
            if let reps = metrics.reps, reps > 0 { return "\(sets)x\(reps)" }
            return "\(sets) sets"
        }
        if let calories = metrics.calories, calories > 0 {
            return "\(calories) cal"
        }
        return nil
    }

    private static func detailMetric(for activity: LoggedActivity, options: DaySummaryCardOptions) -> String? {
        let metrics = activity.metrics
        // Best 1km split (running/walking/hiking) — most impressive when present.
        if activity.type.isCardioDistance, let bestKm = metrics.bestKmSplitSeconds, bestKm > 0 {
            return "Best km \(bestKm / 60):\(String(format: "%02d", bestKm % 60))"
        }
        if let speed = metrics.avgSpeedMetersPerSecond, speed > 0, activity.type == .run {
            let paceSeconds = Int((1000 / speed).rounded())
            return "\(paceSeconds / 60):\(String(format: "%02d", paceSeconds % 60))/km"
        }
        if let elevation = metrics.elevationGainMeters, elevation > 0 {
            return "\(Int(elevation.rounded())) m up"
        }
        if let watts = metrics.avgPowerWatts, watts > 0, !options.privacyHidePower {
            return "\(Int(watts.rounded())) W avg"
        }
        if let cadence = metrics.avgCadence, cadence > 0 {
            // Strava reports cycling cadence in rpm and runs in spm (per-foot, halved). Both already in source units.
            return "\(Int(cadence.rounded())) \(cadenceUnit(for: activity.type))"
        }
        if let effort = metrics.relativeEffort, effort > 0 {
            return "\(effort) effort"
        }
        if let avgHR = metrics.avgHeartRate, avgHR > 0, !options.privacyHideHeartRate {
            return "\(avgHR) bpm avg"
        }
        if let temp = metrics.avgTempCelsius, abs(temp) > 0 {
            return "\(Int(temp.rounded()))°C"
        }
        if let recorded = metrics.percentRecorded, recorded > 0 {
            return "\(Int(recorded.rounded()))% recorded"
        }
        if let prs = metrics.prCount, prs > 0 {
            return "\(prs) PR"
        }
        if let achievements = metrics.achievementCount, achievements > 0 {
            return "\(achievements) achievements"
        }
        return nil
    }

    private static func cadenceUnit(for type: LoggedActivityType) -> String {
        switch type {
        case .run, .walk, .hike: "spm"
        case .swim: "spm"
        case .rowing: "spm"
        default: "rpm"
        }
    }

    private static func ribbonAbbreviation(for type: LoggedActivityType) -> String {
        if type.isStrength { return "GYM" }
        return String(type.rawValue.prefix(3)).uppercased()
    }

    private static func accentColor(for type: LoggedActivityType) -> UIColor {
        if type.isStrength { return UIColor(AppColor.blue) }
        switch type {
        case .swim: return UIColor(AppColor.cadence)
        case .yoga, .pilates, .mobility: return UIColor(AppColor.whoop)
        default: break
        }
        if type.isCardioDistance { return UIColor(AppColor.success) }
        return UIColor(AppColor.mango)
    }

    // MARK: - Shared: Font Size Fitting

    private static func fittingFontSize(for text: String, startingAt start: CGFloat, minimum: CGFloat, maxWidth: CGFloat) -> CGFloat {
        var sz = start
        while sz > minimum {
            let w = text.size(withAttributes: [
                .font: StoryCardFontToken.mono(size: sz, weight: .heavy),
                .kern: -5.0,
            ]).width
            if w <= maxWidth { return sz }
            sz -= 4
        }
        return minimum
    }

    // MARK: - Template: Briefing (Mangox-forward, sport-aware, adaptive)

    private static func drawBriefing(
        cg: CGContext,
        size: CGSize,
        summary: DaySummary,
        options: DaySummaryCardOptions
    ) {
        let mango = UIColor(AppColor.mango)
        let tiles = tileData(for: summary, options: options)

        // Top mango trim (full width thin bar)
        mango.withAlphaComponent(0.92).setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: size.width, height: 6))

        // Header chip
        let chipText: String = {
            let date = headerDateFormatter.string(from: summary.date).uppercased()
            return options.showBrandBadge ? "MANGOX BRIEFING  •  \(date)" : "DAY BRIEFING  •  \(date)"
        }()
        drawCapsuleText(chipText, at: CGPoint(x: sidePad, y: 78), color: mango, fontSize: 20, horizontalPadding: 18)

        // Big day name
        let dayFull = fullDayFormatter.string(from: summary.date).uppercased()
        dayFull.draw(at: CGPoint(x: sidePad, y: 168), withAttributes: [
            .font: StoryCardFontToken.ui(size: 64, weight: .medium),
            .foregroundColor: StoryCardDesign.textPrimary,
            .kern: 1.2,
        ])

        // Hero total time
        let totalTime = summary.totalDurationFormatted.uppercased()
        let timeFontSize = fittingFontSize(for: totalTime, startingAt: 168, minimum: 96, maxWidth: size.width - sidePad * 2 - 80)
        totalTime.draw(at: CGPoint(x: sidePad, y: 252), withAttributes: [
            .font: StoryCardFontToken.mono(size: timeFontSize, weight: .heavy),
            .foregroundColor: StoryCardDesign.textPrimary,
            .kern: -5.5,
        ])

        // Subline
        let countLabel = summary.activityCount == 1 ? "1 activity" : "\(summary.activityCount) activities"
        var subParts: [String] = [countLabel.uppercased()]
        if summary.totalDistanceMeters > 0 { subParts.append(summary.totalDistanceFormatted) }
        if summary.totalElevationGainMeters > 0 { subParts.append("\(Int(summary.totalElevationGainMeters.rounded()))m up") }
        let sub = subParts.joined(separator: "  ·  ")
        sub.draw(at: CGPoint(x: sidePad, y: 252 + timeFontSize + 6), withAttributes: [
            .font: StoryCardFontToken.mono(size: 22, weight: .medium),
            .foregroundColor: mango.withAlphaComponent(0.92),
            .kern: 1.6,
        ])

        // ------ Adaptive activity tiles ------
        // Goal: when there are few activities (1–3), each tile expands to use the available
        // vertical space and shows sport-specific richness (HR zones, secondary stats, polylines).
        // When there are many (4+), tiles compress to compact rows.
        let ribbonStartY: CGFloat = 252 + timeFontSize + 70
        let statsAreaHeight: CGFloat = options.showBrandBadge ? 250 : 190
        let availableH = size.height - ribbonStartY - statsAreaHeight - 24

        let visibleCount = min(tiles.count, 4)
        let extraTilesCount = tiles.count - visibleCount
        let cardGap: CGFloat = 14
        let totalGap = cardGap * CGFloat(max(0, visibleCount - 1))
        let perCardMax: CGFloat = visibleCount == 1 ? 600 : 480
        let perCardMin: CGFloat = 120
        let perCard = max(perCardMin, min(perCardMax, (availableH - totalGap - (extraTilesCount > 0 ? 36 : 0)) / CGFloat(max(visibleCount, 1))))
        let totalUsed = perCard * CGFloat(visibleCount) + totalGap + (extraTilesCount > 0 ? 36 : 0)
        let topOffset = max(0, (availableH - totalUsed) / 2)

        for i in 0..<visibleCount {
            let y = ribbonStartY + topOffset + CGFloat(i) * (perCard + cardGap)
            let rect = CGRect(x: sidePad, y: y, width: size.width - sidePad * 2, height: perCard)
            drawBriefingTile(tile: tiles[i], rect: rect, cg: cg)
        }
        // "+ N more" indicator if we couldn't fit them all
        if extraTilesCount > 0 {
            let pillY = ribbonStartY + topOffset + CGFloat(visibleCount) * (perCard + cardGap) - cardGap + 14
            let pillText = "+ \(extraTilesCount) more"
            drawCapsuleText(pillText.uppercased(), at: CGPoint(x: sidePad, y: pillY), color: mango.withAlphaComponent(0.7), fontSize: 16, horizontalPadding: 14)
        }

        // Stat row + footer
        drawStatRow(summary: summary, options: options, accent: mango, y: size.height - statsAreaHeight, size: size, cg: cg)
        if options.showBrandBadge {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: StoryCardFontToken.mono(size: 20, weight: .medium),
                .foregroundColor: StoryCardDesign.textQuiet,
                .kern: 2.4,
            ]
            let text = "MANGOX"
            let sz = text.size(withAttributes: attrs)
            let footY = size.height - 86
            text.draw(at: CGPoint(x: (size.width - sz.width) / 2, y: footY), withAttributes: attrs)
            mango.withAlphaComponent(0.85).setFill()
            UIRectFill(CGRect(x: (size.width - sz.width) / 2, y: footY + sz.height + 6, width: sz.width, height: 2))
        }
    }

    /// Adaptive tile draw — content tier scales with rect height.
    /// - Compact (h < 180): single-row icon + name + duration + primary metric.
    /// - Medium (h ≥ 180): adds a secondary stats strip at the bottom.
    /// - Large  (h ≥ 280): adds an HR zone strip when available + more secondary stats.
    /// - Hero   (h ≥ 380): adds a sport-specific accent banner; oversized primary metric.
    private static func drawBriefingTile(tile: TileData, rect: CGRect, cg: CGContext) {
        StoryCardDrawing.drawPanel(in: rect, cornerRadius: StoryCardDesign.panelRadius, cg: cg)

        let isMedium = rect.height >= 180
        let isLarge = rect.height >= 280
        let isHero = rect.height >= 380

        // Left vertical sport-color trim
        let trimInsetTop: CGFloat = isHero ? 28 : 18
        tile.accentColor.withAlphaComponent(0.92).setFill()
        UIBezierPath(
            roundedRect: CGRect(
                x: rect.minX + 16,
                y: rect.minY + trimInsetTop,
                width: 6,
                height: rect.height - trimInsetTop * 2
            ),
            cornerRadius: 3
        ).fill()

        // Hero accent banner: subtle wash behind the icon for hero tiles
        if isHero {
            let banner = CGRect(x: rect.minX + 32, y: rect.minY + 28, width: rect.width - 64, height: 72)
            tile.accentColor.withAlphaComponent(0.10).setFill()
            UIBezierPath(roundedRect: banner, cornerRadius: 24).fill()
        }

        // Icon
        let iconRadius: CGFloat = isHero ? 44 : (isLarge ? 38 : 32)
        let iconCenterY: CGFloat = isHero ? rect.minY + 64 : rect.midY - (isMedium ? 22 : 0)
        let iconCenterX: CGFloat = rect.minX + (isHero ? 70 : 56) + iconRadius
        drawIconCircleAndSymbol(
            symbol: tile.symbol,
            color: tile.accentColor,
            center: CGPoint(x: iconCenterX, y: iconCenterY),
            radius: iconRadius,
            cg: cg
        )

        // Type label + duration (header text block)
        let textX = iconCenterX + iconRadius + 20
        let titleSize: CGFloat = isHero ? 36 : (isLarge ? 32 : 30)
        tile.typeLabel.draw(
            at: CGPoint(x: textX, y: iconCenterY - titleSize - 2),
            withAttributes: [
                .font: StoryCardFontToken.ui(size: titleSize, weight: .medium),
                .foregroundColor: StoryCardDesign.textPrimary,
            ]
        )
        tile.durationText.draw(
            at: CGPoint(x: textX, y: iconCenterY + 6),
            withAttributes: [
                .font: StoryCardFontToken.mono(size: isHero ? 28 : 24, weight: .medium),
                .foregroundColor: StoryCardDesign.textMuted,
                .kern: -0.4,
            ]
        )

        // Primary metric (right-aligned)
        let primaryY = iconCenterY - (isHero ? 28 : 24)
        if let metric = tile.metricText {
            let metricSize: CGFloat = isHero ? 44 : 32
            let mAttrs: [NSAttributedString.Key: Any] = [
                .font: StoryCardFontToken.mono(size: metricSize, weight: .bold),
                .foregroundColor: tile.accentColor.withAlphaComponent(0.94),
                .kern: -1.0,
            ]
            let mSz = metric.size(withAttributes: mAttrs)
            metric.draw(
                at: CGPoint(x: rect.maxX - 28 - mSz.width, y: primaryY),
                withAttributes: mAttrs
            )
        }
        if let detail = tile.detailText {
            let dAttrs: [NSAttributedString.Key: Any] = [
                .font: StoryCardFontToken.mono(size: isHero ? 22 : 18, weight: .medium),
                .foregroundColor: StoryCardDesign.textQuiet,
                .kern: 0.4,
            ]
            let dSz = detail.size(withAttributes: dAttrs)
            detail.draw(
                at: CGPoint(x: rect.maxX - 28 - dSz.width, y: primaryY + (isHero ? 56 : 38)),
                withAttributes: dAttrs
            )
        }

        // Bottom region: secondary stats + HR zones + polyline
        guard isMedium else { return }

        let bottomZoneTop = rect.minY + (isHero ? 130 : 92)
        let bottomZone = CGRect(
            x: rect.minX + 32,
            y: bottomZoneTop,
            width: rect.width - 64,
            height: rect.maxY - bottomZoneTop - 24
        )

        // HR zones strip (when available + at least Large)
        let contentTop = bottomZone.minY
        if isLarge, let zones = tile.hrZoneMillis, zones.reduce(0, +) > 0 {
            let stripRect = CGRect(x: bottomZone.minX, y: bottomZone.maxY - 14, width: bottomZone.width, height: 10)
            drawHRZoneStrip(zones: zones, rect: stripRect, cg: cg)
            // Reserve space above the strip
        }

        // Polyline (when available + at least Large)
        if isLarge, let polyline = tile.mapPolyline, !polyline.isEmpty {
            let routeW: CGFloat = isHero ? 200 : 150
            let routeH: CGFloat = isHero ? 130 : 92
            drawMiniRoute(
                polyline: polyline,
                in: CGRect(x: bottomZone.maxX - routeW, y: contentTop, width: routeW, height: routeH),
                color: tile.accentColor,
                cg: cg
            )
        }

        // Secondary stats — pick as many as fit
        let secondaries = tile.secondaryStats
        let maxStats = isHero ? 6 : (isLarge ? 4 : 3)
        let visibleStats = Array(secondaries.prefix(maxStats))
        guard !visibleStats.isEmpty else { return }

        // Lay them out as a wrap: 3 columns top row, 3 columns bottom (hero) / single row otherwise
        let cols = visibleStats.count >= 4 ? 3 : visibleStats.count
        let rows = Int(ceil(Double(visibleStats.count) / Double(cols)))
        let routeReserveW: CGFloat = (isLarge && tile.mapPolyline != nil) ? (isHero ? 220 : 170) : 0
        let statsAreaW = bottomZone.width - routeReserveW
        let statRowH: CGFloat = isHero ? 50 : 44
        let totalStatsH = CGFloat(rows) * statRowH

        // anchor stats grid to top of bottomZone (just below the divider area)
        let statsTop: CGFloat = contentTop
        for (idx, stat) in visibleStats.enumerated() {
            let col = idx % cols
            let row = idx / cols
            let cellW = statsAreaW / CGFloat(cols)
            let x = bottomZone.minX + CGFloat(col) * cellW
            let y = statsTop + CGFloat(row) * statRowH
            stat.label.draw(
                at: CGPoint(x: x, y: y),
                withAttributes: [
                    .font: StoryCardFontToken.mono(size: isHero ? 12 : 11, weight: .semibold),
                    .foregroundColor: tile.accentColor.withAlphaComponent(0.78),
                    .kern: 1.2,
                ]
            )
            stat.value.draw(
                at: CGPoint(x: x, y: y + (isHero ? 16 : 14)),
                withAttributes: [
                    .font: StoryCardFontToken.mono(size: isHero ? 22 : 19, weight: .bold),
                    .foregroundColor: StoryCardDesign.textPrimary,
                    .kern: -0.4,
                ]
            )
        }
        _ = totalStatsH // silence unused if we extend layout later
    }

    // MARK: - Template: Hero Stack

    private static func drawHeroStack(
        cg: CGContext,
        size: CGSize,
        summary: DaySummary,
        options: DaySummaryCardOptions
    ) {
        let accent = gradientAccents[min(options.backgroundGradientIndex, gradientAccents.count - 1)]
        let tiles = tileData(for: summary, options: options)

        drawHeader(summary: summary, options: options, accent: accent, y: 80, size: size, cg: cg)

        // Hero: day number + name
        let dayNum = "\(Calendar.current.component(.day, from: summary.date))"
        let dayName = dayNameFormatter.string(from: summary.date).uppercased()

        let heroNumAttrs: [NSAttributedString.Key: Any] = [
            .font: StoryCardFontToken.mono(size: 116, weight: .heavy),
            .foregroundColor: StoryCardDesign.textPrimary,
            .kern: -4.0,
        ]
        let heroNameAttrs: [NSAttributedString.Key: Any] = [
            .font: StoryCardFontToken.ui(size: 50, weight: .medium),
            .foregroundColor: StoryCardDesign.textMuted,
            .kern: 2.0,
        ]
        let numSize = dayNum.size(withAttributes: heroNumAttrs)
        dayNum.draw(at: CGPoint(x: sidePad, y: 174), withAttributes: heroNumAttrs)
        dayName.draw(at: CGPoint(x: sidePad + numSize.width + 20, y: 244), withAttributes: heroNameAttrs)

        let dotX = sidePad + numSize.width + 20 + dayName.size(withAttributes: heroNameAttrs).width + 22
        accent.setFill()
        UIBezierPath(ovalIn: CGRect(x: dotX, y: 268, width: 15, height: 15)).fill()

        // Summary eyebrow
        let countLabel = summary.activityCount == 1 ? "1 ACTIVITY" : "\(summary.activityCount) ACTIVITIES"
        let eyebrow = "\(countLabel)  •  \(summary.totalDurationFormatted.uppercased())"
        eyebrow.draw(
            at: CGPoint(x: sidePad, y: 340),
            withAttributes: [
                .font: StoryCardFontToken.mono(size: 22, weight: .medium),
                .foregroundColor: StoryCardDesign.textMuted,
                .kern: 1.6,
            ]
        )

        // Divider
        cg.setStrokeColor(StoryCardDesign.divider.cgColor)
        cg.setLineWidth(1)
        cg.move(to: CGPoint(x: sidePad, y: 400))
        cg.addLine(to: CGPoint(x: size.width - sidePad, y: 400))
        cg.strokePath()

        // Activity tiles (up to 4)
        let maxTiles = min(tiles.count, 4)
        let tileH: CGFloat = 172
        let tileGap: CGFloat = 14
        let statsH: CGFloat = 130
        let brandH: CGFloat = options.showBrandBadge ? 110 : 40
        let totalTileH = CGFloat(maxTiles) * tileH + CGFloat(max(0, maxTiles - 1)) * tileGap
        let availH = size.height - 430 - statsH - brandH
        let tilesStartY = 430 + max(0, (availH - totalTileH) / 6)

        for i in 0..<maxTiles {
            let rect = CGRect(x: sidePad, y: tilesStartY + CGFloat(i) * (tileH + tileGap), width: size.width - sidePad * 2, height: tileH)
            drawHeroStackTile(tile: tiles[i], rect: rect, cg: cg)
        }

        // Stat row
        let statsY = size.height - statsH - brandH + 4
        drawStatRow(summary: summary, options: options, accent: accent, y: statsY, size: size, cg: cg)

        if options.showBrandBadge {
            drawBrandBadge(y: size.height - 86, size: size)
        }
    }

    private static func drawHeroStackTile(tile: TileData, rect: CGRect, cg: CGContext) {
        StoryCardDrawing.drawPanel(in: rect, cornerRadius: StoryCardDesign.panelRadius, cg: cg)

        let iconRadius: CGFloat = 40
        let iconCenter = CGPoint(x: rect.minX + 30 + iconRadius, y: rect.midY)
        drawIconCircleAndSymbol(symbol: tile.symbol, color: tile.accentColor, center: iconCenter, radius: iconRadius, cg: cg)

        let textX = iconCenter.x + iconRadius + 22
        tile.typeLabel.draw(
            at: CGPoint(x: textX, y: rect.midY - 38),
            withAttributes: [
                .font: StoryCardFontToken.ui(size: 34, weight: .medium),
                .foregroundColor: StoryCardDesign.textPrimary,
            ]
        )
        tile.durationText.draw(
            at: CGPoint(x: textX, y: rect.midY + 10),
            withAttributes: [
                .font: StoryCardFontToken.mono(size: 28, weight: .medium),
                .foregroundColor: StoryCardDesign.textMuted,
                .kern: -0.4,
            ]
        )

        if let metric = tile.metricText {
            let mAttrs: [NSAttributedString.Key: Any] = [
                .font: StoryCardFontToken.mono(size: 42, weight: .bold),
                .foregroundColor: StoryCardDesign.textPrimary,
                .kern: -1.4,
            ]
            let mSz = metric.size(withAttributes: mAttrs)
            metric.draw(at: CGPoint(x: rect.maxX - 34 - mSz.width, y: rect.midY - 22), withAttributes: mAttrs)
        }
        if let detail = tile.detailText {
            let dAttrs: [NSAttributedString.Key: Any] = [
                .font: StoryCardFontToken.mono(size: 20, weight: .medium),
                .foregroundColor: StoryCardDesign.textQuiet,
                .kern: 0.6,
            ]
            let dSize = detail.size(withAttributes: dAttrs)
            detail.draw(at: CGPoint(x: rect.maxX - 34 - dSize.width, y: rect.midY + 32), withAttributes: dAttrs)
        }
        if let zones = tile.hrZoneMillis {
            drawHRZoneStrip(zones: zones, rect: CGRect(x: textX, y: rect.maxY - 24, width: rect.width - 250, height: 8), cg: cg)
        }
    }

    // MARK: - Template: Mosaic

    private static func drawMosaic(
        cg: CGContext,
        size: CGSize,
        summary: DaySummary,
        options: DaySummaryCardOptions
    ) {
        let accent = gradientAccents[min(options.backgroundGradientIndex, gradientAccents.count - 1)]
        let tiles = tileData(for: summary, options: options)

        drawHeader(summary: summary, options: options, accent: accent, y: 80, size: size, cg: cg)

        // Hero stat
        let (heroValue, heroLabel, heroUnit): (String, String, String) = {
            if summary.totalKilojoules > 0, !options.privacyHidePower {
                return ("\(Int(summary.totalKilojoules.rounded()))", "ENERGY OUTPUT", "kJ")
            }
            return (summary.totalDurationFormatted.uppercased(), "TOTAL TIME", "")
        }()

        heroLabel.draw(
            at: CGPoint(x: sidePad, y: 192),
            withAttributes: [
                .font: StoryCardFontToken.mono(size: 22, weight: .medium),
                .foregroundColor: accent.withAlphaComponent(0.9),
                .kern: 2.0,
            ]
        )

        let maxHeroW = size.width - sidePad * 2 - (heroUnit.isEmpty ? 0 : 160)
        let heroFontSize = fittingFontSize(for: heroValue, startingAt: 140, minimum: 80, maxWidth: maxHeroW)
        let heroAttrs: [NSAttributedString.Key: Any] = [
            .font: StoryCardFontToken.mono(size: heroFontSize, weight: .heavy),
            .foregroundColor: StoryCardDesign.textPrimary,
            .kern: -5.0,
        ]
        let heroSz = heroValue.size(withAttributes: heroAttrs)
        heroValue.draw(at: CGPoint(x: sidePad, y: 242), withAttributes: heroAttrs)
        if !heroUnit.isEmpty {
            heroUnit.draw(
                at: CGPoint(x: sidePad + heroSz.width + 14, y: 242 + heroFontSize * 0.64),
                withAttributes: [
                    .font: StoryCardFontToken.ui(size: 44, weight: .medium),
                    .foregroundColor: StoryCardDesign.textMuted,
                ]
            )
        }

        // 2-column tile grid (up to 6)
        let maxTiles = min(tiles.count, 6)
        let gap: CGFloat = 16
        let tileW = (size.width - sidePad * 2 - gap) / 2
        let tileH: CGFloat = 206
        let gridStartY: CGFloat = 432

        for i in 0..<maxTiles {
            let col = i % 2
            let row = i / 2
            let rect = CGRect(
                x: sidePad + CGFloat(col) * (tileW + gap),
                y: gridStartY + CGFloat(row) * (tileH + gap),
                width: tileW,
                height: tileH
            )
            let tile = tiles[i]
            StoryCardDrawing.drawPanel(in: rect, cornerRadius: StoryCardDesign.panelRadius, cg: cg)

            let iconRadius: CGFloat = 32
            let iconCenter = CGPoint(x: rect.minX + iconRadius + 20, y: rect.minY + iconRadius + 18)
            drawIconCircleAndSymbol(symbol: tile.symbol, color: tile.accentColor, center: iconCenter, radius: iconRadius, cg: cg)

            tile.typeLabel.draw(
                at: CGPoint(x: rect.minX + 20, y: iconCenter.y + iconRadius + 14),
                withAttributes: [
                    .font: StoryCardFontToken.ui(size: 30, weight: .medium),
                    .foregroundColor: StoryCardDesign.textPrimary,
                ]
            )
            tile.durationText.draw(
                at: CGPoint(x: rect.minX + 20, y: iconCenter.y + iconRadius + 54),
                withAttributes: [
                    .font: StoryCardFontToken.mono(size: 26, weight: .medium),
                    .foregroundColor: StoryCardDesign.textMuted,
                    .kern: -0.4,
                ]
            )
            if let metric = tile.metricText {
                let mAttrs: [NSAttributedString.Key: Any] = [
                    .font: StoryCardFontToken.mono(size: 26, weight: .bold),
                    .foregroundColor: tile.accentColor.withAlphaComponent(0.88),
                    .kern: -0.8,
                ]
                let mSz = metric.size(withAttributes: mAttrs)
                metric.draw(at: CGPoint(x: rect.maxX - mSz.width - 16, y: rect.maxY - 44), withAttributes: mAttrs)
            }
            if let detail = tile.detailText {
                detail.draw(
                    at: CGPoint(x: rect.minX + 20, y: rect.maxY - 44),
                    withAttributes: [
                        .font: StoryCardFontToken.mono(size: 18, weight: .medium),
                        .foregroundColor: StoryCardDesign.textQuiet,
                        .kern: 0.4,
                    ]
                )
            }
            if let polyline = tile.mapPolyline, i == 0 {
                drawMiniRoute(polyline: polyline, in: CGRect(x: rect.maxX - 104, y: rect.minY + 18, width: 84, height: 68), color: tile.accentColor, cg: cg)
            }
        }

        let statsY = size.height - (options.showBrandBadge ? 290 : 230)
        drawStatRow(summary: summary, options: options, accent: accent, y: statsY, size: size, cg: cg)

        if options.showBrandBadge {
            drawBrandBadge(y: size.height - 86, size: size)
        }
    }

    // MARK: - Template: Timeline Ribbon

    private static func drawTimelineRibbon(
        cg: CGContext,
        size: CGSize,
        summary: DaySummary,
        options: DaySummaryCardOptions
    ) {
        let accent = gradientAccents[min(options.backgroundGradientIndex, gradientAccents.count - 1)]
        let tiles = tileData(for: summary, options: options)

        drawHeader(summary: summary, options: options, accent: accent, y: 80, size: size, cg: cg)

        // Big day display
        let bigDay = fullDayFormatter.string(from: summary.date).uppercased()
        let bigNum = "\(Calendar.current.component(.day, from: summary.date))"

        bigDay.draw(
            at: CGPoint(x: sidePad, y: 178),
            withAttributes: [
                .font: StoryCardFontToken.ui(size: 38, weight: .medium),
                .foregroundColor: accent.withAlphaComponent(0.88),
                .kern: 2.4,
            ]
        )

        let bigNumAttrs: [NSAttributedString.Key: Any] = [
            .font: StoryCardFontToken.mono(size: 178, weight: .heavy),
            .foregroundColor: StoryCardDesign.textPrimary,
            .kern: -6.0,
        ]
        bigNum.draw(at: CGPoint(x: sidePad - 4, y: 222), withAttributes: bigNumAttrs)

        // Activity count badge (top-right)
        let countText = "\(summary.activityCount) ACT"
        let badgeAttrs: [NSAttributedString.Key: Any] = [
            .font: StoryCardFontToken.mono(size: 20, weight: .medium),
            .foregroundColor: StoryCardDesign.textMuted,
            .kern: 1.2,
        ]
        let badgeSz = countText.size(withAttributes: badgeAttrs)
        let badgeX = size.width - sidePad - badgeSz.width - 24
        let badgeY: CGFloat = 476
        accent.withAlphaComponent(0.16).setFill()
        UIBezierPath(roundedRect: CGRect(x: badgeX - 12, y: badgeY - 8, width: badgeSz.width + 24, height: badgeSz.height + 16), cornerRadius: 20).fill()
        countText.draw(at: CGPoint(x: badgeX, y: badgeY), withAttributes: badgeAttrs)

        // Timeline ribbon bar
        let ribbonRect = CGRect(x: sidePad, y: 544, width: size.width - sidePad * 2, height: 68)
        drawRibbonBar(tiles: tiles, summary: summary, rect: ribbonRect, cg: cg)

        // Connector dots + activity cards below
        let gridStartY = ribbonRect.maxY + 56
        drawTileGrid(tiles: tiles, startY: gridStartY, cols: 2, maxTiles: 4, tileH: 164, size: size, cg: cg)

        let statsY = size.height - (options.showBrandBadge ? 290 : 230)
        drawStatRow(summary: summary, options: options, accent: accent, y: statsY, size: size, cg: cg)

        if options.showBrandBadge {
            drawBrandBadge(y: size.height - 86, size: size)
        }
    }

    private static func drawRibbonBar(
        tiles: [TileData],
        summary: DaySummary,
        rect: CGRect,
        cg: CGContext
    ) {
        let trackPath = UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2)
        StoryCardDesign.panelTop.withAlphaComponent(0.6).setFill()
        trackPath.fill()
        StoryCardDesign.panelBorder.setStroke()
        trackPath.lineWidth = 1
        trackPath.stroke()

        guard !tiles.isEmpty else { return }

        let totalSec = max(1.0, tiles.reduce(0.0) { $0 + $1.durationSeconds })
        let gap: CGFloat = 4
        let totalGaps = gap * CGFloat(max(0, tiles.count - 1))
        let availW = rect.width - totalGaps
        var cursor = rect.minX

        cg.saveGState()
        cg.addPath(trackPath.cgPath)
        cg.clip()

        var segStarts: [CGFloat] = []
        var segWidths: [CGFloat] = []

        for (i, tile) in tiles.enumerated() {
            let segW = max(28, availW * CGFloat(tile.durationSeconds / totalSec))
            tile.accentColor.withAlphaComponent(0.84).setFill()
            UIRectFill(CGRect(x: cursor, y: rect.minY, width: segW, height: rect.height))
            segStarts.append(cursor)
            segWidths.append(segW)
            cursor += segW + (i < tiles.count - 1 ? gap : 0)
        }

        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: StoryCardFontToken.mono(size: 17, weight: .semibold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.82),
            .kern: 0.6,
        ]
        for (i, tile) in tiles.enumerated() {
            let segW = segWidths[i]
            guard segW >= 52 else { continue }
            let labelSz = tile.ribbonLabel.size(withAttributes: labelAttrs)
            let lx = segStarts[i] + (segW - labelSz.width) / 2
            let ly = rect.midY - labelSz.height / 2
            tile.ribbonLabel.draw(at: CGPoint(x: lx, y: ly), withAttributes: labelAttrs)
        }

        cg.restoreGState()
    }

    private static func drawTileGrid(
        tiles: [TileData],
        startY: CGFloat,
        cols: Int,
        maxTiles: Int,
        tileH: CGFloat,
        size: CGSize,
        cg: CGContext
    ) {
        let colsF = CGFloat(cols)
        let gap: CGFloat = 14
        let tileW = (size.width - sidePad * 2 - gap * (colsF - 1)) / colsF
        let count = min(tiles.count, maxTiles)

        for i in 0..<count {
            let col = i % cols
            let row = i / cols
            let rect = CGRect(
                x: sidePad + CGFloat(col) * (tileW + gap),
                y: startY + CGFloat(row) * (tileH + gap),
                width: tileW,
                height: tileH
            )
            guard rect.maxY < size.height - 260 else { break }

            let tile = tiles[i]
            StoryCardDrawing.drawPanel(in: rect, cornerRadius: StoryCardDesign.panelRadius, cg: cg)

            let iconRadius: CGFloat = 28
            let iconCenter = CGPoint(x: rect.minX + iconRadius + 18, y: rect.midY)
            drawIconCircleAndSymbol(symbol: tile.symbol, color: tile.accentColor, center: iconCenter, radius: iconRadius, cg: cg)

            let textX = iconCenter.x + iconRadius + 16
            tile.typeLabel.draw(
                at: CGPoint(x: textX, y: rect.midY - 30),
                withAttributes: [
                    .font: StoryCardFontToken.ui(size: 30, weight: .medium),
                    .foregroundColor: StoryCardDesign.textPrimary,
                ]
            )
            tile.durationText.draw(
                at: CGPoint(x: textX, y: rect.midY + 8),
                withAttributes: [
                    .font: StoryCardFontToken.mono(size: 26, weight: .medium),
                    .foregroundColor: StoryCardDesign.textMuted,
                    .kern: -0.4,
                ]
            )
            if let metric = tile.metricText {
                let mAttrs: [NSAttributedString.Key: Any] = [
                    .font: StoryCardFontToken.mono(size: 28, weight: .bold),
                    .foregroundColor: tile.accentColor.withAlphaComponent(0.88),
                    .kern: -0.8,
                ]
                let mSz = metric.size(withAttributes: mAttrs)
                metric.draw(at: CGPoint(x: rect.maxX - mSz.width - 16, y: rect.midY - 14), withAttributes: mAttrs)
            }
            if let detail = tile.detailText {
                detail.draw(
                    at: CGPoint(x: textX, y: rect.midY + 42),
                    withAttributes: [
                        .font: StoryCardFontToken.mono(size: 17, weight: .medium),
                        .foregroundColor: StoryCardDesign.textQuiet,
                        .kern: 0.4,
                    ]
                )
            }
        }
    }

    // MARK: - Template: Minimalist

    private static func drawMinimalist(
        cg: CGContext,
        size: CGSize,
        summary: DaySummary,
        options: DaySummaryCardOptions
    ) {
        let accent = gradientAccents[min(options.backgroundGradientIndex, gradientAccents.count - 1)]
        let tiles = tileData(for: summary, options: options)

        drawHeader(summary: summary, options: options, accent: accent, y: 80, size: size, cg: cg)

        // Huge count — single digit gets a smaller size so it doesn't look absurdly wide
        let countStr = "\(summary.activityCount)"
        let countFontSize: CGFloat = summary.activityCount < 10 ? 260 : 340
        let countAttrs: [NSAttributedString.Key: Any] = [
            .font: StoryCardFontToken.mono(size: countFontSize, weight: .heavy),
            .foregroundColor: StoryCardDesign.textPrimary,
            .kern: -14.0,
        ]
        let countSz = countStr.size(withAttributes: countAttrs)
        let countY = (size.height - countSz.height) / 2 - 180
        countStr.draw(at: CGPoint(x: (size.width - countSz.width) / 2, y: countY), withAttributes: countAttrs)

        // Label
        let label = summary.activityCount == 1 ? "ACTIVITY TODAY" : "ACTIVITIES TODAY"
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: StoryCardFontToken.mono(size: 26, weight: .medium),
            .foregroundColor: StoryCardDesign.textMuted,
            .kern: 2.4,
        ]
        let labelSz = label.size(withAttributes: labelAttrs)
        label.draw(at: CGPoint(x: (size.width - labelSz.width) / 2, y: countY + countSz.height + 8), withAttributes: labelAttrs)

        // Duration in accent color
        let durAttrs: [NSAttributedString.Key: Any] = [
            .font: StoryCardFontToken.mono(size: 64, weight: .bold),
            .foregroundColor: accent.withAlphaComponent(0.90),
            .kern: -2.0,
        ]
        let durSz = summary.totalDurationFormatted.size(withAttributes: durAttrs)
        let durY = countY + countSz.height + 88
        summary.totalDurationFormatted.draw(
            at: CGPoint(x: (size.width - durSz.width) / 2, y: durY),
            withAttributes: durAttrs
        )

        // Icon row (up to 5 activities)
        let iconRadius: CGFloat = 50
        let iconGap: CGFloat = 20
        let displayTiles = Array(tiles.prefix(5))
        let totalIconW = CGFloat(displayTiles.count) * iconRadius * 2 + CGFloat(max(0, displayTiles.count - 1)) * iconGap
        var iconX = (size.width - totalIconW) / 2
        let iconY = durY + 110

        for tile in displayTiles {
            drawIconCircleAndSymbol(symbol: tile.symbol, color: tile.accentColor, center: CGPoint(x: iconX + iconRadius, y: iconY + iconRadius), radius: iconRadius, cg: cg)
            iconX += iconRadius * 2 + iconGap
        }

        let statsY = size.height - (options.showBrandBadge ? 290 : 230)
        drawStatRow(summary: summary, options: options, accent: accent, y: statsY, size: size, cg: cg)

        if options.showBrandBadge {
            drawBrandBadge(y: size.height - 86, size: size)
        }
    }

    // MARK: - Template: Poster Grid

    private static func drawPosterGrid(
        cg: CGContext,
        size: CGSize,
        summary: DaySummary,
        options: DaySummaryCardOptions
    ) {
        let accent = gradientAccents[min(options.backgroundGradientIndex, gradientAccents.count - 1)]
        let tiles = tileData(for: summary, options: options)

        drawBackdropWord("FULL", at: CGPoint(x: sidePad - 14, y: 142), size: 184, alpha: 0.055)
        drawBackdropWord("DAY", at: CGPoint(x: sidePad - 10, y: 292), size: 206, alpha: 0.070)
        drawCapsuleText("\(summary.activityCount) ACTIVITY MIX", at: CGPoint(x: sidePad, y: 90), color: accent)

        let title = fullDayFormatter.string(from: summary.date).uppercased()
        title.draw(
            at: CGPoint(x: sidePad, y: 194),
            withAttributes: [
                .font: StoryCardFontToken.ui(size: 62, weight: .medium),
                .foregroundColor: StoryCardDesign.textPrimary,
                .kern: 2.0,
            ]
        )

        let hero = summary.totalDurationFormatted.uppercased()
        let heroSize = fittingFontSize(for: hero, startingAt: 128, minimum: 76, maxWidth: size.width - sidePad * 2)
        hero.draw(
            at: CGPoint(x: sidePad, y: 276),
            withAttributes: [
                .font: StoryCardFontToken.mono(size: heroSize, weight: .heavy),
                .foregroundColor: StoryCardDesign.textPrimary,
                .kern: -4.5,
            ]
        )

        let gridStartY: CGFloat = 510
        let gap: CGFloat = 18
        let tileW = (size.width - sidePad * 2 - gap) / 2
        let tileH: CGFloat = 244
        for i in 0..<min(tiles.count, 6) {
            let row = i / 2
            let col = i % 2
            let rect = CGRect(
                x: sidePad + CGFloat(col) * (tileW + gap),
                y: gridStartY + CGFloat(row) * (tileH + gap),
                width: tileW,
                height: tileH
            )
            guard rect.maxY < size.height - 280 else { break }
            let tile = tiles[i]
            StoryCardDrawing.drawPanel(in: rect, cornerRadius: 26, cg: cg)
            drawAngledBand(rect: CGRect(x: rect.minX + 12, y: rect.minY + 18, width: rect.width - 24, height: 58), color: tile.accentColor.withAlphaComponent(0.26), cg: cg)
            drawIconCircleAndSymbol(symbol: tile.symbol, color: tile.accentColor, center: CGPoint(x: rect.minX + 58, y: rect.minY + 56), radius: 30, cg: cg)
            drawOneLine(tile.typeLabel, in: CGRect(x: rect.minX + 22, y: rect.minY + 112, width: rect.width - 44, height: 36), fontSize: 31, minSize: 21, color: StoryCardDesign.textPrimary, weight: .medium)
            tile.durationText.draw(
                at: CGPoint(x: rect.minX + 22, y: rect.minY + 160),
                withAttributes: [
                    .font: StoryCardFontToken.mono(size: 28, weight: .bold),
                    .foregroundColor: tile.accentColor.withAlphaComponent(0.94),
                    .kern: -0.8,
                ]
            )
            if let metric = tile.metricText {
                metric.draw(
                    at: CGPoint(x: rect.minX + 22, y: rect.minY + 198),
                    withAttributes: [
                        .font: StoryCardFontToken.mono(size: 21, weight: .medium),
                        .foregroundColor: StoryCardDesign.textMuted,
                        .kern: 0.4,
                    ]
                )
            }
            if let polyline = tile.mapPolyline {
                drawMiniRoute(polyline: polyline, in: CGRect(x: rect.maxX - 110, y: rect.minY + 18, width: 88, height: 68), color: tile.accentColor, cg: cg)
            } else if let zones = tile.hrZoneMillis {
                drawHRZoneStrip(zones: zones, rect: CGRect(x: rect.minX + 22, y: rect.maxY - 24, width: rect.width - 44, height: 8), cg: cg)
            }
        }

        drawStatRow(summary: summary, options: options, accent: accent, y: size.height - (options.showBrandBadge ? 292 : 230), size: size, cg: cg)
        if options.showBrandBadge { drawBrandBadge(y: size.height - 86, size: size) }
    }

    // MARK: - Template: Orbit

    private static func drawOrbit(
        cg: CGContext,
        size: CGSize,
        summary: DaySummary,
        options: DaySummaryCardOptions
    ) {
        let accent = gradientAccents[min(options.backgroundGradientIndex, gradientAccents.count - 1)]
        let tiles = Array(tileData(for: summary, options: options).prefix(7))
        drawHeader(summary: summary, options: options, accent: accent, y: 80, size: size, cg: cg)

        let center = CGPoint(x: size.width / 2, y: 660)
        for radius in [320, 235, 150] as [CGFloat] {
            cg.setStrokeColor(UIColor.white.withAlphaComponent(radius == 235 ? 0.13 : 0.07).cgColor)
            cg.setLineWidth(radius == 235 ? 2 : 1)
            cg.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        }

        let total = summary.totalDurationFormatted.uppercased()
        let totalAttrs: [NSAttributedString.Key: Any] = [
            .font: StoryCardFontToken.mono(size: fittingFontSize(for: total, startingAt: 98, minimum: 58, maxWidth: 520), weight: .heavy),
            .foregroundColor: StoryCardDesign.textPrimary,
            .kern: -3.0,
        ]
        let totalSize = total.size(withAttributes: totalAttrs)
        total.draw(at: CGPoint(x: center.x - totalSize.width / 2, y: center.y - 58), withAttributes: totalAttrs)
        let label = "\(summary.activityCount) MOVES TODAY"
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: StoryCardFontToken.mono(size: 24, weight: .medium),
            .foregroundColor: accent.withAlphaComponent(0.92),
            .kern: 2.0,
        ]
        let labelSize = label.size(withAttributes: labelAttrs)
        label.draw(at: CGPoint(x: center.x - labelSize.width / 2, y: center.y + 54), withAttributes: labelAttrs)

        for (i, tile) in tiles.enumerated() {
            let angle = (-CGFloat.pi / 2) + CGFloat(i) * (2 * .pi / CGFloat(max(tiles.count, 1)))
            let radius: CGFloat = i.isMultiple(of: 2) ? 310 : 235
            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            drawIconCircleAndSymbol(symbol: tile.symbol, color: tile.accentColor, center: point, radius: i == 0 ? 58 : 46, cg: cg)
        }

        // center the list between the bottom of the orbit icons and the stat row
        let orbitBottom = center.y + 310 + 58 + 24
        let statRowY = size.height - (options.showBrandBadge ? 292 : 230)
        let listCount = CGFloat(min(tiles.count, 4))
        let listHeight = listCount * 92
        let listY = (orbitBottom + statRowY - listHeight) / 2

        for (i, tile) in tiles.prefix(4).enumerated() {
            let y = listY + CGFloat(i) * 92
            let color = tile.accentColor
            color.withAlphaComponent(0.92).setFill()
            UIBezierPath(roundedRect: CGRect(x: sidePad, y: y + 12, width: 9, height: 54), cornerRadius: 4.5).fill()
            drawOneLine(tile.typeLabel, in: CGRect(x: sidePad + 26, y: y, width: 510, height: 36), fontSize: 32, minSize: 22, color: StoryCardDesign.textPrimary, weight: .medium)
            tile.durationText.draw(
                at: CGPoint(x: sidePad + 26, y: y + 42),
                withAttributes: [
                    .font: StoryCardFontToken.mono(size: 24, weight: .medium),
                    .foregroundColor: StoryCardDesign.textMuted,
                    .kern: 0.2,
                ]
            )
            if let detail = tile.detailText {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: StoryCardFontToken.mono(size: 20, weight: .medium),
                    .foregroundColor: tile.accentColor.withAlphaComponent(0.86),
                    .kern: 0.3,
                ]
                let detailSize = detail.size(withAttributes: attrs)
                detail.draw(at: CGPoint(x: size.width - sidePad - detailSize.width, y: y + 42), withAttributes: attrs)
            }
        }

        drawStatRow(summary: summary, options: options, accent: accent, y: size.height - (options.showBrandBadge ? 292 : 230), size: size, cg: cg)
        if options.showBrandBadge { drawBrandBadge(y: size.height - 86, size: size) }
    }

    // MARK: - Template: Scoreboard

    private static func drawScoreboard(
        cg: CGContext,
        size: CGSize,
        summary: DaySummary,
        options: DaySummaryCardOptions
    ) {
        let accent = gradientAccents[min(options.backgroundGradientIndex, gradientAccents.count - 1)]
        let tiles = tileData(for: summary, options: options)

        drawBackdropWord("SCORE", at: CGPoint(x: sidePad - 22, y: 96), size: 150, alpha: 0.055)
        drawHeader(summary: summary, options: options, accent: accent, y: 80, size: size, cg: cg)

        let board = CGRect(x: sidePad, y: 210, width: size.width - sidePad * 2, height: 438)
        StoryCardDrawing.drawPanel(in: board, cornerRadius: 34, cg: cg)
        drawCapsuleText("DAY SCOREBOARD", at: CGPoint(x: board.minX + 32, y: board.minY + 34), color: accent, fontSize: 20)

        let count = "\(summary.activityCount)"
        count.draw(
            at: CGPoint(x: board.minX + 34, y: board.minY + 94),
            withAttributes: [
                .font: StoryCardFontToken.mono(size: 190, weight: .heavy),
                .foregroundColor: StoryCardDesign.textPrimary,
                .kern: -8.0,
            ]
        )
        "ACTIVITIES".draw(
            at: CGPoint(x: board.minX + 48, y: board.minY + 292),
            withAttributes: [
                .font: StoryCardFontToken.mono(size: 28, weight: .medium),
                .foregroundColor: StoryCardDesign.textMuted,
                .kern: 2.4,
            ]
        )

        let rightX = board.midX + 34
        let bigStats: [(String, String)] = [
            ("TIME", summary.totalDurationFormatted.uppercased()),
            ("DIST", summary.totalDistanceMeters > 0 ? summary.totalDistanceFormatted : "—"),
            ("LOAD", summary.totalTSS.map { "\(Int($0.rounded())) TSS" } ?? (summary.totalKilojoules > 0 && !options.privacyHidePower ? "\(Int(summary.totalKilojoules.rounded())) kJ" : "—")),
        ]
        for (i, stat) in bigStats.enumerated() {
            let y = board.minY + 102 + CGFloat(i) * 92
            stat.0.draw(
                at: CGPoint(x: rightX, y: y),
                withAttributes: [
                    .font: StoryCardFontToken.mono(size: 18, weight: .medium),
                    .foregroundColor: accent.withAlphaComponent(0.86),
                    .kern: 1.4,
                ]
            )
            stat.1.draw(
                at: CGPoint(x: rightX, y: y + 28),
                withAttributes: [
                    .font: StoryCardFontToken.mono(size: 38, weight: .bold),
                    .foregroundColor: StoryCardDesign.textPrimary,
                    .kern: -1.2,
                ]
            )
        }

        let lanesY = board.maxY + 54
        for (i, tile) in tiles.prefix(6).enumerated() {
            let y = lanesY + CGFloat(i) * 118
            let lane = CGRect(x: sidePad, y: y, width: size.width - sidePad * 2, height: 92)
            tile.accentColor.withAlphaComponent(i.isMultiple(of: 2) ? 0.15 : 0.09).setFill()
            UIBezierPath(roundedRect: lane, cornerRadius: 22).fill()
            tile.accentColor.withAlphaComponent(0.35).setStroke()
            UIBezierPath(roundedRect: lane.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 22).stroke()
            drawIconCircleAndSymbol(symbol: tile.symbol, color: tile.accentColor, center: CGPoint(x: lane.minX + 48, y: lane.midY), radius: 27, cg: cg)
            drawOneLine(tile.typeLabel, in: CGRect(x: lane.minX + 92, y: lane.minY + 18, width: 500, height: 32), fontSize: 30, minSize: 20, color: StoryCardDesign.textPrimary, weight: .medium)
            tile.durationText.draw(
                at: CGPoint(x: lane.minX + 92, y: lane.minY + 53),
                withAttributes: [
                    .font: StoryCardFontToken.mono(size: 22, weight: .medium),
                    .foregroundColor: StoryCardDesign.textMuted,
                    .kern: 0.2,
                ]
            )
            if let metric = tile.metricText {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: StoryCardFontToken.mono(size: 26, weight: .bold),
                    .foregroundColor: tile.accentColor.withAlphaComponent(0.94),
                    .kern: -0.6,
                ]
                let mSize = metric.size(withAttributes: attrs)
                metric.draw(at: CGPoint(x: lane.maxX - mSize.width - 26, y: lane.midY - 16), withAttributes: attrs)
            }
            if let zones = tile.hrZoneMillis {
                drawHRZoneStrip(zones: zones, rect: CGRect(x: lane.minX + 92, y: lane.maxY - 15, width: lane.width - 190, height: 6), cg: cg)
            }
        }

        if options.showBrandBadge { drawBrandBadge(y: size.height - 86, size: size) }
    }
}

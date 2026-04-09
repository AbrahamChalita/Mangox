import SwiftUI
import Foundation

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Strava Post Builder

/// Generates context-aware Strava titles, structured text descriptions,
/// and a rendered summary card image from workout data.
enum StravaPostBuilder {

    /// Controls optional fields in the text description Strava shows as plain text (proportional font).
    struct DescriptionOptions: Equatable {
        /// Include elapsed duration in the stats block. Strava already shows time on the activity; some athletes prefer to omit it here.
        var includeDuration: Bool = true
        /// Include distance. Strava shows distance on the activity header; omit to shorten the feed preview.
        var includeDistance: Bool = true
        /// Include estimated calories.
        var includeCalories: Bool = true
    }

    // MARK: - Title Generation

    /// Generates a clever, context-aware activity title.
    static func buildTitle(
        workout: Workout,
        routeName: String? = nil,
        dominantPowerZone: PowerZone? = nil,
        personalRecordNames: [String] = []
    ) -> String {
        let hour = Calendar.current.component(.hour, from: workout.startDate)
        let weekday = Calendar.current.component(.weekday, from: workout.startDate)
        let zone = dominantPowerZone ?? PowerZone.zone(for: Int(workout.avgPower.rounded()))
        let tss = workout.tss
        let durationMinutes = workout.duration / 60

        // PR override — always leads with the achievement
        if !personalRecordNames.isEmpty {
            let prTag = personalRecordNames.count == 1
                ? personalRecordNames[0]
                : "\(personalRecordNames.count) PRs"
            return "New \(prTag)"
        }

        // Epic/heroic efforts
        if tss >= 400 {
            return epicTitle(hour: hour, weekday: weekday, zone: zone)
        }

        // Long endurance ride (>2 hr, mostly Z1/Z2)
        if durationMinutes >= 120 && zone.id <= 2 {
            return longEnduranceTitle(hour: hour, weekday: weekday)
        }

        // High intensity / VO2 max
        if zone.id == 5 || workout.intensityFactor >= 1.05 {
            return highIntensityTitle(hour: hour, weekday: weekday)
        }

        // Threshold work
        if zone.id == 4 || (workout.intensityFactor >= 0.88 && workout.intensityFactor < 1.05) {
            return thresholdTitle(hour: hour, weekday: weekday)
        }

        // Tempo
        if zone.id == 3 {
            return tempoTitle(hour: hour, weekday: weekday)
        }

        // Easy/recovery
        if zone.id <= 2 {
            return easyTitle(hour: hour, weekday: weekday)
        }

        // Fallback: generic time-of-day
        let dayPart = dayPartLabel(hour: hour)
        if let routeName, !routeName.isEmpty {
            return "\(dayPart) Ride · \(routeName)"
        }
        return "\(dayPart) Ride"
    }

    // MARK: - Description Generation

    /// Generates a Strava activity description as plain text: short lines and simple bullets so it reads correctly
    /// in Strava’s proportional font (no fixed-width column padding).
    static func buildDescription(
        workout: Workout,
        routeName: String? = nil,
        totalElevationGain: Double = 0,
        dominantPowerZone: PowerZone? = nil,
        zoneBuckets: [(zone: PowerZone, percent: Double)] = [],
        personalRecordNames: [String] = [],
        options: DescriptionOptions = DescriptionOptions()
    ) -> String {
        let zone = dominantPowerZone ?? PowerZone.zone(for: Int(workout.avgPower.rounded()))
        var sections: [String] = []

        // Lead with a short hook so Strava’s feed preview shows the best line first.
        sections.append(descriptionHook(workout: workout, personalRecordNames: personalRecordNames))
        sections.append(narrativeHeadline(workout: workout, zone: zone))

        let distKm = workout.distance / 1000
        let calories = WorkoutExportService.estimateCalories(
            avgPower: workout.avgPower,
            durationSeconds: workout.duration
        )
        var statLines: [String] = []
        if options.includeDistance {
            statLines.append(String(format: "Distance: %.2f km", distKm))
        }
        if options.includeDuration {
            statLines.append("Duration: \(AppFormat.duration(workout.duration))")
        }
        if options.includeCalories {
            statLines.append("Calories (est.): \(calories) kcal")
        }
        if !statLines.isEmpty {
            sections.append(statLines.joined(separator: "\n"))
        }

        let hookUsedPowerSummary = personalRecordNames.isEmpty && workout.normalizedPower > 0

        var powerLines: [String] = []
        powerLines.append(
            "Power: \(Int(workout.avgPower.rounded())) W average · \(workout.maxPower) W max"
        )
        if hookUsedPowerSummary {
            // Hook already showed NP / IF / TSS — avoid repeating in the expanded description.
        } else if workout.normalizedPower > 0 {
            powerLines.append(
                "Normalized power: \(Int(workout.normalizedPower.rounded())) W · IF \(String(format: "%.2f", workout.intensityFactor)) · TSS \(Int(workout.tss.rounded()))"
            )
        }
        sections.append(powerLines.joined(separator: "\n"))

        var auxParts: [String] = []
        if workout.avgCadence > 0 { auxParts.append("\(Int(workout.avgCadence.rounded())) rpm avg cadence") }
        if workout.displayAverageSpeedKmh > 0 {
            auxParts.append(String(format: "%.1f km/h avg speed", workout.displayAverageSpeedKmh))
        }
        if workout.avgHR > 0 { auxParts.append("HR \(Int(workout.avgHR.rounded())) / \(workout.maxHR) bpm") }
        if totalElevationGain > 0 { auxParts.append("+\(Int(totalElevationGain.rounded())) m elevation") }
        if !auxParts.isEmpty {
            sections.append(auxParts.joined(separator: " · "))
        }

        let significantZones = zoneBuckets
            .filter { $0.percent >= 0.01 }
            .sorted { $0.percent > $1.percent }
            .prefix(6)

        if !significantZones.isEmpty {
            let zoneLines = significantZones.map { bucket in
                let pct = Int((bucket.percent * 100).rounded())
                return "• Z\(bucket.zone.id) \(bucket.zone.name) — \(pct)%"
            }
            sections.append("Power zones:\n" + zoneLines.joined(separator: "\n"))
        }

        if let commentary = effortCommentary(workout: workout, zone: zone) {
            sections.append(commentary)
        }

        if !personalRecordNames.isEmpty {
            let prList = personalRecordNames.map { "• \($0)" }.joined(separator: "\n")
            sections.append("Personal records:\n\(prList)")
        }

        let outdoorish =
            (workout.savedRouteName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            || workout.elevationGain > 1
        let outdoorBike = RidePreferences.shared.primaryOutdoorBikeName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let indoorBike = RidePreferences.shared.primaryIndoorBikeName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if outdoorish, !outdoorBike.isEmpty {
            sections.append("Bike: \(outdoorBike)")
        } else if !outdoorish, !indoorBike.isEmpty {
            sections.append("Trainer / bike: \(indoorBike)")
        }

        var footerParts: [String] = []
        if let r = routeName, !r.isEmpty { footerParts.append(r) }
        footerParts.append("Mangox")
        sections.append(footerParts.joined(separator: " · "))

        return sections.joined(separator: "\n\n")
    }

    /// Strava activity names are bounded; keep uploads reliable.
    static func clampActivityName(_ name: String, maxLength: Int = 255) -> String {
        guard name.count > maxLength else { return name }
        return String(name.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Summary Card Image

    /// Renders a 1080×1350 workout summary card as a `UIImage` suitable for uploading
    /// as a Strava activity photo.
    ///
    /// Layout (top → bottom):
    ///  1. Header — branding, date, zone badge
    ///  2. Hero stats row — duration · distance · kcal
    ///  3. Power trace sparkline — every sample, area fill colored by zone
    ///  4. Secondary stats row — avg W · max W · NP · TSS · IF
    ///  5. MMP bar chart — 8 duration buckets, PR durations highlighted
    ///  6. Zone distribution bar
    ///  7. Footer — HR (if any), route, tagline
    ///
    /// Returns `nil` on non-UIKit platforms.
    @MainActor
    static func renderSummaryCard(
        workout: Workout,
        dominantZone: PowerZone,
        sortedSamples: [WorkoutSampleData] = [],
        mmp: WorkoutMMP? = nil,
        newPRFlags: [NewPRFlag] = [],
        routeName: String? = nil,
        totalElevationGain: Double = 0,
        zoneBuckets: [(zone: PowerZone, percent: Double)] = []
    ) -> PlatformImage? {
        #if canImport(UIKit)
        let cardSize = CGSize(width: 1080, height: 1350)
        let renderer = UIGraphicsImageRenderer(size: cardSize)
        return renderer.image { ctx in
            drawCard(
                in: ctx.cgContext,
                size: cardSize,
                workout: workout,
                dominantZone: dominantZone,
                sortedSamples: sortedSamples,
                mmp: mmp,
                newPRFlags: newPRFlags,
                routeName: routeName,
                totalElevationGain: totalElevationGain,
                zoneBuckets: zoneBuckets
            )
        }
        #else
        return nil
        #endif
    }
}

// MARK: - Platform Image Typealias

#if canImport(UIKit)
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
typealias PlatformImage = NSImage
#endif

// MARK: - Private: Title Helpers

private extension StravaPostBuilder {

    static func dayPartLabel(hour: Int) -> String {
        switch hour {
        case 5..<9:   return "Early Morning"
        case 9..<12:  return "Morning"
        case 12..<14: return "Midday"
        case 14..<17: return "Afternoon"
        case 17..<20: return "Evening"
        case 20..<23: return "Night"
        default:      return "Late Night"
        }
    }

    static func epicTitle(hour: Int, weekday: Int, zone: PowerZone) -> String {
        let options: [String]
        switch zone.id {
        case 5: options = ["Sufferfest", "All-Out Carnage", "No Mercy", "Into the Red"]
        case 4: options = ["Epic Threshold Block", "Suffer Hour", "Deep Hurt", "Pain Cave Special"]
        default: options = ["Monster Ride", "The Big One", "Century Grind", "Savage Effort"]
        }
        return options[abs(weekday &* hour) % options.count]
    }

    static func longEnduranceTitle(hour: Int, weekday: Int) -> String {
        let options = [
            "Long Slow Distance", "Base Miles", "Aerobic Foundation",
            "Steady State Cruise", "Zone 2 Session", "The Long Spin",
            "Patience is Power"
        ]
        return options[abs(weekday &* hour) % options.count]
    }

    static func highIntensityTitle(hour: Int, weekday: Int) -> String {
        let options = [
            "VO2 Max Intervals", "High Voltage Session", "Red Zone Special",
            "Suffer and Repeat", "Race Pace Effort", "Interval Carnage", "Max Effort"
        ]
        return options[abs(weekday &* hour) % options.count]
    }

    static func thresholdTitle(hour: Int, weekday: Int) -> String {
        let options = [
            "Threshold Work", "FTP Builder", "Sweet Spot Session",
            "Steady Hard Effort", "Tempo Threshold Block",
            "Controlled Suffering", "Holding the Line"
        ]
        return options[abs(weekday &* hour) % options.count]
    }

    static func tempoTitle(hour: Int, weekday: Int) -> String {
        let options = [
            "Solid Tempo", "Comfortably Hard", "Yellow Zone Cruise",
            "Tempo Build", "Controlled Power", "Strong and Steady",
            "Race Simulation"
        ]
        return options[abs(weekday &* hour) % options.count]
    }

    static func easyTitle(hour: Int, weekday: Int) -> String {
        let options = [
            "Active Recovery", "Easy Spin", "Zone 1 Flush",
            "Legs Out", "Chill Watts",
            "Recovery Ride", "Aerobic Maintenance"
        ]
        return options[abs(weekday &* hour) % options.count]
    }
}

// MARK: - Private: Description Helpers

private extension StravaPostBuilder {

    /// First line(s) tuned for Strava’s truncated feed preview.
    static func descriptionHook(workout: Workout, personalRecordNames: [String]) -> String {
        if !personalRecordNames.isEmpty {
            if personalRecordNames.count == 1 {
                return "New PR: \(personalRecordNames[0])"
            }
            let head = personalRecordNames.prefix(2).joined(separator: " · ")
            if personalRecordNames.count == 2 {
                return "New PRs: \(head)"
            }
            return "New PRs: \(head) · +\(personalRecordNames.count - 2) more"
        }
        if workout.normalizedPower > 0 {
            return "NP \(Int(workout.normalizedPower.rounded())) W · IF \(String(format: "%.2f", workout.intensityFactor)) · TSS \(Int(workout.tss.rounded()))"
        }
        return "\(Int(workout.avgPower.rounded())) W avg · \(Int(workout.tss.rounded())) TSS"
    }

    static func narrativeHeadline(workout: Workout, zone: PowerZone) -> String {
        let tss = workout.tss
        let iF = workout.intensityFactor
        let durationMin = workout.duration / 60

        if tss >= 400 { return "One of those legendary suffer-fests. Every watt fought for." }
        if tss >= 250 { return "Seriously big day on the trainer. The legs will remember this one." }
        if tss >= 150 { return "Solid block of work done. Training stress is building in all the right ways." }
        if iF >= 1.0  { return "Above FTP effort — race-intensity pace held for the whole ride." }
        if iF >= 0.88 { return "Threshold pace. Sitting right at the edge of what's sustainable." }
        if iF >= 0.75 && zone.id >= 3 { return "Tempo effort — comfortably hard, building fitness one watt at a time." }
        if durationMin >= 90 && zone.id <= 2 { return "Long aerobic session. This is where the engine gets built." }
        if zone.id == 1 || iF < 0.65 { return "Active recovery. Legs grateful. Ready to go again." }
        return "Another session in the books. Consistency is the secret."
    }

    static func effortCommentary(workout: Workout, zone: PowerZone) -> String? {
        let vi = workout.avgPower > 0
            ? workout.normalizedPower / max(workout.avgPower, 1)
            : 0
        let tss = workout.tss
        var notes: [String] = []

        if vi >= 1.20 {
            notes.append("VI \(String(format: "%.2f", vi)) — highly variable effort, lots of surges")
        } else if vi <= 1.04 && vi > 0 {
            notes.append("VI \(String(format: "%.2f", vi)) — incredibly steady power output")
        }

        if tss >= 150 && tss < 300       { notes.append("Expect 12-24 h of fatigue") }
        else if tss >= 300 && tss < 450  { notes.append("Expect 24-36 h of fatigue — recovery day tomorrow") }
        else if tss >= 450               { notes.append("High fatigue — 2-3 days of recovery recommended") }

        if workout.avgHR > 0 && workout.avgPower > 0 {
            let aeRatio = workout.normalizedPower / max(Double(workout.avgHR), 1)
            if aeRatio >= 2.5 {
                notes.append("Strong aerobic efficiency — high power per heartbeat")
            }
        }

        return notes.isEmpty ? nil : notes.map { "• \($0)" }.joined(separator: "\n")
    }
}

// MARK: - Private: Card Drawing (UIKit only)

#if canImport(UIKit)
private extension StravaPostBuilder {

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Top-level layout orchestrator
    // ─────────────────────────────────────────────────────────────────────────

    static func drawCard(
        in cgCtx: CGContext,
        size: CGSize,
        workout: Workout,
        dominantZone: PowerZone,
        sortedSamples: [WorkoutSampleData],
        mmp: WorkoutMMP?,
        newPRFlags: [NewPRFlag],
        routeName: String?,
        totalElevationGain: Double,
        zoneBuckets: [(zone: PowerZone, percent: Double)]
    ) {
        let W = size.width
        let H = size.height
        let pad: CGFloat = 56          // horizontal padding
        let sectionGap: CGFloat = 36   // vertical gap between sections

        UIGraphicsPushContext(cgCtx)
        defer { UIGraphicsPopContext() }

        // ── 1. Background ──────────────────────────────────────────────────
        drawBackground(in: cgCtx, size: size, dominantZone: dominantZone)

        // ── 2. Top accent bar (zone-colored gradient) ──────────────────────
        let accentH: CGFloat = 6
        drawHorizontalGradientRect(
            in: cgCtx,
            rect: CGRect(x: 0, y: 0, width: W, height: accentH),
            color: uiColor(from: dominantZone.color)
        )

        var cursorY: CGFloat = accentH + 40

        // ── 3. Header row: branding left, date right ───────────────────────
        drawText("MANGOX", at: CGPoint(x: pad, y: cursorY),
                 font: .systemFont(ofSize: 20, weight: .black),
                 color: UIColor(white: 1, alpha: 0.22),
                 letterSpacing: 5)

        let dateStr = formattedDate(workout.startDate)
        drawText(dateStr, at: CGPoint(x: W - pad, y: cursorY + 1),
                 font: .systemFont(ofSize: 17, weight: .medium),
                 color: UIColor(white: 1, alpha: 0.25),
                 alignment: .right,
                 maxWidth: 340)

        cursorY += 44

        // ── 4. Zone pill badge ─────────────────────────────────────────────
        drawZonePill(zone: dominantZone, at: CGPoint(x: pad, y: cursorY))
        cursorY += 50

        // ── 5. Hero stats: duration · distance · kcal ──────────────────────
        cursorY += 6
        let calories = WorkoutExportService.estimateCalories(
            avgPower: workout.avgPower,
            durationSeconds: workout.duration
        )
        drawHeroStats(
            duration: AppFormat.duration(workout.duration),
            distKm: workout.distance / 1000,
            kcal: calories,
            in: CGRect(x: 0, y: cursorY, width: W, height: 130)
        )
        cursorY += 130 + sectionGap

        // ── 6. Power trace sparkline ───────────────────────────────────────
        let sparkH: CGFloat = sortedSamples.isEmpty ? 0 : 210
        if !sortedSamples.isEmpty {
            drawSectionLabel("POWER TRACE", at: CGPoint(x: pad, y: cursorY))
            cursorY += 26
            drawPowerSparkline(
                samples: sortedSamples,
                ftp: PowerZone.ftp,
                in: CGRect(x: pad, y: cursorY, width: W - pad * 2, height: sparkH),
                cgCtx: cgCtx
            )
            cursorY += sparkH + 6
            // Axis labels: 0 left, max right, avg power dashed line label
            drawSparklineAxisLabels(
                samples: sortedSamples,
                avgPower: workout.avgPower,
                in: CGRect(x: pad, y: cursorY, width: W - pad * 2, height: 26)
            )
            cursorY += 26 + sectionGap
        }

        // ── 7. Secondary stats: avg W · max W · NP · IF · TSS ─────────────
        drawSectionLabel("PERFORMANCE", at: CGPoint(x: pad, y: cursorY))
        cursorY += 26
        drawPerformanceStats(workout: workout, in: CGRect(x: 0, y: cursorY, width: W, height: 110))
        cursorY += 110 + sectionGap

        // ── 8. MMP bar chart ───────────────────────────────────────────────
        if let mmp {
            let mmpH: CGFloat = 220
            drawSectionLabel("MEAN MAXIMAL POWER", at: CGPoint(x: pad, y: cursorY))
            cursorY += 26
            drawMMPChart(
                mmp: mmp,
                newPRFlags: newPRFlags,
                dominantZone: dominantZone,
                in: CGRect(x: pad, y: cursorY, width: W - pad * 2, height: mmpH),
                cgCtx: cgCtx
            )
            cursorY += mmpH + sectionGap
        }

        // ── 9. Zone distribution bar ───────────────────────────────────────
        if !zoneBuckets.isEmpty {
            let zoneBarH: CGFloat = 32
            drawSectionLabel("ZONE DISTRIBUTION", at: CGPoint(x: pad, y: cursorY))
            cursorY += 26
            drawZoneBar(
                in: cgCtx,
                buckets: zoneBuckets,
                rect: CGRect(x: pad, y: cursorY, width: W - pad * 2, height: zoneBarH)
            )
            cursorY += zoneBarH + 10
            drawZoneBarLabels(
                buckets: zoneBuckets,
                rect: CGRect(x: pad, y: cursorY, width: W - pad * 2, height: 22)
            )
            cursorY += 22 + sectionGap
        }

        // ── 10. Footer: HR · route · elevation · tagline ──────────────────
        drawFooter(
            workout: workout,
            routeName: routeName,
            totalElevationGain: totalElevationGain,
            bottomY: H,
            leftPad: pad,
            width: W
        )
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Background
    // ─────────────────────────────────────────────────────────────────────────

    static func drawBackground(in ctx: CGContext, size: CGSize, dominantZone: PowerZone) {
        // Deep dark base
        let topColor    = UIColor(red: 0.030, green: 0.040, blue: 0.060, alpha: 1)
        let bottomColor = UIColor(red: 0.018, green: 0.022, blue: 0.034, alpha: 1)
        let bgColors = [topColor, bottomColor]
        let cgBgColors = bgColors.map { $0.cgColor } as CFArray
        if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgBgColors, locations: nil) {
            ctx.drawLinearGradient(
                grad,
                start: CGPoint(x: size.width / 2, y: 0),
                end: CGPoint(x: size.width / 2, y: size.height),
                options: []
            )
        }

        // Zone-colored radial glow — top-right corner
        let glowCenter = CGPoint(x: size.width * 0.88, y: size.height * 0.08)
        let glowRadius: CGFloat = 400
        let zoneUI = uiColor(from: dominantZone.color)
        let glowColors = [zoneUI.withAlphaComponent(0.10).cgColor, UIColor.clear.cgColor] as CFArray
        if let glowGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: glowColors, locations: [0, 1]) {
            ctx.drawRadialGradient(
                glowGrad,
                startCenter: glowCenter, startRadius: 0,
                endCenter: glowCenter, endRadius: glowRadius,
                options: []
            )
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Zone pill
    // ─────────────────────────────────────────────────────────────────────────

    static func drawZonePill(zone: PowerZone, at origin: CGPoint) {
        let color = uiColor(from: zone.color)
        let text = "Z\(zone.id)  \(zone.name.uppercased())"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 22, weight: .heavy),
            .foregroundColor: color,
            .kern: 2.0
        ]
        let textSize = text.size(withAttributes: attrs)
        let pH: CGFloat = 10, pV: CGFloat = 8
        let pillRect = CGRect(
            x: origin.x - pH,
            y: origin.y - pV,
            width: textSize.width + pH * 2,
            height: textSize.height + pV * 2
        )
        let path = UIBezierPath(roundedRect: pillRect, cornerRadius: pillRect.height / 2)
        color.withAlphaComponent(0.14).setFill()
        path.fill()
        color.withAlphaComponent(0.45).setStroke()
        path.lineWidth = 1.5
        path.stroke()
        text.draw(at: origin, withAttributes: attrs)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Hero stats row
    // ─────────────────────────────────────────────────────────────────────────

    static func drawHeroStats(duration: String, distKm: Double, kcal: Int, in rect: CGRect) {
        let col = rect.width / 3
        drawBigStatCell(
            value: duration,
            unit: "DURATION",
            color: .white,
            in: CGRect(x: rect.minX, y: rect.minY, width: col, height: rect.height)
        )
        drawBigStatCell(
            value: String(format: "%.2f", distKm),
            unit: "KM",
            color: UIColor(white: 1, alpha: 0.85),
            in: CGRect(x: rect.minX + col, y: rect.minY, width: col, height: rect.height)
        )
        drawBigStatCell(
            value: "\(kcal)",
            unit: "KCAL",
            color: UIColor(red: 1, green: 0.73, blue: 0.2, alpha: 1),
            in: CGRect(x: rect.minX + col * 2, y: rect.minY, width: col, height: rect.height)
        )
    }

    static func drawBigStatCell(value: String, unit: String, color: UIColor, in rect: CGRect) {
        let centerX = rect.midX

        let valAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 46, weight: .black),
            .foregroundColor: color
        ]
        let valSize = value.size(withAttributes: valAttrs)
        value.draw(at: CGPoint(x: centerX - valSize.width / 2, y: rect.minY + 6), withAttributes: valAttrs)

        let unitAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16, weight: .bold),
            .foregroundColor: UIColor(white: 1, alpha: 0.25),
            .kern: 2.0
        ]
        let unitSize = unit.size(withAttributes: unitAttrs)
        unit.draw(at: CGPoint(x: centerX - unitSize.width / 2, y: rect.minY + 58), withAttributes: unitAttrs)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Power sparkline
    // ─────────────────────────────────────────────────────────────────────────

    /// Draws a filled area power trace. Each segment is filled with the zone
    /// color corresponding to that power value, creating a natural zone-colored gradient effect.
    static func drawPowerSparkline(
        samples: [WorkoutSampleData],
        ftp: Int,
        in rect: CGRect,
        cgCtx: CGContext
    ) {
        guard samples.count >= 2 else { return }

        let powers = samples.map { $0.power }
        let maxPower = max(powers.max() ?? 1, 1)
        // Floor the chart at 0, soft ceiling at max(ftp*1.6, maxPower) so spikes don't dominate
        let chartMax = Double(max(Int(Double(ftp) * 1.6), maxPower))
        let chartMin: Double = 0

        let W = rect.width
        let H = rect.height
        let n = samples.count
        let baseY = rect.maxY

        // Down-sample to at most 1080 points for performance
        let stride = max(1, n / 1080)
        var downsampled: [(x: CGFloat, y: CGFloat, power: Int)] = []
        var i = 0
        while i < n {
            let s = samples[i]
            let fraction = CGFloat(i) / CGFloat(n - 1)
            let x = rect.minX + fraction * W
            let normalized = CGFloat((Double(s.power) - chartMin) / (chartMax - chartMin))
            let y = baseY - normalized * H
            downsampled.append((x, max(rect.minY, y), s.power))
            i += stride
        }
        // Always include the last point
        if let last = samples.last, downsampled.last.map({ $0.x }) != rect.maxX {
            let normalized = CGFloat((Double(last.power) - chartMin) / (chartMax - chartMin))
            let y = baseY - normalized * H
            downsampled.append((rect.maxX, max(rect.minY, y), last.power))
        }

        guard downsampled.count >= 2 else { return }

        // Draw each segment as a filled trapezoid colored by zone
        for segIdx in 0..<(downsampled.count - 1) {
            let p0 = downsampled[segIdx]
            let p1 = downsampled[segIdx + 1]

            let zone = PowerZone.zone(for: p0.power)
            let zoneColor = uiColor(from: zone.color)

            // Filled trapezoid to baseline
            let path = UIBezierPath()
            path.move(to: CGPoint(x: p0.x, y: baseY))
            path.addLine(to: CGPoint(x: p0.x, y: p0.y))
            path.addLine(to: CGPoint(x: p1.x, y: p1.y))
            path.addLine(to: CGPoint(x: p1.x, y: baseY))
            path.close()

            zoneColor.withAlphaComponent(0.55).setFill()
            path.fill()
        }

        // Draw the stroke on top (brighter, thin line)
        let strokePath = UIBezierPath()
        strokePath.move(to: CGPoint(x: downsampled[0].x, y: downsampled[0].y))
        for pt in downsampled.dropFirst() {
            strokePath.addLine(to: CGPoint(x: pt.x, y: pt.y))
        }
        UIColor(white: 1, alpha: 0.5).setStroke()
        strokePath.lineWidth = 1.5
        strokePath.lineCapStyle = .round
        strokePath.lineJoinStyle = .round
        strokePath.stroke()

        // FTP reference line — subtle dashed horizontal
        let ftpNorm = CGFloat((Double(ftp) - chartMin) / (chartMax - chartMin))
        let ftpY = baseY - ftpNorm * H
        if ftpY >= rect.minY && ftpY <= rect.maxY {
            cgCtx.saveGState()
            cgCtx.setStrokeColor(UIColor(white: 1, alpha: 0.20).cgColor)
            cgCtx.setLineWidth(1)
            cgCtx.setLineDash(phase: 0, lengths: [6, 6])
            cgCtx.move(to: CGPoint(x: rect.minX, y: ftpY))
            cgCtx.addLine(to: CGPoint(x: rect.maxX, y: ftpY))
            cgCtx.strokePath()
            cgCtx.restoreGState()

            // "FTP" label at far right of the dashed line
            let ftpLabel = "FTP \(ftp)W"
            let ftpAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: UIColor(white: 1, alpha: 0.30)
            ]
            ftpLabel.draw(at: CGPoint(x: rect.maxX - 90, y: ftpY - 22), withAttributes: ftpAttrs)
        }

        // Avg power reference line — slightly more visible, orange tint
        let avgPower = samples.reduce(0) { $0 + $1.power } / max(samples.count, 1)
        let avgNorm = CGFloat((Double(avgPower) - chartMin) / (chartMax - chartMin))
        let avgY = baseY - avgNorm * H
        if avgY >= rect.minY && avgY <= rect.maxY {
            cgCtx.saveGState()
            cgCtx.setStrokeColor(UIColor(red: 1, green: 0.73, blue: 0.2, alpha: 0.35).cgColor)
            cgCtx.setLineWidth(1)
            cgCtx.setLineDash(phase: 0, lengths: [4, 8])
            cgCtx.move(to: CGPoint(x: rect.minX, y: avgY))
            cgCtx.addLine(to: CGPoint(x: rect.maxX, y: avgY))
            cgCtx.strokePath()
            cgCtx.restoreGState()
        }
    }

    static func drawSparklineAxisLabels(
        samples: [WorkoutSampleData],
        avgPower: Double,
        in rect: CGRect
    ) {
        guard !samples.isEmpty else { return }
        let powers = samples.map { $0.power }
        let maxPwr = powers.max() ?? 0

        let dimAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .regular),
            .foregroundColor: UIColor(white: 1, alpha: 0.22)
        ]
        "0W".draw(at: CGPoint(x: rect.minX, y: rect.minY), withAttributes: dimAttrs)

        let maxStr = "\(maxPwr)W pk"
        let maxSize = maxStr.size(withAttributes: dimAttrs)
        maxStr.draw(at: CGPoint(x: rect.maxX - maxSize.width, y: rect.minY), withAttributes: dimAttrs)

        let avgStr = "avg \(Int(avgPower.rounded()))W"
        let centerX = rect.midX
        let avgSize = avgStr.size(withAttributes: dimAttrs)
        avgStr.draw(at: CGPoint(x: centerX - avgSize.width / 2, y: rect.minY), withAttributes: dimAttrs)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Performance stats row
    // ─────────────────────────────────────────────────────────────────────────

    static func drawPerformanceStats(workout: Workout, in rect: CGRect) {
        struct Stat { let label: String; let value: String; let color: UIColor }

        let avgZone  = PowerZone.zone(for: Int(workout.avgPower.rounded()))
        let avgColor = uiColor(from: avgZone.color)

        var stats: [Stat] = [
            Stat(label: "AVG W",  value: "\(Int(workout.avgPower.rounded()))",       color: avgColor),
            Stat(label: "MAX W",  value: "\(workout.maxPower)",                       color: UIColor(white: 1, alpha: 0.8)),
            Stat(label: "NP",     value: "\(Int(workout.normalizedPower.rounded()))", color: UIColor(red: 0.95, green: 0.77, blue: 0.3, alpha: 1)),
            Stat(label: "TSS",    value: "\(Int(workout.tss.rounded()))",             color: UIColor(white: 1, alpha: 0.7)),
            Stat(label: "IF",     value: String(format: "%.2f", workout.intensityFactor), color: UIColor(white: 1, alpha: 0.6)),
        ]
        if workout.avgCadence > 0 {
            stats.append(Stat(label: "RPM", value: "\(Int(workout.avgCadence.rounded()))", color: UIColor(red: 0.42, green: 0.76, blue: 0.63, alpha: 1)))
        }

        let n = CGFloat(stats.count)
        let colW = rect.width / n

        for (idx, stat) in stats.enumerated() {
            let colRect = CGRect(x: rect.minX + CGFloat(idx) * colW, y: rect.minY, width: colW, height: rect.height)
            drawCompactStatCell(stat.label, value: stat.value, color: stat.color, in: colRect)
        }
    }

    static func drawCompactStatCell(_ label: String, value: String, color: UIColor, in rect: CGRect) {
        let cx = rect.midX

        let valAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 30, weight: .heavy),
            .foregroundColor: color
        ]
        let valSize = value.size(withAttributes: valAttrs)
        value.draw(at: CGPoint(x: cx - valSize.width / 2, y: rect.minY + 6), withAttributes: valAttrs)

        let lblAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13, weight: .bold),
            .foregroundColor: UIColor(white: 1, alpha: 0.22),
            .kern: 1.5
        ]
        let lblSize = label.size(withAttributes: lblAttrs)
        label.draw(at: CGPoint(x: cx - lblSize.width / 2, y: rect.minY + 44), withAttributes: lblAttrs)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: MMP bar chart
    // ─────────────────────────────────────────────────────────────────────────

    /// Draws a horizontal bar chart of MMP results. PR durations get a gold
    /// highlight + crown glyph. Each bar is colored by its power zone.
    static func drawMMPChart(
        mmp: WorkoutMMP,
        newPRFlags: [NewPRFlag],
        dominantZone: PowerZone,
        in rect: CGRect,
        cgCtx: CGContext
    ) {
        let buckets = MMPDuration.allCases
        let results = buckets.compactMap { dur -> (duration: MMPDuration, watts: Int)? in
            guard let w = mmp.watts(for: dur), w > 0 else { return nil }
            return (dur, w)
        }
        guard !results.isEmpty else { return }

        let prSet = Set(newPRFlags.map { $0.duration })
        let maxWatts = results.map { $0.watts }.max() ?? 1

        let rowCount = CGFloat(results.count)
        let rowH = (rect.height / rowCount).rounded()
        let barMaxW = rect.width * 0.62  // leave room for labels
        let labelColX = rect.minX + barMaxW + 12

        for (idx, result) in results.enumerated() {
            let rowY = rect.minY + CGFloat(idx) * rowH
            let barFraction = CGFloat(result.watts) / CGFloat(maxWatts)
            let barW = max(4, barMaxW * barFraction)
            let barH = rowH - 8
            let barRect = CGRect(x: rect.minX, y: rowY + 4, width: barW, height: barH)

            let isPR = prSet.contains(result.duration)
            let zone = PowerZone.zone(for: result.watts)
            let barColor = isPR
                ? UIColor(red: 1.0, green: 0.80, blue: 0.15, alpha: 1)   // gold for PR
                : uiColor(from: zone.color)

            // Bar background track
            let trackRect = CGRect(x: rect.minX, y: rowY + 4, width: barMaxW, height: barH)
            let trackPath = UIBezierPath(roundedRect: trackRect, cornerRadius: barH / 2)
            barColor.withAlphaComponent(0.08).setFill()
            trackPath.fill()

            // Filled bar
            let barPath = UIBezierPath(roundedRect: barRect, cornerRadius: barH / 2)
            barColor.withAlphaComponent(isPR ? 0.90 : 0.65).setFill()
            barPath.fill()

            // Duration label (left of bar, inside)
            let durLabel = result.duration.label
            let durAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 14, weight: .bold),
                .foregroundColor: UIColor(white: 1, alpha: 0.45),
                .kern: 0.5
            ]
            let durLabelX = rect.minX + 8
            let durLabelY = rowY + (rowH - 18) / 2
            durLabel.draw(at: CGPoint(x: durLabelX, y: durLabelY), withAttributes: durAttrs)

            // Watts label (right of bar)
            let wStr = isPR ? "PR  \(result.watts)W" : "\(result.watts)W"
            let wAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: isPR ? 17 : 15, weight: isPR ? .heavy : .semibold),
                .foregroundColor: isPR
                    ? UIColor(red: 1.0, green: 0.80, blue: 0.15, alpha: 1)
                    : UIColor(white: 1, alpha: 0.55)
            ]
            wStr.draw(at: CGPoint(x: labelColX, y: rowY + (rowH - 20) / 2), withAttributes: wAttrs)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Zone distribution bar
    // ─────────────────────────────────────────────────────────────────────────

    static func drawZoneBar(
        in ctx: CGContext,
        buckets: [(zone: PowerZone, percent: Double)],
        rect: CGRect
    ) {
        guard !buckets.isEmpty else { return }
        let total = buckets.reduce(0.0) { $0 + $1.percent }
        guard total > 0 else { return }

        var xCursor = rect.minX
        let r = rect.height / 2

        // Clip to rounded rect
        ctx.saveGState()
        UIBezierPath(roundedRect: rect, cornerRadius: r).addClip()

        for (idx, bucket) in buckets.enumerated() {
            let fraction = CGFloat(bucket.percent / total)
            let segW = rect.width * fraction
            let segRect = CGRect(x: xCursor, y: rect.minY, width: segW, height: rect.height)
            let color = uiColor(from: bucket.zone.color)
            let alpha: CGFloat = bucket.percent >= 0.05 ? 0.82 : 0.30
            color.withAlphaComponent(alpha).setFill()
            UIRectFill(segRect)

            if idx < buckets.count - 1 {
                UIColor(white: 0, alpha: 0.35).setFill()
                UIRectFill(CGRect(x: xCursor + segW - 1, y: rect.minY, width: 2, height: rect.height))
            }
            xCursor += segW
        }
        ctx.restoreGState()
    }

    static func drawZoneBarLabels(
        buckets: [(zone: PowerZone, percent: Double)],
        rect: CGRect
    ) {
        let total = buckets.reduce(0.0) { $0 + $1.percent }
        guard total > 0 else { return }
        var xCursor = rect.minX

        for bucket in buckets {
            let fraction = CGFloat(bucket.percent / total)
            let segW = rect.width * fraction

            guard bucket.percent >= 0.07 else { xCursor += segW; continue }

            let label = "Z\(bucket.zone.id)"
            let color = uiColor(from: bucket.zone.color)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 15, weight: .bold),
                .foregroundColor: color.withAlphaComponent(0.8),
                .kern: 1.0
            ]
            let labelSize = label.size(withAttributes: attrs)
            label.draw(at: CGPoint(x: xCursor + (segW - labelSize.width) / 2, y: rect.minY), withAttributes: attrs)
            xCursor += segW
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Footer
    // ─────────────────────────────────────────────────────────────────────────

    static func drawFooter(
        workout: Workout,
        routeName: String?,
        totalElevationGain: Double,
        bottomY: CGFloat,
        leftPad: CGFloat,
        width: CGFloat
    ) {
        var parts: [String] = []

        if workout.avgHR > 0 {
            parts.append("\(Int(workout.avgHR.rounded())) / \(workout.maxHR) bpm")
        }
        if let r = routeName, !r.isEmpty {
            parts.append(r)
        }
        if totalElevationGain > 0 {
            parts.append("+\(Int(totalElevationGain.rounded())) m elev")
        }

        if !parts.isEmpty {
            let line = parts.joined(separator: "  ·  ")
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .medium),
                .foregroundColor: UIColor(white: 1, alpha: 0.40)
            ]
            line.draw(at: CGPoint(x: leftPad, y: bottomY - 86), withAttributes: attrs)
        }

        // Tagline
        let tagline = "Recorded with Mangox"
        let tagAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: UIColor(white: 1, alpha: 0.15)
        ]
        let tagSize = tagline.size(withAttributes: tagAttrs)
        tagline.draw(at: CGPoint(x: width / 2 - tagSize.width / 2, y: bottomY - 46), withAttributes: tagAttrs)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Shared Primitives
    // ─────────────────────────────────────────────────────────────────────────

    static func drawSectionLabel(_ text: String, at point: CGPoint) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13, weight: .heavy),
            .foregroundColor: UIColor(white: 1, alpha: 0.20),
            .kern: 2.5
        ]
        text.draw(at: point, withAttributes: attrs)
    }

    static func drawHorizontalGradientRect(in ctx: CGContext, rect: CGRect, color: UIColor) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let brighter = UIColor(hue: h, saturation: max(0, s - 0.1), brightness: min(1, b + 0.12), alpha: 1)
        let cgColors = [color.cgColor, brighter.cgColor] as CFArray
        if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: nil) {
            ctx.drawLinearGradient(
                grad,
                start: CGPoint(x: rect.minX, y: rect.midY),
                end: CGPoint(x: rect.maxX, y: rect.midY),
                options: []
            )
        }
    }

    static func drawText(
        _ text: String,
        at point: CGPoint,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment = .left,
        letterSpacing: CGFloat = 0,
        maxWidth: CGFloat = 800
    ) {
        let para = NSMutableParagraphStyle()
        para.alignment = alignment

        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: para
        ]
        if letterSpacing != 0 { attrs[.kern] = letterSpacing }

        if alignment == .left {
            text.draw(at: point, withAttributes: attrs)
        } else {
            let str = NSAttributedString(string: text, attributes: attrs)
            let bound = str.boundingRect(
                with: CGSize(width: maxWidth, height: 200),
                options: .usesLineFragmentOrigin,
                context: nil
            )
            let drawX: CGFloat = alignment == .right
                ? point.x - bound.width
                : point.x - bound.width / 2
            str.draw(in: CGRect(origin: CGPoint(x: drawX, y: point.y), size: bound.size))
        }
    }

    static func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: date)
    }

    static func uiColor(from swiftUIColor: Color) -> UIColor { UIColor(swiftUIColor) }
}
#endif

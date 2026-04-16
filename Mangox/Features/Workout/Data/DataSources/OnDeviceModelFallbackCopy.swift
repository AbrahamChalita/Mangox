// Features/Workout/Data/DataSources/OnDeviceModelFallbackCopy.swift
// Deterministic ride copy when Apple Intelligence / on-device writing models are unavailable.
import Foundation

enum OnDeviceModelFallbackCopy {

    /// Instagram-style caption (plain text + hashtags), max 280 characters, stats-grounded only.
    static func instagramStoryCaption(
        workout: Workout,
        dominantZoneName: String,
        routeName: String?,
        ftpWatts: Int,
        powerZoneLine: String
    ) -> String {
        let minDur = max(1, Int(workout.duration / 60))
        let avg = Int(workout.avgPower.rounded())
        let tss = Int(workout.tss.rounded())
        let trimmedRoute = routeName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var lead =
            "I logged \(minDur) min on the bike, averaging \(avg) W"
        if tss > 0 {
            lead += " and \(tss) TSS"
        }
        lead += "."

        if ftpWatts > 0, workout.avgPower > 0 {
            let pct = min(300, Int((workout.avgPower / Double(ftpWatts) * 100).rounded()))
            lead += " Roughly \(pct)% of \(ftpWatts) W FTP."
        }

        if !trimmedRoute.isEmpty {
            lead += " Route: \(trimmedRoute)."
        } else {
            lead += " Most time looked like \(dominantZoneName.lowercased()) work."
        }

        if workout.normalizedPower > 0, workout.avgPower > 0 {
            let np = Int(workout.normalizedPower.rounded())
            let ifStr = String(format: "%.2f", workout.intensityFactor)
            lead += " NP \(np) W, IF \(ifStr)."
        }

        let tail = "Zone mix: \(powerZoneLine). #cycling #indoorcycling"
        let spacer = " "
        let maxLead = max(24, 280 - tail.count - spacer.count)
        if lead.count > maxLead {
            lead = String(lead.prefix(max(1, maxLead - 1))).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }
        return lead + spacer + tail
    }

    /// Same shape as on-device ``WorkoutSummaryOnDeviceInsight``; built only from ride stats.
    static func rideSummaryInsight(
        workout: Workout,
        powerZoneLine: String,
        planLine: String?,
        ftpWatts: Int,
        riderCallName: String? = nil
    ) -> WorkoutSummaryOnDeviceInsight {
        let zone = PowerZone.zone(for: Int(workout.avgPower.rounded()))
        let dMin = max(1, Int(workout.duration / 60))
        let headline = StravaPostBuilder.buildTitle(
            workout: workout,
            routeName: workout.savedRouteName,
            dominantPowerZone: zone,
            personalRecordNames: []
        )

        var bullets: [String] = []
        bullets.append(clampBullet("\(dMin) min · \(Int(workout.tss.rounded())) TSS · \(Int(workout.avgPower.rounded())) W avg"))
        if workout.normalizedPower > 0 {
            bullets.append(
                clampBullet(
                    "NP \(Int(workout.normalizedPower.rounded())) W · IF \(String(format: "%.2f", workout.intensityFactor))"
                ))
        }
        bullets.append(clampBullet("Dominant intensity around \(zone.name) · \(powerZoneLine)"))
        if let planLine, !planLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            bullets.append(clampBullet("Plan: \(planLine)"))
        }

        let narrative = clampNarrative(
            narrativeFallbackParagraph(
                workout: workout,
                zone: zone,
                dMin: dMin,
                ftpWatts: ftpWatts,
                riderCallName: riderCallName
            ))

        return WorkoutSummaryOnDeviceInsight(
            headline: headline,
            bullets: Array(bullets.prefix(4)),
            caveat: nil,
            narrative: narrative
        )
    }

    /// Short list label when FM smart title is skipped.
    static func smartWorkoutTitle(workout: Workout, powerZoneLine: String, ftpWatts: Int) -> String {
        let zone = PowerZone.zone(for: Int(workout.avgPower.rounded()))
        return StravaPostBuilder.buildTitle(
            workout: workout,
            routeName: workout.savedRouteName,
            dominantPowerZone: zone,
            personalRecordNames: []
        )
    }

    // MARK: - Private

    private static func clampBullet(_ s: String, maxLen: Int = 100) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > maxLen else { return t }
        return String(t.prefix(maxLen - 1)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private static func clampNarrative(_ s: String, maxLen: Int = 300) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > maxLen else { return t }
        return String(t.prefix(maxLen - 1)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private static func narrativeFallbackParagraph(
        workout: Workout,
        zone: PowerZone,
        dMin: Int,
        ftpWatts: Int,
        riderCallName: String?
    ) -> String {
        let name = riderCallName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let subject = name.isEmpty ? "You" : name
        let tss = Int(workout.tss.rounded())
        let avg = Int(workout.avgPower.rounded())
        let ftp = max(ftpWatts, 1)
        return
            "\(subject) averaged \(avg) W over \(dMin) minutes with \(tss) TSS. The day centered on \(zone.name) — keep stacking quality work toward your \(ftp) W FTP."
    }
}

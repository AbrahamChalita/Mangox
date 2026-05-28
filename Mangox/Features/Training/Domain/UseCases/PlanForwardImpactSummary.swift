// Features/Training/Domain/UseCases/PlanForwardImpactSummary.swift
import Foundation

/// Computes a human-readable PMC impact line for plan save / review UI.
enum PlanForwardImpactSummary {
    @MainActor
    static func compute(
        plan: TrainingPlan,
        eventDateString: String?,
        ftp: Int = PowerZone.ftp
    ) -> String? {
        let horizon = horizonDays(plan: plan, eventDateString: eventDateString)
        guard horizon >= 7 else { return nil }

        let progress = PlanProgressFields(
            startDate: Calendar.current.startOfDay(for: .now),
            currentFTP: ftp
        )
        let vector = PlanTSSVectorBuilder.forwardDailyTSS(
            plan: plan,
            progress: progress,
            horizonDays: horizon
        )
        guard vector.contains(where: { $0 > 0 }) else { return nil }

        let ft = FitnessTracker.shared
        let ctl = ft.isLoaded ? ft.currentCTL : Double(ftp) * 0.85
        let atl = ft.isLoaded ? ft.currentATL : Double(ftp) * 0.70

        guard let result = PlanForwardSimulator.simulate(
            currentCTL: ctl,
            currentATL: atl,
            dailyTSS: vector
        ) else { return nil }

        var line = "Projected over \(horizon) days: \(result.plainLanguageSummary)"
        if result.deltaTSB > 8 {
            line += " Race-day form trend: improving."
        } else if result.deltaTSB < -12 {
            line += " Race-day form trend: likely fatigued — review taper."
        } else {
            line += " Race-day form trend: neutral."
        }
        return line
    }

    private static func horizonDays(plan: TrainingPlan, eventDateString: String?) -> Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)

        if let eventDateString,
           let eventDate = parseEventDate(eventDateString)
        {
            let eventDay = cal.startOfDay(for: eventDate)
            let days = cal.dateComponents([.day], from: today, to: eventDay).day ?? 0
            if days >= 7 { return min(120, days) }
        }

        let planDays = plan.allDays.count
        return min(84, max(14, planDays))
    }

    private static func parseEventDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        if let d = iso.date(from: trimmed) { return d }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        if let d = df.date(from: trimmed) { return d }

        df.dateStyle = .medium
        df.timeStyle = .none
        return df.date(from: trimmed)
    }
}

import Foundation

/// Builds a minimal iCalendar file from an active plan and its start date (workout / FTP days only).
enum PlanICSExport {
    static func buildICS(plan: TrainingPlan, progress: TrainingPlanProgress) -> String {
        var lines: [String] = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Mangox//Training Plan//EN",
            "CALSCALE:GREGORIAN",
        ]
        let stamp = icalUTC(Date())
        let cal = Calendar.current
        for day in plan.allDays
            where day.dayType == .workout || day.dayType == .ftpTest || day.dayType == .optionalWorkout
                || day.dayType == .commute
        {
            let date = progress.calendarDate(for: day)
            let dayStart = cal.startOfDay(for: date)
            let uid = "\(plan.id)-\(day.id)@mangox"
            lines.append("BEGIN:VEVENT")
            lines.append("UID:\(uid)")
            lines.append("DTSTAMP:\(stamp)")
            let startHour = PlanICSPreferences.defaultStartHour
            if day.durationMinutes > 0,
                let startDT = cal.date(
                    bySettingHour: startHour, minute: 0, second: 0, of: dayStart),
                let endDT = cal.date(byAdding: .minute, value: day.durationMinutes, to: startDT)
            {
                lines.append("DTSTART:\(icalLocalFloating(startDT))")
                lines.append("DTEND:\(icalLocalFloating(endDT))")
                if PlanICSPreferences.includeWorkoutReminder {
                    lines.append("BEGIN:VALARM")
                    lines.append("TRIGGER:-PT15M")
                    lines.append("ACTION:DISPLAY")
                    lines.append("DESCRIPTION:\(escapeText(day.title + " — Mangox"))")
                    lines.append("END:VALARM")
                }
            } else {
                lines.append("DTSTART;VALUE=DATE:\(icalDateOnly(dayStart))")
            }
            let summaryPrefix: String = {
                switch day.dayType {
                case .optionalWorkout: return "[Optional] "
                case .commute: return "[Commute] "
                default: return ""
                }
            }()
            lines.append("SUMMARY:\(escapeText(summaryPrefix + day.title))")

            var descriptionLines: [String] = []
            if day.dayType == .optionalWorkout {
                descriptionLines.append("Optional session — flexible if you are tired or short on time.")
            }
            if day.dayType == .commute {
                descriptionLines.append("Easy spinning or commute — keep intensity conversational.")
            }
            if !day.notes.isEmpty {
                descriptionLines.append(day.notes)
            }
            if !descriptionLines.isEmpty {
                lines.append("DESCRIPTION:\(escapeText(descriptionLines.joined(separator: "\n")))")
            }
            lines.append("END:VEVENT")
        }
        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\r\n")
    }

    static func writeTempICSFile(planName: String, icsBody: String) throws -> URL {
        let safe = planName.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .prefix(48)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Mangox-\(safe)-plan.ics")
        guard let data = icsBody.data(using: .utf8) else {
            throw URLError(.cannotCreateFile)
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func icalDateOnly(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMdd"
        return f.string(from: date)
    }

    private static func icalUTC(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.string(from: date)
    }

    /// Local floating time (no `Z`) — calendar apps treat as device-local.
    private static func icalLocalFloating(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = Calendar.current.timeZone
        f.dateFormat = "yyyyMMdd'T'HHmmss"
        return f.string(from: date)
    }

    private static func escapeText(_ s: String) -> String {
        s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
    }
}

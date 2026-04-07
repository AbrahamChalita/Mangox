import Foundation

/// Lightweight season / goal context (UserDefaults) for coach context and optional UI.
enum MangoxTrainingGoals {
    private static let eventNameKey = "mangox_goal_event_name"
    private static let eventDateKey = "mangox_goal_event_date"
    private static let phaseKey = "mangox_goal_phase_label"

    static var eventName: String {
        get { UserDefaults.standard.string(forKey: eventNameKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: eventNameKey) }
    }

    static var eventDate: Date? {
        get {
            let t = UserDefaults.standard.double(forKey: eventDateKey)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set {
            if let d = newValue {
                UserDefaults.standard.set(d.timeIntervalSince1970, forKey: eventDateKey)
            } else {
                UserDefaults.standard.removeObject(forKey: eventDateKey)
            }
        }
    }

    /// Short label shown in settings, e.g. Base, Build, Peak, Taper.
    static var phaseLabel: String {
        get { UserDefaults.standard.string(forKey: phaseKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: phaseKey) }
    }

    /// Single line for coach / analytics context; nil when empty.
    static var summaryLineForCoach: String? {
        let name = eventName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phase = phaseLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        if !name.isEmpty { parts.append("Goal event: \(name)") }
        if let d = eventDate {
            let f = DateFormatter()
            f.dateStyle = .medium
            parts.append("Event date: \(f.string(from: d))")
        }
        if !phase.isEmpty { parts.append("Training phase: \(phase)") }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }
}

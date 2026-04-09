// Features/Training/Data/DataSources/TrainingNotificationsScheduler.swift
import Foundation
import SwiftData
import UserNotifications

/// Local notification preferences and scheduling (evening “tomorrow’s session”, missed key nudge, FTP reminder).
enum TrainingNotificationsPreferences {
    private static let kTomorrow = "mangox_notif_tomorrow_preview"
    private static let kTomorrowHour = "mangox_notif_tomorrow_hour"
    private static let kMissedKey = "mangox_notif_missed_key"
    private static let kFtpDue = "mangox_notif_ftp_due"

    static var tomorrowSessionReminder: Bool {
        get { UserDefaults.standard.bool(forKey: kTomorrow) }
        set { UserDefaults.standard.set(newValue, forKey: kTomorrow) }
    }

    /// Local hour 0–23 for the evening reminder (default 20).
    static var tomorrowReminderHour: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: kTomorrowHour)
            return v > 0 ? min(23, v) : 20
        }
        set { UserDefaults.standard.set(min(23, max(0, newValue)), forKey: kTomorrowHour) }
    }

    static var missedKeyWorkoutNudge: Bool {
        get { UserDefaults.standard.bool(forKey: kMissedKey) }
        set { UserDefaults.standard.set(newValue, forKey: kMissedKey) }
    }

    static var ftpTestReminder: Bool {
        get { UserDefaults.standard.bool(forKey: kFtpDue) }
        set { UserDefaults.standard.set(newValue, forKey: kFtpDue) }
    }
}

enum TrainingNotificationsScheduler {
    private static let idTomorrow = "mangox.evening.tomorrow_session"
    private static let idFtp = "mangox.ftp.reminder"
    private static let missedPrefix = "mangox.missedkey."

    /// Removes pending local training reminders (not delivered notifications).
    @MainActor
    static func cancelPendingTrainingReminders() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [idTomorrow, idFtp])
    }

    /// Re-applies evening + FTP schedules after the user re-enables training notifications.
    @MainActor
    static func refreshDeferredSchedules(modelContext: ModelContext) {
        rescheduleEveningPreview(modelContext: modelContext)
        rescheduleFTPReminder()
    }

    @MainActor
    static func requestAuthorizationIfNeeded() {
        Task {
            let c = UNUserNotificationCenter.current()
            let settings = await c.notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            _ = try? await c.requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    /// Call when app moves to background to refresh the next evening preview.
    @MainActor
    static func rescheduleEveningPreview(modelContext: ModelContext) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [idTomorrow])

        guard MangoxFeatureFlags.allowsTrainingNotifications else { return }
        guard TrainingNotificationsPreferences.tomorrowSessionReminder else { return }

        let cal = Calendar.current
        let hour = TrainingNotificationsPreferences.tomorrowReminderHour
        var fire = cal.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        if fire <= Date() {
            fire = cal.date(byAdding: .day, value: 1, to: fire) ?? fire
        }

        let tomorrowStart = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: fire) ?? fire)

        let progressDescriptor = FetchDescriptor<TrainingPlanProgress>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let progresses = (try? modelContext.fetch(progressDescriptor)) ?? []
        guard let p = progresses.first,
            let plan = PlanLibrary.resolvePlan(planID: p.planID, modelContext: modelContext)
        else { return }

        let match = plan.allDays.first { d in
            cal.isDate(p.calendarDate(for: d), inSameDayAs: tomorrowStart)
                && (d.dayType == .workout || d.dayType == .ftpTest || d.dayType == .optionalWorkout
                    || d.dayType == .commute)
        }

        let body: String
        if let d = match {
            body = "\(d.title) · \(d.formattedDuration)"
        } else {
            body = "Recovery or rest — check your plan in Mangox."
        }

        var dc = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        dc.calendar = cal
        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)

        let content = UNMutableNotificationContent()
        content.title = "Tomorrow’s ride"
        content.body = body
        content.sound = .default
        content.interruptionLevel = .passive
        content.threadIdentifier = "mangox.training.preview"

        let req = UNNotificationRequest(identifier: idTomorrow, content: content, trigger: trigger)
        center.add(req)
    }

    /// When app becomes active: one-shot nudge if yesterday had a mandatory key workout that wasn’t completed.
    @MainActor
    static func evaluateMissedKeyIfNeeded(modelContext: ModelContext) {
        guard MangoxFeatureFlags.allowsTrainingNotifications else { return }
        guard TrainingNotificationsPreferences.missedKeyWorkoutNudge else { return }

        let cal = Calendar.current
        let yesterday = cal.startOfDay(for: cal.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        let yKey = cal.dateComponents([.year, .month, .day], from: yesterday)
        let stamp =
            "\(yKey.year ?? 0)-\(yKey.month ?? 0)-\(yKey.day ?? 0)"
        let udKey = "mangox.missedKey.sent.\(stamp)"
        guard !UserDefaults.standard.bool(forKey: udKey) else { return }

        let progressDescriptor = FetchDescriptor<TrainingPlanProgress>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let progresses = (try? modelContext.fetch(progressDescriptor)) ?? []
        guard !progresses.isEmpty else { return }

        var missedTitles: [String] = []
        for p in progresses {
            guard let plan = PlanLibrary.resolvePlan(planID: p.planID, modelContext: modelContext) else {
                continue
            }
            for day in plan.allDays {
                guard day.isKeyWorkout, day.dayType != .optionalWorkout else { continue }
                guard cal.isDate(p.calendarDate(for: day), inSameDayAs: yesterday) else { continue }
                guard day.dayType == .workout || day.dayType == .ftpTest || day.dayType == .commute else {
                    continue
                }
                if !p.isCompleted(day.id) && !p.isSkipped(day.id) {
                    missedTitles.append(day.title)
                }
            }
        }

        guard !missedTitles.isEmpty else { return }

        UserDefaults.standard.set(true, forKey: udKey)

        let uniqueTitles = Array(Set(missedTitles)).sorted()
        let preview = uniqueTitles.prefix(3).joined(separator: ", ")
        let body: String
        if uniqueTitles.count == 1 {
            body =
                "“\(uniqueTitles[0])” wasn’t logged in Mangox. Adjust your plan or ride when you can."
        } else {
            body =
                "Missed priority sessions: \(preview)\(uniqueTitles.count > 3 ? "…" : ""). Open Mangox to update your plan."
        }

        let content = UNMutableNotificationContent()
        content.title = "Key workout missed"
        content.body = body
        content.sound = .default
        content.interruptionLevel = .active
        content.threadIdentifier = "mangox.training.missedkey"

        let trig = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let req = UNNotificationRequest(
            identifier: missedPrefix + stamp, content: content, trigger: trig)
        UNUserNotificationCenter.current().add(req)
    }

    /// Schedule a gentle FTP nudge if no test recorded in ~90 days.
    @MainActor
    static func rescheduleFTPReminder() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [idFtp])

        guard MangoxFeatureFlags.allowsTrainingNotifications else { return }
        guard TrainingNotificationsPreferences.ftpTestReminder else { return }

        let last = FTPTestHistory.load().map { $0.date }.max()
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        if let last, last > cutoff { return }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 86400 * 2, repeats: false)
        let content = UNMutableNotificationContent()
        content.title = "FTP check-in"
        content.body = "It’s been a while since an FTP test. Fresh numbers keep zones and TSS accurate."
        content.sound = .default
        content.interruptionLevel = .passive
        content.threadIdentifier = "mangox.training.ftp"
        let req = UNNotificationRequest(identifier: idFtp, content: content, trigger: trigger)
        center.add(req)
    }
}

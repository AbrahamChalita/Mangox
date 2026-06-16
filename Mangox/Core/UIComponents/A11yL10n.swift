import Foundation

/// Centralized accessibility strings used throughout the app.
/// Keys follow the pattern `feature.subcomponent.key_name` in Localizable.strings.
enum A11yL10n {

    // MARK: - Coach

    static var closeChat: String { String(localized: "coach.a11y.close_chat") }
    static var conversations: String { String(localized: "coach.a11y.conversations") }
    static var planBuilder: String { String(localized: "coach.a11y.plan_builder") }
    static var newConversation: String { String(localized: "coach.a11y.new_conversation") }
    static var dismissError: String { String(localized: "coach.a11y.dismiss_error") }
    static var scrollToLatest: String { String(localized: "coach.a11y.scroll_to_latest") }
    static var dismissLimitNotice: String { String(localized: "coach.a11y.dismiss_limit_notice") }
    static var deleteWorkout: String { String(localized: "coach.a11y.delete_workout") }
    static func errorFormat(_ message: String) -> String {
        String(format: String(localized: "coach.a11y.error_format"), message)
    }
    static func warningFormat(_ message: String) -> String {
        String(format: String(localized: "a11y.warning_format"), message)
    }
    static func infoFormat(_ message: String) -> String {
        String(format: String(localized: "a11y.info_format"), message)
    }
    static var opensSubscriptionHint: String { String(localized: "coach.a11y.opens_subscription_hint") }
    static var messageInput: String { String(localized: "coach.a11y.message_input") }
    static var yourMessage: String { String(localized: "coach.a11y.your_message") }
    static var onDeviceAnswer: String { String(localized: "coach.a11y.on_device_answer") }
    static var webSourcesAnswer: String { String(localized: "coach.a11y.web_sources_answer") }
    static var coach: String { String(localized: "coach.a11y.coach") }
    static func coachReplyFormat(_ category: String, _ delivery: String) -> String {
        String(format: String(localized: "coach.a11y.coach_reply_format"), category, delivery)
    }
    static func coachStatusFormat(_ text: String) -> String {
        String(format: String(localized: "coach.a11y.coach_status_format"), text)
    }
    static func questionFormat(_ step: Int, _ total: Int) -> String {
        String(format: String(localized: "coach.a11y.question_format"), step, total)
    }
    static var coachTyping: String { String(localized: "coach.a11y.coach_typing") }
    static func confirmPlanGeneration(_ eventName: String) -> String {
        String(format: String(localized: "coach.a11y.confirm_plan_generation"), eventName)
    }
    static var chatWithCoach: String { String(localized: "coach.a11y.chat_with_coach") }
    static var opensFullScreenCoachHint: String { String(localized: "coach.a11y.opens_full_screen_coach_hint") }

    // MARK: - Dashboard (Indoor)

    static var distance: String { String(localized: "dashboard.a11y.distance") }
    static func distanceValueFormat(_ value: String, _ unit: String) -> String {
        String(format: String(localized: "dashboard.a11y.distance_value_format"), value, unit)
    }
    static func heartRateZone(_ badgeText: String) -> String {
        String(format: String(localized: "dashboard.a11y.heart_rate_zone"), badgeText)
    }
    static var dismissTip: String { String(localized: "dashboard.a11y.dismiss_tip") }

    // MARK: - Social (Instagram / Day Summary)

    static var accentColor: String { String(localized: "social.a11y.accent_color") }
    static var removeBackgroundPhoto: String { String(localized: "social.a11y.remove_background_photo") }
    static var regenerateStoryTitle: String { String(localized: "social.a11y.regenerate_story_title") }
    static var mangoxBrandBadge: String { String(localized: "social.a11y.mangox_brand_badge") }
    static var cycleBackgroundColor: String { String(localized: "social.a11y.cycle_background_color") }
    static var brandBadge: String { String(localized: "social.a11y.brand_badge") }

    // MARK: - PM Chart

    static var chartOptions: String { String(localized: "pmchart.a11y.chart_options") }
    static func dayRangeFormat(_ days: Int) -> String {
        String(format: String(localized: "pmchart.a11y.day_range_format"), days)
    }

    // MARK: - Home

    static func nextWorkoutFormat(_ title: String) -> String {
        String(format: String(localized: "home.a11y.next_workout_format"), title)
    }
    static func metricDetailFormat(_ label: String, _ value: String, _ detail: String) -> String {
        String(format: String(localized: "home.a11y.metric_detail_format"), label, value, detail)
    }
    static var recalibrateFTP: String { String(localized: "home.a11y.recalibrate_ftp") }
    static var setFTP: String { String(localized: "home.a11y.set_ftp") }
    static var ftpTestHint: String { String(localized: "home.a11y.ftp_test_hint") }
    static var seeAllWorkouts: String { String(localized: "home.a11y.see_all_workouts") }
    static var noRidesYet: String { String(localized: "home.a11y.no_rides_yet") }

    // MARK: - Summary / Workout

    static var summaryActions: String { String(localized: "workout.a11y.summary_actions") }
    static var resetDescriptionTemplate: String { String(localized: "workout.a11y.reset_description_template") }
    static var activityDescription: String { String(localized: "workout.a11y.activity_description") }
    static var activityDescriptionHint: String { String(localized: "workout.a11y.activity_description_hint") }
    static var activityTitle: String { String(localized: "workout.a11y.activity_title") }
    static var includeDurationHint: String { String(localized: "workout.a11y.include_duration_hint") }
    static func metricStatFormat(_ label: String, _ value: String, _ unit: String) -> String {
        String(format: String(localized: "workout.a11y.metric_stat_format"), label, value, unit)
    }
    static func lapCurrentFormat(_ lap: Int, _ watts: Int, _ duration: String) -> String {
        String(format: String(localized: "workout.a11y.lap_current_format"), lap, watts, duration)
    }
    static func lapWithPreviousFormat(
        _ lap: Int,
        _ currentWatts: Int,
        _ currentDuration: String,
        _ previousWatts: Int,
        _ previousDuration: String
    ) -> String {
        String(
            format: String(localized: "workout.a11y.lap_with_previous_format"),
            lap,
            currentWatts,
            currentDuration,
            previousWatts,
            previousDuration
        )
    }

    // MARK: - Training / Calendar

    static var shareAllWorkouts: String { String(localized: "training.a11y.share_all_workouts") }
    static func otherActivitiesFormat(_ count: Int) -> String {
        String(format: String(localized: "training.a11y.other_activities_format"), count)
    }
    static func otherActivitiesForDayFormat(_ count: Int, _ date: String) -> String {
        String(format: String(localized: "training.a11y.other_activities_for_day_format"), count, date)
    }
    static var viewLayout: String { String(localized: "training.a11y.view_layout") }
    static var switchWorkoutViewHint: String { String(localized: "training.a11y.switch_workout_view_hint") }
    static func filterFormat(_ title: String, _ count: Int) -> String {
        String(format: String(localized: "training.a11y.filter_format"), title, count)
    }
    static var importWorkoutFile: String { String(localized: "training.a11y.import_workout_file") }
    static var ftpTestHistory: String { String(localized: "training.a11y.ftp_test_history") }
    static var close: String { String(localized: "training.a11y.close") }
    static var startFTPTestProtocol: String { String(localized: "training.a11y.start_ftp_test_protocol") }
    static func applyEstimatedFTPFormat(_ watts: Int) -> String {
        String(format: String(localized: "training.a11y.apply_estimated_ftp_format"), watts)
    }

    // MARK: - Profile / Settings

    static var maxHeartRate: String { String(localized: "profile.a11y.max_heart_rate") }
    static var restingHeartRate: String { String(localized: "profile.a11y.resting_heart_rate") }
    static var outdoorBikeLabel: String { String(localized: "profile.a11y.outdoor_bike_label") }
    static var indoorTrainerLabel: String { String(localized: "profile.a11y.indoor_trainer_label") }
    static func opensSettingsHint(_ title: String) -> String {
        String(format: String(localized: "profile.a11y.opens_settings_hint"), title)
    }
    static var saveHealthData: String { String(localized: "profile.a11y.save_health_data") }
    static var editHealthData: String { String(localized: "profile.a11y.edit_health_data") }
    static var ftpValue: String { String(localized: "profile.a11y.ftp_value") }
    static func ftpValueFormat(_ watts: Int) -> String {
        String(format: String(localized: "profile.a11y.ftp_value_format"), watts)
    }
    static func applyFTPFormat(_ watts: Int) -> String {
        String(format: String(localized: "profile.a11y.apply_ftp_format"), watts)
    }
    static var takeFTPTest: String { String(localized: "profile.a11y.take_ftp_test") }
    static var manualMaxHeartRate: String { String(localized: "profile.a11y.manual_max_heart_rate") }
    static var manualRestingHeartRate: String { String(localized: "profile.a11y.manual_resting_heart_rate") }
    static var applyHeartRateOverrides: String { String(localized: "profile.a11y.apply_heart_rate_overrides") }
    static func metricSourceFormat(_ label: String, _ value: String, _ unit: String, _ source: String) -> String {
        String(format: String(localized: "profile.a11y.metric_source_format"), label, value, unit, source)
    }

    // MARK: - Outdoor Dashboard

    static var endRide: String { String(localized: "outdoor.a11y.end_ride") }
    static var showMap: String { String(localized: "outdoor.a11y.show_map") }
    static var route: String { String(localized: "outdoor.a11y.route") }
    static var centerOnLocation: String { String(localized: "outdoor.a11y.center_on_location") }
    static var dropWaypoint: String { String(localized: "outdoor.a11y.drop_waypoint") }
    static var clearWaypoints: String { String(localized: "outdoor.a11y.clear_waypoints") }
    static var discardRide: String { String(localized: "outdoor.a11y.discard_ride") }
    static var weakGPS: String { String(localized: "outdoor.a11y.weak_gps") }

    // MARK: - Onboarding

    static func pageFormat(_ current: Int, _ total: Int) -> String {
        String(format: String(localized: "onboarding.a11y.page_format"), current, total)
    }
    static var weight: String { String(localized: "onboarding.a11y.weight") }
    static func weightValueFormat(_ value: Int, _ unit: String) -> String {
        String(format: String(localized: "onboarding.a11y.weight_value_format"), value, unit)
    }
    static var displayName: String { String(localized: "onboarding.a11y.display_name") }

    // MARK: - Indoor Connection

    static func connectionStatusFormat(_ category: String, _ title: String) -> String {
        String(format: String(localized: "indoor.a11y.connection_status_format"), category, title)
    }
    static func wifiConnectedFormat(_ name: String) -> String {
        String(format: String(localized: "indoor.a11y.wifi_connected_format"), name)
    }
    static func wifiConnectedValueFormat(_ ip: String, _ port: Int) -> String {
        String(format: String(localized: "indoor.a11y.wifi_connected_value_format"), ip, port)
    }
    static func wifiConnectingFormat(_ name: String) -> String {
        String(format: String(localized: "indoor.a11y.wifi_connecting_format"), name)
    }
    static func connectTrainerFormat(_ name: String) -> String {
        String(format: String(localized: "indoor.a11y.connect_trainer_format"), name)
    }
    static func connectTrainerValueFormat(_ ip: String, _ port: Int) -> String {
        String(format: String(localized: "indoor.a11y.connect_trainer_value_format"), ip, port)
    }
    static func bleDeviceFormat(_ name: String, _ type: String) -> String {
        String(format: String(localized: "indoor.a11y.ble_device_format"), name, type)
    }
    static func signalFormat(_ bars: Int) -> String {
        String(format: String(localized: "indoor.a11y.signal_format"), bars)
    }

    // MARK: - Metric Card

    static func metricValueFormat(_ value: String, _ unit: String) -> String {
        String(format: String(localized: "metric_card.a11y.value_format"), value, unit)
    }

    // MARK: - Power Graph

    static func powerGraphCombinedFormat(_ title: String, _ timeframe: String) -> String {
        String(format: String(localized: "power_graph.a11y.combined_format"), title, timeframe)
    }

    // MARK: - Activity Log

    static func activityHeaderFormat(_ name: String, _ date: String, _ source: String) -> String {
        String(format: String(localized: "activity_log.a11y.header_format"), name, date, source)
    }
    static func statFormat(_ label: String, _ value: String) -> String {
        String(format: String(localized: "activity_log.a11y.stat_format"), label, value)
    }
    static func notesFormat(_ notes: String) -> String {
        String(format: String(localized: "activity_log.a11y.notes_format"), notes)
    }
    static func viewOnSourceFormat(_ source: String) -> String {
        String(format: String(localized: "activity_log.a11y.view_on_source_format"), source)
    }
    static var editActivity: String { String(localized: "activity_log.a11y.edit_activity") }
    static var deleteActivity: String { String(localized: "activity_log.a11y.delete_activity") }
    static var deleteActivityHint: String { String(localized: "activity_log.a11y.delete_activity_hint") }

    // MARK: - Ride FAB

    static var startRide: String { String(localized: "ride_fab.a11y.start_ride") }
    static var closeRideOptions: String { String(localized: "ride_fab.a11y.close_ride_options") }

    // MARK: - Mangox Brand

    static var mangox: String { String(localized: "brand.a11y.mangox") }
}

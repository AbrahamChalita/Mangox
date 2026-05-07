// Features/Onboarding/Presentation/ViewModel/OnboardingViewModel.swift
import CoreBluetooth
import CoreLocation
import Foundation
import UserNotifications

@MainActor
@Observable
final class OnboardingViewModel {
    // MARK: - Dependencies
    private let healthKitService: HealthKitServiceProtocol
    private let locationService: LocationServiceProtocol
    private let stravaService: StravaServiceProtocol

    // MARK: - View state
    var currentStep: Int = 0
    var isComplete: Bool = false
    var blePermissionGranted = false
    var healthKitGranted = false
    var locationGranted = false
    var notificationsGranted = false
    var stravaStatus: String?
    var welcomeAppeared = false
    var finishCelebration = false
    var actionInProgress = false
    var onboardingWeightKg: Double = RidePreferences.shared.riderWeightKg
    var onboardingBirthYear: Int = OnboardingViewModel.initialBirthYear()
    var onboardingRiderDisplayName: String = RidePreferences.shared.riderDisplayName

    /// BLE trigger retained so CBCentralManager stays alive during permission polling.
    var bleTrigger: CBCentralManager?

    private let totalPages = 9

    var isPermissionPage: Bool {
        switch currentStep {
        case 1, 2, 4: true
        default: false
        }
    }

    var stravaConnected: Bool { stravaService.isConnected }
    var stravaConfigured: Bool { stravaService.isConfigured }
    var stravaBusy: Bool { stravaService.isBusy }

    init(
        healthKitService: HealthKitServiceProtocol,
        locationService: LocationServiceProtocol,
        stravaService: StravaServiceProtocol
    ) {
        self.healthKitService = healthKitService
        self.locationService = locationService
        self.stravaService = stravaService
    }

    private static func initialBirthYear() -> Int {
        let currentYear = Calendar.current.component(.year, from: .now)
        let maxYear = currentYear - 16
        let year = RidePreferences.shared.riderBirthYear ?? (currentYear - 30)
        return min(max(year, 1940), maxYear)
    }

    // MARK: - Button title

    func buttonTitle() -> String {
        switch currentStep {
        case 0: return "Continue"
        case 1: return blePermissionGranted ? "Continue" : "Enable Bluetooth"
        case 2: return healthKitGranted ? "Continue" : "Enable Health"
        case 3: return "Continue"
        case 4: return locationGranted ? "Continue" : "Enable Location"
        case 5:
            if stravaBusy { return "Connecting..." }
            if stravaConnected { return "Continue" }
            return stravaConfigured ? "Connect Strava" : "Continue"
        case 6: return "Continue"
        case 7: return "Continue"   // Cloud (optional)
        case 8: return "Get Started"
        default: return "Continue"
        }
    }

    // MARK: - Navigation

    func advance() {
        if currentStep < totalPages - 1 {
            currentStep += 1
        }
    }

    func complete() {
        isComplete = true
    }

    func syncWelcomeAppearance(reduceMotion: Bool) {
        if reduceMotion {
            welcomeAppeared = true
        } else if currentStep == 0 {
            welcomeAppeared = false
        }
    }

    func triggerFinishCelebrationIfNeeded(reduceMotion: Bool) {
        if reduceMotion {
            finishCelebration = true
        } else {
            finishCelebration = false
        }
    }

    // MARK: - Initial permission sync

    func syncInitialPermissionState() async {
        locationService.setup()
        blePermissionGranted = CBManager.authorization == .allowedAlways
        healthKitGranted = healthKitService.isAuthorized
        locationGranted = locationService.isAuthorized
        notificationsGranted = await Self.notificationPermissionGranted()
        if stravaService.isConnected {
            stravaStatus = "Connected as \(stravaService.athleteDisplayName ?? "Strava athlete")."
        }
    }

    // MARK: - Permission requests

    func requestBluetooth() {
        actionInProgress = true
        bleTrigger = CBCentralManager(delegate: nil, queue: nil)
        Task {
            for _ in 0..<30 {
                try? await Task.sleep(for: .milliseconds(250))
                let granted = CBManager.authorization == .allowedAlways
                await MainActor.run { blePermissionGranted = granted }
                if CBManager.authorization != .notDetermined { break }
            }
            await MainActor.run {
                actionInProgress = false
                advance()
            }
        }
    }

    func requestHealthKit() async {
        actionInProgress = true
        await healthKitService.requestAuthorization()
        healthKitGranted = healthKitService.isAuthorized
        actionInProgress = false
    }

    func requestLocation() {
        actionInProgress = true
        locationService.requestPermission()
        Task {
            for _ in 0..<40 {
                try? await Task.sleep(for: .milliseconds(250))
                if locationService.authorizationStatus != .notDetermined { break }
            }
            await MainActor.run {
                locationGranted = locationService.isAuthorized
                actionInProgress = false
            }
        }
    }

    func connectStrava() async {
        actionInProgress = true
        defer { actionInProgress = false }
        do {
            try await stravaService.connect()
            stravaStatus = "Connected as \(stravaService.athleteDisplayName ?? "Strava athlete")."
            HapticManager.shared.onboardingCelebration()
        } catch {
            stravaStatus = error.localizedDescription
        }
    }

    /// When opening the rider profile step, pre-fill the name from Strava if the field is still empty.
    func prepareRiderProfileStep() {
        let trimmed = onboardingRiderDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else { return }
        if stravaConnected,
           let n = stravaService.athleteDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !n.isEmpty {
            onboardingRiderDisplayName = String(n.prefix(50))
        }
    }

    /// Check OS notification permission.
    private static func notificationPermissionGranted() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    // MARK: - Onboarding completion

    func markOnboardingComplete() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
    }

    // MARK: - Action handler

    func handleAction(reduceMotion: Bool) {
        guard !actionInProgress else { return }

        switch currentStep {
        case 1:
            if !blePermissionGranted {
                requestBluetooth()
            } else {
                advance()
            }
        case 2:
            if !healthKitGranted {
                Task {
                    await requestHealthKit()
                    advance()
                }
            } else {
                advance()
            }
        case 3:
            advance()
        case 4:
            if !locationGranted {
                requestLocation()
            } else {
                advance()
            }
        case 5:
            if stravaConnected || !stravaConfigured {
                advance()
            } else {
                Task { await connectStrava(); advance() }
            }
        case 6:
            let prefs = RidePreferences.shared
            prefs.riderWeightKg = onboardingWeightKg
            prefs.riderBirthYear = onboardingBirthYear
            prefs.riderDisplayName = onboardingRiderDisplayName
            advance()
        case 7:
            // Cloud step is purely informational + optional sign-in. Continue advances.
            advance()
        case 8:
            HapticManager.shared.onboardingCelebration()
            markOnboardingComplete()
        default:
            advance()
        }
    }
}

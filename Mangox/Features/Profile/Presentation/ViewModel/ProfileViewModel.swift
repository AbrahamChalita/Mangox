// Features/Profile/Presentation/ViewModel/ProfileViewModel.swift
import Foundation

@MainActor
@Observable
final class ProfileViewModel {
    // MARK: - Dependencies
    private let whoopService: WhoopServiceProtocol
    private let purchasesService: PurchasesServiceProtocol
    private let stravaService: StravaServiceProtocol
    private let ftpRefreshTrigger: FTPRefreshTrigger
    private let healthKitService: HealthKitServiceProtocol

    // MARK: - Whoop state
    var whoopConnected: Bool { whoopService.isConnected }
    var whoopDisplayName: String? { whoopService.memberDisplayName }
    var recoveryScore: Double? { whoopService.latestRecoveryScore }
    var recoveryHRV: Int? { whoopService.latestRecoveryHRV }
    var isBusy: Bool { whoopService.isBusy }
    var lastError: String? { whoopService.lastError }
    var readinessHint: String { whoopService.readinessTrainingHint }
    var whoopIsConfigured: Bool { whoopService.isConfigured }
    var whoopIsBusy: Bool { whoopService.isBusy }
    var whoopLastError: String? { whoopService.lastError }
    var whoopLatestRecoveryRestingHR: Int? { whoopService.latestRecoveryRestingHR }
    var whoopLatestRecoveryHRV: Int? { whoopService.latestRecoveryHRV }
    var whoopLatestMaxHeartRateFromProfile: Int? { whoopService.latestMaxHeartRateFromProfile }
    var whoopSyncHeartBaselinesFromWhoop: Bool {
        get { whoopService.syncHeartBaselinesFromWhoop }
        set { whoopService.syncHeartBaselinesFromWhoop = newValue }
    }

    // MARK: - Strava state
    var stravaConnected: Bool { stravaService.isConnected }
    var stravaDisplayName: String? { stravaService.athleteDisplayName }
    var stravaAvatarURL: URL? { stravaService.athleteProfileImageURL }
    var stravaIsConfigured: Bool { stravaService.isConfigured }
    var stravaIsBusy: Bool { stravaService.isBusy }
    var stravaLastError: String? { stravaService.lastError }

    // MARK: - HealthKit state
    var healthKitIsAuthorized: Bool { healthKitService.isAuthorized }
    var healthKitRestingHeartRate: Int? { healthKitService.restingHeartRate }
    var healthKitMaxHeartRate: Int? { healthKitService.maxHeartRate }
    var healthKitEffectiveMaxHR: Int { healthKitService.effectiveMaxHR }
    var healthKitVo2Max: Double? { healthKitService.vo2Max }
    var healthKitSyncWorkoutsToAppleHealth: Bool {
        get { healthKitService.syncWorkoutsToAppleHealth }
        set { healthKitService.syncWorkoutsToAppleHealth = newValue }
    }

    var identityTitle: String {
        if stravaService.isConnected,
           let name = stravaService.athleteDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        return "Mangox"
    }

    // MARK: - FTP state
    var ftp: Int { PowerZone.ftp }
    var ftpGeneration: UInt64 { ftpRefreshTrigger.generation }

    // MARK: - Purchase / Pro state
    var isPro: Bool { purchasesService.isPro }
    var isProDevUnlockOnly: Bool { purchasesService.isProDevUnlockOnly }
    var hasStoreSubscription: Bool { purchasesService.hasStoreSubscription }
    var storeProPlanKind: String? { purchasesService.storeProPlanKind }
    var storeProRenewalDescription: String? { purchasesService.storeProRenewalDescription }
    var subscriptionManagementURL: URL? { purchasesService.subscriptionManagementURL }
    var showPaywall = false

    // MARK: - Init
    init(
        whoopService: WhoopServiceProtocol,
        purchasesService: PurchasesServiceProtocol,
        stravaService: StravaServiceProtocol,
        ftpRefreshTrigger: FTPRefreshTrigger,
        healthKitService: HealthKitServiceProtocol
    ) {
        self.whoopService = whoopService
        self.purchasesService = purchasesService
        self.stravaService = stravaService
        self.ftpRefreshTrigger = ftpRefreshTrigger
        self.healthKitService = healthKitService
    }

    // MARK: - Whoop actions
    func connectWhoop() async {
        try? await whoopService.connect()
    }

    func disconnectWhoop() async {
        await whoopService.disconnect()
    }

    func refreshWhoop() async {
        try? await whoopService.refreshLinkedData()
    }

    func applyHeartBaselinesFromLatestWhoopData() {
        whoopService.applyHeartBaselinesFromLatestWhoopData()
    }

    // MARK: - Strava actions
    func connectStrava() async throws {
        try await stravaService.connect()
    }

    func disconnectStrava() {
        stravaService.disconnect()
    }

    // MARK: - HealthKit actions
    func requestHealthKitAuthorization() async {
        await healthKitService.requestAuthorization()
    }

    func syncHealthKitToZones() {
        if whoopService.syncHeartBaselinesFromWhoop && whoopService.isConnected {
            whoopService.applyHeartBaselinesFromLatestWhoopData()
            return
        }
        let effectiveMax = healthKitService.effectiveMaxHR
        if effectiveMax > 0, !HeartRateZone.hasManualMaxHROverride {
            HeartRateZone.maxHR = effectiveMax
        }
        if let resting = healthKitService.restingHeartRate, resting > 0,
            !HeartRateZone.hasManualRestingHROverride
        {
            HeartRateZone.restingHR = resting
        }
    }

    // MARK: - Paywall / Purchases actions
    func syncPurchases() async {
        await purchasesService.sync()
    }

    func presentPaywall() {
        showPaywall = true
    }

    func dismissPaywall() {
        showPaywall = false
    }

    func makePaywallViewModel() -> PaywallViewModel {
        PaywallViewModel(purchasesService: purchasesService)
    }

    // MARK: - Onboarding reset
    func resetOnboarding() {
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
    }
}

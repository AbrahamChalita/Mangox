// Features/Fitness/Data/DataSources/HealthKitManager.swift
import Foundation
import HealthKit
import os.log

private let logger = Logger(subsystem: "com.abchalita.Mangox", category: "HealthKitManager")

/// Centralized service for reading health data from HealthKit.
/// Provides resting HR, max HR, date of birth, and VO2 Max for accurate heart rate zone calculation.
///
/// Gracefully degrades when the HealthKit entitlement is missing (e.g. personal dev team):
/// - Authorization is attempted **once** per app launch.
/// - If it fails with a missing-entitlement error, no further attempts are made.
/// - Cached values from UserDefaults are used as fallback.
@MainActor @Observable
final class HealthKitManager: HealthKitServiceProtocol {

    // MARK: - Published State

    var isAuthorized: Bool = false
    var restingHeartRate: Int? = nil          // bpm
    var maxHeartRate: Int? = nil              // bpm — from workouts or age-estimated
    var dateOfBirth: DateComponents? = nil
    var vo2Max: Double? = nil                 // mL/kg/min
    var lastError: String? = nil

    /// Last failure when saving a completed ride to Health (separate from general `lastError`).
    /// Cleared on a successful save attempt.
    var workoutSyncToHealthLastError: String? = nil

    /// When enabled, completed rides are written to Apple Health (Fitness rings). Opt-in in Settings.
    var syncWorkoutsToAppleHealth: Bool {
        get { UserDefaults.standard.bool(forKey: Self.syncWorkoutsToHealthKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.syncWorkoutsToHealthKey) }
    }

    /// Computed max HR: prefer measured from workouts, fall back to age-estimated (220 - age).
    var effectiveMaxHR: Int {
        if let maxHeartRate, maxHeartRate > 0 {
            return maxHeartRate
        }
        if let age = currentAge, age > 0 {
            return max(220 - age, 100)
        }
        return 185 // safe default
    }

    /// Current age derived from date of birth.
    var currentAge: Int? {
        guard let dob = dateOfBirth,
              let birthDate = Calendar.current.date(from: dob) else { return nil }
        let components = Calendar.current.dateComponents([.year], from: birthDate, to: Date())
        return components.year
    }

    // MARK: - Storage Keys

    private static let restingHRKey = "healthkit_resting_hr"
    private static let maxHRKey = "healthkit_max_hr"
    private static let vo2MaxKey = "healthkit_vo2max"
    /// User completed the HealthKit permission flow successfully (persists across launches).
    private static let userEnabledKey = "healthkit_user_enabled"
    private static let syncWorkoutsToHealthKey = "healthkit_sync_rides_to_health"

    // MARK: - Private

    private let healthStore: HKHealthStore?
    private let isAvailable: Bool

    /// Tracks whether we've already attempted authorization this launch.
    /// Prevents repeated failed attempts that spam the console.
    private var authorizationAttempted: Bool = false

    /// Set to true when a missing-entitlement error is detected.
    /// Once set, all HealthKit calls are permanently skipped for this launch.
    private var entitlementMissing: Bool = false

    // MARK: - Init

    init() {
        self.isAvailable = HKHealthStore.isHealthDataAvailable()
        self.healthStore = isAvailable ? HKHealthStore() : nil

        // Restore cached values so UI has data before async queries complete
        restoreCachedValues()
        restoreUserAuthorizationFlag()
        if isAuthorized {
            Task { await self.refreshAll() }
        }
    }

    /// HealthKit does not expose a reliable “read access granted” API; we persist
    /// when the user completes `requestAuthorization` so Settings matches Strava-style “connected”.
    private func restoreUserAuthorizationFlag() {
        guard UserDefaults.standard.bool(forKey: Self.userEnabledKey) else { return }
        isAuthorized = true
    }

    private func persistUserAuthorizationEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.userEnabledKey)
    }

    // MARK: - Authorization

    /// Whether the app has the required Info.plist key for HealthKit read authorization.
    /// Without these keys, calling `requestAuthorization` will crash with an NSInvalidArgumentException.
    private var hasShareUsageDescription: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSHealthShareUsageDescription") != nil
    }

    private var hasUpdateUsageDescription: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSHealthUpdateUsageDescription") != nil
    }

    /// Request read access to the HealthKit data types we need.
    ///
    /// **Safety guards** (each one prevents the call entirely):
    /// 1. HealthKit not available on this device → no-op
    /// 2. NSHealthShareUsageDescription missing from Info.plist → no-op (would crash)
    /// 3. Already attempted this launch → no-op (avoids console spam)
    /// 4. Previous attempt revealed missing entitlement → permanent no-op
    func requestAuthorization() async {
        // Once we know the entitlement is missing, never try again.
        guard !entitlementMissing else { return }

        // Only attempt once per app launch.
        guard !authorizationAttempted else { return }
        authorizationAttempted = true

        guard isAvailable, let healthStore else {
            logger.info("HealthKit is not available on this device.")
            await MainActor.run {
                self.lastError = "HealthKit is not available on this device."
            }
            return
        }

        guard hasShareUsageDescription else {
            logger.warning("NSHealthShareUsageDescription not set in Info.plist — skipping HealthKit authorization.")
            await MainActor.run {
                self.isAuthorized = false
                self.entitlementMissing = true
                self.lastError = "HealthKit not configured. Add entitlement and usage description to enable."
                self.persistUserAuthorizationEnabled(false)
            }
            return
        }

        if syncWorkoutsToAppleHealth && !hasUpdateUsageDescription {
            logger.warning("NSHealthUpdateUsageDescription missing — cannot enable workout write.")
            await MainActor.run {
                self.lastError = "Add NSHealthUpdateUsageDescription to save rides to Apple Health."
                self.syncWorkoutsToAppleHealth = false
            }
            return
        }

        var readTypes: Set<HKObjectType> = []

        if let restingHR = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) {
            readTypes.insert(restingHR)
        }
        if let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            readTypes.insert(heartRate)
        }
        if let vo2 = HKQuantityType.quantityType(forIdentifier: .vo2Max) {
            readTypes.insert(vo2)
        }
        if let dob = HKCharacteristicType.characteristicType(forIdentifier: .dateOfBirth) {
            readTypes.insert(dob)
        }

        do {
            try await healthStore.requestAuthorization(toShare: buildTypesToShare(), read: readTypes)
            await MainActor.run {
                self.isAuthorized = true
                self.lastError = nil
                self.persistUserAuthorizationEnabled(true)
            }
            logger.info("HealthKit authorization sheet completed; refreshing data.")
            await refreshAll()
        } catch {
            let nsError = error as NSError

            // HKError.Code.errorAuthorizationDenied == 4; also check for entitlement keywords.
            let isEntitlementError = nsError.code == HKError.Code.errorAuthorizationDenied.rawValue
                || nsError.localizedDescription.localizedCaseInsensitiveContains("entitlement")

            if isEntitlementError {
                logger.warning("HealthKit entitlement missing — disabling HealthKit for this session.")
                await MainActor.run {
                    self.entitlementMissing = true
                    self.isAuthorized = false
                    self.lastError = "HealthKit entitlement not available. Using defaults."
                    self.persistUserAuthorizationEnabled(false)
                }
            } else {
                logger.error("HealthKit authorization failed: \(error.localizedDescription)")
                await MainActor.run {
                    self.isAuthorized = false
                    self.lastError = error.localizedDescription
                    self.persistUserAuthorizationEnabled(false)
                }
            }
        }
    }

    // MARK: - Refresh All

    /// Fetch all data types in parallel.
    func refreshAll() async {
        guard isAvailable, isAuthorized, !entitlementMissing, let healthStore else { return }

        async let rhr: Void = fetchRestingHeartRate(store: healthStore)
        async let mhr: Void = fetchMaxHeartRate(store: healthStore)
        async let vo2: Void = fetchVO2Max(store: healthStore)
        async let dob: Void = fetchDateOfBirth(store: healthStore)

        _ = await (rhr, mhr, vo2, dob)
    }

    // MARK: - Resting Heart Rate

    /// Fetches the most recent resting heart rate sample from the last 30 days.
    private func fetchRestingHeartRate(store: HKHealthStore) async {
        guard let sampleType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return }
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let datePredicate = HKQuery.predicateForSamples(withStart: thirtyDaysAgo, end: Date(), options: .strictEndDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: sampleType, predicate: datePredicate)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        do {
            let samples = try await descriptor.result(for: store)
            if let sample = samples.first {
                let bpm = Int(sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())).rounded())
                restingHeartRate = bpm
                UserDefaults.standard.set(bpm, forKey: Self.restingHRKey)
            }
        } catch {
            lastError = "Resting HR: \(error.localizedDescription)"
        }
    }

    // MARK: - Max Heart Rate (from workout HR samples)

    /// Queries the highest heart rate recorded in any workout sample over the last 90 days.
    private func fetchMaxHeartRate(store: HKHealthStore) async {
        guard let sampleType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        let ninetyDaysAgo = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        let datePredicate = HKQuery.predicateForSamples(withStart: ninetyDaysAgo, end: Date(), options: .strictEndDate)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: HKSamplePredicate.quantitySample(type: sampleType, predicate: datePredicate),
            options: .discreteMax
        )
        do {
            let statistics = try await descriptor.result(for: store)
            if let maxBPM = statistics?.maximumQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())),
               maxBPM > 0 {
                let bpm = Int(maxBPM.rounded())
                maxHeartRate = bpm
                UserDefaults.standard.set(bpm, forKey: Self.maxHRKey)
            }
        } catch {
            lastError = "Max HR: \(error.localizedDescription)"
        }
    }

    // MARK: - VO2 Max

    /// Fetches the most recent VO2 Max sample.
    private func fetchVO2Max(store: HKHealthStore) async {
        guard let sampleType = HKQuantityType.quantityType(forIdentifier: .vo2Max) else { return }
        let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()
        let datePredicate = HKQuery.predicateForSamples(withStart: sixMonthsAgo, end: Date(), options: .strictEndDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: sampleType, predicate: datePredicate)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        do {
            let samples = try await descriptor.result(for: store)
            if let sample = samples.first {
                // VO2 Max unit: mL/(kg·min)
                let unit = HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))
                let value = sample.quantity.doubleValue(for: unit)
                vo2Max = value
                UserDefaults.standard.set(value, forKey: Self.vo2MaxKey)
            }
        } catch {
            lastError = "VO2 Max: \(error.localizedDescription)"
        }
    }

    // MARK: - Date of Birth

    /// Reads the user's date of birth from HealthKit characteristics.
    private func fetchDateOfBirth(store: HKHealthStore) async {
        do {
            let components = try store.dateOfBirthComponents()
            await MainActor.run {
                self.dateOfBirth = components
            }
        } catch {
            // Not an error worth surfacing — user may not have set DOB
        }
    }

    // MARK: - Cache

    private func restoreCachedValues() {
        let cachedResting = UserDefaults.standard.integer(forKey: Self.restingHRKey)
        if cachedResting > 0 {
            restingHeartRate = cachedResting
        }

        let cachedMax = UserDefaults.standard.integer(forKey: Self.maxHRKey)
        if cachedMax > 0 {
            maxHeartRate = cachedMax
        }

        let cachedVO2 = UserDefaults.standard.double(forKey: Self.vo2MaxKey)
        if cachedVO2 > 0 {
            vo2Max = cachedVO2
        }
    }

    // MARK: - Manual Override

    /// Allows the user to manually set max HR (e.g., from a field test).
    /// Pass nil to revert to HealthKit/age-estimated value.
    func setManualMaxHR(_ bpm: Int?) {
        if let bpm, bpm > 0 {
            maxHeartRate = bpm
            UserDefaults.standard.set(bpm, forKey: Self.maxHRKey)
        } else {
            maxHeartRate = nil
            UserDefaults.standard.removeObject(forKey: Self.maxHRKey)
        }
    }

    /// Allows the user to manually set resting HR.
    func setManualRestingHR(_ bpm: Int?) {
        if let bpm, bpm > 0 {
            restingHeartRate = bpm
            UserDefaults.standard.set(bpm, forKey: Self.restingHRKey)
        } else {
            restingHeartRate = nil
            UserDefaults.standard.removeObject(forKey: Self.restingHRKey)
        }
    }

    // MARK: - Save workouts (Apple Health / Fitness)

    /// Saves a completed ride when ``syncWorkoutsToAppleHealth`` is on. Skips duplicates via `HKMetadataKeyExternalUUID`.
    func saveCyclingWorkoutToHealthIfEnabled(_ workout: Workout) async {
        guard syncWorkoutsToAppleHealth else { return }
        guard !entitlementMissing, isAvailable, let healthStore else { return }
        guard workout.isValid, let end = workout.endDate, end > workout.startDate else { return }

        guard hasShareUsageDescription, hasUpdateUsageDescription else {
            let msg = "Health usage descriptions missing for workout sync."
            lastError = msg
            workoutSyncToHealthLastError = msg
            return
        }

        let externalID = workout.id.uuidString

        if await healthKitWorkoutExists(store: healthStore, externalUUID: externalID) {
            return
        }

        var totalDistance: HKQuantity?
        if workout.distance > 1 {
            totalDistance = HKQuantity(unit: .meter(), doubleValue: workout.distance)
        }

        var totalEnergy: HKQuantity?
        if workout.avgPower > 0, workout.duration > 0 {
            let kj = workout.avgPower * workout.duration / 1000.0
            let kcal = kj * 0.239_005_736
            if kcal > 0.5 {
                totalEnergy = HKQuantity(unit: .kilocalorie(), doubleValue: kcal)
            }
        }

        // Outdoor rides set `savedRouteKind`; indoor trainer sessions typically leave it nil.
        let isIndoor = workout.savedRouteKind == nil
        let start = workout.startDate

        do {
            // Run HKWorkoutBuilder operations off the main actor. HealthKit may internally use
            // DispatchQueue.main.sync in some code paths; calling its async APIs while the
            // @MainActor executor owns the main queue triggers "unsafeForcedSync called from
            // Swift Concurrent context". A nonisolated helper runs on the cooperative thread
            // pool, leaving the main GCD queue free for HealthKit's own synchronization.
            try await Self._saveWorkoutWithBuilder(
                store: healthStore,
                isIndoor: isIndoor,
                externalID: externalID,
                start: start,
                end: end,
                totalEnergy: totalEnergy,
                totalDistance: totalDistance
            )
            workoutSyncToHealthLastError = nil
            logger.info("Saved workout \(externalID) to HealthKit.")
        } catch {
            logger.error("HealthKit workout save failed: \(error.localizedDescription)")
            lastError = error.localizedDescription
            workoutSyncToHealthLastError = error.localizedDescription
        }
    }

    /// Builds and saves an `HKWorkout` using `HKWorkoutBuilder`.
    ///
    /// Marked `nonisolated` so execution happens on the cooperative thread pool rather than
    /// the main actor's executor. This keeps the main GCD queue free for HealthKit's internal
    /// synchronization and avoids the "unsafeForcedSync called from Swift Concurrent context"
    /// runtime diagnostic that fires when HealthKit async APIs are awaited on the main actor.
    nonisolated private static func _saveWorkoutWithBuilder(
        store: HKHealthStore,
        isIndoor: Bool,
        externalID: String,
        start: Date,
        end: Date,
        totalEnergy: HKQuantity?,
        totalDistance: HKQuantity?
    ) async throws {
        var metadata: [String: Any] = [
            HKMetadataKeyExternalUUID: externalID,
            HKMetadataKeySyncIdentifier: "mangox-\(externalID)",
        ]
        if isIndoor {
            metadata[HKMetadataKeyIndoorWorkout] = true
        }

        let config = HKWorkoutConfiguration()
        config.activityType = .cycling
        config.locationType = isIndoor ? .indoor : .outdoor

        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        try await builder.beginCollection(at: start)

        var samples: [HKSample] = []
        if let energy = totalEnergy, let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            samples.append(HKQuantitySample(type: energyType, quantity: energy, start: start, end: end))
        }
        if let distance = totalDistance, let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceCycling) {
            samples.append(HKQuantitySample(type: distanceType, quantity: distance, start: start, end: end))
        }
        if !samples.isEmpty {
            try await builder.addSamples(samples)
        }

        try await builder.addMetadata(metadata)
        try await builder.endCollection(at: end)
        _ = try await builder.finishWorkout()
    }

    private func buildTypesToShare() -> Set<HKSampleType> {
        guard syncWorkoutsToAppleHealth else { return [] }
        var share = Set<HKSampleType>()
        share.insert(HKObjectType.workoutType())
        if let e = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            share.insert(e)
        }
        if let d = HKQuantityType.quantityType(forIdentifier: .distanceCycling) {
            share.insert(d)
        }
        return share
    }

    private func healthKitWorkoutExists(store: HKHealthStore, externalUUID: String) async -> Bool {
        let pred = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID,
            allowedValues: [externalUUID]
        )
        return await withCheckedContinuation { continuation in
            let q = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: pred,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: (samples?.isEmpty == false))
            }
            store.execute(q)
        }
    }
}

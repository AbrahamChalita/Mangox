import Foundation
import Observation
import _MapKit_SwiftUI
import CoreLocation
import CoreMotion
import MapKit
import os.log
import UIKit

private let logger = Logger(subsystem: "com.abchalita.Mangox", category: "LocationManager")

private struct RecordedTrackPoint {
    let coordinate: CLLocationCoordinate2D
    let altitude: Double
    let timestamp: Date
}

/// Bridges non-`Sendable` references into `@Sendable` closures (e.g. main-queue cleanup in `deinit`).
private struct UncheckedOptional<T>: @unchecked Sendable {
    /// `nonisolated(unsafe)`: assigned from `nonisolated init` while default module isolation is `MainActor`.
    nonisolated(unsafe) var value: T?
    nonisolated init(_ value: T?) { self.value = value }
}

private struct FixedBuffer<T> {
    private var storage: [T] = []
    let capacity: Int

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    mutating func append(_ value: T) {
        if storage.count == capacity {
            storage.removeFirst()
        }
        storage.append(value)
    }

    mutating func reset() {
        storage.removeAll(keepingCapacity: true)
    }

    var values: [T] { storage }
}

/// Lock-backed; must stay off default `MainActor` isolation (see `SWIFT_DEFAULT_ACTOR_ISOLATION`).
private final class PendingHeadingStore: @unchecked Sendable {
    nonisolated private let lock = NSLock()
    nonisolated(unsafe) private var latestHeading: Double?
    nonisolated(unsafe) private var hasPendingValue = false

    nonisolated init() {}

    nonisolated func store(_ heading: Double) {
        lock.lock()
        latestHeading = heading
        hasPendingValue = true
        lock.unlock()
    }

    nonisolated func take() -> Double? {
        lock.lock()
        defer { lock.unlock() }
        guard hasPendingValue else { return nil }
        hasPendingValue = false
        return latestHeading
    }
}

/// Timers / file handle / heading buffer are not SwiftUI-observable state. Kept outside `@Observable` synthesis
/// so delegate + `deinit` can use `nonisolated(unsafe)` storage without `ObservationTracked` macro conflicts.
/// Stored properties are `nonisolated(unsafe)` so this type is not forced onto `MainActor` by default isolation.
private final class LocationManagerConcurrencyHandles: @unchecked Sendable {
    nonisolated(unsafe) var rideTimer: Timer?
    nonisolated(unsafe) var headingFlushTimer: Timer?
    nonisolated(unsafe) var gpsStaleMonitorTimer: Timer?
    nonisolated(unsafe) var pendingRecordedTrackFileHandle: FileHandle?
    nonisolated let pendingHeadingStore: PendingHeadingStore

    nonisolated init() {
        pendingHeadingStore = PendingHeadingStore()
    }
}

/// Road gradient + climb detection info for live outdoor riding.
struct ClimbInfo {
    /// Road gradient in percent (positive = uphill).
    let grade: Double
    /// How far we have been climbing, in meters.
    let distanceSoFar: Double
}

/// A completed auto-lap snapshot.
struct OutdoorLapRecord: Identifiable {
    let id = UUID()
    let number: Int
    let distanceMeters: Double
    let duration: TimeInterval
    let avgSpeedKmh: Double
    let elevationGainMeters: Double
    /// Wall-clock lap boundaries for persisting `LapSplit`.
    let startedAt: Date
    let endedAt: Date

    /// Human-readable pace string, e.g. "4:32/km".
    var paceString: String {
        guard avgSpeedKmh > 0 else { return "--" }
        let secPerKm = 3600.0 / avgSpeedKmh
        let m = Int(secPerKm / 60)
        let s = Int(secPerKm) % 60
        return String(format: "%d:%02d/km", m, s)
    }
}

struct BreadcrumbChunk: Identifiable {
    let id = UUID()
    let coords: [CLLocationCoordinate2D]
    let avgSpeed: Double
}

enum OutdoorSignalConfidence {
    case searching
    case excellent
    case good
    case weak
    case stale
}

/// Centralized GPS service for outdoor rides.
///
/// Provides live location, speed, altitude, heading, and distance tracking.
/// Records a breadcrumb trail and exports GPX.
/// Uses Kalman-style smoothing to reduce GPS jitter.
///
/// **How Core Location relates to Wi‑Fi / cellular:** The system may fuse GPS with Wi‑Fi and
/// cell towers for *fixes* and for **A‑GPS** (faster time‑to‑first‑fix). **Speed** comes from
/// `CLLocation.speed` (typically GPS Doppler when moving outdoors), and **ride distance** is
/// accumulated from successive **accepted** GPS points — not from network triangulation alone.
/// In **urban canyons** or **tunnels**, when GPS drops, Wi‑Fi/cellular cannot substitute
/// accurate cycling speed; the UI can show a stale state (`isGpsSignalStale`) while cached
/// coordinates (`lastSearchBiasCoordinate` + UserDefaults) only help **search/map bias**, not
/// live speed or distance.
@Observable
@MainActor
final class LocationManager: NSObject {

    // MARK: - Published State

    /// Current authorization status.
    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// Whether location services are authorized (whenInUse or always).
    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    /// Most recent location from GPS.
    var currentLocation: CLLocation?

    /// Current speed in km/h (smoothed). Negative means unavailable.
    var speed: Double = 0

    /// Current altitude in meters.
    var altitude: Double = 0

    /// Current heading in degrees (0-360). Negative means unavailable.
    var heading: Double = -1

    /// Current course (direction of travel) in degrees.
    var course: Double = -1

    /// GPS signal accuracy in meters. Lower = better.
    var horizontalAccuracy: Double = -1

    /// High-level confidence for outdoor ride state and live metrics.
    var signalConfidence: OutdoorSignalConfidence = .searching

    /// True when motion sensors are currently helping maintain ride continuity while GPS is weak.
    var isMotionFallbackActive: Bool = false

    /// True when no `CLLocation` delegate callbacks arrived for a while while preview/recording is active.
    /// Use for live speed display; does not affect accumulated ride distance (which pauses when fixes stop).
    var isGpsSignalStale: Bool = false

    /// Whether we're actively recording a ride.
    var isRecording: Bool = false

    /// Total distance traveled in meters during the current ride.
    var totalDistance: Double = 0

    /// Total elevation gain in meters during the current ride.
    var totalElevationGain: Double = 0

    /// Duration of the current ride in seconds (excludes paused time).
    var rideDuration: TimeInterval = 0

    /// Average speed in km/h for the current ride.
    var averageSpeed: Double = 0

    /// Max speed in km/h for the current ride.
    var maxSpeed: Double = 0

    /// Whether the ride is currently auto-paused (speed < threshold).
    var isAutoPaused: Bool = false

    /// Camera position for the map — updated live.
    var mapCameraPosition: MapCameraPosition = .automatic

    /// Heading (degrees) applied to the map camera after course/compass selection and smoothing.
    /// UI (e.g. north compass) should counter-rotate with this value, not raw `heading`.
    private(set) var mapCameraHeadingDegrees: Double = 0

    /// When true the map auto-centres on the rider. Set to false when the user
    /// pans/zooms manually; re-enabled by tapping the centre-on-user button.
    var isFollowingUser: Bool = true

    /// True while the outdoor dashboard is showing and requesting fixes before/during a ride (not for other screens).
    private(set) var outdoorLocationPreviewActive: Bool = false

    /// Last valid coordinate from Core Location, updated even before accuracy passes the ride filter.
    /// Used for `MKLocalSearchCompleter` region bias when `currentLocation` is still nil.
    private(set) var lastSearchBiasCoordinate: CLLocationCoordinate2D?

    /// Coordinate for address search relevance: live fix if available, else last rough fix, else a neutral world bias.
    var destinationSearchBiasCoordinate: CLLocationCoordinate2D {
        if let c = currentLocation?.coordinate { return c }
        if let c = lastSearchBiasCoordinate { return c }
        return Self.fallbackSearchBiasCoordinate
    }

    /// Neutral center when no location has ever been received (wide span applied in search, not here).
    /// Uses San Francisco as a reasonable English-app default rather than lat:0/lon:0 (mid-Atlantic).
    private static let fallbackSearchBiasCoordinate = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)

    // MARK: - Chunked Breadcrumbs (Performance)

    /// Frozen breadcrumb chunks for efficient map rendering.
    /// Each chunk holds up to 100 coords + average speed (km/h) for colour coding.
    var frozenBreadcrumbChunks: [BreadcrumbChunk] = []

    /// Currently-growing tail — rendered as a single live polyline.
    var liveBreadcrumbTail: [CLLocationCoordinate2D] = []

    // MARK: - Grade & Climb

    /// Current road gradient in percent (positive = uphill, negative = downhill).
    var currentGrade: Double = 0

    /// Non-nil when the rider has been climbing > 3 % for more than 200 m.
    var activeClimb: ClimbInfo? = nil

    // MARK: - Auto-Lap

    /// Lap interval in meters (0 = disabled).
    var lapIntervalMeters: Double = 1000

    /// Completed laps during the current ride.
    var completedLaps: [OutdoorLapRecord] = []

    /// Set to true for one timer tick when a new lap is triggered; UI clears it.
    var newLapJustCompleted: Bool = false

    // MARK: - Pause Gap Markers

    /// Coordinates where auto-pause began — used to break the polyline visually.
    var pauseGapCoordinates: [CLLocationCoordinate2D] = []

    // MARK: - Configuration

    /// Speed threshold for auto-pause in km/h.
    var autoPauseThreshold: Double = 3.0

    // MARK: - Private

    private var clManager: CLLocationManager?
    private let motionManager = CMMotionManager()
    private var rideStartDate: Date?
    private var totalPausedDuration: TimeInterval = 0
    private var lastPauseStart: Date?
    private var lastRecordedLocation: CLLocation?
    private var lastAltitude: Double?
    /// `nonisolated let` + `@unchecked Sendable` bag: readable from `nonisolated` Core Location delegate methods.
    @ObservationIgnored
    nonisolated private let concurrencyHandles = LocationManagerConcurrencyHandles()
    private let headingFlushInterval: TimeInterval = 1.0 / 8.0
    private var pendingRecordedTrackPointsURL: URL?
    private let gpxDateFormatter = ISO8601DateFormatter()

    // Chunked breadcrumbs
    private var liveTailSpeedAccum: Double = 0
    private var liveTailSpeedCount: Int = 0
    private let breadcrumbChunkSize = 100

    // Grade computation — ring buffer of (altitude, totalDistance) pairs
    private var altitudeSamples = FixedBuffer<(alt: Double, dist: Double)>(capacity: 10)
    private let gradeSampleWindow = 10  // ≈ 50 m at 5-m breadcrumb spacing

    // Climb detection
    private var climbStartDist: Double = 0
    private var climbSampleStreak: Int = 0

    // Auto-lap
    private var currentLapStartDistance: Double = 0
    private var currentLapStartDuration: TimeInterval = 0
    private var currentLapStartElevation: Double = 0
    private var currentLapWallStart: Date?

    /// EMA smoothing for speed. Alpha 0.3 ≈ ~3 sample window.
    private var speedEMA: Double = 0
    private let speedAlpha: Double = 0.3
    /// When the denoised speed is zero, decay the EMA faster so brief 1–2 km/h Doppler noise doesn’t linger.
    private let stationarySpeedEMADecay: Double = 0.55
    /// GPS Doppler often reports ~1–2.5 km/h when you are stopped; treat anything below this as stationary.
    private let stationarySpeedDeadZoneKmh: Double = 2.8
    /// If `speedAccuracy` is missing, use a slightly higher floor than 0.5 m/s (~1.8 km/h) to reduce phantom motion.
    private let defaultSpeedNoiseFloorMps: Double = 0.65

    /// Low-pass smoothing for map rotation (0–1); higher = snappier.
    private let mapHeadingSmoothingAlpha: Double = 0.22
    /// GPS speed (m/s) above this prefers **course** over compass for heading-up (Apple Maps–style).
    private let mapHeadingCourseSpeedThresholdMps: Double = 2.0
    private var smoothedMapHeadingDegrees: Double = 0
    private var hasSeededMapHeading = false

    /// EMA smoothing for map camera center position (0–1); prevents GPS jitter from shaking the map.
    /// Alpha 0.45 ≈ ~2 sample window (~2–4 m lag at cycling speed — invisible, but eliminates shake).
    private let mapPositionSmoothingAlpha: Double = 0.45
    private var smoothedMapLat: Double = 0
    private var smoothedMapLon: Double = 0

    /// Caps map camera publish rate: compass + GPS can otherwise exceed 30 Hz and thrash SwiftUI + MapKit.
    private var lastMapCameraUpdateTime: Date = .distantPast
    private let mapCameraUpdateMinInterval: TimeInterval = 1.0 / 30.0
    /// Skips redundant `MapCameraPosition` writes when the camera barely moved (reduces view invalidation).
    private var lastPublishedMapCamera: (lat: Double, lon: Double, heading: Double)?

    /// Consecutive GPS readings below/above autoPauseThreshold before triggering pause/resume.
    /// Prevents false triggers from GPS jitter, weak signal, or momentary traffic-light stops.
    private var pauseDebounceCount: Int = 0
    private var resumeDebounceCount: Int = 0
    private let pauseDebounceRequired: Int = 4   // ~4–8 s depending on GPS rate
    private let resumeDebounceRequired: Int = 2  // resume faster than pause

    /// Minimum GPS accuracy (meters) to accept a location update.
    private let acceptableAccuracy: Double = 50.0

    /// Minimum distance between breadcrumb points (meters) to avoid cluttering.
    private let minimumBreadcrumbDistance: Double = 5.0

    /// Finer sampling while recording a ride (matches previous default).
    private let recordingDistanceFilter: CLLocationDistance = 3
    /// Coarser sampling during map/search preview only — fewer callbacks → less map + CPU work.
    private let previewDistanceFilter: CLLocationDistance = 8

    private static let persistedSearchBiasLatKey = "LocationManager.persistedSearchBiasLat"
    private static let persistedSearchBiasLonKey = "LocationManager.persistedSearchBiasLon"

    private var lastPersistedSearchBiasAt: Date = .distantPast
    private var lastPersistedSearchBiasCoord: CLLocationCoordinate2D?

    /// Last time `didUpdateLocations` fired — tracks link liveness, not accuracy.
    private var lastDelegateLocationAt: Date?

    private let gpsStaleThresholdSeconds: TimeInterval = 10
    private let gpsStaleCheckIntervalSeconds: TimeInterval = 2
    /// Motion fallback helps resume in tunnels / urban canyons without inventing distance.
    private var motionMovementEMA: Double = 0
    private var motionResumeDebounceCount: Int = 0
    private var lastStrongMotionAt: Date?
    private let motionUpdateIntervalSeconds = 0.5
    private let motionResumeRequiredSamples = 5
    private let motionResumeAccelerationThresholdG = 0.045
    private let motionResumeRotationThresholdRad = 0.22
    private let motionResumeMinimumPauseSeconds: TimeInterval = 2.5
    private let weakGpsHorizontalAccuracyThreshold: Double = 28
    private let motionPauseSuppressionWindow: TimeInterval = 3

    // MARK: - Init

    override init() {
        super.init()
        gpxDateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        loadPersistedSearchBiasFromStorage()
        // Create the manager up front so `authorizationStatus` reflects the system
        // setting on launch (previously stayed `.notDetermined` until Outdoor/Connection).
        setup()
    }

    deinit {
        // `Timer` / `FileHandle` are not `Sendable`; wrap for `@Sendable` main-queue cleanup.
        let rideBox = UncheckedOptional<Timer>(concurrencyHandles.rideTimer)
        let gpsBox = UncheckedOptional<Timer>(concurrencyHandles.gpsStaleMonitorTimer)
        let headingBox = UncheckedOptional<Timer>(concurrencyHandles.headingFlushTimer)
        let fileBox = UncheckedOptional<FileHandle>(concurrencyHandles.pendingRecordedTrackFileHandle)
        DispatchQueue.main.async {
            rideBox.value?.invalidate()
            gpsBox.value?.invalidate()
            headingBox.value?.invalidate()
            fileBox.value?.closeFile()
        }
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
    }

    // MARK: - Setup

    /// Initialize the CLLocationManager. Call this during onboarding or first use.
    /// Triggers the system permission dialog if not yet determined.
    func setup() {
        guard clManager == nil else { return }
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = recordingDistanceFilter
        manager.activityType = .fitness
        // Background updates require "Always"; with When-In-Use only, this must stay false.
        applyBackgroundLocationPolicy(to: manager)
        manager.showsBackgroundLocationIndicator = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.headingFilter = 2
        clManager = manager
        authorizationStatus = manager.authorizationStatus
    }

    private func applyBackgroundLocationPolicy(to manager: CLLocationManager) {
        manager.allowsBackgroundLocationUpdates =
            (manager.authorizationStatus == .authorizedAlways) && (isRecording || outdoorLocationPreviewActive)
    }

    private func loadPersistedSearchBiasFromStorage() {
        let d = UserDefaults.standard
        guard d.object(forKey: Self.persistedSearchBiasLatKey) != nil,
              let lat = d.object(forKey: Self.persistedSearchBiasLatKey) as? Double,
              let lon = d.object(forKey: Self.persistedSearchBiasLonKey) as? Double else { return }
        let c = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        guard CLLocationCoordinate2DIsValid(c) else { return }
        lastSearchBiasCoordinate = c
        lastPersistedSearchBiasCoord = c
    }

    private func persistSearchBiasIfNeeded(_ coord: CLLocationCoordinate2D) {
        let now = Date()
        if now.timeIntervalSince(lastPersistedSearchBiasAt) < 60,
           let last = lastPersistedSearchBiasCoord {
            let a = CLLocation(latitude: last.latitude, longitude: last.longitude)
            let b = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            if a.distance(from: b) < 200 { return }
        }
        lastPersistedSearchBiasCoord = coord
        lastPersistedSearchBiasAt = now
        UserDefaults.standard.set(coord.latitude, forKey: Self.persistedSearchBiasLatKey)
        UserDefaults.standard.set(coord.longitude, forKey: Self.persistedSearchBiasLonKey)
    }

    /// Recording uses a tight `distanceFilter`; preview-only uses a looser filter to cut CPU/map work.
    private func applyLocationSamplingPolicy() {
        guard let m = clManager else { return }
        if isRecording {
            m.distanceFilter = recordingDistanceFilter
        } else if outdoorLocationPreviewActive {
            m.distanceFilter = previewDistanceFilter
        }
    }

    private func startGpsStaleMonitoringIfNeeded() {
        guard isRecording || outdoorLocationPreviewActive else { return }
        guard concurrencyHandles.gpsStaleMonitorTimer == nil else { return }
        let timer = Timer(timeInterval: gpsStaleCheckIntervalSeconds, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.checkGpsSignalStale()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        concurrencyHandles.gpsStaleMonitorTimer = timer
    }

    private func stopGpsStaleMonitoring() {
        concurrencyHandles.gpsStaleMonitorTimer?.invalidate()
        concurrencyHandles.gpsStaleMonitorTimer = nil
        isGpsSignalStale = false
        refreshSignalConfidence()
    }

    private func startHeadingFlushTimerIfNeeded() {
        guard concurrencyHandles.headingFlushTimer == nil else { return }
        let timer = Timer(timeInterval: headingFlushInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.flushPendingHeadingIfNeeded()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        concurrencyHandles.headingFlushTimer = timer
    }

    private func stopHeadingFlushTimerIfIdle() {
        guard !(isRecording || outdoorLocationPreviewActive) else { return }
        concurrencyHandles.headingFlushTimer?.invalidate()
        concurrencyHandles.headingFlushTimer = nil
    }

    private func checkGpsSignalStale() {
        guard isRecording || outdoorLocationPreviewActive else { return }
        guard let last = lastDelegateLocationAt else { return }
        let stale = Date().timeIntervalSince(last) > gpsStaleThresholdSeconds
        if stale != isGpsSignalStale { isGpsSignalStale = stale }
        refreshSignalConfidence()
    }

    private func startMotionMonitoringIfNeeded() {
        guard motionManager.isDeviceMotionAvailable else { return }
        guard !motionManager.isDeviceMotionActive else { return }
        motionManager.deviceMotionUpdateInterval = motionUpdateIntervalSeconds
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self else { return }
            if let error {
                logger.error("Device motion error: \(error.localizedDescription)")
                return
            }
            guard let motion else { return }
            self.handleDeviceMotion(motion)
        }
    }

    private func stopMotionMonitoringIfIdle() {
        guard !(isRecording || outdoorLocationPreviewActive) else { return }
        guard motionManager.isDeviceMotionActive else { return }
        motionManager.stopDeviceMotionUpdates()
        motionMovementEMA = 0
        motionResumeDebounceCount = 0
        lastStrongMotionAt = nil
        isMotionFallbackActive = false
        refreshSignalConfidence()
    }

    private func handleDeviceMotion(_ motion: CMDeviceMotion) {
        let accel = motion.userAcceleration
        let accelMagnitude = sqrt((accel.x * accel.x) + (accel.y * accel.y) + (accel.z * accel.z))
        let rotation = motion.rotationRate
        let rotationMagnitude = sqrt((rotation.x * rotation.x) + (rotation.y * rotation.y) + (rotation.z * rotation.z))

        let normalizedAcceleration = accelMagnitude / motionResumeAccelerationThresholdG
        let normalizedRotation = rotationMagnitude / motionResumeRotationThresholdRad
        let instantaneousMotion = max(normalizedAcceleration, normalizedRotation)
        motionMovementEMA = (0.3 * instantaneousMotion) + (0.7 * motionMovementEMA)

        let hasStrongInstantaneousMotion =
            accelMagnitude >= motionResumeAccelerationThresholdG
            || (accelMagnitude >= motionResumeAccelerationThresholdG * 0.72 && rotationMagnitude >= motionResumeRotationThresholdRad)
        let hasSustainedMotion = motionMovementEMA >= 1.0

        if hasStrongInstantaneousMotion || hasSustainedMotion {
            lastStrongMotionAt = Date()
        }

        let shouldAssistResume = shouldAllowMotionAssistedResume()
        isMotionFallbackActive = shouldAssistResume && (hasStrongInstantaneousMotion || hasSustainedMotion)
        refreshSignalConfidence()

        guard shouldAssistResume else {
            motionResumeDebounceCount = 0
            return
        }

        if hasStrongInstantaneousMotion || hasSustainedMotion {
            motionResumeDebounceCount += 1
            if motionResumeDebounceCount >= motionResumeRequiredSamples {
                logger.info("Resuming outdoor ride from motion fallback while GPS is weak/stale.")
                resumeRecording()
                motionResumeDebounceCount = 0
            }
        } else {
            motionResumeDebounceCount = 0
        }
    }

    private func hasRecentStrongMotion() -> Bool {
        guard let lastStrongMotionAt else { return false }
        return Date().timeIntervalSince(lastStrongMotionAt) <= motionPauseSuppressionWindow
    }

    private func shouldSuppressGpsAutoPause() -> Bool {
        let gpsLooksWeak = isGpsSignalStale || horizontalAccuracy < 0 || horizontalAccuracy > weakGpsHorizontalAccuracyThreshold
        return gpsLooksWeak && hasRecentStrongMotion()
    }

    private var effectivePauseDebounceRequired: Int {
        switch signalConfidence {
        case .excellent:
            return pauseDebounceRequired
        case .good:
            return pauseDebounceRequired + 1
        case .weak:
            return pauseDebounceRequired + 3
        case .stale:
            return pauseDebounceRequired + 5
        case .searching:
            return pauseDebounceRequired + 2
        }
    }

    private func refreshSignalConfidence() {
        if isGpsSignalStale {
            signalConfidence = isMotionFallbackActive ? .weak : .stale
            return
        }
        guard horizontalAccuracy >= 0 else {
            signalConfidence = .searching
            return
        }
        if horizontalAccuracy <= 8 {
            signalConfidence = .excellent
        } else if horizontalAccuracy <= 18 {
            signalConfidence = .good
        } else {
            signalConfidence = .weak
        }
    }

    private func shouldAllowMotionAssistedResume() -> Bool {
        guard isRecording, isAutoPaused else { return false }
        guard let pauseStart = lastPauseStart else { return false }
        guard Date().timeIntervalSince(pauseStart) >= motionResumeMinimumPauseSeconds else { return false }

        let gpsLooksWeak = isGpsSignalStale || horizontalAccuracy < 0 || horizontalAccuracy > weakGpsHorizontalAccuracyThreshold
        guard gpsLooksWeak else { return false }

        if let lastStrongMotionAt,
           Date().timeIntervalSince(lastStrongMotionAt) > 4 {
            motionResumeDebounceCount = 0
        }

        return true
    }

    /// Request location permission.
    func requestPermission() {
        setup()
        clManager?.requestWhenInUseAuthorization()
    }

    // MARK: - Recording

    /// Start recording an outdoor ride.
    func startRecording() {
        guard isAuthorized else {
            logger.warning("Cannot start recording — location not authorized.")
            return
        }

        // Prompt for "Always" so rides continue when switching apps (Music, etc.). UIBackgroundModes
        // includes `location`, but `allowsBackgroundLocationUpdates` only applies when authorized Always.
        if authorizationStatus == .authorizedWhenInUse {
            clManager?.requestAlwaysAuthorization()
        }

        // Reset state
        totalDistance = 0
        totalElevationGain = 0
        rideDuration = 0
        averageSpeed = 0
        maxSpeed = 0
        speed = 0
        speedEMA = 0
        isAutoPaused = false
        lastRecordedLocation = nil
        lastAltitude = nil
        totalPausedDuration = 0
        lastPauseStart = nil
        frozenBreadcrumbChunks = []
        liveBreadcrumbTail = []
        liveTailSpeedAccum = 0
        liveTailSpeedCount = 0
        altitudeSamples.reset()
        currentGrade = 0
        activeClimb = nil
        climbStartDist = 0
        climbSampleStreak = 0
        completedLaps = []
        newLapJustCompleted = false
        currentLapStartDistance = 0
        currentLapStartDuration = 0
        currentLapStartElevation = 0
        pauseGapCoordinates = []
        pauseDebounceCount = 0
        resumeDebounceCount = 0
        motionMovementEMA = 0
        motionResumeDebounceCount = 0
        lastStrongMotionAt = nil
        signalConfidence = .searching
        isMotionFallbackActive = false
        smoothedMapLat = 0
        smoothedMapLon = 0
        lastPublishedMapCamera = nil
        lastMapCameraUpdateTime = .distantPast
        resetRecordedTrackStorage()
        prepareRecordedTrackStorage()

        rideStartDate = Date()
        currentLapWallStart = rideStartDate
        isRecording = true
        outdoorLocationPreviewActive = false

        applyLocationSamplingPolicy()
        applyBackgroundLocationPolicy(to: clManager!)
        clManager?.startUpdatingLocation()
        clManager?.startUpdatingHeading()

        startGpsStaleMonitoringIfNeeded()
        startHeadingFlushTimerIfNeeded()
        startMotionMonitoringIfNeeded()
        centerMapOnUser()

        // Start a 1-second timer for duration tracking
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.updateDuration()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        concurrencyHandles.rideTimer = timer
        HapticManager.shared.workoutStarted()

        logger.info("Outdoor ride recording started.")
    }

    /// Re-enables auto-follow and snaps the camera back to the rider.
    func centerMapOnUser() {
        isFollowingUser = true
        // Reset position smoothing so the camera snaps immediately to current location
        // instead of easing from wherever it was.
        smoothedMapLat = 0
        smoothedMapLon = 0
        lastPublishedMapCamera = nil
        lastMapCameraUpdateTime = .distantPast
        if let loc = currentLocation {
            let target = targetHeadingDegrees(for: loc)
            smoothedMapHeadingDegrees = target
            mapCameraHeadingDegrees = target
            hasSeededMapHeading = true
        } else {
            hasSeededMapHeading = false
        }
        updateMapCamera(force: true)
    }

    /// Start live location + heading updates while on the outdoor screen (before or during a ride).
    func startOutdoorLocationPreview() {
        guard isAuthorized else { return }
        guard !isRecording else { return }
        setup()
        outdoorLocationPreviewActive = true
        applyLocationSamplingPolicy()
        if let clManager {
            applyBackgroundLocationPolicy(to: clManager)
        }
        clManager?.startUpdatingLocation()
        clManager?.startUpdatingHeading()
        startGpsStaleMonitoringIfNeeded()
        startHeadingFlushTimerIfNeeded()
        startMotionMonitoringIfNeeded()
    }

    /// If the user already granted location access, request a one-shot fix as soon as the main shell appears.
    /// Warms CoreLocation’s cache without leaving continuous GPS on for the whole Home session; full updates
    /// still start when Outdoor calls `startOutdoorLocationPreview()`.
    func warmUpLocationIfAuthorized() {
        guard isAuthorized else { return }
        setup()
        clManager?.requestLocation()
    }

    /// Stops preview updates when leaving the outdoor screen without an active recording.
    func stopOutdoorLocationPreviewIfIdle() {
        outdoorLocationPreviewActive = false
        guard !isRecording else { return }
        stopGpsStaleMonitoring()
        clManager?.stopUpdatingLocation()
        clManager?.stopUpdatingHeading()
        if let clManager {
            applyBackgroundLocationPolicy(to: clManager)
        }
        stopHeadingFlushTimerIfIdle()
        stopMotionMonitoringIfIdle()
    }

    /// Pause the ride recording (manual or auto-pause).
    func pauseRecording() {
        guard isRecording, !isAutoPaused else { return }
        isAutoPaused = true
        lastPauseStart = Date()
        motionResumeDebounceCount = 0
        motionMovementEMA = 0
        lastStrongMotionAt = nil
        isMotionFallbackActive = false
        refreshSignalConfidence()
        if let loc = currentLocation {
            pauseGapCoordinates.append(loc.coordinate)
        }
        HapticManager.shared.autoPaused()
    }

    /// Resume from pause.
    func resumeRecording() {
        guard isRecording, isAutoPaused else { return }
        if let pauseStart = lastPauseStart {
            totalPausedDuration += Date().timeIntervalSince(pauseStart)
        }
        lastPauseStart = nil
        isAutoPaused = false
        pauseDebounceCount = 0
        resumeDebounceCount = 0
        motionResumeDebounceCount = 0
        motionMovementEMA = 0
        isMotionFallbackActive = false
        refreshSignalConfidence()
        HapticManager.shared.autoResumed()
    }

    /// Stop recording and finalize the ride.
    func stopRecording() {
        isRecording = false
        isAutoPaused = false
        concurrencyHandles.rideTimer?.invalidate()
        concurrencyHandles.rideTimer = nil
        stopGpsStaleMonitoring()
        clManager?.stopUpdatingLocation()
        clManager?.stopUpdatingHeading()
        concurrencyHandles.pendingRecordedTrackFileHandle?.closeFile()
        concurrencyHandles.pendingRecordedTrackFileHandle = nil

        hasSeededMapHeading = false
        if let clManager {
            applyBackgroundLocationPolicy(to: clManager)
        }
        stopHeadingFlushTimerIfIdle()
        stopMotionMonitoringIfIdle()
        signalConfidence = .searching

        // Final duration update
        if let pauseStart = lastPauseStart {
            totalPausedDuration += Date().timeIntervalSince(pauseStart)
        }
        updateDuration()

        logger.info("Outdoor ride stopped. Distance: \(self.totalDistance)m, Duration: \(self.rideDuration)s")
    }

    // MARK: - GPX Export

    /// Generate GPX XML string from recorded locations.
    func exportGPX() -> String {
        let trackPointsBody: String
        if let pendingRecordedTrackPointsURL,
           let data = try? Data(contentsOf: pendingRecordedTrackPointsURL),
           let contents = String(data: data, encoding: .utf8) {
            trackPointsBody = contents
        } else {
            trackPointsBody = ""
        }
        var gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Mangox" xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <name>Outdoor Ride</name>
            <trkseg>

        """
        gpx += trackPointsBody

        gpx += """
            </trkseg>
          </trk>
        </gpx>
        """

        return gpx
    }

    /// Region that encompasses all breadcrumbs with padding.
    var breadcrumbRegion: MKCoordinateRegion? {
        let coordinates = allBreadcrumbCoordinates()
        guard coordinates.count > 1 else {
            guard let loc = currentLocation else { return nil }
            return MKCoordinateRegion(
                center: loc.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            )
        }

        var minLat = coordinates[0].latitude
        var maxLat = coordinates[0].latitude
        var minLon = coordinates[0].longitude
        var maxLon = coordinates[0].longitude

        for coord in coordinates {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        let latSpan = max((maxLat - minLat) * 1.4, 0.003)
        let lonSpan = max((maxLon - minLon) * 1.4, 0.003)

        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan)
        )
    }

    // MARK: - Private Helpers

    private func allBreadcrumbCoordinates() -> [CLLocationCoordinate2D] {
        frozenBreadcrumbChunks.flatMap(\.coords) + liveBreadcrumbTail
    }

    private func resetRecordedTrackStorage() {
        concurrencyHandles.pendingRecordedTrackFileHandle?.closeFile()
        concurrencyHandles.pendingRecordedTrackFileHandle = nil
        if let pendingRecordedTrackPointsURL {
            try? FileManager.default.removeItem(at: pendingRecordedTrackPointsURL)
        }
        pendingRecordedTrackPointsURL = nil
    }

    private func prepareRecordedTrackStorage() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mangox-ride-\(UUID().uuidString)")
            .appendingPathExtension("trk")
        FileManager.default.createFile(atPath: fileURL.path, contents: Data())
        pendingRecordedTrackPointsURL = fileURL
        concurrencyHandles.pendingRecordedTrackFileHandle = try? FileHandle(forWritingTo: fileURL)
    }

    private func appendRecordedTrackPoint(_ location: CLLocation) {
        guard let handle = concurrencyHandles.pendingRecordedTrackFileHandle else { return }
        let point = RecordedTrackPoint(
            coordinate: location.coordinate,
            altitude: location.altitude,
            timestamp: location.timestamp
        )
        let lat = String(format: "%.7f", point.coordinate.latitude)
        let lon = String(format: "%.7f", point.coordinate.longitude)
        let ele = String(format: "%.1f", point.altitude)
        let time = gpxDateFormatter.string(from: point.timestamp)
        let line = "      <trkpt lat=\"\(lat)\" lon=\"\(lon)\"><ele>\(ele)</ele><time>\(time)</time></trkpt>\n"
        guard let data = line.data(using: .utf8) else { return }
        do {
            try handle.write(contentsOf: data)
        } catch {
            logger.error("Failed to append GPX track point: \(error.localizedDescription)")
        }
    }

    private func flushPendingHeadingIfNeeded() {
        guard let latestHeading = concurrencyHandles.pendingHeadingStore.take() else { return }
        heading = latestHeading
        if isFollowingUser && (isRecording || outdoorLocationPreviewActive) {
            updateMapCamera(force: false)
        }
    }

    private func updateDuration() {
        guard let start = rideStartDate else { return }
        let elapsed = Date().timeIntervalSince(start)
        let pauseTime: TimeInterval
        if let pauseStart = lastPauseStart {
            pauseTime = totalPausedDuration + Date().timeIntervalSince(pauseStart)
        } else {
            pauseTime = totalPausedDuration
        }
        rideDuration = max(0, elapsed - pauseTime)

        if rideDuration > 0 {
            averageSpeed = (totalDistance / rideDuration) * 3.6 // m/s to km/h
        }
    }

    private func processLocation(_ location: CLLocation) {
        if CLLocationCoordinate2DIsValid(location.coordinate) {
            lastSearchBiasCoordinate = location.coordinate
        }

        // Filter out inaccurate readings
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= acceptableAccuracy else {
            return
        }

        currentLocation = location
        persistSearchBiasIfNeeded(location.coordinate)
        horizontalAccuracy = location.horizontalAccuracy
        altitude = location.altitude
        course = location.course >= 0 ? location.course : course
        refreshSignalConfidence()

        // Speed: gate against CLLocation's own noise floor before smoothing.
        // speedAccuracy is the 68th-pct uncertainty in m/s (-1 = unavailable).
        // Only counting speed above the noise floor prevents GPS jitter from
        // appearing as phantom motion while stationary.
        let rawSpeedKmh: Double
        if location.speed >= 0 {
            let noiseFloorMs = location.speedAccuracy >= 0 ? location.speedAccuracy : defaultSpeedNoiseFloorMps
            var denoised = location.speed > noiseFloorMs ? location.speed : 0.0
            // Weak horizontal fixes: Doppler speed is less trustworthy; suppress very low “creep”.
            if location.horizontalAccuracy > 22 {
                let strictFloor = noiseFloorMs + 0.25
                denoised = location.speed > strictFloor ? location.speed : 0.0
            }
            rawSpeedKmh = denoised * 3.6
        } else {
            rawSpeedKmh = 0
        }

        // Hard dead zone: iPhone GPS often shows ~2 km/h when standing still.
        let clampedRaw = rawSpeedKmh < stationarySpeedDeadZoneKmh ? 0.0 : rawSpeedKmh

        // EMA smoothing — seed on first real movement to avoid ramp-up lag.
        // When clamped to zero, decay quickly so the UI doesn’t sit at ~2 km/h.
        if speedEMA == 0 && clampedRaw > 0 {
            speedEMA = clampedRaw
        } else if clampedRaw == 0 {
            speedEMA *= stationarySpeedEMADecay
            if speedEMA < 0.15 { speedEMA = 0 }
        } else {
            speedEMA = speedAlpha * clampedRaw + (1 - speedAlpha) * speedEMA
        }
        speed = speedEMA

        // Track max speed
        if speed > maxSpeed {
            maxSpeed = speed
        }

        // Auto-pause with debounce — require N consecutive readings to avoid false triggers
        // from GPS jitter, weak signal, or brief stops at traffic lights.
        if isRecording {
            if speed < autoPauseThreshold {
                if shouldSuppressGpsAutoPause() {
                    pauseDebounceCount = 0
                    resumeDebounceCount = 0
                } else {
                    pauseDebounceCount += 1
                    resumeDebounceCount = 0
                    if pauseDebounceCount >= effectivePauseDebounceRequired && !isAutoPaused {
                        pauseRecording()
                    }
                }
            } else {
                resumeDebounceCount += 1
                pauseDebounceCount = 0
                if resumeDebounceCount >= resumeDebounceRequired && isAutoPaused {
                    resumeRecording()
                }
            }
        }

        // Keep the map centered on the rider when auto-follow is active.
        if isFollowingUser && (isRecording || outdoorLocationPreviewActive) {
            updateMapCamera(force: false)
        }

        // Recording: accumulate distance + breadcrumb chunks
        guard isRecording, !isAutoPaused else { return }

        if let last = lastRecordedLocation {
            let delta = location.distance(from: last)

            // Only accumulate if the movement is plausible (< 50 m/s ≈ 180 km/h)
            if delta > minimumBreadcrumbDistance && delta / max(1, location.timestamp.timeIntervalSince(last.timestamp)) < 50 {
                totalDistance += delta
                // Chunked breadcrumbs — feed live tail
                liveBreadcrumbTail.append(location.coordinate)
                liveTailSpeedAccum += speed
                liveTailSpeedCount += 1
                if liveBreadcrumbTail.count >= breadcrumbChunkSize {
                    let avg = liveTailSpeedCount > 0 ? liveTailSpeedAccum / Double(liveTailSpeedCount) : speed
                    frozenBreadcrumbChunks.append(BreadcrumbChunk(coords: liveBreadcrumbTail, avgSpeed: avg))
                    liveBreadcrumbTail = [location.coordinate]
                    liveTailSpeedAccum = speed
                    liveTailSpeedCount = 1
                }

                // Altitude samples for grade computation
                altitudeSamples.append((alt: location.altitude, dist: totalDistance))
                updateGradeAndClimb()

                // Auto-lap check
                if lapIntervalMeters > 0 {
                    let nextLapDist = currentLapStartDistance + lapIntervalMeters
                    if totalDistance >= nextLapDist {
                        triggerLap()
                    }
                }

                appendRecordedTrackPoint(location)

                // Elevation gain
                if let lastAlt = lastAltitude,
                   location.verticalAccuracy >= 0,
                   location.verticalAccuracy < 20 {
                    let elevDiff = location.altitude - lastAlt
                    if elevDiff > 0.5 { // filter noise: require >0.5m gain
                        totalElevationGain += elevDiff
                    }
                }

                lastRecordedLocation = location
                if location.verticalAccuracy >= 0 && location.verticalAccuracy < 20 {
                    lastAltitude = location.altitude
                }
            }
        } else {
            // First point
            lastRecordedLocation = location
            lastAltitude = location.altitude
            liveBreadcrumbTail.append(location.coordinate)
            appendRecordedTrackPoint(location)
        }
    }

    private func updateGradeAndClimb() {
        let samples = altitudeSamples.values
        guard samples.count >= 2 else {
            currentGrade = 0
            return
        }
        let first = samples[0]
        let last = samples[samples.count - 1]
        let distDelta = last.dist - first.dist
        guard distDelta > 1 else { return }
        let altDelta = last.alt - first.alt
        currentGrade = (altDelta / distDelta) * 100.0

        // Climb detection: sustained grade > 3 % for > 200 m
        if currentGrade > 3.0 {
            climbSampleStreak += 1
            if climbSampleStreak == 1 {
                climbStartDist = totalDistance
            }
            let distClimbing = totalDistance - climbStartDist
            if distClimbing > 200 {
                activeClimb = ClimbInfo(grade: currentGrade, distanceSoFar: distClimbing)
            }
        } else {
            if climbSampleStreak > 0 {
                climbSampleStreak = max(0, climbSampleStreak - 2)
                if climbSampleStreak == 0 {
                    activeClimb = nil
                    climbStartDist = 0
                }
            }
        }
    }

    private func triggerLap() {
        let lapNumber = completedLaps.count + 1
        let lapDist = totalDistance - currentLapStartDistance
        let lapDuration = rideDuration - currentLapStartDuration
        let lapElev = totalElevationGain - currentLapStartElevation
        let lapAvgSpeed = lapDuration > 0 ? (lapDist / lapDuration) * 3.6 : 0
        let endedAt = Date()
        let startedAt = currentLapWallStart ?? rideStartDate ?? endedAt
        let record = OutdoorLapRecord(
            number: lapNumber,
            distanceMeters: lapDist,
            duration: lapDuration,
            avgSpeedKmh: lapAvgSpeed,
            elevationGainMeters: lapElev,
            startedAt: startedAt,
            endedAt: endedAt
        )
        completedLaps.append(record)
        newLapJustCompleted = true
        currentLapStartDistance = totalDistance
        currentLapStartDuration = rideDuration
        currentLapStartElevation = totalElevationGain
        currentLapWallStart = endedAt
    }

    private func updateMapCamera(force: Bool) {
        guard let loc = currentLocation else { return }
        let now = Date()
        if !force, now.timeIntervalSince(lastMapCameraUpdateTime) < mapCameraUpdateMinInterval {
            return
        }

        let rawTarget = targetHeadingDegrees(for: loc)
        if !hasSeededMapHeading {
            smoothedMapHeadingDegrees = rawTarget
            hasSeededMapHeading = true
        } else {
            smoothedMapHeadingDegrees = smoothedMapHeading(
                from: smoothedMapHeadingDegrees,
                toward: rawTarget,
                alpha: mapHeadingSmoothingAlpha
            )
        }
        mapCameraHeadingDegrees = smoothedMapHeadingDegrees

        // EMA-smooth the camera center to eliminate GPS jitter from shaking the map.
        if smoothedMapLat == 0 {
            smoothedMapLat = loc.coordinate.latitude
            smoothedMapLon = loc.coordinate.longitude
        } else {
            let α = mapPositionSmoothingAlpha
            smoothedMapLat = α * loc.coordinate.latitude  + (1 - α) * smoothedMapLat
            smoothedMapLon = α * loc.coordinate.longitude + (1 - α) * smoothedMapLon
        }
        let center = CLLocationCoordinate2D(latitude: smoothedMapLat, longitude: smoothedMapLon)

        if !force,
           let last = lastPublishedMapCamera,
           abs(last.lat - center.latitude) < 1e-7,
           abs(last.lon - center.longitude) < 1e-7,
           headingDifferenceDegrees(last.heading, smoothedMapHeadingDegrees) < 0.35 {
            return
        }

        lastMapCameraUpdateTime = now
        lastPublishedMapCamera = (center.latitude, center.longitude, smoothedMapHeadingDegrees)

        mapCameraPosition = .camera(
            MapCamera(
                centerCoordinate: center,
                distance: 800,
                heading: smoothedMapHeadingDegrees,
                pitch: 45
            )
        )
    }

    /// Prefer **course** (direction of travel) when moving; compass when slow/stopped; then course/last resort.
    private func targetHeadingDegrees(for location: CLLocation) -> Double {
        let speedMps: Double
        if location.speed >= 0 {
            let noiseFloor = location.speedAccuracy >= 0 ? location.speedAccuracy : defaultSpeedNoiseFloorMps
            var s = location.speed > noiseFloor ? location.speed : 0
            if s * 3.6 < stationarySpeedDeadZoneKmh { s = 0 }
            speedMps = s
        } else {
            speedMps = 0
        }
        if speedMps >= mapHeadingCourseSpeedThresholdMps, location.course >= 0 {
            return location.course
        }
        if heading >= 0 {
            return heading
        }
        if location.course >= 0 {
            return location.course
        }
        if course >= 0 {
            return course
        }
        return hasSeededMapHeading ? smoothedMapHeadingDegrees : 0
    }

    private func headingDifferenceDegrees(_ a: Double, _ b: Double) -> Double {
        var d = a - b
        while d > 180 { d -= 360 }
        while d < -180 { d += 360 }
        return abs(d)
    }

    private func smoothedMapHeading(from current: Double, toward target: Double, alpha: Double) -> Double {
        var delta = target - current
        while delta > 180 { delta -= 360 }
        while delta < -180 { delta += 360 }
        var next = current + alpha * delta
        next = next.truncatingRemainder(dividingBy: 360)
        if next < 0 { next += 360 }
        return next
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in
            self.lastDelegateLocationAt = Date()
            self.isGpsSignalStale = false
            processLocation(latest)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        concurrencyHandles.pendingHeadingStore.store(newHeading.trueHeading)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            self.applyBackgroundLocationPolicy(to: manager)
            if self.isRecording || self.outdoorLocationPreviewActive {
                manager.startUpdatingLocation()
            }
            logger.info("Location authorization changed to: \(manager.authorizationStatus.rawValue)")
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            logger.error("Location error: \(error.localizedDescription)")
        }
    }
}

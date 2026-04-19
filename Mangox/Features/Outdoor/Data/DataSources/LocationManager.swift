import CoreLocation
import CoreMotion
import Foundation
import MapKit
import Observation
import SwiftUI
import Synchronization
import UIKit
import os.log

private let logger = Logger(subsystem: "com.abchalita.Mangox", category: "LocationManager")

private struct RecordedTrackPoint {
    let coordinate: CLLocationCoordinate2D
    let altitude: Double
    let timestamp: Date
}

private struct PersistedCoordinate: Codable {
    let latitude: Double
    let longitude: Double

    init(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

private struct PersistedBreadcrumbChunk: Codable {
    let coordinates: [PersistedCoordinate]
    let averageSpeed: Double
}

private struct PersistedOutdoorLapRecord: Codable {
    let number: Int
    let distanceMeters: Double
    let duration: TimeInterval
    let averageSpeedKmh: Double
    let elevationGainMeters: Double
    let startedAt: Date
    let endedAt: Date
}

    private struct OutdoorRideCheckpoint: Codable {
    let persistedAt: Date
    let rideStartDate: Date
    let totalDistance: Double
    let totalElevationGain: Double
    let rideDuration: TimeInterval
    let averageSpeed: Double
    let maxSpeed: Double
    let speed: Double
    let speedEMA: Double
    let isAutoPaused: Bool
    let totalPausedDuration: TimeInterval
    let lastPauseStart: Date?
    let currentGrade: Double
    let lapIntervalMeters: Double
    let completedLaps: [PersistedOutdoorLapRecord]
    let currentLapStartDistance: Double
    let currentLapStartDuration: TimeInterval
    let currentLapStartElevation: Double
    let currentLapWallStart: Date?
    let frozenBreadcrumbChunks: [PersistedBreadcrumbChunk]
    let liveBreadcrumbTail: [PersistedCoordinate]
    let pauseGapCoordinates: [PersistedCoordinate]
    let recordedTrackPath: String?
        let lastKnownCoordinate: PersistedCoordinate?
    }

    private struct PersistedRideCheckpointEnvelope: Codable {
        let version: Int
        let checkpoint: OutdoorRideCheckpoint
    }

/// Bridges non-`Sendable` references into `@Sendable` closures (e.g. main-queue cleanup in `deinit`).
private struct UncheckedOptional<T>: @unchecked Sendable {
    /// `nonisolated(unsafe)`: assigned from `nonisolated init` while default module isolation is `MainActor`.
    nonisolated(unsafe) var value: T?
    nonisolated init(_ value: T?) { self.value = value }
}

private struct FixedBuffer<T> {
    private var storage: [T] = []
    private var writeIndex = 0
    let capacity: Int

    init(capacity: Int) {
        self.capacity = max(1, capacity)
        storage.reserveCapacity(capacity)
    }

    mutating func append(_ value: T) {
        if storage.count < capacity {
            storage.append(value)
            writeIndex = storage.count % capacity
        } else {
            storage[writeIndex] = value
            writeIndex = (writeIndex + 1) % capacity
        }
    }

    mutating func reset() {
        storage.removeAll(keepingCapacity: true)
        writeIndex = 0
    }

    var values: [T] {
        if storage.count < capacity {
            return storage
        }
        return Array(storage[writeIndex...]) + Array(storage[..<writeIndex])
    }
}

/// Mutex-backed; naturally `Sendable` without `@unchecked`.
private final class PendingHeadingStore: Sendable {
    private struct State {
        var latestHeading: Double?
        var hasPendingValue = false
    }
    private let state = Mutex(State())

    nonisolated init() {}

    nonisolated func store(_ heading: Double) {
        state.withLock {
            $0.latestHeading = heading
            $0.hasPendingValue = true
        }
    }

    nonisolated func take() -> Double? {
        state.withLock { s in
            guard s.hasPendingValue else { return nil }
            s.hasPendingValue = false
            return s.latestHeading
        }
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
    nonisolated(unsafe) var appLifecycleObservers: [NSObjectProtocol] = []
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
/// Uses a lightweight 2×1D Kalman filter plus speed-adaptive heading smoothing for live map follow.
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
final class LocationManager: NSObject, LocationServiceProtocol, MapCameraServiceProtocol {

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
    private var didRestoreRecordingFlag = false

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

    /// True when Outdoor map follow UI is visible and wants live heading + smoothing updates.
    var mapFollowActive: Bool = false {
        didSet {
            guard mapFollowActive != oldValue else { return }
            applyHighFrequencySensorsPolicy()
        }
    }

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
    private static let fallbackSearchBiasCoordinate = CLLocationCoordinate2D(
        latitude: 37.7749, longitude: -122.4194)

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
    /// Matches map camera publish cadence; also drives Kalman extrapolation between GPS fixes.
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

    /// GPS speed (m/s) above this prefers **course** over compass for heading-up (Apple Maps–style).
    private let mapHeadingCourseSpeedThresholdMps: Double = 2.0
    private var smoothedMapHeadingDegrees: Double = 0
    private var hasSeededMapHeading = false
    /// Previous **raw** map heading target (before hysteresis) — detects bogus 0/360 flips when nearly stopped.
    private var previousRawMapHeadingDegrees: Double?

    // MARK: - Kalman filter (lat / lon)

    /// Independent 1D Kalman along each axis — constant-velocity prior, position measurements only.
    /// `r` is measurement **variance** in the same units as `x` (degrees² for geo coordinates).
    private struct Kalman1D {
        var x: Double
        var v: Double
        var p: Double
        let q: Double

        init(state: Double, initialVariance: Double, processNoise: Double) {
            x = state
            v = 0
            p = max(initialVariance, 1e-12)
            q = processNoise
        }

        mutating func update(measurement: Double, dt rawDt: Double, measurementVariance r: Double) {
            let dt = min(max(rawDt, 0.05), 4.0)
            let xPred = x + v * dt
            let pPred = p + q * dt
            let rUse = max(r, 1e-12)
            let k = pPred / (pPred + rUse)
            let innovation = measurement - xPred
            x = xPred + k * innovation
            v += k * (innovation / dt)
            p = (1 - k) * pPred
        }

        /// Display extrapolation between GPS measurements (`x` + `v`·Δt), capped to limit runaway drift.
        func extrapolatedPosition(deltaTime rawDt: Double, maxDelta: TimeInterval) -> Double {
            let dt = min(max(rawDt, 0), maxDelta)
            return x + v * dt
        }
    }

    private var kalmanLat: Kalman1D?
    private var kalmanLon: Kalman1D?
    private var lastKalmanUpdateTime: Date?

    /// Smoothed rider position — matches map camera center whenever follow mode is active.
    var smoothedRiderCoordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 0, longitude: 0)

    /// Speed-adaptive heading smoothing.
    private func adaptiveHeadingAlpha() -> Double {
        let speedKmh = speed
        switch speedKmh {
        case ..<2.0: return 0.06     // Very smooth when stopped
        case 2.0..<8.0: return 0.12  // Moderate when starting
        case 8.0..<20.0: return 0.18 // Normal cruising
        default: return 0.25         // Snappy at high speed
        }
    }

    /// Process-noise scale for Kalman — higher when moving so the filter can track turns.
    private func adaptiveProcessNoise() -> Double {
        let speedKmh = speed
        switch speedKmh {
        case ..<2.0: return 0.07
        case 2.0..<10.0: return 0.16
        case 10.0..<25.0: return 0.32
        default: return 0.5
        }
    }

    /// Caps map camera publish rate to ~8 Hz — enough for smooth animation without thrashing SwiftUI.
    private var lastMapCameraUpdateTime: Date = .distantPast
    private let mapCameraUpdateMinInterval: TimeInterval = 1.0 / 8.0

    /// Skips redundant `MapCameraPosition` writes when the camera barely moved (~3m position deadband).
    private var lastPublishedMapCamera: (lat: Double, lon: Double, heading: Double)?
    private let mapPositionDeadbandDegrees: Double = 0.000035  // ≈ 3–4 meters at mid-latitudes
    private let mapHeadingDeadbandDegrees: Double = 0.5
    /// Max time to coast the display state ahead of the last GPS fix (avoids large drift if fixes stall).
    private let mapExtrapolationMaxAdvanceSeconds: TimeInterval = 1.35
    private let mapCameraDistanceMin: CLLocationDistance = 520
    private let mapCameraDistanceMax: CLLocationDistance = 1_050

    /// Below this speed (km/h), reject “teleport” heading readings near the smoothed value (0°/360° flicker).
    private let slowHeadingHysteresisSpeedKmh: Double = 4.0
    private let headingOutlierJumpVersusPreviousDegrees: Double = 110
    private let headingOutlierNearSmoothedDegrees: Double = 18
    /// When slow, ignore sub‑2.5° target wiggles so the map doesn’t hunt.
    private let slowHeadingMicroDeadbandDegrees: Double = 2.5

    /// Consecutive GPS readings below/above autoPauseThreshold before triggering pause/resume.
    /// Prevents false triggers from GPS jitter, weak signal, or momentary traffic-light stops.
    private var pauseDebounceCount: Int = 0
    private var resumeDebounceCount: Int = 0
    private let pauseDebounceRequired: Int = 4  // ~4–8 s depending on GPS rate
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
    private static let outdoorRideCheckpointKey = "LocationManager.outdoorRideCheckpoint.v1"
    private static let outdoorRideCheckpointFileName = "outdoor-ride-checkpoint-v2.json"
    private static let rideTrackFilePrefix = "ride-"
    private static let rideTrackFileExtension = "trk"
    private let checkpointFrozenChunkLimit = 8
    private let checkpointLiveTailLimit = 240
    private let checkpointPauseGapLimit = 30

    private var lastPersistedSearchBiasAt: Date = .distantPast
    private var lastPersistedSearchBiasCoord: CLLocationCoordinate2D?
    private var lastPersistedCheckpointAt: Date = .distantPast

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
    private var activeRideID: UUID?

    // MARK: - Init

    override init() {
        super.init()
        gpxDateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        loadPersistedSearchBiasFromStorage()
        registerApplicationLifecycleObservers()
        // Create the manager up front so `authorizationStatus` reflects the system
        // setting on launch (previously stayed `.notDetermined` until Outdoor/Connection).
        setup()
    }

    deinit {
        for observer in concurrencyHandles.appLifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        concurrencyHandles.appLifecycleObservers.removeAll()
        // `Timer` / `FileHandle` are not `Sendable`; wrap for `@Sendable` main-queue cleanup.
        let rideBox = UncheckedOptional<Timer>(concurrencyHandles.rideTimer)
        let gpsBox = UncheckedOptional<Timer>(concurrencyHandles.gpsStaleMonitorTimer)
        let headingBox = UncheckedOptional<Timer>(concurrencyHandles.headingFlushTimer)
        let fileBox = UncheckedOptional<FileHandle>(
            concurrencyHandles.pendingRecordedTrackFileHandle)
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
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
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
        let applicationState = UIApplication.shared.applicationState
        let shouldAllowPreviewInBackground = outdoorLocationPreviewActive && applicationState == .active
        manager.allowsBackgroundLocationUpdates = isRecording || shouldAllowPreviewInBackground
    }

    private func registerApplicationLifecycleObservers() {
        let center = NotificationCenter.default

        let didEnterBackground = center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.handleApplicationStateTransition(isActive: false)
            }
        }

        let didBecomeActive = center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.handleApplicationStateTransition(isActive: true)
            }
        }

        concurrencyHandles.appLifecycleObservers = [didEnterBackground, didBecomeActive]
    }

    private func handleApplicationStateTransition(isActive: Bool) {
        guard let manager = clManager else { return }

        applyBackgroundLocationPolicy(to: manager)

        guard outdoorLocationPreviewActive, !isRecording else { return }

        if isActive {
            applyLocationSamplingPolicy()
            manager.startUpdatingLocation()
            startGpsStaleMonitoringIfNeeded()
            applyHighFrequencySensorsPolicy()
        } else {
            stopGpsStaleMonitoring()
            manager.stopUpdatingLocation()
            applyHighFrequencySensorsPolicy()
        }
    }

    private func shouldRunMotionFallbackMonitoring() -> Bool {
        guard isRecording, isAutoPaused else { return false }
        return isGpsSignalStale || horizontalAccuracy < 0
            || horizontalAccuracy > weakGpsHorizontalAccuracyThreshold
    }

    private func loadPersistedSearchBiasFromStorage() {
        let d = UserDefaults.standard
        guard d.object(forKey: Self.persistedSearchBiasLatKey) != nil,
            let lat = d.object(forKey: Self.persistedSearchBiasLatKey) as? Double,
            let lon = d.object(forKey: Self.persistedSearchBiasLonKey) as? Double
        else { return }
        let c = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        guard CLLocationCoordinate2DIsValid(c) else { return }
        lastSearchBiasCoordinate = c
        lastPersistedSearchBiasCoord = c
    }

    private func persistSearchBiasIfNeeded(_ coord: CLLocationCoordinate2D) {
        let now = Date()
        if now.timeIntervalSince(lastPersistedSearchBiasAt) < 60,
            let last = lastPersistedSearchBiasCoord
        {
            let a = CLLocation(latitude: last.latitude, longitude: last.longitude)
            let b = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            if a.distance(from: b) < 200 { return }
        }
        lastPersistedSearchBiasCoord = coord
        lastPersistedSearchBiasAt = now
        UserDefaults.standard.set(coord.latitude, forKey: Self.persistedSearchBiasLatKey)
        UserDefaults.standard.set(coord.longitude, forKey: Self.persistedSearchBiasLonKey)
    }

    /// Applies an activity-aware sampling profile.
    /// - Recording + moving: highest quality for navigation.
    /// - Recording but paused/weak: slightly lower power while still tracking well.
    /// - Preview only: lower-cost location updates.
    private func applyLocationSamplingPolicy() {
        guard let m = clManager else { return }

        if isRecording {
            m.distanceFilter = recordingDistanceFilter
            let highQuality = !isAutoPaused && !isGpsSignalStale
            m.desiredAccuracy = highQuality ? kCLLocationAccuracyBestForNavigation : kCLLocationAccuracyNearestTenMeters
            m.pausesLocationUpdatesAutomatically = false
        } else if outdoorLocationPreviewActive {
            m.distanceFilter = previewDistanceFilter
            m.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            m.pausesLocationUpdatesAutomatically = true
        } else {
            m.distanceFilter = kCLDistanceFilterNone
            m.desiredAccuracy = kCLLocationAccuracyHundredMeters
            m.pausesLocationUpdatesAutomatically = true
        }
        m.activityType = .fitness
    }

    private func startGpsStaleMonitoringIfNeeded() {
        guard isRecording || outdoorLocationPreviewActive else { return }
        guard concurrencyHandles.gpsStaleMonitorTimer == nil else { return }
        let timer = Timer(timeInterval: gpsStaleCheckIntervalSeconds, repeats: true) {
            [weak self] _ in
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
        guard mapFollowActive, isRecording || outdoorLocationPreviewActive else { return }
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
        guard !(mapFollowActive && (isRecording || outdoorLocationPreviewActive)) else { return }
        concurrencyHandles.headingFlushTimer?.invalidate()
        concurrencyHandles.headingFlushTimer = nil
    }

    private func applyHighFrequencySensorsPolicy() {
        guard let manager = clManager else { return }

        let shouldRunHeading = mapFollowActive && (isRecording || outdoorLocationPreviewActive)
        let shouldRunMotion = shouldRunMotionFallbackMonitoring()

        if shouldRunHeading {
            manager.startUpdatingHeading()
            startHeadingFlushTimerIfNeeded()
        } else {
            manager.stopUpdatingHeading()
            stopHeadingFlushTimerIfIdle()
        }

        if shouldRunMotion {
            startMotionMonitoringIfNeeded()
        } else {
            stopMotionMonitoringIfIdle()
        }
    }

    private func checkGpsSignalStale() {
        guard isRecording || outdoorLocationPreviewActive else { return }
        guard let last = lastDelegateLocationAt else { return }
        let stale = Date().timeIntervalSince(last) > gpsStaleThresholdSeconds
        if stale != isGpsSignalStale { isGpsSignalStale = stale }
        refreshSignalConfidence()
        applyLocationSamplingPolicy()
        applyHighFrequencySensorsPolicy()
    }

    private func startMotionMonitoringIfNeeded() {
        guard shouldRunMotionFallbackMonitoring() else { return }
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
        guard !shouldRunMotionFallbackMonitoring() else { return }
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
        let rotationMagnitude = sqrt(
            (rotation.x * rotation.x) + (rotation.y * rotation.y) + (rotation.z * rotation.z))

        let normalizedAcceleration = accelMagnitude / motionResumeAccelerationThresholdG
        let normalizedRotation = rotationMagnitude / motionResumeRotationThresholdRad
        let instantaneousMotion = max(normalizedAcceleration, normalizedRotation)
        motionMovementEMA = (0.3 * instantaneousMotion) + (0.7 * motionMovementEMA)

        let hasStrongInstantaneousMotion =
            accelMagnitude >= motionResumeAccelerationThresholdG
            || (accelMagnitude >= motionResumeAccelerationThresholdG * 0.72
                && rotationMagnitude >= motionResumeRotationThresholdRad)
        let hasSustainedMotion = motionMovementEMA >= 1.0

        if hasStrongInstantaneousMotion || hasSustainedMotion {
            lastStrongMotionAt = Date()
        }

        let shouldAssistResume = shouldAllowMotionAssistedResume()
        isMotionFallbackActive =
            shouldAssistResume && (hasStrongInstantaneousMotion || hasSustainedMotion)
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
        let gpsLooksWeak =
            isGpsSignalStale || horizontalAccuracy < 0
            || horizontalAccuracy > weakGpsHorizontalAccuracyThreshold
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
        guard Date().timeIntervalSince(pauseStart) >= motionResumeMinimumPauseSeconds else {
            return false
        }

        let gpsLooksWeak =
            isGpsSignalStale || horizontalAccuracy < 0
            || horizontalAccuracy > weakGpsHorizontalAccuracyThreshold
        guard gpsLooksWeak else { return false }

        if let lastStrongMotionAt,
            Date().timeIntervalSince(lastStrongMotionAt) > 4
        {
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
        clearRideCheckpoint()

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
        resetRecordedTrackStorage()
        activeRideID = UUID()
        prepareRecordedTrackStorage()

        rideStartDate = Date()
        currentLapWallStart = rideStartDate
        isRecording = true
        outdoorLocationPreviewActive = false

        applyLocationSamplingPolicy()
        applyBackgroundLocationPolicy(to: clManager!)
        clManager?.startUpdatingLocation()

        startGpsStaleMonitoringIfNeeded()
        applyHighFrequencySensorsPolicy()
        centerMapOnUser()

        // Start a 1-second timer for duration tracking
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.updateDuration()
                self.persistRideCheckpointIfNeeded(force: false)
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
        resetMapSmoothingForFollow()
        if let loc = currentLocation {
            let target = targetHeadingDegrees(for: loc)
            smoothedMapHeadingDegrees = target
            mapCameraHeadingDegrees = target
            hasSeededMapHeading = true
        } else {
            hasSeededMapHeading = false
        }
        refreshFollowModeMapPresentation(newGPSLocation: currentLocation, forcePublish: true)
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
        startGpsStaleMonitoringIfNeeded()
        applyHighFrequencySensorsPolicy()
    }

    /// If the user already granted location access, request a one-shot fix as soon as the main shell appears.
    /// Warms CoreLocation’s cache without leaving continuous GPS on for the whole Home session; full updates
    /// still start when Outdoor calls `startOutdoorLocationPreview()`.
    func warmUpLocationIfAuthorized() {
        guard isAuthorized else { return }
        setup()
        clManager?.requestLocation()
    }

    func persistRecordingCheckpointIfNeeded() {
        persistRideCheckpointIfNeeded(force: true)
    }

    /// Rehydrate in-memory outdoor ride state after relaunch when a recording checkpoint exists.
    func restoreRecordingIfNeeded() {
        guard !isRecording else { return }
        guard let checkpoint = loadRideCheckpoint() else { return }
        guard Date().timeIntervalSince(checkpoint.persistedAt) <= 24 * 60 * 60 else {
            clearRideCheckpoint()
            return
        }

        restore(from: checkpoint)

        setup()
        applyLocationSamplingPolicy()
        if let clManager {
            applyBackgroundLocationPolicy(to: clManager)
        }
        clManager?.startUpdatingLocation()
        startGpsStaleMonitoringIfNeeded()
        applyHighFrequencySensorsPolicy()

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.updateDuration()
                self.persistRideCheckpointIfNeeded(force: false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        concurrencyHandles.rideTimer = timer

        centerMapOnUser()
        didRestoreRecordingFlag = true
        logger.info("Restored outdoor ride recording from checkpoint.")
    }

    func consumeDidRestoreRecordingFlag() -> Bool {
        let value = didRestoreRecordingFlag
        didRestoreRecordingFlag = false
        return value
    }

    /// Stops preview updates when leaving the outdoor screen without an active recording.
    func stopOutdoorLocationPreviewIfIdle() {
        outdoorLocationPreviewActive = false
        guard !isRecording else { return }
        stopGpsStaleMonitoring()
        clManager?.stopUpdatingLocation()
        if let clManager {
            applyBackgroundLocationPolicy(to: clManager)
        }
        applyHighFrequencySensorsPolicy()
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
        applyLocationSamplingPolicy()
        applyHighFrequencySensorsPolicy()
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
        applyLocationSamplingPolicy()
        applyHighFrequencySensorsPolicy()
        HapticManager.shared.autoResumed()
    }

    /// Stop recording and finalize the ride.
    func stopRecording() {
        persistRideCheckpointIfNeeded(force: true)

        isRecording = false
        isAutoPaused = false
        concurrencyHandles.rideTimer?.invalidate()
        concurrencyHandles.rideTimer = nil
        stopGpsStaleMonitoring()
        clManager?.stopUpdatingLocation()
        concurrencyHandles.pendingRecordedTrackFileHandle?.closeFile()
        concurrencyHandles.pendingRecordedTrackFileHandle = nil

        hasSeededMapHeading = false
        if let clManager {
            applyBackgroundLocationPolicy(to: clManager)
        }
        applyHighFrequencySensorsPolicy()
        signalConfidence = .searching

        // Final duration update
        if let pauseStart = lastPauseStart {
            totalPausedDuration += Date().timeIntervalSince(pauseStart)
        }
        updateDuration()

        logger.info(
            "Outdoor ride stopped. Distance: \(self.totalDistance)m, Duration: \(self.rideDuration)s"
        )

        clearRideCheckpoint()
    }

    // MARK: - GPX Export

    /// Generate GPX XML string from recorded locations.
    func exportGPX() -> String {
        let trackPointsBody: String
        if let pendingRecordedTrackPointsURL,
            let data = try? Data(contentsOf: pendingRecordedTrackPointsURL),
            let contents = String(data: data, encoding: .utf8)
        {
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

    private func persistRideCheckpointIfNeeded(force: Bool) {
        guard isRecording else { return }

        let now = Date()
        if !force, now.timeIntervalSince(lastPersistedCheckpointAt) < 5 {
            return
        }

        guard let rideStartDate else { return }

        let frozenChunksToPersist = Array(frozenBreadcrumbChunks.suffix(checkpointFrozenChunkLimit))
        let liveTailToPersist = Array(liveBreadcrumbTail.suffix(checkpointLiveTailLimit))
        let pauseGapToPersist = Array(pauseGapCoordinates.suffix(checkpointPauseGapLimit))

        let checkpoint = OutdoorRideCheckpoint(
            persistedAt: now,
            rideStartDate: rideStartDate,
            totalDistance: totalDistance,
            totalElevationGain: totalElevationGain,
            rideDuration: rideDuration,
            averageSpeed: averageSpeed,
            maxSpeed: maxSpeed,
            speed: speed,
            speedEMA: speedEMA,
            isAutoPaused: isAutoPaused,
            totalPausedDuration: totalPausedDuration,
            lastPauseStart: lastPauseStart,
            currentGrade: currentGrade,
            lapIntervalMeters: lapIntervalMeters,
            completedLaps: completedLaps.map {
                PersistedOutdoorLapRecord(
                    number: $0.number,
                    distanceMeters: $0.distanceMeters,
                    duration: $0.duration,
                    averageSpeedKmh: $0.avgSpeedKmh,
                    elevationGainMeters: $0.elevationGainMeters,
                    startedAt: $0.startedAt,
                    endedAt: $0.endedAt
                )
            },
            currentLapStartDistance: currentLapStartDistance,
            currentLapStartDuration: currentLapStartDuration,
            currentLapStartElevation: currentLapStartElevation,
            currentLapWallStart: currentLapWallStart,
            frozenBreadcrumbChunks: frozenChunksToPersist.map {
                PersistedBreadcrumbChunk(
                    coordinates: $0.coords.map(PersistedCoordinate.init),
                    averageSpeed: $0.avgSpeed
                )
            },
            liveBreadcrumbTail: liveTailToPersist.map(PersistedCoordinate.init),
            pauseGapCoordinates: pauseGapToPersist.map(PersistedCoordinate.init),
            recordedTrackPath: pendingRecordedTrackPointsURL?.path,
            lastKnownCoordinate: currentLocation.map { PersistedCoordinate($0.coordinate) }
        )

        do {
            let envelope = PersistedRideCheckpointEnvelope(version: 2, checkpoint: checkpoint)
            let data = try JSONEncoder().encode(envelope)
            try data.write(to: rideCheckpointFileURL(), options: .atomic)
            // Keep tiny compatibility marker and remove legacy payload.
            UserDefaults.standard.set(true, forKey: Self.outdoorRideCheckpointKey)
            lastPersistedCheckpointAt = now
        } catch {
            logger.error("Failed to persist outdoor ride checkpoint: \(error.localizedDescription)")
        }
    }

    private func loadRideCheckpoint() -> OutdoorRideCheckpoint? {
        let fileURL = rideCheckpointFileURL()

        if let data = try? Data(contentsOf: fileURL) {
            if let envelope = try? JSONDecoder().decode(PersistedRideCheckpointEnvelope.self, from: data) {
                return envelope.checkpoint
            }
            if let legacy = try? JSONDecoder().decode(OutdoorRideCheckpoint.self, from: data) {
                return legacy
            }
        }

        // Legacy fallback (previous builds wrote the full payload to UserDefaults).
        if let legacyData = UserDefaults.standard.data(forKey: Self.outdoorRideCheckpointKey) {
            do {
                return try JSONDecoder().decode(OutdoorRideCheckpoint.self, from: legacyData)
            } catch {
                logger.error("Failed to decode outdoor ride checkpoint: \(error.localizedDescription)")
                clearRideCheckpoint()
            }
        }

        return nil
    }

    private func clearRideCheckpoint() {
        UserDefaults.standard.removeObject(forKey: Self.outdoorRideCheckpointKey)
        removeRecordedTrackFileReferencedByCheckpointIfPresent()
        try? FileManager.default.removeItem(at: rideCheckpointFileURL())
        pendingRecordedTrackPointsURL = nil
        activeRideID = nil
        lastPersistedCheckpointAt = .distantPast
    }

    private func rideCheckpointFileURL() -> URL {
        applicationSupportMangoxDirectoryURL().appendingPathComponent(Self.outdoorRideCheckpointFileName)
    }

    /// Force a durable checkpoint write for scene/background transitions.
    func persistRecordingCheckpointNow() {
        persistRideCheckpointIfNeeded(force: true)
        do {
            try concurrencyHandles.pendingRecordedTrackFileHandle?.synchronize()
        } catch {
            logger.error("Failed to synchronize pending outdoor track file: \(error.localizedDescription)")
        }
    }

    private func restore(from checkpoint: OutdoorRideCheckpoint) {
        rideStartDate = checkpoint.rideStartDate
        totalDistance = checkpoint.totalDistance
        totalElevationGain = checkpoint.totalElevationGain
        rideDuration = checkpoint.rideDuration
        averageSpeed = checkpoint.averageSpeed
        maxSpeed = checkpoint.maxSpeed
        speed = checkpoint.speed
        speedEMA = checkpoint.speedEMA
        isAutoPaused = checkpoint.isAutoPaused
        totalPausedDuration = checkpoint.totalPausedDuration
        lastPauseStart = checkpoint.lastPauseStart
        currentGrade = checkpoint.currentGrade
        lapIntervalMeters = checkpoint.lapIntervalMeters
        completedLaps = checkpoint.completedLaps.map {
            OutdoorLapRecord(
                number: $0.number,
                distanceMeters: $0.distanceMeters,
                duration: $0.duration,
                avgSpeedKmh: $0.averageSpeedKmh,
                elevationGainMeters: $0.elevationGainMeters,
                startedAt: $0.startedAt,
                endedAt: $0.endedAt
            )
        }
        currentLapStartDistance = checkpoint.currentLapStartDistance
        currentLapStartDuration = checkpoint.currentLapStartDuration
        currentLapStartElevation = checkpoint.currentLapStartElevation
        currentLapWallStart = checkpoint.currentLapWallStart
        climbStartDist = 0
        climbSampleStreak = 0
        activeClimb = nil
        frozenBreadcrumbChunks = checkpoint.frozenBreadcrumbChunks.map {
            BreadcrumbChunk(
                coords: $0.coordinates.map(\.coordinate),
                avgSpeed: $0.averageSpeed
            )
        }
        liveTailSpeedAccum = 0
        liveTailSpeedCount = 0
        liveBreadcrumbTail = checkpoint.liveBreadcrumbTail.map(\.coordinate)
        pauseGapCoordinates = checkpoint.pauseGapCoordinates.map(\.coordinate)
        pauseDebounceCount = 0
        resumeDebounceCount = 0
        motionMovementEMA = 0
        motionResumeDebounceCount = 0
        lastStrongMotionAt = nil
        isMotionFallbackActive = false
        signalConfidence = .searching
        hasSeededMapHeading = false
        lastMapCameraUpdateTime = .distantPast
        lastPublishedMapCamera = nil
        previousRawMapHeadingDegrees = nil
        altitudeSamples.reset()
        if let path = checkpoint.recordedTrackPath {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                pendingRecordedTrackPointsURL = url
                activeRideID = Self.rideID(fromTrackFileURL: url)
                concurrencyHandles.pendingRecordedTrackFileHandle = try? FileHandle(forWritingTo: url)
                concurrencyHandles.pendingRecordedTrackFileHandle?.seekToEndOfFile()
            } else {
                pendingRecordedTrackPointsURL = nil
                activeRideID = nil
                concurrencyHandles.pendingRecordedTrackFileHandle = nil
            }
        } else {
            pendingRecordedTrackPointsURL = nil
            activeRideID = nil
            concurrencyHandles.pendingRecordedTrackFileHandle = nil
        }

        if let coord = checkpoint.lastKnownCoordinate?.coordinate {
            currentLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            smoothedRiderCoordinate = coord
            lastSearchBiasCoordinate = coord
            persistSearchBiasIfNeeded(coord)
        }

        isRecording = true
        outdoorLocationPreviewActive = false
        newLapJustCompleted = false
        lastRecordedLocation = nil
        lastAltitude = nil
        horizontalAccuracy = -1
        heading = -1
        course = -1
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
        activeRideID = nil
    }

    private func prepareRecordedTrackStorage() {
        let rideID = activeRideID ?? UUID()
        activeRideID = rideID
        let fileURL = rideTrackDirectoryURL()
            .appendingPathComponent(Self.trackFileName(for: rideID))
            .appendingPathExtension(Self.rideTrackFileExtension)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: fileURL)
        }
        FileManager.default.createFile(atPath: fileURL.path, contents: Data())
        pendingRecordedTrackPointsURL = fileURL
        concurrencyHandles.pendingRecordedTrackFileHandle = try? FileHandle(forWritingTo: fileURL)
    }

    private func applicationSupportMangoxDirectoryURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Mangox", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func rideTrackDirectoryURL() -> URL {
        let dir = applicationSupportMangoxDirectoryURL().appendingPathComponent("Rides", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func removeRecordedTrackFileReferencedByCheckpointIfPresent() {
        let fileURL = rideCheckpointFileURL()
        guard let data = try? Data(contentsOf: fileURL) else { return }

        if let envelope = try? JSONDecoder().decode(PersistedRideCheckpointEnvelope.self, from: data) {
            removeRecordedTrackFile(atPath: envelope.checkpoint.recordedTrackPath)
            return
        }

        if let legacy = try? JSONDecoder().decode(OutdoorRideCheckpoint.self, from: data) {
            removeRecordedTrackFile(atPath: legacy.recordedTrackPath)
        }
    }

    private func removeRecordedTrackFile(atPath path: String?) {
        guard let path else { return }
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
    }

    private static func trackFileName(for rideID: UUID) -> String {
        "\(rideTrackFilePrefix)\(rideID.uuidString)"
    }

    private static func rideID(fromTrackFileURL url: URL) -> UUID? {
        let stem = url.deletingPathExtension().lastPathComponent
        guard stem.hasPrefix(rideTrackFilePrefix) else { return nil }
        let idString = String(stem.dropFirst(rideTrackFilePrefix.count))
        return UUID(uuidString: idString)
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
        let line =
            "      <trkpt lat=\"\(lat)\" lon=\"\(lon)\"><ele>\(ele)</ele><time>\(time)</time></trkpt>\n"
        guard let data = line.data(using: .utf8) else { return }
        do {
            try handle.write(contentsOf: data)
        } catch {
            logger.error("Failed to append GPX track point: \(error.localizedDescription)")
        }
    }

    private func flushPendingHeadingIfNeeded() {
        if let latestHeading = concurrencyHandles.pendingHeadingStore.take() {
            heading = latestHeading
        }
        // 8 Hz heartbeat: extrapolate map position between GPS fixes and pick up compass updates.
        if isFollowingUser && mapFollowActive && (isRecording || outdoorLocationPreviewActive) {
            refreshFollowModeMapPresentation(newGPSLocation: nil, forcePublish: false)
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
            averageSpeed = (totalDistance / rideDuration) * 3.6  // m/s to km/h
        }
    }

    private func processLocation(_ location: CLLocation) {
        if CLLocationCoordinate2DIsValid(location.coordinate) {
            lastSearchBiasCoordinate = location.coordinate
        }

        // Filter out inaccurate readings and old cached locations
        let locationAge = -location.timestamp.timeIntervalSinceNow
        guard locationAge < 10.0,
            location.horizontalAccuracy >= 0,
            location.horizontalAccuracy <= acceptableAccuracy
        else {
            return
        }

        currentLocation = location
        persistSearchBiasIfNeeded(location.coordinate)
        horizontalAccuracy = location.horizontalAccuracy
        altitude = location.altitude
        course = location.course >= 0 ? location.course : course
        refreshSignalConfidence()
        applyHighFrequencySensorsPolicy()

        // Speed: gate against CLLocation's own noise floor before smoothing.
        // speedAccuracy is the 68th-pct uncertainty in m/s (-1 = unavailable).
        // Only counting speed above the noise floor prevents GPS jitter from
        // appearing as phantom motion while stationary.
        let rawSpeedKmh: Double
        if location.speed >= 0 {
            let noiseFloorMs =
                location.speedAccuracy >= 0 ? location.speedAccuracy : defaultSpeedNoiseFloorMps
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
        if isFollowingUser && mapFollowActive && (isRecording || outdoorLocationPreviewActive) {
            refreshFollowModeMapPresentation(newGPSLocation: location, forcePublish: false)
        }

        // Recording: accumulate distance + breadcrumb chunks
        guard isRecording, !isAutoPaused else { return }

        if let last = lastRecordedLocation {
            let delta = location.distance(from: last)

            // Only accumulate if the movement is plausible (< 50 m/s ≈ 180 km/h)
            if delta > minimumBreadcrumbDistance
                && delta / max(1, location.timestamp.timeIntervalSince(last.timestamp)) < 50
            {
                totalDistance += delta
                // Chunked breadcrumbs — feed live tail
                liveBreadcrumbTail.append(location.coordinate)
                liveTailSpeedAccum += speed
                liveTailSpeedCount += 1
                if liveBreadcrumbTail.count >= breadcrumbChunkSize {
                    let avg =
                        liveTailSpeedCount > 0
                        ? liveTailSpeedAccum / Double(liveTailSpeedCount) : speed
                    frozenBreadcrumbChunks.append(
                        BreadcrumbChunk(coords: liveBreadcrumbTail, avgSpeed: avg))
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
                    location.verticalAccuracy < 20
                {
                    let elevDiff = location.altitude - lastAlt
                    if elevDiff > 0.5 {  // filter noise: require >0.5m gain
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

    private func resetMapSmoothingForFollow() {
        kalmanLat = nil
        kalmanLon = nil
        lastKalmanUpdateTime = nil
        previousRawMapHeadingDegrees = nil
        lastPublishedMapCamera = nil
        lastMapCameraUpdateTime = .distantPast
        if let loc = currentLocation {
            smoothedRiderCoordinate = loc.coordinate
        } else {
            smoothedRiderCoordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }
    }

    /// Rider/camera center: Kalman state advanced to `now` so the UI keeps moving between 1 Hz GPS fixes.
    private func mapDisplayCenterExtrapolated(
        at now: Date,
        fallbackCoordinate: CLLocationCoordinate2D
    ) -> CLLocationCoordinate2D {
        guard let kLat = kalmanLat, let kLon = kalmanLon, let tMeas = lastKalmanUpdateTime else {
            return fallbackCoordinate
        }
        let rawDt = now.timeIntervalSince(tMeas)
        let lat = kLat.extrapolatedPosition(
            deltaTime: rawDt, maxDelta: mapExtrapolationMaxAdvanceSeconds)
        let lon = kLon.extrapolatedPosition(
            deltaTime: rawDt, maxDelta: mapExtrapolationMaxAdvanceSeconds)
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private func applyKalmanMeasurement(_ loc: CLLocation, now: Date) {
        let lat = loc.coordinate.latitude
        let lon = loc.coordinate.longitude
        let accM = max(loc.horizontalAccuracy, 5.0)
        let sigmaLat = accM / 111_320.0
        let cosLat = cos(lat * .pi / 180.0)
        let sigmaLon = accM / (111_320.0 * max(abs(cosLat), 0.01))
        let rLat = sigmaLat * sigmaLat
        let rLon = sigmaLon * sigmaLon
        let q = adaptiveProcessNoise()

        if kalmanLat == nil {
            kalmanLat = Kalman1D(state: lat, initialVariance: rLat, processNoise: q)
            kalmanLon = Kalman1D(state: lon, initialVariance: rLon, processNoise: q)
            lastKalmanUpdateTime = now
            return
        }
        guard let lastT = lastKalmanUpdateTime else {
            lastKalmanUpdateTime = now
            return
        }
        let dt = now.timeIntervalSince(lastT)
        var kLat = kalmanLat!
        var kLon = kalmanLon!
        kLat.update(measurement: lat, dt: dt, measurementVariance: rLat)
        kLon.update(measurement: lon, dt: dt, measurementVariance: rLon)
        kalmanLat = kLat
        kalmanLon = kLon
        lastKalmanUpdateTime = now
    }

    private func applyMapHeadingSmoothing(using loc: CLLocation) {
        let rawTarget = targetHeadingDegrees(for: loc)
        let prevRaw = previousRawMapHeadingDegrees

        var target = rawTarget
        if speed < slowHeadingHysteresisSpeedKmh, let prev = prevRaw {
            let jump = headingDifferenceDegrees(rawTarget, prev)
            let nearSmoothed = headingDifferenceDegrees(rawTarget, smoothedMapHeadingDegrees)
            if jump > headingOutlierJumpVersusPreviousDegrees,
                nearSmoothed < headingOutlierNearSmoothedDegrees
            {
                target = prev
            }
        }
        if speed < slowHeadingHysteresisSpeedKmh, hasSeededMapHeading,
            headingDifferenceDegrees(target, smoothedMapHeadingDegrees) < slowHeadingMicroDeadbandDegrees
        {
            target = smoothedMapHeadingDegrees
        }

        if !hasSeededMapHeading {
            smoothedMapHeadingDegrees = target
            hasSeededMapHeading = true
        } else {
            smoothedMapHeadingDegrees = smoothedMapHeading(
                from: smoothedMapHeadingDegrees,
                toward: target,
                alpha: adaptiveHeadingAlpha()
            )
        }
        mapCameraHeadingDegrees = smoothedMapHeadingDegrees
        previousRawMapHeadingDegrees = rawTarget
    }

    /// Fuses GPS on every sample; publishes `mapCameraPosition` at ~8 Hz with animation unless `forcePublish`.
    private func refreshFollowModeMapPresentation(
        newGPSLocation: CLLocation? = nil,
        forcePublish: Bool = false
    ) {
        guard isFollowingUser, mapFollowActive, isRecording || outdoorLocationPreviewActive else { return }
        guard let loc = newGPSLocation ?? currentLocation else { return }
        let now = Date()

        if let gps = newGPSLocation {
            applyKalmanMeasurement(gps, now: now)
        }

        applyMapHeadingSmoothing(using: loc)

        let center = mapDisplayCenterExtrapolated(at: now, fallbackCoordinate: loc.coordinate)
        smoothedRiderCoordinate = center
        let speedMps = max(0, speed / 3.6)
        let normalizedSpeed = min(max(speedMps / 12.0, 0), 1)
        let dynamicCameraDistance = mapCameraDistanceMin + ((mapCameraDistanceMax - mapCameraDistanceMin) * normalizedSpeed)

        let updateMinInterval = adaptiveMapCameraUpdateMinInterval()

        if !forcePublish {
            if now.timeIntervalSince(lastMapCameraUpdateTime) < updateMinInterval {
                return
            }
            let positionDeadband = adaptiveMapPositionDeadbandDegrees()
            if let last = lastPublishedMapCamera,
                abs(last.lat - center.latitude) < positionDeadband,
                abs(last.lon - center.longitude) < positionDeadband,
                headingDifferenceDegrees(last.heading, smoothedMapHeadingDegrees) < mapHeadingDeadbandDegrees
            {
                return
            }
        }

        lastMapCameraUpdateTime = now
        lastPublishedMapCamera = (center.latitude, center.longitude, smoothedMapHeadingDegrees)

        let camera = MapCamera(
            centerCoordinate: center,
            distance: dynamicCameraDistance,
            heading: smoothedMapHeadingDegrees,
            pitch: 45
        )
        let shouldAnimate = forcePublish || (!isGpsSignalStale && speed > 2.0)

        if !shouldAnimate {
            mapCameraPosition = .camera(camera)
        } else if forcePublish {
            withAnimation(.easeOut(duration: 0.2)) {
                mapCameraPosition = .camera(camera)
            }
        } else {
            withAnimation(.easeOut(duration: 0.18)) {
                mapCameraPosition = .camera(camera)
            }
        }
    }

    private func adaptiveMapCameraUpdateMinInterval() -> TimeInterval {
        if isGpsSignalStale { return 1.0 / 3.0 }
        switch speed {
        case ..<2:
            return 1.0 / 3.0
        case ..<8:
            return 1.0 / 5.0
        default:
            return mapCameraUpdateMinInterval
        }
    }

    private func adaptiveMapPositionDeadbandDegrees() -> Double {
        if isGpsSignalStale { return mapPositionDeadbandDegrees * 2.4 }
        switch speed {
        case ..<2:
            return mapPositionDeadbandDegrees * 2.0
        case ..<8:
            return mapPositionDeadbandDegrees * 1.4
        default:
            return mapPositionDeadbandDegrees
        }
    }

    /// Prefer **course** (direction of travel) when moving; compass when slow/stopped; then course/last resort.
    private func targetHeadingDegrees(for location: CLLocation) -> Double {
        let speedMps: Double
        if location.speed >= 0 {
            let noiseFloor =
                location.speedAccuracy >= 0 ? location.speedAccuracy : defaultSpeedNoiseFloorMps
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

    private func smoothedMapHeading(from current: Double, toward target: Double, alpha: Double)
        -> Double
    {
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

    nonisolated func locationManager(
        _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
    ) {
        guard let latest = locations.last else { return }
        Task { @MainActor in
            self.lastDelegateLocationAt = Date()
            self.isGpsSignalStale = false
            processLocation(latest)
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading
    ) {
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
            self.applyHighFrequencySensorsPolicy()
            logger.info(
                "Location authorization changed to: \(manager.authorizationStatus.rawValue)")
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            logger.error("Location error: \(error.localizedDescription)")
        }
    }
}

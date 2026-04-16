import CoreLocation

/// Contract for location services — permission orchestration, live GPS metrics,
/// ride recording, and outdoor ride metrics.
///
/// Covers both the onboarding permission flow and the full outdoor ride feature set.
/// Concrete implementation: `LocationManager` in Outdoor/Data/.
@MainActor
protocol LocationServiceProtocol: AnyObject {
    // MARK: - Authorization

    var isAuthorized: Bool { get }
    var authorizationStatus: CLAuthorizationStatus { get }
    func setup()
    func requestPermission()
    func warmUpLocationIfAuthorized()
    func restoreRecordingIfNeeded()
    func persistRecordingCheckpointIfNeeded()
    func persistRecordingCheckpointNow()
    func consumeDidRestoreRecordingFlag() -> Bool

    // MARK: - Live GPS Metrics

    var currentLocation: CLLocation? { get }
    var speed: Double { get }
    var altitude: Double { get }
    var heading: Double { get }
    var course: Double { get }
    var horizontalAccuracy: Double { get }
    var isGpsSignalStale: Bool { get }
    var signalConfidence: OutdoorSignalConfidence { get }
    var isMotionFallbackActive: Bool { get }

    // MARK: - Ride Recording

    var isRecording: Bool { get set }
    var totalDistance: Double { get }
    var totalElevationGain: Double { get }
    var rideDuration: TimeInterval { get }
    var averageSpeed: Double { get }
    var maxSpeed: Double { get }
    var isAutoPaused: Bool { get }
    var currentGrade: Double { get }
    var activeClimb: ClimbInfo? { get }
    func startRecording()
    func stopRecording()

    // MARK: - Breadcrumbs

    var frozenBreadcrumbChunks: [BreadcrumbChunk] { get }
    var liveBreadcrumbTail: [CLLocationCoordinate2D] { get }
    var pauseGapCoordinates: [CLLocationCoordinate2D] { get }

    // MARK: - Auto-Lap

    var lapIntervalMeters: Double { get set }
    var completedLaps: [OutdoorLapRecord] { get }
    var newLapJustCompleted: Bool { get set }

    // MARK: - Preview Mode

    var mapFollowActive: Bool { get set }
    func startOutdoorLocationPreview()
    func stopOutdoorLocationPreviewIfIdle()
}

extension LocationServiceProtocol {
    /// Default no-op implementation for conformers that do not support pre-warm.
    func warmUpLocationIfAuthorized() {}
    func restoreRecordingIfNeeded() {}
    func persistRecordingCheckpointIfNeeded() {}
    func persistRecordingCheckpointNow() {}
    func consumeDidRestoreRecordingFlag() -> Bool { false }
}

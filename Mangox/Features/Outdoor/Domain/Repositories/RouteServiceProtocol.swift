import CoreLocation
import MapKit

/// Contract for GPX route loading and route data access.
/// Concrete implementation: `RouteManager` in Outdoor/Data/DataSources/.
@MainActor
protocol RouteServiceProtocol: AnyObject {
    // MARK: - Route State
    var hasRoute: Bool { get }
    var routeName: String? { get }
    var points: [CLLocationCoordinate2D] { get }
    var elevations: [Double?] { get }
    var segmentBreakIndices: [Int] { get }
    var totalDistance: CLLocationDistance { get }

    // MARK: - Elevation
    var hasElevationData: Bool { get }
    var totalElevationGain: Double { get }
    var elevationProfilePoints: [(distance: Double, elevation: Double)] { get }

    // MARK: - Map Display
    var polylineSegments: [[CLLocationCoordinate2D]] { get }
    var cameraRegion: MKCoordinateRegion? { get }

    // MARK: - Methods
    func loadGPX(from url: URL) async throws
    func clearRoute()
    func coordinate(forDistance distance: CLLocationDistance) -> CLLocationCoordinate2D?
    func elevation(forDistance distance: CLLocationDistance) -> Double?
}

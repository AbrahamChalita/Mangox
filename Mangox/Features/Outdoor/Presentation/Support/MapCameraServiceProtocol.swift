import CoreLocation
import MapKit
import SwiftUI

/// Presentation-only map camera contract for the outdoor dashboard.
///
/// Kept separate from `LocationServiceProtocol` so the location domain seam no longer
/// depends on SwiftUI / MapKit camera state.
@MainActor
protocol MapCameraServiceProtocol: AnyObject {
    var mapCameraPosition: MapCameraPosition { get set }
    var isFollowingUser: Bool { get set }
    var mapCameraHeadingDegrees: Double { get }
    var smoothedRiderCoordinate: CLLocationCoordinate2D { get }
    func centerMapOnUser()

    var lastSearchBiasCoordinate: CLLocationCoordinate2D? { get }
    var destinationSearchBiasCoordinate: CLLocationCoordinate2D { get }
}

import CoreLocation
import MapKit
import Testing
@testable import Mangox

struct OutdoorReliabilityTests {

    @MainActor
    @Test func locationManagerRestoresRecordingFromCheckpoint() async throws {
        let original = LocationManager()
        // Ensure this run starts from a clean slate if a previous test/process left a checkpoint behind.
        original.stopRecording()

        original.authorizationStatus = .authorizedAlways
        original.startRecording()

        let first = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.77490, longitude: -122.41940),
            altitude: 21,
            horizontalAccuracy: 6,
            verticalAccuracy: 8,
            course: 45,
            speed: 5.8,
            timestamp: Date().addingTimeInterval(-3)
        )

        let second = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.77505, longitude: -122.41928),
            altitude: 22,
            horizontalAccuracy: 5,
            verticalAccuracy: 7,
            course: 47,
            speed: 6.1,
            timestamp: Date().addingTimeInterval(-1)
        )

        original.locationManager(CLLocationManager(), didUpdateLocations: [first])
        try await Task.sleep(for: .milliseconds(60))
        original.locationManager(CLLocationManager(), didUpdateLocations: [second])
        try await Task.sleep(for: .milliseconds(60))

        original.persistRecordingCheckpointNow()

        let restored = LocationManager()
        restored.restoreRecordingIfNeeded()

        #expect(restored.isRecording)
        #expect(restored.totalDistance > 0)
        #expect(restored.currentLocation != nil)
        #expect(!restored.liveBreadcrumbTail.isEmpty || !restored.frozenBreadcrumbChunks.isEmpty)

        restored.stopRecording()
        original.stopRecording()
    }

    @Test func classifyRouteCalculationErrorHandlesOfflineAndNoRoute() {
        #expect(NavigationService.classifyRouteCalculationError(URLError(.notConnectedToInternet)) == .offline)
        #expect(NavigationService.classifyRouteCalculationError(URLError(.networkConnectionLost)) == .offline)

        let mkNetwork = NSError(domain: MKError.errorDomain, code: Int(MKError.Code.serverFailure.rawValue))
        #expect(NavigationService.classifyRouteCalculationError(mkNetwork) == .offline)

        let noDirections = NSError(domain: MKError.errorDomain, code: Int(MKError.Code.directionsNotFound.rawValue))
        #expect(NavigationService.classifyRouteCalculationError(noDirections) == .noRoute)
    }
}

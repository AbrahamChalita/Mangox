import Foundation
import MapKit
import CoreLocation
import os.log
import UIKit

private let logger = Logger(subsystem: "com.abchalita.Mangox", category: "NavigationService")

/// Turn instruction for display in the navigation HUD.
struct TurnInstruction: Identifiable, Equatable {
    /// `MKRoute` step index, or negative index for synthetic GPX corner hints.
    let stepIndex: Int
    let instruction: String
    let distance: CLLocationDistance   // meters to this turn from current position
    let symbol: String                 // SF Symbol name

    var id: Int { stepIndex }

    /// Human-readable distance string.
    var distanceText: String {
        if distance < 1000 {
            return "\(Int(distance))m"
        }
        return String(format: "%.1fkm", distance / 1000)
    }

    static func == (lhs: TurnInstruction, rhs: TurnInstruction) -> Bool {
        lhs.stepIndex == rhs.stepIndex
    }
}

/// Navigation modes.
enum NavigationMode: Equatable {
    /// Free ride — no route, just record breadcrumbs.
    case freeRide
    /// Following a loaded GPX route.
    case followRoute
    /// Following turn-by-turn directions from Apple Maps.
    case turnByTurn
}

nonisolated enum RouteCalculationFailureKind: Equatable {
    case offline
    case noRoute
    case unknown
}

/// Provides route calculation, turn-by-turn navigation, and off-course detection.
///
/// Uses Apple's MKDirections API for cycling-specific routing.
/// Integrates with LocationManager for live position tracking.
@Observable
@MainActor
final class NavigationService {

    // MARK: - State

    /// Current navigation mode.
    var mode: NavigationMode = .freeRide

    /// The planned route polyline for map display.
    var routePolyline: [CLLocationCoordinate2D] = []

    /// Portion of the route already passed (for traversed vs remaining coloring).
    var completedRoutePolylines: [[CLLocationCoordinate2D]] = []

    /// Portion of the route ahead of the rider (includes the closest vertex).
    var remainingRoutePolylines: [[CLLocationCoordinate2D]] = []

    /// Route name (from search or GPX).
    var routeName: String?

    /// Total route distance in meters.
    var routeDistance: CLLocationDistance = 0

    /// Estimated time of arrival (seconds from now).
    var estimatedTimeRemaining: TimeInterval = 0

    /// Next turn instruction.
    var nextTurn: TurnInstruction?

    /// Upcoming turn after next (preview).
    var upcomingTurn: TurnInstruction?

    /// All remaining turn instructions.
    var remainingSteps: [TurnInstruction] = []

    /// Whether the rider is off the planned route.
    var isOffCourse: Bool = false

    /// Distance from rider to nearest point on route (meters).
    var deviationDistance: Double = 0

    /// Distance along the planned polyline from the start to the perpendicular snap point (meters).
    /// Used for elevation strip cursor and ETA fraction when following a route.
    var distanceAlongRouteMeters: Double = 0

    /// Straight-line distance to the next turn maneuver (turn-by-turn), updated live.
    var distanceToNextManeuver: CLLocationDistance = 0

    /// Hint for sharp bends when following a GPX (no Apple Maps steps).
    var followRouteHint: TurnInstruction?

    /// Off-course threshold in meters.
    var offCourseThreshold: Double = 30

    /// The destination map item (for turn-by-turn).
    var destination: MKMapItem?

    /// Whether a route is currently being calculated.
    var isCalculating: Bool = false

    /// Last error from route calculation.
    var lastError: String?
    var lastRouteFailureKind: RouteCalculationFailureKind?

    // MARK: - Private

    private var currentRoute: MKRoute?
    private var allRouteSteps: [MKRoute.Step] = []
    private var completedStepIndices: Set<Int> = []

    /// 300 m segment of remaining route ahead of the rider — for lookahead ghost rendering.
    private(set) var lookaheadPolylines: [[CLLocationCoordinate2D]] = []

    /// Straight line from rider to nearest on-route point — shown when off-course.
    private(set) var snapBackPolyline: [CLLocationCoordinate2D] = []

    // Turn / GPX cue state (speech + haptic)
    private var lastAnnouncedTurnStepIndex: Int?
    private var previousDistanceToManeuver: Double = .greatestFiniteMagnitude
    private var announcedGPXCornerVertex: Int?
    private var previousGPXHintDistance: Double = .greatestFiniteMagnitude

    /// EMA-smoothed snap coordinate — prevents the completed/remaining polyline split point
    /// from jumping with GPS noise, which makes the route overlay look "wanky" while riding.
    /// Alpha 0.35 ≈ ~3 sample window; invisible lag at cycling speed but kills jitter.
    private var smoothedSnapLat: Double = 0
    private var smoothedSnapLon: Double = 0
    private let snapSmoothingAlpha: Double = 0.35

    /// Last segment chosen for route progress — keeps snapping coherent when parallel roads exist.
    private var lastRouteProgressSegmentIndex: Int = 0
    private var routeCumulativeDistances: [Double] = []
    private var lastRenderedSplitSegmentIndex: Int?
    private var offCourseStartedAt: Date?
    private var onCourseRecoveredAt: Date?
    private var lastAutoRerouteAt: Date?
    private let autoRerouteDelay: TimeInterval = 30
    private let rerouteCooldownAfterRecovery: TimeInterval = 10
    private var routeSegmentBreakIndices: Set<Int> = []

    // MARK: - Route Calculation

    /// Calculate cycling directions from current location to a destination.
    func calculateRoute(from origin: CLLocationCoordinate2D, to mapItem: MKMapItem) async {
        isCalculating = true
        lastError = nil
        lastRouteFailureKind = nil

        let request = MKDirections.Request()
        request.source = MKMapItem(
            location: CLLocation(latitude: origin.latitude, longitude: origin.longitude),
            address: nil
        )
        request.destination = mapItem
        request.transportType = .cycling
        request.requestsAlternateRoutes = false

        do {
            let directions = MKDirections(request: request)
            let response = try await directions.calculate()

            guard let route = response.routes.first else {
                lastError = "No cycling route found."
                lastRouteFailureKind = .noRoute
                isCalculating = false
                return
            }

            self.currentRoute = route
            self.destination = mapItem
            self.routeDistance = route.distance
            self.estimatedTimeRemaining = route.expectedTravelTime
            self.routeName = mapItem.name ?? "Destination"

            // Extract polyline coordinates
            let pointCount = route.polyline.pointCount
            let points = route.polyline.points()
            var coords: [CLLocationCoordinate2D] = []
            for i in 0..<pointCount {
                coords.append(points[i].coordinate)
            }
            self.routePolyline = coords
            self.routeSegmentBreakIndices = []
            resetRouteProgressPolylines()
            lookaheadPolylines = []
            snapBackPolyline = []

            // Extract turn-by-turn steps
            self.allRouteSteps = route.steps.filter { !$0.instructions.isEmpty }
            self.completedStepIndices = []
            resetNavigationCueState()
            updateTurnInstructions(userLocation: nil)

            self.mode = .turnByTurn
            self.isOffCourse = false
            self.deviationDistance = 0

            isCalculating = false
            logger.info("Route calculated: \(route.distance)m, \(self.allRouteSteps.count) steps")

        } catch {
            let failureKind = Self.classifyRouteCalculationError(error)
            lastRouteFailureKind = failureKind
            switch failureKind {
            case .offline:
                lastError = "Offline right now. Check your connection and try again."
            case .noRoute:
                lastError = "No cycling route found."
            case .unknown:
                lastError = "Route calculation failed: \(error.localizedDescription)"
            }
            isCalculating = false
            logger.error("Route calculation failed: \(error.localizedDescription)")
        }
    }

    /// Load a GPX route for following (no turn-by-turn, just off-course detection).
    func followGPXRoute(points: [CLLocationCoordinate2D], name: String?, segmentBreakIndices: [Int] = []) {
        routePolyline = points
        routeSegmentBreakIndices = Set(segmentBreakIndices)
        resetRouteProgressPolylines()
        lookaheadPolylines = []
        snapBackPolyline = []
        routeName = name ?? "GPX Route"
        routeDistance = Self.totalDistance(for: points, segmentBreakIndices: routeSegmentBreakIndices)
        mode = .followRoute
        isOffCourse = false
        deviationDistance = 0
        nextTurn = nil
        upcomingTurn = nil
        remainingSteps = []
        currentRoute = nil
        followRouteHint = nil
        distanceToNextManeuver = 0
        resetNavigationCueState()
        announcedGPXCornerVertex = nil
        previousGPXHintDistance = .greatestFiniteMagnitude
    }

    /// Clear navigation and return to free ride.
    func clearNavigation() {
        mode = .freeRide
        routePolyline = []
        completedRoutePolylines = []
        remainingRoutePolylines = []
        routeName = nil
        routeDistance = 0
        estimatedTimeRemaining = 0
        nextTurn = nil
        upcomingTurn = nil
        remainingSteps = []
        isOffCourse = false
        deviationDistance = 0
        distanceToNextManeuver = 0
        followRouteHint = nil
        destination = nil
        currentRoute = nil
        allRouteSteps = []
        completedStepIndices = []
        resetNavigationCueState()
        lookaheadPolylines = []
        snapBackPolyline = []
        distanceAlongRouteMeters = 0
        announcedGPXCornerVertex = nil
        previousGPXHintDistance = .greatestFiniteMagnitude
        lastRouteProgressSegmentIndex = 0
        routeSegmentBreakIndices = []
        lastRouteFailureKind = nil
    }

    nonisolated static func classifyRouteCalculationError(_ error: Error) -> RouteCalculationFailureKind {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, Self.offlineURLCodes.contains(nsError.code) {
            return .offline
        }

        if nsError.domain == MKError.errorDomain,
            nsError.code >= 0,
            let mkCode = MKError.Code(rawValue: UInt(nsError.code))
        {
            switch mkCode {
            case .serverFailure:
                return .offline
            case .directionsNotFound, .placemarkNotFound:
                return .noRoute
            default:
                break
            }
        }

        return .unknown
    }

    nonisolated private static let offlineURLCodes: Set<Int> = [
        NSURLErrorNotConnectedToInternet,
        NSURLErrorNetworkConnectionLost,
        NSURLErrorTimedOut,
        NSURLErrorCannotFindHost,
        NSURLErrorCannotConnectToHost,
        NSURLErrorDNSLookupFailed,
        NSURLErrorDataNotAllowed,
        NSURLErrorInternationalRoamingOff
    ]

    // MARK: - Live Update

    /// Call this with each new GPS position to update navigation state.
    func updatePosition(_ location: CLLocation) {
        guard mode != .freeRide else { return }

        updateRouteProgressPolyline(at: location.coordinate, horizontalAccuracy: location.horizontalAccuracy)
        handleAutoRerouteIfNeeded(from: location.coordinate)

        if mode == .turnByTurn {
            updateTurnProgress(location: location)
        } else if mode == .followRoute {
            updateFollowRouteHints(location: location)
        }
    }

    // MARK: - Re-route

    /// Recalculate route from current position (when off course).
    func reroute(from coordinate: CLLocationCoordinate2D) async {
        guard let dest = destination else { return }
        await calculateRoute(from: coordinate, to: dest)
    }

    // MARK: - Private Helpers

    private func resetNavigationCueState() {
        lastAnnouncedTurnStepIndex = nil
        previousDistanceToManeuver = .greatestFiniteMagnitude
    }

    private func resetRouteProgressPolylines() {
        completedRoutePolylines = []
        remainingRoutePolylines = Self.segmentedPolylines(for: routePolyline, breaks: routeSegmentBreakIndices)
        distanceAlongRouteMeters = 0
        smoothedSnapLat = 0
        smoothedSnapLon = 0
        lastRouteProgressSegmentIndex = 0
        routeCumulativeDistances = Self.makeCumulativeDistances(for: routePolyline, segmentBreakIndices: routeSegmentBreakIndices)
        lastRenderedSplitSegmentIndex = nil
        offCourseStartedAt = nil
        onCourseRecoveredAt = nil
        lastAutoRerouteAt = nil
    }

    private func routeLengthCapMeters() -> Double {
        if routeDistance > 0 { return routeDistance }
        return Self.totalDistance(for: routePolyline, segmentBreakIndices: routeSegmentBreakIndices)
    }

    private func isSegmentBreak(after pointIndex: Int) -> Bool {
        routeSegmentBreakIndices.contains(pointIndex)
    }

    /// Perpendicular distance to route, distance along polyline to snap point, snap coordinate, and segment index `[i, i+1]` for that snap.
    /// Uses a local window around the last segment when GPS is noisy so the rider doesn’t “jump” to a parallel street.
    private func routeProximityMetrics(for coordinate: CLLocationCoordinate2D) -> (deviation: Double, along: Double, snap: CLLocationCoordinate2D, segmentIndex: Int) {
        guard routePolyline.count > 1 else {
            return (0, 0, coordinate, 0)
        }

        if routePolyline.count > 2 {
            let lastSeg = routePolyline.count - 2
            let lo = max(0, lastRouteProgressSegmentIndex - 2)
            let hi = min(lastSeg, lastRouteProgressSegmentIndex + 14)
            if lo <= hi {
                let window = bestProximityOnSegmentRange(for: coordinate, segmentStart: lo, segmentEnd: hi)
                if window.deviation < 48 {
                    lastRouteProgressSegmentIndex = window.segmentIndex
                    return window
                }
            }
        }

        // Fallback: bounded scan around last known position (±200 segments)
        // instead of full O(n) scan that blocks the main thread on long routes.
        let lastSeg = routePolyline.count - 2
        let fallbackLo = max(0, lastRouteProgressSegmentIndex - 200)
        let fallbackHi = min(lastSeg, lastRouteProgressSegmentIndex + 200)
        let fallback = bestProximityOnSegmentRange(for: coordinate, segmentStart: fallbackLo, segmentEnd: fallbackHi)
        if fallback.deviation < 48 {
            lastRouteProgressSegmentIndex = fallback.segmentIndex
            return fallback
        }

        // Still no match — declare off-course rather than scanning the entire route
        lastRouteProgressSegmentIndex = fallback.segmentIndex
        return fallback
    }

    private func bestProximityOnSegmentRange(
        for coordinate: CLLocationCoordinate2D,
        segmentStart: Int,
        segmentEnd: Int
    ) -> (deviation: Double, along: Double, snap: CLLocationCoordinate2D, segmentIndex: Int) {
        guard routePolyline.count > 1 else {
            return (0, 0, coordinate, 0)
        }
        let s = max(0, segmentStart)
        let e = min(routePolyline.count - 2, segmentEnd)
        guard s <= e else {
            return (0, 0, coordinate, 0)
        }

        var cumulative = routeCumulativeDistances.indices.contains(s) ? routeCumulativeDistances[s] : 0

        var bestDev = Double.greatestFiniteMagnitude
        var bestAlong: Double = 0
        var bestSnap = routePolyline[s]
        var bestSegmentIndex = s

        for i in s...e {
            let a = routePolyline[i]
            let b = routePolyline[i + 1]
            guard !isSegmentBreak(after: i) else { continue }
            let segLen = a.distanceTo(b)
            let dev = perpendicularDistance(point: coordinate, lineStart: a, lineEnd: b)
            let snap = projectPointOntoSegment(point: coordinate, lineStart: a, lineEnd: b)
            let along = cumulative + a.distanceTo(snap)
            if dev < bestDev {
                bestDev = dev
                bestAlong = along
                bestSnap = snap
                bestSegmentIndex = i
            }
            cumulative += segLen
        }
        return (bestDev, bestAlong, bestSnap, bestSegmentIndex)
    }

    private let routeVertexEpsilonMeters: Double = 0.35

    /// Builds traversed vs remaining polylines using the perpendicular snap point on the route (not nearest vertex).
    private func buildCompletedRemainingFromSnap(segmentIndex: Int, snap: CLLocationCoordinate2D) -> (completed: [[CLLocationCoordinate2D]], remaining: [[CLLocationCoordinate2D]]) {
        guard routePolyline.count > 1 else { return ([], []) }
        let segIdx = min(max(0, segmentIndex), routePolyline.count - 2)

        var completedSegments: [[CLLocationCoordinate2D]] = []
        var completed: [CLLocationCoordinate2D] = []
        for j in 0...segIdx {
            completed.append(routePolyline[j])
            if isSegmentBreak(after: j) {
                if completed.count > 1 {
                    completedSegments.append(completed)
                }
                completed = []
            }
        }
        if let last = completed.last, last.distanceTo(snap) > routeVertexEpsilonMeters {
            completed.append(snap)
        }
        if completed.count > 1 {
            completedSegments.append(completed)
        }

        var remainingSegments: [[CLLocationCoordinate2D]] = []
        var remaining: [CLLocationCoordinate2D] = [snap]
        for j in (segIdx + 1)..<routePolyline.count {
            let v = routePolyline[j]
            if remaining.isEmpty {
                remaining = [v]
            } else if remaining.last!.distanceTo(v) > routeVertexEpsilonMeters {
                remaining.append(v)
            }
            if isSegmentBreak(after: j) {
                if remaining.count > 1 {
                    remainingSegments.append(remaining)
                }
                remaining = []
            }
        }
        if remaining.count > 1 {
            remainingSegments.append(remaining)
        }
        return (completedSegments, remainingSegments)
    }

    /// Lookahead along the remaining route starting from the snap (300 m default in call sites).
    private func lookaheadAlongRoute(fromSnap snap: CLLocationCoordinate2D, startSegmentIndex: Int, targetDistance: Double) -> [[CLLocationCoordinate2D]] {
        guard routePolyline.count > 1, startSegmentIndex < routePolyline.count - 1 else { return [] }
        var segments: [[CLLocationCoordinate2D]] = []
        var result: [CLLocationCoordinate2D] = [snap]
        var accumulated: Double = 0

        let firstVertex = routePolyline[startSegmentIndex + 1]
        let d0 = snap.distanceTo(firstVertex)
        accumulated += d0
        result.append(firstVertex)
        if isSegmentBreak(after: startSegmentIndex) {
            if result.count > 1 {
                segments.append(result)
            }
            result = []
        }
        if accumulated >= targetDistance {
            if result.count > 1 {
                segments.append(result)
            }
            return segments
        }

        var i = startSegmentIndex + 1
        while i < routePolyline.count - 1 {
            if isSegmentBreak(after: i) {
                if result.count > 1 {
                    segments.append(result)
                }
                result = [routePolyline[i + 1]]
                i += 1
                continue
            }
            let segDist = routePolyline[i].distanceTo(routePolyline[i + 1])
            accumulated += segDist
            result.append(routePolyline[i + 1])
            i += 1
            if accumulated >= targetDistance { break }
        }
        if result.count > 1 {
            segments.append(result)
        }
        return segments
    }

    /// Splits the route into completed (traversed) vs remaining for map styling.
    private func updateRouteProgressPolyline(at coordinate: CLLocationCoordinate2D, horizontalAccuracy: Double) {
        guard routePolyline.count > 1 else {
            completedRoutePolylines = []
            remainingRoutePolylines = []
            lookaheadPolylines = []
            snapBackPolyline = []
            distanceAlongRouteMeters = 0
            deviationDistance = 0
            return
        }

        let metrics = routeProximityMetrics(for: coordinate)

        deviationDistance = metrics.deviation
        let cap = routeLengthCapMeters()
        let along = max(0, metrics.along)
        distanceAlongRouteMeters = cap > 0 ? min(along, cap) : along

        // GPS error often projects a few metres off the road centre; subtract part of the reported accuracy
        // so brief urban drift doesn’t flip “off course” while you’re still on the same street.
        let hAcc = max(5, horizontalAccuracy >= 0 ? horizontalAccuracy : 20)
        let effectiveDeviation = max(0, metrics.deviation - 0.45 * hAcc)
        let dynamicThreshold = offCourseThreshold + min(max(0, hAcc - 12) * 0.35, 12)

        let wasOffCourse = isOffCourse
        isOffCourse = effectiveDeviation > dynamicThreshold

        if isOffCourse && !wasOffCourse {
            logger.info("Rider went off course. Raw deviation: \(metrics.deviation)m, effective: \(effectiveDeviation)m, hAcc: \(hAcc)m")
        }

        // Smooth the snap coordinate to prevent the polyline split point from jumping
        // with GPS noise on each update. Metrics (distance, off-course) use the raw snap
        // for accuracy; only the visual split uses the smoothed version.
        if smoothedSnapLat == 0 {
            smoothedSnapLat = metrics.snap.latitude
            smoothedSnapLon = metrics.snap.longitude
        } else {
            let α = snapSmoothingAlpha
            smoothedSnapLat = α * metrics.snap.latitude  + (1 - α) * smoothedSnapLat
            smoothedSnapLon = α * metrics.snap.longitude + (1 - α) * smoothedSnapLon
        }
        let visualSnap = CLLocationCoordinate2D(latitude: smoothedSnapLat, longitude: smoothedSnapLon)

        if lastRenderedSplitSegmentIndex != metrics.segmentIndex || completedRoutePolylines.isEmpty || remainingRoutePolylines.isEmpty {
            let split = buildCompletedRemainingFromSnap(segmentIndex: metrics.segmentIndex, snap: visualSnap)
            completedRoutePolylines = split.completed
            remainingRoutePolylines = split.remaining
            lastRenderedSplitSegmentIndex = metrics.segmentIndex
        }

        // Lookahead ghost — 300m of remaining route ahead of snap point
        lookaheadPolylines = lookaheadAlongRoute(
            fromSnap: metrics.snap,
            startSegmentIndex: metrics.segmentIndex,
            targetDistance: 300
        )

        // Snap-back line — perpendicular snap point on the polyline (not just a vertex)
        if isOffCourse {
            snapBackPolyline = [coordinate, metrics.snap]
        } else {
            snapBackPolyline = []
        }
    }

    private func handleAutoRerouteIfNeeded(from coordinate: CLLocationCoordinate2D) {
        guard mode == .turnByTurn, destination != nil else {
            offCourseStartedAt = nil
            onCourseRecoveredAt = nil
            return
        }

        guard isOffCourse else {
            if onCourseRecoveredAt == nil {
                onCourseRecoveredAt = Date()
            }
            offCourseStartedAt = nil
            return
        }

        if let onCourseRecoveredAt,
            Date().timeIntervalSince(onCourseRecoveredAt) < rerouteCooldownAfterRecovery
        {
            return
        }

        onCourseRecoveredAt = nil

        if offCourseStartedAt == nil {
            offCourseStartedAt = Date()
            return
        }

        guard let offCourseStartedAt else { return }
        guard Date().timeIntervalSince(offCourseStartedAt) >= autoRerouteDelay else { return }
        guard !isCalculating else { return }

        if let lastAutoRerouteAt, Date().timeIntervalSince(lastAutoRerouteAt) < autoRerouteDelay {
            return
        }

        lastAutoRerouteAt = Date()
        Task { @MainActor [weak self] in
            await self?.reroute(from: coordinate)
        }
    }

    private func distanceToStepEnd(step: MKRoute.Step, userLocation: CLLocation?) -> CLLocationDistance {
        let stepPoints = step.polyline.points()
        let stepPointCount = step.polyline.pointCount
        guard stepPointCount > 0 else { return step.distance }
        let endpoint = stepPoints[stepPointCount - 1].coordinate
        if let loc = userLocation {
            return loc.distance(from: CLLocation(latitude: endpoint.latitude, longitude: endpoint.longitude))
        }
        return step.distance
    }

    private func updateTurnInstructions(userLocation: CLLocation?) {
        let remaining = allRouteSteps.enumerated().filter { !completedStepIndices.contains($0.offset) }

        self.remainingSteps = remaining.map { index, step in
            TurnInstruction(
                stepIndex: index,
                instruction: step.instructions,
                distance: distanceToStepEnd(step: step, userLocation: userLocation),
                symbol: symbolForStep(step)
            )
        }

        self.nextTurn = remainingSteps.first
        self.upcomingTurn = remainingSteps.count > 1 ? remainingSteps[1] : nil
        self.distanceToNextManeuver = nextTurn?.distance ?? 0
    }

    private func updateTurnProgress(location: CLLocation) {
        // Mark steps as completed when rider is near the step's endpoint
        for (index, step) in allRouteSteps.enumerated() {
            guard !completedStepIndices.contains(index) else { continue }

            // Use the step polyline's last point as the "completion zone"
            let stepPoints = step.polyline.points()
            let stepPointCount = step.polyline.pointCount
            guard stepPointCount > 0 else { continue }

            let endpoint = stepPoints[stepPointCount - 1].coordinate
            let dist = location.coordinate.distanceTo(endpoint)

            if dist < 30 { // within 30m of step endpoint
                completedStepIndices.insert(index)
            }
        }

        updateTurnInstructions(userLocation: location)
        processTurnByTurnCues()

        // Update ETA — use projection-based distance along route
        if let route = currentRoute, distanceAlongRouteMeters > 0 {
            let fraction = min(1, distanceAlongRouteMeters / route.distance)
            estimatedTimeRemaining = route.expectedTravelTime * (1 - fraction)
        }
    }

    private func processTurnByTurnCues() {
        guard RidePreferences.shared.navigationTurnCuesEnabled else { return }
        guard let turn = nextTurn else {
            previousDistanceToManeuver = .greatestFiniteMagnitude
            return
        }

        let d = turn.distance
        let idx = turn.stepIndex

        if lastAnnouncedTurnStepIndex != idx {
            lastAnnouncedTurnStepIndex = idx
            previousDistanceToManeuver = d
            HapticManager.shared.navigationPrimary()
            return
        }

        if previousDistanceToManeuver > 200 && d <= 200 && d > 35 {
            HapticManager.shared.navigationAdvance()
        } else if previousDistanceToManeuver > 50 && d <= 50 && d > 8 {
            HapticManager.shared.navigationImmediate()
        }
        previousDistanceToManeuver = d
    }

    /// Sharp-corner hints along a loaded GPX polyline (bearing change at vertices).
    private func updateFollowRouteHints(location: CLLocation) {
        followRouteHint = nil
        guard routePolyline.count > 2 else {
            previousGPXHintDistance = .greatestFiniteMagnitude
            announcedGPXCornerVertex = nil
            return
        }

        guard let corner = nextSharpCorner(
            from: location.coordinate,
            polyline: routePolyline,
            minBendDegrees: 38,
            maxLookaheadVertices: 55
        ) else {
            previousGPXHintDistance = .greatestFiniteMagnitude
            announcedGPXCornerVertex = nil
            return
        }

        let hint = TurnInstruction(
            stepIndex: -corner.vertexIndex,
            instruction: corner.angleDegrees >= 55 ? "Sharp bend ahead" : "Turn ahead",
            distance: corner.distanceMeters,
            symbol: "arrow.turn.up.right"
        )
        followRouteHint = hint

        guard RidePreferences.shared.navigationTurnCuesEnabled else { return }

        let d = corner.distanceMeters
        if announcedGPXCornerVertex != corner.vertexIndex {
            announcedGPXCornerVertex = corner.vertexIndex
            previousGPXHintDistance = d
            HapticManager.shared.navigationPrimary()
            return
        }

        if previousGPXHintDistance > 120 && d <= 120 && d > 28 {
            HapticManager.shared.navigationAdvance()
        } else if previousGPXHintDistance > 45 && d <= 45 && d > 10 {
            HapticManager.shared.navigationImmediate()
        }
        previousGPXHintDistance = d
    }

    private struct SharpCorner {
        let vertexIndex: Int
        let distanceMeters: Double
        let angleDegrees: Double
    }

    /// Finds the next significant bend ahead of the rider along the polyline.
    private func nextSharpCorner(
        from coordinate: CLLocationCoordinate2D,
        polyline: [CLLocationCoordinate2D],
        minBendDegrees: Double,
        maxLookaheadVertices: Int
    ) -> SharpCorner? {
        guard let (closestSeg, _) = closestSegmentIndex(to: coordinate, on: polyline) else { return nil }
        let start = min(closestSeg, polyline.count - 2)
        let upperIndex = min(polyline.count - 2, start + maxLookaheadVertices)
        guard upperIndex >= start + 1 else { return nil }

        var best: SharpCorner?
        for i in (start + 1)...upperIndex {
            let angle = bendAngleDegrees(at: i, polyline: polyline)
            guard angle >= minBendDegrees else { continue }

            let dist = distanceAlongPolyline(fromSegment: closestSeg, toVertex: i, polyline: polyline, userCoord: coordinate)
            guard dist > 12, dist < 900 else { continue }

            if best == nil || dist < best!.distanceMeters {
                best = SharpCorner(vertexIndex: i, distanceMeters: dist, angleDegrees: angle)
            }
        }
        return best
    }

    private func closestSegmentIndex(to coordinate: CLLocationCoordinate2D, on polyline: [CLLocationCoordinate2D]) -> (Int, Double)? {
        guard polyline.count > 1 else { return nil }
        var bestI = 0
        var bestD = Double.greatestFiniteMagnitude
        for i in 0..<(polyline.count - 1) {
            guard !routeSegmentBreakIndices.contains(i) else { continue }
            let d = perpendicularDistance(point: coordinate, lineStart: polyline[i], lineEnd: polyline[i + 1])
            if d < bestD {
                bestD = d
                bestI = i
            }
        }
        return (bestI, bestD)
    }

    private func distanceAlongPolyline(
        fromSegment closestSeg: Int,
        toVertex targetVertex: Int,
        polyline: [CLLocationCoordinate2D],
        userCoord: CLLocationCoordinate2D
    ) -> Double {
        guard targetVertex > closestSeg, targetVertex < polyline.count else { return 0 }

        let a = polyline[closestSeg]
        let b = polyline[closestSeg + 1]
        let projected = projectPointOntoSegment(point: userCoord, lineStart: a, lineEnd: b)

        var total = userCoord.distanceTo(projected)
        for j in closestSeg..<targetVertex {
            guard !routeSegmentBreakIndices.contains(j) else { continue }
            total += polyline[j].distanceTo(polyline[j + 1])
        }
        return total
    }

    private func projectPointOntoSegment(
        point: CLLocationCoordinate2D,
        lineStart: CLLocationCoordinate2D,
        lineEnd: CLLocationCoordinate2D
    ) -> CLLocationCoordinate2D {
        let dx = lineEnd.longitude - lineStart.longitude
        let dy = lineEnd.latitude - lineStart.latitude
        let len2 = dx * dx + dy * dy
        guard len2 > 1e-18 else { return lineStart }
        let t = ((point.longitude - lineStart.longitude) * dx + (point.latitude - lineStart.latitude) * dy) / len2
        let clamped = max(0, min(1, t))
        return CLLocationCoordinate2D(
            latitude: lineStart.latitude + clamped * dy,
            longitude: lineStart.longitude + clamped * dx
        )
    }

    private func bendAngleDegrees(at index: Int, polyline: [CLLocationCoordinate2D]) -> Double {
        guard index > 0, index < polyline.count - 1 else { return 0 }
        let a = polyline[index - 1]
        let b = polyline[index]
        let c = polyline[index + 1]
        let bearing1 = atan2(b.longitude - a.longitude, b.latitude - a.latitude)
        let bearing2 = atan2(c.longitude - b.longitude, c.latitude - b.latitude)
        var diff = abs(bearing2 - bearing1)
        if diff > .pi { diff = 2 * .pi - diff }
        return diff * 180 / .pi
    }

    private func symbolForStep(_ step: MKRoute.Step) -> String {
        let instructions = step.instructions.lowercased()

        if instructions.contains("left") && instructions.contains("slight") {
            return "arrow.turn.up.left"
        }
        if instructions.contains("right") && instructions.contains("slight") {
            return "arrow.turn.up.right"
        }
        if instructions.contains("left") {
            return "arrow.turn.up.left"
        }
        if instructions.contains("right") {
            return "arrow.turn.up.right"
        }
        if instructions.contains("u-turn") || instructions.contains("u turn") {
            return "arrow.uturn.down"
        }
        if instructions.contains("straight") || instructions.contains("continue") {
            return "arrow.up"
        }
        if instructions.contains("arrive") || instructions.contains("destination") {
            return "flag.checkered"
        }
        if instructions.contains("roundabout") {
            return "arrow.triangle.turn.up.right.circle"
        }

        return "arrow.up"
    }

    /// Find the nearest distance from a point to a polyline.
    private func nearestDistance(from point: CLLocationCoordinate2D, to polyline: [CLLocationCoordinate2D]) -> Double {
        guard polyline.count > 1 else {
            guard let first = polyline.first else { return .greatestFiniteMagnitude }
            return point.distanceTo(first)
        }

        var minDist = Double.greatestFiniteMagnitude

        for i in 1..<polyline.count {
            let dist = perpendicularDistance(point: point, lineStart: polyline[i - 1], lineEnd: polyline[i])
            minDist = min(minDist, dist)
        }

        return minDist
    }

    /// Perpendicular distance from a point to a line segment.
    private func perpendicularDistance(
        point: CLLocationCoordinate2D,
        lineStart: CLLocationCoordinate2D,
        lineEnd: CLLocationCoordinate2D
    ) -> Double {
        let ax = lineStart.longitude
        let ay = lineStart.latitude
        let bx = lineEnd.longitude
        let by = lineEnd.latitude
        let px = point.longitude
        let py = point.latitude

        let dx = bx - ax
        let dy = by - ay
        let len2 = dx * dx + dy * dy
        guard len2 > 1e-18 else { return point.distanceTo(lineStart) }

        let t = ((px - ax) * dx + (py - ay) * dy) / len2
        if t <= 0 { return point.distanceTo(lineStart) }
        if t >= 1 { return point.distanceTo(lineEnd) }

        let projected = CLLocationCoordinate2D(
            latitude: ay + t * dy,
            longitude: ax + t * dx
        )
        return point.distanceTo(projected)
    }

    private static func totalDistance(for points: [CLLocationCoordinate2D], segmentBreakIndices: Set<Int> = []) -> CLLocationDistance {
        guard points.count > 1 else { return 0 }
        var total: CLLocationDistance = 0
        for i in 1..<points.count {
            guard !segmentBreakIndices.contains(i - 1) else { continue }
            total += points[i - 1].distanceTo(points[i])
        }
        return total
    }

    private static func makeCumulativeDistances(for points: [CLLocationCoordinate2D], segmentBreakIndices: Set<Int> = []) -> [Double] {
        guard !points.isEmpty else { return [] }
        var cumulative = Array(repeating: 0.0, count: points.count)
        guard points.count > 1 else { return cumulative }
        for i in 1..<points.count {
            let stepDistance = segmentBreakIndices.contains(i - 1) ? 0 : points[i - 1].distanceTo(points[i])
            cumulative[i] = cumulative[i - 1] + stepDistance
        }
        return cumulative
    }

    private static func segmentedPolylines(for points: [CLLocationCoordinate2D], breaks: Set<Int>) -> [[CLLocationCoordinate2D]] {
        guard !points.isEmpty else { return [] }
        var polylines: [[CLLocationCoordinate2D]] = []
        var current: [CLLocationCoordinate2D] = [points[0]]

        for index in 1..<points.count {
            if breaks.contains(index - 1) {
                if current.count > 1 {
                    polylines.append(current)
                }
                current = [points[index]]
            } else {
                current.append(points[index])
            }
        }

        if current.count > 1 {
            polylines.append(current)
        }
        return polylines
    }
}

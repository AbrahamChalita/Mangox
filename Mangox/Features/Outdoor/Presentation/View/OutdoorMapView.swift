import CoreLocation
import MapKit
import SwiftUI

/// All map content prepared for `OutdoorMapView`.
///
/// The expensive polyline sanitization, identity hashing, and render budgeting are
/// computed off the main actor by `OutdoorMapRenderBuilder`; the view receives this
/// value-ready struct and only lays out `MapPolyline` / `Annotation` / `Marker` content.
struct OutdoorMapRenderData: Equatable {
    struct BreadcrumbChunk: Equatable, Identifiable {
        let id: UUID
        let coords: [CLLocationCoordinate2D]
        let avgSpeed: Double

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.id == rhs.id
                && lhs.avgSpeed == rhs.avgSpeed
                && lhs.coords.elementsEqual(rhs.coords) {
                    $0.latitude == $1.latitude && $0.longitude == $1.longitude
                }
        }
    }

    struct RoutePolyline: Equatable, Identifiable {
        let id: Int
        let coords: [CLLocationCoordinate2D]

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.id == rhs.id
                && lhs.coords.elementsEqual(rhs.coords) {
                    $0.latitude == $1.latitude && $0.longitude == $1.longitude
                }
        }
    }

    struct IdentifiedCoordinate: Equatable, Identifiable {
        let id: Int
        let coordinate: CLLocationCoordinate2D

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.id == rhs.id
                && lhs.coordinate.latitude == rhs.coordinate.latitude
                && lhs.coordinate.longitude == rhs.coordinate.longitude
        }
    }

    struct Waypoint: Equatable, Identifiable {
        let id: Int
        let labelIndex: Int
        let coordinate: CLLocationCoordinate2D

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.id == rhs.id
                && lhs.labelIndex == rhs.labelIndex
                && lhs.coordinate.latitude == rhs.coordinate.latitude
                && lhs.coordinate.longitude == rhs.coordinate.longitude
        }
    }

    struct Destination: Equatable {
        let name: String
        let coordinate: CLLocationCoordinate2D

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.name == rhs.name
                && lhs.coordinate.latitude == rhs.coordinate.latitude
                && lhs.coordinate.longitude == rhs.coordinate.longitude
        }
    }

    struct Rider: Equatable {
        let coordinate: CLLocationCoordinate2D
        let horizontalAccuracy: Double

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.coordinate.latitude == rhs.coordinate.latitude
                && lhs.coordinate.longitude == rhs.coordinate.longitude
                && lhs.horizontalAccuracy == rhs.horizontalAccuracy
        }
    }

    var breadcrumbChunks: [BreadcrumbChunk] = []
    var liveTail: [CLLocationCoordinate2D] = []
    var completedRoutePolylines: [RoutePolyline] = []
    var remainingRoutePolylines: [RoutePolyline] = []
    var lookaheadPolylines: [RoutePolyline] = []
    var pauseGapCoordinates: [IdentifiedCoordinate] = []
    var waypoints: [Waypoint] = []
    var snapBackPolyline: [CLLocationCoordinate2D] = []
    var destination: Destination?
    var rider: Rider?
    var breadcrumbLineWidth: CGFloat = 3
    var routeLineWidth: CGFloat = 3

    static let empty = OutdoorMapRenderData()
}

extension OutdoorMapRenderData {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.breadcrumbChunks == rhs.breadcrumbChunks
            && lhs.liveTail.elementsEqual(rhs.liveTail) {
                $0.latitude == $1.latitude && $0.longitude == $1.longitude
            }
            && lhs.completedRoutePolylines == rhs.completedRoutePolylines
            && lhs.remainingRoutePolylines == rhs.remainingRoutePolylines
            && lhs.lookaheadPolylines == rhs.lookaheadPolylines
            && lhs.pauseGapCoordinates == rhs.pauseGapCoordinates
            && lhs.waypoints == rhs.waypoints
            && lhs.snapBackPolyline.elementsEqual(rhs.snapBackPolyline) {
                $0.latitude == $1.latitude && $0.longitude == $1.longitude
            }
            && lhs.destination == rhs.destination
            && lhs.rider == rhs.rider
            && lhs.breadcrumbLineWidth == rhs.breadcrumbLineWidth
            && lhs.routeLineWidth == rhs.routeLineWidth
    }
}

/// Builds `OutdoorMapRenderData` on a background actor so the dashboard view body
/// never performs polyline sanitization or render budgeting on the main thread.
actor OutdoorMapRenderBuilder {
    func build(
        isRenderingEnabled: Bool,
        cameraDistance: CLLocationDistance,
        frozenChunks: [BreadcrumbChunk],
        liveTail: [CLLocationCoordinate2D],
        pauseGaps: [CLLocationCoordinate2D],
        completedPolylines: [[CLLocationCoordinate2D]],
        remainingPolylines: [[CLLocationCoordinate2D]],
        lookaheadPolylines: [[CLLocationCoordinate2D]],
        snapBackPolyline: [CLLocationCoordinate2D],
        destination: OutdoorMapRenderData.Destination?,
        waypoints: [CLLocationCoordinate2D],
        currentCoordinate: CLLocationCoordinate2D?,
        smoothedRiderCoordinate: CLLocationCoordinate2D,
        isFollowingUser: Bool,
        horizontalAccuracy: Double
    ) -> OutdoorMapRenderData {
        let budgetBucket = Self.budgetBucket(for: cameraDistance)
        let breadcrumbWidth = Self.breadcrumbLineWidth(for: cameraDistance)
        let routeWidth = Self.routeLineWidth(for: cameraDistance)
        let breadcrumbBudget = Self.breadcrumbPointBudget(for: budgetBucket)
        let routeBudget = Self.routePointBudget(for: budgetBucket)

        guard isRenderingEnabled else {
            return OutdoorMapRenderData(
                breadcrumbLineWidth: breadcrumbWidth,
                routeLineWidth: routeWidth
            )
        }

        let renderedChunks: [OutdoorMapRenderData.BreadcrumbChunk] = frozenChunks.compactMap { chunk in
            let sanitized = chunk.coords.sanitizedForMapPolyline(maxPoints: breadcrumbBudget)
            guard sanitized.count > 1 else { return nil }
            return OutdoorMapRenderData.BreadcrumbChunk(
                id: chunk.id,
                coords: sanitized,
                avgSpeed: chunk.avgSpeed
            )
        }

        let renderedLiveTail = liveTail.sanitizedForMapPolyline(
            maxPoints: max(160, breadcrumbBudget)
        )

        let completed = completedPolylines.map { polyline in
            OutdoorMapRenderData.RoutePolyline(
                id: Self.polylineIdentity(polyline),
                coords: polyline.sanitizedForMapPolyline(maxPoints: routeBudget)
            )
        }
        let remaining = remainingPolylines.map { polyline in
            OutdoorMapRenderData.RoutePolyline(
                id: Self.polylineIdentity(polyline),
                coords: polyline.sanitizedForMapPolyline(maxPoints: routeBudget)
            )
        }
        let lookahead = lookaheadPolylines.map { polyline in
            OutdoorMapRenderData.RoutePolyline(
                id: Self.polylineIdentity(polyline),
                coords: polyline.sanitizedForMapPolyline(
                    maxPoints: max(90, routeBudget - 40)
                )
            )
        }

        let rider: OutdoorMapRenderData.Rider? = currentCoordinate.map { coord in
            OutdoorMapRenderData.Rider(
                coordinate: isFollowingUser ? smoothedRiderCoordinate : coord,
                horizontalAccuracy: horizontalAccuracy
            )
        }

        return OutdoorMapRenderData(
            breadcrumbChunks: renderedChunks,
            liveTail: renderedLiveTail,
            completedRoutePolylines: completed,
            remainingRoutePolylines: remaining,
            lookaheadPolylines: lookahead,
            pauseGapCoordinates: Self.identifiedCoordinates(pauseGaps),
            waypoints: Self.identifiedWaypoints(waypoints),
            snapBackPolyline: snapBackPolyline,
            destination: destination,
            rider: rider,
            breadcrumbLineWidth: breadcrumbWidth,
            routeLineWidth: routeWidth
        )
    }

    // MARK: - Budgets / line widths

    private static func budgetBucket(for cameraDistance: CLLocationDistance) -> Int {
        switch cameraDistance {
        case ..<450: return 0
        case ..<1_000: return 1
        case ..<2_500: return 2
        default: return 3
        }
    }

    private static func routePointBudget(for bucket: Int) -> Int {
        switch bucket {
        case 0: return 320
        case 1: return 220
        case 2: return 150
        default: return 90
        }
    }

    private static func breadcrumbPointBudget(for bucket: Int) -> Int {
        switch bucket {
        case 0: return 220
        case 1: return 160
        case 2: return 110
        default: return 80
        }
    }

    private static func routeLineWidth(for cameraDistance: CLLocationDistance) -> CGFloat {
        switch cameraDistance {
        case ..<450: return 6
        case ..<1_000: return 5
        case ..<2_500: return 4
        default: return 3
        }
    }

    private static func breadcrumbLineWidth(for cameraDistance: CLLocationDistance) -> CGFloat {
        switch cameraDistance {
        case ..<450: return 5
        case ..<1_000: return 4
        case ..<2_500: return 3.5
        default: return 3
        }
    }

    // MARK: - Identity helpers

    private static func coordinateIdentity(
        _ coordinate: CLLocationCoordinate2D,
        occurrence: Int = 0
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(coordinate.latitude.bitPattern)
        hasher.combine(coordinate.longitude.bitPattern)
        hasher.combine(occurrence)
        return hasher.finalize()
    }

    private static func polylineIdentity(_ polyline: [CLLocationCoordinate2D]) -> Int {
        var hasher = Hasher()
        hasher.combine(polyline.count)
        if let first = polyline.first {
            hasher.combine(first.latitude.bitPattern)
            hasher.combine(first.longitude.bitPattern)
        }
        if polyline.count > 2 {
            let mid = polyline[polyline.count / 2]
            hasher.combine(mid.latitude.bitPattern)
            hasher.combine(mid.longitude.bitPattern)
        }
        if let last = polyline.last {
            hasher.combine(last.latitude.bitPattern)
            hasher.combine(last.longitude.bitPattern)
        }
        return hasher.finalize()
    }

    private struct CoordinateKey: Hashable {
        let lat: UInt64
        let lon: UInt64

        init(_ coordinate: CLLocationCoordinate2D) {
            lat = coordinate.latitude.bitPattern
            lon = coordinate.longitude.bitPattern
        }
    }

    private static func identifiedCoordinates(
        _ coordinates: [CLLocationCoordinate2D]
    ) -> [OutdoorMapRenderData.IdentifiedCoordinate] {
        var occurrenceByCoordinate: [CoordinateKey: Int] = [:]
        return coordinates.map { coordinate in
            let key = CoordinateKey(coordinate)
            let occurrence = occurrenceByCoordinate[key, default: 0]
            occurrenceByCoordinate[key] = occurrence + 1
            return OutdoorMapRenderData.IdentifiedCoordinate(
                id: coordinateIdentity(coordinate, occurrence: occurrence),
                coordinate: coordinate
            )
        }
    }

    private static func identifiedWaypoints(
        _ coordinates: [CLLocationCoordinate2D]
    ) -> [OutdoorMapRenderData.Waypoint] {
        var occurrenceByCoordinate: [CoordinateKey: Int] = [:]
        return coordinates.enumerated().map { index, coordinate in
            let key = CoordinateKey(coordinate)
            let occurrence = occurrenceByCoordinate[key, default: 0]
            occurrenceByCoordinate[key] = occurrence + 1
            return OutdoorMapRenderData.Waypoint(
                id: coordinateIdentity(coordinate, occurrence: occurrence),
                labelIndex: index + 1,
                coordinate: coordinate
            )
        }
    }
}

/// The map portion of the outdoor dashboard, isolated from layout and lifecycle.
struct OutdoorMapView: View {
    @Binding var cameraPosition: MapCameraPosition
    let renderData: OutdoorMapRenderData
    let isHybridMapStyle: Bool
    let isCompact: Bool
    let statsCardHeight: CGFloat
    let restoredRideToastVisible: Bool
    let showFollowResumeChip: Bool
    let isCalculatingRoute: Bool
    let onResumeFollow: () -> Void

    private var mapStyle: MapStyle {
        if isHybridMapStyle {
            return .hybrid(elevation: .realistic, pointsOfInterest: .excludingAll)
        }
        return .standard(elevation: .realistic, emphasis: .muted)
    }

    var body: some View {
        Map(position: $cameraPosition) {
            // Frozen breadcrumb chunks — colour-coded by average speed
            ForEach(renderData.breadcrumbChunks) { chunk in
                MapPolyline(coordinates: chunk.coords)
                    .stroke(speedColor(chunk.avgSpeed), lineWidth: renderData.breadcrumbLineWidth)
            }

            // Live tail — always mango coloured
            if renderData.liveTail.count > 1 {
                MapPolyline(coordinates: renderData.liveTail)
                    .stroke(AppColor.mango, lineWidth: renderData.breadcrumbLineWidth)
            }

            // Route overlay — traversed (grey) vs remaining (yellow)
            ForEach(renderData.completedRoutePolylines) { done in
                if done.coords.count > 1 {
                    MapPolyline(coordinates: done.coords)
                        .stroke(Color.white.opacity(0.35), lineWidth: renderData.routeLineWidth)
                }
            }
            ForEach(renderData.remainingRoutePolylines) { left in
                if left.coords.count > 1 {
                    MapPolyline(coordinates: left.coords)
                        .stroke(AppColor.yellow, lineWidth: renderData.routeLineWidth)
                }
            }

            // Lookahead ghost — dashed white, 300m ahead on remaining route
            ForEach(renderData.lookaheadPolylines) { lookahead in
                if lookahead.coords.count > 1 {
                    MapPolyline(coordinates: lookahead.coords)
                        .stroke(
                            Color.white.opacity(0.45),
                            style: StrokeStyle(
                                lineWidth: max(2, renderData.routeLineWidth - 1),
                                dash: [8, 6]
                            )
                        )
                }
            }

            // Off-course snap-back line — dashed red line to nearest route point
            let snapBack = renderData.snapBackPolyline
            if snapBack.count == 2 {
                MapPolyline(coordinates: snapBack)
                    .stroke(
                        AppColor.red.opacity(0.75),
                        style: StrokeStyle(lineWidth: 2, dash: [5, 5])
                    )
            }

            // Pause gap markers
            ForEach(renderData.pauseGapCoordinates) { coordinate in
                Annotation("", coordinate: coordinate.coordinate) {
                    Circle()
                        .fill(AppColor.yellow.opacity(0.85))
                        .frame(width: 10, height: 10)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                }
            }

            // Rider position — solid circle dot
            if let rider = renderData.rider {
                Annotation("", coordinate: rider.coordinate) {
                    ZStack {
                        if rider.horizontalAccuracy >= 0 {
                            let ring = CGFloat(min(max(rider.horizontalAccuracy, 5), 60))
                            Circle()
                                .fill(AppColor.mango.opacity(0.12))
                                .frame(width: 18 + ring, height: 18 + ring)
                                .overlay(
                                    Circle()
                                        .strokeBorder(AppColor.mango.opacity(0.2), lineWidth: 1)
                                )
                        }

                        Circle()
                            .fill(AppColor.mango)
                            .frame(width: 18, height: 18)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                            .shadow(color: .black.opacity(0.35), radius: 3)
                    }
                }
            }

            // Destination pin
            if let dest = renderData.destination {
                Marker(dest.name, coordinate: dest.coordinate)
                    .tint(AppColor.red)
            }

            // User-placed waypoints
            ForEach(renderData.waypoints) { waypoint in
                Annotation("", coordinate: waypoint.coordinate) {
                    VStack(spacing: 2) {
                        ZStack {
                            Circle()
                                .fill(AppColor.blue)
                                .frame(width: 22, height: 22)
                            Image(systemName: "mappin")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        Text("WP\(waypoint.labelIndex)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(AppColor.blue.opacity(0.85))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .mapStyle(mapStyle)
        .mapControls {}
        .safeAreaPadding(.top, 90)
        .safeAreaPadding(.bottom, isCompact ? statsCardHeight : 0)
        .overlay {
            if restoredRideToastVisible {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.arrow.trianglehead.counterclockwise")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColor.mango)
                        Text("Ride restored from checkpoint")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .mangoxSurface(.mapOverlay, shape: .capsule)
                    .padding(.top, 22)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if showFollowResumeChip {
                VStack {
                    Spacer()
                    Button {
                        onResumeFollow()
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "location.viewfinder")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Resume Follow")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .mangoxSurface(.mapOverlay, shape: .capsule)
                    }
                    .buttonStyle(MangoxPressStyle())
                    .padding(.bottom, isCompact ? statsCardHeight + 14 : 24)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if isCalculatingRoute {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    ProgressView("Building route…")
                        .tint(AppColor.mango)
                        .padding(20)
                        .glassEffect(
                            .regular,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                }
            }
        }
        .frame(minWidth: 1, minHeight: 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Colour for a breadcrumb chunk based on average speed.
    private func speedColor(_ kmh: Double) -> Color {
        switch kmh {
        case ..<10: return Color.white.opacity(0.35)
        case 10..<20: return AppColor.mango
        case 20..<30: return AppColor.yellow
        default: return AppColor.success
        }
    }
}

import Foundation
import CoreLocation
import MapKit

@Observable
final class RouteManager {
    var routeName: String?
    var points: [CLLocationCoordinate2D] = []
    var elevations: [Double?] = []
    var segmentBreakIndices: [Int] = []
    var totalDistance: CLLocationDistance = 0
    private var cachedElevationProfilePoints: [(distance: Double, elevation: Double)]?

    var hasRoute: Bool {
        points.count > 1
    }

    /// Pre-computed (cumulativeDistance, elevation) pairs for the elevation profile strip.
    /// Only includes points with non-nil elevation. Handles non-uniform point spacing correctly.
    var elevationProfilePoints: [(distance: Double, elevation: Double)] {
        if let cachedElevationProfilePoints {
            return cachedElevationProfilePoints
        }
        guard points.count > 1, elevations.count == points.count else { return [] }
        var result: [(distance: Double, elevation: Double)] = []
        var cumDist: Double = 0
        for i in 0..<points.count {
            if i > 0 && !segmentBreakIndices.contains(i - 1) {
                cumDist += points[i - 1].distanceTo(points[i])
            }
            if let ele = elevations[i] {
                result.append((distance: cumDist, elevation: ele))
            }
        }
        cachedElevationProfilePoints = result
        return result
    }

    /// Route split into GPX track segments so map previews do not draw straight bridges across gaps.
    var polylineSegments: [[CLLocationCoordinate2D]] {
        guard !points.isEmpty else { return [] }
        var segments: [[CLLocationCoordinate2D]] = []
        var current: [CLLocationCoordinate2D] = [points[0]]

        for index in 1..<points.count {
            if segmentBreakIndices.contains(index - 1) {
                if current.count > 1 {
                    segments.append(current)
                }
                current = [points[index]]
            } else {
                current.append(points[index])
            }
        }

        if current.count > 1 {
            segments.append(current)
        }
        return segments
    }

    /// Whether the route has elevation data available.
    var hasElevationData: Bool {
        elevations.contains(where: { $0 != nil })
    }

    func clearRoute() {
        routeName = nil
        points = []
        elevations = []
        segmentBreakIndices = []
        totalDistance = 0
        cachedElevationProfilePoints = nil
    }

    /// Loads and parses GPX off the main thread to keep the UI responsive.
    func loadGPX(from url: URL) async throws {
        let didAccessScopedResource = url.startAccessingSecurityScopedResource()
        defer {
            if didAccessScopedResource {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        let defaultName = url.deletingPathExtension().lastPathComponent
        // Yield so the UI can refresh before XML parsing (keeps sheet/importer responsive).
        await Task.yield()
        let parsed = try Self.parseGPXTrackData(data: data, defaultName: defaultName)
        points = parsed.points
        elevations = parsed.elevations
        segmentBreakIndices = parsed.segmentBreakIndices
        totalDistance = Self.computeDistance(for: points, segmentBreakIndices: segmentBreakIndices)
        routeName = parsed.routeName ?? defaultName
        cachedElevationProfilePoints = nil
    }

    private static func parseGPXTrackData(data: Data, defaultName: String) throws -> (points: [CLLocationCoordinate2D], elevations: [Double?], routeName: String?, segmentBreakIndices: [Int]) {
        let parser = XMLParser(data: data)
        let delegate = GPXTrackParserDelegate()
        parser.delegate = delegate

        guard parser.parse() else {
            throw RouteError.invalidGPX
        }

        guard delegate.points.count > 1 else {
            throw RouteError.tooFewPoints
        }

        return (delegate.points, delegate.elevations, delegate.routeName, delegate.segmentBreakIndices)
    }

    func coordinate(forDistance distance: CLLocationDistance) -> CLLocationCoordinate2D? {
        guard points.count > 1 else { return nil }

        if distance <= 0 {
            return points.first
        }

        if distance >= totalDistance {
            return points.last
        }

        var traversed: CLLocationDistance = 0
        for index in 1..<points.count {
            let from = points[index - 1]
            let to = points[index]
            let segmentDistance = segmentBreakIndices.contains(index - 1) ? 0 : from.distanceTo(to)

            if traversed + segmentDistance >= distance {
                let localDistance = distance - traversed
                let ratio = segmentDistance > 0 ? (localDistance / segmentDistance) : 0
                return CLLocationCoordinate2D(
                    latitude: from.latitude + ((to.latitude - from.latitude) * ratio),
                    longitude: from.longitude + ((to.longitude - from.longitude) * ratio)
                )
            }

            traversed += segmentDistance
        }

        return points.last
    }

    /// Interpolates elevation at a given route distance when GPX contains `<ele>` values.
    func elevation(forDistance distance: CLLocationDistance) -> Double? {
        guard points.count > 1, elevations.count == points.count else { return nil }

        if distance <= 0 {
            return elevations.first ?? nil
        }

        if distance >= totalDistance {
            return elevations.last ?? nil
        }

        var traversed: CLLocationDistance = 0
        for index in 1..<points.count {
            let from = points[index - 1]
            let to = points[index]
            let segmentDistance = segmentBreakIndices.contains(index - 1) ? 0 : from.distanceTo(to)

            if traversed + segmentDistance >= distance {
                let localDistance = distance - traversed
                let ratio = segmentDistance > 0 ? (localDistance / segmentDistance) : 0

                let fromElevation = elevations[index - 1]
                let toElevation = elevations[index]

                switch (fromElevation, toElevation) {
                case let (start?, end?):
                    return start + ((end - start) * ratio)
                case let (start?, nil):
                    return start
                case let (nil, end?):
                    return end
                default:
                    return nil
                }
            }

            traversed += segmentDistance
        }

        return elevations.last ?? nil
    }

    /// Total positive elevation gain (meters) if GPX elevation is available.
    var totalElevationGain: Double {
        guard elevations.count == points.count else { return 0 }
        var gain: Double = 0
        var lastKnown: Double?

        for elevation in elevations {
            guard let elevation else { continue }
            if let lastKnown, elevation > lastKnown {
                gain += (elevation - lastKnown)
            }
            lastKnown = elevation
        }

        return gain
    }

    var cameraRegion: MKCoordinateRegion? {
        guard let first = points.first else { return nil }

        var minLat = first.latitude
        var maxLat = first.latitude
        var minLon = first.longitude
        var maxLon = first.longitude

        for point in points {
            minLat = min(minLat, point.latitude)
            maxLat = max(maxLat, point.latitude)
            minLon = min(minLon, point.longitude)
            maxLon = max(maxLon, point.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        let latSpan = max((maxLat - minLat) * 1.3, 0.003)
        let lonSpan = max((maxLon - minLon) * 1.3, 0.003)

        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan)
        )
    }

    private static func computeDistance(for points: [CLLocationCoordinate2D], segmentBreakIndices: [Int]) -> CLLocationDistance {
        guard points.count > 1 else { return 0 }

        var distance: CLLocationDistance = 0
        for index in 1..<points.count {
            guard !segmentBreakIndices.contains(index - 1) else { continue }
            distance += points[index - 1].distanceTo(points[index])
        }
        return distance
    }
}

enum RouteError: LocalizedError {
    case invalidGPX
    case tooFewPoints

    var errorDescription: String? {
        switch self {
        case .invalidGPX:
            return "Unable to read this GPX file."
        case .tooFewPoints:
            return "The route must contain at least two points."
        }
    }
}

private final class GPXTrackParserDelegate: NSObject, XMLParserDelegate {
    private(set) var points: [CLLocationCoordinate2D] = []
    private(set) var elevations: [Double?] = []
    private(set) var routeName: String?
    private(set) var segmentBreakIndices: [Int] = []

    private var currentPointLatitude: Double?
    private var currentPointLongitude: Double?
    private var currentPointElevation: Double?
    private var currentSegmentStartIndex: Int?

    private var collectingElement: String?
    private var textBuffer = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "trkseg" {
            currentSegmentStartIndex = points.count
            return
        }

        if elementName == "trkpt" || elementName == "rtept" {
            guard let latString = attributeDict["lat"],
                  let lonString = attributeDict["lon"],
                  let latitude = Double(latString),
                  let longitude = Double(lonString) else {
                currentPointLatitude = nil
                currentPointLongitude = nil
                currentPointElevation = nil
                return
            }

            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            guard CLLocationCoordinate2DIsValid(coordinate) else {
                currentPointLatitude = nil
                currentPointLongitude = nil
                currentPointElevation = nil
                return
            }

            currentPointLatitude = latitude
            currentPointLongitude = longitude
            currentPointElevation = nil
            return
        }

        if elementName == "ele", currentPointLatitude != nil {
            collectingElement = "ele"
            textBuffer = ""
            return
        }

        // Capture first route/track/display name when available.
        if elementName == "name", routeName == nil, currentPointLatitude == nil {
            collectingElement = "name"
            textBuffer = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard collectingElement != nil else { return }
        textBuffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "ele", collectingElement == "ele" {
            let trimmed = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if let elevation = Double(trimmed) {
                currentPointElevation = elevation
            }
            collectingElement = nil
            textBuffer = ""
            return
        }

        if elementName == "name", collectingElement == "name" {
            let trimmed = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                routeName = trimmed
            }
            collectingElement = nil
            textBuffer = ""
            return
        }

        if elementName == "trkpt" || elementName == "rtept" {
            guard let latitude = currentPointLatitude, let longitude = currentPointLongitude else {
                currentPointLatitude = nil
                currentPointLongitude = nil
                currentPointElevation = nil
                return
            }

            points.append(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
            elevations.append(currentPointElevation)

            currentPointLatitude = nil
            currentPointLongitude = nil
            currentPointElevation = nil
            return
        }

        if elementName == "trkseg" {
            if let currentSegmentStartIndex, points.count - currentSegmentStartIndex > 1 {
                segmentBreakIndices.append(points.count - 1)
            }
            currentSegmentStartIndex = nil
        }
    }
}

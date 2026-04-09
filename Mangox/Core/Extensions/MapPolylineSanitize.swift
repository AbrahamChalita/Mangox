import CoreLocation

extension CLLocationCoordinate2D {
    /// Distance to another coordinate in meters.
    func distanceTo(_ other: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}

extension Array where Element == CLLocationCoordinate2D {
    /// Drops consecutive points closer than `minSeparationMeters` so `MapPolyline` is less likely to hit
    /// MapKit's internal "triangulation" / clip-path failures on degenerate or duplicate segments.
    func sanitizedForMapPolyline(minSeparationMeters: CLLocationDistance = 0.5) -> [CLLocationCoordinate2D] {
        guard count > 1 else { return self }
        var out: [CLLocationCoordinate2D] = []
        out.reserveCapacity(Swift.min(count, 4096))
        for c in self {
            if let last = out.last {
                let d = last.distanceTo(c)
                if d < minSeparationMeters { continue }
            }
            out.append(c)
        }
        if out.count >= 2 { return out }
        return [self[0], self[count - 1]]
    }
}

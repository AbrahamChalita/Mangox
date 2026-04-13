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
    /// Optionally downsamples to `maxPoints` (while preserving endpoints) to keep rendering smooth on long tracks.
    func sanitizedForMapPolyline(
        minSeparationMeters: CLLocationDistance = 0.5,
        maxPoints: Int? = nil
    ) -> [CLLocationCoordinate2D] {
        guard count > 1 else { return self }
        var deduped: [CLLocationCoordinate2D] = []
        deduped.reserveCapacity(Swift.min(count, 4096))
        for c in self {
            if let last = deduped.last {
                let d = last.distanceTo(c)
                if d < minSeparationMeters { continue }
            }
            deduped.append(c)
        }

        let usable: [CLLocationCoordinate2D]
        if deduped.count >= 2 {
            usable = deduped
        } else {
            usable = [self[0], self[count - 1]]
        }

        guard let maxPoints, maxPoints >= 2, usable.count > maxPoints else {
            return usable
        }

        let step = Double(usable.count - 1) / Double(maxPoints - 1)
        var sampled: [CLLocationCoordinate2D] = []
        sampled.reserveCapacity(maxPoints)
        for i in 0..<(maxPoints - 1) {
            let idx = Int((Double(i) * step).rounded(.toNearestOrAwayFromZero))
            sampled.append(usable[Swift.min(Swift.max(0, idx), usable.count - 1)])
        }
        sampled.append(usable[usable.count - 1])
        return sampled
    }
}

import SwiftUI
import CoreLocation

/// A thin elevation-profile strip rendered as a filled Path.
/// Shows the entire route profile with a cursor at the rider's current position.
/// Upcoming steep segments are tinted amber/red.
struct ElevationProfileStripView: View {
    /// Pre-computed (cumulativeDistance, elevation) pairs. Distances in meters.
    /// This correctly handles non-uniformly-spaced GPX points.
    let profilePoints: [(distance: Double, elevation: Double)]
    /// Total route distance in meters.
    let totalDistance: CLLocationDistance
    /// Rider's distance along the route in meters.
    let riderDistance: CLLocationDistance

    private let stripHeight: CGFloat = 52

    // Pre-computed elevation bounds — avoids .min()/.max() on every Canvas redraw
    private let minElevation: Double
    private let maxElevation: Double
    private let elevationRange: Double

    init(profilePoints: [(distance: Double, elevation: Double)], totalDistance: CLLocationDistance, riderDistance: CLLocationDistance) {
        self.profilePoints = profilePoints
        self.totalDistance = totalDistance
        self.riderDistance = riderDistance
        let elevs = profilePoints.map(\.elevation)
        let minE = elevs.min() ?? 0
        let maxE = elevs.max() ?? 0
        self.minElevation = minE
        self.maxElevation = maxE
        self.elevationRange = max(maxE - minE, 10)
    }

    var body: some View {
        Canvas { context, size in
            guard profilePoints.count > 1, totalDistance > 0 else { return }

            let minElev = minElevation
            let elevRange = elevationRange

            let w = size.width
            let h = size.height
            let pad: CGFloat = 4

            func point(_ i: Int) -> CGPoint {
                let frac = profilePoints[i].distance / totalDistance
                let px = frac * w
                let py = pad + (1 - (profilePoints[i].elevation - minElev) / elevRange) * (h - 2 * pad)
                return CGPoint(x: px, y: py)
            }

            // Build filled profile path
            var path = Path()
            path.move(to: CGPoint(x: 0, y: h))
            for i in 0..<profilePoints.count {
                path.addLine(to: point(i))
            }
            path.addLine(to: CGPoint(x: w, y: h))
            path.closeSubpath()

            // Draw profile fill
            context.fill(path, with: .color(.white.opacity(0.10)))

            // Draw profile stroke
            var strokePath = Path()
            strokePath.move(to: point(0))
            for i in 1..<profilePoints.count {
                strokePath.addLine(to: point(i))
            }
            context.stroke(strokePath, with: .color(.white.opacity(0.30)), lineWidth: 1.5)

            // Highlight steep segments (grade > 5%) in amber/red
            for i in 1..<profilePoints.count {
                let hDist = profilePoints[i].distance - profilePoints[i - 1].distance
                guard hDist > 1 else { continue }
                let dy = profilePoints[i].elevation - profilePoints[i - 1].elevation
                let grade = (dy / hDist) * 100
                let segColor: Color
                if grade > 10 { segColor = Color.red.opacity(0.6) }
                else if grade > 5 { segColor = Color.orange.opacity(0.5) }
                else { continue }
                var seg = Path()
                seg.move(to: point(i - 1))
                seg.addLine(to: point(i))
                context.stroke(seg, with: .color(segColor), lineWidth: 2.5)
            }

            // Rider cursor
            let riderFrac = min(1, max(0, riderDistance / totalDistance))
            let cursorX = riderFrac * w
            // Interpolate elevation at rider position using actual distances
            var cursorY: CGFloat = h / 2
            for i in 1..<profilePoints.count {
                if profilePoints[i].distance / totalDistance >= riderFrac {
                    let prevFrac = profilePoints[i - 1].distance / totalDistance
                    let currFrac = profilePoints[i].distance / totalDistance
                    let t = currFrac > prevFrac
                        ? (riderFrac - prevFrac) / (currFrac - prevFrac)
                        : 0
                    let elev = profilePoints[i - 1].elevation + t * (profilePoints[i].elevation - profilePoints[i - 1].elevation)
                    cursorY = pad + CGFloat((1 - (elev - minElev) / elevRange)) * (h - 2 * pad)
                    break
                }
            }
            // Vertical cursor line
            var cursorLine = Path()
            cursorLine.move(to: CGPoint(x: cursorX, y: 0))
            cursorLine.addLine(to: CGPoint(x: cursorX, y: h))
            context.stroke(cursorLine, with: .color(.white.opacity(0.5)), lineWidth: 1)
            // Cursor dot
            let dotRect = CGRect(x: cursorX - 4, y: cursorY - 4, width: 8, height: 8)
            context.fill(Path(ellipseIn: dotRect), with: .color(.white))
        }
        .frame(height: stripHeight)
        .background(Color.black.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}

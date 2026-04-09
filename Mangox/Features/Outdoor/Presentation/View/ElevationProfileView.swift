import SwiftUI

// MARK: - ElevationProfileView

/// A compact elevation profile strip rendered with Canvas for performance.
/// Shows the full route elevation silhouette with a live rider-position indicator.
/// Only rendered when a GPX route with elevation data is loaded.
struct ElevationProfileView: View {
    @Environment(RouteManager.self) private var routeManager

    let currentDistance: Double     // meters — rider's current position
    var height: CGFloat = 72

    // MARK: - Derived

    private var elevations: [Double] {
        routeManager.elevations.compactMap { $0 }
    }

    private var hasElevation: Bool {
        elevations.count > 1
    }

    private var minElevation: Double {
        elevations.min() ?? 0
    }

    private var maxElevation: Double {
        elevations.max() ?? 1
    }

    private var elevationRange: Double {
        max(maxElevation - minElevation, 1)
    }

    private var totalDistance: Double {
        max(routeManager.totalDistance, 1)
    }

    private var riderFraction: Double {
        min(1.0, max(0.0, currentDistance / totalDistance))
    }

    private var currentElevation: Double? {
        routeManager.elevation(forDistance: currentDistance)
    }

    private var totalGain: Int {
        Int(routeManager.totalElevationGain.rounded())
    }

    // MARK: - Body

    var body: some View {
        if hasElevation {
            VStack(alignment: .leading, spacing: 8) {
                // Header row
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: "mountain.2.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.3))
                        Text("ELEVATION")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.3))
                            .tracking(1.5)
                    }

                    Spacer()

                    if totalGain > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 8))
                                .foregroundStyle(AppColor.success.opacity(0.7))
                            Text("+\(totalGain) m")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }

                    if let elev = currentElevation {
                        HStack(spacing: 3) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(AppColor.mango.opacity(0.8))
                            Text(String(format: "%.0f m", elev))
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(AppColor.mango)
                        }
                    }
                }

                // Canvas profile
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height

                    Canvas { context, size in
                        drawProfile(context: context, size: size)
                        drawLookAhead(context: context, size: size)
                        drawRiderMarker(context: context, size: CGSize(width: w, height: h))
                    }
                    .frame(width: w, height: h)
                }
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.02))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
    }

    // MARK: - Drawing Helpers

    /// Builds the full-route elevation path sampled at a fixed number of points.
    private func elevationPath(in size: CGSize, sampleCount: Int = 200) -> Path {
        let points = routeManager.points
        guard points.count > 1 else { return Path() }

        let w = size.width
        let h = size.height

        return Path { path in
            var first = true

            for i in 0...sampleCount {
                let fraction = Double(i) / Double(sampleCount)
                let dist = fraction * totalDistance

                guard let elev = routeManager.elevation(forDistance: dist) else { continue }

                let x = CGFloat(fraction) * w
                let normalised = (elev - minElevation) / elevationRange
                // Flip: higher elevation = lower y value (up on screen)
                let y = h - CGFloat(normalised) * h * 0.85 - h * 0.05

                if first {
                    path.move(to: CGPoint(x: x, y: y))
                    first = false
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
    }

    /// Draws the filled gradient silhouette of the full route.
    private func drawProfile(context: GraphicsContext, size: CGSize) {
        let profilePath = elevationPath(in: size)
        guard !profilePath.isEmpty else { return }

        // Build a closed fill path (profile + bottom edge)
        var fillPath = profilePath
        fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
        fillPath.addLine(to: CGPoint(x: 0, y: size.height))
        fillPath.closeSubpath()

        // Gradient fill — zone-neutral dark teal
        context.fill(
            fillPath,
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 79/255, green: 195/255, blue: 161/255).opacity(0.25),
                    Color(red: 79/255, green: 195/255, blue: 161/255).opacity(0.04)
                ]),
                startPoint: CGPoint(x: size.width / 2, y: 0),
                endPoint: CGPoint(x: size.width / 2, y: size.height)
            )
        )

        // Profile line
        context.stroke(
            profilePath,
            with: .color(Color(red: 79/255, green: 195/255, blue: 161/255).opacity(0.45)),
            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
        )
    }

    /// Dims the portion of the route already ridden with a subtle overlay.
    private func drawLookAhead(context: GraphicsContext, size: CGSize) {
        guard riderFraction > 0 else { return }

        // Ridden portion: slightly darker overlay
        let riddenRect = CGRect(x: 0, y: 0, width: size.width * CGFloat(riderFraction), height: size.height)
        context.fill(
            Path(riddenRect),
            with: .color(Color.black.opacity(0.18))
        )
    }

    /// Draws the vertical position line and dot at the rider's current distance.
    private func drawRiderMarker(context: GraphicsContext, size: CGSize) {
        let x = CGFloat(riderFraction) * size.width

        // Vertical dashed line
        var linePath = Path()
        linePath.move(to: CGPoint(x: x, y: 0))
        linePath.addLine(to: CGPoint(x: x, y: size.height))

        context.stroke(
            linePath,
            with: .color(AppColor.mango.opacity(0.8)),
            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 4])
        )

        // Position dot on the profile line
        if let elev = currentElevation {
            let normalised = (elev - minElevation) / elevationRange
            let y = size.height - CGFloat(normalised) * size.height * 0.85 - size.height * 0.05

            // Glow
            context.fill(
                Circle().path(in: CGRect(x: x - 7, y: y - 7, width: 14, height: 14)),
                with: .color(AppColor.mango.opacity(0.25))
            )
            // White ring
            context.fill(
                Circle().path(in: CGRect(x: x - 5, y: y - 5, width: 10, height: 10)),
                with: .color(Color.white)
            )
            // Mango fill
            context.fill(
                Circle().path(in: CGRect(x: x - 3.5, y: y - 3.5, width: 7, height: 7)),
                with: .color(AppColor.mango)
            )
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color(red: 0.03, green: 0.04, blue: 0.06).ignoresSafeArea()
        ElevationProfileView(currentDistance: 12_000, height: 80)
            .padding(20)
            .environment(RouteManager())
    }
}

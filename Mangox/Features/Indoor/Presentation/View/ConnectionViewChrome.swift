import SwiftUI

// MARK: - Route Illustration (Dashed Path)

struct RouteIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            Canvas { context, size in
                let path = Path { p in
                    p.move(to: CGPoint(x: 0, y: h * 0.7))
                    p.addCurve(
                        to: CGPoint(x: w * 0.35, y: h * 0.25),
                        control1: CGPoint(x: w * 0.12, y: h * 0.65),
                        control2: CGPoint(x: w * 0.22, y: h * 0.2)
                    )
                    p.addCurve(
                        to: CGPoint(x: w * 0.65, y: h * 0.55),
                        control1: CGPoint(x: w * 0.48, y: h * 0.3),
                        control2: CGPoint(x: w * 0.52, y: h * 0.6)
                    )
                    p.addCurve(
                        to: CGPoint(x: w, y: h * 0.3),
                        control1: CGPoint(x: w * 0.78, y: h * 0.5),
                        control2: CGPoint(x: w * 0.88, y: h * 0.25)
                    )
                }

                // Glow path
                context.stroke(
                    path,
                    with: .color(
                        AppColor.blue.opacity(0.08)),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )

                // Dashed main path
                context.stroke(
                    path,
                    with: .color(
                        AppColor.blue.opacity(0.25)),
                    style: StrokeStyle(
                        lineWidth: 2, lineCap: .round, dash: [6, 8], dashPhase: phase)
                )

                // Waypoint dots
                let dots: [CGPoint] = [
                    CGPoint(x: 0, y: h * 0.7),
                    CGPoint(x: w * 0.35, y: h * 0.25),
                    CGPoint(x: w * 0.65, y: h * 0.55),
                    CGPoint(x: w, y: h * 0.3),
                ]
                for dot in dots {
                    let rect = CGRect(x: dot.x - 3, y: dot.y - 3, width: 6, height: 6)
                    context.fill(
                        Circle().path(in: rect),
                        with: .color(
                            AppColor.blue.opacity(0.4)))
                }
            }
        }
        .onAppear {
            guard !accessibilityReduceMotion else {
                phase = 0
                return
            }
            phase = 0
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                phase = 28
            }
        }
        .onChange(of: accessibilityReduceMotion) { _, reduceMotion in
            guard !reduceMotion else {
                phase = 0
                return
            }
            phase = 0
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                phase = 28
            }
        }
    }
}

// MARK: - Grid Pattern View

struct GridPatternView: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 24
            let color = Color.white.opacity(0.015)

            // Vertical lines
            var x: CGFloat = 0
            while x < size.width {
                let path = Path { p in
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                }
                context.stroke(path, with: .color(color), lineWidth: 1)
                x += spacing
            }

            // Horizontal lines
            var y: CGFloat = 0
            while y < size.height {
                let path = Path { p in
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(path, with: .color(color), lineWidth: 1)
                y += spacing
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let ble = BLEManager()
    let wifi = WiFiTrainerService()
    let dataSource = DataSourceCoordinator(bleManager: ble, wifiService: wifi)
    NavigationStack {
        ConnectionView(
            navigationPath: .constant(NavigationPath()),
            bleService: ble,
            dataSourceService: dataSource,
            routeService: RouteManager(),
            locationService: LocationManager()
        )
    }
}

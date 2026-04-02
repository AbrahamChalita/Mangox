import SwiftUI
import MapKit

struct RouteMiniMapView: View {
    @Environment(RouteManager.self) private var routeManager
    let distance: Double
    var mapHeight: CGFloat = 130

    @State private var cameraPosition: MapCameraPosition = .automatic

    private var riderCoordinate: CLLocationCoordinate2D? {
        routeManager.coordinate(forDistance: distance)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ROUTE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.3))
                    .tracking(1.5)

                Spacer()

                if routeManager.hasRoute {
                    Text(String(format: "%.1f / %.1f km", distance / 1000, routeManager.totalDistance / 1000))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }

            if routeManager.hasRoute {
                Map(position: $cameraPosition) {
                    // Cache sanitized coordinates — polylines only change when route loads
                    let segments = routeManager.polylineSegments
                    ForEach(segments.indices, id: \.self) { i in
                        let coordinates = segments[i].sanitizedForMapPolyline()
                        if coordinates.count > 1 {
                            MapPolyline(coordinates: coordinates)
                                .stroke(AppColor.mango, lineWidth: 4)
                        }
                    }

                    if let riderCoordinate {
                        Annotation("Rider", coordinate: riderCoordinate) {
                            Circle()
                                .fill(Color(red: 240/255, green: 195/255, blue: 78/255))
                                .frame(width: 12, height: 12)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.white.opacity(0.85), lineWidth: 2)
                                )
                                .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)
                        }
                    }
                }
                .frame(height: mapHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "map")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.2))
                    Text("Upload a GPX route to track position")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .frame(maxWidth: .infinity)
                .frame(height: mapHeight)
                .background(Color.white.opacity(0.015))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .onAppear(perform: updateCamera)
        .onChange(of: routeManager.points.count) { _, _ in
            updateCamera()
        }
    }

    private func updateCamera() {
        if let region = routeManager.cameraRegion {
            cameraPosition = .region(region)
        }
    }
}

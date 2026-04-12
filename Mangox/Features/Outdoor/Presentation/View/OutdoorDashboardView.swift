import CoreBluetooth
import MapKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Full-screen outdoor cycling dashboard — bike computer replacement.
///
/// Layout adapts: iPhone shows map-first with overlaid metrics strip;
/// iPad shows a two-column layout (map left, metrics right).
///
/// Supports three modes:
/// - **Free Ride**: breadcrumb trail + live stats
/// - **Follow Route**: GPX overlay + off-course detection
/// - **Turn-by-Turn**: Apple Maps directions + navigation HUD
struct OutdoorDashboardView: View {
    @State private var viewModel: OutdoorViewModel
    @Environment(\.horizontalSizeClass) private var hSizeClass

    let di: DIContainer
    @Binding var navigationPath: NavigationPath

    // searchQuery, searchFieldFocused moved into DestinationSearchOverlay / RouteSearchPage
    // searchDebounceTask removed — now handled by MKLocalSearchCompleter in extracted views
    /// Pre-initialized completer so MapKit search infrastructure is warm before the overlay opens.
    /// `DestinationSearchCompleter` init is now free (MKLocalSearchCompleter is lazy inside it).
    @State private var searchCompleter = DestinationSearchCompleter()
    /// Becomes true ~280ms after appear (after push animation) to trigger MapKit pre-warm.
    /// Keeps the push animation frame-perfect by deferring heavy MapKit init.
    @State private var mapKitPreWarmActive = false
    /// Height of the compact stats card — used to offset the map camera so the rider
    /// position appears in the visible area above the card, not behind it.
    @State private var statsCardHeight: CGFloat = 0
    /// After timeout, show map even if accuracy is still poor (indoors / weak sky view).
    @State private var outdoorLoadingBypassed = false
    /// Whether to show all discovered sensors or just the first 3.
    @State private var showAllSensors = false

    @Bindable private var prefs = RidePreferences.shared

    /// Match `LocationManager` acceptable accuracy for a “ready” outdoor fix.
    private let outdoorReadyAccuracyMeters: Double = 50

    init(navigationPath: Binding<NavigationPath>, di: DIContainer, viewModel: OutdoorViewModel) {
        self._navigationPath = navigationPath
        self.di = di
        self._viewModel = State(initialValue: viewModel)
    }

    /// Shorthand for the location service — replaces the removed `@Environment(LocationManager.self)`.
    private var ls: LocationServiceProtocol { viewModel.locationService }
    private var mapCameraService: MapCameraServiceProtocol { di.mapCameraService }
    /// Shorthand for the VM-owned NavigationService.
    private var ns: NavigationService { viewModel.navigationService }

    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<OutdoorViewModel, Value>)
        -> Binding<Value>
    {
        Binding(
            get: { viewModel[keyPath: keyPath] },
            set: { viewModel[keyPath: keyPath] = $0 }
        )
    }

    /// Live GPS speed, or an em dash when Core Location has not delivered fixes recently.
    private func liveGpsSpeedText(imperial: Bool) -> String {
        if ls.isGpsSignalStale {
            return "—"
        }
        return AppFormat.speedString(ls.speed, imperial: imperial)
    }

    private var hasGoodOutdoorFix: Bool {
        guard let loc = ls.currentLocation else { return false }
        return loc.horizontalAccuracy > 0 && loc.horizontalAccuracy <= outdoorReadyAccuracyMeters
    }

    private var outdoorMapReady: Bool {
        !ls.isAuthorized || hasGoodOutdoorFix || outdoorLoadingBypassed
    }

    private var showOutdoorLoadingShell: Bool {
        ls.isAuthorized && !outdoorMapReady
    }

    private var isPreRide: Bool { !ls.isRecording }

    /// MapKit destination autocomplete: prefer neighborhood when GPS is live, otherwise bias to rough location instead of a global search window.
    private var destinationSearchMapBias: DestinationSearchMapBias {
        if ls.currentLocation != nil { return .preciseGPS }
        if mapCameraService.lastSearchBiasCoordinate != nil { return .regional }
        return .wideFallback
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            AppColor.bg.ignoresSafeArea()

            // ── Pre-warm MapKit + keyboard ────────────────────────────────────
            // Deferred until mapKitPreWarmActive (≥280ms after appear) so the push
            // animation runs without any MapKit main-thread work competing with rendering.
            // By the time the user can tap Navigate → Choose Destination (>1s), everything
            // is already warm.
            if mapKitPreWarmActive {
                Map(position: .constant(.automatic))
                    .frame(width: 1, height: 1)
                    .opacity(0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                TextField("", text: .constant(""))
                    .frame(width: 1, height: 1)
                    .opacity(0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            if !ls.isAuthorized {
                locationPermissionState
            } else if viewModel.showSetupPhase {
                outdoorSetupView
                    .transition(
                        .asymmetric(
                            insertion: .opacity,
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
            } else if showOutdoorLoadingShell {
                outdoorBootstrapView
            } else if hSizeClass == .compact {
                compactLayout
            } else {
                wideLayout
            }

            endDiscardOverlays

            // Full-screen destination search (setup navigate mode)
            if viewModel.showDestinationSearch {
                DestinationSearchOverlay(
                    completer: searchCompleter,
                    onSelect: { item in
                        viewModel.selectDestination(item)
                        viewModel.dismissDestinationSearch()
                    },
                    onDismiss: {
                        // Clear stale destination if user dismisses without a new selection
                        // so the setup card doesn't show a stale "To: ..." subtitle.
                        viewModel.dismissDestinationSearch()
                    },
                    searchMapBias: destinationSearchMapBias,
                    searchBiasCoordinate: mapCameraService.destinationSearchBiasCoordinate
                )
                .zIndex(150)
                .transition(.move(edge: .trailing))
            }
        }
        .animation(MangoxMotion.standard, value: viewModel.showDestinationSearch)
        .onAppear {
            viewModel.handleAppear(
                locationManager: ls,
                autoLapIntervalMeters: prefs.outdoorAutoLapIntervalMeters
            )
        }
        .task {
            // Defer the hidden Map until the navigation push eases (~280ms). Slightly earlier than
            // before: MapKit tile init still avoids the heaviest part of the transition.
            try? await Task.sleep(for: .milliseconds(280))
            mapKitPreWarmActive = true
            searchCompleter.warmUp()
        }
        .onChange(of: viewModel.setupMode) { _, mode in
            viewModel.handleSetupModeChange(
                mode: mode,
                showSetupPhase: viewModel.showSetupPhase,
                locationManager: ls
            )
        }
        .onChange(of: viewModel.showSetupPhase) { _, committed in
            viewModel.handleSetupPhaseChange(
                committed: committed,
                locationManager: ls
            )
        }
        .onChange(of: viewModel.showDestinationSearch) { _, open in
            viewModel.handleDestinationSearchChange(
                isOpen: open,
                locationManager: ls
            )
        }
        .onDisappear {
            ls.persistRecordingCheckpointIfNeeded()
            viewModel.handleDisappear(locationManager: ls)
        }
        .task(id: ls.isAuthorized) {
            outdoorLoadingBypassed = false
            try? await Task.sleep(for: .seconds(12))
            outdoorLoadingBypassed = true
        }
        .task(id: ls.isRecording) {
            await viewModel.syncLiveActivity(
                isRecording: ls.isRecording,
                prefs: prefs,
                locationManager: ls
            )
        }
        .onChange(of: ls.currentLocation) {
            guard !viewModel.showSetupPhase else { return }
            if let loc = ls.currentLocation {
                ns.updatePosition(loc)
            }
        }
        .onChange(of: ls.newLapJustCompleted) {
            guard ls.newLapJustCompleted else { return }
            ls.newLapJustCompleted = false
            withAnimation(MangoxMotion.smooth) {
                viewModel.presentLapToast(for: ls.completedLaps.last)
            }
            Task {
                try? await Task.sleep(for: .seconds(3))
                withAnimation(MangoxMotion.smooth) { viewModel.dismissLapToast() }
            }
        }
        .onChange(of: ls.authorizationStatus) {
            viewModel.handleAuthorizationChange(
                status: ls.authorizationStatus,
                locationManager: ls
            )
        }
        .sheet(
            isPresented: binding(\.showRouteSheet),
            onDismiss: {
                viewModel.dismissRouteSheet()
            }
        ) {
            routePlanningSheet
        }
        .fileImporter(
            isPresented: binding(\.showRouteImporter),
            allowedContentTypes: [UTType(filenameExtension: "gpx") ?? .xml],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task {
                    if let error = await viewModel.importRoute(
                        from: url
                    ) {
                        await MainActor.run {
                            viewModel.presentRouteImportError(error)
                        }
                    } else {
                        await MainActor.run {
                            withAnimation(MangoxMotion.standard) {}
                        }
                    }
                }
            case .failure(let error):
                viewModel.presentRouteImportError(error.localizedDescription)
            }
        }
        .overlay {
            if let error = viewModel.routeImportError {
                MangoxConfirmOverlay(
                    title: "Route Import Failed",
                    message: error,
                    onDismiss: { viewModel.clearRouteImportError() }
                ) {
                    Button {
                        viewModel.clearRouteImportError()
                    } label: {
                        Text("OK")
                            .mangoxButtonChrome(.hero)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let error = viewModel.routeBuildError {
                MangoxConfirmOverlay(
                    title: "Couldn’t build route",
                    message: error,
                    onDismiss: { viewModel.clearRouteBuildError() }
                ) {
                    Button {
                        viewModel.clearRouteBuildError()
                    } label: {
                        Text("OK")
                            .mangoxButtonChrome(.hero)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        // Hide the NavigationStack bar — we use a fully custom chrome.
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: prefs.outdoorAutoLapIntervalMeters) {
            ls.lapIntervalMeters = prefs.outdoorAutoLapIntervalMeters
        }
        .environment(viewModel)
    }

    private var hasActiveRoute: Bool {
        ns.routePolyline.count > 1
    }

    /// Mapless iPhone layout: surface navigation under speed when a route or TBT is active.
    private var maplessNavPriorityActive: Bool {
        prefs.prioritizeNavigationInMaplessBikeComputer
            && (ns.mode == .turnByTurn
                || ns.mode == .followRoute
                || hasActiveRoute)
    }

    /// Cursor on the elevation strip: along-route when following a polyline, else wheel distance.
    private var elevationStripRiderDistance: Double {
        if ns.mode != .freeRide, ns.routePolyline.count > 1 {
            return ns.distanceAlongRouteMeters
        }
        return ls.totalDistance
    }

    private var routeStatusCard: some View {
        routeStatusCardContent
            .padding(14)
            .mangoxSurface(.mapOverlay, shape: .rounded(18))
            .padding(.horizontal, 16)
    }

    private var routeStatusCardContent: some View {
        let isImperial = prefs.isImperial

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ns.routeName ?? viewModel.routeName ?? "Free Ride")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if ns.routeDistance > 0 {
                        Text(
                            "\(AppFormat.distanceString(ns.routeDistance, imperial: isImperial)) \(AppFormat.distanceUnit(imperial: isImperial))"
                        )
                    } else {
                        Text("No route loaded")
                    }

                    if ns.mode == .turnByTurn {
                        Text("Turn-by-turn")
                    } else if ns.mode == .followRoute {
                        Text("Follow route")
                    } else {
                        Text("Free ride")
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
            }

            Spacer()

            if ns.mode != .freeRide {
                Button {
                    viewModel.clearRouteSelection()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .mangoxButtonChrome(.mapIconSmall)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Single liquid-glass panel: next turn + route summary (avoids stacking two cards under the top bar).
    private func combinedTurnByTurnCard(_ turn: TurnInstruction) -> some View {
        let isImperial = prefs.isImperial

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: turn.symbol)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(AppColor.mango)
                    .frame(width: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(turn.instruction)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                    Text("in \(turn.distanceText)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer(minLength: 4)

                if let upcoming = ns.upcomingTurn {
                    VStack(spacing: 4) {
                        Image(systemName: upcoming.symbol)
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.5))
                        Text(upcoming.distanceText)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
            }

            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(height: 1)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ns.routeName ?? viewModel.routeName ?? "Route")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        if ns.routeDistance > 0 {
                            Text(
                                "\(AppFormat.distanceString(ns.routeDistance, imperial: isImperial)) \(AppFormat.distanceUnit(imperial: isImperial))"
                            )
                        }
                        Text("Turn-by-turn")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                Button {
                    viewModel.clearRouteSelection()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .mangoxButtonChrome(.mapIconSmall)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .mangoxSurface(.mapOverlay, shape: .rounded(18))
        .padding(.horizontal, 16)
    }

    private func combinedFollowRouteCard(hint: TurnInstruction) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: hint.symbol)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AppColor.blue)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(hint.instruction)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text("in \(hint.distanceText)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
            }

            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(height: 1)

            routeStatusCardContent
        }
        .padding(14)
        .mangoxSurface(.mapOverlay, shape: .rounded(18))
        .padding(.horizontal, 16)
    }

    private var locationPermissionState: some View {
        VStack(spacing: 22) {
            Spacer()

            ZStack {
                Circle()
                    .fill(AppColor.success.opacity(0.08))
                    .frame(width: 160, height: 160)
                Image(systemName: "location.slash.fill")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(AppColor.success)
            }

            VStack(spacing: 10) {
                Text("Location Needed")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)

                Text(
                    "Outdoor rides use GPS for speed, distance, elevation, breadcrumbs, and route guidance."
                )
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            }

            VStack(spacing: 12) {
                Button {
                    viewModel.requestLocationPermission()
                } label: {
                    Text("Enable Location")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppColor.bg)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(AppColor.mango)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(MangoxPressStyle())

                Button("Back") {
                    navigationPath.removeLast()
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    private var mapStyle: MapStyle {
        if viewModel.isHybridMapStyle {
            return .hybrid(elevation: .realistic, pointsOfInterest: .excludingAll)
        }
        return .standard(elevation: .realistic, emphasis: .muted)
    }

    /// Colour for a breadcrumb chunk based on average speed.
    private func speedColor(_ kmh: Double) -> Color {
        switch kmh {
        case ..<10: return Color.white.opacity(0.35)  // very slow
        case 10..<20: return AppColor.mango  // moderate
        case 20..<30: return AppColor.yellow  // good pace
        default: return AppColor.success  // fast
        }
    }

    // MARK: - GPS loading (defer MapKit until we have a usable fix)

    private var outdoorLoadingView: some View {
        ZStack {
            AppColor.bg.ignoresSafeArea()
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.15)
                    .tint(AppColor.mango)
                Text("Finding GPS…")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                Text("Go outdoors or stand near a window for a quick satellite lock.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Full-screen prep: no map, drawer, or nav chrome until `outdoorMapReady` (then map + route sheet).
    private var outdoorBootstrapView: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                outdoorLoadingView
                HStack {
                    Button {
                        navigationPath.removeLast()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .mangoxButtonChrome(.mapIcon)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, geo.safeAreaInsets.top > 0 ? 4 : 0)
            }
        }
    }

    // MARK: - Setup Phase (pre-ride route selection)

    private var outdoorSetupView: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // Compact top bar
                HStack {
                    Button {
                        navigationPath.removeLast()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .mangoxButtonChrome(.mapIcon)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                    gpsStatusBadge
                }
                .padding(.horizontal, 16)
                .padding(.top, geo.safeAreaInsets.top > 0 ? 4 : 0)
                .padding(.bottom, 10)

                ScrollView {
                    VStack(spacing: 16) {
                        // Title — compact
                        HStack(spacing: 12) {
                            Image(systemName: "figure.outdoor.cycle")
                                .font(.system(size: 28, weight: .light))
                                .foregroundStyle(AppColor.mango)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Outdoor Ride")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(.white)
                                Text("Choose your ride mode")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.45))
                            }
                            Spacer()
                        }
                        .padding(.bottom, 4)

                        // Mode selection cards
                        VStack(spacing: 8) {
                            setupModeCard(.freeRide)
                            setupModeCard(.gpx)
                            setupModeCard(.navigate)
                        }

                        // Destination preview — small map when navigate destination is selected
                        if let dest = viewModel.selectedDestination {
                            destinationPreviewCard(dest)
                        }

                        // MARK: Sensors
                        outdoorSensorsSection

                        // Map style toggle
                        Toggle(isOn: binding(\.isHybridMapStyle)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Satellite map")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text("More contrast outdoors")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                        }
                        .tint(AppColor.mango)
                        .padding(12)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }

                // Dynamic CTA
                setupCTAButton
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, max(20, geo.safeAreaInsets.bottom))
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func setupModeCard(_ mode: OutdoorSetupMode) -> some View {
        let isSelected = viewModel.setupMode == mode
        let icon: String
        let title: String
        let subtitle: String
        switch mode {
        case .freeRide:
            icon = "figure.outdoor.cycle"
            title = "Free Ride"
            subtitle = "Just ride and record your path"
        case .gpx:
            icon = "doc.badge.arrow.up"
            title = "Import GPX"
            subtitle = viewModel.hasRoute ? "Route loaded — ready to go" : "Follow a .gpx file"
        case .navigate:
            icon = "arrow.triangle.turn.up.right.diamond"
            title = "Navigate"
            subtitle =
                viewModel.selectedDestination != nil
                ? "To: \(viewModel.selectedDestination!.name ?? "Destination")"
                : "Apple Maps cycling directions"
        }

        return Button {
            withAnimation(MangoxMotion.micro) { viewModel.selectSetupMode(mode) }
            if mode == .gpx && !viewModel.hasRoute { viewModel.presentRouteImporter() }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? AppColor.mango : .white.opacity(0.55))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(isSelected ? 0.55 : 0.35))
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppColor.mango)
                }
            }
            .padding(14)
            .background(isSelected ? AppColor.mango.opacity(0.08) : Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? AppColor.mango.opacity(0.55) : Color.white.opacity(0.08),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Destination Preview (setup phase)

    /// Small map card showing the selected navigate destination before committing to route calculation.
    private func destinationPreviewCard(_ dest: MKMapItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColor.mango)
                VStack(alignment: .leading, spacing: 1) {
                    Text(dest.name ?? "Destination")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let addr = dest.addressRepresentations?.fullAddress(
                        includingRegion: true, singleLine: true)
                    {
                        Text(addr)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                }
                Spacer()
                Button {
                    viewModel.clearSelectedDestination()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            Map {
                Marker(dest.name ?? "Destination", coordinate: dest.location.coordinate)
                    .tint(AppColor.mango)
            }
            .mapStyle(.standard(elevation: .realistic, emphasis: .muted))
            .mapControls {}
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .background(AppColor.mango.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AppColor.mango.opacity(0.2), lineWidth: 1)
        )
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    // MARK: - Outdoor Sensors Section (setup phase)

    /// Collapsible sensors card on the outdoor setup screen.
    /// Shows connected HR / speed / cadence sensors with a scan button.
    /// Uses AppColor.yellow accent to visually separate from the mango ride-mode cards.
    private var outdoorSensorsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack(spacing: 8) {
                Image(systemName: "sensor.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColor.yellow)
                Text("SENSORS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .tracking(1.0)
                Spacer()
                // Scan / Stop button
                Button {
                    if viewModel.isScanningForSensors {
                        viewModel.stopSensorScan()
                    } else {
                        viewModel.scanForSensors()
                    }
                } label: {
                    HStack(spacing: 4) {
                        if viewModel.isScanningForSensors {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(AppColor.yellow)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        Text(viewModel.isScanningForSensors ? "Scanning…" : "Scan")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(AppColor.yellow)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppColor.yellow.opacity(0.08))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(AppColor.yellow.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            // Connected devices
            VStack(spacing: 0) {
                outdoorSensorRow(
                    icon: "heart.fill",
                    label: "Heart Rate",
                    state: viewModel.hrConnectionState,
                    color: AppColor.heartRate
                )
                Divider().background(Color.white.opacity(0.06)).padding(.leading, 44)
                outdoorSensorRow(
                    icon: "speedometer",
                    label: "Speed / Cadence",
                    state: viewModel.cscConnectionState,
                    color: AppColor.blue
                )
            }

            // Discovered devices — exclude trainers and already-connected/connecting peripherals
            let activeIDs = viewModel.activeSensorIDs
            let sensorResults = viewModel.discoveredSensors.filter {
                $0.deviceType != .trainer && !activeIDs.contains($0.id)
            }
            if !sensorResults.isEmpty {
                Divider().background(Color.white.opacity(0.06)).padding(.horizontal, 14)

                let visibleSensors = showAllSensors ? sensorResults : Array(sensorResults.prefix(3))
                VStack(spacing: 0) {
                    ForEach(visibleSensors) { peripheral in
                        Button {
                            connectOutdoorSensor(peripheral)
                        } label: {
                            HStack(spacing: 10) {
                                Image(
                                    systemName: peripheral.deviceType == .heartRateMonitor
                                        ? "heart.fill" : "sensor.fill"
                                )
                                .font(.system(size: 12))
                                .foregroundStyle(AppColor.yellow.opacity(0.7))
                                .frame(width: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(peripheral.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.white)
                                    Text(
                                        peripheral.deviceType == .heartRateMonitor
                                            ? "Heart Rate Monitor" : "Speed/Cadence Sensor"
                                    )
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.35))
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(AppColor.yellow.opacity(0.6))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }

                    if sensorResults.count > 3 {
                        Button {
                            withAnimation(MangoxMotion.micro) { showAllSensors.toggle() }
                        } label: {
                            HStack(spacing: 4) {
                                Text(
                                    showAllSensors
                                        ? "Show less" : "Show \(sensorResults.count - 3) more"
                                )
                                .font(.system(size: 11, weight: .semibold))
                                Image(systemName: showAllSensors ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundStyle(AppColor.yellow.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Hint when nothing connected
            if !viewModel.isHRMonitorConnected
                && !viewModel.isCSCConnected
                && sensorResults.isEmpty && !viewModel.isScanningForSensors
            {
                Text("Tap Scan to find nearby HR & speed/cadence sensors")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        }
        .padding(.bottom, 10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AppColor.yellow.opacity(0.15), lineWidth: 1)
        )
    }

    private func outdoorSensorRow(
        icon: String, label: String, state: BLEConnectionState, color: Color
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(state.isConnected ? color : .white.opacity(0.25))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(state.isConnected ? 0.9 : 0.45))
                switch state {
                case .connected(let name):
                    Text(name)
                        .font(.system(size: 10))
                        .foregroundStyle(color.opacity(0.8))
                case .connecting(let name):
                    Text("Connecting to \(name)…")
                        .font(.system(size: 10))
                        .foregroundStyle(AppColor.yellow.opacity(0.6))
                default:
                    Text("Not connected")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.25))
                }
            }

            Spacer()

            if state.isConnected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColor.success)
            } else if case .connecting = state {
                ProgressView()
                    .controlSize(.mini)
                    .tint(AppColor.yellow)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func connectOutdoorSensor(_ peripheral: DiscoveredPeripheral) {
        switch peripheral.deviceType {
        case .heartRateMonitor:
            viewModel.connectHRMonitor(peripheral.peripheral)
        case .cyclingSpeedCadence:
            viewModel.connectCSCSensor(peripheral.peripheral)
        default:
            // For unknown types, try CSC (speed/cadence is more common outdoors)
            viewModel.connectCSCSensor(peripheral.peripheral)
        }
    }

    // NOTE: destinationSearchOverlay has been extracted to DestinationSearchView.swift
    // as DestinationSearchOverlay — isolating search state from the 3000-line dashboard
    // body to eliminate keyboard lag from whole-body re-evaluation on every keystroke.

    @ViewBuilder
    private var setupCTAButton: some View {
        switch viewModel.setupMode {
        case .freeRide:
            Button {
                withAnimation(MangoxMotion.standard) { viewModel.commitSetupPhase() }
            } label: {
                ctaLabel("Start Free Ride")
            }
            .buttonStyle(MangoxPressStyle())

        case .gpx:
            if viewModel.hasRoute {
                Button {
                    withAnimation(MangoxMotion.standard) { viewModel.commitSetupPhase() }
                } label: {
                    ctaLabel("Start Route")
                }
                .buttonStyle(MangoxPressStyle())
            } else {
                Button {
                    viewModel.presentRouteImporter()
                } label: {
                    ctaLabel("Import GPX File", secondary: true)
                }
                .buttonStyle(MangoxPressStyle())
            }

        case .navigate:
            if viewModel.selectedDestination != nil {
                Button {
                    startNavigation()
                } label: {
                    if ns.isCalculating {
                        HStack(spacing: 10) {
                            ProgressView()
                                .tint(AppColor.bg)
                            Text("Building route…")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(AppColor.bg)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(AppColor.mango)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else {
                        ctaLabel("Start Navigation")
                    }
                }
                .disabled(ns.isCalculating)
                .buttonStyle(MangoxPressStyle())
            } else {
                Button {
                    viewModel.presentDestinationSearch()
                } label: {
                    ctaLabel("Choose Destination")
                }
                .buttonStyle(MangoxPressStyle())
            }
        }
    }

    private func ctaLabel(_ text: String, secondary: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(secondary ? .white : AppColor.bg)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(secondary ? Color.white.opacity(0.08) : AppColor.mango)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        secondary ? Color.white.opacity(0.15) : Color.clear,
                        lineWidth: secondary ? 1 : 0)
            )
    }

    // MARK: - Compact Layout (iPhone)

    /// Small rotating compass shown bottom-left above the stats card.
    /// The arrow always points toward geographic north; it counter-rotates
    /// with the same rotation as the map camera (course-first + smoothed).
    private var compactCompass: some View {
        let deg = -mapCameraService.mapCameraHeadingDegrees
        return VStack(spacing: 2) {
            Image(systemName: "arrow.up")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
            Text("N")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.65))
        }
        .rotationEffect(.degrees(deg))
        .frame(width: 38, height: 38)
        .mangoxSurface(.mapOverlay, shape: .circle)
        .overlay(Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .animation(MangoxMotion.standard, value: deg)
    }

    /// Full-screen bike-computer when the map is hidden (compact iPhone): works pre-ride and while recording.
    private var showCompactBikeComputerLayout: Bool {
        !viewModel.showMapInCompact && outdoorMapReady
    }

    /// Chrome palette when the map is visible vs full-screen black bike-computer (both use light icons).
    private enum OutdoorChromeSurface {
        case mapOverlay
        case bikeComputerDark
    }

    private func chromeIcon(_ surface: OutdoorChromeSurface) -> Color { .white }
    private func chromeMuted(_ surface: OutdoorChromeSurface) -> Color { .white.opacity(0.6) }
    private func chromeNavPrimary(_ surface: OutdoorChromeSurface) -> Color { .white }
    private func chromeNavSecondary(_ surface: OutdoorChromeSurface) -> Color {
        .white.opacity(0.6)
    }

    /// Frosted glass on the map vs flat cards on the mapless bike-computer sheet.
    private enum CompactNavChromeStyle {
        case frostedGlass
        case bikeComputerSheet
    }

    private enum CompactNavChromeShape {
        case roundedRect
        case capsule
    }

    @ViewBuilder
    private func applyCompactNavChrome<Content: View>(
        style: CompactNavChromeStyle,
        shape: CompactNavChromeShape,
        @ViewBuilder content: () -> Content
    ) -> some View {
        switch (style, shape) {
        case (.frostedGlass, .roundedRect):
            content()
                .mangoxSurface(.mapOverlay, shape: .rounded(14))
        case (.frostedGlass, .capsule):
            content()
                .mangoxSurface(.mapOverlay, shape: .capsule)
        case (.bikeComputerSheet, .roundedRect):
            content()
                .mangoxSurface(.flat, shape: .rounded(12))
        case (.bikeComputerSheet, .capsule):
            content()
                .mangoxSurface(.flat, shape: .capsule)
        }
    }

    private var compactLayout: some View {
        GeometryReader { geo in
            let bikeComputer = showCompactBikeComputerLayout
            let chromeSurface: OutdoorChromeSurface = bikeComputer ? .bikeComputerDark : .mapOverlay
            // Both chrome overlays are applied directly ON the map so that
            // SwiftUI gives them gesture priority over MapKit's UIKit recognizers.
            // ZStack-sibling approach causes MapKit to steal button taps.
            ZStack {
                Group {
                    if outdoorMapReady && geo.size.width > 0 && viewModel.showMapInCompact {
                        mapView
                            .ignoresSafeArea(edges: [.top, .bottom, .leading, .trailing])
                    } else {
                        AppColor.bg
                            .ignoresSafeArea()
                    }
                }
                if bikeComputer {
                    compactBikeComputerStatsLayer(safeBottomInset: geo.safeAreaInsets.bottom)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                removal: .opacity.combined(with: .move(edge: .bottom))
                            ))
                }
            }
            .animation(MangoxMotion.expansive, value: bikeComputer)
            .overlay(alignment: .top) {
                // The overlay already starts at the safe-area boundary (below Dynamic Island),
                // so we only need a small breathing-room inset, not the full safeAreaInsets.top.
                compactTopChrome(safeTopInset: 8, surface: chromeSurface)
            }
            .overlay(alignment: .bottom) {
                if !bikeComputer {
                    VStack(alignment: .leading, spacing: 8) {
                        // Lap toast — floats above the card
                        lapToastView
                            .frame(maxWidth: .infinity, alignment: .center)
                            .animation(MangoxMotion.smooth, value: viewModel.showLapToast)

                        // Climb banner — only during active climb
                        climbBanner

                        // Elevation profile strip — when a GPX route is loaded and has elevation data
                        if viewModel.hasRoute && viewModel.hasElevationData {
                            ElevationProfileStripView(
                                profilePoints: viewModel.routeElevationProfilePoints,
                                totalDistance: viewModel.totalRouteDistance,
                                riderDistance: elevationStripRiderDistance
                            )
                            .padding(.horizontal, 12)
                        }

                        // AUTO-PAUSED floats above the card as a pill — keeping card height
                        // constant so the map viewport doesn't jump when pausing.
                        if ls.isRecording && ls.isAutoPaused {
                            Text("AUTO-PAUSED")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(AppColor.yellow)
                                .tracking(1.0)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 9)
                                .background(AppColor.yellow.opacity(0.08))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().strokeBorder(
                                        AppColor.yellow.opacity(0.25), lineWidth: 1)
                                )
                                .frame(maxWidth: .infinity)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        // Compass: bottom-left, above stats card
                        if viewModel.showMapInCompact {
                            compactCompass
                                .padding(.leading, 20)
                        }
                        compactCardView(safeBottomInset: geo.safeAreaInsets.bottom)
                            .background(
                                GeometryReader { cardGeo in
                                    Color.clear
                                        .onAppear { statsCardHeight = cardGeo.size.height }
                                        .onChange(of: cardGeo.size.height) { _, h in
                                            statsCardHeight = h
                                        }
                                }
                            )
                    }
                }
            }
        }
    }

    /// Full-screen black bike-computer: speed → metrics / nav (order depends on route mode) → bottom actions.
    private func compactBikeComputerStatsLayer(safeBottomInset: CGFloat) -> some View {
        let isImperial = prefs.isImperial
        let canvas = Color.black
        let labelMuted = Color.white.opacity(0.38)
        let tileFont: CGFloat = 28
        let recording = ls.isRecording
        let timePrimary: String =
            recording
            ? AppFormat.duration(ls.rideDuration)
            : "0:00"
        let distPrimary: String = AppFormat.distanceString(
            ls.totalDistance, imperial: isImperial)
        let elevPrimary = AppFormat.elevationString(
            ls.totalElevationGain, imperial: isImperial)
        let avgPrimary = AppFormat.speedString(ls.averageSpeed, imperial: isImperial)
        let navPriority = maplessNavPriorityActive

        return VStack(spacing: 0) {
            if recording {
                lapToastView
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)
                    .animation(MangoxMotion.smooth, value: viewModel.showLapToast)
            }

            Spacer(minLength: 12)

            bikeComputerSpeedHero(
                speedFontSize: navPriority ? 72 : 92,
                labelMuted: labelMuted,
                isImperial: isImperial
            )

            Spacer(minLength: 10)

            if navPriority {
                bikeComputerNavBannersBlock
                compactNavCardRow(surface: .bikeComputerDark, chromeStyle: .bikeComputerSheet)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 10)
                bikeComputerCoreMetricsGrid(
                    timePrimary: timePrimary,
                    distPrimary: distPrimary,
                    elevPrimary: elevPrimary,
                    avgPrimary: avgPrimary,
                    tileFont: tileFont,
                    isImperial: isImperial
                )
                bikeComputerSensorStrip()
            } else {
                bikeComputerCoreMetricsGrid(
                    timePrimary: timePrimary,
                    distPrimary: distPrimary,
                    elevPrimary: elevPrimary,
                    avgPrimary: avgPrimary,
                    tileFont: tileFont,
                    isImperial: isImperial
                )
                bikeComputerSensorStrip()
                bikeComputerNavBannersBlock
                compactNavCardRow(surface: .bikeComputerDark, chromeStyle: .bikeComputerSheet)
                    .frame(maxWidth: .infinity)
            }

            if recording, ls.isAutoPaused {
                Text("AUTO-PAUSED")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppColor.yellow)
                    .tracking(1.0)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(AppColor.yellow.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(AppColor.yellow.opacity(0.25), lineWidth: 1)
                    )
                    .padding(.top, 4)
            }

            Spacer(minLength: 8)

            HStack(alignment: .center, spacing: 12) {
                if recording {
                    Button {
                        viewModel.presentEndConfirmation()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(AppColor.red)
                                .frame(width: 64, height: 64)
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(.white)
                                .frame(width: 22, height: 22)
                        }
                        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                    }
                    .buttonStyle(MangoxPressStyle())
                    .contentShape(Circle())
                    .accessibilityLabel("End ride")

                    Spacer(minLength: 0)

                    Button {
                        withAnimation(MangoxMotion.expansive) {
                            viewModel.showCompactMap()
                        }
                    } label: {
                        Image(systemName: "map")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.45))
                            .mangoxButtonChrome(.icon)
                    }
                    .buttonStyle(MangoxPressStyle())
                    .contentShape(Circle())
                    .accessibilityLabel("Show map")
                } else {
                    Button {
                        viewModel.startRide(using: ls)
                    } label: {
                        Text("Start ride")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(AppColor.bg)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(AppColor.mango)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(MangoxPressStyle())

                    Button {
                        withAnimation(MangoxMotion.expansive) {
                            viewModel.showCompactMap()
                        }
                    } label: {
                        Image(systemName: "map")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.45))
                            .mangoxButtonChrome(.icon)
                    }
                    .buttonStyle(MangoxPressStyle())
                    .accessibilityLabel("Show map")
                }
            }
            .padding(.bottom, max(safeBottomInset, 12))
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(canvas)
    }

    private func bikeComputerSpeedHero(speedFontSize: CGFloat, labelMuted: Color, isImperial: Bool)
        -> some View
    {
        VStack(spacing: 8) {
            Text("SPEED")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(labelMuted)
                .tracking(1.2)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(liveGpsSpeedText(imperial: isImperial))
                    .font(.system(size: speedFontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.mango)
                    .minimumScaleFactor(0.45)
                    .lineLimit(1)
                Text(AppFormat.speedUnit(imperial: isImperial))
                    .font(.system(size: speedFontSize > 80 ? 22 : 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private func bikeComputerCoreMetricsGrid(
        timePrimary: String,
        distPrimary: String,
        elevPrimary: String,
        avgPrimary: String,
        tileFont: CGFloat,
        isImperial: Bool
    ) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                bikeComputerMetricSquare(
                    title: "TIME",
                    primary: timePrimary,
                    unit: nil,
                    valueFontSize: tileFont
                )
                bikeComputerMetricSquare(
                    title: "DISTANCE",
                    primary: distPrimary,
                    unit: AppFormat.distanceUnit(imperial: isImperial),
                    valueFontSize: tileFont
                )
            }
            HStack(alignment: .top, spacing: 10) {
                bikeComputerMetricSquare(
                    title: "ELEVATION",
                    primary: elevPrimary,
                    unit: AppFormat.elevationUnit(imperial: isImperial),
                    valueFontSize: tileFont
                )
                bikeComputerMetricSquare(
                    title: "AVG",
                    primary: avgPrimary,
                    unit: AppFormat.speedUnit(imperial: isImperial),
                    valueFontSize: tileFont
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func bikeComputerSensorStrip() -> some View {
        let showHR = viewModel.isHRMonitorConnected
        let showCad = viewModel.sensorCadence > 0
        let showPow = viewModel.isTrainerConnected
        if showHR || showCad || showPow {
            HStack(spacing: 16) {
                if showHR {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(AppColor.heartRate.opacity(0.9))
                        Text("\(viewModel.smoothedHeartRate)")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.88))
                        Text("bpm")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                if showCad {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                            .font(.system(size: 12))
                            .foregroundStyle(AppColor.blue.opacity(0.85))
                        Text("\(viewModel.sensorCadence)")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.88))
                        Text("rpm")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                if showPow {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(AppColor.mango.opacity(0.9))
                        Text("\(viewModel.smoothedPower)")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.88))
                        Text("W")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var bikeComputerNavBannersBlock: some View {
        if ns.isOffCourse {
            offCourseBanner(surface: .bikeComputerDark, chromeStyle: .bikeComputerSheet)
        }
        // Weak GPS is folded into `compactNavCardRow` via `navCardGpsLine` so it doesn’t stack as a second full-width bar.
    }

    private func bikeComputerMetricSquare(
        title: String,
        primary: String,
        unit: String?,
        valueFontSize: CGFloat
    ) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.38))
                .tracking(0.6)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(primary)
                    .font(.system(size: valueFontSize, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.92))
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                if let unit {
                    Text(unit)
                        .font(.system(size: max(10, valueFontSize - 7), weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .center)
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    /// Top chrome for iPhone: top row (back + GPS), then nav card, then off-course / weak-GPS banners.
    /// Right-side action buttons float independently so the nav card stays near the top.
    /// `safeTopInset` must be supplied so the chrome clears the Dynamic Island /
    /// notch — the overlay inherits the map's ignoresSafeArea coordinate space.
    private func compactTopChrome(
        safeTopInset: CGFloat = 0, surface: OutdoorChromeSurface = .mapOverlay
    ) -> some View {
        ZStack(alignment: .topTrailing) {
            // Left column: back button + nav card stacked tight at the top
            VStack(alignment: .leading, spacing: 4) {
                compactTopRow(surface: surface)
                // Directions / off-course live inside the mapless bike-computer sheet when map is hidden.
                if surface != .bikeComputerDark {
                    compactNavCardRow(surface: surface, chromeStyle: .frostedGlass)
                    if ns.isOffCourse {
                        offCourseBanner(surface: surface, chromeStyle: .frostedGlass)
                            .padding(.top, 4)
                    }
                    // Weak GPS: shown inside the nav card row (`navCardGpsLine`) so it matches card width and alignment.
                }
            }
            .padding(.trailing, 48)  // Leave room for right-side action buttons
            .frame(maxWidth: .infinity, alignment: .topLeading)

            // Right column: action buttons float independently
            compactRightButtons(surface: surface)
        }
        .padding(.top, safeTopInset)
        .padding(.horizontal, 12)
    }

    /// First row: back button only (pre-ride). GPS badge now lives inside the nav card.
    @ViewBuilder
    private func compactTopRow(surface: OutdoorChromeSurface) -> some View {
        if !ls.isRecording {
            // Pre-ride: back button only — GPS merged into nav card below
            HStack {
                Button {
                    navigationPath.removeLast()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(chromeIcon(surface))
                        .mangoxButtonChrome(.mapIcon)
                }
                .buttonStyle(MangoxPressStyle())
            }
            .padding(.vertical, 4)
        }
        // During recording: no top row — nav card sits flush at the top.
    }

    /// Right-side action buttons: route, center, map toggle, discard, END.
    private func compactRightButtons(surface: OutdoorChromeSurface) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            // Small top gap (no compass to avoid anymore)
            Color.clear.frame(height: 8)

            Button {
                viewModel.presentRouteSheet()
                } label: {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(chromeIcon(surface))
                        .mangoxButtonChrome(.mapIcon)
                }
                .buttonStyle(MangoxPressStyle())
                .accessibilityLabel("Route")

            Button {
                mapCameraService.centerMapOnUser()
                } label: {
                    Image(systemName: "location.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(chromeIcon(surface))
                        .mangoxButtonChrome(.mapIcon)
                }
                .buttonStyle(MangoxPressStyle())
                .accessibilityLabel("Center on location")
            .disabled(ls.currentLocation == nil)
            .opacity(ls.currentLocation == nil ? 0.35 : 1)

            // Map visibility toggle (compact / iPhone only) — hidden on mapless bike screen (duplicates bottom control)
            if hSizeClass == .compact, surface != .bikeComputerDark {
                Button {
                    withAnimation(MangoxMotion.expansive) {
                        viewModel.toggleCompactMapVisibility()
                    }
                } label: {
                    Image(systemName: viewModel.showMapInCompact ? "map.fill" : "map")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(
                            viewModel.showMapInCompact
                                ? AppColor.mango : chromeIcon(surface).opacity(0.7)
                        )
                        .mangoxButtonChrome(.mapIcon)
                }
                .buttonStyle(MangoxPressStyle())
                .accessibilityLabel(viewModel.showMapInCompact ? "Hide map" : "Show map")
            }

            if surface != .bikeComputerDark {
                Button {
                    guard let c = ls.currentLocation?.coordinate else { return }
                    viewModel.addWaypoint(c)
                } label: {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(chromeIcon(surface))
                        .mangoxButtonChrome(.mapIcon)
                }
                .buttonStyle(MangoxPressStyle())
                .accessibilityLabel("Drop waypoint at current location")
                .disabled(ls.currentLocation == nil)
                .opacity(ls.currentLocation == nil ? 0.35 : 1)

                if !viewModel.mapWaypoints.isEmpty {
                    Button {
                        viewModel.clearWaypoints()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .mangoxButtonChrome(.mapIcon)
                    }
                    .buttonStyle(MangoxPressStyle())
                    .accessibilityLabel("Clear waypoints")
                }
            }

            if ls.isRecording {
                Button {
                    viewModel.presentDiscardConfirmation()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColor.red)
                        .mangoxButtonChrome(.mapIcon)
                }
                .buttonStyle(MangoxPressStyle())
                .accessibilityLabel("Discard ride")

                if surface != .bikeComputerDark {
                    Button {
                        viewModel.presentEndConfirmation()
                    } label: {
                        Text("END")
                            .mangoxButtonChrome(.endIcon)
                    }
                    .buttonStyle(MangoxPressStyle())
                    .accessibilityLabel("End ride")
                }
            }
        }
    }

    /// Proper card pinned to the bottom of the screen — no drawer, no drag, no peek/expand states.
    private func compactCardView(safeBottomInset: CGFloat) -> some View {
        VStack(spacing: 12) {
            if isPreRide {
                preRideReadinessRow
            } else {
                metricsGrid
                if viewModel.isTrainerConnected
                    || viewModel.isHRMonitorConnected
                    || viewModel.isCSCConnected
                {
                    sensorRow
                }
            }
            // Always show: "Start ride" button pre-ride, AUTO-PAUSED banner when paused,
            // nothing when actively recording.
            compactDrawerBottom
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, safeBottomInset > 0 ? max(safeBottomInset - 8, 8) : 16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppColor.bg.opacity(0.93))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, safeBottomInset > 0 ? 0 : 12)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Wide Layout (iPad)

    private var wideLayout: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                HStack(spacing: 0) {
                    ZStack(alignment: .top) {
                        if outdoorMapReady {
                            mapView
                        } else {
                            AppColor.bg
                        }

                        VStack(spacing: 10) {
                            wideNavHud
                            Spacer(minLength: 0)
                        }
                        .padding(.top, 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                        // Elevation profile strip — bottom of map column
                        if viewModel.hasRoute && viewModel.hasElevationData {
                            VStack {
                                Spacer()
                                ElevationProfileStripView(
                                    profilePoints: viewModel.routeElevationProfilePoints,
                                    totalDistance: viewModel.totalRouteDistance,
                                    riderDistance: elevationStripRiderDistance
                                )
                                .padding(.horizontal, 12)
                                .padding(.bottom, 12)
                            }
                        }
                    }

                    ScrollView {
                        VStack(spacing: 16) {
                            gpsStatusBadge
                                .frame(maxWidth: .infinity, alignment: .trailing)

                            if isPreRide {
                                preRideReadinessRow
                            } else {
                                primaryMetrics

                                if viewModel.isTrainerConnected
                                    || viewModel.isHRMonitorConnected
                                    || viewModel.isCSCConnected
                                {
                                    sensorMetrics
                                }

                                secondaryMetrics
                            }

                            controlBar
                        }
                        .padding(20)
                    }
                    .frame(width: 360)
                    .background(AppColor.bg)
                }

                if showOutdoorLoadingShell {
                    outdoorLoadingView
                        .zIndex(20)
                }

                wideTopChrome()
                    .zIndex(40)
            }
        }
    }

    private func wideTopChrome() -> some View {
        VStack(spacing: 0) {
            topBarOverlay
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var wideNavHud: some View {
        if ns.isOffCourse {
            offCourseBanner(surface: .mapOverlay, chromeStyle: .frostedGlass)
                .padding(.horizontal, 16)
                .padding(.top, 4)
        }
        if ls.isGpsSignalStale {
            weakGpsBanner(surface: .mapOverlay, chromeStyle: .frostedGlass)
                .padding(.horizontal, 16)
                .padding(.top, 4)
        }
        climbBanner
        if ns.mode == .turnByTurn, let turn = ns.nextTurn {
            combinedTurnByTurnCard(turn)
        } else if ns.mode == .followRoute,
            let hint = ns.followRouteHint
        {
            combinedFollowRouteCard(hint: hint)
        } else if hasActiveRoute {
            routeStatusCard
        }
    }

    // MARK: - Map

    @ViewBuilder
    private var mapView: some View {
        Map(
            position: Binding(
                get: { mapCameraService.mapCameraPosition },
                set: { newPos in
                    mapCameraService.mapCameraPosition = newPos
                    mapCameraService.isFollowingUser = false
                }
            )
        ) {
            // Frozen breadcrumb chunks — colour-coded by average speed
            ForEach(ls.frozenBreadcrumbChunks) { chunk in
                let crumbs = chunk.coords.sanitizedForMapPolyline()
                if crumbs.count > 1 {
                    MapPolyline(coordinates: crumbs)
                        .stroke(speedColor(chunk.avgSpeed), lineWidth: 4)
                }
            }

            // Live tail — always mango coloured
            let tail = ls.liveBreadcrumbTail.sanitizedForMapPolyline()
            if tail.count > 1 {
                MapPolyline(coordinates: tail)
                    .stroke(AppColor.mango, lineWidth: 4)
            }

            // Route overlay — traversed (grey) vs remaining (yellow)
            ForEach(ns.completedRoutePolylines.indices, id: \.self) { i in
                let done = ns.completedRoutePolylines[i].sanitizedForMapPolyline()
                if done.count > 1 {
                    MapPolyline(coordinates: done)
                        .stroke(Color.white.opacity(0.35), lineWidth: 5)
                }
            }
            ForEach(ns.remainingRoutePolylines.indices, id: \.self) { i in
                let left = ns.remainingRoutePolylines[i].sanitizedForMapPolyline()
                if left.count > 1 {
                    MapPolyline(coordinates: left)
                        .stroke(AppColor.yellow, lineWidth: 5)
                }
            }

            // Lookahead ghost — dashed white, 300m ahead on remaining route
            ForEach(ns.lookaheadPolylines.indices, id: \.self) { i in
                let lookahead = ns.lookaheadPolylines[i].sanitizedForMapPolyline()
                if lookahead.count > 1 {
                    MapPolyline(coordinates: lookahead)
                        .stroke(
                            Color.white.opacity(0.45),
                            style: StrokeStyle(lineWidth: 3, dash: [8, 6])
                        )
                }
            }

            // Off-course snap-back line — dashed red line to nearest route point
            let snapBack = ns.snapBackPolyline
            if snapBack.count == 2 {
                MapPolyline(coordinates: snapBack)
                    .stroke(
                        AppColor.red.opacity(0.75),
                        style: StrokeStyle(lineWidth: 2, dash: [5, 5])
                    )
            }

            // Pause gap markers
            ForEach(ls.pauseGapCoordinates.indices, id: \.self) { i in
                let coord = ls.pauseGapCoordinates[i]
                Annotation("", coordinate: coord) {
                    Circle()
                        .fill(AppColor.yellow.opacity(0.85))
                        .frame(width: 10, height: 10)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                }
            }

            // Rider position — solid circle dot (smoothed when follow mode matches the camera).
            if let loc = ls.currentLocation {
                let riderCoord =
                    mapCameraService.isFollowingUser
                    ? mapCameraService.smoothedRiderCoordinate
                    : loc.coordinate
                Annotation("", coordinate: riderCoord) {
                    Circle()
                        .fill(AppColor.mango)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                        .shadow(color: .black.opacity(0.35), radius: 3)
                }
            }

            // Destination pin
            if let dest = ns.destination {
                Marker(dest.name ?? "Destination", coordinate: dest.location.coordinate)
                    .tint(AppColor.red)
            }

            // User-placed waypoints
            ForEach(Array(viewModel.mapWaypoints.enumerated()), id: \.offset) { index, coord in
                Annotation("", coordinate: coord) {
                    VStack(spacing: 2) {
                        ZStack {
                            Circle()
                                .fill(AppColor.blue)
                                .frame(width: 22, height: 22)
                            Image(systemName: "mappin")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        Text("WP\(index + 1)")
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
        /// Pinch / pan exits follow mode via `Map` position binding; programmatic camera updates use the same binding.
        .mapControls {}
        .safeAreaPadding(.top, 90)
        // Shift the camera so the rider dot is visible above the stats card,
        // not hidden behind it. Only active on compact (iPhone); wide layout has
        // no overlapping card. statsCardHeight is measured live from the card.
        .safeAreaPadding(.bottom, hSizeClass == .compact ? statsCardHeight : 0)
        .overlay {
            if ns.isCalculating {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    ProgressView("Building route…")
                        .tint(AppColor.mango)
                        .padding(20)
                        .glassEffect(
                            .regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .frame(minWidth: 1, minHeight: 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - End / discard confirmations (custom — works over drawer; compact vs full)

    private var endDiscardOverlays: some View {
        ZStack {
            if viewModel.isShowingEndConfirmation {
                endRideConfirmationOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            if viewModel.isShowingDiscardConfirmation {
                discardRideConfirmationOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(
            MangoxMotion.smooth,
            value: viewModel.isShowingEndConfirmation
        )
        .animation(
            MangoxMotion.smooth,
            value: viewModel.isShowingDiscardConfirmation
        )
        .zIndex(200)
        .allowsHitTesting(viewModel.isShowingConfirmationOverlay)
    }

    private var endRideConfirmationOverlay: some View {
        ZStack {
            Color.black.opacity(0.52)
                .ignoresSafeArea()
                .onTapGesture { viewModel.dismissConfirmation() }

            VStack(alignment: .leading, spacing: 16) {
                Text("End & save ride?")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                Text(
                    "We'll open the summary next so you can review distance, power, and route details."
                )
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button {
                        viewModel.dismissConfirmation()
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Button {
                        endRide()
                    } label: {
                        Text("End & Save")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(AppColor.bg)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .background(AppColor.mango)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(AppColor.bg)
                    .shadow(color: .black.opacity(0.45), radius: 30, y: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Discard Ride Confirmation

    private var discardRideConfirmationOverlay: some View {
        ZStack {
            Color.black.opacity(0.52)
                .ignoresSafeArea()
                .onTapGesture { viewModel.dismissConfirmation() }

            VStack(alignment: .leading, spacing: 16) {
                Text("Discard this ride?")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                Text(
                    "Distance, time, and GPS data from this session will be deleted. This can't be undone."
                )
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button {
                        viewModel.dismissConfirmation()
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Button {
                        discardRide()
                    } label: {
                        Text("Discard")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .background(AppColor.red.opacity(0.95))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(AppColor.bg)
                    .shadow(color: .black.opacity(0.45), radius: 30, y: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Top Bar Overlay

    private var topBarOverlay: some View {
        HStack(alignment: .top, spacing: 8) {
            // Back / exit — always pinned to the left
            Button {
                if viewModel.isShowingConfirmationOverlay {
                    viewModel.dismissConfirmation()
                } else if ls.isRecording {
                    viewModel.presentEndConfirmation()
                } else {
                    navigationPath.removeLast()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .mangoxButtonChrome(.mapIcon)
            }
            .buttonStyle(MangoxPressStyle())

            // Simple spacer — nav card is now a dedicated full-width row below the button bar.
            Spacer()

            // Right column: GPS + controls — always pinned to the right
            VStack(alignment: .trailing, spacing: 8) {
                gpsStatusBadge

                Button {
                    viewModel.presentRouteSheet()
                } label: {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .mangoxButtonChrome(.mapIcon)
                }
                .buttonStyle(MangoxPressStyle())
                .accessibilityLabel("Route")

                Button {
                    mapCameraService.centerMapOnUser()
                } label: {
                    Image(systemName: "location.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .mangoxButtonChrome(.mapIcon)
                }
                .buttonStyle(MangoxPressStyle())
                .accessibilityLabel("Center on location")
                .disabled(ls.currentLocation == nil)
                .opacity(ls.currentLocation == nil ? 0.35 : 1)

                // Map visibility toggle (compact / iPhone only)
                if hSizeClass == .compact {
                    Button {
                        withAnimation(MangoxMotion.expansive) {
                            viewModel.toggleCompactMapVisibility()
                        }
                    } label: {
                        Image(systemName: viewModel.showMapInCompact ? "map.fill" : "map")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(
                                viewModel.showMapInCompact ? AppColor.mango : .white.opacity(0.7)
                            )
                            .mangoxButtonChrome(.mapIcon)
                    }
                    .buttonStyle(MangoxPressStyle())
                    .accessibilityLabel(viewModel.showMapInCompact ? "Hide map" : "Show map")
                }

                Button {
                    guard let c = ls.currentLocation?.coordinate else { return }
                    viewModel.addWaypoint(c)
                } label: {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .mangoxButtonChrome(.mapIcon)
                }
                .buttonStyle(MangoxPressStyle())
                .accessibilityLabel("Drop waypoint at current location")
                .disabled(ls.currentLocation == nil)
                .opacity(ls.currentLocation == nil ? 0.35 : 1)

                if !viewModel.mapWaypoints.isEmpty {
                    Button {
                        viewModel.clearWaypoints()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .mangoxButtonChrome(.mapIcon)
                    }
                    .buttonStyle(MangoxPressStyle())
                    .accessibilityLabel("Clear waypoints")
                }

                if ls.isRecording {
                    Button {
                        viewModel.presentDiscardConfirmation()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColor.red)
                            .mangoxButtonChrome(.mapIcon)
                    }
                    .buttonStyle(MangoxPressStyle())
                    .accessibilityLabel("Discard ride")

                    Button {
                        viewModel.presentEndConfirmation()
                    } label: {
                        Text("END")
                            .mangoxButtonChrome(.endIcon)
                    }
                    .buttonStyle(MangoxPressStyle())
                    .accessibilityLabel("End ride")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    /// Inline GPS dot + label for embedding inside the nav card during recording.
    private func inlineGpsBadge(surface: OutdoorChromeSurface) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(gpsColor)
                .frame(width: 6, height: 6)
            Text(gpsLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(chromeMuted(surface))
        }
    }

    /// Replaces the inline accuracy pill when the fix is stale so we don’t duplicate a full-width weak-GPS banner on mapless layouts.
    @ViewBuilder
    private func navCardGpsLine(surface: OutdoorChromeSurface) -> some View {
        if ls.isGpsSignalStale {
            HStack(spacing: 5) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(AppColor.orange)
                Text("Weak signal · speed may lag")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppColor.orange.opacity(0.95))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Weak GPS signal. Live speed may be unavailable.")
        } else {
            inlineGpsBadge(surface: surface)
        }
    }

    /// Full-width directions / route card shown below the button row in compact (iPhone) layout.
    /// During recording the GPS badge is merged into the card's top-left corner.
    @ViewBuilder
    private func compactNavCardRow(
        surface: OutdoorChromeSurface, chromeStyle: CompactNavChromeStyle = .frostedGlass
    ) -> some View {
        if ns.mode == .turnByTurn, let turn = ns.nextTurn {
            applyCompactNavChrome(style: chromeStyle, shape: .roundedRect) {
                VStack(alignment: .leading, spacing: 6) {
                    navCardGpsLine(surface: surface)
                    HStack(spacing: 10) {
                        Image(systemName: turn.symbol)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(AppColor.mango)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(turn.instruction)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(chromeNavPrimary(surface))
                                .lineLimit(2)
                            Text("in \(turn.distanceText)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(chromeNavSecondary(surface))
                        }
                        Spacer(minLength: 4)
                        if let upcoming = ns.upcomingTurn {
                            VStack(spacing: 2) {
                                Image(systemName: upcoming.symbol)
                                    .font(.system(size: 12))
                                    .foregroundStyle(chromeNavSecondary(surface).opacity(0.85))
                                Text(upcoming.distanceText)
                                    .font(.system(size: 10))
                                    .foregroundStyle(chromeNavSecondary(surface).opacity(0.75))
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        } else if ns.mode == .followRoute,
            let hint = ns.followRouteHint
        {
            applyCompactNavChrome(style: chromeStyle, shape: .roundedRect) {
                VStack(alignment: .leading, spacing: 6) {
                    navCardGpsLine(surface: surface)
                    HStack(spacing: 10) {
                        Image(systemName: hint.symbol)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(AppColor.blue)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hint.instruction)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(chromeNavPrimary(surface))
                                .lineLimit(2)
                            Text("in \(hint.distanceText)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(chromeNavSecondary(surface))
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        } else if hasActiveRoute {
            applyCompactNavChrome(style: chromeStyle, shape: .roundedRect) {
                VStack(alignment: .leading, spacing: 6) {
                    navCardGpsLine(surface: surface)
                    HStack(spacing: 8) {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                            .font(.system(size: 13))
                            .foregroundStyle(chromeNavSecondary(surface))
                        Text(ns.routeName ?? viewModel.routeName ?? "Free Ride")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(chromeNavPrimary(surface))
                            .lineLimit(1)
                        Spacer()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        } else {
            // No route — compact GPS / weak-GPS chip (not a full-width bar).
            if chromeStyle == .bikeComputerSheet {
                applyCompactNavChrome(style: chromeStyle, shape: .capsule) {
                    Group {
                        if ls.isGpsSignalStale {
                            HStack(spacing: 5) {
                                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(AppColor.orange)
                                Text("Weak GPS")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(AppColor.orange.opacity(0.95))
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Weak GPS signal. Live speed may be unavailable.")
                        } else {
                            inlineGpsBadge(surface: surface)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
            } else {
                applyCompactNavChrome(style: chromeStyle, shape: .capsule) {
                    navCardGpsLine(surface: surface)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
            }
        }
    }

    // MARK: - GPS Status Badge

    private var gpsStatusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(gpsColor)
                .frame(width: 6, height: 6)
            Text(gpsLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .mangoxSurface(.mapOverlay, shape: .capsule)
    }

    private var gpsColor: Color {
        switch ls.signalConfidence {
        case .excellent:
            return AppColor.success
        case .good:
            return AppColor.yellow
        case .weak:
            return AppColor.orange
        case .stale, .searching:
            return AppColor.red
        }
    }

    private var gpsLabel: String {
        let acc = ls.horizontalAccuracy
        switch ls.signalConfidence {
        case .searching:
            return "Searching GPS"
        case .stale:
            return ls.isMotionFallbackActive ? "GPS Lost · Motion Assist" : "GPS Lost"
        case .weak:
            if ls.isMotionFallbackActive {
                return acc >= 0 ? "GPS Weak · Motion Assist" : "GPS Weak"
            }
            return acc >= 0 ? "GPS ±\(Int(acc))m" : "GPS Weak"
        case .good, .excellent:
            return acc >= 0 ? "GPS ±\(Int(acc))m" : "GPS"
        }
    }

    // MARK: - Metrics Grid (Compact)

    /// Compact “CarPlay-style” pre-start strip — full metrics appear after Start.
    private var preRideReadinessRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.outdoor.cycle")
                .font(.system(size: 22))
                .foregroundStyle(AppColor.mango.opacity(0.95))
            VStack(alignment: .leading, spacing: 4) {
                Text("Ready")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                Text("GPS updates below. Choose a route, then tap Start.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                viewModel.presentRouteSheet()
            } label: {
                Text("Route")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppColor.bg)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(AppColor.mango)
                    .clipShape(Capsule())
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var metricsGrid: some View {
        let isImperial = prefs.isImperial

        return VStack(spacing: 10) {
            // Primary: Speed + Duration
            HStack(spacing: 10) {
                metricCell(
                    value: liveGpsSpeedText(imperial: isImperial),
                    unit: AppFormat.speedUnit(imperial: isImperial),
                    label: "SPEED",
                    isPrimary: true
                )
                metricCell(
                    value: AppFormat.duration(ls.rideDuration),
                    unit: "",
                    label: "DURATION",
                    isPrimary: true
                )
            }

            // Secondary: Distance + Elevation + Avg Speed
            HStack(spacing: 10) {
                metricCell(
                    value: AppFormat.distanceString(
                        ls.totalDistance, imperial: isImperial),
                    unit: AppFormat.distanceUnit(imperial: isImperial),
                    label: "DISTANCE",
                    isPrimary: false
                )
                metricCell(
                    value: AppFormat.elevationString(
                        ls.totalElevationGain, imperial: isImperial),
                    unit: AppFormat.elevationUnit(imperial: isImperial),
                    label: "ELEVATION",
                    isPrimary: false
                )
                metricCell(
                    value: AppFormat.speedString(
                        ls.averageSpeed, imperial: isImperial),
                    unit: AppFormat.speedUnit(imperial: isImperial),
                    label: "AVG",
                    isPrimary: false
                )
            }

            // Grade row
            if ls.isRecording {
                gradeMetricCell
            }
        }
    }

    // MARK: - Metric Cell

    private func metricCell(value: String, unit: String, label: String, isPrimary: Bool)
        -> some View
    {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: isPrimary ? 36 : 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: isPrimary ? 14 : 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.35))
                .tracking(1.0)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, isPrimary ? 14 : 10)
        .background(Color.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var gradeMetricCell: some View {
        let grade = ls.currentGrade
        let symbol: String
        let color: Color
        if grade > 0.5 {
            symbol = "↑"
            color = grade > 8 ? AppColor.red : grade > 4 ? AppColor.yellow : AppColor.success
        } else if grade < -0.5 {
            symbol = "↓"
            color = Color.white.opacity(0.55)
        } else {
            symbol = "—"
            color = Color.white.opacity(0.35)
        }
        return HStack(spacing: 6) {
            Text(symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(color)
            Text(String(format: "%.1f%%", abs(grade)))
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
            Text("GRADE")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.35))
                .tracking(1.0)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(color.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - BLE Sensor Row (Compact)

    private var sensorRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if viewModel.isHRMonitorConnected {
                    compactSensorMetric(
                        icon: "heart.fill",
                        iconColor: AppColor.heartRate,
                        value: "\(viewModel.smoothedHeartRate)",
                        unit: "bpm",
                        border: AppColor.heartRate.opacity(0.35)
                    )
                }
                if viewModel.isTrainerConnected {
                    compactSensorMetric(
                        icon: "bolt.fill",
                        iconColor: AppColor.mango,
                        value: "\(viewModel.smoothedPower)",
                        unit: "W",
                        border: AppColor.mango.opacity(0.35)
                    )
                }
            }
            if viewModel.sensorCadence > 0 {
                compactSensorMetric(
                    icon: "arrow.trianglehead.2.clockwise.rotate.90",
                    iconColor: AppColor.blue,
                    value: "\(viewModel.sensorCadence)",
                    unit: "rpm",
                    border: AppColor.blue.opacity(0.35)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func compactSensorMetric(
        icon: String, iconColor: Color, value: String, unit: String, border: Color
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(iconColor)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
            Text(unit)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(border, lineWidth: 1)
        )
    }

    // MARK: - iPad Metrics Panels

    private var primaryMetrics: some View {
        let isImperial = prefs.isImperial

        return VStack(spacing: 12) {
            // Speed — big
            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(liveGpsSpeedText(imperial: isImperial))
                        .font(.system(size: 60, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                    Text(AppFormat.speedUnit(imperial: isImperial))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
                Text("SPEED")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.35))
                    .tracking(1.0)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .cardStyle()

            // Duration + Distance
            HStack(spacing: 12) {
                metricCell(
                    value: AppFormat.duration(ls.rideDuration),
                    unit: "",
                    label: "DURATION",
                    isPrimary: false
                )
                metricCell(
                    value: AppFormat.distanceString(
                        ls.totalDistance, imperial: isImperial),
                    unit: AppFormat.distanceUnit(imperial: isImperial),
                    label: "DISTANCE",
                    isPrimary: false
                )
            }
        }
    }

    private var sensorMetrics: some View {
        VStack(spacing: 12) {
            sensorRow
        }
    }

    private var secondaryMetrics: some View {
        let isImperial = prefs.isImperial

        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                metricCell(
                    value: AppFormat.elevationString(
                        ls.totalElevationGain, imperial: isImperial),
                    unit: AppFormat.elevationUnit(imperial: isImperial),
                    label: "ELEVATION",
                    isPrimary: false
                )
                metricCell(
                    value: AppFormat.speedString(
                        ls.averageSpeed, imperial: isImperial),
                    unit: AppFormat.speedUnit(imperial: isImperial),
                    label: "AVG SPEED",
                    isPrimary: false
                )
                metricCell(
                    value: AppFormat.speedString(ls.maxSpeed, imperial: isImperial),
                    unit: AppFormat.speedUnit(imperial: isImperial),
                    label: "MAX",
                    isPrimary: false
                )
            }
            if ls.isRecording {
                gradeMetricCell
            }
        }
    }

    // MARK: - Turn Banner

    // MARK: - Off Course Banner

    private func weakGpsBanner(
        surface: OutdoorChromeSurface, chromeStyle: CompactNavChromeStyle = .frostedGlass
    ) -> some View {
        let rowContent = HStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 14))
                .foregroundStyle(AppColor.orange)
            Text("Weak GPS — live speed may be unavailable")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(chromeNavPrimary(surface))
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)

        // Match `compactNavCardRow` / combined turn cards: same chrome family and corner radii as directions UI.
        return Group {
            switch chromeStyle {
            case .frostedGlass:
                rowContent
                    .mangoxSurface(.mapOverlay, shape: .rounded(18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(AppColor.orange.opacity(0.4), lineWidth: 1)
                    )
            case .bikeComputerSheet:
                applyCompactNavChrome(style: .bikeComputerSheet, shape: .roundedRect) {
                    rowContent
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(AppColor.orange.opacity(0.45), lineWidth: 1)
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Weak GPS signal. Live speed may be unavailable.")
    }

    private func offCourseBanner(
        surface: OutdoorChromeSurface, chromeStyle: CompactNavChromeStyle = .frostedGlass
    ) -> some View {
        let rowContent = HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(AppColor.yellow)
            Text("Off course — \(Int(ns.deviationDistance))m away")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(chromeNavPrimary(surface))
            Spacer()
            if ns.mode == .turnByTurn {
                Button("Re-route") {
                    Task {
                        if let loc = ls.currentLocation {
                            await ns.reroute(from: loc.coordinate)
                        }
                    }
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppColor.bg)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(AppColor.mango)
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)

        return Group {
            switch chromeStyle {
            case .frostedGlass:
                rowContent
                    .mangoxSurface(.mapOverlay, shape: .rounded(18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(AppColor.yellow.opacity(0.35), lineWidth: 1)
                    )
            case .bikeComputerSheet:
                applyCompactNavChrome(style: .bikeComputerSheet, shape: .roundedRect) {
                    rowContent
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(AppColor.yellow.opacity(0.4), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Climb Banner

    @ViewBuilder
    private var climbBanner: some View {
        if ls.isRecording, let climb = ls.activeClimb {
            HStack(spacing: 8) {
                Image(systemName: "mountain.2.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColor.yellow)
                Text(String(format: "Climbing · %.1f%%", climb.grade))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(Int(climb.distanceSoFar))m")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .mangoxSurface(.mapOverlay, shape: .rounded(14))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(AppColor.yellow.opacity(0.30), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
    }

    // MARK: - Lap Toast

    @ViewBuilder
    private var lapToastView: some View {
        if viewModel.showLapToast, let lap = viewModel.latestLapRecord {
            VStack(spacing: 2) {
                Text("Lap \(lap.number) complete")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                HStack(spacing: 6) {
                    Text(AppFormat.duration(lap.duration))
                    Text("·")
                    Text(lap.paceString)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .mangoxSurface(.mapOverlay, shape: .capsule)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Control Bar

    /// Compact drawer bottom: Start button (pre-ride only).
    /// AUTO-PAUSED is now a floating pill above the card so card height stays constant.
    /// End/Discard are in the top-right overlay when recording.
    @ViewBuilder
    private var compactDrawerBottom: some View {
        if !ls.isRecording {
            Button {
                viewModel.startRide(using: ls)
            } label: {
                Text("Start ride")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppColor.bg)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(AppColor.mango)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(MangoxPressStyle())
        }
    }

    private var controlBar: some View {
        HStack(spacing: 12) {
            if ls.isRecording {
                // Discard
                Button {
                    viewModel.presentDiscardConfirmation()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColor.red)
                        .frame(width: 48, height: 48)
                        .background(AppColor.red.opacity(0.1))
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(AppColor.red.opacity(0.2), lineWidth: 1))
                }

                // Pause / Resume
                if ls.isAutoPaused {
                    Text("AUTO-PAUSED")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppColor.yellow)
                        .tracking(1.0)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(AppColor.yellow.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(AppColor.yellow.opacity(0.25), lineWidth: 1)
                        )
                } else {
                    Spacer()
                }

                // End
                Button {
                    viewModel.presentEndConfirmation()
                } label: {
                    Text("END")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AppColor.bg)
                        .frame(width: 80, height: 48)
                        .background(AppColor.red)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(MangoxPressStyle())

            } else {
                // Start — explicit ride begin (no auto-start on screen open)
                Button {
                    viewModel.startRide(using: ls)
                } label: {
                    Text("Start ride")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(AppColor.bg)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(AppColor.mango)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(MangoxPressStyle())
            }
        }
    }

    // MARK: - Route planning sheet (CarPlay-style: pick route first)

    private var routePlanningSheet: some View {
        NavigationStack {
            Group {
                switch viewModel.routeSheetPage {
                case .menu:
                    routeMenuPage
                case .search:
                    routeSearchPage
                }
            }
            .background(AppColor.bg)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(ns.isCalculating)
        .overlay {
            if ns.isCalculating {
                ZStack {
                    Color.black.opacity(0.42)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(AppColor.mango)
                            .scaleEffect(1.1)
                        Text("Building route…")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(24)
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }

    private var routeMenuPage: some View {
        ScrollView {
            VStack(spacing: 12) {
                menuActionButton(
                    title: "Free ride", subtitle: "No route — just ride and record",
                    icon: "figure.outdoor.cycle"
                ) {
                    viewModel.clearRouteSelection()
                    viewModel.dismissRouteSheet()
                }
                menuActionButton(
                    title: "Import GPX", subtitle: "Load a .gpx file from Files",
                    icon: "doc.badge.arrow.up"
                ) {
                    viewModel.presentRouteImporter()
                }
                menuActionButton(
                    title: "Navigate to destination", subtitle: "Apple Maps cycling directions",
                    icon: "arrow.triangle.turn.up.right.diamond"
                ) {
                    viewModel.showRouteSearch()
                }
                Toggle(isOn: binding(\.isHybridMapStyle)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Satellite / hybrid map")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("More contrast outdoors")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .tint(AppColor.mango)
                .padding(14)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if hasActiveRoute || viewModel.hasRoute {
                    Button(role: .destructive) {
                        viewModel.clearRouteSelection()
                    } label: {
                        Text("Clear route")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(16)
        }
        .navigationTitle("Route")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    viewModel.dismissRouteSheet()
                }
                .foregroundStyle(AppColor.mango)
            }
        }
    }

    private func menuActionButton(
        title: String, subtitle: String, icon: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(AppColor.mango)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.25))
            }
            .padding(14)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var routeSearchPage: some View {
        RouteSearchPage(
            completer: searchCompleter,
            onSelect: { item in
                selectDestination(item)
            },
            onBack: {
                viewModel.routeSheetPage = .menu
            },
            searchBiasCoordinate: mapCameraService.destinationSearchBiasCoordinate,
            searchMapBias: destinationSearchMapBias
        )
    }

    // MARK: - Actions

    /// Prefetch cycling directions on the setup screen, then leave setup only when the route is ready.
    private func startNavigation() {
        Task { @MainActor in
            _ = await viewModel.startNavigation(
                destination: viewModel.selectedDestination,
                currentLocation: ls.currentLocation
            )
        }
    }

    /// Same prefetch flow when picking a destination from the in-ride route sheet.
    private func selectDestination(_ item: MKMapItem) {
        Task { @MainActor in
            if await viewModel.selectDestination(
                item,
                currentLocation: ls.currentLocation
            ) {
                // Brief delay so user sees the route land on the map before sheet closes.
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    private func endRide() {
        ls.stopRecording()
        Task { await viewModel.endLiveActivity() }
        let plannedRouteDistanceMeters =
            ns.routeDistance > 0
            ? ns.routeDistance
            : (viewModel.hasRoute ? viewModel.totalRouteDistance : 0)

        let rideModeDraft: OutdoorRideModeDraft
        switch ns.mode {
        case .freeRide:
            rideModeDraft = .freeRide
        case .followRoute:
            rideModeDraft = .followRoute(routeName: ns.routeName ?? viewModel.routeName)
        case .turnByTurn:
            rideModeDraft = .turnByTurn(
                routeName: ns.routeName,
                destinationName: ns.destination?.name,
                destinationSummary: ns.destination?.addressRepresentations?
                    .fullAddress(includingRegion: true, singleLine: true)
            )
        }

        let finishedWorkoutID = viewModel.completeRide(
            session: OutdoorRideSessionSnapshot(
                rideDuration: ls.rideDuration,
                totalDistance: ls.totalDistance,
                totalElevationGain: ls.totalElevationGain,
                averageSpeed: ls.averageSpeed,
                completedLaps: ls.completedLaps
            ),
            plannedRouteDistanceMeters: plannedRouteDistanceMeters,
            mode: rideModeDraft
        )
        navigationPath.removeLast()
        navigationPath.append(AppRoute.summary(workoutID: finishedWorkoutID))
    }

    private func discardRide() {
        viewModel.discardRide(using: ls)
        Task { await viewModel.endLiveActivity() }
        navigationPath.removeLast()
    }
}

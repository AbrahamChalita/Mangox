import CoreBluetooth
import MapKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum ConnectionStartMode {
    case ride
    case ftpTest
}

private enum RideLaunchMode: String, CaseIterable, Identifiable {
    case indoor
    case outdoor

    var id: String { rawValue }

    var label: String {
        switch self {
        case .indoor: return "Indoor"
        case .outdoor: return "Outdoor"
        }
    }

    var icon: String {
        switch self {
        case .indoor: return "bolt.fill"
        case .outdoor: return "location.fill"
        }
    }
}

private struct ConnectedDeviceStateRow: Identifiable {
    let id = UUID()
    let name: String
    let type: DeviceType
    let state: BLEConnectionState
}

struct ConnectionView: View {
    @Environment(BLEManager.self) private var bleManager
    @Environment(DataSourceCoordinator.self) private var dataSource
    @Environment(RouteManager.self) private var routeManager
    @Environment(LocationManager.self) private var locationManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    @Query(sort: \CustomWorkoutTemplate.createdAt, order: .reverse)
    private var customWorkoutTemplates: [CustomWorkoutTemplate]
    @Binding var navigationPath: NavigationPath
    var startMode: ConnectionStartMode = .ride
    var planID: String? = nil
    var planDayID: String? = nil
    /// When true, the indoor/outdoor ride mode picker is hidden and the ride is treated as indoor (e.g. user tapped Indoor on Home).
    var indoorRideLocked: Bool = false
    /// Pair HR + speed/cadence for outdoor rides — no trainer, route, or start-ride CTA.
    var outdoorSensorsOnly: Bool = false

    @State private var showRouteImporter = false
    @State private var routeImportError: String?
    @State private var scanPulse = false
    @State private var routeDropTargeted = false
    @State private var rideLaunchMode: RideLaunchMode = .indoor
    @State private var selectedCustomTemplateID: UUID?
    @State private var showZWOImporter = false
    @State private var zwoImportError: String?

    private let prefs = RidePreferences.shared

    private let accentSuccess = AppColor.success
    private let accentYellow = AppColor.yellow
    private let accentOrange = AppColor.orange
    private let accentRed = AppColor.red
    private let accentBlue = AppColor.blue
    private let accentMango = AppColor.mango
    private let bg = AppColor.bg

    private var canStartRide: Bool {
        if outdoorSensorsOnly { return true }
        guard startMode == .ride else {
            return dataSource.isConnected
        }

        switch rideLaunchMode {
        case .indoor:
            return bleManager.trainerConnectionState.isConnected
                || dataSource.wifiConnectionState.isConnected
        case .outdoor:
            return true
        }
    }

    private var wifiStateAsBLE: BLEConnectionState {
        switch dataSource.wifiConnectionState {
        case .disconnected: return .disconnected
        case .discovering: return .scanning
        case .connecting(let name): return .connecting(name)
        case .connected(let name): return .connected(name)
        case .error: return .disconnected
        }
    }

    // MARK: - Status banner copy (full-width rows; avoids squeezed 3-column pills)

    private var showTrainerStatusRow: Bool { !outdoorSensorsOnly }
    private var showWiFiStatusRow: Bool {
        !outdoorSensorsOnly && startMode == .ride && rideLaunchMode == .indoor
    }
    private var showCSCStatusRow: Bool { outdoorSensorsOnly }

    private var trainerStatusBannerTitle: String {
        switch bleManager.trainerConnectionState {
        case .connected:
            return bleManager.connectedTrainerName ?? "Connected"
        case .connecting(let name):
            return "Connecting to \(name)…"
        case .scanning:
            return "Searching for trainers…"
        case .disconnected:
            return "Not connected"
        }
    }

    private var wifiStatusBannerTitle: String {
        switch dataSource.wifiConnectionState {
        case .connected(let name), .connecting(let name):
            return name
        case .error(let message):
            let m = message
            return m.count > 56 ? String(m.prefix(53)) + "…" : m
        case .discovering:
            return "Searching on your network…"
        case .disconnected:
            return "Not connected"
        }
    }

    private var heartRateStatusBannerTitle: String {
        switch bleManager.hrConnectionState {
        case .connected:
            return bleManager.connectedHRName ?? "Connected"
        case .connecting(let name):
            return "Connecting to \(name)…"
        case .scanning:
            return "Searching for heart rate monitors…"
        case .disconnected:
            return "Not connected"
        }
    }

    private var cscStatusBannerTitle: String {
        switch bleManager.cscConnectionState {
        case .connected:
            return bleManager.connectedCSCName ?? "Connected"
        case .connecting(let name):
            return "Connecting to \(name)…"
        case .scanning:
            return "Searching for sensors…"
        case .disconnected:
            return "Not connected"
        }
    }

    private var wifiStatusBannerAccent: Color? {
        if case .error = dataSource.wifiConnectionState { return AppColor.orange }
        return nil
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    statusBanner
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 20)

                    if bleManager.bluetoothState != .poweredOn
                        && (rideLaunchMode == .indoor || outdoorSensorsOnly)
                    {
                        bluetoothOffCard
                            .padding(.horizontal, 20)
                    } else {
                        if startMode == .ride, planDayID == nil, !indoorRideLocked,
                            !outdoorSensorsOnly
                        {
                            rideModeCard
                                .padding(.horizontal, 20)
                                .padding(.bottom, 20)
                        }

                        // Devices section
                        sectionHeader(
                            title: outdoorSensorsOnly ? "SENSORS" : "DEVICES",
                            icon: "antenna.radiowaves.left.and.right",
                            prominent: true
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)

                        scanButton
                            .padding(.horizontal, 20)
                            .padding(.bottom, 14)

                        devicesCard
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)

                        if startMode == .ride, rideLaunchMode == .indoor, !outdoorSensorsOnly {
                            sectionHeader(title: "WIFI TRAINERS", icon: "wifi", prominent: true)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 10)
                            wifiTrainersCard
                                .padding(.horizontal, 20)
                                .padding(.bottom, 24)
                        }

                        // Route section (ride mode only)
                        if startMode == .ride, !outdoorSensorsOnly {
                            sectionHeader(title: "ROUTE", icon: "map")
                                .padding(.horizontal, 20)
                                .padding(.bottom, 10)

                            routeCard
                                .padding(.horizontal, 20)
                                .padding(.bottom, 24)
                        }

                        // Zwift-style .zwo library (indoor free ride only — plan rides use the calendar day)
                        if startMode == .ride, rideLaunchMode == .indoor, !outdoorSensorsOnly,
                            planDayID == nil
                        {
                            sectionHeader(title: "CUSTOM WORKOUT", icon: "doc.text.fill")
                                .padding(.horizontal, 20)
                                .padding(.bottom, 10)

                            customWorkoutLibraryCard
                                .padding(.horizontal, 20)
                                .padding(.bottom, 24)
                        }

                        // Settings quick glance
                        if !outdoorSensorsOnly {
                            setupSummaryCard
                                .padding(.horizontal, 20)
                                .padding(.bottom, 24)
                        }
                    }

                    #if DEBUG
                        if !outdoorSensorsOnly {
                            debugOverlay
                                .padding(.horizontal, 20)
                                .padding(.bottom, 16)
                        }
                    #endif

                    // Bottom spacer for sticky action bar
                    Color.clear.frame(height: 140)
                }
            }
            .scrollIndicators(.hidden)

            // Sticky bottom action bar
            if bleManager.bluetoothState == .poweredOn
                || (startMode == .ride && rideLaunchMode == .outdoor) || outdoorSensorsOnly
            {
                stickyActionBar
            }
        }
        .background(bg)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(screenTitle)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                    Text(screenSubtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
        .onAppear {
            locationManager.setup()
            dataSource.updateActiveSource()
            syncRideGoalDistanceFromPrefs()
            if indoorRideLocked {
                rideLaunchMode = .indoor
            }
            if planDayID != nil {
                selectedCustomTemplateID = nil
            }
            if outdoorSensorsOnly {
                if bleManager.bluetoothState == .poweredOn {
                    bleManager.reconnectOrScan()
                }
            } else if rideLaunchMode == .indoor,
                bleManager.bluetoothState == .poweredOn,
                !bleManager.trainerConnectionState.isConnected
            {
                bleManager.reconnectOrScan()
            }
        }
        .onDisappear {
            bleManager.stopScan()
            dataSource.stopWiFiDiscovery()
        }
        .fileImporter(
            isPresented: $showRouteImporter,
            allowedContentTypes: [UTType(filenameExtension: "gpx") ?? .xml],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task {
                    do {
                        try await routeManager.loadGPX(from: url)
                    } catch {
                        await MainActor.run {
                            routeImportError = error.localizedDescription
                        }
                    }
                }
            case .failure(let error):
                routeImportError = error.localizedDescription
            }
        }
        .alert(
            "Route Import Failed",
            isPresented: Binding(
                get: { routeImportError != nil },
                set: { if !$0 { routeImportError = nil } }
            ),
            actions: {
                Button("OK") { routeImportError = nil }
            },
            message: {
                Text(routeImportError ?? "")
            })
        .fileImporter(
            isPresented: $showZWOImporter,
            allowedContentTypes: [UTType(filenameExtension: "zwo") ?? .xml],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task {
                    var data: Data?
                    if url.startAccessingSecurityScopedResource() {
                        defer { url.stopAccessingSecurityScopedResource() }
                        data = try? Data(contentsOf: url)
                    } else {
                        data = try? Data(contentsOf: url)
                    }
                    guard let raw = data else {
                        await MainActor.run {
                            zwoImportError = "Could not read the selected file."
                        }
                        return
                    }
                    do {
                        let parsed = try ZWOImportService.parse(data: raw)
                        await MainActor.run {
                            let t = CustomWorkoutTemplate(name: parsed.name, intervals: parsed.intervals)
                            modelContext.insert(t)
                            try? modelContext.save()
                            selectedCustomTemplateID = t.id
                        }
                    } catch {
                        await MainActor.run {
                            zwoImportError =
                                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        }
                    }
                }
            case .failure(let error):
                zwoImportError = error.localizedDescription
            }
        }
        .alert(
            "Workout Import Failed",
            isPresented: Binding(
                get: { zwoImportError != nil },
                set: { if !$0 { zwoImportError = nil } }
            ),
            actions: {
                Button("OK") { zwoImportError = nil }
            },
            message: {
                Text(zwoImportError ?? "")
            })
        .onChange(of: rideLaunchMode) { _, newMode in
            if newMode == .outdoor {
                selectedCustomTemplateID = nil
            }
        }
    }

    // MARK: - Status Banner

    private var statusBannerColumnCount: Int {
        var n = 0
        if showTrainerStatusRow { n += 1 }
        if showWiFiStatusRow { n += 1 }
        n += 1  // heart rate
        if showCSCStatusRow { n += 1 }
        return n
    }

    /// Minimum width before we switch to the stacked layout (narrow phone / portrait).
    private var statusBannerHorizontalMinWidth: CGFloat {
        let n = statusBannerColumnCount
        guard n > 0 else { return 0 }
        return CGFloat(n) * 140 + CGFloat(max(0, n - 1)) * 10
    }

    private var statusBanner: some View {
        ViewThatFits(in: .horizontal) {
            statusBannerHorizontal
                .frame(minWidth: statusBannerHorizontalMinWidth)
            statusBannerVertical
        }
        .padding(.vertical, 4)
        .background(Color.white.opacity(AppOpacity.pillBg))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var statusBannerHorizontal: some View {
        HStack(alignment: .top, spacing: 10) {
            if showTrainerStatusRow {
                connectionStatusRow(
                    icon: "bicycle",
                    category: "Trainer",
                    title: trainerStatusBannerTitle,
                    state: bleManager.trainerConnectionState
                )
                .frame(maxWidth: .infinity)
            }
            if showWiFiStatusRow {
                connectionStatusRow(
                    icon: "wifi",
                    category: "Wi‑Fi",
                    title: wifiStatusBannerTitle,
                    state: wifiStateAsBLE,
                    accentOverride: wifiStatusBannerAccent
                )
                .frame(maxWidth: .infinity)
            }
            connectionStatusRow(
                icon: "heart.fill",
                category: "Heart rate",
                title: heartRateStatusBannerTitle,
                state: bleManager.hrConnectionState
            )
            .frame(maxWidth: .infinity)
            if showCSCStatusRow {
                connectionStatusRow(
                    icon: "arrow.trianglehead.2.clockwise.rotate.90",
                    category: "Speed / cadence",
                    title: cscStatusBannerTitle,
                    state: bleManager.cscConnectionState
                )
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 4)
    }

    private var statusBannerVertical: some View {
        VStack(spacing: 0) {
            if showTrainerStatusRow {
                connectionStatusRow(
                    icon: "bicycle",
                    category: "Trainer",
                    title: trainerStatusBannerTitle,
                    state: bleManager.trainerConnectionState
                )
            }
            if showWiFiStatusRow {
                if showTrainerStatusRow { connectionStatusDivider }
                connectionStatusRow(
                    icon: "wifi",
                    category: "Wi‑Fi",
                    title: wifiStatusBannerTitle,
                    state: wifiStateAsBLE,
                    accentOverride: wifiStatusBannerAccent
                )
            }
            if showTrainerStatusRow || showWiFiStatusRow {
                connectionStatusDivider
            }
            connectionStatusRow(
                icon: "heart.fill",
                category: "Heart rate",
                title: heartRateStatusBannerTitle,
                state: bleManager.hrConnectionState
            )
            if showCSCStatusRow {
                connectionStatusDivider
                connectionStatusRow(
                    icon: "arrow.trianglehead.2.clockwise.rotate.90",
                    category: "Speed / cadence",
                    title: cscStatusBannerTitle,
                    state: bleManager.cscConnectionState
                )
            }
        }
    }

    private var connectionStatusDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 1)
            .padding(.leading, 56)
    }

    private func connectionStatusRow(
        icon: String,
        category: String,
        title: String,
        state: BLEConnectionState,
        accentOverride: Color? = nil
    ) -> some View {
        let isConnected = state.isConnected
        let isConnecting: Bool = {
            if case .connecting = state { return true }
            return false
        }()
        let isScanning: Bool = {
            if case .scanning = state { return true }
            return false
        }()
        let pillColor: Color = {
            if isConnected { return accentSuccess }
            if isConnecting || isScanning { return accentYellow }
            return accentOverride ?? Color.white.opacity(0.28)
        }()

        return HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(pillColor.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(pillColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(category.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.38))
                    .tracking(0.6)

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(isConnected ? 0.95 : 0.55))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isConnected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(accentSuccess)
                    .accessibilityHidden(true)
            } else if isConnecting || isScanning {
                ProgressView()
                    .tint(accentYellow)
                    .scaleEffect(0.85)
                    .frame(width: 22, height: 22)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(category), \(title)")
    }

    // MARK: - Ride Mode

    private var rideModeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "figure.outdoor.cycle")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
                Text("RIDE MODE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.3))
                    .tracking(1.5)
            }

            HStack(spacing: 10) {
                ForEach(RideLaunchMode.allCases) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            rideLaunchMode = mode
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 12, weight: .semibold))
                            Text(mode.label)
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundStyle(rideLaunchMode == mode ? AppColor.bg : .white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            rideLaunchMode == mode ? accentSuccess : Color.white.opacity(0.05)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(MangoxPressStyle())
                }
            }

            Text(rideModeHint)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.38))
        }
        .padding(16)
        .background(Color.white.opacity(AppOpacity.pillBg))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Section Header

    private func sectionHeader(title: String, icon: String, prominent: Bool = false) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: prominent ? 13 : 11, weight: .semibold))
                .foregroundStyle(.white.opacity(prominent ? 0.6 : 0.3))
            Text(title)
                .font(.system(size: prominent ? 13 : 11, weight: .bold))
                .foregroundStyle(.white.opacity(prominent ? 0.7 : 0.35))
                .tracking(prominent ? 1.5 : 2)
            Spacer()
        }
    }

    // MARK: - Scan Button

    private var scanButton: some View {
        Button {
            if bleManager.isScanningForDevices {
                bleManager.stopScan()
                scanPulse = false
            } else {
                bleManager.startScan()
                if accessibilityReduceMotion {
                    scanPulse = true
                } else {
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                        scanPulse = true
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    if bleManager.isScanningForDevices {
                        Circle()
                            .fill(accentSuccess.opacity(scanPulse ? 0.2 : 0.05))
                            .frame(width: 36, height: 36)
                            .animation(
                                accessibilityReduceMotion
                                    ? .default
                                    : .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                                value: scanPulse
                            )

                        ProgressView()
                            .tint(accentSuccess)
                            .scaleEffect(0.75)
                    } else {
                        Circle()
                            .fill(accentSuccess.opacity(0.12))
                            .frame(width: 36, height: 36)

                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(accentSuccess)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(bleManager.isScanningForDevices ? "Scanning…" : "Scan for Devices")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(
                        bleManager.isScanningForDevices
                            ? "Tap to stop"
                            : (outdoorSensorsOnly
                                ? "Find speed/cadence sensors & heart rate monitors"
                                : "Find nearby trainers & HR monitors")
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
                }

                Spacer()

                Image(
                    systemName: bleManager.isScanningForDevices ? "stop.circle" : "arrow.clockwise"
                )
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(accentSuccess.opacity(0.6))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(accentSuccess.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(accentSuccess.opacity(0.15), lineWidth: 1)
            )
        }
    }

    // MARK: - Devices Card

    // MARK: - Connected Device Rows (built from BLEManager state, not discoveredPeripherals)

    private var connectedDeviceRows: [ConnectedDeviceStateRow] {
        var rows: [ConnectedDeviceStateRow] = []
        if !outdoorSensorsOnly, let name = bleManager.connectedTrainerName {
            rows.append(
                ConnectedDeviceStateRow(
                    name: name, type: .trainer, state: bleManager.trainerConnectionState))
        }
        if let name = bleManager.connectedHRName {
            rows.append(
                ConnectedDeviceStateRow(
                    name: name, type: .heartRateMonitor, state: bleManager.hrConnectionState))
        }
        if let name = bleManager.connectedCSCName {
            rows.append(
                ConnectedDeviceStateRow(
                    name: name, type: .cyclingSpeedCadence, state: bleManager.cscConnectionState))
        }
        return rows
    }

    /// IDs of peripherals that are already connected — used to filter scan results so
    /// the same device doesn't appear twice (once in "Connected" and once in scan list).
    private var connectedPeripheralIDs: Set<UUID> {
        var ids = Set<UUID>()
        // Match by name since we don't expose the CBPeripheral from BLEManager for
        // already-connected devices. Discovered peripherals whose name matches a
        // connected device are considered duplicates.
        let connectedNames = Set(connectedDeviceRows.map(\.name))
        for d in bleManager.discoveredPeripherals where connectedNames.contains(d.name) {
            ids.insert(d.id)
        }
        return ids
    }

    private var devicesCard: some View {
        let connected = connectedDeviceRows
        let dupIDs = connectedPeripheralIDs

        // Scan results minus already-connected devices
        let scanResults = bleManager.discoveredPeripherals.filter { !dupIDs.contains($0.id) }
        let scanForDisplay =
            outdoorSensorsOnly ? scanResults.filter { $0.deviceType != .trainer } : scanResults
        let trainers = scanForDisplay.filter { $0.deviceType == .trainer }
        let hrMonitors = scanForDisplay.filter { $0.deviceType == .heartRateMonitor }
        let cscSensors = scanForDisplay.filter { $0.deviceType == .cyclingSpeedCadence }
        let unknowns = scanForDisplay.filter { $0.deviceType == .unknown }
        let hasScanResults = !scanForDisplay.isEmpty
        let hasAnything = !connected.isEmpty || hasScanResults

        return VStack(spacing: 0) {
            if !hasAnything {
                emptyDevicesPlaceholder
            } else {
                VStack(spacing: 0) {
                    // Connected devices always shown at the top
                    if !connected.isEmpty {
                        connectedDevicesSection(devices: connected)
                    }

                    // Scan results below
                    if hasScanResults {
                        if !connected.isEmpty { sectionDivider }

                        if !trainers.isEmpty {
                            deviceSection(
                                title: "Trainers", icon: "bicycle", devices: trainers,
                                type: .trainer)
                        }
                        if !hrMonitors.isEmpty {
                            if !trainers.isEmpty { sectionDivider }
                            deviceSection(
                                title: "HR Monitors", icon: "heart.fill", devices: hrMonitors,
                                type: .heartRateMonitor)
                        }
                        if !cscSensors.isEmpty {
                            if !trainers.isEmpty || !hrMonitors.isEmpty { sectionDivider }
                            deviceSection(
                                title: "Speed / Cadence",
                                icon: "arrow.trianglehead.2.clockwise.rotate.90",
                                devices: cscSensors, type: .cyclingSpeedCadence)
                        }
                        if !unknowns.isEmpty {
                            if !trainers.isEmpty || !hrMonitors.isEmpty || !cscSensors.isEmpty {
                                sectionDivider
                            }
                            deviceSection(
                                title: "Other Devices", icon: "questionmark.circle",
                                devices: unknowns, type: .unknown)
                        }
                    }

                    // Scanning indicator at the bottom when there are already items
                    if bleManager.isScanningForDevices && !scanForDisplay.isEmpty {
                        sectionDivider
                        scanningFooter
                    }

                    // Gentle prompt to scan for more when idle with connected devices but no scan results
                    if !connected.isEmpty && !hasScanResults && !bleManager.isScanningForDevices {
                        sectionDivider
                        scanForMorePrompt
                    }
                }
            }
        }
        .background(Color.white.opacity(AppOpacity.pillBg))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(AppOpacity.cardBorder), lineWidth: 1)
        )
    }

    // MARK: - WiFi Trainers Card

    private var isWiFiDiscovering: Bool {
        if case .discovering = dataSource.wifiConnectionState { return true }
        return false
    }

    private var isWiFiConnecting: Bool {
        if case .connecting = dataSource.wifiConnectionState { return true }
        return false
    }

    private var wifiTrainersCard: some View {
        let wifiState = dataSource.wifiConnectionState
        let connectedID = dataSource.wifiService.connectedTrainer?.id
        let trainers = dataSource.discoveredWiFiTrainers.filter { t in
            guard let connectedID else { return true }
            return t.id != connectedID
        }
        let showWifiRows =
            wifiState.isConnected || isWiFiDiscovering || isWiFiConnecting || !trainers.isEmpty
        let showBrowsingFooter = isWiFiDiscovering && trainers.isEmpty && !wifiState.isConnected

        return VStack(spacing: 0) {
            wifiTrainerDiscoveryButton

            Text(
                "Finds trainers on your Wi‑Fi that advertise as a bridge (e.g. Zwift Companion, Wahoo, FTMS)."
            )
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.28))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, showWifiRows || showBrowsingFooter ? 10 : 14)

            if case .error(let message) = wifiState {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(accentOrange)
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }

            if showWifiRows {
                Rectangle()
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 1)
                    .padding(.horizontal, 16)

                if wifiState.isConnected, let connected = dataSource.wifiService.connectedTrainer {
                    wifiConnectedRow(trainer: connected)
                }

                if case .connecting(let name) = wifiState, !wifiState.isConnected {
                    wifiConnectingRow(name: name)
                }

                ForEach(trainers) { trainer in
                    wifiTrainerRow(
                        trainer: trainer,
                        connectDisabled: wifiState.isConnected || isWiFiConnecting
                    )
                }
            } else if !isWiFiDiscovering {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.2))
                    Text("Search to discover trainers on your network")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.28))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }

            if showBrowsingFooter {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(accentBlue.opacity(0.7))
                        .scaleEffect(0.75)
                    Text("Browsing Bonjour services…")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.32))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
        .background(Color.white.opacity(AppOpacity.pillBg))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(AppOpacity.cardBorder), lineWidth: 1)
        )
    }

    private var wifiTrainerDiscoveryButton: some View {
        Button {
            if isWiFiDiscovering {
                dataSource.stopWiFiDiscovery()
            } else {
                dataSource.startWiFiDiscovery()
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    if isWiFiDiscovering {
                        Circle()
                            .fill(accentBlue.opacity(0.12))
                            .frame(width: 36, height: 36)
                        ProgressView()
                            .tint(accentBlue)
                            .scaleEffect(0.75)
                    } else {
                        Circle()
                            .fill(accentBlue.opacity(0.12))
                            .frame(width: 36, height: 36)
                        Image(systemName: "wifi")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(accentBlue)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(isWiFiDiscovering ? "Searching…" : "Search Wi‑Fi Trainers")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(isWiFiDiscovering ? "Tap to stop" : "Bonjour / mDNS on your local network")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
                }

                Spacer()

                Image(systemName: isWiFiDiscovering ? "stop.circle" : "arrow.clockwise")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(accentBlue.opacity(0.6))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(accentBlue.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(accentBlue.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private func wifiConnectedRow(trainer: DiscoveredWiFiTrainer) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accentSuccess.opacity(0.1))
                    .frame(width: 40, height: 40)
                Image(systemName: "wifi")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accentSuccess)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(trainer.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                Text("\(trainer.ipAddress) · \(trainer.port)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.25))
            }

            Spacer()

            Button("Disconnect") {
                dataSource.disconnectWiFi()
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(accentOrange)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func wifiConnectingRow(name: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(accentYellow)
                .scaleEffect(0.85)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                Text("Connecting…")
                    .font(.system(size: 11))
                    .foregroundStyle(accentYellow.opacity(0.85))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func wifiTrainerRow(trainer: DiscoveredWiFiTrainer, connectDisabled: Bool) -> some View
    {
        Button {
            dataSource.connectWiFi(to: trainer)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accentBlue.opacity(0.08))
                        .frame(width: 40, height: 40)
                    Image(systemName: "wifi")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(accentBlue.opacity(0.85))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(trainer.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                    Text("\(trainer.ipAddress) · \(trainer.port)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.25))
                }

                Spacer()

                Text("Connect")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(connectDisabled ? 0.25 : 0.5))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.1)))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(connectDisabled)
    }

    // MARK: - Connected Devices Section

    private func connectedDevicesSection(devices: [ConnectedDeviceStateRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(accentSuccess.opacity(0.6))
                Text("CONNECTED")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accentSuccess.opacity(0.5))
                    .tracking(1.5)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            ForEach(devices) { device in
                connectedDeviceRow(device: device)
                    .padding(.horizontal, 12)

                if device.id != devices.last?.id {
                    Rectangle()
                        .fill(Color.white.opacity(0.03))
                        .frame(height: 1)
                        .padding(.leading, 62)
                        .padding(.trailing, 12)
                }
            }

            Spacer().frame(height: 10)
        }
    }

    private func connectedDeviceRow(device: ConnectedDeviceStateRow) -> some View {
        let icon: String = {
            switch device.type {
            case .heartRateMonitor: return "heart.fill"
            case .trainer: return "bicycle"
            case .cyclingSpeedCadence: return "arrow.trianglehead.2.clockwise.rotate.90"
            case .unknown: return "sensor.tag.radiowaves.forward"
            }
        }()
        let typeLabel: String = {
            switch device.type {
            case .heartRateMonitor: return "Heart Rate Monitor"
            case .trainer: return "Trainer"
            case .cyclingSpeedCadence: return "Speed / Cadence Sensor"
            case .unknown: return "Device"
            }
        }()

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accentSuccess.opacity(0.1))
                    .frame(width: 40, height: 40)

                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accentSuccess)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)

                Text(typeLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.25))
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(accentSuccess)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }

    // MARK: - Scanning Footer & Scan-for-More Prompt

    private var scanningFooter: some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(accentSuccess.opacity(0.6))
                .scaleEffect(0.65)
            Text("Scanning for more devices…")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.3))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var scanForMorePrompt: some View {
        Button {
            bleManager.startScan()
            if accessibilityReduceMotion {
                scanPulse = true
            } else {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    scanPulse = true
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
                Text("Scan for more devices")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
                Spacer()
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.2))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty / Scanning Placeholder

    private var emptyDevicesPlaceholder: some View {
        VStack(spacing: 10) {
            if bleManager.isScanningForDevices {
                HStack(spacing: 10) {
                    ForEach(0..<3) { i in
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.04))
                            .frame(height: 50)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(
                                        LinearGradient(
                                            colors: [.clear, Color.white.opacity(0.03), .clear],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .offset(
                                        x: accessibilityReduceMotion ? 0 : (scanPulse ? 100 : -100)
                                    )
                                    .animation(
                                        accessibilityReduceMotion
                                            ? .default
                                            : .easeInOut(duration: 1.5)
                                                .repeatForever(autoreverses: false)
                                                .delay(Double(i) * 0.2),
                                        value: scanPulse
                                    )
                            )
                            .clipped()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                Text("Looking for devices…")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.bottom, 16)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "sensor.tag.radiowaves.forward")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.12))
                        .padding(.top, 12)
                    Text("No devices found")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("Tap scan to discover nearby BLE devices")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.2))
                    #if targetEnvironment(simulator)
                        Text(
                            "Bluetooth doesn’t discover trainers or sensors in the Simulator — use a physical iPhone."
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.28))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                    #endif
                }
                .padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.05))
            .frame(height: 1)
            .padding(.horizontal, 16)
    }

    private func deviceSection(
        title: String, icon: String, devices: [DiscoveredPeripheral], type: DeviceType
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.3))
                    .tracking(1.5)
                Spacer()
                Text("\(devices.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.2))
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            ForEach(devices) { device in
                deviceRow(device: device, type: type)
                    .padding(.horizontal, 12)

                if device.id != devices.last?.id {
                    Rectangle()
                        .fill(Color.white.opacity(0.03))
                        .frame(height: 1)
                        .padding(.leading, 62)
                        .padding(.trailing, 12)
                }
            }

            Spacer().frame(height: 10)
        }
    }

    private func deviceRow(device: DiscoveredPeripheral, type: DeviceType) -> some View {
        let connState: BLEConnectionState = {
            switch type {
            case .trainer: return bleManager.trainerConnectionState
            case .heartRateMonitor: return bleManager.hrConnectionState
            case .cyclingSpeedCadence: return bleManager.cscConnectionState
            case .unknown: return bleManager.trainerConnectionState
            }
        }()
        let isThisConnected = {
            if case .connected(let n) = connState, n == device.name { return true }
            return false
        }()
        let isThisConnecting = {
            if case .connecting(let n) = connState, n == device.name { return true }
            return false
        }()
        let rowColor =
            isThisConnected
            ? accentSuccess : (isThisConnecting ? accentYellow : Color.white.opacity(0.5))
        let icon: String = {
            switch type {
            case .heartRateMonitor: return "heart.fill"
            case .trainer: return "bicycle"
            case .cyclingSpeedCadence: return "arrow.trianglehead.2.clockwise.rotate.90"
            case .unknown: return "sensor.tag.radiowaves.forward"
            }
        }()

        return Button {
            switch type {
            case .trainer: bleManager.connectTrainer(device.peripheral)
            case .heartRateMonitor: bleManager.connectHRMonitor(device.peripheral)
            case .cyclingSpeedCadence: bleManager.connectCSCSensor(device.peripheral)
            case .unknown: bleManager.connectTrainer(device.peripheral)
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(rowColor.opacity(0.1))
                        .frame(width: 40, height: 40)

                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(rowColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(device.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        // Signal strength indicator
                        HStack(spacing: 2) {
                            ForEach(0..<4) { bar in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(
                                        bar < signalBars(rssi: device.rssi)
                                            ? rowColor : Color.white.opacity(0.1)
                                    )
                                    .frame(width: 3, height: CGFloat(4 + bar * 3))
                            }
                        }
                        .frame(height: 13, alignment: .bottom)

                        Text("\(device.rssi) dBm")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.25))
                    }
                }

                Spacer()

                if isThisConnected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(accentSuccess)
                } else if isThisConnecting {
                    ProgressView()
                        .tint(accentYellow)
                        .scaleEffect(0.8)
                } else {
                    Text("Connect")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1)))
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Custom workout library (.zwo)

    private var customWorkoutLibraryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(
                    "Import a Zwift .zwo file or pick a saved workout for a structured indoor session with ERG targets."
                )
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.38))
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, customWorkoutTemplates.isEmpty ? 12 : 8)

            if !customWorkoutTemplates.isEmpty {
                VStack(spacing: 0) {
                    ForEach(customWorkoutTemplates, id: \.id) { template in
                        customWorkoutRow(template)
                        if template.id != customWorkoutTemplates.last?.id {
                            Divider().background(Color.white.opacity(0.06))
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }

            Button {
                showZWOImporter = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.doc.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(accentMango)
                    Text("Import .zwo file")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accentMango)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(accentMango.opacity(0.08))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background(
            ZStack {
                Color.white.opacity(0.02)
                GridPatternView().opacity(0.25)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private func customWorkoutRow(_ template: CustomWorkoutTemplate) -> some View {
        let selected = selectedCustomTemplateID == template.id
        return HStack(spacing: 10) {
            Button {
                selectedCustomTemplateID = selected ? nil : template.id
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                (selected ? accentMango : Color.white.opacity(0.5)).opacity(0.12)
                            )
                            .frame(width: 40, height: 40)
                        Image(systemName: "figure.indoor.cycle")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(selected ? accentMango : Color.white.opacity(0.55))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(template.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text("\(template.intervals.count) steps")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.28))
                    }

                    Spacer(minLength: 0)

                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(accentMango)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                deleteCustomTemplate(template)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func deleteCustomTemplate(_ template: CustomWorkoutTemplate) {
        if selectedCustomTemplateID == template.id {
            selectedCustomTemplateID = nil
        }
        modelContext.delete(template)
        try? modelContext.save()
    }

    // MARK: - Route Card

    private var routeCard: some View {
        VStack(spacing: 0) {
            if routeManager.hasRoute {
                loadedRouteCard
            } else {
                emptyRouteCard
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    routeDropTargeted ? accentSuccess.opacity(0.6) : Color.white.opacity(0.07),
                    lineWidth: routeDropTargeted ? 2 : 1
                )
        )
        .animation(.easeInOut(duration: 0.2), value: routeDropTargeted)
        .animation(.easeInOut(duration: 0.35), value: routeManager.hasRoute)
    }

    private var emptyRouteCard: some View {
        Button {
            showRouteImporter = true
        } label: {
            VStack(spacing: 16) {
                // Route illustration
                ZStack {
                    // Dashed path visual
                    RouteIllustration()
                        .frame(height: 80)
                        .padding(.horizontal, 30)

                    // Map pin
                    VStack(spacing: 0) {
                        Image(systemName: "map.fill")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(accentBlue)
                            .frame(width: 56, height: 56)
                            .background(accentBlue.opacity(0.12))
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(accentBlue.opacity(0.2), lineWidth: 1))
                    }
                }
                .padding(.top, 24)

                VStack(spacing: 6) {
                    Text("Add a Route")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))

                    Text(
                        "Import a GPX file to track your position\nduring the ride and unlock route-based GPX export"
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.35))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                }

                // Upload area
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.doc.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(accentBlue)
                    Text("Choose GPX File")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accentBlue)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(accentBlue.opacity(0.1))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(accentBlue.opacity(0.25), lineWidth: 1))
                .padding(.bottom, 6)

                Text("OPTIONAL")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.18))
                    .tracking(2)
                    .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    Color.white.opacity(0.02)

                    // Subtle grid pattern
                    GridPatternView()
                        .opacity(0.3)
                }
            )
        }
        .buttonStyle(.plain)
    }

    private var loadedRouteCard: some View {
        VStack(spacing: 0) {
            // Map preview
            if let region = routeManager.cameraRegion {
                Map(initialPosition: .region(region)) {
                    ForEach(Array(routeManager.polylineSegments.enumerated()), id: \.offset) {
                        _, segment in
                        let coordinates = segment.sanitizedForMapPolyline()
                        if coordinates.count > 1 {
                            MapPolyline(coordinates: coordinates)
                                .stroke(accentSuccess, lineWidth: 3)
                        }
                    }
                }
                .frame(minWidth: 1, minHeight: 1)
                .frame(height: 160)
                .allowsHitTesting(false)
                .overlay(alignment: .topTrailing) {
                    // Route stats overlay
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(String(format: "%.1f km", routeManager.totalDistance / 1000))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                        Text("\(routeManager.points.count) points")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: .rect(cornerRadius: 10))
                    .padding(10)
                }
            }

            // Route info bar
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(accentSuccess)

                VStack(alignment: .leading, spacing: 2) {
                    Text(routeManager.routeName ?? "Route loaded")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    Text(routeSubtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
                }

                Spacer()

                Menu {
                    Button {
                        showRouteImporter = true
                    } label: {
                        Label("Replace Route", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button(role: .destructive) {
                        withAnimation { routeManager.clearRoute() }
                    } label: {
                        Label("Remove Route", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.white.opacity(AppOpacity.pillBg))
        }
    }

    private var routeSubtitle: String {
        let base = String(
            format: "%.1f km · %d waypoints", routeManager.totalDistance / 1000,
            routeManager.points.count)
        let gain = Int(routeManager.totalElevationGain.rounded())
        if gain > 0 {
            return "\(base) · +\(gain)m"
        }
        return base
    }

    // MARK: - Setup Summary

    @State private var rideGoalDistance: Double = 0  // 0 = no goal
    @State private var showCustomDistanceSheet = false
    @State private var customDistanceDraft = ""

    /// Preset chips for distance goal (km). `0` = none.
    private let distanceQuickGoalPresets: [Double] = [0, 10, 20, 30, 40, 50, 100]

    private var isCustomDistanceGoalSelected: Bool {
        guard rideGoalDistance > 0 else { return false }
        return !distanceQuickGoalPresets.contains(rideGoalDistance)
    }

    private var setupSummaryCard: some View {
        FTPRefreshScope {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("QUICK SETTINGS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.35))
                        .tracking(2)
                    Spacer()
                }

                HStack(spacing: 10) {
                    settingChip(label: "FTP", value: "\(PowerZone.ftp) W", color: accentYellow)
                    settingChip(
                        label: "Max HR", value: "\(HeartRateZone.maxHR) bpm", color: accentRed)
                    if HeartRateZone.hasRestingHR {
                        settingChip(
                            label: "Rest HR", value: "\(HeartRateZone.restingHR)", color: accentBlue
                        )
                    }
                }

                // Ride display toggles
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)

                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(accentBlue.opacity(0.7))
                        Text("Show Laps")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    Spacer()
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { prefs.showLaps },
                            set: { prefs.showLaps = $0 }
                        )
                    )
                    .labelsHidden()
                    .tint(accentBlue)
                }

                // Ride goal
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 10))
                            .foregroundStyle(accentSuccess.opacity(0.7))
                        Text("RIDE GOAL")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.35))
                            .tracking(2)
                        Spacer()
                        if rideGoalDistance > 0 {
                            Text("\(Int(rideGoalDistance)) km")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(accentSuccess)
                        }
                    }

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                        spacing: 8
                    ) {
                        ForEach(distanceQuickGoalPresets, id: \.self) { km in
                            goalPresetButton(km: km)
                        }
                        customDistanceGoalButton
                    }
                }
            }
            .padding(16)
            .background(Color.white.opacity(AppOpacity.pillBg))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
            .sheet(isPresented: $showCustomDistanceSheet) {
                customDistanceSheet
            }
        }
    }

    @FocusState private var isCustomDistanceFocused: Bool

    private var customDistanceSheet: some View {
        let range = RideGoal.Kind.distance.range
        return NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Enter your target distance in kilometers.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.55))

                TextField("km", text: $customDistanceDraft)
                    .keyboardType(.decimalPad)
                    .focused($isCustomDistanceFocused)
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text("Range: \(Int(range.lowerBound))–\(Int(range.upperBound)) km")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))

                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(red: 0.05, green: 0.06, blue: 0.09))
            .navigationTitle("Custom distance")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Focus the text field immediately so the system warms up the keyboard process
                isCustomDistanceFocused = true
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showCustomDistanceSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { applyCustomDistanceFromDraft() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func applyCustomDistanceFromDraft() {
        let trimmed = customDistanceDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = Double(trimmed) ?? RideGoal.Kind.distance.defaultValue
        let r = RideGoal.Kind.distance.range
        let clamped = min(max(parsed, r.lowerBound), r.upperBound)
        applyRideGoalDistance(clamped)
        showCustomDistanceSheet = false
    }

    private func applyRideGoalDistance(_ km: Double) {
        rideGoalDistance = km
        if km > 0 {
            prefs.setGoalTarget(.distance, target: km)
            if let idx = prefs.goals.firstIndex(where: { $0.kind == .distance }),
                !prefs.goals[idx].isEnabled
            {
                prefs.toggleGoal(.distance)
            }
        } else {
            if let idx = prefs.goals.firstIndex(where: { $0.kind == .distance }),
                prefs.goals[idx].isEnabled
            {
                prefs.toggleGoal(.distance)
            }
        }
    }

    private func syncRideGoalDistanceFromPrefs() {
        if let g = prefs.goals.first(where: { $0.kind == .distance }), g.isEnabled {
            rideGoalDistance = g.target
        } else {
            rideGoalDistance = 0
        }
    }

    private func goalPresetButton(km: Double) -> some View {
        let isSelected = km == rideGoalDistance && !isCustomDistanceGoalSelected
        let label = km == 0 ? "None" : "\(Int(km))"
        return Button {
            applyRideGoalDistance(km)
        } label: {
            Text(label)
                .font(.system(size: 13, weight: isSelected ? .bold : .medium, design: .monospaced))
                .foregroundStyle(isSelected ? .black : .white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isSelected ? accentSuccess : Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var customDistanceGoalButton: some View {
        let isSelected = isCustomDistanceGoalSelected
        return Button {
            customDistanceDraft =
                rideGoalDistance > 0
                ? "\(Int(rideGoalDistance))"
                : "\(Int(RideGoal.Kind.distance.defaultValue))"
            showCustomDistanceSheet = true
        } label: {
            Text("Custom")
                .font(.system(size: 13, weight: isSelected ? .bold : .medium, design: .monospaced))
                .foregroundStyle(isSelected ? .black : .white.opacity(0.7))
                .frame(minWidth: 68)
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
                .background(isSelected ? accentSuccess : Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func settingChip(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.3))
                .tracking(1)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(color.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Sticky Action Bar

    private var stickyActionBar: some View {
        VStack(spacing: 10) {
            Button {
                handlePrimaryAction()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: outdoorSensorsOnly ? "checkmark.circle.fill" : "play.fill")
                        .font(.system(size: 14))
                    Text(primaryActionTitle)
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundStyle(canStartRide ? .black : .white.opacity(0.4))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    canStartRide
                        ? AnyShapeStyle(accentSuccess)
                        : AnyShapeStyle(Color.white.opacity(0.06))
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: canStartRide ? accentSuccess.opacity(0.3) : .clear, radius: 12, y: 4)
            }
            .disabled(!canStartRide)

            HStack(spacing: 4) {
                Circle()
                    .fill(canStartRide ? accentSuccess : accentOrange)
                    .frame(width: 5, height: 5)
                Text(primaryActionHint)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background {
            ZStack(alignment: .top) {
                // Stable dark panel — avoids gray tint bleed from blurred/material backgrounds.
                Rectangle()
                    .fill(bg)
                    .overlay(
                        Rectangle()
                            .fill(Color.white.opacity(0.04))
                            .frame(height: 1),
                        alignment: .top
                    )
                    .ignoresSafeArea(edges: .bottom)
                    .allowsHitTesting(false)

                // Subtle fade into content above the bar.
                LinearGradient(
                    colors: [bg.opacity(0), bg],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 32)
                .offset(y: -32)
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Bluetooth Off

    private var bluetoothOffCard: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(accentBlue.opacity(0.08))
                    .frame(width: 80, height: 80)
                Image(systemName: "bluetooth")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(accentBlue.opacity(0.6))
            }
            .padding(.top, 40)

            VStack(spacing: 8) {
                Text("Bluetooth Required")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                Text(
                    outdoorSensorsOnly
                        ? "Enable Bluetooth in Settings to\nconnect heart rate and speed/cadence sensors."
                        : "Enable Bluetooth in Settings to\nconnect to your trainer and sensors."
                )
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.35))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
            }
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(AppOpacity.pillBg))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(AppOpacity.cardBorder), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func signalBars(rssi: Int) -> Int {
        if rssi >= -50 { return 4 }
        if rssi >= -65 { return 3 }
        if rssi >= -80 { return 2 }
        if rssi >= -90 { return 1 }
        return 0
    }

    private var screenTitle: String {
        if outdoorSensorsOnly { return "Outdoor sensors" }
        switch startMode {
        case .ride: return "Ride Setup"
        case .ftpTest: return "FTP Setup"
        }
    }

    private var screenSubtitle: String {
        if outdoorSensorsOnly { return "Heart rate & speed/cadence on the road" }
        switch startMode {
        case .ride: return "Connect devices & configure your ride"
        case .ftpTest: return "Connect trainer for 20-min protocol"
        }
    }

    private var primaryActionTitle: String {
        if outdoorSensorsOnly { return "Done" }
        switch startMode {
        case .ride: return rideLaunchMode == .outdoor ? "Start Outdoor Ride" : "Start Indoor Ride"
        case .ftpTest: return "Start FTP Test"
        }
    }

    private var primaryActionHint: String {
        if outdoorSensorsOnly {
            return "Sensors work with outdoor rides from the Home tab"
        }
        if canStartRide {
            switch startMode {
            case .ride:
                if rideLaunchMode == .outdoor {
                    return routeManager.hasRoute
                        ? "Ready — GPX route will be followed outdoors"
                        : "Ready — GPS free ride with optional BLE sensors"
                }
                if rideLaunchMode == .indoor,
                    selectedCustomTemplateID != nil
                {
                    return "Ready — guided workout from your library"
                }
                if rideLaunchMode == .indoor,
                    dataSource.wifiConnectionState.isConnected,
                    !bleManager.trainerConnectionState.isConnected
                {
                    return "Ready — WiFi trainer connected"
                }
                return "Ready — trainer connected"
            case .ftpTest:
                return "Ready — begin when you are"
            }
        }
        switch startMode {
        case .ride:
            return rideLaunchMode == .outdoor
                ? "Location permission will be requested when you start"
                : "Connect a Bluetooth or WiFi trainer to start"
        case .ftpTest:
            return "Connect a trainer to begin"
        }
    }

    private var rideModeHint: String {
        switch rideLaunchMode {
        case .indoor:
            return
                "Indoor rides need a Bluetooth or Wi‑Fi trainer and can optionally use a GPX route for simulation."
        case .outdoor:
            return routeManager.hasRoute
                ? "Your loaded GPX route will appear on the outdoor map with off-course tracking."
                : "Outdoor rides use GPS from your phone and can still show BLE heart rate, cadence, and power."
        }
    }

    private func handlePrimaryAction() {
        if outdoorSensorsOnly {
            navigationPath.removeLast()
            return
        }
        switch startMode {
        case .ride:
            if rideLaunchMode == .outdoor {
                navigationPath.append(AppRoute.outdoorDashboard)
            } else if let dayID = planDayID {
                navigationPath.append(
                    AppRoute.planDashboard(planID: planID ?? CachedPlan.shared.id, dayID: dayID))
            } else if let tid = selectedCustomTemplateID {
                navigationPath.append(AppRoute.customWorkoutRide(templateID: tid))
            } else {
                navigationPath.append(AppRoute.dashboard)
            }
        case .ftpTest:
            navigationPath.append(AppRoute.ftpTest)
        }
    }

    // MARK: - Debug

    #if DEBUG
        private var debugOverlay: some View {
            VStack(alignment: .leading, spacing: 4) {
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                Text("DEBUG")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.25))
                    .tracking(2)
                Text(
                    "BT: \(String(describing: bleManager.bluetoothState.rawValue))  Trainer: \(bleManager.trainerConnectionState.label)  HR: \(bleManager.hrConnectionState.label)  Devices: \(bleManager.discoveredPeripherals.count)"
                )
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.2))
            }
        }
    #endif
}

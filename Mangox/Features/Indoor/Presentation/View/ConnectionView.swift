import CoreBluetooth
import MapKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

#if canImport(UIKit)
    import UIKit
#endif

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

private enum ConnectionFontToken {
    static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let fontName: String
        switch weight {
        case .light:
            fontName = "GeistMono-Light"
        case .medium, .semibold, .bold, .heavy, .black:
            fontName = "GeistMono-Medium"
        default:
            fontName = "GeistMono-Regular"
        }

        #if canImport(UIKit)
            if UIFont(name: fontName, size: size) != nil {
                return .custom(fontName, size: size)
            }
        #endif
        return .system(size: size, weight: weight, design: .monospaced)
    }
}

struct ConnectionView: View {
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

    let bleService: BLEServiceProtocol
    let dataSourceService: DataSourceServiceProtocol
    let routeService: RouteServiceProtocol
    let locationService: LocationServiceProtocol

    init(
        navigationPath: Binding<NavigationPath>,
        startMode: ConnectionStartMode = .ride,
        planID: String? = nil,
        planDayID: String? = nil,
        indoorRideLocked: Bool = false,
        outdoorSensorsOnly: Bool = false,
        bleService: BLEServiceProtocol,
        dataSourceService: DataSourceServiceProtocol,
        routeService: RouteServiceProtocol,
        locationService: LocationServiceProtocol
    ) {
        self._navigationPath = navigationPath
        self.startMode = startMode
        self.planID = planID
        self.planDayID = planDayID
        self.indoorRideLocked = indoorRideLocked
        self.outdoorSensorsOnly = outdoorSensorsOnly
        self.bleService = bleService
        self.dataSourceService = dataSourceService
        self.routeService = routeService
        self.locationService = locationService
    }

    @State private var showRouteImporter = false
    @State private var routeImportError: String?
    @State private var scanPulse = false
    @State private var routeDropTargeted = false
    @State private var rideLaunchMode: RideLaunchMode = .indoor
    @State private var selectedCustomTemplateID: UUID?
    @State private var showZWOImporter = false
    @State private var zwoImportError: String?
    @State private var showRouteImportErrorOverlay = false
    @State private var showZWOImportErrorOverlay = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let prefs = RidePreferences.shared

    private let accentSuccess = AppColor.success
    private let accentYellow = AppColor.yellow
    private let accentOrange = AppColor.orange
    private let accentRed = AppColor.red
    private let accentBlue = AppColor.blue
    private let accentMango = AppColor.mango
    private let bg = AppColor.bg

    private var selectedCustomWorkout: CustomWorkoutTemplate? {
        guard let selectedCustomTemplateID else { return nil }
        return customWorkoutTemplates.first(where: { $0.id == selectedCustomTemplateID })
    }

    private var canStartRide: Bool {
        if outdoorSensorsOnly { return true }
        guard startMode == .ride else {
            return dataSourceService.isConnected
        }

        switch rideLaunchMode {
        case .indoor:
            return bleService.trainerConnectionState.isConnected
                || dataSourceService.wifiConnectionState.isConnected
        case .outdoor:
            return true
        }
    }

    private var wifiStateAsBLE: BLEConnectionState {
        switch dataSourceService.wifiConnectionState {
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
        switch bleService.trainerConnectionState {
        case .connected:
            return bleService.connectedTrainerName ?? "Connected"
        case .connecting(let name):
            return "Connecting to \(name)…"
        case .scanning:
            return "Searching for trainers…"
        case .disconnected:
            return "Not connected"
        }
    }

    private var wifiStatusBannerTitle: String {
        switch dataSourceService.wifiConnectionState {
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
        switch bleService.hrConnectionState {
        case .connected:
            return bleService.connectedHRName ?? "Connected"
        case .connecting(let name):
            return "Connecting to \(name)…"
        case .scanning:
            return "Searching for heart rate monitors…"
        case .disconnected:
            return "Not connected"
        }
    }

    private var cscStatusBannerTitle: String {
        switch bleService.cscConnectionState {
        case .connected:
            return bleService.connectedCSCName ?? "Connected"
        case .connecting(let name):
            return "Connecting to \(name)…"
        case .scanning:
            return "Searching for sensors…"
        case .disconnected:
            return "Not connected"
        }
    }

    private var wifiStatusBannerAccent: Color? {
        if case .error = dataSourceService.wifiConnectionState { return AppColor.orange }
        return nil
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    statusBanner
                        .padding(.horizontal, MangoxSpacing.page)
                        .padding(.top, 12)
                        .padding(.bottom, 20)

                    if bleService.bluetoothState != .poweredOn
                        && (rideLaunchMode == .indoor || outdoorSensorsOnly)
                    {
                        bluetoothOffCard
                            .padding(.horizontal, MangoxSpacing.page)
                    } else {
                        if startMode == .ride, planDayID == nil, !indoorRideLocked,
                            !outdoorSensorsOnly
                        {
                            rideModeCard
                                .padding(.horizontal, MangoxSpacing.page)
                                .padding(.bottom, 20)
                        }

                        // Devices section
                        sectionHeader(
                            title: outdoorSensorsOnly ? "SENSORS" : "DEVICES",
                            icon: "antenna.radiowaves.left.and.right",
                            prominent: true
                        )
                        .padding(.horizontal, MangoxSpacing.page)
                        .padding(.bottom, 10)

                        scanButton
                            .padding(.horizontal, MangoxSpacing.page)
                            .padding(.bottom, 14)

                        devicesCard
                            .padding(.horizontal, MangoxSpacing.page)
                            .padding(.bottom, 24)

                        if startMode == .ride, rideLaunchMode == .indoor, !outdoorSensorsOnly {
                            sectionHeader(title: "WIFI TRAINERS", icon: "wifi", prominent: true)
                                .padding(.horizontal, MangoxSpacing.page)
                                .padding(.bottom, 10)
                            wifiTrainersCard
                                .padding(.horizontal, MangoxSpacing.page)
                                .padding(.bottom, 24)
                        }

                        // Route section (ride mode only)
                        if startMode == .ride, !outdoorSensorsOnly {
                            sectionHeader(title: "ROUTE", icon: "map")
                                .padding(.horizontal, MangoxSpacing.page)
                                .padding(.bottom, 10)

                            routeCard
                                .padding(.horizontal, MangoxSpacing.page)
                                .padding(.bottom, 24)
                        }

                        // Zwift-style .zwo library (indoor free ride only — plan rides use the calendar day)
                        if startMode == .ride, rideLaunchMode == .indoor, !outdoorSensorsOnly,
                            planDayID == nil
                        {
                            sectionHeader(title: "GUIDED WORKOUT", icon: "figure.indoor.cycle")
                                .padding(.horizontal, MangoxSpacing.page)
                                .padding(.bottom, 10)

                            customWorkoutLibraryCard
                                .padding(.horizontal, MangoxSpacing.page)
                                .padding(.bottom, 24)
                        }

                        // Settings quick glance
                        if !outdoorSensorsOnly {
                            setupSummaryCard
                                .padding(.horizontal, MangoxSpacing.page)
                                .padding(.bottom, 24)
                        }
                    }

                    #if DEBUG
                        if !outdoorSensorsOnly {
                            debugOverlay
                                .padding(.horizontal, MangoxSpacing.page)
                                .padding(.bottom, 16)
                        }
                    #endif

                    // Bottom spacer for sticky action bar
                    Color.clear.frame(height: 140)
                }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)

            // Sticky bottom action bar
            if bleService.bluetoothState == .poweredOn
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
                    Text(toolbarEyebrow)
                        .mangoxFont(.caption)
                        .foregroundStyle(AppColor.mango)
                    Text(screenTitle)
                        .font(MangoxFont.title.value)
                        .foregroundStyle(AppColor.fg0)
                    Text(screenSubtitle)
                        .mangoxFont(.micro)
                        .foregroundStyle(AppColor.fg3)
                }
            }
        }
        .onAppear {
            locationService.setup()
            dataSourceService.updateActiveSource()
            syncRideGoalDistanceFromPrefs()
            if indoorRideLocked {
                rideLaunchMode = .indoor
            }
            if planDayID != nil {
                selectedCustomTemplateID = nil
            }
            if outdoorSensorsOnly {
                if bleService.bluetoothState == .poweredOn {
                    bleService.reconnectOrScan()
                }
            } else if rideLaunchMode == .indoor,
                bleService.bluetoothState == .poweredOn,
                !bleService.trainerConnectionState.isConnected
            {
                bleService.reconnectOrScan()
            }
        }
        .onDisappear {
            bleService.stopScan()
            dataSourceService.stopWiFiDiscovery()
        }
        .overlay {
            if showRouteImportErrorOverlay {
                MangoxConfirmOverlay(
                    title: "Route Import Failed",
                    message: routeImportError ?? "",
                    onDismiss: {
                        showRouteImportErrorOverlay = false
                        routeImportError = nil
                    }
                ) {
                    Button {
                        showRouteImportErrorOverlay = false
                        routeImportError = nil
                    } label: {
                        Text("OK")
                            .mangoxButtonChrome(.hero)
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity)
            }

            if showZWOImportErrorOverlay {
                MangoxConfirmOverlay(
                    title: "Workout Import Failed",
                    message: zwoImportError ?? "",
                    onDismiss: {
                        showZWOImportErrorOverlay = false
                        zwoImportError = nil
                    }
                ) {
                    Button {
                        showZWOImportErrorOverlay = false
                        zwoImportError = nil
                    } label: {
                        Text("OK")
                            .mangoxButtonChrome(.hero)
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity)
            }
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
                        try await routeService.loadGPX(from: url)
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
                            do {
                                try modelContext.save()
                                selectedCustomTemplateID = t.id
                            } catch {
                                modelContext.delete(t)
                                zwoImportError =
                                    (error as? LocalizedError)?.errorDescription
                                    ?? error.localizedDescription
                            }
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
        .onChange(of: routeImportError) { _, value in
            showRouteImportErrorOverlay = value != nil
        }
        .onChange(of: zwoImportError) { _, value in
            showZWOImportErrorOverlay = value != nil
        }
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
        .cardStyle(cornerRadius: MangoxRadius.sharp.rawValue)
    }

    private var statusBannerHorizontal: some View {
        HStack(alignment: .top, spacing: 10) {
            if showTrainerStatusRow {
                connectionStatusRow(
                    icon: "bicycle",
                    category: "Trainer",
                    title: trainerStatusBannerTitle,
                    state: bleService.trainerConnectionState
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
                state: bleService.hrConnectionState
            )
            .frame(maxWidth: .infinity)
            if showCSCStatusRow {
                connectionStatusRow(
                    icon: "arrow.trianglehead.2.clockwise.rotate.90",
                    category: "Speed / cadence",
                    title: cscStatusBannerTitle,
                    state: bleService.cscConnectionState
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
                    state: bleService.trainerConnectionState
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
                state: bleService.hrConnectionState
            )
            if showCSCStatusRow {
                connectionStatusDivider
                connectionStatusRow(
                    icon: "arrow.trianglehead.2.clockwise.rotate.90",
                    category: "Speed / cadence",
                    title: cscStatusBannerTitle,
                    state: bleService.cscConnectionState
                )
            }
        }
    }

    private var connectionStatusDivider: some View {
        Rectangle()
            .fill(AppColor.hair)
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
            return accentOverride ?? AppColor.fg3
        }()

        return HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(pillColor.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: icon)
                    .font(MangoxFont.bodyBold.value)
                    .foregroundStyle(pillColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(category.uppercased())
                    .mangoxFont(.label)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.fg3)
                    .tracking(0.6)

                Text(title)
                    .mangoxFont(.bodyBold)
                    .foregroundStyle(isConnected ? AppColor.fg0 : AppColor.fg2)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isConnected {
                Image(systemName: "checkmark.circle.fill")
                    .font(MangoxFont.title.value)
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
                    .mangoxFont(.label)
                    .foregroundStyle(AppColor.fg3)
                Text("RIDE MODE")
                    .mangoxFont(.label)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.fg3)
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
                                .mangoxFont(.callout)
                            Text(mode.label)
                                .mangoxFont(.bodyBold)
                        }
                        .foregroundStyle(rideLaunchMode == mode ? AppColor.bg0 : AppColor.fg2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(rideLaunchMode == mode ? accentSuccess : AppColor.hair)
                        .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue, style: .continuous))
                        .overlay(
                            RoundedRectangle(
                                cornerRadius: MangoxRadius.overlay.rawValue,
                                style: .continuous
                            )
                            .strokeBorder(
                                rideLaunchMode == mode ? accentSuccess : AppColor.hair2,
                                lineWidth: 1
                            )
                        )
                    }
                    .buttonStyle(MangoxPressStyle())
                }
            }

            Text(rideModeHint)
                .mangoxFont(.callout)
                .foregroundStyle(AppColor.fg3)
        }
        .padding(16)
        .cardStyle(cornerRadius: MangoxRadius.sharp.rawValue)
    }

    // MARK: - Section Header

    private func sectionHeader(title: String, icon: String, prominent: Bool = false) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(MangoxFont.callout.value)
                .foregroundStyle(prominent ? AppColor.fg2 : AppColor.fg3)
            Text(title)
                .mangoxFont(.callout)
                .fontWeight(.semibold)
                .foregroundStyle(prominent ? AppColor.fg2 : AppColor.fg3)
                .tracking(prominent ? 1.5 : 2)
            Spacer()
        }
    }

    // MARK: - Scan Button

    private var scanButton: some View {
        Button {
            if bleService.isScanningForDevices {
                bleService.stopScan()
                scanPulse = false
            } else {
                bleService.startScan()
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
                    if bleService.isScanningForDevices {
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
                            .mangoxFont(.callout)
                            .foregroundStyle(accentSuccess)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(bleService.isScanningForDevices ? "Scanning…" : "Scan for Devices")
                        .mangoxFont(.bodyBold)
                        .foregroundStyle(AppColor.fg0)
                    Text(
                        bleService.isScanningForDevices
                            ? "Tap to stop"
                            : (outdoorSensorsOnly
                                ? "Find speed/cadence sensors & heart rate monitors"
                                : "Find nearby trainers & HR monitors")
                    )
                    .mangoxFont(.caption)
                    .foregroundStyle(AppColor.fg3)
                }

                Spacer()

                Image(
                    systemName: bleService.isScanningForDevices ? "stop.circle" : "arrow.clockwise"
                )
                .font(MangoxFont.title.value)
                .foregroundStyle(accentSuccess.opacity(0.6))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(accentSuccess.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue, style: .continuous)
                    .strokeBorder(accentSuccess.opacity(0.15), lineWidth: 1)
            )
        }
        .accessibilityLabel(
            bleService.isScanningForDevices ? "Stop scanning for devices" : "Scan for devices"
        )
        .accessibilityHint(
            bleService.isScanningForDevices
                ? "Stops Bluetooth scanning"
                : "Find nearby trainers and sensors"
        )
    }

    // MARK: - Devices Card

    // MARK: - Connected Device Rows (built from BLEManager state, not discoveredPeripherals)

    private var connectedDeviceRows: [ConnectedDeviceStateRow] {
        var rows: [ConnectedDeviceStateRow] = []
        if !outdoorSensorsOnly, let name = bleService.connectedTrainerName {
            rows.append(
                ConnectedDeviceStateRow(
                    name: name, type: .trainer, state: bleService.trainerConnectionState))
        }
        if let name = bleService.connectedHRName {
            rows.append(
                ConnectedDeviceStateRow(
                    name: name, type: .heartRateMonitor, state: bleService.hrConnectionState))
        }
        if let name = bleService.connectedCSCName {
            rows.append(
                ConnectedDeviceStateRow(
                    name: name, type: .cyclingSpeedCadence, state: bleService.cscConnectionState))
        }
        return rows
    }

    private var devicesCard: some View {
        let connected = connectedDeviceRows

        // Scan results minus already-connected devices
        let scanResults = bleService.discoveredPeripherals.filter { !bleService.activePeripheralIDs.contains($0.id) }
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
                    if bleService.isScanningForDevices && !scanForDisplay.isEmpty {
                        sectionDivider
                        scanningFooter
                    }

                    // Gentle prompt to scan for more when idle with connected devices but no scan results
                    if !connected.isEmpty && !hasScanResults && !bleService.isScanningForDevices {
                        sectionDivider
                        scanForMorePrompt
                    }
                }
            }
        }
        .cardStyle(cornerRadius: MangoxRadius.sharp.rawValue)
    }

    // MARK: - WiFi Trainers Card

    private var isWiFiDiscovering: Bool {
        if case .discovering = dataSourceService.wifiConnectionState { return true }
        return false
    }

    private var isWiFiConnecting: Bool {
        if case .connecting = dataSourceService.wifiConnectionState { return true }
        return false
    }

    private var wifiTrainersCard: some View {
        let wifiState = dataSourceService.wifiConnectionState
        let connectedID = dataSourceService.connectedWiFiTrainer?.id
        let trainers = dataSourceService.discoveredWiFiTrainers.filter { t in
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
            .mangoxFont(.caption)
            .foregroundStyle(AppColor.fg3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, showWifiRows || showBrowsingFooter ? 10 : 14)

            if case .error(let message) = wifiState {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .mangoxFont(.caption)
                        .foregroundStyle(accentOrange)
                    Text(message)
                        .mangoxFont(.body)
                        .foregroundStyle(AppColor.fg2)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }

            if showWifiRows {
                Rectangle()
                    .fill(AppColor.hair)
                    .frame(height: 1)
                    .padding(.horizontal, 16)

                if wifiState.isConnected, let connected = dataSourceService.connectedWiFiTrainer {
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
                        .mangoxFont(.callout)
                        .foregroundStyle(AppColor.fg3)
                    Text("Search to discover trainers on your network")
                        .mangoxFont(.body)
                        .foregroundStyle(AppColor.fg3)
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
                        .mangoxFont(.label)
                        .foregroundStyle(AppColor.fg3)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
        .cardStyle(cornerRadius: MangoxRadius.sharp.rawValue)
    }

    private var wifiTrainerDiscoveryButton: some View {
        Button {
            if isWiFiDiscovering {
                dataSourceService.stopWiFiDiscovery()
            } else {
                dataSourceService.startWiFiDiscovery()
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
                            .mangoxFont(.callout)
                            .fontWeight(.semibold)
                            .foregroundStyle(accentBlue)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(isWiFiDiscovering ? "Searching…" : "Search Wi‑Fi Trainers")
                        .mangoxFont(.bodyBold)
                        .foregroundStyle(AppColor.fg0)
                    Text(isWiFiDiscovering ? "Tap to stop" : "Bonjour / mDNS on your local network")
                        .mangoxFont(.label)
                        .foregroundStyle(AppColor.fg3)
                }

                Spacer()

                Image(systemName: isWiFiDiscovering ? "stop.circle" : "arrow.clockwise")
                    .mangoxFont(.callout)
                    .foregroundStyle(accentBlue.opacity(0.6))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(AppColor.wash(for: accentBlue))
            .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue, style: .continuous)
                    .strokeBorder(accentBlue.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .accessibilityLabel(
            isWiFiDiscovering ? "Stop searching Wi-Fi trainers" : "Search Wi-Fi trainers"
        )
        .accessibilityHint(
            isWiFiDiscovering
                ? "Stops Bonjour discovery"
                : "Find trainers on your local network"
        )
    }

    private func wifiConnectedRow(trainer: DiscoveredWiFiTrainer) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue, style: .continuous)
                    .fill(accentSuccess.opacity(0.1))
                    .frame(width: 40, height: 40)
                Image(systemName: "wifi")
                    .mangoxFont(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(accentSuccess)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(trainer.name)
                    .mangoxFont(.bodyBold)
                    .foregroundStyle(AppColor.fg0)
                    .lineLimit(1)
                Text("\(trainer.ipAddress) · \(trainer.port)")
                    .mangoxFont(.label)
                    .foregroundStyle(AppColor.fg3)
            }

            Spacer()

            Button("Disconnect") {
                dataSourceService.disconnectWiFi()
            }
            .mangoxFont(.caption)
            .foregroundStyle(accentOrange)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(trainer.name), connected Wi-Fi trainer")
        .accessibilityValue("\(trainer.ipAddress), port \(trainer.port)")
    }

    private func wifiConnectingRow(name: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(accentYellow)
                .scaleEffect(0.85)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .mangoxFont(.bodyBold)
                    .foregroundStyle(AppColor.fg0)
                    .lineLimit(1)
                Text("Connecting…")
                    .mangoxFont(.label)
                    .foregroundStyle(accentYellow.opacity(0.85))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), connecting Wi-Fi trainer")
    }

    private func wifiTrainerRow(trainer: DiscoveredWiFiTrainer, connectDisabled: Bool) -> some View
    {
        Button {
            dataSourceService.connectWiFi(to: trainer)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue, style: .continuous)
                        .fill(accentBlue.opacity(0.08))
                        .frame(width: 40, height: 40)
                    Image(systemName: "wifi")
                        .mangoxFont(.callout)
                        .fontWeight(.semibold)
                        .foregroundStyle(accentBlue.opacity(0.85))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(trainer.name)
                        .mangoxFont(.bodyBold)
                        .foregroundStyle(AppColor.fg0)
                        .lineLimit(1)
                    Text("\(trainer.ipAddress) · \(trainer.port)")
                        .mangoxFont(.label)
                        .foregroundStyle(AppColor.fg3)
                }

                Spacer()

                Text("Connect")
                    .mangoxFont(.caption)
                    .foregroundStyle(connectDisabled ? AppColor.fg4 : AppColor.fg2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AppColor.hair)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(AppColor.hair2))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(connectDisabled)
        .accessibilityLabel("Connect \(trainer.name)")
        .accessibilityValue("\(trainer.ipAddress), port \(trainer.port)")
        .accessibilityHint(connectDisabled ? "Another trainer is already connected" : "Connect to trainer over Wi-Fi")
    }

    // MARK: - Connected Devices Section

    private func connectedDevicesSection(devices: [ConnectedDeviceStateRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill")
                    .mangoxFont(.micro)
                    .foregroundStyle(accentSuccess.opacity(0.78))
                Text("CONNECTED")
                    .mangoxFont(.micro)
                    .fontWeight(.bold)
                    .foregroundStyle(accentSuccess.opacity(0.72))
                    .tracking(1.5)
                Spacer()
            }
            .padding(.horizontal, MangoxSpacing.page)
            .padding(.top, 14)
            .padding(.bottom, 8)

            ForEach(devices) { device in
                connectedDeviceRow(device: device)
                    .padding(.horizontal, 12)

                if device.id != devices.last?.id {
                    Rectangle()
                        .fill(AppColor.hair2)
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
                RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue, style: .continuous)
                    .fill(accentSuccess.opacity(0.12))
                    .frame(width: 40, height: 40)

                Image(systemName: icon)
                    .mangoxFont(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(accentSuccess)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .mangoxFont(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(AppColor.fg1)
                    .lineLimit(1)

                Text(typeLabel)
                    .mangoxFont(.micro)
                    .foregroundStyle(AppColor.fg3)
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .mangoxFont(.callout)
                .foregroundStyle(accentSuccess)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }

    // MARK: - Scanning Footer & Scan-for-More Prompt

    private var scanningFooter: some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(accentSuccess.opacity(0.78))
                .scaleEffect(0.65)
            Text("Scanning for more devices…")
                .mangoxFont(.label)
                .foregroundStyle(AppColor.fg3)
            Spacer()
        }
        .padding(.horizontal, MangoxSpacing.page)
        .padding(.vertical, 12)
    }

    private var scanForMorePrompt: some View {
        Button {
            bleService.startScan()
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
                    .mangoxFont(.micro)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.fg2)
                Text("Scan for more devices")
                    .mangoxFont(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(AppColor.fg2)
                Spacer()
                Image(systemName: "arrow.clockwise")
                    .mangoxFont(.micro)
                    .fontWeight(.medium)
                    .foregroundStyle(AppColor.fg3)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .mangoxSurface(.flatSubtle, shape: .rounded(MangoxRadius.overlay.rawValue))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty / Scanning Placeholder

    private var emptyDevicesPlaceholder: some View {
        VStack(spacing: 10) {
            if bleService.isScanningForDevices {
                HStack(spacing: 10) {
                    ForEach(0..<3) { i in
                        RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue)
                            .fill(AppColor.hair)
                            .frame(height: 50)
                            .overlay(
                                RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue)
                                    .fill(
                                        LinearGradient(
                                            colors: [.clear, AppColor.hair2, .clear],
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
                    .mangoxFont(.body)
                    .foregroundStyle(AppColor.fg3)
                    .padding(.bottom, 16)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "sensor.tag.radiowaves.forward")
                        .font(MangoxFont.title.value)
                        .foregroundStyle(AppColor.fg3)
                        .padding(.top, 12)
                    Text("No devices found")
                        .mangoxFont(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(AppColor.fg2)
                    Text("Tap scan to discover nearby BLE devices")
                        .mangoxFont(.label)
                        .foregroundStyle(AppColor.fg3)
                    #if targetEnvironment(simulator)
                        Text(
                            "Bluetooth doesn’t discover trainers or sensors in the Simulator — use a physical iPhone."
                        )
                        .mangoxFont(.label)
                        .foregroundStyle(AppColor.fg3)
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
            .fill(AppColor.hair)
            .frame(height: 1)
            .padding(.horizontal, MangoxSpacing.page)
    }

    private func deviceSection(
        title: String, icon: String, devices: [DiscoveredPeripheral], type: DeviceType
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .mangoxFont(.micro)
                    .foregroundStyle(AppColor.fg3)
                Text(title.uppercased())
                    .mangoxFont(.micro)
                    .fontWeight(.bold)
                    .foregroundStyle(AppColor.fg3)
                    .tracking(1.5)
                Spacer()
                Text("\(devices.count)")
                    .font(ConnectionFontToken.mono(size: 11, weight: .semibold))
                    .foregroundStyle(AppColor.fg3)
            }
            .padding(.horizontal, MangoxSpacing.page)
            .padding(.top, 14)
            .padding(.bottom, 8)

            ForEach(devices) { device in
                deviceRow(device: device, type: type)
                    .padding(.horizontal, 12)

                if device.id != devices.last?.id {
                    Rectangle()
                        .fill(AppColor.hair2)
                        .frame(height: 1)
                        .padding(.leading, 62)
                        .padding(.trailing, 12)
                }
            }

            Spacer().frame(height: 10)
        }
    }

    private func deviceRow(device: DiscoveredPeripheral, type: DeviceType) -> some View {
        let typeLabel: String = {
            switch type {
            case .heartRateMonitor: return "Heart rate monitor"
            case .trainer: return "Trainer"
            case .cyclingSpeedCadence: return "Speed and cadence sensor"
            case .unknown: return "Unknown device"
            }
        }()
        let connState: BLEConnectionState = {
            switch type {
            case .trainer: return bleService.trainerConnectionState
            case .heartRateMonitor: return bleService.hrConnectionState
            case .cyclingSpeedCadence: return bleService.cscConnectionState
            case .unknown: return bleService.trainerConnectionState
            }
        }()
        let isThisConnected = bleService.activePeripheralIDs.contains(device.id) && connState.isConnected
        let isThisConnecting = bleService.activePeripheralIDs.contains(device.id) && {
            if case .connecting = connState { return true }
            return false
        }()
        let rowColor =
            isThisConnected
            ? accentSuccess : (isThisConnecting ? accentYellow : AppColor.fg2)
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
            case .trainer: bleService.connectTrainer(device.peripheral)
            case .heartRateMonitor: bleService.connectHRMonitor(device.peripheral)
            case .cyclingSpeedCadence: bleService.connectCSCSensor(device.peripheral)
            case .unknown: bleService.connectTrainer(device.peripheral)
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue, style: .continuous)
                        .fill(rowColor.opacity(isThisConnected || isThisConnecting ? 0.12 : 0.08))
                        .frame(width: 40, height: 40)

                    Image(systemName: icon)
                        .mangoxFont(.callout)
                        .fontWeight(.semibold)
                        .foregroundStyle(rowColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(device.name)
                        .mangoxFont(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(AppColor.fg1)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        // Signal strength indicator
                        HStack(spacing: 2) {
                            ForEach(0..<4) { bar in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(
                                        bar < signalBars(rssi: device.rssi)
                                            ? rowColor : AppColor.hair
                                    )
                                    .frame(width: 3, height: CGFloat(4 + bar * 3))
                            }
                        }
                        .frame(height: 13, alignment: .bottom)

                        Text("\(device.rssi) dBm")
                            .font(ConnectionFontToken.mono(size: 10))
                            .foregroundStyle(AppColor.fg3)
                    }
                }

                Spacer()

                if isThisConnected {
                    Image(systemName: "checkmark.circle.fill")
                        .mangoxFont(.callout)
                        .foregroundStyle(accentSuccess)
                } else if isThisConnecting {
                    ProgressView()
                        .tint(accentYellow)
                        .scaleEffect(0.8)
                } else {
                    Text("Connect")
                        .mangoxFont(.label)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.fg2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .mangoxSurface(.flatSubtle, shape: .capsule)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(device.name), \(typeLabel)")
        .accessibilityValue(
            isThisConnected
                ? "Connected"
                : (isThisConnecting ? "Connecting" : "Not connected")
        )
        .accessibilityHint("Signal \(signalBars(rssi: device.rssi)) of 4")
    }

    // MARK: - Custom workout library (.zwo)

    private var customWorkoutLibraryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(
                    "Import a Zwift .zwo file or pick a saved workout for a structured indoor session with ERG targets."
                )
                .mangoxFont(.caption)
                .foregroundStyle(AppColor.fg2)
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
                            Divider().background(AppColor.hair)
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
                        .mangoxFont(.body)
                        .foregroundStyle(accentMango)
                    Text("Import .zwo file")
                        .mangoxFont(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(accentMango)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(accentMango.opacity(0.08))
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: MangoxRadius.button.rawValue,
                        style: .continuous
                    )
                )
                .overlay(
                    RoundedRectangle(
                        cornerRadius: MangoxRadius.button.rawValue,
                        style: .continuous
                    )
                    .strokeBorder(accentMango.opacity(0.18), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background(
            ZStack {
                AppColor.bg2
                LinearGradient(
                    colors: [accentMango.opacity(0.05), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                GridPatternView().opacity(0.25)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue, style: .continuous)
                .strokeBorder(AppColor.hair2, lineWidth: 1)
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
                        RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue, style: .continuous)
                            .fill(
                                selected ? accentMango.opacity(0.14) : AppColor.hair
                            )
                            .frame(width: 40, height: 40)
                        Image(systemName: "figure.indoor.cycle")
                            .mangoxFont(.callout)
                            .fontWeight(.semibold)
                            .foregroundStyle(selected ? accentMango : AppColor.fg2)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(template.name)
                            .mangoxFont(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(AppColor.fg1)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text("\(template.intervals.count) steps")
                            .font(ConnectionFontToken.mono(size: 11))
                            .foregroundStyle(AppColor.fg3)
                    }

                    Spacer(minLength: 0)

                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .mangoxFont(.callout)
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
                    .mangoxFont(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(AppColor.fg2)
                    .frame(width: 44, height: 44)
                    .mangoxSurface(.flatSubtle, shape: .circle)
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
        do {
            try modelContext.save()
        } catch {
            zwoImportError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Route Card

    private var routeCard: some View {
        VStack(spacing: 0) {
            if routeService.hasRoute {
                loadedRouteCard
            } else {
                emptyRouteCard
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue, style: .continuous)
                .strokeBorder(
                    routeDropTargeted ? accentSuccess.opacity(0.6) : AppColor.hair2,
                    lineWidth: routeDropTargeted ? 2 : 1
                )
        )
        .animation(.easeInOut(duration: 0.2), value: routeDropTargeted)
        .animation(.easeInOut(duration: 0.35), value: routeService.hasRoute)
    }

    private var emptyRouteCard: some View {
        Button {
            showRouteImporter = true
        } label: {
            VStack(spacing: 16) {
                ZStack {
                    RouteIllustration()
                        .frame(height: 80)
                        .padding(.horizontal, 30)

                    Image(systemName: "map.fill")
                        .font(MangoxFont.title.value)
                        .foregroundStyle(accentBlue)
                        .frame(width: 56, height: 56)
                        .mangoxSurface(.flatSubtle, shape: .circle)
                }
                .padding(.top, 24)

                VStack(spacing: 6) {
                    Text("Add a Route")
                        .mangoxFont(.title)
                        .foregroundStyle(AppColor.fg0)

                    Text(
                        "Import a GPX file to track your position\nduring the ride and unlock route-based GPX export"
                    )
                    .mangoxFont(.body)
                    .foregroundStyle(AppColor.fg2)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                }

                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.doc.fill")
                        .mangoxFont(.callout)
                        .foregroundStyle(accentBlue)
                    Text("Choose GPX File")
                        .mangoxFont(.callout)
                        .fontWeight(.semibold)
                        .foregroundStyle(accentBlue)
                }
                .padding(.horizontal, MangoxSpacing.page)
                .padding(.vertical, 10)
                .background(AppColor.wash(for: accentBlue))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(accentBlue.opacity(0.25), lineWidth: 1))
                .padding(.bottom, 6)

                Text("OPTIONAL")
                    .mangoxFont(.micro)
                    .foregroundStyle(AppColor.fg4)
                    .tracking(2)
                    .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    AppColor.bg2
                    GridPatternView()
                        .opacity(0.22)
                }
            )
        }
        .buttonStyle(.plain)
    }

    private var loadedRouteCard: some View {
        VStack(spacing: 0) {
            // Map preview
            if let region = routeService.cameraRegion {
                Map(initialPosition: .region(region)) {
                    ForEach(Array(routeService.polylineSegments.enumerated()), id: \.offset) {
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
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(String(format: "%.1f km", routeService.totalDistance / 1000))
                            .font(MangoxFont.bodyBold.value)
                            .foregroundStyle(AppColor.fg0)
                        Text("\(routeService.points.count) points")
                            .mangoxFont(.label)
                            .foregroundStyle(AppColor.fg2)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .mangoxSurface(.mapOverlay, shape: .rounded(MangoxRadius.overlay.rawValue))
                    .padding(10)
                }
            }

            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .mangoxFont(.callout)
                    .foregroundStyle(accentSuccess)

                VStack(alignment: .leading, spacing: 2) {
                    Text(routeService.routeName ?? "Route loaded")
                        .mangoxFont(.bodyBold)
                        .foregroundStyle(AppColor.fg0)
                        .lineLimit(1)
                    Text(routeSubtitle)
                        .mangoxFont(.label)
                        .foregroundStyle(AppColor.fg3)
                }

                Spacer()

                Menu {
                    Button {
                        showRouteImporter = true
                    } label: {
                        Label("Replace Route", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button(role: .destructive) {
                        withAnimation { routeService.clearRoute() }
                    } label: {
                        Label("Remove Route", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .mangoxFont(.callout)
                        .foregroundStyle(AppColor.fg2)
                        .frame(width: 44, height: 44)
                        .mangoxSurface(.flatSubtle, shape: .circle)
                        .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(AppColor.bg2)
        }
    }

    private var routeSubtitle: String {
        let base = String(
            format: "%.1f km · %d waypoints", routeService.totalDistance / 1000,
            routeService.points.count)
        let gain = Int(routeService.totalElevationGain.rounded())
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
                        .mangoxFont(.micro)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.fg3)
                    Text("QUICK SETTINGS")
                        .mangoxFont(.micro)
                        .fontWeight(.bold)
                        .foregroundStyle(AppColor.fg3)
                        .tracking(2)
                    Spacer()
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
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
                    .fill(AppColor.hair)
                    .frame(height: 1)

                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "flag.fill")
                            .mangoxFont(.micro)
                            .foregroundStyle(accentBlue.opacity(0.7))
                        Text("Show Laps")
                            .mangoxFont(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(AppColor.fg1)
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
                    .fill(AppColor.hair)
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "flag.checkered")
                            .mangoxFont(.micro)
                            .foregroundStyle(accentSuccess.opacity(0.7))
                        Text("RIDE GOAL")
                            .mangoxFont(.micro)
                            .fontWeight(.bold)
                            .foregroundStyle(AppColor.fg3)
                            .tracking(2)
                        Spacer()
                        if rideGoalDistance > 0 {
                            Text("\(Int(rideGoalDistance)) km")
                                .font(ConnectionFontToken.mono(size: 12, weight: .semibold))
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
            .cardStyle(cornerRadius: MangoxRadius.sharp.rawValue)
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
                    .mangoxFont(.body)
                    .foregroundStyle(AppColor.fg2)

                TextField("km", text: $customDistanceDraft)
                    .keyboardType(.decimalPad)
                    .focused($isCustomDistanceFocused)
                    .font(ConnectionFontToken.mono(size: 20, weight: .semibold))
                    .foregroundStyle(AppColor.fg0)
                    .padding(12)
                    .background(AppColor.bg3)
                    .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue, style: .continuous))
                    .overlay(
                        RoundedRectangle(
                            cornerRadius: MangoxRadius.overlay.rawValue,
                            style: .continuous
                        )
                        .strokeBorder(AppColor.hair, lineWidth: 1)
                    )

                Text("Range: \(Int(range.lowerBound))–\(Int(range.upperBound)) km")
                    .mangoxFont(.label)
                    .foregroundStyle(AppColor.fg3)

                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(AppColor.bg2)
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
                .font(
                    ConnectionFontToken.mono(
                        size: 13,
                        weight: isSelected ? .bold : .medium
                    )
                )
                .foregroundStyle(isSelected ? AppColor.bg : AppColor.fg1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isSelected ? accentSuccess : AppColor.hair)
                .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue, style: .continuous))
                .overlay(
                    RoundedRectangle(
                        cornerRadius: MangoxRadius.overlay.rawValue,
                        style: .continuous
                    )
                    .strokeBorder(isSelected ? accentSuccess : AppColor.hair2, lineWidth: 1)
                )
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
                .font(
                    ConnectionFontToken.mono(
                        size: 13,
                        weight: isSelected ? .bold : .medium
                    )
                )
                .foregroundStyle(isSelected ? AppColor.bg : AppColor.fg1)
                .frame(minWidth: 68)
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
                .background(isSelected ? accentSuccess : AppColor.hair)
                .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue, style: .continuous))
                .overlay(
                    RoundedRectangle(
                        cornerRadius: MangoxRadius.overlay.rawValue,
                        style: .continuous
                    )
                    .strokeBorder(isSelected ? accentSuccess : AppColor.hair2, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func settingChip(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .mangoxFont(.micro)
                .fontWeight(.bold)
                .foregroundStyle(AppColor.fg3)
                .tracking(1)
            Text(value)
                .font(ConnectionFontToken.mono(size: 14, weight: .bold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue, style: .continuous)
                .strokeBorder(color.opacity(0.18), lineWidth: 1)
        )
    }

    // MARK: - Sticky Action Bar

    private var stickyActionBar: some View {
        VStack(spacing: 10) {
            if let selectedCustomWorkout, startMode == .ride, rideLaunchMode == .indoor {
                selectedWorkoutSummary(selectedCustomWorkout)
            }

            Button {
                handlePrimaryAction()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: outdoorSensorsOnly ? "checkmark.circle.fill" : "play.fill")
                        .mangoxFont(.bodyBold)
                    Text(primaryActionTitle)
                        .font(MangoxFont.bodyBold.value)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(canStartRide ? AppColor.bg0 : AppColor.fg3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    canStartRide
                        ? AnyShapeStyle(accentSuccess)
                        : AnyShapeStyle(AppColor.hair)
                )
                .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue, style: .continuous))
                .shadow(color: canStartRide ? accentSuccess.opacity(0.3) : .clear, radius: 12, y: 4)
            }
            .disabled(!canStartRide)

            HStack(spacing: 4) {
                Circle()
                    .fill(canStartRide ? accentSuccess : accentOrange)
                    .frame(width: 5, height: 5)
                Text(primaryActionHint)
                    .mangoxFont(.body)
                    .foregroundStyle(AppColor.fg3)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, MangoxSpacing.page)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background {
            ZStack(alignment: .top) {
                // Stable dark panel — avoids gray tint bleed from blurred/material backgrounds.
                Rectangle()
                    .fill(bg)
                    .overlay(
                        Rectangle()
                            .fill(AppColor.hair)
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

    private func selectedWorkoutSummary(_ template: CustomWorkoutTemplate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "figure.indoor.cycle")
                    .mangoxFont(.callout)
                    .foregroundStyle(accentMango)
                Text("Guided workout selected")
                    .mangoxFont(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(accentMango.opacity(0.9))
                    .tracking(0.8)
                Spacer(minLength: 0)
                Text("\(template.intervals.count) steps")
                    .mangoxFont(.caption)
                    .foregroundStyle(AppColor.fg3)
            }

            Text(template.name)
                .mangoxFont(.bodyBold)
                .foregroundStyle(AppColor.fg0)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppColor.bg2)
        .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue, style: .continuous)
                .strokeBorder(accentMango.opacity(0.18), lineWidth: 1)
        )
    }

    // MARK: - Bluetooth Off

    private var bluetoothOffCard: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(accentBlue.opacity(0.08))
                    .frame(width: 80, height: 80)
                Image(systemName: "bluetooth")
                    .font(MangoxFont.title.value)
                    .foregroundStyle(accentBlue.opacity(0.6))
            }
            .padding(.top, 40)

            VStack(spacing: 8) {
                Text("Bluetooth Required")
                    .font(MangoxFont.title.value)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.fg0)
                Text(
                    outdoorSensorsOnly
                        ? "Enable Bluetooth in Settings to\nconnect heart rate and speed/cadence sensors."
                        : "Enable Bluetooth in Settings to\nconnect to your trainer and sensors."
                )
                .mangoxFont(.caption)
                .foregroundStyle(AppColor.fg3)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
            }
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity)
        .cardStyle(cornerRadius: MangoxRadius.sharp.rawValue)
    }

    // MARK: - Helpers

    private func signalBars(rssi: Int) -> Int {
        if rssi >= -50 { return 4 }
        if rssi >= -65 { return 3 }
        if rssi >= -80 { return 2 }
        if rssi >= -90 { return 1 }
        return 0
    }

    /// Small mango label above the nav title (matches Home / Stats tab hierarchy).
    private var toolbarEyebrow: String {
        if outdoorSensorsOnly { return "OUTDOOR" }
        switch startMode {
        case .ride: return "RIDE"
        case .ftpTest: return "FTP"
        }
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
        case .ride:
            if rideLaunchMode == .indoor, selectedCustomTemplateID != nil {
                return "Start Guided Workout"
            }
            return rideLaunchMode == .outdoor ? "Start Outdoor Ride" : "Start Indoor Ride"
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
                    return routeService.hasRoute
                        ? "Ready — GPX route will be followed outdoors"
                        : "Ready — GPS free ride with optional BLE sensors"
                }
                if rideLaunchMode == .indoor,
                    selectedCustomTemplateID != nil
                {
                    return "Ready — guided workout from your library"
                }
                if rideLaunchMode == .indoor,
                    dataSourceService.wifiConnectionState.isConnected,
                    !bleService.trainerConnectionState.isConnected
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
            return routeService.hasRoute
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
            } else if let dayID = planDayID, let planID {
                navigationPath.append(
                    AppRoute.planDashboard(planID: planID, dayID: dayID))
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
                Rectangle().fill(AppColor.hair).frame(height: 1)
                Text("DEBUG")
                    .mangoxFont(.micro)
                    .fontWeight(.bold)
                    .foregroundStyle(AppColor.fg3)
                    .tracking(2)
                Text(
                    "BT: \(String(describing: bleService.bluetoothState.rawValue))  Trainer: \(bleService.trainerConnectionState.label)  HR: \(bleService.hrConnectionState.label)  Devices: \(bleService.discoveredPeripherals.count)"
                )
                .font(ConnectionFontToken.mono(size: 9))
                .foregroundStyle(AppColor.fg3)
            }
        }
    #endif
}

// Features/Outdoor/Presentation/ViewModel/OutdoorViewModel.swift
import CoreBluetooth
import Foundation
import MapKit
import SwiftData

struct OutdoorRideDraft {
    let startDate: Date
    let duration: TimeInterval
    let distance: Double
    let elevationGain: Double
    let averageSpeed: Double
    let endDate: Date
    let plannedRouteDistanceMeters: Double
    let savedRouteKindRaw: String
    let savedRouteName: String?
    let routeDestinationSummary: String?
    let notes: String
    let lapDrafts: [OutdoorLapSplitDraft]
}

struct OutdoorLapSplitDraft {
    let lapNumber: Int
    let startTime: Date
    let endTime: Date
    let duration: TimeInterval
    let distance: Double
    let averageSpeedKmh: Double
}

struct OutdoorRideSessionSnapshot {
    let rideDuration: TimeInterval
    let totalDistance: Double
    let totalElevationGain: Double
    let averageSpeed: Double
    let completedLaps: [OutdoorLapRecord]
}

enum OutdoorRideModeDraft {
    case freeRide
    case followRoute(routeName: String?)
    case turnByTurn(routeName: String?, destinationName: String?, destinationSummary: String?)
}

enum OutdoorRouteSheetPage: Hashable {
    case menu
    case search
}

enum OutdoorSetupMode: Hashable {
    case freeRide
    case gpx
    case navigate
}

enum OutdoorRideConfirmation: Hashable {
    case end
    case discard
}

@MainActor
@Observable
final class OutdoorViewModel {

    // MARK: - Dependencies
    let locationService: LocationServiceProtocol
    let bleService: BLEServiceProtocol
    let routeService: RouteServiceProtocol
    private let healthKitService: HealthKitServiceProtocol
    private let liveActivityService: LiveActivityServiceProtocol
    let workoutPersistenceRepository: WorkoutPersistenceRepositoryProtocol
    let navigationService = NavigationService()

    // MARK: - Location computed properties (from locationService)
    var isLocationAuthorized: Bool { locationService.isAuthorized }
    var locationAuthorizationStatus: CLAuthorizationStatus { locationService.authorizationStatus }

    // MARK: - BLE computed properties (from bleService)
    var bluetoothState: CBManagerState { bleService.bluetoothState }
    var hrConnectionState: BLEConnectionState { bleService.hrConnectionState }
    var cscConnectionState: BLEConnectionState { bleService.cscConnectionState }
    var trainerConnectionState: BLEConnectionState { bleService.trainerConnectionState }
    var isHRMonitorConnected: Bool { bleService.hrConnectionState.isConnected }
    var isCSCConnected: Bool { bleService.cscConnectionState.isConnected }
    var isTrainerConnected: Bool { bleService.trainerConnectionState.isConnected }
    var isScanningForSensors: Bool { bleService.isScanningForDevices }
    var discoveredSensors: [DiscoveredPeripheral] { bleService.discoveredPeripherals }
    var activeSensorIDs: Set<UUID> { bleService.activePeripheralIDs }
    var smoothedHeartRate: Int { bleService.smoothedHR }
    var smoothedPower: Int { bleService.smoothedPower }
    var sensorCadence: Int { Int(bleService.metrics.cadence) }
    var bleMetrics: CyclingMetrics { bleService.metrics }

    // MARK: - Route computed properties (from routeService)
    var hasRoute: Bool { routeService.hasRoute }
    var routeName: String? { routeService.routeName }
    var hasElevationData: Bool { routeService.hasElevationData }
    var routeElevationProfilePoints: [(distance: Double, elevation: Double)] {
        routeService.elevationProfilePoints
    }
    var totalRouteDistance: CLLocationDistance { routeService.totalDistance }
    var routePoints: [CLLocationCoordinate2D] { routeService.points }
    var routeSegmentBreakIndices: [Int] { routeService.segmentBreakIndices }
    var routeElevations: [Double?] { routeService.elevations }
    var routePolylineSegments: [[CLLocationCoordinate2D]] { routeService.polylineSegments }
    var routeCameraRegion: MKCoordinateRegion? { routeService.cameraRegion }

    // MARK: - View state
    var currentMetrics: CyclingMetrics = CyclingMetrics()
    var isRecording: Bool = false
    var elapsedSeconds: Int = 0
    var currentNudge: RideNudgeDisplay? = nil
    var rideGoals: [RideGoal] = []
    var showLapToast = false
    var latestLapRecord: OutdoorLapRecord?
    var showRouteSheet = false
    var routeSheetPage: OutdoorRouteSheetPage = .menu
    var showRouteImporter = false
    var routeImportError: String?
    var routeBuildError: String?
    var showSetupPhase = true
    var setupMode: OutdoorSetupMode = .freeRide
    var selectedDestination: MKMapItem?
    var showDestinationSearch = false
    var isHybridMapStyle = false
    var showMapInCompact = true
    var mapWaypoints: [CLLocationCoordinate2D] = []
    var activeConfirmation: OutdoorRideConfirmation?

    // MARK: - Init

    init(
        locationService: LocationServiceProtocol,
        bleService: BLEServiceProtocol,
        routeService: RouteServiceProtocol,
        healthKitService: HealthKitServiceProtocol,
        liveActivityService: LiveActivityServiceProtocol,
        workoutPersistenceRepository: WorkoutPersistenceRepositoryProtocol
    ) {
        self.locationService = locationService
        self.bleService = bleService
        self.routeService = routeService
        self.healthKitService = healthKitService
        self.liveActivityService = liveActivityService
        self.workoutPersistenceRepository = workoutPersistenceRepository
    }

    // MARK: - BLE action methods

    func scanForSensors() { bleService.startScan() }
    func stopSensorScan() { bleService.stopScan() }
    func connectHRMonitor(_ peripheral: CBPeripheral) { bleService.connectHRMonitor(peripheral) }
    func connectCSCSensor(_ peripheral: CBPeripheral) { bleService.connectCSCSensor(peripheral) }

    // MARK: - Route action methods

    func routeElevation(forDistance distance: CLLocationDistance) -> Double? {
        routeService.elevation(forDistance: distance)
    }

    func routeCoordinate(forDistance distance: CLLocationDistance) -> CLLocationCoordinate2D? {
        routeService.coordinate(forDistance: distance)
    }

    // MARK: - Nudge engine state
    private var nudgeSession: RideNudgeSessionState = RideNudgeSessionState()

    func evaluateNudge(context: RideNudgeContext, prefs: RidePreferences, guidedStepIndex: Int) {
        if let nudge = RideNudgeEngine.nextTip(
            context: context,
            prefs: prefs,
            guidedStepIndex: guidedStepIndex,
            session: &nudgeSession
        ) {
            currentNudge = nudge
        }
    }

    func dismissNudge() {
        currentNudge = nil
    }

    func resetNudgeSession() {
        nudgeSession.reset()
        currentNudge = nil
    }

    func presentLapToast(for lap: OutdoorLapRecord?) {
        latestLapRecord = lap
        showLapToast = lap != nil
    }

    func dismissLapToast() {
        showLapToast = false
    }

    func presentRouteSheet() {
        showRouteSheet = true
    }

    func dismissRouteSheet() {
        showRouteSheet = false
        routeSheetPage = .menu
    }

    func showRouteSearch() {
        routeSheetPage = .search
    }

    func presentRouteImporter() {
        showRouteImporter = true
    }

    func dismissRouteImporter() {
        showRouteImporter = false
    }

    func presentRouteImportError(_ message: String) {
        routeImportError = message
    }

    func clearRouteImportError() {
        routeImportError = nil
    }

    func presentRouteBuildError(_ message: String) {
        routeBuildError = message
    }

    func clearRouteBuildError() {
        routeBuildError = nil
    }

    func commitSetupPhase() {
        showSetupPhase = false
    }

    func selectSetupMode(_ mode: OutdoorSetupMode) {
        setupMode = mode
    }

    func clearSelectedDestination() {
        selectedDestination = nil
    }

    func selectDestination(_ item: MKMapItem) {
        selectedDestination = item
    }

    func presentDestinationSearch() {
        showDestinationSearch = true
    }

    func dismissDestinationSearch() {
        showDestinationSearch = false
    }

    var isShowingEndConfirmation: Bool {
        activeConfirmation == .end
    }

    var isShowingDiscardConfirmation: Bool {
        activeConfirmation == .discard
    }

    var isShowingConfirmationOverlay: Bool {
        activeConfirmation != nil
    }

    func presentEndConfirmation() {
        activeConfirmation = .end
    }

    func presentDiscardConfirmation() {
        activeConfirmation = .discard
    }

    func dismissConfirmation() {
        activeConfirmation = nil
    }

    func toggleCompactMapVisibility() {
        showMapInCompact.toggle()
    }

    func showCompactMap() {
        showMapInCompact = true
    }

    func addWaypoint(_ coordinate: CLLocationCoordinate2D) {
        mapWaypoints.append(coordinate)
    }

    func clearWaypoints() {
        mapWaypoints.removeAll()
    }

    func resetMapPresentationStateAfterRide() {
        mapWaypoints.removeAll()
        showMapInCompact = true
    }

    func startRide(using locationManager: LocationServiceProtocol) {
        dismissConfirmation()
        locationManager.startRecording()
    }

    func requestLocationPermission() {
        locationService.requestPermission()
    }

    func discardRide(using locationManager: LocationServiceProtocol) {
        locationManager.stopRecording()
        dismissConfirmation()
        resetMapPresentationStateAfterRide()
    }

    func syncLiveActivity(
        isRecording: Bool,
        prefs: RidePreferences,
        locationManager: LocationServiceProtocol
    ) async {
        guard isRecording else {
            await liveActivityService.syncRecording(
                isRecording: false,
                prefs: prefs,
                navigationService: navigationService,
                locationManager: locationManager,
                bleService: bleService
            )
            return
        }

        await liveActivityService.syncRecording(
            isRecording: true,
            prefs: prefs,
            navigationService: navigationService,
            locationManager: locationManager,
            bleService: bleService
        )

        while !Task.isCancelled, locationManager.isRecording {
            try? await Task.sleep(for: .seconds(5))
            guard locationManager.isRecording else { break }
            await liveActivityService.syncRecording(
                isRecording: true,
                prefs: prefs,
                navigationService: navigationService,
                locationManager: locationManager,
                bleService: bleService
            )
        }
    }

    func applyImportedRoute() {
        navigationService.followGPXRoute(
            points: routeService.points,
            name: routeService.routeName,
            segmentBreakIndices: routeService.segmentBreakIndices
        )
        dismissRouteImporter()
        dismissRouteSheet()
        commitSetupPhase()
    }

    func handleAppear(
        locationManager: LocationServiceProtocol,
        autoLapIntervalMeters: Double
    ) {
        locationService.setup()
        locationManager.lapIntervalMeters = autoLapIntervalMeters

        if routeService.hasRoute, navigationService.mode == .freeRide {
            navigationService.followGPXRoute(
                points: routeService.points,
                name: routeService.routeName,
                segmentBreakIndices: routeService.segmentBreakIndices
            )
        }

        if bleService.bluetoothState == .poweredOn {
            bleService.reconnectOrScan()
        }
    }

    func handleSetupModeChange(
        mode: OutdoorSetupMode,
        showSetupPhase: Bool,
        locationManager: LocationServiceProtocol
    ) {
        guard locationService.isAuthorized, showSetupPhase else { return }
        if mode == .freeRide || mode == .gpx {
            locationManager.stopOutdoorLocationPreviewIfIdle()
        }
    }

    func handleSetupPhaseChange(
        committed: Bool,
        locationManager: LocationServiceProtocol
    ) {
        guard committed == false, locationService.isAuthorized else { return }
        locationManager.startOutdoorLocationPreview()
    }

    func handleDestinationSearchChange(
        isOpen: Bool,
        locationManager: LocationServiceProtocol
    ) {
        guard isOpen, locationService.isAuthorized else { return }
        locationManager.startOutdoorLocationPreview()
    }

    func handleDisappear(locationManager: LocationServiceProtocol) {
        if locationManager.isRecording {
            locationManager.stopRecording()
        }
        locationManager.stopOutdoorLocationPreviewIfIdle()
        bleService.disconnectCSC()
    }

    func handleAuthorizationChange(
        status: CLAuthorizationStatus,
        locationManager: LocationServiceProtocol
    ) {
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            if !showSetupPhase {
                locationManager.startOutdoorLocationPreview()
            }
        }
    }

    func importRoute(
        from url: URL
    ) async -> String? {
        do {
            try await routeService.loadGPX(from: url)
            applyImportedRoute()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func selectDestination(
        _ item: MKMapItem,
        currentLocation: CLLocation?
    ) async -> Bool {
        guard let currentLocation else {
            presentRouteBuildError("Location unavailable. Wait for GPS or try near a window.")
            return false
        }

        await navigationService.calculateRoute(from: currentLocation.coordinate, to: item)
        if navigationService.lastError == nil, navigationService.mode == .turnByTurn {
            dismissRouteSheet()
            return true
        }
        if let error = navigationService.lastError {
            presentRouteBuildError(error)
        } else {
            presentRouteBuildError("No cycling route found.")
        }
        return false
    }

    func startNavigation(
        destination: MKMapItem?,
        currentLocation: CLLocation?
    ) async -> Bool {
        guard let destination else { return false }
        guard let currentLocation else {
            presentRouteBuildError("Location unavailable. Wait for GPS or try near a window.")
            return false
        }

        await navigationService.calculateRoute(from: currentLocation.coordinate, to: destination)
        if navigationService.lastError == nil, navigationService.mode == .turnByTurn {
            commitSetupPhase()
            return true
        }
        if let error = navigationService.lastError {
            presentRouteBuildError(error)
        } else {
            presentRouteBuildError("No cycling route found.")
        }
        return false
    }

    func clearRouteSelection() {
        navigationService.clearNavigation()
        routeService.clearRoute()
    }

    func buildCompletedRideDraft(
        endedAt: Date = .now,
        rideDuration: TimeInterval,
        totalDistance: Double,
        totalElevationGain: Double,
        averageSpeed: Double,
        plannedRouteDistanceMeters: Double,
        mode: OutdoorRideModeDraft,
        completedLaps: [OutdoorLapRecord]
    ) -> OutdoorRideDraft {
        let routeDraft = routeDraftDetails(for: mode)

        return OutdoorRideDraft(
            startDate: endedAt.addingTimeInterval(-rideDuration),
            duration: rideDuration,
            distance: totalDistance,
            elevationGain: totalElevationGain,
            averageSpeed: averageSpeed,
            endDate: endedAt,
            plannedRouteDistanceMeters: plannedRouteDistanceMeters,
            savedRouteKindRaw: routeDraft.kind.rawValue,
            savedRouteName: routeDraft.savedRouteName,
            routeDestinationSummary: routeDraft.routeDestinationSummary,
            notes: routeDraft.notes,
            lapDrafts: completedLaps.map {
                OutdoorLapSplitDraft(
                    lapNumber: $0.number,
                    startTime: $0.startedAt,
                    endTime: $0.endedAt,
                    duration: $0.duration,
                    distance: $0.distanceMeters,
                    averageSpeedKmh: $0.avgSpeedKmh
                )
            }
        )
    }

    @discardableResult
    func completeRide(
        session: OutdoorRideSessionSnapshot,
        plannedRouteDistanceMeters: Double,
        mode: OutdoorRideModeDraft
    ) -> UUID {
        let rideDraft = buildCompletedRideDraft(
            rideDuration: session.rideDuration,
            totalDistance: session.totalDistance,
            totalElevationGain: session.totalElevationGain,
            averageSpeed: session.averageSpeed,
            plannedRouteDistanceMeters: plannedRouteDistanceMeters,
            mode: mode,
            completedLaps: session.completedLaps
        )

        let workout = Workout(startDate: rideDraft.startDate)
        workout.duration = rideDraft.duration
        workout.distance = rideDraft.distance
        workout.elevationGain = rideDraft.elevationGain
        workout.avgSpeed = rideDraft.averageSpeed
        workout.endDate = rideDraft.endDate
        workout.status = .completed
        workout.plannedRouteDistanceMeters = rideDraft.plannedRouteDistanceMeters
        workout.savedRouteKindRaw = rideDraft.savedRouteKindRaw
        workout.savedRouteName = rideDraft.savedRouteName
        workout.routeDestinationSummary = rideDraft.routeDestinationSummary
        workout.notes = rideDraft.notes

        var splits: [LapSplit] = []
        for lapDraft in rideDraft.lapDrafts {
            let split = LapSplit(lapNumber: lapDraft.lapNumber, startTime: lapDraft.startTime)
            split.endTime = lapDraft.endTime
            split.duration = lapDraft.duration
            split.distance = lapDraft.distance
            split.avgSpeed = lapDraft.averageSpeedKmh
            split.avgPower = 0
            split.maxPower = 0
            split.avgCadence = 0
            split.avgHR = 0
            split.workout = workout
            splits.append(split)
        }

        try? workoutPersistenceRepository.saveOutdoorRide(workout: workout, splits: splits)

        Task {
            await healthKitService.saveCyclingWorkoutToHealthIfEnabled(workout)
        }

        dismissConfirmation()
        resetMapPresentationStateAfterRide()
        return workout.id
    }

    private func routeDraftDetails(for mode: OutdoorRideModeDraft) -> (
        kind: SavedRouteKind,
        savedRouteName: String?,
        routeDestinationSummary: String?,
        notes: String
    ) {
        switch mode {
        case .freeRide:
            return (.free, nil, nil, "Outdoor free ride")
        case .followRoute(let routeName):
            return (.gpx, routeName, nil, "Outdoor ride — GPX route: \(routeName ?? "route")")
        case .turnByTurn(let routeName, let destinationName, let destinationSummary):
            let destination = destinationName ?? "destination"
            return (
                .directions,
                routeName,
                destinationSummary,
                "Outdoor ride — directions to \(destination)"
            )
        }
    }
}

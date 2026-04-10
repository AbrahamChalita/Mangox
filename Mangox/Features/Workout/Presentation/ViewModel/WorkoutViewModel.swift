// Features/Workout/Presentation/ViewModel/WorkoutViewModel.swift
import Foundation
import SwiftData

struct StravaDescriptionTemplateOptions {
    let includeDuration: Bool
    let includeDistance: Bool
    let includeCalories: Bool
}

struct StravaDescriptionTemplateInput {
    let routeName: String?
    let totalElevationGain: Double
    let dominantPowerZone: PowerZone
    let zoneBuckets: [(zone: PowerZone, percent: Double)]
    let personalRecordNames: [String]
    let options: StravaDescriptionTemplateOptions
}

struct StravaUploadRequest {
    let workout: Workout
    let exportFormat: ExportFormat
    let hasRoute: Bool
    let routeService: any RouteServiceProtocol
    let routeName: String?
    let totalElevationGain: Double
    let dominantPowerZone: PowerZone
    let zoneBuckets: [(zone: PowerZone, percent: Double)]
    let personalRecordNames: [String]
    let descriptionOptions: StravaDescriptionTemplateOptions
    let preferredGearID: String?
}

struct StravaUploadCompletion {
    let activityID: Int
    let duplicateRecovery: Bool
}

enum StravaPhotoUploadResult {
    case uploaded
    case fallbackRequired
    case failed
}

struct WorkoutExternalNavigationRequest: Equatable {
    let id = UUID()
    let url: URL
}

struct SummaryDataSignature: Equatable {
    let workoutStatus: String
    let duration: TimeInterval
    let distance: Double
    let avgPower: Double
    let normalizedPower: Double
    let tss: Double
    let elevationGain: Double
    let savedRouteName: String?
    let sampleCount: Int
    let lapCount: Int
    let lastSampleElapsed: Int
    let lastLapNumber: Int
}

struct ZoneBucket: Identifiable {
    let zone: PowerZone
    let seconds: Int
    let percent: Double
    var id: Int { zone.id }
}

struct HRZoneBucket: Identifiable {
    let zone: HeartRateZone
    let seconds: Int
    let percent: Double
    var id: Int { zone.id }
}

struct WorkoutPreparedSummaryData {
    let signature: SummaryDataSignature
    let sortedSamples: [WorkoutSampleData]
    let sortedLaps: [LapSplit]
    let zoneBuckets: [ZoneBucket]
    let hrZoneBuckets: [HRZoneBucket]
}

enum WorkoutSummaryNavigationAction {
    case pop
    case resetRoot
    case route(AppRoute)
}

@MainActor
@Observable
final class WorkoutViewModel {
    private let stravaService: StravaServiceProtocol
    let routeService: RouteServiceProtocol
    private let personalRecordsService: PersonalRecordsServiceProtocol
    private let healthKitService: HealthKitServiceProtocol
    private let trainingPlanLookupService: TrainingPlanLookupServiceProtocol
    private let workoutPersistenceRepository: WorkoutPersistenceRepositoryProtocol
    private static let stravaVirtualRideSportType = "VirtualRide"
    private static let stravaOutdoorRideSportType = "Ride"

    // MARK: - View state
    var workouts: [Workout] = []
    var isLoading: Bool = false
    var error: String? = nil
    var shareItems: [Any] = []
    var lastExportedFileURL: URL?
    var showShareSheet = false
    var showDeleteConfirmation = false
    var showExportModal = false
    var actionError: String?
    var selectedExportFormat: ExportFormat = .tcx
    var customRepeatTemplateID: UUID?
    var isSummaryDataReady = false
    var stravaStatus: String?
    var lastUploadedActivityID: Int?
    var stravaBikes: [StravaAthleteBike] = []
    var stravaBikesLoading = false
    var stravaBikesLoadFailed = false
    var stravaTitleInput = ""
    var stravaDescriptionInput = ""
    var stravaDraftWorkoutID: UUID?
    var uploadAsVirtualRide = true
    var uploadPhotoAfterUpload = true
    var showDescriptionPreview = false
    var commuteStravaUpload = false
    var showStravaCard = false
    var showStravaPhotoFallbackDialog = false
    var stravaPhotoFallbackImage: Any?
    var showInstagramStoryStudio = false
    var aiStravaDescriptionTask: Task<Void, Never>?
    var pendingExternalNavigation: WorkoutExternalNavigationRequest?
    private(set) var preparedSummaryData: WorkoutPreparedSummaryData?
    private var pendingSummarySignature: SummaryDataSignature?

    init(
        stravaService: StravaServiceProtocol,
        routeService: RouteServiceProtocol,
        personalRecordsService: PersonalRecordsServiceProtocol,
        healthKitService: HealthKitServiceProtocol,
        trainingPlanLookupService: TrainingPlanLookupServiceProtocol,
        workoutPersistenceRepository: WorkoutPersistenceRepositoryProtocol
    ) {
        self.stravaService = stravaService
        self.routeService = routeService
        self.personalRecordsService = personalRecordsService
        self.healthKitService = healthKitService
        self.trainingPlanLookupService = trainingPlanLookupService
        self.workoutPersistenceRepository = workoutPersistenceRepository
    }

    func resolvePlanDay(planID: String?, dayID: String?) -> PlanDay? {
        trainingPlanLookupService.resolveDay(planID: planID, dayID: dayID)
    }

    func resolvePlan(planID: String?) -> TrainingPlan? {
        trainingPlanLookupService.resolvePlan(planID: planID)
    }

    var isStravaBusy: Bool { stravaService.isBusy }
    var isStravaConnected: Bool { stravaService.isConnected }
    var isStravaConfigured: Bool { stravaService.isConfigured }
    var stravaAthleteDisplayName: String? { stravaService.athleteDisplayName }
    var stravaLastError: String? { stravaService.lastError }

    var hasRoute: Bool { routeService.hasRoute }
    var routeName: String? { routeService.routeName }

    var syncWorkoutsToAppleHealth: Bool {
        get { healthKitService.syncWorkoutsToAppleHealth }
        set { healthKitService.syncWorkoutsToAppleHealth = newValue }
    }
    var workoutSyncToHealthLastError: String? { healthKitService.workoutSyncToHealthLastError }

    // MARK: - Personal records pass-through
    func computeMMP(for samples: [WorkoutSampleData], workoutID: UUID) -> WorkoutMMP? {
        personalRecordsService.computeMMP(for: samples, workoutID: workoutID)
    }

    func newPRs(for mmp: WorkoutMMP) -> [NewPRFlag] {
        personalRecordsService.newPRs(for: mmp)
    }

    // MARK: - Route elevation convenience
    var totalElevationGain: Double { routeService.totalElevationGain }

    // MARK: - Live workout metrics (during recording)
    var elapsedSeconds: Int = 0
    var currentPower: Int = 0
    var currentCadence: Double = 0
    var currentHeartRate: Int = 0
    var normalizedPower: Double = 0
    var intensityFactor: Double = 0
    var tss: Double = 0

    func updateMetrics(powerSamples: [Int], durationSeconds: Int, ftp: Double) {
        let result = WorkoutMetricsAggregator.normalizedPowerIntensityAndTSS(
            powerSamples: powerSamples,
            durationSeconds: durationSeconds,
            ftp: ftp
        )
        normalizedPower = result.np
        intensityFactor = result.intensityFactor
        tss = result.tss
    }

    // MARK: - Summary actions state

    func presentExportedFile(_ fileURL: URL) {
        lastExportedFileURL = fileURL
        shareItems = [fileURL]
        showShareSheet = true
    }

    func presentShareItems(_ items: [Any]) {
        shareItems = items
        showShareSheet = true
    }

    func dismissShareSheet() {
        showShareSheet = false
    }

    func presentError(_ message: String) {
        actionError = message
    }

    func clearError() {
        actionError = nil
    }

    func presentDeleteConfirmation() {
        showDeleteConfirmation = true
    }

    func dismissDeleteConfirmation() {
        showDeleteConfirmation = false
    }

    func markSavedCustomTemplate(_ id: UUID) {
        customRepeatTemplateID = id
    }

    func clearStravaDraft() {
        stravaDraftWorkoutID = nil
    }

    func presentStravaSheet() {
        showStravaCard = true
    }

    func dismissStravaSheet() {
        showStravaCard = false
    }

    func presentInstagramStoryStudio() {
        showInstagramStoryStudio = true
    }

    func dismissInstagramStoryStudio() {
        showInstagramStoryStudio = false
    }

    func presentStravaPhotoFallback(_ image: Any) {
        stravaPhotoFallbackImage = image
        showStravaPhotoFallbackDialog = true
    }

    func clearStravaPhotoFallback() {
        stravaPhotoFallbackImage = nil
        showStravaPhotoFallbackDialog = false
    }

    func clearPendingExternalNavigation() {
        pendingExternalNavigation = nil
    }

    func refreshStravaBikesIfNeeded() async {
        guard stravaService.isConnected else {
            stravaBikes = []
            stravaBikesLoadFailed = false
            return
        }

        stravaBikesLoading = true
        stravaBikesLoadFailed = false
        defer { stravaBikesLoading = false }

        do {
            stravaBikes = try await stravaService.fetchAthleteBikes()
        } catch {
            stravaBikes = []
            stravaBikesLoadFailed = true
        }
    }

    func requestOpenStravaUploader() {
        guard let url = URL(string: "https://www.strava.com/upload/select") else { return }
        pendingExternalNavigation = WorkoutExternalNavigationRequest(url: url)
    }

    func requestOpenUploadedStravaActivity() {
        guard let activityID = lastUploadedActivityID,
            let url = URL(string: "https://www.strava.com/activities/\(activityID)")
        else { return }
        pendingExternalNavigation = WorkoutExternalNavigationRequest(url: url)
    }

    func exportWorkout(workout: Workout, format: ExportFormat) {
        do {
            let fileURL = try WorkoutExportService.export(
                workout: workout,
                format: format,
                routeService: routeService
            )
            presentExportedFile(fileURL)
        } catch {
            presentError(error.localizedDescription)
        }
    }

    func ensureStravaDraft(for workout: Workout, template: StravaDescriptionTemplateInput) {
        guard stravaDraftWorkoutID != workout.id else { return }
        stravaTitleInput =
            workout.smartTitle
            ?? StravaPostBuilder.buildTitle(
                workout: workout,
                routeName: template.routeName,
                dominantPowerZone: template.dominantPowerZone,
                personalRecordNames: template.personalRecordNames
            )
        applyStravaDescriptionTemplate(for: workout, template: template)
        stravaDraftWorkoutID = workout.id
        scheduleAIStravaDescription(
            for: workout,
            powerZoneLine: template.zoneBuckets
                .map { "Z\($0.zone.id) \(Int(($0.percent * 100).rounded()))%" }
                .joined(separator: ", "),
            ftpWatts: PowerZone.ftp
        )
    }

    func applyStravaDescriptionTemplate(
        for workout: Workout, template: StravaDescriptionTemplateInput
    ) {
        stravaDescriptionInput = StravaPostBuilder.buildDescription(
            workout: workout,
            routeName: template.routeName,
            totalElevationGain: template.totalElevationGain,
            dominantPowerZone: template.dominantPowerZone,
            zoneBuckets: template.zoneBuckets,
            personalRecordNames: template.personalRecordNames,
            options: StravaPostBuilder.DescriptionOptions(
                includeDuration: template.options.includeDuration,
                includeDistance: template.options.includeDistance,
                includeCalories: template.options.includeCalories
            )
        )
    }

    private func scheduleAIStravaDescription(
        for workout: Workout, powerZoneLine: String, ftpWatts: Int
    ) {
        aiStravaDescriptionTask?.cancel()
        let capturedWorkoutID = workout.id
        aiStravaDescriptionTask = Task { @MainActor in
            let ai = await WorkoutSummaryOnDeviceInsight.generateStravaDescription(
                workout: workout,
                powerZoneLine: powerZoneLine,
                ftpWatts: ftpWatts
            )
            guard !Task.isCancelled, stravaDraftWorkoutID == capturedWorkoutID, let ai else {
                return
            }
            stravaDescriptionInput = ai
        }
    }

    private func stravaExternalID(for workoutID: UUID) -> String {
        "mangox-\(workoutID.uuidString.lowercased())"
    }

    func uploadToStrava(request: StravaUploadRequest) async -> StravaUploadCompletion? {
        do {
            guard stravaService.isConnected else {
                presentError("Connect your Strava account first.")
                return nil
            }

            let canExport = WorkoutExportService.canExport(
                format: request.exportFormat,
                hasRoute: request.hasRoute
            )
            guard canExport else {
                presentError("Selected format requires a loaded route.")
                return nil
            }

            let fileURL = try WorkoutExportService.export(
                workout: request.workout,
                format: request.exportFormat,
                routeService: request.routeService
            )
            lastExportedFileURL = fileURL

            ensureStravaDraft(
                for: request.workout,
                template: StravaDescriptionTemplateInput(
                    routeName: request.routeName,
                    totalElevationGain: request.totalElevationGain,
                    dominantPowerZone: request.dominantPowerZone,
                    zoneBuckets: request.zoneBuckets,
                    personalRecordNames: request.personalRecordNames,
                    options: request.descriptionOptions
                )
            )

            let resolvedTitle = stravaTitleInput.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedDescription = stravaDescriptionInput.trimmingCharacters(
                in: .whitespacesAndNewlines)
            let rideName =
                resolvedTitle.isEmpty
                ? StravaPostBuilder.buildTitle(
                    workout: request.workout,
                    routeName: request.routeName,
                    dominantPowerZone: request.dominantPowerZone,
                    personalRecordNames: request.personalRecordNames
                )
                : resolvedTitle
            let rideDescription =
                resolvedDescription.isEmpty
                ? StravaPostBuilder.buildDescription(
                    workout: request.workout,
                    routeName: request.routeName,
                    totalElevationGain: request.totalElevationGain,
                    dominantPowerZone: request.dominantPowerZone,
                    zoneBuckets: request.zoneBuckets,
                    personalRecordNames: request.personalRecordNames,
                    options: StravaPostBuilder.DescriptionOptions(
                        includeDuration: request.descriptionOptions.includeDuration,
                        includeDistance: request.descriptionOptions.includeDistance,
                        includeCalories: request.descriptionOptions.includeCalories
                    )
                )
                : resolvedDescription

            let sportType =
                uploadAsVirtualRide
                ? Self.stravaVirtualRideSportType
                : Self.stravaOutdoorRideSportType

            if let existingID = await stravaService.checkForDuplicate(
                startDate: request.workout.startDate,
                elapsedSeconds: Int(request.workout.duration)
            ) {
                lastUploadedActivityID = existingID
                stravaStatus = "Already on Strava — opening activity"
                try await stravaService.updateActivity(
                    activityID: existingID,
                    name: rideName,
                    description: rideDescription,
                    sportType: sportType,
                    trainer: uploadAsVirtualRide,
                    commute: commuteStravaUpload,
                    gearID: request.preferredGearID
                )
                return StravaUploadCompletion(activityID: existingID, duplicateRecovery: true)
            }

            let stravaExternalID = stravaExternalID(for: request.workout.id)
            let result: StravaUploadResult
            do {
                result = try await stravaService.uploadWorkoutFile(
                    fileURL: fileURL,
                    name: rideName,
                    description: rideDescription,
                    trainer: uploadAsVirtualRide,
                    externalID: stravaExternalID,
                    sportType: sportType
                )
            } catch {
                if case StravaService.StravaError.uploadTimedOut = error,
                    let recoveredId = await stravaService.checkForDuplicate(
                        startDate: request.workout.startDate,
                        elapsedSeconds: Int(request.workout.duration)
                    )
                {
                    lastUploadedActivityID = recoveredId
                    try await stravaService.updateActivity(
                        activityID: recoveredId,
                        name: rideName,
                        description: rideDescription,
                        sportType: sportType,
                        trainer: uploadAsVirtualRide,
                        commute: commuteStravaUpload,
                        gearID: request.preferredGearID
                    )
                    stravaStatus = "Strava was slow — activity found on your profile."
                    return StravaUploadCompletion(activityID: recoveredId, duplicateRecovery: true)
                }
                throw error
            }

            guard let activityID = result.activityID else {
                stravaStatus = "Upload queued: \(result.status)"
                return nil
            }

            lastUploadedActivityID = activityID
            try await stravaService.updateActivity(
                activityID: activityID,
                name: rideName,
                description: rideDescription,
                sportType: sportType,
                trainer: uploadAsVirtualRide,
                commute: commuteStravaUpload,
                gearID: request.preferredGearID
            )

            stravaStatus =
                result.isDuplicateRecovery
                ? "Strava already had this file — details refreshed."
                : "Uploaded to Strava! 🎉"

            return StravaUploadCompletion(
                activityID: activityID,
                duplicateRecovery: result.isDuplicateRecovery
            )
        } catch {
            presentError((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            return nil
        }
    }

    func uploadStravaSummaryCardPhoto(
        activityID: Int,
        duplicateRecovery: Bool,
        jpegData: Data
    ) async -> StravaPhotoUploadResult {
        do {
            try await stravaService.uploadActivityPhoto(activityID: activityID, jpegData: jpegData)
            stravaStatus =
                duplicateRecovery
                ? "Ride was already on Strava — summary card added."
                : "Uploaded to Strava with summary card! 🎉"
            return .uploaded
        } catch {
            if let stravaErr = error as? StravaService.StravaError,
                case .photoUploadNotSupportedByAPI = stravaErr
            {
                stravaStatus =
                    duplicateRecovery
                    ? "Updated on Strava — API won’t attach photos automatically."
                    : "Uploaded to Strava — API won’t attach photos automatically."
                return .fallbackRequired
            }

            stravaStatus =
                duplicateRecovery
                ? "Details updated (photo failed)"
                : "Uploaded to Strava! 🎉 (photo failed)"
            return .failed
        }
    }

    func saveWorkoutAsCustomTemplate(from workout: Workout) {
        do {
            guard
                let templateID = try workoutPersistenceRepository.saveWorkoutAsCustomTemplate(
                    from: workout)
            else {
                return
            }
            markSavedCustomTemplate(templateID)
            HapticManager.shared.onboardingStepCompleted()
        } catch {
            presentError(error.localizedDescription)
        }
    }

    func deleteWorkout(_ workout: Workout) -> WorkoutSummaryNavigationAction? {
        do {
            try workoutPersistenceRepository.deleteWorkout(workout)
            dismissDeleteConfirmation()
            invalidatePreparedSummaryData()
            MangoxModelNotifications.postWorkoutAggregatesMayHaveChanged()
            return .resetRoot
        } catch {
            presentError(error.localizedDescription)
            return nil
        }
    }

    func navigationActionForRepeatSavedCustomWorkout() -> WorkoutSummaryNavigationAction? {
        guard let id = customRepeatTemplateID else { return nil }
        return .route(.customWorkoutRide(templateID: id))
    }

    func navigationActionForRepeatStructuredWorkout(_ workout: Workout)
        -> WorkoutSummaryNavigationAction?
    {
        guard let dayID = workout.planDayID else { return nil }

        if dayID.hasPrefix("custom-") {
            let rest = String(dayID.dropFirst("custom-".count))
            guard let templateID = UUID(uuidString: rest) else { return nil }
            return .route(.customWorkoutRide(templateID: templateID))
        }

        guard let planID = workout.planID else { return nil }
        return .route(.connectionForPlan(planID: planID, dayID: dayID))
    }

    func navigationActionForClosingSummary(pathIsEmpty: Bool) -> WorkoutSummaryNavigationAction {
        pathIsEmpty ? .resetRoot : .pop
    }

    // MARK: - Prepared summary data

    var sortedSamples: [WorkoutSampleData] {
        preparedSummaryData?.sortedSamples ?? []
    }

    var sortedLaps: [LapSplit] {
        preparedSummaryData?.sortedLaps ?? []
    }

    var zoneBuckets: [ZoneBucket] {
        preparedSummaryData?.zoneBuckets
            ?? PowerZone.zones.map { ZoneBucket(zone: $0, seconds: 0, percent: 0) }
    }

    var hrZoneBuckets: [HRZoneBucket] {
        preparedSummaryData?.hrZoneBuckets
            ?? HeartRateZone.zones.map { HRZoneBucket(zone: $0, seconds: 0, percent: 0) }
    }

    func invalidatePreparedSummaryData() {
        isSummaryDataReady = false
        preparedSummaryData = nil
        pendingSummarySignature = nil
    }

    func prepareSummaryData(
        workout: Workout?,
        signature: SummaryDataSignature?,
        force: Bool = false
    ) async {
        guard let workout, let signature else {
            invalidatePreparedSummaryData()
            return
        }
        guard force || preparedSummaryData?.signature != signature else { return }

        pendingSummarySignature = signature
        isSummaryDataReady = false

        // `LapSplit` is a SwiftData model, so keep this lightweight sort on the main actor.
        let sortedLaps = workout.laps.sorted { $0.lapNumber < $1.lapNumber }
        let workoutID = workout.persistentModelID
        let ftp = PowerZone.ftp
        let hrMax = HeartRateZone.maxHR
        let hrResting = HeartRateZone.restingHR
        let hrUsesKarvonen = HeartRateZone.hasRestingHR

        let sortedSamplesData = await workoutPersistenceRepository.fetchSortedSamples(
            forWorkoutID: workoutID)
        let (powerCounts, heartRateCounts, hrCount) = await Task.detached(
            priority: .userInitiated
        ) {
            var powerCounts = [Int: Int]()
            var heartRateCounts = [Int: Int]()
            var hrCount = 0

            for sample in sortedSamplesData {
                powerCounts[
                    SummaryZoneAggregation.powerZoneId(forWatts: sample.power, ftp: ftp),
                    default: 0
                ] += 1

                if sample.heartRate > 0 {
                    heartRateCounts[
                        SummaryZoneAggregation.heartRateZoneId(
                            forBpm: sample.heartRate,
                            maxHR: hrMax,
                            restingHR: hrResting,
                            usesKarvonen: hrUsesKarvonen
                        ),
                        default: 0
                    ] += 1
                    hrCount += 1
                }
            }

            return (powerCounts, heartRateCounts, hrCount)
        }.value

        guard pendingSummarySignature == signature else { return }

        let totalSamples = max(sortedSamplesData.count, 1)
        let zoneBuckets = PowerZone.zones.map { zone in
            let count = powerCounts[zone.id, default: 0]
            return ZoneBucket(
                zone: zone,
                seconds: count,
                percent: Double(count) / Double(totalSamples)
            )
        }

        let totalHeartRateSamples = max(hrCount, 1)
        let hrZoneBuckets = HeartRateZone.zones.map { zone in
            let count = heartRateCounts[zone.id, default: 0]
            return HRZoneBucket(
                zone: zone,
                seconds: count,
                percent: Double(count) / Double(totalHeartRateSamples)
            )
        }

        preparedSummaryData = WorkoutPreparedSummaryData(
            signature: signature,
            sortedSamples: sortedSamplesData,
            sortedLaps: sortedLaps,
            zoneBuckets: zoneBuckets,
            hrZoneBuckets: hrZoneBuckets
        )
        isSummaryDataReady = true
    }
}
